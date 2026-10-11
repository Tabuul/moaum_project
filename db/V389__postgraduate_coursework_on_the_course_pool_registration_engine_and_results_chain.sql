-- V389 — Postgraduate coursework on the University's own engines.
--
-- The School of Postgraduate Studies kept a coursework system of its own (V211): a course list per programme
-- (admissions.pg_course), registrations (pg_registration), scores endorsed outside the results chain (pg_score) and a
-- GPA of its own. From now on a postgraduate student is a stream of the one portal, as the Centre for Continuing
-- Education's students are (V380, V381):
--
--   1 · Courses: every PG course is a course of the University's pool (catalogue.course), held once whatever the number
--       of programmes that take it, bound to each programme at its level (catalogue.course_offer; a deficiency course is
--       bound as Deficiency and earns no credit, a research course as Research). admissions.pg_course keeps its rows,
--       each now naming the course it is (course_code).
--   2 · Classes and registration: the stream PG. The School opens its classes in its own session (catalogue.pg_open_
--       classes); a PG student registers on the University's registration engine, on the School's calendar
--       (admissions.pg_semester) and behind the PG windows the Directorate of ICT holds (PG_COURSE_REGISTRATION,
--       PG_SCHOOL_FEES_PAYMENT); the Head of Department approves as for every student. The old registration closes to
--       new registrations (PG_REGISTRATION_MOVED); what it holds stays and is read.
--   3 · Results: PG examination sessions release score sheets to the PG classes, which move on the one results chain;
--       a PG class is graded on the School's scale (policy version 'grading' scope POSTGRADUATE: A 70, B 60, C 50, F —
--       the scale admissions.pg_grade applied), read wherever a sheet is read. The PG GPA, CGPA, statement and transcript
--       read both the old coursework and the published results (admissions.pg_course_results).
--   4 · Notices: eligible PG students are told by email and SMS when PG course registration opens and when it is about to
--       close (admissions.pg_tell_registration); applicants' notices also go by SMS.
--   5 · The student's next steps, worked out by the database (admissions.pg_next_steps): fees, registration, examination,
--       results, matriculation and the documents, each only when it applies.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V389: postgraduate coursework on the University''s course pool, registration engine and results chain', true);

-- ── 1 · the postgraduate stream ───────────────────────────────────────────────────────────────────────────────────
ALTER TABLE catalogue.offering DROP CONSTRAINT ck_offering_stream;
ALTER TABLE catalogue.offering ADD CONSTRAINT ck_offering_stream CHECK (stream IN ('REGULAR', 'CCE', 'PG'));
ALTER TABLE assessment.exam_session DROP CONSTRAINT ck_exam_session_stream;
ALTER TABLE assessment.exam_session ADD CONSTRAINT ck_exam_session_stream CHECK (stream IN ('REGULAR', 'CCE', 'PG'));
COMMENT ON COLUMN catalogue.offering.stream IS
  'V380/V389: whose class it is — the full-time students'' (REGULAR), the Centre for Continuing Education''s (CCE) or the School of Postgraduate Studies'' (PG), each in its own session.';

CREATE OR REPLACE FUNCTION people.student_stream(p_student uuid)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN s.entry_mode = 'CCE' THEN 'CCE' WHEN s.entry_mode = 'POSTGRADUATE' THEN 'PG' ELSE 'REGULAR' END FROM people.student s WHERE s.id = p_student
$fn$;

-- ── 2 · the School's calendar is a PG student's calendar ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.calendar_semester(p_student uuid, p_session text, p_semester integer)
RETURNS TABLE(state text, registration_opens date, registration_closes date, late_registration_closes date, fresh_registration_from date, lectures_from date, lectures_to date, calendar text)
LANGUAGE sql STABLE AS $fn$
    SELECT rs.state, rs.registration_opens, rs.registration_closes, rs.late_registration_closes, NULL::date, rs.lectures_from, rs.lectures_to, 'CCE'
      FROM policy.route_semester rs
     WHERE people.student_stream(p_student) = 'CCE' AND rs.route = 'CCE' AND rs.session = p_session AND rs.number = p_semester
    UNION ALL
    -- V389: the School of Postgraduate Studies' semester
    SELECT ps.state, ps.registration_opens, ps.registration_closes, ps.registration_closes, NULL::date, ps.lectures_from, ps.lectures_to, 'PG'
      FROM admissions.pg_semester ps
     WHERE people.student_stream(p_student) = 'PG' AND ps.session = p_session AND ps.number = p_semester
    UNION ALL
    SELECT sm.state, sm.registration_opens, sm.registration_closes, sm.late_registration_closes, sm.fresh_registration_from, sm.lectures_from, sm.lectures_to, 'FULL_TIME'
      FROM policy.semester sm
     WHERE people.student_stream(p_student) = 'REGULAR' AND sm.session = p_session AND sm.number = p_semester
$fn$;

CREATE OR REPLACE FUNCTION registration.open_semester(p_student uuid, p_session text)
RETURNS integer LANGUAGE sql STABLE AS $fn$
    SELECT CASE people.student_stream(p_student)
                WHEN 'CCE' THEN coalesce((SELECT max(rs.number) FROM policy.route_semester rs WHERE rs.route = 'CCE' AND rs.session = p_session AND rs.state = 'OPEN'), 1)
                WHEN 'PG' THEN coalesce((SELECT max(ps.number) FROM admissions.pg_semester ps WHERE ps.session = p_session AND ps.state = 'OPEN'), 1)
                ELSE coalesce((SELECT max(sm.number) FROM policy.semester sm WHERE sm.session = p_session AND sm.state = 'OPEN'), 1) END
$fn$;

CREATE OR REPLACE FUNCTION registration.add_drop_open(p_student uuid, p_session text, p_semester integer)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT CASE people.student_stream(p_student)
                WHEN 'CCE' THEN EXISTS (SELECT 1 FROM policy.route_semester rs
                                         WHERE rs.route = 'CCE' AND rs.session = p_session AND rs.number = p_semester AND rs.state = 'OPEN'
                                           AND current_date <= coalesce(rs.late_registration_closes, rs.registration_closes, current_date))
                WHEN 'PG' THEN EXISTS (SELECT 1 FROM admissions.pg_semester ps
                                        WHERE ps.session = p_session AND ps.number = p_semester AND ps.state = 'OPEN'
                                          AND current_date <= coalesce(ps.registration_closes, current_date))
                ELSE registration.add_drop_open(p_session, p_semester) END
$fn$;

CREATE OR REPLACE FUNCTION people.student_current_session(p_student uuid)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE people.student_stream(p_student)
                WHEN 'CCE' THEN policy.route_session('CCE')
                WHEN 'PG' THEN admissions.pg_current_session()
                ELSE (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1) END
$fn$;

CREATE OR REPLACE FUNCTION people.period_start(p_student uuid, p_session text, p_semester integer)
RETURNS date LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(
        (SELECT coalesce(rs.lectures_from, rs.registration_opens) FROM policy.route_semester rs
          WHERE people.student_stream(p_student) = 'CCE' AND rs.route = 'CCE' AND rs.session = p_session AND rs.number = coalesce(p_semester, 1)),
        (SELECT coalesce(ps.lectures_from, ps.registration_opens) FROM admissions.pg_semester ps
          WHERE people.student_stream(p_student) = 'PG' AND ps.session = p_session AND ps.number = coalesce(p_semester, 1)),
        people.period_start(p_session, p_semester))
$fn$;

