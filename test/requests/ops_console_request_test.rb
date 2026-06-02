require "test_helper"

class OpsConsoleRequestTest < ActionDispatch::IntegrationTest
  setup do
    @operator = User.create!(email_address: "operator-#{SecureRandom.hex(4)}@example.com", password: "strong-password-123", role: "admin")
    @approver = User.create!(email_address: "approver-#{SecureRandom.hex(4)}@example.com", password: "strong-password-123", role: "admin")
    @organization = create_organization
    @wallet = create_wallet(organization: @organization)
    @funding = fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "ops-funding",
      amount_cents: 1_000_000
    )
    @approved_pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "ops-pix-approved",
      pix_key: "supplier@example.com",
      amount_cents: 25_000
    )
    @pending_pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "ops-pix-review",
      pix_key: "review@example.com",
      amount_cents: 600_000
    )
    @reconciliation_run = Reconciliation::Run.call(
      organization: @organization,
      provider: "ops-bank",
      statement_date: Date.current,
      provider_balance_cents: 975_000
    )
  end

  test "redirects unauthenticated operators to the sign-in page" do
    get ops_root_path

    assert_redirected_to new_session_path
  end

  test "renders the operational dashboards and detail pages" do
    sign_in

    get ops_root_path
    assert_response :ok
    assert_includes response.body, "Financial operations"

    get ops_wallets_path(q: @wallet.external_id)
    assert_includes response.body, @wallet.external_id
    assert_includes response.body, "records"

    get ops_wallet_path(@wallet.public_id)
    assert_includes response.body, "Statement"

    get ops_pix_payments_path(status: "pending_review")
    assert_includes response.body, "Receiver"

    get ops_pix_payment_path(@pending_pix_payment.public_id)
    assert_includes response.body, "Risk score"

    get ops_med_cases_path(status: "opened")
    assert_response :ok
    assert_includes response.body, "MED cases"

    get ops_outbox_events_path(status: "pending")
    assert_includes response.body, "Outbox events"

    get ops_reconciliation_runs_path(status: "discrepant")
    assert_includes response.body, "Reconciliation"

    get ops_reconciliation_run_path(@reconciliation_run.public_id)
    assert_includes response.body, "ops-bank"

    get ops_ledger_entries_path
    assert_includes response.body, "wallet.funded"

    get ops_ledger_entry_path(@funding.journal_entry.public_id)
    assert_includes response.body, "Lines"

    get ops_audit_logs_path
    assert_includes response.body, "Audit logs"
  end

  test "performs admin operator actions with audit records" do
    sign_in

    post settle_ops_pix_payment_path(@approved_pix_payment.public_id)
    assert_redirected_to ops_pix_payment_path(@approved_pix_payment.public_id)
    assert @approved_pix_payment.reload.approved?
    settlement_approval = OperatorApproval.find_by!(action: "pix_payment.settle", subject_type: "PixPayment", subject_id: @approved_pix_payment.id)
    assert settlement_approval.pending?
    assert_equal @operator.id, settlement_approval.requested_by_id
    assert AuditLog.exists?(actor_type: "user", actor_id: @operator.id, action: "ops.pix_payment.settle.requested")

    sign_in(@approver)
    post settle_ops_pix_payment_path(@approved_pix_payment.public_id)
    assert_redirected_to ops_pix_payment_path(@approved_pix_payment.public_id)
    assert @approved_pix_payment.reload.settled?
    assert settlement_approval.reload.approved?
    assert_equal @approver.id, settlement_approval.approved_by_id
    assert AuditLog.exists?(actor_type: "user", actor_id: @approver.id, action: "ops.pix_payment.settle.approved")

    post reverse_ops_pix_payment_path(@approved_pix_payment.public_id), params: { reason: "operator_reversal" }
    assert_redirected_to ops_pix_payment_path(@approved_pix_payment.public_id)
    assert @approved_pix_payment.reload.settled?
    reversal_approval = OperatorApproval.find_by!(action: "pix_payment.reverse", subject_type: "PixPayment", subject_id: @approved_pix_payment.id)
    assert reversal_approval.pending?
    assert_equal @approver.id, reversal_approval.requested_by_id
    assert AuditLog.exists?(actor_type: "user", actor_id: @approver.id, action: "ops.pix_payment.reverse.requested")

    sign_in(@operator)
    post reverse_ops_pix_payment_path(@approved_pix_payment.public_id), params: { reason: "operator_reversal" }
    assert_redirected_to ops_pix_payment_path(@approved_pix_payment.public_id)
    assert @approved_pix_payment.reload.reversed?
    assert @approved_pix_payment.reversal_journal_entry.balanced?
    assert reversal_approval.reload.approved?
    assert_equal @operator.id, reversal_approval.approved_by_id
    assert AuditLog.exists?(actor_type: "user", actor_id: @operator.id, action: "ops.pix_payment.reverse.approved")

    post reject_ops_pix_payment_path(@pending_pix_payment.public_id), params: { reason: "operator_rejected" }
    assert_redirected_to ops_pix_payment_path(@pending_pix_payment.public_id)
    assert @pending_pix_payment.reload.rejected?
    assert AuditLog.exists?(actor_type: "user", actor_id: @operator.id, action: "ops.pix_payment.reject")

    med_pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "ops-med-pix",
      pix_key: "ops-med@example.com",
      amount_cents: 5_000
    )
    PixPayments::Settle.call(organization: @organization, pix_payment: med_pix_payment)
    med_case = MedCases::Open.call(
      organization: @organization,
      pix_payment: med_pix_payment,
      external_id: "ops-med",
      amount_cents: 2_000,
      reason: "fraud_report",
      idempotency_key: "ops-med"
    )

    post accept_ops_med_case_path(med_case.public_id), params: { reason: "fraud_confirmed" }
    assert_redirected_to ops_med_case_path(med_case.public_id)
    assert med_case.reload.opened?
    med_approval = OperatorApproval.find_by!(action: "med_case.accept", subject_type: "MedCase", subject_id: med_case.id)
    assert med_approval.pending?
    assert_equal @operator.id, med_approval.requested_by_id
    assert AuditLog.exists?(actor_type: "user", actor_id: @operator.id, action: "ops.med_case.accept.requested")

    sign_in(@approver)
    post accept_ops_med_case_path(med_case.public_id), params: { reason: "fraud_confirmed" }
    assert_redirected_to ops_med_case_path(med_case.public_id)
    assert med_case.reload.refunded?
    assert med_case.refund.settled?
    assert_equal med_approval.id, med_case.operator_approval_id
    assert med_approval.reload.approved?
    assert_equal @approver.id, med_approval.approved_by_id
    assert AuditLog.exists?(actor_type: "user", actor_id: @approver.id, action: "ops.med_case.accept.approved")

    event = OutboxEvent.pending.first
    post retry_ops_outbox_event_path(event.public_id)
    assert_redirected_to ops_outbox_events_path(status: "pending")
    assert_includes enqueued_jobs.map { |job| job[:job] }, OutboxPublishJob
    assert AuditLog.exists?(actor_type: "user", actor_id: @approver.id, action: "ops.outbox.retry")
  end

  test "prevents the requester from approving their own financial action" do
    sign_in

    post settle_ops_pix_payment_path(@approved_pix_payment.public_id)
    assert_redirected_to ops_pix_payment_path(@approved_pix_payment.public_id)

    post settle_ops_pix_payment_path(@approved_pix_payment.public_id)
    assert_redirected_to ops_pix_payment_path(@approved_pix_payment.public_id)
    assert @approved_pix_payment.reload.approved?
    assert OperatorApproval.find_by!(action: "pix_payment.settle", subject_type: "PixPayment", subject_id: @approved_pix_payment.id).pending?
  end

  test "blocks viewers from mutating financial operations" do
    @operator.update!(role: "viewer")
    sign_in

    post settle_ops_pix_payment_path(@approved_pix_payment.public_id)

    assert_redirected_to ops_root_path
    assert @approved_pix_payment.reload.approved?
    assert AuditLog.exists?(actor_type: "user", actor_id: @operator.id, action: "ops.authorization.denied")
  end

  test "allows operators to reject Pix reviews and retry outbox but blocks admin-only actions" do
    @operator.update!(role: "operator")
    settled_pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "ops-pix-settled-for-operator",
      pix_key: "operator-settled@example.com",
      amount_cents: 10_000
    )
    PixPayments::Settle.call(organization: @organization, pix_payment: settled_pix_payment)
    event = OutboxEvent.pending.first
    sign_in

    post settle_ops_pix_payment_path(@approved_pix_payment.public_id)
    assert_redirected_to ops_root_path
    assert @approved_pix_payment.reload.approved?
    assert AuditLog.exists?(
      actor_type: "user",
      actor_id: @operator.id,
      action: "ops.authorization.denied",
      metadata: { capability: "settle_pix_payment" }
    )

    post reverse_ops_pix_payment_path(settled_pix_payment.public_id), params: { reason: "operator_reversal" }
    assert_redirected_to ops_root_path
    assert settled_pix_payment.reload.settled?
    assert AuditLog.exists?(
      actor_type: "user",
      actor_id: @operator.id,
      action: "ops.authorization.denied",
      metadata: { capability: "reverse_pix_payment" }
    )

    med_case = open_med_case_for_ops("ops-med-operator-blocked")
    post accept_ops_med_case_path(med_case.public_id), params: { reason: "fraud_confirmed" }
    assert_redirected_to ops_root_path
    assert med_case.reload.opened?
    assert AuditLog.exists?(
      actor_type: "user",
      actor_id: @operator.id,
      action: "ops.authorization.denied",
      metadata: { capability: "accept_med_case" }
    )

    post reject_ops_pix_payment_path(@pending_pix_payment.public_id), params: { reason: "operator_rejected" }
    assert_redirected_to ops_pix_payment_path(@pending_pix_payment.public_id)
    assert @pending_pix_payment.reload.rejected?

    post retry_ops_outbox_event_path(event.public_id)
    assert_redirected_to ops_outbox_events_path(status: "pending")
    assert_includes enqueued_jobs.map { |job| job[:job] }, OutboxPublishJob
  end

  test "does not retry already published outbox events" do
    event = OutboxEvent.pending.first
    publish_outbox_event(event)
    clear_enqueued_jobs
    sign_in

    post retry_ops_outbox_event_path(event.public_id)

    assert_redirected_to ops_outbox_events_path(status: "published")
    assert_empty enqueued_jobs.select { |job| job[:job] == OutboxPublishJob }
    assert event.reload.published?
  end

  private

  def sign_in(user = @operator)
    post session_path, params: { email_address: user.email_address, password: "strong-password-123" }
    assert_redirected_to root_path
  end

  def publish_outbox_event(event)
    event.claim_for_publish!
    event.publish!(
      Outbox::DeliveryResult.new(adapter: "test", destination: "memory://outbox", message_id: "msg-#{event.public_id}"),
      payload_sha256: Outbox::Publisher.payload_sha256(Outbox::Publisher.envelope_for(event))
    )
  end

  def open_med_case_for_ops(external_id)
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "#{external_id}-pix",
      pix_key: "#{external_id}@example.com",
      amount_cents: 1_000
    )
    PixPayments::Settle.call(organization: @organization, pix_payment:)
    MedCases::Open.call(
      organization: @organization,
      pix_payment:,
      external_id:,
      amount_cents: 500,
      reason: "fraud_report",
      idempotency_key: external_id
    )
  end
end
