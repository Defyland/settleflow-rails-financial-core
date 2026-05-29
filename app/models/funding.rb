class Funding < ApplicationRecord
  belongs_to :organization
  belongs_to :wallet
  belongs_to :journal_entry, optional: true

  enum :status, { posted: "posted", failed: "failed" }

  validates :external_id, :amount_cents, :currency, presence: true
  validates :external_id, uniqueness: { scope: :organization_id }
  validates :idempotency_key, uniqueness: { scope: :organization_id }, allow_nil: true
  validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
end
