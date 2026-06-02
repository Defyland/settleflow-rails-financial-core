class Session < ApplicationRecord
  TTL = 12.hours

  belongs_to :user

  def expired?
    updated_at < TTL.ago
  end
end
