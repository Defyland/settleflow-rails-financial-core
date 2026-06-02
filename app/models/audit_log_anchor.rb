class AuditLogAnchor < ApplicationRecord
  attr_readonly :audit_log_id, :chain_sequence, :hash_value, :previous_anchor_hash, :anchor_hash, :hash_algorithm, :anchored_at

  belongs_to :audit_log
  belongs_to :organization, optional: true

  validates :chain_sequence, :hash_value, :anchor_hash, :hash_algorithm, :anchored_at, presence: true
  validates :chain_sequence, :hash_value, :anchor_hash, uniqueness: true
  validates :hash_algorithm, inclusion: { in: [ "sha256" ] }
  validates :hash_value, :anchor_hash, format: { with: /\A[0-9a-f]{64}\z/ }

  scope :hash_mismatches, -> { where("anchor_hash IS DISTINCT FROM audit_log_anchor_hash(audit_log_anchors)") }
  scope :broken_anchor_links, lambda {
    joins("LEFT JOIN audit_log_anchors previous_anchors ON previous_anchors.id = (SELECT id FROM audit_log_anchors pa WHERE pa.id < audit_log_anchors.id ORDER BY pa.id DESC LIMIT 1)")
      .where("previous_anchors.id IS NOT NULL")
      .where("audit_log_anchors.previous_anchor_hash IS DISTINCT FROM previous_anchors.anchor_hash")
  }

  def self.anchor_chain_intact?
    hash_mismatches.none? && broken_anchor_links.none?
  end

  def self.latest_covers_current_audit_tail?
    latest_anchor = order(:chain_sequence).last
    latest_audit_log = AuditLog.order(:chain_sequence).last
    return true if latest_anchor.blank? && latest_audit_log.blank?
    return false if latest_anchor.blank? || latest_audit_log.blank?

    latest_anchor.chain_sequence == latest_audit_log.chain_sequence &&
      latest_anchor.hash_value == latest_audit_log.hash_value
  end

  def envelope
    {
      id: public_id,
      event_type: "audit.hash_chain_anchored",
      aggregate_type: self.class.name,
      aggregate_id: id,
      payload: {
        audit_log_anchor_id: public_id,
        audit_log_id: audit_log.public_id,
        chain_sequence:,
        hash_value:,
        previous_anchor_hash:,
        anchor_hash:,
        hash_algorithm:,
        anchored_at: anchored_at.utc.iso8601(6)
      }.compact,
      created_at: created_at.utc.iso8601(6)
    }
  end
end
