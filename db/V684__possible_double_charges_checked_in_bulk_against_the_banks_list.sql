-- ═══════════════════════════════════════
-- V684 — Possible bank double charges checked in bulk against the bank's list of payments received
--
--   The University's word of 28 October 2026 ("yes, build the bulk version"), after Old Fees History was asked how duplicates in
--   the legacy payment history are removed by the fee, the payment number, the JAMB number and the matriculation number. A payment
--   number already on record is refused at the upload whichever number the row names (V498, V647), so no number is on two
--   payments; what stays is V561's possible double charge — one student, session, item, Lagos day and amount under two or more
--   of the old portal's payment numbers (148 groups of 2025/2026, ₦6.6m beyond the first payment, on the copy of 21 October
--   2026). Only the bank can say whether both payments arrived, and V561 asked it one group at a time.
--
--   1 · finance.bank_list_match(session, from, to, numbers): the possible double charges of the session (every session when NULL)
--       set against the payment numbers on the bank's or the gateway's list of payments received — read, nothing written. A group
--       not yet checked and paid within the days the list covers is
--         RECEIVED      every payment number of it is on the list;
--         NOT_RECEIVED  at least one is on the list and at least one is not (those not on it never reached the University);
--         NONE_FOUND    none is on the list: the list says nothing about the day, the group stays for a check by hand;
--         AMOUNT_SHORT  a number is on the list for less than the record holds: left for a check by hand;
--         NO_NUMBER     a record of it carries no payment number to look for: left for a check by hand;
--       and CHECKED (checked already, or a withdrawal waits) or OUTSIDE_PERIOD otherwise.
--   2 · finance.bank_list_apply: a Bursary officer records the list (BLC/YYYY/NNNNNN, on evidence): each RECEIVED and
--       NOT_RECEIVED group gets V561's check (finance.double_charge_check, marked with the list), and each record of a NOT_RECEIVED
--       group not on the list is raised for withdrawal (finance.propose_not_received, PNR/…) beside the record of the same day that
--       is. A group whose withdrawal V561 refuses (several payments in one record, linked, swapped, its excess already decided) is
--       left unchecked and named. Kept with every group judged; nothing is withdrawn yet.
--   3 · finance.decide_bank_list: another Bursary officer approves (or rejects, with a note) every withdrawal the list raised that
--       still waits, each through finance.decide_not_received (archived, never deleted — V670; its number remembered; the student
--       told); the officer who recorded the list cancels them. Each withdrawal stands or falls on its own.
--   4 · finance.check_double_charge (V561) restated: a check made again by hand replaces the list's mark.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V684: possible bank double charges checked in bulk against the bank''s list of payments received', true);

-- ── 1 · the lists and the groups each judged ─────────────────────────────────────────────────────────────────────────────
CREATE SEQUENCE finance.bank_list_check_seq;
CREATE TABLE finance.bank_list_check (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    list_ref      text NOT NULL UNIQUE CHECK (list_ref ~ '^BLC/[0-9]{4}/[0-9]{6}$'),
    session       text NULL CHECK (session IS NULL OR session ~ '^[0-9]{4}/[0-9]{4}$'),
    covers_from   date NOT NULL,
    covers_to     date NOT NULL,
    file_name     text NULL,
    rows_read     int  NOT NULL DEFAULT 0 CHECK (rows_read >= 0),
    numbers_read  int  NOT NULL CHECK (numbers_read >= 1),
    with_amounts  boolean NOT NULL DEFAULT false,
    evidence      text NOT NULL CHECK (length(btrim(evidence)) >= 5),
    note          text NULL,
    outcomes      jsonb NOT NULL DEFAULT '{}'::jsonb,
    checked_by    uuid NOT NULL,
    actor_office  text NULL,
    checked_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_blc_period CHECK (covers_from <= covers_to)
);
CREATE INDEX ix_bank_list_check_at ON finance.bank_list_check (checked_at DESC);
COMMENT ON TABLE finance.bank_list_check IS
  'V684: a bank''s or gateway''s list of payments received, set by a Bursary officer against the possible double charges of the days it covers (BLC/YYYY/NNNNNN); its groups are on finance.bank_list_group.';
