require "test_helper"

class TransferCreateTest < ActiveSupport::TestCase
  setup do
    @organization = create_organization
    @source_wallet = create_wallet(organization: @organization)
    @destination_wallet = create_wallet(organization: @organization)
    fund_wallet(
      organization: @organization,
      wallet: @source_wallet,
      external_id: "transfer-funding",
      amount_cents: 5_000
    )
  end

  test "moves money between wallets through liability ledger accounts" do
    transfer = Transfers::Create.call(
      organization: @organization,
      source_wallet: @source_wallet,
      destination_wallet: @destination_wallet,
      external_id: "transfer-001",
      amount_cents: 1_750,
      idempotency_key: "transfer-001",
      memo: "invoice split"
    )

    assert transfer.posted?
    assert transfer.journal_entry.balanced?
    assert_equal 3_250, @source_wallet.balance_projection.reload.available_cents
    assert_equal 1_750, @destination_wallet.balance_projection.reload.available_cents
    assert OutboxEvent.where(event_type: "wallet.transfer.posted").exists?
  end

  test "does not persist a transfer when available balance is insufficient" do
    assert_raises(Errors::InsufficientFunds) do
      Transfers::Create.call(
        organization: @organization,
        source_wallet: @source_wallet,
        destination_wallet: @destination_wallet,
        external_id: "transfer-002",
        amount_cents: 7_500,
        idempotency_key: "transfer-002"
      )
    end

    assert_empty Transfer.where(external_id: "transfer-002")
    assert_equal 5_000, @source_wallet.balance_projection.reload.available_cents
  end

  test "requires an idempotency key for direct service calls" do
    assert_raises(Errors::IdempotencyKeyRequired) do
      Transfers::Create.call(
        organization: @organization,
        source_wallet: @source_wallet,
        destination_wallet: @destination_wallet,
        external_id: "transfer-missing-idempotency",
        amount_cents: 1_000
      )
    end

    assert_empty Transfer.where(external_id: "transfer-missing-idempotency")
  end
end
