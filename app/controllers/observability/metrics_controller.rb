module Observability
  class MetricsController < ApiController
    before_action :authenticate_metrics!

    def show
      render plain: Prometheus::Client::Formats::Text.marshal(Prometheus::Client.registry),
        content_type: "text/plain; version=0.0.4"
    end

    private

    def authenticate_metrics!
      token = ENV["METRICS_BEARER_TOKEN"].presence
      return if token.blank? && !Rails.env.production?

      expected = "Bearer #{token}"
      supplied = request.authorization.to_s
      unless supplied.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(supplied, expected)
        render json: { error: { code: "authentication_failed", message: "Metrics authentication failed" } },
          status: :unauthorized
      end
    end
  end
end
