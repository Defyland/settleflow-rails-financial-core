require "rack/attack"

class Rack::Attack
  throttle("api/ip", limit: ENV.fetch("RATE_LIMIT_PER_MINUTE", 120).to_i, period: 60.seconds) do |request|
    request.ip if request.path.start_with?("/v1")
  end

  throttle("api/key", limit: ENV.fetch("RATE_LIMIT_PER_API_KEY_PER_MINUTE", 240).to_i, period: 60.seconds) do |request|
    request.get_header("HTTP_X_API_KEY").presence if request.path.start_with?("/v1")
  end

  self.throttled_responder = lambda do |request|
    retry_after = (request.env["rack.attack.match_data"] || {})[:period] || 60
    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [
        {
          error: {
            code: "rate_limited",
            message: "Too many requests",
            details: { retry_after_seconds: retry_after },
            request_id: request.env["action_dispatch.request_id"],
            correlation_id: request.get_header("HTTP_X_CORRELATION_ID") || request.env["action_dispatch.request_id"]
          }
        }.to_json
      ]
    ]
  end
end

Rails.application.config.middleware.use Rack::Attack
