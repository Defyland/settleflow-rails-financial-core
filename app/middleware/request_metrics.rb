class RequestMetrics
  def initialize(app)
    @app = app
  end

  def call(env)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status = 500
    response = @app.call(env)
    status = response[0].to_i
    response
  ensure
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    request = ActionDispatch::Request.new(env)
    path = normalize_path(request)

    if defined?(SETTLEFLOW_HTTP_REQUESTS)
      SETTLEFLOW_HTTP_REQUESTS.increment(labels: { method: request.request_method, path:, status: status.to_s })
      SETTLEFLOW_HTTP_DURATION.observe(duration, labels: { method: request.request_method, path: })
    end

    Rails.logger.info(
      {
        event: "http_request",
        method: request.request_method,
        path:,
        status:,
        duration_ms: (duration * 1000).round(2),
        request_id: request.request_id,
        correlation_id: request.get_header("HTTP_X_CORRELATION_ID") || request.request_id
      }.to_json
    )
  end

  private

  def normalize_path(request)
    params = request.path_parameters
    return "/#{params[:controller]}##{params[:action]}" if params[:controller].present?

    request.path
  end
end
