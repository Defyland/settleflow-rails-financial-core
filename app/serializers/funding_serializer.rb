class FundingSerializer
  def self.render(funding)
    {
      id: funding.public_id,
      external_id: funding.external_id,
      wallet_id: funding.wallet.public_id,
      journal_entry_id: funding.journal_entry&.public_id,
      amount_cents: funding.amount_cents,
      currency: funding.currency,
      status: funding.status,
      failure_code: funding.failure_code,
      metadata: funding.metadata,
      created_at: funding.created_at.iso8601
    }
  end
end
