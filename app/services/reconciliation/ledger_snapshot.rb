module Reconciliation
  class LedgerSnapshot < ApplicationService
    def initialize(organization:, currency: "BRL")
      @organization = organization
      @currency = currency
    end

    def call
      Accounts::BootstrapOrganizationLedger.call(organization:, currency:)

      balances = account_balances
      wallet_liability_cents = balances.sum do |account|
        account.fetch(:wallet_id).present? && account.fetch(:account_type) == "liability" ? account.fetch(:balance_cents) : 0
      end
      projection_available_cents = BalanceProjection.where(organization:, currency:).sum(:available_cents)

      {
        currency:,
        captured_at: Time.current.iso8601,
        platform_cash_cents: balance_for(balances, "PLATFORM_CASH:#{currency}"),
        pix_clearing_cents: balance_for(balances, "PIX_CLEARING:#{currency}"),
        payout_clearing_cents: balance_for(balances, "PAYOUT_CLEARING:#{currency}"),
        wallet_liability_cents:,
        projection_available_cents:,
        projection_difference_cents: projection_available_cents - wallet_liability_cents,
        wallet_count: BalanceProjection.where(organization:, currency:).count,
        journal_entry_count: LedgerLine.where(organization:, currency:).distinct.count(:journal_entry_id),
        ledger_line_count: LedgerLine.where(organization:, currency:).count
      }
    end

    private

    attr_reader :organization, :currency

    def account_balances
      organization.ledger_accounts
        .left_outer_joins(:ledger_lines)
        .where(currency:)
        .select(
          "ledger_accounts.id",
          "ledger_accounts.code",
          "ledger_accounts.wallet_id",
          "ledger_accounts.account_type",
          "ledger_accounts.normal_balance",
          "COALESCE(SUM(CASE WHEN ledger_lines.direction = 'debit' THEN ledger_lines.amount_cents ELSE 0 END), 0) AS debit_total_cents",
          "COALESCE(SUM(CASE WHEN ledger_lines.direction = 'credit' THEN ledger_lines.amount_cents ELSE 0 END), 0) AS credit_total_cents"
        )
        .group("ledger_accounts.id")
        .map do |account|
          debit_total = account.read_attribute("debit_total_cents").to_i
          credit_total = account.read_attribute("credit_total_cents").to_i
          {
            code: account.code,
            wallet_id: account.wallet_id,
            account_type: account.account_type,
            balance_cents: account.normal_debit? ? debit_total - credit_total : credit_total - debit_total
          }
        end
    end

    def balance_for(balances, code)
      balances.find { |account| account.fetch(:code) == code }&.fetch(:balance_cents) || 0
    end
  end
end
