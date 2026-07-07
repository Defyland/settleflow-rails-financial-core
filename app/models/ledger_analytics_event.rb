class LedgerAnalyticsEvent < ApplicationRecord
  self.primary_key = :ledger_line_id

  before_update :raise_immutable_record
  before_destroy :raise_immutable_record, prepend: true

  belongs_to :organization
  belongs_to :journal_entry
  belongs_to :ledger_line
  belongs_to :ledger_account
  belongs_to :wallet, optional: true

  enum :direction, { debit: "debit", credit: "credit" }
  enum :account_type, LedgerAccount::ACCOUNT_TYPES.index_with(&:itself)
  enum :normal_balance, LedgerAccount::NORMAL_BALANCES.index_with(&:itself), prefix: :normal

  validates :event_type, :currency, :occurred_at, :occurred_on, presence: true
  validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
  validates :signed_amount_cents, numericality: { only_integer: true }
  validate :occurred_on_matches_occurred_at

  scope :for_period, ->(from:, to:) { where(occurred_on: from..to) }

  private

  def raise_immutable_record
    raise ActiveRecord::ReadOnlyRecord, "Ledger analytics events are immutable after projection"
  end

  def occurred_on_matches_occurred_at
    return if occurred_at.blank? || occurred_on.blank?
    return if occurred_on == occurred_at.to_date

    errors.add(:occurred_on, "must match occurred_at date")
  end
end
