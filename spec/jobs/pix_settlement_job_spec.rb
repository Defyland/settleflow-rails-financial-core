require "rails_helper"

RSpec.describe PixSettlementJob do
  it "settles approved Pix payments" do
    organization = create(:organization)
    wallet = create(:wallet, organization:)
    Fundings::Create.call(organization:, wallet:, external_id: "job-funding", amount_cents: 10_000)
    pix_payment = PixPayments::Create.call(
      organization:,
      wallet:,
      external_id: "pix-job",
      pix_key: "receiver@example.com",
      receiver_name: "Receiver",
      amount_cents: 2_000
    )

    described_class.perform_now(pix_payment.id)

    expect(pix_payment.reload).to be_settled
  end
end
