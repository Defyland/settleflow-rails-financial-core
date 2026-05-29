require "rails_helper"

RSpec.describe "API authentication", type: :request do
  it "rejects requests without an API key" do
    get "/v1/customers", headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
    expect(json_body.dig("error", "code")).to eq("authentication_failed")
  end

  it "isolates resources by organization" do
    api_key = "tenant-one-key"
    organization = create(:organization, api_key:)
    other_customer = create(:customer, organization: create(:organization, api_key: "tenant-two-key"))

    get "/v1/customers/#{other_customer.public_id}", headers: auth_headers(api_key)

    expect(response).to have_http_status(:not_found)
    expect(json_body.dig("error", "code")).to eq("not_found")
    expect(organization.audit_logs.last.metadata["status"]).to eq(404)
  end
end
