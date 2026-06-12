SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: assert_balance_projection_amount_write_context(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_balance_projection_amount_write_context() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  write_context text;
BEGIN
  write_context := current_setting('settleflow.balance_projection_write_context', true);

  IF COALESCE(NULLIF(btrim(write_context), ''), 'none') NOT IN ('ledger_journal_poster', 'balance_projection_rebuilder') THEN
    RAISE EXCEPTION 'balance projection amount updates require ledger or rebuild write context';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: assert_balance_projection_wallet_evidence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_balance_projection_wallet_evidence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  wallet_row wallets%ROWTYPE;
BEGIN
  SELECT * INTO wallet_row
  FROM wallets
  WHERE id = NEW.wallet_id;

  IF wallet_row.id IS NULL THEN
    RAISE EXCEPTION 'balance projection must reference an existing wallet';
  END IF;

  IF wallet_row.organization_id <> NEW.organization_id THEN
    RAISE EXCEPTION 'balance projection organization must match wallet organization';
  END IF;

  IF wallet_row.currency <> NEW.currency THEN
    RAISE EXCEPTION 'balance projection currency must match wallet currency';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: assert_financial_command_journal_evidence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_financial_command_journal_evidence() RETURNS trigger
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


--
-- Name: assert_financial_journal_evidence(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_financial_journal_evidence(journal_entry_id_to_check bigint) RETURNS void
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


--
-- Name: assert_financial_journal_evidence_after_journal_write(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_financial_journal_evidence_after_journal_write() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM assert_financial_journal_evidence(NEW.id);
  RETURN NEW;
END;
$$;


--
-- Name: assert_financial_journal_evidence_after_line_write(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_financial_journal_evidence_after_line_write() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM assert_financial_journal_evidence(NEW.journal_entry_id);
  RETURN NEW;
END;
$$;


--
-- Name: assert_funding_state_evidence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_funding_state_evidence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  funding_row fundings%ROWTYPE;
BEGIN
  SELECT * INTO funding_row FROM fundings WHERE id = NEW.id;

  IF NOT EXISTS (
    SELECT 1
    FROM wallets
    WHERE wallets.id = funding_row.wallet_id
      AND wallets.organization_id = funding_row.organization_id
      AND wallets.currency = funding_row.currency
  ) THEN
    RAISE EXCEPTION 'funding wallet must match organization and currency';
  END IF;

  IF funding_row.status = 'posted' AND funding_row.journal_entry_id IS NULL THEN
    RAISE EXCEPTION 'posted funding requires journal evidence';
  END IF;

  IF funding_row.status = 'failed'
    AND (funding_row.failure_code IS NULL OR funding_row.journal_entry_id IS NOT NULL) THEN
    RAISE EXCEPTION 'failed funding requires failure evidence without journal';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: assert_inserted_journal_entry_balanced(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_inserted_journal_entry_balanced() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM assert_journal_entry_balanced(NEW.id);
  RETURN NULL;
END;
$$;


--
-- Name: assert_journal_entry_balanced(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_journal_entry_balanced(journal_entry_id_to_check bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  line_count integer;
  imbalance_count integer;
BEGIN
  SELECT COUNT(*) INTO line_count
  FROM ledger_lines
  WHERE journal_entry_id = journal_entry_id_to_check;

  IF line_count < 2 THEN
    RAISE EXCEPTION 'journal entry must have at least two ledger lines';
  END IF;

  SELECT COUNT(*) INTO imbalance_count
  FROM (
    SELECT currency
    FROM ledger_lines
    WHERE journal_entry_id = journal_entry_id_to_check
    GROUP BY currency
    HAVING
      SUM(CASE WHEN direction = 'debit' THEN amount_cents ELSE 0 END) <>
      SUM(CASE WHEN direction = 'credit' THEN amount_cents ELSE 0 END)
  ) imbalances;

  IF imbalance_count > 0 THEN
    RAISE EXCEPTION 'journal entry is not balanced';
  END IF;
END;
$$;


--
-- Name: assert_ledger_line_journal_entry_balanced(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_ledger_line_journal_entry_balanced() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM assert_journal_entry_balanced(NEW.journal_entry_id);
  RETURN NULL;
END;
$$;


--
-- Name: assert_med_case_state_evidence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_med_case_state_evidence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  med_case_row med_cases%ROWTYPE;
BEGIN
  SELECT * INTO med_case_row FROM med_cases WHERE id = NEW.id;

  IF med_case_row.status = 'opened'
    AND (
      med_case_row.refund_id IS NOT NULL
      OR med_case_row.resolved_at IS NOT NULL
      OR med_case_row.operator_approval_id IS NOT NULL
    ) THEN
    RAISE EXCEPTION 'opened MED case cannot have resolution evidence';
  END IF;

  IF med_case_row.status = 'rejected'
    AND (
      med_case_row.refund_id IS NOT NULL
      OR med_case_row.resolved_at IS NULL
      OR med_case_row.operator_approval_id IS NULL
      OR NOT med_case_has_resolution_approval(med_case_row.id)
    ) THEN
    RAISE EXCEPTION 'rejected MED case requires approved rejection evidence without refund';
  END IF;

  IF med_case_row.status = 'refunded'
    AND (
      med_case_row.refund_id IS NULL
      OR med_case_row.resolved_at IS NULL
      OR med_case_row.operator_approval_id IS NULL
      OR NOT med_case_has_refund_evidence(med_case_row.id)
      OR NOT med_case_has_resolution_approval(med_case_row.id)
    ) THEN
    RAISE EXCEPTION 'refunded MED case requires refund, resolution, and approved acceptance evidence';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: assert_med_outbox_resolution_payload_evidence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_med_outbox_resolution_payload_evidence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NOT med_outbox_event_has_resolution_payload_evidence(NEW) THEN
    RAISE EXCEPTION 'MED resolution outbox payload evidence is invalid';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: assert_outbox_event_aggregate_evidence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_outbox_event_aggregate_evidence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NOT outbox_event_has_aggregate_evidence(NEW) THEN
    RAISE EXCEPTION 'outbox event aggregate evidence is invalid';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: assert_outbox_event_command_identity_evidence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_outbox_event_command_identity_evidence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NOT outbox_event_has_command_identity_evidence(NEW) THEN
    RAISE EXCEPTION 'outbox event command identity evidence is invalid';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: assert_payout_state_evidence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_payout_state_evidence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  payout_row payouts%ROWTYPE;
BEGIN
  SELECT * INTO payout_row FROM payouts WHERE id = NEW.id;

  IF payout_row.status = 'scheduled'
    AND (
      payout_row.journal_entry_id IS NULL
      OR payout_row.settlement_journal_entry_id IS NOT NULL
      OR payout_row.settled_at IS NOT NULL
      OR payout_row.operator_approval_id IS NOT NULL
    ) THEN
    RAISE EXCEPTION 'scheduled payout requires schedule journal evidence only';
  END IF;

  IF payout_row.status = 'settled'
    AND (
      payout_row.journal_entry_id IS NULL
      OR payout_row.settlement_journal_entry_id IS NULL
      OR payout_row.settled_at IS NULL
    ) THEN
    RAISE EXCEPTION 'settled payout requires schedule and settlement journal evidence';
  END IF;

  IF payout_row.status = 'settled'
    AND payout_row.settled_at::date < payout_row.settlement_due_on
    AND NOT payout_has_early_settlement_approval(payout_row.id) THEN
    RAISE EXCEPTION 'early payout settlement requires approved maker-checker evidence';
  END IF;

  IF payout_row.status = 'failed' AND payout_row.failure_code IS NULL THEN
    RAISE EXCEPTION 'failed payout requires a failure code';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: assert_pix_payment_refund_evidence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_pix_payment_refund_evidence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NOT refund_pix_payment_evidence_valid(NEW.id) THEN
    RAISE EXCEPTION 'Pix payment state conflicts with settled refund evidence';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: assert_pix_payment_state_evidence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_pix_payment_state_evidence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  pix_payment_row pix_payments%ROWTYPE;
BEGIN
  SELECT * INTO pix_payment_row FROM pix_payments WHERE id = NEW.id;

  IF pix_payment_row.status IN ('created', 'pending_review')
    AND (
      pix_payment_row.journal_entry_id IS NOT NULL
      OR pix_payment_row.settlement_journal_entry_id IS NOT NULL
      OR pix_payment_row.reversal_journal_entry_id IS NOT NULL
      OR pix_payment_row.reversed_at IS NOT NULL
      OR pix_payment_row.reversal_reason IS NOT NULL
    ) THEN
    RAISE EXCEPTION 'unposted Pix payment cannot have journal evidence';
  END IF;

  IF pix_payment_row.status = 'rejected'
    AND (
      pix_payment_row.failure_code IS NULL
      OR pix_payment_row.journal_entry_id IS NOT NULL
      OR pix_payment_row.settlement_journal_entry_id IS NOT NULL
      OR pix_payment_row.reversal_journal_entry_id IS NOT NULL
    ) THEN
    RAISE EXCEPTION 'rejected Pix payment requires failure evidence only';
  END IF;

  IF pix_payment_row.status = 'approved'
    AND (
      pix_payment_row.journal_entry_id IS NULL
      OR pix_payment_row.settlement_journal_entry_id IS NOT NULL
      OR pix_payment_row.reversal_journal_entry_id IS NOT NULL
    ) THEN
    RAISE EXCEPTION 'approved Pix payment requires approval journal evidence only';
  END IF;

  IF pix_payment_row.status = 'settled'
    AND (
      pix_payment_row.journal_entry_id IS NULL
      OR pix_payment_row.settlement_journal_entry_id IS NULL
      OR pix_payment_row.reversal_journal_entry_id IS NOT NULL
    ) THEN
    RAISE EXCEPTION 'settled Pix payment requires approval and settlement journal evidence';
  END IF;

  IF pix_payment_row.status = 'reversed'
    AND (
      pix_payment_row.journal_entry_id IS NULL
      OR pix_payment_row.settlement_journal_entry_id IS NULL
      OR pix_payment_row.reversal_journal_entry_id IS NULL
      OR pix_payment_row.reversed_at IS NULL
      OR pix_payment_row.reversal_reason IS NULL
    ) THEN
    RAISE EXCEPTION 'reversed Pix payment requires reversal evidence';
  END IF;

  IF pix_payment_row.status = 'failed' AND pix_payment_row.failure_code IS NULL THEN
    RAISE EXCEPTION 'failed Pix payment requires a failure code';
  END IF;

  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: processed_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.processed_events (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    outbox_event_id bigint NOT NULL,
    processor character varying NOT NULL,
    event_id character varying NOT NULL,
    event_type character varying NOT NULL,
    status character varying DEFAULT 'processing'::character varying NOT NULL,
    payload_sha256 character varying NOT NULL,
    processed_at timestamp(6) without time zone,
    error_class character varying,
    last_error text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT processed_events_payload_sha256_hex_check CHECK (((payload_sha256)::text ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT processed_events_state_evidence_check CHECK (((((status)::text = 'processing'::text) AND (processed_at IS NULL) AND (error_class IS NULL) AND (last_error IS NULL)) OR (((status)::text = 'processed'::text) AND (processed_at IS NOT NULL) AND (error_class IS NULL) AND (last_error IS NULL)) OR (((status)::text = 'failed'::text) AND (processed_at IS NULL) AND (error_class IS NOT NULL) AND (btrim((error_class)::text) <> ''::text) AND (last_error IS NOT NULL) AND (btrim(last_error) <> ''::text)))),
    CONSTRAINT processed_events_status_check CHECK (((status)::text = ANY ((ARRAY['processing'::character varying, 'processed'::character varying, 'failed'::character varying])::text[])))
);


--
-- Name: assert_processed_event_outbox_evidence(public.processed_events); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_processed_event_outbox_evidence(processed_event_row public.processed_events) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM outbox_events
    WHERE outbox_events.id = processed_event_row.outbox_event_id
      AND outbox_events.organization_id = processed_event_row.organization_id
      AND outbox_events.public_id::text = processed_event_row.event_id
      AND outbox_events.event_type = processed_event_row.event_type
      AND outbox_events.payload_sha256 = processed_event_row.payload_sha256
      AND outbox_events.status = 'published'
      AND outbox_events.published_at IS NOT NULL
      AND outbox_events.payload_sha256 IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'processed event must match a published outbox event';
  END IF;
END;
$$;


--
-- Name: assert_reconciliation_run_evidence(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_reconciliation_run_evidence(run_id_to_check bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  run_row reconciliation_runs%ROWTYPE;
BEGIN
  SELECT * INTO run_row
  FROM reconciliation_runs
  WHERE id = run_id_to_check;

  IF run_row.id IS NULL THEN
    RETURN;
  END IF;

  IF NOT reconciliation_run_has_outbox_evidence(run_row.id) THEN
    RAISE EXCEPTION 'reconciliation run requires outbox evidence';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM reconciliation_rows
    WHERE reconciliation_run_id = run_row.id
  ) THEN
    RAISE EXCEPTION 'reconciliation run requires row evidence';
  END IF;

  IF run_row.status = 'matched' AND EXISTS (
    SELECT 1
    FROM reconciliation_rows
    WHERE reconciliation_run_id = run_row.id
      AND status <> 'matched'
  ) THEN
    RAISE EXCEPTION 'matched reconciliation run cannot contain discrepant rows';
  END IF;

  IF run_row.status = 'discrepant' AND NOT EXISTS (
    SELECT 1
    FROM reconciliation_rows
    WHERE reconciliation_run_id = run_row.id
      AND status <> 'matched'
  ) THEN
    RAISE EXCEPTION 'discrepant reconciliation run requires discrepant row evidence';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM reconciliation_rows row
    LEFT JOIN journal_entries journal ON journal.id = row.journal_entry_id
    WHERE row.reconciliation_run_id = run_row.id
      AND (
        row.organization_id <> run_row.organization_id
        OR (journal.id IS NOT NULL AND journal.organization_id <> row.organization_id)
      )
  ) THEN
    RAISE EXCEPTION 'reconciliation rows must match run and journal organization';
  END IF;
END;
$$;


--
-- Name: assert_reconciliation_run_evidence_after_row_write(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_reconciliation_run_evidence_after_row_write() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM assert_reconciliation_run_evidence(COALESCE(NEW.reconciliation_run_id, OLD.reconciliation_run_id));
  RETURN COALESCE(NEW, OLD);
END;
$$;


--
-- Name: assert_reconciliation_run_evidence_after_run_write(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_reconciliation_run_evidence_after_run_write() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM assert_reconciliation_run_evidence(NEW.id);
  RETURN NEW;
END;
$$;


--
-- Name: assert_refund_pix_payment_evidence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_refund_pix_payment_evidence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NOT refund_pix_payment_evidence_valid(NEW.pix_payment_id) THEN
    RAISE EXCEPTION 'settled refunds exceed or mismatch Pix payment evidence';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: assert_refund_state_evidence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_refund_state_evidence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  refund_row refunds%ROWTYPE;
BEGIN
  SELECT * INTO refund_row FROM refunds WHERE id = NEW.id;

  IF refund_row.status = 'settled'
    AND (refund_row.journal_entry_id IS NULL OR refund_row.settled_at IS NULL) THEN
    RAISE EXCEPTION 'settled refund requires journal evidence';
  END IF;

  IF refund_row.status = 'failed' AND refund_row.failure_code IS NULL THEN
    RAISE EXCEPTION 'failed refund requires a failure code';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: assert_split_entry_state_evidence_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_split_entry_state_evidence_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM assert_split_payment_state_evidence(OLD.split_payment_id);
    RETURN OLD;
  END IF;

  PERFORM assert_split_payment_state_evidence(NEW.split_payment_id);
  IF TG_OP = 'UPDATE' AND OLD.split_payment_id <> NEW.split_payment_id THEN
    PERFORM assert_split_payment_state_evidence(OLD.split_payment_id);
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: assert_split_payment_state_evidence(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_split_payment_state_evidence(split_payment_id_to_check bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  split_payment_row split_payments%ROWTYPE;
  split_entry_count integer;
  split_entry_total bigint;
  mismatched_entry_count integer;
BEGIN
  SELECT * INTO split_payment_row FROM split_payments WHERE id = split_payment_id_to_check;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM wallets
    WHERE wallets.id = split_payment_row.source_wallet_id
      AND wallets.organization_id = split_payment_row.organization_id
      AND wallets.currency = split_payment_row.currency
  ) THEN
    RAISE EXCEPTION 'split source wallet must match organization and currency';
  END IF;

  SELECT COUNT(*), COALESCE(SUM(amount_cents), 0)
  INTO split_entry_count, split_entry_total
  FROM split_entries
  WHERE split_payment_id = split_payment_row.id;

  SELECT COUNT(*)
  INTO mismatched_entry_count
  FROM split_entries
  JOIN wallets ON wallets.id = split_entries.destination_wallet_id
  WHERE split_entries.split_payment_id = split_payment_row.id
    AND (
      split_entries.organization_id <> split_payment_row.organization_id
      OR split_entries.currency <> split_payment_row.currency
      OR wallets.organization_id <> split_payment_row.organization_id
      OR wallets.currency <> split_payment_row.currency
      OR wallets.id = split_payment_row.source_wallet_id
    );

  IF split_payment_row.status = 'posted'
    AND (
      split_payment_row.journal_entry_id IS NULL
      OR split_entry_count = 0
      OR split_entry_total <> split_payment_row.total_amount_cents
      OR mismatched_entry_count > 0
    ) THEN
    RAISE EXCEPTION 'posted split requires journal evidence and matching destination entries';
  END IF;

  IF split_payment_row.status = 'failed'
    AND (split_payment_row.failure_code IS NULL OR split_payment_row.journal_entry_id IS NOT NULL) THEN
    RAISE EXCEPTION 'failed split requires failure evidence without journal';
  END IF;
END;
$$;


--
-- Name: assert_split_payment_state_evidence_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_split_payment_state_evidence_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM assert_split_payment_state_evidence(NEW.id);
  RETURN NEW;
END;
$$;


--
-- Name: assert_transfer_state_evidence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_transfer_state_evidence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  transfer_row transfers%ROWTYPE;
BEGIN
  SELECT * INTO transfer_row FROM transfers WHERE id = NEW.id;

  IF NOT EXISTS (
    SELECT 1
    FROM wallets source_wallets
    JOIN wallets destination_wallets ON destination_wallets.id = transfer_row.destination_wallet_id
    WHERE source_wallets.id = transfer_row.source_wallet_id
      AND source_wallets.id <> destination_wallets.id
      AND source_wallets.organization_id = transfer_row.organization_id
      AND destination_wallets.organization_id = transfer_row.organization_id
      AND source_wallets.currency = transfer_row.currency
      AND destination_wallets.currency = transfer_row.currency
  ) THEN
    RAISE EXCEPTION 'transfer wallets must match organization, currency, and be different';
  END IF;

  IF transfer_row.status = 'posted' AND transfer_row.journal_entry_id IS NULL THEN
    RAISE EXCEPTION 'posted transfer requires journal evidence';
  END IF;

  IF transfer_row.status = 'failed'
    AND (transfer_row.failure_code IS NULL OR transfer_row.journal_entry_id IS NOT NULL) THEN
    RAISE EXCEPTION 'failed transfer requires failure evidence without journal';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: assign_audit_log_hash_chain(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assign_audit_log_hash_chain() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  last_sequence bigint;
  last_hash text;
BEGIN
  PERFORM pg_advisory_xact_lock(860029001);

  SELECT chain_sequence, hash_value
    INTO last_sequence, last_hash
    FROM audit_logs
   ORDER BY chain_sequence DESC
   LIMIT 1;

  NEW.chain_sequence := COALESCE(last_sequence, 0) + 1;
  NEW.previous_hash := last_hash;
  NEW.hash_algorithm := 'sha256';
  NEW.hash_value := audit_log_chain_hash(NEW);

  RETURN NEW;
END;
$$;


--
-- Name: audit_log_anchors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log_anchors (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint,
    audit_log_id bigint NOT NULL,
    chain_sequence bigint NOT NULL,
    hash_value character varying NOT NULL,
    previous_anchor_hash character varying,
    anchor_hash character varying NOT NULL,
    hash_algorithm character varying DEFAULT 'sha256'::character varying NOT NULL,
    anchored_at timestamp(6) without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT audit_log_anchors_anchor_hash_format_check CHECK (((anchor_hash)::text ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT audit_log_anchors_hash_algorithm_check CHECK (((hash_algorithm)::text = 'sha256'::text)),
    CONSTRAINT audit_log_anchors_hash_value_format_check CHECK (((hash_value)::text ~ '^[0-9a-f]{64}$'::text))
);


--
-- Name: audit_log_anchor_hash(public.audit_log_anchors); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_log_anchor_hash(anchor_row public.audit_log_anchors) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT encode(digest(audit_log_anchor_payload(anchor_row)::text, 'sha256'), 'hex')
$$;


--
-- Name: audit_log_anchor_payload(public.audit_log_anchors); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_log_anchor_payload(anchor_row public.audit_log_anchors) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
  RETURN jsonb_build_object(
    'chain_sequence', anchor_row.chain_sequence,
    'hash_value', anchor_row.hash_value,
    'previous_anchor_hash', anchor_row.previous_anchor_hash,
    'hash_algorithm', anchor_row.hash_algorithm,
    'anchored_at', anchor_row.anchored_at
  );
END;
$$;


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint,
    actor_type character varying NOT NULL,
    actor_id bigint,
    action character varying NOT NULL,
    subject_type character varying NOT NULL,
    subject_id bigint,
    request_id character varying,
    correlation_id character varying,
    ip_address character varying,
    user_agent character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    chain_sequence bigint NOT NULL,
    previous_hash character varying,
    hash_value character varying NOT NULL,
    hash_algorithm character varying DEFAULT 'sha256'::character varying NOT NULL,
    CONSTRAINT audit_logs_hash_algorithm_check CHECK (((hash_algorithm)::text = 'sha256'::text)),
    CONSTRAINT audit_logs_hash_value_format_check CHECK (((hash_value)::text ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT audit_logs_previous_hash_required_check CHECK (((chain_sequence = 1) OR (previous_hash IS NOT NULL)))
);


--
-- Name: audit_log_chain_hash(public.audit_logs); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_log_chain_hash(log_row public.audit_logs) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT encode(digest(audit_log_chain_payload(log_row)::text, 'sha256'), 'hex')
$$;


--
-- Name: audit_log_chain_payload(public.audit_logs); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_log_chain_payload(log_row public.audit_logs) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
  RETURN jsonb_build_object(
    'chain_sequence', log_row.chain_sequence,
    'previous_hash', log_row.previous_hash,
    'hash_algorithm', log_row.hash_algorithm,
    'public_id', log_row.public_id,
    'organization_id', log_row.organization_id,
    'actor_type', log_row.actor_type,
    'actor_id', log_row.actor_id,
    'action', log_row.action,
    'subject_type', log_row.subject_type,
    'subject_id', log_row.subject_id,
    'request_id', log_row.request_id,
    'correlation_id', log_row.correlation_id,
    'ip_address', log_row.ip_address,
    'user_agent', log_row.user_agent,
    'metadata', log_row.metadata,
    'created_at', log_row.created_at
  );
END;
$$;


--
-- Name: enforce_ledger_line_account_consistency(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_ledger_line_account_consistency() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM ledger_accounts
    WHERE ledger_accounts.id = NEW.ledger_account_id
      AND ledger_accounts.organization_id = NEW.organization_id
      AND ledger_accounts.currency = NEW.currency
  ) THEN
    RAISE EXCEPTION 'ledger line account must match organization and currency';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: financial_aggregate_has_outbox_evidence(text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.financial_aggregate_has_outbox_evidence(aggregate_type_to_check text, aggregate_id_to_check bigint) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM outbox_events
    WHERE aggregate_type = aggregate_type_to_check
      AND aggregate_id = aggregate_id_to_check
  );
$$;


--
-- Name: financial_journal_event_type_requires_evidence(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.financial_journal_event_type_requires_evidence(event_type_to_check text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
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


--
-- Name: financial_journal_has_aggregate_evidence(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.financial_journal_has_aggregate_evidence(journal_entry_id_to_check bigint) RETURNS boolean
    LANGUAGE plpgsql STABLE
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


--
-- Name: financial_journal_line_exists(bigint, bigint, text, bigint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.financial_journal_line_exists(journal_entry_id_to_check bigint, ledger_account_id_to_check bigint, direction_to_check text, amount_cents_to_check bigint, currency_to_check text) RETURNS boolean
    LANGUAGE sql STABLE
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


--
-- Name: lock_refund_pix_payment_evidence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lock_refund_pix_payment_evidence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'INSERT' OR OLD.pix_payment_id IS NOT DISTINCT FROM NEW.pix_payment_id THEN
    PERFORM 1
    FROM pix_payments
    WHERE id = NEW.pix_payment_id
    FOR UPDATE;
    RETURN NEW;
  END IF;

  PERFORM 1
  FROM pix_payments
  WHERE id IN (OLD.pix_payment_id, NEW.pix_payment_id)
  ORDER BY id
  FOR UPDATE;

  RETURN NEW;
END;
$$;


--
-- Name: med_case_has_refund_evidence(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.med_case_has_refund_evidence(med_case_id_to_check bigint) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM med_cases med_case
    JOIN refunds refund
      ON refund.id = med_case.refund_id
    WHERE med_case.id = med_case_id_to_check
      AND refund.organization_id = med_case.organization_id
      AND refund.pix_payment_id = med_case.pix_payment_id
      AND refund.amount_cents = med_case.amount_cents
      AND refund.currency = med_case.currency
      AND refund.status = 'settled'
      AND refund.idempotency_key = 'med_case.refund:' || med_case.id::text
  );
$$;


--
-- Name: med_case_has_resolution_approval(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.med_case_has_resolution_approval(med_case_id_to_check bigint) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM med_cases med_case
    JOIN operator_approvals approval
      ON approval.id = med_case.operator_approval_id
    WHERE med_case.id = med_case_id_to_check
      AND approval.organization_id = med_case.organization_id
      AND approval.subject_type = 'MedCase'
      AND approval.subject_id = med_case.id
      AND approval.status = 'approved'
      AND (
        (med_case.status = 'rejected' AND approval.action = 'med_case.reject')
        OR (med_case.status = 'refunded' AND approval.action = 'med_case.accept')
      )
  );
$$;


--
-- Name: outbox_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.outbox_events (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    aggregate_type character varying NOT NULL,
    aggregate_id bigint NOT NULL,
    event_type character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    correlation_id character varying,
    idempotency_key character varying,
    attempts integer DEFAULT 0 NOT NULL,
    published_at timestamp(6) without time zone,
    last_error character varying,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    next_attempt_at timestamp(6) without time zone,
    last_attempted_at timestamp(6) without time zone,
    dead_lettered_at timestamp(6) without time zone,
    error_class character varying,
    publisher character varying,
    published_to character varying,
    publisher_message_id character varying,
    payload_sha256 character varying,
    CONSTRAINT outbox_events_delivery_state_check CHECK (((((status)::text = 'pending'::text) AND (published_at IS NULL) AND (dead_lettered_at IS NULL) AND (payload_sha256 IS NULL)) OR (((status)::text = 'publishing'::text) AND (last_attempted_at IS NOT NULL) AND (published_at IS NULL) AND (dead_lettered_at IS NULL) AND (payload_sha256 IS NULL)) OR (((status)::text = 'published'::text) AND (published_at IS NOT NULL) AND (payload_sha256 IS NOT NULL) AND (dead_lettered_at IS NULL)) OR (((status)::text = 'dead_lettered'::text) AND (published_at IS NULL) AND (payload_sha256 IS NULL) AND (dead_lettered_at IS NOT NULL) AND (error_class IS NOT NULL) AND (btrim((error_class)::text) <> ''::text) AND (last_error IS NOT NULL) AND (btrim((last_error)::text) <> ''::text)))),
    CONSTRAINT outbox_events_payload_sha256_hex_check CHECK (((payload_sha256 IS NULL) OR ((payload_sha256)::text ~ '^[0-9a-f]{64}$'::text))),
    CONSTRAINT outbox_events_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'publishing'::character varying, 'published'::character varying, 'dead_lettered'::character varying])::text[])))
);


--
-- Name: med_outbox_event_has_resolution_payload_evidence(public.outbox_events); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.med_outbox_event_has_resolution_payload_evidence(event_row public.outbox_events) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  has_evidence boolean;
BEGIN
  IF event_row.aggregate_type <> 'MedCase'
    OR event_row.event_type NOT IN ('med.case.rejected', 'med.case.refunded') THEN
    RETURN true;
  END IF;

  IF event_row.event_type = 'med.case.rejected' THEN
    SELECT EXISTS (
      SELECT 1
      FROM med_cases med_case
      JOIN pix_payments pix_payment
        ON pix_payment.id = med_case.pix_payment_id
      JOIN operator_approvals approval
        ON approval.id = med_case.operator_approval_id
      WHERE med_case.id = event_row.aggregate_id
        AND med_case.organization_id = event_row.organization_id
        AND med_case.status = 'rejected'
        AND med_case.refund_id IS NULL
        AND med_case_has_resolution_approval(med_case.id)
        AND event_row.payload ? 'resolved_at'
        AND event_row.payload @> jsonb_build_object(
          'med_case_id', med_case.public_id::text,
          'pix_payment_id', pix_payment.public_id::text,
          'operator_approval_id', approval.public_id::text,
          'amount_cents', med_case.amount_cents,
          'currency', med_case.currency,
          'status', med_case.status
        )
    ) INTO has_evidence;
    RETURN has_evidence;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM med_cases med_case
    JOIN pix_payments pix_payment
      ON pix_payment.id = med_case.pix_payment_id
    JOIN refunds refund
      ON refund.id = med_case.refund_id
    JOIN operator_approvals approval
      ON approval.id = med_case.operator_approval_id
    WHERE med_case.id = event_row.aggregate_id
      AND med_case.organization_id = event_row.organization_id
      AND med_case.status = 'refunded'
      AND med_case_has_resolution_approval(med_case.id)
      AND med_case_has_refund_evidence(med_case.id)
      AND event_row.payload ? 'resolved_at'
      AND event_row.payload @> jsonb_build_object(
        'med_case_id', med_case.public_id::text,
        'pix_payment_id', pix_payment.public_id::text,
        'refund_id', refund.public_id::text,
        'operator_approval_id', approval.public_id::text,
        'amount_cents', med_case.amount_cents,
        'currency', med_case.currency,
        'status', med_case.status
      )
  ) INTO has_evidence;
  RETURN has_evidence;
END;
$$;


--
-- Name: outbox_event_expected_command_identity(public.outbox_events); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.outbox_event_expected_command_identity(event_row public.outbox_events) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  expected_key text;
BEGIN
  IF event_row.aggregate_type = 'Funding' THEN
    SELECT funding.idempotency_key
      INTO expected_key
      FROM fundings funding
     WHERE funding.id = event_row.aggregate_id
       AND funding.organization_id = event_row.organization_id
       AND event_row.event_type = 'wallet.funded';
    RETURN expected_key;
  END IF;

  IF event_row.aggregate_type = 'Transfer' THEN
    SELECT transfer.idempotency_key
      INTO expected_key
      FROM transfers transfer
     WHERE transfer.id = event_row.aggregate_id
       AND transfer.organization_id = event_row.organization_id
       AND event_row.event_type = 'wallet.transfer.posted';
    RETURN expected_key;
  END IF;

  IF event_row.aggregate_type = 'SplitPayment' THEN
    SELECT split_payment.idempotency_key
      INTO expected_key
      FROM split_payments split_payment
     WHERE split_payment.id = event_row.aggregate_id
       AND split_payment.organization_id = event_row.organization_id
       AND event_row.event_type = 'split.posted';
    RETURN expected_key;
  END IF;

  IF event_row.aggregate_type = 'PixPayment' THEN
    SELECT CASE
             WHEN event_row.event_type IN ('pix.payment.approved', 'pix.payment.pending_review', 'pix.payment.rejected')
               THEN pix_payment.idempotency_key
             WHEN event_row.event_type = 'pix.payment.settled'
               THEN 'pix_payment.settle:' || pix_payment.id::text
             WHEN event_row.event_type = 'pix.payment.reversed'
               THEN 'pix_payment.reverse:' || pix_payment.id::text
           END
      INTO expected_key
      FROM pix_payments pix_payment
     WHERE pix_payment.id = event_row.aggregate_id
       AND pix_payment.organization_id = event_row.organization_id;
    RETURN expected_key;
  END IF;

  IF event_row.aggregate_type = 'Payout' THEN
    SELECT CASE
             WHEN event_row.event_type = 'payout.scheduled'
               THEN payout.idempotency_key
             WHEN event_row.event_type = 'payout.settled'
               THEN 'payout.settle:' || payout.id::text
           END
      INTO expected_key
      FROM payouts payout
     WHERE payout.id = event_row.aggregate_id
       AND payout.organization_id = event_row.organization_id;
    RETURN expected_key;
  END IF;

  IF event_row.aggregate_type = 'Refund' THEN
    SELECT refund.idempotency_key
      INTO expected_key
      FROM refunds refund
     WHERE refund.id = event_row.aggregate_id
       AND refund.organization_id = event_row.organization_id
       AND event_row.event_type = 'refund.settled';
    RETURN expected_key;
  END IF;

  IF event_row.aggregate_type = 'MedCase' THEN
    SELECT CASE
             WHEN event_row.event_type = 'med.case.opened'
               THEN med_case.idempotency_key
             WHEN event_row.event_type = 'med.case.rejected'
               THEN 'med_case.reject:' || med_case.id::text
             WHEN event_row.event_type = 'med.case.refunded'
               THEN 'med_case.accept:' || med_case.id::text
           END
      INTO expected_key
      FROM med_cases med_case
     WHERE med_case.id = event_row.aggregate_id
       AND med_case.organization_id = event_row.organization_id;
    RETURN expected_key;
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: outbox_event_has_aggregate_evidence(public.outbox_events); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.outbox_event_has_aggregate_evidence(event_row public.outbox_events) RETURNS boolean
    LANGUAGE plpgsql STABLE
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


--
-- Name: outbox_event_has_command_identity_evidence(public.outbox_events); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.outbox_event_has_command_identity_evidence(event_row public.outbox_events) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  has_evidence boolean;
BEGIN
  IF event_row.aggregate_type = 'Funding' THEN
    SELECT EXISTS (
      SELECT 1
      FROM fundings funding
      WHERE funding.id = event_row.aggregate_id
        AND funding.organization_id = event_row.organization_id
        AND event_row.event_type = 'wallet.funded'
        AND funding.journal_entry_id IS NOT NULL
        AND event_row.idempotency_key = funding.idempotency_key
    ) INTO has_evidence;
    RETURN has_evidence;
  END IF;

  IF event_row.aggregate_type = 'Transfer' THEN
    SELECT EXISTS (
      SELECT 1
      FROM transfers transfer
      WHERE transfer.id = event_row.aggregate_id
        AND transfer.organization_id = event_row.organization_id
        AND event_row.event_type = 'wallet.transfer.posted'
        AND transfer.journal_entry_id IS NOT NULL
        AND event_row.idempotency_key = transfer.idempotency_key
    ) INTO has_evidence;
    RETURN has_evidence;
  END IF;

  IF event_row.aggregate_type = 'SplitPayment' THEN
    SELECT EXISTS (
      SELECT 1
      FROM split_payments split_payment
      WHERE split_payment.id = event_row.aggregate_id
        AND split_payment.organization_id = event_row.organization_id
        AND event_row.event_type = 'split.posted'
        AND split_payment.journal_entry_id IS NOT NULL
        AND event_row.idempotency_key = split_payment.idempotency_key
    ) INTO has_evidence;
    RETURN has_evidence;
  END IF;

  IF event_row.aggregate_type = 'PixPayment' THEN
    SELECT EXISTS (
      SELECT 1
      FROM pix_payments pix_payment
      WHERE pix_payment.id = event_row.aggregate_id
        AND pix_payment.organization_id = event_row.organization_id
        AND (
          (
            event_row.event_type IN ('pix.payment.approved', 'pix.payment.pending_review')
            AND event_row.idempotency_key = pix_payment.idempotency_key
          )
          OR (
            event_row.event_type = 'pix.payment.rejected'
            AND event_row.idempotency_key IN (
              pix_payment.idempotency_key,
              'pix_payment.reject:' || pix_payment.id::text
            )
          )
          OR (
            event_row.event_type = 'pix.payment.settled'
            AND pix_payment.settlement_journal_entry_id IS NOT NULL
            AND event_row.idempotency_key = 'pix_payment.settle:' || pix_payment.id::text
          )
          OR (
            event_row.event_type = 'pix.payment.reversed'
            AND pix_payment.reversal_journal_entry_id IS NOT NULL
            AND event_row.idempotency_key = 'pix_payment.reverse:' || pix_payment.id::text
          )
        )
    ) INTO has_evidence;
    RETURN has_evidence;
  END IF;

  IF event_row.aggregate_type = 'Payout' THEN
    SELECT EXISTS (
      SELECT 1
      FROM payouts payout
      WHERE payout.id = event_row.aggregate_id
        AND payout.organization_id = event_row.organization_id
        AND (
          (
            event_row.event_type = 'payout.scheduled'
            AND payout.journal_entry_id IS NOT NULL
            AND event_row.idempotency_key = payout.idempotency_key
          )
          OR (
            event_row.event_type = 'payout.settled'
            AND payout.settlement_journal_entry_id IS NOT NULL
            AND payout.settled_at IS NOT NULL
            AND event_row.idempotency_key = 'payout.settle:' || payout.id::text
          )
        )
    ) INTO has_evidence;
    RETURN has_evidence;
  END IF;

  IF event_row.aggregate_type = 'Refund' THEN
    SELECT EXISTS (
      SELECT 1
      FROM refunds refund
      WHERE refund.id = event_row.aggregate_id
        AND refund.organization_id = event_row.organization_id
        AND event_row.event_type = 'refund.settled'
        AND refund.journal_entry_id IS NOT NULL
        AND event_row.idempotency_key = refund.idempotency_key
    ) INTO has_evidence;
    RETURN has_evidence;
  END IF;

  IF event_row.aggregate_type = 'MedCase' THEN
    SELECT EXISTS (
      SELECT 1
      FROM med_cases med_case
      WHERE med_case.id = event_row.aggregate_id
        AND med_case.organization_id = event_row.organization_id
        AND (
          (
            event_row.event_type = 'med.case.opened'
            AND event_row.idempotency_key = med_case.idempotency_key
          )
          OR (
            event_row.event_type = 'med.case.rejected'
            AND med_case.status = 'rejected'
            AND med_case_has_resolution_approval(med_case.id)
            AND event_row.idempotency_key = 'med_case.reject:' || med_case.id::text
          )
          OR (
            event_row.event_type = 'med.case.refunded'
            AND med_case.status = 'refunded'
            AND med_case_has_resolution_approval(med_case.id)
            AND med_case_has_refund_evidence(med_case.id)
            AND event_row.idempotency_key = 'med_case.accept:' || med_case.id::text
          )
        )
    ) INTO has_evidence;
    RETURN has_evidence;
  END IF;

  RETURN true;
END;
$$;


--
-- Name: outbox_legacy_command_identity_exceptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.outbox_legacy_command_identity_exceptions (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    outbox_event_id bigint NOT NULL,
    aggregate_type character varying NOT NULL,
    aggregate_id bigint NOT NULL,
    event_type character varying NOT NULL,
    payload_sha256 character varying NOT NULL,
    expected_idempotency_key character varying NOT NULL,
    reason character varying NOT NULL,
    accepted_at timestamp(6) without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT legacy_outbox_exceptions_expected_key_present_check CHECK ((btrim((expected_idempotency_key)::text) <> ''::text)),
    CONSTRAINT legacy_outbox_exceptions_payload_sha256_hex_check CHECK (((payload_sha256)::text ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT legacy_outbox_exceptions_reason_present_check CHECK ((btrim((reason)::text) <> ''::text))
);


--
-- Name: outbox_legacy_command_identity_exception_valid(public.outbox_legacy_command_identity_exceptions); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.outbox_legacy_command_identity_exception_valid(exception_row public.outbox_legacy_command_identity_exceptions) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  event_row outbox_events%ROWTYPE;
  expected_key text;
BEGIN
  SELECT *
    INTO event_row
    FROM outbox_events
   WHERE id = exception_row.outbox_event_id;

  IF event_row.id IS NULL THEN
    RETURN false;
  END IF;

  expected_key := outbox_event_expected_command_identity(event_row);

  RETURN event_row.organization_id = exception_row.organization_id
    AND event_row.aggregate_type = exception_row.aggregate_type
    AND event_row.aggregate_id = exception_row.aggregate_id
    AND event_row.event_type = exception_row.event_type
    AND event_row.status = 'published'
    AND event_row.published_at IS NOT NULL
    AND event_row.payload_sha256 IS NOT NULL
    AND event_row.payload_sha256 = exception_row.payload_sha256
    AND event_row.idempotency_key IS NULL
    AND expected_key IS NOT NULL
    AND expected_key = exception_row.expected_idempotency_key
    AND btrim(exception_row.reason) <> ''
    AND outbox_event_has_aggregate_evidence(event_row)
    AND NOT outbox_event_has_command_identity_evidence(event_row);
END;
$$;


--
-- Name: payout_has_early_settlement_approval(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payout_has_early_settlement_approval(payout_id_to_check bigint) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM payouts payout
    JOIN operator_approvals approval
      ON approval.id = payout.operator_approval_id
    WHERE payout.id = payout_id_to_check
      AND approval.organization_id = payout.organization_id
      AND approval.subject_type = 'Payout'
      AND approval.subject_id = payout.id
      AND approval.action = 'payout.settle_early'
      AND approval.status = 'approved'
      AND approval.approved_by_id IS NOT NULL
      AND approval.approved_at IS NOT NULL
      AND approval.approved_by_id <> approval.requested_by_id
  );
$$;


--
-- Name: prevent_audit_log_anchor_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_audit_log_anchor_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'audit log anchors are append-only and cannot be mutated'
    USING ERRCODE = 'integrity_constraint_violation';
END;
$$;


--
-- Name: prevent_audit_log_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_audit_log_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'audit logs are append-only and cannot be mutated'
    USING ERRCODE = 'integrity_constraint_violation';
END;
$$;


--
-- Name: prevent_balance_snapshot_evidence_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_balance_snapshot_evidence_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  wallet_row wallets%ROWTYPE;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'balance snapshots are append-only evidence';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'balance snapshots are immutable evidence';
  END IF;

  SELECT * INTO wallet_row
  FROM wallets
  WHERE id = NEW.wallet_id;

  IF wallet_row.id IS NULL THEN
    RAISE EXCEPTION 'balance snapshot must reference an existing wallet';
  END IF;

  IF wallet_row.organization_id <> NEW.organization_id THEN
    RAISE EXCEPTION 'balance snapshot organization must match wallet organization';
  END IF;

  IF wallet_row.currency <> NEW.currency THEN
    RAISE EXCEPTION 'balance snapshot currency must match wallet currency';
  END IF;

  IF NEW.difference_cents <> NEW.available_cents - NEW.ledger_available_cents THEN
    RAISE EXCEPTION 'balance snapshot difference must match projection minus ledger';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: prevent_funding_evidence_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_funding_evidence_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.journal_entry_id IS NOT NULL OR financial_aggregate_has_outbox_evidence('Funding', OLD.id) THEN
      RAISE EXCEPTION 'funding with ledger or outbox evidence is immutable';
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
    OR OLD.public_id IS DISTINCT FROM NEW.public_id
    OR OLD.wallet_id IS DISTINCT FROM NEW.wallet_id
    OR OLD.external_id IS DISTINCT FROM NEW.external_id
    OR OLD.amount_cents IS DISTINCT FROM NEW.amount_cents
    OR OLD.currency IS DISTINCT FROM NEW.currency
    OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
    OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'funding identity and value are immutable';
  END IF;

  IF (OLD.journal_entry_id IS NOT NULL OR financial_aggregate_has_outbox_evidence('Funding', OLD.id))
    AND (
      OLD.journal_entry_id IS DISTINCT FROM NEW.journal_entry_id
      OR OLD.status IS DISTINCT FROM NEW.status
      OR OLD.failure_code IS DISTINCT FROM NEW.failure_code
      OR OLD.metadata IS DISTINCT FROM NEW.metadata
      OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
    ) THEN
    RAISE EXCEPTION 'funding with ledger or outbox evidence is immutable';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: prevent_idempotency_key_evidence_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_idempotency_key_evidence_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'processing' THEN
      RAISE EXCEPTION 'idempotency records must start processing';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF OLD.status = 'succeeded' THEN
      RAISE EXCEPTION 'succeeded idempotency records are replay evidence';
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
    OR OLD.public_id IS DISTINCT FROM NEW.public_id
    OR OLD.key IS DISTINCT FROM NEW.key
    OR OLD.request_method IS DISTINCT FROM NEW.request_method
    OR OLD.request_path IS DISTINCT FROM NEW.request_path
    OR OLD.request_hash IS DISTINCT FROM NEW.request_hash
    OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'idempotency command identity is immutable';
  END IF;

  IF OLD.status = 'succeeded' THEN
    RAISE EXCEPTION 'succeeded idempotency records are immutable replay evidence';
  END IF;

  IF NEW.status = 'succeeded' AND OLD.status <> 'processing' THEN
    RAISE EXCEPTION 'idempotency records can only succeed from processing';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: prevent_ledger_record_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_ledger_record_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'ledger records are append-only';
END;
$$;


--
-- Name: prevent_med_case_evidence_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_med_case_evidence_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  has_evidence boolean;
  allowed_transition boolean;
BEGIN
  has_evidence := OLD.refund_id IS NOT NULL
    OR OLD.resolved_at IS NOT NULL
    OR OLD.operator_approval_id IS NOT NULL
    OR financial_aggregate_has_outbox_evidence('MedCase', OLD.id);

  IF TG_OP = 'DELETE' THEN
    IF has_evidence THEN
      RAISE EXCEPTION 'MED case with resolution or outbox evidence cannot be deleted';
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
    OR OLD.public_id IS DISTINCT FROM NEW.public_id
    OR OLD.pix_payment_id IS DISTINCT FROM NEW.pix_payment_id
    OR OLD.external_id IS DISTINCT FROM NEW.external_id
    OR OLD.amount_cents IS DISTINCT FROM NEW.amount_cents
    OR OLD.currency IS DISTINCT FROM NEW.currency
    OR OLD.reason IS DISTINCT FROM NEW.reason
    OR OLD.opened_at IS DISTINCT FROM NEW.opened_at
    OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
    OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'MED case identity and value are immutable';
  END IF;

  allowed_transition := OLD.status = 'opened' AND (
    (
      NEW.status = 'refunded'
      AND OLD.refund_id IS NULL
      AND NEW.refund_id IS NOT NULL
      AND OLD.resolved_at IS NULL
      AND NEW.resolved_at IS NOT NULL
      AND OLD.operator_approval_id IS NULL
      AND NEW.operator_approval_id IS NOT NULL
      AND OLD.metadata IS NOT DISTINCT FROM NEW.metadata
    )
    OR (
      NEW.status = 'rejected'
      AND OLD.refund_id IS NOT DISTINCT FROM NEW.refund_id
      AND OLD.resolved_at IS NULL
      AND NEW.resolved_at IS NOT NULL
      AND OLD.operator_approval_id IS NULL
      AND NEW.operator_approval_id IS NOT NULL
    )
  );

  IF has_evidence
    AND NOT allowed_transition
    AND (
      OLD.status IS DISTINCT FROM NEW.status
      OR OLD.refund_id IS DISTINCT FROM NEW.refund_id
      OR OLD.resolved_at IS DISTINCT FROM NEW.resolved_at
      OR OLD.operator_approval_id IS DISTINCT FROM NEW.operator_approval_id
      OR OLD.metadata IS DISTINCT FROM NEW.metadata
      OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
    ) THEN
    RAISE EXCEPTION 'MED case with outbox evidence only allows documented approval-backed resolution transitions';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: prevent_operator_approval_evidence_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_operator_approval_evidence_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'operator approvals are governance evidence';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'pending'
      OR NEW.approved_by_id IS NOT NULL
      OR NEW.approved_at IS NOT NULL THEN
      RAISE EXCEPTION 'operator approvals must start pending';
    END IF;

    RETURN NEW;
  END IF;

  IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
    OR OLD.public_id IS DISTINCT FROM NEW.public_id
    OR OLD.action IS DISTINCT FROM NEW.action
    OR OLD.subject_type IS DISTINCT FROM NEW.subject_type
    OR OLD.subject_id IS DISTINCT FROM NEW.subject_id
    OR OLD.requested_by_id IS DISTINCT FROM NEW.requested_by_id
    OR OLD.reason IS DISTINCT FROM NEW.reason
    OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
    OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'operator approval identity is immutable';
  END IF;

  IF OLD.status IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'terminal operator approvals are immutable governance evidence';
  END IF;

  IF OLD.status <> 'pending' OR NEW.status NOT IN ('pending', 'approved', 'rejected') THEN
    RAISE EXCEPTION 'invalid operator approval state transition';
  END IF;

  IF NEW.status = 'pending'
    AND (OLD.approved_by_id IS DISTINCT FROM NEW.approved_by_id OR OLD.approved_at IS DISTINCT FROM NEW.approved_at) THEN
    RAISE EXCEPTION 'pending operator approvals cannot carry checker evidence';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: prevent_outbox_event_evidence_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_outbox_event_evidence_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'pending'
      OR NEW.attempts <> 0
      OR NEW.published_at IS NOT NULL
      OR NEW.last_error IS NOT NULL
      OR NEW.next_attempt_at IS NOT NULL
      OR NEW.last_attempted_at IS NOT NULL
      OR NEW.dead_lettered_at IS NOT NULL
      OR NEW.error_class IS NOT NULL
      OR NEW.publisher IS NOT NULL
      OR NEW.published_to IS NOT NULL
      OR NEW.publisher_message_id IS NOT NULL
      OR NEW.payload_sha256 IS NOT NULL THEN
      RAISE EXCEPTION 'outbox events must start as pending unpublished evidence';
    END IF;

    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'outbox events are append-only evidence';
  END IF;

  IF OLD.status = 'published' THEN
    RAISE EXCEPTION 'published outbox events are immutable delivery evidence';
  END IF;

  IF OLD.public_id IS DISTINCT FROM NEW.public_id
    OR OLD.organization_id IS DISTINCT FROM NEW.organization_id
    OR OLD.aggregate_type IS DISTINCT FROM NEW.aggregate_type
    OR OLD.aggregate_id IS DISTINCT FROM NEW.aggregate_id
    OR OLD.event_type IS DISTINCT FROM NEW.event_type
    OR OLD.payload IS DISTINCT FROM NEW.payload
    OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
    OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'outbox event envelope is immutable';
  END IF;

  IF OLD.payload_sha256 IS NOT NULL
    AND OLD.payload_sha256 IS DISTINCT FROM NEW.payload_sha256 THEN
    RAISE EXCEPTION 'outbox event payload hash is immutable after publication';
  END IF;

  IF OLD.payload_sha256 IS NULL
    AND NEW.payload_sha256 IS NOT NULL
    AND NOT (OLD.status = 'publishing' AND NEW.status = 'published') THEN
    RAISE EXCEPTION 'outbox event payload hash can only be set during publication';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: prevent_outbox_legacy_command_identity_exception_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_outbox_legacy_command_identity_exception_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'legacy outbox command identity exceptions are append-only evidence';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'legacy outbox command identity exceptions are immutable evidence';
  END IF;

  IF NOT outbox_legacy_command_identity_exception_valid(NEW) THEN
    RAISE EXCEPTION 'legacy outbox command identity exception evidence is invalid';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: prevent_payout_evidence_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_payout_evidence_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  has_evidence boolean;
  allowed_transition boolean;
BEGIN
  has_evidence := OLD.journal_entry_id IS NOT NULL
    OR OLD.settlement_journal_entry_id IS NOT NULL
    OR financial_aggregate_has_outbox_evidence('Payout', OLD.id);

  IF TG_OP = 'DELETE' THEN
    IF has_evidence THEN
      RAISE EXCEPTION 'payout with ledger or outbox evidence cannot be deleted';
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
    OR OLD.public_id IS DISTINCT FROM NEW.public_id
    OR OLD.wallet_id IS DISTINCT FROM NEW.wallet_id
    OR OLD.external_id IS DISTINCT FROM NEW.external_id
    OR OLD.amount_cents IS DISTINCT FROM NEW.amount_cents
    OR OLD.currency IS DISTINCT FROM NEW.currency
    OR OLD.settlement_delay_days IS DISTINCT FROM NEW.settlement_delay_days
    OR OLD.settlement_due_on IS DISTINCT FROM NEW.settlement_due_on
    OR OLD.destination_kind IS DISTINCT FROM NEW.destination_kind
    OR OLD.destination_reference IS DISTINCT FROM NEW.destination_reference
    OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
    OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'payout identity and value are immutable';
  END IF;

  IF OLD.journal_entry_id IS NOT NULL AND OLD.journal_entry_id IS DISTINCT FROM NEW.journal_entry_id THEN
    RAISE EXCEPTION 'payout schedule journal evidence is immutable';
  END IF;

  allowed_transition := OLD.status = 'scheduled' AND (
    (
      NEW.status = 'settled'
      AND OLD.settlement_journal_entry_id IS NULL
      AND NEW.settlement_journal_entry_id IS NOT NULL
      AND OLD.settled_at IS NULL
      AND NEW.settled_at IS NOT NULL
      AND (
        (NEW.settled_at::date >= NEW.settlement_due_on AND NEW.operator_approval_id IS NULL)
        OR (NEW.settled_at::date < NEW.settlement_due_on AND OLD.operator_approval_id IS NULL AND NEW.operator_approval_id IS NOT NULL)
      )
      AND OLD.failure_code IS NOT DISTINCT FROM NEW.failure_code
      AND OLD.metadata IS NOT DISTINCT FROM NEW.metadata
    )
    OR (
      NEW.status = 'failed'
      AND OLD.settlement_journal_entry_id IS NOT DISTINCT FROM NEW.settlement_journal_entry_id
      AND OLD.settled_at IS NOT DISTINCT FROM NEW.settled_at
      AND OLD.operator_approval_id IS NOT DISTINCT FROM NEW.operator_approval_id
      AND OLD.failure_code IS NULL
      AND NEW.failure_code IS NOT NULL
      AND OLD.metadata IS NOT DISTINCT FROM NEW.metadata
    )
  );

  IF has_evidence
    AND NOT allowed_transition
    AND (
      OLD.status IS DISTINCT FROM NEW.status
      OR OLD.settlement_journal_entry_id IS DISTINCT FROM NEW.settlement_journal_entry_id
      OR OLD.settled_at IS DISTINCT FROM NEW.settled_at
      OR OLD.operator_approval_id IS DISTINCT FROM NEW.operator_approval_id
      OR OLD.failure_code IS DISTINCT FROM NEW.failure_code
      OR OLD.metadata IS DISTINCT FROM NEW.metadata
      OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
    ) THEN
    RAISE EXCEPTION 'payout with ledger or outbox evidence only allows documented lifecycle transitions';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: prevent_pix_payment_evidence_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_pix_payment_evidence_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  has_evidence boolean;
  allowed_transition boolean;
BEGIN
  has_evidence := OLD.journal_entry_id IS NOT NULL
    OR OLD.settlement_journal_entry_id IS NOT NULL
    OR OLD.reversal_journal_entry_id IS NOT NULL
    OR financial_aggregate_has_outbox_evidence('PixPayment', OLD.id);

  IF TG_OP = 'DELETE' THEN
    IF has_evidence THEN
      RAISE EXCEPTION 'Pix payment with ledger or outbox evidence cannot be deleted';
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
    OR OLD.public_id IS DISTINCT FROM NEW.public_id
    OR OLD.wallet_id IS DISTINCT FROM NEW.wallet_id
    OR OLD.external_id IS DISTINCT FROM NEW.external_id
    OR OLD.pix_key IS DISTINCT FROM NEW.pix_key
    OR OLD.receiver_name IS DISTINCT FROM NEW.receiver_name
    OR OLD.amount_cents IS DISTINCT FROM NEW.amount_cents
    OR OLD.currency IS DISTINCT FROM NEW.currency
    OR OLD.risk_score IS DISTINCT FROM NEW.risk_score
    OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
    OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'Pix payment identity and value are immutable';
  END IF;

  IF OLD.journal_entry_id IS NOT NULL AND OLD.journal_entry_id IS DISTINCT FROM NEW.journal_entry_id THEN
    RAISE EXCEPTION 'Pix approval journal evidence is immutable';
  END IF;

  allowed_transition := (
    OLD.status = 'approved'
    AND NEW.status = 'settled'
    AND OLD.settlement_journal_entry_id IS NULL
    AND NEW.settlement_journal_entry_id IS NOT NULL
    AND OLD.reversal_journal_entry_id IS NOT DISTINCT FROM NEW.reversal_journal_entry_id
    AND OLD.reversed_at IS NOT DISTINCT FROM NEW.reversed_at
    AND OLD.reversal_reason IS NOT DISTINCT FROM NEW.reversal_reason
    AND OLD.failure_code IS NOT DISTINCT FROM NEW.failure_code
    AND OLD.metadata IS NOT DISTINCT FROM NEW.metadata
  ) OR (
    OLD.status = 'settled'
    AND NEW.status = 'reversed'
    AND OLD.reversal_journal_entry_id IS NULL
    AND NEW.reversal_journal_entry_id IS NOT NULL
    AND OLD.reversed_at IS NULL
    AND NEW.reversed_at IS NOT NULL
    AND OLD.reversal_reason IS NULL
    AND NEW.reversal_reason IS NOT NULL
    AND OLD.failure_code IS NOT DISTINCT FROM NEW.failure_code
  ) OR (
    OLD.status = 'pending_review'
    AND NEW.status = 'rejected'
    AND OLD.journal_entry_id IS NOT DISTINCT FROM NEW.journal_entry_id
    AND OLD.settlement_journal_entry_id IS NOT DISTINCT FROM NEW.settlement_journal_entry_id
    AND OLD.reversal_journal_entry_id IS NOT DISTINCT FROM NEW.reversal_journal_entry_id
    AND OLD.reversed_at IS NOT DISTINCT FROM NEW.reversed_at
    AND OLD.reversal_reason IS NOT DISTINCT FROM NEW.reversal_reason
    AND OLD.failure_code IS NULL
    AND NEW.failure_code IS NOT NULL
  );

  IF has_evidence
    AND NOT allowed_transition
    AND (
      OLD.status IS DISTINCT FROM NEW.status
      OR OLD.settlement_journal_entry_id IS DISTINCT FROM NEW.settlement_journal_entry_id
      OR OLD.reversal_journal_entry_id IS DISTINCT FROM NEW.reversal_journal_entry_id
      OR OLD.reversed_at IS DISTINCT FROM NEW.reversed_at
      OR OLD.reversal_reason IS DISTINCT FROM NEW.reversal_reason
      OR OLD.failure_code IS DISTINCT FROM NEW.failure_code
      OR OLD.metadata IS DISTINCT FROM NEW.metadata
      OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
    ) THEN
    RAISE EXCEPTION 'Pix payment with ledger or outbox evidence only allows documented lifecycle transitions';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: prevent_processed_event_evidence_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_processed_event_evidence_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'processed events are downstream processing evidence';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'processing' THEN
      RAISE EXCEPTION 'processed events must start processing';
    END IF;

    PERFORM assert_processed_event_outbox_evidence(NEW);
    RETURN NEW;
  END IF;

  IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
    OR OLD.public_id IS DISTINCT FROM NEW.public_id
    OR OLD.outbox_event_id IS DISTINCT FROM NEW.outbox_event_id
    OR OLD.processor IS DISTINCT FROM NEW.processor
    OR OLD.event_id IS DISTINCT FROM NEW.event_id
    OR OLD.event_type IS DISTINCT FROM NEW.event_type
    OR OLD.payload_sha256 IS DISTINCT FROM NEW.payload_sha256
    OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'processed event identity is immutable';
  END IF;

  IF OLD.status = 'processed' THEN
    RAISE EXCEPTION 'processed events are immutable after success';
  END IF;

  IF NEW.status = 'processed' AND OLD.status NOT IN ('processing', 'failed') THEN
    RAISE EXCEPTION 'processed events can only succeed from processing or failed';
  END IF;

  PERFORM assert_processed_event_outbox_evidence(NEW);
  RETURN NEW;
END;
$$;


--
-- Name: prevent_reconciliation_row_evidence_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_reconciliation_row_evidence_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  run_id_to_check bigint;
BEGIN
  run_id_to_check := COALESCE(NEW.reconciliation_run_id, OLD.reconciliation_run_id);

  IF reconciliation_run_has_outbox_evidence(run_id_to_check) THEN
    RAISE EXCEPTION 'reconciliation rows with outbox evidence are immutable';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;


--
-- Name: prevent_reconciliation_run_evidence_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_reconciliation_run_evidence_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF reconciliation_run_has_outbox_evidence(OLD.id) THEN
      RAISE EXCEPTION 'reconciliation runs with outbox evidence are immutable';
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
    OR OLD.public_id IS DISTINCT FROM NEW.public_id
    OR OLD.provider IS DISTINCT FROM NEW.provider
    OR OLD.statement_date IS DISTINCT FROM NEW.statement_date
    OR OLD.provider_balance_cents IS DISTINCT FROM NEW.provider_balance_cents
    OR OLD.ledger_balance_cents IS DISTINCT FROM NEW.ledger_balance_cents
    OR OLD.discrepancy_cents IS DISTINCT FROM NEW.discrepancy_cents
    OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
    OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'reconciliation run identity and balances are immutable';
  END IF;

  IF reconciliation_run_has_outbox_evidence(OLD.id) THEN
    RAISE EXCEPTION 'reconciliation runs with outbox evidence are immutable';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: prevent_refund_evidence_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_refund_evidence_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.journal_entry_id IS NOT NULL OR financial_aggregate_has_outbox_evidence('Refund', OLD.id) THEN
      RAISE EXCEPTION 'refund with ledger or outbox evidence is immutable';
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
    OR OLD.public_id IS DISTINCT FROM NEW.public_id
    OR OLD.wallet_id IS DISTINCT FROM NEW.wallet_id
    OR OLD.pix_payment_id IS DISTINCT FROM NEW.pix_payment_id
    OR OLD.external_id IS DISTINCT FROM NEW.external_id
    OR OLD.amount_cents IS DISTINCT FROM NEW.amount_cents
    OR OLD.currency IS DISTINCT FROM NEW.currency
    OR OLD.reason IS DISTINCT FROM NEW.reason
    OR OLD.settled_at IS DISTINCT FROM NEW.settled_at
    OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
    OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'refund identity and value are immutable';
  END IF;

  IF (OLD.journal_entry_id IS NOT NULL OR financial_aggregate_has_outbox_evidence('Refund', OLD.id))
    AND (
      OLD.journal_entry_id IS DISTINCT FROM NEW.journal_entry_id
      OR OLD.status IS DISTINCT FROM NEW.status
      OR OLD.failure_code IS DISTINCT FROM NEW.failure_code
      OR OLD.metadata IS DISTINCT FROM NEW.metadata
      OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
    ) THEN
    RAISE EXCEPTION 'refund with ledger or outbox evidence is immutable';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: prevent_split_entry_evidence_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_split_entry_evidence_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  parent_has_evidence boolean;
BEGIN
  IF TG_OP = 'DELETE' THEN
    SELECT split_payments.journal_entry_id IS NOT NULL
        OR financial_aggregate_has_outbox_evidence('SplitPayment', split_payments.id)
    INTO parent_has_evidence
    FROM split_payments
    WHERE split_payments.id = OLD.split_payment_id;

    IF parent_has_evidence THEN
      RAISE EXCEPTION 'split entry with parent ledger or outbox evidence is immutable';
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
    OR OLD.public_id IS DISTINCT FROM NEW.public_id
    OR OLD.split_payment_id IS DISTINCT FROM NEW.split_payment_id
    OR OLD.destination_wallet_id IS DISTINCT FROM NEW.destination_wallet_id
    OR OLD.amount_cents IS DISTINCT FROM NEW.amount_cents
    OR OLD.currency IS DISTINCT FROM NEW.currency
    OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'split entry identity and value are immutable';
  END IF;

  SELECT split_payments.journal_entry_id IS NOT NULL
      OR financial_aggregate_has_outbox_evidence('SplitPayment', split_payments.id)
  INTO parent_has_evidence
  FROM split_payments
  WHERE split_payments.id = OLD.split_payment_id;

  IF parent_has_evidence
    AND (
      OLD.metadata IS DISTINCT FROM NEW.metadata
      OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
    ) THEN
    RAISE EXCEPTION 'split entry with parent ledger or outbox evidence is immutable';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: prevent_split_payment_evidence_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_split_payment_evidence_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.journal_entry_id IS NOT NULL OR financial_aggregate_has_outbox_evidence('SplitPayment', OLD.id) THEN
      RAISE EXCEPTION 'split payment with ledger or outbox evidence is immutable';
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
    OR OLD.public_id IS DISTINCT FROM NEW.public_id
    OR OLD.source_wallet_id IS DISTINCT FROM NEW.source_wallet_id
    OR OLD.external_id IS DISTINCT FROM NEW.external_id
    OR OLD.total_amount_cents IS DISTINCT FROM NEW.total_amount_cents
    OR OLD.currency IS DISTINCT FROM NEW.currency
    OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
    OR OLD.memo IS DISTINCT FROM NEW.memo
    OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'split payment identity and value are immutable';
  END IF;

  IF (OLD.journal_entry_id IS NOT NULL OR financial_aggregate_has_outbox_evidence('SplitPayment', OLD.id))
    AND (
      OLD.journal_entry_id IS DISTINCT FROM NEW.journal_entry_id
      OR OLD.status IS DISTINCT FROM NEW.status
      OR OLD.failure_code IS DISTINCT FROM NEW.failure_code
      OR OLD.metadata IS DISTINCT FROM NEW.metadata
      OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
    ) THEN
    RAISE EXCEPTION 'split payment with ledger or outbox evidence is immutable';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: prevent_transfer_evidence_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_transfer_evidence_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.journal_entry_id IS NOT NULL OR financial_aggregate_has_outbox_evidence('Transfer', OLD.id) THEN
      RAISE EXCEPTION 'transfer with ledger or outbox evidence is immutable';
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
    OR OLD.public_id IS DISTINCT FROM NEW.public_id
    OR OLD.source_wallet_id IS DISTINCT FROM NEW.source_wallet_id
    OR OLD.destination_wallet_id IS DISTINCT FROM NEW.destination_wallet_id
    OR OLD.external_id IS DISTINCT FROM NEW.external_id
    OR OLD.amount_cents IS DISTINCT FROM NEW.amount_cents
    OR OLD.currency IS DISTINCT FROM NEW.currency
    OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
    OR OLD.memo IS DISTINCT FROM NEW.memo
    OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'transfer identity and value are immutable';
  END IF;

  IF (OLD.journal_entry_id IS NOT NULL OR financial_aggregate_has_outbox_evidence('Transfer', OLD.id))
    AND (
      OLD.journal_entry_id IS DISTINCT FROM NEW.journal_entry_id
      OR OLD.status IS DISTINCT FROM NEW.status
      OR OLD.failure_code IS DISTINCT FROM NEW.failure_code
      OR OLD.metadata IS DISTINCT FROM NEW.metadata
      OR OLD.updated_at IS DISTINCT FROM NEW.updated_at
    ) THEN
    RAISE EXCEPTION 'transfer with ledger or outbox evidence is immutable';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: reconciliation_run_has_outbox_evidence(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reconciliation_run_has_outbox_evidence(run_id_to_check bigint) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM outbox_events
    WHERE aggregate_type = 'ReconciliationRun'
      AND aggregate_id = run_id_to_check
      AND event_type IN ('reconciliation.matched', 'reconciliation.discrepant')
  );
$$;


--
-- Name: refund_pix_payment_evidence_valid(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refund_pix_payment_evidence_valid(pix_payment_id_to_check bigint) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM pix_payments pix_payment
    WHERE pix_payment.id = pix_payment_id_to_check
      AND COALESCE((
        SELECT SUM(refund.amount_cents)
        FROM refunds refund
        WHERE refund.pix_payment_id = pix_payment.id
          AND refund.status = 'settled'
      ), 0) <= pix_payment.amount_cents
      AND NOT EXISTS (
        SELECT 1
        FROM refunds refund
        WHERE refund.pix_payment_id = pix_payment.id
          AND refund.status = 'settled'
          AND (
            refund.organization_id <> pix_payment.organization_id
            OR refund.wallet_id <> pix_payment.wallet_id
            OR refund.currency <> pix_payment.currency
            OR pix_payment.status <> 'settled'
            OR pix_payment.reversal_journal_entry_id IS NOT NULL
          )
      )
  );
$$;


--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id bigint NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: api_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_credentials (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    name character varying NOT NULL,
    key_prefix character varying NOT NULL,
    key_digest character varying NOT NULL,
    scopes jsonb DEFAULT '[]'::jsonb NOT NULL,
    last_used_at timestamp(6) without time zone,
    expires_at timestamp(6) without time zone,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: api_credentials_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.api_credentials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.api_credentials_id_seq OWNED BY public.api_credentials.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_log_anchors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_log_anchors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_log_anchors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_log_anchors_id_seq OWNED BY public.audit_log_anchors.id;


--
-- Name: audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_logs_id_seq OWNED BY public.audit_logs.id;


--
-- Name: balance_projections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.balance_projections (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    wallet_id bigint NOT NULL,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    available_cents bigint DEFAULT 0 NOT NULL,
    pending_cents bigint DEFAULT 0 NOT NULL,
    blocked_cents bigint DEFAULT 0 NOT NULL,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT balance_projections_available_non_negative_check CHECK ((available_cents >= 0)),
    CONSTRAINT balance_projections_blocked_non_negative_check CHECK ((blocked_cents >= 0)),
    CONSTRAINT balance_projections_pending_non_negative_check CHECK ((pending_cents >= 0))
);


--
-- Name: balance_projections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.balance_projections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: balance_projections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.balance_projections_id_seq OWNED BY public.balance_projections.id;


--
-- Name: balance_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.balance_snapshots (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    wallet_id bigint NOT NULL,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    captured_on date NOT NULL,
    captured_at timestamp(6) without time zone NOT NULL,
    available_cents bigint NOT NULL,
    pending_cents bigint NOT NULL,
    blocked_cents bigint NOT NULL,
    ledger_available_cents bigint NOT NULL,
    difference_cents bigint NOT NULL,
    source character varying DEFAULT 'scheduled_capture'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT balance_snapshots_available_non_negative_check CHECK ((available_cents >= 0)),
    CONSTRAINT balance_snapshots_blocked_non_negative_check CHECK ((blocked_cents >= 0)),
    CONSTRAINT balance_snapshots_difference_matches_projection_check CHECK ((difference_cents = (available_cents - ledger_available_cents))),
    CONSTRAINT balance_snapshots_pending_non_negative_check CHECK ((pending_cents >= 0)),
    CONSTRAINT balance_snapshots_source_present_check CHECK ((btrim((source)::text) <> ''::text))
);


--
-- Name: balance_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.balance_snapshots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: balance_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.balance_snapshots_id_seq OWNED BY public.balance_snapshots.id;


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    external_id character varying NOT NULL,
    legal_name character varying NOT NULL,
    document_kind character varying NOT NULL,
    document_number character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT customers_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'blocked'::character varying, 'closed'::character varying])::text[])))
);


--
-- Name: customers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.customers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.customers_id_seq OWNED BY public.customers.id;


--
-- Name: fundings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fundings (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    wallet_id bigint NOT NULL,
    journal_entry_id bigint,
    external_id character varying NOT NULL,
    amount_cents bigint NOT NULL,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    status character varying DEFAULT 'posted'::character varying NOT NULL,
    idempotency_key character varying,
    correlation_id character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    failure_code character varying,
    CONSTRAINT fundings_amount_positive_check CHECK ((amount_cents > 0)),
    CONSTRAINT fundings_idempotency_key_required_check CHECK (((idempotency_key IS NOT NULL) AND (btrim((idempotency_key)::text) <> ''::text))),
    CONSTRAINT fundings_status_check CHECK (((status)::text = ANY ((ARRAY['posted'::character varying, 'failed'::character varying])::text[])))
);


--
-- Name: fundings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.fundings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fundings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.fundings_id_seq OWNED BY public.fundings.id;


--
-- Name: idempotency_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.idempotency_keys (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    key character varying NOT NULL,
    request_method character varying NOT NULL,
    request_path character varying NOT NULL,
    request_hash character varying NOT NULL,
    status character varying DEFAULT 'processing'::character varying NOT NULL,
    response_status integer,
    response_body jsonb DEFAULT '{}'::jsonb NOT NULL,
    locked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT idempotency_keys_identity_present_check CHECK (((btrim((key)::text) <> ''::text) AND (btrim((request_method)::text) <> ''::text) AND (btrim((request_path)::text) <> ''::text))),
    CONSTRAINT idempotency_keys_request_hash_sha256_check CHECK (((request_hash)::text ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT idempotency_keys_response_state_check CHECK (((((status)::text = 'processing'::text) AND (locked_at IS NOT NULL) AND (response_status IS NULL)) OR (((status)::text = 'succeeded'::text) AND ((response_status >= 100) AND (response_status <= 599))) OR (((status)::text = 'failed'::text) AND (response_status IS NULL)))),
    CONSTRAINT idempotency_keys_status_check CHECK (((status)::text = ANY ((ARRAY['processing'::character varying, 'succeeded'::character varying, 'failed'::character varying])::text[])))
);


--
-- Name: idempotency_keys_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.idempotency_keys_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: idempotency_keys_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.idempotency_keys_id_seq OWNED BY public.idempotency_keys.id;


--
-- Name: journal_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.journal_entries (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    event_type character varying NOT NULL,
    status character varying DEFAULT 'posted'::character varying NOT NULL,
    reference_type character varying,
    reference_id bigint,
    idempotency_key character varying NOT NULL,
    correlation_id character varying,
    occurred_at timestamp(6) without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT journal_entries_event_type_supported_check CHECK (public.financial_journal_event_type_requires_evidence((event_type)::text)),
    CONSTRAINT journal_entries_reference_required_check CHECK (((reference_type IS NOT NULL) AND (reference_id IS NOT NULL))),
    CONSTRAINT journal_entries_status_check CHECK (((status)::text = ANY ((ARRAY['posted'::character varying, 'reversed'::character varying])::text[])))
);


--
-- Name: journal_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.journal_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: journal_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.journal_entries_id_seq OWNED BY public.journal_entries.id;


--
-- Name: ledger_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ledger_accounts (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    wallet_id bigint,
    code character varying NOT NULL,
    name character varying NOT NULL,
    account_type character varying NOT NULL,
    normal_balance character varying NOT NULL,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT ledger_accounts_account_type_check CHECK (((account_type)::text = ANY ((ARRAY['asset'::character varying, 'liability'::character varying, 'revenue'::character varying, 'expense'::character varying, 'equity'::character varying])::text[]))),
    CONSTRAINT ledger_accounts_normal_balance_check CHECK (((normal_balance)::text = ANY ((ARRAY['debit'::character varying, 'credit'::character varying])::text[]))),
    CONSTRAINT ledger_accounts_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'archived'::character varying])::text[])))
);


--
-- Name: ledger_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ledger_accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ledger_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ledger_accounts_id_seq OWNED BY public.ledger_accounts.id;


--
-- Name: ledger_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ledger_lines (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    journal_entry_id bigint NOT NULL,
    ledger_account_id bigint NOT NULL,
    direction character varying NOT NULL,
    amount_cents bigint NOT NULL,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT ledger_lines_amount_positive_check CHECK ((amount_cents > 0)),
    CONSTRAINT ledger_lines_direction_check CHECK (((direction)::text = ANY ((ARRAY['debit'::character varying, 'credit'::character varying])::text[])))
);


--
-- Name: ledger_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ledger_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ledger_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ledger_lines_id_seq OWNED BY public.ledger_lines.id;


--
-- Name: med_cases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.med_cases (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    pix_payment_id bigint NOT NULL,
    refund_id bigint,
    external_id character varying NOT NULL,
    amount_cents bigint NOT NULL,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    status character varying DEFAULT 'opened'::character varying NOT NULL,
    reason character varying NOT NULL,
    opened_at timestamp(6) without time zone NOT NULL,
    resolved_at timestamp(6) without time zone,
    idempotency_key character varying,
    correlation_id character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    operator_approval_id bigint,
    CONSTRAINT med_cases_amount_positive_check CHECK ((amount_cents > 0)),
    CONSTRAINT med_cases_idempotency_key_required_check CHECK (((idempotency_key IS NOT NULL) AND (btrim((idempotency_key)::text) <> ''::text))),
    CONSTRAINT med_cases_status_check CHECK (((status)::text = ANY ((ARRAY['opened'::character varying, 'rejected'::character varying, 'refunded'::character varying])::text[])))
);


--
-- Name: med_cases_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.med_cases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: med_cases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.med_cases_id_seq OWNED BY public.med_cases.id;


--
-- Name: operator_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.operator_approvals (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    action character varying NOT NULL,
    subject_type character varying NOT NULL,
    subject_id bigint NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    requested_by_id bigint NOT NULL,
    approved_by_id bigint,
    approved_at timestamp(6) without time zone,
    reason character varying,
    correlation_id character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT operator_approvals_dual_control_check CHECK (((approved_by_id IS NULL) OR (approved_by_id <> requested_by_id))),
    CONSTRAINT operator_approvals_identity_present_check CHECK (((btrim((action)::text) <> ''::text) AND (btrim((subject_type)::text) <> ''::text) AND (subject_id > 0))),
    CONSTRAINT operator_approvals_state_evidence_check CHECK (((((status)::text = 'pending'::text) AND (approved_by_id IS NULL) AND (approved_at IS NULL)) OR (((status)::text = ANY ((ARRAY['approved'::character varying, 'rejected'::character varying])::text[])) AND (approved_by_id IS NOT NULL) AND (approved_at IS NOT NULL)))),
    CONSTRAINT operator_approvals_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying])::text[])))
);


--
-- Name: operator_approvals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.operator_approvals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: operator_approvals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.operator_approvals_id_seq OWNED BY public.operator_approvals.id;


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    api_key_digest character varying NOT NULL,
    rate_limit_per_minute integer DEFAULT 120 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT organizations_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'suspended'::character varying])::text[])))
);


