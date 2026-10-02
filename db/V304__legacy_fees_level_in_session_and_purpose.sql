-- V304 — the old-portal fees import (V087, V301, V302) gets three things right.
--
--  1. LEVEL. A row with a blank amount is priced from the fee schedule. It was matched against the student's
--     CURRENT level, so a 400-level student's 2022/2023 payment was priced as 400-level. It now uses the level the
--     student was at in that session (reporting.level_in_session, V279), or the file's own Level column when given.
--
--  2. PURPOSE. The Note (or a Purpose) column says what the money was for: school fees, GST, hostel, and so on.
--     Every row used to be stored as "School fees (legacy)", and arrears and the registration gate count only
--     purposes that start "School fees" — so a GST payment cleared school-fee arrears. A row whose note names another
--     purpose is now stored under that purpose, and its reference carries the purpose, so a student's GST payment and
--     school fees for the same session are separate records, never duplicates of each other.
--     A blank note, or one that does not name another purpose, is school fees, exactly as before; a school-fees
--     reference is unchanged, so rows already imported are still recognised.
--
--  3. THE DATE THE STUDENT PAID. The paid date from the file is kept as the payment's date. It used to be read only
--     as an ISO date; anything else (13/03/2023, 13-Mar-2023, an Excel date serial) silently became the moment of the
--     import. finance.legacy_date reads those, day first. A row with no usable date still loads, dated today, and is
--     counted as "undated" so it can be fixed.
--
--  A row already on record is still skipped and reported, and its AMOUNT is never changed. The one exception is a
--  row imported earlier from the old portal (channel 'Legacy') that this file shows to be wrong in what it says, not
--  what it holds: the same amount under another purpose (relabelled, e.g. a GST payment that went in as school fees),
--  or the same record with the real paid date (the date is corrected). Those are counted as "corrected".

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V304: a GST category for imported payments', true);

INSERT INTO finance.payment_category (code, label, kinds, pattern, ord, revenue)
VALUES ('GST', 'General studies (GST) fee', '{}', '^gst', 85, true)
ON CONFLICT (code) DO NOTHING;

/* a date as the old portal wrote it: ISO, day-first 13/03/2023 or 13-03-2023, 13-Mar-2023, or an Excel date serial */
CREATE OR REPLACE FUNCTION finance.legacy_date(p text)
RETURNS timestamptz LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE t text := btrim(coalesce(p, '')); d date;
BEGIN
    IF t = '' THEN RETURN NULL; END IF;
    BEGIN
        IF t ~ '^[0-9]{5}(\.[0-9]+)?$' AND t::numeric BETWEEN 20000 AND 80000 THEN
            RETURN (date '1899-12-30' + floor(t::numeric)::int)::timestamp AT TIME ZONE 'UTC' + ((t::numeric - floor(t::numeric)) * interval '1 day');
        ELSIF t ~ '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}' THEN
            RETURN t::timestamptz;
        ELSIF t ~ '^[0-9]{1,2}[/.-][0-9]{1,2}[/.-][0-9]{4}' THEN
            d := to_date(substring(t from '^[0-9]{1,2}[/.-][0-9]{1,2}[/.-][0-9]{4}'), 'DD/MM/YYYY');
            RETURN d::timestamp AT TIME ZONE 'UTC';
        ELSIF t ~* '^[0-9]{1,2}[ -][a-z]{3,9}[ ,-]+[0-9]{4}' THEN
            RETURN t::date::timestamp AT TIME ZONE 'UTC';
        END IF;
        RETURN t::timestamptz;
    EXCEPTION WHEN OTHERS THEN RETURN NULL;
    END;
END $$;

DROP FUNCTION IF EXISTS finance.import_legacy_payments(jsonb);

