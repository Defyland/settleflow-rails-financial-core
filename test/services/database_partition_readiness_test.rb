require "test_helper"

class DatabasePartitionReadinessTest < ActiveSupport::TestCase
  test "reports partition readiness for every candidate table" do
    checks = Database::PartitionReadiness.call

    assert_equal Database::PartitionPlan::TABLES.sort, checks.map(&:table).sort
    checks.each do |check|
      assert_includes [ true, false ], check.partitioned
    end
  end
end
