module Wallets
  class BalanceExplainer
    RECENT_LINE_LIMIT = 100

    def self.call(...)
      new(...).call
    end

    def initialize(wallet:)
      @wallet = wallet
    end

    def call
      account = wallet.liability_account
      projection = wallet.balance_projection
      debit_total = account.ledger_lines.debit.sum(:amount_cents)
      credit_total = account.ledger_lines.credit.sum(:amount_cents)
      ledger_available_cents = account.normal_credit? ? credit_total - debit_total : debit_total - credit_total
      difference_cents = projection.available_cents - ledger_available_cents

      {
        wallet_id: wallet.public_id,
        currency: wallet.currency,
        projection_available_cents: projection.available_cents,
        ledger_available_cents:,
        difference_cents:,
        consistent: difference_cents.zero?,
        debit_total_cents: debit_total,
        credit_total_cents: credit_total,
        line_count: account.ledger_lines.count,
        recent_lines: recent_lines(account)
      }
    end

    private

    attr_reader :wallet

    def recent_lines(account)
      running_balance_cents = 0
      ordered_lines = account.ledger_lines.includes(:journal_entry).order(:created_at, :id)
      balances_by_line_id = {}

      ordered_lines.each do |line|
        running_balance_cents += delta_for(account, line)
        balances_by_line_id[line.id] = running_balance_cents
      end

      ordered_lines.to_a.last(RECENT_LINE_LIMIT).map do |line|
        {
          id: line.public_id,
          journal_entry_id: line.journal_entry.public_id,
          event_type: line.journal_entry.event_type,
          direction: line.direction,
          amount_cents: line.amount_cents,
          delta_cents: delta_for(account, line),
          running_available_cents: balances_by_line_id.fetch(line.id),
          occurred_at: line.journal_entry.occurred_at.iso8601
        }
      end
    end

    def delta_for(account, line)
      if account.normal_credit?
        line.credit? ? line.amount_cents : -line.amount_cents
      else
        line.debit? ? line.amount_cents : -line.amount_cents
      end
    end
  end
end
