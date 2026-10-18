-- V553: the Biodata form and the record kept in agreement.
--
-- The Biodata form writes people.biodata; the record keeps its own copy of four of its fields — the state of origin and the date
-- of birth (people.student), the phone and the e-mail the notices go to (people.student_contact). V548 brought the form's state
-- of origin to the record. Read the way the register reads a state, the form and the record name the same state for every live
-- student on the live-shaped copy: the "307 forms naming a state the record does not hold" of V548's note were other spellings of
-- the same state (Cross-River on the form, Cross River on the record since V542) and the 3 records with none.
--   * The form's state of origin and state of residence are kept to the register's spelling as they are written, as the record's
--     are since V542, and the spellings already on the forms are put right.
--   * The date of birth given on the form reaches the record as the state does: given by an office (the Registry on the
--     student's page), always; by the student, only where the record has none. A value that is not a date, lies in the future or
--     before 1900, changes nothing.
--   * The phone and the e-mail given on the form fill the student's contact where it has none, so the notices reach them
--     (people.student_reach reads the contact, then the application's account, never the form); a phone is read as 0 and ten
--     digits (+234… and 234… too), an e-mail as the contact holds it; anything else changes nothing.
--   * The records check lists a student whose form names another state, or another date of birth, than the record — with both,
--     for the Registry to confirm from the documents (people.record_issue_kind FORM_STATE_DIFFERS, FORM_BIRTH_DATE_DIFFERS);
--     people.record_issues restated from V548's text.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'records', true);
SELECT set_config('moaum.reason', 'V553: the Biodata form and the record kept in agreement', true);

-- ── the form's states kept to the register's spelling ──
CREATE FUNCTION people.biodata_state_named() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
    NEW.value := coalesce(ref.state_named(NEW.value), NEW.value);
    RETURN NEW;
END $fn$;
COMMENT ON FUNCTION people.biodata_state_named() IS
  'V553: a state of origin or of residence written on the Biodata form is kept to the register''s name for it (a country or an unknown value as written)';
CREATE TRIGGER trg_biodata_state_named BEFORE INSERT OR UPDATE OF value ON people.biodata
    FOR EACH ROW WHEN (NEW.field IN ('state_of_origin', 'state_of_residence')) EXECUTE FUNCTION people.biodata_state_named();

-- the form's spelling only: V548's trigger would otherwise take the form's state to the record as an office's word
ALTER TABLE people.biodata DISABLE TRIGGER trg_biodata_state_to_record;
DO $$
DECLARE n int;
BEGIN
    WITH named AS MATERIALIZED (
        SELECT d.value, ref.state_named(d.value) AS state
          FROM (SELECT DISTINCT b.value FROM people.biodata b WHERE b.field IN ('state_of_origin', 'state_of_residence')) d),
    put AS (
        UPDATE people.biodata b SET value = n.state
          FROM named n
         WHERE b.field IN ('state_of_origin', 'state_of_residence') AND b.value = n.value AND n.state IS NOT NULL AND b.value <> n.state
        RETURNING 1)
    SELECT count(*) INTO n FROM put;
    RAISE NOTICE 'V553: % Biodata form state(s) given the register''s spelling', n;
END $$;
ALTER TABLE people.biodata ENABLE TRIGGER trg_biodata_state_to_record;

-- ── the date of birth, the phone and the e-mail given on the form reach the record ──
CREATE FUNCTION people.biodata_fields_to_record() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor text := nullif(current_setting('moaum.actor_id', true), '');
        v_val text := nullif(btrim(NEW.value), ''); v_own boolean; v_dob date; v_phone text; v_email text;
BEGIN
    IF v_val IS NULL OR v_office IS NULL THEN RETURN NEW; END IF;   -- nothing given, or an import: the record's own paths state it
    v_own := v_office = 'student' OR v_actor = NEW.student_id::text;
    IF NEW.field = 'date_of_birth' THEN
        IF v_val !~ '^\d{4}-\d{2}-\d{2}$' OR NOT pg_input_is_valid(v_val, 'date') THEN RETURN NEW; END IF;
        v_dob := v_val::date;
        IF v_dob > current_date OR v_dob < date '1900-01-01' THEN RETURN NEW; END IF;
        -- the student's own answer fills an empty record only; an office's corrects it
        UPDATE people.student SET date_of_birth = v_dob
         WHERE id = NEW.student_id AND date_of_birth IS DISTINCT FROM v_dob AND (NOT v_own OR date_of_birth IS NULL);
    ELSIF NEW.field = 'mobile' THEN
        v_phone := regexp_replace(v_val, '\D', '', 'g');
        v_phone := CASE WHEN v_phone ~ '^234[0-9]{10}$' THEN '0' || substr(v_phone, 4) ELSE v_phone END;
        IF v_phone !~ '^0[0-9]{10}$' THEN RETURN NEW; END IF;
        INSERT INTO people.student_contact (student_id, phone) VALUES (NEW.student_id, v_phone)
        ON CONFLICT (student_id) DO UPDATE SET phone = v_phone, updated_at = now()
         WHERE nullif(btrim(people.student_contact.phone), '') IS NULL;
    ELSIF NEW.field = 'personal_email' THEN
        v_email := lower(v_val);
        IF v_email !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN RETURN NEW; END IF;
        INSERT INTO people.student_contact (student_id, email) VALUES (NEW.student_id, v_email)
        ON CONFLICT (student_id) DO UPDATE SET email = v_email, updated_at = now()
         WHERE nullif(btrim(people.student_contact.email), '') IS NULL;
    END IF;
    RETURN NEW;
END $fn$;
COMMENT ON FUNCTION people.biodata_fields_to_record() IS
  'V553: the date of birth given on the Biodata form reaches people.student (by an office always, by the student only into an empty record); the phone and e-mail fill an empty people.student_contact';
CREATE TRIGGER trg_biodata_fields_to_record AFTER INSERT OR UPDATE OF value ON people.biodata
    FOR EACH ROW WHEN (NEW.field IN ('date_of_birth', 'mobile', 'personal_email')) EXECUTE FUNCTION people.biodata_fields_to_record();

-- ── the records check lists a form at odds with the record ──
INSERT INTO people.record_issue_kind (code, ord, title, why, corrects, offices, how) VALUES
  ('FORM_STATE_DIFFERS', 110, 'Biodata form names another state',
   'The fee reads the state on the record; the Biodata form names another. One of them is wrong, and a home-state indigene read as a non-indigene (or the reverse) is charged the wrong fee.',
   'Registry (Records)', ARRAY['records', 'registrar', 'dregistrar'],
   'Confirm the state from the admission documents (and the certificate of indigeneship for the home state), then give it on the student''s Biodata: an office''s entry reaches the record.'),
  ('FORM_BIRTH_DATE_DIFFERS', 120, 'Biodata form names another date of birth',
   'The identity card, the transcript and the certificate read the date of birth on the record; the Biodata form names another.',
   'Registry (Records)', ARRAY['records', 'registrar', 'dregistrar'],
   'Confirm the date from the birth certificate or the JAMB record, then give it on the student''s Biodata: an office''s entry reaches the record.');

-- ── V548's people.record_issues, with the form at odds with the record ──
CREATE OR REPLACE FUNCTION people.record_issues(p_issue text DEFAULT NULL::text, p_faculty text DEFAULT NULL::text)
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
               people.is_postgraduate(s.entry_mode, p.category) AS pg_student,
               -- V553: what the Biodata form says of the state and the date of birth (the state kept to the register's spelling)
               nullif(btrim(bs.value), '') AS form_state, s.date_of_birth AS dob,
               CASE WHEN btrim(bd.value) ~ '^\d{4}-\d{2}-\d{2}$' AND pg_input_is_valid(btrim(bd.value), 'date') THEN btrim(bd.value)::date END AS form_dob
          FROM people.student s
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN fl ON fl.code = s.programme_code
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          LEFT JOIN people.biodata bs ON bs.student_id = s.id AND bs.field = 'state_of_origin'
          LEFT JOIN people.biodata bd ON bd.student_id = s.id AND bd.field = 'date_of_birth'
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
            (CASE WHEN EXISTS (SELECT 1 FROM spelt sp WHERE sp.state = l.state AND sp.country_name IS NULL) THEN 'STATE_NOT_ON_REGISTER' END),
            -- V553: the form at odds with the record — two states of the register, or two dates
            (CASE WHEN l.form_state IS NOT NULL AND l.state IS NOT NULL AND lower(l.form_state) <> lower(l.state)
                       AND EXISTS (SELECT 1 FROM st WHERE st.name = lower(l.form_state)) AND EXISTS (SELECT 1 FROM st WHERE st.name = lower(l.state))
                  THEN 'FORM_STATE_DIFFERS' END),
            (CASE WHEN l.form_dob IS NOT NULL AND l.dob IS NOT NULL AND l.form_dob <> l.dob THEN 'FORM_BIRTH_DATE_DIFFERS' END)
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
                -- V548: what the student gave on the Biodata form — the home state, for the Registry to confirm, or a value that is no state
                WHEN f.issue = 'NO_STATE_OF_ORIGIN'
                     THEN (SELECT CASE WHEN ref.state_named(b.value) IS NULL
                                       THEN 'The student gave "' || btrim(b.value) || '" on the Biodata form, which is not a state on the register'
                                       ELSE 'The student gave ' || ref.state_named(b.value) || ' on the Biodata form'
                                            || coalesce(' on ' || to_char(b.updated_at AT TIME ZONE 'Africa/Lagos', 'FMDD Mon YYYY'), '')
                                            || ': confirm it from the certificate of indigeneship and give it on the student''s Biodata' END
                             FROM people.biodata b WHERE b.student_id = f.id AND b.field = 'state_of_origin' AND btrim(b.value) <> '')
                -- V553: both, for the Registry to confirm
                WHEN f.issue = 'FORM_STATE_DIFFERS' THEN 'The Biodata form says ' || f.form_state || '; the record says ' || f.state
                WHEN f.issue = 'FORM_BIRTH_DATE_DIFFERS'
                     THEN 'The Biodata form says ' || to_char(f.form_dob, 'FMDD Mon YYYY') || '; the record says ' || to_char(f.dob, 'FMDD Mon YYYY')
           END
      FROM found f
      LEFT JOIN ref.faculty fa ON fa.code = f.faculty_code
      LEFT JOIN (SELECT pp.dept_code, string_agg(pp.name || ' (' || pp.code || ')', '; ' ORDER BY pp.name) AS list
                   FROM ref.programme pp WHERE pp.category = 'POST GRADUATE' AND NOT pp.archived GROUP BY pp.dept_code) pg ON pg.dept_code = f.dept_code
     ORDER BY f.issue, fa.name NULLS FIRST, f.programme, f.current_level, f.matric_no NULLS LAST, f.name
$function$;

COMMENT ON FUNCTION people.record_issues(text, text) IS
  'V536/V542/V548/V553: the live students (ADMITTED, ACTIVE, PROBATION) whose record is inconsistent, by issue (people.record_issue_kind), with what it most likely should say (for a missing state, what the student gave on the Biodata form; for a form at odds with the record, both); optionally of one issue and one faculty';

COMMIT;
