module V1
  class FundingsController < BaseController
    def index
      render_success PagedCollectionSerializer.render(
        current_organization.fundings.includes(:wallet, :journal_entry).order(created_at: :desc),
        params:,
        item_serializer: FundingSerializer
      )
    end

    def show
      render_success data: FundingSerializer.render(funding)
    end

    def create
      render_idempotent(status: :created) do
        wallet = find_by_public_id!(current_organization.wallets, params.require(:wallet_id))
        created = Fundings::Create.call(
          organization: current_organization,
          wallet:,
          external_id: params.require(:external_id),
          amount_cents: params.require(:amount_cents),
          currency: params.fetch(:currency, wallet.currency),
          idempotency_key: idempotency_key,
          correlation_id: Current.correlation_id,
          metadata: metadata_param
        )
        { data: FundingSerializer.render(created) }
      end
    end

    private

    def funding
      @funding ||= find_by_public_id!(current_organization.fundings.includes(:wallet, :journal_entry), params[:id])
    end
  end
end
