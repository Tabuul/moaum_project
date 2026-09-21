-- ═══════════════════════════════════════════════════════════════════════════
-- V211 — postgraduate coursework: catalogue, registration, scores, grading
--
--   The postgraduate side grades differently from the undergraduate side (Policy
--   16): A 70+, B 60–69, C 50–59, F below 50 — pass mark 50, no D/E, and no
--   resit; continuous assessment is 30–40% and the examination 60–70%. The
--   University's shared grade bands are version-scoped and in force for the
--   undergraduate scheme, so postgraduate coursework is kept in its own module
--   (as postgraduate admissions is), with its own grade function — leaving the
--   undergraduate engine untouched. Results are computed here and submitted to
--   the School in the policy's format (Sections 17, 33).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── the postgraduate grade of a mark (Policy 16.1) ──────────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_grade(p_mark numeric)
RETURNS TABLE (grade text, points numeric)
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_mark >= 70 THEN 'A' WHEN p_mark >= 60 THEN 'B' WHEN p_mark >= 50 THEN 'C' ELSE 'F' END,
           CASE WHEN p_mark >= 70 THEN 5.00 WHEN p_mark >= 60 THEN 4.00 WHEN p_mark >= 50 THEN 3.00 ELSE 0.00 END;
$$;

-- ── 1 · the course catalogue, per programme (Policy 11) ─────────────────────
CREATE TABLE admissions.pg_course (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    programme_code text NOT NULL REFERENCES ref.programme(code),
    code           text NOT NULL,                 -- e.g. ACC 801 (a 3-letter prefix and a 700/800/900 number)
    title          text NOT NULL,
    units          int  NOT NULL,
    kind           text NOT NULL DEFAULT 'CORE',  -- CORE · ELECTIVE · DEFICIENCY · RESEARCH
    semester       int  NOT NULL DEFAULT 1,
    active         boolean NOT NULL DEFAULT true,
    created_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_pg_course UNIQUE (programme_code, code),
    CONSTRAINT ck_pg_course_units CHECK (units BETWEEN 0 AND 12),
    CONSTRAINT ck_pg_course_kind CHECK (kind IN ('CORE','ELECTIVE','DEFICIENCY','RESEARCH')),
    CONSTRAINT ck_pg_course_sem CHECK (semester IN (1, 2))
);
CREATE INDEX ix_pg_course_prog ON admissions.pg_course (programme_code) WHERE active;
SELECT audit.attach('admissions.pg_course');

-- ── 2 · a student's registration for a session/semester (Policy 7) ──────────
CREATE TABLE admissions.pg_registration (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id   uuid NOT NULL REFERENCES people.student(id),
    session      text NOT NULL,
    semester     int  NOT NULL,
    mode         text NOT NULL DEFAULT 'FULL_TIME',   -- FULL_TIME · PART_TIME
    state        text NOT NULL DEFAULT 'DRAFT',        -- DRAFT · SUBMITTED · ENDORSED
    endorsed_by  uuid NULL REFERENCES iam.person(id),
    endorsed_at  timestamptz NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_pg_reg UNIQUE (student_id, session, semester),
    CONSTRAINT ck_pg_reg_mode CHECK (mode IN ('FULL_TIME','PART_TIME')),
    CONSTRAINT ck_pg_reg_sem CHECK (semester IN (1, 2)),
    CONSTRAINT ck_pg_reg_state CHECK (state IN ('DRAFT','SUBMITTED','ENDORSED'))
);
CREATE INDEX ix_pg_reg_student ON admissions.pg_registration (student_id);
SELECT audit.attach('admissions.pg_registration');

-- ── 3 · the courses on a registration ───────────────────────────────────────
CREATE TABLE admissions.pg_registration_entry (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    registration_id uuid NOT NULL REFERENCES admissions.pg_registration(id) ON DELETE CASCADE,
    course_id       uuid NOT NULL REFERENCES admissions.pg_course(id),
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_pg_reg_entry UNIQUE (registration_id, course_id)
);
CREATE INDEX ix_pg_reg_entry ON admissions.pg_registration_entry (registration_id);
SELECT audit.attach('admissions.pg_registration_entry');

