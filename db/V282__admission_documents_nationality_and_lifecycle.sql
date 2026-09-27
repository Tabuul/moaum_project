-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V282 — the admission documents in one place, the nationality JAMB's state implies, and the
--        lifecycle to matriculation named step by step
--
--   · ref.nationality_of_state: a Nigerian State or the Federal Capital Territory implies the
--     nationality Nigeria — nothing is inferred from a name, a sex or a programme. Read wherever
--     JAMB's state stands: the screening facts the forms print, the student's record at intake
--     (people.default_nationality, only where no nationality is held), and every existing
--     student whose record held none.
--   · admissions.admission_tracker gains 'Student portal active' after the school fees and
--     'Sign-in changed to the matriculation number' after matriculation, so the applicant's
--     tracker runs to the end of the journey.
--   · the matriculation issue records the JAMB registration number as the previous sign-in
--     where the student has one (it is what an entrant signs in with), the admission number
--     otherwise; the notice names it. The account, the password and the student id do not
--     change — only the username (V267).
--   The document centre itself is read from the tables that own each document (the credential
--   store, the fee references, the payment references); nothing is copied.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V282: admission documents, nationality from JAMB''s state, the lifecycle to matriculation', true);

-- ── 1 · the nationality a state implies ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ref.nationality_of_state(p_state text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE
             WHEN p_state IS NULL OR btrim(p_state) = '' THEN NULL
             WHEN EXISTS (SELECT 1 FROM ref.state s
                           WHERE upper(regexp_replace(s.name, '[^A-Za-z]', '', 'g')) = upper(regexp_replace(p_state, '[^A-Za-z]', '', 'g')))
               OR upper(regexp_replace(p_state, '[^A-Za-z]', '', 'g'))
                  IN ('FCT', 'ABUJA', 'FCTABUJA', 'ABUJAFCT', 'FEDERALCAPITALTERRITORYABUJA', 'FEDERALCAPITALTERRITORYFCT', 'NASSARAWA', 'CROSSRIVERS')
             THEN coalesce((SELECT c.name FROM ref.country c WHERE c.home ORDER BY c.ord, c.name LIMIT 1), 'Nigeria')
           END
$fn$;
COMMENT ON FUNCTION ref.nationality_of_state(text) IS
  'The nationality a state of origin implies: a Nigerian State or the FCT (ref.state, with the common spellings) → the home country; anything else → NULL. Never inferred from a name, a sex or a programme.';

CREATE OR REPLACE FUNCTION people.default_nationality(p_student uuid)
RETURNS boolean LANGUAGE plpgsql AS $fn$
DECLARE v_nat text;
BEGIN
    IF EXISTS (SELECT 1 FROM people.biodata b WHERE b.student_id = p_student AND b.field = 'nationality' AND btrim(b.value) <> '') THEN
        RETURN false;   -- a nationality already held is authoritative; it is never overwritten here
    END IF;
    SELECT ref.nationality_of_state(coalesce(s.state_of_origin, r.state_of_origin)) INTO v_nat
      FROM people.student s
      LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
      LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
     WHERE s.id = p_student;
    IF v_nat IS NULL THEN RETURN false; END IF;
    INSERT INTO people.biodata (student_id, field, value) VALUES (p_student, 'nationality', v_nat)
    ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value WHERE btrim(people.biodata.value) = '';
    RETURN true;
END $fn$;
COMMENT ON FUNCTION people.default_nationality(uuid) IS
  'Fills the nationality on a student''s record from the state JAMB sent, only where none is held; returns whether it wrote.';

-- ── 2 · the register: the nationality on the record from intake ──────────────────────────────
CREATE OR REPLACE FUNCTION people.intake_one(p_candidate uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $fn$
DECLARE c admissions.candidate; v_id uuid; v_code text; v_yy text;
BEGIN
    SELECT * INTO c FROM admissions.candidate WHERE id = p_candidate;
    IF c.id IS NULL THEN RAISE EXCEPTION 'no such candidate' USING ERRCODE = '23503'; END IF;
    SELECT id INTO v_id FROM people.student WHERE candidate_id = c.id;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;
    IF c.offer_state NOT IN ('ADMITTED', 'ACCEPTED') THEN
        RAISE EXCEPTION 'only an admitted candidate is brought onto the register; % is %', c.jamb_reg_no, lower(coalesce(c.offer_state, 'not admitted')) USING ERRCODE = '23514';
    END IF;
    -- candidate.programme is the programme NAME; resolve it to a code, accepting a value that is already a code
    v_code := (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1);
    IF v_code IS NULL THEN
        IF EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = c.programme) THEN
            v_code := c.programme;
        ELSE
            RAISE EXCEPTION 'the programme "%" for candidate % is not one the University runs; it cannot be brought onto the register',
                c.programme, c.jamb_reg_no USING ERRCODE = '23503',
                HINT = 'Set the programme''s University name to match ref.programme, or correct the candidate''s programme.';
        END IF;
    END IF;
    v_yy := substr(c.session, 3, 2);
    INSERT INTO people.student (id, candidate_id, admission_no, jamb_reg_no, surname, other_names,
                                programme_code, entry_mode, entry_session, entry_level, current_level)
    VALUES (gen_random_uuid(), c.id,
            'MOAUM/ADM/' || v_yy || '/' || lpad(platform.next_number('ADMISSION', 'UNIVERSITY', c.session)::text, 6, '0'),
            c.jamb_reg_no, c.surname, c.other_names, v_code,
            CASE WHEN c.entry_mode IN ('UTME', 'DIRECT_ENTRY') THEN c.entry_mode ELSE 'UTME' END,
            c.session, c.entry_level, c.entry_level)
    RETURNING id INTO v_id;
    -- the nationality JAMB's state implies, on the record from the first day (V282)
    PERFORM people.default_nationality(v_id);
    RETURN v_id;
END $fn$;

-- ── 3 · the screening facts carry the nationality the forms print ────────────────────────────
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
                                       'state_of_origin', coalesce(st.state_of_origin, cr.state_of_origin),
                                       'nationality', coalesce((SELECT b.value FROM people.biodata b WHERE b.student_id = st.id AND b.field = 'nationality' AND btrim(b.value) <> ''), ref.nationality_of_state(coalesce(st.state_of_origin, cr.state_of_origin))), 'lga', cr.lga, 'email', acc.email, 'phone', acc.phone, 'next_of_kin', a.next_of_kin, 'passport', photo.yes),
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

