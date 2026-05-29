require "rails_helper"

RSpec.describe "Idempotency", type: :request do
  let(:api_key) { "idempotency-key" }
  let!(:organization) { create(:organization, api_key:) }

  it "replays the first response for the same key and request hash" do
    headers = auth_headers(api_key, "Idempotency-Key" => "idem-customer-001")
    payload = {
      external_id: "customer-idem",
      legal_name: "Idempotent Customer",
      document_kind: "cpf",
      document_number: "12345678901"
    }

    post_json "/v1/customers", payload, headers: headers
    first_id = json_body.dig("data", "id")

    post_json "/v1/customers", payload, headers: headers

    expect(response).to have_http_status(:created)
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    expect(json_body.dig("data", "id")).to eq(first_id)
    expect(organization.customers.where(external_id: "customer-idem").count).to eq(1)
  end

  it "rejects key reuse with a different request body" do
    headers = auth_headers(api_key, "Idempotency-Key" => "idem-conflict-001")
    base_payload = {
      external_id: "customer-conflict",
      legal_name: "Original",
      document_kind: "cpf",
      document_number: "12345678902"
    }

    post_json "/v1/customers", base_payload, headers: headers
    post_json "/v1/customers", base_payload.merge(legal_name: "Changed"), headers: headers

    expect(response).to have_http_status(:conflict)
    expect(json_body.dig("error", "code")).to eq("idempotency_conflict")
  end
end
