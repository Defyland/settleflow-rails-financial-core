module Database
  module ConsistencyChecks
    class JournalEventTaxonomy < Base
      def call
        constraint_validated = catalog_value(<<~SQL.squish)
          SELECT EXISTS (
            SELECT 1
            FROM pg_constraint
            WHERE conrelid = 'journal_entries'::regclass
              AND conname = 'journal_entries_event_type_supported_check'
              AND convalidated
          )
        SQL
        unknown_event_types = JournalEntry
          .where.not(event_type: JournalEntry::SUPPORTED_EVENT_TYPES)
          .distinct
          .order(:event_type)
          .pluck(:event_type)

        check(
          name: :journal_event_taxonomy,
          ok: constraint_validated && unknown_event_types.empty?,
          details: {
            constraint_validated:,
            supported_event_types: JournalEntry::SUPPORTED_EVENT_TYPES,
            unknown_event_types:
          }
        )
      end
    end
  end
end
