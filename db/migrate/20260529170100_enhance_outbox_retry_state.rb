class EnhanceOutboxRetryState < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :outbox_events, :next_attempt_at, :datetime
    add_column :outbox_events, :last_attempted_at, :datetime
    add_column :outbox_events, :dead_lettered_at, :datetime
    add_column :outbox_events, :error_class, :string

    add_index :outbox_events, [ :status, :next_attempt_at ], name: "idx_outbox_status_next_attempt", algorithm: :concurrently
  end
end
