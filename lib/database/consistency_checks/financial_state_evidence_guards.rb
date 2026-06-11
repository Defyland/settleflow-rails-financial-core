module Database
  module ConsistencyChecks
    class FinancialStateEvidenceGuards < Base
      def call
        expected_triggers = FinancialContracts::FINANCIAL_STATE_EVIDENCE_TRIGGERS
        enabled_triggers = connection.select_values(<<~SQL.squish)
          SELECT tgname
          FROM pg_trigger
          WHERE NOT tgisinternal
            AND tgenabled <> 'D'
        SQL
        functions = evidence_functions
        refund_limit_mismatches = refund_limit_mismatches(functions)
        payout_early_settlement_mismatches = payout_early_settlement_mismatches(functions)
        unique_split_destination_index_present = catalog_value(<<~SQL.squish)
          SELECT EXISTS (
            SELECT 1
            FROM pg_indexes
            WHERE schemaname = 'public'
              AND tablename = 'split_entries'
              AND indexname = 'idx_split_entries_unique_destination_per_split'
          )
        SQL
        duplicate_split_destination_rows = connection.select_value(<<~SQL.squish).to_i
          SELECT COALESCE(SUM(duplicate_count - 1), 0)
          FROM (
            SELECT COUNT(*) AS duplicate_count
            FROM split_entries
            GROUP BY split_payment_id, destination_wallet_id
            HAVING COUNT(*) > 1
          ) duplicate_split_destinations
        SQL
        present_triggers = enabled_triggers & expected_triggers
        missing_triggers = expected_triggers - present_triggers

        check(
          name: :financial_state_evidence_guards,
          ok: functions.values.all? && refund_limit_mismatches.zero? &&
            payout_early_settlement_mismatches.zero? && unique_split_destination_index_present &&
            duplicate_split_destination_rows.zero? && missing_triggers.empty?,
          details: functions.merge(
            refund_limit_mismatches:,
            payout_early_settlement_mismatches:,
            unique_split_destination_index_present:,
            duplicate_split_destination_rows:,
            present_triggers: present_triggers.sort,
            missing_triggers:
          )
        )
      end

      private

      def evidence_functions
        {
          aggregate_function_present: catalog_value(<<~SQL.squish),
            SELECT EXISTS (
              SELECT 1
              FROM pg_proc
              WHERE proname = 'financial_aggregate_has_outbox_evidence'
            )
          SQL
          med_resolution_functions_present: catalog_value(<<~SQL.squish),
            SELECT EXISTS (
              SELECT 1
              FROM pg_proc
              WHERE proname = 'med_case_has_resolution_approval'
            )
            AND EXISTS (
              SELECT 1
              FROM pg_proc
              WHERE proname = 'med_case_has_refund_evidence'
            )
          SQL
          refund_limit_function_present: catalog_value(<<~SQL.squish),
            SELECT EXISTS (
              SELECT 1
              FROM pg_proc
              WHERE proname = 'refund_pix_payment_evidence_valid'
            )
          SQL
          payout_early_settlement_function_present: catalog_value(<<~SQL.squish)
            SELECT EXISTS (
              SELECT 1
              FROM pg_proc
              WHERE proname = 'payout_has_early_settlement_approval'
            )
          SQL
        }
      end

      def refund_limit_mismatches(functions)
        return 0 unless functions.fetch(:refund_limit_function_present)

        connection.select_value(<<~SQL.squish).to_i
          SELECT COUNT(*)
          FROM pix_payments
          WHERE NOT refund_pix_payment_evidence_valid(id)
        SQL
      end

      def payout_early_settlement_mismatches(functions)
        return 0 unless functions.fetch(:payout_early_settlement_function_present)

        connection.select_value(<<~SQL.squish).to_i
          SELECT COUNT(*)
          FROM payouts
          WHERE status = 'settled'
            AND settled_at::date < settlement_due_on
            AND NOT payout_has_early_settlement_approval(id)
        SQL
      end
    end
  end
end
