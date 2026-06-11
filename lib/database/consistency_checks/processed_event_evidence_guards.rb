module Database
  module ConsistencyChecks
    class ProcessedEventEvidenceGuards < Base
      EXPECTED_CONSTRAINTS = %w[
        processed_events_status_check
        processed_events_payload_sha256_hex_check
        processed_events_state_evidence_check
      ].freeze

      def call
        enabled_constraints = connection.select_values(<<~SQL.squish)
          SELECT conname
          FROM pg_constraint
          WHERE conrelid = 'processed_events'::regclass
        SQL
        present_constraints = enabled_constraints & EXPECTED_CONSTRAINTS
        trigger_present = catalog_value(<<~SQL.squish)
          SELECT EXISTS (
            SELECT 1
            FROM pg_trigger
            WHERE tgname = 'processed_events_prevent_evidence_mutation'
              AND tgrelid = 'processed_events'::regclass
              AND NOT tgisinternal
              AND tgenabled <> 'D'
          )
        SQL
        mismatch_count = connection.select_value(<<~SQL.squish).to_i
          SELECT COUNT(*)
          FROM processed_events pe
          LEFT JOIN outbox_events oe ON oe.id = pe.outbox_event_id
          WHERE oe.id IS NULL
             OR oe.status <> 'published'
             OR oe.published_at IS NULL
             OR oe.payload_sha256 IS NULL
             OR oe.organization_id <> pe.organization_id
             OR oe.public_id::text <> pe.event_id
             OR oe.event_type <> pe.event_type
             OR oe.payload_sha256 <> pe.payload_sha256
        SQL
        missing_constraints = EXPECTED_CONSTRAINTS - present_constraints

        check(
          name: :processed_event_evidence_guards,
          ok: trigger_present && missing_constraints.empty? && mismatch_count.zero?,
          details: {
            mutation_trigger_present: trigger_present,
            present_constraints: present_constraints.sort,
            missing_constraints:,
            outbox_evidence_mismatches: mismatch_count
          }
        )
      end
    end
  end
end
