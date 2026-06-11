class JournalEntrySerializer
  def self.render(journal_entry)
    {
      id: journal_entry.public_id,
      event_type: journal_entry.event_type,
      status: journal_entry.status,
      reference_type: journal_entry.reference_type,
      reference_id: journal_entry.reference&.public_id,
      correlation_id: journal_entry.correlation_id,
      occurred_at: journal_entry.occurred_at.iso8601,
      metadata: ::Privacy::Redactor.metadata(journal_entry.metadata),
      lines: journal_entry.ledger_lines.includes(:ledger_account).map do |line|
        {
          id: line.public_id,
          account_code: line.ledger_account.code,
          account_type: line.ledger_account.account_type,
          direction: line.direction,
          amount_cents: line.amount_cents,
          currency: line.currency,
          metadata: ::Privacy::Redactor.metadata(line.metadata)
        }
      end
    }
  end
end
