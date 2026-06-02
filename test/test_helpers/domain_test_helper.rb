module DomainTestHelper
  def create_organization(api_key: "test-api-key-#{SecureRandom.hex(4)}", status: "active")
    Organization.create!(
      name: "Fintech #{SecureRandom.hex(4)}",
      slug: "fintech-#{SecureRandom.hex(8)}",
      status:,
      api_key_digest: Organization.digest_api_key(api_key),
      rate_limit_per_minute: 120
    ).tap do |organization|
      Accounts::BootstrapOrganizationLedger.call(organization:, currency: "BRL")
    end
  end

  def create_customer(organization:, external_id: "customer-#{SecureRandom.hex(4)}", document_number: SecureRandom.hex(8))
    organization.customers.create!(
      external_id:,
      legal_name: "Customer #{external_id}",
      document_kind: "cpf",
      document_number:,
      metadata: {}
    )
  end

  def create_wallet(organization:, customer: nil, external_id: "wallet-#{SecureRandom.hex(4)}")
    Wallets::Creator.call(
      organization:,
      customer: customer || create_customer(organization:),
      external_id:,
      currency: "BRL",
      metadata: {}
    )
  end

  def fund_wallet(organization:, wallet:, external_id: "funding-#{SecureRandom.hex(4)}", amount_cents: 10_000)
    Fundings::Create.call(
      organization:,
      wallet:,
      external_id:,
      amount_cents:,
      idempotency_key: external_id
    )
  end

  def create_pix_payment(organization:, wallet:, external_id: "pix-#{SecureRandom.hex(4)}", amount_cents: 1_000, pix_key: "receiver-#{SecureRandom.hex(4)}@example.com")
    PixPayments::Create.call(
      organization:,
      wallet:,
      external_id:,
      pix_key:,
      receiver_name: "Receiver",
      amount_cents:,
      idempotency_key: external_id
    )
  end

  def build_pix_payment(organization:, wallet:, status:, external_id: "pix-#{SecureRandom.hex(4)}")
    organization.pix_payments.create!(
      wallet:,
      external_id:,
      pix_key: "receiver-#{SecureRandom.hex(4)}@example.com",
      receiver_name: "Receiver",
      amount_cents: 1_000,
      currency: "BRL",
      status:,
      risk_score: 10,
      idempotency_key: external_id,
      metadata: {}
    )
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include DomainTestHelper
end
