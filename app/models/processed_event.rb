class ProcessedEvent < ApplicationRecord
  PROCESSORS = {
    clickhouse_financial_events: "clickhouse_financial_events"
  }.freeze

  belongs_to :organization
  belongs_to :outbox_event

  enum :status, { processing: "processing", processed: "processed", failed: "failed" }

  validates :processor, :event_id, :event_type, :payload_sha256, :status, presence: true
  validates :payload_sha256, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :event_id, uniqueness: { scope: :processor }
  validates :outbox_event_id, uniqueness: { scope: :processor }
  validate :state_has_expected_evidence
  validate :matches_published_outbox_event

  private

  def state_has_expected_evidence
    if processing?
      errors.add(:processed_at, "must be blank while processing") if processed_at.present?
      errors.add(:error_class, "must be blank while processing") if error_class.present?
      errors.add(:last_error, "must be blank while processing") if last_error.present?
    elsif processed?
      errors.add(:processed_at, "must be present after processing") if processed_at.blank?
      errors.add(:error_class, "must be blank after processing") if error_class.present?
      errors.add(:last_error, "must be blank after processing") if last_error.present?
    elsif failed?
      errors.add(:processed_at, "must be blank after failure") if processed_at.present?
      errors.add(:error_class, "must be present after failure") if error_class.blank?
      errors.add(:last_error, "must be present after failure") if last_error.blank?
    end
  end

  def matches_published_outbox_event
    return if outbox_event.blank?

    errors.add(:outbox_event, "must be published") unless outbox_event.published? && outbox_event.published_at.present?
    errors.add(:organization, "must match outbox event") if organization_id != outbox_event.organization_id
    errors.add(:event_id, "must match outbox public id") if event_id != outbox_event.public_id
    errors.add(:event_type, "must match outbox event type") if event_type != outbox_event.event_type
    errors.add(:payload_sha256, "must match outbox payload hash") if payload_sha256 != outbox_event.payload_sha256
  end
end
