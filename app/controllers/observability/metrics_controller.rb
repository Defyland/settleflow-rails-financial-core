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

      if token.blank?
        return unless Rails.env.production?

        # Production must configure a metrics credential. Failing closed here
        # prevents serving metrics by comparing against an empty "Bearer " token.
        render json: { error: { code: "metrics_unavailable", message: "Metrics authentication is not configured" } },
          status: :service_unavailable
        return
      end

      expected = "Bearer #{token}"
      supplied = request.authorization.to_s
      return if supplied.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(supplied, expected)

      render json: { error: { code: "authentication_failed", message: "Metrics authentication failed" } },
        status: :unauthorized
    end
  end
end
