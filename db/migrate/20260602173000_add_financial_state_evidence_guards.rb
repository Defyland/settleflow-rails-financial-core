class AddFinancialStateEvidenceGuards < ActiveRecord::Migration[8.1]
  def up
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

      CREATE OR REPLACE FUNCTION assert_refund_state_evidence()
      RETURNS trigger AS $$
      DECLARE
        refund_row refunds%ROWTYPE;
      BEGIN
        SELECT * INTO refund_row FROM refunds WHERE id = NEW.id;

        IF refund_row.status = 'settled'
          AND (refund_row.journal_entry_id IS NULL OR refund_row.settled_at IS NULL) THEN
          RAISE EXCEPTION 'settled refund requires journal evidence';
        END IF;

        IF refund_row.status = 'failed' AND refund_row.failure_code IS NULL THEN
          RAISE EXCEPTION 'failed refund requires a failure code';
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

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

      CREATE OR REPLACE FUNCTION assert_pix_payment_state_evidence()
      RETURNS trigger AS $$
      DECLARE
        pix_payment_row pix_payments%ROWTYPE;
      BEGIN
        SELECT * INTO pix_payment_row FROM pix_payments WHERE id = NEW.id;

        IF pix_payment_row.status IN ('created', 'pending_review')
          AND (
            pix_payment_row.journal_entry_id IS NOT NULL
            OR pix_payment_row.settlement_journal_entry_id IS NOT NULL
            OR pix_payment_row.reversal_journal_entry_id IS NOT NULL
            OR pix_payment_row.reversed_at IS NOT NULL
            OR pix_payment_row.reversal_reason IS NOT NULL
          ) THEN
          RAISE EXCEPTION 'unposted Pix payment cannot have journal evidence';
        END IF;

        IF pix_payment_row.status = 'rejected'
          AND (
            pix_payment_row.failure_code IS NULL
            OR pix_payment_row.journal_entry_id IS NOT NULL
            OR pix_payment_row.settlement_journal_entry_id IS NOT NULL
            OR pix_payment_row.reversal_journal_entry_id IS NOT NULL
          ) THEN
          RAISE EXCEPTION 'rejected Pix payment requires failure evidence only';
        END IF;

        IF pix_payment_row.status = 'approved'
          AND (
            pix_payment_row.journal_entry_id IS NULL
            OR pix_payment_row.settlement_journal_entry_id IS NOT NULL
            OR pix_payment_row.reversal_journal_entry_id IS NOT NULL
          ) THEN
          RAISE EXCEPTION 'approved Pix payment requires approval journal evidence only';
        END IF;

        IF pix_payment_row.status = 'settled'
          AND (
            pix_payment_row.journal_entry_id IS NULL
            OR pix_payment_row.settlement_journal_entry_id IS NULL
            OR pix_payment_row.reversal_journal_entry_id IS NOT NULL
          ) THEN
          RAISE EXCEPTION 'settled Pix payment requires approval and settlement journal evidence';
        END IF;

        IF pix_payment_row.status = 'reversed'
          AND (
            pix_payment_row.journal_entry_id IS NULL
            OR pix_payment_row.settlement_journal_entry_id IS NULL
            OR pix_payment_row.reversal_journal_entry_id IS NULL
            OR pix_payment_row.reversed_at IS NULL
            OR pix_payment_row.reversal_reason IS NULL
          ) THEN
          RAISE EXCEPTION 'reversed Pix payment requires reversal evidence';
        END IF;

        IF pix_payment_row.status = 'failed' AND pix_payment_row.failure_code IS NULL THEN
          RAISE EXCEPTION 'failed Pix payment requires a failure code';
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1 FROM payouts
          WHERE (status = 'scheduled' AND (journal_entry_id IS NULL OR settlement_journal_entry_id IS NOT NULL OR settled_at IS NOT NULL))
             OR (status = 'settled' AND (journal_entry_id IS NULL OR settlement_journal_entry_id IS NULL OR settled_at IS NULL))
             OR (status = 'failed' AND failure_code IS NULL)
        ) THEN
          RAISE EXCEPTION 'existing payouts violate state evidence guards';
        END IF;

        IF EXISTS (
          SELECT 1 FROM refunds
          WHERE (status = 'settled' AND (journal_entry_id IS NULL OR settled_at IS NULL))
             OR (status = 'failed' AND failure_code IS NULL)
        ) THEN
          RAISE EXCEPTION 'existing refunds violate state evidence guards';
        END IF;

        IF EXISTS (
          SELECT 1 FROM med_cases
          WHERE (status = 'opened' AND (refund_id IS NOT NULL OR resolved_at IS NOT NULL))
             OR (status = 'rejected' AND (refund_id IS NOT NULL OR resolved_at IS NULL))
             OR (status = 'refunded' AND (refund_id IS NULL OR resolved_at IS NULL))
        ) THEN
          RAISE EXCEPTION 'existing MED cases violate state evidence guards';
        END IF;

        IF EXISTS (
          SELECT 1 FROM pix_payments
          WHERE (status IN ('created', 'pending_review') AND (journal_entry_id IS NOT NULL OR settlement_journal_entry_id IS NOT NULL OR reversal_journal_entry_id IS NOT NULL OR reversed_at IS NOT NULL OR reversal_reason IS NOT NULL))
             OR (status = 'rejected' AND (failure_code IS NULL OR journal_entry_id IS NOT NULL OR settlement_journal_entry_id IS NOT NULL OR reversal_journal_entry_id IS NOT NULL))
             OR (status = 'approved' AND (journal_entry_id IS NULL OR settlement_journal_entry_id IS NOT NULL OR reversal_journal_entry_id IS NOT NULL))
             OR (status = 'settled' AND (journal_entry_id IS NULL OR settlement_journal_entry_id IS NULL OR reversal_journal_entry_id IS NOT NULL))
             OR (status = 'reversed' AND (journal_entry_id IS NULL OR settlement_journal_entry_id IS NULL OR reversal_journal_entry_id IS NULL OR reversed_at IS NULL OR reversal_reason IS NULL))
             OR (status = 'failed' AND failure_code IS NULL)
        ) THEN
          RAISE EXCEPTION 'existing Pix payments violate state evidence guards';
        END IF;
      END;
      $$;

      DROP TRIGGER IF EXISTS payouts_state_evidence_after_write ON payouts;
      CREATE CONSTRAINT TRIGGER payouts_state_evidence_after_write
      AFTER INSERT OR UPDATE ON payouts
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_payout_state_evidence();

      DROP TRIGGER IF EXISTS refunds_state_evidence_after_write ON refunds;
      CREATE CONSTRAINT TRIGGER refunds_state_evidence_after_write
      AFTER INSERT OR UPDATE ON refunds
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_refund_state_evidence();

      DROP TRIGGER IF EXISTS med_cases_state_evidence_after_write ON med_cases;
      CREATE CONSTRAINT TRIGGER med_cases_state_evidence_after_write
      AFTER INSERT OR UPDATE ON med_cases
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_med_case_state_evidence();

      DROP TRIGGER IF EXISTS pix_payments_state_evidence_after_write ON pix_payments;
      CREATE CONSTRAINT TRIGGER pix_payments_state_evidence_after_write
      AFTER INSERT OR UPDATE ON pix_payments
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_pix_payment_state_evidence();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS pix_payments_state_evidence_after_write ON pix_payments;
      DROP TRIGGER IF EXISTS med_cases_state_evidence_after_write ON med_cases;
      DROP TRIGGER IF EXISTS refunds_state_evidence_after_write ON refunds;
      DROP TRIGGER IF EXISTS payouts_state_evidence_after_write ON payouts;
      DROP FUNCTION IF EXISTS assert_pix_payment_state_evidence();
      DROP FUNCTION IF EXISTS assert_med_case_state_evidence();
      DROP FUNCTION IF EXISTS assert_refund_state_evidence();
      DROP FUNCTION IF EXISTS assert_payout_state_evidence();
    SQL
  end
end
