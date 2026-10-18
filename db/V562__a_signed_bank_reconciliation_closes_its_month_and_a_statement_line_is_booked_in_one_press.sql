-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V562 — A signed bank reconciliation closes its month on the ledger; a statement line is booked in one press
--
--   1 · A bank reconciliation signed (V557) closes its month on the ledger for its account: no journal moving 1010 or 1020 is
--       posted with a date in it any more (finance.gl_post refuses a hand-posted one, LEDGER_MONTH_CLOSED, and a posting is refused
--       by a trigger whatever posts it). What the ledger posts by itself for a closed month — a payment, a refund or a withdrawal
--       recorded late with an earlier date — is posted on the first open day after it, its memo saying so (finance.gl_open_date).
--       The month is reopened only on a reason given by one officer of the Bursary and approved by another
--       (finance.request_reconciliation_reopen, finance.decide_reconciliation_reopen), only the latest signed month of an account,
--       and the reconciliation goes back to prepared, the signed copy kept with the request.
--   2 · A statement line is booked in one press: posted against the account the Bursary names (5250 Bank charges, added here, for
--       the bank's charges and a gateway's) and tied to the journal at once (finance.book_statement_line_to); a transfer between
--       the two accounts is booked from its debit on one statement and its credit on the other, both tied to the one journal
--       (finance.book_transfer), the pairs of equal amount within three days offered (finance.transfer_candidates). A line booked
--       so and taken back has its journal reversed.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V562: a signed month closed on the ledger; a statement line booked in one press', true);

-- ── 1 · the month closed on the ledger ───────────────────────────────────────────────────────────────────────────────────
/* the signed reconciliation of an account that holds a day, if any */
CREATE FUNCTION finance.gl_closed_by(p_account text, p_date date)
RETURNS finance.bank_reconciliation LANGUAGE sql STABLE AS $fn$
    SELECT r.* FROM finance.bank_reconciliation r
     WHERE r.state = 'SIGNED' AND r.account = p_account AND p_date BETWEEN r.period_from AND r.period_to
     LIMIT 1
$fn$;

/* the first day on or after the one given that no signed reconciliation of the accounts holds */
CREATE FUNCTION finance.gl_open_date(p_date date, p_accounts text[])
RETURNS date LANGUAGE plpgsql STABLE AS $fn$
DECLARE d date := p_date; v_to date;
BEGIN
    LOOP
        SELECT max(r.period_to) INTO v_to FROM finance.bank_reconciliation r
         WHERE r.state = 'SIGNED' AND r.account = ANY (p_accounts) AND d BETWEEN r.period_from AND r.period_to;
        EXIT WHEN v_to IS NULL;
        d := v_to + 1;
    END LOOP;
    RETURN d;
END $fn$;
COMMENT ON FUNCTION finance.gl_open_date(date, text[]) IS
  'V562: the day itself, or the first day after the months closed on the ledger for any of the accounts by a signed bank reconciliation.';

/* a journal posted (V145): V562 — one dated in a month closed for one of its accounts is refused when posted by hand and posted on
   the first open day when the ledger posts it by itself */
