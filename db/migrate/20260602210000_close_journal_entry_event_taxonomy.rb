class CloseJournalEntryEventTaxonomy < ActiveRecord::Migration[8.1]
  def up
    raise_if_unknown_journal_event_types_exist

    add_check_constraint(
      :journal_entries,
      "financial_journal_event_type_requires_evidence(event_type)",
      name: "journal_entries_event_type_supported_check",
      validate: false
    )
    validate_check_constraint :journal_entries, name: "journal_entries_event_type_supported_check"
  end

  def down
    remove_check_constraint :journal_entries, name: "journal_entries_event_type_supported_check", if_exists: true
  end

  private

  def raise_if_unknown_journal_event_types_exist
    unknown_event_types = select_values(<<~SQL.squish)
      SELECT DISTINCT event_type
      FROM journal_entries
      WHERE NOT financial_journal_event_type_requires_evidence(event_type)
      ORDER BY event_type
    SQL
    return if unknown_event_types.empty?

    raise ActiveRecord::MigrationError,
      "unknown journal_entries.event_type values exist: #{unknown_event_types.join(", ")}"
  end
end
