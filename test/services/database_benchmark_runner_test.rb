require "test_helper"

class DatabaseBenchmarkRunnerTest < ActiveSupport::TestCase
  test "seeds a realistic dataset and returns consistency plus explain evidence" do
    result = Database::BenchmarkRunner.call(organizations: 1, wallets: 2, entries: 2)

    assert_equal 1, result.organizations
    assert_equal 2, result.wallets
    assert_equal 2, result.entries
    assert_operator result.seed_duration_seconds, :>=, 0
    assert_equal 2, result.counts.fetch(:wallets)
    assert result.counts.fetch(:journal_entries).positive?
    assert result.consistency.all? { |check| check.fetch(:ok) }, result.consistency.inspect
    assert_equal %i[audit_chain_tail outbox_publishable reconciliation_accounts wallet_statement].sort,
      result.explains.map { |explain| explain.fetch(:name) }.sort
  end
end
