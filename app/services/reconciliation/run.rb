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
      Accounts::BootstrapOrganizationLedger.call(organization:, currency:)
      platform_cash = Ledger::AccountLocator.platform_cash(organization:, currency:)
      pix_clearing = Ledger::AccountLocator.pix_clearing(organization:, currency:)
      wallet_liability = organization.ledger_accounts
        .where(account_type: "liability", normal_balance: "credit", currency:)
        .where.not(wallet_id: nil)
        .sum { |account| account.balance_cents }
      ledger_balance = platform_cash.balance_cents
      discrepancy = provider_balance_cents - ledger_balance

      organization.reconciliation_runs.create!(
        provider:,
        statement_date:,
        provider_balance_cents:,
        ledger_balance_cents: ledger_balance,
        discrepancy_cents: discrepancy,
        status: discrepancy.zero? ? "matched" : "discrepant",
        correlation_id:,
        metadata: metadata.merge(
          currency:,
          platform_cash_cents: platform_cash.balance_cents,
          wallet_liability_cents: wallet_liability,
          pix_clearing_cents: pix_clearing.balance_cents
        )
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
