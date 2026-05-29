module Errors
  class IdempotencyConflict < ApplicationError
    def initialize(message = "Idempotency key was already used with a different request", details: {})
      super(message, code: "idempotency_conflict", http_status: :conflict, details:)
    end
  end
end
