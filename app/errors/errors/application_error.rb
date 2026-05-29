module Errors
  class ApplicationError < StandardError
    attr_reader :code, :details, :http_status

    def initialize(message, code:, http_status:, details: {})
      super(message)
      @code = code
      @http_status = http_status
      @details = details
    end
  end
end
