-- V655: every course registrable, whatever its class — the word of 25 October 2026 ("all this courses to be available for
-- registration, whether CCMAS or BMAS, enable all the courses"), on the Add Other Course list where HIS 402 History Research Project
-- I & II read "Not offered this session" beside HIS 402 Economic History of Nigeria in the 20th Century.
--
-- A course is never tied to a session; a session holds the course's class (catalogue.offering), opened when registration opens
-- (registration.open_course_registration, for the courses some programme binds then), on a course upload or when a course goes live.
-- A course created, bound or separated under a shared code after that had no class, and registration.course_check refused it:
-- REG_NOT_OFFERED_SESSION ("Course is not offered in 2025/2026 yet") — the student could not register it at all, CCMAS or BMAS.
-- Now:
--   · registration.no_class_refusal says when a course with no class in the session is refused: only when it is not taught in the
--     semester (REG_NOT_OFFERED_SEMESTER, named by the course's own semester: "it runs in the first semester") or the session holds
--     no classes (cancelled or merged: REG_NOT_OFFERED_SESSION); otherwise nothing.
--   · registration.course_check (restated from V611) reads it: a course, a carry-over too, with no class yet passes every other rule
--     as before (programme, level, curriculum while curricula are open, passed, awaited, prerequisites, the BSU-/MOAU- family) and is
--     answered with no class (offering_id NULL) and no refusal.
--   · registration.course_search (restated from V507) lists the programme's courses at every level and the student's carry-overs
--     whether a class is open or not, those taught in the semester first; the University GST/EPS courses and the department's or
--     faculty's still with a class in the session, so they do not crowd the programme's own off the first page.
--   · registration.class_to_add(student, session, semester, course): the class a student adds a course by — the course judged by
--     registration.course_check, refused with its reason, else the session's class of it for the student's stream, opened now when
--     there is none (catalogue.open_class); the add itself (registration.student_add_other, or registration.student_add in add and
--     drop) judges it again with every other rule, in the same transaction, so a refused add leaves no class behind.
--   · registration.open_student_classes(student, session, semester): read as the student opens their registration (never in ICT
--     Support's read-only view of it), it opens the classes of the student's level's courses and carry-overs taught in the semester
--     that the session has none of yet — the pool of courses, registered level by level as students progress: the recommended list
--     holds every course of the level whenever the course was uploaded or bound.
-- Kept: the recommended list (registration.student_menu) reads the classes as before; the GST fee, the unit ceiling, the add and
-- drop window and the Registration options (other courses, how wide, higher levels, curricula) are unchanged.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V655: every course registrable, its class opened when a student adds it', true);

-- ── 1 · when a course with no class in the session is refused ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.no_class_refusal(p_course_semester integer, p_both boolean, p_session text, p_semester integer)
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT CASE
        WHEN NOT catalogue.runs_in(p_course_semester, p_both, p_semester)
            THEN 'REG_NOT_OFFERED_SEMESTER: Course is not offered in this semester; it runs in the '
                 || CASE WHEN p_both THEN 'first and second' WHEN p_course_semester = 1 THEN 'first' WHEN p_course_semester = 2 THEN 'second' ELSE 'third' END
                 || ' semester'
        WHEN NOT EXISTS (SELECT 1 FROM policy.academic_session s WHERE s.name = p_session AND s.state <> 'CANCELLED' AND s.merged_into IS NULL)
            THEN 'REG_NOT_OFFERED_SESSION: Course is not offered in ' || coalesce(p_session, 'this session') || '; the session holds no classes'
    END
$$;
COMMENT ON FUNCTION registration.no_class_refusal(integer, boolean, text, integer) IS
  'V655: why a course with no class in the session cannot be registered — not taught in the semester, or the session cancelled or merged — else NULL: its class opens when a student adds it.';

-- ── 2 · the judge: no class yet is not a refusal (restated from V611) ────────────────────────────────────────────────────────
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
  'V504, V590, V611, V655: whether a student may register a course in a session''s semester, and as what — the one judge of the menu, the search and every add path. A course with no class in the session yet is answered with no class and no refusal unless registration.no_class_refusal refuses it; registration.class_to_add opens the class when the student adds it.';

-- ── 3 · the search: the student's own courses, a class open or not (restated from V507) ───────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.course_search(p_student uuid, p_session text, p_semester integer, p_q text, p_level integer, p_dept text, p_faculty text, p_category text, p_limit integer, p_offset integer)
 RETURNS TABLE(offering_id uuid, course_code text, title text, units integer, kind text, level integer, course_semester integer, dept_code text, department text, faculty_code text, category text, added_as text, why text, refusal text, on_registration boolean, recommended boolean, total bigint)
 LANGUAGE sql
 STABLE
AS $function$
    WITH st AS (SELECT s.*, p.dept_code AS prog_dept, p.faculty_code AS prog_faculty, people.student_stream(s.id) AS stream
                  FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = p_student),
    pol AS (SELECT * FROM registration.flex_rule()),
    ctx AS MATERIALIZED (SELECT * FROM registration.course_context(p_student, p_session, p_semester)),
    mine AS (SELECT o.course_code FROM registration.course_registration r
               JOIN registration.entry e ON e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
               JOIN catalogue.offering o ON o.id = e.offering_id
              WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester),
    menu AS MATERIALIZED (SELECT m.offering_id FROM registration.student_menu(p_student, p_session, p_semester) m),
    q AS (SELECT nullif(btrim(coalesce(p_q, '')), '') AS term),
    -- a typed code or title, or a department or faculty, searches every course
    found AS (
        SELECT c.code, c.title, c.units, c.kind, c.level, c.semester, c.dept_code, d.name AS department, d.faculty_code,
               (upper(c.code) = upper(coalesce(q.term, ''))) AS exact, false AS this_semester
          FROM catalogue.course c LEFT JOIN ref.department d ON d.code = c.dept_code CROSS JOIN q
         WHERE (q.term IS NOT NULL OR p_dept IS NOT NULL OR p_faculty IS NOT NULL)
           AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
           AND (q.term IS NULL OR c.code ILIKE '%' || q.term || '%' OR replace(c.code, ' ', '') ILIKE '%' || replace(q.term, ' ', '') || '%'
                OR c.title ILIKE '%' || q.term || '%')
           AND (p_level IS NULL OR c.level = p_level) AND (p_dept IS NULL OR c.dept_code = p_dept) AND (p_faculty IS NULL OR d.faculty_code = p_faculty)),
    -- otherwise the courses that concern the student: the programme's at every level and the carry-overs, a class in the session or
    -- not (V655: its class opens when it is added); the University GST/EPS courses and the department's or faculty's where the rule
    -- allows them, with a class in the session
    own AS (
        SELECT c.code, c.title, c.units, c.kind, c.level, c.semester, c.dept_code, d.name AS department, d.faculty_code, false AS exact,
               catalogue.runs_in(c.semester, c.both_semesters, p_semester) AS this_semester
          FROM catalogue.course c LEFT JOIN ref.department d ON d.code = c.dept_code CROSS JOIN q CROSS JOIN st CROSS JOIN pol CROSS JOIN ctx
         WHERE q.term IS NULL AND p_dept IS NULL AND p_faculty IS NULL
           AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
           AND (p_level IS NULL OR c.level = p_level)
           AND (c.code = ANY (ctx.carry)
                -- V655: the programme's own courses (the pool, every level) whether or not the session has a class of them yet
                OR EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code AND co.programme_code = st.programme_code)
                -- the University's GST/EPS courses and the department's or faculty's: those with a class in the session, as before
                OR (EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.course_code = c.code AND o.session = p_session AND o.stream = st.stream)
                    AND ((c.kind = 'GST' AND c.general_office IN ('GST', 'EPS'))
                         OR (pol.other_scope IN ('DEPARTMENT', 'FACULTY') AND c.dept_code = st.prog_dept)
                         OR (pol.other_scope = 'FACULTY' AND d.faculty_code = st.prog_faculty))))
           -- the category chosen, read cheaply before the engine judges (it says the category again, and the list is filtered by its word)
           AND (p_category IS NULL
                OR (p_category = 'CARRY_OVER' AND c.code = ANY (ctx.carry))
                OR (p_category = 'GST' AND (c.kind = 'GST' OR EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code
                                                                          AND co.programme_code = st.programme_code AND co.basis = 'GST')))
                OR (p_category IN ('CORE', 'ELECTIVE') AND c.kind <> 'GST' AND NOT c.code = ANY (ctx.carry)))),
    cand AS MATERIALIZED (
        SELECT * FROM (SELECT * FROM found UNION ALL SELECT * FROM own) x
         ORDER BY x.exact DESC, x.this_semester DESC, x.level, x.code LIMIT 300),
    judged AS (
        SELECT c.*, x.offering_id, x.category, x.added_as, x.why, x.refusal
          FROM cand c CROSS JOIN ctx
          CROSS JOIN LATERAL registration.course_check(p_student, p_session, p_semester, c.code, ctx.passed, ctx.awaited, ctx.carry, ctx.other_semester) x)
    SELECT j.offering_id, j.code, j.title, catalogue.units_for(j.code, st.programme_code, NULL), j.kind, j.level, j.semester, j.dept_code, j.department, j.faculty_code,
           j.category, j.added_as, j.why, j.refusal, j.code IN (SELECT m.course_code FROM mine m), j.offering_id IN (SELECT mm.offering_id FROM menu mm), count(*) OVER ()
      FROM judged j CROSS JOIN st
     WHERE p_category IS NULL OR j.category = p_category
     ORDER BY (j.refusal IS NULL) DESC, registration.category_rank(j.category), j.level, j.code
     LIMIT greatest(1, least(coalesce(p_limit, 30), 100)) OFFSET greatest(0, coalesce(p_offset, 0))
