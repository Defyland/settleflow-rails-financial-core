module Analytics
  class ClickHouseEventMapper
    def self.call(...)
      new(...).call
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
        occurred_at: outbox_event.created_at.utc.iso8601(6),
        synced_at: Time.current.utc.iso8601(6)
      }.compact
    end

    private

    attr_reader :outbox_event
  end
end
