class AddFinancialJournalEvidenceGuards < ActiveRecord::Migration[8.1]
  def up
    backfill_legacy_financial_journal_idempotency_keys

    execute <<~SQL
      CREATE OR REPLACE FUNCTION financial_journal_event_type_requires_evidence(event_type_to_check text)
      RETURNS boolean
      LANGUAGE sql
      IMMUTABLE
      AS $$
        SELECT event_type_to_check IN (
          'wallet.funded',
          'wallet.transfer.posted',
          'split.posted',
          'pix.payment.approved',
          'pix.payment.settled',
          'pix.payment.reversed',
          'payout.scheduled',
          'payout.settled',
          'refund.settled'
        );
      $$;

      CREATE OR REPLACE FUNCTION financial_journal_line_exists(
        journal_entry_id_to_check bigint,
        ledger_account_id_to_check bigint,
        direction_to_check text,
        amount_cents_to_check bigint,
        currency_to_check text
      )
      RETURNS boolean
      LANGUAGE sql
      STABLE
      AS $$
        SELECT EXISTS (
          SELECT 1
          FROM ledger_lines
          WHERE journal_entry_id = journal_entry_id_to_check
            AND ledger_account_id = ledger_account_id_to_check
            AND direction = direction_to_check
            AND amount_cents = amount_cents_to_check
            AND currency = currency_to_check
        );
      $$;

      CREATE OR REPLACE FUNCTION financial_journal_has_aggregate_evidence(journal_entry_id_to_check bigint)
      RETURNS boolean
      LANGUAGE plpgsql
      STABLE
      AS $$
      DECLARE
        has_evidence boolean;
      BEGIN
        SELECT EXISTS (
          SELECT 1
          FROM journal_entries je
          JOIN fundings funding
            ON funding.id = je.reference_id
           AND je.reference_type = 'Funding'
           AND funding.journal_entry_id = je.id
          JOIN wallets wallet ON wallet.id = funding.wallet_id
          JOIN ledger_accounts wallet_liability
            ON wallet_liability.wallet_id = wallet.id
           AND wallet_liability.account_type = 'liability'
           AND wallet_liability.normal_balance = 'credit'
           AND wallet_liability.currency = funding.currency
          JOIN ledger_accounts platform_cash
            ON platform_cash.organization_id = funding.organization_id
           AND platform_cash.code = 'PLATFORM_CASH:' || funding.currency
          WHERE je.id = journal_entry_id_to_check
            AND je.event_type = 'wallet.funded'
            AND je.status = 'posted'
            AND je.organization_id = funding.organization_id
            AND je.idempotency_key = funding.idempotency_key
            AND funding.status = 'posted'
            AND wallet.organization_id = funding.organization_id
            AND wallet.currency = funding.currency
            AND (SELECT COUNT(*) FROM ledger_lines WHERE journal_entry_id = je.id) = 2
            AND financial_journal_line_exists(je.id, platform_cash.id, 'debit', funding.amount_cents, funding.currency)
            AND financial_journal_line_exists(je.id, wallet_liability.id, 'credit', funding.amount_cents, funding.currency)
        ) INTO has_evidence;
        IF has_evidence THEN
          RETURN true;
        END IF;

        SELECT EXISTS (
          SELECT 1
          FROM journal_entries je
          JOIN transfers transfer
            ON transfer.id = je.reference_id
           AND je.reference_type = 'Transfer'
           AND transfer.journal_entry_id = je.id
          JOIN wallets source_wallet ON source_wallet.id = transfer.source_wallet_id
          JOIN wallets destination_wallet ON destination_wallet.id = transfer.destination_wallet_id
          JOIN ledger_accounts source_liability
            ON source_liability.wallet_id = source_wallet.id
           AND source_liability.account_type = 'liability'
           AND source_liability.normal_balance = 'credit'
           AND source_liability.currency = transfer.currency
          JOIN ledger_accounts destination_liability
            ON destination_liability.wallet_id = destination_wallet.id
           AND destination_liability.account_type = 'liability'
           AND destination_liability.normal_balance = 'credit'
           AND destination_liability.currency = transfer.currency
          WHERE je.id = journal_entry_id_to_check
            AND je.event_type = 'wallet.transfer.posted'
            AND je.status = 'posted'
            AND je.organization_id = transfer.organization_id
            AND je.idempotency_key = transfer.idempotency_key
            AND transfer.status = 'posted'
            AND source_wallet.organization_id = transfer.organization_id
            AND destination_wallet.organization_id = transfer.organization_id
            AND source_wallet.currency = transfer.currency
            AND destination_wallet.currency = transfer.currency
            AND source_wallet.id <> destination_wallet.id
            AND (SELECT COUNT(*) FROM ledger_lines WHERE journal_entry_id = je.id) = 2
            AND financial_journal_line_exists(je.id, source_liability.id, 'debit', transfer.amount_cents, transfer.currency)
            AND financial_journal_line_exists(je.id, destination_liability.id, 'credit', transfer.amount_cents, transfer.currency)
        ) INTO has_evidence;
        IF has_evidence THEN
          RETURN true;
        END IF;

        SELECT EXISTS (
          SELECT 1
          FROM journal_entries je
          JOIN split_payments split_payment
            ON split_payment.id = je.reference_id
           AND je.reference_type = 'SplitPayment'
           AND split_payment.journal_entry_id = je.id
          JOIN wallets source_wallet ON source_wallet.id = split_payment.source_wallet_id
          JOIN ledger_accounts source_liability
            ON source_liability.wallet_id = source_wallet.id
           AND source_liability.account_type = 'liability'
           AND source_liability.normal_balance = 'credit'
           AND source_liability.currency = split_payment.currency
          WHERE je.id = journal_entry_id_to_check
            AND je.event_type = 'split.posted'
            AND je.status = 'posted'
            AND je.organization_id = split_payment.organization_id
            AND je.idempotency_key = split_payment.idempotency_key
            AND split_payment.status = 'posted'
            AND source_wallet.organization_id = split_payment.organization_id
            AND source_wallet.currency = split_payment.currency
            AND (SELECT COUNT(*) FROM split_entries WHERE split_payment_id = split_payment.id) > 0
            AND (SELECT COALESCE(SUM(amount_cents), 0) FROM split_entries WHERE split_payment_id = split_payment.id) = split_payment.total_amount_cents
            AND (SELECT COUNT(*) FROM ledger_lines WHERE journal_entry_id = je.id) =
              1 + (SELECT COUNT(*) FROM split_entries WHERE split_payment_id = split_payment.id)
            AND financial_journal_line_exists(je.id, source_liability.id, 'debit', split_payment.total_amount_cents, split_payment.currency)
            AND NOT EXISTS (
              SELECT 1
              FROM split_entries split_entry
              JOIN wallets destination_wallet ON destination_wallet.id = split_entry.destination_wallet_id
              JOIN ledger_accounts destination_liability
                ON destination_liability.wallet_id = destination_wallet.id
               AND destination_liability.account_type = 'liability'
               AND destination_liability.normal_balance = 'credit'
               AND destination_liability.currency = split_entry.currency
              WHERE split_entry.split_payment_id = split_payment.id
                AND (
                  split_entry.organization_id <> split_payment.organization_id
                  OR split_entry.currency <> split_payment.currency
                  OR destination_wallet.organization_id <> split_payment.organization_id
                  OR destination_wallet.currency <> split_payment.currency
                  OR destination_wallet.id = source_wallet.id
                  OR NOT financial_journal_line_exists(
                    je.id,
                    destination_liability.id,
                    'credit',
                    split_entry.amount_cents,
                    split_entry.currency
                  )
                )
            )
        ) INTO has_evidence;
        IF has_evidence THEN
          RETURN true;
        END IF;

        SELECT EXISTS (
          SELECT 1
          FROM journal_entries je
          JOIN pix_payments pix_payment
            ON pix_payment.id = je.reference_id
           AND je.reference_type = 'PixPayment'
           AND pix_payment.journal_entry_id = je.id
          JOIN wallets wallet ON wallet.id = pix_payment.wallet_id
          JOIN ledger_accounts wallet_liability
            ON wallet_liability.wallet_id = wallet.id
           AND wallet_liability.account_type = 'liability'
           AND wallet_liability.normal_balance = 'credit'
           AND wallet_liability.currency = pix_payment.currency
          JOIN ledger_accounts pix_clearing
            ON pix_clearing.organization_id = pix_payment.organization_id
           AND pix_clearing.code = 'PIX_CLEARING:' || pix_payment.currency
          WHERE je.id = journal_entry_id_to_check
            AND je.event_type = 'pix.payment.approved'
            AND je.status = 'posted'
            AND je.organization_id = pix_payment.organization_id
            AND je.idempotency_key = pix_payment.idempotency_key
            AND pix_payment.status IN ('approved', 'settled', 'reversed')
            AND wallet.organization_id = pix_payment.organization_id
            AND wallet.currency = pix_payment.currency
            AND (SELECT COUNT(*) FROM ledger_lines WHERE journal_entry_id = je.id) = 2
            AND financial_journal_line_exists(je.id, wallet_liability.id, 'debit', pix_payment.amount_cents, pix_payment.currency)
            AND financial_journal_line_exists(je.id, pix_clearing.id, 'credit', pix_payment.amount_cents, pix_payment.currency)
        ) INTO has_evidence;
        IF has_evidence THEN
          RETURN true;
        END IF;

        SELECT EXISTS (
          SELECT 1
          FROM journal_entries je
          JOIN pix_payments pix_payment
            ON pix_payment.id = je.reference_id
           AND je.reference_type = 'PixPayment'
           AND pix_payment.settlement_journal_entry_id = je.id
          JOIN ledger_accounts pix_clearing
            ON pix_clearing.organization_id = pix_payment.organization_id
           AND pix_clearing.code = 'PIX_CLEARING:' || pix_payment.currency
          JOIN ledger_accounts platform_cash
            ON platform_cash.organization_id = pix_payment.organization_id
           AND platform_cash.code = 'PLATFORM_CASH:' || pix_payment.currency
          WHERE je.id = journal_entry_id_to_check
            AND je.event_type = 'pix.payment.settled'
            AND je.status = 'posted'
            AND je.organization_id = pix_payment.organization_id
            AND je.idempotency_key = 'pix_payment.settle:' || pix_payment.id::text
            AND pix_payment.status IN ('settled', 'reversed')
            AND (SELECT COUNT(*) FROM ledger_lines WHERE journal_entry_id = je.id) = 2
            AND financial_journal_line_exists(je.id, pix_clearing.id, 'debit', pix_payment.amount_cents, pix_payment.currency)
            AND financial_journal_line_exists(je.id, platform_cash.id, 'credit', pix_payment.amount_cents, pix_payment.currency)
        ) INTO has_evidence;
        IF has_evidence THEN
          RETURN true;
        END IF;

        SELECT EXISTS (
          SELECT 1
          FROM journal_entries je
          JOIN pix_payments pix_payment
            ON pix_payment.id = je.reference_id
           AND je.reference_type = 'PixPayment'
           AND pix_payment.reversal_journal_entry_id = je.id
          JOIN wallets wallet ON wallet.id = pix_payment.wallet_id
          JOIN ledger_accounts wallet_liability
            ON wallet_liability.wallet_id = wallet.id
           AND wallet_liability.account_type = 'liability'
           AND wallet_liability.normal_balance = 'credit'
           AND wallet_liability.currency = pix_payment.currency
          JOIN ledger_accounts platform_cash
            ON platform_cash.organization_id = pix_payment.organization_id
           AND platform_cash.code = 'PLATFORM_CASH:' || pix_payment.currency
          WHERE je.id = journal_entry_id_to_check
            AND je.event_type = 'pix.payment.reversed'
            AND je.status = 'posted'
            AND je.organization_id = pix_payment.organization_id
            AND je.idempotency_key = 'pix_payment.reverse:' || pix_payment.id::text
            AND pix_payment.status = 'reversed'
            AND wallet.organization_id = pix_payment.organization_id
            AND wallet.currency = pix_payment.currency
            AND (SELECT COUNT(*) FROM ledger_lines WHERE journal_entry_id = je.id) = 2
            AND financial_journal_line_exists(je.id, platform_cash.id, 'debit', pix_payment.amount_cents, pix_payment.currency)
            AND financial_journal_line_exists(je.id, wallet_liability.id, 'credit', pix_payment.amount_cents, pix_payment.currency)
        ) INTO has_evidence;
        IF has_evidence THEN
          RETURN true;
        END IF;

        SELECT EXISTS (
          SELECT 1
          FROM journal_entries je
          JOIN payouts payout
            ON payout.id = je.reference_id
           AND je.reference_type = 'Payout'
           AND payout.journal_entry_id = je.id
          JOIN wallets wallet ON wallet.id = payout.wallet_id
          JOIN ledger_accounts wallet_liability
            ON wallet_liability.wallet_id = wallet.id
           AND wallet_liability.account_type = 'liability'
           AND wallet_liability.normal_balance = 'credit'
           AND wallet_liability.currency = payout.currency
          JOIN ledger_accounts payout_clearing
            ON payout_clearing.organization_id = payout.organization_id
           AND payout_clearing.code = 'PAYOUT_CLEARING:' || payout.currency
          WHERE je.id = journal_entry_id_to_check
            AND je.event_type = 'payout.scheduled'
            AND je.status = 'posted'
            AND je.organization_id = payout.organization_id
            AND je.idempotency_key = payout.idempotency_key
            AND payout.status IN ('scheduled', 'settled')
            AND wallet.organization_id = payout.organization_id
            AND wallet.currency = payout.currency
            AND (SELECT COUNT(*) FROM ledger_lines WHERE journal_entry_id = je.id) = 2
            AND financial_journal_line_exists(je.id, wallet_liability.id, 'debit', payout.amount_cents, payout.currency)
            AND financial_journal_line_exists(je.id, payout_clearing.id, 'credit', payout.amount_cents, payout.currency)
        ) INTO has_evidence;
        IF has_evidence THEN
          RETURN true;
        END IF;

        SELECT EXISTS (
          SELECT 1
          FROM journal_entries je
          JOIN payouts payout
            ON payout.id = je.reference_id
           AND je.reference_type = 'Payout'
           AND payout.settlement_journal_entry_id = je.id
          JOIN ledger_accounts payout_clearing
            ON payout_clearing.organization_id = payout.organization_id
           AND payout_clearing.code = 'PAYOUT_CLEARING:' || payout.currency
          JOIN ledger_accounts platform_cash
            ON platform_cash.organization_id = payout.organization_id
           AND platform_cash.code = 'PLATFORM_CASH:' || payout.currency
          WHERE je.id = journal_entry_id_to_check
            AND je.event_type = 'payout.settled'
            AND je.status = 'posted'
            AND je.organization_id = payout.organization_id
            AND je.idempotency_key = 'payout.settle:' || payout.id::text
            AND payout.status = 'settled'
            AND (SELECT COUNT(*) FROM ledger_lines WHERE journal_entry_id = je.id) = 2
            AND financial_journal_line_exists(je.id, payout_clearing.id, 'debit', payout.amount_cents, payout.currency)
            AND financial_journal_line_exists(je.id, platform_cash.id, 'credit', payout.amount_cents, payout.currency)
        ) INTO has_evidence;
        IF has_evidence THEN
          RETURN true;
        END IF;

        SELECT EXISTS (
          SELECT 1
          FROM journal_entries je
          JOIN refunds refund
            ON refund.id = je.reference_id
           AND je.reference_type = 'Refund'
           AND refund.journal_entry_id = je.id
          JOIN wallets wallet ON wallet.id = refund.wallet_id
          JOIN ledger_accounts wallet_liability
            ON wallet_liability.wallet_id = wallet.id
           AND wallet_liability.account_type = 'liability'
           AND wallet_liability.normal_balance = 'credit'
           AND wallet_liability.currency = refund.currency
          JOIN ledger_accounts platform_cash
            ON platform_cash.organization_id = refund.organization_id
           AND platform_cash.code = 'PLATFORM_CASH:' || refund.currency
          WHERE je.id = journal_entry_id_to_check
            AND je.event_type = 'refund.settled'
            AND je.status = 'posted'
            AND je.organization_id = refund.organization_id
            AND je.idempotency_key = refund.idempotency_key
            AND refund.status = 'settled'
            AND wallet.organization_id = refund.organization_id
            AND wallet.currency = refund.currency
            AND (SELECT COUNT(*) FROM ledger_lines WHERE journal_entry_id = je.id) = 2
            AND financial_journal_line_exists(je.id, platform_cash.id, 'debit', refund.amount_cents, refund.currency)
            AND financial_journal_line_exists(je.id, wallet_liability.id, 'credit', refund.amount_cents, refund.currency)
        ) INTO has_evidence;
        RETURN has_evidence;
      END;
      $$;

      CREATE OR REPLACE FUNCTION assert_financial_journal_evidence(journal_entry_id_to_check bigint)
      RETURNS void
      LANGUAGE plpgsql
      AS $$
      DECLARE
        event_type_to_check text;
      BEGIN
        SELECT event_type INTO event_type_to_check
        FROM journal_entries
        WHERE id = journal_entry_id_to_check;

        IF event_type_to_check IS NULL THEN
          RETURN;
        END IF;

        IF financial_journal_event_type_requires_evidence(event_type_to_check)
          AND NOT financial_journal_has_aggregate_evidence(journal_entry_id_to_check) THEN
          RAISE EXCEPTION 'financial journal entry does not match aggregate evidence';
        END IF;
      END;
      $$;

      CREATE OR REPLACE FUNCTION assert_financial_journal_evidence_after_journal_write()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        PERFORM assert_financial_journal_evidence(NEW.id);
        RETURN NEW;
      END;
      $$;

      CREATE OR REPLACE FUNCTION assert_financial_journal_evidence_after_line_write()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        PERFORM assert_financial_journal_evidence(NEW.journal_entry_id);
        RETURN NEW;
      END;
      $$;

      CREATE OR REPLACE FUNCTION assert_financial_command_journal_evidence()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_TABLE_NAME = 'fundings' AND NEW.journal_entry_id IS NOT NULL
          AND NOT financial_journal_has_aggregate_evidence(NEW.journal_entry_id) THEN
          RAISE EXCEPTION 'funding journal evidence does not match aggregate';
        END IF;

        IF TG_TABLE_NAME = 'transfers' AND NEW.journal_entry_id IS NOT NULL
          AND NOT financial_journal_has_aggregate_evidence(NEW.journal_entry_id) THEN
          RAISE EXCEPTION 'transfer journal evidence does not match aggregate';
        END IF;

        IF TG_TABLE_NAME = 'split_payments' AND NEW.journal_entry_id IS NOT NULL
          AND NOT financial_journal_has_aggregate_evidence(NEW.journal_entry_id) THEN
          RAISE EXCEPTION 'split payment journal evidence does not match aggregate';
        END IF;

        IF TG_TABLE_NAME = 'pix_payments' THEN
          IF NEW.journal_entry_id IS NOT NULL
            AND NOT financial_journal_has_aggregate_evidence(NEW.journal_entry_id) THEN
            RAISE EXCEPTION 'Pix approval journal evidence does not match aggregate';
          END IF;

          IF NEW.settlement_journal_entry_id IS NOT NULL
            AND NOT financial_journal_has_aggregate_evidence(NEW.settlement_journal_entry_id) THEN
            RAISE EXCEPTION 'Pix settlement journal evidence does not match aggregate';
          END IF;

          IF NEW.reversal_journal_entry_id IS NOT NULL
            AND NOT financial_journal_has_aggregate_evidence(NEW.reversal_journal_entry_id) THEN
            RAISE EXCEPTION 'Pix reversal journal evidence does not match aggregate';
          END IF;
        END IF;

        IF TG_TABLE_NAME = 'payouts' THEN
          IF NEW.journal_entry_id IS NOT NULL
            AND NOT financial_journal_has_aggregate_evidence(NEW.journal_entry_id) THEN
            RAISE EXCEPTION 'payout schedule journal evidence does not match aggregate';
          END IF;

          IF NEW.settlement_journal_entry_id IS NOT NULL
            AND NOT financial_journal_has_aggregate_evidence(NEW.settlement_journal_entry_id) THEN
            RAISE EXCEPTION 'payout settlement journal evidence does not match aggregate';
          END IF;
        END IF;

        IF TG_TABLE_NAME = 'refunds' AND NEW.journal_entry_id IS NOT NULL
          AND NOT financial_journal_has_aggregate_evidence(NEW.journal_entry_id) THEN
          RAISE EXCEPTION 'refund journal evidence does not match aggregate';
        END IF;

        RETURN NEW;
      END;
      $$;

      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM journal_entries
          WHERE financial_journal_event_type_requires_evidence(event_type)
            AND NOT financial_journal_has_aggregate_evidence(id)
        ) THEN
          RAISE EXCEPTION 'existing financial journal entries violate aggregate evidence guards';
        END IF;

        IF EXISTS (
          SELECT 1 FROM fundings WHERE journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(journal_entry_id)
          UNION ALL
          SELECT 1 FROM transfers WHERE journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(journal_entry_id)
          UNION ALL
          SELECT 1 FROM split_payments WHERE journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(journal_entry_id)
          UNION ALL
          SELECT 1 FROM pix_payments WHERE journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(journal_entry_id)
          UNION ALL
          SELECT 1 FROM pix_payments WHERE settlement_journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(settlement_journal_entry_id)
          UNION ALL
          SELECT 1 FROM pix_payments WHERE reversal_journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(reversal_journal_entry_id)
          UNION ALL
          SELECT 1 FROM payouts WHERE journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(journal_entry_id)
          UNION ALL
          SELECT 1 FROM payouts WHERE settlement_journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(settlement_journal_entry_id)
          UNION ALL
          SELECT 1 FROM refunds WHERE journal_entry_id IS NOT NULL AND NOT financial_journal_has_aggregate_evidence(journal_entry_id)
        ) THEN
          RAISE EXCEPTION 'existing financial commands violate journal evidence guards';
        END IF;
      END
      $$;

      DROP TRIGGER IF EXISTS journal_entries_financial_evidence_after_write ON journal_entries;
      CREATE CONSTRAINT TRIGGER journal_entries_financial_evidence_after_write
      AFTER INSERT ON journal_entries
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_financial_journal_evidence_after_journal_write();

      DROP TRIGGER IF EXISTS ledger_lines_financial_evidence_after_write ON ledger_lines;
      CREATE CONSTRAINT TRIGGER ledger_lines_financial_evidence_after_write
      AFTER INSERT ON ledger_lines
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_financial_journal_evidence_after_line_write();

      DROP TRIGGER IF EXISTS fundings_journal_evidence_after_write ON fundings;
      CREATE CONSTRAINT TRIGGER fundings_journal_evidence_after_write
      AFTER INSERT OR UPDATE ON fundings
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_financial_command_journal_evidence();

      DROP TRIGGER IF EXISTS transfers_journal_evidence_after_write ON transfers;
      CREATE CONSTRAINT TRIGGER transfers_journal_evidence_after_write
      AFTER INSERT OR UPDATE ON transfers
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_financial_command_journal_evidence();

      DROP TRIGGER IF EXISTS split_payments_journal_evidence_after_write ON split_payments;
      CREATE CONSTRAINT TRIGGER split_payments_journal_evidence_after_write
      AFTER INSERT OR UPDATE ON split_payments
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_financial_command_journal_evidence();

      DROP TRIGGER IF EXISTS pix_payments_journal_evidence_after_write ON pix_payments;
      CREATE CONSTRAINT TRIGGER pix_payments_journal_evidence_after_write
      AFTER INSERT OR UPDATE ON pix_payments
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_financial_command_journal_evidence();

      DROP TRIGGER IF EXISTS payouts_journal_evidence_after_write ON payouts;
      CREATE CONSTRAINT TRIGGER payouts_journal_evidence_after_write
      AFTER INSERT OR UPDATE ON payouts
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_financial_command_journal_evidence();

      DROP TRIGGER IF EXISTS refunds_journal_evidence_after_write ON refunds;
      CREATE CONSTRAINT TRIGGER refunds_journal_evidence_after_write
      AFTER INSERT OR UPDATE ON refunds
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_financial_command_journal_evidence();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS refunds_journal_evidence_after_write ON refunds;
      DROP TRIGGER IF EXISTS payouts_journal_evidence_after_write ON payouts;
      DROP TRIGGER IF EXISTS pix_payments_journal_evidence_after_write ON pix_payments;
      DROP TRIGGER IF EXISTS split_payments_journal_evidence_after_write ON split_payments;
      DROP TRIGGER IF EXISTS transfers_journal_evidence_after_write ON transfers;
      DROP TRIGGER IF EXISTS fundings_journal_evidence_after_write ON fundings;
      DROP TRIGGER IF EXISTS ledger_lines_financial_evidence_after_write ON ledger_lines;
      DROP TRIGGER IF EXISTS journal_entries_financial_evidence_after_write ON journal_entries;
      DROP FUNCTION IF EXISTS assert_financial_command_journal_evidence();
      DROP FUNCTION IF EXISTS assert_financial_journal_evidence_after_line_write();
      DROP FUNCTION IF EXISTS assert_financial_journal_evidence_after_journal_write();
      DROP FUNCTION IF EXISTS assert_financial_journal_evidence(bigint);
      DROP FUNCTION IF EXISTS financial_journal_has_aggregate_evidence(bigint);
      DROP FUNCTION IF EXISTS financial_journal_line_exists(bigint, bigint, text, bigint, text);
      DROP FUNCTION IF EXISTS financial_journal_event_type_requires_evidence(text);
    SQL
  end

  private

  def backfill_legacy_financial_journal_idempotency_keys
    with_journal_entry_mutation_guard_disabled do
      execute <<~SQL.squish
        UPDATE journal_entries
           SET idempotency_key = 'pix_payment.settle:' || pix_payments.id::text,
               updated_at = CURRENT_TIMESTAMP
          FROM pix_payments
         WHERE journal_entries.id = pix_payments.settlement_journal_entry_id
           AND journal_entries.event_type = 'pix.payment.settled'
           AND journal_entries.idempotency_key LIKE 'legacy-journal-entry:%'
      SQL

      execute <<~SQL.squish
        UPDATE journal_entries
           SET idempotency_key = 'pix_payment.reverse:' || pix_payments.id::text,
               updated_at = CURRENT_TIMESTAMP
          FROM pix_payments
         WHERE journal_entries.id = pix_payments.reversal_journal_entry_id
           AND journal_entries.event_type = 'pix.payment.reversed'
           AND journal_entries.idempotency_key LIKE 'legacy-journal-entry:%'
      SQL

      execute <<~SQL.squish
        UPDATE journal_entries
           SET idempotency_key = 'payout.settle:' || payouts.id::text,
               updated_at = CURRENT_TIMESTAMP
          FROM payouts
         WHERE journal_entries.id = payouts.settlement_journal_entry_id
           AND journal_entries.event_type = 'payout.settled'
           AND journal_entries.idempotency_key LIKE 'legacy-journal-entry:%'
      SQL
    end
  end

  def with_journal_entry_mutation_guard_disabled
    execute "ALTER TABLE journal_entries DISABLE TRIGGER prevent_journal_entry_mutation"
    yield
  ensure
    execute "ALTER TABLE journal_entries ENABLE TRIGGER prevent_journal_entry_mutation"
  end
end
