module Ops
  class MakerChecker < ApplicationService
    Result = Data.define(:status, :approval, :subject)

    def initialize(action:, subject:, operator:, reason: nil, correlation_id: nil, metadata: {})
      @action = action
      @subject = subject
      @operator = operator
      @reason = reason
      @correlation_id = correlation_id
      @metadata = metadata || {}
    end

    def call(&block)
      raise Errors::AuthorizationError.new("Operator is required for maker-checker actions") if operator.blank?

      ActiveRecord::Base.transaction do
        approval = pending_approval

        if approval.blank?
          approval = create_pending_approval!
          Result.new(status: :requested, approval:, subject:)
        else
          approval.lock!
          raise Errors::AuthorizationError.new("A different operator must approve this action") if approval.requested_by_id == operator.id
          raise Errors::ValidationError.new("Approved maker-checker actions must execute a financial operation") if block.blank?

          approval.update!(
            status: "approved",
            approved_by: operator,
            approved_at: Time.current
          )

          Result.new(status: :approved, approval:, subject: block.call(approval))
        end
      end
    end

    private

    attr_reader :action, :subject, :operator, :reason, :correlation_id, :metadata

    def pending_approval
      OperatorApproval.pending.find_by(
        action:,
        subject_type: subject.class.name,
        subject_id: subject.id
      )
    end

    def create_pending_approval!
      OperatorApproval.create!(
        organization: subject.organization,
        action:,
        subject_type: subject.class.name,
        subject_id: subject.id,
        requested_by: operator,
        reason:,
        correlation_id:,
        metadata:
      )
    end
  end
end