CREATE FUNCTION finance.import_legacy_payments(p_rows jsonb)
RETURNS TABLE (rows int, cleared int, no_student int, no_due int, duplicates int, duplicate_sample text, corrected int, undated int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_session text; v_sem int; v_amount numeric; v_sid uuid; v_when timestamptz; v_given timestamptz;
        v_ref text; v_base text; v_rcpt text; v_key text; v_tag text; v_note text; v_cnt int;
        v_level int; v_text text; v_other boolean; v_slug text; st people.student; ex finance.payment_reference;
        n int := 0; nc int := 0; nns int := 0; nnd int := 0; nd int := 0; nfix int := 0; nund int := 0; v_dups text[] := '{}';
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

        SELECT * INTO st FROM people.student WHERE upper(matric_no) = v_matric OR upper(admission_no) = v_matric LIMIT 1;
        IF st.id IS NULL THEN nns := nns + 1; CONTINUE; END IF;
        v_sid := st.id;

        v_sem := nullif(regexp_replace(coalesce(r->>'semester', r->>'sem', ''), '[^0-9]', '', 'g'), '')::int;
        IF v_sem IS NOT NULL AND v_sem NOT IN (1, 2, 3) THEN v_sem := NULL; END IF;

        -- what the money was for: a Purpose column, else the Note; it is another purpose only when it names one
        v_text := btrim(coalesce(r->>'purpose', r->>'item', r->>'note', ''));
        v_other := v_text <> ''
                   AND v_text !~* '(school|tuition|semester fee|session fee)'
                   AND v_text ~* '(^|[^a-z])(gst|gns|general stud|hostel|accommodation|transcript|library|deferment|transfer|wallet|acceptance|application|post-?utme|screening|medical|id card|convocation|late registration|clearance|damage|fine)';
        v_slug := CASE WHEN v_other THEN left(regexp_replace(upper(v_text), '[^0-9A-Z]', '', 'g'), 20) END;

        v_key := replace(v_session, '/', '-') || CASE WHEN v_sem IS NOT NULL THEN '-S' || v_sem ELSE '' END;
        v_base := 'MOAUM-LEG-' || regexp_replace(v_matric, '[^0-9A-Z]', '', 'g') || '-' || v_key;   -- the school-fees reference
        v_ref := v_base || CASE WHEN v_other THEN '-' || v_slug ELSE '' END;

        -- the date the student paid, as the file gives it
        v_given := finance.legacy_date(coalesce(r->>'paidOn', r->>'paid_on', r->>'date'));
        v_amount := nullif(regexp_replace(coalesce(r->>'amount', r->>'amountPaid', r->>'paid', ''), '[^0-9.]', '', 'g'), '')::numeric;

        v_tag := CASE WHEN v_other THEN v_text ELSE 'School fees' END || ' (legacy)'
                 || CASE WHEN v_sem IS NOT NULL THEN ' · semester ' || v_sem ELSE '' END;

        -- already on record: skip and report; the amount is never touched
        SELECT * INTO ex FROM finance.payment_reference WHERE reference = v_ref;
        IF ex.id IS NOT NULL THEN
            IF ex.channel = 'Legacy' AND v_given IS NOT NULL AND ex.confirmed_at IS DISTINCT FROM v_given
               AND (v_amount IS NULL OR v_amount = ex.amount) THEN
                UPDATE finance.payment_reference SET confirmed_at = v_given, expires_at = v_given WHERE id = ex.id;
                nfix := nfix + 1;
            ELSE
                nd := nd + 1; v_dups := v_dups || v_ref;
            END IF;
            CONTINUE;
        END IF;

        -- the same amount already on record as school fees, but this row says it was for something else: relabel it
        IF v_other THEN
            SELECT * INTO ex FROM finance.payment_reference
             WHERE reference = v_base AND channel = 'Legacy' AND purpose LIKE 'School fees%'
               AND v_amount IS NOT NULL AND amount = v_amount;
            IF ex.id IS NOT NULL THEN
                v_when := coalesce(v_given, ex.confirmed_at);
                UPDATE finance.payment_reference
                   SET reference = v_ref, receipt_no = 'LEG-' || v_ref, purpose = v_tag, confirmed_at = v_when, expires_at = v_when,
                       note = coalesce(nullif(btrim(r->>'note'), ''), note)
                 WHERE id = ex.id;
                nfix := nfix + 1;
                CONTINUE;
            END IF;
        END IF;

        IF v_amount IS NULL THEN
            -- the level the student was at in THAT session, unless the file says
            v_level := nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int;
            IF v_level IS NULL OR v_level NOT IN (100, 200, 300, 400, 500, 600) THEN
                v_level := reporting.level_in_session(st.entry_level, st.entry_session, st.current_level, st.entry_mode, v_session);
            END IF;
            SELECT coalesce(sum(f.amount), 0) INTO v_amount
              FROM finance.fee_schedule f
              JOIN ref.programme p ON p.code = st.programme_code
             WHERE f.session = v_session AND f.ended_at IS NULL
               AND (f.level IS NULL OR f.level = v_level)
               AND (f.entry_mode IS NULL OR f.entry_mode = st.entry_mode)
               AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
               AND (f.programme_code IS NULL OR f.programme_code = st.programme_code)
               AND (v_sem IS NULL OR f.semester IS NULL OR f.semester = v_sem)
               AND CASE WHEN v_other THEN f.item ILIKE '%' || v_text || '%' ELSE f.item ILIKE 'school fee%' END;
        END IF;
        IF v_amount IS NULL OR v_amount <= 0 THEN nnd := nnd + 1; CONTINUE; END IF;

        v_when := v_given;
        IF v_when IS NULL THEN v_when := now(); nund := nund + 1; END IF;
        v_rcpt := 'LEG-' || v_ref;
        v_note := coalesce(nullif(btrim(r->>'note'), ''), 'Imported from the old portal');

        INSERT INTO finance.payment_reference
            (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
        VALUES (v_sid, v_session, v_ref, v_tag, v_amount, v_when, v_when, v_actor, 'Legacy', v_rcpt, v_note)
        ON CONFLICT (reference) DO NOTHING;
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
        IF v_cnt > 0 THEN nc := nc + 1; ELSE nd := nd + 1; END IF;
    END LOOP;

    RETURN QUERY SELECT n, nc, nns, nnd, nd, array_to_string(v_dups, ', '), nfix, nund;
END $$;

COMMIT;
