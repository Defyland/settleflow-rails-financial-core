require "test_helper"

class WalletCreatorTest < ActiveSupport::TestCase
  test "rejects wallet creation for an inactive customer" do
    organization = create_organization
    customer = create_customer(organization:)
    customer.update!(status: "blocked")

    error = assert_raises(Errors::ValidationError) do
      Wallets::Creator.call(
        organization:,
        customer:,
        external_id: "wallet-blocked-customer",
        currency: "BRL"
      )
    end

    assert_equal "blocked", error.details.fetch(:customer_status)
    assert_empty organization.wallets.where(external_id: "wallet-blocked-customer")
  end
end
