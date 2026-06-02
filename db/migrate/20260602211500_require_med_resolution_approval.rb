class RequireMedResolutionApproval < ActiveRecord::Migration[8.1]
  def up
    add_reference :med_cases, :operator_approval
    add_foreign_key :med_cases, :operator_approvals, column: :operator_approval_id, validate: false
    validate_foreign_key :med_cases, :operator_approvals, column: :operator_approval_id

    execute <<~SQL
      CREATE OR REPLACE FUNCTION med_case_has_resolution_approval(med_case_id_to_check bigint)
      RETURNS boolean
      LANGUAGE sql
      STABLE
      AS $$
        SELECT EXISTS (
          SELECT 1
          FROM med_cases med_case
          JOIN operator_approvals approval
            ON approval.id = med_case.operator_approval_id
          WHERE med_case.id = med_case_id_to_check
            AND approval.organization_id = med_case.organization_id
            AND approval.subject_type = 'MedCase'
            AND approval.subject_id = med_case.id
            AND approval.status = 'approved'
            AND (
              (med_case.status = 'rejected' AND approval.action = 'med_case.reject')
              OR (med_case.status = 'refunded' AND approval.action = 'med_case.accept')
            )
        );
      $$;

      CREATE OR REPLACE FUNCTION med_case_has_refund_evidence(med_case_id_to_check bigint)
      RETURNS boolean
      LANGUAGE sql
      STABLE
      AS $$
        SELECT EXISTS (
          SELECT 1
          FROM med_cases med_case
          JOIN refunds refund
            ON refund.id = med_case.refund_id
          WHERE med_case.id = med_case_id_to_check
            AND refund.organization_id = med_case.organization_id
            AND refund.pix_payment_id = med_case.pix_payment_id
            AND refund.amount_cents = med_case.amount_cents
            AND refund.currency = med_case.currency
            AND refund.status = 'settled'
            AND refund.idempotency_key = 'med_case.refund:' || med_case.id::text
        );
      $$;

      CREATE OR REPLACE FUNCTION assert_med_case_state_evidence()
      RETURNS trigger AS $$
      DECLARE
        med_case_row med_cases%ROWTYPE;
      BEGIN
        SELECT * INTO med_case_row FROM med_cases WHERE id = NEW.id;

        IF med_case_row.status = 'opened'
          AND (
            med_case_row.refund_id IS NOT NULL
            OR med_case_row.resolved_at IS NOT NULL
            OR med_case_row.operator_approval_id IS NOT NULL
          ) THEN
          RAISE EXCEPTION 'opened MED case cannot have resolution evidence';
        END IF;

        IF med_case_row.status = 'rejected'
          AND (
            med_case_row.refund_id IS NOT NULL
            OR med_case_row.resolved_at IS NULL
            OR med_case_row.operator_approval_id IS NULL
            OR NOT med_case_has_resolution_approval(med_case_row.id)
          ) THEN
          RAISE EXCEPTION 'rejected MED case requires approved rejection evidence without refund';
        END IF;

        IF med_case_row.status = 'refunded'
          AND (
            med_case_row.refund_id IS NULL
            OR med_case_row.resolved_at IS NULL
            OR med_case_row.operator_approval_id IS NULL
            OR NOT med_case_has_refund_evidence(med_case_row.id)
            OR NOT med_case_has_resolution_approval(med_case_row.id)
          ) THEN
          RAISE EXCEPTION 'refunded MED case requires refund, resolution, and approved acceptance evidence';
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE OR REPLACE FUNCTION prevent_med_case_evidence_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        has_evidence boolean;
        allowed_transition boolean;
      BEGIN
        has_evidence := OLD.refund_id IS NOT NULL
          OR OLD.resolved_at IS NOT NULL
          OR OLD.operator_approval_id IS NOT NULL
          OR financial_aggregate_has_outbox_evidence('MedCase', OLD.id);

        IF TG_OP = 'DELETE' THEN
          IF has_evidence THEN
            RAISE EXCEPTION 'MED case with resolution or outbox evidence cannot be deleted';
          END IF;
          RETURN OLD;
        END IF;

        IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.pix_payment_id IS DISTINCT FROM NEW.pix_payment_id
          OR OLD.external_id IS DISTINCT FROM NEW.external_id
          OR OLD.amount_cents IS DISTINCT FROM NEW.amount_cents
          OR OLD.currency IS DISTINCT FROM NEW.currency
          OR OLD.reason IS DISTINCT FROM NEW.reason
          OR OLD.opened_at IS DISTINCT FROM NEW.opened_at
          OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
          OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'MED case identity and value are immutable';
        END IF;

        allowed_transition := OLD.status = 'opened' AND (
          (
            NEW.status = 'refunded'
            AND OLD.refund_id IS NULL
            AND NEW.refund_id IS NOT NULL
            AND OLD.resolved_at IS NULL
            AND NEW.resolved_at IS NOT NULL
            AND OLD.operator_approval_id IS NULL
            AND NEW.operator_approval_id IS NOT NULL
            AND OLD.metadata IS NOT DISTINCT FROM NEW.metadata
          )
          OR (
            NEW.status = 'rejected'
            AND OLD.refund_id IS NOT DISTINCT FROM NEW.refund_id
            AND OLD.resolved_at IS NULL
            AND NEW.resolved_at IS NOT NULL
            AND OLD.operator_approval_id IS NULL
            AND NEW.operator_approval_id IS NOT NULL
          )
        );

        IF has_evidence
          AND NOT allowed_transition
          AND (
            OLD.status IS DISTINCT FROM NEW.status
            OR OLD.refund_id IS DISTINCT FROM NEW.refund_id
            OR OLD.resolved_at IS DISTINCT FROM NEW.resolved_at
            OR OLD.operator_approval_id IS DISTINCT FROM NEW.operator_approval_id
            OR OLD.metadata IS DISTINCT FROM NEW.metadata
            OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
          ) THEN
          RAISE EXCEPTION 'MED case with outbox evidence only allows documented approval-backed resolution transitions';
        END IF;

        RETURN NEW;
      END;
      $$;

      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM med_cases
          WHERE (status = 'opened' AND (refund_id IS NOT NULL OR resolved_at IS NOT NULL OR operator_approval_id IS NOT NULL))
             OR (status = 'rejected' AND (refund_id IS NOT NULL OR resolved_at IS NULL OR operator_approval_id IS NULL OR NOT med_case_has_resolution_approval(id)))
             OR (status = 'refunded' AND (refund_id IS NULL OR resolved_at IS NULL OR operator_approval_id IS NULL OR NOT med_case_has_refund_evidence(id) OR NOT med_case_has_resolution_approval(id)))
        ) THEN
          RAISE EXCEPTION 'existing MED cases violate approval-backed state evidence guards';
        END IF;
      END
      $$;
    SQL
  end

  def down
    execute <<~SQL
      CREATE OR REPLACE FUNCTION assert_med_case_state_evidence()
      RETURNS trigger AS $$
      DECLARE
        med_case_row med_cases%ROWTYPE;
      BEGIN
        SELECT * INTO med_case_row FROM med_cases WHERE id = NEW.id;

        IF med_case_row.status = 'opened'
          AND (med_case_row.refund_id IS NOT NULL OR med_case_row.resolved_at IS NOT NULL) THEN
          RAISE EXCEPTION 'opened MED case cannot have resolution evidence';
        END IF;

        IF med_case_row.status = 'rejected'
          AND (med_case_row.refund_id IS NOT NULL OR med_case_row.resolved_at IS NULL) THEN
          RAISE EXCEPTION 'rejected MED case requires rejection resolution without refund';
        END IF;

        IF med_case_row.status = 'refunded'
          AND (med_case_row.refund_id IS NULL OR med_case_row.resolved_at IS NULL) THEN
          RAISE EXCEPTION 'refunded MED case requires refund and resolution evidence';
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE OR REPLACE FUNCTION prevent_med_case_evidence_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        has_evidence boolean;
        allowed_transition boolean;
      BEGIN
        has_evidence := OLD.refund_id IS NOT NULL
          OR OLD.resolved_at IS NOT NULL
          OR financial_aggregate_has_outbox_evidence('MedCase', OLD.id);

        IF TG_OP = 'DELETE' THEN
          IF has_evidence THEN
            RAISE EXCEPTION 'MED case with resolution or outbox evidence cannot be deleted';
          END IF;
          RETURN OLD;
        END IF;

        IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.pix_payment_id IS DISTINCT FROM NEW.pix_payment_id
          OR OLD.external_id IS DISTINCT FROM NEW.external_id
          OR OLD.amount_cents IS DISTINCT FROM NEW.amount_cents
          OR OLD.currency IS DISTINCT FROM NEW.currency
          OR OLD.reason IS DISTINCT FROM NEW.reason
          OR OLD.opened_at IS DISTINCT FROM NEW.opened_at
          OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
          OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'MED case identity and value are immutable';
        END IF;

        allowed_transition := OLD.status = 'opened' AND (
          (
            NEW.status = 'refunded'
            AND OLD.refund_id IS NULL
            AND NEW.refund_id IS NOT NULL
            AND OLD.resolved_at IS NULL
            AND NEW.resolved_at IS NOT NULL
            AND OLD.metadata IS NOT DISTINCT FROM NEW.metadata
          )
          OR (
            NEW.status = 'rejected'
            AND OLD.refund_id IS NOT DISTINCT FROM NEW.refund_id
            AND OLD.resolved_at IS NULL
            AND NEW.resolved_at IS NOT NULL
          )
        );

        IF has_evidence
          AND NOT allowed_transition
          AND (
            OLD.status IS DISTINCT FROM NEW.status
            OR OLD.refund_id IS DISTINCT FROM NEW.refund_id
            OR OLD.resolved_at IS DISTINCT FROM NEW.resolved_at
            OR OLD.metadata IS DISTINCT FROM NEW.metadata
            OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
          ) THEN
          RAISE EXCEPTION 'MED case with outbox evidence only allows documented resolution transitions';
        END IF;

        RETURN NEW;
      END;
      $$;

      DROP FUNCTION IF EXISTS med_case_has_resolution_approval(bigint);
      DROP FUNCTION IF EXISTS med_case_has_refund_evidence(bigint);
    SQL

    remove_reference :med_cases, :operator_approval, foreign_key: true
  end
end
