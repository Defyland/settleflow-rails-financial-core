class BalanceProjectionSerializer
  def self.render(balance)
    {
      available_cents: balance.available_cents,
      pending_cents: balance.pending_cents,
      blocked_cents: balance.blocked_cents,
      currency: balance.currency,
      version: balance.lock_version,
      updated_at: balance.updated_at.iso8601
    }
  end
end
