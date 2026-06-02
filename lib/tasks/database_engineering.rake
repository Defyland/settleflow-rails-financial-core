require "fileutils"

namespace :database do
  desc "Seed a large deterministic dataset: database:seed_large[organizations,wallets,entries]"
  task :seed_large, [ :organizations, :wallets, :entries ] => :environment do |_task, args|
    organizations = args[:organizations].presence || ENV.fetch("ORGANIZATIONS", 1)
    wallets = args[:wallets].presence || ENV.fetch("WALLETS", 100)
    entries = args[:entries].presence || ENV.fetch("ENTRIES", 1_000)

    seeded = Database::LargeSeed.call(organizations:, wallets:, entries:)
    puts "Seeded #{seeded.size} organization(s), #{wallets} wallet(s) each, #{entries} transfer(s) each"
  end

  desc "Run database benchmark and write JSON result: database:benchmark[organizations,wallets,entries]"
  task :benchmark, [ :organizations, :wallets, :entries ] => :environment do |_task, args|
    organizations = args[:organizations].presence || ENV.fetch("ORGANIZATIONS", 1)
    wallets = args[:wallets].presence || ENV.fetch("WALLETS", 100)
    entries = args[:entries].presence || ENV.fetch("ENTRIES", 2_000)
    result = Database::BenchmarkRunner.call(organizations:, wallets:, entries:)

    failed_checks = result.consistency.reject { |check| check.fetch(:ok) }
    abort "Benchmark dataset consistency failed: #{failed_checks.to_json}" if failed_checks.any?
    failed_thresholds = result.thresholds.reject { |check| check.fetch(:ok) }
    abort "Benchmark thresholds failed: #{failed_thresholds.to_json}" if failed_thresholds.any?

    output_dir = Rails.root.join("benchmarks/database/results")
    FileUtils.mkdir_p(output_dir)
    output_path = output_dir.join("#{Time.current.utc.strftime("%Y%m%d%H%M%S")}_database_benchmark.json")
    File.write(output_path, JSON.pretty_generate(result.to_h))
    puts "Wrote #{output_path}"
  end

  desc "Capture daily balance snapshots for all organizations"
  task capture_balance_snapshots: :environment do
    Organization.find_each do |organization|
      snapshots = BalanceSnapshots::Capture.call(organization:)
      puts "Captured #{snapshots.size} balance snapshot(s) for #{organization.slug}"
    end
  end

  desc "Dry-run or apply balance projection rebuild from ledger: database:rebuild_balance_projections[apply]"
  task :rebuild_balance_projections, [ :apply ] => :environment do |_task, args|
    apply = ActiveModel::Type::Boolean.new.cast(args[:apply] || ENV["APPLY"])
    Organization.find_each do |organization|
      BalanceProjections::Rebuilder.call(organization:, apply:).each do |result|
        puts "#{organization.slug} #{result.wallet_id} current=#{result.current_available_cents} rebuilt=#{result.rebuilt_available_cents} diff=#{result.difference_cents}"
      end
    end
  end

  desc "Verify financial database consistency after restore, migration, or incident"
  task verify_consistency: :environment do
    checks = Database::ConsistencyVerifier.call
    checks.each do |check|
      status = check.ok ? "ok" : "failed"
      puts "#{check.name}=#{status} #{check.details.to_json}"
    end

    failed = checks.reject(&:ok)
    abort "Database consistency verification failed: #{failed.map(&:name).join(", ")}" if failed.any?
  end

  desc "Run PostgreSQL logical backup/restore drill into a temporary database"
  task backup_restore_drill: :environment do
    result = Database::BackupRestoreDrill.call
    failed_checks = result.checks.reject { |check| check.fetch(:ok) }
    abort "Backup restore drill consistency failed: #{failed_checks.to_json}" if failed_checks.any?

    puts "Backup restore drill ok source=#{result.source_database} restored=#{result.restored_database} dump=#{result.dump_path}"
  end

  desc "Write EXPLAIN plans for critical financial queries into benchmarks/database/explain"
  task :explain_queries, [ :organization_slug ] => :environment do |_task, args|
    organization = if args[:organization_slug].present?
      Organization.find_by!(slug: args[:organization_slug])
    else
      Organization.order(:id).first || Database::LargeSeed.call(organizations: 1, wallets: 2, entries: 2).first
    end

    output_dir = Rails.root.join("benchmarks/database/explain")
    FileUtils.mkdir_p(output_dir)

    Database::CriticalQueryExplainer.call(organization:).each do |explain|
      path = output_dir.join("#{explain.fetch(:name)}.json")
      File.write(path, JSON.pretty_generate(explain))
      puts "Wrote #{path}"
    end
  end

  desc "Check migration files for high-volume PostgreSQL safety patterns"
  task migration_safety_check: :environment do
    findings = Database::MigrationSafetyChecker.call

    if findings.empty?
      puts "No high-volume migration safety findings"
    else
      findings.each do |finding|
        puts "[#{finding.severity}] #{finding.file}:#{finding.line} #{finding.message} -- #{finding.evidence}"
      end
    end

    strict = ActiveModel::Type::Boolean.new.cast(ENV["STRICT"])
    abort "Migration safety findings found" if strict && findings.any? { |finding| finding.severity.in?([ :high, :medium ]) }
  end

  desc "Write future partition SQL plan: database:partition_plan[months]"
  task :partition_plan, [ :months ] => :environment do |_task, args|
    months = (args[:months].presence || ENV.fetch("MONTHS", 3)).to_i
    output_dir = Rails.root.join("benchmarks/database/partitioning")
    FileUtils.mkdir_p(output_dir)

    plan = Database::PartitionPlan.new(months:)
    output_path = output_dir.join("next_partitions.sql")
    File.write(output_path, "#{plan.to_sql}\n")
    puts "Wrote #{output_path}"
  end

  desc "Report whether candidate high-volume tables are PostgreSQL partitioned parents"
  task partition_readiness_check: :environment do
    checks = Database::PartitionReadiness.call
    checks.each do |check|
      state = check.partitioned ? "partitioned:#{check.partition_strategy}" : "not_partitioned"
      puts "#{check.table}=#{state}"
    end

    strict = ActiveModel::Type::Boolean.new.cast(ENV["STRICT"])
    abort "Partition readiness failed" if strict && checks.any? { |check| !check.partitioned }
  end

  desc "Report catalog blockers before converting high-volume tables to partitions"
  task partition_feasibility_check: :environment do
    checks = Database::PartitionFeasibility.call

    checks.each do |check|
      status = check.ready ? "ready" : "blocked"
      puts "#{check.table}=#{status} partition_key=#{check.partition_key} strategy=#{check.strategy}"

      check.blockers.each do |finding|
        puts "  [#{finding.severity}] #{finding.code}: #{finding.message} #{finding.details.to_json}"
      end

      check.warnings.each do |finding|
        puts "  [#{finding.severity}] #{finding.code}: #{finding.message} #{finding.details.to_json}"
      end
    end

    output_dir = Rails.root.join("benchmarks/database/partitioning")
    FileUtils.mkdir_p(output_dir)
    output_path = output_dir.join("feasibility.json")
    File.write(output_path, JSON.pretty_generate(checks.map(&:to_h)))
    puts "Wrote #{output_path}"

    strict = ActiveModel::Type::Boolean.new.cast(ENV["STRICT"])
    abort "Partition feasibility failed" if strict && checks.any? { |check| !check.ready }
  end
