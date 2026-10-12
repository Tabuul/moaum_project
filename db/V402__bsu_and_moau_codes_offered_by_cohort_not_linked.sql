-- ═══════════════════════════════════════
-- V402 — BSU- and MOAU- codes offered by cohort, not linked
--
--   The University is moving its course codes from BSU- to MOAU-. The cohorts admitted under the new codes (today's 100 and
--   200 level) register MOAU- codes; the cohorts before them (today's 300 and 400 level) register BSU- codes until they
--   graduate — a carry-over in BSU-LIS 115 is registered as BSU-LIS 115, never as MOAU-LIS 115. Both codes therefore stay in
--   the catalogue and on offer, and nothing links them: the department is not asked to confirm them as one course.
--
--   What is done here:
--     1 · catalogue.code_family_setting: the first entry session that registers MOAU- codes, stated by the Academic Office
--         (seeded as the session before the current one — the cohort now in 200 level — and changed on All courses).
--     2 · a student's family (catalogue.student_code_family): MOAU from that entry session, BSU before it; unstated, none.
--     3 · registration.student_menu: where a BSU- code and its MOAU- twin both reach the student, the student sees their
--         cohort's; a code whose twin is not on offer, or the rule unstated, is shown as before. Carry-overs and deferred
--         courses come by their own code and are untouched. (V396/V398's linking stays available but is no longer suggested.)
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V402: BSU- and MOAU- codes offered by cohort, not linked', true);

-- ── 1 · the rule, stated once ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS catalogue.code_family_setting (
    id                      smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    moau_from_entry_session text NULL CHECK (moau_from_entry_session ~ '^\d{4}/\d{4}$'),
    stated_by               uuid NULL,
    stated_at               timestamptz NULL
);
COMMENT ON TABLE catalogue.code_family_setting IS
  'V402: the first entry session whose cohort registers MOAU- codes; cohorts admitted before it register BSU- codes until they graduate. Unstated: both codes are offered to everyone.';
SELECT audit.attach('catalogue.code_family_setting') WHERE NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_audit_catalogue_code_family_setting');
-- seeded as the cohort now in 200 level: the session before the current one, and every session after it
INSERT INTO catalogue.code_family_setting (id, moau_from_entry_session)
SELECT 1, (left(s, 4)::int - 1)::text || '/' || left(s, 4)
  FROM policy.university_current_session() s
 WHERE s ~ '^\d{4}/\d{4}$'
ON CONFLICT (id) DO NOTHING;

-- ── 2 · a code's family, its twin by code, a student's family ───────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.code_family(p_code text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE WHEN p_code ~ '^BSU-' THEN 'BSU' WHEN p_code ~ '^MOAU-' THEN 'MOAU' END
$fn$;
COMMENT ON FUNCTION catalogue.code_family(text) IS 'V402: BSU or MOAU by the code''s prefix; null for any other code.';

/* the other family's code of the same course, where the catalogue holds it — linked or not */
CREATE OR REPLACE FUNCTION catalogue.twin_by_code(p_code text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT c.code
      FROM catalogue.course c
     WHERE c.code = CASE WHEN p_code ~ '^BSU-' THEN 'MOAU-' || substr(p_code, 5)
                         WHEN p_code ~ '^MOAU-' THEN 'BSU-' || substr(p_code, 6) END
       AND c.state <> 'ENDED'
$fn$;
COMMENT ON FUNCTION catalogue.twin_by_code(text) IS 'V402: the same course under the other family''s code, where the catalogue holds it (linked or not).';

CREATE OR REPLACE FUNCTION catalogue.student_code_family(p_student uuid)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN f.moau_from_entry_session IS NULL THEN NULL
                WHEN st.entry_session >= f.moau_from_entry_session THEN 'MOAU'
                ELSE 'BSU' END
      FROM people.student st
      CROSS JOIN catalogue.code_family_setting f
     WHERE st.id = p_student AND f.id = 1
$fn$;
COMMENT ON FUNCTION catalogue.student_code_family(uuid) IS 'V402: MOAU for a cohort admitted from the stated entry session, BSU before it (an unknown entry session counts as before); null while the rule is unstated.';

/* a code of the other family for this student: the rule stated, the code of a family, the student of the other, the twin held */
CREATE OR REPLACE FUNCTION catalogue.other_familys_code(p_student uuid, p_code text)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(catalogue.code_family(p_code) IS NOT NULL
                    AND catalogue.student_code_family(p_student) IS NOT NULL
                    AND catalogue.code_family(p_code) <> catalogue.student_code_family(p_student)
                    AND catalogue.twin_by_code(p_code) IS NOT NULL, false)
$fn$;

-- ── 3 · the student's menu shows their cohort's code where both codes reach them ───────────────────
CREATE OR REPLACE FUNCTION registration.student_menu(p_student uuid, p_session text, p_semester integer)
 RETURNS TABLE(offering_id uuid, course_code text, title text, units integer, kind text, basis text, owner_dept text, carryover boolean, failed_in text, lecturer text, deferred boolean, deferred_from text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V380: the student's stream: a CCE student is offered the Centre's classes, every other student the full-time ones
    WITH s AS (SELECT st.*, people.student_stream(st.id) AS stream FROM people.student st WHERE st.id = p_student),   -- V389: and the School's classes for a PG student
    -- V366: the GST/EPS courses of the programme at this level the student has already passed
    gst_passed AS (SELECT x.course_code FROM finance.gst_eps_rows(p_session, p_student) x WHERE x.status = 'ALREADY_PASSED'),
    offered AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, co.basis, c.dept_code
          FROM s
          JOIN catalogue.course_offer co ON co.programme_code = s.programme_code AND co.level = s.current_level
                                        AND (co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
          JOIN catalogue.course c ON c.code = co.course_code AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester AND o.stream = s.stream
         WHERE (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)
           AND NOT (c.kind = 'GST' AND c.code IN (SELECT gp.course_code FROM gst_passed gp))),
    -- V402: a BSU- code and its MOAU- twin are both on offer; where both reach the student, the student sees their cohort's
    -- family only (cohorts admitted from the stated session register MOAU-, earlier cohorts BSU-); a code with no twin on offer,
    -- or the rule unstated, is shown as before. Carry-overs and deferred courses come by their own code and are untouched.
    eligible AS (
        SELECT e.* FROM offered e
         WHERE NOT (catalogue.other_familys_code(p_student, e.code)
                    AND EXISTS (SELECT 1 FROM offered e2 WHERE e2.code = catalogue.twin_by_code(e.code)))),
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

COMMIT;
