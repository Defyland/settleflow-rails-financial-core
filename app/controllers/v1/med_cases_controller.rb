module V1
  class MedCasesController < BaseController
    def index
      render_success PagedCollectionSerializer.render(
        current_organization.med_cases.includes(:pix_payment, :refund).order(created_at: :desc),
        params:,
        item_serializer: MedCaseSerializer
      )
    end

    def show
      render_success data: MedCaseSerializer.render(med_case)
    end

    def create
      render_idempotent(status: :created) do
        pix_payment = find_by_public_id!(current_organization.pix_payments, params.require(:pix_payment_id))
        created = MedCases::Open.call(
          organization: current_organization,
          pix_payment:,
          external_id: params.require(:external_id),
          amount_cents: params.require(:amount_cents),
          currency: params.fetch(:currency, pix_payment.currency),
          reason: params.require(:reason),
          idempotency_key: idempotency_key,
          correlation_id: Current.correlation_id,
          metadata: metadata_param
        )
        { data: MedCaseSerializer.render(created) }
      end
    end

    def accept
      render_idempotent(status: :ok) do
        raise Errors::AuthorizationError.new("MED acceptance requires ops maker-checker approval")
      end
    end

    def reject
      render_idempotent(status: :ok) do
        raise Errors::AuthorizationError.new("MED rejection requires ops maker-checker approval")
      end
    end

    private

    def med_case
      @med_case ||= find_by_public_id!(current_organization.med_cases.includes(:pix_payment, :refund), params[:id])
    end
  end
end
