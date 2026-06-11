module Fundings
  class Create
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, wallet:, external_id:, amount_cents:, currency: "BRL", idempotency_key: nil, correlation_id: nil, metadata: {})
      @organization = organization
      @wallet = wallet
      @external_id = external_id
      @amount_cents = amount_cents.to_i
      @currency = currency
      @idempotency_key = idempotency_key
      @correlation_id = correlation_id
      @metadata = metadata || {}
    end

    def call
      raise Errors::IdempotencyKeyRequired if idempotency_key.blank?
      raise Errors::ValidationError.new("Wallet belongs to another organization") if wallet.organization_id != organization.id
      raise Errors::ValidationError.new("Currency mismatch") if wallet.currency != currency
      FinancialLifecycle::StatusGuard.ensure_wallet_active!(wallet, role: :funding)

      ActiveRecord::Base.transaction do
        Accounts::BootstrapOrganizationLedger.call(organization:, currency:)
        funding = organization.fundings.create!(
          wallet:,
          external_id:,
          amount_cents:,
          currency:,
          idempotency_key:,
          correlation_id:,
          metadata:
        )
        journal_entry = Ledger::JournalPoster.call(
          organization:,
          event_type: FinancialContracts::Events::WALLET_FUNDED,
          reference: funding,
          idempotency_key:,
          correlation_id:,
          metadata: { external_id: funding.external_id },
          lines: [
            { account: Ledger::AccountLocator.platform_cash(organization:, currency:), direction: "debit", amount_cents:, currency: },
            { account: wallet.liability_account, direction: "credit", amount_cents:, currency: }
          ]
        )
        funding.update!(journal_entry:)
        OutboxEvents::Emit.call(
          organization:,
          aggregate: funding,
          event_type: FinancialContracts::Events::WALLET_FUNDED,
          correlation_id:,
          idempotency_key:,
          payload: { funding_id: funding.public_id, wallet_id: wallet.public_id, amount_cents:, currency: }
        )
        funding
      end
    end

    private

    attr_reader :organization, :wallet, :external_id, :amount_cents, :currency, :idempotency_key, :correlation_id, :metadata
  end
end
