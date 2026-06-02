class MedCase < ApplicationRecord
  belongs_to :organization
  belongs_to :pix_payment
  belongs_to :refund, optional: true
  belongs_to :operator_approval, optional: true

  enum :status, { opened: "opened", rejected: "rejected", refunded: "refunded" }

  validates :external_id, :amount_cents, :currency, :reason, :opened_at, :idempotency_key, presence: true
  validates :external_id, uniqueness: { scope: :organization_id }
  validates :idempotency_key, uniqueness: { scope: :organization_id }
  validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
  validate :pix_payment_belongs_to_organization
  validate :currency_matches_pix_payment
  validate :terminal_status_has_approved_operator_evidence
  validate :refunded_status_has_matching_refund_evidence

  private

  def pix_payment_belongs_to_organization
    return if pix_payment.blank? || organization_id.blank? || pix_payment.organization_id == organization_id

    errors.add(:pix_payment, "must belong to organization")
  end

  def currency_matches_pix_payment
    return if pix_payment.blank? || currency.blank? || pix_payment.currency == currency

    errors.add(:currency, "must match Pix payment currency")
  end

  def terminal_status_has_approved_operator_evidence
    return if opened?

    if operator_approval.blank?
      errors.add(:operator_approval, "must approve terminal MED resolution")
      return
    end

    expected_action = refunded? ? "med_case.accept" : "med_case.reject"
    return if operator_approval.organization_id == organization_id &&
      operator_approval.subject_type == self.class.name &&
      operator_approval.subject_id == id &&
      operator_approval.approved? &&
      operator_approval.action == expected_action

    errors.add(:operator_approval, "must match the approved MED resolution action")
  end

  def refunded_status_has_matching_refund_evidence
    return unless refunded?

    if refund.blank?
      errors.add(:refund, "must be present for refunded MED cases")
      return
    end

    return if refund.organization_id == organization_id &&
      refund.pix_payment_id == pix_payment_id &&
      refund.amount_cents == amount_cents &&
      refund.currency == currency &&
      refund.status == "settled" &&
      refund.idempotency_key == "med_case.refund:#{id}"

    errors.add(:refund, "must match the MED case Pix payment, amount, currency, and deterministic key")
  end
end
