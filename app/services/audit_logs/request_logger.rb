module AuditLogs
  class RequestLogger
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, actor_type:, action:, subject_type:, request_id:, correlation_id:, ip_address:, user_agent:, status:, params:, actor_id: nil, subject_id: nil, error_code: nil)
      @organization = organization
      @actor_type = actor_type
      @actor_id = actor_id
      @action = action
      @subject_type = subject_type
      @subject_id = subject_id
      @request_id = request_id
      @correlation_id = correlation_id
      @ip_address = ip_address
      @user_agent = user_agent
      @status = status
      @params = params
      @error_code = error_code
    end

    def call
      return if organization.blank?

      AuditLog.create!(
        organization:,
        actor_type:,
        actor_id:,
        action:,
        subject_type:,
        subject_id:,
        request_id:,
        correlation_id:,
        ip_address:,
        user_agent:,
        metadata:
      )
    rescue StandardError => e
      Rails.logger.error(
        event: "audit_log.write_failed",
        organization_id: organization&.id,
        request_id:,
        correlation_id:,
        error_class: e.class.name,
        error_message: e.message
      )
      nil
    end

    private

    attr_reader :organization, :actor_type, :actor_id, :action, :subject_type, :subject_id,
      :request_id, :correlation_id, :ip_address, :user_agent, :status, :params, :error_code

    def metadata
      payload = {
        status:,
        params: AuditLogs::ParameterSanitizer.call(params)
      }
      payload[:error_code] = error_code if error_code.present?
      payload
    end
  end
end