--
-- Name: organizations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.organizations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organizations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.organizations_id_seq OWNED BY public.organizations.id;


--
-- Name: outbox_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.outbox_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: outbox_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.outbox_events_id_seq OWNED BY public.outbox_events.id;


--
-- Name: outbox_legacy_command_identity_exceptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.outbox_legacy_command_identity_exceptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: outbox_legacy_command_identity_exceptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.outbox_legacy_command_identity_exceptions_id_seq OWNED BY public.outbox_legacy_command_identity_exceptions.id;


--
-- Name: payouts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payouts (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    wallet_id bigint NOT NULL,
    journal_entry_id bigint,
    settlement_journal_entry_id bigint,
    external_id character varying NOT NULL,
    amount_cents bigint NOT NULL,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    status character varying DEFAULT 'scheduled'::character varying NOT NULL,
    settlement_delay_days integer DEFAULT 1 NOT NULL,
    settlement_due_on date NOT NULL,
    settled_at timestamp(6) without time zone,
    destination_kind character varying DEFAULT 'bank_account'::character varying NOT NULL,
    destination_reference character varying NOT NULL,
    failure_code character varying,
    idempotency_key character varying,
    correlation_id character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    operator_approval_id bigint,
    CONSTRAINT payouts_amount_positive_check CHECK ((amount_cents > 0)),
    CONSTRAINT payouts_idempotency_key_required_check CHECK (((idempotency_key IS NOT NULL) AND (btrim((idempotency_key)::text) <> ''::text))),
    CONSTRAINT payouts_settlement_delay_non_negative_check CHECK ((settlement_delay_days >= 0)),
    CONSTRAINT payouts_status_check CHECK (((status)::text = ANY ((ARRAY['scheduled'::character varying, 'settled'::character varying, 'failed'::character varying])::text[])))
);


