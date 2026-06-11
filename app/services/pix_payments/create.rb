module PixPayments
  class Create
    REVIEW_THRESHOLD = 70
    REJECT_THRESHOLD = 90

    def self.call(...)
      new(...).call
    end

    def initialize(organization:, wallet:, external_id:, pix_key:, receiver_name:, amount_cents:, currency: "BRL", idempotency_key: nil, correlation_id: nil, metadata: {})
      @organization = organization
      @wallet = wallet
      @external_id = external_id
      @pix_key = pix_key
      @receiver_name = receiver_name
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
      FinancialLifecycle::StatusGuard.ensure_wallet_active!(wallet, role: :pix_payment)

      ActiveRecord::Base.transaction do
        wallet.balance_projection.lock!
        risk_score = Risk::PixScorer.call(amount_cents:, pix_key:, metadata:)
        pix_payment = organization.pix_payments.create!(
          wallet:,
          external_id:,
          pix_key:,
          receiver_name:,
          amount_cents:,
          currency:,
          risk_score:,
          idempotency_key:,
          correlation_id:,
          metadata:
        )

        if risk_score >= REJECT_THRESHOLD
          pix_payment.update!(status: "rejected", failure_code: "risk_rejected")
          emit(pix_payment, FinancialContracts::Events::PIX_PAYMENT_REJECTED)
          return pix_payment
        end

        if risk_score >= REVIEW_THRESHOLD
          pix_payment.update!(status: "pending_review")
          emit(pix_payment, FinancialContracts::Events::PIX_PAYMENT_PENDING_REVIEW)
          return pix_payment
        end

        raise Errors::InsufficientFunds.new(details: { available_cents: wallet.balance_projection.available_cents, required_cents: amount_cents }) if wallet.balance_projection.available_cents < amount_cents

        Accounts::BootstrapOrganizationLedger.call(organization:, currency:)
        journal_entry = Ledger::JournalPoster.call(
          organization:,
          event_type: FinancialContracts::Events::PIX_PAYMENT_APPROVED,
          reference: pix_payment,
          idempotency_key:,
          correlation_id:,
          metadata: { external_id: pix_payment.external_id, pix_key: pix_payment.pix_key },
          lines: [
            { account: wallet.liability_account, direction: "debit", amount_cents:, currency: },
            { account: Ledger::AccountLocator.pix_clearing(organization:, currency:), direction: "credit", amount_cents:, currency: }
          ]
        )
        pix_payment.update!(status: "approved", journal_entry:)
        emit(pix_payment, FinancialContracts::Events::PIX_PAYMENT_APPROVED)
        PixSettlementJob.perform_later(pix_payment.id)
        pix_payment
      end
    end

    private

    attr_reader :organization, :wallet, :external_id, :pix_key, :receiver_name, :amount_cents, :currency, :idempotency_key, :correlation_id, :metadata

    def emit(pix_payment, event_type)
      OutboxEvents::Emit.call(
        organization:,
        aggregate: pix_payment,
        event_type:,
        correlation_id:,
        idempotency_key:,
        payload: {
          pix_payment_id: pix_payment.public_id,
          wallet_id: wallet.public_id,
          amount_cents:,
          currency:,
          status: pix_payment.status,
          risk_score: pix_payment.risk_score
        }
      )
    end
  end
end
