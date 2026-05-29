class OutboxEventSerializer
  def self.render(event)
    {
      id: event.public_id,
      aggregate_type: event.aggregate_type,
      aggregate_id: event.aggregate_id,
      event_type: event.event_type,
      status: event.status,
      correlation_id: event.correlation_id,
      attempts: event.attempts,
      published_at: event.published_at&.iso8601,
      last_error: event.last_error,
      payload: event.payload,
      created_at: event.created_at.iso8601
    }
  end
end
