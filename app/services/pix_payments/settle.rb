module PixPayments
  class Settle
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, pix_payment:, correlation_id: nil)
      @organization = organization
      @pix_payment = pix_payment
      @correlation_id = correlation_id
    end

    def call
      raise Errors::ValidationError.new("Pix payment belongs to another organization") if pix_payment.organization_id != organization.id

      ActiveRecord::Base.transaction do
        pix_payment.lock!
        raise Errors::ValidationError.new("Pix payment must be approved before settlement", details: { status: pix_payment.status }) unless pix_payment.approved?

        Accounts::BootstrapOrganizationLedger.call(organization:, currency: pix_payment.currency)
        journal_entry = Ledger::JournalPoster.call(
          organization:,
          event_type: "pix.payment.settled",
          reference: pix_payment,
          idempotency_key: "pix_payment.settle:#{pix_payment.id}",
          correlation_id:,
          metadata: { external_id: pix_payment.external_id },
          lines: [
            { account: Ledger::AccountLocator.pix_clearing(organization:, currency: pix_payment.currency), direction: "debit", amount_cents: pix_payment.amount_cents, currency: pix_payment.currency },
            { account: Ledger::AccountLocator.platform_cash(organization:, currency: pix_payment.currency), direction: "credit", amount_cents: pix_payment.amount_cents, currency: pix_payment.currency }
          ]
        )
        pix_payment.update!(status: "settled", settlement_journal_entry: journal_entry)
        OutboxEvents::Emit.call(
          organization:,
          aggregate: pix_payment,
          event_type: "pix.payment.settled",
          correlation_id:,
          idempotency_key: "pix_payment.settle:#{pix_payment.id}",
          payload: {
            pix_payment_id: pix_payment.public_id,
            amount_cents: pix_payment.amount_cents,
            currency: pix_payment.currency
          }
        )
        pix_payment
      end
    end

    private

    attr_reader :organization, :pix_payment, :correlation_id
  end
end
