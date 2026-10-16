-- ═══════════════════════════════════════
-- V487 — Prerequisites uploaded, and the impact of enforcing them
--
-- V482 made enforcing prerequisites the Academic Office's switch. The 13 October live copy held one prerequisite, so the
-- switch has little to enforce until prerequisites are recorded, and nothing told the office whom enforcing them would stop.
--
--   registration.passed_codes(student[, among])   the codes of the student's published, graded passes (above 0 points),
--                                           as assessment.student_results reads them; among the codes named when some are.
--   registration.prerequisite_met(requires, passed[], programme, entry level)
--                                           V482's rule in one place: passed under one of the prerequisite's alternates (its
--                                           code, its BSU-/MOAU- twin, a code merged into it: prerequisite_alternates), or below
--                                           the level the student entered at (prerequisite_level).
--   registration.prerequisites_unmet        restated on the two (the same answers as V482's).
--   catalogue.load_prerequisites(rows)      a file of (course, requires) rows written row by row through
--                                           catalogue.add_prerequisite (V471): ADDED, ALREADY (recorded, or an earlier row of
--                                           the file), NO_COURSE, NO_REQUIRED, SELF, CYCLE (it would close a loop with what is
--                                           recorded or an earlier row), INCOMPLETE. The upload's preview runs it and rolls it
--                                           back; the import runs it and keeps what it wrote. Codes are read as the pool reads
--                                           them (catalogue.resolve_course_code).
--   registration.prerequisite_impact([course])   every student in study whose programme binds a course at their level that has a
--                                           prerequisite they have not passed: the course, what is not passed, and whether the
--                                           student is registered on it this session — whom enforcing stops, read at any time.
--
-- Nothing is written by this migration.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V487: prerequisites uploaded and the impact of enforcing them', true);

CREATE FUNCTION registration.passed_codes(p_student uuid, p_among text[] DEFAULT NULL) RETURNS text[]
LANGUAGE sql STABLE AS $$
    -- assessment.student_results' reading of a pass (an approved or locked registration, a registered or approved entry, the
    -- final sitting published and graded above 0 points), read only for the courses asked about when some are named
    SELECT coalesce(array_agg(DISTINCT o.course_code), '{}'::text[])
      FROM registration.course_registration r
      JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED')
      JOIN catalogue.offering o ON o.id = e.offering_id
      CROSS JOIN LATERAL assessment.course_final(p_student, o.id) cf
     WHERE r.student_id = p_student AND r.status IN ('APPROVED', 'LOCKED')
       AND (p_among IS NULL OR o.course_code = ANY (p_among))
       AND cf.stage = 'PUBLISHED' AND cf.outcome = 'GRADED' AND cf.points > 0
$$;
COMMENT ON FUNCTION registration.passed_codes(uuid, text[]) IS
  'V487: the codes of a student''s published, graded passes above 0 points (as assessment.student_results reads them), among the codes named when some are.';

CREATE FUNCTION registration.prerequisite_alternates(p_requires text) RETURNS text[]
LANGUAGE sql STABLE AS $$
    SELECT array_remove(ARRAY[p_requires, catalogue.twin_by_code(p_requires)]
                        || coalesce((SELECT array_agg(a.alias_code) FROM catalogue.course_alias a WHERE a.course_code = p_requires), '{}'::text[]), NULL)
$$;
COMMENT ON FUNCTION registration.prerequisite_alternates(text) IS 'V487: the codes a pass in a prerequisite counts under: its own, its BSU-/MOAU- twin, the codes merged into it.';

CREATE FUNCTION registration.prerequisite_level(p_requires text, p_programme text) RETURNS integer
LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT min(co.level) FROM catalogue.course_offer co WHERE co.course_code = p_requires AND co.programme_code = p_programme),
                    (SELECT c.level FROM catalogue.course c WHERE c.code = p_requires))
$$;
COMMENT ON FUNCTION registration.prerequisite_level(text, text) IS 'V487: the level a prerequisite is taken at in a programme (the course''s own level where the programme does not bind it).';

CREATE FUNCTION registration.prerequisite_met(p_requires text, p_passed text[], p_programme text, p_entry_level integer) RETURNS boolean
LANGUAGE sql STABLE AS $$
    -- passed under its code, its twin or a code merged into it; or below the level the student entered at (a Direct Entry or
    -- postgraduate student never took it)
    SELECT registration.prerequisite_alternates(p_requires) && p_passed
        OR (p_entry_level IS NOT NULL AND registration.prerequisite_level(p_requires, p_programme) < p_entry_level)
$$;
COMMENT ON FUNCTION registration.prerequisite_met(text, text[], text, integer) IS
  'V487: V482''s rule in one place — a prerequisite passed under one of its alternates, or below the student''s entry level.';