$function$;
COMMENT ON FUNCTION registration.course_search(uuid, text, integer, text, integer, text, text, text, integer, integer) IS
  'V504/V507/V655: the student''s Add Other Course search — a code or title, a department or a faculty searches every course; without them, the courses that concern the student (the programme''s at every level and the carry-overs, a class open in the session or not; the University GST/EPS courses and the department''s or faculty''s as registration.flex_policy allows, with a class in the session), those taught in the semester first, narrowed by the level and category; each judged by registration.course_check and marked when on the recommended list, available first, then carry-over, GST, core, elective; at most 300 courses judged';

-- ── 4 · the class a student adds a course by ─────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.class_to_add(p_student uuid, p_session text, p_semester integer, p_course text)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE ctx record; x record; v_code text := btrim(coalesce(p_course, ''));
BEGIN
    IF p_semester IS NULL OR p_semester NOT IN (1, 2, 3) THEN
        RAISE EXCEPTION 'REG_SEMESTER: a semester is 1, 2 or 3' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO ctx FROM registration.course_context(p_student, p_session, p_semester);
    SELECT * INTO x FROM registration.course_check(p_student, p_session, p_semester, v_code, ctx.passed, ctx.awaited, ctx.carry, ctx.other_semester);
    IF x.refusal IS NOT NULL THEN RAISE EXCEPTION '%', x.refusal USING ERRCODE = '23514'; END IF;
    IF x.offering_id IS NOT NULL THEN RETURN x.offering_id; END IF;
    RETURN catalogue.open_class(v_code, p_session, p_semester, people.student_stream(p_student));
