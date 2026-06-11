module OutboxEvents
  class Emit < ApplicationService
    def initialize(organization:, aggregate:, event_type:, payload:, correlation_id: nil, idempotency_key: nil)
      @organization = organization
      @aggregate = aggregate
      @event_type = event_type
      @payload = payload
      @correlation_id = correlation_id
      @idempotency_key = idempotency_key
    end

    def call
      event = organization.outbox_events.create!(
        aggregate_type: aggregate.class.name,
        aggregate_id: aggregate.id,
        event_type:,
        payload:,
        correlation_id:,
        idempotency_key:
      )
      OutboxPublishJob.perform_later(event.id)
      event
    end

    private

    attr_reader :organization, :aggregate, :event_type, :payload, :correlation_id, :idempotency_key
  end
end
