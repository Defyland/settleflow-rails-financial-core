require "uri"

module AuditLogs
  class WormReadiness < ApplicationService
    Check = Data.define(:name, :ok, :details) do
      def to_h
        {
          name: name.to_s,
          ok:,
          details:
        }
      end
    end

    LOCAL_HOSTS = %w[
      0.0.0.0
      127.0.0.1
      localhost
    ].freeze
    def initialize(env: ENV)
      @env = env
    end

    def call
      [
        webhook_configured_check,
        webhook_https_check,
        webhook_external_check,
        webhook_secret_check,
        latest_anchor_check
      ]
    end

    private

    attr_reader :env

    def webhook_configured_check
      Check.new(
        name: :audit_anchor_webhook_url_configured,
        ok: webhook_url.present?,
        details: {
          configured: webhook_url.present?
        }
      )
    end

    def webhook_https_check
      Check.new(
        name: :audit_anchor_webhook_uses_https,
        ok: parsed_webhook_uri&.scheme == "https",
        details: {
          scheme: parsed_webhook_uri&.scheme
        }
      )
    end

    def webhook_external_check
      host = parsed_webhook_uri&.host.to_s.downcase
      Check.new(
        name: :audit_anchor_webhook_external_host,
        ok: host.present? && !host.in?(LOCAL_HOSTS) && !host.end_with?(".local"),
        details: {
          host:,
          rejected_hosts: LOCAL_HOSTS,
          rejects_local_suffix: true
        }
      )
    end

    def webhook_secret_check
      Check.new(
        name: :audit_anchor_webhook_secret_configured,
        ok: webhook_secret.present?,
        details: {
          configured: webhook_secret.present?
        }
      )
    end

    def latest_anchor_check
      Check.new(
        name: :latest_anchor_covers_current_audit_tail,
        ok: AuditLogAnchor.latest_covers_current_audit_tail?,
        details: {
          latest_anchor_sequence: AuditLogAnchor.maximum(:chain_sequence),
          latest_audit_sequence: AuditLog.maximum(:chain_sequence)
        }
      )
    end

    def webhook_url
      env["AUDIT_ANCHOR_WEBHOOK_URL"].to_s.strip
    end

    def webhook_secret
      env["AUDIT_ANCHOR_WEBHOOK_SECRET"].to_s.strip
    end

    def parsed_webhook_uri
      @parsed_webhook_uri ||= URI.parse(webhook_url) if webhook_url.present?
    rescue URI::InvalidURIError
      nil
    end
  end
end
