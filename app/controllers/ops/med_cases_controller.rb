module Ops
  class MedCasesController < BaseController
    rescue_from Errors::ApplicationError, with: :redirect_application_error

    before_action -> { require_capability!(:accept_med_case) }, only: :accept
    before_action -> { require_capability!(:reject_med_case) }, only: :reject

    def index
      @status = params[:status].presence
      scope = MedCase.includes(:organization, :pix_payment, :refund, :operator_approval).order(created_at: :desc)
      scope = scope.where(status: @status) if @status.present?
      if params[:q].present?
        scope = search_like(
          scope.joins(:organization, :pix_payment),
          %w[med_cases.external_id med_cases.reason pix_payments.external_id organizations.slug]
        )
      end
      @med_cases = paginate(scope)
    end

    def show
      @med_case = find_public!(
        MedCase.includes(:organization, :pix_payment, :refund, :operator_approval),
        params[:id]
      )
    end

    def accept
      med_case = find_public!(MedCase.includes(:organization), params[:id])
      result = MedCases::Accept.call(
        organization: med_case.organization,
        med_case:,
        operator: Current.user,
        reason: params[:reason],
        correlation_id: Current.correlation_id
      )
      operator_audit!(action: "ops.med_case.accept.#{result.status}", subject: med_case, metadata: { approval_id: result.approval.public_id, status: med_case.reload.status })
      notice = result.status == :approved ? "MED case accepted and refunded." : "MED acceptance approval requested."
      redirect_to ops_med_case_path(med_case.public_id), notice:
    end

    def reject
      med_case = find_public!(MedCase.includes(:organization), params[:id])
      result = MedCases::Reject.call(
        organization: med_case.organization,
        med_case:,
        operator: Current.user,
        reason: params[:reason],
        correlation_id: Current.correlation_id
      )
      operator_audit!(action: "ops.med_case.reject.#{result.status}", subject: med_case, metadata: { approval_id: result.approval.public_id, reason: params[:reason], status: med_case.reload.status })
      notice = result.status == :approved ? "MED case rejected." : "MED rejection approval requested."
      redirect_to ops_med_case_path(med_case.public_id), notice:
    end

    private

    def redirect_application_error(error)
      redirect_to ops_med_case_path(params[:id]), alert: error.message
    end
  end
end
