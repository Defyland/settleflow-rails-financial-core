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
end
