module Privacy
  # Canonical registry of request/response keys that carry PII or secrets.
  # Owns *what* is sensitive; callers own *how* they mask it (audit redaction
  # vs. response masking). `password` also matches `password_confirmation` and
  # any other `*password*` key through the substring check.
  module SensitiveKeys
    KEYS = %w[
      document_number
      legal_name
      pix_key
      receiver_name
      destination_reference
      metadata
      password
      token
      secret
      api_key
      idempotency_key
    ].freeze

    module_function

    def match?(key)
      normalized = key.to_s.downcase
      KEYS.any? { |sensitive| normalized.include?(sensitive) }
    end
  end
end
