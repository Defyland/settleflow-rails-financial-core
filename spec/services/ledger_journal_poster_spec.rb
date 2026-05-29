require "rails_helper"

RSpec.describe Ledger::JournalPoster do
  let(:organization) { create(:organization) }
  let(:source_wallet) { create(:wallet, organization:) }
  let(:destination_wallet) { create(:wallet, organization:) }

  before do
    Fundings::Create.call(
      organization:,
      wallet: source_wallet,
      external_id: "initial-funding",
      amount_cents: 10_000
    )
  end

  it "posts balanced double-entry lines and updates wallet projections" do
    journal = described_class.call(
      organization:,
      event_type: "test.transfer",
      lines: [
        { account: source_wallet.liability_account, direction: "debit", amount_cents: 2_500, currency: "BRL" },
        { account: destination_wallet.liability_account, direction: "credit", amount_cents: 2_500, currency: "BRL" }
      ]
    )

    expect(journal).to be_balanced
    expect(source_wallet.balance_projection.reload.available_cents).to eq(7_500)
    expect(destination_wallet.balance_projection.reload.available_cents).to eq(2_500)
  end

  it "rejects unbalanced journal entries before persistence" do
    expect do
      described_class.call(
        organization:,
        event_type: "test.bad_entry",
        lines: [
          { account: source_wallet.liability_account, direction: "debit", amount_cents: 2_500, currency: "BRL" },
          { account: destination_wallet.liability_account, direction: "credit", amount_cents: 2_400, currency: "BRL" }
        ]
      )
    end.to raise_error(Errors::ValidationError, /not balanced/)

    expect(JournalEntry.where(event_type: "test.bad_entry")).to be_empty
  end
end
