class Current < ActiveSupport::CurrentAttributes
  attribute :organization, :request_id, :correlation_id, :api_key_digest, :api_credential, :session

  delegate :user, to: :session, allow_nil: true
end