CREATE OR REPLACE FUNCTION registration.prerequisites_unmet(p_student uuid, p_course text) RETURNS text[]
LANGUAGE sql STABLE AS $$
    WITH req AS (SELECT p.requires_code FROM catalogue.course_prerequisite p WHERE p.course_code = p_course),
    -- the student's passes read only among the course's prerequisites and their alternates
    st AS (SELECT s.programme_code, s.entry_level,
                  CASE WHEN EXISTS (SELECT 1 FROM req)
                       THEN registration.passed_codes(s.id, ARRAY(SELECT a FROM req, unnest(registration.prerequisite_alternates(req.requires_code)) a))
                       ELSE '{}'::text[] END AS passed
             FROM people.student s WHERE s.id = p_student)
    SELECT coalesce(array_agg(q.requires_code ORDER BY q.requires_code), '{}'::text[])
      FROM req q CROSS JOIN st
     WHERE NOT registration.prerequisite_met(q.requires_code, st.passed, st.programme_code, st.entry_level)
$$;
COMMENT ON FUNCTION registration.prerequisites_unmet(uuid, text) IS
  'V482, V487: the course''s prerequisites the student has not passed (registration.prerequisite_met).';

CREATE FUNCTION catalogue.load_prerequisites(p_rows jsonb)
RETURNS TABLE(row_no integer, course_in text, requires_in text, course_code text, requires_code text, outcome text, message text)
LANGUAGE plpgsql AS $$
DECLARE r record; c text; q text;
BEGIN
    FOR r IN SELECT t.ord::integer AS ord, btrim(coalesce(t.x->>'course', '')) AS ci, btrim(coalesce(t.x->>'requires', '')) AS ri
               FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) WITH ORDINALITY AS t(x, ord) LOOP
        row_no := r.ord; course_in := r.ci; requires_in := r.ri;
        c := CASE WHEN r.ci = '' THEN NULL ELSE coalesce(catalogue.resolve_course_code(r.ci), upper(regexp_replace(r.ci, '\s+', ' ', 'g'))) END;
        q := CASE WHEN r.ri = '' THEN NULL ELSE coalesce(catalogue.resolve_course_code(r.ri), upper(regexp_replace(r.ri, '\s+', ' ', 'g'))) END;
        course_code := c; requires_code := q;
        IF c IS NULL OR q IS NULL THEN
            outcome := 'INCOMPLETE'; message := 'A row names the course and the course it requires.';
        ELSIF NOT EXISTS (SELECT 1 FROM catalogue.course x WHERE x.code = c) THEN
            outcome := 'NO_COURSE'; message := c || ' is not a course of the University''s pool.';
        ELSIF NOT EXISTS (SELECT 1 FROM catalogue.course x WHERE x.code = q) THEN
            outcome := 'NO_REQUIRED'; message := q || ' is not a course of the University''s pool.';
        ELSIF c = q THEN
            outcome := 'SELF'; message := 'A course does not require itself.';
        ELSIF EXISTS (SELECT 1 FROM catalogue.course_prerequisite p WHERE p.course_code = c AND p.requires_code = q) THEN
            outcome := 'ALREADY'; message := c || ' already requires ' || q || '.';
        ELSE
            BEGIN
                PERFORM catalogue.add_prerequisite(c, q);
                outcome := 'ADDED'; message := c || ' requires ' || q || '.';
            EXCEPTION WHEN check_violation THEN
                outcome := CASE WHEN SQLERRM LIKE 'CAT_PREREQ_CYCLE:%' THEN 'CYCLE' ELSE 'REFUSED' END;
                message := regexp_replace(SQLERRM, '^[A-Z_]+: ', '') || '.';
            END;
        END IF;
        RETURN NEXT;
    END LOOP;
END $$;
COMMENT ON FUNCTION catalogue.load_prerequisites(jsonb) IS
  'V487: a file of (course, requires) rows written row by row through catalogue.add_prerequisite, each row''s outcome returned; the preview runs it and rolls back.';

CREATE FUNCTION registration.prerequisite_impact(p_course text DEFAULT NULL)
RETURNS TABLE(student_id uuid, matric_no text, admission_no text, name text, programme_code text, programme text, level integer,
              course_code text, title text, unmet text, registered boolean)
