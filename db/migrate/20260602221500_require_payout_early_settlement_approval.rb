class RequirePayoutEarlySettlementApproval < ActiveRecord::Migration[8.1]
  def up
    add_reference :payouts, :operator_approval
    add_foreign_key :payouts, :operator_approvals, column: :operator_approval_id, validate: false
    validate_foreign_key :payouts, :operator_approvals, column: :operator_approval_id

    execute <<~SQL
      CREATE OR REPLACE FUNCTION payout_has_early_settlement_approval(payout_id_to_check bigint)
      RETURNS boolean
      LANGUAGE sql
      STABLE
      AS $$
        SELECT EXISTS (
          SELECT 1
          FROM payouts payout
          JOIN operator_approvals approval
            ON approval.id = payout.operator_approval_id
          WHERE payout.id = payout_id_to_check
            AND approval.organization_id = payout.organization_id
            AND approval.subject_type = 'Payout'
            AND approval.subject_id = payout.id
            AND approval.action = 'payout.settle_early'
            AND approval.status = 'approved'
            AND approval.approved_by_id IS NOT NULL
            AND approval.approved_at IS NOT NULL
            AND approval.approved_by_id <> approval.requested_by_id
        );
      $$;

      CREATE OR REPLACE FUNCTION assert_payout_state_evidence()
      RETURNS trigger AS $$
      DECLARE
        payout_row payouts%ROWTYPE;
      BEGIN
        SELECT * INTO payout_row FROM payouts WHERE id = NEW.id;

        IF payout_row.status = 'scheduled'
          AND (
            payout_row.journal_entry_id IS NULL
            OR payout_row.settlement_journal_entry_id IS NOT NULL
            OR payout_row.settled_at IS NOT NULL
            OR payout_row.operator_approval_id IS NOT NULL
          ) THEN
          RAISE EXCEPTION 'scheduled payout requires schedule journal evidence only';
        END IF;

        IF payout_row.status = 'settled'
          AND (
            payout_row.journal_entry_id IS NULL
            OR payout_row.settlement_journal_entry_id IS NULL
            OR payout_row.settled_at IS NULL
          ) THEN
          RAISE EXCEPTION 'settled payout requires schedule and settlement journal evidence';
        END IF;

        IF payout_row.status = 'settled'
          AND payout_row.settled_at::date < payout_row.settlement_due_on
          AND NOT payout_has_early_settlement_approval(payout_row.id) THEN
          RAISE EXCEPTION 'early payout settlement requires approved maker-checker evidence';
        END IF;

        IF payout_row.status = 'failed' AND payout_row.failure_code IS NULL THEN
          RAISE EXCEPTION 'failed payout requires a failure code';
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE OR REPLACE FUNCTION prevent_payout_evidence_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        has_evidence boolean;
        allowed_transition boolean;
      BEGIN
        has_evidence := OLD.journal_entry_id IS NOT NULL
          OR OLD.settlement_journal_entry_id IS NOT NULL
          OR financial_aggregate_has_outbox_evidence('Payout', OLD.id);

        IF TG_OP = 'DELETE' THEN
          IF has_evidence THEN
            RAISE EXCEPTION 'payout with ledger or outbox evidence cannot be deleted';
          END IF;
          RETURN OLD;
        END IF;

        IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.wallet_id IS DISTINCT FROM NEW.wallet_id
          OR OLD.external_id IS DISTINCT FROM NEW.external_id
          OR OLD.amount_cents IS DISTINCT FROM NEW.amount_cents
          OR OLD.currency IS DISTINCT FROM NEW.currency
          OR OLD.settlement_delay_days IS DISTINCT FROM NEW.settlement_delay_days
          OR OLD.settlement_due_on IS DISTINCT FROM NEW.settlement_due_on
          OR OLD.destination_kind IS DISTINCT FROM NEW.destination_kind
          OR OLD.destination_reference IS DISTINCT FROM NEW.destination_reference
          OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
          OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'payout identity and value are immutable';
        END IF;

        IF OLD.journal_entry_id IS NOT NULL AND OLD.journal_entry_id IS DISTINCT FROM NEW.journal_entry_id THEN
          RAISE EXCEPTION 'payout schedule journal evidence is immutable';
        END IF;

        allowed_transition := OLD.status = 'scheduled' AND (
          (
            NEW.status = 'settled'
            AND OLD.settlement_journal_entry_id IS NULL
            AND NEW.settlement_journal_entry_id IS NOT NULL
            AND OLD.settled_at IS NULL
            AND NEW.settled_at IS NOT NULL
            AND (
              (NEW.settled_at::date >= NEW.settlement_due_on AND NEW.operator_approval_id IS NULL)
              OR (NEW.settled_at::date < NEW.settlement_due_on AND OLD.operator_approval_id IS NULL AND NEW.operator_approval_id IS NOT NULL)
            )
            AND OLD.failure_code IS NOT DISTINCT FROM NEW.failure_code
            AND OLD.metadata IS NOT DISTINCT FROM NEW.metadata
          )
          OR (
            NEW.status = 'failed'
            AND OLD.settlement_journal_entry_id IS NOT DISTINCT FROM NEW.settlement_journal_entry_id
            AND OLD.settled_at IS NOT DISTINCT FROM NEW.settled_at
            AND OLD.operator_approval_id IS NOT DISTINCT FROM NEW.operator_approval_id
            AND OLD.failure_code IS NULL
            AND NEW.failure_code IS NOT NULL
            AND OLD.metadata IS NOT DISTINCT FROM NEW.metadata
          )
        );

        IF has_evidence
          AND NOT allowed_transition
          AND (
            OLD.status IS DISTINCT FROM NEW.status
            OR OLD.settlement_journal_entry_id IS DISTINCT FROM NEW.settlement_journal_entry_id
            OR OLD.settled_at IS DISTINCT FROM NEW.settled_at
            OR OLD.operator_approval_id IS DISTINCT FROM NEW.operator_approval_id
            OR OLD.failure_code IS DISTINCT FROM NEW.failure_code
            OR OLD.metadata IS DISTINCT FROM NEW.metadata
            OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
          ) THEN
          RAISE EXCEPTION 'payout with ledger or outbox evidence only allows documented lifecycle transitions';
        END IF;

        RETURN NEW;
      END;
      $$;

      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM payouts
          WHERE status = 'settled'
            AND settled_at::date < settlement_due_on
            AND NOT payout_has_early_settlement_approval(id)
        ) THEN
          RAISE EXCEPTION 'existing early payout settlements lack maker-checker evidence';
        END IF;
      END
      $$;
    SQL
  end

  def down
    execute <<~SQL
      CREATE OR REPLACE FUNCTION assert_payout_state_evidence()
      RETURNS trigger AS $$
      DECLARE
        payout_row payouts%ROWTYPE;
      BEGIN
        SELECT * INTO payout_row FROM payouts WHERE id = NEW.id;

        IF payout_row.status = 'scheduled'
          AND (
            payout_row.journal_entry_id IS NULL
            OR payout_row.settlement_journal_entry_id IS NOT NULL
            OR payout_row.settled_at IS NOT NULL
          ) THEN
          RAISE EXCEPTION 'scheduled payout requires schedule journal evidence only';
        END IF;

        IF payout_row.status = 'settled'
          AND (
            payout_row.journal_entry_id IS NULL
            OR payout_row.settlement_journal_entry_id IS NULL
            OR payout_row.settled_at IS NULL
          ) THEN
          RAISE EXCEPTION 'settled payout requires schedule and settlement journal evidence';
        END IF;

        IF payout_row.status = 'failed' AND payout_row.failure_code IS NULL THEN
          RAISE EXCEPTION 'failed payout requires a failure code';
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE OR REPLACE FUNCTION prevent_payout_evidence_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        has_evidence boolean;
        allowed_transition boolean;
      BEGIN
        has_evidence := OLD.journal_entry_id IS NOT NULL
          OR OLD.settlement_journal_entry_id IS NOT NULL
          OR financial_aggregate_has_outbox_evidence('Payout', OLD.id);

        IF TG_OP = 'DELETE' THEN
          IF has_evidence THEN
            RAISE EXCEPTION 'payout with ledger or outbox evidence cannot be deleted';
          END IF;
          RETURN OLD;
        END IF;

        IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.wallet_id IS DISTINCT FROM NEW.wallet_id
          OR OLD.external_id IS DISTINCT FROM NEW.external_id
          OR OLD.amount_cents IS DISTINCT FROM NEW.amount_cents
          OR OLD.currency IS DISTINCT FROM NEW.currency
          OR OLD.settlement_delay_days IS DISTINCT FROM NEW.settlement_delay_days
          OR OLD.settlement_due_on IS DISTINCT FROM NEW.settlement_due_on
          OR OLD.destination_kind IS DISTINCT FROM NEW.destination_kind
          OR OLD.destination_reference IS DISTINCT FROM NEW.destination_reference
          OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
          OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'payout identity and value are immutable';
        END IF;

        IF OLD.journal_entry_id IS NOT NULL AND OLD.journal_entry_id IS DISTINCT FROM NEW.journal_entry_id THEN
          RAISE EXCEPTION 'payout schedule journal evidence is immutable';
        END IF;

        allowed_transition := OLD.status = 'scheduled' AND (
          (
            NEW.status = 'settled'
            AND OLD.settlement_journal_entry_id IS NULL
            AND NEW.settlement_journal_entry_id IS NOT NULL
            AND OLD.settled_at IS NULL
            AND NEW.settled_at IS NOT NULL
            AND OLD.failure_code IS NOT DISTINCT FROM NEW.failure_code
            AND OLD.metadata IS NOT DISTINCT FROM NEW.metadata
          )
          OR (
            NEW.status = 'failed'
            AND OLD.settlement_journal_entry_id IS NOT DISTINCT FROM NEW.settlement_journal_entry_id
            AND OLD.settled_at IS NOT DISTINCT FROM NEW.settled_at
            AND OLD.failure_code IS NULL
            AND NEW.failure_code IS NOT NULL
            AND OLD.metadata IS NOT DISTINCT FROM NEW.metadata
          )
        );

        IF has_evidence
          AND NOT allowed_transition
          AND (
            OLD.status IS DISTINCT FROM NEW.status
            OR OLD.settlement_journal_entry_id IS DISTINCT FROM NEW.settlement_journal_entry_id
            OR OLD.settled_at IS DISTINCT FROM NEW.settled_at
            OR OLD.failure_code IS DISTINCT FROM NEW.failure_code
            OR OLD.metadata IS DISTINCT FROM NEW.metadata
            OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
          ) THEN
          RAISE EXCEPTION 'payout with ledger or outbox evidence only allows documented lifecycle transitions';
        END IF;

        RETURN NEW;
      END;
      $$;

      DROP FUNCTION IF EXISTS payout_has_early_settlement_approval(bigint);
    SQL

    remove_foreign_key :payouts, column: :operator_approval_id
    remove_reference :payouts, :operator_approval
  end
end
