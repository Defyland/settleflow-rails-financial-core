module Ops
  class DashboardController < BaseController
    def show
      @wallets_count = Wallet.count
      @available_cents = BalanceProjection.sum(:available_cents)
      @pending_review_count = PixPayment.pending_review.count
      @outbox_attention_count = OutboxEvent.attention.count
      @recent_journal_entries = JournalEntry.includes(:organization).order(occurred_at: :desc).limit(8)
      @recent_pix_payments = PixPayment.includes(:organization, :wallet).order(created_at: :desc).limit(8)
      @discrepant_reconciliations = ReconciliationRun.discrepant.order(created_at: :desc).limit(6)
    end
  end
end
