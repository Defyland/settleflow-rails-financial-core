require "test_helper"

class PayoutLifecycleTest < ActiveSupport::TestCase
  setup do
    @organization = create_organization
    @wallet = create_wallet(organization: @organization)
    fund_wallet(organization: @organization, wallet: @wallet, external_id: "payout-funding", amount_cents: 10_000)
  end

  test "schedules a D+N payout by debiting wallet liability into payout clearing" do
    payout = create_payout(amount_cents: 4_000, settlement_delay_days: 2)

    assert payout.scheduled?
    assert_equal Date.current + 2, payout.settlement_due_on
    assert payout.journal_entry.balanced?
    assert_equal 6_000, @wallet.balance_projection.reload.available_cents
    assert_equal 4_000, Ledger::AccountLocator.payout_clearing(organization: @organization, currency: "BRL").balance_cents
    assert_equal "payout.scheduled", OutboxEvent.last.event_type
  end

  test "does not settle before D+N due date" do
    payout = create_payout(amount_cents: 4_000, settlement_delay_days: 2)

    assert_raises(Errors::ValidationError) do
      Payouts::Settle.call(organization: @organization, payout:)
    end

    assert payout.reload.scheduled?
    assert_nil payout.settlement_journal_entry
  end

  test "early payout settlement requires maker-checker approval" do
    payout = create_payout(amount_cents: 4_000, settlement_delay_days: 2)
    maker = create_operator("payout-early-maker")
    checker = create_operator("payout-early-checker")

    assert_raises(Errors::AuthorizationError) do
      Payouts::Settle.call(organization: @organization, payout:, force: true)
    end

    requested = Payouts::Settle.call(
      organization: @organization,
      payout:,
      force: true,
      operator: maker,
      reason: "provider_confirmed_early_settlement",
      correlation_id: "payout-early-corr"
    )
    assert_equal :requested, requested.status
    assert payout.reload.scheduled?

    approved = Payouts::Settle.call(
      organization: @organization,
      payout:,
      force: true,
      operator: checker,
      reason: "provider_confirmed_early_settlement",
      correlation_id: "payout-early-corr"
    )

    assert_equal :approved, approved.status
    settled = approved.subject
    assert settled.settled?
    assert_equal requested.approval.id, settled.operator_approval_id
    assert_equal checker.id, settled.operator_approval.approved_by_id
    assert settled.settled_at.to_date < settled.settlement_due_on
  end

  test "settles a due payout once through platform cash" do
    payout = create_payout(amount_cents: 4_000, settlement_delay_days: 0)
    settled = Payouts::Settle.call(organization: @organization, payout:, correlation_id: "payout-settle-corr")

    assert settled.settled?
    assert settled.settlement_journal_entry.balanced?
    assert_equal 0, Ledger::AccountLocator.payout_clearing(organization: @organization, currency: "BRL").balance_cents
    assert_equal 6_000, Ledger::AccountLocator.platform_cash(organization: @organization, currency: "BRL").balance_cents
    assert_equal "payout.settled", OutboxEvent.last.event_type
    assert_equal "payout-settle-corr", OutboxEvent.last.correlation_id

    assert_raises(Errors::ValidationError) do
      Payouts::Settle.call(organization: @organization, payout:)
    end
    assert_equal 1, @organization.journal_entries.where(reference: payout, event_type: "payout.settled").count
  end

  test "prevents negative available balance and missing idempotency" do
    assert_raises(Errors::IdempotencyKeyRequired) do
      Payouts::Create.call(
        organization: @organization,
        wallet: @wallet,
        external_id: "payout-missing-idem",
        amount_cents: 1_000,
        destination_reference: "bank-account"
      )
    end

    assert_raises(Errors::InsufficientFunds) do
      create_payout(external_id: "payout-too-large", amount_cents: 20_000)
    end

    assert_equal 10_000, @wallet.balance_projection.reload.available_cents
    assert_empty @organization.payouts.where(external_id: [ "payout-missing-idem", "payout-too-large" ])
  end

  private

  def create_payout(external_id: "payout-#{SecureRandom.hex(4)}", amount_cents:, settlement_delay_days: 1)
    Payouts::Create.call(
      organization: @organization,
      wallet: @wallet,
      external_id:,
      amount_cents:,
      settlement_delay_days:,
      destination_reference: "bank-account-#{external_id}",
      idempotency_key: external_id
    )
  end

  def create_operator(email_prefix)
    User.create!(
      email_address: "#{email_prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "strong-password-123",
      role: "admin"
    )
  end
end
