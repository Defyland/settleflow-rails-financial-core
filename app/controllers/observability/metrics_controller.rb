module Observability
  class MetricsController < ApiController
    def show
      render plain: Prometheus::Client::Formats::Text.marshal(Prometheus::Client.registry),
        content_type: "text/plain; version=0.0.4"
    end
  end
end
