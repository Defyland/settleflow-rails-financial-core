module V1
  class BaseController < ApiController
    before_action :authenticate_organization!
    before_action :authorize_api_scope!
    around_action :audit_request

    attr_reader :current_organization

    private

    def authenticate_organization!
      api_key = request.headers["X-Api-Key"].to_s
      credential = ApiCredential.authenticate(api_key)
      organization = credential&.organization || Organization.authenticate_api_key(api_key)
      raise Errors::AuthenticationError if organization.blank?

      Current.organization = organization
      Current.api_key_digest = Organization.digest_api_key(api_key)
      Current.api_credential = credential
      @current_organization = organization
    end

    def authorize_api_scope!
      return if Current.api_credential.blank?

      scope = request.get? || request.head? ? "v1:read" : "v1:write"
      return if Current.api_credential.allows?(scope)

      raise Errors::AuthorizationError.new(details: { required_scope: scope })
    end

    def audit_request
      yield
    ensure
      write_audit_log
    end

    def write_audit_log
      return if current_organization.blank?

      current_organization.audit_logs.create!(
        actor_type: "api_key",
        action: "#{request.request_method} #{request.path}",
        subject_type: controller_name,
        request_id: request.request_id,
        correlation_id: Current.correlation_id,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          status: response.status,
          params: request.filtered_parameters.except("controller", "action")
        }
      )
    end

    def metadata_param
      raw_metadata = params[:metadata]
      return {} if raw_metadata.blank?
      return raw_metadata.to_unsafe_h if raw_metadata.respond_to?(:to_unsafe_h)

      raw_metadata
    end
  end
end
