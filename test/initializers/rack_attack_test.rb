require "test_helper"

class RackAttackTest < ActiveSupport::TestCase
  test "hashes API keys before using them as throttle discriminators" do
    raw_api_key = "tenant-secret-key"
    discriminator = Rack::Attack.api_key_throttle_discriminator(raw_api_key)

    assert_equal OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, raw_api_key), discriminator
    refute_includes discriminator, raw_api_key
  end
end
