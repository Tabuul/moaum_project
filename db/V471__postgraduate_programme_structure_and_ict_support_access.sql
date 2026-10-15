-- ═══════════════════════════════════════
-- V471 — Postgraduate programme structure on the one course pool, and the ICT Support Desk's access to it
--
-- The School of Postgraduate Studies keeps its programmes' courses on the University's one course pool (V389: a PG course
-- is a course of catalogue.course, bound to each programme at its level in catalogue.course_offer). Nothing here is a
-- second course list; it lets the School, its Secretary and the ICT Support Desk work that structure:
--
--   · the support desk's vocabulary (helpdesk.support_capabilities) gains the structure's capabilities the Head grants with a
--     posting — VIEW_PROGRAMME_STRUCTURE, EDIT_COURSES, BIND_COURSES, MANAGE_PREREQUISITES — each within the posting's
--     faculty or department (helpdesk.agent_scope_for), as course allocation's are (V408);
--   · every ICT support agent in service now holds, across the University, viewing the programme structure and course
--     allocation — viewing the allocations, allocating and reassigning a lecturer, removing a co-lecturer (the user: course
--     allocation for all ICT support staff). The bulk allocation import, and editing courses, binding them and their
--     prerequisites, stay the Head's to grant (helpdesk.agent_baseline, V453); helpdesk.agent_scope_for now reads the
--     baseline too, so the allocation desk and the structure follow it;
--   · an offer from the course's side (catalogue.assert_offerable, V332) knows a postgraduate programme: its bases include
--     Deficiency and Research, its levels are 700, 800 and 900; an undergraduate programme's stay 100 to 600;
--   · a prerequisite is added and removed on the desk (catalogue.add_prerequisite, catalogue.remove_prerequisite): a course
--     never requires itself, nor a course that already requires it, however far round;
--   · catalogue.structure_issues lists what is wrong with a structure — a programme with no course, a course without a
--     department, a postgraduate binding off the programme's levels, an ended course still bound, a programme whose
--     department lies in another faculty, a prerequisite cycle, a PG class no PG programme takes, a PG student registered
--     on a course their programme does not carry — and catalogue.pg_structure_summary counts the School's structure;
--   · helpdesk.note_structure puts a structure change made on a ticket on the ticket's timeline.
--
-- No course, binding, registration or result is changed by this migration.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V471: postgraduate programme structure and the ICT Support Desk''s access to it', true);

-- ── 1 · the support desk's vocabulary and its baseline ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.support_capabilities()
RETURNS text[]
LANGUAGE sql IMMUTABLE AS $$
    SELECT ARRAY['VIEW_STUDENT', 'EDIT_CONTACT', 'EDIT_PERSONAL', 'EDIT_FAMILY', 'EDIT_PHOTO', 'REQUEST_CHANGE',
                 'VIEW_PAYMENTS', 'VIEW_DOCUMENTS', 'MANAGE_REGISTRATION', 'EXPORT_STUDENTS',
                 'OVERRIDE_REGISTRATION', 'RESET_PASSWORD', 'INVESTIGATE_PAYMENT', 'VERIFY_PAYMENT', 'SYNC_ENTITLEMENT',
                 'REGENERATE_RECEIPT', 'CREATE_TICKET', 'VIEW_SUPPORT_AUDIT',
                 'VIEW_ALLOCATIONS', 'ALLOCATE_COURSES', 'REMOVE_ALLOCATIONS', 'BULK_ALLOCATE',
                 'VIEW_PROGRAMME_STRUCTURE', 'EDIT_COURSES', 'BIND_COURSES', 'MANAGE_PREREQUISITES']
$$;
COMMENT ON FUNCTION helpdesk.support_capabilities() IS
  'V334, V346, V408, V471: what a support posting may carry. V471 adds the programme structure — viewing it, editing a course, binding a course into a programme and its prerequisites — each within the posting''s scope. Results, refunds, fees, amounts, matriculation and admission decisions are never among them.';

