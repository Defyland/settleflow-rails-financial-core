module V1
  class ReconciliationRunsController < BaseController
    def index
      render_success PagedCollectionSerializer.render(
        current_organization.reconciliation_runs.order(created_at: :desc),
        params:,
        item_serializer: ReconciliationRunSerializer
      )
    end

    def show
      render_success data: ReconciliationRunSerializer.render(reconciliation_run)
    end

    def create
      render_idempotent(status: :created) do
        run = Reconciliation::Run.call(
          organization: current_organization,
          provider: params.require(:provider),
          statement_date: Date.iso8601(params.require(:statement_date)),
          provider_balance_cents: params.require(:provider_balance_cents),
          currency: params.fetch(:currency, "BRL"),
          correlation_id: Current.correlation_id,
          metadata: metadata_param
        )
        { data: ReconciliationRunSerializer.render(run) }
      end
    rescue Date::Error
      raise Errors::ValidationError.new("statement_date must be ISO-8601")
    end

    private

    def reconciliation_run
      @reconciliation_run ||= find_by_public_id!(current_organization.reconciliation_runs, params[:id])
    end
  end
end
