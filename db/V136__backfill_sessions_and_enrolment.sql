-- ═══════════════════════════════════════════════════════════════════════════
-- V136 — backfill: sessions from every import, and match students to the
--        current session
--
--   Two gaps in the historical re-upload:
--
--   1. The results importer already ensures the session/semesters exist and
--      reconstructs the enrolment, registration and score from each result row
--      (assessment.import_legacy_semester). The PAYMENT importer did not — a
--      payment for 2023/2024 left no 2023/2024 session on record. Now it calls
--      assessment.ensure_session for any real YYYY/YYYY session on a row, so a
--      session a student only ever paid into still becomes a real session with
--      its two semesters. Rows with no session (labelled 'LEGACY') are left as
--      they were.
--
--   2. Nothing put a student into the session they are in now. people.enrol_
--      current_session(session) ensures the session exists and enrols every
--      matriculated, currently-studying student (ACTIVE or PROBATION) into it
--      at their current level — so after the re-upload the Registry runs it once
--      and the whole cohort is matched to the current session. Idempotent: a
--      student already enrolled for the session is left alone.
--
--   Both run as the caller (the same broad role the other importers use) inside
--   the request's audit context. The bulk enrolment insert disables the
--   people.enrolment audit trigger around itself — a one-shot backfill of a
--   whole cohort is not per-row audit material — exactly as V123 does for the
--   registration backfill.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. payment importer, now creating the session it is told about ──────────
CREATE OR REPLACE FUNCTION finance.import_payments(p_rows jsonb)
RETURNS TABLE (rows int, imported int, duplicate int, no_student int, bad_amount int, skipped int, first_error text)
LANGUAGE plpgsql AS $$
DECLARE r jsonb;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_student uuid; v_session text; v_amount numeric; v_purpose text;
        v_date date; v_channel text; v_ref text; v_receipt text; v_note text; v_cnt int;
        n int := 0; ni int := 0; nd int := 0; nns int := 0; nba int := 0; ns int := 0; v_firsterr text := NULL;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a payment history is loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, session, amount, purpose, date' USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'matno', r->>'regNo', '')));
        IF v_matric = '' OR v_matric ~* '^matric' THEN CONTINUE; END IF;   -- blank or a header row
        n := n + 1;

        SELECT id INTO v_student FROM people.student
         WHERE upper(matric_no) = v_matric OR upper(admission_no) = v_matric OR upper(jamb_reg_no) = v_matric
         LIMIT 1;
        IF v_student IS NULL THEN nns := nns + 1; CONTINUE; END IF;

        v_amount := nullif(regexp_replace(coalesce(r->>'amount', r->>'amountPaid', r->>'amount_paid', r->>'paid', ''), '[^0-9.]', '', 'g'), '')::numeric;
        IF v_amount IS NULL OR v_amount <= 0 THEN nba := nba + 1; CONTINUE; END IF;

        BEGIN
            v_session := nullif(btrim(coalesce(r->>'session', r->>'academicSession', r->>'academic_session', '')), '');
            IF v_session IS NULL THEN v_session := 'LEGACY'; END IF;
            -- a real session on the row becomes a real session on record (with its two semesters)
            IF v_session ~ '^[0-9]{4}/[0-9]{4}$' THEN PERFORM assessment.ensure_session(v_session); END IF;

            v_purpose := nullif(btrim(coalesce(r->>'purpose', r->>'paymentType', r->>'payment_type', r->>'category', r->>'feeType', r->>'fee', r->>'description', '')), '');
            IF v_purpose IS NULL THEN v_purpose := 'School fees ' || v_session; END IF;

            v_date := NULL;
            BEGIN v_date := (nullif(btrim(coalesce(r->>'date', r->>'paidOn', r->>'paid_on', r->>'paymentDate', r->>'payment_date', r->>'datePaid', '')), ''))::date;
            EXCEPTION WHEN OTHERS THEN v_date := NULL; END;
            IF v_date IS NULL THEN v_date := current_date; END IF;

            v_channel := upper(nullif(btrim(coalesce(r->>'channel', r->>'method', r->>'paymentMethod', r->>'payment_method', '')), ''));
            IF v_channel IS NULL THEN v_channel := 'MIGRATION'; END IF;

            v_note := nullif(btrim(coalesce(r->>'note', r->>'remark', r->>'narration', '')), '');
            IF v_note IS NULL THEN v_note := 'Migrated payment history'; END IF;

            -- keep the original reference/receipt when given; otherwise a stable one derived from the row
            v_ref := upper(nullif(btrim(coalesce(r->>'reference', r->>'ref', r->>'rrr', r->>'transactionRef', r->>'transaction_ref', r->>'receipt', r->>'receiptNo', r->>'receipt_no', '')), ''));
            IF v_ref IS NULL THEN
                v_ref := 'MIGR-' || coalesce(nullif(regexp_replace(v_matric, '[^0-9A-Z]', '', 'g'), ''), 'X') || '-' || upper(substr(md5(r::text), 1, 10));
            END IF;
            v_receipt := upper(nullif(btrim(coalesce(r->>'receipt', r->>'receiptNo', r->>'receipt_no', '')), ''));
            IF v_receipt IS NULL THEN v_receipt := 'RCT-MIGR-' || upper(substr(md5(v_ref), 1, 12)); END IF;

            INSERT INTO finance.payment_reference
                (student_id, session, reference, purpose, amount, generated_at, expires_at,
                 confirmed_at, confirmed_by, channel, note, receipt_no)
            VALUES (v_student, v_session, v_ref, v_purpose, v_amount,
                    v_date::timestamptz, v_date::timestamptz + interval '1 day',
                    v_date::timestamptz, v_actor, v_channel, v_note, v_receipt)
            ON CONFLICT (reference) DO NOTHING;

            GET DIAGNOSTICS v_cnt = ROW_COUNT;
            IF v_cnt > 0 THEN ni := ni + 1; ELSE nd := nd + 1; END IF;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_firsterr IS NULL THEN v_firsterr := left(v_matric || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
        END;
    END LOOP;

    RETURN QUERY SELECT n, ni, nd, nns, nba, ns, v_firsterr;
END $$;

-- ── 2. put every currently-studying student into the current session ────────
CREATE OR REPLACE FUNCTION people.enrol_current_session(p_session text)
RETURNS TABLE (enrolled int, already int, eligible int)
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_added int; v_total int;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'enrolment is run by a person' USING ERRCODE = '23514'; END IF;
    IF p_session !~ '^[0-9]{4}/[0-9]{4}$' THEN
        RAISE EXCEPTION 'a session is named YYYY/YYYY, not %', p_session USING ERRCODE = '23514';
    END IF;
    PERFORM assessment.ensure_session(p_session);

    -- a whole-cohort backfill is not per-row audit material (V123 does the same for the registration backfill)
    ALTER TABLE people.enrolment DISABLE TRIGGER trg_audit_people_enrolment;
    INSERT INTO people.enrolment (id, student_id, session, level)
    SELECT gen_random_uuid(), s.id, p_session, s.current_level
      FROM people.student s
     WHERE s.matric_no IS NOT NULL
       AND s.status IN ('ACTIVE', 'PROBATION')
       AND s.current_level IN (100, 200, 300, 400, 500, 600)
       AND NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.student_id = s.id AND e.session = p_session);
    GET DIAGNOSTICS v_added = ROW_COUNT;
    ALTER TABLE people.enrolment ENABLE TRIGGER trg_audit_people_enrolment;

    SELECT count(*) INTO v_total FROM people.student
     WHERE matric_no IS NOT NULL AND status IN ('ACTIVE', 'PROBATION') AND current_level IN (100, 200, 300, 400, 500, 600);
    RETURN QUERY SELECT v_added, v_total - v_added, v_total;
END $$;

COMMENT ON FUNCTION people.enrol_current_session(text) IS
  'Ensure the session exists and enrol every matriculated, currently-studying '
  'student (ACTIVE/PROBATION) into it at their current level. Idempotent; run '
  'once after the historical re-upload to match the cohort to the current session.';

COMMIT;
