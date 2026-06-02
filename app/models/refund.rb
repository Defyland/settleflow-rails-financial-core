class Refund < ApplicationRecord
  belongs_to :organization
  belongs_to :wallet
  belongs_to :pix_payment
  belongs_to :journal_entry, optional: true
  has_one :med_case, dependent: :restrict_with_exception

  enum :status, { settled: "settled", failed: "failed" }

  validates :external_id, :amount_cents, :currency, :reason, :idempotency_key, presence: true
  validates :external_id, uniqueness: { scope: :organization_id }
  validates :idempotency_key, uniqueness: { scope: :organization_id }
  validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
  validate :records_belong_to_organization
  validate :currency_matches_wallet_and_pix

  private

  def records_belong_to_organization
    return if organization_id.blank?

    errors.add(:wallet, "must belong to organization") if wallet.present? && wallet.organization_id != organization_id
    errors.add(:pix_payment, "must belong to organization") if pix_payment.present? && pix_payment.organization_id != organization_id
  end

  def currency_matches_wallet_and_pix
    return if currency.blank?

    errors.add(:currency, "must match wallet currency") if wallet.present? && wallet.currency != currency
    errors.add(:currency, "must match Pix payment currency") if pix_payment.present? && pix_payment.currency != currency
  end
end
