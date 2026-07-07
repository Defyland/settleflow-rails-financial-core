class Organization < ApplicationRecord
  has_many :customers, dependent: :restrict_with_exception
  has_many :wallets, dependent: :restrict_with_exception
  has_many :ledger_accounts, dependent: :restrict_with_exception
  has_many :journal_entries, dependent: :restrict_with_exception
  has_many :fundings, dependent: :restrict_with_exception
  has_many :transfers, dependent: :restrict_with_exception
  has_many :pix_payments, dependent: :restrict_with_exception
  has_many :payouts, dependent: :restrict_with_exception
  has_many :refunds, dependent: :restrict_with_exception
  has_many :split_payments, dependent: :restrict_with_exception
  has_many :split_entries, dependent: :restrict_with_exception
  has_many :med_cases, dependent: :restrict_with_exception
  has_many :reconciliation_runs, dependent: :restrict_with_exception
  has_many :reconciliation_rows, dependent: :restrict_with_exception
  has_many :outbox_events, dependent: :restrict_with_exception
  has_many :outbox_legacy_command_identity_exceptions, dependent: :restrict_with_exception
  has_many :processed_events, dependent: :restrict_with_exception
  has_many :ledger_analytics_events, dependent: :restrict_with_exception
  has_many :balance_snapshots, dependent: :restrict_with_exception
  has_many :operator_approvals, dependent: :restrict_with_exception
  has_many :api_credentials, dependent: :destroy
  has_many :idempotency_keys, dependent: :delete_all
  has_many :audit_logs, dependent: :nullify
  has_many :audit_log_anchors, dependent: :nullify

  enum :status, { active: "active", suspended: "suspended" }

  validates :name, :slug, :api_key_digest, presence: true
  validates :slug, :api_key_digest, uniqueness: true
  validates :rate_limit_per_minute, numericality: { greater_than: 0 }

  def self.digest_api_key(api_key)
    OpenSSL::Digest::SHA256.hexdigest(api_key.to_s)
  end

  def self.authenticate_api_key(api_key)
    digest = digest_api_key(api_key)
    find_by(api_key_digest: digest)&.then { |organization| organization.active? ? organization : nil }
  end
end