CREATE OR REPLACE FUNCTION finance.gl_post(
    p_date date, p_memo text, p_source text, p_source_type text, p_source_ref text, p_lines jsonb
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid; v_line jsonb; i int := 0; v_date date := coalesce(p_date, current_date); v_open date; v_memo text := p_memo;
        v_accounts text[]; v_closed finance.bank_reconciliation;
BEGIN
    IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) < 2 THEN
        RAISE EXCEPTION 'A journal needs at least two lines';
    END IF;
    -- only where a signed month of a bank account holds the date (none, mostly: a cheap test before anything else)
    IF EXISTS (SELECT 1 FROM finance.bank_reconciliation b WHERE b.state = 'SIGNED' AND v_date BETWEEN b.period_from AND b.period_to) THEN
        SELECT array_agg(DISTINCT btrim(x->>'account')) INTO v_accounts FROM jsonb_array_elements(p_lines) x WHERE btrim(x->>'account') IN ('1010', '1020');
    END IF;
    IF v_accounts IS NOT NULL THEN
        v_open := finance.gl_open_date(v_date, v_accounts);
        IF v_open <> v_date THEN
            IF coalesce(p_source, 'MANUAL') = 'AUTO' THEN
                v_memo := p_memo || ' (of ' || to_char(v_date, 'FMDD FMMon YYYY') || ', a month closed on the ledger)';
                v_date := v_open;
            ELSE
                SELECT c.* INTO v_closed FROM unnest(v_accounts) a CROSS JOIN LATERAL finance.gl_closed_by(a, v_date) c WHERE c.id IS NOT NULL LIMIT 1;
                RAISE EXCEPTION 'LEDGER_MONTH_CLOSED: % to % is closed on the ledger for % by its signed bank reconciliation; date the journal % or later',
                    to_char(v_closed.period_from, 'FMDD FMMonth YYYY'), to_char(v_closed.period_to, 'FMDD FMMonth YYYY'), v_closed.account,
                    to_char(v_open, 'FMDD FMMonth YYYY') USING ERRCODE = '23514',
                    HINT = 'A month is reopened on a reason approved by a second officer of the Bursary (Accounting, Closed months).';
            END IF;
        END IF;
    END IF;
    INSERT INTO finance.gl_journal (entry_date, memo, source, source_type, source_ref, posted_by)
    VALUES (v_date, v_memo, coalesce(p_source,'MANUAL'), p_source_type, p_source_ref,
            nullif(current_setting('moaum.actor_id', true), '')::uuid)
    RETURNING id INTO v_id;

    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
        i := i + 1;
        INSERT INTO finance.gl_posting (journal_id, line, account, debit, credit, narration, session, fund)
        VALUES (v_id, i, btrim(v_line->>'account'),
                round(coalesce((v_line->>'debit')::numeric, 0), 2),
                round(coalesce((v_line->>'credit')::numeric, 0), 2),
                nullif(btrim(coalesce(v_line->>'narration','')), ''),
                nullif(btrim(coalesce(v_line->>'session','')), ''),
                nullif(btrim(coalesce(v_line->>'fund','')), ''));
    END LOOP;
    RETURN v_id;   -- the deferred trigger checks the balance at commit
END $$;

/* whatever posts it, a posting to 1010 or 1020 dated in a month closed for it is refused, and none is taken away (the trigger
   fires for those two accounts only, and reads the closed months directly: it runs for every posting the ledger makes) */
CREATE FUNCTION finance.gl_posting_month_open() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE v_account text; v_journal uuid; v_date date;
BEGIN
    IF TG_OP = 'DELETE' THEN v_account := OLD.account; v_journal := OLD.journal_id; ELSE v_account := NEW.account; v_journal := NEW.journal_id; END IF;
    SELECT j.entry_date INTO v_date FROM finance.gl_journal j
     WHERE j.id = v_journal
       AND EXISTS (SELECT 1 FROM finance.bank_reconciliation b WHERE b.state = 'SIGNED' AND b.account = v_account AND j.entry_date BETWEEN b.period_from AND b.period_to);
    IF v_date IS NOT NULL THEN
        RAISE EXCEPTION 'LEDGER_MONTH_CLOSED: % is in a month closed on the ledger for % by its signed bank reconciliation', to_char(v_date, 'FMDD FMMonth YYYY'), v_account
            USING ERRCODE = '23514';
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $fn$;
CREATE TRIGGER trg_gl_posting_month_open BEFORE INSERT ON finance.gl_posting
    FOR EACH ROW WHEN (NEW.account IN ('1010', '1020')) EXECUTE FUNCTION finance.gl_posting_month_open();
CREATE TRIGGER trg_gl_posting_month_kept BEFORE DELETE ON finance.gl_posting
    FOR EACH ROW WHEN (OLD.account IN ('1010', '1020')) EXECUTE FUNCTION finance.gl_posting_month_open();

