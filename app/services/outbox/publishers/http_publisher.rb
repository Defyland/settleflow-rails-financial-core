require "net/http"
require "openssl"

module Outbox
  module Publishers
    class HttpPublisher
      DEFAULT_OPEN_TIMEOUT_SECONDS = 2
      DEFAULT_READ_TIMEOUT_SECONDS = 5

      class DeliveryError < StandardError
        attr_reader :code, :body

        def initialize(response)
          @code = response.code
          @body = safe_body(response)
          super("outbox webhook failed with HTTP #{code}")
        end

        private

        def safe_body(response)
          response.body if response.respond_to?(:body)
        rescue IOError
          nil
        end
      end

      def initialize(
        url,
        secret: ENV["OUTBOX_WEBHOOK_SECRET"],
        open_timeout: ENV.fetch("OUTBOX_HTTP_OPEN_TIMEOUT", DEFAULT_OPEN_TIMEOUT_SECONDS).to_f,
        read_timeout: ENV.fetch("OUTBOX_HTTP_READ_TIMEOUT", DEFAULT_READ_TIMEOUT_SECONDS).to_f
      )
        @uri = URI(url)
        @secret = secret
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def publish(envelope)
        request = Net::HTTP::Post.new(uri)
        body = JSON.generate(envelope)
        request["Content-Type"] = "application/json"
        request["Idempotency-Key"] = envelope.fetch(:id)
        request["X-SettleFlow-Event-ID"] = envelope.fetch(:id)
        request["X-SettleFlow-Signature"] = signature(body) if secret.present?
        request.body = body

        response = Net::HTTP.start(
          uri.hostname,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout:,
          read_timeout:
        ) do |http|
          http.request(request)
        end
        raise DeliveryError, response unless response.is_a?(Net::HTTPSuccess)

        Outbox::DeliveryResult.new(
          adapter: "http",
          destination: uri.to_s,
          message_id: response["X-Message-ID"].presence || envelope.fetch(:id)
        )
      end

      private

      attr_reader :uri, :secret, :open_timeout, :read_timeout

      def signature(body)
        "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, body)}"
      end
    end
  end
end
