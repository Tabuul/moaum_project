-- ═══════════════════════════════════════════════════════════════════════════
-- V235 — curriculum tracks: BMAS, CCMAS for the BSU cohort, CCMAS for the MOAU cohort
--
--   The framework (V116: CCMAS from 2023/2024, BMAS before) is not the whole
--   story. The University was Benue State University when the 2022/2023 and
--   2023/2024 cohorts matriculated, so their numbers begin BSU; those who
--   came in from 2024/2025 carry MOAUM. The 2023/2024 cohort sits under CCMAS
--   on the BSU structure; the cohorts after it sit under CCMAS on the
--   University's own structure; those before sit under BMAS, which is expected
--   to end after 2027/2028 — the last BMAS cohort's final year plus the two
--   years of spill-over the regulations allow — but ends in fact only when the
--   last BMAS student has gone, because the Senate keeps offering a student
--   the course their curriculum names.
--
--   So a TRACK is recorded beside the framework:
--   · policy.curriculum_track — the three tracks, with the matriculation
--     prefix and the entry sessions that place a student on each, and the
--     session each is expected to end after (a note for planning, not a gate).
--   · people.student.curriculum_track — set on insert and on the update of
--     the number or entry session, from the number's prefix first and the
--     entry session second; curriculum_version stays the track's framework.
--   · catalogue.course_offer.track — a programme-structure row may be for one
--     track (the BSU cohort's CSC 201, the MOAU cohort's), or for any (NULL).
--     The upload's curriculum picker takes a track; the code of the course is
--     the University's to choose — one code shared across tracks, or a code
--     per cohort, both work, because the track lives on the structure row.
--   · registration.student_menu shows a student the rows of their track (and
--     the rows for any track); a student never sees another cohort's structure.
--   · registration.open_course_registration offers a course as long as one of
--     its structure rows is for any track, or for a track that still has an
--     active student in that programme — so BMAS courses are offered until the
--     last BMAS student is gone, and not a session longer.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'academic', true);
SELECT set_config('moaum.reason', 'Curriculum tracks: BMAS, CCMAS-BSU, CCMAS-MOAU (V235)', true);

-- ── 1 · the tracks ───────────────────────────────────────────────────────────
CREATE TABLE policy.curriculum_track (
    code                 text PRIMARY KEY,
    framework            text NOT NULL,                  -- CCMAS · BMAS
    label                text NOT NULL,
    matric_prefix        text NULL,                      -- the number's leading letters that place a student here
    entry_from           text NULL,                      -- first entry session on this track (inclusive)
    entry_to             text NULL,                      -- last entry session on this track (inclusive)
    expected_end_session text NULL,                      -- for planning: when the last cohort should have gone
    ord                  int  NOT NULL,
    note                 text NULL,
    CONSTRAINT ck_track_framework CHECK (framework IN ('CCMAS','BMAS'))
);
SELECT audit.attach('policy.curriculum_track');

INSERT INTO policy.curriculum_track (code, framework, label, matric_prefix, entry_from, entry_to, expected_end_session, ord, note) VALUES
    ('BMAS',       'BMAS',  'BMAS — cohorts up to 2022/2023',         NULL,   NULL,        '2022/2023', '2027/2028', 1,
     'The older NUC framework. Expected to end after 2027/2028: the last cohort''s final year plus two years of spill-over. Offered for as long as a BMAS student remains.'),
    ('CCMAS_BSU',  'CCMAS', 'CCMAS — BSU cohort (entered 2023/2024)', 'BSU',  '2023/2024', '2023/2024', '2029/2030', 2,
     'The CCMAS structure as the University (then Benue State University) adopted it; the cohort''s numbers begin BSU.'),
    ('CCMAS_MOAU', 'CCMAS', 'CCMAS — MOAU cohorts (2024/2025 on)',   'MOAU', '2024/2025', NULL,        NULL,        3,
     'The University''s own CCMAS structure; every cohort from 2024/2025, whose numbers begin MOAUM.');

-- ── 2 · the student's track ──────────────────────────────────────────────────
ALTER TABLE people.student ADD COLUMN IF NOT EXISTS curriculum_track text NULL REFERENCES policy.curriculum_track(code);

