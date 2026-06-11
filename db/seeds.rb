local_seed_environment = Rails.env.development? || Rails.env.test?
unless local_seed_environment || ENV["SETTLEFLOW_ALLOW_PRODUCTION_SEEDS"] == "true"
  abort "Refusing to run demo seeds outside development/test without SETTLEFLOW_ALLOW_PRODUCTION_SEEDS=true"
end

seed_secret = lambda do |name, length: 32|
  value = ENV[name].presence
  next value if value.present?

  raise "#{name} must be set outside development/test" unless local_seed_environment

  SecureRandom.base58(length)
end

demo_api_key = seed_secret.call("SETTLEFLOW_DEMO_API_KEY")
demo_api_key = "sfk_demo_#{demo_api_key}" unless demo_api_key.match?(/\Asfk_[^_]+_.+\z/)
demo_key_prefix = demo_api_key.split("_", 3).second
legacy_seed_api_key = seed_secret.call("SETTLEFLOW_LEGACY_ORG_API_KEY")

organization = Organization.find_or_create_by!(slug: "demo-fintech") do |org|
  org.name = "Demo Fintech"
  org.api_key_digest = Organization.digest_api_key(legacy_seed_api_key)
  org.rate_limit_per_minute = 120
end

demo_credential = organization.api_credentials.find_or_initialize_by(name: "seed demo API credential")
demo_credential.assign_attributes(
  key_prefix: demo_key_prefix,
  key_digest: ApiCredential.digest(demo_api_key),
  scopes: ApiCredential::DEFAULT_SCOPES,
  expires_at: nil,
  revoked_at: nil
)
demo_credential.save!

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

operator_email = ENV.fetch("SETTLEFLOW_OPERATOR_EMAIL", "ops@settleflow.local")
operator_password = seed_secret.call("SETTLEFLOW_OPERATOR_PASSWORD", length: 24)
operator_user = User.find_or_initialize_by(email_address: operator_email)
operator_user_was_new = operator_user.new_record?
operator_user.password = operator_password if operator_user_was_new
operator_user.role = ENV.fetch("SETTLEFLOW_OPERATOR_ROLE", "admin")
operator_user.save!

if Rails.env.development?
  puts "Seeded #{organization.name}. Development API credential: #{demo_api_key}"
  puts "Operator user: #{operator_email}"
  puts "Operator password: #{operator_password}" if operator_user_was_new
end
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
