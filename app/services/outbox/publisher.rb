module Outbox
  class Publisher
    def self.publish(event)
      publisher.publish(envelope_for(event))
    end

    def self.publisher
      Rails.application.config.x.outbox.publisher || default_publisher
    end

    def self.envelope_for(event)
      {
        id: event.public_id,
        event_type: event.event_type,
        aggregate_type: event.aggregate_type,
        aggregate_id: event.aggregate_id,
        organization_id: event.organization.public_id,
        payload: event.payload,
        correlation_id: event.correlation_id,
        idempotency_key: event.idempotency_key,
        created_at: event.created_at.iso8601
      }.compact
    end

    def self.payload_sha256(envelope)
      OpenSSL::Digest::SHA256.hexdigest(JSON.generate(envelope.deep_stringify_keys))
    end

    def self.default_publisher
      if ENV["OUTBOX_WEBHOOK_URL"].present?
        Outbox::Publishers::HttpPublisher.new(ENV.fetch("OUTBOX_WEBHOOK_URL"))
      else
        Outbox::Publishers::LogPublisher.new
      end
    end
  end
end
