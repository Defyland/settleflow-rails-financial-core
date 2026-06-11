class OutboxPublishJob < ApplicationJob
  queue_as :outbox

  discard_on ActiveRecord::RecordNotFound

  def perform(outbox_event_id)
    event = OutboxEvent.find(outbox_event_id)
    return unless event.claim_for_publish!

    return unless publish_event(event)

    enqueue_analytics_sync(event)
  rescue ActiveRecord::RecordNotFound
    raise
  end

  private

  def publish_event(event)
    envelope = Outbox::Publisher.envelope_for(event)
    delivery_result = Outbox::Publisher.publisher.publish(envelope)
    event.publish!(delivery_result, payload_sha256: Outbox::Publisher.payload_sha256(envelope))
    true
  rescue StandardError => e
    event.mark_publish_failed!(e)
    OutboxPublishJob.set(wait_until: event.next_attempt_at).perform_later(event.id) if event.pending?
    Rails.logger.error(
      event: "outbox.publish_failed",
      outbox_event_id: event.id,
      error_class: e.class.name,
      error_message: e.message
    )
    false
  end

  def enqueue_analytics_sync(event)
    return unless Analytics::ClickHouseClient.configured?

    ClickHouseSyncJob.perform_later(event.id)
  rescue StandardError => e
    Rails.logger.error(
      event: "outbox.analytics_enqueue_failed",
      outbox_event_id: event.id,
      error_class: e.class.name,
      error_message: e.message
    )
  end
end
