require "test_helper"

class FundingCreateTest < ActiveSupport::TestCase
  setup do
    @organization = create_organization
    @wallet = create_wallet(organization: @organization)
  end

  test "requires an idempotency key for direct service calls" do
    assert_raises(Errors::IdempotencyKeyRequired) do
      Fundings::Create.call(
        organization: @organization,
        wallet: @wallet,
        external_id: "funding-missing-idempotency",
        amount_cents: 1_000
      )
    end

    assert_empty Funding.where(external_id: "funding-missing-idempotency")
    assert_equal 0, @wallet.balance_projection.reload.available_cents
  end

  test "rejects funding currency that does not match wallet currency" do
    assert_raises(Errors::ValidationError) do
      Fundings::Create.call(
        organization: @organization,
        wallet: @wallet,
        external_id: "funding-currency-mismatch",
        amount_cents: 1_000,
        currency: "USD",
        idempotency_key: "funding-currency-mismatch"
      )
    end

    assert_empty Funding.where(external_id: "funding-currency-mismatch")
    assert_equal 0, @wallet.balance_projection.reload.available_cents
  end

  test "rejects funding into an inactive wallet" do
    @wallet.update!(status: "blocked")

    error = assert_raises(Errors::ValidationError) do
      Fundings::Create.call(
        organization: @organization,
        wallet: @wallet,
        external_id: "funding-blocked-wallet",
        amount_cents: 1_000,
        idempotency_key: "funding-blocked-wallet"
      )
    end

    assert_equal "blocked", error.details.fetch(:wallet_status)
    assert_empty Funding.where(external_id: "funding-blocked-wallet")
    assert_equal 0, @wallet.balance_projection.reload.available_cents
  end
end
