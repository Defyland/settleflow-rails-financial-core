require "test_helper"

class DatabaseBenchmarkThresholdsTest < ActiveSupport::TestCase
  Result = Data.define(:organizations, :wallets, :entries, :counts, :consistency, :explains)

  test "fails when wallet statement plan does not use a ledger index" do
    result = Result.new(
      organizations: 1,
      wallets: 1,
      entries: 1,
      counts: { wallets: 1, journal_entries: 2, ledger_lines: 4, ledger_analytics_events: 4, outbox_events: 100 },
      consistency: [ { name: :consistency, ok: true, details: {} } ],
      explains: [
        explain(:wallet_statement, seq_scan_plan("ledger_lines")),
        explain(:outbox_publishable, index_plan("outbox_events", "idx_outbox_status_next_attempt")),
        explain(:reconciliation_accounts, seq_scan_plan("ledger_accounts")),
        explain(:ledger_analytics_wallet_daily, index_plan("ledger_analytics_events", "index_ledger_analytics_events_on_org_wallet_day")),
        explain(:audit_chain_tail, seq_scan_plan("audit_logs"))
      ]
    )

    check = Database::BenchmarkThresholds.call(result:).find { |item| item.name == :wallet_statement_uses_ledger_index }

    assert_not check.ok
  end

  test "fails when benchmark input is below the configured volume profile" do
    result = Result.new(
      organizations: 1,
      wallets: 25,
      entries: 250,
      counts: { wallets: 25, journal_entries: 275, ledger_lines: 550, ledger_analytics_events: 550, outbox_events: 100 },
      consistency: [ { name: :consistency, ok: true, details: {} } ],
      explains: [
        explain(:wallet_statement, index_plan("ledger_lines", "index_ledger_lines_on_organization_id_and_created_at")),
        explain(:outbox_publishable, index_plan("outbox_events", "idx_outbox_status_next_attempt")),
        explain(:reconciliation_accounts, seq_scan_plan("ledger_accounts")),
        explain(:ledger_analytics_wallet_daily, index_plan("ledger_analytics_events", "index_ledger_analytics_events_on_org_wallet_day")),
        explain(:audit_chain_tail, seq_scan_plan("audit_logs"))
      ]
    )

    check = Database::BenchmarkThresholds.call(
      result:,
      minimum_wallets: 100,
      minimum_entries: 2_000
    ).find { |item| item.name == :minimum_benchmark_profile }

    assert_not check.ok
    assert_equal 100, check.details.fetch(:minimum_wallets)
    assert_equal 2_000, check.details.fetch(:minimum_entries)
  end

  test "fails when ledger analytics projection is not complete" do
    result = Result.new(
      organizations: 1,
      wallets: 100,
      entries: 2_000,
      counts: { wallets: 100, journal_entries: 2_100, ledger_lines: 4_200, ledger_analytics_events: 4_199, outbox_events: 100 },
      consistency: [ { name: :consistency, ok: true, details: {} } ],
      explains: [
        explain(:wallet_statement, index_plan("ledger_lines", "index_ledger_lines_on_organization_id_and_created_at")),
        explain(:outbox_publishable, index_plan("outbox_events", "idx_outbox_status_next_attempt")),
        explain(:reconciliation_accounts, seq_scan_plan("ledger_accounts")),
        explain(:ledger_analytics_wallet_daily, index_plan("ledger_analytics_events", "index_ledger_analytics_events_on_org_wallet_day")),
        explain(:audit_chain_tail, seq_scan_plan("audit_logs"))
      ]
    )

    check = Database::BenchmarkThresholds.call(result:).find { |item| item.name == :ledger_analytics_projection_complete }

    assert_not check.ok
    assert_equal 4_200, check.details.fetch(:ledger_lines)
    assert_equal 4_199, check.details.fetch(:projected_events)
  end

  private

  def explain(name, plan)
    { name:, sql: "SELECT 1", plan: JSON.generate([ { "Plan" => plan, "Execution Time" => 1.0 } ]) }
  end

  def seq_scan_plan(relation_name)
    {
      "Node Type" => "Seq Scan",
      "Relation Name" => relation_name,
      "Temp Written Blocks" => 0
    }
  end

  def index_plan(relation_name, index_name)
    {
      "Node Type" => "Index Scan",
      "Relation Name" => relation_name,
      "Index Name" => index_name,
      "Temp Written Blocks" => 0
    }
  end
end
