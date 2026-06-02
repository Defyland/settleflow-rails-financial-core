class AddPixPaymentReversalState < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_reference :pix_payments, :reversal_journal_entry, foreign_key: false, index: { algorithm: :concurrently }
    add_column :pix_payments, :reversed_at, :datetime
    add_column :pix_payments, :reversal_reason, :string
    add_foreign_key :pix_payments, :journal_entries, column: :reversal_journal_entry_id, validate: false
    validate_foreign_key :pix_payments, column: :reversal_journal_entry_id
    add_check_constraint :pix_payments,
      "status IN ('created', 'pending_review', 'approved', 'rejected', 'settled', 'failed', 'reversed')",
      name: "pix_payments_status_check",
      validate: false
    validate_check_constraint :pix_payments, name: "pix_payments_status_check"
  end

  def down
    remove_check_constraint :pix_payments, name: "pix_payments_status_check"
    remove_foreign_key :pix_payments, column: :reversal_journal_entry_id
    remove_index :pix_payments, :reversal_journal_entry_id, algorithm: :concurrently
    remove_column :pix_payments, :reversal_journal_entry_id
    remove_column :pix_payments, :reversed_at
    remove_column :pix_payments, :reversal_reason
  end
end
