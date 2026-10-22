-- V627: the audit trail searched by date and by person, and past results held to the Directorate of ICT by the database as well as
-- the API (the University's word of 21 October 2026, "do 1 and 2, 3, 4, 5").
--   · The audit screen's date range and "who" filter read the person's own entries: audit.entries by actor (ix_entries_actor, V002)
--     and the sign-ins by person, which had no index: iam.sign_in_event (person_id, at DESC) and iam.student_event (student_id,
--     at DESC), built CONCURRENTLY below.
--   · Past results load as final with no approval chain, because they were approved on the old portal, so V626 kept the upload to
--     the Directorate of ICT (and the super administrator) in the API. Now the loaders hold the same rule:
--     assessment.legacy_semester_load and admissions.import_legacy_pg_semester, asked to load results (or to preview them), refuse
--     an acting office other than ict or super with PAST_RESULTS_OFFICE (42501). A load with no acting office (the database's
--     own maintenance, the demo data) is not an office's act and passes.
--     Posting results already uploaded and held for a student not yet loaded (reconcile_legacy_holding and
--     pg_reconcile_legacy_holding, run after every student upload) brings in no new result, so stays open: each marks its own
--     transaction while it posts. The two loaders are restated exactly as they stand (V619 and V214), with the one check added first.

BEGIN;

CREATE OR REPLACE FUNCTION assessment.past_results_office()
RETURNS void
LANGUAGE plpgsql
STABLE
AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF v_office IS NOT NULL AND v_office NOT IN ('ict', 'super')
       AND coalesce(current_setting('moaum.legacy_reconcile', true), '') <> 'on' THEN
        RAISE EXCEPTION 'PAST_RESULTS_OFFICE: past results are uploaded by the Directorate of ICT'
              USING ERRCODE = '42501';
    END IF;
END $$;
COMMENT ON FUNCTION assessment.past_results_office() IS
  'V627: refuses a past results load (or its preview) by an acting office other than ict or super; posting held results '
  '(moaum.legacy_reconcile on, set by the reconcile functions for their own transaction) and a load with no acting office pass.';

CREATE OR REPLACE FUNCTION assessment.legacy_semester_load(p_session text, p_semester integer, p_rows jsonb, p_with_results boolean, p_preview boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_line text; v_matric text; v_raw_code text; v_code text; v_units int; v_level int; v_ca int; v_exam int; v_total int; v_outcome text;
    v_student uuid; v_programme text; v_stream text; v_offering uuid; v_sheet uuid; v_reg uuid; v_reg_status text; v_entry uuid; v_entry_status text;
    v_entry_units int; v_have_mark boolean; v_status text; v_detail text; v_entry_state text;
    v_new_reg boolean; v_new_entry boolean; v_new_offering boolean; v_reapprove boolean; v_posted boolean; v_deferred boolean := false;
    n int := 0; n_off int := 0; n_reg int := 0; n_entry int := 0; n_res int := 0; n_already int := 0; n_units int := 0; n_dropped int := 0;
    n_open int := 0; n_reapproved int := 0; nns int := 0; n_held int := 0; nnc int := 0; nnm int := 0; n_refused int := 0; n_dup int := 0;
    -- V614: the mark read as the whole, and a result already on record (the same, an earlier upload's replaced, one entered on the portal)
    v_mark_note text; v_prev assessment.score; v_prev_found boolean;
    n_as_total int := 0; n_res_same int := 0; n_res_replaced int := 0; n_res_portal int := 0;
    -- V619: the old portal's ABS read as an absence
    v_abs_note text; n_absent int := 0;
    v_firsterr text := NULL; v_lines jsonb := '[]'::jsonb;
    seen_students uuid[] := '{}'; seen_codes text[] := '{}'; seen_keys text[] := '{}';
BEGIN
    IF p_with_results THEN PERFORM assessment.past_results_office(); END IF;  -- V627: past results are the Directorate of ICT's to load
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, course, units and the mark' USING ERRCODE = '23514';
    END IF;

    BEGIN   -- the whole load; a preview undoes it at the end, keeping what it learned
        PERFORM assessment.ensure_session(p_session);
        v_deferred := people.defer_positions();

        FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
            v_line := nullif(btrim(coalesce(r->>'line', '')), '');
            v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'regNo', r->>'reg_no', '')));
            v_raw_code := upper(btrim(coalesce(r->>'course', r->>'courseCode', r->>'course_code', r->>'code', '')));
            IF v_matric = '' THEN CONTINUE; END IF;
            n := n + 1;
            v_status := NULL; v_detail := NULL; v_student := NULL; v_code := NULL; v_entry_state := NULL; v_mark_note := NULL; v_abs_note := NULL;
            v_new_reg := false; v_new_entry := false; v_new_offering := false; v_reapprove := false; v_posted := false;

            BEGIN   -- one savepoint per row: what the portal refuses sets the row aside, the batch goes on
                IF v_raw_code = '' THEN
                    v_status := 'NO_COURSE'; v_detail := 'The row has no course code';
                ELSE
                    v_code := coalesce(catalogue.resolve_course_code(v_raw_code), regexp_replace(v_raw_code, '^([A-Z]{2,4})\s*([0-9]{3})$', '\1 \2'));
                    SELECT s.id, s.programme_code INTO v_student, v_programme FROM people.student s WHERE upper(s.matric_no) = v_matric;
                    IF (v_matric || '|' || v_code) = ANY (seen_keys) THEN
                        v_status := 'DUPLICATE_IN_FILE'; v_detail := 'The same student and course appear earlier in the file';
                    ELSIF v_student IS NULL THEN
                        IF p_with_results THEN
                            -- the student is not on the register yet: the result is HELD, to be posted on reconcile
                            INSERT INTO assessment.legacy_result_holding (session, semester, matric, course_code, raw)
                            VALUES (p_session, p_semester, v_matric, v_code, r)
                            ON CONFLICT (session, semester, matric, course_code) DO UPDATE SET raw = EXCLUDED.raw, loaded_at = now();
                            v_status := 'HELD'; v_detail := 'No student with this number yet; the result posts once the student is uploaded';
                        ELSE
                            v_status := 'NO_STUDENT'; v_detail := 'No student on the register has this matriculation number';
                        END IF;
                    ELSIF NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_code) THEN
                        v_status := 'NO_COURSE'; v_detail := format('No course %s in the catalogue', v_raw_code);
                    ELSE
                        v_stream := people.student_stream(v_student);
                        IF v_stream = 'PG' THEN
                            RAISE EXCEPTION 'POSTGRADUATE_STUDENT: % is a postgraduate student; their registration and results come over through the PG uploads', v_matric
                                USING ERRCODE = '23514';
                        END IF;
                        SELECT c.level INTO v_level FROM catalogue.course c WHERE c.code = v_code;
                        v_level := coalesce(nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int, v_level);

                        -- what is on record: the student's registration for the semester, and the course on it
                        SELECT cr.id, cr.status INTO v_reg, v_reg_status FROM registration.course_registration cr
                         WHERE cr.student_id = v_student AND cr.session = p_session AND cr.semester = p_semester;
                        v_entry := NULL; v_entry_status := NULL; v_entry_units := NULL;
                        IF v_reg IS NOT NULL THEN
                            SELECT e.offering_id, e.status, e.units INTO v_entry, v_entry_status, v_entry_units
                              FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id
                             WHERE e.registration_id = v_reg AND o.course_code = v_code
                             ORDER BY (e.status IN ('APPROVED', 'REGISTERED')) DESC LIMIT 1;
                        END IF;
                        v_units := catalogue.units_for(v_code, v_programme, v_level);

                        IF v_entry IS NULL THEN
                            SELECT id INTO v_offering FROM catalogue.offering
                             WHERE course_code = v_code AND session = p_session AND semester = p_semester AND stream = v_stream;
                            IF v_offering IS NULL THEN
                                v_offering := gen_random_uuid();
                                INSERT INTO catalogue.offering (id, course_code, session, semester, stream) VALUES (v_offering, v_code, p_session, p_semester, v_stream);
                                v_new_offering := true;
                            END IF;
                            INSERT INTO people.enrolment (id, student_id, session, level)
                            VALUES (gen_random_uuid(), v_student, p_session, v_level) ON CONFLICT (student_id, session) DO NOTHING;
                            IF v_reg IS NULL THEN
                                v_reg := gen_random_uuid();
                                INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at, approved_by)
                                VALUES (v_reg, v_student, p_session, p_semester, v_level, 'APPROVED', now(), now(), v_actor);
                                v_new_reg := true;
                            END IF;
                            INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
                            VALUES (v_reg, v_offering, v_units, 'CURRENT', 'APPROVED');
                            v_entry := v_offering;
                            v_new_entry := true;
                            IF NOT v_new_reg AND v_reg_status NOT IN ('APPROVED', 'LOCKED') THEN
                                v_status := 'ADDED_TO_OPEN_REGISTRATION';
                                v_detail := format('Added to the student''s %s registration for this semester on the portal', lower(v_reg_status));
                            ELSE
                                v_status := 'ADDED';
                                v_detail := format('%s units%s', v_units, CASE WHEN v_new_reg THEN '; a new approved registration for the semester' END);
                            END IF;
                        ELSIF v_entry_status NOT IN ('APPROVED', 'REGISTERED') THEN
                            IF p_with_results THEN
                                -- a result is evidence the course was taken: the entry is approved, as before
                                UPDATE registration.entry SET status = 'APPROVED' WHERE registration_id = v_reg AND offering_id = v_entry;
                                v_reapprove := true;
                                v_status := 'ADDED';
                                v_detail := format('%s on record; approved again because a result was posted', lower(v_entry_status));
                            ELSE
                                v_status := 'DROPPED_ON_RECORD';
                                v_detail := format('%s on the student''s registration; left as it is', initcap(lower(v_entry_status)));
                            END IF;
                        ELSIF v_units IS NOT NULL AND v_entry_units IS DISTINCT FROM v_units THEN
                            v_status := 'UNITS_DIFFER';
                            v_detail := format('On record at %s units; the programme takes it at %s — left as it is', v_entry_units, v_units);
                        ELSE
                            v_status := 'ALREADY_ON_RECORD'; v_detail := format('On record at %s units', v_entry_units);
                        END IF;
                        v_offering := v_entry;   -- the entry is keyed by its registration and its class
                        v_entry_state := v_status;

                        IF p_with_results AND v_status <> 'DROPPED_ON_RECORD' THEN
                            v_ca := nullif(regexp_replace(coalesce(r->>'ca', r->>'CA', ''), '[^0-9]', '', 'g'), '')::int;
                            v_exam := nullif(regexp_replace(coalesce(r->>'exam', r->>'EXAM', ''), '[^0-9]', '', 'g'), '')::int;
                            v_total := nullif(regexp_replace(coalesce(r->>'total', r->>'TOTAL', r->>'score', r->>'SCORE', r->>'mark', ''), '[^0-9]', '', 'g'), '')::int;
                            v_outcome := upper(btrim(coalesce(r->>'outcome', 'GRADED')));
                            -- V619: the old portal marks a candidate who did not sit "ABS" (or "AB", "ABSENT", "ABS (F)") — in the Outcome,
                            -- Remark or Grade column, or in place of the mark itself. That is an absence (F, owed), never "No mark": a row
                            -- left unposted shows the candidate as NR on the broadsheet. A mark cell reads as the absence only when no
                            -- mark cell of the row carries a number (an "AB" beside an exam score is not an absence from the examination).
                            IF v_outcome <> 'ABSENT' AND regexp_replace(v_outcome, '[^A-Z]', '', 'g') IN ('ABS', 'AB', 'ABSENT', 'ABSF', 'ABSENTF') THEN
                                v_abs_note := format('"%s" on the old portal read as absent (F)', btrim(r->>'outcome'));
                                v_outcome := 'ABSENT';
                            END IF;
                            IF v_outcome NOT IN ('GRADED','ABSENT','WITHHELD','INCOMPLETE','MALPRACTICE','EXEMPTED') THEN v_outcome := 'GRADED'; END IF;
                            IF v_outcome = 'GRADED' AND v_ca IS NULL AND v_exam IS NULL AND v_total IS NULL THEN
                                SELECT format('"%s" in the %s column read as absent (F)', btrim(x.v), x.k) INTO v_abs_note
                                  FROM (VALUES (1, 'CA', coalesce(r->>'ca', r->>'CA')), (2, 'Exam', coalesce(r->>'exam', r->>'EXAM')),
                                               (3, 'Total', coalesce(r->>'total', r->>'TOTAL', r->>'score', r->>'SCORE', r->>'mark'))) x(o, k, v)
                                 WHERE regexp_replace(upper(coalesce(x.v, '')), '[^A-Z]', '', 'g') IN ('ABS', 'AB', 'ABSENT', 'ABSF', 'ABSENTF')
                                 ORDER BY x.o LIMIT 1;
                                IF v_abs_note IS NOT NULL THEN v_outcome := 'ABSENT'; END IF;
                            END IF;
                            -- V614: the old portal's mark as it stands, never refused for the 40/60 split. CA and exam as the record splits them
                            -- (CA 0–40, exam 0–60) stay so; otherwise the mark is the whole, out of 100: the Total column where the file has
                            -- one, else an exam column over 60 or with no CA beside it (the old portal had added the CA in), else a CA over 40
                            -- added to the exam
                            IF v_outcome = 'GRADED' THEN
                                IF v_ca IS NOT NULL AND v_exam IS NOT NULL AND v_ca <= 40 AND v_exam <= 60 AND (v_total IS NULL OR v_total = v_ca + v_exam) THEN
                                    v_total := NULL;
                                ELSIF v_total IS NOT NULL THEN
                                    IF v_ca IS NOT NULL OR v_exam IS NOT NULL THEN
                                        v_mark_note := format('the Total column taken as the mark: %s of 100', v_total);
                                    END IF;
                                    v_ca := NULL; v_exam := NULL;
                                ELSIF v_exam IS NOT NULL AND (v_ca IS NULL OR v_exam > 60) THEN
                                    v_mark_note := format('the exam column read as the whole mark: %s of 100%s', v_exam,
                                                          CASE WHEN v_ca IS NOT NULL THEN format(' (the CA of %s already in it)', v_ca) ELSE '' END);
                                    v_total := v_exam; v_ca := NULL; v_exam := NULL;
                                ELSIF v_exam IS NOT NULL THEN
                                    v_mark_note := format('CA %s and exam %s added as the whole mark: %s of 100', v_ca, v_exam, v_ca + v_exam);
                                    v_total := v_ca + v_exam; v_ca := NULL; v_exam := NULL;
                                ELSIF v_ca IS NOT NULL THEN
                                    v_total := v_ca; v_ca := NULL;   -- a lone mark is the whole, as before
                                END IF;
                            END IF;
                            IF v_outcome = 'GRADED' AND ((v_total IS NULL AND (v_ca IS NULL OR v_exam IS NULL)) OR coalesce(v_total, 0) > 100) THEN
                                v_status := 'NO_MARK';
                                v_detail := CASE WHEN coalesce(v_total, 0) > 100 THEN format('The mark is over 100 (%s)', v_total) ELSE 'No mark' END
                                            || CASE WHEN v_new_entry THEN '; the course was still registered' ELSE '' END;
                            ELSE
                                -- V614: a result already on record is not posted twice — the same one is left as it is, a different one an
                                -- earlier upload posted is replaced (and said so), one entered on the portal is never loaded over
                                SELECT id INTO v_sheet FROM assessment.score_sheet WHERE offering_id = v_offering;
                                v_prev_found := false;
                                IF v_sheet IS NOT NULL THEN
                                    SELECT * INTO v_prev FROM assessment.score WHERE sheet_id = v_sheet AND student_id = v_student ORDER BY version DESC LIMIT 1;
                                    v_prev_found := FOUND;
                                END IF;
                                IF v_prev_found AND v_prev.outcome = v_outcome
                                   AND (v_outcome <> 'GRADED' OR coalesce(v_prev.total, v_prev.ca + v_prev.exam) = coalesce(v_total, v_ca + v_exam)) THEN
                                    v_status := 'RESULT_ALREADY_ON_RECORD';
                                    v_detail := format('The same result is on record (%s); not posted again',
                                                       assessment.legacy_mark_words(v_prev.outcome, v_prev.ca, v_prev.exam, v_prev.total));
                                    DELETE FROM assessment.legacy_result_holding
                                     WHERE session = p_session AND semester = p_semester AND matric = v_matric AND course_code = v_code;
                                ELSIF v_prev_found AND NOT v_prev.imported THEN
                                    v_status := 'RESULT_ON_PORTAL';
                                    v_detail := format('A result entered on the portal is on record (%s); the old portal''s (%s) is not loaded over it — amend it through Result amendments',
                                                       assessment.legacy_mark_words(v_prev.outcome, v_prev.ca, v_prev.exam, v_prev.total),
                                                       assessment.legacy_mark_words(v_outcome, v_ca, v_exam, v_total));
                                ELSE
                                    IF v_sheet IS NULL THEN
                                        v_sheet := gen_random_uuid();
                                        INSERT INTO assessment.score_sheet (id, offering_id, stage, senate_minute, published_at)
                                        VALUES (v_sheet, v_offering, 'PUBLISHED', 'Migrated from the legacy portal', now());
                                    ELSIF (SELECT stage FROM assessment.score_sheet WHERE id = v_sheet) <> 'PUBLISHED' THEN
                                        UPDATE assessment.score_sheet SET stage = 'PUBLISHED', senate_minute = coalesce(senate_minute, 'Migrated from the legacy portal'),
                                               published_at = coalesce(published_at, now()) WHERE id = v_sheet;
                                    END IF;
                                    INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, total, outcome, imported, reason)
                                    VALUES (v_sheet, v_student,
                                            coalesce((SELECT max(version) + 1 FROM assessment.score WHERE sheet_id = v_sheet AND student_id = v_student), 1),
                                            CASE WHEN v_outcome = 'GRADED' AND v_exam IS NOT NULL THEN v_ca END,
                                            CASE WHEN v_outcome = 'GRADED' AND v_exam IS NOT NULL THEN v_exam END,
                                            CASE WHEN v_outcome = 'GRADED' AND v_exam IS NULL THEN v_total END,
                                            v_outcome, true,
                                            CASE WHEN v_prev_found THEN 'Re-imported from the legacy portal' END);
                                    DELETE FROM assessment.legacy_result_holding
                                     WHERE session = p_session AND semester = p_semester AND matric = v_matric AND course_code = v_code;
                                    v_posted := true;
                                    v_detail := 'Result posted' || coalesce('; ' || v_abs_note, '') || coalesce('; ' || v_mark_note, '')
                                                || CASE WHEN v_prev_found THEN format('; replaces %s an earlier upload posted',
                                                                                      assessment.legacy_mark_words(v_prev.outcome, v_prev.ca, v_prev.exam, v_prev.total)) ELSE '' END
                                                || coalesce('; ' || v_detail, '');
                                    v_status := CASE WHEN v_prev_found THEN 'RESULT_REPLACED' WHEN v_mark_note IS NOT NULL THEN 'RESULT_AS_TOTAL' ELSE 'RESULT_POSTED' END;
                                END IF;
                            END IF;
                        END IF;
                    END IF;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                v_status := 'REFUSED';
                v_detail := left(SQLERRM, 300);
                v_new_reg := false; v_new_entry := false; v_new_offering := false; v_reapprove := false; v_posted := false;
                IF v_firsterr IS NULL THEN v_firsterr := left(v_matric || ' ' || coalesce(v_code, v_raw_code) || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
            END;

            -- the row's outcome, counted only once its writes stood
            IF v_code IS NOT NULL AND v_status NOT IN ('DUPLICATE_IN_FILE') THEN seen_keys := seen_keys || (v_matric || '|' || v_code); END IF;
            CASE v_status
                WHEN 'ADDED' THEN NULL;
                WHEN 'ADDED_TO_OPEN_REGISTRATION' THEN n_open := n_open + 1;
                WHEN 'ALREADY_ON_RECORD' THEN n_already := n_already + 1;
                WHEN 'UNITS_DIFFER' THEN n_units := n_units + 1;
                WHEN 'DROPPED_ON_RECORD' THEN n_dropped := n_dropped + 1;
                WHEN 'NO_STUDENT' THEN nns := nns + 1;
                WHEN 'HELD' THEN n_held := n_held + 1;
                WHEN 'NO_COURSE' THEN nnc := nnc + 1;
                WHEN 'NO_MARK' THEN nnm := nnm + 1;
                WHEN 'DUPLICATE_IN_FILE' THEN n_dup := n_dup + 1;
                WHEN 'RESULT_ALREADY_ON_RECORD' THEN n_res_same := n_res_same + 1;
                WHEN 'RESULT_ON_PORTAL' THEN n_res_portal := n_res_portal + 1;
                WHEN 'RESULT_REPLACED' THEN n_res_replaced := n_res_replaced + 1;
                WHEN 'REFUSED' THEN n_refused := n_refused + 1;
                ELSE NULL;
            END CASE;
            -- a posted result's course was already on record, or on record at other units, or added
            IF v_posted AND v_entry_state = 'ALREADY_ON_RECORD' THEN n_already := n_already + 1; END IF;
            IF v_posted AND v_entry_state = 'UNITS_DIFFER' THEN n_units := n_units + 1; END IF;
            IF v_posted AND v_entry_state = 'ADDED_TO_OPEN_REGISTRATION' THEN n_open := n_open + 1; END IF;
            IF v_new_reg THEN n_reg := n_reg + 1; END IF;
            IF v_new_entry THEN n_entry := n_entry + 1; END IF;
            IF v_reapprove THEN n_reapproved := n_reapproved + 1; END IF;
            IF v_posted THEN n_res := n_res + 1; END IF;
            IF v_posted AND v_mark_note IS NOT NULL THEN n_as_total := n_as_total + 1; END IF;
            IF v_posted AND v_abs_note IS NOT NULL THEN n_absent := n_absent + 1; END IF;
            IF v_status IN ('ADDED', 'ADDED_TO_OPEN_REGISTRATION', 'ALREADY_ON_RECORD', 'UNITS_DIFFER', 'DROPPED_ON_RECORD', 'RESULT_POSTED', 'NO_MARK',
                            'RESULT_AS_TOTAL', 'RESULT_REPLACED', 'RESULT_ALREADY_ON_RECORD', 'RESULT_ON_PORTAL') THEN
                IF NOT (v_student = ANY (seen_students)) THEN seen_students := seen_students || v_student; END IF;
                IF NOT (v_code = ANY (seen_codes)) THEN seen_codes := seen_codes || v_code; n_off := n_off + 1; END IF;
            END IF;
            -- the rows the office reads: every row on a preview; on an import, every row not loaded or left as it was
            IF p_preview OR v_status NOT IN ('ADDED', 'ADDED_TO_OPEN_REGISTRATION', 'ALREADY_ON_RECORD', 'RESULT_POSTED') THEN
                v_lines := v_lines || jsonb_build_object('line', v_line, 'matric', v_matric, 'course', coalesce(v_code, v_raw_code),
                                                         'session', p_session, 'semester', p_semester, 'status', v_status, 'detail', v_detail);
            END IF;
        END LOOP;

        IF v_deferred AND NOT p_preview THEN PERFORM people.refresh_deferred_positions(); END IF;
        IF p_preview THEN RAISE EXCEPTION 'LEGACY_PREVIEW_UNDONE' USING ERRCODE = 'P0001'; END IF;
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'LEGACY_PREVIEW_UNDONE' THEN RAISE; END IF;
    END;

    RETURN jsonb_build_object(
        'preview', p_preview, 'session', p_session, 'semester', p_semester,
        'rows', n, 'students', cardinality(seen_students), 'offerings', n_off, 'registrations', n_reg, 'entries', n_entry,
        'already', n_already, 'units_differ', n_units, 'dropped_kept', n_dropped, 'added_to_open', n_open, 'reapproved', n_reapproved,
        'results', n_res, 'no_student', nns, 'held', n_held, 'no_course', nnc, 'no_mark', nnm,
        'duplicate', n_dup, 'refused', n_refused, 'skipped', n_refused + n_dup, 'first_error', v_firsterr,
        'marks_as_total', n_as_total, 'results_same', n_res_same, 'results_replaced', n_res_replaced, 'results_on_portal', n_res_portal,
        'absent_from_abs', n_absent,
        'lines', v_lines);
END $function$;
COMMENT ON FUNCTION assessment.legacy_semester_load(text, integer, jsonb, boolean, boolean) IS
  'V472, V614, V619, V627: a past semester''s registration (and results) from the old portal, row by row, or what it would do (a preview, undone); the mark read as the old portal states it (the 40/60 split never refuses it: an exam over 60, a Total, a CA over 40 is the whole mark of 100), its ABS read as an absence, and a result already on record never posted twice; results (and their preview) loaded only by the Directorate of ICT (assessment.past_results_office)';

CREATE OR REPLACE FUNCTION admissions.import_legacy_pg_semester(p_session text, p_semester integer, p_rows jsonb, p_with_results boolean)
 RETURNS TABLE(rows integer, students integer, courses integer, registrations integer, results integer, no_student integer, held integer, no_mark integer, skipped integer, first_error text)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_code text; v_title text; v_units int; v_kind text; v_mode text;
        v_ca numeric; v_exam numeric; v_total numeric; v_grade text; v_points numeric;
        v_student uuid; v_pg boolean; v_prog text; v_course uuid; v_reg uuid; v_entry uuid;
        n int := 0; n_course int := 0; n_reg int := 0; n_res int := 0; nns int := 0; n_held int := 0;
        nnm int := 0; ns int := 0; v_firsterr text := NULL;
        seen_students uuid[] := '{}';
BEGIN
    IF p_with_results THEN PERFORM assessment.past_results_office(); END IF;  -- V627: past results are the Directorate of ICT's to load
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_semester NOT IN (1, 2) THEN
        RAISE EXCEPTION 'postgraduate study has two semesters: the semester is 1 or 2' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, course, units and the mark' USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'matno', r->>'regNo', r->>'reg_no', '')));
        v_code := upper(btrim(coalesce(r->>'course', r->>'courseCode', r->>'course_code', r->>'code', '')));
        v_code := regexp_replace(v_code, '^([A-Z]{2,4})\s*([0-9]{3})$', '\1 \2');
        IF v_matric = '' OR v_code = '' THEN CONTINUE; END IF;
        n := n + 1;

        BEGIN   -- one savepoint per row: any unexpected error sets the row aside, the batch survives
            SELECT s.id, (s.entry_mode = 'POSTGRADUATE'), s.programme_code
              INTO v_student, v_pg, v_prog
              FROM people.student s WHERE upper(s.matric_no) = v_matric;

            IF v_student IS NULL THEN
                -- the student is not on the register yet: HOLD a results row, to be posted on reconcile
                IF p_with_results THEN
                    INSERT INTO admissions.pg_legacy_holding (session, semester, matric, course_code, raw)
                    VALUES (p_session, p_semester, v_matric, v_code, r)
                    ON CONFLICT (session, semester, matric, course_code) DO UPDATE SET raw = EXCLUDED.raw, loaded_at = now();
                    n_held := n_held + 1;
                ELSE
                    nns := nns + 1;
                END IF;
                CONTINUE;
            END IF;
            IF NOT v_pg THEN
                -- the number belongs to a student who is not a postgraduate — not for this importer
                nns := nns + 1; CONTINUE;
            END IF;

            -- resolve the course of the student's programme, creating it from the row when it is not on record
            v_title := nullif(btrim(coalesce(r->>'title', r->>'courseTitle', r->>'course_title', r->>'name', '')), '');
            v_units := coalesce(nullif(regexp_replace(coalesce(r->>'units', r->>'unit', r->>'credit', r->>'cu', ''), '[^0-9]', '', 'g'), '')::int, 3);
            IF v_units < 0 OR v_units > 12 THEN v_units := 3; END IF;
            v_kind := upper(btrim(coalesce(r->>'kind', r->>'type', 'CORE')));
            IF v_kind NOT IN ('CORE','ELECTIVE','DEFICIENCY','RESEARCH') THEN v_kind := 'CORE'; END IF;

            SELECT id INTO v_course FROM admissions.pg_course WHERE programme_code = v_prog AND upper(code) = v_code;
            IF v_course IS NULL THEN
                INSERT INTO admissions.pg_course (programme_code, code, title, units, kind, semester)
                VALUES (v_prog, v_code, coalesce(v_title, v_code), v_units, v_kind, p_semester)
                ON CONFLICT (programme_code, code) DO NOTHING
                RETURNING id INTO v_course;
                IF v_course IS NULL THEN
                    SELECT id INTO v_course FROM admissions.pg_course WHERE programme_code = v_prog AND upper(code) = v_code;
                ELSE
                    n_course := n_course + 1;
                END IF;
            END IF;
            IF v_course IS NULL THEN ns := ns + 1; CONTINUE; END IF;

            -- the registration for this session/semester (created endorsed under a legacy minute, or endorsed if present)
            v_mode := upper(btrim(coalesce(r->>'mode', r->>'studyMode', r->>'study_mode', '')));
            v_mode := CASE WHEN v_mode LIKE 'PART%' OR v_mode = 'PT' THEN 'PART_TIME' ELSE 'FULL_TIME' END;
            SELECT id INTO v_reg FROM admissions.pg_registration
             WHERE student_id = v_student AND session = p_session AND semester = p_semester;
            IF v_reg IS NULL THEN
                INSERT INTO admissions.pg_registration (student_id, session, semester, mode, state, endorsed_by, endorsed_at)
                VALUES (v_student, p_session, p_semester, v_mode, 'ENDORSED', v_actor, now())
                RETURNING id INTO v_reg;
                n_reg := n_reg + 1;
            ELSE
                UPDATE admissions.pg_registration
                   SET state = 'ENDORSED', endorsed_by = coalesce(endorsed_by, v_actor),
                       endorsed_at = coalesce(endorsed_at, now()), updated_at = now()
                 WHERE id = v_reg;
            END IF;

            INSERT INTO admissions.pg_registration_entry (registration_id, course_id)
            VALUES (v_reg, v_course) ON CONFLICT (registration_id, course_id) DO NOTHING
            RETURNING id INTO v_entry;
            IF v_entry IS NULL THEN
                SELECT id INTO v_entry FROM admissions.pg_registration_entry
                 WHERE registration_id = v_reg AND course_id = v_course;
            END IF;
            IF NOT (v_student = ANY(seen_students)) THEN seen_students := seen_students || v_student; END IF;

            IF NOT p_with_results THEN CONTINUE; END IF;

            -- the score: CA + exam → total (0–100), graded on the postgraduate scale
            v_ca := nullif(regexp_replace(coalesce(r->>'ca', r->>'CA', ''), '[^0-9.]', '', 'g'), '')::numeric;
            v_exam := nullif(regexp_replace(coalesce(r->>'exam', r->>'EXAM', ''), '[^0-9.]', '', 'g'), '')::numeric;
            v_total := nullif(regexp_replace(coalesce(r->>'total', r->>'TOTAL', r->>'score', r->>'SCORE', r->>'mark', ''), '[^0-9.]', '', 'g'), '')::numeric;
            IF v_total IS NULL AND v_ca IS NOT NULL AND v_exam IS NOT NULL THEN v_total := v_ca + v_exam; END IF;
            IF v_total IS NULL THEN nnm := nnm + 1; CONTINUE; END IF;
            v_total := round(v_total);
            IF v_total < 0 OR v_total > 100 THEN nnm := nnm + 1; CONTINUE; END IF;

            SELECT g.grade, g.points INTO v_grade, v_points FROM admissions.pg_grade(v_total) g;
            INSERT INTO admissions.pg_score (entry_id, ca, exam, total, grade, points, recorded_by)
            VALUES (v_entry, v_ca, v_exam, v_total, v_grade, v_points, v_actor)
            ON CONFLICT (entry_id) DO UPDATE SET ca = EXCLUDED.ca, exam = EXCLUDED.exam, total = EXCLUDED.total,
                grade = EXCLUDED.grade, points = EXCLUDED.points, recorded_at = now(), recorded_by = EXCLUDED.recorded_by;
            n_res := n_res + 1;
            -- the result is posted: clear any hold for this student/course
            DELETE FROM admissions.pg_legacy_holding
             WHERE session = p_session AND semester = p_semester AND matric = v_matric AND course_code = v_code;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_firsterr IS NULL THEN v_firsterr := left(v_matric || ' ' || v_code || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, cardinality(seen_students), n_course, n_reg, n_res, nns, n_held, nnm, ns, v_firsterr;
END $function$;
COMMENT ON FUNCTION admissions.import_legacy_pg_semester(text, integer, jsonb, boolean) IS
  'V214, V627: a past postgraduate semester''s registration (and results) from the old portal; results loaded only by the Directorate of ICT (assessment.past_results_office)';

CREATE OR REPLACE FUNCTION assessment.reconcile_legacy_holding()
 RETURNS TABLE(reconciled integer, still_held integer)
 LANGUAGE plpgsql
AS $function$
DECLARE grp record; v_before int; v_after int;
BEGIN
    PERFORM set_config('moaum.legacy_reconcile', 'on', true);  -- V627: posting held results is open to every migrating office
    SELECT count(*) INTO v_before FROM assessment.legacy_result_holding h
     WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric);
    FOR grp IN
        SELECT h.session, h.semester, jsonb_agg(h.raw) AS rows
          FROM assessment.legacy_result_holding h
         WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric)
         GROUP BY h.session, h.semester
    LOOP
        PERFORM assessment.import_legacy_semester(grp.session, grp.semester, grp.rows, true);
    END LOOP;
    SELECT count(*) INTO v_after FROM assessment.legacy_result_holding h
     WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric);
    PERFORM set_config('moaum.legacy_reconcile', '', true);
    RETURN QUERY SELECT greatest(v_before - v_after, 0),
                        (SELECT count(*)::int FROM assessment.legacy_result_holding);
