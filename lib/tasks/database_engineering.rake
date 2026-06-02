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
end
