class RequireJournalEntryReferences < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE journal_entries
         SET reference_type = 'LegacyJournalEntry',
             reference_id = id
       WHERE reference_type IS NULL
          OR reference_id IS NULL
    SQL

    add_check_constraint :journal_entries,
      "reference_type IS NOT NULL AND reference_id IS NOT NULL",
      name: "journal_entries_reference_required_check"
  end

  def down
    remove_check_constraint :journal_entries, name: "journal_entries_reference_required_check"
  end
end