/* nor is a journal moving 1010 or 1020 moved into or out of a closed month, or taken away from one */
CREATE FUNCTION finance.gl_journal_month_open() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF EXISTS (SELECT 1 FROM finance.gl_posting p WHERE p.journal_id = OLD.id AND p.account IN ('1010', '1020')
                     AND (finance.gl_closed_by(p.account, OLD.entry_date)).id IS NOT NULL) THEN
            RAISE EXCEPTION 'LEDGER_MONTH_CLOSED: journal #% is in a month closed on the ledger and is not taken away', OLD.journal_no USING ERRCODE = '23514';
        END IF;
        RETURN OLD;
    END IF;
    IF NEW.entry_date IS DISTINCT FROM OLD.entry_date AND EXISTS (
           SELECT 1 FROM finance.gl_posting p WHERE p.journal_id = OLD.id AND p.account IN ('1010', '1020')
              AND ((finance.gl_closed_by(p.account, OLD.entry_date)).id IS NOT NULL OR (finance.gl_closed_by(p.account, NEW.entry_date)).id IS NOT NULL)) THEN
        RAISE EXCEPTION 'LEDGER_MONTH_CLOSED: journal #% is not moved into or out of a month closed on the ledger', OLD.journal_no USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_gl_journal_month_open BEFORE UPDATE OF entry_date OR DELETE ON finance.gl_journal
    FOR EACH ROW EXECUTE FUNCTION finance.gl_journal_month_open();

-- ── the month reopened ───────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.bank_reconciliation_reopen (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reconciliation_id uuid NOT NULL REFERENCES finance.bank_reconciliation(id),
    account           text NOT NULL,
    period_from       date NOT NULL,
    period_to         date NOT NULL,
    reason            text NOT NULL CHECK (btrim(reason) <> ''),
    state             text NOT NULL DEFAULT 'REQUESTED' CHECK (state IN ('REQUESTED', 'APPROVED', 'REJECTED')),
    requested_by      uuid NOT NULL,
    requested_at      timestamptz NOT NULL DEFAULT now(),
    decided_by        uuid NULL,
    decided_at        timestamptz NULL,
    decision_note     text NULL,
    signed_copy       jsonb NULL
);
CREATE UNIQUE INDEX ux_brec_reopen_pending ON finance.bank_reconciliation_reopen (reconciliation_id) WHERE state = 'REQUESTED';
SELECT audit.attach('finance.bank_reconciliation_reopen');
COMMENT ON TABLE finance.bank_reconciliation_reopen IS
  'V562: a signed month of 1010 or 1020 asked to be reopened on a reason, approved or rejected by another officer of the Bursary; the signed reconciliation as it was kept with an approved request.';

/* a signed reconciliation is kept as signed (V557) — V562: unless a second officer has approved reopening it */
CREATE OR REPLACE FUNCTION finance.bank_reconciliation_kept() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
    IF OLD.state = 'SIGNED' AND NOT (TG_OP = 'UPDATE' AND NEW.state = 'DRAFT' AND current_setting('moaum.reconciliation_reopen', true) = 'on') THEN
        RAISE EXCEPTION 'RECON_SIGNED: the reconciliation of % for % to % is signed and kept as it was signed', OLD.account,
            to_char(OLD.period_from, 'FMDD FMMonth YYYY'), to_char(OLD.period_to, 'FMDD FMMonth YYYY') USING ERRCODE = '23514';
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $fn$;

