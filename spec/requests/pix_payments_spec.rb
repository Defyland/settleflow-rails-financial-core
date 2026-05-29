require "rails_helper"

RSpec.describe "Pix payments API", type: :request do
  let(:api_key) { "pix-api-key" }
  let!(:organization) { create(:organization, api_key:) }
  let!(:customer) { create(:customer, organization:) }
  let!(:wallet) { create(:wallet, organization:, customer:) }

  before do
    Fundings::Create.call(organization:, wallet:, external_id: "pix-api-funding", amount_cents: 15_000)
  end

  it "creates a low-risk Pix payment and exposes ledger entries" do
    post_json "/v1/pix_payments", {
      wallet_id: wallet.public_id,
      external_id: "pix-api-1",
      pix_key: "receiver@example.com",
      receiver_name: "Receiver",
      amount_cents: 4_500
    }, headers: auth_headers(api_key, "Idempotency-Key" => "pix-api-1")

    expect(response).to have_http_status(:created)
    expect(json_body.dig("data", "status")).to eq("approved")
    expect(json_body.dig("data", "risk_score")).to be < 70

    get "/v1/ledger_entries", headers: auth_headers(api_key)
    event_types = json_body.fetch("data").map { |entry| entry.fetch("event_type") }
    expect(event_types).to include("pix.payment.approved", "wallet.funded")
  end

  it "rejects overdrawn low-risk Pix payments" do
    post_json "/v1/pix_payments", {
      wallet_id: wallet.public_id,
      external_id: "pix-api-overdraw",
      pix_key: "receiver2@example.com",
      receiver_name: "Receiver",
      amount_cents: 20_000
    }, headers: auth_headers(api_key, "Idempotency-Key" => "pix-api-overdraw")

    expect(response).to have_http_status(:unprocessable_content)
    expect(json_body.dig("error", "code")).to eq("insufficient_funds")
  end
end