--
-- Name: payouts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payouts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payouts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payouts_id_seq OWNED BY public.payouts.id;


--
-- Name: pix_payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pix_payments (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    wallet_id bigint NOT NULL,
    journal_entry_id bigint,
    settlement_journal_entry_id bigint,
    external_id character varying NOT NULL,
    pix_key character varying NOT NULL,
    receiver_name character varying NOT NULL,
    amount_cents bigint NOT NULL,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    status character varying DEFAULT 'created'::character varying NOT NULL,
    risk_score integer DEFAULT 0 NOT NULL,
    idempotency_key character varying,
    correlation_id character varying,
    failure_code character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    reversal_journal_entry_id bigint,
    reversed_at timestamp(6) without time zone,
    reversal_reason character varying,
    CONSTRAINT pix_payments_amount_positive_check CHECK ((amount_cents > 0)),
    CONSTRAINT pix_payments_idempotency_key_required_check CHECK (((idempotency_key IS NOT NULL) AND (btrim((idempotency_key)::text) <> ''::text))),
    CONSTRAINT pix_payments_status_check CHECK (((status)::text = ANY ((ARRAY['created'::character varying, 'pending_review'::character varying, 'approved'::character varying, 'rejected'::character varying, 'settled'::character varying, 'failed'::character varying, 'reversed'::character varying])::text[])))
);


