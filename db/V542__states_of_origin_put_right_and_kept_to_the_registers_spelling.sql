-- V542: states of origin put right, and kept to the register's spelling on every write; the records check names what a record
-- most likely should say.
--
-- The records check (V536) found 394 live students on the live-shaped copy whose state of origin the register does not spell that
-- way — Cross-River 177, Nassarawa 135, Akwa-Ibom 50, FCT/Fct/FCT-Abuja/Abuja 18, River 4, C/River, Akwa Ibon — and 8 with a
-- country (Cameroun, Cameroon, Mali, Benin Republic). None was a spelling of Benue, so no fee was wrong; a home state spelt
-- otherwise would be charged as non-indigene. The forms already offer only the register's list; uploads (the register, the
-- biodata sheets, the old portal's) carry what was typed.
--   * ref.state_named(text): the register's name for a spelling of a state — the letters compared without case, spaces or
--     punctuation and without a trailing "State" (Cross-River, CROSS RIVER STATE → Cross River), and the known other names
--     (Nassarawa → Nasarawa, Akwa Ibon → Akwa Ibom, River → Rivers, C/River → Cross River, FCT, FCT-Abuja, Abuja →
--     Federal Capital Territory); ref.country_named(text) the same for a country (Cameroun → Cameroon, Benin Republic → Benin).
--   * The students' records put right: a state spelt another way is given the register's name (316 on the copy); a student with no
--     state of their own whose admission (the JAMB row) spells it another way is given the register's name (82). Countries are
--     left as they are. Each change is on the audit spine.
--   * people.student keeps it so: a state written in a spelling the register does not use is given the register's name as it is
--     written, by every path (forms, uploads, imports); a blank state is no state; anything else (a country) is kept as written.
--   * people.record_issues: a country is no longer listed as a state spelt another way; each issue carries a suggestion — the
--     department's postgraduate programmes for a postgraduate record on an undergraduate programme (on the copy the three such
--     records were an M.Sc.-shaped record on B.Sc. Accounting and two at 900 Level on MBBS), the register's name for a spelling.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'registrar', true);
SELECT set_config('moaum.reason', 'V542: states of origin put right to the register''s spelling', true);

-- a place's name as letters only, without case, a trailing "State" or "Republic", or a leading "Republic of"
CREATE FUNCTION ref.place_key(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT regexp_replace(regexp_replace(regexp_replace(lower(coalesce(p, '')), '[^a-z]', '', 'g'), '^(republicof|stateof)', ''), '(state|republic)$', '')
$$;

CREATE FUNCTION ref.state_named(p text) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT s.name FROM ref.state s WHERE ref.place_key(s.name) = ref.place_key(p) AND ref.place_key(p) <> '' ORDER BY s.name LIMIT 1),
        (SELECT a.name FROM (VALUES ('nassarawa', 'Nasarawa'), ('akwaibon', 'Akwa Ibom'), ('criver', 'Cross River'), ('crossrivers', 'Cross River'),
                                    ('river', 'Rivers'), ('fct', 'Federal Capital Territory'), ('fctabuja', 'Federal Capital Territory'),
                                    ('abuja', 'Federal Capital Territory'), ('abujafct', 'Federal Capital Territory'),
                                    ('federalcapital', 'Federal Capital Territory'), ('federalcapitalterritoryabuja', 'Federal Capital Territory')) a(k, name)
          WHERE a.k = ref.place_key(p) AND EXISTS (SELECT 1 FROM ref.state s WHERE s.name = a.name)))
$$;
COMMENT ON FUNCTION ref.state_named(text) IS 'V542: the register''s name for a spelling of a state of Nigeria, or null when the spelling names none';

CREATE FUNCTION ref.country_named(p text) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT c.name FROM ref.country c WHERE ref.place_key(c.name) = ref.place_key(p) AND ref.place_key(p) <> '' ORDER BY c.name LIMIT 1),
        (SELECT a.name FROM (VALUES ('cameroun', 'Cameroon'), ('ivorycoast', 'Côte d''Ivoire'), ('cotedivoire', 'Côte d''Ivoire')) a(k, name)
          WHERE a.k = ref.place_key(p) AND EXISTS (SELECT 1 FROM ref.country c WHERE c.name = a.name)))
$$;
COMMENT ON FUNCTION ref.country_named(text) IS 'V542: the register''s name for a spelling of a country, or null';

-- the records put right: a spelling the register does not use, on the student's record or (with none there) on the admission
-- each spelling read once, not for every student
WITH spelling AS MATERIALIZED (
    SELECT d.v, ref.state_named(d.v) AS name
      FROM (SELECT DISTINCT s.state_of_origin AS v FROM people.student s WHERE nullif(btrim(s.state_of_origin), '') IS NOT NULL) d
     WHERE NOT EXISTS (SELECT 1 FROM ref.state x WHERE lower(x.name) = lower(btrim(d.v))))
UPDATE people.student s SET state_of_origin = sp.name
  FROM spelling sp
 WHERE s.state_of_origin = sp.v AND sp.name IS NOT NULL;

WITH spelling AS MATERIALIZED (
    SELECT d.v, ref.state_named(d.v) AS name
      FROM (SELECT DISTINCT r.state_of_origin AS v FROM admissions.caps_row r WHERE nullif(btrim(r.state_of_origin), '') IS NOT NULL) d
     WHERE NOT EXISTS (SELECT 1 FROM ref.state x WHERE lower(x.name) = lower(btrim(d.v))))
