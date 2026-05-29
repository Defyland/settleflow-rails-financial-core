FactoryBot.define do
  factory :customer do
    organization
    sequence(:external_id) { |n| "customer-#{n}" }
    legal_name { Faker::Name.name }
    document_kind { "cpf" }
    sequence(:document_number) { |n| "0000000#{n.to_s.rjust(4, '0')}" }
    status { "active" }
    metadata { {} }
  end
end
