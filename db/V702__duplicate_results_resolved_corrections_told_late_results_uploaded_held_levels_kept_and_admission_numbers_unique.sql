-- ═══════════════════════════════════════
-- V702 — follow-ups to V692, V696 and V700
--
-- The University's word of 29 October 2026 ("d 1-7"), on the follow-ups V700 and V696 left:
--
--   1. Duplicate results. A student with marks for one course under two codes in a semester (its BSU-/MOAU- twin, or a second
--      course under the code: on the live-shaped copy of 28 October 2026, 2,172 in 2024/2025's first semester, BSU-CMS 101 beside
--      CMS 101) is resolved by the Registry's side — Exams & Records, the Registry, the Academic Office, or the Director of ICT and
--      the Database Operators over the University — choosing the one that stands (the University's choice of 29 October 2026). The
--      other course is withdrawn from the student's registration (its mark stays on its sheet, the history), so the transcript, the
--      CGPA (its kept figure goes stale on the change) and the broadsheet stop counting it; the decision is written down
--      (assessment.duplicate_resolution) and may be put back. assessment.result_duplicates lists them; the exceptions pass over a
--      pair resolved and the withdrawn course's mark.
--   2. Correction requests told. The course's lecturer is told of a request by email, SMS and the portal (CORRECTION_REQUESTED),
--      and the Director of ICT who asked is told when it is corrected or declined (CORRECTION_CLOSED).
--   3. Late results by the sheet. assessment.raise_late_results raises a late result (V422) for each candidate on a published
--      sheet's roll with no mark, from one upload, each through the chain to Senate as before; a row is RAISED, NOT_LATE (the
--      student has a mark, or is not on the roll), REPEATED or REFUSED with the chain's reason.
--   4. A held student's level. A student held a level behind after a change of department (V696) never goes above the hold: an
--      upload, a desk or anything else that would raise them is held at it and the attempt written down (LEVEL_HELD_DEPARTMENT_CHANGE),
--      the level desk offers nothing above it, and the session roll-over counts the hold in the session it rolls into.
--   5. The held students' fees. Charged as they are (the University's word of 29 October 2026: the held level's fee);
--      finance.department_change_fee_effect lists, for the Bursary, each held student's fee at the level held and a level up.
--   6. COS 203 unbound from B.Sc. Computer Science, beside CSC 203 (both "Discrete Structures"; the new CCMAS structure has CSC 203).
--   7. An admission number is never one another student holds. Each session counted its own series under the two digits of its year,
--      so two sessions a century apart (2084/2085 and a test's 2384/2385) both issued MOAUM/ADM/84/000001 — AdmissionLifecycleIT's
--      duplicate key in CI on 29 October 2026. people.next_admission_no takes the next number no student holds; intake and the
--      postgraduate admission use it (the inter-university transfer already did, V588).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V702: the follow-ups to V692, V696 and V700', true);

-- ── 7. an admission number no student holds ──
CREATE OR REPLACE FUNCTION people.next_admission_no(p_yy text, p_session text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE v text; n int := 0;
BEGIN
    LOOP
        v := 'MOAUM/ADM/' || p_yy || '/' || lpad(platform.next_number('ADMISSION', 'UNIVERSITY', p_session)::text, 6, '0');
        EXIT WHEN NOT EXISTS (SELECT 1 FROM people.student s WHERE s.admission_no = v);
        n := n + 1;
        IF n > 100000 THEN RAISE EXCEPTION 'ADMISSION_NUMBERS: no free admission number after % in %', v, p_session USING ERRCODE = '23514'; END IF;
    END LOOP;
    RETURN v;
END $$;
COMMENT ON FUNCTION people.next_admission_no(text, text) IS
  'V702: the next admission number of a session''s series (MOAUM/ADM/yy/nnnnnn) that no student holds — a number held already (a session a century apart, an imported record) is passed over.';
-- restated from V431 (people.intake_one) and V337 (admissions.pg_admit): the admission number by people.next_admission_no
CREATE OR REPLACE FUNCTION people.intake_one(p_candidate uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE c admissions.candidate; v_id uuid; v_code text; v_yy text; l admissions.cce_candidate; v_prev uuid; v_prev_prog text; v_busy boolean;
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
    -- V429: a student already on the register under the candidate's JAMB number for the same entry session, never linked to a candidate
    -- (taken on by an earlier list or by hand), IS the candidate: linked, never made a second time. Untouched yet (no registration,
    -- payment or mark), it takes the programme the admission names; with a history on another programme the Registry decides.
    SELECT s.id, s.programme_code INTO v_prev, v_prev_prog FROM people.student s
     WHERE s.candidate_id IS NULL AND s.duplicate_of IS NULL AND s.jamb_reg_no IS NOT NULL AND upper(s.jamb_reg_no) = upper(c.jamb_reg_no) AND s.entry_session = c.session
     ORDER BY s.admission_no NULLS LAST LIMIT 1;
    IF v_prev IS NOT NULL THEN
        IF v_prev_prog IS DISTINCT FROM v_code THEN
            v_busy := EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = v_prev)
                   OR EXISTS (SELECT 1 FROM finance.payment_reference p WHERE p.student_id = v_prev)
                   OR EXISTS (SELECT 1 FROM assessment.score sc WHERE sc.student_id = v_prev);
            IF v_busy THEN
                RAISE EXCEPTION 'INTAKE_DUPLICATE_JAMB: % is already on the register for % on another programme, with registrations, payments or marks; the Registry reconciles the two before the candidate is taken on', c.jamb_reg_no, c.session
                    USING ERRCODE = '23514';
            END IF;
            UPDATE people.student SET programme_code = v_code WHERE id = v_prev;
        END IF;
        UPDATE people.student SET candidate_id = c.id WHERE id = v_prev;
        RETURN v_prev;
    END IF;
    v_yy := substr(c.session, 3, 2);
    -- V379: a CCE candidate comes onto the register CCE and part-time, in the CCE session admitted for, with what the list gave
    SELECT * INTO l FROM admissions.cce_candidate WHERE id = c.cce_candidate_id;
    INSERT INTO people.student (id, candidate_id, admission_no, jamb_reg_no, surname, other_names,
                                programme_code, entry_mode, entry_session, entry_level, current_level, study_mode, date_of_birth, sex, state_of_origin)
    VALUES (gen_random_uuid(), c.id,
            people.next_admission_no(v_yy, c.session),
            c.jamb_reg_no, c.surname, c.other_names, v_code,
            CASE WHEN c.entry_mode IN ('UTME', 'DIRECT_ENTRY', 'CCE') THEN c.entry_mode ELSE 'UTME' END,
            c.session, c.entry_level, c.entry_level,
            CASE WHEN c.entry_mode = 'CCE' THEN coalesce((SELECT r.study_mode FROM policy.study_route r WHERE r.code = 'CCE'), 'PART_TIME') ELSE 'FULL_TIME' END,
            l.date_of_birth, l.sex, l.state_of_origin)
    RETURNING id INTO v_id;
    IF c.entry_mode = 'CCE' THEN
        INSERT INTO people.biodata (student_id, field, value)
        SELECT v_id, x.field, x.value FROM admissions.screening_answer x JOIN admissions.application a ON a.id = x.application_id
         WHERE a.candidate_id = c.id AND btrim(x.value) <> ''
        ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value;
    END IF;
    -- the nationality JAMB's state implies, on the record from the first day (V282)
    PERFORM people.default_nationality(v_id);
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION admissions.pg_admit(p_application uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.pg_application; p admissions.pg_applicant; v_student uuid; v_yy text;
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_application FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such postgraduate application' USING ERRCODE = '23503'; END IF;
    IF a.student_id IS NOT NULL THEN RETURN a.student_id; END IF;   -- idempotent
    IF a.state <> 'ACCEPTED' THEN
        RAISE EXCEPTION 'PG_NOT_ACCEPTED: only an accepted offer is admitted to the register (this application is %)', lower(replace(a.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF NOT admissions.pg_screening_ok(p_application) THEN
        RAISE EXCEPTION 'PG_SCREENING_NOT_CLEARED: the applicant is admitted to the register once physical screening has cleared them' USING ERRCODE = '23514',
              HINT = 'Record the screening decision; CLEARED admits the applicant at once.';
    END IF;
    SELECT * INTO p FROM admissions.pg_applicant WHERE id = a.applicant_id;
    v_yy := substr(a.session, 3, 2);

    INSERT INTO people.student (id, candidate_id, admission_no, surname, other_names, sex, date_of_birth, state_of_origin,
                               programme_code, entry_mode, entry_session, entry_level, current_level, status, school_id)
    VALUES (gen_random_uuid(), NULL,
            people.next_admission_no(v_yy, a.session),
            p.surname, p.other_names, p.sex, p.date_of_birth, p.state_of_origin,
            a.programme_code, 'POSTGRADUATE', a.session, a.entry_level, a.entry_level, 'ADMITTED', 'S002')
    RETURNING id INTO v_student;

    -- the applicant's reach becomes the student's, so every notice from here finds them
    INSERT INTO people.student_contact (student_id, phone, email, address, updated_at)
    VALUES (v_student, p.phone, lower(p.email), p.contact_address, now())
    ON CONFLICT (student_id) DO NOTHING;

    -- the same password opens the student portal on the admission number: no second account to create
    INSERT INTO iam.student_account (id, student_id, password_hash, must_change)
    VALUES (gen_random_uuid(), v_student, p.password_hash, false)
    ON CONFLICT (student_id) DO NOTHING;

    UPDATE admissions.pg_application
       SET state = 'ADMITTED', admitted_at = now(), student_id = v_student
     WHERE id = p_application;
    RETURN v_student;
END;
$function$;

-- ── 1. duplicate results resolved by the Registry's side ──
CREATE TABLE assessment.duplicate_resolution (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id       uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    session          text NOT NULL,
    semester         integer NOT NULL,
    base_code        text NOT NULL,
    kept_offering    uuid NOT NULL REFERENCES catalogue.offering (id) ON DELETE CASCADE,
    dropped_offering uuid NOT NULL REFERENCES catalogue.offering (id) ON DELETE CASCADE,
    dropped_entry_was text,   -- the withdrawn course's registration as it stood (APPROVED, REGISTERED), NULL when it had none
    reason           text NOT NULL CHECK (length(btrim(reason)) >= 10),
    decided_by       uuid NOT NULL,
    decided_office   text NOT NULL,
    decided_at       timestamptz NOT NULL DEFAULT now(),
    undone_at        timestamptz,
    undone_by        uuid,
    undone_office    text,
    undone_reason    text,
    CHECK (kept_offering <> dropped_offering),
    CHECK ((undone_at IS NULL) = (undone_by IS NULL) AND (undone_at IS NULL) = (undone_reason IS NULL))
);
-- a class is withdrawn for a student once at a time (a course on three classes takes two decisions)
CREATE UNIQUE INDEX ux_duplicate_resolution_open ON assessment.duplicate_resolution (student_id, dropped_offering) WHERE undone_at IS NULL;
CREATE INDEX ix_duplicate_resolution_student ON assessment.duplicate_resolution (student_id, session, semester) WHERE undone_at IS NULL;
SELECT audit.attach('assessment.duplicate_resolution');
COMMENT ON TABLE assessment.duplicate_resolution IS
  'V702: a student''s duplicate result resolved — the class that stands and the one withdrawn from the registration (its mark kept on its sheet), why, by whom; put back when undone.';

-- the course a code is (its BSU-/MOAU- twin and a second course under the code read as one, as the exceptions read it)
CREATE OR REPLACE FUNCTION assessment.base_course_code(p_code text)
RETURNS text LANGUAGE sql STABLE AS $$ SELECT regexp_replace(catalogue.shown_code(p_code), '^(BSU|MOAU)-', '') $$;

-- each class of a duplicated course with a mark for the student: the result on it, the registration of it, and the decision standing
CREATE OR REPLACE FUNCTION assessment.result_duplicates(p_session text, p_sem integer, p_fac text, p_dept text, p_prog text)
RETURNS TABLE (student_id uuid, number text, student_name text, programme_code text, level integer, base_code text,
               offering_id uuid, course_code text, course_title text, sheet_id uuid, stage text, ca integer, exam integer, total integer,
               grade text, entry_status text, decision text, resolution_id uuid, decided_at timestamptz, decided_office text, decided_reason text,
               standing integer)
LANGUAGE sql STABLE AS $$
    WITH scoped AS MATERIALIZED (
        SELECT st.id, st.programme_code, st.current_level, coalesce(st.matric_no, st.admission_no) AS number,
               upper(st.surname) || ', ' || st.other_names AS student_name
          FROM people.student st JOIN ref.programme p ON p.code = st.programme_code
         WHERE (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR st.programme_code = p_prog)),
    marks AS MATERIALIZED (
        SELECT DISTINCT ON (sc.student_id, o.id) sc.student_id, o.id AS offering_id, o.course_code, assessment.base_course_code(o.course_code) AS base_code
          FROM assessment.score sc
          JOIN scoped s ON s.id = sc.student_id
          JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id
          JOIN catalogue.offering o ON o.id = sh.offering_id
         WHERE o.session = p_session AND o.semester = p_sem),
    grp AS (SELECT m.student_id, m.base_code FROM marks m GROUP BY 1, 2 HAVING count(DISTINCT m.offering_id) > 1),
    rws AS (
        SELECT m.*, dr.id AS resolution_id, dr.decided_at, dr.decided_office, dr.reason,
               CASE WHEN dr.dropped_offering = m.offering_id THEN 'WITHDRAWN' WHEN dr.kept_offering = m.offering_id THEN 'KEPT' END AS decision
          FROM marks m
          JOIN grp g ON g.student_id = m.student_id AND g.base_code = m.base_code
          LEFT JOIN LATERAL (
              SELECT d.* FROM assessment.duplicate_resolution d
               WHERE d.student_id = m.student_id AND d.undone_at IS NULL AND m.offering_id IN (d.kept_offering, d.dropped_offering)
               ORDER BY (d.dropped_offering = m.offering_id) DESC, d.decided_at DESC LIMIT 1) dr ON true)
    SELECT r.student_id, s.number, s.student_name, s.programme_code,
           coalesce((SELECT cr.level FROM registration.course_registration cr
                      WHERE cr.student_id = r.student_id AND cr.session = p_session AND cr.semester = p_sem LIMIT 1), s.current_level),
           r.base_code, r.offering_id, r.course_code, c.title, cf.sheet_id, cf.stage, cf.ca, cf.exam, cf.total, cf.grade,
           (SELECT e.status FROM registration.entry e JOIN registration.course_registration cr ON cr.id = e.registration_id
             WHERE cr.student_id = r.student_id AND e.offering_id = r.offering_id ORDER BY (e.status = 'APPROVED') DESC, (e.status = 'WITHDRAWN') LIMIT 1),
           r.decision, r.resolution_id, r.decided_at, r.decided_office, r.reason,
           (count(*) FILTER (WHERE r.decision IS DISTINCT FROM 'WITHDRAWN') OVER (PARTITION BY r.student_id, r.base_code))::int
      FROM rws r
      JOIN scoped s ON s.id = r.student_id
      LEFT JOIN catalogue.course c ON c.code = r.course_code
      LEFT JOIN LATERAL assessment.course_final(r.student_id, r.offering_id) cf ON true
$$;
COMMENT ON FUNCTION assessment.result_duplicates(text, integer, text, text, text) IS
  'V702: the students in scope with marks for one course on two classes in a session''s semester — each class with the result on it, the student''s registration of it and the decision standing (KEPT, WITHDRAWN); standing counts the classes not withdrawn (1: resolved).';

CREATE OR REPLACE FUNCTION assessment.duplicate_resolver() RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE v_office text := coalesce(nullif(current_setting('moaum.actor_office', true), ''), '');
BEGIN
    IF v_office NOT IN ('records', 'registrar', 'dregistrar', 'academic', 'ict', 'dbops', 'super') THEN
        RAISE EXCEPTION 'DUP_OFFICE: a duplicate result is resolved by Exams & Records, the Registry, the Academic Office or the Directorate of ICT' USING ERRCODE = '42501';
    END IF;
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'DUP_OFFICE: a duplicate result is resolved by a person' USING ERRCODE = '42501';
    END IF;
    RETURN v_office;
END $$;

CREATE OR REPLACE FUNCTION assessment.resolve_duplicate(p_student uuid, p_keep uuid, p_drop uuid, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_office text := assessment.duplicate_resolver(); v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        k catalogue.offering; d catalogue.offering; v_was text; v_id uuid;
BEGIN
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'DUP_REASON: say why this course stands, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO k FROM catalogue.offering WHERE id = p_keep;
    SELECT * INTO d FROM catalogue.offering WHERE id = p_drop;
    IF k.id IS NULL OR d.id IS NULL OR k.id = d.id OR k.session <> d.session OR k.semester <> d.semester
       OR assessment.base_course_code(k.course_code) <> assessment.base_course_code(d.course_code) THEN
        RAISE EXCEPTION 'DUP_NOT_SAME: the two classes are not one course in one session''s semester' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM assessment.score sc JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id WHERE sh.offering_id = p_keep AND sc.student_id = p_student)
       OR NOT EXISTS (SELECT 1 FROM assessment.score sc JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id WHERE sh.offering_id = p_drop AND sc.student_id = p_student) THEN
        RAISE EXCEPTION 'DUP_NOT_DUPLICATE: the student does not have a mark on both classes' USING ERRCODE = '23514';
    END IF;
    PERFORM 1 FROM people.student WHERE id = p_student FOR UPDATE;   -- one decision for a student at a time
    IF EXISTS (SELECT 1 FROM assessment.duplicate_resolution r WHERE r.student_id = p_student AND r.undone_at IS NULL
                AND r.dropped_offering IN (p_keep, p_drop)) THEN
        RAISE EXCEPTION 'DUP_RESOLVED: one of these classes is withdrawn for the student already; put that decision back first to choose again' USING ERRCODE = '23514';
    END IF;
    SELECT e.status INTO v_was FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
     WHERE r.student_id = p_student AND e.offering_id = p_drop AND e.status IN ('APPROVED', 'REGISTERED') ORDER BY (e.status = 'APPROVED') DESC LIMIT 1;
    UPDATE registration.entry e SET status = 'WITHDRAWN'
      FROM registration.course_registration r
     WHERE r.id = e.registration_id AND r.student_id = p_student AND e.offering_id = p_drop AND e.status IN ('APPROVED', 'REGISTERED');
    INSERT INTO assessment.duplicate_resolution (student_id, session, semester, base_code, kept_offering, dropped_offering, dropped_entry_was, reason, decided_by, decided_office)
    VALUES (p_student, k.session, k.semester, assessment.base_course_code(k.course_code), p_keep, p_drop, v_was, btrim(p_reason), v_actor, v_office)
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;
COMMENT ON FUNCTION assessment.resolve_duplicate(uuid, uuid, uuid, text) IS
  'V702: a duplicate result resolved — the class kept stands; the other is withdrawn from the student''s registration (its mark stays on its sheet), written down with the reason. DUP_OFFICE, DUP_REASON, DUP_NOT_SAME, DUP_NOT_DUPLICATE, DUP_RESOLVED.';

CREATE OR REPLACE FUNCTION assessment.undo_duplicate_resolution(p_id uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_office text := assessment.duplicate_resolver(); v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        x assessment.duplicate_resolution;
BEGIN
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'DUP_REASON: say why it is put back, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO x FROM assessment.duplicate_resolution WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR x.undone_at IS NOT NULL THEN
        RAISE EXCEPTION 'DUP_NOT_FOUND: no standing decision %', p_id USING ERRCODE = 'P0002';
    END IF;
    IF x.dropped_entry_was IS NOT NULL THEN
        UPDATE registration.entry e SET status = x.dropped_entry_was
          FROM registration.course_registration r
         WHERE r.id = e.registration_id AND r.student_id = x.student_id AND e.offering_id = x.dropped_offering AND e.status = 'WITHDRAWN';
    END IF;
    UPDATE assessment.duplicate_resolution SET undone_at = now(), undone_by = v_actor, undone_office = v_office, undone_reason = btrim(p_reason) WHERE id = p_id;
END $$;
COMMENT ON FUNCTION assessment.undo_duplicate_resolution(uuid, text) IS
  'V702: a duplicate''s decision put back — the withdrawn course''s registration as it stood, the decision kept with who undid it and why.';

-- restated from V700: the exceptions pass over a class withdrawn as a duplicate
CREATE OR REPLACE FUNCTION assessment.result_exceptions(p_session text, p_sem integer, p_fac text, p_dept text, p_prog text, p_level integer)
 RETURNS TABLE(kind text, student_id uuid, offering_id uuid, sheet_id uuid, course_code text, level integer, detail text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH rec AS MATERIALIZED (
        SELECT * FROM assessment.result_records(p_session, p_sem, p_fac, p_dept, p_prog, p_level, NULL)),
    scoped AS MATERIALIZED (
        SELECT st.id, st.programme_code, st.current_level
          FROM people.student st JOIN ref.programme p ON p.code = st.programme_code
         WHERE (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR st.programme_code = p_prog)),
    marks AS MATERIALIZED (   -- the latest mark of each student in scope on each sheet of the session's semester
        SELECT DISTINCT ON (sc.sheet_id, sc.student_id) sc.sheet_id, sc.student_id, sc.version, sc.ca, sc.exam, sc.total, sc.outcome, sc.imported,
               o.id AS offering_id, o.course_code, c.ca_max,
               regexp_replace(catalogue.shown_code(o.course_code), '^(BSU|MOAU)-', '') AS base_code,
               coalesce((SELECT r.level FROM registration.course_registration r
                          WHERE r.student_id = sc.student_id AND r.session = p_session AND r.semester = p_sem LIMIT 1), s.current_level) AS level
          FROM assessment.score sc
          JOIN scoped s ON s.id = sc.student_id
          JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id
          JOIN catalogue.offering o ON o.id = sh.offering_id
          JOIN catalogue.course c ON c.code = o.course_code
         WHERE o.session = p_session AND o.semester = p_sem
         ORDER BY sc.sheet_id, sc.student_id, sc.version DESC),
    lv AS MATERIALIZED (SELECT * FROM marks WHERE p_level IS NULL OR level = p_level),
    -- one course with marks on two classes: grouped once, never each mark against every other
    dup AS MATERIALIZED (
        SELECT d.student_id, d.base_code, string_agg(DISTINCT d.course_code, ', ' ORDER BY d.course_code) AS codes
          FROM lv d
         WHERE NOT EXISTS (SELECT 1 FROM assessment.duplicate_resolution dr   -- V702: a class withdrawn for the student is not counted
                            WHERE dr.student_id = d.student_id AND dr.dropped_offering = d.offering_id AND dr.undone_at IS NULL)
         GROUP BY d.student_id, d.base_code HAVING count(DISTINCT d.offering_id) > 1)
    -- a mark with no approved registration of the course
    SELECT 'RESULT_WITHOUT_REGISTRATION'::text, m.student_id, m.offering_id, m.sheet_id, m.course_code, m.level,
           'A mark for ' || m.course_code || ' with no approved registration of the course in ' || p_session || ', semester ' || p_sem
      FROM lv m
     WHERE NOT EXISTS (SELECT 1 FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                        WHERE e.offering_id = m.offering_id AND r.student_id = m.student_id AND e.status = 'APPROVED' AND r.status IN ('APPROVED', 'LOCKED'))
       AND NOT EXISTS (SELECT 1 FROM assessment.duplicate_resolution dr   -- V702: withdrawn as a duplicate, its mark kept as history
                        WHERE dr.student_id = m.student_id AND dr.dropped_offering = m.offering_id AND dr.undone_at IS NULL)
    UNION ALL
    -- marks for one course on two classes
    SELECT 'DUPLICATE_RESULT', m.student_id, m.offering_id, m.sheet_id, m.course_code, m.level, 'Marks for the same course on ' || d.codes
      FROM lv m JOIN dup d ON d.student_id = m.student_id AND d.base_code = m.base_code
     WHERE NOT EXISTS (SELECT 1 FROM assessment.duplicate_resolution dr
                        WHERE dr.student_id = m.student_id AND dr.dropped_offering = m.offering_id AND dr.undone_at IS NULL)
    UNION ALL
    -- a registered student with no mark on a sheet past entry
    SELECT 'MISSING_SCORE', r.student_id, r.offering_id, r.sheet_id, r.course_code, r.level,
           'Registered for ' || r.course_code || '; its sheet is at ' || r.stage || ' with no mark for the student'
      FROM rec r WHERE assessment.result_state(r.stage, r.has_score) = 'MISSING'
    UNION ALL
    -- a mark entered on the portal above the course's CA or its examination maximum (an old portal's total is read whole, V614)
    SELECT 'INVALID_SCORE', m.student_id, m.offering_id, m.sheet_id, m.course_code, m.level,
           m.course_code || ': CA ' || coalesce(m.ca::text, '–') || ' and examination ' || coalesce(m.exam::text, '–') || ' against a CA of '
           || coalesce(m.ca_max, 40) || ' and an examination of ' || (100 - coalesce(m.ca_max, 40))
      FROM lv m
     WHERE m.outcome = 'GRADED' AND NOT m.imported
       AND (coalesce(m.ca, 0) > coalesce(m.ca_max, 40) OR coalesce(m.exam, 0) > 100 - coalesce(m.ca_max, 40))
    UNION ALL
    -- a course of a higher level than the registration, with a mark
    SELECT 'COURSE_ABOVE_LEVEL', r.student_id, r.offering_id, r.sheet_id, r.course_code, r.level,
           r.course_code || ' is a ' || r.course_level || ' Level course on a ' || r.level || ' Level registration'
      FROM rec r WHERE r.has_score AND r.course_level > r.level
    UNION ALL
    -- a course taught in the other semester, with a mark in this one
    SELECT 'COURSE_OTHER_SEMESTER', r.student_id, r.offering_id, r.sheet_id, r.course_code, r.level,
           r.course_code || ' is taught in semester ' || r.course_semester || ', with a mark in semester ' || p_sem
      FROM rec r WHERE r.has_score AND r.course_semester IS NOT NULL AND NOT catalogue.runs_in(r.course_semester, coalesce(r.both_semesters, false), p_sem)
    UNION ALL
    -- a course with a mark the programme neither registered under its structure nor binds (the broadsheet's rule, V624)
    SELECT 'COURSE_OUTSIDE_PROGRAMME', r.student_id, r.offering_id, r.sheet_id, r.course_code, r.level,
           r.course_code || ' is not in the structure of ' || r.programme_code
      FROM rec r
     WHERE r.has_score AND r.basis IS NULL
       AND regexp_replace(r.course_code, '^(BSU|MOAU)-', '') !~ '^(GST|EPS) '
       AND NOT EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = r.course_code AND c.kind = 'GST')
       AND NOT EXISTS (SELECT 1 FROM catalogue.course_offer co
                        WHERE co.programme_code = r.programme_code
                          AND co.course_code IN (r.course_code, regexp_replace(r.course_code, '^(BSU|MOAU)-', ''),
                                                 'BSU-' || regexp_replace(r.course_code, '^(BSU|MOAU)-', ''),
                                                 'MOAU-' || regexp_replace(r.course_code, '^(BSU|MOAU)-', '')))
       AND NOT EXISTS (SELECT 1 FROM assessment.broadsheet_omission bo
                        WHERE bo.programme_code = r.programme_code AND bo.level = r.level AND bo.session = p_session AND bo.semester = p_sem
                          AND bo.course_code = r.course_code)
    UNION ALL
    -- a carry-over registered for a course passed on a published result before
    SELECT 'PASSED_STILL_CARRIED', r.student_id, r.offering_id, r.sheet_id, r.course_code, r.level,
           r.course_code || ' is registered as a carry-over, passed in ' || pr.session || ' (' || pr.grade || ')'
      FROM rec r
      CROSS JOIN LATERAL (
          SELECT o2.session, cf.grade
            FROM registration.course_registration r2
            JOIN registration.entry e2 ON e2.registration_id = r2.id AND e2.status = 'APPROVED'
            JOIN catalogue.offering o2 ON o2.id = e2.offering_id
            CROSS JOIN LATERAL assessment.course_final(r2.student_id, o2.id) cf
           WHERE r2.student_id = r.student_id AND r2.status IN ('APPROVED', 'LOCKED')
             AND regexp_replace(catalogue.shown_code(o2.course_code), '^(BSU|MOAU)-', '') = regexp_replace(catalogue.shown_code(r.course_code), '^(BSU|MOAU)-', '')
             AND (left(o2.session, 4)::int < left(p_session, 4)::int OR (o2.session = p_session AND o2.semester < p_sem))
             AND cf.stage = 'PUBLISHED' AND coalesce(cf.points, 0) > 0
           ORDER BY o2.session DESC LIMIT 1) pr
     WHERE r.entry_type = 'CARRYOVER'
    UNION ALL
    -- an uploaded result held for a number no student holds (no programme to scope it by: University-wide only)
    SELECT 'RESULT_HELD_NO_STUDENT', NULL::uuid, NULL::uuid, NULL::uuid, h.course_code, NULL::integer,
           'Uploaded for ' || h.matric || ' on ' || to_char(h.loaded_at, 'DD Mon YYYY') || '; no student holds that number'
      FROM assessment.legacy_result_holding h
     WHERE h.session = p_session AND h.semester = p_sem AND p_fac IS NULL AND p_dept IS NULL AND p_prog IS NULL AND p_level IS NULL
$function$;

-- ── 2. correction requests told ──
CREATE OR REPLACE FUNCTION assessment.mark_words(p_ca integer, p_exam integer, p_total integer, p_grade text, p_outcome text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_outcome IS NOT NULL AND p_outcome <> 'GRADED' THEN initcap(lower(p_outcome))
                WHEN p_ca IS NULL AND p_exam IS NULL AND p_total IS NULL THEN 'no mark'
                ELSE concat_ws(' · ', CASE WHEN p_ca IS NOT NULL THEN 'CA ' || p_ca END, CASE WHEN p_exam IS NOT NULL THEN 'Exam ' || p_exam END,
                               coalesce(p_total, p_ca + p_exam)::text || CASE WHEN p_grade IS NOT NULL THEN ' (' || p_grade || ')' ELSE '' END) END
$$;

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('CORRECTION_REQUESTED', 'A result correction asked of the desk of entry',
 'To the course''s lecturer when the Director of ICT asks for a student''s result to be corrected',
 'Correction [REF]: [COURSE] — [STUDENT]',
 E'Dear [FIRST_NAME],\n\nThe Director of ICT asks for a correction of [STUDENT]''s result in [COURSE] ([SESSION]).\n\nReason: [REASON] — [NOTE]\nAs it stands: [CURRENT]\nAsked for: [PROPOSED]\n\nCorrect the mark on the score sheet while it is at entry, or raise the amendment once it is published; or decline it with your reason. It is on the sheet in your portal: [PORTAL_URL]\n\n[UNIVERSITY_SHORT] Directorate of ICT',
 '[UNIVERSITY_SHORT]: correction [REF] asked of you for [STUDENT] in [COURSE] ([SESSION]). See the score sheet on your portal.',
 'Correction asked: [COURSE]',
 'The Director of ICT asks for a correction of [STUDENT]''s result in [COURSE] ([SESSION]): [REASON] — [NOTE]. As it stands: [CURRENT]. Asked for: [PROPOSED]. Correct it on the sheet, raise the amendment, or decline it with your reason.',
 ARRAY['FIRST_NAME','REF','COURSE','STUDENT','SESSION','REASON','NOTE','CURRENT','PROPOSED','PORTAL_URL','UNIVERSITY_SHORT'], false, 'HIGH'),
('CORRECTION_CLOSED', 'A result correction answered',
 'To the person who asked for a result correction, when it is corrected or declined',
 'Correction [REF] [STATE]: [COURSE] — [STUDENT]',
 E'Dear [FIRST_NAME],\n\nYour correction [REF] of [STUDENT]''s result in [COURSE] ([SESSION]) was [STATE].\n\n[NOTE]\n\n[UNIVERSITY_SHORT]',
 '[UNIVERSITY_SHORT]: correction [REF] of [STUDENT] in [COURSE] was [STATE].',
 'Correction [REF] [STATE]',
 'Your correction [REF] of [STUDENT]''s result in [COURSE] ([SESSION]) was [STATE]. [NOTE]',
 ARRAY['FIRST_NAME','REF','COURSE','STUDENT','SESSION','STATE','NOTE','UNIVERSITY_SHORT'], false, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION assessment.correction_told()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE o catalogue.offering; st people.student; v_student text; v_reason text;
BEGIN
    SELECT og.* INTO o FROM assessment.score_sheet sh JOIN catalogue.offering og ON og.id = sh.offering_id WHERE sh.id = NEW.sheet_id;
    SELECT * INTO st FROM people.student WHERE id = NEW.student_id;
    v_student := upper(st.surname) || ', ' || st.other_names || ' (' || coalesce(st.matric_no, st.admission_no, '') || ')';
    v_reason := initcap(lower(replace(NEW.reason_kind, '_', ' ')));
    IF TG_OP = 'INSERT' THEN
        -- the course's lecturer is told; the request is on the sheet for the rest of the desk of entry
        IF o.lecturer_id IS NOT NULL THEN
            PERFORM platform.tell_person(o.lecturer_id, 'CORRECTION_REQUESTED', NULL,
                jsonb_build_object('REF', NEW.ref, 'COURSE', o.course_code, 'STUDENT', v_student, 'SESSION', o.session || ', semester ' || o.semester,
                                   'REASON', v_reason, 'NOTE', NEW.note,
                                   'CURRENT', assessment.mark_words(NEW.was_ca, NEW.was_exam, NEW.was_total, NEW.was_grade, NEW.was_outcome),
                                   'PROPOSED', CASE WHEN NEW.ca IS NULL AND NEW.outcome IS NULL THEN 'the result removed or moved'
                                                    ELSE assessment.mark_words(NEW.ca, NEW.exam, NULL, NULL, NEW.outcome) END),
                'CORRECTION_REQUESTED:' || NEW.ref);
        END IF;
    ELSIF NEW.state IN ('RESOLVED', 'DECLINED') AND OLD.state IS DISTINCT FROM NEW.state THEN
        PERFORM platform.tell_person(NEW.requested_by, 'CORRECTION_CLOSED', NULL,
            jsonb_build_object('REF', NEW.ref, 'COURSE', o.course_code, 'STUDENT', v_student, 'SESSION', o.session || ', semester ' || o.semester,
                               'STATE', CASE NEW.state WHEN 'RESOLVED' THEN 'corrected' ELSE 'declined' END, 'NOTE', coalesce(NEW.closed_note, '')),
            'CORRECTION_CLOSED:' || NEW.ref || ':' || NEW.state);
    END IF;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_correction_told AFTER INSERT OR UPDATE OF state ON assessment.correction_request
    FOR EACH ROW EXECUTE FUNCTION assessment.correction_told();

-- ── 3. late results raised by the sheet ──
CREATE OR REPLACE FUNCTION assessment.raise_late_results(p_sheet uuid, p_rows jsonb, p_reason text)
RETURNS TABLE (row_no integer, number text, outcome text, detail text, ref text)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; i int := 0; v_no text; v_student uuid; v_id uuid; v_err text; v_seen text[] := '{}';
BEGIN
    -- the whole upload refused at once where every row would be: the desk, the sheet's stage, the reason
    PERFORM assessment.require_stage_desk('ENTRY', nullif(current_setting('moaum.actor_office', true), ''), 'raised');
    IF NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh WHERE sh.id = p_sheet AND sh.stage = 'PUBLISHED') THEN
        RAISE EXCEPTION 'LATE_NOT_PUBLISHED: late results are raised for a published sheet; before publication the marks go on the sheet itself' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'LATE_REASON: say why the results are late, in words Senate can read' USING ERRCODE = '23514';
    END IF;
    IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'LATE_ROWS: the upload has no rows' USING ERRCODE = '23514';
    END IF;
    IF jsonb_array_length(p_rows) > 2000 THEN
        RAISE EXCEPTION 'LATE_ROWS: at most 2,000 rows a time' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT x FROM jsonb_array_elements(p_rows) x LOOP
        i := i + 1;
        row_no := i;
        v_no := upper(btrim(coalesce(r->>'number', r->>'matric', r->>'matricNo', '')));
        number := v_no;
        ref := NULL;
        IF v_no = '' THEN
            outcome := 'REFUSED'; detail := 'No matriculation number'; RETURN NEXT; CONTINUE;
        END IF;
        IF v_no = ANY (v_seen) THEN
            outcome := 'REPEATED'; detail := 'The number is on an earlier row'; RETURN NEXT; CONTINUE;
        END IF;
        v_seen := v_seen || v_no;
        SELECT c.student_id INTO v_student FROM assessment.late_candidates(p_sheet) c WHERE upper(c.number) = v_no LIMIT 1;
        IF v_student IS NULL THEN
            outcome := 'NOT_LATE';
            detail := CASE WHEN EXISTS (SELECT 1 FROM assessment.score sc JOIN people.student s ON s.id = sc.student_id
                                         WHERE sc.sheet_id = p_sheet AND upper(coalesce(s.matric_no, s.admission_no)) = v_no)
                           THEN 'The student has a mark on this sheet: correct it by an amendment' ELSE 'Not on this class''s roll without a mark' END;
            RETURN NEXT; CONTINUE;
        END IF;
        BEGIN
            v_id := assessment.raise_amendment(p_sheet, v_student, nullif(r->>'ca', '')::int, nullif(r->>'exam', '')::int,
                                               nullif(upper(btrim(coalesce(r->>'outcome', ''))), ''), p_reason, NULL);
            outcome := 'RAISED'; detail := NULL;
            ref := (SELECT m.ref FROM assessment.amendment m WHERE m.id = v_id);
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
            outcome := 'REFUSED'; detail := v_err;
        END;
        RETURN NEXT;
    END LOOP;
END $$;
COMMENT ON FUNCTION assessment.raise_late_results(uuid, jsonb, text) IS
  'V702: late results raised from one upload for a published sheet''s candidates with no mark — each a late amendment through the chain (assessment.raise_amendment, V422); RAISED, NOT_LATE, REPEATED or REFUSED with the reason.';

-- ── 4. a held student never goes above the hold ──
CREATE OR REPLACE FUNCTION people.department_hold_of(p_student uuid, p_session text)
RETURNS integer LANGUAGE sql STABLE AS $$
    -- the cohort standing is the one the change of department set (a cohort the desk set since for another reason is not a hold)
    SELECT people.cohort_cap(p_student, p_session)
     WHERE EXISTS (SELECT 1 FROM people.cohort_override o
                    WHERE o.student_id = p_student
                      AND EXISTS (SELECT 1 FROM people.cohort_decision d WHERE d.student_id = p_student AND d.rule = 'COHORT_DEPARTMENT_CHANGE'
                                     AND d.effective_cohort = o.effective_cohort AND d.reason IS NOT DISTINCT FROM o.reason))
$$;
COMMENT ON FUNCTION people.department_hold_of(uuid, text) IS
  'V702: the level a student held after a change of department (V696) may reach in a session — NULL when no hold stands (none set, or taken off on the cohort desk).';

CREATE OR REPLACE FUNCTION people.hold_level_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_ses text; v_cap int;
BEGIN
    -- the Bursary's reading of the fees without the hold lifts it for a moment and undoes it (finance.department_change_fee_effect)
    IF coalesce(current_setting('moaum.level_hold', true), '') = 'off' THEN RETURN NEW; END IF;
    -- the session the level is for: the one a roll-over rolls into (it says so), else the student's current session
    v_ses := coalesce(nullif(current_setting('moaum.level_session', true), ''), people.student_current_session(NEW.id), policy.university_current_session());
    v_cap := people.department_hold_of(NEW.id, v_ses);
    IF v_cap IS NOT NULL AND NEW.current_level > v_cap THEN
        INSERT INTO people.cohort_decision (student_id, previous_status, final_status, previous_cohort, effective_cohort, previous_level, new_level,
                                            rule, reason, officer, actor_office, session)
        SELECT NEW.id, OLD.status, NEW.status, OLD.entry_session, o.effective_cohort, OLD.current_level, greatest(OLD.current_level, v_cap),
               'LEVEL_HELD_DEPARTMENT_CHANGE', 'Held at ' || greatest(OLD.current_level, v_cap) || ' Level after a change of department; ' || NEW.current_level
               || ' asked for. Take the hold off on the cohort desk first.',
               nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''), v_ses
          FROM people.cohort_override o WHERE o.student_id = NEW.id;
        NEW.current_level := greatest(OLD.current_level, v_cap);
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_student_hold_level BEFORE UPDATE OF current_level ON people.student
    FOR EACH ROW WHEN (NEW.current_level > OLD.current_level) EXECUTE FUNCTION people.hold_level_guard();

-- restated from V641 (people.roll_over_session): the hold counted in the session rolled into
CREATE OR REPLACE FUNCTION people.roll_over_session(p_to_session text, p_confirm text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_created boolean := false; v_promoted int := 0; v_held int := 0; v_to int; r record;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a session roll-over is made by a person' USING ERRCODE = '23514';
    END IF;
    IF upper(btrim(coalesce(p_confirm, ''))) <> 'ROLLOVER' THEN
        RAISE EXCEPTION 'type ROLLOVER to confirm promoting continuing students into %', p_to_session USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'a session roll-over names its reason' USING ERRCODE = '23514';
    END IF;
    v_to := policy.session_year(p_to_session);
    IF v_to IS NULL THEN
        RAISE EXCEPTION 'a session is named YYYY/YYYY, not %', p_to_session USING ERRCODE = '23514';
    END IF;
    -- V702: the levels set here are the target session's (a student held after a change of department is held in it)
    PERFORM set_config('moaum.level_session', p_to_session, true);

    -- open the target session (and its two semesters) if it is not there yet, as PLANNED
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_to_session) THEN
        PERFORM assessment.ensure_session(p_to_session);
        UPDATE policy.academic_session SET state = 'PLANNED' WHERE name = p_to_session;
        v_created := true;
    END IF;

    -- V641: a student enters a session at their entry level — never promoted into their entry session (or one before it), nor
    -- past the level the entry reaches by the target session; counted, before anyone moves
    SELECT count(*) INTO v_held
      FROM people.student s
     WHERE s.status IN ('ACTIVE', 'PROBATION')
       AND s.matric_no IS NOT NULL
       AND s.current_level < coalesce(finance.final_level(s.programme_code), 400)
       AND NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.student_id = s.id AND e.session = p_to_session)
       AND NOT coalesce(policy.session_year(s.entry_session) < v_to
                        AND s.current_level + 100 <= s.entry_level + 100 * (v_to - policy.session_year(s.entry_session))
                        AND s.current_level + 100 <= coalesce(people.department_hold_of(s.id, p_to_session), 999), false);   -- V702

    FOR r IN
        SELECT s.id, s.current_level + 100 AS new_level
          FROM people.student s
         WHERE s.status IN ('ACTIVE', 'PROBATION')
           AND s.matric_no IS NOT NULL
           AND s.current_level < coalesce(finance.final_level(s.programme_code), 400)
           AND NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.student_id = s.id AND e.session = p_to_session)
           AND policy.session_year(s.entry_session) < v_to
           AND s.current_level + 100 <= s.entry_level + 100 * (v_to - policy.session_year(s.entry_session))
           AND s.current_level + 100 <= coalesce(people.department_hold_of(s.id, p_to_session), 999)   -- V702: never above a hold
    LOOP
        UPDATE people.student SET current_level = r.new_level WHERE id = r.id;
        INSERT INTO people.enrolment (id, student_id, session, level)
        VALUES (gen_random_uuid(), r.id, p_to_session, r.new_level)
        ON CONFLICT (student_id, session) DO NOTHING;
        v_promoted := v_promoted + 1;
    END LOOP;

    PERFORM set_config('moaum.level_session', '', true);
    RETURN jsonb_build_object('session', p_to_session, 'created_session', v_created,
                             'promoted', v_promoted, 'held', v_held, 'reason', btrim(p_reason));
END $function$;

-- restated from V628 (people.level_options): heldAt; nothing offered above it
CREATE OR REPLACE FUNCTION people.level_options(p_student uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s people.student; p ref.programme; v_pg boolean; v_final int; v_levels int[]; v_next int; v_progress text; v_correct text; v_status text;
        v_spill text; v_spill_years int;
        v_cur text; v_cohort text; v_choices jsonb := '[]'::jsonb;  -- V628
        v_held int;  -- V702
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEVEL_STUDENT: no such student' USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO p FROM ref.programme WHERE code = s.programme_code;
    v_pg := s.entry_mode IS DISTINCT FROM 'CCE' AND (s.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE');
    IF v_pg THEN
        -- a postgraduate student is held at the programme's own level (V455): a Master's 800, a PhD 900, a PGD 700
        v_final := coalesce(people.pg_level_of(s.programme_code), 800);
        v_levels := ARRAY[v_final];
    ELSE
        v_final := coalesce(records.final_level_of(p_student), 400);
        SELECT array_agg(l ORDER BY l) INTO v_levels FROM generate_series(100, v_final, 100) l;
        v_next := CASE WHEN s.current_level < v_final THEN s.current_level + 100 END;
    END IF;
    -- V601: the cohort engine's spillover reading — past the programme's length, the student belongs at the final level
    SELECT ap.spillover_state, ap.spillover_years, ap.current_session, ap.effective_cohort INTO v_spill, v_spill_years, v_cur, v_cohort
      FROM people.academic_position ap WHERE ap.student_id = p_student;
    v_cur := coalesce(v_cur, policy.university_current_session());
    -- V702: a student held a level behind after a change of department (V696) reaches no level above the hold this session
    IF NOT v_pg THEN
        v_held := people.department_hold_of(p_student, v_cur);
        IF v_held IS NOT NULL AND v_next > v_held THEN v_next := NULL; END IF;
    END IF;
    v_status := lower(replace(s.status, '_', ' '));
    -- what holds either change, then what holds a progression
    v_correct := CASE
        WHEN s.duplicate_of IS NOT NULL THEN 'LEVEL_MERGED_RECORD: this record was merged into another; change the level on the record it was merged into'
        WHEN s.status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') THEN 'LEVEL_STATUS: the student is ' || v_status || '; a level is changed only for a student in study (admitted, active or on probation)'
        END;
    v_progress := coalesce(v_correct, CASE
        WHEN v_pg THEN 'LEVEL_PG_PROGRESSION: a postgraduate student stays at the programme''s level (' || v_final || '); there is no next level'
        WHEN v_held IS NOT NULL AND s.current_level >= v_held AND s.current_level < v_final THEN 'LEVEL_HELD_DEPARTMENT_CHANGE: the student changed department and is held at '
             || v_held || ' Level this session, a level behind the cohort they entered with; take the hold off on the cohort desk first'
        WHEN s.current_level >= v_final THEN 'LEVEL_AT_FINAL: the student is at the programme''s final level (' || v_final || '); a further session there is a spillover year, not a new level'
        WHEN v_spill LIKE 'SPILLOVER%' THEN 'LEVEL_IN_SPILLOVER: the student is past the programme''s length ('
             || CASE WHEN v_spill = 'SPILLOVER_LIMIT_REACHED' THEN 'beyond the spillover limit' ELSE 'SP' || coalesce(v_spill_years, 1) END
             || '); the record belongs at the final level (' || v_final || ') — correct it there rather than progress it a level at a time'
        END);
    -- V628: the spillover years the desk may set — SP1 and SP2, and the final year again for a student in spillover — each by the
    -- expected completion it pins (people.completion_override): the session before this one makes this one SP1, two before SP2,
    -- this one the final year. Offered for an undergraduate in study, a session on the calendar not before the cohort; never the
    -- year the student is in now.
    IF NOT v_pg AND v_correct IS NULL AND v_cur IS NOT NULL THEN
        SELECT coalesce(jsonb_agg(jsonb_build_object('year', z.y, 'completion', z.c) ORDER BY z.y), '[]'::jsonb) INTO v_choices
          FROM (SELECT y, CASE WHEN y = 0 THEN v_cur ELSE policy.session_before(v_cur, y) END AS c FROM unnest(ARRAY[0, 1, 2]) y) z
         WHERE (z.y > 0 OR v_spill LIKE 'SPILLOVER%')
           AND NOT (s.current_level = v_final AND coalesce(v_spill, '') = CASE WHEN z.y = 0 THEN '' ELSE 'SPILLOVER_YEAR_' || z.y END)
           AND EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = z.c AND a.state <> 'CANCELLED')
           AND (v_cohort IS NULL OR policy.session_year(z.c) >= policy.session_year(v_cohort));
    END IF;
    RETURN jsonb_build_object(
        'currentLevel', s.current_level, 'entryLevel', s.entry_level, 'finalLevel', v_final, 'postgraduate', v_pg, 'levels', to_jsonb(v_levels),
        'nextLevel', v_next, 'status', s.status, 'progressRefusal', v_progress, 'correctRefusal', v_correct, 'spilloverState', v_spill,
        'otherLevels', to_jsonb(ARRAY(SELECT l FROM unnest(v_levels) l WHERE l <> s.current_level AND (v_held IS NULL OR l <= v_held) ORDER BY l)),
        'currentSession', v_cur, 'spilloverChoices', v_choices, 'heldAt', v_held);
END $function$;

-- restated from V642 (people.support_set_level): a level above the hold refused
CREATE OR REPLACE FUNCTION people.support_set_level(p_student uuid, p_action text, p_level integer, p_expected integer, p_reason text, p_session text, p_semester integer, p_ticket uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor  uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
        v_action text := upper(btrim(coalesce(p_action, '')));
        s people.student; o jsonb; v_target int; v_refusal text; v_last people.cohort_decision; ap people.academic_position; v_id uuid; v_rule text; v_carried jsonb;
BEGIN
    -- V591: the Students Account Officer holds the level desk beside ICT Support
    IF coalesce(v_office, '') NOT IN ('ictagent', 'helpdeskhead', 'ict', 'admin', 'super', 'studentaccounts', 'academic', 'registrar', 'dregistrar') THEN
        RAISE EXCEPTION 'LEVEL_SUPPORT_OFFICE: a level is changed by ICT Support, the Students Account Officer, the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF v_action NOT IN ('PROGRESS', 'CORRECTION') THEN
        RAISE EXCEPTION 'LEVEL_ACTION: a level is progressed (PROGRESS) or corrected (CORRECTION)' USING ERRCODE = '23514';
    END IF;
    IF v_reason IS NULL OR length(v_reason) < 10 THEN
        RAISE EXCEPTION 'LEVEL_REASON: say why the level is changed, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    -- one change at a time on a student: the row is held until the change is written
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEVEL_STUDENT: no such student' USING ERRCODE = 'P0002'; END IF;
    o := people.level_options(p_student);
    v_target := CASE WHEN v_action = 'PROGRESS' THEN (o->>'nextLevel')::int ELSE p_level END;
    v_rule := CASE WHEN v_action = 'PROGRESS' THEN 'LEVEL_PROGRESS' ELSE 'LEVEL_CORRECTION' END;

    -- the level read on the screen is no longer the record's: the same change a moment ago by the same person is that change,
    -- anything else is refused, so a stale screen never moves a student twice
    IF p_expected IS DISTINCT FROM s.current_level THEN
        SELECT * INTO v_last FROM people.cohort_decision d
         WHERE d.student_id = p_student AND d.rule IN ('LEVEL_PROGRESS', 'LEVEL_CORRECTION') ORDER BY d.decided_at DESC LIMIT 1;
        IF v_last.id IS NOT NULL AND v_last.decided_at > now() - interval '1 minute' AND v_last.officer IS NOT DISTINCT FROM v_actor
           AND v_last.previous_level = p_expected AND v_last.new_level = s.current_level
           AND v_last.rule = v_rule AND (v_action = 'PROGRESS' OR p_level = s.current_level) THEN
            RETURN jsonb_build_object('alreadyDone', true, 'previousLevel', v_last.previous_level, 'newLevel', v_last.new_level, 'decisionId', v_last.id,
                                      'action', v_last.rule);
        END IF;
        RAISE EXCEPTION 'LEVEL_CHANGED: the record''s level is now %, not %; read the student again', s.current_level, coalesce(p_expected::text, 'what was shown')
            USING ERRCODE = '23514';
    END IF;

    v_refusal := CASE WHEN v_action = 'PROGRESS' THEN o->>'progressRefusal' ELSE o->>'correctRefusal' END;
    IF v_refusal IS NOT NULL THEN RAISE EXCEPTION '%', v_refusal USING ERRCODE = '23514'; END IF;
    IF v_action = 'PROGRESS' AND p_level IS NOT NULL AND p_level IS DISTINCT FROM v_target THEN
        RAISE EXCEPTION 'LEVEL_NOT_NEXT: the next level after % is %, not %; a different level is a correction', s.current_level, v_target, p_level USING ERRCODE = '23514';
    END IF;
    IF v_target IS NULL OR NOT (v_target = ANY (SELECT jsonb_array_elements_text(o->'levels')::int)) THEN
        RAISE EXCEPTION 'LEVEL_NOT_IN_PROGRAMME: % is not one of the levels of the student''s programme (%)', coalesce(v_target::text, 'no level'),
            (SELECT string_agg(x, ', ') FROM jsonb_array_elements_text(o->'levels') x) USING ERRCODE = '23514';
    END IF;
    IF v_target = s.current_level THEN
        RAISE EXCEPTION 'LEVEL_UNCHANGED: the student is already at % Level', v_target USING ERRCODE = '23514';
    END IF;
    -- V702: never above a hold after a change of department
    IF (o->>'heldAt') IS NOT NULL AND v_target > (o->>'heldAt')::int THEN
        RAISE EXCEPTION 'LEVEL_HELD_DEPARTMENT_CHANGE: the student changed department and is held at % Level this session; % is above it — take the hold off on the cohort desk first',
            o->>'heldAt', v_target USING ERRCODE = '23514';
    END IF;

    PERFORM set_config('moaum.reason', v_reason, true);
    SELECT * INTO ap FROM people.academic_position WHERE student_id = p_student;
    INSERT INTO people.cohort_decision (student_id, previous_status, proposed_status, final_status, classification, previous_cohort, effective_cohort,
                                        previous_level, new_level, rule, reason, officer, actor_office, session, semester, ticket_id)
    VALUES (p_student, s.status, s.status, s.status, ap.classification, ap.entry_session, ap.effective_cohort,
            s.current_level, v_target, v_rule, v_reason, v_actor, v_office,
            p_session, p_semester, p_ticket)
    RETURNING id INTO v_id;
    UPDATE people.student SET current_level = v_target WHERE id = p_student;
    -- V641: a correction carries into the session's course registrations and enrolment still at the level corrected from — the
    -- level the examination card, the GST & EPS permit, the receipt, the results and the transcript read for the session
    IF v_action = 'CORRECTION' THEN
        v_carried := people.carry_level_to_session(p_student, s.current_level, v_target, coalesce(p_session, policy.university_current_session()));
    END IF;
    -- V628: below the final level the student is not past the programme's length, so an expected completion pinned before this
    -- session (by the level desk's spillover year or the Registry) no longer stands
    IF v_target < (o->>'finalLevel')::int AND EXISTS (
            SELECT 1 FROM people.completion_override c
             WHERE c.student_id = p_student
               AND policy.session_year(c.expected_completion) < policy.session_year(coalesce(ap.current_session, policy.university_current_session()))) THEN
        PERFORM people.set_completion_override(p_student, NULL, 'Level corrected to ' || v_target || ', below the final level: ' || v_reason);
    END IF;
    RETURN jsonb_build_object('alreadyDone', false, 'previousLevel', s.current_level, 'newLevel', v_target, 'decisionId', v_id, 'action', v_rule,
                              'carried', v_carried);
END $function$;

-- ── 5. the held students' fees, for the Bursary ──
-- Charged as they are (the held level's fee). Beside it, what the session would charge without the hold — the cohort as entered,
-- the record at the level the hold lowered it from — read with the hold lifted and everything undone, as finance.level_fee_effect
-- reads a level change (V576).
CREATE OR REPLACE FUNCTION finance.department_change_fee_effect(p_session text)
RETURNS TABLE (student_id uuid, number text, student_name text, programme_code text, held_level integer, unheld_level integer,
               held_spillover text, charged_held numeric, charged_unheld numeric, difference numeric)
LANGUAGE plpgsql AS $$
DECLARE v_ids uuid[]; v_now jsonb := '{}'; v_then jsonb := '{}'; v_up jsonb := '{}'; v_spill jsonb := '{}';
BEGIN
    IF coalesce(p_session, '') !~ '^[0-9]{4}/[0-9]{4}$' THEN
        RAISE EXCEPTION 'HELD_FEES_SESSION: a session is named YYYY/YYYY, not %', coalesce(p_session, 'nothing') USING ERRCODE = '23514';
    END IF;
    SELECT array_agg(s.id) INTO v_ids
      FROM people.student s
     WHERE s.status IN ('ACTIVE', 'PROBATION') AND s.duplicate_of IS NULL
       AND people.department_hold_of(s.id, p_session) IS NOT NULL;
    IF v_ids IS NULL THEN RETURN; END IF;
    -- the levels the hold lowered each record by (V696's LEVEL_DEPARTMENT_CHANGE)
    SELECT coalesce(jsonb_object_agg(d.student_id, d.by), '{}') INTO v_up
      FROM (SELECT d.student_id, sum(d.previous_level - d.new_level) AS by
              FROM people.cohort_decision d
             WHERE d.student_id = ANY (v_ids) AND d.rule = 'LEVEL_DEPARTMENT_CHANGE' AND d.previous_level > d.new_level
             GROUP BY d.student_id) d;
    SELECT coalesce(jsonb_object_agg(ap.student_id, ap.spillover_state), '{}') INTO v_spill
      FROM people.academic_position ap WHERE ap.student_id = ANY (v_ids) AND ap.spillover_state IS NOT NULL;
    SELECT coalesce(jsonb_object_agg(c.student_id, c.total), '{}') INTO v_now
      FROM finance.session_charges(p_session) c WHERE c.student_id = ANY (v_ids);
    BEGIN
        PERFORM set_config('moaum.level_hold', 'off', true);
        PERFORM people.defer_positions();
        DELETE FROM people.cohort_override o WHERE o.student_id = ANY (v_ids);
        UPDATE people.student s SET current_level = s.current_level + (v_up->>s.id::text)::int
         WHERE s.id = ANY (v_ids) AND (v_up->>s.id::text) IS NOT NULL;
        PERFORM people.refresh_academic_positions(v_ids);
        SELECT coalesce(jsonb_object_agg(c.student_id, c.total), '{}') INTO v_then
          FROM finance.session_charges(p_session) c WHERE c.student_id = ANY (v_ids);
        RAISE EXCEPTION 'HELD_FEES_UNDONE' USING ERRCODE = 'P0099';
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
        NULL;
    END;
    PERFORM set_config('moaum.level_hold', '', true);
    RETURN QUERY
    SELECT s.id, coalesce(s.matric_no, s.admission_no), upper(s.surname) || ', ' || s.other_names, s.programme_code,
           s.current_level, s.current_level + coalesce((v_up->>s.id::text)::int, 0), v_spill->>s.id::text,
           coalesce((v_now->>s.id::text)::numeric, 0), coalesce((v_then->>s.id::text)::numeric, 0),
           coalesce((v_now->>s.id::text)::numeric, 0) - coalesce((v_then->>s.id::text)::numeric, 0)
      FROM people.student s
     WHERE s.id = ANY (v_ids)
     ORDER BY s.programme_code, s.current_level, s.surname, s.other_names;
END $$;
COMMENT ON FUNCTION finance.department_change_fee_effect(text) IS
  'V702: each student held a level behind after a change of department (V696) — the session''s charges at the level held, and what they would be without the hold (the cohort as entered, the record where it stood); difference = held less unheld. Read only: the hold lifted for the reading is undone.';

-- ── 6. COS 203 unbound from B.Sc. Computer Science ──
DO $$
DECLARE r record; v_outcome text;
BEGIN
    FOR r IN SELECT co.level FROM catalogue.course_offer co WHERE co.course_code = 'COS 203' AND co.programme_code = 'C00023' ORDER BY co.level LOOP
        v_outcome := catalogue.unbind_offer('COS 203', 'C00023', r.level,
            'The University''s word of 29 October 2026: COS 203 Discrete Structures is not in B.Sc. Computer Science''s structure; CSC 203 is (V702)');
        RAISE NOTICE 'V702: COS 203 taken out of B.Sc. Computer Science at % Level (%)', r.level, v_outcome;
    END LOOP;
    IF NOT FOUND THEN
        RAISE NOTICE 'V702: COS 203 is not bound to B.Sc. Computer Science here; nothing to do';
    END IF;
END $$;

-- ── what stands here ──
DO $$
DECLARE v_held int;
BEGIN
    SELECT count(*) INTO v_held FROM people.student s
     WHERE s.status IN ('ACTIVE', 'PROBATION') AND people.department_hold_of(s.id, policy.university_current_session()) IS NOT NULL;
    RAISE NOTICE 'V702: % students held a level behind after a change of department', v_held;
END $$;

COMMIT;
