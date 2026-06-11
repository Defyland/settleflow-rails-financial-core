module Database
  class BenchmarkRunner
    Result = Data.define(:organizations, :wallets, :entries, :seed_duration_seconds, :counts, :consistency, :explains, :thresholds)

    def self.call(...)
      new(...).call
    end

    def initialize(organizations: 1, wallets: 100, entries: 2_000)
      @organizations = organizations.to_i
      @wallets = wallets.to_i
      @entries = entries.to_i
    end

    def call
      validate!

      started_at = monotonic_time
      seeded_organizations = Database::LargeSeed.call(organizations:, wallets:, entries:)
      seed_duration_seconds = monotonic_time - started_at
      consistency = Database::ConsistencyVerifier.call(organizations: Organization.where(id: seeded_organizations.map(&:id)))
      explains = Database::CriticalQueryExplainer.call(organization: seeded_organizations.first)

      result = Result.new(
        organizations:,
        wallets:,
        entries:,
        seed_duration_seconds: seed_duration_seconds.round(3),
        counts: counts_for(seeded_organizations),
        consistency: consistency.map { |check| { name: check.name, ok: check.ok, details: check.details } },
        explains: explains.map { |explain| explain.slice(:name, :sql, :plan) },
        thresholds: []
      )
      result.with(thresholds: Database::BenchmarkThresholds.call(result:).map { |check| { name: check.name, ok: check.ok, details: check.details } })
    end

    private

    attr_reader :organizations, :wallets, :entries

    def validate!
      raise ArgumentError, "organizations must be positive" unless organizations.positive?
      raise ArgumentError, "wallets must be positive" unless wallets.positive?
      raise ArgumentError, "entries must be positive" unless entries.positive?
    end

    def counts_for(seeded_organizations)
      organization_ids = seeded_organizations.map(&:id)
      {
        organizations: seeded_organizations.size,
        wallets: Wallet.where(organization_id: organization_ids).count,
        journal_entries: JournalEntry.where(organization_id: organization_ids).count,
        ledger_lines: LedgerLine.where(organization_id: organization_ids).count,
        outbox_events: OutboxEvent.where(organization_id: organization_ids).count,
        audit_logs: AuditLog.where(organization_id: organization_ids).count
      }
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
