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
      # Walk only the most recent `limit` lines, newest first, deriving each
      # running balance backward from the account's ledger balance. This avoids
      # loading the wallet's entire history to return one small window, and
      # reads the authoritative ledger total rather than a possibly-stale
      # projection association on the caller's wallet.
      balance_cents = account.balance_cents
      recent_lines.map do |line|
        delta_cents = delta_for(line)
        statement_line = StatementLine.new(ledger_line: line, delta_cents:, running_available_cents: balance_cents)
        balance_cents -= delta_cents
        statement_line
      end
    end

    private

    attr_reader :wallet, :limit

    def recent_lines
      account.ledger_lines
        .includes(:journal_entry, :ledger_account)
        .order(created_at: :desc, id: :desc)
        .limit(limit)
    end

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
