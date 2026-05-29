module Errors
  class InsufficientFunds < ApplicationError
    def initialize(message = "Wallet does not have enough available balance", details: {})
      super(message, code: "insufficient_funds", http_status: :unprocessable_content, details:)
    end
  end
end
