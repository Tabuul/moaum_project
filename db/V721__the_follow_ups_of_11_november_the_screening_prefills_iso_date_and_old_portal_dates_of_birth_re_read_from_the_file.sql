-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V721 · The follow-ups of 11 November 2026 ("do 1-6"): the screening prefill carries an ISO date of birth beside JAMB's text,
--  and old-portal students' dates of birth are re-read from the migration file
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  Six follow-ups were asked for after V717 and V719; two of them are the database's:
--   5. The screening facts (admissions.screening_facts, V282) gave the date of birth as JAMB's raw text ("12-09-2003"), and the
--      applicant's screening, the Screening Review and the prefill queries of the API read the same raw text. Since V717 every
--      reader reads it day first, but a reader is one more place to get it wrong. The identity block now carries
--      date_of_birth_iso — the student record's date, else JAMB's text read day first (platform.read_date) — beside the raw text,
--      which stays for the forms and the Post-UTME door's digit match.
--   4. Students imported from the old portal with an ambiguous day-month-year date of birth and no JAMB date-of-birth file still
--      hold the month-first misreading the old reading made of it. people.file_dates_of_birth(rows, commit, reason) reads the
--      migration file's rows (a matriculation or JAMB number, a date of birth as the file writes it) against the register, as
--      people.jamb_dates_of_birth (V717) reads JAMB's file: AGREES; FILLED (the record held none); CORRECTED (the record held
--      exactly the misreading — the file's day and month swapped); DIFFERS (another date stands: left, listed); UNREADABLE (the
--      file's text is no date); NO_STUDENT (no record under that number); AMBIGUOUS (two records under the numbers given).
--      Commit writes the record and an empty or misread Biodata form, on the audit spine with the reason, by the offices of
--      people.jamb_dob_officer (the Academic Office, the Registry, Records, the Director of ICT, super); preview writes nothing.
--  The other four are the API's and the frontend's: the preliminary desk's default route ranked by the routes' own kind rather
--  than the fee types' order (the nightly suite-twice failure), the postgraduate applicant editor handing an admitted applicant
--  to the student edit page, the postgraduate register's Edit link and the desk's document upload, and the School's report of
--  programme changes (the swaps of postgraduate students).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V721: the follow-ups of 11 November 2026', true);

