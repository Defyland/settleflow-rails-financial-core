require "test_helper"

class OutboxEventContractTest < ActiveSupport::TestCase
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  test "schema event type enum matches financial contract events" do
    expected = FinancialContracts::Events.constants.map { |name| FinancialContracts::Events.const_get(name) }.sort

    assert_equal expected, event_type_enum.sort
  end

  test "wallet funding outbox envelope matches public contract" do
    organization = create_organization
    wallet = create_wallet(organization:)
    funding = fund_wallet(organization:, wallet:, external_id: "contract-funding", amount_cents: 1_000)
    event = organization.outbox_events.find_by!(aggregate_type: "Funding", aggregate_id: funding.id)

    assert_valid_contract_envelope event
  end

  test "Pix approval outbox envelope matches public contract" do
    organization = create_organization
    wallet = create_wallet(organization:)
    fund_wallet(organization:, wallet:, external_id: "contract-pix-funding", amount_cents: 5_000)
    pix_payment = create_pix_payment(
      organization:,
      wallet:,
      external_id: "contract-pix",
      amount_cents: 1_000
    )
    event = organization.outbox_events.find_by!(aggregate_type: "PixPayment", aggregate_id: pix_payment.id, event_type: "pix.payment.approved")

    assert_valid_contract_envelope event
  end

  test "reconciliation outbox envelope matches public contract" do
    organization = create_organization
    wallet = create_wallet(organization:)
    fund_wallet(organization:, wallet:, external_id: "contract-reconciliation-funding", amount_cents: 2_000)
    run = Reconciliation::Run.call(
      organization:,
      provider: "contract-bank",
      statement_date: Date.current,
      provider_balance_cents: 2_000,
      correlation_id: "contract-reconciliation"
    )
    event = organization.outbox_events.find_by!(aggregate_type: "ReconciliationRun", aggregate_id: run.id)

    assert_valid_contract_envelope event
  end

  private

  def assert_valid_contract_envelope(event)
    envelope = Outbox::Publisher.envelope_for(event).deep_stringify_keys
    schema = event_schema
    properties = schema.fetch("properties")

    assert_empty schema.fetch("required") - envelope.keys
    assert_empty envelope.keys - properties.keys
    assert_match UUID_PATTERN, envelope.fetch("id")
    assert_includes event_type_enum, envelope.fetch("event_type")
    assert_includes properties.dig("aggregate_type", "enum"), envelope.fetch("aggregate_type")
    assert_kind_of Integer, envelope.fetch("aggregate_id")
    assert_match UUID_PATTERN, envelope.fetch("organization_id")
    assert_kind_of Hash, envelope.fetch("payload")
    assert envelope.fetch("payload").present?
    assert Time.iso8601(envelope.fetch("created_at"))
  end

  def event_schema
    @event_schema ||= JSON.parse(Rails.root.join("docs/events/outbox_event.v1.json").read)
  end

  def event_type_enum
    event_schema.dig("properties", "event_type", "enum")
  end
end
