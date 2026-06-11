module PixPayments
  class Reject < ApplicationService
    def initialize(organization:, pix_payment:, reason:, correlation_id: nil)
      @organization = organization
      @pix_payment = pix_payment
      @reason = reason.presence || "operator_rejected"
      @correlation_id = correlation_id
    end

    def call
      raise Errors::ValidationError.new("Pix payment belongs to another organization") if pix_payment.organization_id != organization.id

      ActiveRecord::Base.transaction do
        pix_payment.lock!
        raise Errors::ValidationError.new("Only pending review Pix payments can be rejected", details: { status: pix_payment.status }) unless pix_payment.pending_review?

        pix_payment.update!(
          status: "rejected",
          failure_code: reason,
          metadata: pix_payment.metadata.merge("operator_rejected_at" => Time.current.iso8601)
        )
        OutboxEvents::Emit.call(
          organization:,
          aggregate: pix_payment,
          event_type: FinancialContracts::Events::PIX_PAYMENT_REJECTED,
          correlation_id:,
          idempotency_key: FinancialContracts.pix_payment_rejection_key(pix_payment),
          payload: {
            pix_payment_id: pix_payment.public_id,
            wallet_id: pix_payment.wallet.public_id,
            amount_cents: pix_payment.amount_cents,
            currency: pix_payment.currency,
            status: pix_payment.status,
            failure_code: pix_payment.failure_code
          }
        )
        pix_payment
      end
    end

    private

    attr_reader :organization, :pix_payment, :reason, :correlation_id
  end
end
