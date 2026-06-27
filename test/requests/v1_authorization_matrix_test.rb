require "test_helper"

class V1AuthorizationMatrixTest < ActionDispatch::IntegrationTest
  setup do
    @organization = create_organization
    _credential, @read_api_key = ApiCredential.issue!(
      organization: @organization,
      name: "read only matrix",
      scopes: %w[v1:read]
    )

    source_customer = create_customer(organization: @organization, external_id: "v1-matrix-source-customer")
    destination_customer = create_customer(organization: @organization, external_id: "v1-matrix-destination-customer")
    @source_wallet = create_wallet(organization: @organization, customer: source_customer, external_id: "v1-matrix-source-wallet")
    @destination_wallet = create_wallet(organization: @organization, customer: destination_customer, external_id: "v1-matrix-destination-wallet")
    @extra_wallet = create_wallet(organization: @organization, external_id: "v1-matrix-extra-wallet")

    @funding = fund_wallet(
      organization: @organization,
      wallet: @source_wallet,
      external_id: "v1-matrix-funding",
      amount_cents: 50_000
    )
    @transfer = Transfers::Create.call(
      organization: @organization,
      source_wallet: @source_wallet,
      destination_wallet: @destination_wallet,
      external_id: "v1-matrix-transfer",
      amount_cents: 5_000,
      idempotency_key: "v1-matrix-transfer"
    )
    @split_payment = SplitPayments::Create.call(
      organization: @organization,
      source_wallet: @source_wallet,
      external_id: "v1-matrix-split",
      entries: [
        { destination_wallet: @destination_wallet, amount_cents: 2_000 },
        { destination_wallet: @extra_wallet, amount_cents: 1_000 }
      ],
      idempotency_key: "v1-matrix-split"
    )
    @payout = Payouts::Create.call(
      organization: @organization,
      wallet: @source_wallet,
      external_id: "v1-matrix-payout",
      amount_cents: 4_000,
      destination_reference: "bank-account-v1-matrix",
      settlement_delay_days: 0,
      idempotency_key: "v1-matrix-payout"
    )
    @pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @source_wallet,
      external_id: "v1-matrix-pix",
      pix_key: "approved-v1-matrix@example.com",
      amount_cents: 3_000
    )

    refund_pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @source_wallet,
      external_id: "v1-matrix-refund-pix",
      pix_key: "refund-v1-matrix@example.com",
      amount_cents: 2_500
    )
    PixPayments::Settle.call(organization: @organization, pix_payment: refund_pix_payment)
    @refund = Refunds::Create.call(
      organization: @organization,
      pix_payment: refund_pix_payment,
      external_id: "v1-matrix-refund",
      amount_cents: 1_000,
      reason: "customer_request",
      idempotency_key: "v1-matrix-refund"
    )

    med_pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @source_wallet,
      external_id: "v1-matrix-med-pix",
      pix_key: "med-v1-matrix@example.com",
      amount_cents: 2_000
    )
    PixPayments::Settle.call(organization: @organization, pix_payment: med_pix_payment)
    @med_case = MedCases::Open.call(
      organization: @organization,
      pix_payment: med_pix_payment,
      external_id: "v1-matrix-med",
      amount_cents: 1_500,
      reason: "fraud_report",
      idempotency_key: "v1-matrix-med"
    )

    @reconciliation_run = Reconciliation::Run.call(
      organization: @organization,
      provider: "v1-matrix-bank",
      statement_date: Date.current,
      provider_balance_cents: @source_wallet.balance_projection.reload.available_cents
    )
  end

  test "keeps the v1 route inventory aligned with the authenticated public surface" do
    assert_equal expected_route_inventory, discovered_route_inventory
  end

  test "requires an api key for every v1 surface" do
    (read_surfaces + write_surfaces).each do |surface|
      perform_request(surface, headers: json_headers)

      assert_response :unauthorized, failure_message(surface)
      assert_equal "authentication_failed", json_body.dig("error", "code")
    end
  end

  test "allows read scoped credentials on every v1 read surface" do
    read_surfaces.each do |surface|
      perform_request(surface, headers: auth_headers(@read_api_key))

      assert_response :ok, failure_message(surface)
    end
  end

  test "denies read scoped credentials on every v1 write surface without side effects" do
    snapshot = write_side_effect_snapshot

    write_surfaces.each do |surface|
      perform_request(
        surface,
        headers: auth_headers(@read_api_key, "Idempotency-Key" => "read-scope-#{surface.fetch(:action)}")
      )

      assert_response :forbidden, failure_message(surface)
      assert_equal "authorization_failed", json_body.dig("error", "code")
    end

    assert_equal snapshot, write_side_effect_snapshot
  end

  private

  def read_surfaces
    [
      { verb: "GET", pattern: "/v1/customers(.:format)", controller: "v1/customers", action: "index", path: "/v1/customers" },
      { verb: "GET", pattern: "/v1/customers/:id(.:format)", controller: "v1/customers", action: "show", path: "/v1/customers/#{@source_wallet.customer.public_id}" },
      { verb: "GET", pattern: "/v1/wallets(.:format)", controller: "v1/wallets", action: "index", path: "/v1/wallets" },
      { verb: "GET", pattern: "/v1/wallets/:id(.:format)", controller: "v1/wallets", action: "show", path: "/v1/wallets/#{@source_wallet.public_id}" },
      { verb: "GET", pattern: "/v1/wallets/:id/balance(.:format)", controller: "v1/wallets", action: "balance", path: "/v1/wallets/#{@source_wallet.public_id}/balance" },
      { verb: "GET", pattern: "/v1/wallets/:id/balance_explanation(.:format)", controller: "v1/wallets", action: "balance_explanation", path: "/v1/wallets/#{@source_wallet.public_id}/balance_explanation" },
      { verb: "GET", pattern: "/v1/wallets/:id/statement(.:format)", controller: "v1/wallets", action: "statement", path: "/v1/wallets/#{@source_wallet.public_id}/statement" },
      { verb: "GET", pattern: "/v1/fundings(.:format)", controller: "v1/fundings", action: "index", path: "/v1/fundings" },
      { verb: "GET", pattern: "/v1/fundings/:id(.:format)", controller: "v1/fundings", action: "show", path: "/v1/fundings/#{@funding.public_id}" },
      { verb: "GET", pattern: "/v1/transfers(.:format)", controller: "v1/transfers", action: "index", path: "/v1/transfers" },
      { verb: "GET", pattern: "/v1/transfers/:id(.:format)", controller: "v1/transfers", action: "show", path: "/v1/transfers/#{@transfer.public_id}" },
      { verb: "GET", pattern: "/v1/split_payments(.:format)", controller: "v1/split_payments", action: "index", path: "/v1/split_payments" },
      { verb: "GET", pattern: "/v1/split_payments/:id(.:format)", controller: "v1/split_payments", action: "show", path: "/v1/split_payments/#{@split_payment.public_id}" },
      { verb: "GET", pattern: "/v1/payouts(.:format)", controller: "v1/payouts", action: "index", path: "/v1/payouts" },
      { verb: "GET", pattern: "/v1/payouts/:id(.:format)", controller: "v1/payouts", action: "show", path: "/v1/payouts/#{@payout.public_id}" },
      { verb: "GET", pattern: "/v1/pix_payments(.:format)", controller: "v1/pix_payments", action: "index", path: "/v1/pix_payments" },
      { verb: "GET", pattern: "/v1/pix_payments/:id(.:format)", controller: "v1/pix_payments", action: "show", path: "/v1/pix_payments/#{@pix_payment.public_id}" },
      { verb: "GET", pattern: "/v1/refunds(.:format)", controller: "v1/refunds", action: "index", path: "/v1/refunds" },
      { verb: "GET", pattern: "/v1/refunds/:id(.:format)", controller: "v1/refunds", action: "show", path: "/v1/refunds/#{@refund.public_id}" },
      { verb: "GET", pattern: "/v1/med_cases(.:format)", controller: "v1/med_cases", action: "index", path: "/v1/med_cases" },
      { verb: "GET", pattern: "/v1/med_cases/:id(.:format)", controller: "v1/med_cases", action: "show", path: "/v1/med_cases/#{@med_case.public_id}" },
      { verb: "GET", pattern: "/v1/ledger_entries(.:format)", controller: "v1/ledger_entries", action: "index", path: "/v1/ledger_entries" },
      { verb: "GET", pattern: "/v1/ledger_entries/:id(.:format)", controller: "v1/ledger_entries", action: "show", path: "/v1/ledger_entries/#{@funding.journal_entry.public_id}" },
      { verb: "GET", pattern: "/v1/reconciliation_runs(.:format)", controller: "v1/reconciliation_runs", action: "index", path: "/v1/reconciliation_runs" },
      { verb: "GET", pattern: "/v1/reconciliation_runs/:id(.:format)", controller: "v1/reconciliation_runs", action: "show", path: "/v1/reconciliation_runs/#{@reconciliation_run.public_id}" }
    ]
  end

  def write_surfaces
    [
      {
        verb: "POST",
        pattern: "/v1/customers(.:format)",
        controller: "v1/customers",
        action: "create",
        path: "/v1/customers",
        payload: {
          external_id: "v1-matrix-create-customer",
          legal_name: "Matrix Customer",
          document_kind: "cpf",
          document_number: "12345678900"
        }
      },
      {
        verb: "POST",
        pattern: "/v1/wallets(.:format)",
        controller: "v1/wallets",
        action: "create",
        path: "/v1/wallets",
        payload: {
          customer_id: @source_wallet.customer.public_id,
          external_id: "v1-matrix-create-wallet"
        }
      },
      {
        verb: "POST",
        pattern: "/v1/fundings(.:format)",
        controller: "v1/fundings",
        action: "create",
        path: "/v1/fundings",
        payload: {
          wallet_id: @source_wallet.public_id,
          external_id: "v1-matrix-create-funding",
          amount_cents: 1_000
        }
      },
      {
        verb: "POST",
        pattern: "/v1/transfers(.:format)",
        controller: "v1/transfers",
        action: "create",
        path: "/v1/transfers",
        payload: {
          source_wallet_id: @source_wallet.public_id,
          destination_wallet_id: @destination_wallet.public_id,
          external_id: "v1-matrix-create-transfer",
          amount_cents: 1_000
        }
      },
      {
        verb: "POST",
        pattern: "/v1/split_payments(.:format)",
        controller: "v1/split_payments",
        action: "create",
        path: "/v1/split_payments",
        payload: {
          source_wallet_id: @source_wallet.public_id,
          external_id: "v1-matrix-create-split",
          entries: [
            { destination_wallet_id: @destination_wallet.public_id, amount_cents: 500 },
            { destination_wallet_id: @extra_wallet.public_id, amount_cents: 700 }
          ]
        }
      },
      {
        verb: "POST",
        pattern: "/v1/payouts(.:format)",
        controller: "v1/payouts",
        action: "create",
        path: "/v1/payouts",
        payload: {
          wallet_id: @source_wallet.public_id,
          external_id: "v1-matrix-create-payout",
          amount_cents: 1_000,
          destination_reference: "bank-account-create-v1-matrix"
        }
      },
      {
        verb: "POST",
        pattern: "/v1/payouts/:id/settle(.:format)",
        controller: "v1/payouts",
        action: "settle",
        path: "/v1/payouts/#{@payout.public_id}/settle",
        payload: {}
      },
      {
        verb: "POST",
        pattern: "/v1/pix_payments(.:format)",
        controller: "v1/pix_payments",
        action: "create",
        path: "/v1/pix_payments",
        payload: {
          wallet_id: @source_wallet.public_id,
          external_id: "v1-matrix-create-pix",
          pix_key: "create-v1-matrix@example.com",
          receiver_name: "Receiver",
          amount_cents: 1_000
        }
      },
      {
        verb: "POST",
        pattern: "/v1/pix_payments/:id/settle(.:format)",
        controller: "v1/pix_payments",
        action: "settle",
        path: "/v1/pix_payments/#{@pix_payment.public_id}/settle",
        payload: {}
      },
      {
        verb: "POST",
        pattern: "/v1/refunds(.:format)",
        controller: "v1/refunds",
        action: "create",
        path: "/v1/refunds",
        payload: {
          pix_payment_id: @pix_payment.public_id,
          external_id: "v1-matrix-create-refund",
          amount_cents: 500,
          reason: "customer_request"
        }
      },
      {
        verb: "POST",
        pattern: "/v1/med_cases(.:format)",
        controller: "v1/med_cases",
        action: "create",
        path: "/v1/med_cases",
        payload: {
          pix_payment_id: @pix_payment.public_id,
          external_id: "v1-matrix-create-med",
          amount_cents: 500,
          reason: "fraud_report"
        }
      },
      {
        verb: "POST",
        pattern: "/v1/med_cases/:id/accept(.:format)",
        controller: "v1/med_cases",
        action: "accept",
        path: "/v1/med_cases/#{@med_case.public_id}/accept",
        payload: {}
      },
      {
        verb: "POST",
        pattern: "/v1/med_cases/:id/reject(.:format)",
        controller: "v1/med_cases",
        action: "reject",
        path: "/v1/med_cases/#{@med_case.public_id}/reject",
        payload: {}
      },
      {
        verb: "POST",
        pattern: "/v1/reconciliation_runs(.:format)",
        controller: "v1/reconciliation_runs",
        action: "create",
        path: "/v1/reconciliation_runs",
        payload: {
          provider: "v1-matrix-create-bank",
          statement_date: Date.current.iso8601,
          provider_balance_cents: @source_wallet.balance_projection.reload.available_cents
        }
      }
    ]
  end

  def expected_route_inventory
    (read_surfaces + write_surfaces).map do |surface|
      [
        surface.fetch(:verb),
        surface.fetch(:pattern),
        surface.fetch(:controller),
        surface.fetch(:action)
      ]
    end.sort
  end

  def discovered_route_inventory
    Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller]
      action = route.defaults[:action]
      next unless controller&.start_with?("v1/")

      verb = normalize_verb(route.verb)
      next if verb.blank?

      [ verb, route.path.spec.to_s, controller, action ]
    end.sort
  end

  def write_side_effect_snapshot
    {
      customers: @organization.customers.count,
      wallets: @organization.wallets.count,
      fundings: @organization.fundings.count,
      transfers: @organization.transfers.count,
      split_payments: @organization.split_payments.count,
      payouts: @organization.payouts.count,
      pix_payments: @organization.pix_payments.count,
      refunds: @organization.refunds.count,
      med_cases: @organization.med_cases.count,
      reconciliation_runs: @organization.reconciliation_runs.count,
      journal_entries: @organization.journal_entries.count,
      ledger_lines: LedgerLine.joins(:journal_entry).where(journal_entries: { organization_id: @organization.id }).count,
      outbox_events: @organization.outbox_events.count,
      payout_status: @payout.reload.status,
      pix_payment_status: @pix_payment.reload.status,
      med_case_status: @med_case.reload.status
    }
  end

  def perform_request(surface, headers:)
    if surface.fetch(:verb) == "GET"
      get surface.fetch(:path), headers:
    else
      post surface.fetch(:path), params: surface.fetch(:payload).to_json, headers:
    end
  end

  def normalize_verb(route_verb)
    verb = route_verb.to_s
    return "POST" if verb.include?("POST")
    return "GET" if verb.include?("GET")

    nil
  end

  def json_headers
    {
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }
  end

  def failure_message(surface)
    "#{surface.fetch(:controller)}##{surface.fetch(:action)}"
  end
end