end

namespace :clickhouse do
  desc "Create ClickHouse database/table for financial analytics"
  task create_schema: :environment do
    Analytics::ClickHouseClient.new.create_schema!
    puts "ClickHouse schema ready"
  end

  desc "Backfill published outbox events into ClickHouse: clickhouse:backfill[limit]"
  task :backfill, [ :limit ] => :environment do |_task, args|
    limit = (args[:limit].presence || ENV.fetch("LIMIT", 1_000)).to_i
    synced = 0

    OutboxEvent.published.order(:id).limit(limit).find_each do |event|
      Analytics::ClickHouseSync.call(outbox_event: event)
      synced += 1
    end

    puts "Synced #{synced} published outbox event(s) to ClickHouse"
  end

  desc "Verify real ClickHouse schema, duplicate-event dedupe, and daily analytics view"
  task verify: :environment do
    abort "CLICKHOUSE_URL is required" unless Analytics::ClickHouseClient.configured?

    database = "settleflow_verify_#{Time.current.utc.strftime("%Y%m%d%H%M%S")}_#{SecureRandom.hex(4)}"
    client = Analytics::ClickHouseClient.new(database:)
    event_id = SecureRandom.uuid
    event = {
      event_id:,
      event_type: "clickhouse.verify",
      aggregate_type: "Verification",
      aggregate_id: 1,
      organization_id: SecureRandom.uuid,
      correlation_id: SecureRandom.uuid,
      idempotency_key: "clickhouse-verify-#{event_id}",
      payload: JSON.generate(amount_cents: 1_234),
      payload_sha256: OpenSSL::Digest::SHA256.hexdigest("clickhouse-verify-#{event_id}"),
      occurred_at: Analytics::ClickHouseEventMapper.format_time(Time.current),
      synced_at: Analytics::ClickHouseEventMapper.format_time(Time.current)
    }

    begin
      client.execute!("DROP DATABASE IF EXISTS `#{database}`")
      client.create_schema!
      2.times { client.insert_financial_event!(event.merge(synced_at: Analytics::ClickHouseEventMapper.format_time(Time.current))) }

      rows = client.query_json_each_row!(<<~SQL.squish)
        SELECT event_type, event_count, amount_cents_sum
        FROM #{client.qualified_daily_rollup_view_name}
        WHERE event_type = 'clickhouse.verify'
      SQL
      row = rows.sole
      abort "ClickHouse dedupe failed: #{row.inspect}" unless row.fetch("event_count").to_i == 1
      abort "ClickHouse amount rollup failed: #{row.inspect}" unless row.fetch("amount_cents_sum").to_i == 1_234

      puts "ClickHouse verified database=#{database} event_id=#{event_id}"
    ensure
      client.execute!("DROP DATABASE IF EXISTS `#{database}`") if client
    end
  end
end

namespace :redis do
  desc "Verify real Redis temporary lock behavior without storing financial truth"
  task verify: :environment do
    abort "REDIS_URL is required" unless Operational::RedisTemporaryLock.configured?

    key = "verify:#{SecureRandom.hex(8)}"
    client = RedisClient.config(url: ENV.fetch("REDIS_URL")).new_client

    Operational::RedisTemporaryLock.call(key:, ttl: 5.seconds) do
      begin
        Operational::RedisTemporaryLock.call(key:, ttl: 5.seconds) { abort "Redis duplicate lock unexpectedly acquired" }
      rescue Errors::ValidationError
        nil
      end
    end

    leaked_value = client.call("GET", "operational-lock:#{key}")
    abort "Redis temporary lock leaked after release" if leaked_value.present?

    puts "Redis temporary lock verified key=#{key}"
  ensure
    client&.close
  end
end

namespace :audit do
  desc "Anchor the current audit hash-chain tail and optionally publish it to AUDIT_ANCHOR_WEBHOOK_URL"
  task anchor_hash_chain: :environment do
    anchor = AuditLogs::HashChainAnchor.call
    puts "Audit hash chain anchored sequence=#{anchor.chain_sequence} anchor_hash=#{anchor.anchor_hash}"
  end
end