--
-- Name: pix_payments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pix_payments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pix_payments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pix_payments_id_seq OWNED BY public.pix_payments.id;


--
-- Name: processed_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.processed_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: processed_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.processed_events_id_seq OWNED BY public.processed_events.id;


--
-- Name: reconciliation_rows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reconciliation_rows (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    reconciliation_run_id bigint NOT NULL,
    journal_entry_id bigint,
    row_type character varying NOT NULL,
    status character varying NOT NULL,
    external_id character varying NOT NULL,
    occurred_on date NOT NULL,
    provider_amount_cents bigint DEFAULT 0 NOT NULL,
    ledger_amount_cents bigint DEFAULT 0 NOT NULL,
    difference_cents bigint DEFAULT 0 NOT NULL,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT reconciliation_rows_amount_status_check CHECK (((((status)::text = 'matched'::text) AND (difference_cents = 0)) OR (((status)::text = 'discrepant'::text) AND (difference_cents <> 0)) OR (((status)::text = 'missing_in_ledger'::text) AND (ledger_amount_cents = 0) AND (provider_amount_cents <> 0)) OR (((status)::text = 'missing_in_provider'::text) AND (provider_amount_cents = 0) AND (ledger_amount_cents <> 0)))),
    CONSTRAINT reconciliation_rows_difference_check CHECK ((difference_cents = (provider_amount_cents - ledger_amount_cents))),
    CONSTRAINT reconciliation_rows_external_id_required_check CHECK ((external_id IS NOT NULL)),
    CONSTRAINT reconciliation_rows_row_type_check CHECK (((row_type)::text = ANY ((ARRAY['cash_balance'::character varying, 'projection_balance'::character varying, 'provider_statement_entry'::character varying, 'ledger_statement_entry'::character varying])::text[]))),
    CONSTRAINT reconciliation_rows_status_check CHECK (((status)::text = ANY ((ARRAY['matched'::character varying, 'discrepant'::character varying, 'missing_in_ledger'::character varying, 'missing_in_provider'::character varying])::text[]))),
    CONSTRAINT reconciliation_rows_type_status_check CHECK (((((row_type)::text = ANY ((ARRAY['cash_balance'::character varying, 'projection_balance'::character varying])::text[])) AND ((status)::text = ANY ((ARRAY['matched'::character varying, 'discrepant'::character varying])::text[]))) OR (((row_type)::text = 'provider_statement_entry'::text) AND ((status)::text = ANY ((ARRAY['matched'::character varying, 'discrepant'::character varying, 'missing_in_ledger'::character varying])::text[]))) OR (((row_type)::text = 'ledger_statement_entry'::text) AND ((status)::text = 'missing_in_provider'::text))))
);


