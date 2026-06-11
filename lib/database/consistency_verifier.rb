module Database
  class ConsistencyVerifier
    Check = Database::ConsistencyCheck

    CHECKS = [
      ConsistencyChecks::AuditChains,
      ConsistencyChecks::OutboxEvidenceGuards,
      ConsistencyChecks::IdempotencyEvidenceGuards,
      ConsistencyChecks::ProcessedEventEvidenceGuards,
      ConsistencyChecks::BalanceEvidenceGuards,
      ConsistencyChecks::OperatorApprovalEvidenceGuards,
      ConsistencyChecks::ReconciliationEvidenceGuards,
      ConsistencyChecks::FinancialStateEvidenceGuards,
      ConsistencyChecks::FinancialJournalEvidenceGuards,
      ConsistencyChecks::JournalEventTaxonomy,
      ConsistencyChecks::JournalBalance,
      ConsistencyChecks::NegativeBalanceProjections,
      ConsistencyChecks::ProjectionRebuild
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(organizations: Organization.all)
      @organizations = organizations
    end

    def call
      CHECKS.flat_map { |check| Array(check.call(organizations: organizations)) }
    end

    private

    attr_reader :organizations
  end
end