/* one officer asks for the latest signed month of an account to be reopened, with the reason */
CREATE FUNCTION finance.request_reconciliation_reopen(p_reconciliation uuid, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; r finance.bank_reconciliation; v_id uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a reopening is asked for by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM finance.bank_reconciliation WHERE id = p_reconciliation FOR UPDATE;
    IF r.id IS NULL OR r.state <> 'SIGNED' THEN
        RAISE EXCEPTION 'RECON_REOPEN_NOT_SIGNED: only a signed reconciliation closes a month, and only one is reopened' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM finance.bank_reconciliation l WHERE l.account = r.account AND l.state = 'SIGNED' AND l.period_from > r.period_to) THEN
        RAISE EXCEPTION 'RECON_REOPEN_LATER: a later month of % is signed; the latest is reopened first', r.account USING ERRCODE = '23514';
    END IF;
    IF btrim(coalesce(p_reason, '')) = '' THEN RAISE EXCEPTION 'RECON_REOPEN_REASON: say why the month is reopened' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM finance.bank_reconciliation_reopen q WHERE q.reconciliation_id = r.id AND q.state = 'REQUESTED') THEN
        RAISE EXCEPTION 'RECON_REOPEN_PENDING: reopening this month is already asked for' USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.bank_reconciliation_reopen (reconciliation_id, account, period_from, period_to, reason, requested_by)
    VALUES (r.id, r.account, r.period_from, r.period_to, btrim(p_reason), v_actor) RETURNING id INTO v_id;
    RETURN v_id;
END $fn$;
COMMENT ON FUNCTION finance.request_reconciliation_reopen(uuid, text) IS
  'V562: the latest signed month of 1010 or 1020 asked to be reopened, with the reason; another officer of the Bursary decides.';