--
-- Name: reconciliation_rows_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reconciliation_rows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reconciliation_rows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reconciliation_rows_id_seq OWNED BY public.reconciliation_rows.id;


--
-- Name: reconciliation_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reconciliation_runs (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    provider character varying NOT NULL,
    statement_date date NOT NULL,
    provider_balance_cents bigint NOT NULL,
    ledger_balance_cents bigint NOT NULL,
    discrepancy_cents bigint NOT NULL,
    status character varying NOT NULL,
    correlation_id character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT reconciliation_runs_discrepancy_check CHECK ((discrepancy_cents = (provider_balance_cents - ledger_balance_cents))),
    CONSTRAINT reconciliation_runs_provider_present_check CHECK ((btrim((provider)::text) <> ''::text)),
    CONSTRAINT reconciliation_runs_status_check CHECK (((status)::text = ANY ((ARRAY['matched'::character varying, 'discrepant'::character varying])::text[])))
);


--
-- Name: reconciliation_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reconciliation_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reconciliation_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reconciliation_runs_id_seq OWNED BY public.reconciliation_runs.id;


--
-- Name: refunds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refunds (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    wallet_id bigint NOT NULL,
    pix_payment_id bigint NOT NULL,
    journal_entry_id bigint,
    external_id character varying NOT NULL,
    amount_cents bigint NOT NULL,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    status character varying DEFAULT 'settled'::character varying NOT NULL,
    reason character varying NOT NULL,
    settled_at timestamp(6) without time zone,
    failure_code character varying,
    idempotency_key character varying,
    correlation_id character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT refunds_amount_positive_check CHECK ((amount_cents > 0)),
    CONSTRAINT refunds_idempotency_key_required_check CHECK (((idempotency_key IS NOT NULL) AND (btrim((idempotency_key)::text) <> ''::text))),
    CONSTRAINT refunds_status_check CHECK (((status)::text = ANY ((ARRAY['settled'::character varying, 'failed'::character varying])::text[])))
);


