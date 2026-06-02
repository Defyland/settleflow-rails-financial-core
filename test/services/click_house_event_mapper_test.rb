require "test_helper"

class ClickHouseEventMapperTest < ActiveSupport::TestCase
  test "formats timestamps for ClickHouse DateTime64 JSONEachRow parsing" do
    organization = create_organization
    wallet = create_wallet(organization:)
    event = nil
    travel_to Time.utc(2026, 6, 2, 15, 10, 11, 123456), with_usec: true do
      funding = fund_wallet(
        organization:,
        wallet:,
        external_id: "clickhouse-mapper-funding",
        amount_cents: 1_000
      )
      event = organization.outbox_events.find_by!(
        aggregate_type: "Funding",
        aggregate_id: funding.id,
        event_type: "wallet.funded"
      )
    end
    event.claim_for_publish!
    event.publish!(
      Outbox::DeliveryResult.new(adapter: "test", destination: "memory://clickhouse", message_id: "msg-#{event.public_id}"),
      payload_sha256: Outbox::Publisher.payload_sha256(Outbox::Publisher.envelope_for(event))
    )

    row = Analytics::ClickHouseEventMapper.call(outbox_event: event)

    assert_equal "2026-06-02 15:10:11.123456", row.fetch(:occurred_at)
    assert_match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{6}\z/, row.fetch(:synced_at))
  end
end
