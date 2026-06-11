class WalletStatementLineSerializer
  def self.render(statement_line)
    line = statement_line.ledger_line

    {
      id: line.public_id,
      journal_entry_id: line.journal_entry.public_id,
      event_type: line.journal_entry.event_type,
      account_code: line.ledger_account.code,
      direction: line.direction,
      amount_cents: line.amount_cents,
      delta_cents: statement_line.delta_cents,
      running_available_cents: statement_line.running_available_cents,
      currency: line.currency,
      occurred_at: line.journal_entry.occurred_at.iso8601,
      metadata: ::Privacy::Redactor.metadata(line.metadata)
    }
  end
end
