class JournalEntry < ApplicationRecord
  belongs_to :organization
  belongs_to :reference, polymorphic: true, optional: true
  has_many :ledger_lines, dependent: :restrict_with_exception

  enum :status, { posted: "posted", reversed: "reversed" }

  validates :event_type, :occurred_at, presence: true
  validates :idempotency_key, uniqueness: { scope: :organization_id }, allow_nil: true

  def balanced?
    ledger_lines.debit.sum(:amount_cents) == ledger_lines.credit.sum(:amount_cents)
  end
end
