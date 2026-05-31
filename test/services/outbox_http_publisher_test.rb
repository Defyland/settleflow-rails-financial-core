require "test_helper"

class OutboxHttpPublisherTest < ActiveSupport::TestCase
  test "posts signed JSON envelopes with bounded HTTP timeouts" do
    envelope = { id: "evt-123", event_type: "wallet.created", payload: { wallet_id: "wlt-123" } }
    requests = []
    response = Net::HTTPOK.new("1.1", "202", "Accepted")
    response["X-Message-ID"] = "provider-msg-123"
    start_args = []
    http = Object.new
    http.define_singleton_method(:request) do |request|
      requests << request
      response
    end

    starter = lambda do |hostname, port, use_ssl:, open_timeout:, read_timeout:, &block|
      start_args << {
        hostname:,
        port:,
        use_ssl:,
        open_timeout:,
        read_timeout:
      }
      block.call(http)
    end

    with_net_http_start(starter) do
      result = Outbox::Publishers::HttpPublisher.new(
        "https://events.example.test/outbox",
        secret: "webhook-secret",
        open_timeout: 1.5,
        read_timeout: 3.5
      ).publish(envelope)

      assert_equal "http", result.adapter
      assert_equal "https://events.example.test/outbox", result.destination
      assert_equal "provider-msg-123", result.message_id
    end

    request = requests.fetch(0)
    start_options = start_args.fetch(0)
    expected_body = JSON.generate(envelope)
    signature_digest = OpenSSL::HMAC.hexdigest("SHA256", "webhook-secret", expected_body)
    expected_signature = "sha256=#{signature_digest}"

    assert_equal "events.example.test", start_options.fetch(:hostname)
    assert_equal 443, start_options.fetch(:port)
    assert_equal true, start_options.fetch(:use_ssl)
    assert_equal 1.5, start_options.fetch(:open_timeout)
    assert_equal 3.5, start_options.fetch(:read_timeout)
    assert_equal "application/json", request["Content-Type"]
    assert_equal "evt-123", request["Idempotency-Key"]
    assert_equal "evt-123", request["X-SettleFlow-Event-ID"]
    assert_equal expected_signature, request["X-SettleFlow-Signature"]
    assert_equal expected_body, request.body
  end

  test "raises delivery errors for non-success responses" do
    response = Net::HTTPInternalServerError.new("1.1", "500", "Internal Server Error")
    http = Object.new
    http.define_singleton_method(:request) { |_request| response }
    starter = ->(_hostname, _port, **_options, &block) { block.call(http) }

    error = assert_raises(Outbox::Publishers::HttpPublisher::DeliveryError) do
      with_net_http_start(starter) do
        Outbox::Publishers::HttpPublisher.new("https://events.example.test/outbox").publish(
          id: "evt-500",
          event_type: "wallet.created",
          payload: {}
        )
      end
    end

    assert_equal "500", error.code
  end

  private

  def with_net_http_start(starter)
    original_start = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start, &starter)
    yield
  ensure
    Net::HTTP.define_singleton_method(:start) do |*args, **kwargs, &block|
      original_start.call(*args, **kwargs, &block)
    end
  end
end
