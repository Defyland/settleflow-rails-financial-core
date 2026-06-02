class AddFinancialAggregateMutationGuards < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION financial_aggregate_has_outbox_evidence(
        aggregate_type_to_check text,
        aggregate_id_to_check bigint
      )
      RETURNS boolean
      LANGUAGE sql
      STABLE
      AS $$
        SELECT EXISTS (
          SELECT 1
          FROM outbox_events
          WHERE aggregate_type = aggregate_type_to_check
            AND aggregate_id = aggregate_id_to_check
        );
      $$;

      CREATE OR REPLACE FUNCTION prevent_funding_evidence_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          IF OLD.journal_entry_id IS NOT NULL OR financial_aggregate_has_outbox_evidence('Funding', OLD.id) THEN
            RAISE EXCEPTION 'funding with ledger or outbox evidence is immutable';
          END IF;
          RETURN OLD;
        END IF;

        IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.wallet_id IS DISTINCT FROM NEW.wallet_id
          OR OLD.external_id IS DISTINCT FROM NEW.external_id
          OR OLD.amount_cents IS DISTINCT FROM NEW.amount_cents
          OR OLD.currency IS DISTINCT FROM NEW.currency
          OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
          OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'funding identity and value are immutable';
        END IF;

        IF (OLD.journal_entry_id IS NOT NULL OR financial_aggregate_has_outbox_evidence('Funding', OLD.id))
          AND (
            OLD.journal_entry_id IS DISTINCT FROM NEW.journal_entry_id
            OR OLD.status IS DISTINCT FROM NEW.status
            OR OLD.failure_code IS DISTINCT FROM NEW.failure_code
            OR OLD.metadata IS DISTINCT FROM NEW.metadata
            OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
          ) THEN
          RAISE EXCEPTION 'funding with ledger or outbox evidence is immutable';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE OR REPLACE FUNCTION prevent_transfer_evidence_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          IF OLD.journal_entry_id IS NOT NULL OR financial_aggregate_has_outbox_evidence('Transfer', OLD.id) THEN
            RAISE EXCEPTION 'transfer with ledger or outbox evidence is immutable';
          END IF;
          RETURN OLD;
        END IF;

        IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.source_wallet_id IS DISTINCT FROM NEW.source_wallet_id
          OR OLD.destination_wallet_id IS DISTINCT FROM NEW.destination_wallet_id
          OR OLD.external_id IS DISTINCT FROM NEW.external_id
          OR OLD.amount_cents IS DISTINCT FROM NEW.amount_cents
          OR OLD.currency IS DISTINCT FROM NEW.currency
          OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
          OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
          OR OLD.memo IS DISTINCT FROM NEW.memo
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'transfer identity and value are immutable';
        END IF;

        IF (OLD.journal_entry_id IS NOT NULL OR financial_aggregate_has_outbox_evidence('Transfer', OLD.id))
          AND (
            OLD.journal_entry_id IS DISTINCT FROM NEW.journal_entry_id
            OR OLD.status IS DISTINCT FROM NEW.status
            OR OLD.failure_code IS DISTINCT FROM NEW.failure_code
            OR OLD.metadata IS DISTINCT FROM NEW.metadata
            OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
          ) THEN
          RAISE EXCEPTION 'transfer with ledger or outbox evidence is immutable';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE OR REPLACE FUNCTION prevent_split_payment_evidence_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          IF OLD.journal_entry_id IS NOT NULL OR financial_aggregate_has_outbox_evidence('SplitPayment', OLD.id) THEN
            RAISE EXCEPTION 'split payment with ledger or outbox evidence is immutable';
          END IF;
          RETURN OLD;
        END IF;

        IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.source_wallet_id IS DISTINCT FROM NEW.source_wallet_id
          OR OLD.external_id IS DISTINCT FROM NEW.external_id
          OR OLD.total_amount_cents IS DISTINCT FROM NEW.total_amount_cents
          OR OLD.currency IS DISTINCT FROM NEW.currency
          OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
          OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
          OR OLD.memo IS DISTINCT FROM NEW.memo
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'split payment identity and value are immutable';
        END IF;

        IF (OLD.journal_entry_id IS NOT NULL OR financial_aggregate_has_outbox_evidence('SplitPayment', OLD.id))
          AND (
            OLD.journal_entry_id IS DISTINCT FROM NEW.journal_entry_id
            OR OLD.status IS DISTINCT FROM NEW.status
            OR OLD.failure_code IS DISTINCT FROM NEW.failure_code
            OR OLD.metadata IS DISTINCT FROM NEW.metadata
            OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
          ) THEN
          RAISE EXCEPTION 'split payment with ledger or outbox evidence is immutable';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE OR REPLACE FUNCTION prevent_split_entry_evidence_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        parent_has_evidence boolean;
      BEGIN
        IF TG_OP = 'DELETE' THEN
          SELECT split_payments.journal_entry_id IS NOT NULL
              OR financial_aggregate_has_outbox_evidence('SplitPayment', split_payments.id)
          INTO parent_has_evidence
          FROM split_payments
          WHERE split_payments.id = OLD.split_payment_id;

          IF parent_has_evidence THEN
            RAISE EXCEPTION 'split entry with parent ledger or outbox evidence is immutable';
          END IF;
          RETURN OLD;
        END IF;

        IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.split_payment_id IS DISTINCT FROM NEW.split_payment_id
          OR OLD.destination_wallet_id IS DISTINCT FROM NEW.destination_wallet_id
          OR OLD.amount_cents IS DISTINCT FROM NEW.amount_cents
          OR OLD.currency IS DISTINCT FROM NEW.currency
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'split entry identity and value are immutable';
        END IF;

        SELECT split_payments.journal_entry_id IS NOT NULL
            OR financial_aggregate_has_outbox_evidence('SplitPayment', split_payments.id)
        INTO parent_has_evidence
        FROM split_payments
        WHERE split_payments.id = OLD.split_payment_id;

        IF parent_has_evidence
          AND (
            OLD.metadata IS DISTINCT FROM NEW.metadata
            OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
          ) THEN
          RAISE EXCEPTION 'split entry with parent ledger or outbox evidence is immutable';
        END IF;

        RETURN NEW;
      END;
      $$;

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

      CREATE OR REPLACE FUNCTION prevent_refund_evidence_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          IF OLD.journal_entry_id IS NOT NULL OR financial_aggregate_has_outbox_evidence('Refund', OLD.id) THEN
            RAISE EXCEPTION 'refund with ledger or outbox evidence is immutable';
          END IF;
          RETURN OLD;
        END IF;

        IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.wallet_id IS DISTINCT FROM NEW.wallet_id
          OR OLD.pix_payment_id IS DISTINCT FROM NEW.pix_payment_id
          OR OLD.external_id IS DISTINCT FROM NEW.external_id
          OR OLD.amount_cents IS DISTINCT FROM NEW.amount_cents
          OR OLD.currency IS DISTINCT FROM NEW.currency
          OR OLD.reason IS DISTINCT FROM NEW.reason
          OR OLD.settled_at IS DISTINCT FROM NEW.settled_at
          OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
          OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'refund identity and value are immutable';
        END IF;

        IF (OLD.journal_entry_id IS NOT NULL OR financial_aggregate_has_outbox_evidence('Refund', OLD.id))
          AND (
            OLD.journal_entry_id IS DISTINCT FROM NEW.journal_entry_id
            OR OLD.status IS DISTINCT FROM NEW.status
            OR OLD.failure_code IS DISTINCT FROM NEW.failure_code
            OR OLD.metadata IS DISTINCT FROM NEW.metadata
            OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
          ) THEN
          RAISE EXCEPTION 'refund with ledger or outbox evidence is immutable';
        END IF;

        RETURN NEW;
      END;
      $$;

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

      CREATE OR REPLACE FUNCTION prevent_pix_payment_evidence_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        has_evidence boolean;
        allowed_transition boolean;
      BEGIN
        has_evidence := OLD.journal_entry_id IS NOT NULL
          OR OLD.settlement_journal_entry_id IS NOT NULL
          OR OLD.reversal_journal_entry_id IS NOT NULL
          OR financial_aggregate_has_outbox_evidence('PixPayment', OLD.id);

        IF TG_OP = 'DELETE' THEN
          IF has_evidence THEN
            RAISE EXCEPTION 'Pix payment with ledger or outbox evidence cannot be deleted';
          END IF;
          RETURN OLD;
        END IF;

        IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.wallet_id IS DISTINCT FROM NEW.wallet_id
          OR OLD.external_id IS DISTINCT FROM NEW.external_id
          OR OLD.pix_key IS DISTINCT FROM NEW.pix_key
          OR OLD.receiver_name IS DISTINCT FROM NEW.receiver_name
          OR OLD.amount_cents IS DISTINCT FROM NEW.amount_cents
          OR OLD.currency IS DISTINCT FROM NEW.currency
          OR OLD.risk_score IS DISTINCT FROM NEW.risk_score
          OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
          OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'Pix payment identity and value are immutable';
        END IF;

        IF OLD.journal_entry_id IS NOT NULL AND OLD.journal_entry_id IS DISTINCT FROM NEW.journal_entry_id THEN
          RAISE EXCEPTION 'Pix approval journal evidence is immutable';
        END IF;

        allowed_transition := (
          OLD.status = 'approved'
          AND NEW.status = 'settled'
          AND OLD.settlement_journal_entry_id IS NULL
          AND NEW.settlement_journal_entry_id IS NOT NULL
          AND OLD.reversal_journal_entry_id IS NOT DISTINCT FROM NEW.reversal_journal_entry_id
          AND OLD.reversed_at IS NOT DISTINCT FROM NEW.reversed_at
          AND OLD.reversal_reason IS NOT DISTINCT FROM NEW.reversal_reason
          AND OLD.failure_code IS NOT DISTINCT FROM NEW.failure_code
          AND OLD.metadata IS NOT DISTINCT FROM NEW.metadata
        ) OR (
          OLD.status = 'settled'
          AND NEW.status = 'reversed'
          AND OLD.reversal_journal_entry_id IS NULL
          AND NEW.reversal_journal_entry_id IS NOT NULL
          AND OLD.reversed_at IS NULL
          AND NEW.reversed_at IS NOT NULL
          AND OLD.reversal_reason IS NULL
          AND NEW.reversal_reason IS NOT NULL
          AND OLD.failure_code IS NOT DISTINCT FROM NEW.failure_code
        ) OR (
          OLD.status = 'pending_review'
          AND NEW.status = 'rejected'
          AND OLD.journal_entry_id IS NOT DISTINCT FROM NEW.journal_entry_id
          AND OLD.settlement_journal_entry_id IS NOT DISTINCT FROM NEW.settlement_journal_entry_id
          AND OLD.reversal_journal_entry_id IS NOT DISTINCT FROM NEW.reversal_journal_entry_id
          AND OLD.reversed_at IS NOT DISTINCT FROM NEW.reversed_at
          AND OLD.reversal_reason IS NOT DISTINCT FROM NEW.reversal_reason
          AND OLD.failure_code IS NULL
          AND NEW.failure_code IS NOT NULL
        );

        IF has_evidence
          AND NOT allowed_transition
          AND (
            OLD.status IS DISTINCT FROM NEW.status
            OR OLD.settlement_journal_entry_id IS DISTINCT FROM NEW.settlement_journal_entry_id
            OR OLD.reversal_journal_entry_id IS DISTINCT FROM NEW.reversal_journal_entry_id
            OR OLD.reversed_at IS DISTINCT FROM NEW.reversed_at
            OR OLD.reversal_reason IS DISTINCT FROM NEW.reversal_reason
            OR OLD.failure_code IS DISTINCT FROM NEW.failure_code
            OR OLD.metadata IS DISTINCT FROM NEW.metadata
            OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
          ) THEN
          RAISE EXCEPTION 'Pix payment with ledger or outbox evidence only allows documented lifecycle transitions';
        END IF;

        RETURN NEW;
      END;
      $$;

      DROP TRIGGER IF EXISTS fundings_prevent_evidence_mutation ON fundings;
      CREATE TRIGGER fundings_prevent_evidence_mutation
      BEFORE UPDATE OR DELETE ON fundings
      FOR EACH ROW EXECUTE FUNCTION prevent_funding_evidence_mutation();

      DROP TRIGGER IF EXISTS transfers_prevent_evidence_mutation ON transfers;
      CREATE TRIGGER transfers_prevent_evidence_mutation
      BEFORE UPDATE OR DELETE ON transfers
      FOR EACH ROW EXECUTE FUNCTION prevent_transfer_evidence_mutation();

      DROP TRIGGER IF EXISTS split_payments_prevent_evidence_mutation ON split_payments;
      CREATE TRIGGER split_payments_prevent_evidence_mutation
      BEFORE UPDATE OR DELETE ON split_payments
      FOR EACH ROW EXECUTE FUNCTION prevent_split_payment_evidence_mutation();

      DROP TRIGGER IF EXISTS split_entries_prevent_evidence_mutation ON split_entries;
      CREATE TRIGGER split_entries_prevent_evidence_mutation
      BEFORE UPDATE OR DELETE ON split_entries
      FOR EACH ROW EXECUTE FUNCTION prevent_split_entry_evidence_mutation();

      DROP TRIGGER IF EXISTS payouts_prevent_evidence_mutation ON payouts;
      CREATE TRIGGER payouts_prevent_evidence_mutation
      BEFORE UPDATE OR DELETE ON payouts
      FOR EACH ROW EXECUTE FUNCTION prevent_payout_evidence_mutation();

      DROP TRIGGER IF EXISTS refunds_prevent_evidence_mutation ON refunds;
      CREATE TRIGGER refunds_prevent_evidence_mutation
      BEFORE UPDATE OR DELETE ON refunds
      FOR EACH ROW EXECUTE FUNCTION prevent_refund_evidence_mutation();

      DROP TRIGGER IF EXISTS med_cases_prevent_evidence_mutation ON med_cases;
      CREATE TRIGGER med_cases_prevent_evidence_mutation
      BEFORE UPDATE OR DELETE ON med_cases
      FOR EACH ROW EXECUTE FUNCTION prevent_med_case_evidence_mutation();

      DROP TRIGGER IF EXISTS pix_payments_prevent_evidence_mutation ON pix_payments;
      CREATE TRIGGER pix_payments_prevent_evidence_mutation
      BEFORE UPDATE OR DELETE ON pix_payments
      FOR EACH ROW EXECUTE FUNCTION prevent_pix_payment_evidence_mutation();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS pix_payments_prevent_evidence_mutation ON pix_payments;
      DROP TRIGGER IF EXISTS med_cases_prevent_evidence_mutation ON med_cases;
      DROP TRIGGER IF EXISTS refunds_prevent_evidence_mutation ON refunds;
      DROP TRIGGER IF EXISTS payouts_prevent_evidence_mutation ON payouts;
      DROP TRIGGER IF EXISTS split_entries_prevent_evidence_mutation ON split_entries;
      DROP TRIGGER IF EXISTS split_payments_prevent_evidence_mutation ON split_payments;
      DROP TRIGGER IF EXISTS transfers_prevent_evidence_mutation ON transfers;
      DROP TRIGGER IF EXISTS fundings_prevent_evidence_mutation ON fundings;
      DROP FUNCTION IF EXISTS prevent_pix_payment_evidence_mutation();
      DROP FUNCTION IF EXISTS prevent_med_case_evidence_mutation();
      DROP FUNCTION IF EXISTS prevent_refund_evidence_mutation();
      DROP FUNCTION IF EXISTS prevent_payout_evidence_mutation();
      DROP FUNCTION IF EXISTS prevent_split_entry_evidence_mutation();
      DROP FUNCTION IF EXISTS prevent_split_payment_evidence_mutation();
      DROP FUNCTION IF EXISTS prevent_transfer_evidence_mutation();
      DROP FUNCTION IF EXISTS prevent_funding_evidence_mutation();
      DROP FUNCTION IF EXISTS financial_aggregate_has_outbox_evidence(text, bigint);
    SQL
  end
end
