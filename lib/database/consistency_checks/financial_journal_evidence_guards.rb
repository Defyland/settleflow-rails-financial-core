module Database
  module ConsistencyChecks
    class FinancialJournalEvidenceGuards < Base
      EXPECTED_TRIGGERS = %w[
        journal_entries_financial_evidence_after_write
        ledger_lines_financial_evidence_after_write
        fundings_journal_evidence_after_write
        transfers_journal_evidence_after_write
        split_payments_journal_evidence_after_write
        pix_payments_journal_evidence_after_write
        payouts_journal_evidence_after_write
        refunds_journal_evidence_after_write
      ].freeze

      def call
        expected_triggers = EXPECTED_TRIGGERS
        enabled_triggers = connection.select_values(<<~SQL.squish)
          SELECT tgname
          FROM pg_trigger
          WHERE NOT tgisinternal
            AND tgenabled <> 'D'
        SQL
        evidence_functions_present = catalog_value(<<~SQL.squish)
          SELECT EXISTS (
            SELECT 1
            FROM pg_proc
            WHERE proname = 'financial_journal_event_type_requires_evidence'
          )
          AND EXISTS (
            SELECT 1
            FROM pg_proc
            WHERE proname = 'financial_journal_has_aggregate_evidence'
          )
        SQL
        evidence_mismatches = evidence_mismatches(evidence_functions_present)
        present_triggers = enabled_triggers & expected_triggers
        missing_triggers = expected_triggers - present_triggers

        check(
          name: :financial_journal_evidence_guards,
          ok: evidence_functions_present && evidence_mismatches.zero? && missing_triggers.empty?,
          details: {
            evidence_functions_present:,
            present_triggers: present_triggers.sort,
            missing_triggers:,
            evidence_mismatches:
          }
        )
      end

      private

      def evidence_mismatches(evidence_functions_present)
        return 0 unless evidence_functions_present

        connection.select_value(<<~SQL.squish).to_i
          SELECT
            (
              SELECT COUNT(*)
              FROM journal_entries
              WHERE financial_journal_event_type_requires_evidence(event_type)
                AND NOT financial_journal_has_aggregate_evidence(id)
            )
            +
            (
              SELECT COUNT(*)
              FROM (
                SELECT journal_entry_id FROM fundings WHERE journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(journal_entry_id)
                UNION ALL
                SELECT journal_entry_id FROM transfers WHERE journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(journal_entry_id)
                UNION ALL
                SELECT journal_entry_id FROM split_payments WHERE journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(journal_entry_id)
                UNION ALL
                SELECT journal_entry_id FROM pix_payments WHERE journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(journal_entry_id)
                UNION ALL
                SELECT settlement_journal_entry_id FROM pix_payments WHERE settlement_journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(settlement_journal_entry_id)
                UNION ALL
                SELECT reversal_journal_entry_id FROM pix_payments WHERE reversal_journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(reversal_journal_entry_id)
                UNION ALL
                SELECT journal_entry_id FROM payouts WHERE journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(journal_entry_id)
                UNION ALL
                SELECT settlement_journal_entry_id FROM payouts WHERE settlement_journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(settlement_journal_entry_id)
                UNION ALL
                SELECT journal_entry_id FROM refunds WHERE journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(journal_entry_id)
              ) mismatches
            )
        SQL
      end
    end
  end
end
