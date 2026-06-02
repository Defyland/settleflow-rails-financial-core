class CreateReconciliationRows < ActiveRecord::Migration[8.1]
  def change
    create_table :reconciliation_rows do |t|
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :organization, null: false, foreign_key: true
      t.references :reconciliation_run, null: false, foreign_key: true
      t.references :journal_entry, foreign_key: true
      t.string :row_type, null: false
      t.string :status, null: false
      t.string :external_id
      t.date :occurred_on, null: false
      t.bigint :provider_amount_cents, null: false, default: 0
      t.bigint :ledger_amount_cents, null: false, default: 0
      t.bigint :difference_cents, null: false, default: 0
      t.string :currency, null: false, default: "BRL"
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :reconciliation_rows, :public_id, unique: true
    add_index :reconciliation_rows, [ :reconciliation_run_id, :status ], name: "idx_reconciliation_rows_run_status"
    add_index :reconciliation_rows, [ :reconciliation_run_id, :external_id ], name: "idx_reconciliation_rows_run_external_id"
    add_index :reconciliation_rows, [ :organization_id, :occurred_on, :status ], name: "idx_reconciliation_rows_org_day_status"
    add_index :reconciliation_rows, [ :organization_id, :external_id ], name: "idx_reconciliation_rows_org_external_id"
    add_check_constraint :reconciliation_rows,
      "row_type IN ('cash_balance', 'projection_balance', 'provider_statement_entry', 'ledger_statement_entry')",
      name: "reconciliation_rows_row_type_check"
    add_check_constraint :reconciliation_rows,
      "status IN ('matched', 'discrepant', 'missing_in_ledger', 'missing_in_provider')",
      name: "reconciliation_rows_status_check"
    add_check_constraint :reconciliation_rows,
      "difference_cents = provider_amount_cents - ledger_amount_cents",
      name: "reconciliation_rows_difference_check"
  end
end
