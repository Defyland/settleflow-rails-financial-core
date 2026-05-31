require "test_helper"

class PixPaymentsApiTest < ActionDispatch::IntegrationTest
  setup do
    @api_key = "pix-api-key"
    @organization = create_organization(api_key: @api_key)
    @customer = create_customer(organization: @organization)
    @wallet = create_wallet(organization: @organization, customer: @customer)
    fund_wallet(organization: @organization, wallet: @wallet, external_id: "pix-api-funding", amount_cents: 15_000)
  end

  test "creates a low-risk Pix payment and exposes ledger entries" do
    post_json "/v1/pix_payments", {
      wallet_id: @wallet.public_id,
      external_id: "pix-api-1",
      pix_key: "receiver@example.com",
      receiver_name: "Receiver",
      amount_cents: 4_500
    }, headers: auth_headers(@api_key, "Idempotency-Key" => "pix-api-1")

    assert_response :created
    assert_equal "approved", json_body.dig("data", "status")
    assert_operator json_body.dig("data", "risk_score"), :<, 70

    get "/v1/ledger_entries", headers: auth_headers(@api_key)
    event_types = json_body.fetch("data").map { |entry| entry.fetch("event_type") }
    assert_includes event_types, "pix.payment.approved"
    assert_includes event_types, "wallet.funded"
  end

  test "rejects overdrawn low-risk Pix payments" do
    post_json "/v1/pix_payments", {
      wallet_id: @wallet.public_id,
      external_id: "pix-api-overdraw",
      pix_key: "receiver2@example.com",
      receiver_name: "Receiver",
      amount_cents: 20_000
    }, headers: auth_headers(@api_key, "Idempotency-Key" => "pix-api-overdraw")

    assert_response 422
    assert_equal "insufficient_funds", json_body.dig("error", "code")
  end
end
