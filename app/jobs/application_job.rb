class ApplicationJob < ActiveJob::Base
  self.enqueue_after_transaction_commit = true if respond_to?(:enqueue_after_transaction_commit=)

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
