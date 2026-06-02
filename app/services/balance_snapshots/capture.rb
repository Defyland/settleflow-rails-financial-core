module BalanceSnapshots
  class Capture
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, captured_on: Date.current, source: "scheduled_capture", metadata: {})
      @organization = organization
      @captured_on = captured_on
      @source = source
      @metadata = metadata || {}
    end

    def call
      captured_at = Time.current
      organization.wallets.includes(:balance_projection, :ledger_accounts).find_each.map do |wallet|
        projection = wallet.balance_projection
        ledger_available_cents = wallet.liability_account.balance_cents

        snapshot = organization.balance_snapshots.find_or_initialize_by(
          wallet:,
          currency: wallet.currency,
          captured_on:
        )
        if snapshot.new_record?
          snapshot.captured_at = captured_at
          snapshot.available_cents = projection.available_cents
          snapshot.pending_cents = projection.pending_cents
          snapshot.blocked_cents = projection.blocked_cents
          snapshot.ledger_available_cents = ledger_available_cents
          snapshot.difference_cents = projection.available_cents - ledger_available_cents
          snapshot.source = source
          snapshot.metadata = metadata
        end
        snapshot.save!
        snapshot
      end
    end

    private

    attr_reader :organization, :captured_on, :source, :metadata
  end
end
