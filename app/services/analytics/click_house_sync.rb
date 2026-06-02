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
      relation = outbox_event.organization.processed_events
      processed_event = relation.find_by(processor: PROCESSOR, event_id: outbox_event.public_id)
      return validate_processed_event!(processed_event) if processed_event.present?

      validate_processed_event!(
        relation.create!(
          processor: PROCESSOR,
          event_id: outbox_event.public_id,
          outbox_event:,
          event_type: outbox_event.event_type,
          payload_sha256:,
          status: "processing"
        )
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      raise unless recoverable_processed_event_conflict?(e)

      validate_processed_event!(
        outbox_event.organization.processed_events.find_by!(
          processor: PROCESSOR,
          event_id: outbox_event.public_id
        )
      )
    end

    def validate_processed_event!(processed_event)
      unless processed_event.outbox_event_id == outbox_event.id &&
          processed_event.event_type == outbox_event.event_type &&
          processed_event.payload_sha256 == payload_sha256
        raise Errors::ValidationError.new(
          "Processed event does not match outbox event",
          details: {
            processed_event_id: processed_event.public_id,
            outbox_event_id: outbox_event.public_id
          }
        )
      end

      processed_event
    end

    def recoverable_processed_event_conflict?(error)
      return true if error.is_a?(ActiveRecord::RecordNotUnique)
      return false unless error.record.is_a?(ProcessedEvent)

      error.record.errors.added?(:event_id, :taken) ||
        error.record.errors.added?(:outbox_event_id, :taken)
    end

    def payload_sha256
      @payload_sha256 ||= begin
        calculated_payload_sha256 = Outbox::Publisher.payload_sha256(envelope)
        unless outbox_event.payload_sha256 == calculated_payload_sha256
          raise Errors::ValidationError.new(
            "Outbox payload hash does not match the published envelope",
            details: { outbox_event_id: outbox_event.public_id }
          )
        end

        calculated_payload_sha256
      end
    end

    def envelope
      @envelope ||= Outbox::Publisher.envelope_for(outbox_event)
    end

    def mark_failed(error)
      return unless outbox_event&.persisted?

      processed_event = find_or_create_processed_event
      processed_event.update!(
        status: "failed",
        error_class: error.class.name,
        last_error: error.message.presence || error.class.name
      )
    rescue StandardError
      nil
    end
  end
end
