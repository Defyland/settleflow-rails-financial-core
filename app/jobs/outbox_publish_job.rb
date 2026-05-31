class OutboxPublishJob < ApplicationJob
  queue_as :outbox

  discard_on ActiveRecord::RecordNotFound

  def perform(outbox_event_id)
    event = OutboxEvent.find(outbox_event_id)
    return unless event.publishable?

    envelope = Outbox::Publisher.envelope_for(event)
    delivery_result = Outbox::Publisher.publisher.publish(envelope)
    event.publish!(delivery_result, payload_sha256: Outbox::Publisher.payload_sha256(envelope))
  rescue ActiveRecord::RecordNotFound
    raise
  rescue StandardError => e
    event&.mark_publish_failed!(e)
    OutboxPublishJob.set(wait_until: event.next_attempt_at).perform_later(event.id) if event&.pending?
    Rails.logger.error(
      event: "outbox.publish_failed",
      outbox_event_id: event&.id,
      error_class: e.class.name,
      error_message: e.message
    )
  end
end
