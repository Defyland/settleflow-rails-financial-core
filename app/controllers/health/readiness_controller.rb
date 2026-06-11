module Health
  class ReadinessController < ApiController
    def show
      ActiveRecord::Base.connection.execute("SELECT 1")
      render_success({ status: "ready", checks: { database: "ok" } })
    rescue StandardError => e
      Rails.logger.error(
        event: "readiness.database_check_failed",
        error_class: e.class.name,
        error_message: e.message
      )
      render json: { status: "not_ready", checks: { database: "failed" } }, status: :service_unavailable
    end
  end
end
