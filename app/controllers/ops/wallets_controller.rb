module Ops
  class WalletsController < BaseController
    def index
      scope = Wallet.includes(:organization, :customer, :balance_projection).order(created_at: :desc)
      scope = search_like(scope.joins(:organization, :customer), %w[wallets.external_id customers.legal_name organizations.slug]) if params[:q].present?
      @wallets = paginate(scope)
    end

    def show
      @wallet = find_public!(Wallet.includes(:organization, :customer, :balance_projection), params[:id])
      @ledger_lines = LedgerLine
        .joins(:ledger_account, :journal_entry)
        .where(ledger_account: { wallet_id: @wallet.id })
        .includes(:journal_entry, :ledger_account)
        .order(created_at: :desc)
        .limit(100)
    end
  end
end
