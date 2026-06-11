require "test_helper"

class SplitPaymentCreateTest < ActiveSupport::TestCase
  setup do
    @organization = create_organization
    @source_wallet = create_wallet(organization: @organization, external_id: "split-source")
    @destination_one = create_wallet(organization: @organization, external_id: "split-destination-one")
    @destination_two = create_wallet(organization: @organization, external_id: "split-destination-two")
    fund_wallet(organization: @organization, wallet: @source_wallet, external_id: "split-funding", amount_cents: 10_000)
  end

  test "posts a multi-destination split as one balanced journal entry" do
    split_payment = SplitPayments::Create.call(
      organization: @organization,
      source_wallet: @source_wallet,
      external_id: "split-001",
      entries: [
        { destination_wallet: @destination_one, amount_cents: 2_000 },
        { destination_wallet: @destination_two, amount_cents: 3_000 }
      ],
      idempotency_key: "split-001",
      correlation_id: "split-corr",
      memo: "merchant split"
    )

    assert split_payment.posted?
    assert_equal 5_000, split_payment.total_amount_cents
    assert_equal 2, split_payment.split_entries.size
    assert split_payment.journal_entry.balanced?
    assert_equal 3, split_payment.journal_entry.ledger_lines.count
    assert_equal 5_000, @source_wallet.balance_projection.reload.available_cents
    assert_equal 2_000, @destination_one.balance_projection.reload.available_cents
    assert_equal 3_000, @destination_two.balance_projection.reload.available_cents
    assert_equal "split.posted", OutboxEvent.last.event_type
    assert_equal "split-corr", OutboxEvent.last.correlation_id
  end

  test "prevents missing idempotency, duplicate destinations, self split, and insufficient funds" do
    assert_raises(Errors::IdempotencyKeyRequired) do
      SplitPayments::Create.call(
        organization: @organization,
        source_wallet: @source_wallet,
        external_id: "split-missing-idem",
        entries: [ { destination_wallet: @destination_one, amount_cents: 1_000 } ]
      )
    end

    assert_raises(Errors::ValidationError) do
      create_split(
        external_id: "split-duplicate-destination",
        entries: [
          { destination_wallet: @destination_one, amount_cents: 1_000 },
          { destination_wallet: @destination_one, amount_cents: 1_000 }
        ]
      )
    end

    assert_raises(Errors::ValidationError) do
      create_split(
        external_id: "split-self",
        entries: [ { destination_wallet: @source_wallet, amount_cents: 1_000 } ]
      )
    end

    assert_raises(Errors::InsufficientFunds) do
      create_split(
        external_id: "split-too-large",
        entries: [ { destination_wallet: @destination_one, amount_cents: 20_000 } ]
      )
    end

    assert_equal 10_000, @source_wallet.balance_projection.reload.available_cents
    assert_empty @organization.split_payments.where(external_id: [ "split-missing-idem", "split-duplicate-destination", "split-self", "split-too-large" ])
  end

  test "rejects split payments with inactive source or destination wallets" do
    @source_wallet.update!(status: "blocked")

    source_error = assert_raises(Errors::ValidationError) do
      create_split(
        external_id: "split-blocked-source",
        entries: [ { destination_wallet: @destination_one, amount_cents: 1_000 } ]
      )
    end
    assert_equal "blocked", source_error.details.fetch(:wallet_status)

    @source_wallet.update!(status: "active")
    @destination_one.update!(status: "closed")

    destination_error = assert_raises(Errors::ValidationError) do
      create_split(
        external_id: "split-closed-destination",
        entries: [ { destination_wallet: @destination_one, amount_cents: 1_000 } ]
      )
    end
    assert_equal "closed", destination_error.details.fetch(:wallet_status)

    assert_empty @organization.split_payments.where(external_id: [ "split-blocked-source", "split-closed-destination" ])
    assert_equal 10_000, @source_wallet.balance_projection.reload.available_cents
    assert_equal 0, @destination_one.balance_projection.reload.available_cents
  end

  private

  def create_split(external_id:, entries:)
    SplitPayments::Create.call(
      organization: @organization,
      source_wallet: @source_wallet,
      external_id:,
      entries:,
      idempotency_key: external_id
    )
  end
end
