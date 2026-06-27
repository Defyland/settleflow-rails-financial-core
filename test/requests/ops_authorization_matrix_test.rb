require "test_helper"

class OpsAuthorizationMatrixTest < ActionDispatch::IntegrationTest
  setup do
    @operator = User.create!(
      email_address: "ops-matrix-#{SecureRandom.hex(4)}@example.com",
      password: "strong-password-123",
      role: "operator"
    )
    sign_in_as(@operator)

    @organization = create_organization
    @wallet = create_wallet(organization: @organization)
    @funding = fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "ops-matrix-funding",
      amount_cents: 1_000_000
    )
    @approved_pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "ops-matrix-pix-approved",
      pix_key: "approved@example.com",
      amount_cents: 25_000
    )
    @pending_pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "ops-matrix-pix-review",
      pix_key: "review@example.com",
      amount_cents: 600_000
    )
    @settled_pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "ops-matrix-pix-settled",
      pix_key: "settled@example.com",
      amount_cents: 10_000
    )
    PixPayments::Settle.call(organization: @organization, pix_payment: @settled_pix_payment)

    med_pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "ops-matrix-med-pix",
      pix_key: "med@example.com",
      amount_cents: 5_000
    )
    PixPayments::Settle.call(organization: @organization, pix_payment: med_pix_payment)
    @med_case = MedCases::Open.call(
      organization: @organization,
      pix_payment: med_pix_payment,
      external_id: "ops-matrix-med",
      amount_cents: 2_000,
      reason: "fraud_report",
      idempotency_key: "ops-matrix-med"
    )
    @reconciliation_run = Reconciliation::Run.call(
      organization: @organization,
      provider: "ops-matrix-bank",
      statement_date: Date.current,
      provider_balance_cents: 965_000
    )
    @outbox_event = OutboxEvent.pending.order(:id).last

    clear_enqueued_jobs
  end

  test "keeps the ops route inventory aligned with the admin-only contract" do
    assert_equal expected_route_inventory, discovered_route_inventory
    assert_equal mutation_surfaces.map { |surface| surface.fetch(:capability) }.sort,
      Ops::CapabilityPolicy::CAPABILITIES.keys.sort
  end

  test "denies non-admin access to every ops read surface with audit evidence" do
    read_surfaces.each do |surface|
      assert_difference -> { AuditLog.count }, 1, failure_message(surface) do
        get surface.fetch(:path)
      end

      assert_response :forbidden, failure_message(surface)
      assert_equal "Forbidden", response.body

      audit_log = AuditLog.order(:id).last
      assert_equal "ops.global_read.denied", audit_log.action
      assert_equal @operator.id, audit_log.actor_id
      assert_equal surface.fetch(:audit_controller), audit_log.metadata["controller"]
      assert_equal surface.fetch(:action), audit_log.metadata["action"]
    end
  end

  test "denies non-admin access to every ops mutation surface with audit evidence" do
    mutation_surfaces.each do |surface|
      assert_no_changes -> { OperatorApproval.count }, failure_message(surface) do
        assert_no_changes -> { enqueued_jobs.size }, failure_message(surface) do
          assert_difference -> { AuditLog.count }, 1, failure_message(surface) do
            post surface.fetch(:path), params: surface.fetch(:params, {})
          end
        end
      end

      assert_redirected_to ops_root_path, failure_message(surface)

      audit_log = AuditLog.order(:id).last
      assert_equal "ops.authorization.denied", audit_log.action
      assert_equal @operator.id, audit_log.actor_id
      assert_equal surface.fetch(:capability).to_s, audit_log.metadata["capability"]
    end

    assert @pending_pix_payment.reload.pending_review?
    assert @settled_pix_payment.reload.settled?
    assert @med_case.reload.opened?
  end

  private

  def read_surfaces
    [
      { verb: "GET", pattern: "/", route_controller: "ops/dashboard", audit_controller: "dashboard", action: "show", path: root_path },
      { verb: "GET", pattern: "/ops(.:format)", route_controller: "ops/dashboard", audit_controller: "dashboard", action: "show", path: ops_root_path },
      { verb: "GET", pattern: "/ops/wallets(.:format)", route_controller: "ops/wallets", audit_controller: "wallets", action: "index", path: ops_wallets_path },
      { verb: "GET", pattern: "/ops/wallets/:id(.:format)", route_controller: "ops/wallets", audit_controller: "wallets", action: "show", path: ops_wallet_path(@wallet.public_id) },
      { verb: "GET", pattern: "/ops/pix_payments(.:format)", route_controller: "ops/pix_payments", audit_controller: "pix_payments", action: "index", path: ops_pix_payments_path },
      { verb: "GET", pattern: "/ops/pix_payments/:id(.:format)", route_controller: "ops/pix_payments", audit_controller: "pix_payments", action: "show", path: ops_pix_payment_path(@pending_pix_payment.public_id) },
      { verb: "GET", pattern: "/ops/med_cases(.:format)", route_controller: "ops/med_cases", audit_controller: "med_cases", action: "index", path: ops_med_cases_path },
      { verb: "GET", pattern: "/ops/med_cases/:id(.:format)", route_controller: "ops/med_cases", audit_controller: "med_cases", action: "show", path: ops_med_case_path(@med_case.public_id) },
      { verb: "GET", pattern: "/ops/outbox_events(.:format)", route_controller: "ops/outbox_events", audit_controller: "outbox_events", action: "index", path: ops_outbox_events_path },
      { verb: "GET", pattern: "/ops/reconciliation_runs(.:format)", route_controller: "ops/reconciliation_runs", audit_controller: "reconciliation_runs", action: "index", path: ops_reconciliation_runs_path },
      { verb: "GET", pattern: "/ops/reconciliation_runs/:id(.:format)", route_controller: "ops/reconciliation_runs", audit_controller: "reconciliation_runs", action: "show", path: ops_reconciliation_run_path(@reconciliation_run.public_id) },
      { verb: "GET", pattern: "/ops/ledger_entries(.:format)", route_controller: "ops/ledger_entries", audit_controller: "ledger_entries", action: "index", path: ops_ledger_entries_path },
      { verb: "GET", pattern: "/ops/ledger_entries/:id(.:format)", route_controller: "ops/ledger_entries", audit_controller: "ledger_entries", action: "show", path: ops_ledger_entry_path(@funding.journal_entry.public_id) },
      { verb: "GET", pattern: "/ops/audit_logs(.:format)", route_controller: "ops/audit_logs", audit_controller: "audit_logs", action: "index", path: ops_audit_logs_path }
    ]
  end

  def mutation_surfaces
    [
      { verb: "POST", pattern: "/ops/pix_payments/:id/settle(.:format)", route_controller: "ops/pix_payments", action: "settle", capability: :settle_pix_payment, path: settle_ops_pix_payment_path(@approved_pix_payment.public_id), params: {} },
      { verb: "POST", pattern: "/ops/pix_payments/:id/reject(.:format)", route_controller: "ops/pix_payments", action: "reject", capability: :reject_pix_payment, path: reject_ops_pix_payment_path(@pending_pix_payment.public_id), params: { reason: "operator_rejected" } },
      { verb: "POST", pattern: "/ops/pix_payments/:id/reverse(.:format)", route_controller: "ops/pix_payments", action: "reverse", capability: :reverse_pix_payment, path: reverse_ops_pix_payment_path(@settled_pix_payment.public_id), params: { reason: "operator_reversal" } },
      { verb: "POST", pattern: "/ops/med_cases/:id/accept(.:format)", route_controller: "ops/med_cases", action: "accept", capability: :accept_med_case, path: accept_ops_med_case_path(@med_case.public_id), params: { reason: "fraud_confirmed" } },
      { verb: "POST", pattern: "/ops/med_cases/:id/reject(.:format)", route_controller: "ops/med_cases", action: "reject", capability: :reject_med_case, path: reject_ops_med_case_path(@med_case.public_id), params: { reason: "insufficient_evidence" } },
      { verb: "POST", pattern: "/ops/outbox_events/:id/retry(.:format)", route_controller: "ops/outbox_events", action: "retry", capability: :retry_outbox_event, path: retry_ops_outbox_event_path(@outbox_event.public_id), params: {} }
    ]
  end

  def expected_route_inventory
    (read_surfaces + mutation_surfaces).map do |surface|
      [
        surface.fetch(:verb),
        surface.fetch(:pattern),
        surface.fetch(:route_controller),
        surface.fetch(:action)
      ]
    end.sort
  end

  def discovered_route_inventory
    Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller]
      action = route.defaults[:action]
      next unless controller&.start_with?("ops/")

      verb = normalize_verb(route.verb)
      next if verb.blank?

      [ verb, route.path.spec.to_s, controller, action ]
    end.sort
  end

  def normalize_verb(route_verb)
    verb = route_verb.to_s
    return "POST" if verb.include?("POST")
    return "GET" if verb.include?("GET")

    nil
  end

  def failure_message(surface)
    "#{surface.fetch(:route_controller)}##{surface.fetch(:action)}"
  end
end