SELECT audit.attach('finance.bank_list_check');

CREATE TABLE finance.bank_list_group (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    list_id     uuid NOT NULL REFERENCES finance.bank_list_check(id),
    student_id  uuid NOT NULL,
    session     text NOT NULL,
    purpose     text NOT NULL,
    paid_on     date NOT NULL,
    amount      numeric(14,2) NOT NULL,
    refs        text[] NOT NULL,
    payrefs     text[] NOT NULL,
    outcome     text NOT NULL CHECK (outcome IN ('RECEIVED', 'NOT_RECEIVED', 'NONE_FOUND', 'AMOUNT_SHORT', 'NO_NUMBER', 'CHECKED', 'REFUSED')),
    found       text[] NOT NULL DEFAULT '{}',
    missing     text[] NOT NULL DEFAULT '{}',
    check_id    uuid NULL,
    raised      text[] NOT NULL DEFAULT '{}',
    refusal     text NULL
);
CREATE INDEX ix_bank_list_group_list ON finance.bank_list_group (list_id);
CREATE INDEX ix_bank_list_group_raised ON finance.bank_list_group USING gin (raised);
COMMENT ON TABLE finance.bank_list_group IS
  'V684: each possible double charge a bank list judged — what the list showed (found, missing), the check recorded, the withdrawals raised, or why V561 refused them — written once.';
SELECT audit.attach('finance.bank_list_group');

-- what a list judged is kept as it was: a group is written once, and neither a group nor a list is removed (but by the go-live
-- reset, moaum.maintenance); a list's outcome counts are written when it is recorded
CREATE FUNCTION finance.bank_list_kept()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF coalesce(current_setting('moaum.maintenance', true), '') <> 'on' THEN
            RAISE EXCEPTION 'BANK_LIST_KEPT: what a bank list judged is kept' USING ERRCODE = '23514';
        END IF;
        RETURN OLD;
    END IF;
    IF TG_TABLE_NAME = 'bank_list_group'
       OR (to_jsonb(NEW) - 'outcomes') IS DISTINCT FROM (to_jsonb(OLD) - 'outcomes') THEN
        RAISE EXCEPTION 'BANK_LIST_KEPT: what a bank list judged is kept as it was recorded' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_bank_list_check_kept BEFORE UPDATE OR DELETE ON finance.bank_list_check
    FOR EACH ROW EXECUTE FUNCTION finance.bank_list_kept();
CREATE TRIGGER trg_bank_list_group_kept BEFORE UPDATE OR DELETE ON finance.bank_list_group
    FOR EACH ROW EXECUTE FUNCTION finance.bank_list_kept();

ALTER TABLE finance.double_charge_check ADD COLUMN bank_list_id uuid NULL REFERENCES finance.bank_list_check(id);
CREATE INDEX ix_double_charge_check_list ON finance.double_charge_check (bank_list_id) WHERE bank_list_id IS NOT NULL;
COMMENT ON COLUMN finance.double_charge_check.bank_list_id IS
  'V684: the bank list the check was recorded from; cleared when the check is made again by hand.';

-- ── 2 · the list set against the possible double charges ─────────────────────────────────────────────────────────────────
-- the payment numbers a list sends — {"n": number, "a": amount} or a bare number — written as the old portal keeps them: upper
-- case, no spaces; an amount only where it reads as one
CREATE FUNCTION finance.bank_list_numbers(p_numbers jsonb)
RETURNS TABLE (n text, amount numeric)
LANGUAGE sql IMMUTABLE AS $$
    SELECT t.n, CASE WHEN t.a ~ '^[0-9]+(\.[0-9]+)?$' THEN t.a::numeric END
      FROM (SELECT upper(regexp_replace(CASE jsonb_typeof(e) WHEN 'string' THEN e #>> '{}' WHEN 'object' THEN coalesce(e->>'n', '') ELSE '' END, '\s+', '', 'g')) AS n,
                   CASE jsonb_typeof(e) WHEN 'object' THEN btrim(replace(coalesce(e->>'a', ''), ',', '')) ELSE '' END AS a
              FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_numbers) = 'array' THEN p_numbers ELSE '[]'::jsonb END) e) t
     WHERE t.n <> ''
