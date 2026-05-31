require "test_helper"

class OrganizationTest < ActiveSupport::TestCase
  test "authenticates active organizations by API key digest" do
    organization = create_organization(api_key: "secret-key")

    assert_equal organization, Organization.authenticate_api_key("secret-key")
    assert_nil Organization.authenticate_api_key("wrong-key")
  end

  test "does not authenticate suspended organizations" do
    create_organization(api_key: "secret-key", status: "suspended")

    assert_nil Organization.authenticate_api_key("secret-key")
  end
end
