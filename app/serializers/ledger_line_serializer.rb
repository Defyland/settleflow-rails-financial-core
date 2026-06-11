class LedgerLineSerializer
  def self.render(line)
    {
      id: line.public_id,
      journal_entry_id: line.journal_entry.public_id,
      event_type: line.journal_entry.event_type,
      account_code: line.ledger_account.code,
      direction: line.direction,
      amount_cents: line.amount_cents,
      currency: line.currency,
      occurred_at: line.journal_entry.occurred_at.iso8601,
      metadata: ::Privacy::Redactor.metadata(line.metadata)
    }
  end
end
