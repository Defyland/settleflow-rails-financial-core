require "test_helper"
require "base64"
require "socket"

class ClickHouseClientTest < ActiveSupport::TestCase
  setup do
    @requests = []
    @server = TCPServer.new("127.0.0.1", 0)
    @url = "http://127.0.0.1:#{@server.addr[1]}"
    @thread = Thread.new { accept_requests }
  end

  teardown do
    @server.close
    @thread.join(2)
  end

  test "creates schema with separate DDL requests and analytics rollup" do
    client = Analytics::ClickHouseClient.new(
      url: @url,
      database: "settleflow_test",
      table: "financial_events_test",
      daily_rollup_table: "daily_rollups_test",
      daily_rollup_view: "daily_rollups_mv_test"
    )

    assert client.create_schema!

    queries = @requests.map { |request| request.fetch(:query) }
    assert_equal 4, queries.size
    assert queries.none? { |query| query.include?(";") }, "ClickHouse HTTP requests must not rely on multi-statements"
    assert_equal "CREATE DATABASE IF NOT EXISTS `settleflow_test`", queries.first
    assert_includes queries.second, "CREATE TABLE IF NOT EXISTS `settleflow_test`.`financial_events_test`"
    assert_includes queries.third, "ENGINE = SummingMergeTree"
    assert_includes queries.fourth, "CREATE MATERIALIZED VIEW IF NOT EXISTS `settleflow_test`.`daily_rollups_mv_test`"
    assert_includes queries.fourth, "TO `settleflow_test`.`daily_rollups_test`"
    assert_equal [ "text/plain" ], @requests.map { |request| request.fetch(:content_type) }.uniq
  end

  test "inserts JSONEachRow event with basic auth" do
    client = Analytics::ClickHouseClient.new(
      url: @url,
      database: "settleflow_test",
      table: "financial_events_test",
      username: "analytics_user",
      password: "secret"
    )
    event = {
      event_id: SecureRandom.uuid,
      event_type: "wallet.funded",
      aggregate_type: "Funding",
      aggregate_id: 123,
      organization_id: SecureRandom.uuid,
      payload: JSON.generate(amount_cents: 1_000),
      payload_sha256: "a" * 64,
      occurred_at: Time.current.utc.iso8601(6),
      synced_at: Time.current.utc.iso8601(6)
    }

    assert client.insert_financial_event!(event)

    request = @requests.sole
    assert_equal "INSERT INTO `settleflow_test`.`financial_events_test` FORMAT JSONEachRow", request.fetch(:query)
    assert_equal "#{JSON.generate(event)}\n", request.fetch(:body)
    assert_equal "application/json", request.fetch(:content_type)
    assert_equal "Basic #{Base64.strict_encode64("analytics_user:secret")}", request.fetch(:authorization)
  end

  test "rejects unsafe identifiers from configuration" do
    error = assert_raises(ArgumentError) do
      Analytics::ClickHouseClient.new(url: @url, database: "settleflow; DROP TABLE financial_events")
    end

    assert_match(/plain ClickHouse identifier/, error.message)
  end

  private

  def accept_requests
    loop do
      socket = @server.accept
      capture_request(socket)
    end
  rescue IOError, Errno::EBADF
    nil
  end

  def capture_request(socket)
    request_line = socket.gets
    headers = {}
    while (line = socket.gets)
      break if line == "\r\n"

      key, value = line.split(":", 2)
      headers[key] = value.strip if key && value
    end
    body = headers["Content-Length"].to_i.positive? ? socket.read(headers["Content-Length"].to_i) : nil
    path = request_line.split.fetch(1)
    query = URI.decode_www_form(URI(path).query).to_h.fetch("query")

    @requests << {
      query:,
      body:,
      content_type: headers["Content-Type"],
      authorization: headers["Authorization"]
    }

    socket.write "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOk"
  ensure
    socket.close
  end
end
