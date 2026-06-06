module MedCases
  class Reject
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, med_case:, operator:, reason:, correlation_id: nil)
      @organization = organization
      @med_case = med_case
      @operator = operator
      @reason = reason.presence || "med_rejected"
      @correlation_id = correlation_id
    end

    def call
      raise Errors::ValidationError.new("MED case belongs to another organization") if med_case.organization_id != organization.id
      med_case.reload
      raise Errors::ValidationError.new("MED case must be opened before rejection", details: { status: med_case.status }) unless med_case.opened?

      Ops::MakerChecker.call(
        action: FinancialContracts::Actions::MED_CASE_REJECT,
        subject: med_case,
        operator:,
        reason:,
        correlation_id:
      ) do |approval|
        med_case.lock!
        raise Errors::ValidationError.new("MED case must be opened before rejection", details: { status: med_case.status }) unless med_case.opened?

        med_case.update!(
          status: "rejected",
          operator_approval: approval,
          resolved_at: Time.current,
          metadata: med_case.metadata.merge("rejection_reason" => reason)
        )
        OutboxEvents::Emit.call(
          organization:,
          aggregate: med_case,
          event_type: FinancialContracts::Events::MED_CASE_REJECTED,
          correlation_id: correlation_id || med_case.correlation_id,
          idempotency_key: FinancialContracts.med_case_rejection_key(med_case),
          payload: {
            med_case_id: med_case.public_id,
            pix_payment_id: med_case.pix_payment.public_id,
            operator_approval_id: approval.public_id,
            amount_cents: med_case.amount_cents,
            currency: med_case.currency,
            status: med_case.status,
            reason:,
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
