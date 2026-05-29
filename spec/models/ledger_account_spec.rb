require "rails_helper"

RSpec.describe LedgerAccount do
  it "calculates balance according to the normal balance side" do
    organization = create(:organization)
    wallet = create(:wallet, organization:)

    Fundings::Create.call(
      organization:,
      wallet:,
      external_id: "ledger-account-funding",
      amount_cents: 8_000
    )

    expect(wallet.liability_account.balance_cents).to eq(8_000)
    expect(Ledger::AccountLocator.platform_cash(organization:, currency: "BRL").balance_cents).to eq(8_000)
  end
end
