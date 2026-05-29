FactoryBot.define do
  factory :funding do
    organization
    wallet { association(:wallet, organization:) }
    sequence(:external_id) { |n| "funding-#{n}" }
    amount_cents { 10_000 }
    currency { "BRL" }
    status { "posted" }
    metadata { {} }
  end
end
