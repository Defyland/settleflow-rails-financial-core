require "test_helper"

class DatabasePitrReadinessTest < ActiveSupport::TestCase
  test "passes when PostgreSQL WAL archive settings are PITR-ready" do
    checks = Database::PitrReadiness.call(
      adapter: "postgresql",
      settings: settings(
        "wal_level" => "replica",
        "archive_mode" => "on",
        "archive_command" => "test ! -f /archives/%f && cp %p /archives/%f",
        "archive_library" => "",
        "max_wal_senders" => "10"
      ),
      lsn: "0/16B6C50"
    )

    assert checks.all?(&:ok), checks.map(&:to_h).inspect
  end

  test "fails when archive mode is off or archive command is fake" do
    checks = Database::PitrReadiness.call(
      adapter: "postgresql",
      settings: settings(
        "wal_level" => "replica",
        "archive_mode" => "off",
        "archive_command" => "/bin/true",
        "archive_library" => "",
        "max_wal_senders" => "0"
      ),
      lsn: "0/16B6C50"
    )

    checks_by_name = checks.index_by(&:name)
    assert_not checks_by_name.fetch(:wal_archive_mode_enabled).ok
    assert_not checks_by_name.fetch(:wal_archive_destination_configured).ok
    assert_not checks_by_name.fetch(:wal_senders_available).ok
  end

  test "accepts archive library as a configured WAL archive destination" do
    checks = Database::PitrReadiness.call(
      adapter: "postgresql",
      settings: settings(
        "wal_level" => "logical",
        "archive_mode" => "always",
        "archive_command" => "",
        "archive_library" => "basic_archive",
        "max_wal_senders" => "5"
      ),
      lsn: "0/16B6C50"
    )

    assert checks.find { |check| check.name == :wal_archive_destination_configured }.ok
  end

  private

  def settings(overrides)
    overrides.transform_values do |value|
      {
        setting: value,
        unit: nil,
        boot_val: nil,
        reset_val: value,
        source: "test"
      }
    end
  end
end
