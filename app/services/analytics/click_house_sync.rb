module Analytics
  class ClickHouseSync
    PROCESSOR = ProcessedEvent::PROCESSORS.fetch(:clickhouse_financial_events)

    def self.call(...)
      new(...).call
    end

    def initialize(outbox_event:, client: nil)
      @outbox_event = outbox_event
      @client = client
    end

    def call
      raise Errors::ValidationError.new("Only published outbox events can be synced to ClickHouse") unless outbox_event.published?
      return unless client_available?

      processed_event = find_or_create_processed_event
      processed_event.with_lock do
        if processed_event.processed?
          processed_event
        else
          client.insert_financial_event!(Analytics::ClickHouseEventMapper.call(outbox_event:))
          processed_event.update!(
            status: "processed",
            processed_at: Time.current,
            error_class: nil,
            last_error: nil
          )
          processed_event
        end
      end
    rescue StandardError => e
      mark_failed(e)
      raise
    end

    private

    attr_reader :outbox_event

    def client
      @client ||= Analytics::ClickHouseClient.new
    end

    def client_available?
      @client.present? || Analytics::ClickHouseClient.configured?
    end

    def find_or_create_processed_event
      envelope = Outbox::Publisher.envelope_for(outbox_event)
      outbox_event.organization.processed_events.find_or_create_by!(
        processor: PROCESSOR,
        event_id: outbox_event.public_id
      ) do |processed_event|
        processed_event.outbox_event = outbox_event
        processed_event.event_type = outbox_event.event_type
        processed_event.payload_sha256 = Outbox::Publisher.payload_sha256(envelope)
        processed_event.status = "processing"
      end
    end

    def mark_failed(error)
      return unless outbox_event&.persisted?

      processed_event = find_or_create_processed_event
      processed_event.update!(
        status: "failed",
        error_class: error.class.name,
        last_error: error.message
      )
    rescue StandardError
      nil
    end
  end
end
