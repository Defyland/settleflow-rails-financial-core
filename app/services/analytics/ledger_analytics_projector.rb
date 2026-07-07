module Analytics
  class LedgerAnalyticsProjector < ApplicationService
    def initialize(journal_entry:)
      @journal_entry = journal_entry
    end

    def call
      Analytics::LedgerAnalyticsPartitions.ensure_month!(journal_entry.occurred_at.to_date)
      LedgerAnalyticsEvent.insert_all(rows, unique_by: %i[ledger_line_id occurred_on]) if rows.any?

      LedgerAnalyticsEvent.where(journal_entry_id: journal_entry.id).order(:ledger_line_id).to_a
    end

    private

    attr_reader :journal_entry

    def rows
      @rows ||= journal_entry.ledger_lines.includes(:ledger_account).map do |line|
        account = line.ledger_account
        {
          organization_id: journal_entry.organization_id,
          journal_entry_id: journal_entry.id,
          ledger_line_id: line.id,
          ledger_account_id: account.id,
          wallet_id: account.wallet_id,
          event_type: journal_entry.event_type,
          direction: line.direction,
          account_type: account.account_type,
          normal_balance: account.normal_balance,
          amount_cents: line.amount_cents,
          signed_amount_cents: signed_amount_cents(line),
          currency: line.currency,
          occurred_at: journal_entry.occurred_at,
          occurred_on: journal_entry.occurred_at.to_date,
          metadata: projection_metadata(line),
          created_at: Time.current,
          updated_at: Time.current
        }
      end
    end

    def signed_amount_cents(line)
      account = line.ledger_account

      if account.normal_debit?
        line.debit? ? line.amount_cents : -line.amount_cents
      else
        line.credit? ? line.amount_cents : -line.amount_cents
      end
    end

    def projection_metadata(line)
      {
        journal_entry_public_id: journal_entry.public_id,
        ledger_line_public_id: line.public_id,
        reference_type: journal_entry.reference_type,
        reference_id: journal_entry.reference_id
      }.compact
    end
  end
end
