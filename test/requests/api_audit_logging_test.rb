require "test_helper"

class ApiAuditLoggingTest < ActionDispatch::IntegrationTest
  setup do
    @api_key = "audit-api-key"
    @organization = create_organization(api_key: @api_key)
  end

  test "audits successful API requests once with sanitized params" do
    assert_difference -> { @organization.audit_logs.count }, 1 do
      post_json "/v1/customers", {
        external_id: "audit-success-customer",
        legal_name: "Audit Success",
        document_kind: "cpf",
        document_number: "12345678901",
        metadata: { tier: "private" }
      }, headers: auth_headers(@api_key, "Idempotency-Key" => "audit-success-customer")
    end

    assert_response :created

    audit_log = @organization.audit_logs.order(:id).last
    params = audit_log.metadata.fetch("params")

    assert_equal 201, audit_log.metadata.fetch("status")
    assert_nil audit_log.metadata["error_code"]
    assert_equal "audit-success-customer", params.fetch("external_id")
    assert_equal "[FILTERED]", params.fetch("document_number")
    assert_equal "[FILTERED]", params.fetch("metadata")
  end

  test "audits validation errors once with final status and sanitized params" do
    assert_difference -> { @organization.audit_logs.count }, 1 do
      post_json "/v1/customers", {
        external_id: "audit-invalid-customer",
        document_kind: "cpf",
        document_number: "99988877766",
        metadata: { private_note: "do not persist raw" }
      }, headers: auth_headers(@api_key, "Idempotency-Key" => "audit-invalid-customer")
    end

    assert_response 422

    audit_log = @organization.audit_logs.order(:id).last
    params = audit_log.metadata.fetch("params")

    assert_equal 422, audit_log.metadata.fetch("status")
    assert_equal "validation_failed", audit_log.metadata.fetch("error_code")
    assert_equal "audit-invalid-customer", params.fetch("external_id")
    assert_equal "[FILTERED]", params.fetch("document_number")
    assert_equal "[FILTERED]", params.fetch("metadata")
  end

  test "audit write failure does not mask original API error" do
    original_create = AuditLog.method(:create!)
    AuditLog.define_singleton_method(:create!) { |*args, **kwargs| raise "audit store unavailable" }

    post_json "/v1/customers", {
      external_id: "audit-write-failure",
      document_kind: "cpf",
      document_number: "11122233344"
    }, headers: auth_headers(@api_key, "Idempotency-Key" => "audit-write-failure")

    assert_response 422
    assert_equal "validation_failed", json_body.dig("error", "code")
  ensure
    AuditLog.define_singleton_method(:create!) do |*args, **kwargs, &block|
      original_create.call(*args, **kwargs, &block)
    end
  end
end
