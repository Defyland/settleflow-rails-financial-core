FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "Fintech #{n}" }
    sequence(:slug) { |n| "fintech-#{n}" }
    status { "active" }
    rate_limit_per_minute { 120 }

    transient do
      api_key { "test_api_key_#{SecureRandom.hex(4)}" }
    end

    api_key_digest { Organization.digest_api_key(api_key) }

    after(:create) do |organization|
      Accounts::BootstrapOrganizationLedger.call(organization:, currency: "BRL")
    end
  end
end
