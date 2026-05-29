class OutboxPublishJob < ApplicationJob
  queue_as :outbox

  discard_on ActiveRecord::RecordNotFound

  def perform(outbox_event_id)
    event = OutboxEvent.find(outbox_event_id)
    return unless event.pending?

    event.publish!
  rescue StandardError => e
    event&.dead_letter!(e)
    raise
  end
end
