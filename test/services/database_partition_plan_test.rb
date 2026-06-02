require "test_helper"

class DatabasePartitionPlanTest < ActiveSupport::TestCase
  test "generates monthly partition SQL for financial high-volume tables" do
    statements = Database::PartitionPlan.call(start_on: Date.new(2026, 6, 15), months: 2)

    assert_equal 10, statements.size
    assert_equal "journal_entries_y2026m06", statements.first.partition_name
    assert_equal Date.new(2026, 6, 1), statements.first.from
    assert_equal Date.new(2026, 7, 1), statements.first.to
    assert_includes statements.first.sql, "PARTITION OF journal_entries"
    assert_includes statements.map(&:table), "reconciliation_rows"
    assert_includes statements.last.sql, "FOR VALUES FROM ('2026-07-01') TO ('2026-08-01')"
  end

  test "rejects non-positive month count" do
    assert_raises(ArgumentError) do
      Database::PartitionPlan.call(start_on: Date.new(2026, 6, 1), months: 0)
    end
  end
end