UPDATE people.student s SET state_of_origin = sp.name
  FROM admissions.candidate c JOIN admissions.caps_row r ON r.id = c.admitted_from JOIN spelling sp ON sp.v = r.state_of_origin
 WHERE c.id = s.candidate_id
   AND nullif(btrim(s.state_of_origin), '') IS NULL
   AND sp.name IS NOT NULL;

-- and kept so, by every path that writes a student's state
CREATE FUNCTION people.student_state_named() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.state_of_origin IS NOT NULL THEN
        IF btrim(NEW.state_of_origin) = '' THEN
            NEW.state_of_origin := NULL;
        ELSIF NOT EXISTS (SELECT 1 FROM ref.state x WHERE lower(x.name) = lower(btrim(NEW.state_of_origin))) THEN
            NEW.state_of_origin := coalesce(ref.state_named(NEW.state_of_origin), btrim(NEW.state_of_origin));
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_student_state_named BEFORE INSERT OR UPDATE OF state_of_origin ON people.student
    FOR EACH ROW EXECUTE FUNCTION people.student_state_named();

UPDATE people.record_issue_kind
   SET why = 'A state is matched by its name: one spelt another way is no state on the register, and a home state spelt another way would be charged as non-indigene. Since V542 the known spellings (Cross-River, Nassarawa, FCT…) are put right as they are written; a country, for a student from abroad, is not listed.'
 WHERE code = 'STATE_NOT_ON_REGISTER';

DROP FUNCTION people.record_issues(text, text);
CREATE FUNCTION people.record_issues(p_issue text DEFAULT NULL::text, p_faculty text DEFAULT NULL::text)
 RETURNS TABLE(student_id uuid, matric_no text, admission_no text, name text, faculty_code text, faculty text, programme_code text, programme text, current_level integer, entry_mode text, status text, state text, final_level integer, issue text, suggestion text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH allowed AS (SELECT coalesce((SELECT max_spillover_years FROM policy.progression_setting ORDER BY row_no LIMIT 1), 2) AS years),
    -- V541/V542: held, so the final level is read once a programme; inlined, it was read for every student joined to it
    fl AS MATERIALIZED (SELECT pr.code, finance.final_level(pr.code) AS final FROM ref.programme pr),
    st AS (SELECT lower(name) AS name FROM ref.state),
    live AS (
        SELECT s.id, s.matric_no, s.admission_no, btrim(coalesce(s.surname, '') || ', ' || coalesce(s.other_names, ''), ', ') AS name,
               p.faculty_code, p.dept_code, s.programme_code, p.name AS programme, p.category, p.archived, p.code IS NULL AS no_programme,
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
    -- V542: each spelling read once — a state of the register, or a country (a student from abroad is not listed)
    spelt AS MATERIALIZED (
        SELECT d.state, ref.state_named(d.state) AS state_name, ref.country_named(d.state) AS country_name
          FROM (SELECT DISTINCT l.state FROM live l WHERE l.state IS NOT NULL) d
         WHERE NOT EXISTS (SELECT 1 FROM st WHERE st.name = lower(d.state))),
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
            (CASE WHEN EXISTS (SELECT 1 FROM spelt sp WHERE sp.state = l.state AND sp.country_name IS NULL) THEN 'STATE_NOT_ON_REGISTER' END)
         ) AS x(issue)
         WHERE x.issue IS NOT NULL AND (p_issue IS NULL OR x.issue = p_issue))
    SELECT f.id, f.matric_no, f.admission_no, f.name, f.faculty_code, fa.name, f.programme_code, f.programme, f.current_level, f.entry_mode,
           f.status, f.state, f.final, f.issue,
           -- V542: what the record most likely should say
           CASE WHEN f.issue = 'UG_POSTGRADUATE_ENTRY' OR (f.issue = 'LEVEL_BEYOND_PROGRAMME' AND f.current_level >= 700)
                     THEN CASE WHEN pg.list IS NOT NULL THEN 'Postgraduate programmes of the department: ' || pg.list
                               ELSE 'The department has no postgraduate programme on the register' END
                WHEN f.issue = 'STATE_NOT_ON_REGISTER'
                     THEN (SELECT 'The register''s name: ' || sp.state_name FROM spelt sp WHERE sp.state = f.state AND sp.state_name IS NOT NULL)
           END
      FROM found f
      LEFT JOIN ref.faculty fa ON fa.code = f.faculty_code
      LEFT JOIN (SELECT pp.dept_code, string_agg(pp.name || ' (' || pp.code || ')', '; ' ORDER BY pp.name) AS list
                   FROM ref.programme pp WHERE pp.category = 'POST GRADUATE' AND NOT pp.archived GROUP BY pp.dept_code) pg ON pg.dept_code = f.dept_code
     ORDER BY f.issue, fa.name NULLS FIRST, f.programme, f.current_level, f.matric_no NULLS LAST, f.name
$function$;

COMMENT ON FUNCTION people.record_issues(text, text) IS
  'V536/V542: the live students (ADMITTED, ACTIVE, PROBATION) whose record is inconsistent, by issue (people.record_issue_kind), with what it most likely should say; optionally of one issue and one faculty';

COMMIT;
