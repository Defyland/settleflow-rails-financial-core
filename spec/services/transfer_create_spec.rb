require "rails_helper"

RSpec.describe Transfers::Create do
  let(:organization) { create(:organization) }
  let(:source_wallet) { create(:wallet, organization:) }
  let(:destination_wallet) { create(:wallet, organization:) }

  before do
    Fundings::Create.call(
      organization:,
      wallet: source_wallet,
      external_id: "transfer-funding",
      amount_cents: 5_000
    )
  end

  it "moves money between wallets through liability ledger accounts" do
    transfer = described_class.call(
      organization:,
      source_wallet:,
      destination_wallet:,
      external_id: "transfer-001",
      amount_cents: 1_750,
      memo: "invoice split"
    )

    expect(transfer).to be_posted
    expect(transfer.journal_entry).to be_balanced
    expect(source_wallet.balance_projection.reload.available_cents).to eq(3_250)
    expect(destination_wallet.balance_projection.reload.available_cents).to eq(1_750)
    expect(OutboxEvent.where(event_type: "wallet.transfer.posted")).to exist
  end

  it "does not persist a transfer when available balance is insufficient" do
    expect do
      described_class.call(
        organization:,
        source_wallet:,
        destination_wallet:,
        external_id: "transfer-002",
        amount_cents: 7_500
      )
    end.to raise_error(Errors::InsufficientFunds)

    expect(Transfer.where(external_id: "transfer-002")).to be_empty
    expect(source_wallet.balance_projection.reload.available_cents).to eq(5_000)
  end
end