CREATE OR REPLACE FUNCTION people.period_end(p_student uuid, p_session text, p_semester integer)
RETURNS date LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(
        (SELECT coalesce(rs.exams_to, rs.lectures_to) FROM policy.route_semester rs
          WHERE people.student_stream(p_student) = 'CCE' AND rs.route = 'CCE' AND rs.session = p_session AND rs.number = p_semester),
        (SELECT coalesce(ps.exams_to, ps.lectures_to) FROM admissions.pg_semester ps
          WHERE people.student_stream(p_student) = 'PG' AND ps.session = p_session AND ps.number = p_semester),
        people.period_end(p_session, p_semester))
$fn$;

-- ── 3 · the PG windows the Directorate of ICT holds ───────────────────────────────────────────────────────────────
ALTER TABLE policy.portal_window DROP CONSTRAINT portal_window_window_type_check;
ALTER TABLE policy.portal_window ADD CONSTRAINT portal_window_window_type_check CHECK (window_type = ANY (ARRAY[
    'SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION',
    'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION',
    'CCE_SCHOOL_FEES_PAYMENT', 'CCE_COURSE_REGISTRATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING',
    'PG_SCHOOL_FEES_PAYMENT', 'PG_COURSE_REGISTRATION']));

CREATE OR REPLACE FUNCTION policy.window_type_for(p_student uuid, p_type text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN p_type IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION') AND people.student_stream(p_student) = 'CCE' THEN 'CCE_' || p_type
                WHEN p_type IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION') AND people.student_stream(p_student) = 'PG' THEN 'PG_' || p_type
                ELSE p_type END
$fn$;

/* whether PG course registration is open for a session's semester: the School's classes set up, the School's semester
   open and within its dates, and the PG window open where the Directorate of ICT holds one — null when open, else why not */
CREATE FUNCTION registration.pg_gate_of(p_session text, p_semester integer)
RETURNS text LANGUAGE sql STABLE AS $fn$
    WITH ps AS (SELECT * FROM admissions.pg_semester WHERE session = p_session AND number = p_semester),
         w AS (SELECT CASE p_semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END AS ord)
    SELECT CASE
             WHEN NOT EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.session = p_session AND o.semester = p_semester AND o.stream = 'PG')
                  THEN 'Course registration for the ' || w.ord || ' semester of ' || p_session || ' opens when the School of Postgraduate Studies'' classes for it are set up.'
             WHEN pw.configured AND pw.state = 'CLOSED' THEN 'Postgraduate course registration is currently closed for ' || p_session || ' ' || w.ord || ' semester.' || coalesce(' ' || pw.reason, '')
             WHEN pw.configured AND pw.state = 'SCHEDULED' THEN 'Postgraduate course registration for ' || p_session || ' ' || w.ord || ' semester opens on ' || to_char(pw.opens_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY HH24:MI') || '.'
             WHEN pw.configured AND pw.state = 'EXPIRED' THEN 'Postgraduate course registration for ' || p_session || ' ' || w.ord || ' semester closed on ' || to_char(coalesce(pw.late_until, pw.closes_at) AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY HH24:MI') || '.'
             WHEN pw.configured AND pw.state = 'OPEN' THEN NULL
             WHEN ps.session IS NULL THEN 'The School of Postgraduate Studies has not yet opened the ' || w.ord || ' semester of ' || p_session || ' for registration.'
             WHEN ps.state = 'CLOSED' THEN 'The ' || w.ord || ' semester of ' || p_session || ' is closed for postgraduate registration.'
             WHEN ps.state = 'NOT_YET_OPEN' THEN 'The ' || w.ord || ' semester of ' || p_session || ' is not yet open for postgraduate registration'
                  || coalesce('; registration opens on ' || to_char(ps.registration_opens, 'FMDD FMMonth YYYY'), '') || '.'
             WHEN ps.registration_opens IS NOT NULL AND current_date < ps.registration_opens
                  THEN 'Postgraduate course registration for the ' || w.ord || ' semester of ' || p_session || ' opens on ' || to_char(ps.registration_opens, 'FMDD FMMonth YYYY') || '.'
             WHEN ps.registration_closes IS NOT NULL AND current_date > ps.registration_closes
                  THEN 'Postgraduate course registration for the ' || w.ord || ' semester of ' || p_session || ' closed on ' || to_char(ps.registration_closes, 'FMDD FMMonth YYYY') || '.'
             ELSE NULL END
      FROM w LEFT JOIN ps ON true LEFT JOIN LATERAL (SELECT * FROM policy.window_state('PG_COURSE_REGISTRATION', p_session, p_semester)) pw ON true
$fn$;
COMMENT ON FUNCTION registration.pg_gate_of(text, integer) IS
  'V389: null when postgraduate course registration is open for the semester, else why not — the School''s classes, its semester and dates, and the PG window where held.';

-- ── 4 · the School's classes ──────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION catalogue.pg_require_office(p_what text)
RETURNS void LANGUAGE plpgsql STABLE AS $fn$
BEGIN
    IF coalesce(nullif(current_setting('moaum.actor_office', true), ''), '') NOT IN ('pgschool', 'pgsecretary', 'academic', 'super') THEN
        RAISE EXCEPTION 'PG_OFFICE: % is the School of Postgraduate Studies'' or the Academic Office''s', p_what USING ERRCODE = '23514';
    END IF;
END $fn$;

/* the session a PG class may be opened in: a session of the School's calendar that is not closed, and on the University's */
CREATE FUNCTION catalogue.pg_class_session(p_session text)
RETURNS void LANGUAGE plpgsql STABLE AS $fn$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admissions.pg_academic_session WHERE name = p_session AND state <> 'CLOSED')
       OR NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN
        RAISE EXCEPTION 'PG_CLASS_SESSION: % is not an open session of the School of Postgraduate Studies'' calendar', p_session USING ERRCODE = '23514';
    END IF;
END $fn$;

/* every class the School's semester needs, opened at once: the courses bound to its programmes with students, taught in
   the semester, and the carryovers its students owe */
CREATE FUNCTION catalogue.pg_open_classes(p_session text, p_semester integer)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
    PERFORM catalogue.pg_require_office('opening the School''s classes');
    IF p_semester IS NULL OR p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'PG_CLASS_SEMESTER: a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    PERFORM catalogue.pg_class_session(p_session);
    WITH live AS (SELECT DISTINCT st.programme_code, st.curriculum_track FROM people.student st
                   WHERE st.entry_mode = 'POSTGRADUATE' AND st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
    offered AS (
        SELECT DISTINCT c.code
          FROM catalogue.course c
          JOIN catalogue.course_offer co ON co.course_code = c.code
          JOIN ref.programme p ON p.code = co.programme_code AND p.category = 'POST GRADUATE'
         WHERE catalogue.runs_in(c.semester, c.both_semesters, p_semester) AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
           AND EXISTS (SELECT 1 FROM live l WHERE l.programme_code = co.programme_code
                          AND (co.track IS NULL OR l.curriculum_track IS NULL OR l.curriculum_track = co.track))
        UNION
        SELECT DISTINCT c.code
          FROM people.student st
          CROSS JOIN LATERAL registration.carryovers(st.id) cv
          JOIN catalogue.course c ON c.code = cv.course_code
         WHERE st.entry_mode = 'POSTGRADUATE' AND st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
           AND catalogue.runs_in(c.semester, c.both_semesters, p_semester) AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %')
    INSERT INTO catalogue.offering (id, course_code, session, semester, stream)
    SELECT gen_random_uuid(), o.code, p_session, p_semester, 'PG' FROM offered o
    ON CONFLICT (course_code, session, semester, stream) DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION catalogue.pg_open_classes(text, integer) IS
  'V389: the School of Postgraduate Studies opens its semester''s classes (stream PG) in its own session; the Head of Department allocates their lecturers as for every class.';

/* one class added by hand: a course of the pool, in the School's session */
CREATE FUNCTION catalogue.pg_add_class(p_course text, p_session text, p_semester integer)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_code text := catalogue.resolve_course_code(p_course); v uuid;
BEGIN
    PERFORM catalogue.pg_require_office('a class of the School');
    IF p_semester IS NULL OR p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'PG_CLASS_SEMESTER: a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    PERFORM catalogue.pg_class_session(p_session);
    IF NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_code AND state <> 'ENDED') THEN
        RAISE EXCEPTION 'PG_CLASS_COURSE: % is not a live course of the pool', p_course USING ERRCODE = '23514';
    END IF;
    INSERT INTO catalogue.offering (id, course_code, session, semester, stream) VALUES (gen_random_uuid(), v_code, p_session, p_semester, 'PG')
    ON CONFLICT (course_code, session, semester, stream) DO UPDATE SET semester = EXCLUDED.semester RETURNING id INTO v;
    RETURN v;
END $fn$;

-- ── 5 · the PG courses in the University's pool ───────────────────────────────────────────────────────────────────
ALTER TABLE catalogue.course_offer DROP CONSTRAINT ck_offer_basis;
ALTER TABLE catalogue.course_offer ADD CONSTRAINT ck_offer_basis CHECK (basis IN ('Core', 'Elective', 'Borrowed', 'GST', 'Deficiency', 'Research'));
COMMENT ON COLUMN catalogue.course_offer.basis IS
  'Core, Elective, Borrowed or GST; V389: Deficiency (a postgraduate student makes up a deficiency; it earns no credit) and Research (a postgraduate research course).';

ALTER TABLE admissions.pg_course ADD COLUMN course_code text REFERENCES catalogue.course (code) ON UPDATE CASCADE ON DELETE SET NULL;
CREATE INDEX ix_pg_course_course ON admissions.pg_course (course_code);
COMMENT ON COLUMN admissions.pg_course.course_code IS
  'V389: the course of the University''s pool this row is; the old registrations and scores keep pointing at the row, the new ones are on the pool''s classes.';

CREATE FUNCTION catalogue.pg_kind_basis(p_kind text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE upper(coalesce(p_kind, '')) WHEN 'ELECTIVE' THEN 'Elective' WHEN 'DEFICIENCY' THEN 'Deficiency' WHEN 'RESEARCH' THEN 'Research' ELSE 'Core' END
$fn$;

/* a PG course into the pool and bound to its programme at the programme's level: the course the pool holds already
   however its code is written, or a new course owned by the programme's department */
CREATE FUNCTION catalogue.pg_bind_course(p_programme text, p_code text, p_title text, p_units integer, p_semester integer, p_kind text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE p ref.programme; v_code text; v_level int; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO p FROM ref.programme WHERE code = btrim(coalesce(p_programme, ''));
    IF p.code IS NULL OR p.category IS DISTINCT FROM 'POST GRADUATE' THEN
        RAISE EXCEPTION 'PG_PROGRAMME: % is not a postgraduate programme', p_programme USING ERRCODE = '23514';
    END IF;
    v_code := catalogue.resolve_course_code(p_code);
    IF v_code IS NULL OR v_code !~ '^[A-Z][A-Z0-9 /-]{2,19}$' THEN
        RAISE EXCEPTION 'PG_COURSE_CODE: % is not a course code', p_code USING ERRCODE = '23514';
    END IF;
    v_level := admissions.pg_award_level(p.pg_award);
    IF NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_code) THEN
        INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
        VALUES (v_code, coalesce(nullif(btrim(p_title), ''), v_code), least(greatest(coalesce(p_units, 0), 0), 12),
                CASE WHEN p_semester IN (1, 2, 3) THEN p_semester ELSE 1 END, v_level, p.dept_code,
                CASE WHEN upper(coalesce(p_kind, '')) = 'ELECTIVE' THEN 'Elective' ELSE 'Core' END, 'LIVE');
    END IF;
    INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis, added_by, source)
    VALUES (v_code, p.code, v_level, catalogue.pg_kind_basis(p_kind), v_actor, 'PG')
    ON CONFLICT (course_code, programme_code, level) DO UPDATE SET basis = EXCLUDED.basis;
    RETURN v_code;
END $fn$;
COMMENT ON FUNCTION catalogue.pg_bind_course(text, text, text, integer, integer, text) IS
  'V389: a postgraduate programme''s course: the pool''s course (one record whatever the programmes), bound at the programme''s level with its basis.';

/* the old course list into the pool: each active row bound, each row naming its course; a row that cannot be read is left
   unnamed and listed (admissions.pg_course_unmapped) for the School to settle */
DO $$
DECLARE r admissions.pg_course; v text;
BEGIN
    FOR r IN SELECT * FROM admissions.pg_course ORDER BY programme_code, code LOOP
        BEGIN
            IF r.active THEN
                v := catalogue.pg_bind_course(r.programme_code, r.code, r.title, r.units, r.semester, r.kind);
            ELSE
                v := catalogue.resolve_course_code(r.code);
                IF NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = v) THEN v := NULL; END IF;
            END IF;
            UPDATE admissions.pg_course SET course_code = v WHERE id = r.id;
        EXCEPTION WHEN others THEN
            RAISE WARNING 'V389: % of % not brought into the pool: %', r.code, r.programme_code, SQLERRM;
        END;
    END LOOP;
END $$;
CREATE VIEW admissions.pg_course_unmapped AS
    SELECT c.id, c.programme_code, c.code, c.title, c.units, c.kind, c.semester, c.active FROM admissions.pg_course c WHERE c.course_code IS NULL;
COMMENT ON VIEW admissions.pg_course_unmapped IS 'V389: the School''s old course rows not yet a course of the pool.';

/* a course the School adds or edits on its desk, or uploads, is a course of the pool and bound at once */
CREATE FUNCTION admissions.pg_course_into_pool()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v text := catalogue.resolve_course_code(NEW.code);
BEGIN
    IF NEW.active AND v ~ '^[A-Z][A-Z0-9 /-]{2,19}$'
       AND EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = NEW.programme_code AND p.category = 'POST GRADUATE') THEN
        NEW.course_code := catalogue.pg_bind_course(NEW.programme_code, NEW.code, NEW.title, NEW.units, NEW.semester, NEW.kind);
    ELSIF NEW.course_code IS NULL AND EXISTS (SELECT 1 FROM catalogue.course WHERE code = v) THEN
        NEW.course_code := v;
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_pg_course_into_pool BEFORE INSERT OR UPDATE OF code, title, units, kind, semester, active, programme_code ON admissions.pg_course
    FOR EACH ROW EXECUTE FUNCTION admissions.pg_course_into_pool();

