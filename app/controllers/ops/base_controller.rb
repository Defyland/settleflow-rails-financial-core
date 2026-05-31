module Ops
  class BaseController < ApplicationController
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100

    helper_method :can?, :pagination

    private

    def can?(capability)
      CapabilityPolicy.allowed?(Current.user, capability)
    end

    def require_capability!(capability)
      return if can?(capability)

      operator_audit!(
        action: "ops.authorization.denied",
        subject: Current.user,
        metadata: { capability: }
      )
      redirect_back fallback_location: ops_root_path, alert: "You are not allowed to perform this action."
    end

    def find_public!(scope, id)
      scope.find_by!(public_id: id)
    end

    def paginate(scope)
      page = [ params[:page].to_i, 1 ].max
      requested_per_page = params[:per_page].presence&.to_i || DEFAULT_PER_PAGE
      per_page = requested_per_page.clamp(1, MAX_PER_PAGE)
      total = scope.count
      total_pages = [ (total.to_f / per_page).ceil, 1 ].max
      page = total_pages if page > total_pages
      @pagination = { page:, per_page:, total:, total_pages: }
      scope.offset((page - 1) * per_page).limit(per_page)
    end

    def pagination
      @pagination
    end

    def search_like(scope, columns)
      @query = params[:q].to_s.strip
      return scope if @query.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      clause = columns.map { |column| "#{column} ILIKE :query" }.join(" OR ")
      scope.where(clause, query: pattern)
    end

    def operator_audit!(action:, subject:, metadata: {})
      AuditLog.create!(
        organization: subject.respond_to?(:organization) ? subject.organization : nil,
        actor_type: "user",
        actor_id: Current.user&.id,
        action:,
        subject_type: subject.class.name,
        subject_id: subject.id,
        request_id: request.request_id,
        correlation_id: Current.correlation_id,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata:
      )
    end
  end
end