CREATE OR REPLACE FUNCTION helpdesk.agent_baseline()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $fn$
    SELECT ARRAY['ALLOCATE_COURSES', 'INVESTIGATE_PAYMENT', 'MANAGE_REGISTRATION', 'REGENERATE_RECEIPT', 'REMOVE_ALLOCATIONS', 'SYNC_ENTITLEMENT',
                 'VERIFY_PAYMENT', 'VIEW_ALLOCATIONS', 'VIEW_PAYMENTS', 'VIEW_PROGRAMME_STRUCTURE', 'VIEW_STUDENT']::text[]
$fn$;
COMMENT ON FUNCTION helpdesk.agent_baseline() IS
  'V453, V471: what every ICT support agent in service may do across the University — open a student in support mode, manage course registration, payment support (V453); view the programme structure and allocate courses: view the allocations, allocate and reassign a lecturer, remove a co-lecturer (V471). The bulk allocation import and editing the structure are granted with a posting.';

-- the scope of one capability: the postings that carry it, and the University for a baseline capability of an agent in service
CREATE OR REPLACE FUNCTION helpdesk.agent_scope_for(p_person uuid, p_capability text)
RETURNS TABLE (global boolean, faculties text[], departments text[], words text)
LANGUAGE sql STABLE AS $$
    WITH live AS (
        SELECT a.scope_kind, upper(a.scope_ref) AS ref
          FROM helpdesk.agent_assignment a
         WHERE a.person_id = p_person AND a.active AND a.scope_kind <> 'OFFICE' AND p_capability = ANY (a.capabilities)
           AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)),
    base AS (SELECT p_capability = ANY (helpdesk.agent_baseline()) AND helpdesk.agent_in_service(p_person) AS held),
    fac AS (
        SELECT ref AS code FROM live WHERE scope_kind = 'FACULTY'
        UNION
        SELECT f.code FROM live l JOIN ref.faculty f ON l.scope_kind = 'COLLEGE' AND upper(coalesce(f.college_code, '')) = l.ref),
    dep AS (SELECT ref AS code FROM live WHERE scope_kind = 'DEPARTMENT')
    SELECT EXISTS (SELECT 1 FROM live WHERE scope_kind = 'GLOBAL') OR (SELECT held FROM base),
           coalesce((SELECT array_agg(code ORDER BY code) FROM fac), '{}'::text[]),
           coalesce((SELECT array_agg(code ORDER BY code) FROM dep), '{}'::text[]),
           CASE WHEN EXISTS (SELECT 1 FROM live WHERE scope_kind = 'GLOBAL') OR (SELECT held FROM base) THEN 'The University'
                ELSE nullif(concat_ws('; ',
                        (SELECT string_agg(f.name, ', ' ORDER BY f.name) FROM fac JOIN ref.faculty f ON f.code = fac.code),
                        (SELECT string_agg(d.name, ', ' ORDER BY d.name) FROM dep JOIN ref.department d ON d.code = dep.code)), '') END
$$;
COMMENT ON FUNCTION helpdesk.agent_scope_for(uuid, text) IS
  'V346: the scope of the postings that carry one capability — the filter a list applies. V471: a baseline capability of an agent in service (helpdesk.agent_baseline) reaches the University.';

-- ── 2 · prerequisites on the desk ─────────────────────────────────────────────────────────────────────────────────────
/* the courses a course requires, however far round (its prerequisites, theirs, and so on) */
CREATE OR REPLACE FUNCTION catalogue.prerequisite_chain(p_course text)
RETURNS TABLE(course_code text)
LANGUAGE sql STABLE AS $fn$
    WITH RECURSIVE chain(code, path) AS (
        SELECT q.requires_code, ARRAY[q.course_code, q.requires_code] FROM catalogue.course_prerequisite q WHERE q.course_code = p_course
        UNION
        SELECT q.requires_code, c.path || q.requires_code
          FROM chain c JOIN catalogue.course_prerequisite q ON q.course_code = c.code
         WHERE NOT q.requires_code = ANY (c.path))
    SELECT DISTINCT code FROM chain
$fn$;
COMMENT ON FUNCTION catalogue.prerequisite_chain(text) IS 'V471: every course a course requires, through its prerequisites'' own.';

