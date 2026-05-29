class ReconciliationRunSerializer
  def self.render(run)
    {
      id: run.public_id,
      provider: run.provider,
      statement_date: run.statement_date.iso8601,
      provider_balance_cents: run.provider_balance_cents,
      ledger_balance_cents: run.ledger_balance_cents,
      discrepancy_cents: run.discrepancy_cents,
      status: run.status,
      metadata: run.metadata,
      created_at: run.created_at.iso8601
    }
  end
end
