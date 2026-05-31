class AddPixPaymentReversalState < ActiveRecord::Migration[8.1]
  def change
    add_reference :pix_payments, :reversal_journal_entry, foreign_key: { to_table: :journal_entries }
    add_column :pix_payments, :reversed_at, :datetime
    add_column :pix_payments, :reversal_reason, :string
    add_check_constraint :pix_payments, "status IN ('created', 'pending_review', 'approved', 'rejected', 'settled', 'failed', 'reversed')", name: "pix_payments_status_check"
  end
end
