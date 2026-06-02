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

wallet = organization.wallets.find_by!(external_id: "wallet-demo-001")

Fundings::Create.call(
  organization:,
  wallet:,
  external_id: "funding-demo-001",
  amount_cents: 1_000_000,
  idempotency_key: "seed-funding-demo-001",
  correlation_id: "seed-demo",
  metadata: { channel: "seed" }
) unless organization.fundings.exists?(external_id: "funding-demo-001")

PixPayments::Create.call(
  organization:,
  wallet:,
  external_id: "pix-approved-demo-001",
  pix_key: "supplier@example.com",
  receiver_name: "Fornecedor Demo",
  amount_cents: 42_000,
  idempotency_key: "seed-pix-approved-demo-001",
  correlation_id: "seed-demo",
  metadata: { purpose: "supplier_payment" }
) unless organization.pix_payments.exists?(external_id: "pix-approved-demo-001")

PixPayments::Create.call(
  organization:,
  wallet:,
  external_id: "pix-review-demo-001",
  pix_key: "review@example.com",
  receiver_name: "Recebedor Revisao",
  amount_cents: 600_000,
  idempotency_key: "seed-pix-review-demo-001",
  correlation_id: "seed-demo",
  metadata: { purpose: "manual_review" }
) unless organization.pix_payments.exists?(external_id: "pix-review-demo-001")

Reconciliation::Run.call(
  organization:,
  provider: "demo-bank",
  statement_date: Date.current,
  provider_balance_cents: 975_000,
  correlation_id: "seed-demo",
  metadata: { source: "seed" }
) unless organization.reconciliation_runs.exists?(provider: "demo-bank", statement_date: Date.current)

operator_user = User.find_or_initialize_by(email_address: ENV.fetch("SETTLEFLOW_OPERATOR_EMAIL", "ops@settleflow.local"))
operator_user.password = ENV.fetch("SETTLEFLOW_OPERATOR_PASSWORD", "settleflow-dev-password-123") if operator_user.new_record?
operator_user.role = ENV.fetch("SETTLEFLOW_OPERATOR_ROLE", "admin")
operator_user.save!

puts "Seeded #{organization.name}. Development API key: #{demo_api_key}" if Rails.env.development?
puts "Operator user: #{ENV.fetch("SETTLEFLOW_OPERATOR_EMAIL", "ops@settleflow.local")}" if Rails.env.development?
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
