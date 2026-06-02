class PayoutSerializer
  def self.render(payout)
    {
      id: payout.public_id,
      external_id: payout.external_id,
      wallet_id: payout.wallet.public_id,
      journal_entry_id: payout.journal_entry&.public_id,
      settlement_journal_entry_id: payout.settlement_journal_entry&.public_id,
      operator_approval_id: payout.operator_approval&.public_id,
      amount_cents: payout.amount_cents,
      currency: payout.currency,
      status: payout.status,
      settlement_delay_days: payout.settlement_delay_days,
      settlement_due_on: payout.settlement_due_on.iso8601,
      settled_at: payout.settled_at&.iso8601,
      destination_kind: payout.destination_kind,
      destination_reference: payout.destination_reference,
      failure_code: payout.failure_code,
      metadata: payout.metadata,
      created_at: payout.created_at.iso8601
    }
  end
end
