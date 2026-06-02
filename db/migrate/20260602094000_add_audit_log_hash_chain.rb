class AddAuditLogHashChain < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :audit_logs, :chain_sequence, :bigint
    add_column :audit_logs, :previous_hash, :string
    add_column :audit_logs, :hash_value, :string
    add_column :audit_logs, :hash_algorithm, :string, default: "sha256"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION audit_log_chain_payload(log_row audit_logs)
      RETURNS jsonb AS $$
      BEGIN
        RETURN jsonb_build_object(
          'chain_sequence', log_row.chain_sequence,
          'previous_hash', log_row.previous_hash,
          'hash_algorithm', log_row.hash_algorithm,
          'public_id', log_row.public_id,
          'organization_id', log_row.organization_id,
          'actor_type', log_row.actor_type,
          'actor_id', log_row.actor_id,
          'action', log_row.action,
          'subject_type', log_row.subject_type,
          'subject_id', log_row.subject_id,
          'request_id', log_row.request_id,
          'correlation_id', log_row.correlation_id,
          'ip_address', log_row.ip_address,
          'user_agent', log_row.user_agent,
          'metadata', log_row.metadata,
          'created_at', log_row.created_at
        );
      END;
      $$ LANGUAGE plpgsql IMMUTABLE;

      CREATE OR REPLACE FUNCTION audit_log_chain_hash(log_row audit_logs)
      RETURNS text AS $$
        SELECT encode(digest(audit_log_chain_payload(log_row)::text, 'sha256'), 'hex')
      $$ LANGUAGE SQL IMMUTABLE;
    SQL

    execute <<~SQL
      DO $$
      DECLARE
        audit_record audit_logs%ROWTYPE;
        sequence_value bigint := 0;
        previous_value text := NULL;
        computed_hash text;
      BEGIN
        FOR audit_record IN SELECT * FROM audit_logs ORDER BY created_at ASC, id ASC LOOP
          sequence_value := sequence_value + 1;

          UPDATE audit_logs
             SET chain_sequence = sequence_value,
                 previous_hash = previous_value,
                 hash_algorithm = 'sha256'
           WHERE id = audit_record.id
           RETURNING * INTO audit_record;

          computed_hash := audit_log_chain_hash(audit_record);

          UPDATE audit_logs
             SET hash_value = computed_hash
           WHERE id = audit_record.id;

          previous_value := computed_hash;
        END LOOP;
      END;
      $$;
    SQL

    change_column_null :audit_logs, :chain_sequence, false
    change_column_null :audit_logs, :hash_value, false
    change_column_null :audit_logs, :hash_algorithm, false

    add_index :audit_logs, :chain_sequence, unique: true, algorithm: :concurrently
    add_index :audit_logs, :hash_value, unique: true, algorithm: :concurrently
    add_check_constraint :audit_logs, "hash_algorithm = 'sha256'", name: "audit_logs_hash_algorithm_check", validate: false
    add_check_constraint :audit_logs, "hash_value ~ '^[0-9a-f]{64}$'", name: "audit_logs_hash_value_format_check", validate: false
    add_check_constraint :audit_logs, "chain_sequence = 1 OR previous_hash IS NOT NULL", name: "audit_logs_previous_hash_required_check", validate: false
    validate_check_constraint :audit_logs, name: "audit_logs_hash_algorithm_check"
    validate_check_constraint :audit_logs, name: "audit_logs_hash_value_format_check"
    validate_check_constraint :audit_logs, name: "audit_logs_previous_hash_required_check"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION assign_audit_log_hash_chain()
      RETURNS trigger AS $$
      DECLARE
        last_sequence bigint;
        last_hash text;
      BEGIN
        PERFORM pg_advisory_xact_lock(860029001);

        SELECT chain_sequence, hash_value
          INTO last_sequence, last_hash
          FROM audit_logs
         ORDER BY chain_sequence DESC
         LIMIT 1;

        NEW.chain_sequence := COALESCE(last_sequence, 0) + 1;
        NEW.previous_hash := last_hash;
        NEW.hash_algorithm := 'sha256';
        NEW.hash_value := audit_log_chain_hash(NEW);

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER audit_logs_hash_chain_before_insert
      BEFORE INSERT ON audit_logs
      FOR EACH ROW
      EXECUTE FUNCTION assign_audit_log_hash_chain();

      CREATE OR REPLACE FUNCTION prevent_audit_log_mutation()
      RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'audit logs are append-only and cannot be mutated'
          USING ERRCODE = 'integrity_constraint_violation';
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER audit_logs_prevent_update_delete
      BEFORE UPDATE OR DELETE ON audit_logs
      FOR EACH ROW
      EXECUTE FUNCTION prevent_audit_log_mutation();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS audit_logs_prevent_update_delete ON audit_logs;
      DROP TRIGGER IF EXISTS audit_logs_hash_chain_before_insert ON audit_logs;
      DROP FUNCTION IF EXISTS prevent_audit_log_mutation();
      DROP FUNCTION IF EXISTS assign_audit_log_hash_chain();
      DROP FUNCTION IF EXISTS audit_log_chain_hash(audit_logs);
      DROP FUNCTION IF EXISTS audit_log_chain_payload(audit_logs);
    SQL

    remove_check_constraint :audit_logs, name: "audit_logs_previous_hash_required_check"
    remove_check_constraint :audit_logs, name: "audit_logs_hash_value_format_check"
    remove_check_constraint :audit_logs, name: "audit_logs_hash_algorithm_check"
    remove_index :audit_logs, :hash_value, algorithm: :concurrently
    remove_index :audit_logs, :chain_sequence, algorithm: :concurrently
    remove_column :audit_logs, :hash_algorithm
    remove_column :audit_logs, :hash_value
    remove_column :audit_logs, :previous_hash
    remove_column :audit_logs, :chain_sequence
  end
end
