class BalanceProjectionSerializer
  def self.render(balance)
    {
      available_cents: balance.available_cents,
      currency: balance.currency,
      version: balance.lock_version,
      updated_at: balance.updated_at.iso8601
    }
  end
end
