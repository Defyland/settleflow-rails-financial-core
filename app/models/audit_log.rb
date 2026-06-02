class AuditLog < ApplicationRecord
  attr_readonly :chain_sequence, :previous_hash, :hash_value, :hash_algorithm

  belongs_to :organization, optional: true

  validates :actor_type, :action, :subject_type, presence: true
  validates :chain_sequence, :hash_value, :hash_algorithm, presence: true, on: :update
  validates :hash_algorithm, inclusion: { in: [ "sha256" ] }, allow_nil: true

  scope :hash_mismatches, -> { where("hash_value IS DISTINCT FROM audit_log_chain_hash(audit_logs)") }
  scope :broken_chain_links, lambda {
    joins("LEFT JOIN audit_logs previous_audit_logs ON previous_audit_logs.chain_sequence = audit_logs.chain_sequence - 1")
      .where("audit_logs.chain_sequence > 1")
      .where("previous_audit_logs.id IS NULL OR audit_logs.previous_hash IS DISTINCT FROM previous_audit_logs.hash_value")
  }
  scope :invalid_genesis_links, -> { where(chain_sequence: 1).where.not(previous_hash: nil) }

  def self.hash_chain_intact?
    hash_mismatches.none? && broken_chain_links.none? && invalid_genesis_links.none?
  end

  def calculated_hash
    self.class.connection.select_value(
      self.class.sanitize_sql_array([ "SELECT audit_log_chain_hash(audit_logs) FROM audit_logs WHERE id = ?", id ])
    )
  end

  def hash_valid?
    hash_value == calculated_hash
  end
end
