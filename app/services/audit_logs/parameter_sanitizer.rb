module AuditLogs
  class ParameterSanitizer
    FILTERED = "[FILTERED]".freeze
    SENSITIVE_KEYS = %w[
      document_number
      pix_key
      receiver_name
      destination_reference
      metadata
      password
      password_confirmation
      token
      secret
      api_key
      idempotency_key
    ].freeze

    def self.call(value)
      new(value).call
    end

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
          result[key.to_s] = sensitive_key?(key) ? FILTERED : sanitize(item)
        end
      when Array
        current.map { |item| sanitize(item) }
      else
        current
      end
    end

    def sensitive_key?(key)
      normalized = key.to_s.downcase
      SENSITIVE_KEYS.any? { |sensitive| normalized.include?(sensitive) }
    end
  end
end
