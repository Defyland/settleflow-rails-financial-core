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

    def statement
      lines = LedgerLine
        .joins(:ledger_account, :journal_entry)
        .where(organization: current_organization, ledger_account: { wallet_id: wallet.id })
        .includes(:journal_entry, :ledger_account)
        .order(created_at: :desc)

      render_success PagedCollectionSerializer.render(
        lines,
        params:,
        item_serializer: LedgerLineSerializer
      )
    end

    private

    def wallet
      @wallet ||= find_by_public_id!(current_organization.wallets.includes(:customer, :balance_projection), params[:id])
    end
  end
end
