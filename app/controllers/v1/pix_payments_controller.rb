module V1
  class PixPaymentsController < BaseController
    def index
      render_success PagedCollectionSerializer.render(
        current_organization.pix_payments.includes(:wallet, :journal_entry, :settlement_journal_entry).order(created_at: :desc),
        params:,
        item_serializer: PixPaymentSerializer
      )
    end

    def show
      render_success data: PixPaymentSerializer.render(pix_payment)
    end

    def create
      render_idempotent(status: :created) do
        wallet = find_by_public_id!(current_organization.wallets.includes(:balance_projection), params.require(:wallet_id))
        created = PixPayments::Create.call(
          organization: current_organization,
          wallet:,
          external_id: params.require(:external_id),
          pix_key: params.require(:pix_key),
          receiver_name: params.require(:receiver_name),
          amount_cents: params.require(:amount_cents),
          currency: params.fetch(:currency, wallet.currency),
          idempotency_key: idempotency_key,
          correlation_id: Current.correlation_id,
          metadata: metadata_param
        )
        { data: PixPaymentSerializer.render(created) }
      end
    end

    def settle
      render_idempotent(status: :ok) do
        settled = PixPayments::Settle.call(
          organization: current_organization,
          pix_payment:,
          correlation_id: Current.correlation_id
        )
        { data: PixPaymentSerializer.render(settled) }
      end
    end

    private

    def pix_payment
      @pix_payment ||= find_by_public_id!(current_organization.pix_payments.includes(:wallet, :journal_entry, :settlement_journal_entry), params[:id])
    end
  end
end
