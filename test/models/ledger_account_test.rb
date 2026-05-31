require "test_helper"

class LedgerAccountTest < ActiveSupport::TestCase
  test "calculates balance according to the normal balance side" do
    organization = create_organization
    wallet = create_wallet(organization:)

    fund_wallet(organization:, wallet:, external_id: "ledger-account-funding", amount_cents: 8_000)

    assert_equal 8_000, wallet.liability_account.balance_cents
    assert_equal 8_000, Ledger::AccountLocator.platform_cash(organization:, currency: "BRL").balance_cents
  end
end
