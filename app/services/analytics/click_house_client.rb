require "json"
require "net/http"

module Analytics
  class ClickHouseClient
    DEFAULT_DATABASE = "settleflow".freeze
    DEFAULT_TABLE = "financial_events".freeze
    DEFAULT_DAILY_ROLLUP_TABLE = "financial_event_daily_rollups".freeze
    DEFAULT_DAILY_ROLLUP_VIEW = "financial_event_daily_rollups_mv".freeze
    IDENTIFIER_PATTERN = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/

    class Error < StandardError; end

    def self.configured?
      ENV["CLICKHOUSE_URL"].present?
    end

    def initialize(
      url: ENV["CLICKHOUSE_URL"],
      database: ENV.fetch("CLICKHOUSE_DATABASE", DEFAULT_DATABASE),
      table: ENV.fetch("CLICKHOUSE_FINANCIAL_EVENTS_TABLE", DEFAULT_TABLE),
      daily_rollup_table: ENV.fetch("CLICKHOUSE_DAILY_ROLLUP_TABLE", DEFAULT_DAILY_ROLLUP_TABLE),
      daily_rollup_view: ENV.fetch("CLICKHOUSE_DAILY_ROLLUP_VIEW", DEFAULT_DAILY_ROLLUP_VIEW),
      username: ENV["CLICKHOUSE_USERNAME"],
      password: ENV["CLICKHOUSE_PASSWORD"]
    )
      raise ArgumentError, "CLICKHOUSE_URL is required" if url.blank?

      @uri = URI(url)
      raise ArgumentError, "CLICKHOUSE_URL must be http or https" unless @uri.is_a?(URI::HTTP)

      @database = validate_identifier!(database, "CLICKHOUSE_DATABASE")
      @table = validate_identifier!(table, "CLICKHOUSE_FINANCIAL_EVENTS_TABLE")
      @daily_rollup_table = validate_identifier!(daily_rollup_table, "CLICKHOUSE_DAILY_ROLLUP_TABLE")
      @daily_rollup_view = validate_identifier!(daily_rollup_view, "CLICKHOUSE_DAILY_ROLLUP_VIEW")
      @username = username
      @password = password
    end

    def insert_financial_event!(event)
      response = request(sql: insert_sql, body: "#{JSON.generate(event)}\n")
      raise Error, "ClickHouse insert failed with HTTP #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      true
    end

    def create_schema!
      [
        create_database_sql,
        create_events_table_sql,
        create_daily_rollup_table_sql,
        create_daily_rollup_view_sql
      ].each do |sql|
        response = request(sql:)
        raise Error, "ClickHouse schema creation failed with HTTP #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)
      end

      true
    end

    private

    attr_reader :uri, :database, :table, :daily_rollup_table, :daily_rollup_view, :username, :password

    def request(sql:, body: nil)
      request_uri = uri.dup
      request_uri.query = URI.encode_www_form(query: sql)
      request = Net::HTTP::Post.new(request_uri)
      request.basic_auth(username, password) if username.present?
      request["Content-Type"] = body.present? ? "application/json" : "text/plain"
      request.body = body if body.present?

      Net::HTTP.start(request_uri.hostname, request_uri.port, use_ssl: request_uri.scheme == "https") do |http|
        http.request(request)
      end
    end

    def insert_sql
      "INSERT INTO #{qualified_table} FORMAT JSONEachRow"
    end

    def qualified_table
      "#{quoted(database)}.#{quoted(table)}"
    end

    def qualified_daily_rollup_table
      "#{quoted(database)}.#{quoted(daily_rollup_table)}"
    end

    def qualified_daily_rollup_view
      "#{quoted(database)}.#{quoted(daily_rollup_view)}"
    end

    def create_database_sql
      "CREATE DATABASE IF NOT EXISTS #{quoted(database)}"
    end

    def create_events_table_sql
      <<~SQL.squish
        CREATE TABLE IF NOT EXISTS #{qualified_table}
        (
          event_id UUID,
          event_type LowCardinality(String),
          aggregate_type LowCardinality(String),
          aggregate_id UInt64,
          organization_id UUID,
          correlation_id String,
          idempotency_key Nullable(String),
          payload String,
          payload_sha256 FixedString(64),
          occurred_at DateTime64(6, 'UTC'),
          synced_at DateTime64(6, 'UTC')
        )
        ENGINE = MergeTree
        PARTITION BY toYYYYMM(occurred_at)
        ORDER BY (organization_id, event_type, occurred_at, event_id)
      SQL
    end

    def create_daily_rollup_table_sql
      <<~SQL.squish
        CREATE TABLE IF NOT EXISTS #{qualified_daily_rollup_table}
        (
          organization_id UUID,
          event_type LowCardinality(String),
          occurred_on Date,
          event_count UInt64,
          amount_cents_sum Int64
        )
        ENGINE = SummingMergeTree
        PARTITION BY toYYYYMM(occurred_on)
        ORDER BY (organization_id, event_type, occurred_on)
      SQL
    end

    def create_daily_rollup_view_sql
      <<~SQL.squish
        CREATE MATERIALIZED VIEW IF NOT EXISTS #{qualified_daily_rollup_view}
        TO #{qualified_daily_rollup_table}
        AS
        SELECT
          organization_id,
          event_type,
          toDate(occurred_at) AS occurred_on,
          count() AS event_count,
          sum(toInt64OrZero(JSONExtractString(payload, 'amount_cents'))) AS amount_cents_sum
        FROM #{qualified_table}
        GROUP BY organization_id, event_type, occurred_on
      SQL
    end

    def validate_identifier!(value, name)
      identifier = value.to_s
      return identifier if identifier.match?(IDENTIFIER_PATTERN)

      raise ArgumentError, "#{name} must be a plain ClickHouse identifier"
    end

    def quoted(identifier)
      "`#{identifier}`"
    end
  end
end
