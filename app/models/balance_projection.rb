class BalanceProjection < ApplicationRecord
  belongs_to :organization
  belongs_to :wallet

  validates :currency, presence: true
  validates :available_cents, :pending_cents, :blocked_cents,
    numericality: { greater_than_or_equal_to: 0, only_integer: true }

  def apply_available_delta!(delta_cents)
    with_lock do
      next_available_cents = available_cents + delta_cents
      if next_available_cents.negative?
        raise Errors::InsufficientFunds.new(
          details: { available_cents:, required_cents: delta_cents.abs }
        )
      end

      update!(available_cents: next_available_cents)
    end
  end
end
