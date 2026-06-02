class SplitPaymentSerializer
  def self.render(split_payment)
    {
      id: split_payment.public_id,
      external_id: split_payment.external_id,
      source_wallet_id: split_payment.source_wallet.public_id,
      journal_entry_id: split_payment.journal_entry&.public_id,
      total_amount_cents: split_payment.total_amount_cents,
      currency: split_payment.currency,
      status: split_payment.status,
      memo: split_payment.memo,
      failure_code: split_payment.failure_code,
      entries: split_payment.split_entries.includes(:destination_wallet).map do |entry|
        {
          id: entry.public_id,
          destination_wallet_id: entry.destination_wallet.public_id,
          amount_cents: entry.amount_cents,
          currency: entry.currency,
          metadata: entry.metadata
        }
      end,
      metadata: split_payment.metadata,
      created_at: split_payment.created_at.iso8601
    }
  end
end
