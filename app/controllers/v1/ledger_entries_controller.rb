module V1
  class LedgerEntriesController < BaseController
    def index
      render_success PagedCollectionSerializer.render(
        current_organization.journal_entries.includes(:ledger_lines).order(occurred_at: :desc),
        params:,
        item_serializer: JournalEntrySerializer
      )
    end

    def show
      render_success data: JournalEntrySerializer.render(journal_entry)
    end

    private

    def journal_entry
      @journal_entry ||= find_by_public_id!(current_organization.journal_entries.includes(ledger_lines: :ledger_account), params[:id])
    end
  end
end