CREATE OR REPLACE FUNCTION catalogue.add_prerequisite(p_course text, p_requires text)
RETURNS void
LANGUAGE plpgsql AS $fn$
DECLARE c text := upper(btrim(coalesce(p_course, ''))); r text := upper(btrim(coalesce(p_requires, '')));
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = c) THEN
        RAISE EXCEPTION 'CAT_PREREQ_COURSE: % is not a course of the pool', c USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = r) THEN
        RAISE EXCEPTION 'CAT_PREREQ_COURSE: % is not a course of the pool', r USING ERRCODE = '23514';
    END IF;
    IF c = r THEN
        RAISE EXCEPTION 'CAT_PREREQ_SELF: a course does not require itself' USING ERRCODE = '23514';
    END IF;
    IF c IN (SELECT course_code FROM catalogue.prerequisite_chain(r)) THEN
        RAISE EXCEPTION 'CAT_PREREQ_CYCLE: % already requires %, so % cannot require %', r, c, c, r USING ERRCODE = '23514';
    END IF;
    INSERT INTO catalogue.course_prerequisite (course_code, requires_code, added_by) VALUES (c, r, v_actor) ON CONFLICT DO NOTHING;
END $fn$;
COMMENT ON FUNCTION catalogue.add_prerequisite(text, text) IS
  'V471: a course requires another — refused for a course not in the pool, for itself, and for a course that already requires it however far round.';

CREATE OR REPLACE FUNCTION catalogue.remove_prerequisite(p_course text, p_requires text)
RETURNS integer
LANGUAGE plpgsql AS $fn$
DECLARE n integer;
BEGIN
    DELETE FROM catalogue.course_prerequisite WHERE course_code = upper(btrim(p_course)) AND requires_code = upper(btrim(p_requires));
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION catalogue.remove_prerequisite(text, text) IS 'V471: a prerequisite taken off a course; the courses themselves stay.';

-- ── 2b · a binding from the course's side knows a postgraduate programme ────────────────────────────────────────────
/* V332's check of an offer (catalogue.bind_offer, catalogue.propose_offer) knew the undergraduate bases only and any level
   from 100 to 900: a postgraduate programme takes a course as Core, Elective, Borrowed, Deficiency or Research (V389), at
   700, 800 or 900 level; an undergraduate programme as Core, Elective, Borrowed or GST, at 100 to 600 */
CREATE OR REPLACE FUNCTION catalogue.assert_offerable(p_course text, p_programme text, p_level integer, p_basis text, p_track text)
RETURNS void
LANGUAGE plpgsql STABLE AS $fn$
DECLARE c catalogue.course; p ref.programme; v_pg boolean;
BEGIN
    SELECT * INTO c FROM catalogue.course WHERE code = upper(btrim(coalesce(p_course, '')));
    IF c.code IS NULL THEN RAISE EXCEPTION 'no course is coded %', p_course USING ERRCODE = '23503'; END IF;
    IF c.state = 'ENDED' THEN
        RAISE EXCEPTION 'CAT_ENDED: % has ended; an ended course is not offered to a programme', c.code USING ERRCODE = '23514',
            HINT = 'Restore the course on its department''s desk first.';
    END IF;
    SELECT * INTO p FROM ref.programme WHERE code = upper(btrim(coalesce(p_programme, '')));
    IF p.code IS NULL THEN RAISE EXCEPTION 'no programme is coded %', p_programme USING ERRCODE = '23503'; END IF;
    IF coalesce(p.archived, false) THEN
        RAISE EXCEPTION 'CAT_PROGRAMME_ARCHIVED: % is archived; a course is not offered to it', p.code USING ERRCODE = '23514';
    END IF;
    IF p.dept_code IS NULL OR NOT EXISTS (SELECT 1 FROM ref.department d WHERE d.code = p.dept_code AND d.ended_on IS NULL) THEN
        RAISE EXCEPTION 'CAT_DEPT_ENDED: the department of % is not live on the register', p.code USING ERRCODE = '23514';
    END IF;
    v_pg := p.category = 'POST GRADUATE';
    IF v_pg AND coalesce(nullif(btrim(p_basis), ''), 'Core') NOT IN ('Core', 'Elective', 'Borrowed', 'Deficiency', 'Research') THEN
        RAISE EXCEPTION 'CAT_BASIS: a postgraduate programme takes a course as Core, Elective, Borrowed, Deficiency or Research' USING ERRCODE = '23514';
    END IF;
    IF NOT v_pg AND coalesce(nullif(btrim(p_basis), ''), 'Core') NOT IN ('Core', 'Elective', 'Borrowed', 'GST') THEN
        RAISE EXCEPTION 'CAT_BASIS: a course is offered to a programme as Core, Elective, Borrowed or GST' USING ERRCODE = '23514';
    END IF;
    IF v_pg AND (p_level IS NULL OR p_level NOT IN (700, 800, 900)) THEN
        RAISE EXCEPTION 'CAT_PG_LEVEL: a postgraduate programme takes its courses at 700, 800 or 900 level' USING ERRCODE = '23514';
    END IF;
    IF NOT v_pg AND (p_level IS NULL OR p_level NOT BETWEEN 100 AND 600 OR p_level % 100 <> 0) THEN
        RAISE EXCEPTION 'CAT_UG_LEVEL: an undergraduate programme takes its courses at 100 to 600 level' USING ERRCODE = '23514';
    END IF;
    IF nullif(upper(btrim(coalesce(p_track, ''))), '') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM policy.curriculum_track t WHERE t.code = upper(btrim(p_track))) THEN
        RAISE EXCEPTION 'CAT_TRACK: no curriculum track is coded %', p_track USING ERRCODE = '23514';
    END IF;
