require "test_helper"

class IdempotencyTest < ActionDispatch::IntegrationTest
  setup do
    @api_key = "idempotency-key"
    @organization = create_organization(api_key: @api_key)
  end

  test "replays the first response for the same key and request hash" do
    headers = auth_headers(@api_key, "Idempotency-Key" => "idem-customer-001")
    payload = {
      external_id: "customer-idem",
      legal_name: "Idempotent Customer",
      document_kind: "cpf",
      document_number: "12345678901"
    }

    post_json "/v1/customers", payload, headers: headers
    first_id = json_body.dig("data", "id")

    post_json "/v1/customers", payload, headers: headers

    assert_response :created
    assert_equal "true", response.headers["Idempotency-Replayed"]
    assert_equal first_id, json_body.dig("data", "id")
    assert_equal 1, @organization.customers.where(external_id: "customer-idem").count
  end

  test "rejects key reuse with a different request body" do
    headers = auth_headers(@api_key, "Idempotency-Key" => "idem-conflict-001")
    base_payload = {
      external_id: "customer-conflict",
      legal_name: "Original",
      document_kind: "cpf",
      document_number: "12345678902"
    }

    post_json "/v1/customers", base_payload, headers: headers
    post_json "/v1/customers", base_payload.merge(legal_name: "Changed"), headers: headers

    assert_response :conflict
    assert_equal "idempotency_conflict", json_body.dig("error", "code")
  end
end
