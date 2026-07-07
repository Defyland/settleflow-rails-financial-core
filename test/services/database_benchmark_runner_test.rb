require "test_helper"

class DatabaseBenchmarkRunnerTest < ActiveSupport::TestCase
  test "seeds a realistic dataset and returns consistency plus explain evidence" do
    result = with_benchmark_minimums(wallets: 1, entries: 1) do
      Database::BenchmarkRunner.call(organizations: 1, wallets: 5, entries: 50)
    end

    assert_equal 1, result.organizations
    assert_equal 5, result.wallets
    assert_equal 50, result.entries
    assert_operator result.seed_duration_seconds, :>=, 0
    assert_equal 5, result.counts.fetch(:wallets)
    assert result.counts.fetch(:journal_entries).positive?
    assert_equal result.counts.fetch(:ledger_lines), result.counts.fetch(:ledger_analytics_events)
    assert result.consistency.all? { |check| check.fetch(:ok) }, result.consistency.inspect
    thresholds_by_name = result.thresholds.index_by { |check| check.fetch(:name) }
    assert thresholds_by_name.fetch(:minimum_benchmark_profile).fetch(:ok), result.thresholds.inspect
    assert thresholds_by_name.fetch(:ledger_analytics_projection_complete).fetch(:ok), result.thresholds.inspect
    assert_includes thresholds_by_name, :wallet_statement_uses_ledger_index
    assert_equal %i[audit_chain_tail ledger_analytics_wallet_daily outbox_publishable reconciliation_accounts wallet_statement].sort,
      result.explains.map { |explain| explain.fetch(:name) }.sort
  end

  private

  def with_benchmark_minimums(wallets:, entries:)
    previous_wallets = ENV["DATABASE_BENCHMARK_MIN_WALLETS"]
    previous_entries = ENV["DATABASE_BENCHMARK_MIN_ENTRIES"]
    ENV["DATABASE_BENCHMARK_MIN_WALLETS"] = wallets.to_s
    ENV["DATABASE_BENCHMARK_MIN_ENTRIES"] = entries.to_s
    yield
  ensure
    ENV["DATABASE_BENCHMARK_MIN_WALLETS"] = previous_wallets
    ENV["DATABASE_BENCHMARK_MIN_ENTRIES"] = previous_entries
  end
end
