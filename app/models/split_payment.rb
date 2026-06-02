class SplitPayment < ApplicationRecord
  belongs_to :organization
  belongs_to :source_wallet, class_name: "Wallet"
  belongs_to :journal_entry, optional: true
  has_many :split_entries, dependent: :restrict_with_exception

  enum :status, { posted: "posted", failed: "failed" }

  validates :external_id, :total_amount_cents, :currency, :idempotency_key, presence: true
  validates :external_id, uniqueness: { scope: :organization_id }
  validates :idempotency_key, uniqueness: { scope: :organization_id }
  validates :total_amount_cents, numericality: { greater_than: 0, only_integer: true }
  validate :source_wallet_belongs_to_organization
  validate :currency_matches_source_wallet

  private

  def source_wallet_belongs_to_organization
    return if source_wallet.blank? || organization_id.blank? || source_wallet.organization_id == organization_id

    errors.add(:source_wallet, "must belong to organization")
  end

  def currency_matches_source_wallet
    return if source_wallet.blank? || currency.blank? || source_wallet.currency == currency

    errors.add(:currency, "must match source wallet currency")
  end
end
