module Operational
  class TemporaryLock < ApplicationService
    DEFAULT_TTL = 30.seconds
    FORBIDDEN_KEY_PARTS = %w[
      balance
      journal
      ledger
      idempotency
      payout
      refund
      settlement
      med
      reconciliation
      audit
    ].freeze

    def initialize(key:, ttl: DEFAULT_TTL, cache: Rails.cache)
      @key = key.to_s
      @ttl = ttl
      @cache = cache
    end

    def call
      validate!(block_given?)

      token = SecureRandom.uuid
      namespaced_key = "operational-lock:#{key}"
      acquired = cache.write(namespaced_key, token, expires_in: ttl, unless_exist: true)
      raise Errors::ValidationError.new("Temporary operational lock is already held") unless acquired

      yield
    ensure
      cache.delete(namespaced_key) if namespaced_key.present? && token.present? && cache.read(namespaced_key) == token
    end

    private

    attr_reader :key, :ttl, :cache

    def validate!(has_block)
      raise Errors::ValidationError.new("Temporary operational lock requires a block") unless has_block
      raise Errors::ValidationError.new("Temporary operational lock key is required") if key.blank?
      raise Errors::ValidationError.new("Temporary operational lock TTL must be positive") unless ttl.to_i.positive?
      raise Errors::ValidationError.new("Temporary operational lock TTL is too long") if ttl.to_i > 5.minutes.to_i
      return unless FORBIDDEN_KEY_PARTS.any? { |part| key.match?(/(^|[:_-])#{Regexp.escape(part)}($|[:_-])/i) }

      raise Errors::ValidationError.new("Temporary operational locks cannot guard financial source-of-truth state")
    end
  end
end
