require "test_helper"

class DatabaseBenchmarkThresholdsTest < ActiveSupport::TestCase
  Result = Data.define(:organizations, :wallets, :entries, :counts, :consistency, :explains)

  test "fails when wallet statement plan does not use a ledger index" do
    result = Result.new(
      organizations: 1,
      wallets: 1,
      entries: 1,
      counts: { wallets: 1, journal_entries: 2, ledger_lines: 4, outbox_events: 100 },
      consistency: [ { name: :consistency, ok: true, details: {} } ],
      explains: [
        explain(:wallet_statement, seq_scan_plan("ledger_lines")),
        explain(:outbox_publishable, index_plan("outbox_events", "idx_outbox_status_next_attempt")),
        explain(:reconciliation_accounts, seq_scan_plan("ledger_accounts")),
        explain(:audit_chain_tail, seq_scan_plan("audit_logs"))
      ]
    )

    check = Database::BenchmarkThresholds.call(result:).find { |item| item.name == :wallet_statement_uses_ledger_index }

    assert_not check.ok
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