-- ── 6 · the School's grading scale on the results chain ───────────────────────────────────────────────────────────
DO $$
DECLARE v uuid := gen_random_uuid();
BEGIN
    IF policy.in_force('grading', 'POSTGRADUATE', current_date) IS NULL THEN
        INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
        VALUES (v, 'grading', 'POSTGRADUATE', daterange('1990-10-01', NULL), 'School of Postgraduate Studies grading: A 70, B 60, C 50, F below 50 (as admissions.pg_grade applied)', 'pgschool');
        INSERT INTO policy.grade_band (version_id, grade, low, high, points)
        VALUES (v, 'A', 70, 100, 5.00), (v, 'B', 60, 69, 4.00), (v, 'C', 50, 59, 3.00), (v, 'F', 0, 49, 0.00);
    END IF;
END $$;

/* the grading a class is read on: the School's for a PG class while a scale is in force for it, the University's otherwise */
CREATE FUNCTION policy.grading_scope(p_offering uuid)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN o.stream = 'PG' AND policy.in_force('grading', 'POSTGRADUATE', current_date) IS NOT NULL THEN 'POSTGRADUATE' ELSE 'UNIVERSITY' END
      FROM catalogue.offering o WHERE o.id = p_offering
$fn$;
CREATE FUNCTION policy.grade_of(p_mark integer, p_at date, p_scope text)
RETURNS TABLE(grade text, points numeric) LANGUAGE sql STABLE AS $fn$
    SELECT b.grade, b.points
      FROM policy.grade_band b
     WHERE b.version_id = coalesce(policy.in_force('grading', coalesce(p_scope, 'UNIVERSITY'), p_at), policy.in_force('grading', 'UNIVERSITY', p_at))
       AND p_mark BETWEEN b.low AND b.high
