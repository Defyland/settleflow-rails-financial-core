module V1
  class SplitPaymentsController < BaseController
    def index
      render_success PagedCollectionSerializer.render(
        current_organization.split_payments.includes(:source_wallet, :journal_entry, split_entries: :destination_wallet).order(created_at: :desc),
        params:,
        item_serializer: SplitPaymentSerializer
      )
    end

    def show
      render_success data: SplitPaymentSerializer.render(split_payment)
    end

    def create
      render_idempotent(status: :created) do
        source_wallet = find_by_public_id!(current_organization.wallets.includes(:balance_projection), params.require(:source_wallet_id))
        created = SplitPayments::Create.call(
          organization: current_organization,
          source_wallet:,
          external_id: params.require(:external_id),
          entries: split_entries_param,
          currency: params.fetch(:currency, source_wallet.currency),
          idempotency_key: idempotency_key,
          correlation_id: Current.correlation_id,
          memo: params[:memo],
          metadata: metadata_param
        )
        { data: SplitPaymentSerializer.render(created) }
      end
    end

    private

    def split_payment
      @split_payment ||= find_by_public_id!(
        current_organization.split_payments.includes(:source_wallet, :journal_entry, split_entries: :destination_wallet),
        params[:id]
      )
    end

    def split_entries_param
      params.require(:entries).map do |raw_entry|
        entry = raw_entry.respond_to?(:to_unsafe_h) ? raw_entry.to_unsafe_h : raw_entry
        {
          destination_wallet: find_by_public_id!(current_organization.wallets, entry.fetch("destination_wallet_id")),
          amount_cents: entry.fetch("amount_cents"),
          metadata: entry["metadata"] || {}
        }
      end
    end
  end
end
