class BalanceProjection < ApplicationRecord
  belongs_to :organization
  belongs_to :wallet

  validates :currency, presence: true
  validates :available_cents, :pending_cents, :blocked_cents, numericality: { only_integer: true }

  def apply_available_delta!(delta_cents)
    with_lock do
      update!(available_cents: available_cents + delta_cents)
    end
  end
end
