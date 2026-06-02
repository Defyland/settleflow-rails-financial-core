require "test_helper"

class FinancialExtensionsApiTest < ActionDispatch::IntegrationTest
  setup do
    @api_key = "financial-extensions-key"
    @organization = create_organization(api_key: @api_key)
    @source_wallet = create_wallet(organization: @organization, external_id: "api-extension-source")
    @destination_one = create_wallet(organization: @organization, external_id: "api-extension-destination-one")
    @destination_two = create_wallet(organization: @organization, external_id: "api-extension-destination-two")
    fund_wallet(organization: @organization, wallet: @source_wallet, external_id: "api-extension-funding", amount_cents: 30_000)
  end

  test "executes financial extensions and blocks MED terminal resolution without ops approval" do
    post_json "/v1/split_payments", {
      source_wallet_id: @source_wallet.public_id,
      external_id: "api-split-001",
      entries: [
        { destination_wallet_id: @destination_one.public_id, amount_cents: 2_000 },
        { destination_wallet_id: @destination_two.public_id, amount_cents: 3_000 }
      ],
      memo: "api split"
    }, headers: auth_headers(@api_key, "Idempotency-Key" => "api-split-001")

    assert_response :created
    assert_equal "posted", json_body.dig("data", "status")
    assert_equal 25_000, @source_wallet.balance_projection.reload.available_cents

    post_json "/v1/payouts", {
      wallet_id: @source_wallet.public_id,
      external_id: "api-payout-001",
      amount_cents: 4_000,
      settlement_delay_days: 0,
      destination_reference: "bank-account-001"
    }, headers: auth_headers(@api_key, "Idempotency-Key" => "api-payout-001")

    assert_response :created
    payout_id = json_body.dig("data", "id")
    assert_equal "scheduled", json_body.dig("data", "status")
    assert_equal 21_000, @source_wallet.balance_projection.reload.available_cents

    post_json "/v1/payouts/#{payout_id}/settle", {}, headers: auth_headers(@api_key, "Idempotency-Key" => "api-payout-settle-001")

    assert_response :ok
    assert_equal "settled", json_body.dig("data", "status")

    post_json "/v1/payouts", {
      wallet_id: @source_wallet.public_id,
      external_id: "api-payout-early-001",
      amount_cents: 1_000,
      settlement_delay_days: 2,
      destination_reference: "bank-account-early-001"
    }, headers: auth_headers(@api_key, "Idempotency-Key" => "api-payout-early-001")

    assert_response :created
    early_payout_id = json_body.dig("data", "id")

    post_json "/v1/payouts/#{early_payout_id}/settle?force=true", {}, headers: auth_headers(@api_key, "Idempotency-Key" => "api-payout-early-settle-001")

    assert_response :forbidden
    assert_equal "authorization_failed", json_body.dig("error", "code")
    assert_equal "scheduled", @organization.payouts.find_by!(public_id: early_payout_id).status

    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @source_wallet,
      external_id: "api-refund-pix",
      pix_key: "api-refund@example.com",
      amount_cents: 5_000
    )
    PixPayments::Settle.call(organization: @organization, pix_payment:)

    post_json "/v1/refunds", {
      pix_payment_id: pix_payment.public_id,
      external_id: "api-refund-001",
      amount_cents: 2_000,
      reason: "customer_request"
    }, headers: auth_headers(@api_key, "Idempotency-Key" => "api-refund-001")

    assert_response :created
    assert_equal "settled", json_body.dig("data", "status")

    med_pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @source_wallet,
      external_id: "api-med-pix",
      pix_key: "api-med@example.com",
      amount_cents: 4_000
    )
    PixPayments::Settle.call(organization: @organization, pix_payment: med_pix_payment)

    post_json "/v1/med_cases", {
      pix_payment_id: med_pix_payment.public_id,
      external_id: "api-med-001",
      amount_cents: 3_000,
      reason: "fraud_report"
    }, headers: auth_headers(@api_key, "Idempotency-Key" => "api-med-001")

    assert_response :created
    med_case_id = json_body.dig("data", "id")
    assert_equal "opened", json_body.dig("data", "status")

    post_json "/v1/med_cases/#{med_case_id}/accept", {}, headers: auth_headers(@api_key, "Idempotency-Key" => "api-med-accept-001")

    assert_response :forbidden
    assert_equal "authorization_failed", json_body.dig("error", "code")
    assert_equal "opened", @organization.med_cases.find_by!(public_id: med_case_id).status
    assert AuditLog.hash_chain_intact?
  end
end
