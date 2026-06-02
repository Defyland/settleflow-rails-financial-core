module Errors
  class IdempotencyKeyRequired < ApplicationError
    def initialize(message = "Idempotency-Key header is required for mutating requests", details: {})
      super(message, code: "idempotency_key_required", http_status: :bad_request, details:)
    end
  end
end
