module Health
  class ReadinessController < ApplicationController
    def show
      ActiveRecord::Base.connection.execute("SELECT 1")
      render_success({ status: "ready", checks: { database: "ok" } })
    rescue StandardError => e
      render json: { status: "not_ready", checks: { database: e.message } }, status: :service_unavailable
    end
  end
end
