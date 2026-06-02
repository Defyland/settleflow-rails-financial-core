class BalanceProjection < ApplicationRecord
  belongs_to :organization
  belongs_to :wallet

  validates :currency, presence: true
  validates :available_cents, :pending_cents, :blocked_cents,
    numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validate :wallet_belongs_to_organization
  validate :currency_matches_wallet

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

  private

  def wallet_belongs_to_organization
    return if wallet.blank? || organization_id == wallet.organization_id

    errors.add(:wallet, "must belong to the organization")
  end

  def currency_matches_wallet
    return if wallet.blank? || currency == wallet.currency

    errors.add(:currency, "must match wallet currency")
  end
end
