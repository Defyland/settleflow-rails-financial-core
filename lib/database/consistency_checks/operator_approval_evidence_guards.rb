module Database
  module ConsistencyChecks
    class OperatorApprovalEvidenceGuards < Base
      EXPECTED_CONSTRAINTS = %w[
        operator_approvals_status_check
        operator_approvals_dual_control_check
        operator_approvals_identity_present_check
        operator_approvals_state_evidence_check
      ].freeze
      EXPECTED_TRIGGERS = %w[
        operator_approvals_prevent_evidence_mutation
      ].freeze

      def call
        enabled_constraints = connection.select_values(<<~SQL.squish)
          SELECT conname
          FROM pg_constraint
          WHERE conrelid = 'operator_approvals'::regclass
        SQL
        enabled_triggers = connection.select_values(<<~SQL.squish)
          SELECT tgname
          FROM pg_trigger
          WHERE tgrelid = 'operator_approvals'::regclass
            AND NOT tgisinternal
            AND tgenabled <> 'D'
        SQL
        evidence_mismatches = connection.select_value(<<~SQL.squish).to_i
          SELECT COUNT(*)
          FROM operator_approvals
          WHERE btrim(action) = ''
             OR btrim(subject_type) = ''
             OR subject_id <= 0
             OR status NOT IN ('pending', 'approved', 'rejected')
             OR approved_by_id = requested_by_id
             OR (status = 'pending' AND (approved_by_id IS NOT NULL OR approved_at IS NOT NULL))
             OR (status IN ('approved', 'rejected') AND (approved_by_id IS NULL OR approved_at IS NULL))
        SQL
        present_constraints = enabled_constraints & EXPECTED_CONSTRAINTS
        present_triggers = enabled_triggers & EXPECTED_TRIGGERS
        missing_constraints = EXPECTED_CONSTRAINTS - present_constraints
        missing_triggers = EXPECTED_TRIGGERS - present_triggers

        check(
          name: :operator_approval_evidence_guards,
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
    end
  end
end
