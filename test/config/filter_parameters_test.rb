require "test_helper"

class FilterParametersTest < ActiveSupport::TestCase
  # Guards the Rails framework log-filtering layer (config.filter_parameters),
  # which is distinct from the application-level Privacy::SensitiveKeys registry.
  test "framework parameter filtering masks PII keys including legal_name" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    filtered = filter.filter(
      "external_id" => "keep-me",
      "legal_name" => "Alice Example",
      "document_number" => "12345678901",
      "pix_key" => "alice@example.com",
      "password" => "supersecret"
    )

    assert_equal "keep-me", filtered["external_id"]
    assert_equal "[FILTERED]", filtered["legal_name"]
    assert_equal "[FILTERED]", filtered["document_number"]
    assert_equal "[FILTERED]", filtered["pix_key"]
    assert_equal "[FILTERED]", filtered["password"]
  end
end
