class Wallet < ApplicationRecord
  belongs_to :organization
  belongs_to :customer
  has_many :ledger_accounts, dependent: :restrict_with_exception
  has_one :balance_projection, dependent: :restrict_with_exception
  has_many :fundings, dependent: :restrict_with_exception
  has_many :pix_payments, dependent: :restrict_with_exception
  has_many :payouts, dependent: :restrict_with_exception
  has_many :refunds, dependent: :restrict_with_exception
  has_many :balance_snapshots, dependent: :restrict_with_exception
  has_many :source_transfers, class_name: "Transfer", foreign_key: :source_wallet_id, dependent: :restrict_with_exception, inverse_of: :source_wallet
  has_many :destination_transfers, class_name: "Transfer", foreign_key: :destination_wallet_id, dependent: :restrict_with_exception, inverse_of: :destination_wallet
  has_many :source_split_payments, class_name: "SplitPayment", foreign_key: :source_wallet_id, dependent: :restrict_with_exception, inverse_of: :source_wallet
  has_many :destination_split_entries, class_name: "SplitEntry", foreign_key: :destination_wallet_id, dependent: :restrict_with_exception, inverse_of: :destination_wallet

  enum :status, { active: "active", blocked: "blocked", closed: "closed" }

  validates :external_id, :currency, presence: true
  validates :external_id, uniqueness: { scope: :organization_id }

  def liability_account
    @liability_account ||= begin
      if ledger_accounts.loaded?
        ledger_accounts.detect { |account| account.account_type == "liability" && account.normal_balance == "credit" && account.currency == currency } ||
          raise(ActiveRecord::RecordNotFound, "Couldn't find liability account for Wallet #{id}")
      else
        ledger_accounts.find_by!(account_type: "liability", normal_balance: "credit", currency:)
      end
    end
  end
end
