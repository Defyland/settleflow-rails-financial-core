require "test_helper"

class AuditLogHashChainTest < ActiveSupport::TestCase
  test "assigns a verifiable append-only hash chain" do
    organization = create_organization
    first = create_audit_log(organization:, action: "wallet.created")
    second = create_audit_log(organization:, action: "wallet.funded")

    first.reload
    second.reload

    assert_equal first.chain_sequence + 1, second.chain_sequence
    assert_equal first.hash_value, second.previous_hash
    assert_equal "sha256", first.hash_algorithm
    assert_match(/\A[0-9a-f]{64}\z/, first.hash_value)
    assert first.hash_valid?
    assert second.hash_valid?
    assert AuditLog.hash_chain_intact?
  end

  test "rejects direct audit log mutation and deletion" do
    log = create_audit_log(organization: create_organization)

    assert_database_constraint_violation { log.update_columns(action: "tampered") }
    assert_database_constraint_violation { log.destroy }
  end

  test "detects tampering when database guards are bypassed" do
    log = create_audit_log(organization: create_organization)

    with_audit_log_mutation_guard_disabled do
      log.update_columns(action: "tampered")
    end

    assert_not log.reload.hash_valid?
    assert_not AuditLog.hash_chain_intact?
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
    connection = AuditLog.connection
    connection.execute("SAVEPOINT audit_log_guard_test")

    assert_raises(ActiveRecord::StatementInvalid) { yield }
  ensure
    connection.execute("ROLLBACK TO SAVEPOINT audit_log_guard_test")
    connection.execute("RELEASE SAVEPOINT audit_log_guard_test")
  end

  def with_audit_log_mutation_guard_disabled
    AuditLog.connection.execute("ALTER TABLE audit_logs DISABLE TRIGGER audit_logs_prevent_update_delete")
    yield
  ensure
    AuditLog.connection.execute("ALTER TABLE audit_logs ENABLE TRIGGER audit_logs_prevent_update_delete")
  end
end
