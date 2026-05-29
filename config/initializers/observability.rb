require "prometheus/client"
require "prometheus/client/formats/text"
require Rails.root.join("app/middleware/request_metrics")

registry = Prometheus::Client.registry

SETTLEFLOW_HTTP_REQUESTS = registry.get(:settleflow_http_requests_total) ||
  registry.register(
    Prometheus::Client::Counter.new(
      :settleflow_http_requests_total,
      docstring: "Total HTTP requests served by SettleFlow",
      labels: [ :method, :path, :status ]
    )
  )

SETTLEFLOW_HTTP_DURATION = registry.get(:settleflow_http_request_duration_seconds) ||
  registry.register(
    Prometheus::Client::Histogram.new(
      :settleflow_http_request_duration_seconds,
      docstring: "HTTP request duration in seconds",
      labels: [ :method, :path ],
      buckets: [ 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5 ]
    )
  )

begin
  require "opentelemetry/sdk"
  require "opentelemetry/exporter/otlp"
  require "opentelemetry/instrumentation/all"

  if ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present?
    OpenTelemetry::SDK.configure do |config|
      config.service_name = ENV.fetch("OTEL_SERVICE_NAME", "settleflow-rails-financial-core")
      config.use_all
    end
  end
rescue StandardError => e
  Rails.logger.warn({ event: "opentelemetry_setup_failed", error: e.message }.to_json)
end

Rails.application.config.middleware.use RequestMetrics
