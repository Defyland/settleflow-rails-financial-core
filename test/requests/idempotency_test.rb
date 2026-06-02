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

  test "rejects mutating requests without an idempotency key before side effects" do
    post_json "/v1/customers", {
      external_id: "customer-missing-idem",
      legal_name: "Missing Idempotency",
      document_kind: "cpf",
      document_number: "12345678909"
    }, headers: auth_headers(@api_key)

    assert_response :bad_request
    assert_equal "idempotency_key_required", json_body.dig("error", "code")
    assert_not @organization.customers.exists?(external_id: "customer-missing-idem")
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

  test "rejects key reuse when query parameters change command semantics" do
    wallet = create_wallet(organization: @organization, external_id: "idem-query-wallet")
    fund_wallet(organization: @organization, wallet:, external_id: "idem-query-funding", amount_cents: 10_000)
    payout = Payouts::Create.call(
      organization: @organization,
      wallet:,
      external_id: "idem-query-payout",
      amount_cents: 1_000,
      destination_reference: "query-sensitive-destination",
      settlement_delay_days: 0,
      idempotency_key: "idem-query-payout"
    )
    headers = auth_headers(@api_key, "Idempotency-Key" => "idem-query-settle")

    post_json "/v1/payouts/#{payout.public_id}/settle", {}, headers: headers
    assert_response :ok

    post_json "/v1/payouts/#{payout.public_id}/settle?force=true", {}, headers: headers

    assert_response :conflict
    assert_equal "idempotency_conflict", json_body.dig("error", "code")
    assert_nil response.headers["Idempotency-Replayed"]
  end

  test "rolls back command effects when idempotency response persistence fails" do
    original_update = IdempotencyKey.instance_method(:update!)
    IdempotencyKey.define_method(:update!) do |*args, **kwargs, &block|
      attributes = args.first || kwargs
      raise "idempotency store unavailable" if attributes[:status] == "succeeded"

      original_update.bind_call(self, *args, **kwargs, &block)
    end

    assert_raises(RuntimeError) do
      Idempotency::Runner.call(
        organization: @organization,
        key: "idem-atomicity-001",
        request_method: "POST",
        request_path: "/v1/customers",
        request_hash: "a" * 64
      ) do
        customer = @organization.customers.create!(
          external_id: "atomicity-customer",
          legal_name: "Atomicity Customer",
          document_kind: "cpf",
          document_number: "44455566677",
          metadata: {}
        )
        Idempotency::Response.new(status: 201, body: { data: { id: customer.public_id } }, replayed: false)
      end
    end

    assert_not @organization.customers.exists?(external_id: "atomicity-customer")
  ensure
    IdempotencyKey.define_method(:update!) do |*args, **kwargs, &block|
      original_update.bind_call(self, *args, **kwargs, &block)
    end
  end

  test "allows retry after a stale processing lock" do
    @organization.idempotency_keys.create!(
      key: "idem-stale-processing",
      request_method: "POST",
      request_path: "/v1/customers",
      request_hash: "b" * 64,
      status: "processing",
      locked_at: 30.minutes.ago
    )

    response = Idempotency::Runner.call(
      organization: @organization,
      key: "idem-stale-processing",
      request_method: "POST",
      request_path: "/v1/customers",
      request_hash: "b" * 64
    ) do
      Idempotency::Response.new(status: 201, body: { data: { id: "retried" } }, replayed: false)
    end

    assert_equal 201, response.status
    assert_equal "succeeded", @organization.idempotency_keys.find_by!(key: "idem-stale-processing").status
  end

  test "rejects retry while a fresh request is still processing" do
    @organization.idempotency_keys.create!(
      key: "idem-active-processing",
      request_method: "POST",
      request_path: "/v1/customers",
      request_hash: "c" * 64,
      status: "processing",
      locked_at: Time.current
    )

    assert_raises(Errors::IdempotencyConflict) do
      Idempotency::Runner.call(
        organization: @organization,
        key: "idem-active-processing",
        request_method: "POST",
        request_path: "/v1/customers",
        request_hash: "c" * 64
      ) do
        Idempotency::Response.new(status: 201, body: {}, replayed: false)
      end
    end
  end
end