-- The track a student sits on: a postgraduate is BMAS (as V117 has it); else the number's prefix
-- decides where it can (BSU → the BSU track, MOAU/MOAUM → the MOAU track), the entry session
-- decides where it cannot — and a BSU number entered before 2023/2024 is BMAS whatever its prefix.
CREATE OR REPLACE FUNCTION people.track_for(p_matric text, p_session text, p_school_id text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN upper(coalesce(p_school_id, '')) = 'S002' THEN 'BMAS'
        WHEN p_session IS NOT NULL AND p_session ~ '^[0-9]{4}/[0-9]{4}$' AND p_session < '2023/2024' THEN 'BMAS'
        WHEN upper(coalesce(p_matric, '')) LIKE 'MOAU%' THEN 'CCMAS_MOAU'
        WHEN upper(coalesce(p_matric, '')) LIKE 'BSU%' THEN
             CASE WHEN p_session IS NOT NULL AND p_session ~ '^[0-9]{4}/[0-9]{4}$' AND p_session >= '2024/2025' THEN 'CCMAS_MOAU' ELSE 'CCMAS_BSU' END
        WHEN p_session IS NOT NULL AND p_session ~ '^[0-9]{4}/[0-9]{4}$' AND p_session = '2023/2024' THEN 'CCMAS_BSU'
        WHEN p_session IS NOT NULL AND p_session ~ '^[0-9]{4}/[0-9]{4}$' THEN 'CCMAS_MOAU'
        ELSE NULL END
$$;

-- the trigger sets both: the track, and the framework the track belongs to
CREATE OR REPLACE FUNCTION people.fill_curriculum() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.curriculum_track IS NULL
       OR NEW.matric_no IS DISTINCT FROM OLD.matric_no OR NEW.entry_session IS DISTINCT FROM OLD.entry_session
       OR NEW.school_id IS DISTINCT FROM OLD.school_id THEN
        NEW.curriculum_track := people.track_for(NEW.matric_no, NEW.entry_session, NEW.school_id);
    END IF;
    IF NEW.curriculum_version IS NULL OR TG_OP = 'INSERT'
       OR NEW.curriculum_track IS DISTINCT FROM OLD.curriculum_track THEN
        NEW.curriculum_version := coalesce((SELECT framework FROM policy.curriculum_track WHERE code = NEW.curriculum_track),
                                           people.curriculum_for(NEW.entry_session, NEW.school_id));
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_student_curriculum ON people.student;
CREATE TRIGGER trg_student_curriculum BEFORE INSERT OR UPDATE ON people.student
    FOR EACH ROW EXECUTE FUNCTION people.fill_curriculum();

-- the register as it stands, placed on its tracks (audit-light bulk, as V117 did it)
ALTER TABLE people.student DISABLE TRIGGER trg_audit_people_student;
ALTER TABLE people.student DISABLE TRIGGER trg_student_curriculum;
UPDATE people.student
   SET curriculum_track = people.track_for(matric_no, entry_session, school_id),
       curriculum_version = coalesce((SELECT framework FROM policy.curriculum_track t WHERE t.code = people.track_for(matric_no, entry_session, school_id)), curriculum_version);
ALTER TABLE people.student ENABLE TRIGGER trg_student_curriculum;
ALTER TABLE people.student ENABLE TRIGGER trg_audit_people_student;
CREATE INDEX IF NOT EXISTS ix_student_track ON people.student (curriculum_track) WHERE status IN ('ACTIVE','PROBATION');

-- ── 3 · the structure row's track ────────────────────────────────────────────
ALTER TABLE catalogue.course_offer ADD COLUMN IF NOT EXISTS track text NULL REFERENCES policy.curriculum_track(code);

-- the upload takes a track (or a bare framework) as its curriculum: the course keeps the framework,
-- the structure rows keep the track
ALTER FUNCTION catalogue.import_courses(text, jsonb, text) RENAME TO import_courses_rows;

CREATE FUNCTION catalogue.import_courses(p_programme text, p_rows jsonb, p_curriculum text DEFAULT NULL)
RETURNS TABLE (rows int, courses int, offers int, no_dept int, bad_code int, skipped int, first_error text)
LANGUAGE plpgsql AS $$
DECLARE r record; v_in text := upper(nullif(btrim(coalesce(p_curriculum, '')), '')); v_track text; v_framework text; v_prog text;
BEGIN
    IF v_in IN ('CCMAS_BSU', 'CCMAS_MOAU', 'BMAS') THEN
        v_track := v_in; v_framework := (SELECT framework FROM policy.curriculum_track WHERE code = v_in);
    ELSIF v_in = 'CCMAS' THEN
        v_track := NULL; v_framework := 'CCMAS';       -- CCMAS for any cohort
    ELSE
        v_track := NULL; v_framework := v_in;
    END IF;
    FOR r IN SELECT * FROM catalogue.import_courses_rows(p_programme, p_rows, v_framework) LOOP
        rows := r.rows; courses := r.courses; offers := r.offers; no_dept := r.no_dept; bad_code := r.bad_code;
        skipped := r.skipped; first_error := r.first_error;
        SELECT code INTO v_prog FROM ref.programme
         WHERE upper(code) = upper(btrim(p_programme)) OR upper(name) = upper(btrim(p_programme)) ORDER BY archived, code LIMIT 1;
        IF v_prog IS NOT NULL THEN
            UPDATE catalogue.course_offer co SET track = v_track
             WHERE co.programme_code = v_prog
               AND upper(co.course_code) IN (
                   SELECT regexp_replace(upper(btrim(coalesce(x->>'code', x->>'courseCode', x->>'course_code', ''))), '\s+', ' ', 'g')
                     FROM jsonb_array_elements(p_rows) x)
               AND co.track IS DISTINCT FROM v_track;
        END IF;
        RETURN NEXT;
    END LOOP;
END $$;

COMMENT ON FUNCTION catalogue.import_courses(text, jsonb, text) IS
  'Loads a programme structure (catalogue.import_courses_rows, V116) under a curriculum given as a track — BMAS, CCMAS_BSU, CCMAS_MOAU — or a bare framework; the course keeps the framework, the structure rows keep the track.';

-- ── 4 · the menu shows a student their track ────────────────────────────────
CREATE OR REPLACE FUNCTION registration.student_menu(p_student uuid, p_session text, p_semester int)
RETURNS TABLE (offering_id uuid, course_code text, title text, units int, kind text, basis text, owner_dept text,
               carryover boolean, failed_in text, lecturer text)
LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT * FROM people.student WHERE id = p_student),
    eligible AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, co.basis, c.dept_code
          FROM s
          JOIN catalogue.course_offer co ON co.programme_code = s.programme_code AND co.level = s.current_level
                                        AND (co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
          JOIN catalogue.course c ON c.code = co.course_code AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
         WHERE c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version),
    carry AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, 'Carryover'::text AS basis, c.dept_code, cv.failed_in
          FROM registration.carryovers(p_student) cv
          JOIN catalogue.course c ON c.code = cv.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
          CROSS JOIN s
         WHERE registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version))
    SELECT x.offering_id, x.code, x.title, x.units, x.kind, x.basis, d.name,
           (x.basis = 'Carryover'), x.failed_in, p.surname || ', ' || p.given_names
      FROM (SELECT e.*, NULL::text AS failed_in FROM eligible e
            WHERE NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.offering_id = e.offering_id)
            UNION ALL SELECT * FROM carry) x
      JOIN ref.department d ON d.code = x.dept_code
      JOIN catalogue.offering o ON o.id = x.offering_id
      LEFT JOIN iam.person p ON p.id = o.lecturer_id
     ORDER BY (x.basis = 'Carryover') DESC, x.kind, x.code;
