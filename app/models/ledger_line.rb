class LedgerLine < ApplicationRecord
  belongs_to :organization
  belongs_to :journal_entry
  belongs_to :ledger_account

  enum :direction, { debit: "debit", credit: "credit" }

  validates :direction, :currency, presence: true
  validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
  validate :account_belongs_to_same_organization

  private

  def account_belongs_to_same_organization
    return if ledger_account.blank? || ledger_account.organization_id == organization_id

    errors.add(:ledger_account, "must belong to the same organization")
  end
end
