require "test_helper"

class FinancialWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    @api_key = "workflow-key"
    @organization = create_organization(api_key: @api_key)
  end

  test "creates customers, wallets, funding, transfers, statements, and reconciliation" do
    customer_one_id = create_customer_via_api("customer-api-1", "11111111111")
    customer_two_id = create_customer_via_api("customer-api-2", "22222222222")
    source_wallet_id = create_wallet_via_api(customer_one_id, "wallet-api-1")
    destination_wallet_id = create_wallet_via_api(customer_two_id, "wallet-api-2")

    post_json "/v1/fundings", {
      wallet_id: source_wallet_id,
      external_id: "funding-api-1",
      amount_cents: 10_000
    }, headers: auth_headers(@api_key, "Idempotency-Key" => "funding-api-1")

    assert_response :created
    assert_equal "posted", json_body.dig("data", "status")

    post_json "/v1/transfers", {
      source_wallet_id:,
      destination_wallet_id:,
      external_id: "transfer-api-1",
      amount_cents: 2_500,
      memo: "shared bill"
    }, headers: auth_headers(@api_key, "Idempotency-Key" => "transfer-api-1")

    assert_response :created
    assert_equal "posted", json_body.dig("data", "status")

    get "/v1/wallets/#{source_wallet_id}/balance", headers: auth_headers(@api_key)
    assert_equal 7_500, json_body.dig("data", "available_cents")

    get "/v1/wallets/#{source_wallet_id}/balance_explanation", headers: auth_headers(@api_key)
    assert_response :ok
    assert_equal 7_500, json_body.dig("data", "projection_available_cents")
    assert_equal 7_500, json_body.dig("data", "ledger_available_cents")
    assert_equal true, json_body.dig("data", "consistent")
    assert_equal [ 10_000, 7_500 ], json_body.dig("data", "recent_lines").map { |line| line.fetch("running_available_cents") }

    get "/v1/wallets/#{destination_wallet_id}/statement", headers: auth_headers(@api_key)
    assert_equal 2_500, json_body.fetch("data").first.fetch("amount_cents")
    assert_equal 2_500, json_body.fetch("data").first.fetch("delta_cents")
    assert_equal 2_500, json_body.fetch("data").first.fetch("running_available_cents")

    post_json "/v1/reconciliation_runs", {
      provider: "bank-sandbox",
      statement_date: "2026-05-29",
      provider_balance_cents: 10_000
    }, headers: auth_headers(@api_key, "Idempotency-Key" => "recon-api-1")

    assert_response :created
    assert_equal "matched", json_body.dig("data", "status")
  end

  test "returns standardized validation errors" do
    post_json "/v1/customers", { external_id: "bad" }, headers: auth_headers(@api_key, "Idempotency-Key" => "bad-customer-validation")

    assert_response 422
    assert_equal "validation_failed", json_body.dig("error", "code")
    assert_includes json_body.dig("error", "details"), "legal_name"
    assert_includes json_body.dig("error", "details"), "document_kind"
    assert_includes json_body.dig("error", "details"), "document_number"
  end

  test "requires idempotency keys for mutating API requests" do
    post_json "/v1/customers", {
      external_id: "missing-idempotency",
      legal_name: "Missing Idempotency",
      document_kind: "cpf",
      document_number: "33333333333"
    }, headers: auth_headers(@api_key)

    assert_response :bad_request
    assert_equal "idempotency_key_required", json_body.dig("error", "code")
    assert_not @organization.customers.exists?(external_id: "missing-idempotency")
  end

  private

  def create_customer_via_api(external_id, document_number)
    post_json "/v1/customers", {
      external_id:,
      legal_name: "Customer #{external_id}",
      document_kind: "cpf",
      document_number:
    }, headers: auth_headers(@api_key, "Idempotency-Key" => external_id)

    assert_response :created
    json_body.dig("data", "id")
  end

  def create_wallet_via_api(customer_id, external_id)
    post_json "/v1/wallets", {
      customer_id:,
      external_id:
    }, headers: auth_headers(@api_key, "Idempotency-Key" => external_id)

    assert_response :created
    json_body.dig("data", "id")
  end
end
