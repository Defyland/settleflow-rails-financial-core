module Ops
  class PixPaymentsController < BaseController
    rescue_from Errors::ApplicationError, with: :redirect_application_error

    before_action -> { require_capability!(:settle_pix_payment) }, only: :settle
    before_action -> { require_capability!(:reject_pix_payment) }, only: :reject
    before_action -> { require_capability!(:reverse_pix_payment) }, only: :reverse

    def index
      @status = params[:status].presence
      scope = PixPayment.includes(:organization, :wallet).order(created_at: :desc)
      scope = scope.where(status: @status) if @status.present?
      scope = search_like(scope.joins(:organization, :wallet), %w[pix_payments.external_id pix_payments.receiver_name pix_payments.pix_key organizations.slug wallets.external_id]) if params[:q].present?
      @pix_payments = paginate(scope)
    end

    def show
      @pix_payment = find_public!(PixPayment.includes(:organization, :wallet, :journal_entry, :settlement_journal_entry), params[:id])
    end

    def settle
      pix_payment = find_public!(PixPayment.includes(:organization), params[:id])
      result = MakerChecker.call(
        action: "pix_payment.settle",
        subject: pix_payment,
        operator: Current.user,
        reason: params[:reason],
        correlation_id: Current.correlation_id
      ) do
        PixPayments::Settle.call(organization: pix_payment.organization, pix_payment:, correlation_id: Current.correlation_id)
      end
      operator_audit!(action: "ops.pix_payment.settle.#{result.status}", subject: pix_payment, metadata: { approval_id: result.approval.public_id, status: pix_payment.reload.status })
      notice = result.status == :approved ? "Pix payment settled." : "Pix settlement approval requested."
      redirect_to ops_pix_payment_path(pix_payment.public_id), notice:
    end

    def reject
      pix_payment = find_public!(PixPayment.includes(:organization), params[:id])
      PixPayments::Reject.call(
        organization: pix_payment.organization,
        pix_payment:,
        reason: params[:reason],
        correlation_id: Current.correlation_id
      )
      operator_audit!(action: "ops.pix_payment.reject", subject: pix_payment, metadata: { reason: params[:reason] })
      redirect_to ops_pix_payment_path(pix_payment.public_id), notice: "Pix payment rejected."
    end

    def reverse
      pix_payment = find_public!(PixPayment.includes(:organization), params[:id])
      result = MakerChecker.call(
        action: "pix_payment.reverse",
        subject: pix_payment,
        operator: Current.user,
        reason: params[:reason],
        correlation_id: Current.correlation_id
      ) do
        PixPayments::Reverse.call(
          organization: pix_payment.organization,
          pix_payment:,
          reason: params[:reason],
          correlation_id: Current.correlation_id
        )
      end
      operator_audit!(action: "ops.pix_payment.reverse.#{result.status}", subject: pix_payment, metadata: { approval_id: result.approval.public_id, reason: params[:reason] })
      notice = result.status == :approved ? "Pix payment reversed." : "Pix reversal approval requested."
      redirect_to ops_pix_payment_path(pix_payment.public_id), notice:
    end

    private

    def redirect_application_error(error)
      redirect_to ops_pix_payment_path(params[:id]), alert: error.message
    end
  end
end
