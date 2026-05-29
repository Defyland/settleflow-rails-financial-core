FactoryBot.define do
  factory :wallet do
    organization
    customer { association(:customer, organization:) }
    sequence(:external_id) { |n| "wallet-#{n}" }
    currency { "BRL" }
    status { "active" }
    metadata { {} }

    after(:create) do |wallet|
      wallet.ledger_accounts.find_or_create_by!(code: "WALLET:#{wallet.public_id}:#{wallet.currency}") do |account|
        account.organization = wallet.organization
        account.name = "Customer wallet liability #{wallet.public_id}"
        account.account_type = "liability"
        account.normal_balance = "credit"
        account.currency = wallet.currency
      end

      wallet.create_balance_projection!(
        organization: wallet.organization,
        currency: wallet.currency
      ) unless wallet.balance_projection
    end
  end
end