$fn$;
CREATE FUNCTION assessment.grace_total(p_raw integer, p_at date, p_scope text)
RETURNS integer LANGUAGE sql STABLE AS $fn$
    SELECT CASE
             WHEN p_raw IS NULL THEN NULL
             WHEN p_raw = (SELECT min(b.low) FROM policy.grade_band b
                            WHERE b.version_id = coalesce(policy.in_force('grading', coalesce(p_scope, 'UNIVERSITY'), p_at), policy.in_force('grading', 'UNIVERSITY', p_at))
                              AND b.points > 0) - 1
               THEN p_raw + 1
             ELSE p_raw END
$fn$;

-- ── 7 · a PG student's results from both sources ──────────────────────────────────────────────────────────────────
/* every course result of a PG student: the old coursework's scores and the published results of the School's classes */
CREATE FUNCTION admissions.pg_course_results(p_student uuid)
RETURNS TABLE(session text, semester integer, code text, title text, units integer, kind text, grade text, points numeric, total integer, source text)
LANGUAGE sql STABLE AS $fn$
    SELECT r.session, r.semester, coalesce(c.course_code, c.code), c.title, c.units, c.kind, sc.grade, sc.points, round(sc.total)::int, 'PG_COURSEWORK'
      FROM admissions.pg_registration r
      JOIN admissions.pg_registration_entry e ON e.registration_id = r.id
      JOIN admissions.pg_course c ON c.id = e.course_id
      JOIN admissions.pg_score sc ON sc.entry_id = e.id
     WHERE r.student_id = p_student
    UNION ALL
    SELECT o.session, o.semester, o.course_code, coalesce(o.title, c.title), coalesce(e.units, o.units, c.units),
           CASE coalesce(co.basis, 'Core') WHEN 'Deficiency' THEN 'DEFICIENCY' WHEN 'Research' THEN 'RESEARCH' WHEN 'Elective' THEN 'ELECTIVE' ELSE 'CORE' END,
           coalesce(f.grade, CASE WHEN f.outcome = 'ABSENT' THEN 'F' END), coalesce(f.points, CASE WHEN f.outcome = 'ABSENT' THEN 0 END), f.total, 'RESULTS'
      FROM registration.course_registration cr
      JOIN registration.entry e ON e.registration_id = cr.id AND e.status IN ('REGISTERED', 'APPROVED')
      JOIN catalogue.offering o ON o.id = e.offering_id AND o.stream = 'PG'
      JOIN catalogue.course c ON c.code = o.course_code
      JOIN people.student st ON st.id = cr.student_id
      LEFT JOIN catalogue.course_offer co ON co.course_code = o.course_code AND co.programme_code = st.programme_code AND co.level = cr.level
      CROSS JOIN LATERAL assessment.course_final(cr.student_id, o.id) f
     WHERE cr.student_id = p_student AND cr.status IN ('APPROVED', 'LOCKED') AND f.stage = 'PUBLISHED'
       AND (f.grade IS NOT NULL OR f.outcome = 'ABSENT')
$fn$;
COMMENT ON FUNCTION admissions.pg_course_results(uuid) IS
  'V389: a postgraduate student''s course results — the old coursework''s and the published results of the School''s classes — read alike by the GPA, the statement and the dashboard.';

CREATE OR REPLACE FUNCTION admissions.pg_gpa(p_student uuid, p_session text, p_semester integer)
RETURNS numeric LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN sum(x.units) > 0 THEN round(sum(x.points * x.units) / sum(x.units), 2) ELSE 0 END
      FROM admissions.pg_course_results(p_student) x
     WHERE x.session = p_session AND x.semester = p_semester AND x.kind <> 'DEFICIENCY' AND x.points IS NOT NULL;   -- deficiency courses earn no credit (Policy 11.3.3)
$fn$;
CREATE OR REPLACE FUNCTION admissions.pg_cgpa(p_student uuid)
RETURNS numeric LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN sum(x.units) > 0 THEN round(sum(x.points * x.units) / sum(x.units), 2) ELSE 0 END
      FROM admissions.pg_course_results(p_student) x
     WHERE x.kind <> 'DEFICIENCY' AND x.points IS NOT NULL;
$fn$;

-- ── 8 · notices: PG course registration open and closing; applicants by SMS too ───────────────────────────────────
CREATE TABLE admissions.pg_registration_notice (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session   text NOT NULL REFERENCES policy.academic_session (name),
    semester  integer NOT NULL CHECK (semester BETWEEN 1 AND 3),
    kind      text NOT NULL CHECK (kind IN ('OPENED', 'CLOSING')),
    students  integer NOT NULL DEFAULT 0,
    sent_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (session, semester, kind)
);
COMMENT ON TABLE admissions.pg_registration_notice IS
  'V389: the PG course registration notices sent, once each: OPENED when registration opens for a semester, CLOSING three days before it closes.';
SELECT audit.attach('admissions.pg_registration_notice');

/* the day PG course registration closes for a semester: the PG window's end where the Directorate holds one, else the School's date */
CREATE FUNCTION registration.pg_registration_closes(p_session text, p_semester integer)
RETURNS timestamptz LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(
        (SELECT coalesce(w.late_until, w.closes_at) FROM policy.window_state('PG_COURSE_REGISTRATION', p_session, p_semester) w WHERE w.configured),
        (SELECT (ps.registration_closes + 1)::timestamp AT TIME ZONE 'Africa/Lagos' FROM admissions.pg_semester ps WHERE ps.session = p_session AND ps.number = p_semester))
$fn$;

