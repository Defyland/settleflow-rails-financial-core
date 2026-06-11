module Analytics
  class ClickHouseEventMapper < ApplicationService
    TIMESTAMP_FORMAT = "%Y-%m-%d %H:%M:%S.%6N".freeze
    def self.format_time(time)
      time.utc.strftime(TIMESTAMP_FORMAT)
    end

    def initialize(outbox_event:)
      @outbox_event = outbox_event
    end

    def call
      envelope = Outbox::Publisher.envelope_for(outbox_event)
      payload_json = JSON.generate(envelope.fetch(:payload).deep_stringify_keys)

      {
        event_id: outbox_event.public_id,
        event_type: outbox_event.event_type,
        aggregate_type: outbox_event.aggregate_type,
        aggregate_id: outbox_event.aggregate_id,
        organization_id: outbox_event.organization.public_id,
        correlation_id: outbox_event.correlation_id.to_s,
        idempotency_key: outbox_event.idempotency_key,
        payload: payload_json,
        payload_sha256: Outbox::Publisher.payload_sha256(envelope),
        occurred_at: self.class.format_time(outbox_event.created_at),
        synced_at: self.class.format_time(Time.current)
      }.compact
    end

    private

    attr_reader :outbox_event
  end
end
