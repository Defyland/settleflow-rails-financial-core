class PixPaymentSerializer
  def self.render(pix_payment)
    {
      id: pix_payment.public_id,
      external_id: pix_payment.external_id,
      wallet_id: pix_payment.wallet.public_id,
      journal_entry_id: pix_payment.journal_entry&.public_id,
      settlement_journal_entry_id: pix_payment.settlement_journal_entry&.public_id,
      reversal_journal_entry_id: pix_payment.reversal_journal_entry&.public_id,
      pix_key: pix_payment.pix_key,
      receiver_name: pix_payment.receiver_name,
      amount_cents: pix_payment.amount_cents,
      currency: pix_payment.currency,
      status: pix_payment.status,
      risk_score: pix_payment.risk_score,
      failure_code: pix_payment.failure_code,
      reversal_reason: pix_payment.reversal_reason,
      reversed_at: pix_payment.reversed_at&.iso8601,
      metadata: pix_payment.metadata,
      created_at: pix_payment.created_at.iso8601
    }
  end
end
