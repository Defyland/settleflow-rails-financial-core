module Reconciliation
  class Run
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, provider:, statement_date:, provider_balance_cents:, currency: "BRL", correlation_id: nil, metadata: {})
      @organization = organization
      @provider = provider
      @statement_date = statement_date
      @provider_balance_cents = provider_balance_cents.to_i
      @currency = currency
      @correlation_id = correlation_id
      @metadata = metadata || {}
    end

    def call
      snapshot = Reconciliation::LedgerSnapshot.call(organization:, currency:)
      ledger_balance = snapshot.fetch(:platform_cash_cents)
      discrepancy = provider_balance_cents - ledger_balance
      projection_difference = snapshot.fetch(:projection_difference_cents)
      status = discrepancy.zero? && projection_difference.zero? ? "matched" : "discrepant"

      organization.reconciliation_runs.create!(
        provider:,
        statement_date:,
        provider_balance_cents:,
        ledger_balance_cents: ledger_balance,
        discrepancy_cents: discrepancy,
        status:,
        correlation_id:,
        metadata: metadata.merge(snapshot)
      ).tap do |run|
        OutboxEvents::Emit.call(
          organization:,
          aggregate: run,
          event_type: "reconciliation.#{run.status}",
          correlation_id:,
          payload: {
            reconciliation_run_id: run.public_id,
            provider:,
            statement_date: run.statement_date.iso8601,
            ledger_balance_cents: ledger_balance,
            provider_balance_cents:,
            discrepancy_cents: discrepancy
          }
        )
      end
    end

    private

    attr_reader :organization, :provider, :statement_date, :provider_balance_cents, :currency, :correlation_id, :metadata
  end
end
