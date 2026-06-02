module Payouts
  class Settle
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, payout:, correlation_id: nil, force: false)
      @organization = organization
      @payout = payout
      @correlation_id = correlation_id
      @force = force
    end

    def call
      raise Errors::ValidationError.new("Payout belongs to another organization") if payout.organization_id != organization.id

      ActiveRecord::Base.transaction do
        payout.lock!
        raise Errors::ValidationError.new("Payout must be scheduled before settlement", details: { status: payout.status }) unless payout.scheduled?
        raise Errors::ValidationError.new("Payout settlement date has not arrived", details: { settlement_due_on: payout.settlement_due_on.iso8601 }) if !force && payout.settlement_due_on > Date.current

        Accounts::BootstrapOrganizationLedger.call(organization:, currency: payout.currency)
        journal_entry = Ledger::JournalPoster.call(
          organization:,
          event_type: "payout.settled",
          reference: payout,
          idempotency_key: "payout.settle:#{payout.id}",
          correlation_id:,
          metadata: { external_id: payout.external_id, settlement_due_on: payout.settlement_due_on.iso8601 },
          lines: [
            { account: Ledger::AccountLocator.payout_clearing(organization:, currency: payout.currency), direction: "debit", amount_cents: payout.amount_cents, currency: payout.currency },
            { account: Ledger::AccountLocator.platform_cash(organization:, currency: payout.currency), direction: "credit", amount_cents: payout.amount_cents, currency: payout.currency }
          ]
        )
        payout.update!(status: "settled", settlement_journal_entry: journal_entry, settled_at: Time.current)
        OutboxEvents::Emit.call(
          organization:,
          aggregate: payout,
          event_type: "payout.settled",
          correlation_id:,
          idempotency_key: "payout.settle:#{payout.id}",
          payload: {
            payout_id: payout.public_id,
            wallet_id: payout.wallet.public_id,
            amount_cents: payout.amount_cents,
            currency: payout.currency,
            settlement_due_on: payout.settlement_due_on.iso8601
          }
        )
        payout
      end
    end

    private

    attr_reader :organization, :payout, :correlation_id, :force
  end
end
