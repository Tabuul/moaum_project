-- V536: the Registry's records check — every live student whose record is at odds with itself or with the register, by what is
-- wrong, each naming the office that corrects it.
--
-- A record wrong in one field is charged and counted wrongly without anybody seeing it: on the live-shaped copy (54,571 live
-- students, 17 Oct 2026) three students sat on an undergraduate programme with the postgraduate entry mode at a postgraduate
-- level (an M.Sc.-shaped record at 700 Level on B.Sc. Accounting, two at 900 Level on MBBS), so no undergraduate fee line ever
-- reached them and no postgraduate line was theirs either; 424 had no state of origin, so the fee rule read them as
-- non-indigenes whatever their state; 394 gave a state the register does not spell that way (Cross-River, Nassarawa, FCT) or a
-- country. Each was found only by reading a fee sheet line by line.
--
-- people.record_issue_kind names what is wrong, why it matters and who corrects it (the offices, in words and as office keys);
-- people.record_issues(issue, faculty) lists the live students (ADMITTED, ACTIVE, PROBATION) with each issue, read in one pass:
--   LEVEL_BEYOND_PROGRAMME   an undergraduate above the programme's final level plus the spillover years allowed
--   UG_POSTGRADUATE_ENTRY    an undergraduate programme with the postgraduate entry mode
--   PG_UNDERGRADUATE_LEVEL   a postgraduate programme at an undergraduate level
--   DIRECT_ENTRY_AT_100      a Direct Entry student at 100 Level (Direct Entry begins at 200)
--   NO_ENTRY_MODE            no entry mode: no fee line that names one reaches the student
--   LEVEL_NOT_A_LEVEL        no level, or one that is not 100 to 900
--   PROGRAMME_ARCHIVED       a programme withdrawn from the register
--   PROGRAMME_UNKNOWN        no programme, or one the register does not hold
--   NO_STATE_OF_ORIGIN       no state of origin on the record or on the admission it came from
--   STATE_NOT_ON_REGISTER    a state the register does not spell that way (a country, for a student from abroad, is left as it is)
-- Nothing is changed: each is corrected where its office corrects records.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'registrar', true);
SELECT set_config('moaum.reason', 'V536: the Registry''s records check', true);

CREATE TABLE people.record_issue_kind (
    code      text PRIMARY KEY CHECK (code ~ '^[A-Z0-9_]+$'),
    ord       integer NOT NULL,
    title     text NOT NULL,
    why       text NOT NULL,
    corrects  text NOT NULL,
    offices   text[] NOT NULL,
    how       text NOT NULL
);
COMMENT ON TABLE people.record_issue_kind IS
  'V536: what the records check finds wrong on a student''s record, why it matters, and the office that corrects it';
SELECT audit.attach('people.record_issue_kind');

INSERT INTO people.record_issue_kind (code, ord, title, why, corrects, offices, how) VALUES
  ('LEVEL_BEYOND_PROGRAMME', 10, 'Level beyond the programme',
   'The level is above the programme''s final level and the spillover years allowed: no fee line, timetable or result sheet of the programme reaches the student.',
   'Registry (Records), with the Academic Office', ARRAY['records', 'registrar', 'dregistrar', 'academic'],
   'Correct the level on the student''s record — or, if the student is on another programme (a postgraduate one), move the record to it.'),
  ('UG_POSTGRADUATE_ENTRY', 20, 'Postgraduate entry on an undergraduate programme',
   'The postgraduate entry mode keeps every undergraduate fee line from the student, and the programme keeps every postgraduate one.',
   'Registry (Records), with the School of Postgraduate Studies', ARRAY['records', 'registrar', 'dregistrar', 'pgschool', 'pgsecretary'],
   'Give the entry mode the student was admitted by (UTME, Direct Entry, Transfer) — or, for a postgraduate student, move the record to the postgraduate programme.'),
  ('PG_UNDERGRADUATE_LEVEL', 30, 'Undergraduate level on a postgraduate programme',
   'A postgraduate student is read at 700, 800 or 900 Level; at an undergraduate level no postgraduate fee line or course reaches the student.',
   'School of Postgraduate Studies', ARRAY['pgschool', 'pgsecretary', 'registrar'],
   'Correct the level (700 for a postgraduate diploma or master''s first year, 800 or 900 as the programme reads it).'),
  ('DIRECT_ENTRY_AT_100', 40, 'Direct Entry at 100 Level',
   'Direct Entry students begin at 200 Level; the fee lines for Direct Entry name 200 Level and up, so none reaches the student.',
   'Registry (Records)', ARRAY['records', 'registrar', 'dregistrar'],
   'Correct the level to the one the student was admitted into, or the entry mode if the student came by UTME.'),
  ('NO_ENTRY_MODE', 50, 'No entry mode',
   'Every fee line of 2025/2026 names the entry mode, so none reaches the student.',
   'Registry (Records)', ARRAY['records', 'registrar', 'dregistrar'],
   'Give the entry mode from the admission list.'),
  ('LEVEL_NOT_A_LEVEL', 60, 'No level, or not a level',
   'A level must be 100 to 900 in hundreds; any other is matched by no fee line, course or result sheet.',
   'Registry (Records)', ARRAY['records', 'registrar', 'dregistrar'],
   'Give the student''s level.'),
  ('PROGRAMME_ARCHIVED', 70, 'Programme withdrawn from the register',
   'A withdrawn programme opens no new classes and no fee line is stated for it.',
   'Academic Office, with the Registry', ARRAY['academic', 'records', 'registrar', 'dregistrar'],
   'Move the student to the programme that replaced it, or bring the programme back on the course register.'),
  ('PROGRAMME_UNKNOWN', 80, 'No programme on the register',
   'The record names no programme the register holds, so nothing of a programme reaches the student.',
   'Registry (Records)', ARRAY['records', 'registrar', 'dregistrar'],
   'Give the student''s programme.'),
  ('NO_STATE_OF_ORIGIN', 90, 'No state of origin',
   'The school fee depends on indigeneship: with no state, the student is charged as a non-indigene whatever the state.',
   'The student on the biodata form, or the Registry (Records)', ARRAY['records', 'registrar', 'dregistrar', 'ict'],
   'Ask the student to complete the biodata form, or give the state from the admission documents.'),
  ('STATE_NOT_ON_REGISTER', 100, 'State spelt another way',
   'A state is matched by its name: one spelt another way (Cross-River, Nassarawa, FCT) is no state on the register, and a home state spelt another way would be charged as non-indigene. A country, for a student from abroad, needs no correction.',
   'Registry (Records)', ARRAY['records', 'registrar', 'dregistrar', 'ict'],
   'Choose the state from the list on the student''s record.');

