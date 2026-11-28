-- V786. PG applicants' application fees, uploaded in the old fees format, clear by application number.
--
-- The University, 24 November 2026, with a sheet in the Bursary's old-fees layout ("payment upload single school fees history PG
-- APPLICANT.xlsx": Matriculation Number, Session, Semester, Level, Amount, Purpose/Payment Item, Payment Date, Channel, Reference — one row:
-- PG/26/000310, 2026/2027, ₦20,000, PG APPLICATION, 2026-03-09, Interswitch, PR202609033502624): "I want to upload those payments in this
-- format to solve my issue".
--
-- What stood. The Bursary's Old Fees History upload (finance.import_legacy_payments) finds the payer among the STUDENTS — by matriculation
-- number, an old one a correction replaced, or the admission number — and a PG applicant is not a student: PG/26/000310 is an application
-- number of this portal. Run through it, the sheet's row was counted and held as "no student"; nothing was cleared. V783 clears a PG
-- application fee the old portal marked Paid, but only through the PG migration template, whose required columns (the old application
-- number, the names, the email, the session, the programme) the payment sheet does not carry.
--
-- What V786 does. The PG Legacy Migration desk's fees tab takes this sheet as it is. admissions.pg_old_fees_upload reads each row:
--   · the number (the first column) is the applicant's application number on this portal (PG/YY/NNNNNN) or the number the old portal
--     gave it; a student's number is not read here (the Old Fees History upload records it); a number no application holds is not found;
--   · the payment item must read as an application fee (acceptance fees, school fees and every other item are not cleared here);
--   · the reference and the amount must be there;
--   · the fee is recorded as an old-portal application fee (admissions.pg_legacy_fee, stated Paid) and V783's clearing runs on it
--     (admissions.pg_legacy_fee_autoclear: the amount reaches the session's application fee, the reference is on no other ledger and was
--     not rejected, the person has not paid elsewhere, no fee is confirmed here already): CLEARED, or HELD with the reason for the Bursary
--     or the PG Secretary on the Old-portal fees tab — exactly the rules of V783, one predicate;
--   · a reference already recorded for the same application is not recorded twice (ALREADY: the same file again changes nothing), and a
--     reference recorded for another application is a CONFLICT, written nowhere.
-- A Check (apply = false) does all of it in a subtransaction that is undone, and answers each row as the upload will: the officer sees what
-- will clear and what will be held before anything is written. An Upload (apply = true) writes one batch, kind FEES, completed, which the PG
-- migration history lists, and a notice to each applicant whose fee cleared (the same notice an officer's verification sends).
-- Who may: the offices that migrate (the School, its Secretary, the Academic Office, the Director of ICT, the Database Operators) and the Bursar.
--
--   admissions.pg_old_fees_upload(file, sha256, rows, apply, notify) — the report: counts, and for each row its number, the application,
--                                                                        the applicant, the reference, the amount, the result and the reason
-- A payment an officer rejected for an application is not put back by an upload (REJECTED).
-- Not changed: V783's rules; the PG migration template; the Old Fees History upload.
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V786: PG applicants'' application fee payments uploaded in the old fees format', true);

-- ── 1 · a batch of this kind: the payments of one file, completed as it is made ─────────────────────────────────
ALTER TABLE admissions.pg_migration_batch DROP CONSTRAINT pg_migration_batch_kind_check;
ALTER TABLE admissions.pg_migration_batch ADD CONSTRAINT pg_migration_batch_kind_check CHECK (kind IN ('APPLICANTS', 'ADMITTED', 'FEES'));

-- ── 2 · the upload ──────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.pg_old_fees_upload(p_file text, p_sha text, p_rows jsonb, p_apply boolean DEFAULT false, p_notify boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SET jit = off
AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := coalesce(current_setting('moaum.actor_office', true), '');
        v_file text; v_year text; v_batch uuid; v_batch_ref text;
        e record; r jsonb; v_row bigint;
        v_no text; v_ref text; v_text text; v_amount numeric; v_paid date; v_session text;
        v_apps uuid[]; v_app uuid; v_appno text; v_name text; v_app_session text; v_fee uuid; v_old admissions.pg_legacy_fee; v_old_no text; v_rej admissions.pg_legacy_fee;
        v_result text; v_reason text; v_note text; v_out jsonb := '[]'::jsonb;
        n_rows int := 0; n_cleared int := 0; n_held int := 0; n_already int := 0; n_refused int := 0;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PGFEES_ACTOR: payments are uploaded by a person' USING ERRCODE = '23514'; END IF;
    IF v_office NOT IN ('pgschool', 'pgsecretary', 'academic', 'ict', 'dbops', 'super', 'bursar') THEN
        RAISE EXCEPTION 'PGFEES_OFFICE: the School of Postgraduate Studies, its Secretary, the Academic Office, the Director of ICT, a Database Operator or the Bursar uploads old-portal application fee payments, not %', v_office
              USING ERRCODE = '42501';
    END IF;
    v_file := btrim(regexp_replace(coalesce(p_file, ''), '^.*[\\/]', ''));
    IF v_file !~* '\.xlsx$' OR length(v_file) > 255 THEN
        RAISE EXCEPTION 'PGFEES_FILE_TYPE: the payments are an Excel workbook (.xlsx)' USING ERRCODE = '23514';
    END IF;
    IF p_sha IS NOT NULL AND lower(p_sha) !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'PGFEES_CHECKSUM: the file''s checksum did not arrive intact' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) < 1 OR jsonb_array_length(p_rows) > 20000 THEN
        RAISE EXCEPTION 'PGFEES_ROWS: the payments are 1 to 20,000 rows: number, session, amount, item, date, channel, reference' USING ERRCODE = '23514';
    END IF;

    BEGIN   -- the work; a Check undoes it
        v_year := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY');
        v_batch_ref := 'PG-MIG/' || v_year || '/' || lpad(platform.next_number('PG_MIGRATION', 'UNIVERSITY', v_year)::text, 6, '0');
        INSERT INTO admissions.pg_migration_batch (reference, kind, file_name, file_sha256, rows_expected, state, notify, started_by, started_office, completed_at, completed_by)
        VALUES (v_batch_ref, 'FEES', v_file, lower(p_sha), jsonb_array_length(p_rows), 'COMPLETED', coalesce(p_notify, true), v_actor, v_office, now(), v_actor)
        RETURNING id INTO v_batch;

        FOR e IN SELECT x.value AS r, x.ordinality AS n FROM jsonb_array_elements(p_rows) WITH ORDINALITY x(value, ordinality) LOOP
            r := e.r; v_row := e.n;
            v_no := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'number', r->>'applicationNo', '')));
            IF v_no = '' THEN CONTINUE; END IF;                                  -- a blank row
            IF v_no ~* '^(mat(ric|no)|application|number|reg)' THEN CONTINUE; END IF;   -- a header row
            n_rows := n_rows + 1;
            v_result := NULL; v_reason := NULL; v_note := NULL; v_app := NULL; v_appno := NULL; v_name := NULL; v_fee := NULL;

            v_ref := btrim(coalesce(r->>'receiptNo', r->>'reference', r->>'receipt', r->>'payref', ''));
            v_text := btrim(coalesce(nullif(finance.legacy_item_of(coalesce(r->>'purpose', r->>'item', r->>'payItem', r->>'paymentItem', r->>'feeType', '')), ''), r->>'note', ''));
            v_amount := CASE WHEN regexp_replace(coalesce(r->>'amount', r->>'amountPaid', r->>'paid', ''), '[^0-9.]', '', 'g') ~ '^[0-9]+(\.[0-9]+)?$'
                             THEN regexp_replace(coalesce(r->>'amount', r->>'amountPaid', r->>'paid', ''), '[^0-9.]', '', 'g')::numeric END;
            v_paid := finance.legacy_date(coalesce(r->>'paidOn', r->>'paid_on', r->>'date'))::date;
            v_session := btrim(coalesce(r->>'session', ''));

            -- the application: this portal's number, else the number the old portal gave it
            SELECT array_agg(a.id) INTO v_apps FROM admissions.pg_application a WHERE upper(a.application_no) = v_no;
            IF coalesce(cardinality(v_apps), 0) = 0 THEN
                SELECT array_agg(DISTINCT l.application_id) INTO v_apps FROM admissions.pg_legacy_application l WHERE upper(btrim(l.legacy_application_no)) = v_no;
            END IF;

            IF v_text = '' OR v_text !~* 'application' OR v_text ~* 'acceptance' THEN
                v_result := 'NOT_APPLICATION_FEE';
                v_reason := CASE WHEN v_text = '' THEN 'the row names no payment item: write PG APPLICATION'
                                 ELSE 'only a postgraduate application fee is cleared here, and this row says "' || left(v_text, 40) || '"' END;
            ELSIF v_ref = '' THEN
                v_result := 'NO_REFERENCE'; v_reason := 'the row has no payment reference';
            ELSIF v_amount IS NULL OR v_amount <= 0 THEN
                v_result := 'NO_AMOUNT'; v_reason := 'the row has no amount';
            ELSIF coalesce(cardinality(v_apps), 0) = 0 THEN
                IF (SELECT rs.student_id FROM people.resolve_student(v_no, false) rs) IS NOT NULL THEN
                    v_result := 'IS_STUDENT'; v_reason := 'this is a student''s number: the Old Fees History upload records a student''s payments';
                ELSE
                    v_result := 'NOT_FOUND'; v_reason := 'no postgraduate application has this number';
                END IF;
            ELSIF cardinality(v_apps) > 1 THEN
                v_result := 'NOT_FOUND'; v_reason := 'more than one application has this number: use the application number of this portal (PG/YY/NNNNNN)';
            ELSE
                v_app := v_apps[1];
                SELECT a.application_no, p.surname || ', ' || p.other_names, a.session INTO v_appno, v_name, v_app_session
                  FROM admissions.pg_application a JOIN admissions.pg_applicant p ON p.id = a.applicant_id WHERE a.id = v_app;
                IF v_session <> '' AND v_session <> v_app_session THEN
                    v_note := 'the file says ' || v_session || ', the application is in ' || v_app_session;
                END IF;
                -- a reference already recorded: for this application it is not recorded twice, for another it is a conflict
                SELECT * INTO v_old FROM admissions.pg_legacy_fee x
                 WHERE x.kind = 'APPLICATION' AND upper(btrim(x.legacy_reference)) = upper(v_ref) AND x.state <> 'REJECTED' LIMIT 1;
                SELECT * INTO v_rej FROM admissions.pg_legacy_fee x
                 WHERE x.kind = 'APPLICATION' AND upper(btrim(x.legacy_reference)) = upper(v_ref) AND x.state = 'REJECTED' AND x.application_id = v_app
                 ORDER BY x.decided_at DESC NULLS LAST LIMIT 1;
                IF v_rej.id IS NOT NULL AND v_old.id IS NULL THEN
                    -- an officer has rejected this payment for this very application: an upload does not put it back
                    v_result := 'REJECTED'; v_reason := 'an officer rejected this payment on ' || v_appno || ' (' || left(coalesce(v_rej.decision_note, 'no note'), 120) || ')';
                ELSIF v_old.id IS NOT NULL AND v_old.application_id IS DISTINCT FROM v_app THEN
                    SELECT a.application_no INTO v_old_no FROM admissions.pg_application a WHERE a.id = v_old.application_id;
                    v_result := 'CONFLICT'; v_reason := 'this reference is already recorded for ' || coalesce(v_old_no, 'another applicant');
                ELSIF v_old.id IS NOT NULL AND v_old.state = 'POSTED' THEN
                    v_result := 'ALREADY'; v_reason := 'this payment is already recorded and posted'; v_fee := v_old.id;
                ELSE
                    IF v_old.id IS NOT NULL THEN
                        v_fee := v_old.id;      -- held before: the clearing is tried again, the rules or the facts may have changed
                    ELSE
                        INSERT INTO admissions.pg_legacy_fee (batch_id, application_id, kind, legacy_reference, amount, paid_on, session, purpose, stated_status, state)
                        VALUES (v_batch, v_app, 'APPLICATION', left(v_ref, 80), v_amount, v_paid, v_app_session, 'Application fee paid on the old portal', 'Paid', 'REQUIRES_REVIEW')
                        RETURNING id INTO v_fee;
                    END IF;
                    IF admissions.pg_legacy_fee_autoclear(v_fee, coalesce(p_notify, true)) THEN
                        v_result := 'CLEARED';
                    ELSE
                        v_result := 'HELD'; v_reason := admissions.pg_legacy_fee_clear_reason(v_fee);
                    END IF;
                END IF;
            END IF;

            IF v_result = 'CLEARED' THEN n_cleared := n_cleared + 1;
            ELSIF v_result = 'HELD' THEN n_held := n_held + 1;
            ELSIF v_result = 'ALREADY' THEN n_already := n_already + 1;
            ELSE n_refused := n_refused + 1; END IF;
            v_out := v_out || jsonb_build_array(jsonb_build_object('rowNo', CASE WHEN r->>'row' ~ '^[0-9]{1,6}$' THEN (r->>'row')::int ELSE v_row::int + 1 END, 'number', v_no, 'applicationNo', v_appno, 'name', v_name, 'reference', v_ref,
                                                                    'amount', v_amount, 'result', v_result, 'reason', v_reason, 'note', v_note));
        END LOOP;

        IF NOT coalesce(p_apply, false) THEN
            RAISE EXCEPTION 'PGFEES_CHECK_UNDONE' USING ERRCODE = 'P0001';
        END IF;
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'PGFEES_CHECK_UNDONE' THEN RAISE; END IF;
        v_batch := NULL; v_batch_ref := NULL;
    END;

    RETURN jsonb_build_object('applied', coalesce(p_apply, false), 'batchId', v_batch, 'batchReference', v_batch_ref, 'fileName', v_file,
                              'rows', n_rows, 'cleared', n_cleared, 'held', n_held, 'already', n_already, 'refused', n_refused, 'results', v_out);
END $$;

COMMIT;
