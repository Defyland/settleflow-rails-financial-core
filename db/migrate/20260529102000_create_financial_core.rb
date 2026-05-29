class CreateFinancialCore < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto"

    create_table :organizations do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.string :name, null: false
      t.string :slug, null: false
      t.string :status, null: false, default: "active"
      t.string :api_key_digest, null: false
      t.integer :rate_limit_per_minute, null: false, default: 120

      t.timestamps
    end
    add_index :organizations, :public_id, unique: true
    add_index :organizations, :slug, unique: true
    add_index :organizations, :api_key_digest, unique: true

    create_table :customers do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :legal_name, null: false
      t.string :document_kind, null: false
      t.string :document_number, null: false
      t.string :status, null: false, default: "active"
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :customers, :public_id, unique: true
    add_index :customers, [ :organization_id, :external_id ], unique: true
    add_index :customers, [ :organization_id, :document_number ], unique: true

    create_table :wallets do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :currency, null: false, default: "BRL"
      t.string :status, null: false, default: "active"
      t.integer :lock_version, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :wallets, :public_id, unique: true
    add_index :wallets, [ :organization_id, :external_id ], unique: true

    create_table :ledger_accounts do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.references :wallet, foreign_key: true
      t.string :code, null: false
      t.string :name, null: false
      t.string :account_type, null: false
      t.string :normal_balance, null: false
      t.string :currency, null: false, default: "BRL"
      t.string :status, null: false, default: "active"

      t.timestamps
    end
    add_index :ledger_accounts, :public_id, unique: true
    add_index :ledger_accounts, [ :organization_id, :code ], unique: true
    add_check_constraint :ledger_accounts, "account_type IN ('asset', 'liability', 'revenue', 'expense', 'equity')", name: "ledger_accounts_account_type_check"
    add_check_constraint :ledger_accounts, "normal_balance IN ('debit', 'credit')", name: "ledger_accounts_normal_balance_check"

    create_table :journal_entries do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.string :event_type, null: false
      t.string :status, null: false, default: "posted"
      t.string :reference_type
      t.bigint :reference_id
      t.string :idempotency_key
      t.string :correlation_id
      t.datetime :occurred_at, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :journal_entries, :public_id, unique: true
    add_index :journal_entries, [ :organization_id, :idempotency_key ], unique: true, where: "idempotency_key IS NOT NULL"
    add_index :journal_entries, [ :reference_type, :reference_id ]
    add_index :journal_entries, [ :organization_id, :event_type ]

    create_table :ledger_lines do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.references :journal_entry, null: false, foreign_key: true
      t.references :ledger_account, null: false, foreign_key: true
      t.string :direction, null: false
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: "BRL"
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :ledger_lines, :public_id, unique: true
    add_index :ledger_lines, [ :organization_id, :ledger_account_id ]
    add_index :ledger_lines, [ :organization_id, :created_at ]
    add_check_constraint :ledger_lines, "direction IN ('debit', 'credit')", name: "ledger_lines_direction_check"
    add_check_constraint :ledger_lines, "amount_cents > 0", name: "ledger_lines_amount_positive_check"

    create_table :balance_projections do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.references :wallet, null: false, foreign_key: true
      t.string :currency, null: false, default: "BRL"
      t.bigint :available_cents, null: false, default: 0
      t.bigint :pending_cents, null: false, default: 0
      t.bigint :blocked_cents, null: false, default: 0
      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end
    add_index :balance_projections, :public_id, unique: true
    add_index :balance_projections, [ :organization_id, :wallet_id, :currency ], unique: true, name: "idx_balance_projection_wallet_currency"

    create_table :fundings do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.references :wallet, null: false, foreign_key: true
      t.references :journal_entry, foreign_key: true
      t.string :external_id, null: false
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: "BRL"
      t.string :status, null: false, default: "posted"
      t.string :idempotency_key
      t.string :correlation_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :fundings, :public_id, unique: true
    add_index :fundings, [ :organization_id, :external_id ], unique: true
    add_index :fundings, [ :organization_id, :idempotency_key ], unique: true, where: "idempotency_key IS NOT NULL"
    add_check_constraint :fundings, "amount_cents > 0", name: "fundings_amount_positive_check"

    create_table :transfers do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.references :source_wallet, null: false, foreign_key: { to_table: :wallets }
      t.references :destination_wallet, null: false, foreign_key: { to_table: :wallets }
      t.references :journal_entry, foreign_key: true
      t.string :external_id, null: false
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: "BRL"
      t.string :status, null: false, default: "posted"
      t.string :idempotency_key
      t.string :correlation_id
      t.string :memo
      t.string :failure_code
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :transfers, :public_id, unique: true
    add_index :transfers, [ :organization_id, :external_id ], unique: true
    add_index :transfers, [ :organization_id, :idempotency_key ], unique: true, where: "idempotency_key IS NOT NULL"
    add_check_constraint :transfers, "amount_cents > 0", name: "transfers_amount_positive_check"

    create_table :pix_payments do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.references :wallet, null: false, foreign_key: true
      t.references :journal_entry, foreign_key: true
      t.references :settlement_journal_entry, foreign_key: { to_table: :journal_entries }
      t.string :external_id, null: false
      t.string :pix_key, null: false
      t.string :receiver_name, null: false
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: "BRL"
      t.string :status, null: false, default: "created"
      t.integer :risk_score, null: false, default: 0
      t.string :idempotency_key
      t.string :correlation_id
      t.string :failure_code
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :pix_payments, :public_id, unique: true
    add_index :pix_payments, [ :organization_id, :external_id ], unique: true
    add_index :pix_payments, [ :organization_id, :idempotency_key ], unique: true, where: "idempotency_key IS NOT NULL"
    add_check_constraint :pix_payments, "amount_cents > 0", name: "pix_payments_amount_positive_check"

    create_table :reconciliation_runs do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.string :provider, null: false
      t.date :statement_date, null: false
      t.bigint :provider_balance_cents, null: false
      t.bigint :ledger_balance_cents, null: false
      t.bigint :discrepancy_cents, null: false
      t.string :status, null: false
      t.string :correlation_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :reconciliation_runs, :public_id, unique: true
    add_index :reconciliation_runs, [ :organization_id, :provider, :statement_date ], unique: true, name: "idx_reconciliation_provider_day"

    create_table :outbox_events do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.string :aggregate_type, null: false
      t.bigint :aggregate_id, null: false
      t.string :event_type, null: false
      t.string :status, null: false, default: "pending"
      t.string :correlation_id
      t.string :idempotency_key
      t.integer :attempts, null: false, default: 0
      t.datetime :published_at
      t.string :last_error
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end
    add_index :outbox_events, :public_id, unique: true
    add_index :outbox_events, [ :status, :created_at ]
    add_index :outbox_events, [ :aggregate_type, :aggregate_id ]

    create_table :idempotency_keys do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.string :key, null: false
      t.string :request_method, null: false
      t.string :request_path, null: false
      t.string :request_hash, null: false
      t.string :status, null: false, default: "processing"
      t.integer :response_status
      t.jsonb :response_body, null: false, default: {}
      t.datetime :locked_at

      t.timestamps
    end
    add_index :idempotency_keys, :public_id, unique: true
    add_index :idempotency_keys, [ :organization_id, :key ], unique: true

    create_table :audit_logs do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, foreign_key: true
      t.string :actor_type, null: false
      t.bigint :actor_id
      t.string :action, null: false
      t.string :subject_type, null: false
      t.bigint :subject_id
      t.string :request_id
      t.string :correlation_id
      t.string :ip_address
      t.string :user_agent
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :audit_logs, :public_id, unique: true
    add_index :audit_logs, [ :organization_id, :created_at ]
    add_index :audit_logs, [ :subject_type, :subject_id ]
  end
end
