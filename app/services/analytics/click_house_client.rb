require "net/http"

module Analytics
  class ClickHouseClient
    DEFAULT_DATABASE = "settleflow".freeze
    DEFAULT_TABLE = "financial_events".freeze

    class Error < StandardError; end

    def self.configured?
      ENV["CLICKHOUSE_URL"].present?
    end

    def initialize(
      url: ENV["CLICKHOUSE_URL"],
      database: ENV.fetch("CLICKHOUSE_DATABASE", DEFAULT_DATABASE),
      table: ENV.fetch("CLICKHOUSE_FINANCIAL_EVENTS_TABLE", DEFAULT_TABLE),
      username: ENV["CLICKHOUSE_USERNAME"],
      password: ENV["CLICKHOUSE_PASSWORD"]
    )
      raise ArgumentError, "CLICKHOUSE_URL is required" if url.blank?

      @uri = URI(url)
      @database = database
      @table = table
      @username = username
      @password = password
    end

    def insert_financial_event!(event)
      response = request(sql: insert_sql, body: "#{JSON.generate(event)}\n")
      raise Error, "ClickHouse insert failed with HTTP #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      true
    end

    def create_schema!
      response = request(sql: create_schema_sql)
      raise Error, "ClickHouse schema creation failed with HTTP #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      true
    end

    private

    attr_reader :uri, :database, :table, :username, :password

    def request(sql:, body: nil)
      request_uri = uri.dup
      request_uri.query = URI.encode_www_form(query: sql)
      request = Net::HTTP::Post.new(request_uri)
      request.basic_auth(username, password) if username.present?
      request["Content-Type"] = "application/json"
      request.body = body if body.present?

      Net::HTTP.start(request_uri.hostname, request_uri.port, use_ssl: request_uri.scheme == "https") do |http|
        http.request(request)
      end
    end

    def insert_sql
      "INSERT INTO #{qualified_table} FORMAT JSONEachRow"
    end

    def qualified_table
      "#{database}.#{table}"
    end

    def create_schema_sql
      <<~SQL.squish
        CREATE DATABASE IF NOT EXISTS #{database};
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
  end
end
