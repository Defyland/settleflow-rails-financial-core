class ReconciliationRunSerializer
  def self.render(run, include_rows: false)
    payload = {
      id: run.public_id,
      provider: run.provider,
      statement_date: run.statement_date.iso8601,
      provider_balance_cents: run.provider_balance_cents,
      ledger_balance_cents: run.ledger_balance_cents,
      discrepancy_cents: run.discrepancy_cents,
      status: run.status,
      rows_summary: run.metadata.fetch("row_status_counts") { run.reconciliation_rows.group(:status).count },
      metadata: Privacy::Redactor.metadata(run.metadata),
      created_at: run.created_at.iso8601
    }

    if include_rows
      payload[:rows] = run.reconciliation_rows.includes(:journal_entry).order(:id).map do |row|
        ReconciliationRowSerializer.render(row)
      end
    end

    payload
  end
end
