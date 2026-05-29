class Current < ActiveSupport::CurrentAttributes
  attribute :organization, :request_id, :correlation_id, :api_key_digest
end
