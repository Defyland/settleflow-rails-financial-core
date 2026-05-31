require "test_helper"

class ApiAuthenticationTest < ActionDispatch::IntegrationTest
  test "rejects requests without an API key" do
    get "/v1/customers", headers: { "Accept" => "application/json" }

    assert_response :unauthorized
    assert_equal "authentication_failed", json_body.dig("error", "code")
  end

  test "isolates resources by organization" do
    api_key = "tenant-one-key"
    organization = create_organization(api_key:)
    other_customer = create_customer(organization: create_organization(api_key: "tenant-two-key"))

    get "/v1/customers/#{other_customer.public_id}", headers: auth_headers(api_key)

    assert_response :not_found
    assert_equal "not_found", json_body.dig("error", "code")
    assert_equal 404, organization.audit_logs.last.metadata["status"]
  end
end
