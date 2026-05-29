module Errors
  class ValidationError < ApplicationError
    def initialize(message = "Validation failed", details: {})
      super(message, code: "validation_failed", http_status: :unprocessable_content, details:)
    end
  end
end
