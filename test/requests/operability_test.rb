require "test_helper"

class OperabilityTest < ActionDispatch::IntegrationTest
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
end
