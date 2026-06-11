class OutboxSweepJob < ApplicationJob
  DEFAULT_BATCH_SIZE = 100

  queue_as :outbox

  def perform(batch_size: DEFAULT_BATCH_SIZE)
    OutboxEvent.publishable.order(:created_at).limit(batch_size).find_each do |event|
      OutboxPublishJob.perform_later(event.id)
    end
  end
end
