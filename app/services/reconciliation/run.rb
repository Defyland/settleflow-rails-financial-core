module Reconciliation
  class Run < ApplicationService
    def initialize(organization:, provider:, statement_date:, provider_balance_cents:, currency: "BRL", correlation_id: nil, metadata: {}, statement_entries: [])
      @organization = organization
      @provider = provider
      @statement_date = statement_date
      @provider_balance_cents = provider_balance_cents.to_i
      @currency = currency
      @correlation_id = correlation_id
      @metadata = metadata || {}
      @statement_entries = statement_entries || []
    end

    def call
      snapshot = Reconciliation::LedgerSnapshot.call(organization:, currency:)
      ledger_balance = snapshot.fetch(:platform_cash_cents)
      discrepancy = provider_balance_cents - ledger_balance

      ActiveRecord::Base.transaction do
        run = organization.reconciliation_runs.create!(
          provider:,
          statement_date:,
          provider_balance_cents:,
          ledger_balance_cents: ledger_balance,
          discrepancy_cents: discrepancy,
          status: "matched",
          correlation_id:,
          metadata: metadata.merge(snapshot)
        )
        rows = Reconciliation::RowsBuilder.call(run:, snapshot:, statement_entries:, currency:)
        status = rows.all?(&:matched?) ? "matched" : "discrepant"
        row_status_counts = rows.group_by(&:status).transform_values(&:count)
        run.update!(
          status:,
          metadata: run.metadata.merge(
            statement_entry_count: statement_entries.size,
            reconciliation_row_count: rows.size,
            row_status_counts:
          )
        )

        event_type = run.matched? ? FinancialContracts::Events::RECONCILIATION_MATCHED : FinancialContracts::Events::RECONCILIATION_DISCREPANT
        OutboxEvents::Emit.call(
          organization:,
          aggregate: run,
          event_type:,
          correlation_id:,
          payload: {
            reconciliation_run_id: run.public_id,
            provider:,
            statement_date: run.statement_date.iso8601,
            ledger_balance_cents: ledger_balance,
            provider_balance_cents:,
            discrepancy_cents: discrepancy,
            reconciliation_row_count: rows.size,
            row_status_counts:
          }
        )
        run
      end
    end

    private

    attr_reader :organization, :provider, :statement_date, :provider_balance_cents, :currency, :correlation_id, :metadata, :statement_entries
  end
end
