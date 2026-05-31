class Current < ActiveSupport::CurrentAttributes
  attribute :organization, :request_id, :correlation_id, :api_key_digest, :session

  delegate :user, to: :session, allow_nil: true
end
