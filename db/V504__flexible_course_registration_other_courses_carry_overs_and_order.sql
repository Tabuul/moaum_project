-- ═══════════════════════════════════════
-- V504 — Flexible course registration: the student adds other valid courses, the carry-overs listed, and the order kept
--
--   A student's menu (registration.student_menu: the programme's courses at the student's level that run this semester, the
--   carry-overs and the deferred courses) stays the recommended list. A student also finds and adds a course that is not on it,
--   when the University's own structure allows it, without asking ICT Support; the engine judges each one, never the browser:
--
--     · registration.flex_policy — the Academic Office's, the Registry's or the Directorate of ICT's rule: whether students add
--       other courses (ON), how wide (PROGRAMME: a course of the student's own programme at another level, an elective of it, a
--       University-wide GST/EPS course; DEPARTMENT or FACULTY adds the department's or the faculty's courses), and whether a
--       course of a higher level than the student's may be added (OFF);
--     · registration.course_check — one course for one student and semester: its class this semester, the category it would be
--       registered in (CARRY_OVER, GST, CORE, ELECTIVE), why it may be added, or why not — inactive, not offered this session or
--       semester, already passed, a result still awaited (never read as a failure), already registered in another semester of the
--       session, the SIWES semester, another curriculum, the other code family (V402), a postgraduate course for an undergraduate,
--       a higher level, not part of the student's programme, department or faculty as the rule allows, a prerequisite not passed
--       where the Academic Office enforces them (V482). The GST fee owed (V314) holds it as it holds every course on the list;
--     · registration.course_search — the courses a search finds, each judged, available ones first, in the order below;
--     · registration.outstanding_courses — the student's carry-overs as the published results state them (a published F or a
--       recorded absence, not since passed; no result is never one), each with whether it runs this semester and why not;
--     · registration.student_add_other — the student adds one course to the semester's draft (made if there is none): a course
--       already on it is refused (Course already added), one the check refuses is refused with its reason;
--     · registration.student_choose, registration.student_add (add and drop) and registration.auto_approve (V491) restated so a
--       course the student added beside the menu is kept on saving, added during add/drop, and approved automatically when it
--       still passes the check — never approved blindly; registration.entry records that the student added it, and as what;
--     · registration.entry_rank / entry_category — the University's order, everywhere a registration is listed: carry-overs and
--       outstanding courses, then GST, then core, then electives; student_menu restated in that order.
--
--   Carry-overs stay as the engine has them: a carry-over that runs this semester is put on the registration and is not removed,
--   at whatever level it was failed; one that does not run this semester is listed with the semester it runs in.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V504: flexible course registration — other valid courses, the carry-overs listed, the order kept', true);

-- ── the rule ──
CREATE TABLE registration.flex_policy (
    id                  integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    allow_other_courses boolean NOT NULL DEFAULT true,
    other_scope         text    NOT NULL DEFAULT 'PROGRAMME' CHECK (other_scope IN ('PROGRAMME', 'DEPARTMENT', 'FACULTY')),
    allow_higher_levels boolean NOT NULL DEFAULT false,
    reason              text    NOT NULL CHECK (length(btrim(reason)) >= 10),
    set_by              uuid    NULL,
    set_office          text    NULL,
    set_at              timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE registration.flex_policy IS
  'V504: whether students add courses beside their recommended list, how wide (PROGRAMME, DEPARTMENT, FACULTY) and whether a course of a higher level than the student''s may be added; one row, set by the Academic Office, the Registry, the Directorate of ICT or super with a reason';
SELECT audit.attach('registration.flex_policy');
INSERT INTO registration.flex_policy (id, reason) VALUES (1, 'V504: students add other valid courses of their programme and the University GST/EPS courses');

CREATE FUNCTION registration.flex_rule()
RETURNS registration.flex_policy LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT p FROM registration.flex_policy p WHERE p.id = 1),
                    ROW(1, true, 'PROGRAMME', false, 'the default', NULL, NULL, now())::registration.flex_policy)
$$;

