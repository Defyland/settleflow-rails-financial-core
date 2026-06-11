module Wallets
  class Creator
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, customer:, external_id:, currency: "BRL", metadata: {})
      @organization = organization
      @customer = customer
      @external_id = external_id
      @currency = currency
      @metadata = metadata || {}
    end

    def call
      raise Errors::ValidationError.new("Customer belongs to another organization") if customer.organization_id != organization.id
      FinancialLifecycle::StatusGuard.ensure_customer_active!(customer, role: :wallet_owner)

      ActiveRecord::Base.transaction do
        wallet = organization.wallets.create!(
          customer:,
          external_id:,
          currency:,
          metadata:
        )
        wallet.ledger_accounts.create!(
          organization:,
          code: "WALLET:#{wallet.public_id}:#{currency}",
          name: "Customer wallet liability #{wallet.public_id}",
          account_type: "liability",
          normal_balance: "credit",
          currency:
        )
        wallet.create_balance_projection!(
          organization:,
          currency:,
          available_cents: 0,
          pending_cents: 0,
          blocked_cents: 0
        )
        wallet
      end
    end

    private

    attr_reader :organization, :customer, :external_id, :currency, :metadata
  end
end
