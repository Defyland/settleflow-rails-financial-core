require "test_helper"
require "tmpdir"

class DatabaseMigrationSafetyCheckerTest < ActiveSupport::TestCase
  test "flags blocking indexes on high-volume tables" do
    with_migration("20260601000000_add_blocking_index.rb", <<~RUBY) do |root|
      class AddBlockingIndex < ActiveRecord::Migration[8.1]
        def change
          add_index :journal_entries, :occurred_at
        end
      end
    RUBY
      findings = Database::MigrationSafetyChecker.call(root:)

      assert_equal 1, findings.size
      assert_equal :high, findings.first.severity
      assert_match(/created concurrently/, findings.first.message)
    end
  end

  test "allows concurrent indexes when ddl transaction is disabled" do
    with_migration("20260601000000_add_concurrent_index.rb", <<~RUBY) do |root|
      class AddConcurrentIndex < ActiveRecord::Migration[8.1]
        disable_ddl_transaction!

        def change
          add_index :journal_entries, :occurred_at, algorithm: :concurrently
        end
      end
    RUBY
      assert_empty Database::MigrationSafetyChecker.call(root:)
    end
  end

  test "allows validated high-volume check constraints" do
    with_migration("20260601000000_add_validated_check.rb", <<~RUBY) do |root|
      class AddValidatedCheck < ActiveRecord::Migration[8.1]
        def up
          add_check_constraint :journal_entries, "idempotency_key IS NOT NULL", name: "journal_entries_idempotency_key_required_check", validate: false
          validate_check_constraint :journal_entries, name: "journal_entries_idempotency_key_required_check"
          change_column_null :journal_entries, :idempotency_key, false
        end
      end
    RUBY
      assert_empty Database::MigrationSafetyChecker.call(root:)
    end
  end

  private

  def with_migration(filename, body)
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      migration_dir = root.join("db/migrate")
      FileUtils.mkdir_p(migration_dir)
      File.write(migration_dir.join(filename), body)
      yield root
    end
  end
end