-- ── 4 · the score for a registered course (CA + exam → total → grade) ────────
CREATE TABLE admissions.pg_score (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    entry_id     uuid NOT NULL UNIQUE REFERENCES admissions.pg_registration_entry(id) ON DELETE CASCADE,
    ca           numeric(5,2) NULL,                    -- continuous assessment (30–40%)
    exam         numeric(5,2) NULL,                    -- examination (60–70%)
    total        numeric(5,2) NOT NULL,
    grade        text NOT NULL,
    points       numeric(3,2) NOT NULL,
    recorded_at  timestamptz NOT NULL DEFAULT now(),
    recorded_by  uuid NULL REFERENCES iam.person(id),
    CONSTRAINT ck_pg_score_total CHECK (total BETWEEN 0 AND 100),
    CONSTRAINT ck_pg_score_grade CHECK (grade IN ('A','B','C','F'))
);
SELECT audit.attach('admissions.pg_score');

-- ── 5 · register a student's courses for a session/semester (idempotent upsert)
CREATE OR REPLACE FUNCTION admissions.pg_register(p_student uuid, p_session text, p_semester int, p_mode text, p_courses uuid[])
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_reg uuid; v_course uuid; v_prog text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_student AND entry_mode = 'POSTGRADUATE') THEN
        RAISE EXCEPTION 'not a postgraduate student %', p_student USING ERRCODE = '23514';
    END IF;
    SELECT programme_code INTO v_prog FROM people.student WHERE id = p_student;
    INSERT INTO admissions.pg_registration (student_id, session, semester, mode)
    VALUES (p_student, p_session, p_semester, coalesce(nullif(p_mode, ''), 'FULL_TIME'))
    ON CONFLICT (student_id, session, semester)
      DO UPDATE SET mode = coalesce(nullif(p_mode, ''), admissions.pg_registration.mode),
                    state = 'SUBMITTED', updated_at = now()
    RETURNING id INTO v_reg;
    -- replace the entries with the given set (only courses of the student's programme)
    DELETE FROM admissions.pg_registration_entry e
     WHERE e.registration_id = v_reg
       AND NOT EXISTS (SELECT 1 FROM admissions.pg_score s WHERE s.entry_id = e.id);
    FOREACH v_course IN ARRAY coalesce(p_courses, ARRAY[]::uuid[]) LOOP
        IF EXISTS (SELECT 1 FROM admissions.pg_course c WHERE c.id = v_course AND c.programme_code = v_prog AND c.active) THEN
            INSERT INTO admissions.pg_registration_entry (registration_id, course_id)
            VALUES (v_reg, v_course) ON CONFLICT (registration_id, course_id) DO NOTHING;
        END IF;
    END LOOP;
    RETURN v_reg;
END $$;

-- ── 6 · record a score (computes the grade), for the department/School ───────
CREATE OR REPLACE FUNCTION admissions.pg_record_score(p_entry uuid, p_ca numeric, p_exam numeric, p_by uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_total numeric; v_grade text; v_points numeric;
BEGIN
    v_total := round(coalesce(p_ca, 0) + coalesce(p_exam, 0));
    SELECT g.grade, g.points INTO v_grade, v_points FROM admissions.pg_grade(v_total) g;
    INSERT INTO admissions.pg_score (entry_id, ca, exam, total, grade, points, recorded_by)
    VALUES (p_entry, p_ca, p_exam, v_total, v_grade, v_points, p_by)
    ON CONFLICT (entry_id) DO UPDATE SET ca = EXCLUDED.ca, exam = EXCLUDED.exam, total = EXCLUDED.total,
        grade = EXCLUDED.grade, points = EXCLUDED.points, recorded_at = now(), recorded_by = EXCLUDED.recorded_by;
END $$;

-- ── 7 · GPA for a session/semester, and the cumulative CGPA (Policy 15.5/20) ─
CREATE OR REPLACE FUNCTION admissions.pg_gpa(p_student uuid, p_session text, p_semester int)
RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN sum(c.units) > 0 THEN round(sum(s.points * c.units) / sum(c.units), 2) ELSE 0 END
      FROM admissions.pg_registration r
      JOIN admissions.pg_registration_entry e ON e.registration_id = r.id
      JOIN admissions.pg_course c ON c.id = e.course_id
      JOIN admissions.pg_score s ON s.entry_id = e.id
     WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester
       AND c.kind <> 'DEFICIENCY';   -- deficiency courses earn no credit (Policy 11.3.3)
$$;

CREATE OR REPLACE FUNCTION admissions.pg_cgpa(p_student uuid)
RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN sum(c.units) > 0 THEN round(sum(s.points * c.units) / sum(c.units), 2) ELSE 0 END
      FROM admissions.pg_registration r
      JOIN admissions.pg_registration_entry e ON e.registration_id = r.id
      JOIN admissions.pg_course c ON c.id = e.course_id
      JOIN admissions.pg_score s ON s.entry_id = e.id
     WHERE r.student_id = p_student AND c.kind <> 'DEFICIENCY';
$$;

COMMIT;
