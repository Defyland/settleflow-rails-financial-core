class Transfer < ApplicationRecord
  belongs_to :organization
  belongs_to :source_wallet, class_name: "Wallet"
  belongs_to :destination_wallet, class_name: "Wallet"
  belongs_to :journal_entry, optional: true

  enum :status, { posted: "posted", failed: "failed" }

  validates :external_id, :amount_cents, :currency, :idempotency_key, presence: true
  validates :external_id, uniqueness: { scope: :organization_id }
  validates :idempotency_key, uniqueness: { scope: :organization_id }
  validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
  validate :wallets_belong_to_organization
  validate :wallets_are_different
  validate :currency_matches_wallets

  private

  def wallets_belong_to_organization
    return if source_wallet.blank? || destination_wallet.blank?
    return if source_wallet.organization_id == organization_id && destination_wallet.organization_id == organization_id

    errors.add(:base, "wallets must belong to the same organization")
  end

  def wallets_are_different
    return if source_wallet_id.blank? || destination_wallet_id.blank? || source_wallet_id != destination_wallet_id

    errors.add(:destination_wallet_id, "must be different from source_wallet_id")
  end

  def currency_matches_wallets
    return if currency.blank?

    errors.add(:currency, "must match source wallet currency") if source_wallet.present? && source_wallet.currency != currency
    errors.add(:currency, "must match destination wallet currency") if destination_wallet.present? && destination_wallet.currency != currency
  end
end
