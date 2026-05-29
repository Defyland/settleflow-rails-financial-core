FactoryBot.define do
  factory :pix_payment do
    organization
    wallet { association(:wallet, organization:) }
    sequence(:external_id) { |n| "pix-#{n}" }
    pix_key { "receiver#{SecureRandom.hex(2)}@example.com" }
    receiver_name { Faker::Name.name }
    amount_cents { 1_000 }
    currency { "BRL" }
    status { "created" }
    risk_score { 10 }
    metadata { {} }
  end
end
