class JournalEntry < ApplicationRecord
  SUPPORTED_EVENT_TYPES = FinancialContracts::JOURNAL_EVENT_TYPES

  before_update :raise_immutable_record
  before_destroy :raise_immutable_record, prepend: true

  belongs_to :organization
  belongs_to :reference, polymorphic: true, optional: true
  has_many :ledger_lines, dependent: :restrict_with_exception

  enum :status, { posted: "posted", reversed: "reversed" }

  validates :event_type, :occurred_at, :idempotency_key, :reference_type, :reference_id, presence: true
  validates :event_type, inclusion: { in: SUPPORTED_EVENT_TYPES }
  validates :idempotency_key, uniqueness: { scope: :organization_id }

  # Balanced means debits equal credits within every currency, matching
  # Ledger::JournalPoster and the database balance trigger. A plain
  # debit-vs-credit total across currencies would call a multi-currency
  # journal balanced even when it is not.
  def balanced?
    ledger_lines
      .group(:currency)
      .sum(Arel.sql("CASE WHEN direction = 'debit' THEN amount_cents ELSE -amount_cents END"))
      .values.all?(&:zero?)
  end

  private

  def raise_immutable_record
    raise ActiveRecord::ReadOnlyRecord, "Journal entries are immutable after creation"
  end
end
