module Errors
  class AuthorizationError < ApplicationError
    def initialize(message = "API credential is not authorized for this operation", details: {})
      super(message, code: "authorization_failed", http_status: :forbidden, details:)
    end
  end
end
