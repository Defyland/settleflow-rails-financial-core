require "test_helper"

class DatabasePartitionFeasibilityTest < ActiveSupport::TestCase
  test "reports feasibility for every partition candidate" do
    checks = Database::PartitionFeasibility.call

    assert_equal Database::PartitionFeasibility::CANDIDATES.map(&:table).sort, checks.map(&:table).sort
    checks.each do |check|
      assert_not_empty check.partition_key
      assert_includes [ true, false ], check.ready
    end
  end

  test "reports catalog blockers that prevent pretending partitioning is implemented" do
    checks = Database::PartitionFeasibility.call

    journal_entries = checks.find { |check| check.table == "journal_entries" }
    audit_logs = checks.find { |check| check.table == "audit_logs" }
    reconciliation_runs = checks.find { |check| check.table == "reconciliation_runs" }
    reconciliation_rows = checks.find { |check| check.table == "reconciliation_rows" }

    assert_not journal_entries.ready
    assert_blocker journal_entries, :primary_key_missing_partition_key, index_name: "journal_entries_pkey"
    assert_blocker journal_entries, :unique_index_missing_partition_key, index_name: "index_journal_entries_on_public_id"
    assert_blocker journal_entries, :foreign_key_references_without_partition_key, source_table: "ledger_lines"
    assert_warning journal_entries, :missing_partition_key_index

    assert_not audit_logs.ready
    assert_blocker audit_logs, :unique_index_missing_partition_key, index_name: "index_audit_logs_on_chain_sequence"
    assert_blocker audit_logs, :foreign_key_references_without_partition_key, source_table: "audit_log_anchors"

    assert_not reconciliation_runs.ready
    assert_blocker reconciliation_runs, :primary_key_missing_partition_key, index_name: "reconciliation_runs_pkey"
    assert_blocker reconciliation_runs, :foreign_key_references_without_partition_key, source_table: "reconciliation_rows"

    assert_not reconciliation_rows.ready
    assert_blocker reconciliation_rows, :primary_key_missing_partition_key, index_name: "reconciliation_rows_pkey"
    assert_blocker reconciliation_rows, :unique_index_missing_partition_key, index_name: "idx_reconciliation_rows_run_type_external_id"
    assert_blocker reconciliation_rows, :unique_index_missing_partition_key, index_name: "index_reconciliation_rows_on_public_id"
  end

  test "does not report nullable partition keys in current schema" do
    checks = Database::PartitionFeasibility.call

    checks.each do |check|
      assert_no_blocker check, :nullable_partition_key
    end
  end

  private

  def assert_blocker(check, code, details = {})
    assert finding_matching?(check.blockers, code, details),
      "Expected blocker #{code.inspect} with #{details.inspect} for #{check.table}; got #{check.blockers.map(&:to_h).inspect}"
  end

  def assert_no_blocker(check, code)
    assert_not check.blockers.any? { |finding| finding.code == code },
      "Expected no blocker #{code.inspect} for #{check.table}; got #{check.blockers.map(&:to_h).inspect}"
  end

  def assert_warning(check, code, details = {})
    assert finding_matching?(check.warnings, code, details),
      "Expected warning #{code.inspect} with #{details.inspect} for #{check.table}; got #{check.warnings.map(&:to_h).inspect}"
  end

  def finding_matching?(findings, code, details)
    findings.any? do |finding|
      finding.code == code && details.all? { |key, value| finding.details.fetch(key) == value }
    end
  end
end
