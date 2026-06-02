require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "knows whether the user can operate financial workflows" do
    assert_not User.new(role: "viewer").can_operate?
    assert User.new(role: "operator").can_operate?
    assert User.new(role: "admin").can_operate?
  end

  test "requires stronger operator passwords when setting a password" do
    user = User.new(email_address: "weak@example.com", role: "admin", password: "short")

    assert_not user.valid?
    assert_includes user.errors[:password], "is too short (minimum is 12 characters)"
  end
end