-- ── 1 · the screening facts: the date of birth as a date, beside JAMB's text (V282 restated) ──
CREATE OR REPLACE FUNCTION admissions.screening_facts(p_app uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $fn$
    WITH a AS (SELECT ap.*, c.surname, c.other_names, c.jamb_reg_no, c.programme AS candidate_programme, c.entry_mode, c.entry_level, c.jamb_key, c.admitted_from, c.id AS cand_id
                 FROM admissions.application ap JOIN admissions.candidate c ON c.id = ap.candidate_id WHERE ap.id = p_app),
         acc AS (SELECT acc.email, acc.phone FROM a JOIN admissions.applicant_account acc ON acc.id = a.account_id),
         cr AS (SELECT r.* FROM a LEFT JOIN admissions.caps_row r ON r.id = a.admitted_from),
         st AS (SELECT s.* FROM a LEFT JOIN people.student s ON s.candidate_id = a.cand_id),
         pr AS (SELECT p.code, p.name, p.category, f.name AS faculty, d.name AS department FROM a LEFT JOIN ref.programme p ON p.code = admissions.programme_code_of(a.candidate_programme)
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code),
         dob AS (SELECT x.payload ->> 'dob' AS dob FROM a JOIN admissions.attachment x ON x.candidate_id = a.cand_id AND x.kind = 'DATE_OF_BIRTH' ORDER BY x.arrived_at DESC LIMIT 1),
         photo AS (SELECT EXISTS (SELECT 1 FROM a JOIN admissions.attachment x ON x.session = a.session AND x.jamb_key = a.jamb_key AND x.kind = 'PASSPORT' AND jsonb_exists(x.payload, 'dataUrl')) AS yes),
         utme AS (SELECT (SELECT string_agg(e.value, ', ' ORDER BY e.key) FROM jsonb_each_text(cr.raw) e
                            WHERE regexp_replace(lower(e.key), '[^a-z0-9]', '', 'g') IN ('subject1','subject2','subject3','subject4') AND nullif(btrim(e.value), '') IS NOT NULL) AS subjects, cr.aggregate FROM cr),
         ol AS (SELECT coalesce(jsonb_agg(jsonb_build_object('exam_body', x.exam_body, 'exam_number', x.exam_number, 'exam_year', x.exam_year, 'subject', x.subject, 'grade', x.grade) ORDER BY x.ord), '[]'::jsonb) AS rows
                  FROM admissions.screening_olevel x WHERE x.application_id = p_app AND x.active),
         jol AS (SELECT coalesce(jsonb_agg(jsonb_build_object('exam_body', s.exam_body, 'exam_number', s.exam_number, 'exam_year', s.exam_year, 'subject', g.subject, 'grade', g.grade) ORDER BY s.ord, g.subject), '[]'::jsonb) AS rows
                   FROM a JOIN admissions.olevel_sitting s ON s.session = a.session AND s.jamb_key = a.jamb_key JOIN admissions.olevel_grade g ON g.sitting_id = s.id),
         docs AS (SELECT coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'filename', d.filename, 'uploaded_at', d.uploaded_at, 'status', d.status, 'review_note', d.review_note) ORDER BY d.kind, d.uploaded_at DESC), '[]'::jsonb) AS rows
                    FROM admissions.application_document d WHERE d.application_id = p_app),
         ans AS (SELECT coalesce(jsonb_object_agg(x.field, x.value) FILTER (WHERE btrim(x.value) <> ''), '{}'::jsonb) AS m FROM admissions.screening_answer x WHERE x.application_id = p_app),
         bio AS (SELECT coalesce(jsonb_object_agg(b.field, b.value) FILTER (WHERE btrim(b.value) <> ''), '{}'::jsonb) AS m FROM st JOIN people.biodata b ON b.student_id = st.id),
         inst AS (SELECT coalesce(jsonb_agg(jsonb_build_object('name', i.name, 'from_year', i.from_year, 'to_year', i.to_year, 'certificate', i.certificate, 'award_year', i.award_year) ORDER BY i.ord), '[]'::jsonb) AS rows
                    FROM admissions.screening_institution i WHERE i.application_id = p_app AND i.active),
         pay AS (SELECT coalesce(jsonb_object_agg(fr.kind, jsonb_build_object('reference', fr.reference, 'amount', fr.amount, 'confirmed_at', fr.confirmed_at, 'receipt_no', fr.receipt_no, 'channel', fr.channel)), '{}'::jsonb) AS m
                   FROM admissions.fee_reference fr WHERE fr.application_id = p_app AND fr.confirmed_at IS NOT NULL),
         ent AS (SELECT * FROM admissions.acceptance_entitlement(p_app)),
         scr AS (SELECT * FROM admissions.screening_form WHERE application_id = p_app)
    SELECT jsonb_build_object(
        'identity', jsonb_build_object('surname', a.surname, 'other_names', a.other_names, 'sex', coalesce(st.sex, cr.sex), 'date_of_birth', coalesce(st.date_of_birth::text, dob.dob),
                                       -- V721: the date as a date — the record's, else JAMB's text read day first; the raw text stays beside it
                                       'date_of_birth_iso', coalesce(st.date_of_birth, platform.read_date(dob.dob))::text,
                                       'state_of_origin', coalesce(st.state_of_origin, cr.state_of_origin),
                                       'nationality', coalesce((SELECT b.value FROM people.biodata b WHERE b.student_id = st.id AND b.field = 'nationality' AND btrim(b.value) <> ''), ref.nationality_of_state(coalesce(st.state_of_origin, cr.state_of_origin))),
                                       'lga', cr.lga, 'email', acc.email, 'phone', acc.phone, 'next_of_kin', a.next_of_kin, 'passport', photo.yes),
        'jamb', jsonb_build_object('jamb_reg_no', a.jamb_reg_no, 'utme_aggregate', utme.aggregate, 'utme_subjects', utme.subjects, 'entry_mode', a.entry_mode, 'entry_level', a.entry_level,
                                   'programme', a.candidate_programme, 'session', a.session, 'list_source', (SELECT b.source FROM admissions.caps_row r JOIN admissions.caps_batch b ON b.id = r.batch_id WHERE r.id = a.admitted_from)),
        'admission', jsonb_build_object('application_no', a.application_no, 'programme', pr.name, 'programme_code', pr.code, 'degree_type', pr.category, 'faculty', pr.faculty, 'department', pr.department,
                                        'decision', a.decision, 'decision_basis', a.decision_basis, 'decision_released_at', a.decision_released_at, 'undertaking_at', a.undertaking_at, 'accepted_at', a.accepted_at,
                                        'acceptance_reference', ent.reference, 'acceptance_confirmed_at', ent.confirmed_at, 'admission_no', st.admission_no, 'matric_no', st.matric_no, 'student_status', st.status),
        'olevel', CASE WHEN jsonb_array_length(ol.rows) > 0 THEN ol.rows ELSE jol.rows END,
        'jamb_olevel', jol.rows,
        'institutions', inst.rows,
        'documents', docs.rows,
        'payments', pay.m,
        'answers', ans.m,
        'biodata', bio.m,
        'screening', CASE WHEN scr.application_id IS NULL THEN NULL ELSE jsonb_build_object('screening_no', scr.screening_no, 'state', scr.state, 'version', scr.version, 'decided_at', scr.decided_at, 'decided_office', scr.decided_office,
                                                                                            'decision_reason', scr.decision_reason, 'remarks', scr.remarks, 'returned_note', scr.returned_note, 'membership', scr.membership) END)
      FROM a, acc, cr, st, pr, photo, utme, ol, jol, docs, ans, bio, inst, pay, ent LEFT JOIN dob ON true LEFT JOIN scr ON true;
