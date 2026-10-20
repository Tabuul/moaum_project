-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V590 — Course registration open to every level and both curricula (BMAS, CCMAS)
--
--   A student's course list read the programme's structure through the student's cohort: a course bound to the programme at a
--   level for one curriculum track (BMAS, CCMAS_BSU, CCMAS_MOAU) was listed only to the students of that track, a course of one
--   curriculum (catalogue.course.curriculum) only to the students of that curriculum (REG_OTHER_CURRICULUM when added beside the
--   list), and a class was opened for a track's courses only where the programme still had a live student of that track. Where a
--   programme's structure is bound under one track while its students sit in another, whole levels saw few or none of their
--   courses. The University moves on from those restrictions:
--     · registration.flex_policy.curriculum_open (ON from this migration): while it is on, every student sees and registers the
--       programme's courses at their level whatever the binding's track and the course's curriculum; a course added beside the
--       list is judged without the curriculum test; and the classes are opened for every track's courses;
--     · the Academic Office, the Registry and the Directorate of ICT (super too) turn it off again with a reason
--       (registration.set_curriculum_open), on the Registration options screen, should the curricula be kept apart once more;
--     · nothing else changes: the student's stream (CCE, postgraduate), specialisation, the GST/EPS courses already passed, the
--       BSU-/MOAU- code family of the cohort (the same course taught once, registered under one code), carry-overs and deferred
--       courses, the minimum and maximum load (still by the student's curriculum), the fee and GST gates, the approval — and what
--       a student owes for GST/EPS (finance.gst_eps_rows) is not touched.
--   The functions are restated from their current definitions with the switch added.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V590: course registration open to every level and both curricula', true);

-- ── 1 · the switch ──────────────────────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE registration.flex_policy ADD COLUMN curriculum_open boolean NOT NULL DEFAULT true;
COMMENT ON COLUMN registration.flex_policy.curriculum_open IS
  'V590: ON — every student sees and registers the programme''s courses at their level whatever the curriculum track of the binding and the curriculum of the course, and classes open for every track; OFF — the cohort''s track and curriculum only (as before V590)';

CREATE FUNCTION registration.curriculum_open() RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT p.curriculum_open FROM registration.flex_policy p WHERE p.id = 1), true)
$fn$;
COMMENT ON FUNCTION registration.curriculum_open() IS 'V590: whether every curriculum''s courses are open to every student (ON when no rule is stated)';

CREATE FUNCTION registration.set_curriculum_open(p_open boolean, p_reason text)
RETURNS registration.flex_policy LANGUAGE plpgsql AS $fn$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); v registration.flex_policy;
BEGIN
    IF coalesce(v_office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'ict', 'super') THEN
        RAISE EXCEPTION 'REG_FLEX_OFFICE: the rule is set by the Academic Office, the Registry or the Directorate of ICT' USING ERRCODE = '42501';
    END IF;
    IF p_open IS NULL THEN
        RAISE EXCEPTION 'REG_CURRICULUM_OPEN: say whether every curriculum''s courses are open' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'REG_FLEX_REASON: say why the rule changes, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', btrim(p_reason), true);
    INSERT INTO registration.flex_policy (id, curriculum_open, reason, set_by, set_office, set_at)
    VALUES (1, p_open, btrim(p_reason), nullif(current_setting('moaum.actor_id', true), '')::uuid, v_office, now())
    ON CONFLICT (id) DO UPDATE SET curriculum_open = EXCLUDED.curriculum_open, reason = EXCLUDED.reason, set_by = EXCLUDED.set_by,
        set_office = EXCLUDED.set_office, set_at = EXCLUDED.set_at
    RETURNING * INTO v;
    RETURN v;
END $fn$;
COMMENT ON FUNCTION registration.set_curriculum_open(boolean, text) IS
  'V590: every curriculum''s courses opened to every student, or the curricula kept apart again — by the Academic Office, the Registry or the Directorate of ICT, with a reason';

-- ── 2 · the rule read, with its new default ──────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.flex_rule()
 RETURNS registration.flex_policy
 LANGUAGE sql
 STABLE
AS $function$
    SELECT coalesce((SELECT p FROM registration.flex_policy p WHERE p.id = 1),
                    ROW(1, true, 'PROGRAMME', false, 'the default', NULL, NULL, now(), true)::registration.flex_policy)
