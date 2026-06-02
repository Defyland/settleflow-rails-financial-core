class AddProcessedEventEvidenceGuards < ActiveRecord::Migration[8.1]
  def up
    allow_legacy_outbox_hash_backfill!
    backfill_legacy_published_outbox_hashes

    execute <<~SQL
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM outbox_events
          WHERE status NOT IN ('pending', 'publishing', 'published', 'dead_lettered')
             OR (
               status = 'pending'
               AND (published_at IS NOT NULL OR dead_lettered_at IS NOT NULL OR payload_sha256 IS NOT NULL)
             )
             OR (
               status = 'publishing'
               AND (last_attempted_at IS NULL OR published_at IS NOT NULL OR dead_lettered_at IS NOT NULL OR payload_sha256 IS NOT NULL)
             )
             OR (
               status = 'published'
               AND (published_at IS NULL OR payload_sha256 IS NULL OR dead_lettered_at IS NOT NULL)
             )
             OR (
               status = 'dead_lettered'
               AND (
                 published_at IS NOT NULL
                 OR payload_sha256 IS NOT NULL
                 OR dead_lettered_at IS NULL
                 OR error_class IS NULL
                 OR btrim(error_class) = ''
                 OR last_error IS NULL
                 OR btrim(last_error) = ''
               )
             )
        ) THEN
          RAISE EXCEPTION 'existing outbox_events violate delivery state guards';
        END IF;

        IF EXISTS (
          SELECT 1
          FROM processed_events pe
          LEFT JOIN outbox_events oe ON oe.id = pe.outbox_event_id
          WHERE pe.status NOT IN ('processing', 'processed', 'failed')
             OR pe.payload_sha256 !~ '^[0-9a-f]{64}$'
             OR (pe.status = 'processing' AND (pe.processed_at IS NOT NULL OR pe.error_class IS NOT NULL OR pe.last_error IS NOT NULL))
             OR (pe.status = 'processed' AND (pe.processed_at IS NULL OR pe.error_class IS NOT NULL OR pe.last_error IS NOT NULL))
             OR (pe.status = 'failed' AND (
               pe.processed_at IS NOT NULL
               OR pe.error_class IS NULL
               OR btrim(pe.error_class) = ''
               OR pe.last_error IS NULL
               OR btrim(pe.last_error) = ''
             ))
             OR oe.id IS NULL
             OR oe.status <> 'published'
             OR oe.published_at IS NULL
             OR oe.payload_sha256 IS NULL
             OR oe.organization_id <> pe.organization_id
             OR oe.public_id::text <> pe.event_id
             OR oe.event_type <> pe.event_type
             OR oe.payload_sha256 <> pe.payload_sha256
        ) THEN
          RAISE EXCEPTION 'existing processed_events violate outbox evidence guards';
        END IF;
      END
      $$;
    SQL

    add_check_constraint :outbox_events, "status IN ('pending', 'publishing', 'published', 'dead_lettered')", name: "outbox_events_status_check", validate: false
    add_check_constraint :outbox_events, outbox_event_state_check, name: "outbox_events_delivery_state_check", validate: false
    validate_check_constraint :outbox_events, name: "outbox_events_status_check"
    validate_check_constraint :outbox_events, name: "outbox_events_delivery_state_check"

    add_check_constraint :processed_events, "payload_sha256 ~ '^[0-9a-f]{64}$'", name: "processed_events_payload_sha256_hex_check", validate: false
    add_check_constraint :processed_events, processed_event_state_check, name: "processed_events_state_evidence_check", validate: false
    validate_check_constraint :processed_events, name: "processed_events_payload_sha256_hex_check"
    validate_check_constraint :processed_events, name: "processed_events_state_evidence_check"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION assert_processed_event_outbox_evidence(processed_event_row processed_events)
      RETURNS void
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1
          FROM outbox_events
          WHERE outbox_events.id = processed_event_row.outbox_event_id
            AND outbox_events.organization_id = processed_event_row.organization_id
            AND outbox_events.public_id::text = processed_event_row.event_id
            AND outbox_events.event_type = processed_event_row.event_type
            AND outbox_events.payload_sha256 = processed_event_row.payload_sha256
            AND outbox_events.status = 'published'
            AND outbox_events.published_at IS NOT NULL
            AND outbox_events.payload_sha256 IS NOT NULL
        ) THEN
          RAISE EXCEPTION 'processed event must match a published outbox event';
        END IF;
      END;
      $$;

      CREATE OR REPLACE FUNCTION prevent_processed_event_evidence_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'processed events are downstream processing evidence';
        END IF;

        IF TG_OP = 'INSERT' THEN
          IF NEW.status <> 'processing' THEN
            RAISE EXCEPTION 'processed events must start processing';
          END IF;

          PERFORM assert_processed_event_outbox_evidence(NEW);
          RETURN NEW;
        END IF;

        IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.outbox_event_id IS DISTINCT FROM NEW.outbox_event_id
          OR OLD.processor IS DISTINCT FROM NEW.processor
          OR OLD.event_id IS DISTINCT FROM NEW.event_id
          OR OLD.event_type IS DISTINCT FROM NEW.event_type
          OR OLD.payload_sha256 IS DISTINCT FROM NEW.payload_sha256
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'processed event identity is immutable';
        END IF;

        IF OLD.status = 'processed' THEN
          RAISE EXCEPTION 'processed events are immutable after success';
        END IF;

        IF NEW.status = 'processed' AND OLD.status NOT IN ('processing', 'failed') THEN
          RAISE EXCEPTION 'processed events can only succeed from processing or failed';
        END IF;

        PERFORM assert_processed_event_outbox_evidence(NEW);
        RETURN NEW;
      END;
      $$;

      DROP TRIGGER IF EXISTS processed_events_prevent_evidence_mutation ON processed_events;
      CREATE TRIGGER processed_events_prevent_evidence_mutation
      BEFORE INSERT OR UPDATE OR DELETE ON processed_events
      FOR EACH ROW EXECUTE FUNCTION prevent_processed_event_evidence_mutation();

      CREATE OR REPLACE FUNCTION prevent_outbox_event_evidence_mutation()
      RETURNS trigger AS $$
      BEGIN
        IF TG_OP = 'INSERT' THEN
          IF NEW.status <> 'pending'
            OR NEW.attempts <> 0
            OR NEW.published_at IS NOT NULL
            OR NEW.last_error IS NOT NULL
            OR NEW.next_attempt_at IS NOT NULL
            OR NEW.last_attempted_at IS NOT NULL
            OR NEW.dead_lettered_at IS NOT NULL
            OR NEW.error_class IS NOT NULL
            OR NEW.publisher IS NOT NULL
            OR NEW.published_to IS NOT NULL
            OR NEW.publisher_message_id IS NOT NULL
            OR NEW.payload_sha256 IS NOT NULL THEN
            RAISE EXCEPTION 'outbox events must start as pending unpublished evidence';
          END IF;

          RETURN NEW;
        END IF;

        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'outbox events are append-only evidence';
        END IF;

        IF OLD.status = 'published' THEN
          RAISE EXCEPTION 'published outbox events are immutable delivery evidence';
        END IF;

        IF OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.aggregate_type IS DISTINCT FROM NEW.aggregate_type
          OR OLD.aggregate_id IS DISTINCT FROM NEW.aggregate_id
          OR OLD.event_type IS DISTINCT FROM NEW.event_type
          OR OLD.payload IS DISTINCT FROM NEW.payload
          OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
          OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'outbox event envelope is immutable';
        END IF;

        IF OLD.payload_sha256 IS NOT NULL
          AND OLD.payload_sha256 IS DISTINCT FROM NEW.payload_sha256 THEN
          RAISE EXCEPTION 'outbox event payload hash is immutable after publication';
        END IF;

        IF OLD.payload_sha256 IS NULL
          AND NEW.payload_sha256 IS NOT NULL
          AND NOT (OLD.status = 'publishing' AND NEW.status = 'published') THEN
          RAISE EXCEPTION 'outbox event payload hash can only be set during publication';
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      DROP TRIGGER IF EXISTS outbox_events_prevent_evidence_mutation ON outbox_events;
      CREATE TRIGGER outbox_events_prevent_evidence_mutation
      BEFORE INSERT OR UPDATE OR DELETE ON outbox_events
      FOR EACH ROW EXECUTE FUNCTION prevent_outbox_event_evidence_mutation();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS processed_events_prevent_evidence_mutation ON processed_events;
      DROP FUNCTION IF EXISTS prevent_processed_event_evidence_mutation();
      DROP FUNCTION IF EXISTS assert_processed_event_outbox_evidence(processed_events);

      CREATE OR REPLACE FUNCTION prevent_outbox_event_evidence_mutation()
      RETURNS trigger AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'outbox events are append-only evidence';
        END IF;

        IF OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.aggregate_type IS DISTINCT FROM NEW.aggregate_type
          OR OLD.aggregate_id IS DISTINCT FROM NEW.aggregate_id
          OR OLD.event_type IS DISTINCT FROM NEW.event_type
          OR OLD.payload IS DISTINCT FROM NEW.payload
          OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
          OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'outbox event envelope is immutable';
        END IF;

        IF OLD.payload_sha256 IS NOT NULL
          AND OLD.payload_sha256 IS DISTINCT FROM NEW.payload_sha256 THEN
          RAISE EXCEPTION 'outbox event payload hash is immutable after publication';
        END IF;

        IF OLD.payload_sha256 IS NULL
          AND NEW.payload_sha256 IS NOT NULL
          AND NOT (OLD.status = 'publishing' AND NEW.status = 'published') THEN
          RAISE EXCEPTION 'outbox event payload hash can only be set during publication';
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      DROP TRIGGER IF EXISTS outbox_events_prevent_evidence_mutation ON outbox_events;
      CREATE TRIGGER outbox_events_prevent_evidence_mutation
      BEFORE UPDATE OR DELETE ON outbox_events
      FOR EACH ROW EXECUTE FUNCTION prevent_outbox_event_evidence_mutation();
    SQL

    remove_check_constraint :processed_events, name: "processed_events_state_evidence_check"
    remove_check_constraint :processed_events, name: "processed_events_payload_sha256_hex_check"
    remove_check_constraint :outbox_events, name: "outbox_events_delivery_state_check"
    remove_check_constraint :outbox_events, name: "outbox_events_status_check"
  end

  private

  def allow_legacy_outbox_hash_backfill!
    execute <<~SQL
      CREATE OR REPLACE FUNCTION prevent_outbox_event_evidence_mutation()
      RETURNS trigger AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'outbox events are append-only evidence';
        END IF;

        IF OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.aggregate_type IS DISTINCT FROM NEW.aggregate_type
          OR OLD.aggregate_id IS DISTINCT FROM NEW.aggregate_id
          OR OLD.event_type IS DISTINCT FROM NEW.event_type
          OR OLD.payload IS DISTINCT FROM NEW.payload
          OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
          OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'outbox event envelope is immutable';
        END IF;

        IF OLD.status = 'published'
          AND NEW.status = 'published'
          AND OLD.published_at IS NOT NULL
          AND OLD.payload_sha256 IS NULL
          AND NEW.payload_sha256 IS NOT NULL THEN
          RETURN NEW;
        END IF;

        IF OLD.payload_sha256 IS NOT NULL
          AND OLD.payload_sha256 IS DISTINCT FROM NEW.payload_sha256 THEN
          RAISE EXCEPTION 'outbox event payload hash is immutable after publication';
        END IF;

        IF OLD.payload_sha256 IS NULL
          AND NEW.payload_sha256 IS NOT NULL
          AND NOT (OLD.status = 'publishing' AND NEW.status = 'published') THEN
          RAISE EXCEPTION 'outbox event payload hash can only be set during publication';
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL
  end

  def backfill_legacy_published_outbox_hashes
    OutboxEvent.reset_column_information
    say_with_time "Backfilling legacy published outbox payload hashes" do
      OutboxEvent.where(status: "published", payload_sha256: nil).includes(:organization).find_each do |event|
        event.update_columns(payload_sha256: Outbox::Publisher.payload_sha256(Outbox::Publisher.envelope_for(event)))
      end
    end
  end

  def outbox_event_state_check
    <<~SQL.squish
      (
        status = 'pending'
        AND published_at IS NULL
        AND dead_lettered_at IS NULL
        AND payload_sha256 IS NULL
      )
      OR (
        status = 'publishing'
        AND last_attempted_at IS NOT NULL
        AND published_at IS NULL
        AND dead_lettered_at IS NULL
        AND payload_sha256 IS NULL
      )
      OR (
        status = 'published'
        AND published_at IS NOT NULL
        AND payload_sha256 IS NOT NULL
        AND dead_lettered_at IS NULL
      )
      OR (
        status = 'dead_lettered'
        AND published_at IS NULL
        AND payload_sha256 IS NULL
        AND dead_lettered_at IS NOT NULL
        AND error_class IS NOT NULL
        AND btrim(error_class) <> ''
        AND last_error IS NOT NULL
        AND btrim(last_error) <> ''
      )
    SQL
  end

  def processed_event_state_check
    <<~SQL.squish
      (
        status = 'processing'
        AND processed_at IS NULL
        AND error_class IS NULL
        AND last_error IS NULL
      )
      OR (
        status = 'processed'
        AND processed_at IS NOT NULL
        AND error_class IS NULL
        AND last_error IS NULL
      )
      OR (
        status = 'failed'
        AND processed_at IS NULL
        AND error_class IS NOT NULL
        AND btrim(error_class) <> ''
        AND last_error IS NOT NULL
        AND btrim(last_error) <> ''
      )
    SQL
  end
end
