module Privacy
  class Redactor
    FILTERED = "[FILTERED]".freeze

    def self.name(value)
      value.present? ? FILTERED : value
    end

    def self.document(value)
      mask_tail(value)
    end

    def self.contact(value)
      mask_tail(value)
    end

    def self.reference(value)
      mask_tail(value)
    end

    def self.metadata(value)
      value.present? ? { redacted: true } : {}
    end

    def self.sanitize_response(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), result|
          result[key] = SensitiveKeys.match?(key) ? redacted_value(key, item) : sanitize_response(item)
        end
      when Array
        value.map { |item| sanitize_response(item) }
      else
        value
      end
    end

    def self.mask_tail(value)
      return value if value.blank?

      tail = value.to_s.last(4)
      "#{FILTERED}:#{tail}"
    end
    private_class_method :mask_tail

    def self.redacted_value(key, value)
      case key.to_s
      when /document_number/
        document(value)
      when /pix_key/
        contact(value)
      when /destination_reference/
        reference(value)
      when /metadata/
        metadata(value)
      else
        FILTERED
      end
    end
    private_class_method :redacted_value
  end
end
