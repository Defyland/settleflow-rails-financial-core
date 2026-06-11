require "test_helper"

class PrivacyRedactionTest < ActionDispatch::IntegrationTest
  setup do
    @api_key = "privacy-api-key"
    @organization = create_organization(api_key: @api_key)
  end

  test "customer API responses and idempotency evidence redact PII" do
    post_json "/v1/customers", {
      external_id: "privacy-customer",
      legal_name: "Sensitive Customer",
      document_kind: "cpf",
      document_number: "12345678901",
      metadata: { internal_note: "private" }
    }, headers: auth_headers(@api_key, "Idempotency-Key" => "privacy-customer")

    assert_response :created
    assert_equal "[FILTERED]", json_body.dig("data", "legal_name")
    assert_equal "[FILTERED]:8901", json_body.dig("data", "document_number")
    assert_equal({ "redacted" => true }, json_body.dig("data", "metadata"))
    assert_not_includes response.body, "Sensitive Customer"
    assert_not_includes response.body, "12345678901"
    assert_not_includes response.body, "private"

    stored_body = @organization.idempotency_keys.find_by!(key: "privacy-customer").response_body
    assert_equal "[FILTERED]", stored_body.dig("data", "legal_name")
    assert_equal "[FILTERED]:8901", stored_body.dig("data", "document_number")
    assert_equal({ "redacted" => true }, stored_body.dig("data", "metadata"))
  end

  test "Pix and payout API responses redact payment destination details" do
    wallet = create_wallet(organization: @organization)
    fund_wallet(organization: @organization, wallet:, external_id: "privacy-funding", amount_cents: 20_000)

    post_json "/v1/pix_payments", {
      wallet_id: wallet.public_id,
      external_id: "privacy-pix",
      pix_key: "receiver@example.com",
      receiver_name: "Receiver Private",
      amount_cents: 1_000,
      metadata: { private_note: "pix-private" }
    }, headers: auth_headers(@api_key, "Idempotency-Key" => "privacy-pix")

    assert_response :created
    assert_equal "[FILTERED]:.com", json_body.dig("data", "pix_key")
    assert_equal "[FILTERED]", json_body.dig("data", "receiver_name")
    assert_equal({ "redacted" => true }, json_body.dig("data", "metadata"))
    assert_not_includes response.body, "receiver@example.com"
    assert_not_includes response.body, "Receiver Private"
    assert_not_includes response.body, "pix-private"

    post_json "/v1/payouts", {
      wallet_id: wallet.public_id,
      external_id: "privacy-payout",
      amount_cents: 1_000,
      destination_reference: "bank-account-private-001",
      metadata: { private_note: "payout-private" }
    }, headers: auth_headers(@api_key, "Idempotency-Key" => "privacy-payout")

    assert_response :created
    assert_equal "[FILTERED]:-001", json_body.dig("data", "destination_reference")
    assert_equal({ "redacted" => true }, json_body.dig("data", "metadata"))
    assert_not_includes response.body, "bank-account-private-001"
    assert_not_includes response.body, "payout-private"
  end

  test "ops wallet and Pix pages mask default PII display" do
    operator = User.create!(email_address: "privacy-operator-#{SecureRandom.hex(4)}@example.com", password: "strong-password-123", role: "admin")
    customer = create_customer(organization: @organization, external_id: "privacy-ops-customer", document_number: "44455566677")
    wallet = create_wallet(organization: @organization, customer:, external_id: "privacy-ops-wallet")
    fund_wallet(organization: @organization, wallet:, external_id: "privacy-ops-funding", amount_cents: 5_000)
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet:,
      external_id: "privacy-ops-pix",
      pix_key: "ops-private@example.com",
      amount_cents: 1_000
    )
    sign_in_as(operator)

    get ops_wallet_path(wallet.public_id)
    assert_response :ok
    assert_not_includes response.body, customer.legal_name

    get ops_pix_payment_path(pix_payment.public_id)
    assert_response :ok
    assert_not_includes response.body, "ops-private@example.com"
    assert_not_includes response.body, pix_payment.receiver_name
    assert_includes response.body, "[FILTERED]"
  end
end
