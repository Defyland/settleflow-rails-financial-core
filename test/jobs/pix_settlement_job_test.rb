require "test_helper"

class PixSettlementJobTest < ActiveJob::TestCase
  test "settles approved Pix payments" do
    organization = create_organization
    wallet = create_wallet(organization:)
    fund_wallet(organization:, wallet:, external_id: "job-funding", amount_cents: 10_000)
    pix_payment = create_pix_payment(
      organization:,
      wallet:,
      external_id: "pix-job",
      pix_key: "receiver@example.com",
      amount_cents: 2_000
    )

    PixSettlementJob.perform_now(pix_payment.id)

    assert pix_payment.reload.settled?
  end
end
