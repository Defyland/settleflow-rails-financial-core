module Database
  module ConsistencyChecks
    class OutboxEvidenceGuards < Base
      EXPECTED_CONSTRAINTS = %w[
        outbox_events_payload_sha256_hex_check
        outbox_events_status_check
        outbox_events_delivery_state_check
      ].freeze

      EXPECTED_TRIGGERS = %w[
        outbox_legacy_command_identity_exceptions_prevent_mutation
        outbox_events_prevent_evidence_mutation
        outbox_events_aggregate_evidence_before_write
        outbox_events_med_resolution_payload_before_write
        outbox_events_command_identity_before_write
      ].freeze

      def call
        expected_constraints = EXPECTED_CONSTRAINTS
        expected_triggers = EXPECTED_TRIGGERS
        enabled_constraints = connection.select_values(<<~SQL.squish)
          SELECT conname
          FROM pg_constraint
          WHERE conrelid = 'outbox_events'::regclass
        SQL
        enabled_triggers = connection.select_values(<<~SQL.squish)
          SELECT tgname
          FROM pg_trigger
          WHERE tgrelid IN (
              'outbox_events'::regclass,
              to_regclass('public.outbox_legacy_command_identity_exceptions')
            )
            AND NOT tgisinternal
            AND tgenabled <> 'D'
        SQL
        functions = evidence_functions
        mismatches = evidence_mismatches(functions)
        present_constraints = enabled_constraints & expected_constraints
        present_triggers = enabled_triggers & expected_triggers
        missing_constraints = expected_constraints - present_constraints
        missing_triggers = expected_triggers - present_triggers

        check(
          name: :outbox_evidence_guards,
          ok: functions.values.all? &&
            mismatches.fetch(:aggregate_evidence_mismatches).zero? &&
            mismatches.fetch(:mutable_command_identity_mismatches).zero? &&
            mismatches.fetch(:legacy_exception_evidence_mismatches).zero? &&
            mismatches.fetch(:unaccepted_published_legacy_command_identity_mismatches).zero? &&
            missing_constraints.empty? && missing_triggers.empty?,
          details: functions.merge(
            present_constraints: present_constraints.sort,
            missing_constraints:,
            present_triggers: present_triggers.sort,
            missing_triggers:
          ).merge(mismatches)
        )
      end

      private

      def evidence_functions
        {
          aggregate_function_present: catalog_value(<<~SQL.squish),
            SELECT EXISTS (
              SELECT 1
              FROM pg_proc
              WHERE proname = 'outbox_event_has_aggregate_evidence'
            )
          SQL
          med_payload_function_present: catalog_value(<<~SQL.squish),
            SELECT EXISTS (
              SELECT 1
              FROM pg_proc
              WHERE proname = 'med_outbox_event_has_resolution_payload_evidence'
            )
          SQL
          command_identity_function_present: catalog_value(<<~SQL.squish),
            SELECT EXISTS (
              SELECT 1
              FROM pg_proc
              WHERE proname = 'outbox_event_has_command_identity_evidence'
            )
          SQL
          legacy_exception_table_present: catalog_value(<<~SQL.squish),
            SELECT to_regclass('public.outbox_legacy_command_identity_exceptions') IS NOT NULL
          SQL
          legacy_exception_functions_present: catalog_value(<<~SQL.squish)
            SELECT EXISTS (
              SELECT 1
              FROM pg_proc
              WHERE proname = 'outbox_event_expected_command_identity'
            )
            AND EXISTS (
              SELECT 1
              FROM pg_proc
              WHERE proname = 'outbox_legacy_command_identity_exception_valid'
            )
          SQL
        }
      end

      def evidence_mismatches(functions)
        {
          aggregate_evidence_mismatches: aggregate_evidence_mismatches(functions),
          mutable_command_identity_mismatches: mutable_command_identity_mismatches(functions),
          published_legacy_command_identity_mismatches: published_legacy_command_identity_mismatches(functions),
          accepted_published_legacy_command_identity_mismatches: accepted_published_legacy_command_identity_mismatches(functions),
          unaccepted_published_legacy_command_identity_mismatches: unaccepted_published_legacy_command_identity_mismatches(functions),
          legacy_exception_evidence_mismatches: legacy_exception_evidence_mismatches(functions)
        }
      end

      def aggregate_evidence_mismatches(functions)
        return 0 unless functions.fetch(:aggregate_function_present)

        connection.select_value(<<~SQL.squish).to_i
          SELECT COUNT(*)
          FROM outbox_events
          WHERE NOT outbox_event_has_aggregate_evidence(outbox_events)
        SQL
      end

      def mutable_command_identity_mismatches(functions)
        return 0 unless functions.fetch(:command_identity_function_present)

        connection.select_value(financial_command_identity_sql(<<~SQL.squish)).to_i
          SELECT COUNT(*)
          FROM outbox_events
          WHERE aggregate_type IN (?)
            AND payload_sha256 IS NULL
            AND status <> 'published'
            AND NOT outbox_event_has_command_identity_evidence(outbox_events)
        SQL
      end

      def published_legacy_command_identity_mismatches(functions)
        return 0 unless functions.fetch(:command_identity_function_present)

        connection.select_value(financial_command_identity_sql(<<~SQL.squish)).to_i
          SELECT COUNT(*)
          FROM outbox_events
          WHERE aggregate_type IN (?)
            AND payload_sha256 IS NOT NULL
            AND NOT outbox_event_has_command_identity_evidence(outbox_events)
        SQL
      end

      def accepted_published_legacy_command_identity_mismatches(functions)
        return 0 unless legacy_exception_checks_enabled?(functions)

        connection.select_value(financial_command_identity_sql(<<~SQL.squish)).to_i
          SELECT COUNT(*)
          FROM outbox_events event
          JOIN outbox_legacy_command_identity_exceptions exception
            ON exception.outbox_event_id = event.id
           AND outbox_legacy_command_identity_exception_valid(exception)
          WHERE event.aggregate_type IN (?)
            AND event.payload_sha256 IS NOT NULL
            AND NOT outbox_event_has_command_identity_evidence(event)
        SQL
      end

      def unaccepted_published_legacy_command_identity_mismatches(functions)
        return 0 unless legacy_exception_checks_enabled?(functions)

        connection.select_value(financial_command_identity_sql(<<~SQL.squish)).to_i
          SELECT COUNT(*)
          FROM outbox_events event
          LEFT JOIN outbox_legacy_command_identity_exceptions exception
            ON exception.outbox_event_id = event.id
           AND outbox_legacy_command_identity_exception_valid(exception)
          WHERE event.aggregate_type IN (?)
            AND event.payload_sha256 IS NOT NULL
            AND NOT outbox_event_has_command_identity_evidence(event)
            AND exception.id IS NULL
        SQL
      end

      def legacy_exception_evidence_mismatches(functions)
        return 0 unless functions.fetch(:legacy_exception_table_present) && functions.fetch(:legacy_exception_functions_present)

        connection.select_value(<<~SQL.squish).to_i
          SELECT COUNT(*)
          FROM outbox_legacy_command_identity_exceptions exception
          WHERE NOT outbox_legacy_command_identity_exception_valid(exception)
        SQL
      end

      def legacy_exception_checks_enabled?(functions)
        functions.fetch(:legacy_exception_table_present) &&
          functions.fetch(:legacy_exception_functions_present) &&
          functions.fetch(:command_identity_function_present)
      end

      def financial_command_identity_sql(sql)
        sanitize_sql_array([ sql, FinancialContracts::FINANCIAL_COMMAND_AGGREGATE_TYPES ])
      end
    end
  end
end
