class MedCase < ApplicationRecord
  belongs_to :organization
  belongs_to :pix_payment
  belongs_to :refund, optional: true

  enum :status, { opened: "opened", rejected: "rejected", refunded: "refunded" }

  validates :external_id, :amount_cents, :currency, :reason, :opened_at, presence: true
  validates :external_id, uniqueness: { scope: :organization_id }
  validates :idempotency_key, uniqueness: { scope: :organization_id }, allow_nil: true
  validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
  validate :pix_payment_belongs_to_organization
  validate :currency_matches_pix_payment

  private

  def pix_payment_belongs_to_organization
    return if pix_payment.blank? || organization_id.blank? || pix_payment.organization_id == organization_id

    errors.add(:pix_payment, "must belong to organization")
  end

  def currency_matches_pix_payment
    return if pix_payment.blank? || currency.blank? || pix_payment.currency == currency

    errors.add(:currency, "must match Pix payment currency")
  end
end
