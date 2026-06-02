require "test_helper"

class ClickHouseEventMapperTest < ActiveSupport::TestCase
  test "formats timestamps for ClickHouse DateTime64 JSONEachRow parsing" do
    organization = create_organization
    event = organization.outbox_events.create!(
      aggregate_type: "Funding",
      aggregate_id: 123,
      event_type: "wallet.funded",
      status: "published",
      published_at: Time.current,
      payload_sha256: "a" * 64,
      payload: { amount_cents: 1_000 },
      created_at: Time.utc(2026, 6, 2, 15, 10, 11, 123456)
    )

    row = Analytics::ClickHouseEventMapper.call(outbox_event: event)

    assert_equal "2026-06-02 15:10:11.123456", row.fetch(:occurred_at)
    assert_match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{6}\z/, row.fetch(:synced_at))
  end
end
