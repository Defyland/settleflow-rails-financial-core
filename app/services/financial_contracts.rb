module FinancialContracts
  module Events
    WALLET_FUNDED = "wallet.funded"
    WALLET_TRANSFER_POSTED = "wallet.transfer.posted"
    SPLIT_POSTED = "split.posted"
    PIX_PAYMENT_APPROVED = "pix.payment.approved"
    PIX_PAYMENT_PENDING_REVIEW = "pix.payment.pending_review"
    PIX_PAYMENT_REJECTED = "pix.payment.rejected"
    PIX_PAYMENT_SETTLED = "pix.payment.settled"
    PIX_PAYMENT_REVERSED = "pix.payment.reversed"
    PAYOUT_SCHEDULED = "payout.scheduled"
    PAYOUT_SETTLED = "payout.settled"
    REFUND_SETTLED = "refund.settled"
    MED_CASE_OPENED = "med.case.opened"
    MED_CASE_REJECTED = "med.case.rejected"
    MED_CASE_REFUNDED = "med.case.refunded"
    RECONCILIATION_MATCHED = "reconciliation.matched"
    RECONCILIATION_DISCREPANT = "reconciliation.discrepant"
  end

  module Actions
    PAYOUT_SETTLE_EARLY = "payout.settle_early"
    MED_CASE_ACCEPT = "med_case.accept"
    MED_CASE_REJECT = "med_case.reject"
  end

  RECONCILIATION_EVENT_TYPES = [
    Events::RECONCILIATION_MATCHED,
    Events::RECONCILIATION_DISCREPANT
  ].freeze

  JOURNAL_EVENT_TYPES = [
    Events::WALLET_FUNDED,
    Events::WALLET_TRANSFER_POSTED,
    Events::SPLIT_POSTED,
    Events::PIX_PAYMENT_APPROVED,
    Events::PIX_PAYMENT_SETTLED,
    Events::PIX_PAYMENT_REVERSED,
    Events::PAYOUT_SCHEDULED,
    Events::PAYOUT_SETTLED,
    Events::REFUND_SETTLED
  ].freeze

  FINANCIAL_COMMAND_AGGREGATE_TYPES = %w[
    Funding
    Transfer
    SplitPayment
    PixPayment
    Payout
    Refund
    MedCase
  ].freeze

  IDEMPOTENCY_REQUIRED_COMMAND_CONSTRAINTS = {
    "fundings" => "fundings_idempotency_key_required_check",
    "transfers" => "transfers_idempotency_key_required_check",
    "split_payments" => "split_payments_idempotency_key_required_check",
    "pix_payments" => "pix_payments_idempotency_key_required_check",
    "payouts" => "payouts_idempotency_key_required_check",
    "refunds" => "refunds_idempotency_key_required_check",
    "med_cases" => "med_cases_idempotency_key_required_check"
  }.freeze

  OUTBOX_EVIDENCE_CONSTRAINTS = %w[
    outbox_events_payload_sha256_hex_check
    outbox_events_status_check
    outbox_events_delivery_state_check
  ].freeze

  OUTBOX_EVIDENCE_TRIGGERS = %w[
    outbox_legacy_command_identity_exceptions_prevent_mutation
    outbox_events_prevent_evidence_mutation
    outbox_events_aggregate_evidence_before_write
    outbox_events_med_resolution_payload_before_write
    outbox_events_command_identity_before_write
  ].freeze

  FINANCIAL_STATE_EVIDENCE_TRIGGERS = %w[
    fundings_state_evidence_after_write
    fundings_prevent_evidence_mutation
    transfers_state_evidence_after_write
    transfers_prevent_evidence_mutation
    split_payments_state_evidence_after_write
    split_payments_prevent_evidence_mutation
    split_entries_state_evidence_after_write
    split_entries_prevent_evidence_mutation
    payouts_state_evidence_after_write
    payouts_prevent_evidence_mutation
    refunds_state_evidence_after_write
    refunds_prevent_evidence_mutation
    refunds_lock_pix_payment_before_write
    refunds_pix_payment_evidence_after_write
    pix_payments_refund_evidence_after_write
    med_cases_state_evidence_after_write
    med_cases_prevent_evidence_mutation
    pix_payments_state_evidence_after_write
    pix_payments_prevent_evidence_mutation
  ].freeze

  FINANCIAL_JOURNAL_EVIDENCE_TRIGGERS = %w[
    journal_entries_financial_evidence_after_write
    ledger_lines_financial_evidence_after_write
    fundings_journal_evidence_after_write
    transfers_journal_evidence_after_write
    split_payments_journal_evidence_after_write
    pix_payments_journal_evidence_after_write
    payouts_journal_evidence_after_write
    refunds_journal_evidence_after_write
  ].freeze

  module_function

  def pix_payment_settlement_key(pix_payment)
    "pix_payment.settle:#{record_id(pix_payment)}"
  end

  def pix_payment_reversal_key(pix_payment)
    "pix_payment.reverse:#{record_id(pix_payment)}"
  end

  def pix_payment_rejection_key(pix_payment)
    "pix_payment.reject:#{record_id(pix_payment)}"
  end

  def payout_settlement_key(payout)
    "payout.settle:#{record_id(payout)}"
  end

  def med_case_acceptance_key(med_case)
    "med_case.accept:#{record_id(med_case)}"
  end

  def med_case_rejection_key(med_case)
    "med_case.reject:#{record_id(med_case)}"
  end

  def med_case_refund_key(med_case)
    "med_case.refund:#{record_id(med_case)}"
  end

  def record_id(record_or_id)
    record_or_id.respond_to?(:id) ? record_or_id.id : record_or_id
  end
  private_class_method :record_id
end
