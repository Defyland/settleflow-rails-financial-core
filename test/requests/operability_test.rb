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
