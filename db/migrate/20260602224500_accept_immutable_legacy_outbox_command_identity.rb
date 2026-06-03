class AcceptImmutableLegacyOutboxCommandIdentity < ActiveRecord::Migration[8.1]
  def up
    create_table :outbox_legacy_command_identity_exceptions do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true, index: { name: "idx_legacy_outbox_exceptions_org" }
      t.references :outbox_event, null: false, foreign_key: true, index: { unique: true, name: "idx_legacy_outbox_exceptions_event" }
      t.string :aggregate_type, null: false
      t.bigint :aggregate_id, null: false
      t.string :event_type, null: false
      t.string :payload_sha256, null: false
      t.string :expected_idempotency_key, null: false
      t.string :reason, null: false
      t.datetime :accepted_at, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :outbox_legacy_command_identity_exceptions, :public_id, unique: true, name: "idx_legacy_outbox_exceptions_public_id"
    add_index :outbox_legacy_command_identity_exceptions,
      [ :aggregate_type, :aggregate_id, :event_type ],
      name: "idx_legacy_outbox_exceptions_aggregate"
    add_check_constraint :outbox_legacy_command_identity_exceptions,
      "payload_sha256 ~ '^[0-9a-f]{64}$'",
      name: "legacy_outbox_exceptions_payload_sha256_hex_check"
    add_check_constraint :outbox_legacy_command_identity_exceptions,
      "btrim(expected_idempotency_key) <> ''",
      name: "legacy_outbox_exceptions_expected_key_present_check"
    add_check_constraint :outbox_legacy_command_identity_exceptions,
      "btrim(reason) <> ''",
      name: "legacy_outbox_exceptions_reason_present_check"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION outbox_event_expected_command_identity(event_row outbox_events)
      RETURNS text
      LANGUAGE plpgsql
      STABLE
      AS $$
      DECLARE
        expected_key text;
      BEGIN
        IF event_row.aggregate_type = 'Funding' THEN
          SELECT funding.idempotency_key
            INTO expected_key
            FROM fundings funding
           WHERE funding.id = event_row.aggregate_id
             AND funding.organization_id = event_row.organization_id
             AND event_row.event_type = 'wallet.funded';
          RETURN expected_key;
        END IF;

        IF event_row.aggregate_type = 'Transfer' THEN
          SELECT transfer.idempotency_key
            INTO expected_key
            FROM transfers transfer
           WHERE transfer.id = event_row.aggregate_id
             AND transfer.organization_id = event_row.organization_id
             AND event_row.event_type = 'wallet.transfer.posted';
          RETURN expected_key;
        END IF;

        IF event_row.aggregate_type = 'SplitPayment' THEN
          SELECT split_payment.idempotency_key
            INTO expected_key
            FROM split_payments split_payment
           WHERE split_payment.id = event_row.aggregate_id
             AND split_payment.organization_id = event_row.organization_id
             AND event_row.event_type = 'split.posted';
          RETURN expected_key;
        END IF;

        IF event_row.aggregate_type = 'PixPayment' THEN
          SELECT CASE
                   WHEN event_row.event_type IN ('pix.payment.approved', 'pix.payment.pending_review', 'pix.payment.rejected')
                     THEN pix_payment.idempotency_key
                   WHEN event_row.event_type = 'pix.payment.settled'
                     THEN 'pix_payment.settle:' || pix_payment.id::text
                   WHEN event_row.event_type = 'pix.payment.reversed'
                     THEN 'pix_payment.reverse:' || pix_payment.id::text
                 END
            INTO expected_key
            FROM pix_payments pix_payment
           WHERE pix_payment.id = event_row.aggregate_id
             AND pix_payment.organization_id = event_row.organization_id;
          RETURN expected_key;
        END IF;

        IF event_row.aggregate_type = 'Payout' THEN
          SELECT CASE
                   WHEN event_row.event_type = 'payout.scheduled'
                     THEN payout.idempotency_key
                   WHEN event_row.event_type = 'payout.settled'
                     THEN 'payout.settle:' || payout.id::text
                 END
            INTO expected_key
            FROM payouts payout
           WHERE payout.id = event_row.aggregate_id
             AND payout.organization_id = event_row.organization_id;
          RETURN expected_key;
        END IF;

        IF event_row.aggregate_type = 'Refund' THEN
          SELECT refund.idempotency_key
            INTO expected_key
            FROM refunds refund
           WHERE refund.id = event_row.aggregate_id
             AND refund.organization_id = event_row.organization_id
             AND event_row.event_type = 'refund.settled';
          RETURN expected_key;
        END IF;

        IF event_row.aggregate_type = 'MedCase' THEN
          SELECT CASE
                   WHEN event_row.event_type = 'med.case.opened'
                     THEN med_case.idempotency_key
                   WHEN event_row.event_type = 'med.case.rejected'
                     THEN 'med_case.reject:' || med_case.id::text
                   WHEN event_row.event_type = 'med.case.refunded'
                     THEN 'med_case.accept:' || med_case.id::text
                 END
            INTO expected_key
            FROM med_cases med_case
           WHERE med_case.id = event_row.aggregate_id
             AND med_case.organization_id = event_row.organization_id;
          RETURN expected_key;
        END IF;

        RETURN NULL;
      END;
      $$;

      CREATE OR REPLACE FUNCTION outbox_legacy_command_identity_exception_valid(exception_row outbox_legacy_command_identity_exceptions)
      RETURNS boolean
      LANGUAGE plpgsql
      STABLE
      AS $$
      DECLARE
        event_row outbox_events%ROWTYPE;
        expected_key text;
      BEGIN
        SELECT *
          INTO event_row
          FROM outbox_events
         WHERE id = exception_row.outbox_event_id;

        IF event_row.id IS NULL THEN
          RETURN false;
        END IF;

        expected_key := outbox_event_expected_command_identity(event_row);

        RETURN event_row.organization_id = exception_row.organization_id
          AND event_row.aggregate_type = exception_row.aggregate_type
          AND event_row.aggregate_id = exception_row.aggregate_id
          AND event_row.event_type = exception_row.event_type
          AND event_row.status = 'published'
          AND event_row.published_at IS NOT NULL
          AND event_row.payload_sha256 IS NOT NULL
          AND event_row.payload_sha256 = exception_row.payload_sha256
          AND event_row.idempotency_key IS NULL
          AND expected_key IS NOT NULL
          AND expected_key = exception_row.expected_idempotency_key
          AND btrim(exception_row.reason) <> ''
          AND outbox_event_has_aggregate_evidence(event_row)
          AND NOT outbox_event_has_command_identity_evidence(event_row);
      END;
      $$;

      CREATE OR REPLACE FUNCTION prevent_outbox_legacy_command_identity_exception_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'legacy outbox command identity exceptions are append-only evidence';
        END IF;

        IF TG_OP = 'UPDATE' THEN
          RAISE EXCEPTION 'legacy outbox command identity exceptions are immutable evidence';
        END IF;

        IF NOT outbox_legacy_command_identity_exception_valid(NEW) THEN
          RAISE EXCEPTION 'legacy outbox command identity exception evidence is invalid';
        END IF;

        RETURN NEW;
      END;
      $$;

      DROP TRIGGER IF EXISTS outbox_legacy_command_identity_exceptions_prevent_mutation
        ON outbox_legacy_command_identity_exceptions;
      CREATE TRIGGER outbox_legacy_command_identity_exceptions_prevent_mutation
      BEFORE INSERT OR UPDATE OR DELETE ON outbox_legacy_command_identity_exceptions
      FOR EACH ROW EXECUTE FUNCTION prevent_outbox_legacy_command_identity_exception_mutation();

      INSERT INTO outbox_legacy_command_identity_exceptions (
        organization_id,
        outbox_event_id,
        aggregate_type,
        aggregate_id,
        event_type,
        payload_sha256,
        expected_idempotency_key,
        reason,
        accepted_at,
        metadata,
        created_at,
        updated_at
      )
      SELECT event.organization_id,
             event.id,
             event.aggregate_type,
             event.aggregate_id,
             event.event_type,
             event.payload_sha256,
             outbox_event_expected_command_identity(event),
             'published_immutable_envelope_predates_command_identity_guard',
             CURRENT_TIMESTAMP,
             jsonb_build_object(
               'source_migration', '20260602224500_accept_immutable_legacy_outbox_command_identity',
               'original_idempotency_key', event.idempotency_key,
               'acceptance_policy', 'preserve_published_payload_hash'
             ),
             CURRENT_TIMESTAMP,
             CURRENT_TIMESTAMP
        FROM outbox_events event
       WHERE event.aggregate_type IN ('Funding', 'Transfer', 'SplitPayment', 'PixPayment', 'Payout', 'Refund', 'MedCase')
         AND event.payload_sha256 IS NOT NULL
         AND event.idempotency_key IS NULL
         AND NOT outbox_event_has_command_identity_evidence(event)
         AND outbox_event_expected_command_identity(event) IS NOT NULL
      ON CONFLICT (outbox_event_id) DO NOTHING;
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS outbox_legacy_command_identity_exceptions_prevent_mutation
        ON outbox_legacy_command_identity_exceptions;
      DROP FUNCTION IF EXISTS prevent_outbox_legacy_command_identity_exception_mutation();
      DROP FUNCTION IF EXISTS outbox_legacy_command_identity_exception_valid(outbox_legacy_command_identity_exceptions);
      DROP FUNCTION IF EXISTS outbox_event_expected_command_identity(outbox_events);
    SQL

    drop_table :outbox_legacy_command_identity_exceptions
  end
end
