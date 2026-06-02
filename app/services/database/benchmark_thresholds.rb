module Database
  class BenchmarkThresholds
    Check = Data.define(:name, :ok, :details)
    REQUIRED_EXPLAIN_NAMES = %i[
      audit_chain_tail
      outbox_publishable
      reconciliation_accounts
      wallet_statement
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(result:, max_execution_time_ms: ENV.fetch("DATABASE_BENCHMARK_MAX_QUERY_MS", 250).to_f)
      @result = result
      @max_execution_time_ms = max_execution_time_ms
    end

    def call
      [
        consistency_check,
        count_check,
        critical_plan_check,
        wallet_statement_index_check,
        outbox_publishable_index_check,
        temp_spill_check,
        execution_time_check
      ]
    end

    private

    attr_reader :result, :max_execution_time_ms

    def consistency_check
      failed = result.consistency.reject { |check| check.fetch(:ok) }
      Check.new(name: :consistency_green, ok: failed.empty?, details: { failed: failed.map { |check| check.fetch(:name) } })
    end

    def count_check
      expected_wallets = result.organizations * result.wallets
      expected_journal_entries = result.organizations * (result.wallets + result.entries)
      expected_ledger_lines = expected_journal_entries * 2
      counts = result.counts
      ok = counts.fetch(:wallets) >= expected_wallets &&
        counts.fetch(:journal_entries) >= expected_journal_entries &&
        counts.fetch(:ledger_lines) >= expected_ledger_lines

      Check.new(
        name: :minimum_dataset_counts,
        ok:,
        details: {
          expected_wallets:,
          actual_wallets: counts.fetch(:wallets),
          expected_journal_entries:,
          actual_journal_entries: counts.fetch(:journal_entries),
          expected_ledger_lines:,
          actual_ledger_lines: counts.fetch(:ledger_lines)
        }
      )
    end

    def critical_plan_check
      missing = REQUIRED_EXPLAIN_NAMES - explains_by_name.keys
      Check.new(name: :critical_plans_present, ok: missing.empty?, details: { missing: })
    end

    def wallet_statement_index_check
      plan = parsed_plan(:wallet_statement)
      ok = plan.present? && plan_nodes(plan).any? do |node|
        node.fetch("Node Type", "").include?("Index") &&
          (node.fetch("Relation Name", "") == "ledger_lines" || node.fetch("Index Name", "").include?("ledger_lines"))
      end
      Check.new(name: :wallet_statement_uses_ledger_index, ok:, details: {})
    end

    def outbox_publishable_index_check
      return Check.new(name: :outbox_publishable_uses_status_index, ok: true, details: { skipped: "outbox_events < 100" }) if result.counts.fetch(:outbox_events).to_i < 100

      plan = parsed_plan(:outbox_publishable)
      ok = plan.present? && plan_nodes(plan).any? do |node|
        node.fetch("Node Type", "").include?("Index") &&
          (node.fetch("Relation Name", "") == "outbox_events" || node.fetch("Index Name", "").include?("outbox"))
      end
      Check.new(name: :outbox_publishable_uses_status_index, ok:, details: {})
    end

    def temp_spill_check
      spills = explains_by_name.filter_map do |name, explain|
        total_temp_written = plan_nodes(JSON.parse(explain.fetch(:plan))).sum { |node| node.fetch("Temp Written Blocks", 0).to_i }
        [ name, total_temp_written ] if total_temp_written.positive?
      end.to_h
      Check.new(name: :no_temp_file_spills, ok: spills.empty?, details: { spills: })
    end

    def execution_time_check
      slow = explains_by_name.filter_map do |name, explain|
        execution_time = JSON.parse(explain.fetch(:plan)).first.fetch("Execution Time").to_f
        [ name, execution_time ] if execution_time > max_execution_time_ms
      end.to_h
      Check.new(name: :query_execution_time, ok: slow.empty?, details: { max_execution_time_ms:, slow: })
    end

    def explains_by_name
      @explains_by_name ||= result.explains.index_by { |explain| explain.fetch(:name).to_sym }
    end

    def parsed_plan(name)
      explain = explains_by_name[name]
      JSON.parse(explain.fetch(:plan)) if explain.present?
    end

    def plan_nodes(plan)
      plan.flat_map { |entry| flatten_plan(entry.fetch("Plan")) }
    end

    def flatten_plan(node)
      [ node ] + Array(node["Plans"]).flat_map { |child| flatten_plan(child) }
    end
  end
end
