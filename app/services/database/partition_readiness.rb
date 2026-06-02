module Database
  class PartitionReadiness
    Check = Data.define(:table, :partitioned, :partition_strategy)
    TABLES = Database::PartitionPlan::TABLES.freeze

    def self.call(...)
      new(...).call
    end

    def call
      rows = ActiveRecord::Base.connection.exec_query(<<~SQL.squish)
        SELECT
          c.relname AS table_name,
          pt.partstrat AS partition_strategy
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        LEFT JOIN pg_partitioned_table pt ON pt.partrelid = c.oid
        WHERE n.nspname = 'public'
        ORDER BY c.relname
      SQL
      rows_by_table = rows.select { |row| row.fetch("table_name").in?(TABLES) }.index_by { |row| row.fetch("table_name") }

      TABLES.map do |table|
        row = rows_by_table[table]
        strategy = row&.fetch("partition_strategy")
        Check.new(
          table:,
          partitioned: strategy.present?,
          partition_strategy: strategy
        )
      end
    end
  end
end
