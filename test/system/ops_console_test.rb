require "application_system_test_case"

class OpsConsoleTest < ApplicationSystemTestCase
  setup do
    @operator = users(:operator)
    suffix = "#{name.parameterize}-#{SecureRandom.hex(4)}"
    @organization = Organization.create!(
      name: "System Test Fintech",
      slug: "system-test-#{suffix}",
      api_key_digest: Organization.digest_api_key("system-test-key-#{suffix}")
    )
    Accounts::BootstrapOrganizationLedger.call(organization: @organization, currency: "BRL")
    customer = @organization.customers.create!(
      external_id: "customer-#{suffix}",
      legal_name: "System Test Customer",
      document_kind: "cpf",
      document_number: "11144477735-#{suffix}",
      metadata: {}
    )
    @wallet = Wallets::Creator.call(
      organization: @organization,
      customer:,
      external_id: "wallet-#{suffix}",
      currency: "BRL",
      metadata: {}
    )
    Fundings::Create.call(
      organization: @organization,
      wallet: @wallet,
      external_id: "funding-#{suffix}",
      amount_cents: 1_000_000,
      idempotency_key: "funding-#{suffix}",
      correlation_id: suffix,
      metadata: {}
    )
    @pending_pix_payment = PixPayments::Create.call(
      organization: @organization,
      wallet: @wallet,
      external_id: "pix-review-#{suffix}",
      pix_key: "review-#{suffix}@example.com",
      receiver_name: "Manual Review Receiver",
      amount_cents: 600_000,
      idempotency_key: "pix-review-#{suffix}",
      correlation_id: suffix,
      metadata: {}
    )
    Reconciliation::Run.call(
      organization: @organization,
      provider: "system-bank",
      statement_date: Date.current,
      provider_balance_cents: 975_000,
      correlation_id: suffix,
      metadata: {}
    )
  end

  test "operator signs in and rejects a pending Pix payment" do
    sign_in

    assert_text "Financial operations"
    assert_text "PIX PENDING REVIEW"

    assert_selector :link, "Pix review", href: ops_pix_payments_path(status: "pending_review")
    visit ops_pix_payments_path(status: "pending_review")
    assert_current_path ops_pix_payments_path, ignore_query: true
    assert_text "Manual Review Receiver", wait: 10

    assert_selector :link, @pending_pix_payment.public_id.to_s.first(8), href: ops_pix_payment_path(@pending_pix_payment.public_id)
    visit ops_pix_payment_path(@pending_pix_payment.public_id)
    assert_current_path ops_pix_payment_path(@pending_pix_payment.public_id), ignore_query: true
    assert_text "RISK SCORE"

    click_button "Reject"

    assert_text "Pix payment rejected.", wait: 10
    assert_text "Rejected"
    assert @pending_pix_payment.reload.rejected?
    assert AuditLog.exists?(actor_type: "user", actor_id: @operator.id, action: "ops.pix_payment.reject")
  end

  test "ops console requires authentication" do
    visit ops_root_path

    assert_current_path new_session_path, ignore_query: true
    assert_text "Operator sign in"
  end

  private

  def sign_in
    visit new_session_path
    fill_in "Email address", with: @operator.email_address
    fill_in "Password", with: "password"
    click_button "Sign in"
  end
end
