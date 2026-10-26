-- ═══════════════════════════════════════
-- V663 — flexible carry-over selection
--
-- The University's master prompt of 26 October 2026 ("FLEXIBLE STUDENT CARRY-OVER COURSE SELECTION & REGISTRATION"): a student sees
-- every earlier course they still owe, at every level below theirs, ticks those to carry over and adds them at once, recorded as
-- carry-overs; never only an SP1 or SP2 student, never held to the minimum when the registration is of carry-overs alone (V597),
-- the course found by its id. Most of it stood: a published F is a carry-over at whatever level (registration.carryovers), placed on
-- the draft where the semester holds its class; a course registered in an earlier session with no result on the portal is a
-- carry-over the student declares (V611); a course with no class yet opens one as it is added (V655). What stood in the way: a course
-- of the programme below the student's level with no record on the portal at all — the history of 2019–2022 is on the old portal — was
-- not owed, so it came as a course of another level and counted against the minimum; and the student found carry-overs one search at
-- a time. With the University's answer — such a course is selectable, as a declared carry-over:
--   · registration.course_context (restated from V611, now with a declare switch) owes, beside the published F and the declared, where the
--     carry-over picker declares (registration.carry_over_candidates; the API's add sets moaum.carry_declare), a course the programme binds
--     below the student's level and not below their entry level, core, required, borrowed or GST/EPS (no elective never chosen), of
--     their track and specialisation, of which the portal holds no registration or result of the student nor of its BSU-/MOAU- twin.
--     It is judged and marked as the declared ones are (registration.course_check: CARRY_OVER, CARRY_OVER_DECLARED); nothing places
--     it on a draft by itself (the menu and the classes opened on the page read registration.carryovers alone). Anywhere else (Add Other
--     Course, saving, approval) such a course is a course of another level, as V504 reads it; once added as a carry-over it stays one.
--   · registration.carry_over_candidates(student, session, semester): every earlier course of the student with what it is now
--     (OUTSTANDING, NO_RESULT, NO_RECORD, AWAITED, CLEARED, ALREADY_REGISTERED, NOT_OWED), its level and semester, the session it was
--     last registered in and the last grade, selectable only where the engine allows it as a carry-over, the reason in words.
--   · reporting.course_registration_rows (restated from V652) reads a type — CURRENT or CARRY_OVER — beside the category, so the
--     report reads CARRY-OVER + GST.
-- The API adds the ticked courses one by one through the engine (each its own transaction, each answered), by course id.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V663: flexible carry-over selection', true);

-- ── 1 · what a student owes: the declared include a course of the programme with no record on the portal ─────────────────────
CREATE FUNCTION registration.course_context(p_student uuid, p_session text, p_semester integer, p_declare boolean)
RETURNS TABLE (passed text[], awaited text[], carry text[], other_semester text[])
LANGUAGE sql STABLE AS $$
    WITH r AS MATERIALIZED (SELECT * FROM assessment.student_results(p_student)),
    -- registered before, with no published result yet (or one held): not owed, not passed — never read as a failure
    pending AS MATERIALIZED (
        SELECT x.* FROM r x
         WHERE (x.session, x.semester) < (p_session, p_semester)
           AND (NOT x.published OR x.outcome IS NULL OR x.outcome NOT IN ('GRADED', 'ABSENT'))
           AND NOT EXISTS (SELECT 1 FROM r y WHERE y.course_code = x.course_code AND y.published AND y.outcome IN ('GRADED', 'ABSENT')
                             AND (y.session, y.semester) >= (x.session, x.semester))),
    -- V611: of those, a course every pending registration of which is of an earlier session and holds no result of the student on the
    -- portal — no score sheet of it, or a published sheet without them (its result is on the old portal) — and not passed: a carry-over
    -- the student may declare. A sheet not yet published, a result held, a registration earlier this session: the result is awaited
    declared AS MATERIALIZED (
        SELECT DISTINCT x.course_code FROM pending x
         WHERE NOT EXISTS (SELECT 1 FROM pending z WHERE z.course_code = x.course_code
                              AND (z.stage NOT IN ('NO_SHEET', 'NO_RESULT') OR z.session >= p_session))
           AND NOT EXISTS (SELECT 1 FROM r y WHERE y.course_code = x.course_code AND y.published AND y.outcome = 'GRADED' AND y.points > 0)),
    -- V663: no record — a course the student's programme binds below the level they are at (and not below the level they entered at:
    -- a direct-entry student owes nothing beneath it), core, required, borrowed or GST/EPS (never an elective they did not choose), of
    -- the student's track and specialisation, of which the portal holds no registration and no result of the student, nor of its
    -- BSU-/MOAU- twin: its record is on the old portal, and a carry-over the student may declare (the University's word of 26 October 2026)
    unrecorded AS MATERIALIZED (
        SELECT DISTINCT co.course_code
          FROM people.student s
          CROSS JOIN registration.flex_rule() pol
          JOIN catalogue.course_offer co ON co.programme_code = s.programme_code AND co.level < s.current_level
                                         AND co.level >= coalesce(s.entry_level, 100)
                                         AND coalesce(co.basis, 'Core') NOT IN ('Elective', 'Deficiency', 'Research')
          JOIN catalogue.course c ON c.code = co.course_code AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
         WHERE p_declare AND s.id = p_student
           AND (pol.curriculum_open OR co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
           AND (NOT EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code AND x.level = co.level)
                OR EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x JOIN people.student_specialisation ss ON ss.specialisation_id = x.specialisation_id AND ss.student_id = s.id
                            WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code AND x.level = co.level))
           AND NOT EXISTS (SELECT 1 FROM r x WHERE x.course_code = co.course_code)
           AND NOT EXISTS (SELECT 1 FROM catalogue.course_twin t JOIN r x ON x.course_code IN (t.bsu_code, t.moau_code)
                            WHERE t.unlinked_at IS NULL AND co.course_code IN (t.bsu_code, t.moau_code)))
    SELECT coalesce((SELECT array_agg(DISTINCT x.course_code) FROM r x WHERE x.published AND x.outcome = 'GRADED' AND x.points > 0), '{}'::text[]),
           coalesce((SELECT array_agg(DISTINCT x.course_code) FROM pending x WHERE x.course_code NOT IN (SELECT d.course_code FROM declared d)), '{}'::text[]),
           coalesce((SELECT array_agg(DISTINCT k.course_code)
                       FROM (SELECT cv.course_code FROM registration.carryovers(p_student) cv UNION SELECT d.course_code FROM declared d
                             UNION SELECT u.course_code FROM unrecorded u) k), '{}'::text[]),
           coalesce((SELECT array_agg(DISTINCT o.course_code)
                       FROM registration.course_registration cr
                       JOIN registration.entry e ON e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                       JOIN catalogue.offering o ON o.id = e.offering_id
                      WHERE cr.student_id = p_student AND cr.session = p_session AND cr.semester <> p_semester), '{}'::text[])
