module Errors
  class AuthenticationError < ApplicationError
    def initialize(message = "Invalid or missing API key", details: {})
      super(message, code: "authentication_failed", http_status: :unauthorized, details:)
    end
  end
end
