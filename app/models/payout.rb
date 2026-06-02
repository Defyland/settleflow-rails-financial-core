class Payout < ApplicationRecord
  belongs_to :organization
  belongs_to :wallet
  belongs_to :journal_entry, optional: true
  belongs_to :settlement_journal_entry, class_name: "JournalEntry", optional: true

  enum :status, { scheduled: "scheduled", settled: "settled", failed: "failed" }

  validates :external_id, :amount_cents, :currency, :settlement_due_on, :destination_kind, :destination_reference, :idempotency_key, presence: true
  validates :external_id, uniqueness: { scope: :organization_id }
  validates :idempotency_key, uniqueness: { scope: :organization_id }
  validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
  validates :settlement_delay_days, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validate :wallet_belongs_to_organization
  validate :currency_matches_wallet

  private

  def wallet_belongs_to_organization
    return if wallet.blank? || organization_id.blank? || wallet.organization_id == organization_id

    errors.add(:wallet, "must belong to organization")
  end

  def currency_matches_wallet
    return if wallet.blank? || currency.blank? || wallet.currency == currency

    errors.add(:currency, "must match wallet currency")
  end
end
