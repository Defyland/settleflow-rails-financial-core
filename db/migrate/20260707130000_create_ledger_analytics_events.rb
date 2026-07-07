class CreateLedgerAnalyticsEvents < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE ledger_analytics_events (
        organization_id bigint NOT NULL REFERENCES organizations(id),
        journal_entry_id bigint NOT NULL REFERENCES journal_entries(id),
        ledger_line_id bigint NOT NULL REFERENCES ledger_lines(id),
        ledger_account_id bigint NOT NULL REFERENCES ledger_accounts(id),
        wallet_id bigint REFERENCES wallets(id),
        event_type character varying NOT NULL,
        direction character varying NOT NULL,
        account_type character varying NOT NULL,
        normal_balance character varying NOT NULL,
        amount_cents bigint NOT NULL,
        signed_amount_cents bigint NOT NULL,
        currency character varying DEFAULT 'BRL'::character varying NOT NULL,
        occurred_at timestamp(6) without time zone NOT NULL,
        occurred_on date NOT NULL,
        metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
        created_at timestamp(6) without time zone NOT NULL,
        updated_at timestamp(6) without time zone NOT NULL,
        PRIMARY KEY (ledger_line_id, occurred_on),
        CONSTRAINT ledger_analytics_events_amount_positive_check CHECK (amount_cents > 0),
        CONSTRAINT ledger_analytics_events_direction_check CHECK (direction IN ('debit', 'credit')),
        CONSTRAINT ledger_analytics_events_account_type_check CHECK (account_type IN ('asset', 'liability', 'revenue', 'expense', 'equity')),
        CONSTRAINT ledger_analytics_events_normal_balance_check CHECK (normal_balance IN ('debit', 'credit')),
        CONSTRAINT ledger_analytics_events_occurred_on_check CHECK (occurred_on = occurred_at::date)
      ) PARTITION BY RANGE (occurred_on);

      CREATE INDEX index_ledger_analytics_events_on_org_day_event
        ON ledger_analytics_events (organization_id, occurred_on, event_type);

      CREATE INDEX index_ledger_analytics_events_on_org_wallet_day
        ON ledger_analytics_events (organization_id, wallet_id, occurred_on);

      CREATE INDEX index_ledger_analytics_events_on_org_account_day
        ON ledger_analytics_events (organization_id, ledger_account_id, occurred_on);
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS ledger_analytics_events CASCADE"
  end
end
