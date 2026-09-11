-- ═══════════════════════════════════════════════════════════════════════════
-- V087 — old students' school-fees history, from the old portal
--
--   A returning student migrated from the old portal owes every past session
--   the University has a fee schedule for, because the new portal knows only the
--   payments confirmed on it. This imports what a student already paid, per
--   session and (optionally) per semester, as a CONFIRMED school-fees payment,
--   so the past sessions settle and the arrears flag clears.
--
--   Each row: matriculation number, session, and either the amount paid or,
--   with the amount left blank, "cleared in full" — the importer then settles
--   the session (or the named semester) against its own fee schedule. A row is
--   idempotent on (student, session, semester): re-uploading updates, never
--   duplicates. Every write is attributed on the audit spine.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'bursar', true);
SELECT set_config('moaum.reason', 'Old students'' school-fees history from the old portal (V087)', true);

CREATE OR REPLACE FUNCTION finance.import_legacy_payments(p_rows jsonb)
RETURNS TABLE (rows int, cleared int, no_student int, no_due int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_session text; v_sem int; v_amount numeric; v_sid uuid; v_when timestamptz;
        v_ref text; v_rcpt text; v_key text; v_tag text; v_note text;
        n int := 0; nc int := 0; nns int := 0; nnd int := 0;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a legacy payment is recorded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the payments are rows: matriculation number, session, amount (or blank for cleared in full)' USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'regNo', '')));
        v_session := btrim(coalesce(r->>'session', ''));
        IF v_matric = '' OR v_session !~ '^[0-9]{4}/[0-9]{4}$' THEN CONTINUE; END IF;
        IF v_matric ~* '^matric' THEN CONTINUE; END IF;   -- a header row
        n := n + 1;

        SELECT id INTO v_sid FROM people.student WHERE upper(matric_no) = v_matric OR upper(admission_no) = v_matric LIMIT 1;
        IF v_sid IS NULL THEN nns := nns + 1; CONTINUE; END IF;

        v_sem := nullif(regexp_replace(coalesce(r->>'semester', r->>'sem', ''), '[^0-9]', '', 'g'), '')::int;
        IF v_sem IS NOT NULL AND v_sem NOT IN (1, 2, 3) THEN v_sem := NULL; END IF;

        v_amount := nullif(regexp_replace(coalesce(r->>'amount', r->>'amountPaid', r->>'paid', ''), '[^0-9.]', '', 'g'), '')::numeric;
        IF v_amount IS NULL THEN
            -- amount blank → cleared in full: settle against the student's own fee schedule for the session (+ semester)
            SELECT coalesce(sum(f.amount), 0) INTO v_amount
              FROM finance.fee_schedule f
              JOIN people.student s ON s.id = v_sid
              JOIN ref.programme p ON p.code = s.programme_code
             WHERE f.session = v_session AND f.ended_at IS NULL
               AND (f.level IS NULL OR f.level = s.current_level)
               AND (f.entry_mode IS NULL OR f.entry_mode = s.entry_mode)
               AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
               AND (f.programme_code IS NULL OR f.programme_code = s.programme_code)
               AND (v_sem IS NULL OR f.semester IS NULL OR f.semester = v_sem);
        END IF;
        IF v_amount IS NULL OR v_amount <= 0 THEN nnd := nnd + 1; CONTINUE; END IF;

        BEGIN v_when := (r->>'paidOn')::timestamptz;
        EXCEPTION WHEN OTHERS THEN
            BEGIN v_when := (r->>'date')::timestamptz; EXCEPTION WHEN OTHERS THEN v_when := now(); END;
        END;
        IF v_when IS NULL THEN v_when := now(); END IF;

        v_tag := 'School fees (legacy)' || CASE WHEN v_sem IS NOT NULL THEN ' · semester ' || v_sem ELSE '' END;
        v_key := replace(v_session, '/', '-') || CASE WHEN v_sem IS NOT NULL THEN '-S' || v_sem ELSE '' END;
        v_ref := 'MOAUM-LEG-' || regexp_replace(v_matric, '[^0-9A-Z]', '', 'g') || '-' || v_key;
        v_rcpt := 'LEG-' || v_ref;
        v_note := coalesce(nullif(btrim(r->>'note'), ''), 'Imported from the old portal');

        INSERT INTO finance.payment_reference
            (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
        VALUES (v_sid, v_session, v_ref, v_tag, v_amount, v_when, v_when, v_actor, 'Legacy', v_rcpt, v_note)
        ON CONFLICT (reference) DO UPDATE SET amount = EXCLUDED.amount, purpose = EXCLUDED.purpose,
            confirmed_at = EXCLUDED.confirmed_at, confirmed_by = EXCLUDED.confirmed_by, note = EXCLUDED.note;
        nc := nc + 1;
    END LOOP;

    RETURN QUERY SELECT n, nc, nns, nnd;
END $$;

COMMIT;