END $fn$;
COMMENT ON FUNCTION catalogue.assert_offerable(text, text, integer, text, text) IS
  'V332, V471: an offer of a course to a programme is possible — a live course, a live programme of a live department, a basis and a level of the programme''s kind (a postgraduate programme''s Core, Elective, Borrowed, Deficiency or Research at 700, 800 or 900; an undergraduate''s Core, Elective, Borrowed or GST at 100 to 600), a known track.';

ALTER TABLE catalogue.offer_proposal DROP CONSTRAINT offer_proposal_basis_check;
ALTER TABLE catalogue.offer_proposal ADD CONSTRAINT offer_proposal_basis_check
    CHECK (basis IN ('Core', 'Elective', 'Borrowed', 'GST', 'Deficiency', 'Research'));

-- ── 3 · what is wrong with a structure ───────────────────────────────────────────────────────────────────────────────
/* p_category: 'POST GRADUATE' or 'UNDER GRADUATE' for that kind of programme, NULL for every programme */
CREATE OR REPLACE FUNCTION catalogue.structure_issues(p_category text DEFAULT NULL)
RETURNS TABLE(kind text, programme_code text, programme text, course_code text, course text, level integer, dept_code text, faculty_code text, detail text)
LANGUAGE sql STABLE AS $fn$
    WITH prog AS (SELECT p.* FROM ref.programme p WHERE NOT coalesce(p.archived, false) AND (p_category IS NULL OR p.category = p_category)),
    bound AS (SELECT co.*, p.name AS programme_name, p.category, p.dept_code AS prog_dept, p.faculty_code AS prog_faculty, p.pg_award
                FROM catalogue.course_offer co JOIN prog p ON p.code = co.programme_code)
    -- a programme that carries no course
    SELECT 'PROGRAMME_WITHOUT_COURSES', p.code, p.name, NULL::text, NULL::text, NULL::int, p.dept_code, p.faculty_code,
           'No course is bound to this programme, so its students find nothing to register'
      FROM prog p WHERE NOT EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.programme_code = p.code)
    UNION ALL
    -- a programme with no department of the register, or whose department lies in another faculty
    SELECT 'PROGRAMME_DEPARTMENT', p.code, p.name, NULL, NULL, NULL, p.dept_code, p.faculty_code,
           CASE WHEN d.code IS NULL THEN 'The programme names no department of the register'
                ELSE 'The programme''s department is in ' || coalesce(d.faculty_code, 'no faculty') || ', the programme in ' || coalesce(p.faculty_code, 'no faculty') END
      FROM prog p LEFT JOIN ref.department d ON d.code = p.dept_code
     WHERE d.code IS NULL OR d.faculty_code IS DISTINCT FROM p.faculty_code
    UNION ALL
    -- a bound course without a department of the register
    SELECT 'COURSE_WITHOUT_DEPARTMENT', b.programme_code, b.programme_name, c.code, c.title, b.level, c.dept_code, NULL,
           'The course names no department of the register'
      FROM bound b JOIN catalogue.course c ON c.code = b.course_code
     WHERE NOT EXISTS (SELECT 1 FROM ref.department d WHERE d.code = c.dept_code)
    UNION ALL
    -- a binding off the programme's levels: a postgraduate programme's are 700, 800 and 900, an undergraduate's 100 to 600
    SELECT 'LEVEL_OFF_PROGRAMME', b.programme_code, b.programme_name, c.code, c.title, b.level, b.prog_dept, b.prog_faculty,
           CASE WHEN b.category = 'POST GRADUATE' THEN 'A postgraduate programme takes its courses at 700, 800 or 900 level'
                ELSE 'An undergraduate programme takes its courses at 100 to 600 level' END
      FROM bound b JOIN catalogue.course c ON c.code = b.course_code
     WHERE (b.category = 'POST GRADUATE' AND b.level NOT IN (700, 800, 900))
        OR (b.category = 'UNDER GRADUATE' AND b.level > 600)
    UNION ALL
    -- an ended course still bound to a programme
    SELECT 'ENDED_COURSE_BOUND', b.programme_code, b.programme_name, c.code, c.title, b.level, c.dept_code, b.prog_faculty,
           'The course has ended' || coalesce(' (' || to_char(c.ended_on, 'DD Mon YYYY') || ')', '') || ' but is still bound here'
      FROM bound b JOIN catalogue.course c ON c.code = b.course_code
     WHERE c.state = 'ENDED'
    UNION ALL
    -- a course bound to one programme at more than one level
    SELECT 'BOUND_AT_TWO_LEVELS', b.programme_code, min(b.programme_name), b.course_code, min(c.title), min(b.level), min(c.dept_code), min(b.prog_faculty),
           'Bound at ' || string_agg(b.level::text, ' and ' ORDER BY b.level)
      FROM bound b JOIN catalogue.course c ON c.code = b.course_code
     GROUP BY b.programme_code, b.course_code HAVING count(*) > 1
    UNION ALL
    -- a prerequisite that leads back to the course
    SELECT 'PREREQUISITE_CYCLE', NULL, NULL, q.course_code, c.title, NULL, c.dept_code, NULL,
           q.course_code || ' requires ' || q.requires_code || ', which leads back to ' || q.course_code
      FROM catalogue.course_prerequisite q JOIN catalogue.course c ON c.code = q.course_code
     WHERE q.course_code IN (SELECT course_code FROM catalogue.prerequisite_chain(q.requires_code))
       AND (p_category IS NULL OR EXISTS (SELECT 1 FROM bound b WHERE b.course_code = q.course_code))
    UNION ALL
    -- a PG class of a course no PG programme takes
    SELECT 'PG_CLASS_UNBOUND', NULL, NULL, o.course_code, min(c.title), NULL, min(c.dept_code), NULL,
           'A postgraduate class is open (' || string_agg(DISTINCT o.session || ' semester ' || o.semester, ', ') || ') but no postgraduate programme takes the course'
      FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
     WHERE o.stream = 'PG' AND coalesce(p_category, 'POST GRADUATE') = 'POST GRADUATE'
       AND NOT EXISTS (SELECT 1 FROM catalogue.course_offer co JOIN ref.programme p ON p.code = co.programme_code
                        WHERE co.course_code = o.course_code AND p.category = 'POST GRADUATE')
     GROUP BY o.course_code
    UNION ALL
    -- a PG student registered on a course their programme does not carry
    SELECT 'REGISTERED_OFF_STRUCTURE', s.programme_code, min(p.name), o.course_code, min(c.title), r.level, min(p.dept_code), min(p.faculty_code),
           count(DISTINCT s.id) || ' student' || CASE WHEN count(DISTINCT s.id) = 1 THEN '' ELSE 's' END || ' registered on it in ' || r.session
           || ', though the programme does not carry it at ' || r.level || ' level'
      FROM registration.course_registration r
      JOIN registration.entry e ON e.registration_id = r.id AND e.status <> 'DROPPED'
      JOIN catalogue.offering o ON o.id = e.offering_id AND o.stream = 'PG'
      JOIN people.student s ON s.id = r.student_id
      JOIN prog p ON p.code = s.programme_code
      JOIN catalogue.course c ON c.code = o.course_code
     WHERE NOT EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = o.course_code AND co.programme_code = s.programme_code AND co.level = r.level)
     GROUP BY s.programme_code, o.course_code, r.level, r.session