END $$;
COMMENT ON FUNCTION registration.class_to_add(uuid, text, integer, text) IS
  'V655: the session''s class of a course a student adds — the course judged by registration.course_check (refused with its reason), the class there is, else one opened now for the student''s stream (catalogue.open_class). The add itself judges the course again with every other rule; called in its transaction, so a refused add opens no class.';

-- ── 5 · a student's own classes opened as their registration is read: the pool of courses, registered level by level ──────────
-- the courses of the programme at the student's level (every curriculum while curricula are open) and the student's carry-overs,
-- taught in the semester, with no class yet in the session: their classes open, so the recommended list holds every course of
-- the level whenever it was bound. Only for a student who registers, and a session that holds classes and is not closed.
CREATE OR REPLACE FUNCTION registration.open_student_classes(p_student uuid, p_session text, p_semester integer)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE s people.student; v_stream text; n integer := 0; k record;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF s.id IS NULL OR s.status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') OR p_semester IS NULL OR p_semester NOT IN (1, 2, 3) THEN
        RETURN 0;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session a
                    WHERE a.name = p_session AND a.state NOT IN ('CLOSED', 'ARCHIVED', 'CANCELLED') AND a.merged_into IS NULL) THEN
        RETURN 0;
    END IF;
    v_stream := people.student_stream(p_student);
    FOR k IN
        WITH cand AS (
            SELECT co.course_code AS code FROM catalogue.course_offer co
             WHERE co.programme_code = s.programme_code AND co.level = s.current_level
               AND (registration.curriculum_open() OR co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
            UNION
            SELECT cv.course_code FROM registration.carryovers(p_student) cv)
        SELECT c.code
          FROM cand JOIN catalogue.course c ON c.code = cand.code
         WHERE c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
           AND catalogue.runs_in(c.semester, c.both_semesters, p_semester)
           AND NOT EXISTS (SELECT 1 FROM catalogue.offering o
                            WHERE o.course_code = c.code AND o.session = p_session AND o.semester = p_semester AND o.stream = v_stream)
         ORDER BY c.code
    LOOP
        PERFORM catalogue.open_class(k.code, p_session, p_semester, v_stream);
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;
COMMENT ON FUNCTION registration.open_student_classes(uuid, text, integer) IS
  'V655: as a student''s registration is read, the classes of their level''s courses (every curriculum while curricula are open) and of their carry-overs, taught in the semester, opened where the session has none yet — a course is never tied to a session, and the recommended list holds every course of the level whenever it was bound. A student who registers, a session not closed, cancelled or merged; returns how many opened.';

COMMIT;
