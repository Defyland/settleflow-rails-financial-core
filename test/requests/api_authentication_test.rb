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

  test "authenticates generated API credentials and records last use" do
    organization = create_organization
    credential, raw_key = ApiCredential.issue!(
      organization:,
      name: "primary integration",
      scopes: %w[v1:read v1:write]
    )

    get "/v1/customers", headers: auth_headers(raw_key)

    assert_response :ok
    assert credential.reload.last_used_at.present?
  end

  test "rejects revoked API credentials" do
    organization = create_organization
    credential, raw_key = ApiCredential.issue!(
      organization:,
      name: "revoked integration",
      scopes: %w[v1:read]
    )
    credential.revoke!

    get "/v1/customers", headers: auth_headers(raw_key)

    assert_response :unauthorized
    assert_equal "authentication_failed", json_body.dig("error", "code")
  end

  test "enforces API credential scopes" do
    organization = create_organization
    _credential, raw_key = ApiCredential.issue!(
      organization:,
      name: "read only integration",
      scopes: %w[v1:read]
    )

    post_json "/v1/customers", {
      external_id: "scope-denied",
      legal_name: "Scope Denied",
      document_kind: "cpf",
      document_number: "99988877766"
    }, headers: auth_headers(raw_key, "Idempotency-Key" => "scope-denied")

    assert_response :forbidden
    assert_equal "authorization_failed", json_body.dig("error", "code")
  end
end
