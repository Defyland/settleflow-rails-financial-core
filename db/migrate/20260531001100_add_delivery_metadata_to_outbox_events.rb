class AddDeliveryMetadataToOutboxEvents < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :outbox_events, :publisher, :string
    add_column :outbox_events, :published_to, :string
    add_column :outbox_events, :publisher_message_id, :string
    add_column :outbox_events, :payload_sha256, :string

    add_index :outbox_events, :publisher_message_id, algorithm: :concurrently
    add_index :outbox_events, :payload_sha256, algorithm: :concurrently
  end
end
