require "net/http"

module Outbox
  module Publishers
    class HttpPublisher
      def initialize(url)
        @uri = URI(url)
      end

      def publish(envelope)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Idempotency-Key"] = envelope.fetch(:id)
        request.body = JSON.generate(envelope)

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.request(request)
        end
        raise "outbox webhook failed with HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        Outbox::DeliveryResult.new(
          adapter: "http",
          destination: uri.to_s,
          message_id: response["X-Message-ID"].presence || envelope.fetch(:id)
        )
      end

      private

      attr_reader :uri
    end
  end
end
