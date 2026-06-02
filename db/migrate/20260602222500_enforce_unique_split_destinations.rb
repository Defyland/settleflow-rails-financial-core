class EnforceUniqueSplitDestinations < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  LEGACY_INDEX_NAMES = %w[
    idx_on_split_payment_id_destination_wallet_id_3ed8360afa
    index_split_entries_on_split_payment_id_and_destination_wallet_id
  ].freeze
  UNIQUE_INDEX_NAME = "idx_split_entries_unique_destination_per_split"
  INDEX_COLUMNS = [ :split_payment_id, :destination_wallet_id ].freeze

  def up
    duplicate_count = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*)
      FROM (
        SELECT split_payment_id, destination_wallet_id
        FROM split_entries
        GROUP BY split_payment_id, destination_wallet_id
        HAVING COUNT(*) > 1
      ) duplicate_split_destinations
    SQL
    raise ActiveRecord::IrreversibleMigration, "duplicate split destinations exist: #{duplicate_count}" if duplicate_count.positive?

    add_index :split_entries,
      INDEX_COLUMNS,
      unique: true,
      name: UNIQUE_INDEX_NAME,
      algorithm: :concurrently,
      if_not_exists: true

    LEGACY_INDEX_NAMES.each do |index_name|
      remove_index :split_entries, name: index_name, algorithm: :concurrently, if_exists: true
    end
  end

  def down
    add_index :split_entries,
      INDEX_COLUMNS,
      name: LEGACY_INDEX_NAMES.first,
      algorithm: :concurrently,
      if_not_exists: true

    remove_index :split_entries, name: UNIQUE_INDEX_NAME, algorithm: :concurrently, if_exists: true
  end
end
