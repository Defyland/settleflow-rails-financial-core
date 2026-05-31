class OutboxEvent < ApplicationRecord
  MAX_ATTEMPTS = 5
  PUBLISHING_LOCK_TIMEOUT = 10.minutes
  RETRY_BACKOFF = [
    1.minute,
    5.minutes,
    15.minutes,
    1.hour,
    6.hours
  ].freeze

  belongs_to :organization

  enum :status, { pending: "pending", publishing: "publishing", published: "published", dead_lettered: "dead_lettered" }

  scope :publishable, lambda {
    pending_due = where(status: "pending").where("next_attempt_at IS NULL OR next_attempt_at <= ?", Time.current)
    stale_publishing = where(status: "publishing").where("last_attempted_at IS NULL OR last_attempted_at <= ?", PUBLISHING_LOCK_TIMEOUT.ago)

    pending_due.or(stale_publishing)
  }
  scope :attention, -> { where(status: %w[pending publishing dead_lettered]) }

  validates :aggregate_type, :aggregate_id, :event_type, presence: true

  def claim_for_publish!
    with_lock do
      return false unless claimable_for_publish?

      update!(
        status: "publishing",
        last_attempted_at: Time.current,
        next_attempt_at: nil
      )
    end
  end

  def publish!(delivery_result = nil, payload_sha256: nil)
    with_lock do
      return false unless publishing?

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
  end

  def dead_letter!(error)
    with_lock do
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
  end

  def mark_publish_failed!(error)
    with_lock do
      if attempts + 1 >= MAX_ATTEMPTS
        update!(
          status: "dead_lettered",
          attempts: attempts + 1,
          last_attempted_at: Time.current,
          dead_lettered_at: Time.current,
          next_attempt_at: nil,
          error_class: error.class.name,
          last_error: error.to_s
        )
      else
        update!(
          status: "pending",
          attempts: attempts + 1,
          last_attempted_at: Time.current,
          next_attempt_at: Time.current + RETRY_BACKOFF.fetch(attempts, RETRY_BACKOFF.last),
          error_class: error.class.name,
          last_error: error.to_s
        )
      end
    end
  end

  def reset_for_retry!
    with_lock do
      return false if publishing? && !publishing_stale?

      update!(
        status: "pending",
        next_attempt_at: Time.current,
        last_error: nil,
        error_class: nil,
        dead_lettered_at: nil
      )
    end
  end

  def publishable?
    pending_due? || (publishing? && publishing_stale?)
  end

  private

  def claimable_for_publish?
    pending_due? || (publishing? && publishing_stale?)
  end

  def pending_due?
    pending? && (next_attempt_at.blank? || next_attempt_at <= Time.current)
  end

  def publishing_stale?
    last_attempted_at.blank? || last_attempted_at <= PUBLISHING_LOCK_TIMEOUT.ago
  end
end
