require "test_helper"

class ClickHouseSyncTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:events, :failure, keyword_init: true) do
    def insert_financial_event!(event)
      raise failure if failure

      events << event
      true
    end
  end

  setup do
    @organization = create_organization
    @event = create_published_outbox_event(
      aggregate_type: "Funding",
      aggregate_id: 123,
      event_type: "wallet.funded",
      payload: { wallet_id: SecureRandom.uuid, amount_cents: 1_000 }
    )
  end

  test "syncs a published outbox event once and records processed event" do
    client = FakeClient.new(events: [])

    first = Analytics::ClickHouseSync.call(outbox_event: @event, client:)
    second = Analytics::ClickHouseSync.call(outbox_event: @event, client:)

    assert first.processed?
    assert second.processed?
    assert_equal 1, client.events.size
    assert_equal @event.public_id, client.events.first.fetch(:event_id)
    assert_equal 1, @organization.processed_events.where(processor: "clickhouse_financial_events", event_id: @event.public_id).count
  end

  test "marks processed event failed when ClickHouse insert fails" do
    client = FakeClient.new(events: [], failure: RuntimeError.new("clickhouse unavailable"))

    assert_raises(RuntimeError) do
      Analytics::ClickHouseSync.call(outbox_event: @event, client:)
    end

    processed_event = @organization.processed_events.find_by!(event_id: @event.public_id)
    assert processed_event.failed?
    assert_equal "RuntimeError", processed_event.error_class
    assert_equal "clickhouse unavailable", processed_event.last_error
  end

  test "retries a failed processed event without creating duplicate processor evidence" do
    failing_client = FakeClient.new(events: [], failure: RuntimeError.new("clickhouse unavailable"))
    assert_raises(RuntimeError) do
      Analytics::ClickHouseSync.call(outbox_event: @event, client: failing_client)
    end
    failed_processed_event = @organization.processed_events.find_by!(event_id: @event.public_id)
    client = FakeClient.new(events: [])

    retried_processed_event = Analytics::ClickHouseSync.call(outbox_event: @event, client:)

    assert_equal failed_processed_event.id, retried_processed_event.id
    assert retried_processed_event.processed?
    assert_equal 1, client.events.size
    assert_equal 1, @organization.processed_events.where(processor: "clickhouse_financial_events", event_id: @event.public_id).count
  end

  test "rejects unpublished outbox events" do
    event = @organization.outbox_events.create!(
      aggregate_type: "Funding",
      aggregate_id: 123,
      event_type: "wallet.funded",
      payload: { wallet_id: SecureRandom.uuid, amount_cents: 1_000 }
    )

    assert_raises(Errors::ValidationError) do
      Analytics::ClickHouseSync.call(outbox_event: event, client: FakeClient.new(events: []))
    end
  end

  private

  def create_published_outbox_event(**attributes)
    event = @organization.outbox_events.create!(attributes)
    event.claim_for_publish!
    envelope = Outbox::Publisher.envelope_for(event)
    event.publish!(
      Outbox::DeliveryResult.new(adapter: "test", destination: "memory://clickhouse", message_id: "msg-#{event.public_id}"),
      payload_sha256: Outbox::Publisher.payload_sha256(envelope)
    )
    event
  end
end
