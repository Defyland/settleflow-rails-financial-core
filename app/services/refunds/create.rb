module Refunds
  class Create
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, pix_payment:, external_id:, amount_cents:, reason:, currency: nil, idempotency_key: nil, correlation_id: nil, metadata: {})
      @organization = organization
      @pix_payment = pix_payment
      @external_id = external_id
      @amount_cents = amount_cents.to_i
      @reason = reason.presence || "customer_refund"
      @currency = currency || pix_payment.currency
      @idempotency_key = idempotency_key
      @correlation_id = correlation_id
      @metadata = metadata || {}
    end

    def call
      raise Errors::IdempotencyKeyRequired if idempotency_key.blank?
      raise Errors::ValidationError.new("Pix payment belongs to another organization") if pix_payment.organization_id != organization.id
      raise Errors::ValidationError.new("Currency mismatch") if pix_payment.currency != currency

      ActiveRecord::Base.transaction do
        pix_payment.lock!
        raise Errors::ValidationError.new("Only settled Pix payments can be refunded", details: { status: pix_payment.status }) unless pix_payment.settled?
        raise Errors::ValidationError.new("Pix payment already has a reversal") if pix_payment.reversal_journal_entry_id.present?
        raise Errors::ValidationError.new("Refund exceeds refundable Pix amount", details: refundable_details) if amount_cents > refundable_cents

        Accounts::BootstrapOrganizationLedger.call(organization:, currency:)
        refund = organization.refunds.create!(
          wallet: pix_payment.wallet,
          pix_payment:,
          external_id:,
          amount_cents:,
          currency:,
          reason:,
          settled_at: Time.current,
          idempotency_key:,
          correlation_id:,
          metadata:
        )
        journal_entry = Ledger::JournalPoster.call(
          organization:,
          event_type: "refund.settled",
          reference: refund,
          idempotency_key:,
          correlation_id:,
          metadata: { external_id: refund.external_id, pix_payment_id: pix_payment.public_id, reason: },
          lines: [
            { account: Ledger::AccountLocator.platform_cash(organization:, currency:), direction: "debit", amount_cents:, currency: },
            { account: pix_payment.wallet.liability_account, direction: "credit", amount_cents:, currency: }
          ]
        )
        refund.update!(journal_entry:)
        OutboxEvents::Emit.call(
          organization:,
          aggregate: refund,
          event_type: "refund.settled",
          correlation_id:,
          idempotency_key:,
          payload: {
            refund_id: refund.public_id,
            pix_payment_id: pix_payment.public_id,
            wallet_id: pix_payment.wallet.public_id,
            amount_cents:,
            currency:,
            reason:
          }
        )
        refund
      end
    end

    private

    attr_reader :organization, :pix_payment, :external_id, :amount_cents, :reason, :currency, :idempotency_key, :correlation_id, :metadata

    def refundable_cents
      pix_payment.amount_cents - refunded_cents
    end

    def refunded_cents
      organization.refunds.where(pix_payment:, status: "settled").sum(:amount_cents)
    end

    def refundable_details
      {
        pix_payment_amount_cents: pix_payment.amount_cents,
        refunded_cents:,
        requested_cents: amount_cents
      }
    end
  end
end
