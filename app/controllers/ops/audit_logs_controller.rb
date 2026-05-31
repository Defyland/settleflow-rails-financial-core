module Ops
  class AuditLogsController < BaseController
    def index
      scope = AuditLog.includes(:organization).order(created_at: :desc)
      scope = search_like(scope.left_joins(:organization), %w[audit_logs.action audit_logs.subject_type audit_logs.correlation_id organizations.slug]) if params[:q].present?
      @audit_logs = paginate(scope)
    end
  end
end
