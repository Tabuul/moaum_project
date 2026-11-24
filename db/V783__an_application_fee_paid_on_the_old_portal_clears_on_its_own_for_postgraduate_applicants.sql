-- V783. A postgraduate application fee paid on the old portal clears on its own.
--
-- The University, 24 November 2026, on the application fees the School uploaded from the old portal (PG/26/000243–245, ₦20,000 each, an
-- Interswitch reference apiece): "clear them for application fee so they dont have to pay the pg application fee on the new portal
-- again", and, when asked whether an officer should still verify each one: "i have aready uploaded some .. that i need the system to
-- auto clear them".
--
-- What stood (V675). An application fee the old portal marked Verified was posted as paid at the import; one it marked only Paid was
-- held (admissions.pg_legacy_fee, REQUIRES_REVIEW) until the Bursary or the PG Secretary — never the officer who uploaded it —
-- verified it against the bank or the gateway. The applicant was not asked to pay meanwhile (PG_FEE_UNDER_REVIEW), and was not told
-- the fee was counted until an officer had looked.
--
-- What V783 does. A Paid APPLICATION fee clears on its own, at the import and for the ones already held, when the portal can check
-- everything it can check by itself (admissions.pg_application_fee_hold — one predicate, read by the import, by the dry run and by the
-- desk's list, so they cannot disagree):
--   · the old portal's own status word says it was paid (Paid, Successful, Success, Completed, Yes — the template offers Paid): a word
--     that says the fee is not verified, pending or awaiting verification, or requires review, is held for an officer;
--   · the amount reaches the application fee of the application's session (admissions.pg_fee_rule), so a part payment is held;
--   · the old reference is no other fee's — no postgraduate fee reference or other old-portal fee holds it (V675's clash), no officer
--     has rejected it on another application, and it is on none of the portal's other ledgers (an applicant's fee reference, a
--     preliminary applicant's old-portal fee, an inter-university transfer fee, a JUPEB fee, a student's payment or receipt);
--   · the applicant has not paid the application fee on another application of theirs in the session (V694's one fee a person) — the
--     dry run reads it for a new applicant from the row's own name, date of birth and phone, the import from the application it made;
--   · no application fee is confirmed on this portal for the application already (a second payment is still the Bursary's to settle).
-- Cleared is the same as verified: the fee is posted as a confirmed reference with the channel "Old portal" (admissions.pg_mig_post_fee,
-- unchanged), the application reads its fee as paid, and the applicant is not asked for it. The row is stamped decided by "system",
-- with the University's word of 24 November 2026 as its note; an event on the application (OLD_PORTAL_FEE_CLEARED); the import's row
-- note says "application fee cleared on its own" or "application fee held: <why>"; the applicant's once-only migration notice says the
-- fee is recorded; a fee cleared after the import (the ones already held, below) emails the applicant once with the event key an
-- officer's verification uses, so never twice. A fee that fails a check stays held, with its reason on the desk's Old-portal fees
-- tab, for an officer to verify or reject as before.
--
-- Not changed: a fee the old portal marked Verified is posted exactly as before (V675: no amount or reference test — the
-- uploader's word); acceptance fees are still held for the Bursary or the PG Secretary (the University named the application fee);
-- school fees are never posted here; an officer's verify and reject keep every rule. As before, no posted postgraduate fee has a
-- reversal door.
--
--   admissions.pg_application_fee_short(session, amount)     — NULL when the amount reaches the session's application fee, else why not
--   admissions.pg_application_fee_elsewhere(reference)       — NULL when no other ledger of the portal holds the reference, else which
--   admissions.pg_application_paid_by_person_of(session, surname, other names, date of birth, phone, except) and
--   admissions.pg_application_paid_by_person(application) — the number of another application of the same person that is paid
--                                                              (V694's two-of-three rule, found through the date of birth and the
--                                                              phone first: the whole-session scan of V694 costs ~0.3 s a call at
--                                                              3,000 applications and would cost an import ~75 s a chunk)
--   admissions.pg_application_fee_hold(app, session, ref, amount, status, the row's name, date of birth and phone)
--                                                            — NULL when the fee may clear on its own, else why it is held
--   admissions.pg_legacy_fee_clear_reason(fee)               — the same for a held fee row
--   admissions.pg_legacy_fee_autoclear(fee, notify)          — clears it when it may; returns whether it did
--   admissions.pg_legacy_fees_autoclear_held(notify)         — every held application fee in one pass: (cleared, held)
--   restated by text (each anchor asserted to occur once): admissions.pg_migration_apply (calls autoclear for a Paid application fee;
--   its row note says what happened to the fee), pg_migration_assess (the check warns only of a fee that will be held, and says why),
--   pg_legacy_list (the fees view gains hold_reason), pg_migration_columns (the template's help), pg_mig_tell (the once-only notice).
-- The new functions run set-based reads, so each carries SET jit = off as V782 does for the overpaid reading: CI's PostgreSQL 17 has JIT on, a
-- never-analysed database can make the planner put a statement above jit_above_cost, and a statement compiled for ten seconds a call would make an
-- import of a few hundred rows crawl.
-- Then the application fees already held are cleared once, with the email.
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V783: a postgraduate application fee paid on the old portal clears on its own', true);

-- ── 1 · the amount against the session's application fee ────────────────────────────────────────────────────────
CREATE FUNCTION admissions.pg_application_fee_short(p_session text, p_amount numeric)
RETURNS text
LANGUAGE plpgsql
STABLE
SET jit = off
AS $$
DECLARE v_fee numeric;
BEGIN
    IF p_session IS NULL OR p_amount IS NULL THEN RETURN NULL; END IF;
    SELECT x.application_fee INTO v_fee FROM admissions.pg_fee_rule(p_session) x LIMIT 1;
    IF v_fee IS NULL THEN
        RETURN 'no application fee is stated for ' || p_session;
    END IF;
    IF p_amount < v_fee THEN
        RETURN 'the amount, ₦' || to_char(p_amount, 'FM999,999,990') || ', is below the application fee of ₦' || to_char(v_fee, 'FM999,999,990');
    END IF;
    RETURN NULL;
END $$;

-- ── 2 · the reference on the portal's other ledgers ──────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.pg_application_fee_elsewhere(p_ref text)
RETURNS text
LANGUAGE sql
STABLE
SET jit = off
AS $$
    SELECT coalesce(
        (SELECT 'the fee reference of an undergraduate or preliminary application' || coalesce(' ' || ap.application_no, '')
           FROM admissions.fee_reference fr LEFT JOIN admissions.application ap ON ap.id = fr.application_id
          WHERE fr.reference IN (btrim(p_ref), upper(btrim(p_ref))) OR fr.receipt_no IN (btrim(p_ref), upper(btrim(p_ref))) LIMIT 1),
        (SELECT 'an old-portal preliminary fee already recorded' || coalesce(' for ' || ap.application_no, '')
           FROM admissions.prelim_legacy_fee x LEFT JOIN admissions.application ap ON ap.id = x.application_id
          WHERE (upper(btrim(x.legacy_reference)) = upper(btrim(p_ref)) OR upper(btrim(x.gateway_reference)) = upper(btrim(p_ref)))
            AND x.state <> 'REJECTED' LIMIT 1),
        (SELECT 'an inter-university transfer fee reference'
           FROM admissions.iut_fee_reference x
          WHERE x.reference IN (btrim(p_ref), upper(btrim(p_ref))) OR x.receipt_no IN (btrim(p_ref), upper(btrim(p_ref))) LIMIT 1),
        (SELECT 'a JUPEB fee reference' FROM jupeb.fee_reference x WHERE x.reference IN (btrim(p_ref), upper(btrim(p_ref))) LIMIT 1),
        (SELECT 'a payment reference of ' || coalesce(s.matric_no, s.admission_no, 'a student')
           FROM finance.payment_reference pr LEFT JOIN people.student s ON s.id = pr.student_id
          WHERE pr.reference IN (btrim(p_ref), upper(btrim(p_ref))) OR pr.receipt_no IN (btrim(p_ref), upper(btrim(p_ref))) LIMIT 1))
    WHERE nullif(btrim(coalesce(p_ref, '')), '') IS NOT NULL
$$;

-- ── 3 · the applicant's other application that is paid (V694's two of three: name, date of birth, phone) ────────────
CREATE FUNCTION admissions.pg_application_paid_by_person_of(p_session text, p_surname text, p_other_names text, p_dob date, p_phone text, p_except uuid DEFAULT NULL)
RETURNS text
LANGUAGE sql
STABLE
SET jit = off
AS $$
    WITH me AS (SELECT admissions.pg_name_key(p_surname, p_other_names) AS n, admissions.pg_phone_key(p_phone) AS ph),
         -- any two of the three agreeing means the date of birth or the phone agrees: those are looked for first (a stored phone is always
         -- 0 and ten digits, ck_pgapplicant_phone, so it is compared as it stands and its index is usable), and the name key is made for them only
         cand AS MATERIALIZED (
             SELECT a.application_no, p.surname, p.other_names, p.date_of_birth AS d, admissions.pg_phone_key(p.phone) AS ph
               FROM me JOIN admissions.pg_application a ON a.session = p_session AND a.id IS DISTINCT FROM p_except AND a.fee_confirmed_at IS NOT NULL
                       JOIN admissions.pg_applicant p ON p.id = a.applicant_id
              WHERE (p_dob IS NOT NULL AND p.date_of_birth = p_dob) OR (me.ph IS NOT NULL AND p.phone = me.ph))
    SELECT c.application_no
      FROM cand c CROSS JOIN me
     WHERE admissions.pg_same_person(admissions.pg_name_key(c.surname, c.other_names), c.d, c.ph, me.n, p_dob, me.ph)
     ORDER BY c.application_no LIMIT 1
$$;

CREATE FUNCTION admissions.pg_application_paid_by_person(p_app uuid)
RETURNS text
LANGUAGE sql
STABLE
SET jit = off
AS $$
    SELECT admissions.pg_application_paid_by_person_of(a.session, p.surname, p.other_names, p.date_of_birth, p.phone, a.id)
      FROM admissions.pg_application a JOIN admissions.pg_applicant p ON p.id = a.applicant_id WHERE a.id = p_app
$$;

-- ── 4 · why a fee is held, or NULL when it may clear on its own — one predicate for the import, the check and the desk ──
CREATE FUNCTION admissions.pg_application_fee_hold(p_app uuid, p_session text, p_ref text, p_amount numeric, p_status text DEFAULT NULL,
                                                   p_surname text DEFAULT NULL, p_other_names text DEFAULT NULL, p_dob date DEFAULT NULL, p_phone text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
STABLE
SET jit = off
AS $$
DECLARE v_session text := p_session; v_x text;
BEGIN
    IF p_app IS NOT NULL THEN
        SELECT coalesce(a.session, p_session) INTO v_session FROM admissions.pg_application a WHERE a.id = p_app;
    END IF;
    -- the old portal's own word: a status that says the fee is not verified, pending, awaiting verification or to be reviewed is not Paid
    IF nullif(btrim(coalesce(p_status, '')), '') IS NOT NULL
       AND upper(btrim(regexp_replace(p_status, '\s+', ' ', 'g'))) NOT IN ('PAID', 'SUCCESSFUL', 'SUCCESS', 'COMPLETED', 'YES') THEN
        RETURN 'the old portal''s status, "' || left(btrim(p_status), 40) || '", does not say the fee was paid';
    END IF;
    v_x := admissions.pg_application_fee_short(coalesce(v_session, p_session), p_amount);
    IF v_x IS NOT NULL THEN RETURN v_x; END IF;
    v_x := admissions.pg_mig_fee_clash('APPLICATION', p_ref, p_app, NULL);
    IF v_x IS NOT NULL THEN RETURN 'the reference is ' || v_x; END IF;
    SELECT 'the reference was rejected on ' || coalesce(a.application_no, 'another application') || ' (' || left(coalesce(x.decision_note, 'no note'), 120) || ')'
      INTO v_x
      FROM admissions.pg_legacy_fee x LEFT JOIN admissions.pg_application a ON a.id = x.application_id
     WHERE upper(btrim(x.legacy_reference)) = upper(btrim(p_ref)) AND x.state = 'REJECTED' AND x.application_id IS DISTINCT FROM p_app
     ORDER BY x.decided_at DESC NULLS LAST LIMIT 1;
    IF v_x IS NOT NULL THEN RETURN v_x; END IF;
    v_x := admissions.pg_application_fee_elsewhere(p_ref);
    IF v_x IS NOT NULL THEN RETURN 'the reference is ' || v_x; END IF;
    IF p_app IS NOT NULL THEN
        v_x := admissions.pg_application_paid_by_person(p_app);
    ELSIF p_surname IS NOT NULL THEN   -- a new applicant the dry run has no application for: the row's own name, date of birth and phone
        v_x := admissions.pg_application_paid_by_person_of(v_session, p_surname, p_other_names, p_dob, p_phone, NULL);
    END IF;
    IF v_x IS NOT NULL THEN
        RETURN 'the applicant has paid the application fee on another application of theirs in the session (' || v_x || ')';
    END IF;
    RETURN NULL;
END $$;

CREATE FUNCTION admissions.pg_legacy_fee_clear_reason(p_fee uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SET jit = off
AS $$
DECLARE f admissions.pg_legacy_fee; a admissions.pg_application;
BEGIN
    SELECT * INTO f FROM admissions.pg_legacy_fee WHERE id = p_fee;
    IF f.id IS NULL THEN RETURN 'no such old-portal fee'; END IF;
    IF f.state <> 'REQUIRES_REVIEW' THEN RETURN 'it is already ' || lower(replace(f.state, '_', ' ')); END IF;
    IF f.kind <> 'APPLICATION' THEN
        RETURN 'an acceptance fee is verified by the Bursary or the PG Secretary; only an application fee clears on its own';
    END IF;
    IF f.application_id IS NULL THEN RETURN 'it is not on an application'; END IF;
    SELECT * INTO a FROM admissions.pg_application WHERE id = f.application_id;
    IF a.id IS NULL THEN RETURN 'no such application'; END IF;
    IF a.fee_confirmed_at IS NOT NULL THEN
        RETURN 'an application fee is already confirmed on this portal for this application: the Bursary settles the second payment';
    END IF;
    RETURN admissions.pg_application_fee_hold(f.application_id, a.session, f.legacy_reference, f.amount, f.stated_status);
END $$;

-- ── 5 · clear it ────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.pg_legacy_fee_autoclear(p_fee uuid, p_notify boolean DEFAULT false)
RETURNS boolean
LANGUAGE plpgsql
SET jit = off
AS $$
DECLARE f admissions.pg_legacy_fee; a admissions.pg_application; p admissions.pg_applicant; v_prev text; v_note text;
BEGIN
    SELECT * INTO f FROM admissions.pg_legacy_fee WHERE id = p_fee FOR UPDATE;
    IF f.id IS NULL OR admissions.pg_legacy_fee_clear_reason(f.id) IS NOT NULL THEN RETURN false; END IF;
    SELECT * INTO a FROM admissions.pg_application WHERE id = f.application_id;
    v_prev := coalesce(current_setting('moaum.pg_migration', true), '');
    PERFORM set_config('moaum.pg_migration', 'fee cleared', true);
    PERFORM admissions.pg_mig_post_fee(f.id);
    PERFORM set_config('moaum.pg_migration', v_prev, true);
    v_note := format('Cleared on its own, the University''s word of 24 November 2026: the amount, ₦%s, reaches the application fee of %s, the reference %s is on no other ledger and no application fee was confirmed here.',
                     to_char(f.amount, 'FM999,999,990'), a.session, f.legacy_reference);
    UPDATE admissions.pg_legacy_fee SET decided_office = 'system', decided_at = now(), decision_note = v_note WHERE id = f.id;
    PERFORM admissions.pg_app_event(f.application_id, 'OLD_PORTAL_FEE_CLEARED',
            format('Application fee paid on the old portal (%s, ₦%s) cleared on its own.', f.legacy_reference, to_char(f.amount, 'FM999,999,990')));
    IF p_notify THEN
        SELECT * INTO p FROM admissions.pg_applicant WHERE id = a.applicant_id;
        PERFORM platform.queue_notice('EMAIL', p.email, 'Your application fee paid on the old portal is recorded',
                'Dear ' || p.other_names || ',' || E'\n\n' || 'The application fee you paid on the University''s old portal (reference ' || f.legacy_reference
                || ') is recorded on your application ' || a.application_no || '. You do not pay it again.'
                || E'\n\n' || 'School of Postgraduate Studies, Rev. Fr. Moses Orshio Adasu University, Makurdi',
                'pg_application', a.id, 'pg-fee-verified:' || f.id, NULL, 'NORMAL');
    END IF;
    RETURN true;
END $$;

-- every application fee held for review, in one pass (the migration runs it once; it is safe to run again)
CREATE FUNCTION admissions.pg_legacy_fees_autoclear_held(p_notify boolean DEFAULT true)
RETURNS TABLE(cleared integer, held integer)
LANGUAGE plpgsql
SET jit = off
AS $$
DECLARE r record; v_cleared integer := 0; v_held integer := 0;
BEGIN
    FOR r IN SELECT f.id FROM admissions.pg_legacy_fee f WHERE f.kind = 'APPLICATION' AND f.state = 'REQUIRES_REVIEW' ORDER BY f.created_at, f.id LOOP
        IF admissions.pg_legacy_fee_autoclear(r.id, p_notify) THEN v_cleared := v_cleared + 1; ELSE v_held := v_held + 1; END IF;
    END LOOP;
    RETURN QUERY SELECT v_cleared, v_held;
END $$;

-- ── 6 · the existing functions, edited by text and each anchor asserted ─────────────────────────────────────────
CREATE FUNCTION pg_temp.v783_edit(p_fn regprocedure, p_edits text[]) RETURNS void LANGUAGE plpgsql AS $$
DECLARE d text := pg_get_functiondef(p_fn); i integer; n integer;
BEGIN
    IF coalesce(array_length(p_edits, 1), 0) = 0 OR array_length(p_edits, 1) % 2 <> 0 THEN
        RAISE EXCEPTION 'V783: the edits of % come in pairs', p_fn;
    END IF;
    FOR i IN 1 .. array_length(p_edits, 1) / 2 LOOP
        n := (length(d) - length(replace(d, p_edits[2 * i - 1], ''))) / length(p_edits[2 * i - 1]);
        IF n <> 1 THEN
            RAISE EXCEPTION 'V783: % is not as main left it (% found % times)', p_fn, left(p_edits[2 * i - 1], 80), n;
        END IF;
        d := replace(d, p_edits[2 * i - 1], p_edits[2 * i]);
    END LOOP;
    EXECUTE d;
    IF pg_get_functiondef(p_fn) IS DISTINCT FROM d THEN
        RAISE EXCEPTION 'V783: % did not take its edit', p_fn;
    END IF;
END $$;

-- the import: a Paid application fee goes through the same clearing; a Verified one is posted as before; the row's note says what
-- became of the fee
SELECT pg_temp.v783_edit('admissions.pg_migration_apply(uuid,text)'::regprocedure, ARRAY[
$a$PERFORM admissions.pg_mig_post_fee(v_fee);$a$,
$b$PERFORM admissions.pg_mig_post_fee(v_fee);
            ELSIF v_status = 'CLAIMED' AND f.kind = 'APPLICATION' THEN
                -- V783: a Paid application fee clears on its own when the portal can check it; else it stays held
                PERFORM admissions.pg_legacy_fee_autoclear(v_fee, false);$b$,
$a$WHERE s.id = coalesce(v_student, (SELECT g.student_id FROM admissions.pg_application g WHERE g.id = v_app)))));$a$,
$b$WHERE s.id = coalesce(v_student, (SELECT g.student_id FROM admissions.pg_application g WHERE g.id = v_app))),
                                  (SELECT CASE WHEN z.state = 'POSTED' THEN 'application fee cleared on its own'
                                               ELSE 'application fee held: ' || coalesce(admissions.pg_legacy_fee_clear_reason(z.id), 'for an officer') END
                                     FROM admissions.pg_legacy_fee z
                                    WHERE z.batch_id = b.id AND z.row_id = r.id AND z.application_id = v_app AND z.kind = 'APPLICATION'
                                      AND (z.state = 'REQUIRES_REVIEW' OR z.decided_office = 'system') LIMIT 1)));$b$]);

