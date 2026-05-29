module V1
  class TransfersController < BaseController
    def index
      render_success PagedCollectionSerializer.render(
        current_organization.transfers.includes(:source_wallet, :destination_wallet, :journal_entry).order(created_at: :desc),
        params:,
        item_serializer: TransferSerializer
      )
    end

    def show
      render_success data: TransferSerializer.render(transfer)
    end

    def create
      render_idempotent(status: :created) do
        source_wallet = find_by_public_id!(current_organization.wallets.includes(:balance_projection), params.require(:source_wallet_id))
        destination_wallet = find_by_public_id!(current_organization.wallets.includes(:balance_projection), params.require(:destination_wallet_id))
        created = Transfers::Create.call(
          organization: current_organization,
          source_wallet:,
          destination_wallet:,
          external_id: params.require(:external_id),
          amount_cents: params.require(:amount_cents),
          currency: params.fetch(:currency, source_wallet.currency),
          idempotency_key: idempotency_key,
          correlation_id: Current.correlation_id,
          memo: params[:memo],
          metadata: metadata_param
        )
        { data: TransferSerializer.render(created) }
      end
    end

    private

    def transfer
      @transfer ||= find_by_public_id!(current_organization.transfers.includes(:source_wallet, :destination_wallet, :journal_entry), params[:id])
    end
  end
end
