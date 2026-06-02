require "test_helper"

class OperationalTemporaryLockTest < ActiveSupport::TestCase
  test "runs the block once and releases the temporary cache lock" do
    cache = ActiveSupport::Cache::MemoryStore.new
    executed = 0

    result = Operational::TemporaryLock.call(key: "rate-limit-refresh", cache:) do
      executed += 1
      "done"
    end

    assert_equal "done", result
    assert_equal 1, executed
    assert_nil cache.read("operational-lock:rate-limit-refresh")
  end

  test "rejects concurrent ownership of the same temporary lock" do
    cache = ActiveSupport::Cache::MemoryStore.new
    assert cache.write("operational-lock:cache-warm", "existing-owner", expires_in: 1.minute, unless_exist: true)

    error = assert_raises(Errors::ValidationError) do
      Operational::TemporaryLock.call(key: "cache-warm", cache:) { flunk("lock should not be acquired") }
    end

    assert_match(/already held/, error.message)
  end

  test "does not allow temporary locks around financial source-of-truth state" do
    cache = ActiveSupport::Cache::MemoryStore.new

    %w[
      balance:projection
      ledger:journal
      idempotency-key
      payout_settlement
      refund:retry
      med-case
      reconciliation-run
      audit-log
    ].each do |key|
      error = assert_raises(Errors::ValidationError) do
        Operational::TemporaryLock.call(key:, cache:) { true }
      end

      assert_match(/source-of-truth/, error.message)
    end
  end

  test "requires a bounded positive ttl" do
    cache = ActiveSupport::Cache::MemoryStore.new

    assert_raises(Errors::ValidationError) do
      Operational::TemporaryLock.call(key: "cache-warm", ttl: 0.seconds, cache:) { true }
    end

    assert_raises(Errors::ValidationError) do
      Operational::TemporaryLock.call(key: "cache-warm", ttl: 10.minutes, cache:) { true }
    end
  end
end
