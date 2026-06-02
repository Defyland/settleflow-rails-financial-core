module Database
  class PartitionPlan
    Statement = Data.define(:table, :partition_name, :from, :to, :sql)

    TABLES = [
      "journal_entries",
      "ledger_lines",
      "audit_logs",
      "reconciliation_runs"
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(start_on: Date.current.beginning_of_month, months: 3)
      @start_on = start_on.to_date.beginning_of_month
      @months = months.to_i
    end

    def call
      raise ArgumentError, "months must be positive" unless months.positive?

      month_ranges.flat_map do |from_date, to_date|
        TABLES.map do |table|
          build_statement(table, from_date, to_date)
        end
      end
    end

    def to_sql
      call.map(&:sql).join("\n\n")
    end

    private

    attr_reader :start_on, :months

    def month_ranges
      months.times.map do |offset|
        from_date = start_on.advance(months: offset)
        [ from_date, from_date.next_month ]
      end
    end

    def build_statement(table, from_date, to_date)
      partition_name = "#{table}_y#{from_date.year}m#{from_date.month.to_s.rjust(2, "0")}"
      Statement.new(
        table:,
        partition_name:,
        from: from_date,
        to: to_date,
        sql: <<~SQL.squish
          CREATE TABLE IF NOT EXISTS #{partition_name}
          PARTITION OF #{table}
          FOR VALUES FROM ('#{from_date.iso8601}') TO ('#{to_date.iso8601}');
        SQL
      )
    end
  end
end
