module SplitPayments
  class Create
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, source_wallet:, external_id:, entries:, currency: "BRL", idempotency_key: nil, correlation_id: nil, memo: nil, metadata: {})
      @organization = organization
      @source_wallet = source_wallet
      @external_id = external_id
      @entries = entries
      @currency = currency
      @idempotency_key = idempotency_key
      @correlation_id = correlation_id
      @memo = memo
      @metadata = metadata || {}
    end

    def call
      raise Errors::IdempotencyKeyRequired if idempotency_key.blank?
      normalized_entries = normalize_entries
      validate_wallets!(normalized_entries)

      ActiveRecord::Base.transaction do
        source_wallet.balance_projection.lock!
        raise Errors::InsufficientFunds.new(details: { available_cents: source_wallet.balance_projection.available_cents, required_cents: total_amount_cents(normalized_entries) }) if source_wallet.balance_projection.available_cents < total_amount_cents(normalized_entries)

        split_payment = organization.split_payments.create!(
          source_wallet:,
          external_id:,
          total_amount_cents: total_amount_cents(normalized_entries),
          currency:,
          idempotency_key:,
          correlation_id:,
          memo:,
          metadata:
        )
        normalized_entries.each do |entry|
          split_payment.split_entries.create!(
            organization:,
            destination_wallet: entry.fetch(:destination_wallet),
            amount_cents: entry.fetch(:amount_cents),
            currency:,
            metadata: entry.fetch(:metadata)
          )
        end
        journal_entry = Ledger::JournalPoster.call(
          organization:,
          event_type: FinancialContracts::Events::SPLIT_POSTED,
          reference: split_payment,
          idempotency_key:,
          correlation_id:,
          metadata: { external_id: split_payment.external_id },
          lines: ledger_lines(normalized_entries)
        )
        split_payment.update!(journal_entry:)
        OutboxEvents::Emit.call(
          organization:,
          aggregate: split_payment,
          event_type: FinancialContracts::Events::SPLIT_POSTED,
          correlation_id:,
          idempotency_key:,
          payload: {
            split_payment_id: split_payment.public_id,
            source_wallet_id: source_wallet.public_id,
            total_amount_cents: split_payment.total_amount_cents,
            currency:,
            entries: split_payment.split_entries.includes(:destination_wallet).map do |entry|
              {
                destination_wallet_id: entry.destination_wallet.public_id,
                amount_cents: entry.amount_cents
              }
            end
          }
        )
        split_payment
      end
    end

    private

    attr_reader :organization, :source_wallet, :external_id, :entries, :currency, :idempotency_key, :correlation_id, :memo, :metadata

    def normalize_entries
      raise Errors::ValidationError.new("Split requires at least one destination") if entries.blank?

      entries.map do |entry|
        wallet = entry[:destination_wallet] || entry["destination_wallet"]
        {
          destination_wallet: wallet,
          amount_cents: (entry[:amount_cents] || entry["amount_cents"]).to_i,
          metadata: entry[:metadata] || entry["metadata"] || {}
        }
      end
    end

    def validate_wallets!(normalized_entries)
      raise Errors::ValidationError.new("Source wallet belongs to another organization") if source_wallet.organization_id != organization.id
      raise Errors::ValidationError.new("Currency mismatch") if source_wallet.currency != currency
      raise Errors::ValidationError.new("Split amount must be positive") if total_amount_cents(normalized_entries) <= 0

      destination_ids = normalized_entries.map { |entry| entry.fetch(:destination_wallet)&.id }
      raise Errors::ValidationError.new("Split destinations must be present") if destination_ids.any?(&:blank?)
      raise Errors::ValidationError.new("Split destinations must be unique") if destination_ids.uniq.size != destination_ids.size
      raise Errors::ValidationError.new("Source wallet cannot receive its own split") if destination_ids.include?(source_wallet.id)

      normalized_entries.each do |entry|
        destination_wallet = entry.fetch(:destination_wallet)
        raise Errors::ValidationError.new("Destination wallet belongs to another organization") if destination_wallet.organization_id != organization.id
        raise Errors::ValidationError.new("Currency mismatch") if destination_wallet.currency != currency
        raise Errors::ValidationError.new("Split entry amount must be positive") if entry.fetch(:amount_cents) <= 0
      end
    end

    def total_amount_cents(normalized_entries)
      normalized_entries.sum { |entry| entry.fetch(:amount_cents) }
    end

    def ledger_lines(normalized_entries)
      [
        { account: source_wallet.liability_account, direction: "debit", amount_cents: total_amount_cents(normalized_entries), currency: }
      ] + normalized_entries.map do |entry|
        {
          account: entry.fetch(:destination_wallet).liability_account,
          direction: "credit",
          amount_cents: entry.fetch(:amount_cents),
          currency:,
          metadata: entry.fetch(:metadata)
        }
      end
    end
  end
end
