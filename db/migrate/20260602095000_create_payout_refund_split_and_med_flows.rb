class CreatePayoutRefundSplitAndMedFlows < ActiveRecord::Migration[8.1]
  def change
    create_table :payouts do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.references :wallet, null: false, foreign_key: true
      t.references :journal_entry, foreign_key: true
      t.references :settlement_journal_entry, foreign_key: { to_table: :journal_entries }
      t.string :external_id, null: false
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: "BRL"
      t.string :status, null: false, default: "scheduled"
      t.integer :settlement_delay_days, null: false, default: 1
      t.date :settlement_due_on, null: false
      t.datetime :settled_at
      t.string :destination_kind, null: false, default: "bank_account"
      t.string :destination_reference, null: false
      t.string :failure_code
      t.string :idempotency_key
      t.string :correlation_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :payouts, :public_id, unique: true
    add_index :payouts, [ :organization_id, :external_id ], unique: true
    add_index :payouts, [ :organization_id, :idempotency_key ], unique: true, where: "idempotency_key IS NOT NULL"
    add_index :payouts, [ :status, :settlement_due_on ]
    add_check_constraint :payouts, "amount_cents > 0", name: "payouts_amount_positive_check"
    add_check_constraint :payouts, "settlement_delay_days >= 0", name: "payouts_settlement_delay_non_negative_check"
    add_check_constraint :payouts, "status IN ('scheduled', 'settled', 'failed')", name: "payouts_status_check"

    create_table :refunds do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.references :wallet, null: false, foreign_key: true
      t.references :pix_payment, null: false, foreign_key: true
      t.references :journal_entry, foreign_key: true
      t.string :external_id, null: false
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: "BRL"
      t.string :status, null: false, default: "settled"
      t.string :reason, null: false
      t.datetime :settled_at
      t.string :failure_code
      t.string :idempotency_key
      t.string :correlation_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :refunds, :public_id, unique: true
    add_index :refunds, [ :organization_id, :external_id ], unique: true
    add_index :refunds, [ :organization_id, :idempotency_key ], unique: true, where: "idempotency_key IS NOT NULL"
    add_index :refunds, [ :pix_payment_id, :status ]
    add_check_constraint :refunds, "amount_cents > 0", name: "refunds_amount_positive_check"
    add_check_constraint :refunds, "status IN ('settled', 'failed')", name: "refunds_status_check"

    create_table :split_payments do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.references :source_wallet, null: false, foreign_key: { to_table: :wallets }
      t.references :journal_entry, foreign_key: true
      t.string :external_id, null: false
      t.bigint :total_amount_cents, null: false
      t.string :currency, null: false, default: "BRL"
      t.string :status, null: false, default: "posted"
      t.string :memo
      t.string :failure_code
      t.string :idempotency_key
      t.string :correlation_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :split_payments, :public_id, unique: true
    add_index :split_payments, [ :organization_id, :external_id ], unique: true
    add_index :split_payments, [ :organization_id, :idempotency_key ], unique: true, where: "idempotency_key IS NOT NULL"
    add_check_constraint :split_payments, "total_amount_cents > 0", name: "split_payments_total_amount_positive_check"
    add_check_constraint :split_payments, "status IN ('posted', 'failed')", name: "split_payments_status_check"

    create_table :split_entries do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.references :split_payment, null: false, foreign_key: true
      t.references :destination_wallet, null: false, foreign_key: { to_table: :wallets }
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: "BRL"
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :split_entries, :public_id, unique: true
    add_index :split_entries, [ :split_payment_id, :destination_wallet_id ]
    add_check_constraint :split_entries, "amount_cents > 0", name: "split_entries_amount_positive_check"

    create_table :med_cases do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.references :pix_payment, null: false, foreign_key: true
      t.references :refund, foreign_key: true
      t.string :external_id, null: false
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: "BRL"
      t.string :status, null: false, default: "opened"
      t.string :reason, null: false
      t.datetime :opened_at, null: false
      t.datetime :resolved_at
      t.string :idempotency_key
      t.string :correlation_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :med_cases, :public_id, unique: true
    add_index :med_cases, [ :organization_id, :external_id ], unique: true
    add_index :med_cases, [ :organization_id, :idempotency_key ], unique: true, where: "idempotency_key IS NOT NULL"
    add_index :med_cases, [ :pix_payment_id, :status ]
    add_check_constraint :med_cases, "amount_cents > 0", name: "med_cases_amount_positive_check"
    add_check_constraint :med_cases, "status IN ('opened', 'rejected', 'refunded')", name: "med_cases_status_check"
  end
end
