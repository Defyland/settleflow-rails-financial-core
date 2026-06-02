require "test_helper"

class AuditLogHashChainAnchorTest < ActiveSupport::TestCase
  RecordingPublisher = Struct.new(:envelopes, keyword_init: true) do
    def publish(envelope)
      envelopes << envelope
      Outbox::DeliveryResult.new(adapter: "memory", destination: "memory://audit-anchor", message_id: envelope.fetch(:id))
    end
  end

  test "anchors current audit hash-chain tail and publishes exportable envelope" do
    organization = create_organization
    audit_log = create_audit_log(organization:, action: "wallet.funded")
    publisher = RecordingPublisher.new(envelopes: [])

    anchor = AuditLogs::HashChainAnchor.call(publisher:)

    assert_equal audit_log.reload.chain_sequence, anchor.chain_sequence
    assert_equal audit_log.hash_value, anchor.hash_value
    assert_match(/\A[0-9a-f]{64}\z/, anchor.anchor_hash)
    assert AuditLogAnchor.anchor_chain_intact?
    assert AuditLogAnchor.latest_covers_current_audit_tail?

    envelope = publisher.envelopes.sole
    assert_equal anchor.public_id, envelope.fetch(:id)
    assert_equal "audit.hash_chain_anchored", envelope.fetch(:event_type)
    assert_equal anchor.anchor_hash, envelope.fetch(:payload).fetch(:anchor_hash)
  end

  test "chains consecutive anchors and does not duplicate persisted anchor for same tail" do
    organization = create_organization
    first_log = create_audit_log(organization:, action: "wallet.created")
    first_anchor = AuditLogs::HashChainAnchor.call(publisher: nil)

    create_audit_log(organization:, action: "wallet.funded")
    second_anchor = AuditLogs::HashChainAnchor.call(publisher: nil)
    repeated_anchor = AuditLogs::HashChainAnchor.call(publisher: nil)

    assert_equal first_log.reload.hash_value, first_anchor.hash_value
    assert_equal first_anchor.anchor_hash, second_anchor.previous_anchor_hash
    assert_equal second_anchor.id, repeated_anchor.id
    assert_equal 2, AuditLogAnchor.count
    assert AuditLogAnchor.anchor_chain_intact?
  end

  test "rejects anchoring when audit hash chain is broken" do
    log = create_audit_log(organization: create_organization)

    with_audit_log_mutation_guard_disabled do
      log.update_columns(action: "tampered")
    end

    assert_raises(Errors::ValidationError) do
      AuditLogs::HashChainAnchor.call(publisher: nil)
    end
  end

  test "audit log anchors are append-only" do
    create_audit_log(organization: create_organization)
    anchor = AuditLogs::HashChainAnchor.call(publisher: nil)

    assert_database_constraint_violation { anchor.update_columns(metadata: { tampered: true }) }
    assert_database_constraint_violation { anchor.destroy }
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

  def assert_database_constraint_violation
    connection = AuditLogAnchor.connection
    connection.execute("SAVEPOINT audit_log_anchor_guard_test")

    assert_raises(ActiveRecord::StatementInvalid) { yield }
  ensure
    connection.execute("ROLLBACK TO SAVEPOINT audit_log_anchor_guard_test")
    connection.execute("RELEASE SAVEPOINT audit_log_anchor_guard_test")
  end

  def with_audit_log_mutation_guard_disabled
    AuditLog.connection.execute("ALTER TABLE audit_logs DISABLE TRIGGER audit_logs_prevent_update_delete")
    yield
  ensure
    AuditLog.connection.execute("ALTER TABLE audit_logs ENABLE TRIGGER audit_logs_prevent_update_delete")
  end
end
