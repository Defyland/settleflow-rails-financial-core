module Wallets
  class BalanceExplainer < ApplicationService
    RECENT_LINE_LIMIT = 100
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
        recent_lines: recent_lines(account, ledger_available_cents)
      }
    end

    private

    attr_reader :wallet

    # Build the most recent lines (oldest first within the window) by walking
    # the newest `RECENT_LINE_LIMIT` lines backward from the ledger-derived
    # available balance, instead of materializing the wallet's full history.
    def recent_lines(account, anchor_cents)
      balance_cents = anchor_cents
      account.ledger_lines
        .includes(:journal_entry)
        .order(created_at: :desc, id: :desc)
        .limit(RECENT_LINE_LIMIT)
        .map do |line|
          delta_cents = delta_for(account, line)
          view = {
            id: line.public_id,
            journal_entry_id: line.journal_entry.public_id,
            event_type: line.journal_entry.event_type,
            direction: line.direction,
            amount_cents: line.amount_cents,
            delta_cents:,
            running_available_cents: balance_cents,
            occurred_at: line.journal_entry.occurred_at.iso8601
          }
          balance_cents -= delta_cents
          view
        end.reverse
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
