module Database
  module ConsistencyChecks
    class ReconciliationEvidenceGuards < Base
      EXPECTED_CONSTRAINTS = %w[
        reconciliation_runs_provider_present_check
        reconciliation_runs_status_check
        reconciliation_runs_discrepancy_check
        reconciliation_rows_difference_check
        reconciliation_rows_external_id_required_check
        reconciliation_rows_row_type_check
        reconciliation_rows_status_check
        reconciliation_rows_type_status_check
        reconciliation_rows_amount_status_check
      ].freeze
      EXPECTED_TRIGGERS = %w[
        reconciliation_runs_prevent_evidence_mutation
        reconciliation_rows_prevent_evidence_mutation
        reconciliation_runs_evidence_after_write
        reconciliation_rows_evidence_after_write
      ].freeze

      def call
        enabled_constraints = connection.select_values(<<~SQL.squish)
          SELECT conname
          FROM pg_constraint
          WHERE conrelid IN ('reconciliation_runs'::regclass, 'reconciliation_rows'::regclass)
        SQL
        enabled_triggers = connection.select_values(<<~SQL.squish)
          SELECT tgname
          FROM pg_trigger
          WHERE tgrelid IN ('reconciliation_runs'::regclass, 'reconciliation_rows'::regclass)
            AND NOT tgisinternal
            AND tgenabled <> 'D'
        SQL
        evidence_mismatches = connection.select_value(evidence_mismatches_sql).to_i
        present_constraints = enabled_constraints & EXPECTED_CONSTRAINTS
        present_triggers = enabled_triggers & EXPECTED_TRIGGERS
        missing_constraints = EXPECTED_CONSTRAINTS - present_constraints
        missing_triggers = EXPECTED_TRIGGERS - present_triggers

        check(
          name: :reconciliation_evidence_guards,
          ok: missing_constraints.empty? && missing_triggers.empty? && evidence_mismatches.zero?,
          details: {
            present_constraints: present_constraints.sort,
            missing_constraints:,
            present_triggers: present_triggers.sort,
            missing_triggers:,
            evidence_mismatches:
          }
        )
      end

      private

      def evidence_mismatches_sql
        sanitize_sql_array(
          [ <<~SQL.squish, FinancialContracts::RECONCILIATION_EVENT_TYPES ]
            SELECT
              (
                SELECT COUNT(*)
                FROM reconciliation_runs rr
                WHERE btrim(provider) = ''
                   OR status NOT IN ('matched', 'discrepant')
                   OR discrepancy_cents <> provider_balance_cents - ledger_balance_cents
                   OR NOT EXISTS (
                     SELECT 1
                     FROM outbox_events oe
                     WHERE oe.aggregate_type = 'ReconciliationRun'
                       AND oe.aggregate_id = rr.id
                       AND oe.event_type IN (?)
                   )
                   OR NOT EXISTS (
                     SELECT 1
                     FROM reconciliation_rows row
                     WHERE row.reconciliation_run_id = rr.id
                   )
                   OR (status = 'matched' AND EXISTS (
                     SELECT 1
                     FROM reconciliation_rows row
                     WHERE row.reconciliation_run_id = rr.id
                       AND row.status <> 'matched'
                   ))
                   OR (status = 'discrepant' AND NOT EXISTS (
                     SELECT 1
                     FROM reconciliation_rows row
                     WHERE row.reconciliation_run_id = rr.id
                       AND row.status <> 'matched'
                   ))
              )
              +
              (
                SELECT COUNT(*)
                FROM reconciliation_rows row
                LEFT JOIN reconciliation_runs run ON run.id = row.reconciliation_run_id
                LEFT JOIN journal_entries journal ON journal.id = row.journal_entry_id
                WHERE run.id IS NULL
                   OR run.organization_id <> row.organization_id
                   OR (journal.id IS NOT NULL AND journal.organization_id <> row.organization_id)
                   OR (row.status = 'matched' AND row.difference_cents <> 0)
                   OR (row.status = 'discrepant' AND row.difference_cents = 0)
                   OR (row.status = 'missing_in_ledger' AND (row.ledger_amount_cents <> 0 OR row.provider_amount_cents = 0))
                   OR (row.status = 'missing_in_provider' AND (row.provider_amount_cents <> 0 OR row.ledger_amount_cents = 0))
              )
          SQL
        )
      end
    end
  end
end
