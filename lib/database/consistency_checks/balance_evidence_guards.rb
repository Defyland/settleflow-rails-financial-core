module Database
  module ConsistencyChecks
    class BalanceEvidenceGuards < Base
      EXPECTED_CONSTRAINTS = %w[
        balance_projections_available_non_negative_check
        balance_projections_pending_non_negative_check
        balance_projections_blocked_non_negative_check
        balance_snapshots_available_non_negative_check
        balance_snapshots_pending_non_negative_check
        balance_snapshots_blocked_non_negative_check
        balance_snapshots_difference_matches_projection_check
        balance_snapshots_source_present_check
      ].freeze
      EXPECTED_TRIGGERS = %w[
        balance_projections_amount_write_gate_before_update
        balance_projections_wallet_evidence_before_write
        balance_snapshots_prevent_evidence_mutation
      ].freeze

      def call
        enabled_constraints = connection.select_values(<<~SQL.squish)
          SELECT conname
          FROM pg_constraint
          WHERE conrelid IN ('balance_projections'::regclass, 'balance_snapshots'::regclass)
        SQL
        enabled_triggers = connection.select_values(<<~SQL.squish)
          SELECT tgname
          FROM pg_trigger
          WHERE tgrelid IN ('balance_projections'::regclass, 'balance_snapshots'::regclass)
            AND NOT tgisinternal
            AND tgenabled <> 'D'
        SQL
        projection_mismatches = connection.select_value(<<~SQL.squish).to_i
          SELECT COUNT(*)
          FROM balance_projections bp
          LEFT JOIN wallets w ON w.id = bp.wallet_id
          WHERE w.id IS NULL
             OR w.organization_id <> bp.organization_id
             OR w.currency <> bp.currency
        SQL
        snapshot_mismatches = connection.select_value(<<~SQL.squish).to_i
          SELECT COUNT(*)
          FROM balance_snapshots bs
          LEFT JOIN wallets w ON w.id = bs.wallet_id
          WHERE w.id IS NULL
             OR w.organization_id <> bs.organization_id
             OR w.currency <> bs.currency
             OR bs.difference_cents <> bs.available_cents - bs.ledger_available_cents
             OR btrim(bs.source) = ''
        SQL
        write_gate_function_present = catalog_value(<<~SQL.squish)
          SELECT EXISTS (
            SELECT 1
            FROM pg_proc
            WHERE proname = 'assert_balance_projection_amount_write_context'
          )
        SQL
        present_constraints = enabled_constraints & EXPECTED_CONSTRAINTS
        present_triggers = enabled_triggers & EXPECTED_TRIGGERS
        missing_constraints = EXPECTED_CONSTRAINTS - present_constraints
        missing_triggers = EXPECTED_TRIGGERS - present_triggers

        check(
          name: :balance_evidence_guards,
          ok: write_gate_function_present && missing_constraints.empty? && missing_triggers.empty? &&
            projection_mismatches.zero? && snapshot_mismatches.zero?,
          details: {
            write_gate_function_present:,
            present_constraints: present_constraints.sort,
            missing_constraints:,
            present_triggers: present_triggers.sort,
            missing_triggers:,
            projection_wallet_mismatches: projection_mismatches,
            snapshot_evidence_mismatches: snapshot_mismatches
          }
        )
      end
    end
  end
end
