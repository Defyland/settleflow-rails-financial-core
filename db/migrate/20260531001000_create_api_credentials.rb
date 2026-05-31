class CreateApiCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :api_credentials do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :key_prefix, null: false
      t.string :key_digest, null: false
      t.jsonb :scopes, null: false, default: []
      t.datetime :last_used_at
      t.datetime :expires_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :api_credentials, :key_prefix, unique: true
    add_index :api_credentials, :key_digest, unique: true
    add_index :api_credentials, [ :organization_id, :revoked_at ]
  end
end
