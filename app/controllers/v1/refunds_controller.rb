module V1
  class RefundsController < BaseController
    def index
      render_success PagedCollectionSerializer.render(
        current_organization.refunds.includes(:wallet, :pix_payment, :journal_entry).order(created_at: :desc),
        params:,
        item_serializer: RefundSerializer
      )
    end

    def show
      render_success data: RefundSerializer.render(refund)
    end

    def create
      render_idempotent(status: :created) do
        pix_payment = find_by_public_id!(current_organization.pix_payments.includes(:wallet), params.require(:pix_payment_id))
        created = Refunds::Create.call(
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
        { data: RefundSerializer.render(created) }
      end
    end

    private

    def refund
      @refund ||= find_by_public_id!(current_organization.refunds.includes(:wallet, :pix_payment, :journal_entry), params[:id])
    end
  end
end
