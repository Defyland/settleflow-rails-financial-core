require "test_helper"

class CustomerTest < ActiveSupport::TestCase
  test "validates required customer fields" do
    customer = Customer.new

    assert_not customer.valid?
    assert_includes customer.errors[:external_id], "can't be blank"
    assert_includes customer.errors[:legal_name], "can't be blank"
    assert_includes customer.errors[:document_kind], "can't be blank"
  end

  test "validates supported document kinds" do
    organization = create_organization
    customer = create_customer(organization:)

    assert customer.valid?

    customer.document_kind = "passport"
    assert_not customer.valid?
    assert_includes customer.errors[:document_kind], "is not included in the list"
  end
end
