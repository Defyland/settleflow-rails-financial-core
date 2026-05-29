class TransferSerializer
  def self.render(transfer)
    {
      id: transfer.public_id,
      external_id: transfer.external_id,
      source_wallet_id: transfer.source_wallet.public_id,
      destination_wallet_id: transfer.destination_wallet.public_id,
      journal_entry_id: transfer.journal_entry&.public_id,
      amount_cents: transfer.amount_cents,
      currency: transfer.currency,
      status: transfer.status,
      memo: transfer.memo,
      failure_code: transfer.failure_code,
      metadata: transfer.metadata,
      created_at: transfer.created_at.iso8601
    }
  end
end
