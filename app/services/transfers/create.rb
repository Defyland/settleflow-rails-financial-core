module Transfers
  class Create
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, source_wallet:, destination_wallet:, external_id:, amount_cents:, currency: "BRL", idempotency_key: nil, correlation_id: nil, memo: nil, metadata: {})
      @organization = organization
      @source_wallet = source_wallet
      @destination_wallet = destination_wallet
      @external_id = external_id
      @amount_cents = amount_cents.to_i
      @currency = currency
      @idempotency_key = idempotency_key
      @correlation_id = correlation_id
      @memo = memo
      @metadata = metadata || {}
    end

    def call
      validate_wallets!

      ActiveRecord::Base.transaction do
        source_wallet.balance_projection.lock!
        raise Errors::InsufficientFunds.new(details: { available_cents: source_wallet.balance_projection.available_cents, required_cents: amount_cents }) if source_wallet.balance_projection.available_cents < amount_cents

        transfer = organization.transfers.create!(
          source_wallet:,
          destination_wallet:,
          external_id:,
          amount_cents:,
          currency:,
          idempotency_key:,
          correlation_id:,
          memo:,
          metadata:
        )
        journal_entry = Ledger::JournalPoster.call(
          organization:,
          event_type: "wallet.transfer.posted",
          reference: transfer,
          idempotency_key:,
          correlation_id:,
          metadata: { external_id: transfer.external_id },
          lines: [
            { account: source_wallet.liability_account, direction: "debit", amount_cents:, currency: },
            { account: destination_wallet.liability_account, direction: "credit", amount_cents:, currency: }
          ]
        )
        transfer.update!(journal_entry:)
        OutboxEvents::Emit.call(
          organization:,
          aggregate: transfer,
          event_type: "wallet.transfer.posted",
          correlation_id:,
          idempotency_key:,
          payload: {
            transfer_id: transfer.public_id,
            source_wallet_id: source_wallet.public_id,
            destination_wallet_id: destination_wallet.public_id,
            amount_cents:,
            currency:
          }
        )
        transfer
      end
    end

    private

    attr_reader :organization, :source_wallet, :destination_wallet, :external_id, :amount_cents, :currency, :idempotency_key, :correlation_id, :memo, :metadata

    def validate_wallets!
      raise Errors::ValidationError.new("Source wallet belongs to another organization") if source_wallet.organization_id != organization.id
      raise Errors::ValidationError.new("Destination wallet belongs to another organization") if destination_wallet.organization_id != organization.id
      raise Errors::ValidationError.new("Source and destination wallets must be different") if source_wallet.id == destination_wallet.id
      raise Errors::ValidationError.new("Currency mismatch") if source_wallet.currency != currency || destination_wallet.currency != currency
    end
  end
end
