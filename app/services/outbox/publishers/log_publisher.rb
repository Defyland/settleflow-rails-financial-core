module Outbox
  module Publishers
    class LogPublisher
      def publish(envelope)
        Rails.logger.info({ event: "outbox.published", outbox: envelope }.to_json)
        Outbox::DeliveryResult.new(
          adapter: "log",
          destination: "rails.log",
          message_id: envelope.fetch(:id)
        )
      end
    end
  end
end