$fn$;
COMMENT ON FUNCTION admissions.screening_facts(p_app uuid) IS
  'V282, V721: everything the screening forms, the applicant''s screening and the review read of one application — identity (the date of birth as JAMB''s text and, since V721, as a date: date_of_birth_iso), JAMB, admission, O''Level, institutions, documents, payments, answers, biodata, the screening form.';

-- ── 2 · old-portal students' dates of birth re-read from the migration file ──
CREATE OR REPLACE FUNCTION people.file_dates_of_birth(p_rows jsonb, p_commit boolean, p_reason text DEFAULT NULL)
RETURNS TABLE(row_no int, matric_no text, jamb_reg_no text, student_id uuid, surname text, other_names text, programme_code text,
              file_text text, file_date date, held date, form_value text, action text)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE r record; v_reason text := coalesce(nullif(btrim(p_reason), ''), nullif(current_setting('moaum.reason', true), ''), 'Date of birth as the old portal''s file gave it, read day, month, year');
        v_misread date; v_form text; s record; n_found int;
BEGIN
    IF p_commit THEN
        PERFORM people.jamb_dob_officer();
        PERFORM set_config('moaum.reason', v_reason, true);
    END IF;
    FOR r IN
        SELECT (x.ord)::int AS row_no,
               nullif(upper(regexp_replace(btrim(coalesce(x.v ->> 'matric', x.v ->> 'matric_no', x.v ->> 'matno', '')), '\s+', '', 'g')), '') AS matric,
               nullif(upper(regexp_replace(btrim(coalesce(x.v ->> 'jamb', x.v ->> 'jamb_reg_no', x.v ->> 'jambRegNo', '')), '\s+', '', 'g')), '') AS jamb,
               btrim(coalesce(x.v ->> 'dob', x.v ->> 'dateOfBirth', x.v ->> 'date_of_birth', '')) AS text
          FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) WITH ORDINALITY x(v, ord)
    LOOP
        row_no := r.row_no; matric_no := r.matric; jamb_reg_no := r.jamb; file_text := nullif(r.text, '');
        file_date := platform.read_date(r.text);
        IF file_date IS NOT NULL AND (file_date > current_date OR file_date < date '1900-01-01') THEN file_date := NULL; END IF;   -- as V717: a date no one was born on
        student_id := NULL; surname := NULL; other_names := NULL; programme_code := NULL; held := NULL; form_value := NULL;
        -- the record: by the matriculation number; where that finds none, by the JAMB number
        n_found := 0;
        IF r.matric IS NOT NULL THEN
            SELECT count(*), min(st.id::text)::uuid INTO n_found, student_id FROM people.student st
             WHERE st.duplicate_of IS NULL AND upper(regexp_replace(coalesce(st.matric_no, ''), '\s+', '', 'g')) = r.matric;
        END IF;
        IF n_found = 0 AND r.jamb IS NOT NULL THEN
            SELECT count(*), min(st.id::text)::uuid INTO n_found, student_id FROM people.student st
             WHERE st.duplicate_of IS NULL AND upper(coalesce(st.jamb_reg_no, '')) = r.jamb;
        END IF;
        IF n_found = 0 THEN action := 'NO_STUDENT'; RETURN NEXT; CONTINUE; END IF;
        IF n_found > 1 THEN student_id := NULL; action := 'AMBIGUOUS'; RETURN NEXT; CONTINUE; END IF;
        SELECT st.surname, st.other_names, st.programme_code, st.date_of_birth INTO s FROM people.student st WHERE st.id = student_id;
        surname := s.surname; other_names := s.other_names; programme_code := s.programme_code; held := s.date_of_birth;
        SELECT b.value INTO v_form FROM people.biodata b WHERE b.student_id = file_dates_of_birth.student_id AND b.field = 'date_of_birth';
        form_value := v_form;
        -- what the old reading made of the file's date: day and month swapped, where both are twelve or less
        v_misread := CASE WHEN file_date IS NOT NULL AND extract(day FROM file_date) <= 12 AND extract(day FROM file_date) <> extract(month FROM file_date)
                          THEN make_date(extract(year FROM file_date)::int, extract(day FROM file_date)::int, extract(month FROM file_date)::int) END;
        action := CASE WHEN file_date IS NULL THEN 'UNREADABLE'
                       WHEN held IS NULL THEN 'FILLED'
                       WHEN held = file_date THEN 'AGREES'
                       WHEN v_misread IS NOT NULL AND held = v_misread THEN 'CORRECTED'
                       ELSE 'DIFFERS' END;
        IF p_commit AND action IN ('FILLED', 'CORRECTED', 'AGREES') THEN
            IF action <> 'AGREES' THEN
                UPDATE people.student SET date_of_birth = file_date WHERE id = file_dates_of_birth.student_id;
            END IF;
            IF v_form IS NULL OR btrim(v_form) = '' OR (v_misread IS NOT NULL AND platform.read_date(v_form) = v_misread) THEN
                INSERT INTO people.biodata (student_id, field, value) VALUES (file_dates_of_birth.student_id, 'date_of_birth', file_date::text)
                ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value;
                form_value := file_date::text;
            END IF;
        END IF;
        RETURN NEXT;
    END LOOP;
