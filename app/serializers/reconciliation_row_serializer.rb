class ReconciliationRowSerializer
  def self.render(row)
    {
      id: row.public_id,
      row_type: row.row_type,
      status: row.status,
      external_id: row.external_id,
      occurred_on: row.occurred_on.iso8601,
      provider_amount_cents: row.provider_amount_cents,
      ledger_amount_cents: row.ledger_amount_cents,
      difference_cents: row.difference_cents,
      currency: row.currency,
      journal_entry_id: row.journal_entry&.public_id,
      metadata: Privacy::Redactor.metadata(row.metadata),
      created_at: row.created_at.iso8601
    }
  end
end
