module Database
  module ConsistencyChecks
    class IdempotencyEvidenceGuards < Base
      EXPECTED_CONSTRAINTS = %w[
        idempotency_keys_status_check
        idempotency_keys_request_hash_sha256_check
        idempotency_keys_identity_present_check
        idempotency_keys_response_state_check
      ].freeze

      def call
        expected_command_constraints = FinancialContracts::IDEMPOTENCY_REQUIRED_COMMAND_CONSTRAINTS
        enabled_constraints = connection.select_values(<<~SQL.squish)
          SELECT conname
          FROM pg_constraint
          WHERE conrelid = 'idempotency_keys'::regclass
        SQL
        command_constraints = connection.exec_query(command_constraints_sql(expected_command_constraints)).to_a.to_h do |row|
          [ row.fetch("table_name"), row.fetch("constraint_name") ]
        end
        trigger_present = catalog_value(<<~SQL.squish)
          SELECT EXISTS (
            SELECT 1
            FROM pg_trigger
            WHERE tgname = 'idempotency_keys_prevent_evidence_mutation'
              AND tgrelid = 'idempotency_keys'::regclass
              AND NOT tgisinternal
              AND tgenabled <> 'D'
          )
        SQL
        present_constraints = enabled_constraints & EXPECTED_CONSTRAINTS
        missing_constraints = EXPECTED_CONSTRAINTS - present_constraints
        present_command_constraints = expected_command_constraints.select do |table_name, constraint_name|
          command_constraints[table_name] == constraint_name
        end
        missing_command_constraints = expected_command_constraints.except(*present_command_constraints.keys)

        check(
          name: :idempotency_evidence_guards,
          ok: trigger_present && missing_constraints.empty? && missing_command_constraints.empty?,
          details: {
            mutation_trigger_present: trigger_present,
            present_constraints: present_constraints.sort,
            missing_constraints:,
            present_command_constraints: present_command_constraints.values.sort,
            missing_command_constraints: missing_command_constraints.values.sort
          }
        )
      end

      private

      def command_constraints_sql(expected_command_constraints)
        sanitize_sql_array(
          [ <<~SQL.squish, expected_command_constraints.keys, expected_command_constraints.values ]
            SELECT cls.relname AS table_name, con.conname AS constraint_name
            FROM pg_constraint con
            JOIN pg_class cls ON cls.oid = con.conrelid
            WHERE cls.relname IN (?)
              AND con.conname IN (?)
          SQL
        )
      end
    end
  end
end
