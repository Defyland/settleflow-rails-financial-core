module Payouts
  class Create < ApplicationService
    def initialize(organization:, wallet:, external_id:, amount_cents:, destination_reference:, currency: "BRL", settlement_delay_days: 1, destination_kind: "bank_account", idempotency_key: nil, correlation_id: nil, metadata: {})
      @organization = organization
      @wallet = wallet
      @external_id = external_id
      @amount_cents = amount_cents.to_i
      @destination_reference = destination_reference
      @currency = currency
      @settlement_delay_days = settlement_delay_days.to_i
      @destination_kind = destination_kind
      @idempotency_key = idempotency_key
      @correlation_id = correlation_id
      @metadata = metadata || {}
    end

    def call
      raise Errors::IdempotencyKeyRequired if idempotency_key.blank?
      validate_wallet!

      ActiveRecord::Base.transaction do
        wallet.balance_projection.lock!
        raise Errors::InsufficientFunds.new(details: { available_cents: wallet.balance_projection.available_cents, required_cents: amount_cents }) if wallet.balance_projection.available_cents < amount_cents

        Accounts::BootstrapOrganizationLedger.call(organization:, currency:)
        payout = organization.payouts.create!(
          wallet:,
          external_id:,
          amount_cents:,
          currency:,
          settlement_delay_days:,
          settlement_due_on: Date.current + settlement_delay_days,
          destination_kind:,
          destination_reference:,
          idempotency_key:,
          correlation_id:,
          metadata:
        )
        journal_entry = Ledger::JournalPoster.call(
          organization:,
          event_type: FinancialContracts::Events::PAYOUT_SCHEDULED,
          reference: payout,
          idempotency_key:,
          correlation_id:,
          metadata: { external_id: payout.external_id, settlement_due_on: payout.settlement_due_on.iso8601 },
          lines: [
            { account: wallet.liability_account, direction: "debit", amount_cents:, currency: },
            { account: Ledger::AccountLocator.payout_clearing(organization:, currency:), direction: "credit", amount_cents:, currency: }
          ]
        )
        payout.update!(journal_entry:)
        emit(payout, FinancialContracts::Events::PAYOUT_SCHEDULED)
        payout
      end
    end

    private

    attr_reader :organization, :wallet, :external_id, :amount_cents, :destination_reference, :currency, :settlement_delay_days, :destination_kind, :idempotency_key, :correlation_id, :metadata

    def validate_wallet!
      raise Errors::ValidationError.new("Wallet belongs to another organization") if wallet.organization_id != organization.id
      raise Errors::ValidationError.new("Currency mismatch") if wallet.currency != currency
      raise Errors::ValidationError.new("Settlement delay must be non-negative") if settlement_delay_days.negative?
      FinancialLifecycle::StatusGuard.ensure_wallet_active!(wallet, role: :payout)
    end

    def emit(payout, event_type)
      OutboxEvents::Emit.call(
        organization:,
        aggregate: payout,
        event_type:,
        correlation_id:,
        idempotency_key:,
        payload: {
          payout_id: payout.public_id,
          wallet_id: wallet.public_id,
          amount_cents:,
          currency:,
          status: payout.status,
          settlement_due_on: payout.settlement_due_on.iso8601
        }
      )
    end
  end
end
