module V1
  class WalletsController < BaseController
    def index
      render_success PagedCollectionSerializer.render(
        current_organization.wallets.includes(:customer, :balance_projection).order(created_at: :desc),
        params:,
        item_serializer: WalletSerializer
      )
    end

    def show
      render_success data: WalletSerializer.render(wallet)
    end

    def create
      render_idempotent(status: :created) do
        customer = find_by_public_id!(current_organization.customers, params.require(:customer_id))
        created = Wallets::Creator.call(
          organization: current_organization,
          customer:,
          external_id: params.require(:external_id),
          currency: params.fetch(:currency, "BRL"),
          metadata: metadata_param
        )
        { data: WalletSerializer.render(created) }
      end
    end

    def balance
      render_success data: BalanceProjectionSerializer.render(wallet.balance_projection)
    end

    def balance_explanation
      render_success data: Wallets::BalanceExplainer.call(wallet:)
    end

    def statement
      limit = [ [ params.fetch(:limit, Wallets::StatementBuilder::DEFAULT_LIMIT).to_i, 1 ].max, Wallets::StatementBuilder::MAX_LIMIT ].min
      lines = Wallets::StatementBuilder.call(wallet:, limit:)

      render_success(
        data: lines.map { |line| WalletStatementLineSerializer.render(line) },
        meta: { limit:, returned: lines.size }
      )
    end

    private

    def wallet
      @wallet ||= find_by_public_id!(current_organization.wallets.includes(:customer, :balance_projection), params[:id])
    end
  end
end