-- the live students with each issue, one pass over the register
CREATE FUNCTION people.record_issues(p_issue text DEFAULT NULL, p_faculty text DEFAULT NULL)
RETURNS TABLE (student_id uuid, matric_no text, admission_no text, name text, faculty_code text, faculty text, programme_code text,
               programme text, current_level integer, entry_mode text, status text, state text, final_level integer, issue text)
LANGUAGE sql STABLE AS $fn$
    WITH allowed AS (SELECT coalesce((SELECT max_spillover_years FROM policy.progression_setting ORDER BY row_no LIMIT 1), 2) AS years),
    fl AS (SELECT pr.code, finance.final_level(pr.code) AS final FROM ref.programme pr),
    st AS (SELECT lower(name) AS name FROM ref.state),
    live AS (
        SELECT s.id, s.matric_no, s.admission_no, btrim(coalesce(s.surname, '') || ', ' || coalesce(s.other_names, ''), ', ') AS name,
               p.faculty_code, s.programme_code, p.name AS programme, p.category, p.archived, p.code IS NULL AS no_programme,
               s.current_level, s.entry_mode, s.status, fl.final,
               coalesce(nullif(btrim(s.state_of_origin), ''), nullif(btrim(r.state_of_origin), '')) AS state,
               people.is_postgraduate(s.entry_mode, p.category) AS pg_student
          FROM people.student s
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN fl ON fl.code = s.programme_code
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
           AND (p_faculty IS NULL OR p.faculty_code = p_faculty)),
    found AS (
        SELECT l.*, x.issue
          FROM live l
         CROSS JOIN LATERAL (VALUES
            (CASE WHEN l.category IS DISTINCT FROM 'POST GRADUATE' AND NOT l.no_programme AND l.final IS NOT NULL
                       AND l.current_level > l.final + 100 * (SELECT years FROM allowed) THEN 'LEVEL_BEYOND_PROGRAMME' END),
            (CASE WHEN l.category IS DISTINCT FROM 'POST GRADUATE' AND NOT l.no_programme AND l.entry_mode = 'POSTGRADUATE' THEN 'UG_POSTGRADUATE_ENTRY' END),
            (CASE WHEN l.category = 'POST GRADUATE' AND l.current_level < 700 THEN 'PG_UNDERGRADUATE_LEVEL' END),
            (CASE WHEN l.entry_mode = 'DIRECT_ENTRY' AND l.current_level = 100 THEN 'DIRECT_ENTRY_AT_100' END),
            (CASE WHEN nullif(btrim(l.entry_mode), '') IS NULL THEN 'NO_ENTRY_MODE' END),
            (CASE WHEN l.current_level IS NULL OR l.current_level NOT IN (100, 200, 300, 400, 500, 600, 700, 800, 900) THEN 'LEVEL_NOT_A_LEVEL' END),
            (CASE WHEN l.archived THEN 'PROGRAMME_ARCHIVED' END),
            (CASE WHEN l.no_programme THEN 'PROGRAMME_UNKNOWN' END),
            -- a fee reads indigeneship for an undergraduate; a postgraduate or CCE student's fee does not turn on it
            (CASE WHEN l.state IS NULL AND NOT l.pg_student AND l.entry_mode IS DISTINCT FROM 'CCE' THEN 'NO_STATE_OF_ORIGIN' END),
            (CASE WHEN l.state IS NOT NULL AND NOT EXISTS (SELECT 1 FROM st WHERE st.name = lower(l.state)) THEN 'STATE_NOT_ON_REGISTER' END)
         ) AS x(issue)
         WHERE x.issue IS NOT NULL AND (p_issue IS NULL OR x.issue = p_issue))
    SELECT f.id, f.matric_no, f.admission_no, f.name, f.faculty_code, fa.name, f.programme_code, f.programme, f.current_level, f.entry_mode,
           f.status, f.state, f.final, f.issue
      FROM found f
      LEFT JOIN ref.faculty fa ON fa.code = f.faculty_code
     ORDER BY f.issue, fa.name NULLS FIRST, f.programme, f.current_level, f.matric_no NULLS LAST, f.name
$fn$;
COMMENT ON FUNCTION people.record_issues(text, text) IS
  'V536: the live students (ADMITTED, ACTIVE, PROBATION) whose record is inconsistent, by issue (people.record_issue_kind), optionally of one issue and one faculty';

COMMIT;
