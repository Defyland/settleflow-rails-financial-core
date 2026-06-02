class CreateAuditLogAnchors < ActiveRecord::Migration[8.1]
  def up
    create_table :audit_log_anchors do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: true, foreign_key: true
      t.references :audit_log, null: false, foreign_key: true
      t.bigint :chain_sequence, null: false
      t.string :hash_value, null: false
      t.string :previous_anchor_hash
      t.string :anchor_hash, null: false
      t.string :hash_algorithm, null: false, default: "sha256"
      t.datetime :anchored_at, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :audit_log_anchors, :public_id, unique: true
    add_index :audit_log_anchors, :chain_sequence, unique: true
    add_index :audit_log_anchors, :hash_value, unique: true
    add_index :audit_log_anchors, :anchor_hash, unique: true
    add_check_constraint :audit_log_anchors, "hash_algorithm = 'sha256'", name: "audit_log_anchors_hash_algorithm_check"
    add_check_constraint :audit_log_anchors, "hash_value ~ '^[0-9a-f]{64}$'", name: "audit_log_anchors_hash_value_format_check"
    add_check_constraint :audit_log_anchors, "anchor_hash ~ '^[0-9a-f]{64}$'", name: "audit_log_anchors_anchor_hash_format_check"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION audit_log_anchor_payload(anchor_row audit_log_anchors)
      RETURNS jsonb AS $$
      BEGIN
        RETURN jsonb_build_object(
          'chain_sequence', anchor_row.chain_sequence,
          'hash_value', anchor_row.hash_value,
          'previous_anchor_hash', anchor_row.previous_anchor_hash,
          'hash_algorithm', anchor_row.hash_algorithm,
          'anchored_at', anchor_row.anchored_at
        );
      END;
      $$ LANGUAGE plpgsql IMMUTABLE;

      CREATE OR REPLACE FUNCTION audit_log_anchor_hash(anchor_row audit_log_anchors)
      RETURNS text AS $$
        SELECT encode(digest(audit_log_anchor_payload(anchor_row)::text, 'sha256'), 'hex')
      $$ LANGUAGE SQL IMMUTABLE;

      CREATE OR REPLACE FUNCTION prevent_audit_log_anchor_mutation()
      RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'audit log anchors are append-only and cannot be mutated'
          USING ERRCODE = 'integrity_constraint_violation';
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER audit_log_anchors_prevent_update_delete
      BEFORE UPDATE OR DELETE ON audit_log_anchors
      FOR EACH ROW
      EXECUTE FUNCTION prevent_audit_log_anchor_mutation();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS audit_log_anchors_prevent_update_delete ON audit_log_anchors;
      DROP FUNCTION IF EXISTS prevent_audit_log_anchor_mutation();
      DROP FUNCTION IF EXISTS audit_log_anchor_hash(audit_log_anchors);
      DROP FUNCTION IF EXISTS audit_log_anchor_payload(audit_log_anchors);
    SQL

    drop_table :audit_log_anchors
  end
end
