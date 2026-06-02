class AddOutboxEventEvidenceGuards < ActiveRecord::Migration[8.1]
  def up
    add_check_constraint :outbox_events,
      "payload_sha256 IS NULL OR payload_sha256 ~ '^[0-9a-f]{64}$'",
      name: "outbox_events_payload_sha256_hex_check",
      validate: false
    validate_check_constraint :outbox_events, name: "outbox_events_payload_sha256_hex_check"

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
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS outbox_events_prevent_evidence_mutation ON outbox_events;
      DROP FUNCTION IF EXISTS prevent_outbox_event_evidence_mutation();
    SQL
    remove_check_constraint :outbox_events, name: "outbox_events_payload_sha256_hex_check"
  end
end
