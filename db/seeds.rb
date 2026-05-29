demo_api_key = ENV.fetch("SETTLEFLOW_DEMO_API_KEY", "settleflow_dev_key_change_me")

organization = Organization.find_or_create_by!(slug: "demo-fintech") do |org|
  org.name = "Demo Fintech"
  org.api_key_digest = Organization.digest_api_key(demo_api_key)
  org.rate_limit_per_minute = 120
end

Accounts::BootstrapOrganizationLedger.call(organization:, currency: "BRL")

customer = organization.customers.find_or_create_by!(external_id: "customer-demo-001") do |record|
  record.legal_name = "Maria Demo"
  record.document_kind = "cpf"
  record.document_number = "11144477735"
  record.metadata = { segment: "sandbox" }
end

Wallets::Creator.call(
  organization:,
  customer:,
  external_id: "wallet-demo-001",
  currency: "BRL",
  metadata: { purpose: "demo" }
) unless organization.wallets.exists?(external_id: "wallet-demo-001")

puts "Seeded #{organization.name}. Development API key: #{demo_api_key}" if Rails.env.development?
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