/* tell the School's students, once, that registration is open, and those not yet registered that it closes within three days */
CREATE FUNCTION admissions.pg_tell_registration()
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE s text := admissions.pg_current_session(); sem record; st record; n int; total int := 0; v_closes timestamptz; ord text;
BEGIN
    FOR sem IN SELECT ps.number FROM admissions.pg_semester ps WHERE ps.session = s AND ps.state = 'OPEN' ORDER BY ps.number LOOP
        IF registration.pg_gate_of(s, sem.number) IS NOT NULL THEN CONTINUE; END IF;
        ord := CASE sem.number WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END;
        v_closes := registration.pg_registration_closes(s, sem.number);
        -- the opening is told here when the School's calendar opens it; where the Directorate holds a PG window its act tells the students
        IF NOT EXISTS (SELECT 1 FROM admissions.pg_registration_notice WHERE session = s AND semester = sem.number AND kind = 'OPENED')
           AND NOT coalesce((SELECT w.configured FROM policy.window_state('PG_COURSE_REGISTRATION', s, sem.number) w), false) THEN
            n := 0;
            FOR st IN SELECT x.id FROM people.student x WHERE x.entry_mode = 'POSTGRADUATE' AND x.status IN ('ADMITTED', 'ACTIVE', 'PROBATION') LOOP
                IF people.tell_student(st.id, 'Postgraduate course registration is open: ' || s || ', ' || ord || ' semester',
                       'Course registration for the ' || ord || ' semester of ' || s || ' is open on the student portal (Course Registration).'
                       || coalesce(E'\n\nIt closes on ' || to_char(v_closes AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY') || '.', '')
                       || E'\n\nSchool of Postgraduate Studies',
                       'PG registration open ' || s || ' ' || sem.number,
                       'MOAUM PG: course registration for ' || s || ' ' || ord || ' semester is open on the student portal.') THEN
                    n := n + 1;
                END IF;
            END LOOP;
            INSERT INTO admissions.pg_registration_notice (session, semester, kind, students) VALUES (s, sem.number, 'OPENED', n);
            total := total + n;
        END IF;
        IF v_closes IS NOT NULL AND v_closes > now() AND v_closes - now() <= interval '3 days'
           AND NOT EXISTS (SELECT 1 FROM admissions.pg_registration_notice WHERE session = s AND semester = sem.number AND kind = 'CLOSING') THEN
            n := 0;
            FOR st IN SELECT x.id FROM people.student x
                       WHERE x.entry_mode = 'POSTGRADUATE' AND x.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
                         AND NOT EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = x.id AND r.session = s AND r.semester = sem.number
                                            AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) LOOP
                IF people.tell_student(st.id, 'Postgraduate course registration closes soon: ' || s || ', ' || ord || ' semester',
                       'Course registration for the ' || ord || ' semester of ' || s || ' closes on '
                       || to_char(v_closes AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY') || ', and your registration is not yet submitted.'
                       || E'\n\nSchool of Postgraduate Studies',
                       'PG registration closing ' || s || ' ' || sem.number,
                       'MOAUM PG: course registration for ' || s || ' ' || ord || ' semester closes on ' || to_char(v_closes AT TIME ZONE 'Africa/Lagos', 'FMDD Mon') || '. Submit yours.') THEN
                    n := n + 1;
                END IF;
            END LOOP;
            INSERT INTO admissions.pg_registration_notice (session, semester, kind, students) VALUES (s, sem.number, 'CLOSING', n);
            total := total + n;
        END IF;
    END LOOP;
    RETURN total;
END $fn$;
COMMENT ON FUNCTION admissions.pg_tell_registration() IS
  'V389: the School''s students told by email and SMS when PG course registration opens on the School''s calendar (a PG window''s opening is told by the Directorate''s act), and those not yet registered three days before it closes; once each.';

-- ── 9 · the PG student's next steps, from the record ──────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.pg_next_steps(p_student uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE st people.student; app admissions.pg_application; s text; sem int; v_gate text; reg registration.course_registration;
        pos record; stated boolean; fw record; steps jsonb := '[]'::jsonb; n_units int; n_courses int; n_results int; v_card boolean;
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

    -- matriculation
    steps := steps || CASE WHEN st.matric_no IS NOT NULL
        THEN jsonb_build_object('key', 'MATRICULATION', 'state', 'DONE', 'label', 'Matriculated', 'detail', st.matric_no)
        ELSE jsonb_build_object('key', 'MATRICULATION', 'state', 'WAITING', 'label', 'Matriculation pending', 'detail', 'Your matriculation number is issued after your registration is approved and your fees are settled.') END;
    RETURN steps;
END $fn$;
COMMENT ON FUNCTION admissions.pg_next_steps(uuid) IS
  'V389: the PG student''s next steps worked out from the record — the offer, fees, registration, examination card, results and matriculation — each only when it applies.';

-- ── 10 · the engine reads the PG student on the School's calendar and gate ─────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.registration_gate(p_student uuid, p_session text, p_semester integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    WITH sm AS (SELECT * FROM policy.semester WHERE session = p_session AND number = p_semester),
         st AS (SELECT * FROM people.student WHERE id = p_student),
         w AS (SELECT CASE p_semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END AS ord)
    SELECT CASE
             -- V380: a CCE student's door is the Centre's: its classes, the CCE window and the CCE calendar — never the full-time ones of the session
             WHEN st.entry_mode = 'CCE' THEN registration.cce_gate(p_student, p_session, p_semester)
             -- V389: a postgraduate student's door is the School's: its classes, its calendar and the PG window
             WHEN st.entry_mode = 'POSTGRADUATE' THEN registration.pg_gate_of(p_session, p_semester)
             WHEN pw.configured AND pw.state = 'CLOSED' THEN 'Course registration is currently closed for ' || p_session || ' ' || w.ord || ' semester.' || coalesce(' ' || pw.reason, '')
             WHEN pw.configured AND pw.state = 'SCHEDULED' THEN 'Course registration for ' || p_session || ' ' || w.ord || ' semester opens on ' || to_char(pw.opens_at AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') || '.'
             WHEN pw.configured AND pw.state = 'EXPIRED' THEN 'Course registration for ' || p_session || ' ' || w.ord || ' semester closed on ' || to_char(coalesce(pw.late_until, pw.closes_at) AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') || '.'
             WHEN pw.configured AND pw.state = 'OPEN' THEN NULL
             WHEN NOT EXISTS (SELECT 1 FROM sm) THEN NULL
             WHEN sm.state = 'OPEN' THEN NULL
             WHEN sm.state IN ('CLOSED', 'ARCHIVED') THEN 'The ' || w.ord || ' semester of ' || p_session || ' is closed for registration.'
             WHEN sm.fresh_registration_from IS NOT NULL AND sm.fresh_registration_from <= current_date AND st.entry_session = p_session THEN NULL
             WHEN sm.fresh_registration_from IS NOT NULL AND st.entry_session = p_session
                  THEN 'The ' || w.ord || ' semester of ' || p_session || ' opens to fresh students on ' || to_char(sm.fresh_registration_from, 'DD Month YYYY') || '.'
             WHEN sm.fresh_registration_from IS NOT NULL
                  THEN 'The ' || w.ord || ' semester of ' || p_session || ' is not yet open; only the session''s fresh students register from ' || to_char(sm.fresh_registration_from, 'DD Month YYYY') || '.'
             ELSE 'The ' || w.ord || ' semester of ' || p_session || ' is not yet open for registration.'
           END
      FROM w LEFT JOIN sm ON true LEFT JOIN st ON true LEFT JOIN LATERAL (SELECT * FROM policy.window_state('COURSE_REGISTRATION', p_session, p_semester)) pw ON true
$function$;
CREATE OR REPLACE FUNCTION registration.student_menu(p_student uuid, p_session text, p_semester integer)
 RETURNS TABLE(offering_id uuid, course_code text, title text, units integer, kind text, basis text, owner_dept text, carryover boolean, failed_in text, lecturer text, deferred boolean, deferred_from text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V380: the student's stream: a CCE student is offered the Centre's classes, every other student the full-time ones
    WITH s AS (SELECT st.*, people.student_stream(st.id) AS stream FROM people.student st WHERE st.id = p_student),   -- V389: and the School's classes for a PG student
    -- V366: the GST/EPS courses of the programme at this level the student has already passed
    gst_passed AS (SELECT x.course_code FROM finance.gst_eps_rows(p_session, p_student) x WHERE x.status = 'ALREADY_PASSED'),
    eligible AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, co.basis, c.dept_code
          FROM s
          JOIN catalogue.course_offer co ON co.programme_code = s.programme_code AND co.level = s.current_level
                                        AND (co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
          JOIN catalogue.course c ON c.code = co.course_code AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester AND o.stream = s.stream
         WHERE (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)
           AND NOT (c.kind = 'GST' AND c.code IN (SELECT gp.course_code FROM gst_passed gp))),
    carry AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, 'Carryover'::text AS basis, c.dept_code, cv.failed_in
          FROM registration.carryovers(p_student) cv
          JOIN catalogue.course c ON c.code = cv.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
          CROSS JOIN s
         WHERE o.stream = s.stream AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)),
    -- a course set aside by an approved deferment, due since the student returned, offered this semester and not yet passed
    deferred AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, 'Deferred'::text AS basis, c.dept_code,
               dc.original_session || ' semester ' || dc.original_semester AS deferred_from
          FROM people.deferred_courses(p_student) dc
          JOIN catalogue.course c ON c.code = dc.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
          CROSS JOIN s
         WHERE o.stream = s.stream AND dc.status = 'DEFERRED' AND dc.due
           AND (dc.original_session, dc.original_semester) < (p_session, p_semester)
           AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.code = c.code))
    SELECT x.offering_id, x.code, x.title, x.units, x.kind, x.basis, d.name,
           (x.basis IN ('Carryover','Deferred')), x.failed_in, p.surname || ', ' || p.given_names,
           (x.basis = 'Deferred'), x.deferred_from
      FROM (SELECT e.*, NULL::text AS failed_in, NULL::text AS deferred_from FROM eligible e
            WHERE NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.offering_id = e.offering_id)
              AND NOT EXISTS (SELECT 1 FROM deferred df WHERE df.offering_id = e.offering_id)
            UNION ALL SELECT cv.*, NULL::text AS deferred_from FROM carry cv
            UNION ALL SELECT df.offering_id, df.code, df.title, df.units, df.kind, df.basis, df.dept_code, NULL::text, df.deferred_from FROM deferred df) x
      JOIN ref.department d ON d.code = x.dept_code
      JOIN catalogue.offering o ON o.id = x.offering_id
      LEFT JOIN iam.person p ON p.id = o.lecturer_id
     ORDER BY (x.basis = 'Carryover') DESC, (x.basis = 'Deferred') DESC, x.kind, x.code;