--
-- Name: refunds_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.refunds_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: refunds_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.refunds_id_seq OWNED BY public.refunds.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    ip_address character varying,
    user_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;


--
-- Name: split_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.split_entries (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    split_payment_id bigint NOT NULL,
    destination_wallet_id bigint NOT NULL,
    amount_cents bigint NOT NULL,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT split_entries_amount_positive_check CHECK ((amount_cents > 0))
);


--
-- Name: split_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.split_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: split_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.split_entries_id_seq OWNED BY public.split_entries.id;


--
-- Name: split_payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.split_payments (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    source_wallet_id bigint NOT NULL,
    journal_entry_id bigint,
    external_id character varying NOT NULL,
    total_amount_cents bigint NOT NULL,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    status character varying DEFAULT 'posted'::character varying NOT NULL,
    memo character varying,
    failure_code character varying,
    idempotency_key character varying,
    correlation_id character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT split_payments_idempotency_key_required_check CHECK (((idempotency_key IS NOT NULL) AND (btrim((idempotency_key)::text) <> ''::text))),
    CONSTRAINT split_payments_status_check CHECK (((status)::text = ANY ((ARRAY['posted'::character varying, 'failed'::character varying])::text[]))),
    CONSTRAINT split_payments_total_amount_positive_check CHECK ((total_amount_cents > 0))
);


--
-- Name: split_payments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.split_payments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: split_payments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.split_payments_id_seq OWNED BY public.split_payments.id;


--
-- Name: transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transfers (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    source_wallet_id bigint NOT NULL,
    destination_wallet_id bigint NOT NULL,
    journal_entry_id bigint,
    external_id character varying NOT NULL,
    amount_cents bigint NOT NULL,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    status character varying DEFAULT 'posted'::character varying NOT NULL,
    idempotency_key character varying,
    correlation_id character varying,
    memo character varying,
    failure_code character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT transfers_amount_positive_check CHECK ((amount_cents > 0)),
    CONSTRAINT transfers_idempotency_key_required_check CHECK (((idempotency_key IS NOT NULL) AND (btrim((idempotency_key)::text) <> ''::text))),
    CONSTRAINT transfers_status_check CHECK (((status)::text = ANY ((ARRAY['posted'::character varying, 'failed'::character varying])::text[])))
);


--
-- Name: transfers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.transfers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transfers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.transfers_id_seq OWNED BY public.transfers.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email_address character varying NOT NULL,
    password_digest character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    role character varying DEFAULT 'operator'::character varying NOT NULL,
    CONSTRAINT users_role_check CHECK (((role)::text = ANY ((ARRAY['viewer'::character varying, 'operator'::character varying, 'admin'::character varying])::text[])))
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: wallets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallets (
    id bigint NOT NULL,
    public_id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id bigint NOT NULL,
    customer_id bigint NOT NULL,
    external_id character varying NOT NULL,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    lock_version integer DEFAULT 0 NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT wallets_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'blocked'::character varying, 'closed'::character varying])::text[])))
);


--
-- Name: wallets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wallets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wallets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wallets_id_seq OWNED BY public.wallets.id;


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: api_credentials id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_credentials ALTER COLUMN id SET DEFAULT nextval('public.api_credentials_id_seq'::regclass);


--
-- Name: audit_log_anchors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log_anchors ALTER COLUMN id SET DEFAULT nextval('public.audit_log_anchors_id_seq'::regclass);


--
-- Name: audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs ALTER COLUMN id SET DEFAULT nextval('public.audit_logs_id_seq'::regclass);


--
-- Name: balance_projections id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.balance_projections ALTER COLUMN id SET DEFAULT nextval('public.balance_projections_id_seq'::regclass);


--
-- Name: balance_snapshots id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.balance_snapshots ALTER COLUMN id SET DEFAULT nextval('public.balance_snapshots_id_seq'::regclass);


--
-- Name: customers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers ALTER COLUMN id SET DEFAULT nextval('public.customers_id_seq'::regclass);


--
-- Name: fundings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fundings ALTER COLUMN id SET DEFAULT nextval('public.fundings_id_seq'::regclass);


--
-- Name: idempotency_keys id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys ALTER COLUMN id SET DEFAULT nextval('public.idempotency_keys_id_seq'::regclass);


--
-- Name: journal_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries ALTER COLUMN id SET DEFAULT nextval('public.journal_entries_id_seq'::regclass);


--
-- Name: ledger_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_accounts ALTER COLUMN id SET DEFAULT nextval('public.ledger_accounts_id_seq'::regclass);


--
-- Name: ledger_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_lines ALTER COLUMN id SET DEFAULT nextval('public.ledger_lines_id_seq'::regclass);


--
-- Name: med_cases id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.med_cases ALTER COLUMN id SET DEFAULT nextval('public.med_cases_id_seq'::regclass);


--
-- Name: operator_approvals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operator_approvals ALTER COLUMN id SET DEFAULT nextval('public.operator_approvals_id_seq'::regclass);


--
-- Name: organizations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations ALTER COLUMN id SET DEFAULT nextval('public.organizations_id_seq'::regclass);


--
-- Name: outbox_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_events ALTER COLUMN id SET DEFAULT nextval('public.outbox_events_id_seq'::regclass);


--
-- Name: outbox_legacy_command_identity_exceptions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_legacy_command_identity_exceptions ALTER COLUMN id SET DEFAULT nextval('public.outbox_legacy_command_identity_exceptions_id_seq'::regclass);


--
-- Name: payouts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts ALTER COLUMN id SET DEFAULT nextval('public.payouts_id_seq'::regclass);


--
-- Name: pix_payments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pix_payments ALTER COLUMN id SET DEFAULT nextval('public.pix_payments_id_seq'::regclass);


--
-- Name: processed_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed_events ALTER COLUMN id SET DEFAULT nextval('public.processed_events_id_seq'::regclass);


--
-- Name: reconciliation_rows id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliation_rows ALTER COLUMN id SET DEFAULT nextval('public.reconciliation_rows_id_seq'::regclass);


--
-- Name: reconciliation_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliation_runs ALTER COLUMN id SET DEFAULT nextval('public.reconciliation_runs_id_seq'::regclass);


