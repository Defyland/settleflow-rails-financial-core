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
      render_success data: ReconciliationRunSerializer.render(reconciliation_run, include_rows: true)
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
          metadata: metadata_param,
          statement_entries: statement_entries_param
        )
        { data: ReconciliationRunSerializer.render(run) }
      end
    rescue Date::Error
      raise Errors::ValidationError.new("statement_date must be ISO-8601")
    end

    private

    def reconciliation_run
      @reconciliation_run ||= find_by_public_id!(current_organization.reconciliation_runs.includes(reconciliation_rows: :journal_entry), params[:id])
    end

    def statement_entries_param
      raw_entries = params[:statement_entries] || params[:entries]
      return [] if raw_entries.blank?

      raise Errors::ValidationError.new("statement_entries must be an array") unless raw_entries.is_a?(Array)

      raw_entries.map do |entry|
        entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry
      end
    end
  end
end
