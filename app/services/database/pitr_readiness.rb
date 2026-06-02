module Database
  class PitrReadiness
    Check = Data.define(:name, :ok, :details) do
      def to_h
        {
          name: name.to_s,
          ok:,
          details:
        }
      end
    end

    PITR_WAL_LEVELS = %w[replica logical].freeze
    ENABLED_ARCHIVE_MODES = %w[on always].freeze
    FAKE_ARCHIVE_COMMANDS = [
      "",
      "(disabled)",
      "/bin/true",
      "true"
    ].freeze

    SETTING_NAMES = %w[
      archive_command
      archive_library
      archive_mode
      max_wal_senders
      wal_keep_size
      wal_level
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(settings: nil, adapter: nil, lsn: nil)
      @settings_override = settings
      @adapter_override = adapter
      @lsn_override = lsn
    end

    def call
      [
        postgresql_check,
        wal_level_check,
        archive_mode_check,
        archive_destination_check,
        wal_sender_check,
        current_lsn_check
      ]
    end

    private

    attr_reader :settings_override, :adapter_override, :lsn_override

    def postgresql_check
      Check.new(
        name: :postgresql_adapter,
        ok: adapter == "postgresql",
        details: {
          adapter:
        }
      )
    end

    def wal_level_check
      wal_level = setting_value("wal_level")
      Check.new(
        name: :wal_level_supports_pitr,
        ok: wal_level.in?(PITR_WAL_LEVELS),
        details: {
          wal_level:,
          accepted: PITR_WAL_LEVELS
        }
      )
    end

    def archive_mode_check
      archive_mode = setting_value("archive_mode")
      Check.new(
        name: :wal_archive_mode_enabled,
        ok: archive_mode.in?(ENABLED_ARCHIVE_MODES),
        details: {
          archive_mode:,
          accepted: ENABLED_ARCHIVE_MODES
        }
      )
    end

    def archive_destination_check
      archive_command = setting_value("archive_command").to_s.strip
      archive_library = setting_value("archive_library").to_s.strip
      configured = archive_library.present? || !archive_command.in?(FAKE_ARCHIVE_COMMANDS)

      Check.new(
        name: :wal_archive_destination_configured,
        ok: configured,
        details: {
          archive_command:,
          archive_library:,
          rejected_commands: FAKE_ARCHIVE_COMMANDS
        }
      )
    end

    def wal_sender_check
      max_wal_senders = setting_value("max_wal_senders").to_i
      Check.new(
        name: :wal_senders_available,
        ok: max_wal_senders.positive?,
        details: {
          max_wal_senders:
        }
      )
    end

    def current_lsn_check
      Check.new(
        name: :current_wal_lsn_observable,
        ok: current_lsn.present?,
        details: {
          current_wal_lsn: current_lsn
        }
      )
    end

    def adapter
      @adapter ||= adapter_override || ActiveRecord::Base.connection_db_config.configuration_hash.fetch(:adapter)
    end

    def setting_value(name)
      settings.fetch(name, {}).fetch(:setting, nil)
    end

    def settings
      @settings ||= settings_override || load_settings
    end

    def load_settings
      rows = ActiveRecord::Base.connection.exec_query(<<~SQL.squish)
        SELECT name, setting, unit, boot_val, reset_val, source
        FROM pg_settings
        WHERE name IN ('archive_command', 'archive_library', 'archive_mode', 'max_wal_senders', 'wal_keep_size', 'wal_level')
      SQL

      rows.each_with_object({}) do |row, result|
        result[row.fetch("name")] = {
          setting: row["setting"],
          unit: row["unit"],
          boot_val: row["boot_val"],
          reset_val: row["reset_val"],
          source: row["source"]
        }
      end
    end

    def current_lsn
      @current_lsn ||= lsn_override || ActiveRecord::Base.connection.select_value("SELECT pg_current_wal_lsn()::text")
    end
  end
end
