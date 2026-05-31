class ApiController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
  rescue_from ActiveRecord::RecordNotUnique, with: :render_record_not_unique
  rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
  rescue_from Errors::ApplicationError, with: :render_application_error

  before_action :assign_request_context

  private

  def assign_request_context
    Current.request_id = request.request_id
    Current.correlation_id = request.headers["X-Correlation-ID"].presence || request.request_id
    response.set_header("X-Correlation-ID", Current.correlation_id)
  end

  def render_success(body = nil, status: :ok, **body_kwargs)
    body = body_kwargs if body.nil?
    render json: body, status:
  end

  def render_idempotent(status: :created)
    result = Idempotency::Runner.call(
      organization: current_organization,
      key: idempotency_key,
      request_method: request.request_method,
      request_path: request.path,
      request_hash: request_hash
    ) do
      body = yield
      Idempotency::Response.new(status: Rack::Utils.status_code(status), body:, replayed: false)
    end
    response.set_header("Idempotency-Replayed", "true") if result.replayed
    render json: result.body, status: result.status
  end

  def idempotency_key
    request.headers["Idempotency-Key"].presence
  end

  def request_hash
    OpenSSL::Digest::SHA256.hexdigest(request.raw_post.to_s)
  end

  def find_by_public_id!(scope, public_id)
    scope.find_by!(public_id:)
  end

  def render_not_found(error)
    render_application_error(Errors::NotFound.new(details: { resource: error.model, query: error.primary_key }))
  end

  def render_record_invalid(error)
    render_application_error(
      Errors::ValidationError.new(details: error.record.errors.to_hash(true))
    )
  end

  def render_record_not_unique(error)
    render_application_error(
      Errors::ValidationError.new("Uniqueness constraint violated", details: { database_error: error.message })
    )
  end

  def render_parameter_missing(error)
    render_application_error(
      Errors::ValidationError.new("Required parameter is missing", details: { parameter: error.param })
    )
  end

  def render_application_error(error)
    write_error_audit_log(error)

    render json: {
      error: {
        code: error.code,
        message: error.message,
        details: error.details,
        request_id: request.request_id,
        correlation_id: Current.correlation_id
      }
    }, status: error.http_status
  end

  def write_error_audit_log(error)
    return if Current.organization.blank?

    Current.organization.audit_logs.create!(
      actor_type: "api_key",
      action: "#{request.request_method} #{request.path}",
      subject_type: params[:controller] || "unknown",
      request_id: request.request_id,
      correlation_id: Current.correlation_id,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: {
        status: Rack::Utils.status_code(error.http_status),
        error_code: error.code,
        params: request.filtered_parameters.except("controller", "action")
      }
    )
  end
end
