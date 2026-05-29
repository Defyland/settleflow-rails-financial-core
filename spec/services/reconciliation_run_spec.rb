require "rails_helper"

RSpec.describe Reconciliation::Run do
  let(:organization) { create(:organization) }
  let(:wallet) { create(:wallet, organization:) }

  it "compares provider balance with the platform cash ledger" do
    Fundings::Create.call(
      organization:,
      wallet:,
      external_id: "recon-funding",
      amount_cents: 12_345
    )

    run = described_class.call(
      organization:,
      provider: "bank-sandbox",
      statement_date: Date.new(2026, 5, 29),
      provider_balance_cents: 12_300
    )

    expect(run).to be_discrepant
    expect(run.ledger_balance_cents).to eq(12_345)
    expect(run.discrepancy_cents).to eq(-45)
  end
end
