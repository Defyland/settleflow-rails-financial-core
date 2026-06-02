module Database
  class ConsistencyVerifier
    Check = Data.define(:name, :ok, :details)

    def self.call(...)
      new(...).call
    end

    def initialize(organizations: Organization.all)
      @organizations = organizations
    end

    def call
      [
        audit_hash_chain_check,
        audit_anchor_chain_check,
        journal_balance_check,
        negative_projection_check,
        projection_rebuild_check
      ]
    end

    private

    attr_reader :organizations

    def audit_hash_chain_check
      Check.new(
        name: :audit_hash_chain,
        ok: AuditLog.hash_chain_intact?,
        details: {
          hash_mismatches: AuditLog.hash_mismatches.count,
          broken_links: AuditLog.broken_chain_links.count,
          invalid_genesis_links: AuditLog.invalid_genesis_links.count
        }
      )
    end

    def journal_balance_check
      rows = ActiveRecord::Base.connection.exec_query(<<~SQL.squish)
        SELECT journal_entry_id, currency
        FROM ledger_lines
        GROUP BY journal_entry_id, currency
        HAVING
          COUNT(*) < 2 OR
          SUM(CASE WHEN direction = 'debit' THEN amount_cents ELSE 0 END) <>
          SUM(CASE WHEN direction = 'credit' THEN amount_cents ELSE 0 END)
      SQL

      Check.new(
        name: :journal_balance,
        ok: rows.empty?,
        details: { unbalanced_journal_currency_pairs: rows.count }
      )
    end

    def audit_anchor_chain_check
      Check.new(
        name: :audit_anchor_chain,
        ok: AuditLogAnchor.anchor_chain_intact?,
        details: {
          anchor_hash_mismatches: AuditLogAnchor.hash_mismatches.count,
          broken_anchor_links: AuditLogAnchor.broken_anchor_links.count,
          latest_anchor_sequence: AuditLogAnchor.maximum(:chain_sequence),
          latest_audit_sequence: AuditLog.maximum(:chain_sequence),
          latest_anchor_covers_current_audit_tail: AuditLogAnchor.latest_covers_current_audit_tail?
        }
      )
    end

    def negative_projection_check
      count = BalanceProjection.where("available_cents < 0 OR pending_cents < 0 OR blocked_cents < 0").count
      Check.new(
        name: :negative_balance_projections,
        ok: count.zero?,
        details: { negative_projection_rows: count }
      )
    end

    def projection_rebuild_check
      differences = organizations.flat_map do |organization|
        BalanceProjections::Rebuilder.call(organization:, apply: false).select { |result| result.difference_cents != 0 }
      end

      Check.new(
        name: :projection_rebuild,
        ok: differences.empty?,
        details: {
          mismatched_wallets: differences.size,
          difference_cents_sum: differences.sum(&:difference_cents)
        }
      )
    end
  end
end
