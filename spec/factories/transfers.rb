FactoryBot.define do
  factory :transfer do
    organization
    source_wallet { association(:wallet, organization:) }
    destination_wallet { association(:wallet, organization:) }
    sequence(:external_id) { |n| "transfer-#{n}" }
    amount_cents { 1_000 }
    currency { "BRL" }
    status { "posted" }
    metadata { {} }
  end
end
