require "open3"

module Database
  class BackupRestoreDrill
    Result = Data.define(:source_database, :restored_database, :dump_path, :checks)

    def self.call(...)
      new(...).call
    end

    def initialize(output_dir: Rails.root.join("tmp/backup_restore_drills"), database_suffix: SecureRandom.hex(4))
      @output_dir = Pathname(output_dir)
      @database_suffix = database_suffix
      @source_config = ActiveRecord::Base.connection_db_config.configuration_hash.symbolize_keys
    end

    def call
      raise Errors::ValidationError.new("Backup restore drill requires PostgreSQL") unless source_config.fetch(:adapter) == "postgresql"

      FileUtils.mkdir_p(output_dir)
      dump_path = output_dir.join("#{source_database}_#{Time.current.utc.strftime("%Y%m%d%H%M%S")}.dump")
      restored_database = "#{source_database}_restore_drill_#{database_suffix}"

      run!(pg_dump_command(dump_path))
      run!(createdb_command(restored_database))
      run!(pg_restore_command(restored_database, dump_path))
      checks = verify_restored_database(restored_database)

      Result.new(
        source_database:,
        restored_database:,
        dump_path: dump_path.to_s,
        checks: checks.map { |check| { name: check.name, ok: check.ok, details: check.details } }
      )
    ensure
      reconnect_source_database
      run!(dropdb_command(restored_database), allow_failure: true) if restored_database.present?
    end

    private

    attr_reader :output_dir, :database_suffix, :source_config

    def source_database
      source_config.fetch(:database)
    end

    def pg_dump_command(dump_path)
      postgres_command("pg_dump", "--format=custom", "--no-owner", "--no-privileges", "--file", dump_path.to_s, source_database)
    end

    def createdb_command(database)
      postgres_command("createdb", database)
    end

    def pg_restore_command(database, dump_path)
      postgres_command("pg_restore", "--no-owner", "--no-privileges", "--dbname", database, dump_path.to_s)
    end

    def dropdb_command(database)
      postgres_command("dropdb", "--if-exists", database)
    end

    def postgres_command(command, *args)
      [ command, *connection_args, *args ]
    end

    def connection_args
      [
        optional_arg("--host", source_config[:host]),
        optional_arg("--port", source_config[:port]),
        optional_arg("--username", source_config[:username])
      ].compact.flatten
    end

    def optional_arg(name, value)
      [ name, value.to_s ] if value.present?
    end

    def command_env
      password = source_config[:password]
      password.present? ? { "PGPASSWORD" => password.to_s } : {}
    end

    def run!(command, allow_failure: false)
      _stdout, stderr, status = Open3.capture3(command_env, *command)
      return if status.success? || allow_failure

      raise Errors::ValidationError.new("Backup restore drill command failed", details: { command: command.first, error: stderr })
    end

    def verify_restored_database(database)
      ActiveRecord::Base.establish_connection(source_config.merge(database:))
      Database::ConsistencyVerifier.call
    end

    def reconnect_source_database
      ActiveRecord::Base.establish_connection(source_config)
    end
  end
end