LANGUAGE sql STABLE AS $$
    WITH ses AS MATERIALIZED (SELECT policy.university_current_session() AS ug, admissions.pg_current_session() AS pg),
    pairs AS MATERIALIZED (
        SELECT st.id, st.programme_code, st.current_level, st.entry_level, co.course_code
          FROM people.student st
          JOIN catalogue.course_offer co ON co.programme_code = st.programme_code AND co.level = st.current_level
         WHERE st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
           AND (p_course IS NULL OR co.course_code = p_course)   -- one course's students, when one is asked for
           AND EXISTS (SELECT 1 FROM catalogue.course_prerequisite p WHERE p.course_code = co.course_code)
           -- the bindings on the student's menu (registration.student_menu): a live course, the student's track, and a binding
           -- named for specialisations only for those specialisations' students (V483)
           AND EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = co.course_code AND c.state <> 'ENDED')
           AND (co.track IS NULL OR st.curriculum_track IS NULL OR co.track = st.curriculum_track)
           AND (NOT EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x
                             WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code AND x.level = co.level)
                OR EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x
                             JOIN people.student_specialisation ss ON ss.specialisation_id = x.specialisation_id AND ss.student_id = st.id
                            WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code AND x.level = co.level))),
    -- every requirement of every pair: (student, course, required course), with the required course's level in the programme
    -- (prerequisite_level, once per required course and programme)
    needs AS MATERIALIZED (
        SELECT pr.id, pr.programme_code, pr.current_level, pr.entry_level, pr.course_code, p.requires_code
          FROM pairs pr JOIN catalogue.course_prerequisite p ON p.course_code = pr.course_code),
    lvls AS MATERIALIZED (
        SELECT x.requires_code, x.programme_code, registration.prerequisite_level(x.requires_code, x.programme_code) AS level
          FROM (SELECT DISTINCT n.requires_code, n.programme_code FROM needs n) x),
    -- each required course's alternates as rows (prerequisite_alternates, once per required course)
    alt AS MATERIALIZED (
        SELECT q.requires_code, c AS code
          FROM (SELECT DISTINCT n.requires_code FROM needs n) q
          CROSS JOIN LATERAL unnest(registration.prerequisite_alternates(q.requires_code)) c),
    every_alt AS MATERIALIZED (SELECT coalesce(array_agg(DISTINCT a.code), '{}'::text[]) AS codes FROM alt a),
    -- each student's passes among those codes, as rows (passed_codes, once per student)
    passed AS MATERIALIZED (
        SELECT s.id, c AS code
          FROM (SELECT DISTINCT n.id FROM needs n) s
          CROSS JOIN LATERAL unnest(registration.passed_codes(s.id, (SELECT e.codes FROM every_alt e))) c),
    met AS MATERIALIZED (
        SELECT DISTINCT ps.id, a.requires_code FROM passed ps JOIN alt a ON a.code = ps.code),
    -- registration.prerequisite_met, set-wise: not passed under an alternate, and not below the entry level
    unmet AS (
        SELECT n.id, n.programme_code, n.current_level, n.course_code, string_agg(n.requires_code, ', ' ORDER BY n.requires_code) AS unmet
          FROM needs n
          JOIN lvls l ON l.requires_code = n.requires_code AND l.programme_code = n.programme_code
          LEFT JOIN met m ON m.id = n.id AND m.requires_code = n.requires_code
         WHERE m.id IS NULL AND NOT (n.entry_level IS NOT NULL AND l.level < n.entry_level)
         GROUP BY n.id, n.programme_code, n.current_level, n.course_code),
    -- registered on the course this session (the student's own session: the School's for a postgraduate), read once
    reg AS MATERIALIZED (
        SELECT DISTINCT r.student_id, r.session, o.course_code
          FROM registration.course_registration r
          JOIN registration.entry e ON e.registration_id = r.id AND e.status <> 'DROPPED' AND e.entry_type NOT IN ('CARRYOVER', 'DEFERRED')
          JOIN catalogue.offering o ON o.id = e.offering_id
         WHERE r.session IN (SELECT ses.ug FROM ses UNION SELECT ses.pg FROM ses)
           AND o.course_code IN (SELECT DISTINCT pr.course_code FROM pairs pr))
    SELECT u.id, st.matric_no, st.admission_no, st.surname || ', ' || st.other_names, u.programme_code, g.name, u.current_level,
           u.course_code, c.title, u.unmet, rg.student_id IS NOT NULL
      FROM unmet u
      CROSS JOIN ses
      JOIN people.student st ON st.id = u.id
      JOIN ref.programme g ON g.code = u.programme_code
      JOIN catalogue.course c ON c.code = u.course_code
      LEFT JOIN reg rg ON rg.student_id = u.id AND rg.course_code = u.course_code
                      AND rg.session = CASE WHEN st.entry_mode = 'POSTGRADUATE' THEN ses.pg ELSE ses.ug END
     ORDER BY u.course_code, g.name, st.surname, st.other_names
$$;
COMMENT ON FUNCTION registration.prerequisite_impact(text) IS
  'V487: every student in study whose programme binds a course at their level with a prerequisite they have not passed — whom enforcing prerequisites stops, and whether they are registered on it this session.';

COMMIT;
