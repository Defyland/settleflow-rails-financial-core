require "test_helper"

class RefundAndMedLifecycleTest < ActiveSupport::TestCase
  setup do
    @organization = create_organization
    @wallet = create_wallet(organization: @organization)
    fund_wallet(organization: @organization, wallet: @wallet, external_id: "refund-funding", amount_cents: 20_000)
    @pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "refund-pix",
      pix_key: "refund-receiver@example.com",
      amount_cents: 5_000
    )
    PixPayments::Settle.call(organization: @organization, pix_payment: @pix_payment)
  end

  test "settles a partial refund and restores wallet balance" do
    refund = create_refund(external_id: "refund-001", amount_cents: 2_000)

    assert refund.settled?
    assert refund.journal_entry.balanced?
    assert_equal 17_000, @wallet.balance_projection.reload.available_cents
    assert_equal 17_000, Ledger::AccountLocator.platform_cash(organization: @organization, currency: "BRL").balance_cents
    assert_equal "refund.settled", OutboxEvent.last.event_type
  end

  test "prevents over-refund and direct Pix reversal after refund" do
    create_refund(external_id: "refund-001", amount_cents: 2_000)
    create_refund(external_id: "refund-002", amount_cents: 3_000)

    assert_raises(Errors::ValidationError) do
      create_refund(external_id: "refund-too-large", amount_cents: 1)
    end

    assert_raises(Errors::ValidationError) do
      PixPayments::Reverse.call(organization: @organization, pix_payment: @pix_payment, reason: "operator_reversal")
    end

    assert_equal 20_000, @wallet.balance_projection.reload.available_cents
    assert_equal 2, @organization.refunds.where(pix_payment: @pix_payment).count
    assert_nil @pix_payment.reload.reversal_journal_entry
  end

  test "requires idempotency before creating refund state" do
    assert_raises(Errors::IdempotencyKeyRequired) do
      Refunds::Create.call(
        organization: @organization,
        pix_payment: @pix_payment,
        external_id: "refund-missing-idem",
        amount_cents: 1_000,
        reason: "customer_request"
      )
    end

    assert_empty @organization.refunds.where(external_id: "refund-missing-idem")
  end

  test "opens and accepts a MED case with exactly one linked refund" do
    med_case = open_med_case(external_id: "med-001", amount_cents: 3_000)
    stale_med_case = MedCase.find(med_case.id)
    maker = create_operator("med-maker")
    checker = create_operator("med-checker")

    requested = MedCases::Accept.call(
      organization: @organization,
      med_case:,
      operator: maker,
      reason: "fraud_confirmed",
      correlation_id: "med-accept-corr"
    )
    assert_equal :requested, requested.status
    assert med_case.reload.opened?

    approved = MedCases::Accept.call(
      organization: @organization,
      med_case:,
      operator: checker,
      reason: "fraud_confirmed",
      correlation_id: "med-accept-corr"
    )
    accepted = approved.subject

    assert_equal :approved, approved.status
    assert accepted.refunded?
    assert accepted.refund.settled?
    assert_equal requested.approval.id, accepted.operator_approval_id
    assert_equal checker.id, accepted.operator_approval.approved_by_id
    assert_equal accepted.refund_id, accepted.reload.refund_id
    assert_equal 18_000, @wallet.balance_projection.reload.available_cents
    assert_equal "med.case.refunded", OutboxEvent.last.event_type
    assert_equal "med-accept-corr", OutboxEvent.last.correlation_id
    assert_equal requested.approval.public_id, OutboxEvent.last.payload.fetch("operator_approval_id")
    assert_equal accepted.refund.public_id, OutboxEvent.last.payload.fetch("refund_id")

    assert_raises(Errors::ValidationError) do
      MedCases::Accept.call(organization: @organization, med_case: stale_med_case, operator: maker)
    end
    assert_equal 1, @organization.refunds.where(idempotency_key: FinancialContracts.med_case_refund_key(med_case)).count
  end

  test "rejects a MED case without ledger mutation" do
    med_case = open_med_case(external_id: "med-rejected", amount_cents: 3_000)
    maker = create_operator("med-reject-maker")
    checker = create_operator("med-reject-checker")

    requested = MedCases::Reject.call(
      organization: @organization,
      med_case:,
      operator: maker,
      reason: "insufficient_evidence"
    )
    assert_equal :requested, requested.status

    approved = MedCases::Reject.call(
      organization: @organization,
      med_case:,
      operator: checker,
      reason: "insufficient_evidence"
    )
    rejected = approved.subject

    assert_equal :approved, approved.status
    assert rejected.rejected?
    assert_equal requested.approval.id, rejected.operator_approval_id
    assert_nil rejected.refund
    assert_equal requested.approval.public_id, OutboxEvent.last.payload.fetch("operator_approval_id")
    assert_equal "insufficient_evidence", rejected.metadata.fetch("rejection_reason")
    assert_equal 15_000, @wallet.balance_projection.reload.available_cents
    assert_empty @organization.refunds.where(metadata: { "med_case_id" => med_case.public_id })
  end

  test "does not open MED for unsettled Pix payments" do
    unsettled = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "med-unsettled-pix",
      pix_key: "med-unsettled@example.com",
      amount_cents: 1_000
    )

    assert_raises(Errors::ValidationError) do
      MedCases::Open.call(
        organization: @organization,
        pix_payment: unsettled,
        external_id: "med-unsettled",
        amount_cents: 1_000,
        reason: "fraud_report",
        idempotency_key: "med-unsettled"
      )
    end

    assert_empty @organization.med_cases.where(external_id: "med-unsettled")
  end

  private

  def create_refund(external_id:, amount_cents:)
    Refunds::Create.call(
      organization: @organization,
      pix_payment: @pix_payment,
      external_id:,
      amount_cents:,
      reason: "customer_request",
      idempotency_key: external_id
    )
  end

  def open_med_case(external_id:, amount_cents:)
    MedCases::Open.call(
      organization: @organization,
      pix_payment: @pix_payment,
      external_id:,
      amount_cents:,
      reason: "fraud_report",
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
