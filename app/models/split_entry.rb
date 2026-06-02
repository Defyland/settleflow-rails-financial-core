class SplitEntry < ApplicationRecord
  belongs_to :organization
  belongs_to :split_payment
  belongs_to :destination_wallet, class_name: "Wallet"

  validates :amount_cents, :currency, presence: true
  validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
  validate :records_belong_to_organization
  validate :currency_matches_destination_wallet

  private

  def records_belong_to_organization
    return if organization_id.blank?

    errors.add(:split_payment, "must belong to organization") if split_payment.present? && split_payment.organization_id != organization_id
    errors.add(:destination_wallet, "must belong to organization") if destination_wallet.present? && destination_wallet.organization_id != organization_id
  end

  def currency_matches_destination_wallet
    return if destination_wallet.blank? || currency.blank? || destination_wallet.currency == currency

    errors.add(:currency, "must match destination wallet currency")
  end
end