$function$;
CREATE OR REPLACE FUNCTION registration.open_course_registration(p_session text, p_semester integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'catalogue', 'registration', 'ref', 'policy'
AS $function$
DECLARE v_count int;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'course registration is opened by a person' USING ERRCODE = '23514';
    END IF;
    IF p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN
        RAISE EXCEPTION 'no academic session % on the calendar — open the session first', p_session USING ERRCODE = '23503';
    END IF;

    -- 1 · decide, before any lock: the courses of this semester that some structure row offers for any
    --     track, or for a track that still has a student in that programme
    CREATE TEMP TABLE IF NOT EXISTS to_offer (course_code text PRIMARY KEY) ON COMMIT DROP;
    TRUNCATE to_offer;
    WITH live AS (
        SELECT DISTINCT st.programme_code, st.curriculum_track
          FROM people.student st
         WHERE st.status IN ('ACTIVE','PROBATION','ADMITTED')
    )
    INSERT INTO to_offer (course_code)
    SELECT DISTINCT c.code
      FROM catalogue.course c
      JOIN catalogue.course_offer co ON co.course_code = c.code
     WHERE catalogue.runs_in(c.semester, c.both_semesters, p_semester)   -- V386: a course taught in both semesters too
       AND c.state <> 'ENDED'
       AND NOT EXISTS (SELECT 1 FROM ref.programme pp WHERE pp.code = co.programme_code AND pp.category = 'POST GRADUATE')   -- V389: the School opens its own
       AND (co.track IS NULL
            OR EXISTS (SELECT 1 FROM live l WHERE l.programme_code = co.programme_code AND l.curriculum_track = co.track))
       AND NOT EXISTS (SELECT 1 FROM catalogue.offering o   -- V380: the full-time classes; the Centre opens its own
                        WHERE o.course_code = c.code AND o.session = p_session AND o.semester = p_semester AND o.stream = 'REGULAR');

    -- 2 · insert the rows already chosen, with the audit trigger off for exactly that long
    ALTER TABLE catalogue.offering DISABLE TRIGGER trg_audit_catalogue_offering;
    INSERT INTO catalogue.offering (id, course_code, session, semester)
    SELECT gen_random_uuid(), t.course_code, p_session, p_semester FROM to_offer t;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ALTER TABLE catalogue.offering ENABLE TRIGGER trg_audit_catalogue_offering;

    RETURN v_count;
END $function$;
CREATE OR REPLACE FUNCTION registration.semesters_unregistered(p_student uuid)
 RETURNS TABLE(semesters integer, last_registered text, first_missed text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH s AS (SELECT * FROM people.student WHERE id = p_student),
    reg AS (SELECT r.session, r.semester FROM registration.course_registration r
             WHERE r.student_id = p_student AND r.status IN ('APPROVED','LOCKED')
            UNION ALL   -- V389: and a postgraduate student's registration on the School's old coursework
            SELECT g.session, g.semester FROM admissions.pg_registration g WHERE g.student_id = p_student AND g.state IN ('SUBMITTED', 'ENDORSED')),
    -- V380: the semesters the student's calendar has closed — the CCE calendar's for a CCE student, the full-time calendar's for every other
    closed AS (
        SELECT c.session, c.semester FROM registration.closed_semesters() c CROSS JOIN s WHERE coalesce(s.entry_mode, '') NOT IN ('CCE', 'POSTGRADUATE')
        UNION ALL   -- V389: the School of Postgraduate Studies' closed semesters for a PG student
        SELECT ps.session, ps.number FROM admissions.pg_semester ps CROSS JOIN s
         WHERE s.entry_mode = 'POSTGRADUATE' AND (ps.state = 'CLOSED' OR ps.registration_closes < current_date)
        UNION ALL
        SELECT rs.session, rs.number FROM policy.route_semester rs CROSS JOIN s
         WHERE s.entry_mode = 'CCE' AND rs.route = 'CCE'
           AND (rs.state = 'CLOSED' OR coalesce(rs.late_registration_closes, rs.registration_closes) < current_date)),
    missed AS (
        SELECT c.session, c.semester FROM closed c CROSS JOIN s
         WHERE c.session >= s.entry_session
           AND NOT EXISTS (SELECT 1 FROM reg WHERE (reg.session, reg.semester) >= (c.session, c.semester))
           -- a semester set aside by an approved deferment was not missed
           AND NOT EXISTS (SELECT 1 FROM people.deferment d WHERE d.student_id = p_student AND d.session = c.session
                             AND d.state IN ('APPROVED','ACTIVE','COMPLETED') AND (d.kind = 'SESSION' OR d.semester = c.semester))
    ),
    word AS (SELECT 1 AS n, 'first' AS w UNION ALL SELECT 2, 'second' UNION ALL SELECT 3, 'third')
    SELECT (SELECT count(*) FROM missed)::int,
           (SELECT r.session || ' ' || coalesce(w.w, r.semester::text) || ' semester' FROM reg r LEFT JOIN word w ON w.n = r.semester ORDER BY r.session DESC, r.semester DESC LIMIT 1),
           (SELECT m.session || ' ' || coalesce(w.w, m.semester::text) || ' semester' FROM missed m LEFT JOIN word w ON w.n = m.semester ORDER BY m.session, m.semester LIMIT 1)
$function$;
CREATE OR REPLACE FUNCTION people.deferments_tick()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE d record; st people.deferment_setting; n int := 0; s people.student;
BEGIN
    SELECT * INTO st FROM people.deferment_setting WHERE id = 1;
    -- approved, and the period has begun (or the session is the current one and the semester open): in force
    FOR d IN
        SELECT x.* FROM people.deferment x
         WHERE x.state = 'APPROVED'
           AND (current_date >= x.period_from
                OR (people.student_stream(x.student_id) = 'REGULAR'
                    AND EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = x.session AND a.state = 'CURRENT'
                                 AND (x.kind = 'SESSION' OR EXISTS (SELECT 1 FROM policy.semester sm WHERE sm.session = x.session AND sm.number = x.semester AND sm.state = 'OPEN'))))
                -- V381: a CCE student's deferment begins with the CCE session, or its CCE semester open
                OR (people.student_stream(x.student_id) = 'CCE' AND x.session = policy.route_session('CCE')
                    AND (x.kind = 'SESSION' OR EXISTS (SELECT 1 FROM policy.route_semester rs WHERE rs.route = 'CCE' AND rs.session = x.session AND rs.number = x.semester AND rs.state = 'OPEN')))
                -- V389: a PG student's deferment begins with the School's session, or its semester open
                OR (people.student_stream(x.student_id) = 'PG' AND x.session = admissions.pg_current_session()
                    AND (x.kind = 'SESSION' OR EXISTS (SELECT 1 FROM admissions.pg_semester ps WHERE ps.session = x.session AND ps.number = x.semester AND ps.state = 'OPEN'))))
    LOOP
        SELECT * INTO s FROM people.student WHERE id = d.student_id;
        UPDATE people.deferment SET state = 'ACTIVE', activated_at = now(), prior_status = s.status, updated_at = now() WHERE id = d.id;
        IF s.status IN ('ACTIVE','PROBATION','ADMITTED') AND s.matric_no IS NOT NULL THEN
            PERFORM people.change_status(s.id, 'DEFERRED', d.reference, current_date, 'Deferment in force');
            UPDATE people.status_change SET expires_on = d.return_on WHERE id = (SELECT id FROM people.status_change WHERE student_id = s.id ORDER BY effective_on DESC, id DESC LIMIT 1);
        END IF;
        PERFORM people.deferment_log(d.id, 'ACTIVATED', 'APPROVED', 'ACTIVE', 'The deferred period has begun');
        PERFORM people.deferment_tell(d.id, 'Your deferment is now in force', 'Your deferment of ' || d.session || coalesce(' semester ' || d.semester, '') || ' is in force. Your expected return is ' || d.return_session || ' semester ' || d.return_semester || '.');
        n := n + 1;
    END LOOP;
    -- the return approaching: reminded once
    FOR d IN
        SELECT x.* FROM people.deferment x
         WHERE x.state = 'ACTIVE' AND x.reminder_sent_at IS NULL AND x.return_on IS NOT NULL AND x.return_on <= current_date + st.reminder_days
    LOOP
        UPDATE people.deferment SET reminder_sent_at = now() WHERE id = d.id;
        PERFORM people.deferment_tell(d.id, 'Your deferment is ending soon',
            'Your approved deferment ends on ' || to_char(d.return_on, 'DD Month YYYY') || '. Review your school fees and course registration for ' || d.return_session || ' semester ' || d.return_semester || '; the desk confirms your return.');
        PERFORM people.deferment_tell_desk(d.id, 'hod', 'A student is due to return from deferment', 'A student of your department is due to return from deferment on ' || to_char(d.return_on, 'DD Month YYYY') || '. Confirm the return on the deferments desk when they present themselves.');
        n := n + 1;
    END LOOP;
    RETURN n;
END $function$;

-- ── 11 · the PG windows on the Directorate's desk ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION policy.window_act(p_type text, p_session text, p_semester integer, p_action text, p_opens timestamp with time zone, p_closes timestamp with time zone, p_late_until timestamp with time zone, p_late_fee boolean, p_reason text, p_actor uuid, p_office text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE cur policy.portal_window; prev record; v_forced text; v_opens timestamptz; v_closes timestamptz; v_late timestamptz; v_fee boolean; v_id uuid; nxt record;
BEGIN
    IF p_type NOT IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION',
                      'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION',
                      'CCE_SCHOOL_FEES_PAYMENT', 'CCE_COURSE_REGISTRATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING',
                      'PG_SCHOOL_FEES_PAYMENT', 'PG_COURSE_REGISTRATION') THEN
        RAISE EXCEPTION 'no such portal window %', p_type USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('ADMISSION_STATUS_CHECKING', 'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_ADMISSION_STATUS_CHECKING', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING')
       AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_CHECKING_SESSION: this window opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION') AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_APPLICATION_SESSION: an application window opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN RAISE EXCEPTION 'no academic session % on the calendar', p_session USING ERRCODE = '23503'; END IF;
    IF p_action NOT IN ('OPEN', 'CLOSE', 'REOPEN', 'SCHEDULE', 'EXTEND', 'SHORTEN', 'EDIT') THEN RAISE EXCEPTION 'unknown action %', p_action USING ERRCODE = '23514'; END IF;
    IF p_action IN ('CLOSE', 'REOPEN', 'SHORTEN') AND nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'the reason for % is recorded, and none was given', lower(p_action) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO cur FROM policy.portal_window WHERE window_type = p_type AND session = p_session AND coalesce(semester, 0) = coalesce(p_semester, 0) AND superseded_at IS NULL FOR UPDATE;
    SELECT * INTO prev FROM policy.window_state(p_type, p_session, p_semester);
    v_opens := coalesce(p_opens, cur.opens_at); v_closes := coalesce(p_closes, cur.closes_at); v_late := coalesce(p_late_until, cur.late_until);
    v_fee := coalesce(p_late_fee, cur.late_fee_enabled, false);
    CASE p_action
        WHEN 'OPEN', 'REOPEN' THEN v_forced := CASE WHEN p_opens IS NULL AND p_closes IS NULL THEN 'OPEN' ELSE NULL END;
                                   IF p_opens IS NULL AND p_closes IS NOT NULL THEN v_opens := now(); END IF;
        WHEN 'CLOSE' THEN v_forced := 'CLOSED';
        WHEN 'SCHEDULE' THEN IF p_opens IS NULL THEN RAISE EXCEPTION 'a schedule names when the window opens' USING ERRCODE = '23514'; END IF; v_forced := NULL;
        WHEN 'EXTEND' THEN IF p_closes IS NULL AND p_late_until IS NULL THEN RAISE EXCEPTION 'an extension names the new closing' USING ERRCODE = '23514'; END IF;
                           IF cur.id IS NOT NULL AND p_closes IS NOT NULL AND cur.closes_at IS NOT NULL AND p_closes < cur.closes_at THEN RAISE EXCEPTION 'that closing is earlier than before; shorten the window instead' USING ERRCODE = '23514'; END IF;
                           v_forced := CASE WHEN cur.forced = 'CLOSED' THEN NULL ELSE cur.forced END;
        WHEN 'SHORTEN' THEN IF p_closes IS NULL THEN RAISE EXCEPTION 'a shortening names the new closing' USING ERRCODE = '23514'; END IF; v_forced := cur.forced;
        WHEN 'EDIT' THEN v_forced := cur.forced;
    END CASE;
    IF v_closes IS NOT NULL AND v_opens IS NOT NULL AND v_closes < v_opens THEN RAISE EXCEPTION 'the window closes before it opens' USING ERRCODE = '23514'; END IF;
    IF v_late IS NOT NULL AND v_closes IS NOT NULL AND v_late < v_closes THEN RAISE EXCEPTION 'the late period ends before the window closes' USING ERRCODE = '23514'; END IF;
    IF cur.id IS NOT NULL THEN UPDATE policy.portal_window SET superseded_at = now() WHERE id = cur.id; END IF;
    INSERT INTO policy.portal_window (window_type, session, semester, opens_at, closes_at, late_until, late_fee_enabled, forced, reason, created_by, created_office)
    VALUES (p_type, p_session, p_semester, v_opens, v_closes, v_late, v_fee, v_forced, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office)
    RETURNING id INTO v_id;
    SELECT * INTO nxt FROM policy.window_state(p_type, p_session, p_semester);
    INSERT INTO policy.portal_window_event (window_id, window_type, session, semester, action, previous_state, new_state, previous_opens_at, previous_closes_at, previous_late_until,
                                            new_opens_at, new_closes_at, new_late_until, late_fee_enabled, reason, actor, office)
    VALUES (v_id, p_type, p_session, p_semester, p_action, CASE WHEN prev.configured THEN prev.state ELSE prev.state || ' (default)' END, nxt.state, cur.opens_at, cur.closes_at, cur.late_until,
            v_opens, v_closes, v_late, v_fee, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office);
    RETURN v_id;
END $function$;

-- ── 12 · a PG class's marks read on the School's scale ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION assessment.latest_scores(p_sheet uuid)
 RETURNS TABLE(student_id uuid, ca integer, exam integer, total integer, grade text, points numeric, outcome text, version integer, amended boolean)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT s.student_id, s.ca, s.exam, t.total,
           g.grade, g.points, s.outcome, s.version, s.version > 1
      FROM (SELECT DISTINCT ON (student_id) * FROM assessment.score
             WHERE sheet_id = p_sheet ORDER BY student_id, version DESC) s
      -- V389: the class's grading — the School's for a PG class, the University's for every other
      CROSS JOIN (SELECT policy.grading_scope(sh.offering_id) AS scope FROM assessment.score_sheet sh WHERE sh.id = p_sheet) gs
      CROSS JOIN LATERAL (SELECT CASE WHEN s.outcome <> 'GRADED' THEN NULL
                                      WHEN s.ca IS NOT NULL AND s.exam IS NOT NULL AND NOT s.imported THEN assessment.grace_total(s.ca + s.exam, current_date, gs.scope)
                                      ELSE coalesce(s.ca + s.exam, s.total) END AS total) t
      LEFT JOIN LATERAL policy.grade_of(t.total, current_date, gs.scope) g ON true
$function$;
CREATE OR REPLACE FUNCTION assessment.course_final(p_student uuid, p_offering uuid)
 RETURNS TABLE(sheet_id uuid, stage text, published_at timestamp with time zone, senate_minute text, ca integer, exam integer, total integer, grade text, points numeric, outcome text, sitting text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH sittings AS (
        SELECT sh.id AS sheet_id, sh.stage, sh.published_at, sh.senate_minute,
               coalesce(es.kind, 'MAIN') AS kind,
               ls.ca, ls.exam, ls.total, ls.grade, ls.points, ls.outcome
          FROM assessment.score_sheet sh
          LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id
          LEFT JOIN LATERAL assessment.latest_scores(sh.id) ls ON ls.student_id = p_student
         WHERE sh.offering_id = p_offering
    ),
    pass AS (   -- the pass mark of the standing grading scheme: the lowest band scoring points
        SELECT b.grade, b.points, b.low
          FROM policy.grade_band b
         WHERE b.version_id = coalesce(policy.in_force('grading', policy.grading_scope(p_offering), current_date), policy.in_force('grading', 'UNIVERSITY', current_date))
           AND b.points > 0   -- V389: the class's scale
         ORDER BY b.points ASC LIMIT 1
    ),
    picked AS (   -- a published special or re-sit the student sat supersedes the Main, else the Main stands
        SELECT s.*, CASE s.kind WHEN 'SPECIAL' THEN 1 WHEN 'RESIT' THEN 2 ELSE 3 END AS pr
          FROM sittings s
         WHERE (s.kind IN ('SPECIAL','RESIT') AND s.stage = 'PUBLISHED' AND s.outcome IS NOT NULL)
            OR s.kind = 'MAIN'
         ORDER BY pr LIMIT 1
    )
    SELECT p.sheet_id, p.stage, p.published_at, p.senate_minute,
           p.ca, p.exam,
           -- a passed re-sit is recorded at the pass mark; a special and the Main are as scored
           CASE WHEN p.pr = 2 AND coalesce(p.points, 0) > 0 THEN (SELECT low    FROM pass) ELSE p.total  END,
           CASE WHEN p.pr = 2 AND coalesce(p.points, 0) > 0 THEN (SELECT grade  FROM pass) ELSE p.grade  END,
           CASE WHEN p.pr = 2 AND coalesce(p.points, 0) > 0 THEN (SELECT points FROM pass) ELSE p.points END,
           p.outcome,
           CASE p.pr WHEN 1 THEN 'SPECIAL' WHEN 2 THEN 'RESIT' ELSE 'MAIN' END
      FROM picked p;
$function$;

-- ── 13 · the statement reads a PG student's results from both sources ───────────────────────────────────────────
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

-- ── 14 · the old registration closes to new registrations; applicants are told by SMS too ──────────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_register(p_student uuid, p_session text, p_semester integer, p_mode text, p_courses uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- V389: postgraduate course registration is on the University's registration engine, in the School's session; what
    -- this list holds stays and is read (admissions.pg_course_results), and the old-portal import (V214) still writes it
    RAISE EXCEPTION 'PG_REGISTRATION_MOVED: postgraduate course registration is now on the student portal''s Course Registration' USING ERRCODE = '23514';
END $function$;
CREATE OR REPLACE FUNCTION admissions.pg_tell_applicant(p_app uuid, p_subject text, p_body text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v_email text; v_no text; v_phone text;
BEGIN
    SELECT p.email, a.application_no, p.phone INTO v_email, v_no, v_phone
      FROM admissions.pg_application a JOIN admissions.pg_applicant p ON p.id = a.applicant_id
     WHERE a.id = p_app;
    -- V389: the applicant is told by SMS as well, in a line, and reads the rest on the portal
    PERFORM platform.queue_notice('SMS', v_phone, p_subject, 'MOAUM PG: ' || p_subject || '. Sign in to the applicant portal.', 'pg_application', p_app);
    IF v_email IS NULL THEN RETURN; END IF;
    PERFORM platform.queue_notice('EMAIL', v_email, p_subject,
        'Dear applicant,' || E'\n\n' || p_body || E'\n\n' || 'Application number: ' || coalesce(v_no, '') || E'\n' ||
        'School of Postgraduate Studies, Rev. Fr. Moses Orshio Adasu University, Makurdi',
        'pg_application', p_app);
END $function$;

COMMIT;
