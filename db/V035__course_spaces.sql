-- ═══════════════════════════════════════════════════════════════════════════
-- V035 — course spaces
--
--   A course space is built from the approved registrations: the lecturer
--   the department allocated publishes material and sets assignments; the
--   students on the roll — and nobody else — read the material and submit.
--   Every read of a material is counted, so engagement is a figure counted
--   from the record and not typed beside it. The gradebook total, promoted,
--   lands in the CA column of the score sheet as a new version with its
--   reason, where it still passes verification, the Board, the Faculty and
--   Senate like any other mark (V013).
--
--   Files are held here up to 5 MB; larger material is linked by address.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE SCHEMA IF NOT EXISTS lms;
GRANT USAGE ON SCHEMA lms TO app_student, app_results, app_auditor;

CREATE TABLE lms.material (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    offering_id   uuid NOT NULL REFERENCES catalogue.offering(id),
    week          int  NULL,
    title         text NOT NULL,
    kind          text NOT NULL DEFAULT 'NOTES',
    description   text NULL,
    filename      text NULL,
    content_type  text NULL,
    bytes         bigint NULL,
    link          text NULL,
    published_at  timestamptz NULL,
    published_by  uuid NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    ended_at      timestamptz NULL,
    CONSTRAINT ck_lm_kind CHECK (kind IN ('NOTES','SLIDES','READING','VIDEO','AUDIO','OTHER')),
    CONSTRAINT ck_lm_title CHECK (btrim(title) <> ''),
    CONSTRAINT ck_lm_week CHECK (week IS NULL OR week BETWEEN 1 AND 20),
    CONSTRAINT ck_lm_bytes CHECK (bytes IS NULL OR bytes BETWEEN 1 AND 5242880),
    CONSTRAINT ck_lm_content CHECK (filename IS NOT NULL OR link IS NOT NULL)
);
CREATE INDEX ix_lm_offering ON lms.material (offering_id, week);
SELECT audit.attach('lms.material');

CREATE TABLE lms.material_blob (
    material_id uuid PRIMARY KEY REFERENCES lms.material(id),
    content     bytea NOT NULL
);
SELECT audit.exempt('lms.material_blob', 'The file itself, up to 5 MB; the fact of it — name, size, who published it — is on the spine in lms.material.');

CREATE TABLE lms.access (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    material_id uuid NOT NULL REFERENCES lms.material(id),
    student_id  uuid NOT NULL REFERENCES people.student(id),
    at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_la_material ON lms.access (material_id, student_id);
SELECT audit.exempt('lms.access', 'A read counted; a log of reads is not a state change, and auditing it doubles every row.');

CREATE TABLE lms.assignment (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    offering_id uuid NOT NULL REFERENCES catalogue.offering(id),
    title       text NOT NULL,
    brief       text NULL,
    kind        text NOT NULL DEFAULT 'INDIVIDUAL',
    opens_at    timestamptz NOT NULL DEFAULT now(),
    closes_at   timestamptz NOT NULL,
    late_hours  int NOT NULL DEFAULT 48,
    late_penalty int NOT NULL DEFAULT 10,
    weight      int NOT NULL,
    out_of      int NOT NULL DEFAULT 100,
    created_by  uuid NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    ended_at    timestamptz NULL,
    CONSTRAINT ck_las_kind CHECK (kind IN ('INDIVIDUAL','PAIRS','GROUP')),
    CONSTRAINT ck_las_title CHECK (btrim(title) <> ''),
    CONSTRAINT ck_las_dates CHECK (closes_at > opens_at),
    CONSTRAINT ck_las_weight CHECK (weight BETWEEN 1 AND 40),
    CONSTRAINT ck_las_penalty CHECK (late_penalty BETWEEN 0 AND 100 AND late_hours BETWEEN 0 AND 720),
    CONSTRAINT ck_las_out_of CHECK (out_of BETWEEN 1 AND 1000)
);
CREATE INDEX ix_las_offering ON lms.assignment (offering_id);
SELECT audit.attach('lms.assignment');

CREATE TABLE lms.submission (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id uuid NOT NULL REFERENCES lms.assignment(id),
    student_id    uuid NOT NULL REFERENCES people.student(id),
    submitted_at  timestamptz NOT NULL DEFAULT now(),
    text          text NULL,
    filename      text NULL,
    content_type  text NULL,
    bytes         bigint NULL,
    late          boolean NOT NULL DEFAULT false,
    mark          numeric(6,2) NULL,
    marked_at     timestamptz NULL,
    marked_by     uuid NULL,
    feedback      text NULL,
    UNIQUE (assignment_id, student_id),
    CONSTRAINT ck_ls_content CHECK (text IS NOT NULL OR filename IS NOT NULL),
    CONSTRAINT ck_ls_bytes CHECK (bytes IS NULL OR bytes BETWEEN 1 AND 5242880),
    CONSTRAINT ck_ls_mark CHECK (mark IS NULL OR mark >= 0),
    CONSTRAINT ck_ls_marked CHECK ((mark IS NULL) = (marked_at IS NULL))
);
SELECT audit.attach('lms.submission');

CREATE TABLE lms.submission_blob (
    submission_id uuid PRIMARY KEY REFERENCES lms.submission(id),
    content       bytea NOT NULL
);
SELECT audit.exempt('lms.submission_blob', 'The submitted file itself, up to 5 MB; the fact of it is on the spine in lms.submission.');

-- ── who is on the roll of a space: the approved registrations, nobody else ──
CREATE OR REPLACE FUNCTION lms.on_roll(p_offering uuid, p_student uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                    WHERE e.offering_id = p_offering AND r.student_id = p_student AND e.status IN ('REGISTERED','APPROVED') AND r.status IN ('APPROVED','LOCKED'))
$$;

CREATE OR REPLACE FUNCTION lms.roll_size(p_offering uuid)
RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT count(*)::int FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
     WHERE e.offering_id = p_offering AND e.status IN ('REGISTERED','APPROVED') AND r.status IN ('APPROVED','LOCKED')
$$;

-- ── the student submits: on time, late within the window at the penalty, or not at all ──
CREATE OR REPLACE FUNCTION lms.submit(p_assignment uuid, p_student uuid, p_text text, p_filename text, p_content_type text, p_bytes bigint)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE a lms.assignment; v uuid := gen_random_uuid(); v_late boolean;
BEGIN
    SELECT * INTO a FROM lms.assignment WHERE id = p_assignment AND ended_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such assignment' USING ERRCODE = '23503'; END IF;
    IF NOT lms.on_roll(a.offering_id, p_student) THEN
        RAISE EXCEPTION 'you are not registered and approved for this course' USING ERRCODE = '23514',
            HINT = 'The course space is built from the approved registrations; a student who is not on the roll cannot submit.';
    END IF;
    IF now() < a.opens_at THEN RAISE EXCEPTION 'the assignment opens on %', a.opens_at::date USING ERRCODE = '23514'; END IF;
    v_late := now() > a.closes_at;
    IF v_late AND now() > a.closes_at + make_interval(hours => a.late_hours) THEN
        RAISE EXCEPTION 'the assignment closed on % and the late window of % hours has passed', a.closes_at::date, a.late_hours USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM lms.submission WHERE assignment_id = p_assignment AND student_id = p_student AND mark IS NOT NULL) THEN
        RAISE EXCEPTION 'this submission is marked; it is not replaced' USING ERRCODE = '23514';
    END IF;
    DELETE FROM lms.submission_blob WHERE submission_id IN (SELECT id FROM lms.submission WHERE assignment_id = p_assignment AND student_id = p_student);
    DELETE FROM lms.submission WHERE assignment_id = p_assignment AND student_id = p_student;
    INSERT INTO lms.submission (id, assignment_id, student_id, text, filename, content_type, bytes, late)
    VALUES (v, p_assignment, p_student, nullif(btrim(p_text), ''), p_filename, p_content_type, p_bytes, v_late);
    RETURN v;