/* another officer approves (the month is open again, the reconciliation back to prepared, its signed copy kept) or rejects */
CREATE FUNCTION finance.decide_reconciliation_reopen(p_request uuid, p_approve boolean, p_note text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; q finance.bank_reconciliation_reopen; r finance.bank_reconciliation;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a reopening is decided by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO q FROM finance.bank_reconciliation_reopen WHERE id = p_request FOR UPDATE;
    IF q.id IS NULL OR q.state <> 'REQUESTED' THEN RAISE EXCEPTION 'RECON_REOPEN_DECIDED: the request is not waiting for a decision' USING ERRCODE = '23514'; END IF;
    IF q.requested_by = v_actor THEN
        RAISE EXCEPTION 'RECON_REOPEN_SAME_OFFICER: the officer who asked for the month to be reopened does not decide it' USING ERRCODE = '23514',
            HINT = 'Another officer of the Bursary decides it.';
    END IF;
    IF NOT coalesce(p_approve, false) THEN
        IF btrim(coalesce(p_note, '')) = '' THEN RAISE EXCEPTION 'RECON_REOPEN_NOTE: say why the month stays closed' USING ERRCODE = '23514'; END IF;
        UPDATE finance.bank_reconciliation_reopen SET state = 'REJECTED', decided_by = v_actor, decided_at = now(), decision_note = btrim(p_note) WHERE id = q.id;
        RETURN;
    END IF;
    SELECT * INTO r FROM finance.bank_reconciliation WHERE id = q.reconciliation_id FOR UPDATE;
    IF EXISTS (SELECT 1 FROM finance.bank_reconciliation l WHERE l.account = r.account AND l.state = 'SIGNED' AND l.period_from > r.period_to) THEN
        RAISE EXCEPTION 'RECON_REOPEN_LATER: a later month of % is signed; the latest is reopened first', r.account USING ERRCODE = '23514';
    END IF;
    UPDATE finance.bank_reconciliation_reopen SET state = 'APPROVED', decided_by = v_actor, decided_at = now(), decision_note = nullif(btrim(coalesce(p_note, '')), ''),
           signed_copy = to_jsonb(r) WHERE id = q.id;
    PERFORM set_config('moaum.reconciliation_reopen', 'on', true);
    UPDATE finance.bank_reconciliation SET state = 'DRAFT', signed_by = NULL, signed_at = NULL, items = NULL,
           note = concat_ws(E'\n', r.note, 'Reopened: ' || q.reason) WHERE id = r.id;
    PERFORM set_config('moaum.reconciliation_reopen', 'off', true);
END $fn$;
COMMENT ON FUNCTION finance.decide_reconciliation_reopen(uuid, boolean, text) IS
  'V562: a request to reopen a signed month decided by an officer other than the one who asked — approved, the month is open on the ledger again and the reconciliation prepared, not signed, its signed copy kept with the request; rejected, on a note.';

-- ── 2 · a statement line booked in one press ─────────────────────────────────────────────────────────────────────────────
INSERT INTO finance.gl_account (code, name, type, normal_side, parent_code, postable, active, ord)
SELECT '5250', 'Bank charges', 'EXPENSE', a.normal_side, '5200', true, true, 65
  FROM finance.gl_account a WHERE a.code = '5230'
ON CONFLICT (code) DO NOTHING;

/* a line open to booking: in no signed month of its account, not yet accounted for */
CREATE FUNCTION finance.statement_line_for_booking(p_line uuid)
RETURNS finance.bank_statement_line LANGUAGE plpgsql AS $fn$
DECLARE l finance.bank_statement_line; s finance.bank_statement; v_account text;
BEGIN
    SELECT * INTO l FROM finance.bank_statement_line WHERE id = p_line FOR UPDATE;
    IF l.id IS NULL THEN RAISE EXCEPTION 'no statement line %', p_line USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO s FROM finance.bank_statement WHERE id = l.statement_id;
    v_account := finance.bank_account_of(s.account_kind);
    IF (finance.gl_closed_by(v_account, coalesce(l.value_date, s.period_to))).id IS NOT NULL THEN
        RAISE EXCEPTION 'RECON_SIGNED_PERIOD: line % falls in a signed reconciliation of %', l.line_no, v_account USING ERRCODE = '23514';
    END IF;
    IF l.ledger_journal IS NOT NULL THEN
        RAISE EXCEPTION 'LINE_ALREADY_BOOKED: line % is accounted for already; take it back first', l.line_no USING ERRCODE = '23514';
    END IF;
    IF l.status IN ('MATCHED', 'RECEIVED_NOT_CONFIRMED') OR l.matched_kind = 'NELFUND' THEN
        RAISE EXCEPTION 'LINE_NOT_FOR_JOURNAL: a line matched to the portal or to a remittance, or one the portal is to confirm, is not booked with a journal' USING ERRCODE = '23514';
    END IF;
    RETURN l;
END $fn$;

/* the reference of a journal booked for a line: the line's own, numbered again when an earlier one was taken back and reversed */
CREATE FUNCTION finance.bank_line_journal_ref(p_type text, p_ref text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN n = 0 THEN p_ref ELSE p_ref || '#' || (n + 1) END
      FROM (SELECT count(*) AS n FROM finance.gl_journal j WHERE j.source_type = p_type AND (j.source_ref = p_ref OR j.source_ref LIKE p_ref || '#%')) x
$fn$;

/* a line booked against the account the Bursary names and tied to the journal at once: money out Dr the account, Cr the bank; money
   in Dr the bank, Cr the account; a gateway's day or an amount that differs, the difference */
CREATE FUNCTION finance.book_statement_line_to(p_line uuid, p_account text, p_note text)
RETURNS bigint LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; l finance.bank_statement_line; s finance.bank_statement;
        v_bank text; v_out numeric; v_amount numeric; v_journal uuid; v_date date; v_memo text; v_ref text;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a line is booked by a person' USING ERRCODE = '23514'; END IF;
    l := finance.statement_line_for_booking(p_line);
    SELECT * INTO s FROM finance.bank_statement WHERE id = l.statement_id;
    v_bank := finance.bank_account_of(s.account_kind);
    IF btrim(coalesce(p_note, '')) = '' THEN RAISE EXCEPTION 'LINE_JOURNAL_NOTE: say what the journal records for the line' USING ERRCODE = '23514'; END IF;
    IF p_account IN ('1010', '1020') OR NOT EXISTS (SELECT 1 FROM finance.gl_account a WHERE a.code = p_account AND a.postable AND a.active) THEN
        RAISE EXCEPTION 'LINE_BOOK_ACCOUNT: % is not an account a line is booked against (a transfer between the bank accounts is booked as a transfer)', p_account
            USING ERRCODE = '23514';
    END IF;
    -- what left the bank (positive) or came into it (negative) that the ledger does not hold
    v_out := CASE WHEN l.status = 'SETTLEMENT' THEN l.expected_amount - l.credit
                  WHEN l.status = 'AMOUNT_DIFFERS' AND s.account_kind = 'COLLECTIONS' THEN l.expected_amount - l.credit
                  WHEN l.status = 'AMOUNT_DIFFERS' THEN l.debit - l.expected_amount
                  WHEN l.debit > 0 THEN l.debit
                  ELSE -l.credit END;
    v_amount := abs(coalesce(v_out, 0));
    IF v_amount = 0 THEN RAISE EXCEPTION 'LINE_NOTHING_TO_BOOK: line % leaves nothing to book', l.line_no USING ERRCODE = '23514'; END IF;
    v_date := coalesce(l.value_date, s.period_to);
    v_memo := btrim(p_note) || ' — ' || s.label || ', line ' || l.line_no;
    v_ref := finance.bank_line_journal_ref('BANK_LINE', 'LINE-' || l.id);
    v_journal := finance.gl_post(v_date, v_memo, 'MANUAL', 'BANK_LINE', v_ref, jsonb_build_array(
        jsonb_build_object('account', CASE WHEN v_out > 0 THEN p_account ELSE v_bank END, 'debit', v_amount, 'narration', btrim(p_note)),
        jsonb_build_object('account', CASE WHEN v_out > 0 THEN v_bank ELSE p_account END, 'credit', v_amount, 'narration', btrim(p_note))));
    UPDATE finance.bank_statement_line SET ledger_journal = v_journal, booked_by = v_actor, booked_at = now(), booked_note = btrim(p_note) WHERE id = l.id;
    RETURN (SELECT j.journal_no FROM finance.gl_journal j WHERE j.id = v_journal);
END $fn$;
COMMENT ON FUNCTION finance.book_statement_line_to(uuid, text, text) IS
  'V562: a statement line booked in one press against the account named (money out Dr the account, Cr the bank; money in the reverse; a gateway''s day or an amount that differs, the difference), dated the line''s day, and tied to the journal.';

/* a transfer between the bank accounts booked from its two lines: the debit on one statement, the credit on the other */
CREATE FUNCTION finance.book_transfer(p_out uuid, p_in uuid, p_note text)
RETURNS bigint LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; o finance.bank_statement_line; i finance.bank_statement_line;
        so finance.bank_statement; si finance.bank_statement; v_journal uuid; v_date date;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a transfer is booked by a person' USING ERRCODE = '23514'; END IF;
    o := finance.statement_line_for_booking(p_out);
    i := finance.statement_line_for_booking(p_in);
    SELECT * INTO so FROM finance.bank_statement WHERE id = o.statement_id;
    SELECT * INTO si FROM finance.bank_statement WHERE id = i.statement_id;
    IF so.account_kind = si.account_kind OR o.debit <= 0 OR i.credit <= 0 OR o.status NOT IN ('DEBIT', 'UNMATCHED') OR i.status NOT IN ('CREDIT', 'UNMATCHED') THEN
        RAISE EXCEPTION 'TRANSFER_LINES: a transfer is booked from a debit on one account''s statement and a credit on the other''s' USING ERRCODE = '23514';
    END IF;
    IF o.debit <> i.credit THEN
        RAISE EXCEPTION 'TRANSFER_AMOUNTS: NGN % left one account and NGN % reached the other', to_char(o.debit, 'FM999,999,999,990.00'), to_char(i.credit, 'FM999,999,999,990.00')
            USING ERRCODE = '23514';
    END IF;
    IF abs(coalesce(o.value_date, so.period_to) - coalesce(i.value_date, si.period_to)) > 3 THEN
        RAISE EXCEPTION 'TRANSFER_DATES: the two lines are more than three days apart' USING ERRCODE = '23514';
    END IF;
    IF btrim(coalesce(p_note, '')) = '' THEN RAISE EXCEPTION 'LINE_JOURNAL_NOTE: say what the transfer was for' USING ERRCODE = '23514'; END IF;
    v_date := coalesce(o.value_date, so.period_to);
    v_journal := finance.gl_post(v_date, 'Transfer from ' || finance.bank_account_of(so.account_kind) || ' to ' || finance.bank_account_of(si.account_kind) || ' — ' || btrim(p_note),
        'MANUAL', 'BANK_TRANSFER', finance.bank_line_journal_ref('BANK_TRANSFER', 'TRANSFER-' || o.id), jsonb_build_array(
            jsonb_build_object('account', finance.bank_account_of(si.account_kind), 'debit', o.debit, 'narration', btrim(p_note)),
            jsonb_build_object('account', finance.bank_account_of(so.account_kind), 'credit', o.debit, 'narration', btrim(p_note))));
    UPDATE finance.bank_statement_line SET ledger_journal = v_journal, booked_by = v_actor, booked_at = now(), booked_note = btrim(p_note) WHERE id IN (o.id, i.id);
    RETURN (SELECT j.journal_no FROM finance.gl_journal j WHERE j.id = v_journal);
END $fn$;
COMMENT ON FUNCTION finance.book_transfer(uuid, uuid, text) IS
  'V562: a transfer between 1010 and 1020 booked from its debit on one account''s statement and its credit on the other''s (the same amount, within three days): Dr the account it reached, Cr the one it left, both lines tied to the journal.';

/* the transfers the statements show and no one has booked: a debit on one account and a credit of the same amount on the other,
   within three days, in a span */
CREATE FUNCTION finance.transfer_candidates(p_from date, p_to date)
RETURNS TABLE (out_line uuid, out_account text, out_day date, out_text text, in_line uuid, in_account text, in_day date, in_text text, amount numeric)
LANGUAGE sql STABLE AS $fn$
    WITH x AS (
        SELECT l.id, finance.bank_account_of(s.account_kind) AS account, coalesce(l.value_date, s.period_to) AS d, l.debit, l.credit, l.status,
               concat_ws(' · ', nullif(btrim(coalesce(l.reference, '')), ''), l.description, s.label || ', line ' || l.line_no) AS txt
          FROM finance.bank_statement_line l JOIN finance.bank_statement s ON s.id = l.statement_id
         WHERE l.ledger_journal IS NULL AND coalesce(l.value_date, s.period_to) BETWEEN p_from - 3 AND p_to + 3)
    SELECT o.id, o.account, o.d, o.txt, i.id, i.account, i.d, i.txt, o.debit
      FROM x o JOIN x i ON i.account <> o.account AND i.credit = o.debit AND abs(i.d - o.d) <= 3
     WHERE o.debit > 0 AND o.status IN ('DEBIT', 'UNMATCHED') AND i.credit > 0 AND i.status IN ('CREDIT', 'UNMATCHED')
       AND (o.d BETWEEN p_from AND p_to OR i.d BETWEEN p_from AND p_to)
       AND (finance.gl_closed_by(o.account, o.d)).id IS NULL AND (finance.gl_closed_by(i.account, i.d)).id IS NULL
     ORDER BY o.d, o.debit DESC
$fn$;
COMMENT ON FUNCTION finance.transfer_candidates(date, date) IS
  'V562: the pairs the statements show and no one has booked — a debit on one bank account and a credit of the same amount on the other within three days — offered to be booked as transfers.';

/* a line accounted for with a journal (V557) — V562: one booked in one press and taken back has its journal reversed on its own day,
   and a transfer's other line is taken back with it */
CREATE OR REPLACE FUNCTION finance.book_statement_line(p_line uuid, p_journal_no bigint, p_note text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; l finance.bank_statement_line; s finance.bank_statement;
        j finance.gl_journal; v_account text; t finance.gl_journal; x record; v_new uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a line is accounted for by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO l FROM finance.bank_statement_line WHERE id = p_line FOR UPDATE;
    IF l.id IS NULL THEN RAISE EXCEPTION 'no statement line %', p_line USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO s FROM finance.bank_statement WHERE id = l.statement_id;
    v_account := finance.bank_account_of(s.account_kind);
    IF EXISTS (SELECT 1 FROM finance.bank_reconciliation r WHERE r.account = v_account AND r.state = 'SIGNED'
                AND coalesce(l.value_date, s.period_to) BETWEEN r.period_from AND r.period_to) THEN
        RAISE EXCEPTION 'RECON_SIGNED_PERIOD: line % falls in a signed reconciliation of %', l.line_no, v_account USING ERRCODE = '23514';
    END IF;
    IF p_journal_no IS NULL THEN
        SELECT * INTO t FROM finance.gl_journal WHERE id = l.ledger_journal;
        IF t.id IS NOT NULL AND t.source_type IN ('BANK_LINE', 'BANK_TRANSFER') THEN
            -- the journal booked for it in one press is reversed, and every line tied to it taken back
            FOR x IN SELECT bl.id, bl.line_no, bs.label, finance.bank_account_of(bs.account_kind) AS account, coalesce(bl.value_date, bs.period_to) AS d
                       FROM finance.bank_statement_line bl JOIN finance.bank_statement bs ON bs.id = bl.statement_id WHERE bl.ledger_journal = t.id LOOP
                IF (finance.gl_closed_by(x.account, x.d)).id IS NOT NULL THEN
                    RAISE EXCEPTION 'RECON_SIGNED_PERIOD: line % of % falls in a signed reconciliation of %', x.line_no, x.label, x.account USING ERRCODE = '23514';
                END IF;
            END LOOP;
            UPDATE finance.bank_statement_line SET ledger_journal = NULL, booked_by = NULL, booked_at = NULL, booked_note = NULL WHERE ledger_journal = t.id;
            IF t.status = 'POSTED' THEN
                -- reversed on its own day, so the booking and its reversal cancel within the month
                v_new := finance.gl_post(t.entry_date, 'Reversal of #' || t.journal_no || ' — taken back from ' || s.label || ', line ' || l.line_no, 'MANUAL', 'REVERSAL', t.id::text,
                    (SELECT jsonb_agg(jsonb_build_object('account', p.account, 'debit', p.credit, 'credit', p.debit, 'narration', p.narration, 'session', p.session, 'fund', p.fund) ORDER BY p.line)
                       FROM finance.gl_posting p WHERE p.journal_id = t.id));
                UPDATE finance.gl_journal SET reverses = t.id WHERE id = v_new;
                UPDATE finance.gl_journal SET status = 'REVERSED' WHERE id = t.id;
            END IF;
        ELSE
            UPDATE finance.bank_statement_line SET ledger_journal = NULL, booked_by = NULL, booked_at = NULL, booked_note = NULL WHERE id = l.id;
        END IF;
        RETURN;
    END IF;
    IF l.status IN ('MATCHED', 'RECEIVED_NOT_CONFIRMED') THEN
        RAISE EXCEPTION 'LINE_NOT_FOR_JOURNAL: a line matched to the portal, or one the portal is to confirm, is not accounted for with a journal' USING ERRCODE = '23514';
    END IF;
    IF btrim(coalesce(p_note, '')) = '' THEN RAISE EXCEPTION 'LINE_JOURNAL_NOTE: say what the journal records for the line' USING ERRCODE = '23514'; END IF;
    SELECT * INTO j FROM finance.gl_journal WHERE journal_no = p_journal_no;
    IF j.id IS NULL OR j.status <> 'POSTED' THEN
        RAISE EXCEPTION 'LINE_JOURNAL: journal #% is not a posted journal', p_journal_no USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM finance.gl_posting p WHERE p.journal_id = j.id AND p.account = v_account) THEN
        RAISE EXCEPTION 'LINE_JOURNAL_ACCOUNT: journal #% does not move %, the account of this statement', p_journal_no, v_account USING ERRCODE = '23514';
    END IF;
    UPDATE finance.bank_statement_line SET ledger_journal = j.id, booked_by = v_actor, booked_at = now(), booked_note = btrim(p_note) WHERE id = l.id;
END $fn$;

COMMIT;
