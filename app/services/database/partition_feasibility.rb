module Database
  class PartitionFeasibility
    Candidate = Data.define(:table, :partition_key, :strategy)
    Finding = Data.define(:code, :severity, :message, :details) do
      def to_h
        {
          code: code.to_s,
          severity: severity.to_s,
          message:,
          details:
        }
      end
    end
    Check = Data.define(:table, :partition_key, :strategy, :ready, :blockers, :warnings) do
      def to_h
        {
          table:,
          partition_key:,
          strategy:,
          ready:,
          blockers: blockers.map(&:to_h),
          warnings: warnings.map(&:to_h)
        }
      end
    end

    CANDIDATES = [
      Candidate.new(table: "journal_entries", partition_key: "occurred_at", strategy: "monthly_range"),
      Candidate.new(table: "ledger_lines", partition_key: "created_at", strategy: "monthly_range"),
      Candidate.new(table: "audit_logs", partition_key: "created_at", strategy: "monthly_range"),
      Candidate.new(table: "reconciliation_runs", partition_key: "statement_date", strategy: "monthly_range"),
      Candidate.new(table: "reconciliation_rows", partition_key: "occurred_on", strategy: "monthly_range")
    ].freeze

    def self.call(...)
      new(...).call
    end

    def call
      CANDIDATES.map do |candidate|
        blockers = table_blockers(candidate)
        warnings = table_warnings(candidate)

        Check.new(
          table: candidate.table,
          partition_key: candidate.partition_key,
          strategy: candidate.strategy,
          ready: blockers.empty?,
          blockers:,
          warnings:
        )
      end
    end

    private

    def table_blockers(candidate)
      [
        *partition_key_blockers(candidate),
        *unique_index_blockers(candidate),
        *inbound_foreign_key_blockers(candidate)
      ]
    end

    def table_warnings(candidate)
      return [] unless table_columns.key?(candidate.table)
      return [] if indexes.fetch(candidate.table, []).any? { |index| index.columns.include?(candidate.partition_key) }

      [
        Finding.new(
          code: :missing_partition_key_index,
          severity: :warning,
          message: "table has no current index that includes the intended partition key",
          details: {
            table: candidate.table,
            partition_key: candidate.partition_key
          }
        )
      ]
    end

    def partition_key_blockers(candidate)
      columns = table_columns[candidate.table]
      return [ missing_table(candidate) ] unless columns
      return [ missing_partition_key(candidate) ] unless columns.key?(candidate.partition_key)
      return [] if columns.fetch(candidate.partition_key)

      [
        Finding.new(
          code: :nullable_partition_key,
          severity: :blocker,
          message: "partition key must be NOT NULL before financial range partitioning",
          details: {
            table: candidate.table,
            partition_key: candidate.partition_key
          }
        )
      ]
    end

    def unique_index_blockers(candidate)
      indexes.fetch(candidate.table, []).filter_map do |index|
        next unless index.unique?
        next if index.columns.include?(candidate.partition_key)

        Finding.new(
          code: index.primary? ? :primary_key_missing_partition_key : :unique_index_missing_partition_key,
          severity: :blocker,
          message: "PostgreSQL partitioned-table uniqueness must include every partition key column",
          details: {
            table: candidate.table,
            index_name: index.name,
            columns: index.columns,
            partition_key: candidate.partition_key,
            partial: index.partial?,
            predicate: index.predicate
          }
        )
      end
    end

    def inbound_foreign_key_blockers(candidate)
      foreign_keys.filter_map do |foreign_key|
        next unless foreign_key.target_table == candidate.table
        next if foreign_key.target_columns.include?(candidate.partition_key)

        Finding.new(
          code: :foreign_key_references_without_partition_key,
          severity: :blocker,
          message: "foreign key references this table without the intended partition key",
          details: {
            constraint_name: foreign_key.name,
            source_table: foreign_key.source_table,
            source_columns: foreign_key.source_columns,
            target_table: foreign_key.target_table,
            target_columns: foreign_key.target_columns,
            partition_key: candidate.partition_key
          }
        )
      end
    end

    def missing_table(candidate)
      Finding.new(
        code: :missing_table,
        severity: :blocker,
        message: "candidate table does not exist in public schema",
        details: {
          table: candidate.table
        }
      )
    end

    def missing_partition_key(candidate)
      Finding.new(
        code: :missing_partition_key,
        severity: :blocker,
        message: "candidate table does not have the intended partition key",
        details: {
          table: candidate.table,
          partition_key: candidate.partition_key
        }
      )
    end

    Index = Data.define(:table, :name, :unique, :primary, :partial, :predicate, :columns) do
      def unique?
        unique
      end

      def primary?
        primary
      end

      def partial?
        partial
      end
    end

    ForeignKey = Data.define(:name, :source_table, :source_columns, :target_table, :target_columns)

    def table_columns
      @table_columns ||= column_rows.each_with_object({}) do |row, result|
        result[row.fetch("table_name")] ||= {}
        result[row.fetch("table_name")][row.fetch("column_name")] = row.fetch("not_null")
      end
    end

    def indexes
      @indexes ||= index_rows.each_with_object({}) do |row, result|
        result[row.fetch("table_name")] ||= []
        result[row.fetch("table_name")] << Index.new(
          table: row.fetch("table_name"),
          name: row.fetch("index_name"),
          unique: row.fetch("unique"),
          primary: row.fetch("primary"),
          partial: row.fetch("partial"),
          predicate: row["predicate"],
          columns: normalize_pg_array(row.fetch("columns"))
        )
      end
    end

    def foreign_keys
      @foreign_keys ||= foreign_key_rows.map do |row|
        ForeignKey.new(
          name: row.fetch("constraint_name"),
          source_table: row.fetch("source_table"),
          source_columns: normalize_pg_array(row.fetch("source_columns")),
          target_table: row.fetch("target_table"),
          target_columns: normalize_pg_array(row.fetch("target_columns"))
        )
      end
    end

    def column_rows
      connection.exec_query(<<~SQL.squish)
        SELECT
          c.relname AS table_name,
          a.attname AS column_name,
          a.attnotnull AS not_null
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_attribute a ON a.attrelid = c.oid
        WHERE n.nspname = 'public'
          AND c.relkind IN ('r', 'p')
          AND a.attnum > 0
          AND a.attisdropped = false
        ORDER BY c.relname, a.attnum
      SQL
    end

    def index_rows
      connection.exec_query(<<~SQL.squish)
        SELECT
          c.relname AS table_name,
          i.relname AS index_name,
          ix.indisunique AS unique,
          ix.indisprimary AS primary,
          ix.indpred IS NOT NULL AS partial,
          pg_get_expr(ix.indpred, ix.indrelid) AS predicate,
          COALESCE(array_remove(array_agg(a.attname ORDER BY keys.ordinality), NULL), ARRAY[]::text[]) AS columns
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_index ix ON ix.indrelid = c.oid
        JOIN pg_class i ON i.oid = ix.indexrelid
        LEFT JOIN LATERAL unnest(ix.indkey) WITH ORDINALITY AS keys(attnum, ordinality) ON true
        LEFT JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = keys.attnum
        WHERE n.nspname = 'public'
          AND c.relkind IN ('r', 'p')
        GROUP BY c.relname, i.relname, ix.indisunique, ix.indisprimary, ix.indpred, ix.indrelid
        ORDER BY c.relname, i.relname
      SQL
    end

    def foreign_key_rows
      connection.exec_query(<<~SQL.squish)
        SELECT
          con.conname AS constraint_name,
          source.relname AS source_table,
          target.relname AS target_table,
          ARRAY(
            SELECT source_attr.attname
            FROM unnest(con.conkey) WITH ORDINALITY AS source_keys(attnum, ordinality)
            JOIN pg_attribute source_attr ON source_attr.attrelid = source.oid
              AND source_attr.attnum = source_keys.attnum
            ORDER BY source_keys.ordinality
          ) AS source_columns,
          ARRAY(
            SELECT target_attr.attname
            FROM unnest(con.confkey) WITH ORDINALITY AS target_keys(attnum, ordinality)
            JOIN pg_attribute target_attr ON target_attr.attrelid = target.oid
              AND target_attr.attnum = target_keys.attnum
            ORDER BY target_keys.ordinality
          ) AS target_columns
        FROM pg_constraint con
        JOIN pg_class source ON source.oid = con.conrelid
        JOIN pg_namespace source_namespace ON source_namespace.oid = source.relnamespace
        JOIN pg_class target ON target.oid = con.confrelid
        JOIN pg_namespace target_namespace ON target_namespace.oid = target.relnamespace
        WHERE con.contype = 'f'
          AND source_namespace.nspname = 'public'
          AND target_namespace.nspname = 'public'
        ORDER BY target.relname, source.relname, con.conname
      SQL
    end

    def normalize_pg_array(value)
      return value if value.is_a?(Array)

      value.to_s.delete_prefix("{").delete_suffix("}").split(",").reject(&:blank?)
    end

    def connection
      ActiveRecord::Base.connection
    end
  end
end
