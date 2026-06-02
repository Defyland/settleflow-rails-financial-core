class EnforceMedOutboxResolutionPayloadEvidence < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION med_outbox_event_has_resolution_payload_evidence(event_row outbox_events)
      RETURNS boolean
      LANGUAGE plpgsql
      STABLE
      AS $$
      DECLARE
        has_evidence boolean;
      BEGIN
        IF event_row.aggregate_type <> 'MedCase'
          OR event_row.event_type NOT IN ('med.case.rejected', 'med.case.refunded') THEN
          RETURN true;
        END IF;

        IF event_row.event_type = 'med.case.rejected' THEN
          SELECT EXISTS (
            SELECT 1
            FROM med_cases med_case
            JOIN pix_payments pix_payment
              ON pix_payment.id = med_case.pix_payment_id
            JOIN operator_approvals approval
              ON approval.id = med_case.operator_approval_id
            WHERE med_case.id = event_row.aggregate_id
              AND med_case.organization_id = event_row.organization_id
              AND med_case.status = 'rejected'
              AND med_case.refund_id IS NULL
              AND med_case_has_resolution_approval(med_case.id)
              AND event_row.payload ? 'resolved_at'
              AND event_row.payload @> jsonb_build_object(
                'med_case_id', med_case.public_id::text,
                'pix_payment_id', pix_payment.public_id::text,
                'operator_approval_id', approval.public_id::text,
                'amount_cents', med_case.amount_cents,
                'currency', med_case.currency,
                'status', med_case.status
              )
          ) INTO has_evidence;
          RETURN has_evidence;
        END IF;

        SELECT EXISTS (
          SELECT 1
          FROM med_cases med_case
          JOIN pix_payments pix_payment
            ON pix_payment.id = med_case.pix_payment_id
          JOIN refunds refund
            ON refund.id = med_case.refund_id
          JOIN operator_approvals approval
            ON approval.id = med_case.operator_approval_id
          WHERE med_case.id = event_row.aggregate_id
            AND med_case.organization_id = event_row.organization_id
            AND med_case.status = 'refunded'
            AND med_case_has_resolution_approval(med_case.id)
            AND med_case_has_refund_evidence(med_case.id)
            AND event_row.payload ? 'resolved_at'
            AND event_row.payload @> jsonb_build_object(
              'med_case_id', med_case.public_id::text,
              'pix_payment_id', pix_payment.public_id::text,
              'refund_id', refund.public_id::text,
              'operator_approval_id', approval.public_id::text,
              'amount_cents', med_case.amount_cents,
              'currency', med_case.currency,
              'status', med_case.status
            )
        ) INTO has_evidence;
        RETURN has_evidence;
      END;
      $$;

      CREATE OR REPLACE FUNCTION assert_med_outbox_resolution_payload_evidence()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NOT med_outbox_event_has_resolution_payload_evidence(NEW) THEN
          RAISE EXCEPTION 'MED resolution outbox payload evidence is invalid';
        END IF;

        RETURN NEW;
      END;
      $$;

      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM outbox_events
          WHERE NOT med_outbox_event_has_resolution_payload_evidence(outbox_events)
        ) THEN
          RAISE EXCEPTION 'existing MED resolution outbox events violate payload evidence guards';
        END IF;
      END
      $$;

      DROP TRIGGER IF EXISTS outbox_events_med_resolution_payload_before_write ON outbox_events;
      CREATE TRIGGER outbox_events_med_resolution_payload_before_write
      BEFORE INSERT OR UPDATE OF aggregate_type, aggregate_id, event_type, payload ON outbox_events
      FOR EACH ROW EXECUTE FUNCTION assert_med_outbox_resolution_payload_evidence();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS outbox_events_med_resolution_payload_before_write ON outbox_events;
      DROP FUNCTION IF EXISTS assert_med_outbox_resolution_payload_evidence();
      DROP FUNCTION IF EXISTS med_outbox_event_has_resolution_payload_evidence(outbox_events);
    SQL
  end
end
