module Database
  class MigrationSafetyChecker
    Finding = Data.define(:file, :line, :severity, :message, :evidence)

    HIGH_VOLUME_TABLES = %w[
      audit_logs
      balance_snapshots
      idempotency_keys
      journal_entries
      ledger_lines
      outbox_events
      pix_payments
      processed_events
      reconciliation_runs
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(root: Rails.root)
      @root = Pathname(root)
    end

    def call
      migration_paths.flat_map { |path| scan(path) }
    end

    private

    attr_reader :root

    def migration_paths
      Dir[root.join("db/migrate/*.rb")].sort.map { |path| Pathname(path) }
    end

    def scan(path)
      lines = path.readlines
      content = lines.join
      created_tables = content.scan(/create_table\s+:([a-z_]+)/).flatten
      ddl_transaction_disabled = content.include?("disable_ddl_transaction!")

      lines.each_with_index.filter_map do |line, index|
        statement = lines[index, 8].join(" ")
        table = table_from(statement)
        next unless table.in?(HIGH_VOLUME_TABLES)
        next if created_tables.include?(table)

        finding_for(
          path:,
          line_number: index + 1,
          line:,
          statement:,
          ddl_transaction_disabled:,
          has_validated_check: content.include?("validate_check_constraint :#{table}")
        )
      end
    end

    def finding_for(path:, line_number:, line:, statement:, ddl_transaction_disabled:, has_validated_check:)
      if line.match?(/\badd_index\b/) && !statement.include?("algorithm: :concurrently")
        build_finding(path, line_number, :high, "index on high-volume table must be created concurrently", line)
      elsif line.match?(/\badd_index\b/) && statement.include?("algorithm: :concurrently") && !ddl_transaction_disabled
        build_finding(path, line_number, :high, "concurrent index migration must disable DDL transactions", line)
      elsif line.match?(/\badd_reference\b/) && statement.exclude?("index: false") && statement.exclude?("algorithm: :concurrently")
        build_finding(path, line_number, :high, "reference on high-volume table must use a concurrent index or index: false", line)
      elsif line.match?(/\badd_foreign_key\b/) && statement.exclude?("validate: false")
        build_finding(path, line_number, :medium, "foreign key on high-volume table should be added NOT VALID then validated", line)
      elsif line.match?(/\badd_check_constraint\b/) && statement.exclude?("validate: false")
        build_finding(path, line_number, :medium, "check constraint on high-volume table should be added NOT VALID then validated", line)
      elsif line.match?(/\bchange_column_null\b/) && !has_validated_check
        build_finding(path, line_number, :medium, "NOT NULL change on high-volume table needs validated-check evidence or a lock window", line)
      elsif line.match?(/CREATE\s+(UNIQUE\s+)?INDEX/i) && !line.match?(/CONCURRENTLY/i)
        build_finding(path, line_number, :high, "raw CREATE INDEX on high-volume table must use CONCURRENTLY", line)
      end
    end

    def table_from(statement)
      statement.match(/\b(?:add_index|add_reference|add_foreign_key|add_check_constraint|change_column_null)\s+:([a-z_]+)/)&.captures&.first ||
        statement.match(/\b(?:ON|ALTER TABLE)\s+(?:public\.)?([a-z_]+)/i)&.captures&.first
    end

    def build_finding(path, line_number, severity, message, evidence)
      Finding.new(
        file: path.relative_path_from(root).to_s,
        line: line_number,
        severity:,
        message:,
        evidence: evidence.strip
      )
    end
  end
end
