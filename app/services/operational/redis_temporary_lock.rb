require "redis-client"

module Operational
  class RedisTemporaryLock
    DEFAULT_TTL = Operational::TemporaryLock::DEFAULT_TTL
    FORBIDDEN_KEY_PARTS = Operational::TemporaryLock::FORBIDDEN_KEY_PARTS
    RELEASE_SCRIPT = <<~LUA.squish
      if redis.call("GET", KEYS[1]) == ARGV[1] then
        return redis.call("DEL", KEYS[1])
      end
      return 0
    LUA

    def self.configured?
      ENV["REDIS_URL"].present?
    end

    def self.call(**kwargs, &block)
      new(**kwargs).call(&block)
    end

    def initialize(key:, ttl: DEFAULT_TTL, redis_url: ENV["REDIS_URL"], client: nil)
      @key = key.to_s
      @ttl = ttl
      @redis_url = redis_url
      @client = client
      @owns_client = client.blank?
    end

    def call
      validate!(block_given?)

      redis = client || build_client
      token = SecureRandom.uuid
      namespaced_key = "operational-lock:#{key}"
      acquired = redis.call("SET", namespaced_key, token, "NX", "PX", ttl_ms) == "OK"
      raise Errors::ValidationError.new("Temporary Redis lock is already held") unless acquired

      yield
    ensure
      release(redis, namespaced_key, token) if redis.present? && namespaced_key.present? && token.present?
      redis&.close if owns_client
    end

    private

    attr_reader :key, :ttl, :redis_url, :client, :owns_client

    def validate!(has_block)
      raise Errors::ValidationError.new("Temporary Redis lock requires a block") unless has_block
      raise Errors::ValidationError.new("REDIS_URL is required for Redis temporary locks") if redis_url.blank? && client.blank?
      raise Errors::ValidationError.new("Temporary Redis lock key is required") if key.blank?
      raise Errors::ValidationError.new("Temporary Redis lock TTL must be positive") unless ttl.to_i.positive?
      raise Errors::ValidationError.new("Temporary Redis lock TTL is too long") if ttl.to_i > 5.minutes.to_i
      return unless FORBIDDEN_KEY_PARTS.any? { |part| key.match?(/(^|[:_-])#{Regexp.escape(part)}($|[:_-])/i) }

      raise Errors::ValidationError.new("Temporary Redis locks cannot guard financial source-of-truth state")
    end

    def build_client
      RedisClient.config(url: redis_url).new_client
    end

    def ttl_ms
      (ttl.to_f * 1_000).ceil
    end

    def release(redis, namespaced_key, token)
      redis.call("EVAL", RELEASE_SCRIPT, 1, namespaced_key, token)
    end
  end
end
