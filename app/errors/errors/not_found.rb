module Errors
  class NotFound < ApplicationError
    def initialize(message = "Resource not found", details: {})
      super(message, code: "not_found", http_status: :not_found, details:)
    end
  end
end