$fn$;
COMMENT ON FUNCTION catalogue.structure_issues(text) IS
  'V471: what is wrong with the programmes'' structures (one kind of programme, or all): programmes without courses, a programme''s department or faculty out of step, bound courses without a department, bindings off the programme''s levels, ended courses still bound, a course bound at two levels, prerequisite cycles, PG classes no PG programme takes, PG students registered off their programme''s structure.';

CREATE OR REPLACE FUNCTION catalogue.pg_structure_summary()
RETURNS TABLE(programmes bigint, programmes_with_courses bigint, programmes_without_courses bigint, courses bigint, active_courses bigint,
              inactive_courses bigint, unbound_pg_courses bigint, multi_programme_courses bigint, multi_department_courses bigint, issues bigint)
LANGUAGE sql STABLE AS $fn$
    WITH prog AS (SELECT p.code, p.dept_code FROM ref.programme p WHERE p.category = 'POST GRADUATE' AND NOT coalesce(p.archived, false)),
    bound AS (SELECT co.course_code, co.programme_code, p.dept_code FROM catalogue.course_offer co JOIN prog p ON p.code = co.programme_code),
    pgc AS (SELECT DISTINCT course_code FROM bound)
    SELECT (SELECT count(*) FROM prog),
           (SELECT count(*) FROM prog WHERE code IN (SELECT programme_code FROM bound)),
           (SELECT count(*) FROM prog WHERE code NOT IN (SELECT programme_code FROM bound)),
           (SELECT count(*) FROM pgc),
           (SELECT count(*) FROM pgc JOIN catalogue.course c ON c.code = pgc.course_code WHERE c.state <> 'ENDED'),
           (SELECT count(*) FROM pgc JOIN catalogue.course c ON c.code = pgc.course_code WHERE c.state = 'ENDED'),
           -- a postgraduate-level course of the pool that no programme takes
           (SELECT count(*) FROM catalogue.course c WHERE c.level >= 700 AND c.state <> 'ENDED'
                AND NOT EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code)),
           (SELECT count(*) FROM (SELECT course_code FROM bound GROUP BY course_code HAVING count(DISTINCT programme_code) > 1) x),
           (SELECT count(*) FROM (SELECT course_code FROM bound GROUP BY course_code HAVING count(DISTINCT dept_code) > 1) x),
           (SELECT count(*) FROM catalogue.structure_issues('POST GRADUATE'))
$fn$;
COMMENT ON FUNCTION catalogue.pg_structure_summary() IS
  'V471: the School of Postgraduate Studies'' structure counted — its programmes with and without courses, its courses active and ended, the postgraduate-level courses no programme takes, the courses shared across programmes and departments, and the issues the structure checks find.';

-- ── 4 · a structure change made on a ticket, on the ticket's timeline ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.note_structure(p_ticket uuid, p_summary text, p_reason text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF p_ticket IS NULL THEN RETURN; END IF;
    INSERT INTO helpdesk.ticket_event (ticket_id, actor_kind, actor_id, actor_name, action, to_value, detail)
    VALUES (p_ticket, 'AGENT', who, helpdesk.person_name(who), 'SUPPORT_PROGRAMME_STRUCTURE', left(p_summary, 200),
            left('Action taken: ' || p_summary || coalesce(E'\nReason: ' || nullif(btrim(p_reason), ''), ''), 2000));
END $$;
COMMENT ON FUNCTION helpdesk.note_structure(uuid, text, text) IS 'V471: a programme structure change made on a ticket, put on the ticket''s timeline with what was done and why.';

COMMIT;
