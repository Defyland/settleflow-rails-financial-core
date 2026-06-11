module Database
  class CriticalQueryExplainer
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, analyze: true)
      @organization = organization
      @analyze = analyze
    end

    def call
      queries.map do |name, relation|
        sql = relation.to_sql
        plan = connection.exec_query(Arel.sql("#{explain_prefix} #{sql}")).rows.first.first
        { name:, sql:, plan: }
      end
    end

    private

    attr_reader :organization, :analyze

    def connection
      ActiveRecord::Base.connection
    end

    def explain_prefix
      analyze ? "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)" : "EXPLAIN (BUFFERS, FORMAT JSON)"
    end

    def queries
      wallet = organization.wallets.order(:id).first
      {
        wallet_statement: LedgerLine.joins(:ledger_account, :journal_entry)
          .where(organization:, ledger_account: { wallet_id: wallet&.id })
          .order(created_at: :desc)
          .limit(100),
        reconciliation_accounts: organization.ledger_accounts
          .left_outer_joins(:ledger_lines)
          .where(currency: wallet&.currency || "BRL")
          .group("ledger_accounts.id")
          .select("ledger_accounts.id, COALESCE(SUM(ledger_lines.amount_cents), 0) AS amount_total_cents"),
        outbox_publishable: OutboxEvent.publishable.order(:created_at).limit(100),
        audit_chain_tail: AuditLog.order(chain_sequence: :desc).limit(100)
      }
    end
  end
end
