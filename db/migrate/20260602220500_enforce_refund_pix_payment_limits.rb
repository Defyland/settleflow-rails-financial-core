class EnforceRefundPixPaymentLimits < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION refund_pix_payment_evidence_valid(pix_payment_id_to_check bigint)
      RETURNS boolean
      LANGUAGE sql
      STABLE
      AS $$
        SELECT EXISTS (
          SELECT 1
          FROM pix_payments pix_payment
          WHERE pix_payment.id = pix_payment_id_to_check
            AND COALESCE((
              SELECT SUM(refund.amount_cents)
              FROM refunds refund
              WHERE refund.pix_payment_id = pix_payment.id
                AND refund.status = 'settled'
            ), 0) <= pix_payment.amount_cents
            AND NOT EXISTS (
              SELECT 1
              FROM refunds refund
              WHERE refund.pix_payment_id = pix_payment.id
                AND refund.status = 'settled'
                AND (
                  refund.organization_id <> pix_payment.organization_id
                  OR refund.wallet_id <> pix_payment.wallet_id
                  OR refund.currency <> pix_payment.currency
                  OR pix_payment.status <> 'settled'
                  OR pix_payment.reversal_journal_entry_id IS NOT NULL
                )
            )
        );
      $$;

      CREATE OR REPLACE FUNCTION lock_refund_pix_payment_evidence()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_OP = 'INSERT' OR OLD.pix_payment_id IS NOT DISTINCT FROM NEW.pix_payment_id THEN
          PERFORM 1
          FROM pix_payments
          WHERE id = NEW.pix_payment_id
          FOR UPDATE;
          RETURN NEW;
        END IF;

        PERFORM 1
        FROM pix_payments
        WHERE id IN (OLD.pix_payment_id, NEW.pix_payment_id)
        ORDER BY id
        FOR UPDATE;

        RETURN NEW;
      END;
      $$;

      CREATE OR REPLACE FUNCTION assert_refund_pix_payment_evidence()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NOT refund_pix_payment_evidence_valid(NEW.pix_payment_id) THEN
          RAISE EXCEPTION 'settled refunds exceed or mismatch Pix payment evidence';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE OR REPLACE FUNCTION assert_pix_payment_refund_evidence()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NOT refund_pix_payment_evidence_valid(NEW.id) THEN
          RAISE EXCEPTION 'Pix payment state conflicts with settled refund evidence';
        END IF;

        RETURN NEW;
      END;
      $$;

      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM pix_payments
          WHERE NOT refund_pix_payment_evidence_valid(id)
        ) THEN
          RAISE EXCEPTION 'existing refunds violate Pix payment refund limits';
        END IF;
      END
      $$;

      DROP TRIGGER IF EXISTS refunds_lock_pix_payment_before_write ON refunds;
      CREATE TRIGGER refunds_lock_pix_payment_before_write
      BEFORE INSERT OR UPDATE OF pix_payment_id, status, amount_cents, organization_id, wallet_id, currency ON refunds
      FOR EACH ROW EXECUTE FUNCTION lock_refund_pix_payment_evidence();

      DROP TRIGGER IF EXISTS refunds_pix_payment_evidence_after_write ON refunds;
      CREATE CONSTRAINT TRIGGER refunds_pix_payment_evidence_after_write
      AFTER INSERT OR UPDATE OF pix_payment_id, status, amount_cents, organization_id, wallet_id, currency ON refunds
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_refund_pix_payment_evidence();

      DROP TRIGGER IF EXISTS pix_payments_refund_evidence_after_write ON pix_payments;
      CREATE CONSTRAINT TRIGGER pix_payments_refund_evidence_after_write
      AFTER UPDATE OF status, amount_cents, organization_id, wallet_id, currency, reversal_journal_entry_id ON pix_payments
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_pix_payment_refund_evidence();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS pix_payments_refund_evidence_after_write ON pix_payments;
      DROP TRIGGER IF EXISTS refunds_pix_payment_evidence_after_write ON refunds;
      DROP TRIGGER IF EXISTS refunds_lock_pix_payment_before_write ON refunds;
      DROP FUNCTION IF EXISTS assert_pix_payment_refund_evidence();
      DROP FUNCTION IF EXISTS assert_refund_pix_payment_evidence();
      DROP FUNCTION IF EXISTS lock_refund_pix_payment_evidence();
      DROP FUNCTION IF EXISTS refund_pix_payment_evidence_valid(bigint);
    SQL
  end
end