END $$;

-- ── the gradebook: each student's weighted total over the marked assignments ──
CREATE OR REPLACE FUNCTION lms.gradebook(p_offering uuid)
RETURNS TABLE (student_id uuid, number text, name text, submitted int, marked int, total numeric, weight_marked int)
LANGUAGE sql STABLE AS $$
    WITH roll AS (
        SELECT st.id, coalesce(st.matric_no, st.admission_no) AS number, st.surname || ', ' || st.other_names AS name
          FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id JOIN people.student st ON st.id = r.student_id
         WHERE e.offering_id = p_offering AND e.status IN ('REGISTERED','APPROVED') AND r.status IN ('APPROVED','LOCKED')),
    marks AS (
        SELECT s.student_id, count(*)::int AS submitted, count(s.mark)::int AS marked,
               sum(CASE WHEN s.mark IS NULL THEN 0 ELSE
                   round(least(s.mark, a.out_of) / a.out_of * a.weight * CASE WHEN s.late THEN (100 - a.late_penalty) / 100.0 ELSE 1 END, 2) END) AS total,
               coalesce(sum(a.weight) FILTER (WHERE s.mark IS NOT NULL), 0)::int AS weight_marked
          FROM lms.submission s JOIN lms.assignment a ON a.id = s.assignment_id
         WHERE a.offering_id = p_offering AND a.ended_at IS NULL GROUP BY s.student_id)
    SELECT r.id, r.number, r.name, coalesce(m.submitted, 0), coalesce(m.marked, 0), coalesce(m.total, 0), coalesce(m.weight_marked, 0)
      FROM roll r LEFT JOIN marks m ON m.student_id = r.id ORDER BY r.name
$$;

-- promoted, the total lands in the CA column of the score sheet, as a new version with its reason (V013)
CREATE OR REPLACE FUNCTION lms.promote_ca(p_offering uuid)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE sh assessment.score_sheet; g record; l record; n int := 0; v_ca int;
BEGIN
    SELECT * INTO sh FROM assessment.score_sheet WHERE offering_id = p_offering;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no score sheet exists for this offering yet' USING ERRCODE = '23514',
            HINT = 'The sheet is generated when the examination session is opened; promote the gradebook after that.';
    END IF;
    IF sh.stage <> 'ENTRY' THEN
        RAISE EXCEPTION 'the score sheet has left the lecturer; the gradebook is not promoted into it' USING ERRCODE = '23514',
            HINT = 'A change to a mark now is a return with the reason, or a result query.';
    END IF;
    FOR g IN SELECT * FROM lms.gradebook(p_offering) LOOP
        v_ca := least(40, round(g.total))::int;
        SELECT * INTO l FROM assessment.latest_scores(sh.id) x WHERE x.student_id = g.student_id;
        IF FOUND AND l.ca IS NOT DISTINCT FROM v_ca THEN CONTINUE; END IF;
        INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, outcome, reason)
        VALUES (sh.id, g.student_id, coalesce(l.version, 0) + 1, v_ca, CASE WHEN FOUND THEN l.exam END,
                CASE WHEN FOUND AND l.exam IS NOT NULL THEN 'GRADED' WHEN FOUND THEN l.outcome ELSE 'INCOMPLETE' END,
                CASE WHEN FOUND THEN 'Promoted from the course space gradebook (' || g.total || ' over ' || g.weight_marked || '% marked)' END);
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

COMMIT;
