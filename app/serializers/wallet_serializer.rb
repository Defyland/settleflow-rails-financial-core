class WalletSerializer
  def self.render(wallet)
    {
      id: wallet.public_id,
      external_id: wallet.external_id,
      customer_id: wallet.customer.public_id,
      currency: wallet.currency,
      status: wallet.status,
      balance: BalanceProjectionSerializer.render(wallet.balance_projection),
      metadata: Privacy::Redactor.metadata(wallet.metadata),
      created_at: wallet.created_at.iso8601
    }
  end
end
