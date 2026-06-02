class AddOperatorApprovalEvidenceGuards < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM operator_approvals
          WHERE btrim(action) = ''
             OR btrim(subject_type) = ''
             OR subject_id <= 0
             OR status NOT IN ('pending', 'approved', 'rejected')
             OR approved_by_id = requested_by_id
             OR (status = 'pending' AND (approved_by_id IS NOT NULL OR approved_at IS NOT NULL))
             OR (status IN ('approved', 'rejected') AND (approved_by_id IS NULL OR approved_at IS NULL))
        ) THEN
          RAISE EXCEPTION 'existing operator_approvals violate evidence guards';
        END IF;
      END
      $$;
    SQL

    add_check_constraint :operator_approvals,
      "btrim(action) <> '' AND btrim(subject_type) <> '' AND subject_id > 0",
      name: "operator_approvals_identity_present_check",
      validate: false
    add_check_constraint :operator_approvals,
      <<~SQL.squish,
        (
          status = 'pending'
          AND approved_by_id IS NULL
          AND approved_at IS NULL
        )
        OR (
          status IN ('approved', 'rejected')
          AND approved_by_id IS NOT NULL
          AND approved_at IS NOT NULL
        )
      SQL
      name: "operator_approvals_state_evidence_check",
      validate: false
    validate_check_constraint :operator_approvals, name: "operator_approvals_identity_present_check"
    validate_check_constraint :operator_approvals, name: "operator_approvals_state_evidence_check"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION prevent_operator_approval_evidence_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'operator approvals are governance evidence';
        END IF;

        IF TG_OP = 'INSERT' THEN
          IF NEW.status <> 'pending'
            OR NEW.approved_by_id IS NOT NULL
            OR NEW.approved_at IS NOT NULL THEN
            RAISE EXCEPTION 'operator approvals must start pending';
          END IF;

          RETURN NEW;
        END IF;

        IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.action IS DISTINCT FROM NEW.action
          OR OLD.subject_type IS DISTINCT FROM NEW.subject_type
          OR OLD.subject_id IS DISTINCT FROM NEW.subject_id
          OR OLD.requested_by_id IS DISTINCT FROM NEW.requested_by_id
          OR OLD.reason IS DISTINCT FROM NEW.reason
          OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'operator approval identity is immutable';
        END IF;

        IF OLD.status IN ('approved', 'rejected') THEN
          RAISE EXCEPTION 'terminal operator approvals are immutable governance evidence';
        END IF;

        IF OLD.status <> 'pending' OR NEW.status NOT IN ('pending', 'approved', 'rejected') THEN
          RAISE EXCEPTION 'invalid operator approval state transition';
        END IF;

        IF NEW.status = 'pending'
          AND (OLD.approved_by_id IS DISTINCT FROM NEW.approved_by_id OR OLD.approved_at IS DISTINCT FROM NEW.approved_at) THEN
          RAISE EXCEPTION 'pending operator approvals cannot carry checker evidence';
        END IF;

        RETURN NEW;
      END;
      $$;

      DROP TRIGGER IF EXISTS operator_approvals_prevent_evidence_mutation ON operator_approvals;
      CREATE TRIGGER operator_approvals_prevent_evidence_mutation
      BEFORE INSERT OR UPDATE OR DELETE ON operator_approvals
      FOR EACH ROW EXECUTE FUNCTION prevent_operator_approval_evidence_mutation();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS operator_approvals_prevent_evidence_mutation ON operator_approvals;
      DROP FUNCTION IF EXISTS prevent_operator_approval_evidence_mutation();
    SQL

    remove_check_constraint :operator_approvals, name: "operator_approvals_state_evidence_check"
    remove_check_constraint :operator_approvals, name: "operator_approvals_identity_present_check"
  end
end
