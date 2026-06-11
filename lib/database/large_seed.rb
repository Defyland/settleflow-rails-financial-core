module Database
  class LargeSeed
    def self.call(...)
      new(...).call
    end

    def initialize(organizations: 1, wallets: 100, entries: 1_000, currency: "BRL")
      @organizations = organizations.to_i
      @wallets = wallets.to_i
      @entries = entries.to_i
      @currency = currency
    end

    def call
      organizations.times.map do |organization_index|
        seed_organization(organization_index)
      end
    end

    private

    attr_reader :organizations, :wallets, :entries, :currency

    def seed_organization(organization_index)
      organization = create_organization(organization_index)
      created_wallets = create_wallets(organization)
      seed_fundings(organization, created_wallets)
      seed_transfers(organization, created_wallets)
      organization
    end

    def create_organization(index)
      suffix = "#{Time.current.to_i}-#{index}"
      Organization.create!(
        name: "Database Benchmark #{suffix}",
        slug: "database-benchmark-#{suffix}",
        status: "active",
        api_key_digest: Organization.digest_api_key("database-benchmark-key-#{suffix}"),
        rate_limit_per_minute: 10_000
      ).tap do |organization|
        Accounts::BootstrapOrganizationLedger.call(organization:, currency:)
      end
    end

    def create_wallets(organization)
      wallets.times.map do |index|
        customer = organization.customers.create!(
          external_id: "benchmark-customer-#{index}",
          legal_name: "Benchmark Customer #{index}",
          document_kind: "cpf",
          document_number: "bench-#{organization.id}-#{index}",
          metadata: {}
        )
        Wallets::Creator.call(
          organization:,
          customer:,
          external_id: "benchmark-wallet-#{index}",
          currency:,
          metadata: { benchmark: true }
        )
      end
    end

    def seed_fundings(organization, created_wallets)
      created_wallets.each_with_index do |wallet, index|
        Fundings::Create.call(
          organization:,
          wallet:,
          external_id: "benchmark-funding-#{index}",
          amount_cents: 1_000_000,
          currency:,
          idempotency_key: "benchmark-funding-#{index}"
        )
      end
    end

    def seed_transfers(organization, created_wallets)
      entries.times do |index|
        source_wallet = created_wallets[index % created_wallets.size]
        destination_wallet = created_wallets[(index + 1) % created_wallets.size]
        Transfers::Create.call(
          organization:,
          source_wallet:,
          destination_wallet:,
          external_id: "benchmark-transfer-#{index}",
          amount_cents: 100,
          currency:,
          idempotency_key: "benchmark-transfer-#{index}",
          memo: "database benchmark"
        )
      end
    end
  end
end
