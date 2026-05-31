require "test_helper"

class PixPaymentLifecycleTest < ActiveSupport::TestCase
  setup do
    @organization = create_organization
    @wallet = create_wallet(organization: @organization)
    fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "pix-funding",
      amount_cents: 20_000
    )
  end

  test "approves low-risk payments, debits the wallet, and enqueues settlement" do
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "pix-001",
      pix_key: "receiver@example.com",
      amount_cents: 4_000
    )

    assert pix_payment.approved?
    assert_equal 16_000, @wallet.balance_projection.reload.available_cents
    assert_includes enqueued_jobs.map { |job| job[:job] }, PixSettlementJob
  end

  test "settles approved payments through the Pix clearing account" do
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "pix-002",
      pix_key: "receiver2@example.com",
      amount_cents: 3_000
    )

    settled = PixPayments::Settle.call(organization: @organization, pix_payment:)

    assert settled.settled?
    assert settled.settlement_journal_entry.balanced?
    assert_equal 0, Ledger::AccountLocator.pix_clearing(organization: @organization, currency: "BRL").balance_cents
  end

  test "does not settle from a stale approved instance after another worker settled it" do
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "pix-stale-settle",
      pix_key: "stale-settle@example.com",
      amount_cents: 3_000
    )
    stale_pix_payment = PixPayment.find(pix_payment.id)

    PixPayments::Settle.call(organization: @organization, pix_payment:)

    assert_raises(Errors::ValidationError) do
      PixPayments::Settle.call(organization: @organization, pix_payment: stale_pix_payment)
    end
    assert_equal 1, @organization.journal_entries.where(reference: pix_payment, event_type: "pix.payment.settled").count
  end

  test "reverses settled payments through a compensating journal entry" do
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "pix-005",
      pix_key: "receiver5@example.com",
      amount_cents: 3_000
    )
    PixPayments::Settle.call(organization: @organization, pix_payment:)

    reversed = PixPayments::Reverse.call(
      organization: @organization,
      pix_payment:,
      reason: "provider_returned",
      correlation_id: "reverse-corr"
    )

    assert reversed.reversed?
    assert_equal "provider_returned", reversed.reversal_reason
    assert reversed.reversal_journal_entry.balanced?
    assert_equal 20_000, @wallet.balance_projection.reload.available_cents
    assert_equal 20_000, Ledger::AccountLocator.platform_cash(organization: @organization, currency: "BRL").balance_cents
    assert_equal "pix.payment.reversed", OutboxEvent.last.event_type
    assert_equal "reverse-corr", OutboxEvent.last.correlation_id
  end

  test "does not reverse from a stale settled instance after another worker reversed it" do
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "pix-stale-reverse",
      pix_key: "stale-reverse@example.com",
      amount_cents: 3_000
    )
    PixPayments::Settle.call(organization: @organization, pix_payment:)
    stale_pix_payment = PixPayment.find(pix_payment.id)

    PixPayments::Reverse.call(organization: @organization, pix_payment:, reason: "provider_returned")

    assert_raises(Errors::ValidationError) do
      PixPayments::Reverse.call(organization: @organization, pix_payment: stale_pix_payment, reason: "provider_returned")
    end
    assert_equal 1, @organization.journal_entries.where(reference: pix_payment, event_type: "pix.payment.reversed").count
  end

  test "does not reverse payments that have not settled" do
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "pix-006",
      pix_key: "receiver6@example.com",
      amount_cents: 3_000
    )

    assert_raises(Errors::ValidationError) do
      PixPayments::Reverse.call(organization: @organization, pix_payment:, reason: "operator_reversal")
    end

    assert pix_payment.reload.approved?
    assert_nil pix_payment.reversal_journal_entry
  end

  test "does not reverse payments across organizations" do
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "pix-007",
      pix_key: "receiver7@example.com",
      amount_cents: 3_000
    )
    PixPayments::Settle.call(organization: @organization, pix_payment:)

    assert_raises(Errors::ValidationError) do
      PixPayments::Reverse.call(organization: create_organization, pix_payment:, reason: "operator_reversal")
    end

    assert pix_payment.reload.settled?
    assert_nil pix_payment.reversal_journal_entry
  end

  test "sends suspicious medium-risk payments to manual review without debiting balance" do
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "pix-003",
      pix_key: "receiver3@example.com",
      amount_cents: 600_000
    )

    assert pix_payment.pending_review?
    assert_equal 20_000, @wallet.balance_projection.reload.available_cents
  end

  test "rejects high-risk payments before ledger mutation" do
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "pix-004",
      pix_key: "blocked@example.com",
      amount_cents: 600_000
    )

    assert pix_payment.rejected?
    assert_equal "risk_rejected", pix_payment.failure_code
    assert_equal 20_000, @wallet.balance_projection.reload.available_cents
  end
end
