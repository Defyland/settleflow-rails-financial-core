require "test_helper"

class OpenapiContractTest < ActiveSupport::TestCase
  test "idempotency key is required for documented mutating commands" do
    assert_equal true, openapi.dig("components", "parameters", "IdempotencyKey", "required")

    post_operations.each do |path, spec|
      next unless spec.fetch("parameters", []).any? { |parameter| parameter["$ref"] == "#/components/parameters/IdempotencyKey" }

      responses = spec.fetch("responses")
      assert_includes responses, "400", "#{path} must document idempotency_key_required"
      assert_includes responses, "409", "#{path} must document idempotency conflicts"
    end
  end

  test "public MED terminal resolution documents forbidden runtime behavior" do
    %w[/v1/med_cases/{id}/accept /v1/med_cases/{id}/reject].each do |path|
      responses = openapi.fetch("paths").fetch(path).fetch("post").fetch("responses")

      assert_not_includes responses, "200"
      assert_includes responses, "403"
    end
  end

  private

  def openapi
    @openapi ||= YAML.load_file(Rails.root.join("openapi.yaml"))
  end

  def post_operations
    openapi.fetch("paths").filter_map do |path, operations|
      post = operations["post"]
      [ path, post ] if post
    end
  end
end
