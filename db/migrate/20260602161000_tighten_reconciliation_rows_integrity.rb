class TightenReconciliationRowsIntegrity < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  TYPE_STATUS_CONSTRAINT = <<~SQL.squish
    (
      row_type IN ('cash_balance', 'projection_balance')
      AND status IN ('matched', 'discrepant')
    )
    OR (
      row_type = 'provider_statement_entry'
      AND status IN ('matched', 'discrepant', 'missing_in_ledger')
    )
    OR (
      row_type = 'ledger_statement_entry'
      AND status = 'missing_in_provider'
    )
  SQL

  def up
    add_check_constraint :reconciliation_rows,
      "external_id IS NOT NULL",
      name: "reconciliation_rows_external_id_required_check",
      validate: false
    validate_check_constraint :reconciliation_rows, name: "reconciliation_rows_external_id_required_check"
    change_column_null :reconciliation_rows, :external_id, false

    add_check_constraint :reconciliation_rows,
      TYPE_STATUS_CONSTRAINT,
      name: "reconciliation_rows_type_status_check",
      validate: false
    validate_check_constraint :reconciliation_rows, name: "reconciliation_rows_type_status_check"

    add_index :reconciliation_rows,
      [ :reconciliation_run_id, :row_type, :external_id ],
      unique: true,
      name: "idx_reconciliation_rows_run_type_external_id",
      algorithm: :concurrently
  end

  def down
    remove_index :reconciliation_rows, name: "idx_reconciliation_rows_run_type_external_id"
    remove_check_constraint :reconciliation_rows, name: "reconciliation_rows_type_status_check"
    change_column_null :reconciliation_rows, :external_id, true
    remove_check_constraint :reconciliation_rows, name: "reconciliation_rows_external_id_required_check"
  end
end