$$;

CREATE FUNCTION finance.bank_list_match(p_session text, p_from date, p_to date, p_numbers jsonb)
RETURNS TABLE (student_id uuid, number text, name text, programme_code text, session text, purpose text, paid_on date, amount numeric, payments int,
               refs text[], payrefs text[], outcome text, found text[], missing text[])
LANGUAGE sql STABLE AS $$
    WITH b AS MATERIALIZED (SELECT x.n, max(x.amount) AS amount FROM finance.bank_list_numbers(p_numbers) x GROUP BY x.n),
    d AS MATERIALIZED (SELECT * FROM finance.possible_double_charges(p_session)),
    -- each record of each group, and whether its payment number is on the list (and for how much)
    r AS (SELECT d.student_id, d.session, d.purpose, d.paid_on, d.amount, u.ref, u.payref, b.n IS NOT NULL AS hit, b.amount AS bank_amount
            FROM d CROSS JOIN LATERAL unnest(d.refs, d.payrefs) AS u(ref, payref)
            LEFT JOIN b ON b.n = u.payref AND u.payref <> ''),
    a AS (SELECT r.student_id, r.session, r.purpose, r.paid_on, r.amount,
                 coalesce(array_agg(r.ref ORDER BY r.ref) FILTER (WHERE r.hit), '{}') AS found,
                 coalesce(array_agg(r.ref ORDER BY r.ref) FILTER (WHERE NOT r.hit), '{}') AS missing,
                 coalesce(bool_or(r.hit AND r.bank_amount IS NOT NULL AND r.bank_amount < r.amount - 1), false) AS short
            FROM r GROUP BY r.student_id, r.session, r.purpose, r.paid_on, r.amount)
    SELECT d.student_id, d.number, d.name, d.programme_code, d.session, d.purpose, d.paid_on, d.amount, d.payments, d.refs, d.payrefs,
           CASE WHEN d.verdict IS NOT NULL OR d.open_requests > 0 THEN 'CHECKED'
                WHEN d.paid_on < p_from OR d.paid_on > p_to THEN 'OUTSIDE_PERIOD'
                WHEN '' = ANY (d.payrefs) THEN 'NO_NUMBER'
                WHEN cardinality(a.found) = 0 THEN 'NONE_FOUND'
                WHEN a.short THEN 'AMOUNT_SHORT'
                WHEN cardinality(a.missing) = 0 THEN 'RECEIVED'
                ELSE 'NOT_RECEIVED' END,
           a.found, a.missing
      FROM d
      JOIN a ON a.student_id = d.student_id AND a.session = d.session AND a.purpose = d.purpose AND a.paid_on = d.paid_on AND a.amount = d.amount
$$;
COMMENT ON FUNCTION finance.bank_list_match(text, date, date, jsonb) IS
  'V684: the possible double charges of the session (every session when NULL) set against a bank list of payment numbers received — read, nothing written.';