$$;
COMMENT ON FUNCTION registration.course_context(uuid, text, integer, boolean) IS
  'V504, V611, V663: what a course check reads of the student once: the courses passed, awaited, owed (registration.carryovers, the carry-overs the student may declare: registered in an earlier session with no result of the student on the portal; and, where p_declare, a course the programme binds below the student''s level, core or GST/EPS, with no record of the student on the portal), and registered in another semester of the session';

-- the reading every engine function makes: owed with no record only where the carry-over picker declares (moaum.carry_declare on, set by the
-- API in the transaction that adds the ticked carry-overs); elsewhere a course of another level the student never took is a course of
-- another level, as V504 reads it
CREATE OR REPLACE FUNCTION registration.course_context(p_student uuid, p_session text, p_semester integer)
RETURNS TABLE (passed text[], awaited text[], carry text[], other_semester text[])
LANGUAGE sql STABLE AS $$
    SELECT * FROM registration.course_context(p_student, p_session, p_semester, coalesce(current_setting('moaum.carry_declare', true), '') = 'on')
$$;
COMMENT ON FUNCTION registration.course_context(uuid, text, integer) IS
  'V504, V611, V663: registration.course_context(student, session, semester, declare) with declare read from moaum.carry_declare (on only in the carry-over picker''s add): the courses passed, awaited, owed, and registered in another semester of the session';

