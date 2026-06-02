class ClickHouseSyncJob < ApplicationJob
  queue_as :analytics

  discard_on ActiveRecord::RecordNotFound

  def perform(outbox_event_id)
    Analytics::ClickHouseSync.call(outbox_event: OutboxEvent.find(outbox_event_id))
  end
end
