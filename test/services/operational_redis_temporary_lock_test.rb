require "test_helper"

class OperationalRedisTemporaryLockTest < ActiveSupport::TestCase
  FakeRedis = Struct.new(:store, :calls, keyword_init: true) do
    def call(*args)
      calls << args
      case args.first
      when "SET"
        _command, key, value, nx, px, ttl_ms = args
        raise "expected NX PX" unless nx == "NX" && px == "PX"

        return nil if store.key?(key)

        store[key] = { value:, ttl_ms: }
        "OK"
      when "EVAL"
        _command, _script, key_count, key, token = args
        raise "expected one key" unless key_count == 1

        return 0 unless store.dig(key, :value) == token

        store.delete(key)
        1
      else
        raise "unexpected redis command #{args.inspect}"
      end
    end
  end

  test "uses Redis SET NX PX and releases with compare-and-delete script" do
    redis = FakeRedis.new(store: {}, calls: [])
    executed = 0

    result = Operational::RedisTemporaryLock.call(key: "cache-warm", ttl: 2.seconds, client: redis) do
      executed += 1
      "done"
    end

    assert_equal "done", result
    assert_equal 1, executed
    assert_empty redis.store
    assert_equal "SET", redis.calls.first.first
    assert_equal "operational-lock:cache-warm", redis.calls.first.second
    assert_equal 2_000, redis.calls.first.last
    assert_equal "EVAL", redis.calls.last.first
  end

  test "rejects an already held Redis lock" do
    redis = FakeRedis.new(
      store: { "operational-lock:cache-warm" => { value: "other-owner", ttl_ms: 30_000 } },
      calls: []
    )

    error = assert_raises(Errors::ValidationError) do
      Operational::RedisTemporaryLock.call(key: "cache-warm", client: redis) { true }
    end

    assert_match(/already held/, error.message)
  end

  test "does not allow Redis locks around financial source-of-truth state" do
    redis = FakeRedis.new(store: {}, calls: [])

    error = assert_raises(Errors::ValidationError) do
      Operational::RedisTemporaryLock.call(key: "settlement-run", client: redis) { true }
    end

    assert_match(/source-of-truth/, error.message)
  end
end
