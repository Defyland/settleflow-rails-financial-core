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
