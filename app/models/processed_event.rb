class ProcessedEvent < ApplicationRecord
  PROCESSORS = {
    clickhouse_financial_events: "clickhouse_financial_events"
  }.freeze

  belongs_to :organization
  belongs_to :outbox_event

  enum :status, { processing: "processing", processed: "processed", failed: "failed" }

  validates :processor, :event_id, :event_type, :payload_sha256, :status, presence: true
  validates :event_id, uniqueness: { scope: :processor }
  validates :outbox_event_id, uniqueness: { scope: :processor }
end
