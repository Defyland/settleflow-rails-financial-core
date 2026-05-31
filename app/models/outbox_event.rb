class OutboxEvent < ApplicationRecord
  MAX_ATTEMPTS = 5
  RETRY_BACKOFF = [
    1.minute,
    5.minutes,
    15.minutes,
    1.hour,
    6.hours
  ].freeze

  belongs_to :organization

  enum :status, { pending: "pending", published: "published", dead_lettered: "dead_lettered" }

  scope :publishable, -> { pending.where("next_attempt_at IS NULL OR next_attempt_at <= ?", Time.current) }
  scope :attention, -> { where(status: %w[pending dead_lettered]) }

  validates :aggregate_type, :aggregate_id, :event_type, presence: true

  def publish!(delivery_result = nil, payload_sha256: nil)
    update!(
      status: "published",
      attempts: attempts + 1,
      published_at: Time.current,
      last_attempted_at: Time.current,
      next_attempt_at: nil,
      last_error: nil,
      error_class: nil,
      dead_lettered_at: nil,
      publisher: delivery_result&.adapter,
      published_to: delivery_result&.destination,
      publisher_message_id: delivery_result&.message_id,
      payload_sha256:
    )
  end

  def dead_letter!(error)
    update!(
      status: "dead_lettered",
      attempts: attempts + 1,
      last_attempted_at: Time.current,
      dead_lettered_at: Time.current,
      next_attempt_at: nil,
      error_class: error.class.name,
      last_error: error.to_s
    )
  end

  def mark_publish_failed!(error)
    return dead_letter!(error) if attempts + 1 >= MAX_ATTEMPTS

    update!(
      status: "pending",
      attempts: attempts + 1,
      last_attempted_at: Time.current,
      next_attempt_at: Time.current + RETRY_BACKOFF.fetch(attempts, RETRY_BACKOFF.last),
      error_class: error.class.name,
      last_error: error.to_s
    )
  end

  def reset_for_retry!
    update!(
      status: "pending",
      next_attempt_at: Time.current,
      last_error: nil,
      error_class: nil,
      dead_lettered_at: nil
    )
  end

  def publishable?
    pending? && (next_attempt_at.blank? || next_attempt_at <= Time.current)
  end
end
