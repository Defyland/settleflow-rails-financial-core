module MedCases
  class Accept
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, med_case:, operator:, reason: nil, correlation_id: nil)
      @organization = organization
      @med_case = med_case
      @operator = operator
      @reason = reason.presence || "med_accept"
      @correlation_id = correlation_id
    end

    def call
      raise Errors::ValidationError.new("MED case belongs to another organization") if med_case.organization_id != organization.id
      med_case.reload
      raise Errors::ValidationError.new("MED case must be opened before refund", details: { status: med_case.status }) unless med_case.opened?

      Ops::MakerChecker.call(
        action: "med_case.accept",
        subject: med_case,
        operator:,
        reason:,
        correlation_id:
      ) do |approval|
        med_case.lock!
        raise Errors::ValidationError.new("MED case must be opened before refund", details: { status: med_case.status }) unless med_case.opened?

        refund = Refunds::Create.call(
          organization:,
          pix_payment: med_case.pix_payment,
          external_id: "med-refund-#{med_case.public_id}",
          amount_cents: med_case.amount_cents,
          currency: med_case.currency,
          reason: "med_accepted:#{med_case.reason}",
          idempotency_key: "med_case.refund:#{med_case.id}",
          correlation_id: correlation_id || med_case.correlation_id,
          metadata: med_case.metadata.merge("med_case_id" => med_case.public_id)
        )
        med_case.update!(status: "refunded", refund:, operator_approval: approval, resolved_at: Time.current)
        OutboxEvents::Emit.call(
          organization:,
          aggregate: med_case,
          event_type: "med.case.refunded",
          correlation_id: correlation_id || med_case.correlation_id,
          payload: {
            med_case_id: med_case.public_id,
            refund_id: refund.public_id,
            operator_approval_id: approval.public_id,
            pix_payment_id: med_case.pix_payment.public_id,
            amount_cents: med_case.amount_cents,
            currency: med_case.currency,
            status: med_case.status,
            resolved_at: med_case.resolved_at.iso8601
          }
        )
        med_case
      end
    end

    private

    attr_reader :organization, :med_case, :operator, :reason, :correlation_id
  end
end
