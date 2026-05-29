require "rails_helper"

RSpec.describe "Pix payment lifecycle" do
  let(:organization) { create(:organization) }
  let(:wallet) { create(:wallet, organization:) }

  before do
    Fundings::Create.call(
      organization:,
      wallet:,
      external_id: "pix-funding",
      amount_cents: 20_000
    )
  end

  it "approves low-risk payments, debits the wallet, and enqueues settlement" do
    pix_payment = PixPayments::Create.call(
      organization:,
      wallet:,
      external_id: "pix-001",
      pix_key: "receiver@example.com",
      receiver_name: "Receiver",
      amount_cents: 4_000
    )

    expect(pix_payment).to be_approved
    expect(wallet.balance_projection.reload.available_cents).to eq(16_000)
    expect(enqueued_jobs.map { |job| job[:job] }).to include(PixSettlementJob)
  end

  it "settles approved payments through the Pix clearing account" do
    pix_payment = PixPayments::Create.call(
      organization:,
      wallet:,
      external_id: "pix-002",
      pix_key: "receiver2@example.com",
      receiver_name: "Receiver",
      amount_cents: 3_000
    )

    settled = PixPayments::Settle.call(organization:, pix_payment:)

    expect(settled).to be_settled
    expect(settled.settlement_journal_entry).to be_balanced
    expect(Ledger::AccountLocator.pix_clearing(organization:, currency: "BRL").balance_cents).to eq(0)
  end

  it "sends suspicious medium-risk payments to manual review without debiting balance" do
    pix_payment = PixPayments::Create.call(
      organization:,
      wallet:,
      external_id: "pix-003",
      pix_key: "receiver3@example.com",
      receiver_name: "Receiver",
      amount_cents: 600_000
    )

    expect(pix_payment).to be_pending_review
    expect(wallet.balance_projection.reload.available_cents).to eq(20_000)
  end

  it "rejects high-risk payments before ledger mutation" do
    pix_payment = PixPayments::Create.call(
      organization:,
      wallet:,
      external_id: "pix-004",
      pix_key: "blocked@example.com",
      receiver_name: "Receiver",
      amount_cents: 600_000
    )

    expect(pix_payment).to be_rejected
    expect(pix_payment.failure_code).to eq("risk_rejected")
    expect(wallet.balance_projection.reload.available_cents).to eq(20_000)
  end
end