CREATE FUNCTION registration.set_flex_policy(p_allow_other boolean, p_scope text, p_allow_higher boolean, p_reason text)
RETURNS registration.flex_policy LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); v registration.flex_policy;
BEGIN
    IF coalesce(v_office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'ict', 'super') THEN
        RAISE EXCEPTION 'REG_FLEX_OFFICE: the rule is set by the Academic Office, the Registry or the Directorate of ICT' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'REG_FLEX_REASON: say why the rule changes, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    IF upper(coalesce(p_scope, '')) NOT IN ('PROGRAMME', 'DEPARTMENT', 'FACULTY') THEN
        RAISE EXCEPTION 'REG_FLEX_SCOPE: a course is added from the student''s PROGRAMME, DEPARTMENT or FACULTY' USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', btrim(p_reason), true);
    INSERT INTO registration.flex_policy (id, allow_other_courses, other_scope, allow_higher_levels, reason, set_by, set_office, set_at)
    VALUES (1, coalesce(p_allow_other, true), upper(p_scope), coalesce(p_allow_higher, false), btrim(p_reason),
            nullif(current_setting('moaum.actor_id', true), '')::uuid, v_office, now())
    ON CONFLICT (id) DO UPDATE SET allow_other_courses = EXCLUDED.allow_other_courses, other_scope = EXCLUDED.other_scope,
        allow_higher_levels = EXCLUDED.allow_higher_levels, reason = EXCLUDED.reason, set_by = EXCLUDED.set_by,
        set_office = EXCLUDED.set_office, set_at = EXCLUDED.set_at
    RETURNING * INTO v;
    RETURN v;
END $$;

-- ── a course the student added beside the menu, and as what ──
ALTER TABLE registration.entry
    ADD COLUMN student_added_at timestamptz NULL,
    ADD COLUMN added_as         text        NULL
        CHECK (added_as IS NULL OR added_as IN ('PROGRAMME_OTHER_LEVEL', 'UNIVERSITY_GST', 'UNIVERSITY_EPS', 'DEPARTMENT', 'FACULTY'));
COMMENT ON COLUMN registration.entry.added_as IS
  'V504: a course the student added beside the recommended list: of the programme at another level, a University-wide GST or EPS course, of the student''s department or faculty (as registration.flex_policy allows); NULL for a course of the menu';

