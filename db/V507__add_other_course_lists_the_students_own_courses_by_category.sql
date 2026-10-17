-- ═══════════════════════════════════════
-- V507 — Add Other Course lists the student's own courses, a category alone filtering them
--
--   V504's search found courses only by a code or title, a level, a department or a faculty: a category chosen alone (Carry-over,
--   GST, Core, Elective), or the dialog just opened, listed nothing ("No course matches the search").
--
--   registration.course_search now lists, when no code or title is typed and no department or faculty is chosen, the courses that
--   concern the student: their programme's courses at every level, the University-wide GST and EPS courses, their carry-overs, and
--   the department's or faculty's courses where registration.flex_policy allows them — those with a class in the session, the
--   semester's first — narrowed by the level and the category chosen. Each is judged by registration.course_check as before
--   (available first, then carry-over, GST, core, elective); a typed code or title, or a department or faculty, still searches
--   every course.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V507: Add Other Course lists the student''s own courses, a category alone filtering them', true);

CREATE OR REPLACE FUNCTION registration.course_search(p_student uuid, p_session text, p_semester integer, p_q text, p_level integer, p_dept text,
                                                      p_faculty text, p_category text, p_limit integer, p_offset integer)
RETURNS TABLE (offering_id uuid, course_code text, title text, units integer, kind text, level integer, course_semester integer, dept_code text,
               department text, faculty_code text, category text, added_as text, why text, refusal text, on_registration boolean, recommended boolean,
               total bigint)
LANGUAGE sql STABLE AS $$
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
    -- otherwise the courses that concern the student, with a class in the session (a carry-over whatever): the programme's at
    -- every level, the University GST/EPS courses, the carry-overs, the department's or faculty's where the rule allows them
    own AS (
        SELECT c.code, c.title, c.units, c.kind, c.level, c.semester, c.dept_code, d.name AS department, d.faculty_code, false AS exact,
               EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
                          AND o.stream = st.stream) AS this_semester
          FROM catalogue.course c LEFT JOIN ref.department d ON d.code = c.dept_code CROSS JOIN q CROSS JOIN st CROSS JOIN pol CROSS JOIN ctx
         WHERE q.term IS NULL AND p_dept IS NULL AND p_faculty IS NULL
           AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
           AND (p_level IS NULL OR c.level = p_level)
           AND (c.code = ANY (ctx.carry)
                OR (EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.course_code = c.code AND o.session = p_session AND o.stream = st.stream)
                    AND (EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code AND co.programme_code = st.programme_code)
                         OR (c.kind = 'GST' AND c.general_office IN ('GST', 'EPS'))
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
$$;
COMMENT ON FUNCTION registration.course_search(uuid, text, integer, text, integer, text, text, text, integer, integer) IS
  'V504/V507: the student''s Add Other Course search — a code or title, a department or a faculty searches every course; without them, the courses that concern the student (the programme''s at every level, the University GST/EPS courses, the carry-overs, the department''s or faculty''s as registration.flex_policy allows, with a class in the session), narrowed by the level and category; each judged by registration.course_check and marked when on the recommended list, available first, then carry-over, GST, core, elective; at most 300 courses judged';

COMMIT;