$function$;

-- ── 3 · the student's list: the programme's courses at the student's level, whatever the binding's track and the course's ──
--       curriculum, while curricula are open (the stream, the specialisation, the GST passed and the BSU-/MOAU- family as before)
CREATE OR REPLACE FUNCTION registration.student_menu(p_student uuid, p_session text, p_semester integer)
 RETURNS TABLE(offering_id uuid, course_code text, title text, units integer, kind text, basis text, owner_dept text, carryover boolean, failed_in text, lecturer text, deferred boolean, deferred_from text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V380: the student's stream: a CCE student is offered the Centre's classes, every other student the full-time ones
    WITH s AS (SELECT st.*, people.student_stream(st.id) AS stream, registration.curriculum_open() AS open_all,   -- V590: every curriculum's courses open   -- V389: and the School's classes for a PG student
                      -- V483: the student's specialisation within their programme (none: the courses for every student only)
                      (SELECT ss.specialisation_id FROM people.student_specialisation ss
                         JOIN catalogue.programme_specialisation ps ON ps.id = ss.specialisation_id AND ps.programme_code = st.programme_code
                        WHERE ss.student_id = st.id) AS specialisation_id
                 FROM people.student st WHERE st.id = p_student),
    -- V366: the GST/EPS courses of the programme at this level the student has already passed
    gst_passed AS (SELECT x.course_code FROM finance.gst_eps_rows(p_session, p_student) x WHERE x.status = 'ALREADY_PASSED'),
    offered AS (
        SELECT o.id AS offering_id, c.code, c.title, coalesce(co.units, c.units) AS units, c.kind, co.basis, c.dept_code   -- V460: the programme's units
          FROM s
          JOIN catalogue.course_offer co ON co.programme_code = s.programme_code AND co.level = s.current_level
                                        AND (s.open_all OR co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
          JOIN catalogue.course c ON c.code = co.course_code AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester AND o.stream = s.stream
         WHERE (s.open_all OR c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)
           AND NOT (c.kind = 'GST' AND c.code IN (SELECT gp.course_code FROM gst_passed gp))
           -- V483: a binding named for specialisations is offered to the students of those specialisations only
           AND (NOT EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x
                             WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code AND x.level = co.level)
                OR EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x
                            WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code AND x.level = co.level
                              AND x.specialisation_id = s.specialisation_id))),
    -- V402: a BSU- code and its MOAU- twin are both on offer; where both reach the student, the student sees their cohort's
    -- family only (cohorts admitted from the stated session register MOAU-, earlier cohorts BSU-); a code with no twin on offer,
    -- or the rule unstated, is shown as before. Carry-overs and deferred courses come by their own code and are untouched.
    eligible AS (
        SELECT e.* FROM offered e
         WHERE NOT (catalogue.other_familys_code(p_student, e.code)
                    AND EXISTS (SELECT 1 FROM offered e2 WHERE e2.code = catalogue.twin_by_code(e.code)))),
    carry AS (
        SELECT o.id AS offering_id, c.code, c.title, catalogue.units_for(c.code, s.programme_code, NULL) AS units, c.kind, 'Carryover'::text AS basis, c.dept_code, cv.failed_in
          FROM registration.carryovers(p_student) cv
          JOIN catalogue.course c ON c.code = cv.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
          CROSS JOIN s
         WHERE o.stream = s.stream AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND (s.open_all OR c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)),
    -- a course set aside by an approved deferment, due since the student returned, offered this semester and not yet passed
    deferred AS (
        SELECT o.id AS offering_id, c.code, c.title, catalogue.units_for(c.code, s.programme_code, NULL) AS units, c.kind, 'Deferred'::text AS basis, c.dept_code,
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
     -- V504: the University's order — carry-overs and deferred courses, then GST, then core, then electives
     ORDER BY registration.entry_rank(NULL, x.kind, x.basis), (x.basis = 'Carryover') DESC, x.code;
$function$;

-- ── 4 · a course added beside the list: no REG_OTHER_CURRICULUM, the binding found whatever its track, while curricula are open ─
CREATE OR REPLACE FUNCTION registration.course_check(p_student uuid, p_session text, p_semester integer, p_code text, p_passed text[], p_awaited text[], p_carry text[], p_other_semester text[])
 RETURNS TABLE(offering_id uuid, category text, added_as text, why text, refusal text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s people.student; p ref.programme; c catalogue.course; o catalogue.offering; pol registration.flex_policy;
        v_stream text; v_spec uuid; b record; v_unmet text[]; v_twin text; v_other_sems text; v_pg boolean;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    SELECT * INTO p FROM ref.programme WHERE code = s.programme_code;
    SELECT * INTO c FROM catalogue.course WHERE code = p_code;
    pol := registration.flex_rule();
    IF c.code IS NULL THEN refusal := 'REG_COURSE_UNKNOWN: there is no course ' || coalesce(p_code, ''); RETURN NEXT; RETURN; END IF;
    v_stream := people.student_stream(p_student);
    SELECT * INTO o FROM catalogue.offering x WHERE x.course_code = c.code AND x.session = p_session AND x.semester = p_semester AND x.stream = v_stream;
    offering_id := o.id;
    SELECT string_agg(CASE x.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END, ' and ' ORDER BY x.semester) INTO v_other_sems
      FROM catalogue.offering x WHERE x.course_code = c.code AND x.session = p_session AND x.stream = v_stream;
    IF c.code = ANY (p_carry) THEN category := 'CARRY_OVER'; END IF;
    IF c.state = 'ENDED' OR c.code LIKE 'DMO %' THEN
        refusal := 'REG_COURSE_INACTIVE: ' || c.code || ' is no longer taught'; RETURN NEXT; RETURN;
    END IF;
    IF registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NOT NULL THEN
        refusal := 'REG_SIWES_SEMESTER: only the SIWES / industrial training course is registered in this semester'; RETURN NEXT; RETURN;
    END IF;
    IF c.code = ANY (p_passed) THEN
        refusal := 'REG_ALREADY_PASSED: Course has already been successfully completed'; RETURN NEXT; RETURN;
    END IF;
    IF c.code = ANY (p_other_semester) THEN
        refusal := 'REG_ALREADY_REGISTERED: ' || c.code || ' is already on your registration for another semester of ' || p_session; RETURN NEXT; RETURN;
    END IF;
    -- registered before with no published result (or one held): not owed and not passed — never read as a failure
    IF c.code = ANY (p_awaited) AND NOT c.code = ANY (p_carry) THEN
        refusal := 'REG_RESULT_AWAITED: Result pending — your earlier registration of ' || c.code || ' has no published result yet, so it is not a carry-over; '
                || 'your department settles the result, or ICT Support adds the course on your ticket';
        RETURN NEXT; RETURN;
    END IF;
    IF NOT pol.curriculum_open AND c.curriculum IS NOT NULL AND s.curriculum_version IS NOT NULL AND c.curriculum <> s.curriculum_version THEN   -- V590
        refusal := 'REG_OTHER_CURRICULUM: ' || c.code || ' belongs to the ' || c.curriculum || ' curriculum, not yours (' || s.curriculum_version || ')'; RETURN NEXT; RETURN;
    END IF;
    IF c.code = ANY (p_carry) THEN
        -- a carry-over is owed at whatever level it was failed; one that runs this semester the menu puts on the registration
        IF o.id IS NULL THEN
            refusal := CASE WHEN v_other_sems IS NOT NULL
                            THEN 'REG_NOT_OFFERED_SEMESTER: Course is not offered in this semester; it runs in the ' || v_other_sems || ' semester of ' || p_session
                            ELSE 'REG_NOT_OFFERED_SESSION: Course is not offered in ' || p_session || ' yet' END;
        ELSE
            why := 'Carry-over: failed earlier and owed';
        END IF;
        RETURN NEXT; RETURN;
    END IF;
    v_pg := s.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE';
    IF NOT v_pg AND c.level >= 700 THEN
        refusal := 'REG_OTHER_CATEGORY: Course is restricted to postgraduate students'; RETURN NEXT; RETURN;
    END IF;
    -- the programme's own binding, at any level, as the menu reads it (track, specialisation)
    SELECT ss.specialisation_id INTO v_spec FROM people.student_specialisation ss
      JOIN catalogue.programme_specialisation ps ON ps.id = ss.specialisation_id AND ps.programme_code = s.programme_code WHERE ss.student_id = s.id;
    SELECT co.level, co.basis INTO b FROM catalogue.course_offer co
     WHERE co.course_code = c.code AND co.programme_code = s.programme_code
       AND (pol.curriculum_open OR co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
       AND (NOT EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code AND x.level = co.level)
            OR EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code
                          AND x.level = co.level AND x.specialisation_id = v_spec))
     ORDER BY (co.level = s.current_level) DESC, abs(co.level - s.current_level), co.level LIMIT 1;
    IF FOUND THEN
        category := CASE WHEN c.kind = 'GST' OR b.basis = 'GST' THEN 'GST' WHEN b.basis = 'Elective' THEN 'ELECTIVE' ELSE 'CORE' END;
        added_as := CASE WHEN b.level = s.current_level THEN NULL ELSE 'PROGRAMME_OTHER_LEVEL' END;
        why := CASE WHEN category = 'ELECTIVE' THEN 'Elective of your programme' WHEN category = 'GST' THEN 'GST/EPS course of your programme'
                    ELSE 'Course of your programme' END || ' (' || b.level || ' Level)';
    ELSIF c.kind = 'GST' AND c.general_office IN ('GST', 'EPS') THEN
        category := 'GST'; added_as := 'UNIVERSITY_' || c.general_office; why := 'University-wide ' || c.general_office || ' course';
    ELSIF pol.other_scope IN ('DEPARTMENT', 'FACULTY') AND c.dept_code = p.dept_code THEN
        category := CASE WHEN c.kind = 'Elective' THEN 'ELECTIVE' ELSE 'CORE' END; added_as := 'DEPARTMENT'; why := 'Course of your department';
    ELSIF pol.other_scope = 'FACULTY' AND (SELECT d.faculty_code FROM ref.department d WHERE d.code = c.dept_code) = p.faculty_code THEN
        category := CASE WHEN c.kind = 'Elective' THEN 'ELECTIVE' ELSE 'CORE' END; added_as := 'FACULTY'; why := 'Course of your faculty';
    ELSE
        refusal := 'REG_NOT_AVAILABLE: This course is not available for registration by your programme/level/session'; RETURN NEXT; RETURN;
    END IF;
    -- a course of a higher level than the student's waits for that level, unless the rule allows it
    IF added_as IS NOT NULL AND coalesce(b.level, c.level) > s.current_level AND NOT pol.allow_higher_levels THEN
        refusal := 'REG_HIGHER_LEVEL: ' || c.code || ' is taken at ' || coalesce(b.level, c.level) || ' Level; you are at ' || s.current_level || ' Level';
        RETURN NEXT; RETURN;
    END IF;
    IF added_as IS NOT NULL AND NOT pol.allow_other_courses THEN
        refusal := 'REG_OTHER_COURSES_OFF: courses beside your recommended list are not open to students now; ask your department'; RETURN NEXT; RETURN;
    END IF;
    IF o.id IS NULL THEN
        refusal := CASE WHEN v_other_sems IS NOT NULL
                        THEN 'REG_NOT_OFFERED_SEMESTER: Course is not offered in this semester; it runs in the ' || v_other_sems || ' semester of ' || p_session
                        ELSE 'REG_NOT_OFFERED_SESSION: Course is not offered in ' || p_session || ' yet' END;
        RETURN NEXT; RETURN;
    END IF;
    -- V402: a BSU- code and its MOAU- twin: the student's cohort registers its own family
    v_twin := catalogue.twin_by_code(c.code);
    IF catalogue.other_familys_code(p_student, c.code) AND v_twin IS NOT NULL
       AND EXISTS (SELECT 1 FROM catalogue.offering x WHERE x.course_code = v_twin AND x.session = p_session AND x.semester = p_semester AND x.stream = v_stream) THEN
        refusal := 'REG_OTHER_CODE_FAMILY: your cohort registers ' || v_twin || ' instead'; RETURN NEXT; RETURN;
    END IF;
    -- V482: where the Academic Office enforces prerequisites, one not passed holds the course
    IF registration.prerequisite_mode() = 'ENFORCED' THEN
        v_unmet := registration.prerequisites_unmet(p_student, c.code);
        IF cardinality(v_unmet) > 0 THEN
            refusal := 'REG_PREREQUISITE: ' || c.code || ' needs ' || array_to_string(v_unmet, ', ') || ' passed first'; RETURN NEXT; RETURN;
        END IF;
    END IF;
    RETURN NEXT;
END $function$;

-- ── 5 · the classes opened for every track's courses while curricula are open (a class must exist to be listed) ───────────
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
       AND (registration.curriculum_open() OR co.track IS NULL   -- V590: every track's courses while curricula are open
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

CREATE OR REPLACE FUNCTION catalogue.open_classes_for_courses(p_codes text[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
    WITH opened AS (
        SELECT DISTINCT o.session, o.semester
          FROM catalogue.offering o
          JOIN policy.academic_session s ON s.name = o.session AND s.state NOT IN ('CLOSED', 'ARCHIVED', 'CANCELLED')
         WHERE o.stream = 'REGULAR'),
    live AS (
        SELECT DISTINCT st.programme_code, st.curriculum_track
          FROM people.student st
         WHERE st.status IN ('ACTIVE', 'PROBATION', 'ADMITTED'))
    INSERT INTO catalogue.offering (id, course_code, session, semester)
    SELECT gen_random_uuid(), c.code, x.session, x.semester
      FROM catalogue.course c
      JOIN opened x ON catalogue.runs_in(c.semester, c.both_semesters, x.semester)
     WHERE c.code = ANY (p_codes) AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
       AND EXISTS (SELECT 1
                     FROM catalogue.course_offer co
                    WHERE co.course_code = c.code
                      AND NOT EXISTS (SELECT 1 FROM ref.programme pp WHERE pp.code = co.programme_code AND pp.category = 'POST GRADUATE')
                      AND (registration.curriculum_open() OR co.track IS NULL OR EXISTS (SELECT 1 FROM live l WHERE l.programme_code = co.programme_code AND l.curriculum_track = co.track)))
       AND NOT EXISTS (SELECT 1 FROM catalogue.offering o
                        WHERE o.course_code = c.code AND o.session = x.session AND o.semester = x.semester AND o.stream = 'REGULAR')
    ON CONFLICT (course_code, session, semester, stream) DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $function$;

CREATE OR REPLACE FUNCTION catalogue.cce_open_classes(p_session text, p_semester integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['cce', 'academic', 'super'], 'opening the Centre''s classes');
    IF p_semester IS NULL OR p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'CCE_CLASS_SEMESTER: a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    PERFORM catalogue.cce_class_session(p_session);
    WITH live AS (SELECT DISTINCT st.programme_code, st.curriculum_track FROM people.student st
                   WHERE st.entry_mode = 'CCE' AND st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
    offered AS (
        SELECT DISTINCT c.code
          FROM catalogue.course c
          JOIN catalogue.course_offer co ON co.course_code = c.code
          JOIN ref.programme_route pr ON pr.programme_code = co.programme_code AND pr.route = 'CCE' AND pr.active
         WHERE catalogue.runs_in(c.semester, c.both_semesters, p_semester) AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'   -- V386
           AND (registration.curriculum_open() OR co.track IS NULL OR EXISTS (SELECT 1 FROM live l WHERE l.programme_code = co.programme_code AND l.curriculum_track = co.track))
        UNION
        SELECT DISTINCT c.code
          FROM people.student st
          CROSS JOIN LATERAL registration.carryovers(st.id) cv
          JOIN catalogue.course c ON c.code = cv.course_code
         WHERE st.entry_mode = 'CCE' AND st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
           AND catalogue.runs_in(c.semester, c.both_semesters, p_semester) AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %')
    INSERT INTO catalogue.offering (id, course_code, session, semester, stream)
    SELECT gen_random_uuid(), o.code, p_session, p_semester, 'CCE' FROM offered o
    ON CONFLICT (course_code, session, semester, stream) DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $function$;

CREATE OR REPLACE FUNCTION catalogue.pg_open_classes(p_session text, p_semester integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
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
                          AND (registration.curriculum_open() OR co.track IS NULL OR l.curriculum_track IS NULL OR l.curriculum_track = co.track))
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
END $function$;

COMMIT;
