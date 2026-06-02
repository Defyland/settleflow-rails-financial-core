class AddOutboxAggregateEvidenceGuards < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION outbox_event_has_aggregate_evidence(event_row outbox_events)
      RETURNS boolean
      LANGUAGE plpgsql
      STABLE
      AS $$
      DECLARE
        has_evidence boolean;
      BEGIN
        IF event_row.aggregate_type = 'Funding' THEN
          SELECT EXISTS (
            SELECT 1
            FROM fundings
            WHERE fundings.id = event_row.aggregate_id
              AND fundings.organization_id = event_row.organization_id
              AND event_row.event_type = 'wallet.funded'
              AND event_row.payload @> jsonb_build_object(
                'funding_id', fundings.public_id::text,
                'wallet_id', (SELECT wallets.public_id::text FROM wallets WHERE wallets.id = fundings.wallet_id),
                'amount_cents', fundings.amount_cents,
                'currency', fundings.currency
              )
          ) INTO has_evidence;
          RETURN has_evidence;
        END IF;

        IF event_row.aggregate_type = 'Transfer' THEN
          SELECT EXISTS (
            SELECT 1
            FROM transfers
            JOIN wallets source_wallets ON source_wallets.id = transfers.source_wallet_id
            JOIN wallets destination_wallets ON destination_wallets.id = transfers.destination_wallet_id
            WHERE transfers.id = event_row.aggregate_id
              AND transfers.organization_id = event_row.organization_id
              AND event_row.event_type = 'wallet.transfer.posted'
              AND event_row.payload @> jsonb_build_object(
                'transfer_id', transfers.public_id::text,
                'source_wallet_id', source_wallets.public_id::text,
                'destination_wallet_id', destination_wallets.public_id::text,
                'amount_cents', transfers.amount_cents,
                'currency', transfers.currency
              )
          ) INTO has_evidence;
          RETURN has_evidence;
        END IF;

        IF event_row.aggregate_type = 'SplitPayment' THEN
          SELECT EXISTS (
            SELECT 1
            FROM split_payments
            JOIN wallets source_wallets ON source_wallets.id = split_payments.source_wallet_id
            WHERE split_payments.id = event_row.aggregate_id
              AND split_payments.organization_id = event_row.organization_id
              AND event_row.event_type = 'split.posted'
              AND event_row.payload @> jsonb_build_object(
                'split_payment_id', split_payments.public_id::text,
                'source_wallet_id', source_wallets.public_id::text,
                'total_amount_cents', split_payments.total_amount_cents,
                'currency', split_payments.currency
              )
          ) INTO has_evidence;
          RETURN has_evidence;
        END IF;

        IF event_row.aggregate_type = 'PixPayment' THEN
          SELECT EXISTS (
            SELECT 1
            FROM pix_payments
            WHERE pix_payments.id = event_row.aggregate_id
              AND pix_payments.organization_id = event_row.organization_id
              AND event_row.event_type IN (
                'pix.payment.approved',
                'pix.payment.pending_review',
                'pix.payment.rejected',
                'pix.payment.settled',
                'pix.payment.reversed'
              )
              AND event_row.payload @> jsonb_build_object(
                'pix_payment_id', pix_payments.public_id::text,
                'amount_cents', pix_payments.amount_cents,
                'currency', pix_payments.currency
              )
          ) INTO has_evidence;
          RETURN has_evidence;
        END IF;

        IF event_row.aggregate_type = 'Payout' THEN
          SELECT EXISTS (
            SELECT 1
            FROM payouts
            JOIN wallets ON wallets.id = payouts.wallet_id
            WHERE payouts.id = event_row.aggregate_id
              AND payouts.organization_id = event_row.organization_id
              AND event_row.event_type IN ('payout.scheduled', 'payout.settled')
              AND event_row.payload @> jsonb_build_object(
                'payout_id', payouts.public_id::text,
                'wallet_id', wallets.public_id::text,
                'amount_cents', payouts.amount_cents,
                'currency', payouts.currency
              )
          ) INTO has_evidence;
          RETURN has_evidence;
        END IF;

        IF event_row.aggregate_type = 'Refund' THEN
          SELECT EXISTS (
            SELECT 1
            FROM refunds
            JOIN pix_payments ON pix_payments.id = refunds.pix_payment_id
            JOIN wallets ON wallets.id = refunds.wallet_id
            WHERE refunds.id = event_row.aggregate_id
              AND refunds.organization_id = event_row.organization_id
              AND event_row.event_type = 'refund.settled'
              AND event_row.payload @> jsonb_build_object(
                'refund_id', refunds.public_id::text,
                'pix_payment_id', pix_payments.public_id::text,
                'wallet_id', wallets.public_id::text,
                'amount_cents', refunds.amount_cents,
                'currency', refunds.currency
              )
          ) INTO has_evidence;
          RETURN has_evidence;
        END IF;

        IF event_row.aggregate_type = 'MedCase' THEN
          SELECT EXISTS (
            SELECT 1
            FROM med_cases
            JOIN pix_payments ON pix_payments.id = med_cases.pix_payment_id
            WHERE med_cases.id = event_row.aggregate_id
              AND med_cases.organization_id = event_row.organization_id
              AND event_row.event_type IN ('med.case.opened', 'med.case.rejected', 'med.case.refunded')
              AND event_row.payload @> jsonb_build_object(
                'med_case_id', med_cases.public_id::text,
                'pix_payment_id', pix_payments.public_id::text,
                'amount_cents', med_cases.amount_cents,
                'currency', med_cases.currency
              )
          ) INTO has_evidence;
          RETURN has_evidence;
        END IF;

        IF event_row.aggregate_type = 'ReconciliationRun' THEN
          SELECT EXISTS (
            SELECT 1
            FROM reconciliation_runs
            WHERE reconciliation_runs.id = event_row.aggregate_id
              AND reconciliation_runs.organization_id = event_row.organization_id
              AND event_row.event_type = 'reconciliation.' || reconciliation_runs.status
              AND event_row.payload @> jsonb_build_object(
                'reconciliation_run_id', reconciliation_runs.public_id::text,
                'provider', reconciliation_runs.provider,
                'ledger_balance_cents', reconciliation_runs.ledger_balance_cents,
                'provider_balance_cents', reconciliation_runs.provider_balance_cents,
                'discrepancy_cents', reconciliation_runs.discrepancy_cents
              )
          ) INTO has_evidence;
          RETURN has_evidence;
        END IF;

        RETURN false;
      END;
      $$;

      CREATE OR REPLACE FUNCTION assert_outbox_event_aggregate_evidence()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NOT outbox_event_has_aggregate_evidence(NEW) THEN
          RAISE EXCEPTION 'outbox event aggregate evidence is invalid';
        END IF;

        RETURN NEW;
      END;
      $$;

      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM outbox_events
          WHERE NOT outbox_event_has_aggregate_evidence(outbox_events)
        ) THEN
          RAISE EXCEPTION 'existing outbox_events violate aggregate evidence guards';
        END IF;
      END
      $$;

      DROP TRIGGER IF EXISTS outbox_events_aggregate_evidence_before_write ON outbox_events;
      CREATE TRIGGER outbox_events_aggregate_evidence_before_write
      BEFORE INSERT OR UPDATE OF organization_id, aggregate_type, aggregate_id, event_type, payload ON outbox_events
      FOR EACH ROW EXECUTE FUNCTION assert_outbox_event_aggregate_evidence();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS outbox_events_aggregate_evidence_before_write ON outbox_events;
      DROP FUNCTION IF EXISTS assert_outbox_event_aggregate_evidence();
      DROP FUNCTION IF EXISTS outbox_event_has_aggregate_evidence(outbox_events);
    SQL
  end
end
