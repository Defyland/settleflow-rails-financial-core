module Wallets
  class StatementBuilder < ApplicationService
    StatementLine = Data.define(:ledger_line, :delta_cents, :running_available_cents)
    DEFAULT_LIMIT = 50
    MAX_LIMIT = 100
    def initialize(wallet:, limit: DEFAULT_LIMIT)
      @wallet = wallet
      @limit = limit.to_i.clamp(1, MAX_LIMIT)
    end

    def call
      running_balance_cents = 0
      ordered_lines = account.ledger_lines.includes(:journal_entry, :ledger_account).order(:created_at, :id)
      statement_lines = ordered_lines.map do |line|
        delta_cents = delta_for(line)
        running_balance_cents += delta_cents
        StatementLine.new(ledger_line: line, delta_cents:, running_available_cents: running_balance_cents)
      end

      statement_lines.last(limit).reverse
    end

    private

    attr_reader :wallet, :limit

    def account
      @account ||= wallet.liability_account
    end

    def delta_for(line)
      if account.normal_credit?
        line.credit? ? line.amount_cents : -line.amount_cents
      else
        line.debit? ? line.amount_cents : -line.amount_cents
      end
    end
  end
end
