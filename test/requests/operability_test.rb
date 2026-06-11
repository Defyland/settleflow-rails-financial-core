require "test_helper"

class OperabilityTest < ActionDispatch::IntegrationTest
  teardown do
    ENV.delete("METRICS_BEARER_TOKEN")
  end

  test "serves readiness without authentication" do
    get "/ready"

    assert_response :ok
    assert_equal "ready", json_body.fetch("status")
  end

  test "readiness failure does not expose database exception details" do
    connection = ActiveRecord::Base.connection
    original_execute = connection.method(:execute)
    connection.define_singleton_method(:execute) { |*args, **kwargs| raise ActiveRecord::ConnectionNotEstablished, "db password leaked" }

    get "/ready"

    assert_response :service_unavailable
    assert_equal "not_ready", json_body.fetch("status")
    assert_equal "failed", json_body.fetch("checks").fetch("database")
    assert_not_includes response.body, "db password leaked"
  ensure
    connection.define_singleton_method(:execute) do |*args, **kwargs, &block|
      original_execute.call(*args, **kwargs, &block)
    end
  end

  test "serves Prometheus metrics without authentication" do
    get "/metrics"

    assert_response :ok
    assert_includes response.body, "settleflow_http_requests_total"
  end

  test "requires metrics bearer token when configured" do
    ENV["METRICS_BEARER_TOKEN"] = "metrics-secret"

    get "/metrics"
    assert_response :unauthorized

    get "/metrics", headers: { "Authorization" => "Bearer metrics-secret" }
    assert_response :ok
  end
end
