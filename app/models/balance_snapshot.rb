class BalanceSnapshot < ApplicationRecord
  belongs_to :organization
  belongs_to :wallet

  validates :currency, :captured_on, :captured_at, :source, presence: true
  validates :available_cents, :pending_cents, :blocked_cents,
    numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :ledger_available_cents, :difference_cents, numericality: { only_integer: true }
  validates :wallet_id, uniqueness: { scope: [ :organization_id, :currency, :captured_on ] }
end
