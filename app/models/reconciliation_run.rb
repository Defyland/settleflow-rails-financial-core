class ReconciliationRun < ApplicationRecord
  belongs_to :organization

  enum :status, { matched: "matched", discrepant: "discrepant" }

  validates :provider, :statement_date, :status, presence: true
  validates :provider, uniqueness: { scope: [:organization_id, :statement_date] }
  validates :provider_balance_cents, :ledger_balance_cents, :discrepancy_cents, numericality: { only_integer: true }
end
