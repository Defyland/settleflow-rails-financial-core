module Ops
  class ReconciliationRunsController < BaseController
    def index
      @status = params[:status].presence
      scope = ReconciliationRun.includes(:organization).order(created_at: :desc)
      scope = scope.where(status: @status) if @status.present?
      scope = search_like(scope.joins(:organization), %w[reconciliation_runs.provider reconciliation_runs.correlation_id organizations.slug]) if params[:q].present?
      @runs = paginate(scope)
    end

    def show
      @run = find_public!(ReconciliationRun.includes(:organization), params[:id])
    end
  end
end
