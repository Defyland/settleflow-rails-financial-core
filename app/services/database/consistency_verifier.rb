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
        idempotency_evidence_guards_check,
        processed_event_evidence_guards_check,
        balance_evidence_guards_check,
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
      expected_constraints = %w[
        outbox_events_payload_sha256_hex_check
        outbox_events_status_check
        outbox_events_delivery_state_check
      ]
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
      enabled_constraints = ActiveRecord::Base.connection.select_values(<<~SQL.squish)
        SELECT conname
        FROM pg_constraint
        WHERE conrelid = 'outbox_events'::regclass
      SQL
      present_constraints = enabled_constraints & expected_constraints
      missing_constraints = expected_constraints - present_constraints

      Check.new(
        name: :outbox_evidence_guards,
        ok: trigger_present && missing_constraints.empty?,
        details: {
          mutation_trigger_present: trigger_present,
          present_constraints: present_constraints.sort,
          missing_constraints:
        }
      )
    end

    def idempotency_evidence_guards_check
      expected_constraints = %w[
        idempotency_keys_status_check
        idempotency_keys_request_hash_sha256_check
        idempotency_keys_identity_present_check
        idempotency_keys_response_state_check
      ]
      enabled_constraints = ActiveRecord::Base.connection.select_values(<<~SQL.squish)
        SELECT conname
        FROM pg_constraint
        WHERE conrelid = 'idempotency_keys'::regclass
      SQL
      present_constraints = enabled_constraints & expected_constraints
      trigger_present = catalog_value(<<~SQL.squish)
        SELECT EXISTS (
          SELECT 1
          FROM pg_trigger
          WHERE tgname = 'idempotency_keys_prevent_evidence_mutation'
            AND tgrelid = 'idempotency_keys'::regclass
            AND NOT tgisinternal
            AND tgenabled <> 'D'
        )
      SQL
      missing_constraints = expected_constraints - present_constraints

      Check.new(
        name: :idempotency_evidence_guards,
        ok: trigger_present && missing_constraints.empty?,
        details: {
          mutation_trigger_present: trigger_present,
          present_constraints: present_constraints.sort,
          missing_constraints:
        }
      )
    end

    def processed_event_evidence_guards_check
      expected_constraints = %w[
        processed_events_status_check
        processed_events_payload_sha256_hex_check
        processed_events_state_evidence_check
      ]
      enabled_constraints = ActiveRecord::Base.connection.select_values(<<~SQL.squish)
        SELECT conname
        FROM pg_constraint
        WHERE conrelid = 'processed_events'::regclass
      SQL
      present_constraints = enabled_constraints & expected_constraints
      trigger_present = catalog_value(<<~SQL.squish)
        SELECT EXISTS (
          SELECT 1
          FROM pg_trigger
          WHERE tgname = 'processed_events_prevent_evidence_mutation'
            AND tgrelid = 'processed_events'::regclass
            AND NOT tgisinternal
            AND tgenabled <> 'D'
        )
      SQL
      mismatch_count = ActiveRecord::Base.connection.select_value(<<~SQL.squish).to_i
        SELECT COUNT(*)
        FROM processed_events pe
        LEFT JOIN outbox_events oe ON oe.id = pe.outbox_event_id
        WHERE oe.id IS NULL
           OR oe.status <> 'published'
           OR oe.published_at IS NULL
           OR oe.payload_sha256 IS NULL
           OR oe.organization_id <> pe.organization_id
           OR oe.public_id::text <> pe.event_id
           OR oe.event_type <> pe.event_type
           OR oe.payload_sha256 <> pe.payload_sha256
      SQL
      missing_constraints = expected_constraints - present_constraints

      Check.new(
        name: :processed_event_evidence_guards,
        ok: trigger_present && missing_constraints.empty? && mismatch_count.zero?,
        details: {
          mutation_trigger_present: trigger_present,
          present_constraints: present_constraints.sort,
          missing_constraints:,
          outbox_evidence_mismatches: mismatch_count
        }
      )
    end

    def balance_evidence_guards_check
      expected_constraints = %w[
        balance_projections_available_non_negative_check
        balance_projections_pending_non_negative_check
        balance_projections_blocked_non_negative_check
        balance_snapshots_available_non_negative_check
        balance_snapshots_pending_non_negative_check
        balance_snapshots_blocked_non_negative_check
        balance_snapshots_difference_matches_projection_check
        balance_snapshots_source_present_check
      ]
      expected_triggers = %w[
        balance_projections_wallet_evidence_before_write
        balance_snapshots_prevent_evidence_mutation
      ]
      enabled_constraints = ActiveRecord::Base.connection.select_values(<<~SQL.squish)
        SELECT conname
        FROM pg_constraint
        WHERE conrelid IN ('balance_projections'::regclass, 'balance_snapshots'::regclass)
      SQL
      enabled_triggers = ActiveRecord::Base.connection.select_values(<<~SQL.squish)
        SELECT tgname
        FROM pg_trigger
        WHERE tgrelid IN ('balance_projections'::regclass, 'balance_snapshots'::regclass)
          AND NOT tgisinternal
          AND tgenabled <> 'D'
      SQL
      projection_mismatches = ActiveRecord::Base.connection.select_value(<<~SQL.squish).to_i
        SELECT COUNT(*)
        FROM balance_projections bp
        LEFT JOIN wallets w ON w.id = bp.wallet_id
        WHERE w.id IS NULL
           OR w.organization_id <> bp.organization_id
           OR w.currency <> bp.currency
      SQL
      snapshot_mismatches = ActiveRecord::Base.connection.select_value(<<~SQL.squish).to_i
        SELECT COUNT(*)
        FROM balance_snapshots bs
        LEFT JOIN wallets w ON w.id = bs.wallet_id
        WHERE w.id IS NULL
           OR w.organization_id <> bs.organization_id
           OR w.currency <> bs.currency
           OR bs.difference_cents <> bs.available_cents - bs.ledger_available_cents
           OR btrim(bs.source) = ''
      SQL
      present_constraints = enabled_constraints & expected_constraints
      present_triggers = enabled_triggers & expected_triggers
      missing_constraints = expected_constraints - present_constraints
      missing_triggers = expected_triggers - present_triggers

      Check.new(
        name: :balance_evidence_guards,
        ok: missing_constraints.empty? && missing_triggers.empty? && projection_mismatches.zero? && snapshot_mismatches.zero?,
        details: {
          present_constraints: present_constraints.sort,
          missing_constraints:,
          present_triggers: present_triggers.sort,
          missing_triggers:,
          projection_wallet_mismatches: projection_mismatches,
          snapshot_evidence_mismatches: snapshot_mismatches
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
