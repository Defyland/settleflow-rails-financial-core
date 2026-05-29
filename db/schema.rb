# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_29_102000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id"
    t.string "actor_type", null: false
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.jsonb "metadata", default: {}, null: false
    t.bigint "organization_id"
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.string "request_id"
    t.bigint "subject_id"
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["organization_id", "created_at"], name: "index_audit_logs_on_organization_id_and_created_at"
    t.index ["organization_id"], name: "index_audit_logs_on_organization_id"
    t.index ["public_id"], name: "index_audit_logs_on_public_id", unique: true
    t.index ["subject_type", "subject_id"], name: "index_audit_logs_on_subject_type_and_subject_id"
  end

  create_table "balance_projections", force: :cascade do |t|
    t.bigint "available_cents", default: 0, null: false
    t.bigint "blocked_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "BRL", null: false
    t.integer "lock_version", default: 0, null: false
    t.bigint "organization_id", null: false
    t.bigint "pending_cents", default: 0, null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "updated_at", null: false
    t.bigint "wallet_id", null: false
    t.index ["organization_id", "wallet_id", "currency"], name: "idx_balance_projection_wallet_currency", unique: true
    t.index ["organization_id"], name: "index_balance_projections_on_organization_id"
    t.index ["public_id"], name: "index_balance_projections_on_public_id", unique: true
    t.index ["wallet_id"], name: "index_balance_projections_on_wallet_id"
  end

  create_table "customers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "document_kind", null: false
    t.string "document_number", null: false
    t.string "external_id", null: false
    t.string "legal_name", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "organization_id", null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "document_number"], name: "index_customers_on_organization_id_and_document_number", unique: true
    t.index ["organization_id", "external_id"], name: "index_customers_on_organization_id_and_external_id", unique: true
    t.index ["organization_id"], name: "index_customers_on_organization_id"
    t.index ["public_id"], name: "index_customers_on_public_id", unique: true
  end

  create_table "fundings", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.string "currency", default: "BRL", null: false
    t.string "external_id", null: false
    t.string "idempotency_key"
    t.bigint "journal_entry_id"
    t.jsonb "metadata", default: {}, null: false
    t.bigint "organization_id", null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.string "status", default: "posted", null: false
    t.datetime "updated_at", null: false
    t.bigint "wallet_id", null: false
    t.index ["journal_entry_id"], name: "index_fundings_on_journal_entry_id"
    t.index ["organization_id", "external_id"], name: "index_fundings_on_organization_id_and_external_id", unique: true
    t.index ["organization_id", "idempotency_key"], name: "index_fundings_on_organization_id_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["organization_id"], name: "index_fundings_on_organization_id"
    t.index ["public_id"], name: "index_fundings_on_public_id", unique: true
    t.index ["wallet_id"], name: "index_fundings_on_wallet_id"
    t.check_constraint "amount_cents > 0", name: "fundings_amount_positive_check"
  end

  create_table "idempotency_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "locked_at"
    t.bigint "organization_id", null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.string "request_hash", null: false
    t.string "request_method", null: false
    t.string "request_path", null: false
    t.jsonb "response_body", default: {}, null: false
    t.integer "response_status"
    t.string "status", default: "processing", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "key"], name: "index_idempotency_keys_on_organization_id_and_key", unique: true
    t.index ["organization_id"], name: "index_idempotency_keys_on_organization_id"
    t.index ["public_id"], name: "index_idempotency_keys_on_public_id", unique: true
  end

  create_table "journal_entries", force: :cascade do |t|
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "idempotency_key"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.bigint "organization_id", null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.bigint "reference_id"
    t.string "reference_type"
    t.string "status", default: "posted", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "event_type"], name: "index_journal_entries_on_organization_id_and_event_type"
    t.index ["organization_id", "idempotency_key"], name: "index_journal_entries_on_organization_id_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["organization_id"], name: "index_journal_entries_on_organization_id"
    t.index ["public_id"], name: "index_journal_entries_on_public_id", unique: true
    t.index ["reference_type", "reference_id"], name: "index_journal_entries_on_reference_type_and_reference_id"
  end

  create_table "ledger_accounts", force: :cascade do |t|
    t.string "account_type", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "BRL", null: false
    t.string "name", null: false
    t.string "normal_balance", null: false
    t.bigint "organization_id", null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.bigint "wallet_id"
    t.index ["organization_id", "code"], name: "index_ledger_accounts_on_organization_id_and_code", unique: true
    t.index ["organization_id"], name: "index_ledger_accounts_on_organization_id"
    t.index ["public_id"], name: "index_ledger_accounts_on_public_id", unique: true
    t.index ["wallet_id"], name: "index_ledger_accounts_on_wallet_id"
    t.check_constraint "account_type::text = ANY (ARRAY['asset'::character varying, 'liability'::character varying, 'revenue'::character varying, 'expense'::character varying, 'equity'::character varying]::text[])", name: "ledger_accounts_account_type_check"
    t.check_constraint "normal_balance::text = ANY (ARRAY['debit'::character varying, 'credit'::character varying]::text[])", name: "ledger_accounts_normal_balance_check"
  end

  create_table "ledger_lines", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "BRL", null: false
    t.string "direction", null: false
    t.bigint "journal_entry_id", null: false
    t.bigint "ledger_account_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "organization_id", null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "updated_at", null: false
    t.index ["journal_entry_id"], name: "index_ledger_lines_on_journal_entry_id"
    t.index ["ledger_account_id"], name: "index_ledger_lines_on_ledger_account_id"
    t.index ["organization_id", "created_at"], name: "index_ledger_lines_on_organization_id_and_created_at"
    t.index ["organization_id", "ledger_account_id"], name: "index_ledger_lines_on_organization_id_and_ledger_account_id"
    t.index ["organization_id"], name: "index_ledger_lines_on_organization_id"
    t.index ["public_id"], name: "index_ledger_lines_on_public_id", unique: true
    t.check_constraint "amount_cents > 0", name: "ledger_lines_amount_positive_check"
    t.check_constraint "direction::text = ANY (ARRAY['debit'::character varying, 'credit'::character varying]::text[])", name: "ledger_lines_direction_check"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "api_key_digest", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.integer "rate_limit_per_minute", default: 120, null: false
    t.string "slug", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key_digest"], name: "index_organizations_on_api_key_digest", unique: true
    t.index ["public_id"], name: "index_organizations_on_public_id", unique: true
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
  end

  create_table "outbox_events", force: :cascade do |t|
    t.bigint "aggregate_id", null: false
    t.string "aggregate_type", null: false
    t.integer "attempts", default: 0, null: false
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "idempotency_key"
    t.string "last_error"
    t.bigint "organization_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "published_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["aggregate_type", "aggregate_id"], name: "index_outbox_events_on_aggregate_type_and_aggregate_id"
    t.index ["organization_id"], name: "index_outbox_events_on_organization_id"
    t.index ["public_id"], name: "index_outbox_events_on_public_id", unique: true
    t.index ["status", "created_at"], name: "index_outbox_events_on_status_and_created_at"
  end

  create_table "pix_payments", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.string "currency", default: "BRL", null: false
    t.string "external_id", null: false
    t.string "failure_code"
    t.string "idempotency_key"
    t.bigint "journal_entry_id"
    t.jsonb "metadata", default: {}, null: false
    t.bigint "organization_id", null: false
    t.string "pix_key", null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.string "receiver_name", null: false
    t.integer "risk_score", default: 0, null: false
    t.bigint "settlement_journal_entry_id"
    t.string "status", default: "created", null: false
    t.datetime "updated_at", null: false
    t.bigint "wallet_id", null: false
    t.index ["journal_entry_id"], name: "index_pix_payments_on_journal_entry_id"
    t.index ["organization_id", "external_id"], name: "index_pix_payments_on_organization_id_and_external_id", unique: true
    t.index ["organization_id", "idempotency_key"], name: "index_pix_payments_on_organization_id_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["organization_id"], name: "index_pix_payments_on_organization_id"
    t.index ["public_id"], name: "index_pix_payments_on_public_id", unique: true
    t.index ["settlement_journal_entry_id"], name: "index_pix_payments_on_settlement_journal_entry_id"
    t.index ["wallet_id"], name: "index_pix_payments_on_wallet_id"
    t.check_constraint "amount_cents > 0", name: "pix_payments_amount_positive_check"
  end

  create_table "reconciliation_runs", force: :cascade do |t|
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.bigint "discrepancy_cents", null: false
    t.bigint "ledger_balance_cents", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "organization_id", null: false
    t.string "provider", null: false
    t.bigint "provider_balance_cents", null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.date "statement_date", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "provider", "statement_date"], name: "idx_reconciliation_provider_day", unique: true
    t.index ["organization_id"], name: "index_reconciliation_runs_on_organization_id"
    t.index ["public_id"], name: "index_reconciliation_runs_on_public_id", unique: true
  end

  create_table "transfers", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.string "currency", default: "BRL", null: false
    t.bigint "destination_wallet_id", null: false
    t.string "external_id", null: false
    t.string "failure_code"
    t.string "idempotency_key"
    t.bigint "journal_entry_id"
    t.string "memo"
    t.jsonb "metadata", default: {}, null: false
    t.bigint "organization_id", null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.bigint "source_wallet_id", null: false
    t.string "status", default: "posted", null: false
    t.datetime "updated_at", null: false
    t.index ["destination_wallet_id"], name: "index_transfers_on_destination_wallet_id"
    t.index ["journal_entry_id"], name: "index_transfers_on_journal_entry_id"
    t.index ["organization_id", "external_id"], name: "index_transfers_on_organization_id_and_external_id", unique: true
    t.index ["organization_id", "idempotency_key"], name: "index_transfers_on_organization_id_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["organization_id"], name: "index_transfers_on_organization_id"
    t.index ["public_id"], name: "index_transfers_on_public_id", unique: true
    t.index ["source_wallet_id"], name: "index_transfers_on_source_wallet_id"
    t.check_constraint "amount_cents > 0", name: "transfers_amount_positive_check"
  end

  create_table "wallets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "BRL", null: false
    t.bigint "customer_id", null: false
    t.string "external_id", null: false
    t.integer "lock_version", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "organization_id", null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_wallets_on_customer_id"
    t.index ["organization_id", "external_id"], name: "index_wallets_on_organization_id_and_external_id", unique: true
    t.index ["organization_id"], name: "index_wallets_on_organization_id"
    t.index ["public_id"], name: "index_wallets_on_public_id", unique: true
  end

  add_foreign_key "audit_logs", "organizations"
  add_foreign_key "balance_projections", "organizations"
  add_foreign_key "balance_projections", "wallets"
  add_foreign_key "customers", "organizations"
  add_foreign_key "fundings", "journal_entries"
  add_foreign_key "fundings", "organizations"
  add_foreign_key "fundings", "wallets"
  add_foreign_key "idempotency_keys", "organizations"
  add_foreign_key "journal_entries", "organizations"
  add_foreign_key "ledger_accounts", "organizations"
  add_foreign_key "ledger_accounts", "wallets"
  add_foreign_key "ledger_lines", "journal_entries"
  add_foreign_key "ledger_lines", "ledger_accounts"
  add_foreign_key "ledger_lines", "organizations"
  add_foreign_key "outbox_events", "organizations"
  add_foreign_key "pix_payments", "journal_entries"
  add_foreign_key "pix_payments", "journal_entries", column: "settlement_journal_entry_id"
  add_foreign_key "pix_payments", "organizations"
  add_foreign_key "pix_payments", "wallets"
  add_foreign_key "reconciliation_runs", "organizations"
  add_foreign_key "transfers", "journal_entries"
  add_foreign_key "transfers", "organizations"
  add_foreign_key "transfers", "wallets", column: "destination_wallet_id"
  add_foreign_key "transfers", "wallets", column: "source_wallet_id"
  add_foreign_key "wallets", "customers"
  add_foreign_key "wallets", "organizations"
end
