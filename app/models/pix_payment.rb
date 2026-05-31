class PixPayment < ApplicationRecord
  belongs_to :organization
  belongs_to :wallet
  belongs_to :journal_entry, optional: true
  belongs_to :settlement_journal_entry, class_name: "JournalEntry", optional: true
  belongs_to :reversal_journal_entry, class_name: "JournalEntry", optional: true

  enum :status, {
    created: "created",
    pending_review: "pending_review",
    approved: "approved",
    rejected: "rejected",
    settled: "settled",
    failed: "failed",
    reversed: "reversed"
  }

  validates :external_id, :pix_key, :receiver_name, :amount_cents, :currency, presence: true
  validates :external_id, uniqueness: { scope: :organization_id }
  validates :idempotency_key, uniqueness: { scope: :organization_id }, allow_nil: true
  validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
  validates :risk_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100, only_integer: true }
end
