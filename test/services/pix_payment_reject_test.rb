require "test_helper"

class PixPaymentRejectTest < ActiveSupport::TestCase
  setup do
    @organization = create_organization
    @wallet = create_wallet(organization: @organization)
    fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "reject-funding",
      amount_cents: 1_000_000
    )
  end

  test "rejects a pending-review Pix payment and emits an outbox event" do
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "reject-pix-review",
      pix_key: "review@example.com",
      amount_cents: 600_000
    )

    rejected = PixPayments::Reject.call(
      organization: @organization,
      pix_payment:,
      reason: "operator_rejected",
      correlation_id: "corr-123"
    )

    assert rejected.rejected?
    assert_equal "operator_rejected", rejected.failure_code
    assert_includes rejected.metadata, "operator_rejected_at"
    assert_equal "PixPayment", OutboxEvent.last.aggregate_type
    assert_equal pix_payment.id, OutboxEvent.last.aggregate_id
    assert_equal "pix.payment.rejected", OutboxEvent.last.event_type
    assert_equal "corr-123", OutboxEvent.last.correlation_id
  end

  test "rejects cross-organization calls" do
    other_organization = create_organization
    pix_payment = build_pix_payment(organization: @organization, wallet: @wallet, status: "pending_review")

    assert_raises(Errors::ValidationError) do
      PixPayments::Reject.call(organization: other_organization, pix_payment:, reason: "operator_rejected")
    end
  end

  test "only rejects pending-review Pix payments" do
    pix_payment = build_pix_payment(organization: @organization, wallet: @wallet, status: "approved")

    assert_raises(Errors::ValidationError) do
      PixPayments::Reject.call(organization: @organization, pix_payment:, reason: "operator_rejected")
    end
  end

  test "revalidates status after locking a stale pending-review instance" do
    pix_payment = build_pix_payment(organization: @organization, wallet: @wallet, status: "pending_review")
    stale_pix_payment = PixPayment.find(pix_payment.id)
    pix_payment.update!(status: "approved")

    assert_raises(Errors::ValidationError) do
      PixPayments::Reject.call(organization: @organization, pix_payment: stale_pix_payment, reason: "operator_rejected")
    end

    assert pix_payment.reload.approved?
    assert_empty OutboxEvent.where(aggregate_type: "PixPayment", aggregate_id: pix_payment.id, event_type: "pix.payment.rejected")
  end
end
