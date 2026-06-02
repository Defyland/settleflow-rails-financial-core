class BalanceSnapshot < ApplicationRecord
  belongs_to :organization
  belongs_to :wallet

  validates :currency, :captured_on, :captured_at, :source, presence: true
  validates :available_cents, :pending_cents, :blocked_cents,
    numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :ledger_available_cents, :difference_cents, numericality: { only_integer: true }
  validates :wallet_id, uniqueness: { scope: [ :organization_id, :currency, :captured_on ] }
  validate :wallet_belongs_to_organization
  validate :currency_matches_wallet
  validate :difference_matches_projection_minus_ledger
  before_update :prevent_mutation
  before_destroy :prevent_mutation

  private

  def wallet_belongs_to_organization
    return if wallet.blank? || organization_id == wallet.organization_id

    errors.add(:wallet, "must belong to the organization")
  end

  def currency_matches_wallet
    return if wallet.blank? || currency == wallet.currency

    errors.add(:currency, "must match wallet currency")
  end

  def difference_matches_projection_minus_ledger
    return if available_cents.blank? || ledger_available_cents.blank? || difference_cents.blank?
    return if difference_cents == available_cents - ledger_available_cents

    errors.add(:difference_cents, "must equal available cents minus ledger available cents")
  end

  def prevent_mutation
    errors.add(:base, "balance snapshots are immutable evidence")
    throw :abort
  end
end