-- the course check (restated from V655) says which a declared carry-over is: one registered here with no result, or one with no record
CREATE OR REPLACE FUNCTION registration.course_check(p_student uuid, p_session text, p_semester integer, p_code text, p_passed text[], p_awaited text[], p_carry text[], p_other_semester text[])
 RETURNS TABLE(offering_id uuid, category text, added_as text, why text, refusal text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s people.student; p ref.programme; c catalogue.course; o catalogue.offering; pol registration.flex_policy;
        v_stream text; v_spec uuid; b record; v_unmet text[]; v_twin text; v_pg boolean;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    SELECT * INTO p FROM ref.programme WHERE code = s.programme_code;
    SELECT * INTO c FROM catalogue.course WHERE code = p_code;
    pol := registration.flex_rule();
    IF c.code IS NULL THEN refusal := 'REG_COURSE_UNKNOWN: there is no course ' || coalesce(p_code, ''); RETURN NEXT; RETURN; END IF;
    v_stream := people.student_stream(p_student);
    SELECT * INTO o FROM catalogue.offering x WHERE x.course_code = c.code AND x.session = p_session AND x.semester = p_semester AND x.stream = v_stream;
    offering_id := o.id;
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
    -- registered before with no published result (or one held): not owed and not passed — never read as a failure.
    -- V611: one whose result is on its way here (a score sheet of it on the portal, or registered earlier this session); one registered in
    -- an earlier session with no score sheet here comes as a carry-over the student may declare (registration.course_context)
    IF c.code = ANY (p_awaited) AND NOT c.code = ANY (p_carry) THEN
        refusal := 'REG_RESULT_AWAITED: Result pending — your earlier registration of ' || c.code || ' has no published result yet, so it is not a carry-over; '
                || 'your department publishes the result, or ICT Support adds the course on your ticket';
        RETURN NEXT; RETURN;
    END IF;
    IF NOT pol.curriculum_open AND c.curriculum IS NOT NULL AND s.curriculum_version IS NOT NULL AND c.curriculum <> s.curriculum_version THEN   -- V590
        refusal := 'REG_OTHER_CURRICULUM: ' || c.code || ' belongs to the ' || c.curriculum || ' curriculum, not yours (' || s.curriculum_version || ')'; RETURN NEXT; RETURN;
    END IF;
    IF c.code = ANY (p_carry) THEN
        -- a carry-over is owed at whatever level it was failed; one that runs this semester the menu puts on the registration
        -- V611: one the student declares — registered in an earlier session, and the portal holds no score sheet of it (its result is
        -- on the old portal) — is marked so; a carry-over with a published F is the results' own
        IF NOT EXISTS (SELECT 1 FROM registration.course_registration cr
                         JOIN registration.entry e ON e.registration_id = cr.id AND e.status IN ('REGISTERED', 'APPROVED')
                         JOIN catalogue.offering ox ON ox.id = e.offering_id AND ox.course_code = c.code
                         CROSS JOIN LATERAL assessment.course_final(p_student, ox.id) cf
                        WHERE cr.student_id = p_student AND cr.status IN ('APPROVED', 'LOCKED')
                          AND cf.stage = 'PUBLISHED' AND cf.outcome IN ('GRADED', 'ABSENT') AND coalesce(cf.points, 0) = 0) THEN
            added_as := 'CARRY_OVER_DECLARED';
        END IF;
        -- V655: a carry-over with no class yet is registered all the same: its class opens when the student adds it
        IF o.id IS NULL AND registration.no_class_refusal(c.semester, c.both_semesters, p_session, p_semester) IS NOT NULL THEN
            refusal := registration.no_class_refusal(c.semester, c.both_semesters, p_session, p_semester);
        ELSIF added_as = 'CARRY_OVER_DECLARED' AND NOT EXISTS (SELECT 1 FROM registration.course_registration cr
                                                                 JOIN registration.entry e ON e.registration_id = cr.id
                                                                 JOIN catalogue.offering ox ON ox.id = e.offering_id AND ox.course_code = c.code
                                                                WHERE cr.student_id = p_student) THEN
            -- V663: a course of the programme below the student's level the portal holds no record of them taking
            why := 'Carry-over you declare: the portal holds no record of your taking ' || c.code;
        ELSIF added_as = 'CARRY_OVER_DECLARED' THEN
            why := 'Carry-over you declare: the portal holds no result of your earlier registration of ' || c.code;
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
    -- V655: a course is never tied to a session: with no class in the session yet, it is refused only when it is not taught in this
    -- semester or the session holds no classes; otherwise its class opens when the student adds it (registration.class_to_add)
    IF o.id IS NULL THEN
        refusal := registration.no_class_refusal(c.semester, c.both_semesters, p_session, p_semester);
        IF refusal IS NOT NULL THEN RETURN NEXT; RETURN; END IF;
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
COMMENT ON FUNCTION registration.course_check(uuid, text, integer, text, text[], text[], text[], text[]) IS
  'V504, V590, V611, V655, V663: whether a student may register a course in a session''s semester, the category it is registered in, what it is added as and why, or the refusal; V663: a declared carry-over is said to be one registered here with no result, or one of the programme with no record of the student taking it.';

-- ── 2 · every earlier course of the student, with what it is now ─────────────────────────────────────────────────────────────
CREATE FUNCTION registration.carry_over_candidates(p_student uuid, p_session text, p_semester integer)
RETURNS TABLE (course_id uuid, course_code text, shown_code text, title text, units integer, level integer, course_semester integer,
               both_semesters boolean, course_group text, status text, origin_session text, origin_semester integer, last_grade text,
               offering_id uuid, selectable boolean, reason text)
LANGUAGE plpgsql STABLE AS $$
DECLARE s people.student; ctx record; v_failed text[];
BEGIN
    SELECT * INTO s FROM people.student x WHERE x.id = p_student;
    IF NOT FOUND THEN RETURN; END IF;
    SELECT * INTO ctx FROM registration.course_context(p_student, p_session, p_semester, true);   -- the picker owes the no-record ones too
    v_failed := ARRAY(SELECT cv.course_code FROM registration.carryovers(p_student) cv);
    RETURN QUERY
    WITH r AS MATERIALIZED (SELECT * FROM assessment.student_results(p_student)),
    mine AS (SELECT DISTINCT o.course_code
               FROM registration.course_registration cr
               JOIN registration.entry e ON e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
               JOIN catalogue.offering o ON o.id = e.offering_id
              WHERE cr.student_id = p_student AND cr.session = p_session AND cr.semester = p_semester),
    -- the programme's courses below the student's level (and not below the level they entered at)
    bound AS (SELECT DISTINCT ON (co.course_code) co.course_code, co.level
                FROM catalogue.course_offer co
               WHERE co.programme_code = s.programme_code AND co.level < s.current_level AND co.level >= coalesce(s.entry_level, 100)
               ORDER BY co.course_code, co.level),
    codes AS (SELECT x.course_code FROM r x WHERE (x.session, x.semester) < (p_session, p_semester)
              UNION SELECT b.course_code FROM bound b
              UNION SELECT unnest(ctx.carry)),
    -- the latest earlier registration of each, and its latest published grade
    last AS (SELECT DISTINCT ON (x.course_code) x.course_code, x.session, x.semester
               FROM r x WHERE (x.session, x.semester) < (p_session, p_semester)
              ORDER BY x.course_code, x.session DESC, x.semester DESC),
    graded AS (SELECT DISTINCT ON (x.course_code) x.course_code, x.grade
                 FROM r x WHERE x.published AND x.grade IS NOT NULL
                ORDER BY x.course_code, x.session DESC, x.semester DESC),
    judged AS (SELECT k.course_code, ch.offering_id, ch.category, ch.refusal
                 FROM codes k
                 CROSS JOIN LATERAL registration.course_check(p_student, p_session, p_semester, k.course_code,
                                                              ctx.passed, ctx.awaited, ctx.carry, ctx.other_semester) ch),
    shaped AS (
        SELECT c.id AS cid, c.code, c.title AS ctitle, coalesce(catalogue.units_for(c.code, s.programme_code, b.level), c.units) AS cunits,
               coalesce(b.level, c.level) AS clevel, c.semester AS csem, coalesce(c.both_semesters, false) AS cboth,
               CASE WHEN c.kind = 'GST' AND c.general_office = 'EPS' THEN 'EPS' WHEN c.kind = 'GST' THEN 'GST' ELSE 'OTHER' END AS cgroup,
               CASE WHEN c.code = ANY (ctx.passed) THEN 'CLEARED'
                    WHEN c.code IN (SELECT m.course_code FROM mine m) OR c.code = ANY (ctx.other_semester) THEN 'ALREADY_REGISTERED'
                    WHEN c.code = ANY (v_failed) THEN 'OUTSTANDING'
                    WHEN c.code = ANY (ctx.carry) AND EXISTS (SELECT 1 FROM r x WHERE x.course_code = c.code) THEN 'NO_RESULT'
                    WHEN c.code = ANY (ctx.carry) THEN 'NO_RECORD'
                    WHEN c.code = ANY (ctx.awaited) THEN 'AWAITED'
                    ELSE 'NOT_OWED' END AS cstatus,
               l.session AS osession, l.semester AS osemester, g.grade AS ograde, j.offering_id AS coffering, j.category AS ccategory, j.refusal AS crefusal
          FROM judged j
          JOIN catalogue.course c ON c.code = j.course_code
          LEFT JOIN bound b ON b.course_code = c.code
          LEFT JOIN last l ON l.course_code = c.code
          LEFT JOIN graded g ON g.course_code = c.code
         -- the other BSU-/MOAU- family's code of a course is never the student's: its twin is listed instead
         WHERE coalesce(j.refusal, '') NOT LIKE 'REG_OTHER_CODE_FAMILY%')
    SELECT x.cid, x.code, catalogue.shown_code(x.code), x.ctitle, x.cunits, x.clevel, x.csem, x.cboth, x.cgroup, x.cstatus,
           x.osession, x.osemester, x.ograde, x.coffering,
           x.cstatus IN ('OUTSTANDING', 'NO_RESULT', 'NO_RECORD') AND x.crefusal IS NULL AND x.ccategory = 'CARRY_OVER',
           CASE WHEN x.cstatus = 'CLEARED' THEN 'Cleared: passed on a published result'
                WHEN x.cstatus = 'ALREADY_REGISTERED' THEN 'Already registered in ' || p_session
                WHEN x.crefusal IS NOT NULL THEN regexp_replace(x.crefusal, '^[A-Z_]+: ', '')
                WHEN x.cstatus = 'OUTSTANDING' THEN 'Failed on a published result' || coalesce(' (' || x.osession || ')', '')
                WHEN x.cstatus = 'NO_RESULT' THEN 'Registered in ' || coalesce(x.osession, 'an earlier session') || '; no result on this portal'
                WHEN x.cstatus = 'NO_RECORD' THEN 'No record on this portal; add it only if you did not pass it'
                WHEN x.cstatus = 'AWAITED' THEN 'Result pending: your department publishes it'
                ELSE 'Not a carry-over of yours' END
      FROM shaped x
     WHERE (x.clevel < s.current_level OR x.cstatus IN ('OUTSTANDING', 'NO_RESULT', 'AWAITED'))
       -- a course the student never took and does not owe (an elective not chosen) is not theirs to see here
       AND NOT (x.cstatus = 'NOT_OWED' AND x.osession IS NULL)
     ORDER BY x.clevel, x.csem, x.code;
END $$;
COMMENT ON FUNCTION registration.carry_over_candidates(uuid, text, integer) IS
  'V663: every earlier course of the student for the carry-over picker — those registered before, those their programme binds below their level, and those owed — each with what it is now: OUTSTANDING (a published F not since passed), NO_RESULT (registered in an earlier session, no result on the portal), NO_RECORD (bound below the level, no record on the portal), AWAITED, CLEARED, ALREADY_REGISTERED or NOT_OWED; judged by registration.course_check, selectable only as a carry-over it allows, with the reason in words. The other code family''s twin is left out.';

-- ── 3 · the course registration report: CURRENT or CARRY_OVER beside the category ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION reporting.course_registration_rows(p_session text, p_semester int, p_f jsonb)
RETURNS TABLE (
    student_id uuid, matric_no text, jamb_no text, full_name text, sex text,
    faculty_code text, faculty text, dept_code text, department text, programme_code text, programme text, programme_category text,
    admission_route text, study_mode text, centre_code text, level int, session text, semester int,
    registration_id uuid, registration_status text, submitted_at timestamptz, approved_at timestamptz,
    offering_id uuid, course_code text, shown_code text, course_title text, units int, category text, course_kind text, curriculum text,
    course_dept text, entry_type text, entry_status text, carry_over boolean, added_as text,
    holds_card boolean, holds_permit boolean, eligible boolean)
LANGUAGE sql STABLE SET jit = off AS $$
    WITH f AS (SELECT nullif(btrim(p_f->>'fac'), '') AS fac, nullif(btrim(p_f->>'dept'), '') AS dept, nullif(btrim(p_f->>'prog'), '') AS prog,
                      (nullif(btrim(p_f->>'level'), ''))::int AS lvl, nullif(btrim(p_f->>'course'), '') AS course,
                      (nullif(btrim(p_f->>'offering'), ''))::uuid AS offering, upper(nullif(btrim(p_f->>'category'), '')) AS category,
                      upper(nullif(btrim(p_f->>'office'), '')) AS office, upper(nullif(btrim(p_f->>'curriculum'), '')) AS curriculum,
                      upper(nullif(btrim(p_f->>'sex'), '')) AS sex, upper(nullif(btrim(p_f->>'reg'), '')) AS reg,
                      upper(nullif(btrim(p_f->>'eligible'), '')) AS eligible, (nullif(btrim(p_f->>'from'), ''))::date AS d_from,
                      (nullif(btrim(p_f->>'to'), ''))::date AS d_to, nullif(btrim(p_f->>'q'), '') AS q,
                      coalesce((p_f->>'dropped')::boolean, false) AS with_dropped,
                      upper(nullif(btrim(p_f->>'type'), '')) AS reg_type),   -- V663: CURRENT or CARRY_OVER, beside the category
    x AS (
        SELECT s.id AS student_id, s.matric_no, coalesce(s.jamb_reg_no, (SELECT c2.jamb_reg_no FROM admissions.candidate c2 WHERE c2.id = s.candidate_id)) AS jamb_no,
               upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS full_name, upper(left(coalesce(s.sex, ''), 1)) AS sex,
               d.faculty_code, fa.name AS faculty, p.dept_code, d.name AS department, p.code AS programme_code, p.name AS programme, p.category AS programme_category,
               s.entry_mode AS admission_route, s.study_mode, s.centre_code, r.level, r.session, r.semester,
               r.id AS registration_id, r.status AS registration_status, r.submitted_at, r.approved_at,
               o.id AS offering_id, c.code AS course_code, catalogue.shown_code(c.code) AS shown_code, c.title AS course_title, e.units,
               CASE WHEN c.kind = 'GST' AND c.general_office = 'GST' THEN 'GST'
                    WHEN c.kind = 'GST' AND c.general_office = 'EPS' THEN 'EPS'
                    WHEN c.dept_code = p.dept_code THEN 'DEPARTMENTAL'
                    WHEN cd.faculty_code = d.faculty_code THEN 'FACULTY'
                    ELSE 'OTHER' END AS category,
               c.kind AS course_kind, c.curriculum, c.dept_code AS course_dept, e.entry_type, e.status AS entry_status,
               e.entry_type = 'CARRYOVER' AS carry_over, e.added_as,
               EXISTS (SELECT 1 FROM registration.exam_card_issue ci WHERE ci.student_id = s.id AND ci.session = r.session AND ci.semester = r.semester) AS holds_card,
               EXISTS (SELECT 1 FROM registration.gst_eps_permit pm WHERE pm.student_id = s.id AND pm.session = r.session AND pm.semester = r.semester
                          AND pm.revoked_at IS NULL) AS holds_permit
          FROM f
          JOIN registration.course_registration r ON r.session = p_session AND (p_semester IS NULL OR r.semester = p_semester)
          JOIN registration.entry e ON e.registration_id = r.id
          JOIN catalogue.offering o ON o.id = e.offering_id
          JOIN catalogue.course c ON c.code = o.course_code
          JOIN people.student s ON s.id = r.student_id
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN ref.department d ON d.code = p.dept_code
          LEFT JOIN ref.faculty fa ON fa.code = d.faculty_code
          LEFT JOIN ref.department cd ON cd.code = c.dept_code
         WHERE (f.with_dropped OR e.status NOT IN ('DROPPED', 'WITHDRAWN'))
           AND (f.fac IS NULL OR d.faculty_code = f.fac) AND (f.dept IS NULL OR p.dept_code = f.dept) AND (f.prog IS NULL OR p.code = f.prog)
           AND (f.lvl IS NULL OR r.level = f.lvl)
           AND (f.offering IS NULL OR o.id = f.offering)
           AND (f.course IS NULL OR c.code = upper(f.course) OR catalogue.shown_code(c.code) = upper(f.course))
           AND (f.office IS NULL OR (c.kind = 'GST' AND c.general_office = f.office))
           AND (f.curriculum IS NULL OR c.curriculum = f.curriculum)
           AND (f.reg IS NULL OR r.status = f.reg)
           AND (f.d_from IS NULL OR coalesce(r.submitted_at, r.approved_at)::date >= f.d_from)
           AND (f.d_to IS NULL OR coalesce(r.submitted_at, r.approved_at)::date <= f.d_to))
    SELECT x.*, CASE WHEN x.category IN ('GST', 'EPS') THEN x.holds_permit ELSE x.holds_card END AS eligible
      FROM x CROSS JOIN f
     WHERE (f.category IS NULL OR CASE f.category
                WHEN 'CARRY_OVER' THEN x.carry_over
                WHEN 'OTHER_COURSES' THEN x.category NOT IN ('GST', 'EPS')
                ELSE x.category = f.category END)
       AND (f.sex IS NULL OR CASE f.sex WHEN 'U' THEN x.sex NOT IN ('M', 'F') ELSE x.sex = f.sex END)
       AND (f.reg_type IS NULL OR (f.reg_type = 'CARRY_OVER') = x.carry_over)
       AND (f.eligible IS NULL OR (f.eligible = 'YES') = CASE WHEN x.category IN ('GST', 'EPS') THEN x.holds_permit ELSE x.holds_card END)
       AND (f.q IS NULL OR x.full_name ILIKE '%' || f.q || '%' OR coalesce(x.matric_no, '') ILIKE '%' || f.q || '%'
            OR coalesce(x.jamb_no, '') ILIKE '%' || f.q || '%' OR x.course_code ILIKE '%' || f.q || '%' OR x.course_title ILIKE '%' || f.q || '%')
$$;
COMMENT ON FUNCTION reporting.course_registration_rows(text, int, jsonb) IS
  'V652, V663: the course registration report — one row a student and course registered in the session (and semester), the dropped and withdrawn left out unless asked for: the student, faculty, department, programme, level, the registration and its status, the course by its own key with the code shown, units, category (GST, EPS, DEPARTMENTAL, FACULTY, OTHER), curriculum, carry-over, and whether the examination card or the GST & EPS permit is held. Filters: fac, dept, prog, level, course, offering, category (also CARRY_OVER, OTHER_COURSES), type (CURRENT or CARRY_OVER, V663), office (GST or EPS), curriculum, sex, reg, eligible, from, to, q, dropped.';

COMMIT;
