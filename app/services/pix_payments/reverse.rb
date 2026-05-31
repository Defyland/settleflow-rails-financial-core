module PixPayments
  class Reverse
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, pix_payment:, reason:, correlation_id: nil)
      @organization = organization
      @pix_payment = pix_payment
      @reason = reason.presence || "operator_reversal"
      @correlation_id = correlation_id
    end

    def call
      raise Errors::ValidationError.new("Pix payment belongs to another organization") if pix_payment.organization_id != organization.id
      raise Errors::ValidationError.new("Only settled Pix payments can be reversed", details: { status: pix_payment.status }) unless pix_payment.settled?

      ActiveRecord::Base.transaction do
        pix_payment.lock!
        Accounts::BootstrapOrganizationLedger.call(organization:, currency: pix_payment.currency)
        journal_entry = Ledger::JournalPoster.call(
          organization:,
          event_type: "pix.payment.reversed",
          reference: pix_payment,
          correlation_id:,
          metadata: { external_id: pix_payment.external_id, reason: },
          lines: [
            { account: Ledger::AccountLocator.platform_cash(organization:, currency: pix_payment.currency), direction: "debit", amount_cents: pix_payment.amount_cents, currency: pix_payment.currency },
            { account: pix_payment.wallet.liability_account, direction: "credit", amount_cents: pix_payment.amount_cents, currency: pix_payment.currency }
          ]
        )
        pix_payment.update!(
          status: "reversed",
          reversal_journal_entry: journal_entry,
          reversed_at: Time.current,
          reversal_reason: reason,
          metadata: pix_payment.metadata.merge("operator_reversed_at" => Time.current.iso8601)
        )
        OutboxEvents::Emit.call(
          organization:,
          aggregate: pix_payment,
          event_type: "pix.payment.reversed",
          correlation_id:,
          payload: {
            pix_payment_id: pix_payment.public_id,
            wallet_id: pix_payment.wallet.public_id,
            amount_cents: pix_payment.amount_cents,
            currency: pix_payment.currency,
            reversal_reason: pix_payment.reversal_reason
          }
        )
        pix_payment
      end
    end

    private

    attr_reader :organization, :pix_payment, :reason, :correlation_id
  end
end