-- ── 4 · the tracker runs to the end of the journey ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.admission_tracker(p_app uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $fn$
DECLARE a admissions.application; f admissions.screening_form; s people.student; q admissions.programme_change_request; st record; req boolean; ent record; steps jsonb := '[]'::jsonb;
        paid boolean; reg boolean; offered boolean; accepted boolean; scr_done boolean; scr_failed boolean; chg_approved boolean;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO st FROM admissions.admission_status(p_app);
    offered := a.decision = 'OFFERED' AND a.decision_released_at IS NOT NULL;
    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);
    accepted := a.accepted_at IS NOT NULL;
    req := admissions.screening_required(p_app);
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    SELECT * INTO q FROM admissions.programme_change_request x WHERE x.application_id = p_app AND x.state IN ('REQUESTED', 'APPROVED') ORDER BY x.requested_at DESC LIMIT 1;
    scr_done := coalesce(f.state = 'SUCCESSFUL', false); scr_failed := coalesce(f.state = 'UNSUCCESSFUL', false);
    chg_approved := scr_failed AND coalesce(q.state = 'APPROVED' AND q.decided_at >= f.decided_at, false);
    SELECT * INTO s FROM people.student WHERE candidate_id = a.candidate_id LIMIT 1;
    paid := s.id IS NOT NULL AND coalesce((SELECT fp.paid_in_full AND fp.due > 0 FROM finance.position(s.id, a.session) fp), false);
    reg := s.id IS NOT NULL AND EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = a.session AND r.status IN ('APPROVED', 'LOCKED'));
    steps := steps || admissions.tracker_step('ADMISSION', 'JAMB admission', CASE WHEN offered THEN 'done' WHEN a.decision_released_at IS NULL THEN 'now' ELSE 'failed' END);
    steps := steps || admissions.tracker_step('ADMISSION_STATUS', 'Admission status checked', CASE WHEN ent.checking_paid OR a.status_checked_at IS NOT NULL OR accepted OR ent.paid OR a.undertaking_at IS NOT NULL THEN 'done' WHEN a.decision_released_at IS NOT NULL THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('ACCEPTANCE_PAYMENT', 'Acceptance payment', CASE WHEN ent.paid THEN 'done' WHEN offered AND NOT admissions.checking_due(p_app) AND (a.status_checked_at IS NOT NULL OR a.undertaking_at IS NOT NULL) THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('ACCEPTANCE_LETTER', 'Acceptance letter', CASE WHEN accepted THEN 'done' WHEN ent.paid THEN 'now' ELSE 'todo' END);
    IF req THEN
        steps := steps || admissions.tracker_step('SCREENING', 'University screening', CASE WHEN coalesce(f.state, '') IN ('SUCCESSFUL', 'UNSUCCESSFUL') THEN 'done' WHEN accepted THEN 'now' ELSE 'todo' END);
        IF scr_failed THEN
            steps := steps || admissions.tracker_step('SCREENING_DECISION', 'Screening unsuccessful', 'failed');
            steps := steps || admissions.tracker_step('CHANGE_OF_PROGRAMME', 'Change of programme', CASE WHEN q.id IS NOT NULL AND q.requested_at >= f.decided_at THEN 'done' ELSE 'now' END);
            steps := steps || admissions.tracker_step('CHANGE_APPROVAL', 'Approval', CASE WHEN chg_approved THEN 'done' WHEN q.id IS NOT NULL AND q.state = 'REQUESTED' THEN 'now' ELSE 'todo' END);
        ELSE
            steps := steps || admissions.tracker_step('SCREENING_DECISION', 'Screening successful', CASE WHEN scr_done THEN 'done' WHEN coalesce(f.state, '') IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED') THEN 'now' ELSE 'todo' END);
            steps := steps || admissions.tracker_step('SCREENING_FORMS', 'Screening forms generated', CASE WHEN scr_done THEN 'done' ELSE 'todo' END);
        END IF;
    END IF;
    steps := steps || admissions.tracker_step('SCHOOL_FEES', 'School fees', CASE WHEN paid THEN 'done' WHEN st.status = 'SCHOOL_FEES_PENDING' OR st.status = 'REGISTER_PENDING' THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('STUDENT_ACCOUNT', 'Student portal active', CASE WHEN paid THEN 'done' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('COURSE_REGISTRATION', 'Course registration', CASE WHEN reg THEN 'done' WHEN st.status = 'COURSE_REGISTRATION_PENDING' THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('MATRICULATION', 'Matriculation', CASE WHEN s.matric_no IS NOT NULL THEN 'done' WHEN st.status = 'MATRICULATION_PENDING' THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('USERNAME', 'Sign-in changed to the matriculation number', CASE WHEN s.matric_no IS NOT NULL THEN 'done' ELSE 'todo' END);
    RETURN steps;
END $fn$;

-- ── 5 · the matriculation issue: the previous sign-in is the JAMB number where there is one ──
CREATE OR REPLACE FUNCTION people.matric_batch_issue(p_batch uuid, p_actor uuid, p_office text)
 RETURNS TABLE(issued integer, username_updates integer, run_ref text)
 LANGUAGE plpgsql
AS $fn$
DECLARE b people.matric_batch; v record; r record; s people.student; c record; v_taken text; v_n int := 0; v_prev text; mf people.matric_format;
BEGIN
    SELECT * INTO b FROM people.matric_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such batch' USING ERRCODE = '23503'; END IF;
    IF b.state <> 'READY_FOR_ISSUANCE' THEN RAISE EXCEPTION 'only a batch marked READY FOR ISSUANCE is issued; this one is %', lower(replace(b.state, '_', ' ')) USING ERRCODE = '23514', HINT = 'Review the numbers and mark the batch ready first.'; END IF;
    SELECT * INTO mf FROM people.matric_format WHERE id = 'UNIVERSITY';
    IF mf.separate_duties AND p_actor IS NOT NULL AND (b.prepared_by = p_actor OR b.reviewed_by = p_actor) THEN
        RAISE EXCEPTION 'the officer who prepared or reviewed a batch does not issue it: duties are separated' USING ERRCODE = '23514', HINT = 'Another authorised officer issues the batch, or the Registry turns the separation off under Matriculation number format.';
    END IF;
    SELECT * INTO v FROM people.matric_batch_validate(p_batch);
    IF v.conflicts > 0 THEN RAISE EXCEPTION 'cannot issue matriculation numbers: % record(s) require attention', v.conflicts USING ERRCODE = '23514', HINT = 'Resolve every conflict before final issuance; nothing was issued.'; END IF;
    IF v.students = 0 THEN RAISE EXCEPTION 'the batch has no student on it' USING ERRCODE = '23514'; END IF;
    -- the run of this reference, so the register reads the batch like any run
    INSERT INTO people.matriculation_run (id, ref, session, issued) VALUES (b.id, b.ref, b.session, 0);
    FOR r IN SELECT br.* FROM people.matric_batch_row br WHERE br.batch_id = p_batch AND br.state = 'PROPOSED' ORDER BY br.series_code, br.sequence LOOP
        SELECT * INTO s FROM people.student WHERE id = r.student_id FOR UPDATE;
        -- verified again at the moment of issue; any failure rolls the whole batch back
        IF s.matric_no IS NOT NULL THEN RAISE EXCEPTION '% already holds %; nothing was issued', s.surname, s.matric_no USING ERRCODE = '23514'; END IF;
        IF s.status <> 'ADMITTED' THEN RAISE EXCEPTION '% is %, not admitted; nothing was issued', s.surname, lower(s.status) USING ERRCODE = '23514'; END IF;
        v_taken := people.matric_number_taken(r.proposed_no, r.series_code, r.sequence, r.id);
        IF v_taken IS NOT NULL THEN RAISE EXCEPTION '% for %; nothing was issued', v_taken, r.proposed_no USING ERRCODE = '23505'; END IF;
        PERFORM 1 FROM people.matric_series WHERE code = r.series_code FOR UPDATE;
        INSERT INTO people.matric_history (student_id, matric_no, series_code, sequence, components, run_id, issued_by, actor_office, reason)
        VALUES (r.student_id, r.proposed_no, r.series_code, r.sequence, coalesce(r.components, '{}'::jsonb) || jsonb_build_object('batch', b.ref, 'edited', r.edited),
                b.id, p_actor, p_office, 'Matriculation batch ' || b.ref || CASE WHEN r.edited THEN ' (number corrected: ' || coalesce(r.edit_reason, '') || ')' ELSE '' END);
        UPDATE people.matric_series SET last_issued = greatest(last_issued, r.sequence), updated_at = now() WHERE code = r.series_code;
        v_prev := coalesce(s.jamb_reg_no, s.admission_no);   -- the JAMB number is the sign-in an entrant has used since application (V282)
        UPDATE people.student SET matric_no = r.proposed_no, matriculated_at = now(), matriculation_run = b.id, status = 'ACTIVE' WHERE id = s.id;
        INSERT INTO people.status_change (id, student_id, from_status, to_status, instrument, effective_on, reason)
        VALUES (gen_random_uuid(), s.id, s.status, 'ACTIVE', b.ref, current_date, 'Matriculated (batch ' || b.ref || ')');
        INSERT INTO people.student_username_change (student_id, previous_username, new_username, reason, changed_by, office, batch_id)
        VALUES (s.id, v_prev, r.proposed_no, 'Student matriculated', p_actor, p_office, b.id);
        UPDATE people.matric_reservation SET released_at = now(), release_reason = 'Issued' WHERE row_id = r.id AND released_at IS NULL;
        UPDATE people.matric_batch_row SET state = 'ISSUED', issued_no = r.proposed_no, issued_at = now() WHERE id = r.id;
        PERFORM people.matric_tell(s.id, r.proposed_no);
        v_n := v_n + 1;
    END LOOP;
    UPDATE people.matriculation_run SET issued = v_n WHERE id = b.id;
    UPDATE people.matric_batch SET state = 'ISSUED', issued_by = p_actor, issued_office = p_office, issued_at = now(), issued = v_n, run_id = b.id WHERE id = p_batch;
    RETURN QUERY SELECT v_n, v_n, b.ref;
END $fn$;
-- ── the single issue (next_matric) records the same previous sign-in ──
CREATE OR REPLACE FUNCTION people.next_matric(p_student uuid, p_run uuid, p_reason text)
 RETURNS text
 LANGUAGE plpgsql
AS $fn$
DECLARE c record; ms people.matric_series; v_seq bigint; v_no text; v_try int := 0;
BEGIN
    SELECT * INTO c FROM people.matric_components(p_student);
    IF c.problem IS NOT NULL THEN
        RAISE EXCEPTION 'the matriculation number cannot be built: %', c.problem USING ERRCODE = '23514', HINT = 'The Registry configures the faculty, the programme and the series under Matriculation number format.';
    END IF;
    SELECT * INTO ms FROM people.matric_series WHERE code = c.series_code FOR UPDATE;
    IF ms.code IS NULL THEN RAISE EXCEPTION 'no series %', c.series_code USING ERRCODE = '23503'; END IF;
    LOOP
        v_try := v_try + 1;
        v_seq := ms.last_issued + v_try;
        v_no := people.format_matric(c.university_code, c.faculty_segment, c.programme_segment, c.yy, v_seq);
        EXIT WHEN people.matric_number_taken(v_no, c.series_code, v_seq, NULL) IS NULL;
        IF v_try > 100000 THEN RAISE EXCEPTION 'no free number in series % after a hundred thousand tries', c.series_code USING ERRCODE = '23514'; END IF;
    END LOOP;
    UPDATE people.matric_series SET last_issued = v_seq, updated_at = now() WHERE code = ms.code;
    INSERT INTO people.matric_history (student_id, matric_no, series_code, sequence, components, run_id, issued_by, actor_office, reason)
    VALUES (p_student, v_no, c.series_code, v_seq,
            jsonb_build_object('university', c.university_code, 'faculty', c.faculty_segment, 'programme', c.programme_segment, 'usesCode', c.uses_code,
                               'year', c.yy, 'sequence', v_seq, 'programmeCode', c.programme_code, 'facultyCode', c.faculty_code),
            p_run, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''), p_reason);
    -- the sign-in identity moves with the number on every path, not only the batch
    INSERT INTO people.student_username_change (student_id, previous_username, new_username, reason, changed_by, office)
    SELECT s.id, coalesce(s.jamb_reg_no, s.admission_no), v_no, coalesce(p_reason, 'Student matriculated'), nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), '')
      FROM people.student s WHERE s.id = p_student;
    RETURN v_no;
END $fn$;

CREATE OR REPLACE FUNCTION people.matric_tell(p_student uuid, p_no text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE reach record; prev text;
BEGIN
    SELECT * INTO reach FROM people.student_reach(p_student);
    SELECT coalesce(s.jamb_reg_no, s.admission_no) INTO prev FROM people.student s WHERE s.id = p_student;
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Congratulations — you have been officially matriculated',
        'Congratulations. Your official matriculation number has been issued: ' || p_no || '. It is permanent and appears on every document the University issues to you.'
        || E'\n\nYour matriculation number is now your official student portal username, in place of ' || coalesce(prev, 'the number you signed in with')
        || '. Your existing password remains unchanged; please use your matriculation number for every future sign-in.'
        || E'\n\nOffice of the Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi', 'student', p_student);
    PERFORM platform.queue_notice('SMS', reach.phone, 'Your matriculation number',
        'MOAUM: you are matriculated. Your matriculation number ' || p_no || ' is now your portal username; your password is unchanged.', 'student', p_student);
END $fn$;

-- ── 6 · every student whose record holds no nationality, from JAMB's state ───────────────────
DO $do$
DECLARE r record; n integer := 0;
BEGIN
    FOR r IN SELECT s.id FROM people.student s
              WHERE NOT EXISTS (SELECT 1 FROM people.biodata b WHERE b.student_id = s.id AND b.field = 'nationality' AND btrim(b.value) <> '')
    LOOP
        IF people.default_nationality(r.id) THEN n := n + 1; END IF;
    END LOOP;
    RAISE NOTICE 'V282: nationality filled from the state of origin on % student record(s)', n;
END $do$;

COMMIT;