$$;

-- ── 5 · a track's course is offered while a student of that track remains ───
CREATE OR REPLACE FUNCTION registration.open_course_registration(p_session text, p_semester int)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, catalogue, registration, ref, policy
AS $$
DECLARE v_count int;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'course registration is opened by a person' USING ERRCODE = '23514';
    END IF;
    IF p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN
        RAISE EXCEPTION 'no academic session % on the calendar — open the session first', p_session USING ERRCODE = '23503';
    END IF;

    ALTER TABLE catalogue.offering DISABLE TRIGGER trg_audit_catalogue_offering;
    INSERT INTO catalogue.offering (id, course_code, session, semester)
    SELECT gen_random_uuid(), c.code, p_session, p_semester
      FROM catalogue.course c
     WHERE c.semester = p_semester
       AND c.state <> 'ENDED'
       -- a structure row for any track, or for a track that still has a student in the programme
       AND EXISTS (SELECT 1 FROM catalogue.course_offer co
                    WHERE co.course_code = c.code
                      AND (co.track IS NULL
                           OR EXISTS (SELECT 1 FROM people.student st
                                       WHERE st.programme_code = co.programme_code AND st.curriculum_track = co.track
                                         AND st.status IN ('ACTIVE','PROBATION','ADMITTED'))))
       AND NOT EXISTS (SELECT 1 FROM catalogue.offering o
                        WHERE o.course_code = c.code AND o.session = p_session AND o.semester = p_semester);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ALTER TABLE catalogue.offering ENABLE TRIGGER trg_audit_catalogue_offering;

    RETURN v_count;
END $$;

-- ── 6 · the figures a desk asks for ─────────────────────────────────────────
-- students by track in a department (or the University), with each track's expected end
CREATE OR REPLACE FUNCTION policy.track_census(p_dept text DEFAULT NULL)
RETURNS TABLE (code text, label text, framework text, expected_end_session text, students bigint)
LANGUAGE sql STABLE AS $$
    SELECT t.code, t.label, t.framework, t.expected_end_session,
           (SELECT count(*) FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
             WHERE s.curriculum_track = t.code AND s.status IN ('ACTIVE','PROBATION')
               AND (p_dept IS NULL OR p.dept_code = p_dept))
      FROM policy.curriculum_track t ORDER BY t.ord
$$;

COMMIT;
