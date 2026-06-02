class EnforceOutboxCommandIdentityEvidence < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DROP TRIGGER IF EXISTS outbox_events_prevent_evidence_mutation ON outbox_events;

      UPDATE outbox_events event
         SET idempotency_key = 'pix_payment.settle:' || pix_payment.id::text
        FROM pix_payments pix_payment
       WHERE event.aggregate_type = 'PixPayment'
         AND event.aggregate_id = pix_payment.id
         AND event.event_type = 'pix.payment.settled'
         AND event.idempotency_key IS NULL
         AND event.payload_sha256 IS NULL
         AND event.status <> 'published';

      UPDATE outbox_events event
         SET idempotency_key = 'pix_payment.reverse:' || pix_payment.id::text
        FROM pix_payments pix_payment
       WHERE event.aggregate_type = 'PixPayment'
         AND event.aggregate_id = pix_payment.id
         AND event.event_type = 'pix.payment.reversed'
         AND event.idempotency_key IS NULL
         AND event.payload_sha256 IS NULL
         AND event.status <> 'published';

      UPDATE outbox_events event
         SET idempotency_key = 'pix_payment.reject:' || pix_payment.id::text
        FROM pix_payments pix_payment
       WHERE event.aggregate_type = 'PixPayment'
         AND event.aggregate_id = pix_payment.id
         AND event.event_type = 'pix.payment.rejected'
         AND event.idempotency_key IS NULL
         AND event.payload_sha256 IS NULL
         AND event.status <> 'published';

      UPDATE outbox_events event
         SET idempotency_key = 'payout.settle:' || payout.id::text
        FROM payouts payout
       WHERE event.aggregate_type = 'Payout'
         AND event.aggregate_id = payout.id
         AND event.event_type = 'payout.settled'
         AND event.idempotency_key IS NULL
         AND event.payload_sha256 IS NULL
         AND event.status <> 'published';

      UPDATE outbox_events event
         SET idempotency_key = 'med_case.reject:' || med_case.id::text
        FROM med_cases med_case
       WHERE event.aggregate_type = 'MedCase'
         AND event.aggregate_id = med_case.id
         AND event.event_type = 'med.case.rejected'
         AND event.idempotency_key IS NULL
         AND event.payload_sha256 IS NULL
         AND event.status <> 'published';

      UPDATE outbox_events event
         SET idempotency_key = 'med_case.accept:' || med_case.id::text
        FROM med_cases med_case
       WHERE event.aggregate_type = 'MedCase'
         AND event.aggregate_id = med_case.id
         AND event.event_type = 'med.case.refunded'
         AND event.idempotency_key IS NULL
         AND event.payload_sha256 IS NULL
         AND event.status <> 'published';

      CREATE TRIGGER outbox_events_prevent_evidence_mutation
      BEFORE INSERT OR UPDATE OR DELETE ON outbox_events
      FOR EACH ROW EXECUTE FUNCTION prevent_outbox_event_evidence_mutation();

      CREATE OR REPLACE FUNCTION outbox_event_has_command_identity_evidence(event_row outbox_events)
      RETURNS boolean
      LANGUAGE plpgsql
      STABLE
      AS $$
      DECLARE
        has_evidence boolean;
      BEGIN
        IF event_row.aggregate_type = 'Funding' THEN
          SELECT EXISTS (
            SELECT 1
            FROM fundings funding
            WHERE funding.id = event_row.aggregate_id
              AND funding.organization_id = event_row.organization_id
              AND event_row.event_type = 'wallet.funded'
              AND funding.journal_entry_id IS NOT NULL
              AND event_row.idempotency_key = funding.idempotency_key
          ) INTO has_evidence;
          RETURN has_evidence;
        END IF;

        IF event_row.aggregate_type = 'Transfer' THEN
          SELECT EXISTS (
            SELECT 1
            FROM transfers transfer
            WHERE transfer.id = event_row.aggregate_id
              AND transfer.organization_id = event_row.organization_id
              AND event_row.event_type = 'wallet.transfer.posted'
              AND transfer.journal_entry_id IS NOT NULL
              AND event_row.idempotency_key = transfer.idempotency_key
          ) INTO has_evidence;
          RETURN has_evidence;
        END IF;

        IF event_row.aggregate_type = 'SplitPayment' THEN
          SELECT EXISTS (
            SELECT 1
            FROM split_payments split_payment
            WHERE split_payment.id = event_row.aggregate_id
              AND split_payment.organization_id = event_row.organization_id
              AND event_row.event_type = 'split.posted'
              AND split_payment.journal_entry_id IS NOT NULL
              AND event_row.idempotency_key = split_payment.idempotency_key
          ) INTO has_evidence;
          RETURN has_evidence;
        END IF;

        IF event_row.aggregate_type = 'PixPayment' THEN
          SELECT EXISTS (
            SELECT 1
            FROM pix_payments pix_payment
            WHERE pix_payment.id = event_row.aggregate_id
              AND pix_payment.organization_id = event_row.organization_id
              AND (
                (
                  event_row.event_type IN ('pix.payment.approved', 'pix.payment.pending_review')
                  AND event_row.idempotency_key = pix_payment.idempotency_key
                )
                OR (
                  event_row.event_type = 'pix.payment.rejected'
                  AND event_row.idempotency_key IN (
                    pix_payment.idempotency_key,
                    'pix_payment.reject:' || pix_payment.id::text
                  )
                )
                OR (
                  event_row.event_type = 'pix.payment.settled'
                  AND pix_payment.settlement_journal_entry_id IS NOT NULL
                  AND event_row.idempotency_key = 'pix_payment.settle:' || pix_payment.id::text
                )
                OR (
                  event_row.event_type = 'pix.payment.reversed'
                  AND pix_payment.reversal_journal_entry_id IS NOT NULL
                  AND event_row.idempotency_key = 'pix_payment.reverse:' || pix_payment.id::text
                )
              )
          ) INTO has_evidence;
          RETURN has_evidence;
        END IF;

        IF event_row.aggregate_type = 'Payout' THEN
          SELECT EXISTS (
            SELECT 1
            FROM payouts payout
            WHERE payout.id = event_row.aggregate_id
              AND payout.organization_id = event_row.organization_id
              AND (
                (
                  event_row.event_type = 'payout.scheduled'
                  AND payout.journal_entry_id IS NOT NULL
                  AND event_row.idempotency_key = payout.idempotency_key
                )
                OR (
                  event_row.event_type = 'payout.settled'
                  AND payout.settlement_journal_entry_id IS NOT NULL
                  AND payout.settled_at IS NOT NULL
                  AND event_row.idempotency_key = 'payout.settle:' || payout.id::text
                )
              )
          ) INTO has_evidence;
          RETURN has_evidence;
        END IF;

        IF event_row.aggregate_type = 'Refund' THEN
          SELECT EXISTS (
            SELECT 1
            FROM refunds refund
            WHERE refund.id = event_row.aggregate_id
              AND refund.organization_id = event_row.organization_id
              AND event_row.event_type = 'refund.settled'
              AND refund.journal_entry_id IS NOT NULL
              AND event_row.idempotency_key = refund.idempotency_key
          ) INTO has_evidence;
          RETURN has_evidence;
        END IF;

        IF event_row.aggregate_type = 'MedCase' THEN
          SELECT EXISTS (
            SELECT 1
            FROM med_cases med_case
            WHERE med_case.id = event_row.aggregate_id
              AND med_case.organization_id = event_row.organization_id
              AND (
                (
                  event_row.event_type = 'med.case.opened'
                  AND event_row.idempotency_key = med_case.idempotency_key
                )
                OR (
                  event_row.event_type = 'med.case.rejected'
                  AND med_case.status = 'rejected'
                  AND med_case_has_resolution_approval(med_case.id)
                  AND event_row.idempotency_key = 'med_case.reject:' || med_case.id::text
                )
                OR (
                  event_row.event_type = 'med.case.refunded'
                  AND med_case.status = 'refunded'
                  AND med_case_has_resolution_approval(med_case.id)
                  AND med_case_has_refund_evidence(med_case.id)
                  AND event_row.idempotency_key = 'med_case.accept:' || med_case.id::text
                )
              )
          ) INTO has_evidence;
          RETURN has_evidence;
        END IF;

        RETURN true;
      END;
      $$;

      CREATE OR REPLACE FUNCTION assert_outbox_event_command_identity_evidence()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NOT outbox_event_has_command_identity_evidence(NEW) THEN
          RAISE EXCEPTION 'outbox event command identity evidence is invalid';
        END IF;

        RETURN NEW;
      END;
      $$;

      DROP TRIGGER IF EXISTS outbox_events_command_identity_before_write ON outbox_events;
      CREATE TRIGGER outbox_events_command_identity_before_write
      BEFORE INSERT OR UPDATE OF organization_id, aggregate_type, aggregate_id, event_type, idempotency_key ON outbox_events
      FOR EACH ROW EXECUTE FUNCTION assert_outbox_event_command_identity_evidence();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS outbox_events_command_identity_before_write ON outbox_events;
      DROP FUNCTION IF EXISTS assert_outbox_event_command_identity_evidence();
      DROP FUNCTION IF EXISTS outbox_event_has_command_identity_evidence(outbox_events);
    SQL
  end
end
