class AddIdempotencyKeyEvidenceGuards < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM idempotency_keys
          WHERE status NOT IN ('processing', 'succeeded', 'failed')
             OR request_hash !~ '^[0-9a-f]{64}$'
             OR btrim(key) = ''
             OR btrim(request_method) = ''
             OR btrim(request_path) = ''
             OR (status = 'processing' AND (locked_at IS NULL OR response_status IS NOT NULL))
             OR (status = 'succeeded' AND (response_status IS NULL OR response_status < 100 OR response_status > 599))
             OR (status = 'failed' AND response_status IS NOT NULL)
        ) THEN
          RAISE EXCEPTION 'existing idempotency_keys violate evidence guards';
        END IF;
      END
      $$;
    SQL

    add_check_constraint :idempotency_keys,
      "status IN ('processing', 'succeeded', 'failed')",
      name: "idempotency_keys_status_check",
      validate: false
    add_check_constraint :idempotency_keys,
      "request_hash ~ '^[0-9a-f]{64}$'",
      name: "idempotency_keys_request_hash_sha256_check",
      validate: false
    add_check_constraint :idempotency_keys,
      "btrim(key) <> '' AND btrim(request_method) <> '' AND btrim(request_path) <> ''",
      name: "idempotency_keys_identity_present_check",
      validate: false
    response_state_check = <<~SQL.squish
      (
        status = 'processing'
        AND locked_at IS NOT NULL
        AND response_status IS NULL
      )
      OR (
        status = 'succeeded'
        AND response_status BETWEEN 100 AND 599
      )
      OR (
        status = 'failed'
        AND response_status IS NULL
      )
    SQL
    add_check_constraint :idempotency_keys,
      response_state_check,
      name: "idempotency_keys_response_state_check",
      validate: false

    validate_check_constraint :idempotency_keys, name: "idempotency_keys_status_check"
    validate_check_constraint :idempotency_keys, name: "idempotency_keys_request_hash_sha256_check"
    validate_check_constraint :idempotency_keys, name: "idempotency_keys_identity_present_check"
    validate_check_constraint :idempotency_keys, name: "idempotency_keys_response_state_check"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION prevent_idempotency_key_evidence_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_OP = 'INSERT' THEN
          IF NEW.status <> 'processing' THEN
            RAISE EXCEPTION 'idempotency records must start processing';
          END IF;
          RETURN NEW;
        END IF;

        IF TG_OP = 'DELETE' THEN
          IF OLD.status = 'succeeded' THEN
            RAISE EXCEPTION 'succeeded idempotency records are replay evidence';
          END IF;
          RETURN OLD;
        END IF;

        IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.key IS DISTINCT FROM NEW.key
          OR OLD.request_method IS DISTINCT FROM NEW.request_method
          OR OLD.request_path IS DISTINCT FROM NEW.request_path
          OR OLD.request_hash IS DISTINCT FROM NEW.request_hash
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'idempotency command identity is immutable';
        END IF;

        IF OLD.status = 'succeeded' THEN
          RAISE EXCEPTION 'succeeded idempotency records are immutable replay evidence';
        END IF;

        IF NEW.status = 'succeeded' AND OLD.status <> 'processing' THEN
          RAISE EXCEPTION 'idempotency records can only succeed from processing';
        END IF;

        RETURN NEW;
      END;
      $$;

      DROP TRIGGER IF EXISTS idempotency_keys_prevent_evidence_mutation ON idempotency_keys;
      CREATE TRIGGER idempotency_keys_prevent_evidence_mutation
      BEFORE INSERT OR UPDATE OR DELETE ON idempotency_keys
      FOR EACH ROW EXECUTE FUNCTION prevent_idempotency_key_evidence_mutation();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS idempotency_keys_prevent_evidence_mutation ON idempotency_keys;
      DROP FUNCTION IF EXISTS prevent_idempotency_key_evidence_mutation();
    SQL

    remove_check_constraint :idempotency_keys, name: "idempotency_keys_response_state_check"
    remove_check_constraint :idempotency_keys, name: "idempotency_keys_identity_present_check"
    remove_check_constraint :idempotency_keys, name: "idempotency_keys_request_hash_sha256_check"
    remove_check_constraint :idempotency_keys, name: "idempotency_keys_status_check"
  end
end
