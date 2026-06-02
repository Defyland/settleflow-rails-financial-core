class CreateDatabaseEngineeringPackTables < ActiveRecord::Migration[8.1]
  def change
    create_table :balance_snapshots do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.references :wallet, null: false, foreign_key: true
      t.string :currency, null: false, default: "BRL"
      t.date :captured_on, null: false
      t.datetime :captured_at, null: false
      t.bigint :available_cents, null: false
      t.bigint :pending_cents, null: false
      t.bigint :blocked_cents, null: false
      t.bigint :ledger_available_cents, null: false
      t.bigint :difference_cents, null: false
      t.string :source, null: false, default: "scheduled_capture"
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :balance_snapshots, :public_id, unique: true
    add_index :balance_snapshots, [ :organization_id, :wallet_id, :currency, :captured_on ], unique: true, name: "idx_balance_snapshots_wallet_day"
    add_index :balance_snapshots, [ :organization_id, :captured_on ]
    add_check_constraint :balance_snapshots, "available_cents >= 0", name: "balance_snapshots_available_non_negative_check"
    add_check_constraint :balance_snapshots, "pending_cents >= 0", name: "balance_snapshots_pending_non_negative_check"
    add_check_constraint :balance_snapshots, "blocked_cents >= 0", name: "balance_snapshots_blocked_non_negative_check"

    create_table :processed_events do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.references :outbox_event, null: false, foreign_key: true
      t.string :processor, null: false
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.string :status, null: false, default: "processing"
      t.string :payload_sha256, null: false
      t.datetime :processed_at
      t.string :error_class
      t.text :last_error
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :processed_events, :public_id, unique: true
    add_index :processed_events, [ :processor, :event_id ], unique: true
    add_index :processed_events, [ :organization_id, :processor, :status ]
    add_index :processed_events, [ :outbox_event_id, :processor ], unique: true
    add_check_constraint :processed_events, "status IN ('processing', 'processed', 'failed')", name: "processed_events_status_check"
  end
end
