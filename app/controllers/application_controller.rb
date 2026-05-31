class ApplicationController < ActionController::Base
  include Authentication

  before_action :assign_request_context

  private

  def assign_request_context
    Current.request_id = request.request_id
    Current.correlation_id = request.headers["X-Correlation-ID"].presence || request.request_id
    response.set_header("X-Correlation-ID", Current.correlation_id)
  end
end
