class ReconciliationRow < ApplicationRecord
  belongs_to :organization
  belongs_to :reconciliation_run
  belongs_to :journal_entry, optional: true

  enum :row_type, {
    cash_balance: "cash_balance",
    projection_balance: "projection_balance",
    provider_statement_entry: "provider_statement_entry",
    ledger_statement_entry: "ledger_statement_entry"
  }
  enum :status, {
    matched: "matched",
    discrepant: "discrepant",
    missing_in_ledger: "missing_in_ledger",
    missing_in_provider: "missing_in_provider"
  }

  validates :row_type, :status, :external_id, :occurred_on, :currency, presence: true
  validates :provider_amount_cents, :ledger_amount_cents, :difference_cents, numericality: { only_integer: true }
  validate :difference_matches_amounts
  validate :status_matches_row_type
  validate :status_matches_amount_evidence
  validate :run_belongs_to_same_organization
  validate :journal_entry_belongs_to_same_organization
  private

  def difference_matches_amounts
    return if difference_cents == provider_amount_cents - ledger_amount_cents

    errors.add(:difference_cents, "must equal provider amount minus ledger amount")
  end

  def status_matches_row_type
    valid_statuses = case row_type
    when "cash_balance", "projection_balance"
      %w[matched discrepant]
    when "provider_statement_entry"
      %w[matched discrepant missing_in_ledger]
    when "ledger_statement_entry"
      %w[missing_in_provider]
    else
      []
    end
    return if status.in?(valid_statuses)

    errors.add(:status, "is not valid for row type")
  end

  def status_matches_amount_evidence
    case status
    when "matched"
      errors.add(:difference_cents, "must be zero for matched rows") unless difference_cents.to_i.zero?
    when "discrepant"
      errors.add(:difference_cents, "must be non-zero for discrepant rows") if difference_cents.to_i.zero?
    when "missing_in_ledger"
      if ledger_amount_cents.to_i != 0 || provider_amount_cents.to_i.zero?
        errors.add(:base, "missing-in-ledger rows require provider amount and zero ledger amount")
      end
    when "missing_in_provider"
      if provider_amount_cents.to_i != 0 || ledger_amount_cents.to_i.zero?
        errors.add(:base, "missing-in-provider rows require ledger amount and zero provider amount")
      end
    end
  end

  def run_belongs_to_same_organization
    return if reconciliation_run.blank? || reconciliation_run.organization_id == organization_id

    errors.add(:reconciliation_run, "must belong to the same organization")
  end

  def journal_entry_belongs_to_same_organization
    return if journal_entry.blank? || journal_entry.organization_id == organization_id

    errors.add(:journal_entry, "must belong to the same organization")
  end
end