-- what a list must say before it is set against anything
CREATE FUNCTION finance.bank_list_validate(p_session text, p_from date, p_to date, p_numbers jsonb)
RETURNS void
LANGUAGE plpgsql STABLE AS $$
DECLARE v_n int;
BEGIN
    IF nullif(btrim(coalesce(p_session, '')), '') IS NOT NULL AND btrim(p_session) !~ '^[0-9]{4}/[0-9]{4}$' THEN
        RAISE EXCEPTION 'BANK_LIST_SESSION: a session is written YYYY/YYYY (or left out for every session)' USING ERRCODE = '23514';
    END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_from > p_to THEN
        RAISE EXCEPTION 'BANK_LIST_PERIOD: say the first and the last day of the payments the list covers' USING ERRCODE = '23514';
    END IF;
    IF p_to > (now() AT TIME ZONE 'Africa/Lagos')::date THEN
        RAISE EXCEPTION 'BANK_LIST_PERIOD: a list of payments received cannot cover days still to come' USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO v_n FROM finance.bank_list_numbers(p_numbers);
    IF v_n = 0 THEN
        RAISE EXCEPTION 'BANK_LIST_EMPTY: the list names no payment number' USING ERRCODE = '23514';
    END IF;
    IF v_n > 300000 THEN
        RAISE EXCEPTION 'BANK_LIST_TOO_LONG: % payment numbers; send a list of at most 300,000 (a shorter period)', v_n USING ERRCODE = '23514';
    END IF;
END $$;

-- what recording the list would do — read, nothing written
CREATE FUNCTION finance.bank_list_preview(p_session text, p_from date, p_to date, p_numbers jsonb)
RETURNS TABLE (student_id uuid, number text, name text, programme_code text, session text, purpose text, paid_on date, amount numeric, payments int,
               refs text[], payrefs text[], outcome text, found text[], missing text[])
LANGUAGE plpgsql STABLE AS $$
BEGIN
    PERFORM finance.bank_list_validate(p_session, p_from, p_to, p_numbers);
    RETURN QUERY SELECT * FROM finance.bank_list_match(nullif(btrim(coalesce(p_session, '')), ''), p_from, p_to, p_numbers);
END $$;
COMMENT ON FUNCTION finance.bank_list_preview(text, date, date, jsonb) IS
  'V684: the possible double charges of the session (every session when NULL) set against a bank list of payment numbers received: RECEIVED, NOT_RECEIVED (found and missing named), NONE_FOUND, AMOUNT_SHORT, NO_NUMBER, CHECKED or OUTSIDE_PERIOD — read, nothing written.';

