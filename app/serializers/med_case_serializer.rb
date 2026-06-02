class MedCaseSerializer
  def self.render(med_case)
    {
      id: med_case.public_id,
      external_id: med_case.external_id,
      pix_payment_id: med_case.pix_payment.public_id,
      refund_id: med_case.refund&.public_id,
      operator_approval_id: med_case.operator_approval&.public_id,
      amount_cents: med_case.amount_cents,
      currency: med_case.currency,
      status: med_case.status,
      reason: med_case.reason,
      opened_at: med_case.opened_at.iso8601,
      resolved_at: med_case.resolved_at&.iso8601,
      metadata: med_case.metadata,
      created_at: med_case.created_at.iso8601
    }
  end
end
