-- ═══════════════════════════════════════
-- V488 — A postgraduate specialisation from the application to the transcript
--
-- V483 gave a postgraduate programme its specialisations and let the School give a student theirs by hand. Now the
-- specialisation is carried end to end:
--
--   admissions.pg_application.specialisation_id   chosen on the application form among the programme's running ones
--   admissions.pg_set_specialisation(application, specialisation)   set or cleared (the form, the School's desk); a
--                                                  specialisation of the application's own programme; not once admitted
--                                                  (the student's own is changed on the programme structure then)
--   trigger: at admission (pg_admit sets the application's student) the application's specialisation becomes the student's
--   people.load_student_specialisations(programme, rows)   a file of (student number, specialisation code) rows, each set on
--                                                  the programme's own student, previewed by rolling it back like V487's upload
--   admissions.pg_coursework_audit(student)        the courses the programme requires of the student — Core and Research
--                                                  bindings at the student's level, for every student and for the student's
--                                                  own specialisation, never another specialisation's — each PASSED (a
--                                                  published pass under the course or an alternate, as V487 reads it),
--                                                  IN_PROGRESS (registered this session, no published pass) or OUTSTANDING
--   admissions.pg_next_steps                       restated with a COURSEWORK step: n of m required courses passed
--   credentials.build_statement                    restated with 'specialisation': named on the statement of result and the
--                                                  transcript where one is set
--
-- The offer of admission names the specialisation from the application (the API reads it). Nothing is written by this
-- migration.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V488: a postgraduate specialisation from the application to the transcript', true);

ALTER TABLE admissions.pg_application ADD COLUMN specialisation_id uuid REFERENCES catalogue.programme_specialisation (id);
CREATE INDEX ix_pg_application_specialisation ON admissions.pg_application (specialisation_id) WHERE specialisation_id IS NOT NULL;
COMMENT ON COLUMN admissions.pg_application.specialisation_id IS 'V488: the specialisation applied for, among the programme''s running ones; carried to the student at admission.';

CREATE FUNCTION admissions.pg_set_specialisation(p_application uuid, p_specialisation text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE a admissions.pg_application; v_id uuid; v_code text; v_in text := btrim(coalesce(p_specialisation, ''));
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_application;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such postgraduate application' USING ERRCODE = '23503'; END IF;
    IF a.student_id IS NOT NULL THEN
        RAISE EXCEPTION 'PG_SPECIALISATION_ADMITTED: the applicant is a student now; the School sets the student''s specialisation on the programme structure'
            USING ERRCODE = '23514';
    END IF;
    IF v_in = '' THEN
        UPDATE admissions.pg_application SET specialisation_id = NULL WHERE id = p_application AND specialisation_id IS NOT NULL;
        RETURN NULL;
    END IF;
    SELECT ps.id, ps.code INTO v_id, v_code FROM catalogue.programme_specialisation ps
     WHERE ps.programme_code = a.programme_code AND ps.active AND (ps.id::text = v_in OR ps.code = upper(v_in));
    IF v_id IS NULL THEN
        RAISE EXCEPTION 'PG_SPECIALISATION_OTHER: % is not a running specialisation of the programme applied for', v_in USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.pg_application SET specialisation_id = v_id WHERE id = p_application AND specialisation_id IS DISTINCT FROM v_id;
    RETURN v_code;
END $$;
COMMENT ON FUNCTION admissions.pg_set_specialisation(uuid, text) IS
  'V488: the specialisation applied for (its id or code), set or cleared; one of the programme''s running specialisations; not once admitted.';

CREATE FUNCTION admissions.pg_specialisation_to_student() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO people.student_specialisation (student_id, specialisation_id, set_by, set_office)
    VALUES (NEW.student_id, NEW.specialisation_id, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    ON CONFLICT (student_id) DO NOTHING;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_pg_application_specialisation AFTER UPDATE OF student_id ON admissions.pg_application
    FOR EACH ROW WHEN (OLD.student_id IS NULL AND NEW.student_id IS NOT NULL AND NEW.specialisation_id IS NOT NULL)
    EXECUTE FUNCTION admissions.pg_specialisation_to_student();
COMMENT ON FUNCTION admissions.pg_specialisation_to_student() IS 'V488: at admission the specialisation applied for becomes the student''s (one already set is kept).';

CREATE FUNCTION people.load_student_specialisations(p_programme text, p_rows jsonb)
RETURNS TABLE(row_no integer, number_in text, specialisation_in text, student_id uuid, name text, specialisation text, outcome text, message text)
LANGUAGE plpgsql AS $$
DECLARE r record; v_prog text := upper(btrim(coalesce(p_programme, ''))); v_st people.student; v_sp catalogue.programme_specialisation; v_now uuid;
BEGIN
    FOR r IN SELECT t.ord::integer AS ord, btrim(coalesce(t.x->>'number', '')) AS ni, btrim(coalesce(t.x->>'specialisation', '')) AS si
               FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) WITH ORDINALITY AS t(x, ord) LOOP
        row_no := r.ord; number_in := r.ni; specialisation_in := r.si; student_id := NULL; name := NULL; specialisation := NULL;
        v_st := NULL; v_sp := NULL;
        SELECT * INTO v_st FROM people.student s WHERE upper(s.matric_no) = upper(r.ni) OR upper(s.admission_no) = upper(r.ni)
         ORDER BY (upper(s.matric_no) = upper(r.ni)) DESC NULLS LAST LIMIT 1;
        SELECT * INTO v_sp FROM catalogue.programme_specialisation ps WHERE ps.programme_code = v_prog AND ps.code = upper(r.si);
        student_id := v_st.id; name := CASE WHEN v_st.id IS NOT NULL THEN v_st.surname || ', ' || v_st.other_names END; specialisation := v_sp.code;
        IF r.ni = '' OR r.si = '' THEN
            outcome := 'INCOMPLETE'; message := 'A row names the student''s number and the specialisation''s code.';
        ELSIF v_st.id IS NULL THEN
            outcome := 'NO_STUDENT'; message := 'No student has the number ' || r.ni || '.';
        ELSIF v_st.programme_code IS DISTINCT FROM v_prog THEN
            outcome := 'OTHER_PROGRAMME'; message := name || ' is a student of ' || v_st.programme_code || ', not of ' || v_prog || '.';
        ELSIF v_sp.id IS NULL THEN
            outcome := 'NO_SPECIALISATION'; message := v_prog || ' has no specialisation ' || upper(r.si) || '.';
        ELSIF NOT v_sp.active THEN
            outcome := 'ENDED'; message := 'The specialisation ' || v_sp.code || ' has ended; it is no longer given.';
        ELSE
            SELECT ss.specialisation_id INTO v_now FROM people.student_specialisation ss WHERE ss.student_id = v_st.id;
            IF v_now = v_sp.id THEN
                outcome := 'ALREADY'; message := name || ' reads ' || v_sp.code || ' already.';
            ELSE
                PERFORM people.set_student_specialisation(v_st.id, v_sp.id);
                outcome := CASE WHEN v_now IS NULL THEN 'SET' ELSE 'CHANGED' END;
                message := name || CASE WHEN v_now IS NULL THEN ' given ' ELSE ' moved to ' END || v_sp.code || ' — ' || v_sp.name || '.';
            END IF;
        END IF;
        RETURN NEXT;
    END LOOP;
END $$;
COMMENT ON FUNCTION people.load_student_specialisations(text, jsonb) IS
  'V488: a file of (student number, specialisation code) rows set on the programme''s own students, each row''s outcome returned; previewed by rolling back.';

CREATE FUNCTION admissions.pg_coursework_audit(p_student uuid)
RETURNS TABLE(course_code text, title text, units integer, level integer, basis text, specialisation text, state text)
LANGUAGE sql STABLE AS $$
    WITH st AS (
        SELECT s.id, s.programme_code, s.current_level,
               (SELECT ss.specialisation_id FROM people.student_specialisation ss
                  JOIN catalogue.programme_specialisation ps ON ps.id = ss.specialisation_id AND ps.programme_code = s.programme_code
                 WHERE ss.student_id = s.id) AS spec,
               CASE WHEN s.entry_mode = 'POSTGRADUATE' THEN admissions.pg_current_session() ELSE policy.university_current_session() END AS session
          FROM people.student s JOIN ref.programme g ON g.code = s.programme_code AND g.category = 'POST GRADUATE'   -- a postgraduate programme's students only
         WHERE s.id = p_student),
    -- the programme's required courses at the student's level (a postgraduate level is the award's, held for the whole
    -- programme): those for every student, and those of their specialisation
    req AS (
        SELECT co.course_code, c.title, catalogue.units_for(co.course_code, co.programme_code, co.level) AS units, co.level, co.basis,
               (SELECT string_agg(ps.code, ', ' ORDER BY ps.code) FROM catalogue.course_offer_specialisation x
                  JOIN catalogue.programme_specialisation ps ON ps.id = x.specialisation_id
                 WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code AND x.level = co.level) AS for_spec
          FROM st
          JOIN catalogue.course_offer co ON co.programme_code = st.programme_code AND co.level = st.current_level AND co.basis IN ('Core', 'Research')
          JOIN catalogue.course c ON c.code = co.course_code AND c.state <> 'ENDED'
         WHERE NOT EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x
                            WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code AND x.level = co.level)
            OR EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x
                        WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code AND x.level = co.level
                          AND x.specialisation_id = st.spec)),
    passed AS (
        SELECT registration.passed_codes(p_student,
                   ARRAY(SELECT a FROM req, unnest(registration.prerequisite_alternates(req.course_code)) a)) AS codes)
    SELECT r.course_code, r.title, r.units, r.level, r.basis, r.for_spec,
           CASE WHEN registration.prerequisite_alternates(r.course_code) && (SELECT codes FROM passed) THEN 'PASSED'
                WHEN EXISTS (SELECT 1 FROM registration.course_registration g
                               JOIN registration.entry e ON e.registration_id = g.id AND e.status IN ('REGISTERED', 'APPROVED')
                               JOIN catalogue.offering o ON o.id = e.offering_id
                              WHERE g.student_id = p_student AND g.session = (SELECT session FROM st)
                                AND o.course_code = ANY (registration.prerequisite_alternates(r.course_code))) THEN 'IN_PROGRESS'
                ELSE 'OUTSTANDING' END
      FROM req r
     ORDER BY r.level, r.course_code
$$;
COMMENT ON FUNCTION admissions.pg_coursework_audit(uuid) IS
  'V488: the courses a postgraduate programme requires of the student (Core and Research at their level, for every student and for their specialisation): PASSED, IN_PROGRESS or OUTSTANDING.';

CREATE OR REPLACE FUNCTION admissions.pg_next_steps(p_student uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE st people.student; app admissions.pg_application; s text; sem int; v_gate text; reg registration.course_registration;
        pos record; stated boolean; fw record; steps jsonb := '[]'::jsonb; n_units int; n_courses int; n_results int; v_card boolean;
        n_required int; n_passed int; n_progress int;
BEGIN
    SELECT * INTO st FROM people.student WHERE id = p_student;
    IF st.id IS NULL OR st.entry_mode IS DISTINCT FROM 'POSTGRADUATE' THEN RETURN steps; END IF;
    SELECT * INTO app FROM admissions.pg_application WHERE student_id = p_student ORDER BY admitted_at DESC NULLS LAST LIMIT 1;
    s := people.student_current_session(p_student);
    sem := registration.open_semester(p_student, s);

    -- admission and the offer
    IF app.id IS NOT NULL THEN
        steps := steps || jsonb_build_object('key', 'ADMISSION', 'state', 'DONE', 'label', 'Admitted',
                 'detail', 'Application ' || app.application_no || coalesce(', admitted on ' || to_char(app.admitted_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY'), ''),
                 'href', CASE WHEN app.acceptance_confirmed_at IS NOT NULL THEN '/student/pg-offer/pdf' END, 'action', CASE WHEN app.acceptance_confirmed_at IS NOT NULL THEN 'Offer of admission' END);
    END IF;

    -- school fees: stated, paid, payable
    stated := coalesce(finance.fee_stated(p_student, s), false);
    SELECT * INTO pos FROM finance.position(p_student, s);
    SELECT * INTO fw FROM policy.window_state(policy.window_type_for(p_student, 'SCHOOL_FEES_PAYMENT'), s, NULL);
    steps := steps || CASE
        WHEN NOT stated THEN jsonb_build_object('key', 'FEES', 'state', 'WAITING', 'label', 'School fees', 'detail', 'The Bursary has not yet stated the school fees of ' || s || ' for your programme.')
        WHEN coalesce(pos.paid_in_full, false) THEN jsonb_build_object('key', 'FEES', 'state', 'DONE', 'label', 'School fees paid', 'detail', s, 'href', '/student/fees', 'action', 'Receipts')
        WHEN fw.state = 'OPEN' THEN jsonb_build_object('key', 'FEES', 'state', 'ACTION', 'label', 'Pay school fees',
                 'detail', 'Outstanding for ' || s || ': ' || to_char(coalesce(pos.balance, 0), 'FM999,999,999,990.00'), 'href', '/student/fees', 'action', 'Pay school fees')
        ELSE jsonb_build_object('key', 'FEES', 'state', 'BLOCKED', 'label', 'School fees', 'detail', 'School fees payment is ' || lower(coalesce(fw.state, 'closed')) || ' for ' || s || coalesce(': ' || fw.reason, '.'), 'href', '/student/fees') END;

    -- course registration in the School's semester
    SELECT * INTO reg FROM registration.course_registration WHERE student_id = p_student AND session = s AND semester = sem;
    SELECT count(*), coalesce(sum(e.units), 0) INTO n_courses, n_units FROM registration.entry e WHERE e.registration_id = reg.id AND e.status IN ('REGISTERED', 'APPROVED');
    v_gate := registration.registration_gate(p_student, s, sem);
    steps := steps || CASE
        WHEN reg.status IN ('APPROVED', 'LOCKED') THEN jsonb_build_object('key', 'REGISTRATION', 'state', 'DONE', 'label', 'Registered',
                 'detail', s || ', ' || CASE sem WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END || ' semester: ' || n_courses || ' course(s), ' || n_units || ' units', 'href', '/student/register', 'action', 'Course form')
        WHEN reg.status = 'SUBMITTED' THEN jsonb_build_object('key', 'REGISTRATION', 'state', 'WAITING', 'label', 'Registration submitted', 'detail', 'Awaiting your Head of Department''s approval', 'href', '/student/register')
        WHEN reg.status IN ('DRAFT', 'RETURNED') AND v_gate IS NULL THEN jsonb_build_object('key', 'REGISTRATION', 'state', 'ACTION', 'label', CASE WHEN reg.status = 'RETURNED' THEN 'Registration returned for correction' ELSE 'Finish your course registration' END,
                 'detail', coalesce(reg.returned_comment, s), 'href', '/student/register', 'action', 'Course registration')
        WHEN v_gate IS NULL THEN jsonb_build_object('key', 'REGISTRATION', 'state', 'ACTION', 'label', 'Register your courses', 'detail', s || ', ' || CASE sem WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END || ' semester', 'href', '/student/register', 'action', 'Course registration')
        ELSE jsonb_build_object('key', 'REGISTRATION', 'state', 'BLOCKED', 'label', 'Course registration', 'detail', v_gate) END;

    -- the examination card, once the School's examination cards are out and the registration approved
    v_card := reg.status IN ('APPROVED', 'LOCKED') AND EXISTS (SELECT 1 FROM assessment.exam_session x WHERE x.session = s AND x.stream = 'PG' AND x.cards_released_at IS NOT NULL AND x.state <> 'DRAFT');
    IF v_card THEN
        steps := steps || jsonb_build_object('key', 'EXAMINATION', 'state', 'ACTION', 'label', 'Examination card', 'detail', s, 'href', '/student/exams', 'action', 'Examination card');
    END IF;

    -- results published this session
    SELECT count(*) INTO n_results FROM admissions.pg_course_results(p_student) x WHERE x.session = s;
    IF n_results > 0 THEN
        steps := steps || jsonb_build_object('key', 'RESULTS', 'state', 'DONE', 'label', 'Results published', 'detail', n_results || ' course(s) in ' || s, 'href', '/student/pg-progress', 'action', 'Results');
    END IF;

    -- V488: the coursework the programme requires of the student (theirs and their specialisation's), passed so far
    SELECT count(*), count(*) FILTER (WHERE x.state = 'PASSED'), count(*) FILTER (WHERE x.state = 'IN_PROGRESS')
      INTO n_required, n_passed, n_progress FROM admissions.pg_coursework_audit(p_student) x;
    IF n_required > 0 THEN
        steps := steps || jsonb_build_object('key', 'COURSEWORK',
                 'state', CASE WHEN n_passed = n_required THEN 'DONE' WHEN n_progress > 0 THEN 'WAITING' ELSE 'ACTION' END,
                 'label', CASE WHEN n_passed = n_required THEN 'Required coursework passed' ELSE 'Required coursework' END,
                 'detail', n_passed || ' of ' || n_required || ' required course(s) passed'
                           || CASE WHEN n_progress > 0 THEN ', ' || n_progress || ' awaiting results' ELSE '' END
                           || coalesce('; specialisation ' || (SELECT ps.name FROM people.student_specialisation ss
                                                                JOIN catalogue.programme_specialisation ps ON ps.id = ss.specialisation_id AND ps.programme_code = st.programme_code
                                                               WHERE ss.student_id = p_student), ''),
                 'href', '/student/pg-progress', 'action', 'Coursework');
    END IF;

    -- matriculation
    steps := steps || CASE WHEN st.matric_no IS NOT NULL
        THEN jsonb_build_object('key', 'MATRICULATION', 'state', 'DONE', 'label', 'Matriculated', 'detail', st.matric_no)
        ELSE jsonb_build_object('key', 'MATRICULATION', 'state', 'WAITING', 'label', 'Matriculation pending', 'detail', 'Your matriculation number is issued after your registration is approved and your fees are settled.') END;
    RETURN steps;
END $function$;
COMMENT ON FUNCTION admissions.pg_next_steps(uuid) IS
  'V389: the PG student''s next steps worked out from the record — the offer, fees, registration, examination card, results and matriculation — each only when it applies. V488: the required coursework passed so far.';

CREATE OR REPLACE FUNCTION credentials.build_statement(p_student uuid, p_kind text, p_session text, p_semester integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE st record; g record; pol credentials.document_policy; v_sessions jsonb; v_cgpa numeric; v_class text; v_scope text; v_cur text; v_cur_sem int;
        v_pg boolean; v_research jsonb; v_totals record; v_semesters jsonb;
BEGIN
    SELECT s.id, s.surname, s.other_names, s.matric_no, s.admission_no, s.entry_mode, s.entry_session, s.entry_level, s.current_level, s.status, s.programme_code, s.study_mode,
           p.name AS programme, p.dept_code, d.name AS department, p.faculty_code, f.name AS faculty, coalesce(p.pg_award, p.name) AS award_name
      INTO st FROM people.student s JOIN ref.programme p ON p.code = s.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE s.id = p_student;
    IF st.id IS NULL THEN RAISE EXCEPTION 'no student record' USING ERRCODE = '23503'; END IF;
    SELECT * INTO pol FROM credentials.document_policy WHERE kind = p_kind;
    SELECT * INTO g FROM records.graduand gg WHERE gg.student_id = p_student AND gg.senate_state = 'APPROVED' ORDER BY gg.session DESC LIMIT 1;
    v_pg := st.entry_mode = 'POSTGRADUATE' OR EXISTS (SELECT 1 FROM admissions.pg_registration r WHERE r.student_id = p_student);
    v_cur := (SELECT name FROM policy.academic_session WHERE state = 'CURRENT');
    v_cur_sem := (SELECT number FROM policy.semester WHERE session = v_cur AND state = 'OPEN' ORDER BY number DESC LIMIT 1);
    -- V381: a CCE student's current semester is the CCE calendar's
    IF st.entry_mode = 'CCE' THEN
        v_cur := policy.route_session('CCE');
        v_cur_sem := (SELECT number FROM policy.route_semester WHERE route = 'CCE' AND session = v_cur AND state = 'OPEN' ORDER BY number DESC LIMIT 1);
    END IF;
    -- the scope of the document
    v_scope := CASE p_kind WHEN 'SESSIONAL_TRANSCRIPT' THEN 'SELECTED_SESSION' WHEN 'MINI_TRANSCRIPT' THEN pol.includes ELSE 'CUMULATIVE' END;
    IF NOT v_pg THEN
        SELECT jsonb_agg(jsonb_build_object('session', q.session, 'semesters', q.semesters) ORDER BY q.session) INTO v_sessions
          FROM (SELECT r.session,
                       jsonb_agg(jsonb_build_object('semester', r.semester, 'courses', r.courses, 'units', gp.units, 'gpa', gp.gpa, 'cgpa', gp.cgpa, 'tcr', gp.tcr, 'tce', gp.tce, 'twgp', gp.twgp) ORDER BY r.semester) AS semesters
                  FROM (SELECT x.session, x.semester,
                               jsonb_agg(jsonb_build_object('code', x.course_code, 'title', x.title, 'units', x.units, 'grade', x.grade, 'points', x.points, 'quality', round(coalesce(x.points, 0) * x.units, 2), 'type', x.entry_type, 'outcome', x.outcome) ORDER BY x.course_code) AS courses
                          FROM assessment.student_results(p_student) x
                         WHERE x.published
                           AND (v_scope = 'CUMULATIVE' OR (v_scope = 'SELECTED_SESSION' AND x.session = p_session)
                                OR (v_scope = 'SELECTED_SEMESTER' AND x.session = p_session AND x.semester = p_semester)
                                OR (v_scope = 'CURRENT_SEMESTER' AND x.session = v_cur AND x.semester = coalesce(v_cur_sem, x.semester)))
                         GROUP BY x.session, x.semester) r
                  LEFT JOIN assessment.student_gpa(p_student) gp ON gp.session = r.session AND gp.semester = r.semester
                 GROUP BY r.session) q;
        SELECT coalesce(max(cgpa) FILTER (WHERE (session, semester) = (SELECT session, semester FROM assessment.student_gpa(p_student) ORDER BY session DESC, semester DESC LIMIT 1)), 0) INTO v_cgpa FROM assessment.student_gpa(p_student);
        IF g.cgpa IS NOT NULL THEN v_cgpa := g.cgpa; END IF;
        v_class := CASE WHEN g.student_id IS NOT NULL THEN coalesce(policy.class_of(g.cgpa), 'Pass') ELSE policy.class_of(v_cgpa) END;
        v_research := NULL;
    ELSE
        SELECT jsonb_agg(jsonb_build_object('session', q.session, 'semesters', q.semesters) ORDER BY q.session) INTO v_sessions
          FROM (SELECT r.session,
                       jsonb_agg(jsonb_build_object('semester', r.semester, 'courses', r.courses, 'units', r.units, 'gpa', admissions.pg_gpa(p_student, r.session, r.semester)) ORDER BY r.semester) AS semesters
                  -- V389: the old coursework's scores and the published results of the School's classes alike
                  FROM (SELECT x.session, x.semester, sum(x.units) FILTER (WHERE x.kind <> 'DEFICIENCY') AS units,
                               jsonb_agg(jsonb_build_object('code', x.code, 'title', x.title, 'units', x.units, 'grade', x.grade, 'points', x.points, 'quality', round(x.points * x.units, 2), 'type', x.kind) ORDER BY x.code) AS courses
                          FROM admissions.pg_course_results(p_student) x
                         WHERE (v_scope = 'CUMULATIVE' OR (v_scope = 'SELECTED_SESSION' AND x.session = p_session)
                                OR (v_scope = 'SELECTED_SEMESTER' AND x.session = p_session AND x.semester = p_semester)
                                OR (v_scope = 'CURRENT_SEMESTER' AND x.session = v_cur))
                         GROUP BY x.session, x.semester) r
                 GROUP BY r.session) q;
        v_cgpa := coalesce(g.cgpa, admissions.pg_cgpa(p_student));
        v_class := CASE WHEN g.student_id IS NOT NULL THEN 'Awarded' ELSE NULL END;
        SELECT jsonb_build_object('kind', pr.degree_kind, 'topic', pr.topic, 'stage', pr.stage, 'vivaGrade', pr.viva_grade, 'awardedAt', pr.awarded_at) INTO v_research
          FROM admissions.pg_research pr WHERE pr.student_id = p_student;
    END IF;
    RETURN jsonb_strip_nulls(jsonb_build_object(
        'holder', st.surname || ', ' || st.other_names,
        'matricNo', st.matric_no, 'admissionNo', st.admission_no,
        'programme', st.programme, 'programmeCode', st.programme_code, 'department', st.department, 'faculty', st.faculty,
        -- V488: a postgraduate student's specialisation within the programme, where one is set
        'specialisation', (SELECT ps.name FROM people.student_specialisation ss
                             JOIN catalogue.programme_specialisation ps ON ps.id = ss.specialisation_id AND ps.programme_code = st.programme_code
                            WHERE ss.student_id = p_student),
        'award', CASE WHEN g.student_id IS NOT NULL THEN coalesce(g.award, st.award_name) ELSE st.award_name END,
        'entryMode', st.entry_mode, 'entrySession', st.entry_session, 'entryLevel', st.entry_level, 'level', st.current_level, 'status', st.status,
        -- V381: the mode of study and the route, and for CCE the Centre and the programme's duration on it
        'studyMode', CASE st.study_mode WHEN 'PART_TIME' THEN 'Part-time' ELSE 'Full-time' END,
        'route', CASE WHEN st.entry_mode = 'CCE' THEN 'Centre for Continuing Education (CCE)' END,
        'centre', CASE WHEN st.entry_mode = 'CCE' THEN (SELECT u.name FROM policy.study_route r JOIN ref.unit u ON u.code = r.centre_unit WHERE r.code = 'CCE') END,
        'durationYears', CASE WHEN st.entry_mode = 'CCE' THEN (SELECT t.duration_years FROM ref.programme_route_terms(st.programme_code, 'CCE') t) END,
        'postgraduate', v_pg, 'scope', v_scope, 'session', p_session, 'semester', p_semester,
        'sessions', coalesce(v_sessions, '[]'::jsonb),
        'cgpa', v_cgpa, 'classOfDegree', v_class,
        'standing', CASE WHEN g.student_id IS NOT NULL THEN 'Graduated' WHEN st.status = 'GRADUATED' THEN 'Graduated' ELSE initcap(lower(replace(st.status, '_', ' '))) END,
        'graduationSession', g.session, 'graduationMinute', g.senate_minute,
        'graduationDate', CASE WHEN g.student_id IS NOT NULL THEN (SELECT ends_on FROM policy.academic_session WHERE name = g.session) END,
        'research', v_research,
        'gradingScale', (SELECT jsonb_agg(jsonb_build_object('grade', b.grade, 'low', b.low, 'high', b.high, 'points', b.points) ORDER BY b.points DESC)
                           FROM policy.grade_band b WHERE b.version_id = policy.in_force('grading', 'UNIVERSITY', current_date)),
        'classificationBands', (SELECT jsonb_agg(jsonb_build_object('class', b.class, 'low', b.low, 'high', b.high) ORDER BY b.ord)
                                  FROM policy.classification_band b WHERE b.version_id = policy.in_force('classification', 'UNIVERSITY', current_date))
    ));
END $function$;

COMMIT;
