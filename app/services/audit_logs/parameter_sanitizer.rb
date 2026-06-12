module AuditLogs
  class ParameterSanitizer < ApplicationService
    FILTERED = "[FILTERED]".freeze

    def initialize(value)
      @value = value
    end

    def call
      sanitize(value)
    end

    private

    attr_reader :value

    def sanitize(current)
      case current
      when ActionController::Parameters
        sanitize(current.to_unsafe_h)
      when Hash
        current.each_with_object({}) do |(key, item), result|
          result[key.to_s] = Privacy::SensitiveKeys.match?(key) ? FILTERED : sanitize(item)
        end
      when Array
        current.map { |item| sanitize(item) }
      else
        current
      end
    end
  end
end