-- the check: the warning is only for a fee that will be held, and says why (the application's own session, as the import reads it)
SELECT pg_temp.v783_edit('admissions.pg_migration_assess(uuid)'::regprocedure, ARRAY[
$a$ELSIF f.kind = 'APPLICATION' AND v_status = 'CLAIMED' THEN$a$,
$b$ELSIF f.kind = 'APPLICATION' AND v_status = 'CLAIMED' AND admissions.pg_application_fee_hold(v_app, v_session, v_ref, v_amt, admissions.pg_mig_t(d, f.status_key), CASE WHEN v_app IS NULL THEN v_surname END, CASE WHEN v_app IS NULL THEN v_given END, CASE WHEN v_app IS NULL THEN v_dob END, CASE WHEN v_app IS NULL THEN v_phone END) IS NOT NULL THEN$b$,
$a$'The application fee is not verified: held for the Bursary or the PG Secretary to verify; the applicant is not asked to pay it again meanwhile.', NULL);$a$,
$b$format('The application fee is held for the Bursary or the PG Secretary to verify (%s); the applicant is not asked to pay it again meanwhile.', admissions.pg_application_fee_hold(v_app, v_session, v_ref, v_amt, admissions.pg_mig_t(d, f.status_key), CASE WHEN v_app IS NULL THEN v_surname END, CASE WHEN v_app IS NULL THEN v_given END, CASE WHEN v_app IS NULL THEN v_dob END, CASE WHEN v_app IS NULL THEN v_phone END)), NULL);$b$]);

