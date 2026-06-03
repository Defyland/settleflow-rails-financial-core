class OutboxLegacyCommandIdentityException < ApplicationRecord
  belongs_to :organization
  belongs_to :outbox_event

  validates :aggregate_type, :aggregate_id, :event_type, :payload_sha256, :expected_idempotency_key,
    :reason, :accepted_at, presence: true
  validates :payload_sha256, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :outbox_event_id, uniqueness: true

  before_update :raise_immutable_record
  before_destroy :raise_immutable_record, prepend: true

  private

  def raise_immutable_record
    raise ActiveRecord::ReadOnlyRecord, "Legacy outbox command identity exceptions are immutable evidence"
  end
end
