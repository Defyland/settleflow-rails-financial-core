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
        outbox_evidence_guards_check,
        financial_state_evidence_guards_check,
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

    def outbox_evidence_guards_check
      trigger_present = catalog_value(<<~SQL.squish)
        SELECT EXISTS (
          SELECT 1
          FROM pg_trigger
          WHERE tgname = 'outbox_events_prevent_evidence_mutation'
            AND tgrelid = 'outbox_events'::regclass
            AND NOT tgisinternal
            AND tgenabled <> 'D'
        )
      SQL
      payload_hash_check_present = catalog_value(<<~SQL.squish)
        SELECT EXISTS (
          SELECT 1
          FROM pg_constraint
          WHERE conname = 'outbox_events_payload_sha256_hex_check'
            AND conrelid = 'outbox_events'::regclass
        )
      SQL

      Check.new(
        name: :outbox_evidence_guards,
        ok: trigger_present && payload_hash_check_present,
        details: {
          mutation_trigger_present: trigger_present,
          payload_hash_check_present:
        }
      )
    end

    def financial_state_evidence_guards_check
      expected_triggers = %w[
        fundings_state_evidence_after_write
        transfers_state_evidence_after_write
        split_payments_state_evidence_after_write
        split_entries_state_evidence_after_write
        payouts_state_evidence_after_write
        refunds_state_evidence_after_write
        med_cases_state_evidence_after_write
        pix_payments_state_evidence_after_write
      ]
      enabled_triggers = ActiveRecord::Base.connection.select_values(<<~SQL.squish)
        SELECT tgname
        FROM pg_trigger
        WHERE NOT tgisinternal
          AND tgenabled <> 'D'
      SQL
      present_triggers = enabled_triggers & expected_triggers
      missing_triggers = expected_triggers - present_triggers

      Check.new(
        name: :financial_state_evidence_guards,
        ok: missing_triggers.empty?,
        details: {
          present_triggers: present_triggers.sort,
          missing_triggers:
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

    def catalog_value(sql)
      ActiveRecord::Type::Boolean.new.cast(ActiveRecord::Base.connection.select_value(sql))
    end
  end
end