END $$;
COMMENT ON FUNCTION people.file_dates_of_birth(jsonb, boolean, text) IS
  'V721: the old portal''s file (matric or JAMB number, date of birth as written) read against the register, as V717 reads JAMB''s file — AGREES, FILLED, CORRECTED (the record holds the file''s day and month swapped, whatever form the file writes the date in: the old reading of a day-month-year figure), DIFFERS (left), UNREADABLE, NO_STUDENT, AMBIGUOUS. Commit writes the record and an empty or misread Biodata form with the reason, by people.jamb_dob_officer''s offices; preview writes nothing.';

-- ── 3 · the issued screening forms stand: the new key is left out of the comparison that re-issues them (V280's
--        admissions.issue_screening_forms, the one line changed in place, as V715 changed V642's) ──
DO $do$
DECLARE d text;
        o text := $o$(((cur.statement -> 'facts') - 'screening') - 'documents') - 'payments' = ((facts - 'screening') - 'documents') - 'payments'$o$;
        n text := $n$((((cur.statement -> 'facts') - 'screening') - 'documents') - 'payments') #- '{identity,date_of_birth_iso}' = ((((facts - 'screening') - 'documents') - 'payments') #- '{identity,date_of_birth_iso}')$n$;
BEGIN
    d := pg_get_functiondef('admissions.issue_screening_forms(uuid)'::regprocedure);
    IF (length(d) - length(replace(d, o, ''))) / length(o) <> 1 THEN
        RAISE EXCEPTION 'V721: admissions.issue_screening_forms no longer compares the facts as V280 wrote it; restate it by hand';
    END IF;
    EXECUTE replace(d, o, n);
END $do$;
COMMENT ON FUNCTION admissions.issue_screening_forms(uuid) IS
  'V280, V721: the five screening forms issued once the screening is successful, and re-issued (a new version, a new code) only when the record they were drawn from changed — the date of birth as a date (date_of_birth_iso, V721) is not such a change.';