END $function$;

CREATE OR REPLACE FUNCTION admissions.pg_reconcile_legacy_holding()
 RETURNS TABLE(reconciled integer, still_held integer)
 LANGUAGE plpgsql
AS $function$
DECLARE grp record; v_before int; v_after int;
BEGIN
    PERFORM set_config('moaum.legacy_reconcile', 'on', true);  -- V627: posting held results is open to every migrating office
    SELECT count(*) INTO v_before FROM admissions.pg_legacy_holding h
     WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric AND s.entry_mode = 'POSTGRADUATE');
    FOR grp IN
        SELECT h.session, h.semester, jsonb_agg(h.raw) AS rows
          FROM admissions.pg_legacy_holding h
         WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric AND s.entry_mode = 'POSTGRADUATE')
         GROUP BY h.session, h.semester
    LOOP
        PERFORM admissions.import_legacy_pg_semester(grp.session, grp.semester, grp.rows, true);
    END LOOP;
    SELECT count(*) INTO v_after FROM admissions.pg_legacy_holding h
     WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric AND s.entry_mode = 'POSTGRADUATE');
    PERFORM set_config('moaum.legacy_reconcile', '', true);
    RETURN QUERY SELECT greatest(v_before - v_after, 0),
                        (SELECT count(*)::int FROM admissions.pg_legacy_holding);
END $function$;

COMMIT;

-- the person's own sign-ins, newest first, for the audit screen's "who" filter
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_sign_in_person ON iam.sign_in_event (person_id, at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_student_event_student ON iam.student_event (student_id, at DESC);
