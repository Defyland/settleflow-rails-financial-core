class LedgerAccount < ApplicationRecord
  belongs_to :organization
  belongs_to :wallet, optional: true
  has_many :ledger_lines, dependent: :restrict_with_exception

  ACCOUNT_TYPES = %w[asset liability revenue expense equity].freeze
  NORMAL_BALANCES = %w[debit credit].freeze

  enum :account_type, ACCOUNT_TYPES.index_with(&:itself)
  enum :normal_balance, NORMAL_BALANCES.index_with(&:itself), prefix: :normal
  enum :status, { active: "active", archived: "archived" }

  validates :code, :name, :account_type, :normal_balance, :currency, presence: true
  validates :code, uniqueness: { scope: :organization_id }

  def balance_cents
    debit_total = ledger_lines.debit.sum(:amount_cents)
    credit_total = ledger_lines.credit.sum(:amount_cents)
    normal_debit? ? debit_total - credit_total : credit_total - debit_total
  end
end
