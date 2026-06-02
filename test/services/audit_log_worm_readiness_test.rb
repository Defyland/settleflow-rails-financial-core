require "test_helper"

class AuditLogWormReadinessTest < ActiveSupport::TestCase
  test "passes when external HTTPS anchor export is configured and current anchor is fresh" do
    create_audit_log(organization: create_organization)
    AuditLogs::HashChainAnchor.call(publisher: nil)

    checks = AuditLogs::WormReadiness.call(env: {
      "AUDIT_ANCHOR_WEBHOOK_URL" => "https://worm-vault.example.com/audit-anchors",
      "AUDIT_ANCHOR_WEBHOOK_SECRET" => "signed-secret"
    })

    assert checks.all?(&:ok), checks.map(&:to_h).inspect
  end

  test "fails when anchor export is missing or local" do
    checks = AuditLogs::WormReadiness.call(env: {
      "AUDIT_ANCHOR_WEBHOOK_URL" => "http://localhost/audit-anchors",
      "AUDIT_ANCHOR_WEBHOOK_SECRET" => ""
    })

    checks_by_name = checks.index_by(&:name)
    assert_not checks_by_name.fetch(:audit_anchor_webhook_uses_https).ok
    assert_not checks_by_name.fetch(:audit_anchor_webhook_external_host).ok
    assert_not checks_by_name.fetch(:audit_anchor_webhook_secret_configured).ok
  end

  test "fails when latest anchor does not cover the current audit tail" do
    organization = create_organization
    create_audit_log(organization:, action: "first.action")
    AuditLogs::HashChainAnchor.call(publisher: nil)
    create_audit_log(organization:, action: "second.action")

    check = AuditLogs::WormReadiness.call(env: {
      "AUDIT_ANCHOR_WEBHOOK_URL" => "https://worm-vault.example.com/audit-anchors",
      "AUDIT_ANCHOR_WEBHOOK_SECRET" => "signed-secret"
    }).find { |item| item.name == :latest_anchor_covers_current_audit_tail }

    assert_not check.ok
  end

  private

  def create_audit_log(organization:, action: "api.request")
    organization.audit_logs.create!(
      actor_type: "api_key",
      action:,
      subject_type: "wallets",
      request_id: SecureRandom.uuid,
      correlation_id: SecureRandom.uuid,
      ip_address: "127.0.0.1",
      user_agent: "Minitest",
      metadata: { status: 200 }
    )
  end
end
