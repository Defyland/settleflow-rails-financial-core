class RefundSerializer
  def self.render(refund)
    {
      id: refund.public_id,
      external_id: refund.external_id,
      wallet_id: refund.wallet.public_id,
      pix_payment_id: refund.pix_payment.public_id,
      journal_entry_id: refund.journal_entry&.public_id,
      amount_cents: refund.amount_cents,
      currency: refund.currency,
      status: refund.status,
      reason: refund.reason,
      settled_at: refund.settled_at&.iso8601,
      failure_code: refund.failure_code,
      metadata: refund.metadata,
      created_at: refund.created_at.iso8601
    }
  end
end
