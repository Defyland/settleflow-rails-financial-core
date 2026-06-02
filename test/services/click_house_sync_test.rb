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
    @event = @organization.outbox_events.create!(
      aggregate_type: "Funding",
      aggregate_id: 123,
      event_type: "wallet.funded",
      status: "published",
      published_at: Time.current,
      payload_sha256: "a" * 64,
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

  test "rejects processed event drift before inserting analytics rows" do
    @organization.processed_events.create!(
      outbox_event: @event,
      processor: "clickhouse_financial_events",
      event_id: @event.public_id,
      event_type: @event.event_type,
      payload_sha256: "b" * 64,
      status: "failed"
    )
    client = FakeClient.new(events: [])

    assert_raises(Errors::ValidationError) do
      Analytics::ClickHouseSync.call(outbox_event: @event, client:)
    end

    assert_empty client.events
    assert @organization.processed_events.find_by!(event_id: @event.public_id).failed?
  end

  test "rejects unpublished outbox events" do
    @event.update!(status: "pending", published_at: nil)

    assert_raises(Errors::ValidationError) do
      Analytics::ClickHouseSync.call(outbox_event: @event, client: FakeClient.new(events: []))
    end
  end
end