-- ── the order: carry-over and outstanding courses, then GST, then core, then electives ──
CREATE FUNCTION registration.entry_category(p_entry_type text, p_kind text, p_basis text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_entry_type IN ('CARRYOVER', 'DEFERRED', 'REPEAT') OR p_basis IN ('Carryover', 'Deferred') THEN 'CARRY_OVER'
                WHEN p_entry_type = 'GST' OR p_kind = 'GST' OR p_basis = 'GST' THEN 'GST'
                -- the programme's own setup decides core or elective (course_offer.basis, as registration.is_elective_for reads it);
                -- without one, the entry's type, then the course's kind
                WHEN p_basis IN ('Core', 'Elective', 'Borrowed', 'Research', 'Deficiency') THEN CASE p_basis WHEN 'Elective' THEN 'ELECTIVE' ELSE 'CORE' END
                WHEN p_entry_type = 'ELECTIVE' OR (p_entry_type IS NULL AND p_kind = 'Elective') THEN 'ELECTIVE'
                ELSE 'CORE' END
$$;
CREATE FUNCTION registration.entry_rank(p_entry_type text, p_kind text, p_basis text)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE registration.entry_category(p_entry_type, p_kind, p_basis) WHEN 'CARRY_OVER' THEN 1 WHEN 'GST' THEN 2 WHEN 'CORE' THEN 3 ELSE 4 END
$$;
COMMENT ON FUNCTION registration.entry_rank(text, text, text) IS
  'V504: the University''s order of a registration''s courses — 1 carry-over and outstanding, 2 GST, 3 core, 4 elective — from the entry''s type, the course''s kind and the programme''s basis';
CREATE FUNCTION registration.category_rank(p_category text)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_category WHEN 'CARRY_OVER' THEN 1 WHEN 'GST' THEN 2 WHEN 'CORE' THEN 3 WHEN 'ELECTIVE' THEN 4 ELSE 5 END
$$;

-- ── the student's record, read once for a check: passed, awaited, owed, and registered elsewhere in the session ──
CREATE FUNCTION registration.course_context(p_student uuid, p_session text, p_semester integer)
RETURNS TABLE (passed text[], awaited text[], carry text[], other_semester text[])
LANGUAGE sql STABLE AS $$
    WITH r AS MATERIALIZED (SELECT * FROM assessment.student_results(p_student))
    SELECT coalesce((SELECT array_agg(DISTINCT x.course_code) FROM r x WHERE x.published AND x.outcome = 'GRADED' AND x.points > 0), '{}'::text[]),
           -- registered before, with no published result yet (or one held): not owed, not passed — never read as a failure
           coalesce((SELECT array_agg(DISTINCT x.course_code) FROM r x
                      WHERE (x.session, x.semester) < (p_session, p_semester)
                        AND (NOT x.published OR x.outcome IS NULL OR x.outcome NOT IN ('GRADED', 'ABSENT'))
                        AND NOT EXISTS (SELECT 1 FROM r y WHERE y.course_code = x.course_code AND y.published AND y.outcome IN ('GRADED', 'ABSENT')
                                          AND (y.session, y.semester) >= (x.session, x.semester))), '{}'::text[]),
           coalesce((SELECT array_agg(DISTINCT cv.course_code) FROM registration.carryovers(p_student) cv), '{}'::text[]),
           coalesce((SELECT array_agg(DISTINCT o.course_code)
                       FROM registration.course_registration cr
                       JOIN registration.entry e ON e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                       JOIN catalogue.offering o ON o.id = e.offering_id
                      WHERE cr.student_id = p_student AND cr.session = p_session AND cr.semester <> p_semester), '{}'::text[])
$$;
COMMENT ON FUNCTION registration.course_context(uuid, text, integer) IS
  'V504: what a course check reads of the student once: the courses passed (a published graded pass), awaited (registered in an earlier semester with no published result, or one held), owed (registration.carryovers), and registered in another semester of the session';

-- ── one course, one student, one semester: the class, the category, why it may be added, or why not ──
CREATE FUNCTION registration.course_check(p_student uuid, p_session text, p_semester integer, p_code text,
                                          p_passed text[], p_awaited text[], p_carry text[], p_other_semester text[])
RETURNS TABLE (offering_id uuid, category text, added_as text, why text, refusal text)
LANGUAGE plpgsql STABLE AS $$
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
    IF c.curriculum IS NOT NULL AND s.curriculum_version IS NOT NULL AND c.curriculum <> s.curriculum_version THEN
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
       AND (co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
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
END $$;
COMMENT ON FUNCTION registration.course_check(uuid, text, integer, text, text[], text[], text[], text[]) IS
  'V504: whether a student may register a course in a semester beside the menu — the class, the category (CARRY_OVER, GST, CORE, ELECTIVE), what it is added as and why, or the refusal with its reason; the record read once by registration.course_context';

-- the same, for one class, reading the record itself
CREATE FUNCTION registration.course_refusal(p_student uuid, p_session text, p_semester integer, p_offering uuid)
RETURNS TABLE (offering_id uuid, category text, added_as text, why text, refusal text)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_code text; ctx record; x record;
BEGIN
    SELECT o.course_code INTO v_code FROM catalogue.offering o WHERE o.id = p_offering AND o.session = p_session AND o.semester = p_semester;
    IF v_code IS NULL THEN
        offering_id := p_offering; refusal := 'REG_NOT_THIS_SEMESTER: that class is not of ' || p_session || ' semester ' || p_semester; RETURN NEXT; RETURN;
    END IF;
    SELECT * INTO ctx FROM registration.course_context(p_student, p_session, p_semester);
    SELECT * INTO x FROM registration.course_check(p_student, p_session, p_semester, v_code, ctx.passed, ctx.awaited, ctx.carry, ctx.other_semester);
    offering_id := x.offering_id; category := x.category; added_as := x.added_as; why := x.why; refusal := x.refusal;
    IF refusal IS NULL AND x.offering_id IS DISTINCT FROM p_offering THEN
        refusal := 'REG_NOT_YOUR_CLASS: that class is not one your stream registers';
    END IF;
    RETURN NEXT;
END $$;

-- ── the search: the courses found, each judged, the available first in the University's order ──
CREATE FUNCTION registration.course_search(p_student uuid, p_session text, p_semester integer, p_q text, p_level integer, p_dept text,
                                           p_faculty text, p_category text, p_limit integer, p_offset integer)
RETURNS TABLE (offering_id uuid, course_code text, title text, units integer, kind text, level integer, course_semester integer, dept_code text,
               department text, faculty_code text, category text, added_as text, why text, refusal text, on_registration boolean, recommended boolean,
               total bigint)
LANGUAGE sql STABLE AS $$
    WITH st AS (SELECT * FROM people.student WHERE id = p_student),
    ctx AS MATERIALIZED (SELECT * FROM registration.course_context(p_student, p_session, p_semester)),
    mine AS (SELECT o.course_code FROM registration.course_registration r
               JOIN registration.entry e ON e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
               JOIN catalogue.offering o ON o.id = e.offering_id
              WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester),
    menu AS MATERIALIZED (SELECT m.offering_id FROM registration.student_menu(p_student, p_session, p_semester) m),
    q AS (SELECT nullif(btrim(coalesce(p_q, '')), '') AS term),
    cand AS MATERIALIZED (
        SELECT c.code, c.title, c.units, c.kind, c.level, c.semester, c.dept_code, d.name AS department, d.faculty_code
          FROM catalogue.course c LEFT JOIN ref.department d ON d.code = c.dept_code CROSS JOIN q
         WHERE c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
           AND (q.term IS NULL OR c.code ILIKE '%' || q.term || '%' OR replace(c.code, ' ', '') ILIKE '%' || replace(q.term, ' ', '') || '%'
                OR c.title ILIKE '%' || q.term || '%')
           AND (p_level IS NULL OR c.level = p_level) AND (p_dept IS NULL OR c.dept_code = p_dept) AND (p_faculty IS NULL OR d.faculty_code = p_faculty)
           AND (q.term IS NOT NULL OR p_level IS NOT NULL OR p_dept IS NOT NULL OR p_faculty IS NOT NULL)
         ORDER BY (upper(c.code) = upper(coalesce(q.term, ''))) DESC, c.code LIMIT 300),
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
$$;
COMMENT ON FUNCTION registration.course_search(uuid, text, integer, text, integer, text, text, text, integer, integer) IS
  'V504: the student''s Add Other Course search — courses found by code or title (a term, a level, a department or a faculty is required), each judged by registration.course_check and marked when it is on the student''s recommended list, available first, then carry-over, GST, core, elective; at most 300 courses judged';

-- ── the carry-overs, as the published results state them, and whether each runs this semester ──
CREATE FUNCTION registration.outstanding_courses(p_student uuid, p_session text, p_semester integer)
RETURNS TABLE (course_code text, title text, units integer, failed_in text, course_level integer, course_semester integer,
               offering_id uuid, on_registration boolean, runs_in text)
LANGUAGE sql STABLE AS $$
    WITH st AS (SELECT * FROM people.student WHERE id = p_student),
    cv AS (SELECT * FROM registration.carryovers(p_student))
    SELECT cv.course_code, coalesce(c.title, cv.title), coalesce(catalogue.units_for(cv.course_code, st.programme_code, NULL), cv.units), cv.failed_in,
           c.level, c.semester, o.id,
           EXISTS (SELECT 1 FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                    JOIN catalogue.offering x ON x.id = e.offering_id
                    WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester AND x.course_code = cv.course_code),
           (SELECT string_agg(CASE y.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END, ' and ' ORDER BY y.semester)
              FROM catalogue.offering y WHERE y.course_code = cv.course_code AND y.session = p_session AND y.stream = people.student_stream(p_student))
      FROM cv CROSS JOIN st
      LEFT JOIN catalogue.course c ON c.code = cv.course_code
      LEFT JOIN catalogue.offering o ON o.course_code = cv.course_code AND o.session = p_session AND o.semester = p_semester AND o.stream = people.student_stream(p_student)
     ORDER BY cv.failed_in, cv.course_code
$$;
COMMENT ON FUNCTION registration.outstanding_courses(uuid, text, integer) IS
  'V504: a student''s carry-overs (a published F or recorded absence not since passed; no result is never one) with the class this semester where there is one, whether it is on the semester''s registration, and the semesters of the session it runs in';

-- ── the student adds one course to the semester's draft ──
CREATE FUNCTION registration.student_add_other(p_student uuid, p_session text, p_semester integer, p_offering uuid)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_reg uuid; r registration.course_registration; m record; x record; v_gate text; v_unmet text[]; v_type text; v_code text;
BEGIN
    v_reg := registration.student_draft(p_student, p_session, p_semester);
    SELECT * INTO r FROM registration.course_registration WHERE id = v_reg FOR UPDATE;   -- one add at a time on a registration
    IF r.status NOT IN ('DRAFT', 'RETURNED') THEN
        RAISE EXCEPTION 'REG_NOT_EDITABLE: this registration is %; a course is added to it during add and drop', lower(r.status) USING ERRCODE = '23514';
    END IF;
    SELECT o.course_code INTO v_code FROM catalogue.offering o WHERE o.id = p_offering;
    IF EXISTS (SELECT 1 FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id
                WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN') AND o.course_code = v_code) THEN
        RAISE EXCEPTION 'REG_ALREADY_ADDED: Course already added' USING ERRCODE = '23514';
    END IF;
    -- a course of the menu is added as choosing it adds it
    SELECT * INTO m FROM registration.student_menu(p_student, p_session, p_semester) mm WHERE mm.offering_id = p_offering LIMIT 1;
    IF FOUND THEN
        IF NOT m.carryover THEN
            v_gate := registration.gst_gate(p_student, p_session, m.course_code);
            IF v_gate IS NOT NULL THEN RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514'; END IF;
            IF registration.prerequisite_mode() = 'ENFORCED' THEN
                v_unmet := registration.prerequisites_unmet(p_student, m.course_code);
                IF cardinality(v_unmet) > 0 THEN
                    RAISE EXCEPTION 'REG_PREREQUISITE: % needs % passed first', m.course_code, array_to_string(v_unmet, ', ') USING ERRCODE = '23514';
                END IF;
            END IF;
        END IF;
        v_type := CASE WHEN m.deferred THEN 'DEFERRED' WHEN m.carryover THEN 'CARRYOVER' WHEN m.basis = 'GST' OR m.kind = 'GST' THEN 'GST'
                       WHEN m.basis = 'Borrowed' THEN 'BORROWED' WHEN m.basis = 'Elective' OR (m.basis IS NULL AND m.kind = 'Elective') THEN 'ELECTIVE' ELSE 'CURRENT' END;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type) VALUES (r.id, p_offering, m.units, v_type)
        ON CONFLICT (registration_id, offering_id) DO UPDATE SET status = 'REGISTERED', entry_type = EXCLUDED.entry_type, units = EXCLUDED.units;
        RETURN jsonb_build_object('added', true, 'courseCode', m.course_code, 'category', registration.entry_category(v_type, m.kind, m.basis),
                                  'units', registration.units_of(r.id), 'recommended', true);
    END IF;
    SELECT * INTO x FROM registration.course_refusal(p_student, p_session, p_semester, p_offering);
    IF x.refusal IS NOT NULL THEN RAISE EXCEPTION '%', x.refusal USING ERRCODE = '23514'; END IF;
    -- V314: the GST fee owed holds every course the student registers, as on the menu (registration.gst_gate)
    v_gate := registration.gst_gate(p_student, p_session, v_code);
    IF v_gate IS NOT NULL THEN RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514'; END IF;
    v_type := CASE x.category WHEN 'CARRY_OVER' THEN 'CARRYOVER' WHEN 'GST' THEN 'GST' WHEN 'ELECTIVE' THEN 'ELECTIVE' ELSE 'CURRENT' END;
    INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, student_added_at, added_as)
    SELECT r.id, p_offering, catalogue.units_for(v_code, s.programme_code, NULL), v_type, now(), x.added_as FROM people.student s WHERE s.id = p_student
    ON CONFLICT (registration_id, offering_id) DO UPDATE SET status = 'REGISTERED', entry_type = EXCLUDED.entry_type, units = EXCLUDED.units,
        student_added_at = EXCLUDED.student_added_at, added_as = EXCLUDED.added_as;
    RETURN jsonb_build_object('added', true, 'courseCode', v_code, 'category', x.category, 'addedAs', x.added_as, 'why', x.why,
                              'units', registration.units_of(r.id), 'recommended', false);
END $$;
COMMENT ON FUNCTION registration.student_add_other(uuid, text, integer, uuid) IS
  'V504: the student adds one course to the semester''s draft (made if there is none): a course of the menu as choosing it adds it, any other only when registration.course_check allows it and the GST fee owed does not hold it (V314); a course already on it is refused (REG_ALREADY_ADDED)';
CREATE OR REPLACE FUNCTION registration.student_menu(p_student uuid, p_session text, p_semester integer)
 RETURNS TABLE(offering_id uuid, course_code text, title text, units integer, kind text, basis text, owner_dept text, carryover boolean, failed_in text, lecturer text, deferred boolean, deferred_from text)
 LANGUAGE sql
 STABLE
AS $$
    -- V380: the student's stream: a CCE student is offered the Centre's classes, every other student the full-time ones
    WITH s AS (SELECT st.*, people.student_stream(st.id) AS stream,   -- V389: and the School's classes for a PG student
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
                                        AND (co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
          JOIN catalogue.course c ON c.code = co.course_code AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester AND o.stream = s.stream
         WHERE (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)
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
           AND (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)),
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
$$
;

-- ── saving the draft (V482) keeps a course the student added beside the menu, judged again ──
CREATE OR REPLACE FUNCTION registration.student_choose(p_registration uuid, p_offerings uuid[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; m record; n int := 0; v_gate text; v_unmet text[];
        v_added jsonb; v_menu uuid[]; v_code text; ctx record; v_ctx boolean := false; x record; v_units int;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status NOT IN ('DRAFT','RETURNED') THEN
        RAISE EXCEPTION 'this registration is %; it is not edited', lower(r.status) USING ERRCODE = '23514',
            HINT = 'A submitted registration is changed by the level adviser returning it.';
    END IF;
    -- V504: when each course the student added beside the menu was first added, kept across saves
    SELECT coalesce(jsonb_object_agg(e.offering_id::text, e.student_added_at), '{}'::jsonb) INTO v_added
      FROM registration.entry e WHERE e.registration_id = p_registration AND e.student_added_at IS NOT NULL;
    DELETE FROM registration.entry WHERE registration_id = p_registration AND entry_type NOT IN ('CARRYOVER','DEFERRED') AND support_override_at IS NULL;
    -- a deferred course or a carry-over that has since become due is added to a draft that predates it
    FOR m IN SELECT * FROM registration.student_menu(r.student_id, r.session, r.semester) WHERE carryover LOOP
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (p_registration, m.offering_id, m.units, CASE WHEN m.deferred THEN 'DEFERRED' ELSE 'CARRYOVER' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
    END LOOP;
    SELECT coalesce(array_agg(mm.offering_id), '{}'::uuid[]) INTO v_menu FROM registration.student_menu(r.student_id, r.session, r.semester) mm;
    FOR m IN SELECT * FROM registration.student_menu(r.student_id, r.session, r.semester) WHERE NOT carryover AND offering_id = ANY(p_offerings) LOOP
        -- V314: a GST or EPS course is registered only by a student whose GST fee is paid
        v_gate := registration.gst_gate(r.student_id, r.session, m.course_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; registration opens the moment the payment is confirmed.';
        END IF;
        -- V482: where the Academic Office enforces prerequisites, a course whose prerequisite the student has not passed is refused
        IF registration.prerequisite_mode() = 'ENFORCED' THEN
            v_unmet := registration.prerequisites_unmet(r.student_id, m.course_code);
            IF cardinality(v_unmet) > 0 THEN
                RAISE EXCEPTION 'REG_PREREQUISITE: % needs % passed first; no published pass is on your record', m.course_code, array_to_string(v_unmet, ', ')
                    USING ERRCODE = '23514', HINT = 'If you passed it and the result is not yet published, or were exempted, your department asks ICT Support to add the course on your ticket.';
            END IF;
        END IF;
        -- V504: the programme's own setup (course_offer.basis) types it, as registration.is_elective_for reads it — a course the
        -- programme takes as core is core here though its own department offers it as an elective
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (p_registration, m.offering_id, m.units,
                CASE WHEN m.basis = 'GST' OR m.kind = 'GST' THEN 'GST' WHEN m.basis = 'Borrowed' THEN 'BORROWED'
                     WHEN m.basis = 'Elective' OR (m.basis IS NULL AND m.kind = 'Elective') THEN 'ELECTIVE' ELSE 'CURRENT' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        n := n + 1;
    END LOOP;
    -- V504: a course beside the menu is kept only when the engine still allows it (registration.course_check); the record is
    -- read once for all of them
    FOR v_code IN SELECT o.course_code FROM catalogue.offering o
                   WHERE o.id = ANY (p_offerings) AND NOT o.id = ANY (v_menu)
                     AND NOT EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = p_registration AND e.offering_id = o.id)
                   ORDER BY o.course_code LOOP
        IF NOT v_ctx THEN SELECT * INTO ctx FROM registration.course_context(r.student_id, r.session, r.semester); v_ctx := true; END IF;
        SELECT * INTO x FROM registration.course_check(r.student_id, r.session, r.semester, v_code, ctx.passed, ctx.awaited, ctx.carry, ctx.other_semester);
        IF x.refusal IS NOT NULL THEN
            RAISE EXCEPTION '%', x.refusal USING ERRCODE = '23514', HINT = 'Remove ' || v_code || ' from your selection and save again.';
        END IF;
        IF NOT x.offering_id = ANY (p_offerings) THEN CONTINUE; END IF;   -- another stream's class of the course: not the student's
        -- V314: the GST fee owed holds every course the student registers, as on the menu (registration.gst_gate)
        v_gate := registration.gst_gate(r.student_id, r.session, v_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; registration opens the moment the payment is confirmed.';
        END IF;
        SELECT catalogue.units_for(v_code, s.programme_code, NULL) INTO v_units FROM people.student s WHERE s.id = r.student_id;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, student_added_at, added_as)
        VALUES (p_registration, x.offering_id, v_units,
                CASE x.category WHEN 'CARRY_OVER' THEN 'CARRYOVER' WHEN 'GST' THEN 'GST' WHEN 'ELECTIVE' THEN 'ELECTIVE' ELSE 'CURRENT' END,
                coalesce((v_added ->> x.offering_id::text)::timestamptz, now()), x.added_as)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        n := n + 1;
    END LOOP;
    RETURN registration.units_of(p_registration);
END $function$;

-- ── add and drop (V482) adds a course beside the menu the engine allows ──
CREATE OR REPLACE FUNCTION registration.student_add(p_student uuid, p_session text, p_semester integer, p_offering uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; m record; lim policy.level_limit; v_units int; v_type text; v_status text; v_gate text; v_unmet text[];
        v_code text; x record; v_as text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF NOT FOUND THEN RAISE EXCEPTION 'register first, then add or drop' USING ERRCODE = '23514'; END IF;
    IF r.status = 'LOCKED' THEN RAISE EXCEPTION 'this registration is locked and cannot be changed' USING ERRCODE = '23514'; END IF;
    IF NOT registration.add_drop_open(p_student, p_session, p_semester) THEN   -- V380: by the student's calendar
        RAISE EXCEPTION 'add and drop is not open for % semester %', p_session, p_semester USING ERRCODE = '23514',
            HINT = 'It runs while the semester is open, up to the late-registration deadline set by the Registry.';
    END IF;
    IF NOT finance.clears(p_student, p_session, 'REGISTRATION') THEN
        RAISE EXCEPTION 'the Bursary has not cleared you for registration in %', p_session USING ERRCODE = '23514';
    END IF;
    -- V504: a course already on the registration is not added twice
    SELECT o.course_code INTO v_code FROM catalogue.offering o WHERE o.id = p_offering;
    IF EXISTS (SELECT 1 FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id
                WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN') AND o.course_code = v_code) THEN
        RAISE EXCEPTION 'REG_ALREADY_ADDED: Course already added' USING ERRCODE = '23514';
    END IF;

    SELECT * INTO m FROM registration.student_menu(p_student, p_session, p_semester) WHERE offering_id = p_offering AND NOT carryover;
    IF FOUND THEN
        -- V314: a GST or EPS course is added only by a student whose GST fee is paid
        v_gate := registration.gst_gate(p_student, p_session, m.course_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; it opens the moment the payment is confirmed.';
        END IF;
        -- V482: where the Academic Office enforces prerequisites, a course whose prerequisite the student has not passed is refused
        IF registration.prerequisite_mode() = 'ENFORCED' THEN
            v_unmet := registration.prerequisites_unmet(p_student, m.course_code);
            IF cardinality(v_unmet) > 0 THEN
                RAISE EXCEPTION 'REG_PREREQUISITE: % needs % passed first; no published pass is on your record', m.course_code, array_to_string(v_unmet, ', ')
                    USING ERRCODE = '23514', HINT = 'If you passed it and the result is not yet published, or were exempted, your department asks ICT Support to add the course on your ticket.';
            END IF;
        END IF;
        v_units := m.units;
        v_type := CASE WHEN m.basis = 'GST' OR m.kind = 'GST' THEN 'GST' WHEN m.basis = 'Borrowed' THEN 'BORROWED'
                       WHEN m.basis = 'Elective' OR (m.basis IS NULL AND m.kind = 'Elective') THEN 'ELECTIVE' ELSE 'CURRENT' END;
    ELSE
        -- V504: a course beside the menu, when the engine allows it (registration.course_check judges it; prerequisites included)
        SELECT * INTO x FROM registration.course_refusal(p_student, p_session, p_semester, p_offering);
        IF x.refusal IS NOT NULL THEN RAISE EXCEPTION '%', x.refusal USING ERRCODE = '23514'; END IF;
        -- V314: the GST fee owed holds every course the student registers, as on the menu (registration.gst_gate)
        v_gate := registration.gst_gate(p_student, p_session, v_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; it opens the moment the payment is confirmed.';
        END IF;
        SELECT catalogue.units_for(v_code, s.programme_code, NULL) INTO v_units FROM people.student s WHERE s.id = p_student;
        v_type := CASE x.category WHEN 'CARRY_OVER' THEN 'CARRYOVER' WHEN 'GST' THEN 'GST' WHEN 'ELECTIVE' THEN 'ELECTIVE' ELSE 'CURRENT' END;
        v_as := x.added_as;
    END IF;
    -- an approved registration has no further approval step, so the added course is examinable at once;
    -- a still-submitted one keeps REGISTERED and the HOD's approval flips it with the batch (RegistrationRepository)
    v_status := CASE WHEN r.status = 'APPROVED' THEN 'APPROVED' ELSE 'REGISTERED' END;

    -- would this exceed the level's maximum?
    SELECT * INTO lim FROM registration.unit_limit(p_student, r.level);   -- V380: the CCE course load for a CCE student
    IF FOUND AND registration.units_of(r.id) + v_units > lim.max_units THEN
        RAISE EXCEPTION 'adding this course puts you at % units, over the maximum of % at % level',
            registration.units_of(r.id) + v_units, lim.max_units, r.level USING ERRCODE = '23514',
            HINT = 'Drop a course first, or ask your Head of Department for an overload.';
    END IF;

    -- reinstate a dropped entry, or add a new one
    IF EXISTS (SELECT 1 FROM registration.entry WHERE registration_id = r.id AND offering_id = p_offering) THEN
        UPDATE registration.entry SET status = v_status, units = v_units, entry_type = v_type,
               student_added_at = CASE WHEN m.offering_id IS NULL THEN now() END, added_as = v_as
         WHERE registration_id = r.id AND offering_id = p_offering;
    ELSE
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status, student_added_at, added_as)
        VALUES (r.id, p_offering, v_units, v_type, v_status, CASE WHEN m.offering_id IS NULL THEN now() END, v_as);
    END IF;
    RETURN registration.units_of(r.id);
END $function$;

-- ── V491's automatic approval approves a course the student added only when the engine still allows it ──
CREATE OR REPLACE FUNCTION registration.auto_approve(p_registration uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; v_status text; n int; v_units int; bad text; v_card text; v_sem text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration FOR UPDATE;
    IF NOT FOUND THEN RETURN 'REG_NOT_FOUND: no such registration'; END IF;
    IF r.status IN ('APPROVED', 'LOCKED') THEN RETURN 'approved'; END IF;
    IF r.status <> 'SUBMITTED' THEN RETURN 'REG_NOT_SUBMITTED: the registration is ' || lower(r.status); END IF;
    SELECT s.status INTO v_status FROM people.student s WHERE s.id = r.student_id;
    IF v_status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') THEN
        RETURN 'REG_STUDENT_NOT_ELIGIBLE: a student who is ' || lower(v_status) || ' does not register';
    END IF;
    SELECT count(*), coalesce(sum(e.units), 0) INTO n, v_units FROM registration.entry e
     WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN');
    IF n = 0 THEN RETURN 'REG_NO_COURSES: the registration carries no course'; END IF;
    -- every course one the student may take this semester: on the student's menu (offered to the programme and level, a
    -- carryover, a GST/EPS course, an elective or a borrowed course), added by ICT Support on the student's ticket, or (V504)
    -- added by the student beside the menu and still allowed by registration.course_check
    WITH menu AS MATERIALIZED (SELECT m.offering_id FROM registration.student_menu(r.student_id, r.session, r.semester) m),
    ctx AS MATERIALIZED (SELECT * FROM registration.course_context(r.student_id, r.session, r.semester))
    SELECT o.course_code INTO bad FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id
     WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN') AND e.support_override_at IS NULL
       AND e.entry_type NOT IN ('CARRYOVER', 'DEFERRED')
       AND NOT EXISTS (SELECT 1 FROM menu WHERE menu.offering_id = e.offering_id)
       AND NOT (e.student_added_at IS NOT NULL
                AND EXISTS (SELECT 1 FROM ctx CROSS JOIN LATERAL registration.course_check(r.student_id, r.session, r.semester, o.course_code,
                                                                                        ctx.passed, ctx.awaited, ctx.carry, ctx.other_semester) x
                             WHERE x.refusal IS NULL AND x.offering_id = e.offering_id))
     ORDER BY o.course_code LIMIT 1;
    IF bad IS NOT NULL THEN
        RETURN 'REG_COURSE_NOT_OFFERED: ' || bad || ' is not offered to this student''s programme and level for ' || r.session || ' semester ' || r.semester;
    END IF;
    UPDATE registration.course_registration SET status = 'APPROVED', approved_at = now(), approved_by = NULL, approval_mode = 'AUTO'
     WHERE id = r.id;
    UPDATE registration.entry SET status = 'APPROVED' WHERE registration_id = r.id AND status = 'REGISTERED';
    UPDATE registration.approval_review SET cleared_at = now() WHERE registration_id = r.id AND cleared_at IS NULL;
    v_sem := CASE r.semester WHEN 1 THEN 'first semester' WHEN 2 THEN 'second semester' ELSE 'third semester' END;
    v_card := CASE WHEN NOT coalesce((registration.approval_rule(r.session, r.semester)).card_on_approval, true)
                   THEN 'Your examination card is released with the examination timetable.'
                   WHEN policy.in_force('clearance', 'UNIVERSITY', current_date) IS NULL OR finance.clears(r.student_id, r.session, 'EXAMINATION')
                   THEN 'Your examination card is now available for printing.'
                   ELSE 'Your examination card follows when your fees are cleared for the examination.' END;
    PERFORM platform.tell_student(r.student_id, 'REG_AUTO_APPROVED', NULL,
        jsonb_build_object('SESSION', r.session, 'SEMESTER', v_sem, 'UNITS', v_units, 'CARD_NOTE', v_card),
        'REG_AUTO_APPROVED:' || r.id || ':' || floor(extract(epoch FROM coalesce(r.submitted_at, now())))::bigint);
    RETURN 'approved';
END $function$;

COMMIT;