-- ── 3 · the list recorded ────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.bank_list_apply(p_session text, p_from date, p_to date, p_numbers jsonb, p_evidence text, p_note text,
                                        p_file text DEFAULT NULL, p_rows int DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := finance.bursary_actor(); office text := nullif(current_setting('moaum.actor_office', true), '');
        v_ses text := nullif(btrim(coalesce(p_session, '')), ''); v_id uuid := gen_random_uuid(); v_ref text; v_n int; v_amounts boolean;
        v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_ev text; v_reason text; v_kept text; x text;
        g record; v_check uuid; v_raised text[]; v_outcome text; v_refusal text; v_counts jsonb := '{}'::jsonb;
        v_recorded int := 0; v_raised_n int := 0; v_raised_amount numeric := 0;
BEGIN
    PERFORM finance.bank_list_validate(v_ses, p_from, p_to, p_numbers);
    IF length(btrim(coalesce(p_evidence, ''))) < 5 THEN
        RAISE EXCEPTION 'BANK_LIST_EVIDENCE: name the list — the bank''s statement or the gateway''s report, and the days it covers' USING ERRCODE = '23514';
    END IF;
    SELECT count(DISTINCT bn.n), coalesce(bool_or(bn.amount IS NOT NULL), false) INTO v_n, v_amounts FROM finance.bank_list_numbers(p_numbers) bn;
    v_ref := 'BLC/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('finance.bank_list_check_seq')::text, 6, '0');
    PERFORM set_config('moaum.reason', left('Bank list ' || v_ref || ' set against the possible double charges — ' || btrim(p_evidence), 2000), true);
    INSERT INTO finance.bank_list_check (id, list_ref, session, covers_from, covers_to, file_name, rows_read, numbers_read, with_amounts, evidence, note,
                                         checked_by, actor_office)
    VALUES (v_id, v_ref, v_ses, p_from, p_to, nullif(left(btrim(coalesce(p_file, '')), 200), ''), greatest(coalesce(p_rows, v_n), 0), v_n, v_amounts,
            btrim(p_evidence), v_note, who, office);
    v_ev := left(btrim(p_evidence), 440) || ' (bank list ' || v_ref || ')';

    FOR g IN SELECT * FROM finance.bank_list_match(v_ses, p_from, p_to, p_numbers) m ORDER BY m.name, m.paid_on, m.purpose LOOP
        v_outcome := g.outcome; v_refusal := NULL; v_raised := '{}'; v_check := NULL;
        IF g.outcome IN ('RECEIVED', 'NOT_RECEIVED') THEN
            BEGIN
                INSERT INTO finance.double_charge_check (student_id, session, purpose, paid_on, amount, verdict, evidence, note, not_received, checked_by,
                                                         actor_office, bank_list_id)
                VALUES (g.student_id, g.session, g.purpose, g.paid_on, g.amount, g.outcome, v_ev, v_note,
                        CASE WHEN g.outcome = 'NOT_RECEIVED' THEN g.missing ELSE '{}' END, who, office, v_id)
                ON CONFLICT (student_id, session, purpose, paid_on, amount) DO NOTHING
                RETURNING id INTO v_check;
                IF v_check IS NULL THEN
                    v_outcome := 'CHECKED';   -- checked by hand while the list was read
                ELSIF g.outcome = 'NOT_RECEIVED' THEN
                    v_kept := g.found[1];
                    v_reason := 'Not on the bank''s list ' || v_ref || ' of payments received from ' || to_char(p_from, 'DD Mon YYYY') || ' to '
                                || to_char(p_to, 'DD Mon YYYY') || '; ' || v_kept || ' of the same day is on it';
                    FOREACH x IN ARRAY g.missing LOOP
                        v_raised := v_raised || finance.propose_not_received(x, v_ev, v_reason, v_check, v_kept);
                    END LOOP;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                -- V561 refuses the withdrawal (several payments in one record, linked, swapped, the excess decided): the group is left
                -- unchecked, the reason kept
                v_outcome := 'REFUSED'; v_refusal := left(split_part(SQLERRM, ':', 1), 80); v_check := NULL; v_raised := '{}';
            END;
            IF v_outcome IN ('RECEIVED', 'NOT_RECEIVED') THEN
                v_recorded := v_recorded + 1;
                v_raised_n := v_raised_n + cardinality(v_raised);
                v_raised_amount := v_raised_amount + g.amount * cardinality(v_raised);
            END IF;
        END IF;
        -- the groups the list judged (one checked by hand meanwhile among them); not those checked before it or outside its days
        IF g.outcome NOT IN ('OUTSIDE_PERIOD', 'CHECKED') THEN
            INSERT INTO finance.bank_list_group (list_id, student_id, session, purpose, paid_on, amount, refs, payrefs, outcome, found, missing, check_id, raised, refusal)
            VALUES (v_id, g.student_id, g.session, g.purpose, g.paid_on, g.amount, g.refs, g.payrefs, v_outcome, g.found, g.missing, v_check, v_raised, v_refusal);
        END IF;
        v_counts := jsonb_set(v_counts, ARRAY[v_outcome], to_jsonb(coalesce((v_counts->>v_outcome)::int, 0) + 1));
    END LOOP;

    IF v_recorded = 0 THEN
        RAISE EXCEPTION 'BANK_LIST_NOTHING_TO_RECORD: the list settles no possible double charge of those days — none has a payment number on it beside one that is not, or all of them on it'
            USING ERRCODE = '23514', HINT = 'Look at the preview: a list that names none of a day''s payments says nothing about that day.';
    END IF;
    UPDATE finance.bank_list_check
       SET outcomes = v_counts || jsonb_build_object('raised', v_raised_n, 'raised_amount', v_raised_amount)
     WHERE id = v_id;
    RETURN v_ref;
END $$;
COMMENT ON FUNCTION finance.bank_list_apply(text, date, date, jsonb, text, text, text, int) IS
  'V684: a Bursary officer records a bank list (BLC/YYYY/NNNNNN): each possible double charge of the days it covers whose payment numbers are all on it is checked RECEIVED; one with some on it and some not is checked NOT_RECEIVED and each record not on it raised for withdrawal (PNR/…) for another officer to approve; the rest are left for a check by hand, every group judged kept.';

-- ── 4 · the withdrawals a list raised, decided together ──────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.decide_bank_list(p_list text, p_action text, p_note text)
RETURNS TABLE (done int, refused int, refusals text[])
LANGUAGE plpgsql AS $$
DECLARE who uuid := finance.bursary_actor(); l finance.bank_list_check; v_action text := upper(btrim(coalesce(p_action, '')));
        v_note text := nullif(btrim(coalesce(p_note, '')), ''); w record; nd int := 0; nr int := 0; v_refusals text[] := '{}';
BEGIN
    SELECT * INTO l FROM finance.bank_list_check WHERE list_ref = upper(btrim(coalesce(p_list, ''))) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'BANK_LIST_NONE: no bank list %', p_list USING ERRCODE = '23514'; END IF;
    IF v_action NOT IN ('APPROVE', 'REJECT', 'CANCEL') THEN
        RAISE EXCEPTION 'BANK_LIST_ACTION: the withdrawals a list raised are approved, rejected or cancelled' USING ERRCODE = '23514';
    END IF;
    IF v_action IN ('APPROVE', 'REJECT') AND l.checked_by = who THEN
        RAISE EXCEPTION 'BANK_LIST_SAME_OFFICER: another Bursary officer decides the withdrawals of the list you recorded' USING ERRCODE = '42501';
    END IF;
    IF v_action = 'CANCEL' AND l.checked_by <> who THEN
        RAISE EXCEPTION 'BANK_LIST_NOT_YOURS: only the officer who recorded a list cancels its withdrawals; another officer rejects them' USING ERRCODE = '42501';
    END IF;
    IF v_action = 'REJECT' AND (v_note IS NULL OR length(v_note) < 5) THEN
        RAISE EXCEPTION 'BANK_LIST_NOTE: say why the withdrawals are rejected' USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', left('Withdrawals of bank list ' || l.list_ref || ' ' || lower(v_action) || 'd' || coalesce(' — ' || v_note, ''), 2000), true);
    FOR w IN SELECT q.request_ref FROM finance.payment_not_received q
              WHERE q.state = 'PROPOSED'
                AND q.request_ref IN (SELECT unnest(g.raised) FROM finance.bank_list_group g WHERE g.list_id = l.id)
              ORDER BY q.request_ref LOOP
        BEGIN
            IF v_action = 'CANCEL' THEN PERFORM finance.cancel_not_received(w.request_ref);
            ELSE PERFORM finance.decide_not_received(w.request_ref, v_action = 'APPROVE', coalesce(v_note, 'With bank list ' || l.list_ref));
            END IF;
            nd := nd + 1;
        EXCEPTION WHEN OTHERS THEN
            nr := nr + 1;
            v_refusals := v_refusals || (w.request_ref || ': ' || left(split_part(SQLERRM, ':', 1), 80));
        END;
    END LOOP;
    IF nd + nr = 0 THEN
        RAISE EXCEPTION 'BANK_LIST_NOTHING_WAITING: no withdrawal raised by % waits for a decision', l.list_ref USING ERRCODE = '23514';
    END IF;
    RETURN QUERY SELECT nd, nr, v_refusals;
END $$;
COMMENT ON FUNCTION finance.decide_bank_list(text, text, text) IS
  'V684: every withdrawal a bank list raised that still waits, approved or rejected (with a note) by another Bursary officer, or cancelled by the one who recorded the list — each through V561''s own decision (archived, never deleted), each standing or falling on its own.';

-- ── 5 · a check made again by hand is the officer's, not the list's ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.check_double_charge(p_student uuid, p_session text, p_purpose text, p_paid_on date, p_amount numeric,
                                                       p_verdict text, p_evidence text, p_note text, p_not_received text[])
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE who uuid := finance.bursary_actor(); office text := nullif(current_setting('moaum.actor_office', true), '');
        d record; v_id uuid; v_verdict text := upper(btrim(coalesce(p_verdict, ''))); v_list text[] := coalesce(p_not_received, '{}'); x text;
BEGIN
    IF v_verdict NOT IN ('RECEIVED', 'NOT_RECEIVED') THEN
        RAISE EXCEPTION 'PAY_CHECK_VERDICT: the bank either received every payment (RECEIVED) or not all of them (NOT_RECEIVED)' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_evidence, ''))) < 5 THEN
        RAISE EXCEPTION 'PAY_CHECK_EVIDENCE: name the evidence — the bank statement and its date, or the gateway''s report' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO d FROM finance.possible_double_charges(p_session) g
     WHERE g.student_id = p_student AND g.purpose = p_purpose AND g.paid_on = p_paid_on AND g.amount = round(p_amount);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PAY_CHECK_NOT_LISTED: those payments are not a possible double charge (any more)' USING ERRCODE = '23514';
    END IF;
    IF d.open_requests > 0 THEN
        RAISE EXCEPTION 'PAY_CHECK_OPEN_REQUEST: a withdrawal of one of these payments waits for approval; decide or cancel it first' USING ERRCODE = '23514';
    END IF;
    v_list := ARRAY(SELECT DISTINCT upper(btrim(y)) FROM unnest(v_list) y WHERE btrim(y) <> '');
    IF v_verdict = 'RECEIVED' AND cardinality(v_list) > 0 THEN
        RAISE EXCEPTION 'PAY_CHECK_NOT_RECEIVED_LIST: payments the bank received are not withdrawn' USING ERRCODE = '23514';
    END IF;
    IF v_verdict = 'NOT_RECEIVED' AND (cardinality(v_list) = 0 OR cardinality(v_list) >= d.payments
                                       OR EXISTS (SELECT 1 FROM unnest(v_list) y WHERE NOT (y = ANY (d.refs)))) THEN
        RAISE EXCEPTION 'PAY_CHECK_NOT_RECEIVED_LIST: name the records of this group the bank did not receive — at least one, and not all' USING ERRCODE = '23514',
            HINT = 'When the bank received none of them, withdraw each on its own from Payments not received.';
    END IF;
    PERFORM set_config('moaum.reason', left('Bank check of a possible double charge: ' || v_verdict || ' — ' || btrim(p_evidence), 2000), true);
    INSERT INTO finance.double_charge_check (student_id, session, purpose, paid_on, amount, verdict, evidence, note, not_received, checked_by, actor_office)
    VALUES (p_student, d.session, d.purpose, d.paid_on, d.amount, v_verdict, btrim(p_evidence), nullif(btrim(coalesce(p_note, '')), ''), v_list, who, office)
    ON CONFLICT (student_id, session, purpose, paid_on, amount) DO UPDATE SET
        verdict = EXCLUDED.verdict, evidence = EXCLUDED.evidence, note = EXCLUDED.note, not_received = EXCLUDED.not_received,
        checked_by = EXCLUDED.checked_by, actor_office = EXCLUDED.actor_office, checked_at = now(),
        bank_list_id = NULL   -- V684: checked again by hand
    RETURNING id INTO v_id;
    FOREACH x IN ARRAY v_list LOOP
        PERFORM finance.propose_not_received(x, p_evidence,
            coalesce(nullif(btrim(coalesce(p_note, '')), ''), 'The bank shows this payment never arrived; the other payment of the same day stands'), v_id,
            (SELECT min(y) FROM unnest(d.refs) y WHERE NOT (y = ANY (v_list))));
    END LOOP;
    RETURN v_id;
END $$;
COMMENT ON FUNCTION finance.check_double_charge(uuid, text, text, date, numeric, text, text, text, text[]) IS
  'V561, V684: a Bursary officer records what the bank shows for a possible double charge — RECEIVED, or NOT_RECEIVED naming the records that did not arrive (at least one did), each then raised for withdrawal on the same evidence; a check made again by hand is no longer the bank list''s.';

COMMIT;