--
-- Name: refunds id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds ALTER COLUMN id SET DEFAULT nextval('public.refunds_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: split_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.split_entries ALTER COLUMN id SET DEFAULT nextval('public.split_entries_id_seq'::regclass);


--
-- Name: split_payments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.split_payments ALTER COLUMN id SET DEFAULT nextval('public.split_payments_id_seq'::regclass);


--
-- Name: transfers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers ALTER COLUMN id SET DEFAULT nextval('public.transfers_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: wallets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets ALTER COLUMN id SET DEFAULT nextval('public.wallets_id_seq'::regclass);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: api_credentials api_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_credentials
    ADD CONSTRAINT api_credentials_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_log_anchors audit_log_anchors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log_anchors
    ADD CONSTRAINT audit_log_anchors_pkey PRIMARY KEY (id);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: balance_projections balance_projections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.balance_projections
    ADD CONSTRAINT balance_projections_pkey PRIMARY KEY (id);


--
-- Name: balance_snapshots balance_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.balance_snapshots
    ADD CONSTRAINT balance_snapshots_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: fundings fundings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fundings
    ADD CONSTRAINT fundings_pkey PRIMARY KEY (id);


--
-- Name: idempotency_keys idempotency_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT idempotency_keys_pkey PRIMARY KEY (id);


--
-- Name: journal_entries journal_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_pkey PRIMARY KEY (id);


--
-- Name: ledger_accounts ledger_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_accounts
    ADD CONSTRAINT ledger_accounts_pkey PRIMARY KEY (id);


--
-- Name: ledger_lines ledger_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_lines
    ADD CONSTRAINT ledger_lines_pkey PRIMARY KEY (id);


--
-- Name: med_cases med_cases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.med_cases
    ADD CONSTRAINT med_cases_pkey PRIMARY KEY (id);


--
-- Name: operator_approvals operator_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operator_approvals
    ADD CONSTRAINT operator_approvals_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: outbox_events outbox_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_events
    ADD CONSTRAINT outbox_events_pkey PRIMARY KEY (id);


--
-- Name: outbox_legacy_command_identity_exceptions outbox_legacy_command_identity_exceptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_legacy_command_identity_exceptions
    ADD CONSTRAINT outbox_legacy_command_identity_exceptions_pkey PRIMARY KEY (id);


--
-- Name: payouts payouts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT payouts_pkey PRIMARY KEY (id);


--
-- Name: pix_payments pix_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pix_payments
    ADD CONSTRAINT pix_payments_pkey PRIMARY KEY (id);


--
-- Name: processed_events processed_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed_events
    ADD CONSTRAINT processed_events_pkey PRIMARY KEY (id);


--
-- Name: reconciliation_rows reconciliation_rows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliation_rows
    ADD CONSTRAINT reconciliation_rows_pkey PRIMARY KEY (id);


--
-- Name: reconciliation_runs reconciliation_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliation_runs
    ADD CONSTRAINT reconciliation_runs_pkey PRIMARY KEY (id);


--
-- Name: refunds refunds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: split_entries split_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.split_entries
    ADD CONSTRAINT split_entries_pkey PRIMARY KEY (id);


--
-- Name: split_payments split_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.split_payments
    ADD CONSTRAINT split_payments_pkey PRIMARY KEY (id);


--
-- Name: transfers transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: wallets wallets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_pkey PRIMARY KEY (id);


--
-- Name: idx_balance_projection_wallet_currency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_balance_projection_wallet_currency ON public.balance_projections USING btree (organization_id, wallet_id, currency);


--
-- Name: idx_balance_snapshots_wallet_day; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_balance_snapshots_wallet_day ON public.balance_snapshots USING btree (organization_id, wallet_id, currency, captured_on);


--
-- Name: idx_legacy_outbox_exceptions_aggregate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_legacy_outbox_exceptions_aggregate ON public.outbox_legacy_command_identity_exceptions USING btree (aggregate_type, aggregate_id, event_type);


--
-- Name: idx_legacy_outbox_exceptions_event; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_legacy_outbox_exceptions_event ON public.outbox_legacy_command_identity_exceptions USING btree (outbox_event_id);


--
-- Name: idx_legacy_outbox_exceptions_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_legacy_outbox_exceptions_org ON public.outbox_legacy_command_identity_exceptions USING btree (organization_id);


--
-- Name: idx_legacy_outbox_exceptions_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_legacy_outbox_exceptions_public_id ON public.outbox_legacy_command_identity_exceptions USING btree (public_id);


--
-- Name: idx_on_organization_id_processor_status_4e31dea64d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_processor_status_4e31dea64d ON public.processed_events USING btree (organization_id, processor, status);


--
-- Name: idx_operator_approvals_one_pending_action; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_operator_approvals_one_pending_action ON public.operator_approvals USING btree (action, subject_type, subject_id) WHERE ((status)::text = 'pending'::text);


--
-- Name: idx_outbox_status_next_attempt; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_outbox_status_next_attempt ON public.outbox_events USING btree (status, next_attempt_at);


--
-- Name: idx_reconciliation_provider_day; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_reconciliation_provider_day ON public.reconciliation_runs USING btree (organization_id, provider, statement_date);


--
-- Name: idx_reconciliation_rows_org_day_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reconciliation_rows_org_day_status ON public.reconciliation_rows USING btree (organization_id, occurred_on, status);


--
-- Name: idx_reconciliation_rows_org_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reconciliation_rows_org_external_id ON public.reconciliation_rows USING btree (organization_id, external_id);


--
-- Name: idx_reconciliation_rows_run_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reconciliation_rows_run_external_id ON public.reconciliation_rows USING btree (reconciliation_run_id, external_id);


--
-- Name: idx_reconciliation_rows_run_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reconciliation_rows_run_status ON public.reconciliation_rows USING btree (reconciliation_run_id, status);


--
-- Name: idx_reconciliation_rows_run_type_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_reconciliation_rows_run_type_external_id ON public.reconciliation_rows USING btree (reconciliation_run_id, row_type, external_id);


--
-- Name: idx_split_entries_unique_destination_per_split; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_split_entries_unique_destination_per_split ON public.split_entries USING btree (split_payment_id, destination_wallet_id);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_api_credentials_on_key_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_api_credentials_on_key_digest ON public.api_credentials USING btree (key_digest);


--
-- Name: index_api_credentials_on_key_prefix; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_api_credentials_on_key_prefix ON public.api_credentials USING btree (key_prefix);


--
-- Name: index_api_credentials_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_credentials_on_organization_id ON public.api_credentials USING btree (organization_id);


--
-- Name: index_api_credentials_on_organization_id_and_revoked_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_credentials_on_organization_id_and_revoked_at ON public.api_credentials USING btree (organization_id, revoked_at);


--
-- Name: index_audit_log_anchors_on_anchor_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_log_anchors_on_anchor_hash ON public.audit_log_anchors USING btree (anchor_hash);


--
-- Name: index_audit_log_anchors_on_audit_log_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_log_anchors_on_audit_log_id ON public.audit_log_anchors USING btree (audit_log_id);


--
-- Name: index_audit_log_anchors_on_chain_sequence; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_log_anchors_on_chain_sequence ON public.audit_log_anchors USING btree (chain_sequence);


--
-- Name: index_audit_log_anchors_on_hash_value; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_log_anchors_on_hash_value ON public.audit_log_anchors USING btree (hash_value);


--
-- Name: index_audit_log_anchors_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_log_anchors_on_organization_id ON public.audit_log_anchors USING btree (organization_id);


--
-- Name: index_audit_log_anchors_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_log_anchors_on_public_id ON public.audit_log_anchors USING btree (public_id);


--
-- Name: index_audit_logs_on_chain_sequence; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_logs_on_chain_sequence ON public.audit_logs USING btree (chain_sequence);


--
-- Name: index_audit_logs_on_hash_value; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_logs_on_hash_value ON public.audit_logs USING btree (hash_value);


--
-- Name: index_audit_logs_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_organization_id ON public.audit_logs USING btree (organization_id);


--
-- Name: index_audit_logs_on_organization_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_organization_id_and_created_at ON public.audit_logs USING btree (organization_id, created_at);


--
-- Name: index_audit_logs_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_logs_on_public_id ON public.audit_logs USING btree (public_id);


--
-- Name: index_audit_logs_on_subject_type_and_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_subject_type_and_subject_id ON public.audit_logs USING btree (subject_type, subject_id);


--
-- Name: index_balance_projections_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_balance_projections_on_organization_id ON public.balance_projections USING btree (organization_id);


--
-- Name: index_balance_projections_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_balance_projections_on_public_id ON public.balance_projections USING btree (public_id);


--
-- Name: index_balance_projections_on_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_balance_projections_on_wallet_id ON public.balance_projections USING btree (wallet_id);


--
-- Name: index_balance_snapshots_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_balance_snapshots_on_organization_id ON public.balance_snapshots USING btree (organization_id);


--
-- Name: index_balance_snapshots_on_organization_id_and_captured_on; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_balance_snapshots_on_organization_id_and_captured_on ON public.balance_snapshots USING btree (organization_id, captured_on);


--
-- Name: index_balance_snapshots_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_balance_snapshots_on_public_id ON public.balance_snapshots USING btree (public_id);


--
-- Name: index_balance_snapshots_on_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_balance_snapshots_on_wallet_id ON public.balance_snapshots USING btree (wallet_id);


--
-- Name: index_customers_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customers_on_organization_id ON public.customers USING btree (organization_id);


--
-- Name: index_customers_on_organization_id_and_document_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customers_on_organization_id_and_document_number ON public.customers USING btree (organization_id, document_number);


--
-- Name: index_customers_on_organization_id_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customers_on_organization_id_and_external_id ON public.customers USING btree (organization_id, external_id);


--
-- Name: index_customers_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customers_on_public_id ON public.customers USING btree (public_id);


--
-- Name: index_fundings_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fundings_on_journal_entry_id ON public.fundings USING btree (journal_entry_id);


--
-- Name: index_fundings_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fundings_on_organization_id ON public.fundings USING btree (organization_id);


--
-- Name: index_fundings_on_organization_id_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_fundings_on_organization_id_and_external_id ON public.fundings USING btree (organization_id, external_id);


--
-- Name: index_fundings_on_organization_id_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_fundings_on_organization_id_and_idempotency_key ON public.fundings USING btree (organization_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: index_fundings_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_fundings_on_public_id ON public.fundings USING btree (public_id);


--
-- Name: index_fundings_on_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fundings_on_wallet_id ON public.fundings USING btree (wallet_id);


--
-- Name: index_idempotency_keys_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_idempotency_keys_on_organization_id ON public.idempotency_keys USING btree (organization_id);


--
-- Name: index_idempotency_keys_on_organization_id_and_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_idempotency_keys_on_organization_id_and_key ON public.idempotency_keys USING btree (organization_id, key);


--
-- Name: index_idempotency_keys_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_idempotency_keys_on_public_id ON public.idempotency_keys USING btree (public_id);


--
-- Name: index_journal_entries_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_journal_entries_on_organization_id ON public.journal_entries USING btree (organization_id);


--
-- Name: index_journal_entries_on_organization_id_and_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_journal_entries_on_organization_id_and_event_type ON public.journal_entries USING btree (organization_id, event_type);


--
-- Name: index_journal_entries_on_organization_id_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_journal_entries_on_organization_id_and_idempotency_key ON public.journal_entries USING btree (organization_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: index_journal_entries_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_journal_entries_on_public_id ON public.journal_entries USING btree (public_id);


--
-- Name: index_journal_entries_on_reference_type_and_reference_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_journal_entries_on_reference_type_and_reference_id ON public.journal_entries USING btree (reference_type, reference_id);


--
-- Name: index_ledger_accounts_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ledger_accounts_on_organization_id ON public.ledger_accounts USING btree (organization_id);


--
-- Name: index_ledger_accounts_on_organization_id_and_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ledger_accounts_on_organization_id_and_code ON public.ledger_accounts USING btree (organization_id, code);


--
-- Name: index_ledger_accounts_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ledger_accounts_on_public_id ON public.ledger_accounts USING btree (public_id);


--
-- Name: index_ledger_accounts_on_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ledger_accounts_on_wallet_id ON public.ledger_accounts USING btree (wallet_id);


--
-- Name: index_ledger_lines_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ledger_lines_on_journal_entry_id ON public.ledger_lines USING btree (journal_entry_id);


--
-- Name: index_ledger_lines_on_ledger_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ledger_lines_on_ledger_account_id ON public.ledger_lines USING btree (ledger_account_id);


--
-- Name: index_ledger_lines_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ledger_lines_on_organization_id ON public.ledger_lines USING btree (organization_id);


--
-- Name: index_ledger_lines_on_organization_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ledger_lines_on_organization_id_and_created_at ON public.ledger_lines USING btree (organization_id, created_at);


--
-- Name: index_ledger_lines_on_organization_id_and_ledger_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ledger_lines_on_organization_id_and_ledger_account_id ON public.ledger_lines USING btree (organization_id, ledger_account_id);


--
-- Name: index_ledger_lines_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ledger_lines_on_public_id ON public.ledger_lines USING btree (public_id);


--
-- Name: index_med_cases_on_operator_approval_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_med_cases_on_operator_approval_id ON public.med_cases USING btree (operator_approval_id);


--
-- Name: index_med_cases_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_med_cases_on_organization_id ON public.med_cases USING btree (organization_id);


--
-- Name: index_med_cases_on_organization_id_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_med_cases_on_organization_id_and_external_id ON public.med_cases USING btree (organization_id, external_id);


--
-- Name: index_med_cases_on_organization_id_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_med_cases_on_organization_id_and_idempotency_key ON public.med_cases USING btree (organization_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: index_med_cases_on_pix_payment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_med_cases_on_pix_payment_id ON public.med_cases USING btree (pix_payment_id);


--
-- Name: index_med_cases_on_pix_payment_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_med_cases_on_pix_payment_id_and_status ON public.med_cases USING btree (pix_payment_id, status);


--
-- Name: index_med_cases_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_med_cases_on_public_id ON public.med_cases USING btree (public_id);


--
-- Name: index_med_cases_on_refund_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_med_cases_on_refund_id ON public.med_cases USING btree (refund_id);


--
-- Name: index_operator_approvals_on_approved_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_operator_approvals_on_approved_by_id ON public.operator_approvals USING btree (approved_by_id);


--
-- Name: index_operator_approvals_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_operator_approvals_on_organization_id ON public.operator_approvals USING btree (organization_id);


--
-- Name: index_operator_approvals_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_operator_approvals_on_public_id ON public.operator_approvals USING btree (public_id);


--
-- Name: index_operator_approvals_on_requested_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_operator_approvals_on_requested_by_id ON public.operator_approvals USING btree (requested_by_id);


--
-- Name: index_organizations_on_api_key_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_organizations_on_api_key_digest ON public.organizations USING btree (api_key_digest);


--
-- Name: index_organizations_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_organizations_on_public_id ON public.organizations USING btree (public_id);


--
-- Name: index_organizations_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_organizations_on_slug ON public.organizations USING btree (slug);


--
-- Name: index_outbox_events_on_aggregate_type_and_aggregate_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_outbox_events_on_aggregate_type_and_aggregate_id ON public.outbox_events USING btree (aggregate_type, aggregate_id);


--
-- Name: index_outbox_events_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_outbox_events_on_organization_id ON public.outbox_events USING btree (organization_id);


--
-- Name: index_outbox_events_on_payload_sha256; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_outbox_events_on_payload_sha256 ON public.outbox_events USING btree (payload_sha256);


--
-- Name: index_outbox_events_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_outbox_events_on_public_id ON public.outbox_events USING btree (public_id);


--
-- Name: index_outbox_events_on_publisher_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_outbox_events_on_publisher_message_id ON public.outbox_events USING btree (publisher_message_id);


--
-- Name: index_outbox_events_on_status_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_outbox_events_on_status_and_created_at ON public.outbox_events USING btree (status, created_at);


--
-- Name: index_payouts_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payouts_on_journal_entry_id ON public.payouts USING btree (journal_entry_id);


--
-- Name: index_payouts_on_operator_approval_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payouts_on_operator_approval_id ON public.payouts USING btree (operator_approval_id);


--
-- Name: index_payouts_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payouts_on_organization_id ON public.payouts USING btree (organization_id);


--
-- Name: index_payouts_on_organization_id_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_payouts_on_organization_id_and_external_id ON public.payouts USING btree (organization_id, external_id);


--
-- Name: index_payouts_on_organization_id_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_payouts_on_organization_id_and_idempotency_key ON public.payouts USING btree (organization_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: index_payouts_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_payouts_on_public_id ON public.payouts USING btree (public_id);


--
-- Name: index_payouts_on_settlement_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payouts_on_settlement_journal_entry_id ON public.payouts USING btree (settlement_journal_entry_id);


--
-- Name: index_payouts_on_status_and_settlement_due_on; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payouts_on_status_and_settlement_due_on ON public.payouts USING btree (status, settlement_due_on);


--
-- Name: index_payouts_on_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payouts_on_wallet_id ON public.payouts USING btree (wallet_id);


--
-- Name: index_pix_payments_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_pix_payments_on_journal_entry_id ON public.pix_payments USING btree (journal_entry_id);


--
-- Name: index_pix_payments_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_pix_payments_on_organization_id ON public.pix_payments USING btree (organization_id);


--
-- Name: index_pix_payments_on_organization_id_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_pix_payments_on_organization_id_and_external_id ON public.pix_payments USING btree (organization_id, external_id);


--
-- Name: index_pix_payments_on_organization_id_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_pix_payments_on_organization_id_and_idempotency_key ON public.pix_payments USING btree (organization_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: index_pix_payments_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_pix_payments_on_public_id ON public.pix_payments USING btree (public_id);


--
-- Name: index_pix_payments_on_reversal_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_pix_payments_on_reversal_journal_entry_id ON public.pix_payments USING btree (reversal_journal_entry_id);


--
-- Name: index_pix_payments_on_settlement_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_pix_payments_on_settlement_journal_entry_id ON public.pix_payments USING btree (settlement_journal_entry_id);


--
-- Name: index_pix_payments_on_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_pix_payments_on_wallet_id ON public.pix_payments USING btree (wallet_id);


--
-- Name: index_processed_events_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_processed_events_on_organization_id ON public.processed_events USING btree (organization_id);


--
-- Name: index_processed_events_on_outbox_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_processed_events_on_outbox_event_id ON public.processed_events USING btree (outbox_event_id);


--
-- Name: index_processed_events_on_outbox_event_id_and_processor; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_processed_events_on_outbox_event_id_and_processor ON public.processed_events USING btree (outbox_event_id, processor);


--
-- Name: index_processed_events_on_processor_and_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_processed_events_on_processor_and_event_id ON public.processed_events USING btree (processor, event_id);


--
-- Name: index_processed_events_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_processed_events_on_public_id ON public.processed_events USING btree (public_id);


--
-- Name: index_reconciliation_rows_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reconciliation_rows_on_journal_entry_id ON public.reconciliation_rows USING btree (journal_entry_id);


--
-- Name: index_reconciliation_rows_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reconciliation_rows_on_organization_id ON public.reconciliation_rows USING btree (organization_id);


--
-- Name: index_reconciliation_rows_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_reconciliation_rows_on_public_id ON public.reconciliation_rows USING btree (public_id);


--
-- Name: index_reconciliation_rows_on_reconciliation_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reconciliation_rows_on_reconciliation_run_id ON public.reconciliation_rows USING btree (reconciliation_run_id);


--
-- Name: index_reconciliation_runs_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reconciliation_runs_on_organization_id ON public.reconciliation_runs USING btree (organization_id);


--
-- Name: index_reconciliation_runs_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_reconciliation_runs_on_public_id ON public.reconciliation_runs USING btree (public_id);


--
-- Name: index_refunds_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_refunds_on_journal_entry_id ON public.refunds USING btree (journal_entry_id);


--
-- Name: index_refunds_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_refunds_on_organization_id ON public.refunds USING btree (organization_id);


--
-- Name: index_refunds_on_organization_id_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_refunds_on_organization_id_and_external_id ON public.refunds USING btree (organization_id, external_id);


--
-- Name: index_refunds_on_organization_id_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_refunds_on_organization_id_and_idempotency_key ON public.refunds USING btree (organization_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: index_refunds_on_pix_payment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_refunds_on_pix_payment_id ON public.refunds USING btree (pix_payment_id);


--
-- Name: index_refunds_on_pix_payment_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_refunds_on_pix_payment_id_and_status ON public.refunds USING btree (pix_payment_id, status);


--
-- Name: index_refunds_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_refunds_on_public_id ON public.refunds USING btree (public_id);


--
-- Name: index_refunds_on_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_refunds_on_wallet_id ON public.refunds USING btree (wallet_id);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_split_entries_on_destination_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_split_entries_on_destination_wallet_id ON public.split_entries USING btree (destination_wallet_id);


--
-- Name: index_split_entries_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_split_entries_on_organization_id ON public.split_entries USING btree (organization_id);


--
-- Name: index_split_entries_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_split_entries_on_public_id ON public.split_entries USING btree (public_id);


--
-- Name: index_split_entries_on_split_payment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_split_entries_on_split_payment_id ON public.split_entries USING btree (split_payment_id);


--
-- Name: index_split_payments_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_split_payments_on_journal_entry_id ON public.split_payments USING btree (journal_entry_id);


--
-- Name: index_split_payments_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_split_payments_on_organization_id ON public.split_payments USING btree (organization_id);


--
-- Name: index_split_payments_on_organization_id_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_split_payments_on_organization_id_and_external_id ON public.split_payments USING btree (organization_id, external_id);


--
-- Name: index_split_payments_on_organization_id_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_split_payments_on_organization_id_and_idempotency_key ON public.split_payments USING btree (organization_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: index_split_payments_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_split_payments_on_public_id ON public.split_payments USING btree (public_id);


--
-- Name: index_split_payments_on_source_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_split_payments_on_source_wallet_id ON public.split_payments USING btree (source_wallet_id);


--
-- Name: index_transfers_on_destination_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_transfers_on_destination_wallet_id ON public.transfers USING btree (destination_wallet_id);


--
-- Name: index_transfers_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_transfers_on_journal_entry_id ON public.transfers USING btree (journal_entry_id);


--
-- Name: index_transfers_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_transfers_on_organization_id ON public.transfers USING btree (organization_id);


--
-- Name: index_transfers_on_organization_id_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_transfers_on_organization_id_and_external_id ON public.transfers USING btree (organization_id, external_id);


--
-- Name: index_transfers_on_organization_id_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_transfers_on_organization_id_and_idempotency_key ON public.transfers USING btree (organization_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: index_transfers_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_transfers_on_public_id ON public.transfers USING btree (public_id);


--
-- Name: index_transfers_on_source_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_transfers_on_source_wallet_id ON public.transfers USING btree (source_wallet_id);


--
-- Name: index_users_on_email_address; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email_address ON public.users USING btree (email_address);


--
-- Name: index_users_on_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_role ON public.users USING btree (role);


--
-- Name: index_wallets_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_wallets_on_customer_id ON public.wallets USING btree (customer_id);


--
-- Name: index_wallets_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_wallets_on_organization_id ON public.wallets USING btree (organization_id);


--
-- Name: index_wallets_on_organization_id_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_wallets_on_organization_id_and_external_id ON public.wallets USING btree (organization_id, external_id);


--
-- Name: index_wallets_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_wallets_on_public_id ON public.wallets USING btree (public_id);


--
-- Name: audit_log_anchors audit_log_anchors_prevent_update_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_log_anchors_prevent_update_delete BEFORE DELETE OR UPDATE ON public.audit_log_anchors FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_anchor_mutation();


--
-- Name: audit_logs audit_logs_hash_chain_before_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_logs_hash_chain_before_insert BEFORE INSERT ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.assign_audit_log_hash_chain();


--
-- Name: audit_logs audit_logs_prevent_update_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_logs_prevent_update_delete BEFORE DELETE OR UPDATE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_mutation();


--
-- Name: balance_projections balance_projections_amount_write_gate_before_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER balance_projections_amount_write_gate_before_update BEFORE UPDATE OF available_cents, pending_cents, blocked_cents ON public.balance_projections FOR EACH ROW WHEN (((old.available_cents IS DISTINCT FROM new.available_cents) OR (old.pending_cents IS DISTINCT FROM new.pending_cents) OR (old.blocked_cents IS DISTINCT FROM new.blocked_cents))) EXECUTE FUNCTION public.assert_balance_projection_amount_write_context();


--
-- Name: balance_projections balance_projections_wallet_evidence_before_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER balance_projections_wallet_evidence_before_write BEFORE INSERT OR UPDATE OF organization_id, wallet_id, currency ON public.balance_projections FOR EACH ROW EXECUTE FUNCTION public.assert_balance_projection_wallet_evidence();


--
-- Name: balance_snapshots balance_snapshots_prevent_evidence_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER balance_snapshots_prevent_evidence_mutation BEFORE INSERT OR DELETE OR UPDATE ON public.balance_snapshots FOR EACH ROW EXECUTE FUNCTION public.prevent_balance_snapshot_evidence_mutation();


--
-- Name: ledger_lines enforce_ledger_line_account_consistency; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER enforce_ledger_line_account_consistency BEFORE INSERT ON public.ledger_lines FOR EACH ROW EXECUTE FUNCTION public.enforce_ledger_line_account_consistency();


--
-- Name: fundings fundings_journal_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER fundings_journal_evidence_after_write AFTER INSERT OR UPDATE ON public.fundings DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_financial_command_journal_evidence();


--
-- Name: fundings fundings_prevent_evidence_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER fundings_prevent_evidence_mutation BEFORE DELETE OR UPDATE ON public.fundings FOR EACH ROW EXECUTE FUNCTION public.prevent_funding_evidence_mutation();


--
-- Name: fundings fundings_state_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER fundings_state_evidence_after_write AFTER INSERT OR UPDATE ON public.fundings DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_funding_state_evidence();


--
-- Name: idempotency_keys idempotency_keys_prevent_evidence_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER idempotency_keys_prevent_evidence_mutation BEFORE INSERT OR DELETE OR UPDATE ON public.idempotency_keys FOR EACH ROW EXECUTE FUNCTION public.prevent_idempotency_key_evidence_mutation();


--
-- Name: journal_entries journal_entries_financial_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER journal_entries_financial_evidence_after_write AFTER INSERT ON public.journal_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_financial_journal_evidence_after_journal_write();


--
-- Name: journal_entries journal_entry_balanced_after_journal_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER journal_entry_balanced_after_journal_insert AFTER INSERT ON public.journal_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_inserted_journal_entry_balanced();


--
-- Name: ledger_lines journal_entry_balanced_after_line_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER journal_entry_balanced_after_line_insert AFTER INSERT ON public.ledger_lines DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_ledger_line_journal_entry_balanced();


--
-- Name: ledger_lines ledger_lines_financial_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER ledger_lines_financial_evidence_after_write AFTER INSERT ON public.ledger_lines DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_financial_journal_evidence_after_line_write();


--
-- Name: med_cases med_cases_prevent_evidence_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER med_cases_prevent_evidence_mutation BEFORE DELETE OR UPDATE ON public.med_cases FOR EACH ROW EXECUTE FUNCTION public.prevent_med_case_evidence_mutation();


--
-- Name: med_cases med_cases_state_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER med_cases_state_evidence_after_write AFTER INSERT OR UPDATE ON public.med_cases DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_med_case_state_evidence();


--
-- Name: operator_approvals operator_approvals_prevent_evidence_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER operator_approvals_prevent_evidence_mutation BEFORE INSERT OR DELETE OR UPDATE ON public.operator_approvals FOR EACH ROW EXECUTE FUNCTION public.prevent_operator_approval_evidence_mutation();


--
-- Name: outbox_events outbox_events_aggregate_evidence_before_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER outbox_events_aggregate_evidence_before_write BEFORE INSERT OR UPDATE OF organization_id, aggregate_type, aggregate_id, event_type, payload ON public.outbox_events FOR EACH ROW EXECUTE FUNCTION public.assert_outbox_event_aggregate_evidence();


--
-- Name: outbox_events outbox_events_command_identity_before_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER outbox_events_command_identity_before_write BEFORE INSERT OR UPDATE OF organization_id, aggregate_type, aggregate_id, event_type, idempotency_key ON public.outbox_events FOR EACH ROW EXECUTE FUNCTION public.assert_outbox_event_command_identity_evidence();


--
-- Name: outbox_events outbox_events_med_resolution_payload_before_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER outbox_events_med_resolution_payload_before_write BEFORE INSERT OR UPDATE OF aggregate_type, aggregate_id, event_type, payload ON public.outbox_events FOR EACH ROW EXECUTE FUNCTION public.assert_med_outbox_resolution_payload_evidence();


--
-- Name: outbox_events outbox_events_prevent_evidence_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER outbox_events_prevent_evidence_mutation BEFORE INSERT OR DELETE OR UPDATE ON public.outbox_events FOR EACH ROW EXECUTE FUNCTION public.prevent_outbox_event_evidence_mutation();


--
-- Name: outbox_legacy_command_identity_exceptions outbox_legacy_command_identity_exceptions_prevent_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER outbox_legacy_command_identity_exceptions_prevent_mutation BEFORE INSERT OR DELETE OR UPDATE ON public.outbox_legacy_command_identity_exceptions FOR EACH ROW EXECUTE FUNCTION public.prevent_outbox_legacy_command_identity_exception_mutation();


--
-- Name: payouts payouts_journal_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER payouts_journal_evidence_after_write AFTER INSERT OR UPDATE ON public.payouts DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_financial_command_journal_evidence();


--
-- Name: payouts payouts_prevent_evidence_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payouts_prevent_evidence_mutation BEFORE DELETE OR UPDATE ON public.payouts FOR EACH ROW EXECUTE FUNCTION public.prevent_payout_evidence_mutation();


--
-- Name: payouts payouts_state_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER payouts_state_evidence_after_write AFTER INSERT OR UPDATE ON public.payouts DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_payout_state_evidence();


--
-- Name: pix_payments pix_payments_journal_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER pix_payments_journal_evidence_after_write AFTER INSERT OR UPDATE ON public.pix_payments DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_financial_command_journal_evidence();


--
-- Name: pix_payments pix_payments_prevent_evidence_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pix_payments_prevent_evidence_mutation BEFORE DELETE OR UPDATE ON public.pix_payments FOR EACH ROW EXECUTE FUNCTION public.prevent_pix_payment_evidence_mutation();


--
-- Name: pix_payments pix_payments_refund_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER pix_payments_refund_evidence_after_write AFTER UPDATE OF status, amount_cents, organization_id, wallet_id, currency, reversal_journal_entry_id ON public.pix_payments DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_pix_payment_refund_evidence();


--
-- Name: pix_payments pix_payments_state_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER pix_payments_state_evidence_after_write AFTER INSERT OR UPDATE ON public.pix_payments DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_pix_payment_state_evidence();


--
-- Name: journal_entries prevent_journal_entry_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER prevent_journal_entry_mutation BEFORE DELETE OR UPDATE ON public.journal_entries FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_record_mutation();


--
-- Name: ledger_lines prevent_ledger_line_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER prevent_ledger_line_mutation BEFORE DELETE OR UPDATE ON public.ledger_lines FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_record_mutation();


--
-- Name: processed_events processed_events_prevent_evidence_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER processed_events_prevent_evidence_mutation BEFORE INSERT OR DELETE OR UPDATE ON public.processed_events FOR EACH ROW EXECUTE FUNCTION public.prevent_processed_event_evidence_mutation();


--
-- Name: reconciliation_rows reconciliation_rows_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER reconciliation_rows_evidence_after_write AFTER INSERT OR DELETE OR UPDATE ON public.reconciliation_rows DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_reconciliation_run_evidence_after_row_write();


--
-- Name: reconciliation_rows reconciliation_rows_prevent_evidence_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER reconciliation_rows_prevent_evidence_mutation BEFORE INSERT OR DELETE OR UPDATE ON public.reconciliation_rows FOR EACH ROW EXECUTE FUNCTION public.prevent_reconciliation_row_evidence_mutation();


--
-- Name: reconciliation_runs reconciliation_runs_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER reconciliation_runs_evidence_after_write AFTER INSERT OR UPDATE ON public.reconciliation_runs DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_reconciliation_run_evidence_after_run_write();


--
-- Name: reconciliation_runs reconciliation_runs_prevent_evidence_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER reconciliation_runs_prevent_evidence_mutation BEFORE DELETE OR UPDATE ON public.reconciliation_runs FOR EACH ROW EXECUTE FUNCTION public.prevent_reconciliation_run_evidence_mutation();


--
-- Name: refunds refunds_journal_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER refunds_journal_evidence_after_write AFTER INSERT OR UPDATE ON public.refunds DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_financial_command_journal_evidence();


--
-- Name: refunds refunds_lock_pix_payment_before_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER refunds_lock_pix_payment_before_write BEFORE INSERT OR UPDATE OF pix_payment_id, status, amount_cents, organization_id, wallet_id, currency ON public.refunds FOR EACH ROW EXECUTE FUNCTION public.lock_refund_pix_payment_evidence();


--
-- Name: refunds refunds_pix_payment_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER refunds_pix_payment_evidence_after_write AFTER INSERT OR UPDATE OF pix_payment_id, status, amount_cents, organization_id, wallet_id, currency ON public.refunds DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_refund_pix_payment_evidence();


--
-- Name: refunds refunds_prevent_evidence_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER refunds_prevent_evidence_mutation BEFORE DELETE OR UPDATE ON public.refunds FOR EACH ROW EXECUTE FUNCTION public.prevent_refund_evidence_mutation();


--
-- Name: refunds refunds_state_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER refunds_state_evidence_after_write AFTER INSERT OR UPDATE ON public.refunds DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_refund_state_evidence();


--
-- Name: split_entries split_entries_prevent_evidence_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER split_entries_prevent_evidence_mutation BEFORE DELETE OR UPDATE ON public.split_entries FOR EACH ROW EXECUTE FUNCTION public.prevent_split_entry_evidence_mutation();


--
-- Name: split_entries split_entries_state_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER split_entries_state_evidence_after_write AFTER INSERT OR DELETE OR UPDATE ON public.split_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_split_entry_state_evidence_trigger();


--
-- Name: split_payments split_payments_journal_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER split_payments_journal_evidence_after_write AFTER INSERT OR UPDATE ON public.split_payments DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_financial_command_journal_evidence();


--
-- Name: split_payments split_payments_prevent_evidence_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER split_payments_prevent_evidence_mutation BEFORE DELETE OR UPDATE ON public.split_payments FOR EACH ROW EXECUTE FUNCTION public.prevent_split_payment_evidence_mutation();


--
-- Name: split_payments split_payments_state_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER split_payments_state_evidence_after_write AFTER INSERT OR UPDATE ON public.split_payments DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_split_payment_state_evidence_trigger();


--
-- Name: transfers transfers_journal_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER transfers_journal_evidence_after_write AFTER INSERT OR UPDATE ON public.transfers DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_financial_command_journal_evidence();


--
-- Name: transfers transfers_prevent_evidence_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER transfers_prevent_evidence_mutation BEFORE DELETE OR UPDATE ON public.transfers FOR EACH ROW EXECUTE FUNCTION public.prevent_transfer_evidence_mutation();


--
-- Name: transfers transfers_state_evidence_after_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER transfers_state_evidence_after_write AFTER INSERT OR UPDATE ON public.transfers DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_transfer_state_evidence();


--
-- Name: ledger_accounts fk_rails_022c225858; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_accounts
    ADD CONSTRAINT fk_rails_022c225858 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: fundings fk_rails_096e1edeb5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fundings
    ADD CONSTRAINT fk_rails_096e1edeb5 FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: operator_approvals fk_rails_0da5ecbb86; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operator_approvals
    ADD CONSTRAINT fk_rails_0da5ecbb86 FOREIGN KEY (approved_by_id) REFERENCES public.users(id);


--
-- Name: audit_logs fk_rails_13aa3bd6ad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT fk_rails_13aa3bd6ad FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: payouts fk_rails_14046417f7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT fk_rails_14046417f7 FOREIGN KEY (settlement_journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: idempotency_keys fk_rails_149452d765; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT fk_rails_149452d765 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: payouts fk_rails_15f7baae91; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT fk_rails_15f7baae91 FOREIGN KEY (operator_approval_id) REFERENCES public.operator_approvals(id);


--
-- Name: balance_snapshots fk_rails_19719194e6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.balance_snapshots
    ADD CONSTRAINT fk_rails_19719194e6 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: wallets fk_rails_28077d4aa2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT fk_rails_28077d4aa2 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: balance_snapshots fk_rails_286447968d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.balance_snapshots
    ADD CONSTRAINT fk_rails_286447968d FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: ledger_lines fk_rails_28f5a6762e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_lines
    ADD CONSTRAINT fk_rails_28f5a6762e FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: wallets fk_rails_2b35eef34b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT fk_rails_2b35eef34b FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: refunds fk_rails_2e853887c5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT fk_rails_2e853887c5 FOREIGN KEY (pix_payment_id) REFERENCES public.pix_payments(id);


--
-- Name: outbox_legacy_command_identity_exceptions fk_rails_323fa922ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_legacy_command_identity_exceptions
    ADD CONSTRAINT fk_rails_323fa922ed FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: split_entries fk_rails_3b1e99c548; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.split_entries
    ADD CONSTRAINT fk_rails_3b1e99c548 FOREIGN KEY (split_payment_id) REFERENCES public.split_payments(id);


--
-- Name: outbox_legacy_command_identity_exceptions fk_rails_410a8535fc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_legacy_command_identity_exceptions
    ADD CONSTRAINT fk_rails_410a8535fc FOREIGN KEY (outbox_event_id) REFERENCES public.outbox_events(id);


--
-- Name: reconciliation_rows fk_rails_48a7f59771; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliation_rows
    ADD CONSTRAINT fk_rails_48a7f59771 FOREIGN KEY (reconciliation_run_id) REFERENCES public.reconciliation_runs(id);


--
-- Name: med_cases fk_rails_4e3e5fe13a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.med_cases
    ADD CONSTRAINT fk_rails_4e3e5fe13a FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: ledger_accounts fk_rails_4f78b177f6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_accounts
    ADD CONSTRAINT fk_rails_4f78b177f6 FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: split_entries fk_rails_566956e892; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.split_entries
    ADD CONSTRAINT fk_rails_566956e892 FOREIGN KEY (destination_wallet_id) REFERENCES public.wallets(id);


--
-- Name: pix_payments fk_rails_5808e88679; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pix_payments
    ADD CONSTRAINT fk_rails_5808e88679 FOREIGN KEY (journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: customers fk_rails_58234c715e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT fk_rails_58234c715e FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: transfers fk_rails_5ac317b559; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT fk_rails_5ac317b559 FOREIGN KEY (journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: operator_approvals fk_rails_5dc7bdce6d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operator_approvals
    ADD CONSTRAINT fk_rails_5dc7bdce6d FOREIGN KEY (requested_by_id) REFERENCES public.users(id);


--
-- Name: fundings fk_rails_655f0f53a2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fundings
    ADD CONSTRAINT fk_rails_655f0f53a2 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: balance_projections fk_rails_694db2a880; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.balance_projections
    ADD CONSTRAINT fk_rails_694db2a880 FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: fundings fk_rails_6d59ee71eb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fundings
    ADD CONSTRAINT fk_rails_6d59ee71eb FOREIGN KEY (journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: refunds fk_rails_778360c382; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT fk_rails_778360c382 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: balance_projections fk_rails_78556fc9c6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.balance_projections
    ADD CONSTRAINT fk_rails_78556fc9c6 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: med_cases fk_rails_7e1be497a2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.med_cases
    ADD CONSTRAINT fk_rails_7e1be497a2 FOREIGN KEY (pix_payment_id) REFERENCES public.pix_payments(id);


--
-- Name: ledger_lines fk_rails_8577096259; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_lines
    ADD CONSTRAINT fk_rails_8577096259 FOREIGN KEY (ledger_account_id) REFERENCES public.ledger_accounts(id);


--
-- Name: split_payments fk_rails_85ba9e5558; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.split_payments
    ADD CONSTRAINT fk_rails_85ba9e5558 FOREIGN KEY (journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: med_cases fk_rails_931e5c387a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.med_cases
    ADD CONSTRAINT fk_rails_931e5c387a FOREIGN KEY (operator_approval_id) REFERENCES public.operator_approvals(id);


--
-- Name: refunds fk_rails_94ce031b15; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT fk_rails_94ce031b15 FOREIGN KEY (journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: med_cases fk_rails_98054f6c1b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.med_cases
    ADD CONSTRAINT fk_rails_98054f6c1b FOREIGN KEY (refund_id) REFERENCES public.refunds(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: operator_approvals fk_rails_9bf7a2138c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operator_approvals
    ADD CONSTRAINT fk_rails_9bf7a2138c FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: audit_log_anchors fk_rails_a63eb6c722; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log_anchors
    ADD CONSTRAINT fk_rails_a63eb6c722 FOREIGN KEY (audit_log_id) REFERENCES public.audit_logs(id);


--
-- Name: journal_entries fk_rails_aad8a6d0fe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT fk_rails_aad8a6d0fe FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: split_entries fk_rails_afa7634697; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.split_entries
    ADD CONSTRAINT fk_rails_afa7634697 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: payouts fk_rails_b618081134; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT fk_rails_b618081134 FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: outbox_events fk_rails_b6cb24ddb3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_events
    ADD CONSTRAINT fk_rails_b6cb24ddb3 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: audit_log_anchors fk_rails_bb37efe629; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log_anchors
    ADD CONSTRAINT fk_rails_bb37efe629 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: api_credentials fk_rails_be4b4015d9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_credentials
    ADD CONSTRAINT fk_rails_be4b4015d9 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: split_payments fk_rails_c5d221ed22; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.split_payments
    ADD CONSTRAINT fk_rails_c5d221ed22 FOREIGN KEY (source_wallet_id) REFERENCES public.wallets(id);


--
-- Name: transfers fk_rails_c5e21c21e1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT fk_rails_c5e21c21e1 FOREIGN KEY (destination_wallet_id) REFERENCES public.wallets(id);


--
-- Name: transfers fk_rails_c67feee3ec; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT fk_rails_c67feee3ec FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: ledger_lines fk_rails_d088bea263; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_lines
    ADD CONSTRAINT fk_rails_d088bea263 FOREIGN KEY (journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: pix_payments fk_rails_d12a3796e4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pix_payments
    ADD CONSTRAINT fk_rails_d12a3796e4 FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: payouts fk_rails_d13fce3946; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT fk_rails_d13fce3946 FOREIGN KEY (journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: pix_payments fk_rails_d3b180fc2a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pix_payments
    ADD CONSTRAINT fk_rails_d3b180fc2a FOREIGN KEY (reversal_journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: reconciliation_rows fk_rails_d410954a4e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliation_rows
    ADD CONSTRAINT fk_rails_d410954a4e FOREIGN KEY (journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: pix_payments fk_rails_d74603299a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pix_payments
    ADD CONSTRAINT fk_rails_d74603299a FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: reconciliation_rows fk_rails_d74666def8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliation_rows
    ADD CONSTRAINT fk_rails_d74666def8 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: pix_payments fk_rails_dbda65b1d0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pix_payments
    ADD CONSTRAINT fk_rails_dbda65b1d0 FOREIGN KEY (settlement_journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: transfers fk_rails_dfe4c7c78e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT fk_rails_dfe4c7c78e FOREIGN KEY (source_wallet_id) REFERENCES public.wallets(id);


--
-- Name: processed_events fk_rails_e5e2b6b786; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed_events
    ADD CONSTRAINT fk_rails_e5e2b6b786 FOREIGN KEY (outbox_event_id) REFERENCES public.outbox_events(id);


--
-- Name: payouts fk_rails_e83f526e5a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT fk_rails_e83f526e5a FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: split_payments fk_rails_ec6140c53b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.split_payments
    ADD CONSTRAINT fk_rails_ec6140c53b FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: processed_events fk_rails_f1d88ff35f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed_events
    ADD CONSTRAINT fk_rails_f1d88ff35f FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: reconciliation_runs fk_rails_fa7156f82b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliation_runs
    ADD CONSTRAINT fk_rails_fa7156f82b FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: refunds fk_rails_fda274a516; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT fk_rails_fda274a516 FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260612120000'),
('20260602224500'),
('20260602223500'),
('20260602222500'),
('20260602221500'),
('20260602220500'),
('20260602215500'),
('20260602214500'),
('20260602213000'),
('20260602211500'),
('20260602210000'),
('20260602204500'),
('20260602203000'),
('20260602201500'),
('20260602200000'),
('20260602194500'),
('20260602193000'),
('20260602190000'),
('20260602183000'),
('20260602180000'),
('20260602173000'),
('20260602170000'),
('20260602161000'),
('20260602130000'),
('20260602110000'),
('20260602101000'),
('20260602100000'),
('20260602095000'),
('20260602094000'),
('20260602093000'),
('20260602090000'),
('20260531001100'),
('20260531001000'),
('20260529170200'),
('20260529170100'),
('20260529170000'),
('20260529155322'),
('20260529155321'),
('20260529155311'),
('20260529102000');

