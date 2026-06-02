module V1
  class PayoutsController < BaseController
    def index
      render_success PagedCollectionSerializer.render(
        current_organization.payouts.includes(:wallet, :journal_entry, :settlement_journal_entry).order(created_at: :desc),
        params:,
        item_serializer: PayoutSerializer
      )
    end

    def show
      render_success data: PayoutSerializer.render(payout)
    end

    def create
      render_idempotent(status: :created) do
        wallet = find_by_public_id!(current_organization.wallets.includes(:balance_projection), params.require(:wallet_id))
        created = Payouts::Create.call(
          organization: current_organization,
          wallet:,
          external_id: params.require(:external_id),
          amount_cents: params.require(:amount_cents),
          currency: params.fetch(:currency, wallet.currency),
          settlement_delay_days: params.fetch(:settlement_delay_days, 1),
          destination_kind: params.fetch(:destination_kind, "bank_account"),
          destination_reference: params.require(:destination_reference),
          idempotency_key: idempotency_key,
          correlation_id: Current.correlation_id,
          metadata: metadata_param
        )
        { data: PayoutSerializer.render(created) }
      end
    end

    def settle
      render_idempotent(status: :ok) do
        settled = Payouts::Settle.call(
          organization: current_organization,
          payout:,
          correlation_id: Current.correlation_id,
          force: ActiveModel::Type::Boolean.new.cast(params[:force])
        )
        { data: PayoutSerializer.render(settled) }
      end
    end

    private

    def payout
      @payout ||= find_by_public_id!(current_organization.payouts.includes(:wallet, :journal_entry, :settlement_journal_entry), params[:id])
    end
  end
end
