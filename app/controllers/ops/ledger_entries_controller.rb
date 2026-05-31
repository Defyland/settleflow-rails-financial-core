module Ops
  class LedgerEntriesController < BaseController
    def index
      scope = JournalEntry.includes(:organization, ledger_lines: :ledger_account).order(occurred_at: :desc)
      scope = search_like(scope.joins(:organization), %w[journal_entries.event_type journal_entries.correlation_id organizations.slug]) if params[:q].present?
      @journal_entries = paginate(scope)
    end

    def show
      @journal_entry = find_public!(JournalEntry.includes(:organization, ledger_lines: :ledger_account), params[:id])
    end
  end
end
