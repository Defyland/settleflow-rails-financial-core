class CreateOperatorApprovals < ActiveRecord::Migration[8.1]
  def change
    create_table :operator_approvals do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.string :action, null: false
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.string :status, null: false, default: "pending"
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.references :approved_by, foreign_key: { to_table: :users }
      t.datetime :approved_at
      t.string :reason
      t.string :correlation_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :operator_approvals, :public_id, unique: true
    add_index :operator_approvals, [ :action, :subject_type, :subject_id ],
      unique: true,
      where: "status = 'pending'",
      name: "idx_operator_approvals_one_pending_action"
    add_check_constraint :operator_approvals, "status IN ('pending', 'approved', 'rejected')", name: "operator_approvals_status_check"
    add_check_constraint :operator_approvals, "approved_by_id IS NULL OR approved_by_id <> requested_by_id", name: "operator_approvals_dual_control_check"
  end
end
