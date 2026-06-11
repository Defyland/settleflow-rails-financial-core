class ReconciliationRun < ApplicationRecord
  belongs_to :organization
  has_many :reconciliation_rows, dependent: :restrict_with_exception

  enum :status, { matched: "matched", discrepant: "discrepant" }

  validates :provider, :statement_date, :status, presence: true
  validates :provider, uniqueness: { scope: [ :organization_id, :statement_date ] }
  validates :provider_balance_cents, :ledger_balance_cents, :discrepancy_cents, numericality: { only_integer: true }
  validate :discrepancy_matches_balances

  private

  def discrepancy_matches_balances
    return if provider_balance_cents.blank? || ledger_balance_cents.blank? || discrepancy_cents.blank?
    return if discrepancy_cents == provider_balance_cents - ledger_balance_cents

    errors.add(:discrepancy_cents, "must equal provider balance minus ledger balance")
  end
end
