class OutboxEvent < ApplicationRecord
  belongs_to :organization

  enum :status, { pending: "pending", published: "published", dead_lettered: "dead_lettered" }

  validates :aggregate_type, :aggregate_id, :event_type, presence: true

  def publish!
    update!(status: "published", attempts: attempts + 1, published_at: Time.current, last_error: nil)
  end

  def dead_letter!(error)
    update!(status: "dead_lettered", attempts: attempts + 1, last_error: error.to_s)
  end
end
