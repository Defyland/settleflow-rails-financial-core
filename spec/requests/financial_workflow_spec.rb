require "rails_helper"

RSpec.describe "Financial workflow", type: :request do
  let(:api_key) { "workflow-key" }
  let!(:organization) { create(:organization, api_key:) }

  it "creates customers, wallets, funding, transfers, statements, and reconciliation" do
    customer_one_id = create_customer("customer-api-1", "11111111111")
    customer_two_id = create_customer("customer-api-2", "22222222222")
    source_wallet_id = create_wallet(customer_one_id, "wallet-api-1")
    destination_wallet_id = create_wallet(customer_two_id, "wallet-api-2")

    post_json "/v1/fundings", {
      wallet_id: source_wallet_id,
      external_id: "funding-api-1",
      amount_cents: 10_000
    }, headers: auth_headers(api_key, "Idempotency-Key" => "funding-api-1")

    expect(response).to have_http_status(:created)
    expect(json_body.dig("data", "status")).to eq("posted")

    post_json "/v1/transfers", {
      source_wallet_id:,
      destination_wallet_id:,
      external_id: "transfer-api-1",
      amount_cents: 2_500,
      memo: "shared bill"
    }, headers: auth_headers(api_key, "Idempotency-Key" => "transfer-api-1")

    expect(response).to have_http_status(:created)
    expect(json_body.dig("data", "status")).to eq("posted")

    get "/v1/wallets/#{source_wallet_id}/balance", headers: auth_headers(api_key)
    expect(json_body.dig("data", "available_cents")).to eq(7_500)

    get "/v1/wallets/#{destination_wallet_id}/statement", headers: auth_headers(api_key)
    expect(json_body.fetch("data").first.fetch("amount_cents")).to eq(2_500)

    post_json "/v1/reconciliation_runs", {
      provider: "bank-sandbox",
      statement_date: "2026-05-29",
      provider_balance_cents: 10_000
    }, headers: auth_headers(api_key, "Idempotency-Key" => "recon-api-1")

    expect(response).to have_http_status(:created)
    expect(json_body.dig("data", "status")).to eq("matched")
  end

  it "returns standardized validation errors" do
    post_json "/v1/customers", { external_id: "bad" }, headers: auth_headers(api_key)

    expect(response).to have_http_status(:unprocessable_content)
    expect(json_body.dig("error", "code")).to eq("validation_failed")
    expect(json_body.dig("error", "details")).to include("legal_name", "document_kind", "document_number")
  end

  private

  def create_customer(external_id, document_number)
    post_json "/v1/customers", {
      external_id:,
      legal_name: "Customer #{external_id}",
      document_kind: "cpf",
      document_number:
    }, headers: auth_headers(api_key, "Idempotency-Key" => external_id)

    expect(response).to have_http_status(:created)
    json_body.dig("data", "id")
  end

  def create_wallet(customer_id, external_id)
    post_json "/v1/wallets", {
      customer_id:,
      external_id:
    }, headers: auth_headers(api_key, "Idempotency-Key" => external_id)

    expect(response).to have_http_status(:created)
    json_body.dig("data", "id")
  end
end
