module MedCases
  class Open < ApplicationService
    def initialize(organization:, pix_payment:, external_id:, amount_cents:, reason:, currency: nil, idempotency_key: nil, correlation_id: nil, metadata: {})
      @organization = organization
      @pix_payment = pix_payment
      @external_id = external_id
      @amount_cents = amount_cents.to_i
      @reason = reason.presence || "med_dispute"
      @currency = currency || pix_payment.currency
      @idempotency_key = idempotency_key
      @correlation_id = correlation_id
      @metadata = metadata || {}
    end

    def call
      raise Errors::IdempotencyKeyRequired if idempotency_key.blank?
      raise Errors::ValidationError.new("Pix payment belongs to another organization") if pix_payment.organization_id != organization.id
      raise Errors::ValidationError.new("Currency mismatch") if pix_payment.currency != currency

      ActiveRecord::Base.transaction do
        pix_payment.lock!
        raise Errors::ValidationError.new("Only settled Pix payments can enter MED", details: { status: pix_payment.status }) unless pix_payment.settled?
        raise Errors::ValidationError.new("MED amount exceeds Pix amount") if amount_cents > pix_payment.amount_cents

        med_case = organization.med_cases.create!(
          pix_payment:,
          external_id:,
          amount_cents:,
          currency:,
          reason:,
          opened_at: Time.current,
          idempotency_key:,
          correlation_id:,
          metadata:
        )
        OutboxEvents::Emit.call(
          organization:,
          aggregate: med_case,
          event_type: FinancialContracts::Events::MED_CASE_OPENED,
          correlation_id:,
          idempotency_key:,
          payload: {
            med_case_id: med_case.public_id,
            pix_payment_id: pix_payment.public_id,
            amount_cents:,
            currency:,
            status: med_case.status
          }
        )
        med_case
      end
    end

    private

    attr_reader :organization, :pix_payment, :external_id, :amount_cents, :reason, :currency, :idempotency_key, :correlation_id, :metadata
  end
end