-- the desk's list of fees to settle: why each application fee on the page is held (worked out for the rows shown, not for every held fee)
SELECT pg_temp.v783_edit('admissions.pg_legacy_list(text,integer,integer)'::regprocedure, ARRAY[
$a$jsonb_agg(to_jsonb(y)) FROM (SELECT * FROM x ORDER BY x.state DESC, x.created_at DESC LIMIT lim OFFSET off) y$a$,
$b$jsonb_agg(to_jsonb(y) || jsonb_build_object('hold_reason', CASE WHEN y.state = 'REQUIRES_REVIEW' AND y.kind = 'APPLICATION' THEN admissions.pg_legacy_fee_clear_reason(y.id) END))
                                              FROM (SELECT * FROM x ORDER BY x.state DESC, x.created_at DESC LIMIT lim OFFSET off) y$b$]);

-- the template's help for the column
SELECT pg_temp.v783_edit('admissions.pg_migration_columns(text)'::regprocedure, ARRAY[
$a$'Verified (posted as paid), Paid (held for the Bursary to verify) or Unpaid.'$a$,
$b$'Verified (posted as paid), Paid (posted as paid too when the amount reaches the application fee and the reference is on no other ledger, else held for the Bursary to verify) or Unpaid.'$b$]);

-- the once-only notice: a fee cleared on its own is said to be recorded
SELECT pg_temp.v783_edit('admissions.pg_mig_tell(uuid)'::regprocedure, ARRAY[
$a$v_review boolean; v_first boolean; v_student_first boolean;$a$,
$b$v_review boolean; v_cleared boolean; v_first boolean; v_student_first boolean;$b$,
$a$v_review := EXISTS (SELECT 1 FROM admissions.pg_legacy_fee x WHERE x.application_id = p_app AND x.state = 'REQUIRES_REVIEW');$a$,
$b$v_review := EXISTS (SELECT 1 FROM admissions.pg_legacy_fee x WHERE x.application_id = p_app AND x.state = 'REQUIRES_REVIEW');
    v_cleared := EXISTS (SELECT 1 FROM admissions.pg_legacy_fee x WHERE x.application_id = p_app AND x.kind = 'APPLICATION' AND x.state = 'POSTED' AND x.decided_office = 'system');$b$,
$a$ELSE '' END || '.';$a$,
$b$WHEN v_cleared THEN ', and the application fee you paid on the old portal is recorded — you do not pay it again' ELSE '' END || '.';$b$]);

-- ── 7 · the application fees already held, cleared once ─────────────────────────────────────────────────────────
DO $v783$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM admissions.pg_legacy_fees_autoclear_held(true);
    RAISE NOTICE 'V783: % application fee(s) paid on the old portal cleared, % kept held for an officer', r.cleared, r.held;
END $v783$;

COMMIT;
