-- V651: postgraduate stages, cycles, extension, restart and stage-based fees — the University's master prompt of 24 October 2026
-- ("POSTGRADUATE SCHOOL LEVEL, EXTENSION, RESTART & FEE MANAGEMENT MODULE"). A PG student's level (700, 800, 900) is the
-- qualification; within it the student moves through stages, year by year, each with a first and a second semester:
--   PG Diploma  700 Level (year 1), 700 Extension
--   Masters     800 A — Year 1, 800 B — Year 2, 800 C — Extension
--   PhD         900 A, 900 B, 900 C (years 1–3), 900 D — Extension 1, 900 E — Extension 2
-- A student who has not finished at the end of the last extension has exhausted the maximum period; a restart is a new
-- academic cycle, never the old one rewritten. The first stage of a cycle is FRESH for fees, every later one RETURNING.
--
--   · admissions.pg_qualification / admissions.pg_stage: the structure, configurable (normal years, extension years, the
--     stages' labels; codes 700A, 700B, 800A–800C, 900A–900E kept internal), seeded with the University's rules and changed
--     only by admissions.pg_set_qualification (the PG School).
--   · people.pg_cycle (cycle 1, 2, … of a student; ACTIVE, COMPLETED, GRADUATED, MAXIMUM_PERIOD_EXHAUSTED, CLOSED) and
--     people.pg_cycle_stage (the stage of a cycle in a session, recorded by the School: reconciliation, progression,
--     extension, restart, correction). A cycle is never overwritten; a restart opens the next.
--   · admissions.pg_stages_of(session, students): the one reading of a student's stage in a session — the stage recorded for
--     it, else calculated from the last recorded stage (or the start of the cycle) by the sessions the calendar counts since
--     (policy.sessions_elapsed; a cancelled session is not counted); its fresh/returning category; whether the maximum period
--     is passed; and a recommendation (NORMAL_PROGRESS, EXTENSION_REQUIRED, MAXIMUM_PERIOD_REACHED, RESTART_REQUIRED, …).
--     A PG student with no cycle recorded yet is read as cycle 1 from the admission session. Nothing is promoted by itself.
--   · Fee lines name a PG stage (finance.fee_schedule.pg_stage) or a category (fee_category FRESH / RETURNING); every matcher
--     reads the student's stage and category (finance.pg_stage_line), the bulk fee profiles carry them, a copy keeps them.
--   · Progression, extension (APPROVE_PG_EXTENSION), closing a cycle, the restart workflow (requested, recommended by the
--     department, approved by the School, the new cycle at its first stage), the reconciliation of the existing PG students
--     (scan, preview, commit), the data-quality list, the counts by stage, and admissions.pg_grant (who may do what).
--   · finance.payment_pg_context: a PG student's school-fees reference names the cycle, stage and category it was raised under.
-- people.student.current_level stays 700 / 800 / 900: registration, results and the programme structure read it as before.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'pgschool', true),
       set_config('moaum.reason', 'V651: postgraduate stages, cycles, extension, restart and stage-based fees (the University, 24 October 2026)', true);

-- ── the structure: qualifications and their stages ──
CREATE TABLE admissions.pg_qualification (
    code text PRIMARY KEY CHECK (code ~ '^[A-Z_]{2,20}$'),
    label text NOT NULL CHECK (btrim(label) <> ''),
    level integer NOT NULL UNIQUE CHECK (level IN (700, 800, 900)),
    normal_years integer NOT NULL CHECK (normal_years BETWEEN 1 AND 6),
    extension_years integer NOT NULL CHECK (extension_years BETWEEN 0 AND 4),
    restart_allowed boolean NOT NULL DEFAULT true,
    updated_at timestamptz NOT NULL DEFAULT now()
);
SELECT audit.attach('admissions.pg_qualification');
COMMENT ON TABLE admissions.pg_qualification IS
  'V651: a postgraduate qualification (PG Diploma 700, Masters 800, PhD 900) — its normal years and extension years; the maximum period is their sum, after which the student restarts in a new cycle. Changed by admissions.pg_set_qualification.';

CREATE TABLE admissions.pg_stage (
    code text PRIMARY KEY CHECK (code ~ '^[789]00[A-Z]$'),
    qualification text NOT NULL REFERENCES admissions.pg_qualification(code),
    label text NOT NULL CHECK (btrim(label) <> ''),
    short_label text NOT NULL CHECK (btrim(short_label) <> ''),
    sequence integer NOT NULL CHECK (sequence BETWEEN 1 AND 10),
    year_number integer CHECK (year_number BETWEEN 1 AND 6),
    extension_number integer CHECK (extension_number BETWEEN 1 AND 4),
    semesters integer[] NOT NULL DEFAULT '{1,2}',
    active boolean NOT NULL DEFAULT true,
    UNIQUE (qualification, sequence),
    CHECK ((year_number IS NULL) <> (extension_number IS NULL))
);
SELECT audit.attach('admissions.pg_stage');
COMMENT ON TABLE admissions.pg_stage IS
  'V651: a stage of a postgraduate qualification — a year of normal study (year_number) or an extension (extension_number), in order (sequence), each with its semesters. The code is internal (800B); the label is what is shown (800 B — Year 2).';

INSERT INTO admissions.pg_qualification (code, label, level, normal_years, extension_years, restart_allowed) VALUES
    ('PGD', 'Postgraduate Diploma', 700, 1, 1, true),
    ('MASTERS', 'Masters', 800, 2, 1, true),
    ('PHD', 'Doctor of Philosophy', 900, 3, 2, true);
INSERT INTO admissions.pg_stage (code, qualification, label, short_label, sequence, year_number, extension_number) VALUES
    ('700A', 'PGD', '700 Level', '700', 1, 1, NULL),
    ('700B', 'PGD', '700 Extension', '700 Extension', 2, NULL, 1),
    ('800A', 'MASTERS', '800 A — Year 1', '800 A', 1, 1, NULL),
    ('800B', 'MASTERS', '800 B — Year 2', '800 B', 2, 2, NULL),
    ('800C', 'MASTERS', '800 C — Extension', '800 C', 3, NULL, 1),
    ('900A', 'PHD', '900 A — Year 1', '900 A', 1, 1, NULL),
    ('900B', 'PHD', '900 B — Year 2', '900 B', 2, 2, NULL),
    ('900C', 'PHD', '900 C — Year 3', '900 C', 3, 3, NULL),
    ('900D', 'PHD', '900 D — Extension 1', '900 D', 4, NULL, 1),
    ('900E', 'PHD', '900 E — Extension 2', '900 E', 5, NULL, 2);

-- ── who may do what in PG academic management ──
CREATE TABLE admissions.pg_grant (
    office_code text NOT NULL,
    permission text NOT NULL CHECK (permission IN ('VIEW_PG_LEVEL_STRUCTURE', 'MANAGE_PG_LEVEL_STRUCTURE', 'MANAGE_PG_PROGRESSION', 'VIEW_PG_EXTENSION',
                                                   'APPROVE_PG_EXTENSION', 'VIEW_PG_RESTART', 'REQUEST_PG_RESTART', 'RECOMMEND_PG_RESTART',
                                                   'APPROVE_PG_RESTART', 'MANAGE_PG_ACADEMIC_CYCLE', 'VIEW_PG_ACADEMIC_HISTORY')),
    granted_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (office_code, permission)
);
SELECT audit.attach('admissions.pg_grant');
COMMENT ON TABLE admissions.pg_grant IS
  'V651: what each office may do in postgraduate academic management. The Dean of the PG School (and the platform) holds all; the PG Secretary manages progression and cycles but approves no extension or restart; a Head of Department requests and recommends a restart for their department; the reading offices read.';
INSERT INTO admissions.pg_grant (office_code, permission)
SELECT o, p FROM unnest(ARRAY['pgschool', 'super']) o
CROSS JOIN unnest(ARRAY['VIEW_PG_LEVEL_STRUCTURE', 'MANAGE_PG_LEVEL_STRUCTURE', 'MANAGE_PG_PROGRESSION', 'VIEW_PG_EXTENSION', 'APPROVE_PG_EXTENSION',
                        'VIEW_PG_RESTART', 'REQUEST_PG_RESTART', 'RECOMMEND_PG_RESTART', 'APPROVE_PG_RESTART', 'MANAGE_PG_ACADEMIC_CYCLE',
                        'VIEW_PG_ACADEMIC_HISTORY']) p
UNION ALL
SELECT 'pgsecretary', p FROM unnest(ARRAY['VIEW_PG_LEVEL_STRUCTURE', 'MANAGE_PG_PROGRESSION', 'VIEW_PG_EXTENSION', 'VIEW_PG_RESTART', 'REQUEST_PG_RESTART',
                                          'RECOMMEND_PG_RESTART', 'MANAGE_PG_ACADEMIC_CYCLE', 'VIEW_PG_ACADEMIC_HISTORY']) p
UNION ALL
SELECT 'hod', p FROM unnest(ARRAY['VIEW_PG_LEVEL_STRUCTURE', 'VIEW_PG_EXTENSION', 'VIEW_PG_RESTART', 'REQUEST_PG_RESTART', 'RECOMMEND_PG_RESTART',
                                  'VIEW_PG_ACADEMIC_HISTORY']) p
UNION ALL
SELECT o, p FROM unnest(ARRAY['academic', 'registrar', 'dregistrar', 'dean', 'vc', 'dvc', 'ict', 'admin', 'records']) o
CROSS JOIN unnest(ARRAY['VIEW_PG_LEVEL_STRUCTURE', 'VIEW_PG_EXTENSION', 'VIEW_PG_RESTART', 'VIEW_PG_ACADEMIC_HISTORY']) p
UNION ALL
SELECT o, p FROM unnest(ARRAY['bursar', 'studentaccounts', 'audit', 'deputyaudit']) o
CROSS JOIN unnest(ARRAY['VIEW_PG_LEVEL_STRUCTURE', 'VIEW_PG_ACADEMIC_HISTORY']) p
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION admissions.pg_permissions(p_office text)
RETURNS text[]
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce((SELECT array_agg(g.permission ORDER BY g.permission) FROM admissions.pg_grant g WHERE g.office_code = p_office), '{}')
$$;

CREATE OR REPLACE FUNCTION admissions.pg_may(p_office text, p_permission text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (SELECT 1 FROM admissions.pg_grant g WHERE g.office_code = coalesce(p_office, '') AND g.permission = p_permission)
$$;

CREATE OR REPLACE FUNCTION admissions.pg_require(p_permission text)
RETURNS void
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF NOT admissions.pg_may(nullif(current_setting('moaum.actor_office', true), ''), p_permission) THEN
        RAISE EXCEPTION 'PG_NOT_PERMITTED: your office does not hold % in postgraduate academic management', p_permission USING ERRCODE = '42501';
    END IF;
END $$;

-- the qualification a PG programme leads to: by the level its name gives (people.pg_level_of — PhD 900, PG Diploma 700, else 800)
CREATE OR REPLACE FUNCTION admissions.pg_qualification_of(p_programme text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT q.code FROM admissions.pg_qualification q WHERE q.level = people.pg_level_of(p_programme)
$$;

-- ── a student's academic cycles and the stage of each session ──
CREATE TABLE people.pg_cycle (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    cycle_no integer NOT NULL CHECK (cycle_no >= 1),
    qualification text NOT NULL REFERENCES admissions.pg_qualification(code),
    programme_code text NOT NULL REFERENCES ref.programme(code),
    start_session text NOT NULL CHECK (start_session ~ '^[0-9]{4}/[0-9]{4}$'),
    status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'COMPLETED', 'GRADUATED', 'MAXIMUM_PERIOD_EXHAUSTED', 'CLOSED')),
    status_reason text,
    status_at timestamptz,
    status_by uuid,
    source text NOT NULL CHECK (source IN ('RECONCILIATION', 'ADMISSION', 'RESTART')),
    restart_of uuid REFERENCES people.pg_cycle(id),
    created_by uuid,
    created_office text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (student_id, cycle_no)
);
CREATE UNIQUE INDEX ux_pg_cycle_one_active ON people.pg_cycle (student_id) WHERE status = 'ACTIVE';
SELECT audit.attach('people.pg_cycle');
-- a programme merge (V574) moves a cycle with its students, each row recorded so the merge can be undone
INSERT INTO ref.programme_reference (tab, col, policy, note)
VALUES ('people.pg_cycle', 'programme_code', 'MOVE', 'a postgraduate cycle: it follows its students into the kept programme');
COMMENT ON TABLE people.pg_cycle IS
  'V651: a postgraduate academic cycle — cycle 1 from admission, a later one on an approved restart. Never overwritten or deleted (but with the student by the go-live reset); its status is changed by admissions.pg_close_cycle and an approved restart. One ACTIVE cycle a student.';

CREATE TABLE people.pg_cycle_stage (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    cycle_id uuid NOT NULL REFERENCES people.pg_cycle(id) ON DELETE CASCADE,
    session text NOT NULL CHECK (session ~ '^[0-9]{4}/[0-9]{4}$'),
    stage_code text NOT NULL REFERENCES admissions.pg_stage(code),
    source text NOT NULL CHECK (source IN ('RECONCILIATION', 'PROGRESSION', 'EXTENSION', 'RESTART', 'CORRECTION', 'ADMISSION')),
    reason text,
    decided_by uuid,
    decided_office text,
    at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (cycle_id, session)
);
CREATE INDEX ix_pg_cycle_stage_session ON people.pg_cycle_stage (session, stage_code);
SELECT audit.attach('people.pg_cycle_stage');
COMMENT ON TABLE people.pg_cycle_stage IS
  'V651: the stage of a postgraduate cycle in a session, recorded by the PG School (admissions.pg_record_stage); a correction rewrites the session''s row, the audit trail keeping what it was.';

-- ── the stage of a student in a session: recorded, else calculated; fresh or returning; the recommendation ──
-- the reading, for the students named (driven from their ids, so one student is one index read). Set-based throughout: the
-- calendar read once (a session's year, the cancelled sessions between two — what policy.sessions_elapsed counts), each student's
-- latest cycle and latest recorded stage found by DISTINCT ON, the qualification read once a programme
CREATE OR REPLACE FUNCTION admissions.pg_stages_read(p_session text, p_ids uuid[])
RETURNS TABLE(student_id uuid, cycle_id uuid, cycle_no integer, qualification text, programme_code text, start_session text,
              cycle_status text, stage_code text, stage_label text, stage_seq integer, stages integer, is_extension boolean,
              official boolean, category text, beyond boolean, recommendation text)
LANGUAGE sql
STABLE
AS $$
    WITH sy AS MATERIALIZED (SELECT CASE WHEN p_session ~ '^[0-9]{4}/[0-9]{4}$' THEN left(p_session, 4)::int END AS y),
    cancelled AS MATERIALIZED (SELECT left(a.name, 4)::int AS y FROM policy.academic_session a WHERE a.state = 'CANCELLED' AND a.name ~ '^[0-9]{4}/[0-9]{4}$'),
    s AS MATERIALIZED (
        SELECT st.id, st.programme_code, st.entry_session, st.status
          FROM unnest(p_ids) u(id)
          JOIN people.student st ON st.id = u.id
          JOIN ref.programme p ON p.code = st.programme_code
         WHERE people.is_postgraduate(st.entry_mode, p.category)),
    progq AS MATERIALIZED (SELECT d.programme_code, admissions.pg_qualification_of(d.programme_code) AS qualification
                             FROM (SELECT DISTINCT s.programme_code FROM s) d),
    q AS MATERIALIZED (
        SELECT pq.code, pq.restart_allowed,
               (SELECT count(*) FROM admissions.pg_stage x WHERE x.qualification = pq.code AND x.active)::int AS n
          FROM admissions.pg_qualification pq),
    lastc AS MATERIALIZED (
        -- the cycle covering the session: the latest begun on or before it
        SELECT DISTINCT ON (c.student_id) c.student_id, c.id, c.cycle_no, c.qualification, c.programme_code, c.start_session, c.status,
               EXISTS (SELECT 1 FROM people.pg_cycle n WHERE n.student_id = c.student_id AND n.cycle_no > c.cycle_no) AS restarted
          FROM people.pg_cycle c JOIN s ON s.id = c.student_id CROSS JOIN sy
         WHERE left(c.start_session, 4)::int <= sy.y
         ORDER BY c.student_id, c.cycle_no DESC),
    cyc AS (
        -- with none recorded, the admission read as cycle 1
        SELECT s.id AS student_id, c.id AS cycle_id, coalesce(c.cycle_no, 1) AS cycle_no, coalesce(c.qualification, pq.qualification) AS qualification,
               coalesce(c.programme_code, s.programme_code) AS programme_code, coalesce(c.start_session, s.entry_session) AS start_session,
               coalesce(c.status, 'NOT_RECORDED') AS cycle_status, coalesce(c.restarted, false) AS restarted, s.status AS student_status
          FROM s
          LEFT JOIN lastc c ON c.student_id = s.id
          LEFT JOIN progq pq ON pq.programme_code = s.programme_code),
    laststage AS MATERIALIZED (
        -- the stage recorded for the session, else the latest recorded before it
        SELECT DISTINCT ON (cs.cycle_id) cs.cycle_id, cs.session, bs.sequence
          FROM people.pg_cycle_stage cs JOIN lastc c ON c.id = cs.cycle_id JOIN admissions.pg_stage bs ON bs.code = cs.stage_code CROSS JOIN sy
         WHERE left(cs.session, 4)::int <= sy.y
         ORDER BY cs.cycle_id, left(cs.session, 4)::int DESC),
    sq AS (
        SELECT cy.*, b.session IS NOT DISTINCT FROM p_session AS official,
               CASE WHEN b.session = p_session THEN b.sequence
                    WHEN b.sequence IS NOT NULL
                         THEN b.sequence + (sy.y - left(b.session, 4)::int) - (SELECT count(*) FROM cancelled k WHERE k.y > left(b.session, 4)::int AND k.y <= sy.y)::int
                    WHEN cy.start_session ~ '^[0-9]{4}/[0-9]{4}$'
                         THEN 1 + (sy.y - left(cy.start_session, 4)::int)
                              - CASE WHEN sy.y >= left(cy.start_session, 4)::int
                                     THEN (SELECT count(*) FROM cancelled k WHERE k.y > left(cy.start_session, 4)::int AND k.y <= sy.y)::int
                                     ELSE -(SELECT count(*) FROM cancelled k WHERE k.y > sy.y AND k.y <= left(cy.start_session, 4)::int)::int END
                    END AS seq
          FROM cyc cy CROSS JOIN sy
          LEFT JOIN laststage b ON b.cycle_id = cy.cycle_id)
    SELECT x.student_id, x.cycle_id, x.cycle_no, x.qualification, x.programme_code, x.start_session, x.cycle_status,
           st.code, st.label, x.seq, q.n, st.extension_number IS NOT NULL, x.official,
           CASE WHEN x.seq IS NULL OR x.seq < 1 THEN NULL WHEN x.seq = 1 THEN 'FRESH' ELSE 'RETURNING' END,
           coalesce(x.seq > q.n, false),
           CASE WHEN x.student_status = 'GRADUATED' OR x.cycle_status IN ('GRADUATED', 'COMPLETED') THEN 'COMPLETED'
                -- a closed cycle a later one follows (the restart approved, its cycle not yet begun) needs nothing more
                WHEN x.cycle_status IN ('MAXIMUM_PERIOD_EXHAUSTED', 'CLOSED') THEN CASE WHEN q.restart_allowed AND NOT x.restarted THEN 'RESTART_REQUIRED' ELSE 'CLOSED' END
                WHEN x.qualification IS NULL OR x.seq IS NULL THEN 'UNKNOWN'
                WHEN x.seq < 1 THEN 'NOT_STARTED'
                WHEN x.seq > q.n THEN 'MAXIMUM_PERIOD_REACHED'
                WHEN st.extension_number IS NOT NULL THEN CASE WHEN x.official THEN 'EXTENSION' ELSE 'EXTENSION_REQUIRED' END
                ELSE 'NORMAL_PROGRESS' END
      FROM sq x
      LEFT JOIN q ON q.code = x.qualification
      LEFT JOIN admissions.pg_stage st ON st.qualification = x.qualification AND st.sequence = x.seq AND st.active
$$;

-- the one entry: every PG student, or those named. PL/pgSQL on purpose — the reading is never folded into a caller's query,
-- whose estimates it would throw off (the bulk fee sums went from 0.3 s to 5 s when it was)
CREATE OR REPLACE FUNCTION admissions.pg_stages_of(p_session text, p_students uuid[] DEFAULT NULL)
RETURNS TABLE(student_id uuid, cycle_id uuid, cycle_no integer, qualification text, programme_code text, start_session text,
              cycle_status text, stage_code text, stage_label text, stage_seq integer, stages integer, is_extension boolean,
              official boolean, category text, beyond boolean, recommendation text)
LANGUAGE plpgsql
STABLE
ROWS 1000
AS $$
DECLARE v_ids uuid[] := p_students;
BEGIN
    IF v_ids IS NULL THEN
        SELECT array_agg(st.id) INTO v_ids FROM people.student st JOIN ref.programme p ON p.code = st.programme_code
         WHERE people.is_postgraduate(st.entry_mode, p.category);
    END IF;
    IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
        RETURN;
    END IF;
    RETURN QUERY SELECT * FROM admissions.pg_stages_read(p_session, v_ids);
END $$;
COMMENT ON FUNCTION admissions.pg_stages_of(text, uuid[]) IS
  'V651: each PG student''s stage in a session (all of them, or those named) — recorded (official), else calculated from the last recorded stage or the start of the cycle by the sessions the calendar counts since; FRESH at the first stage of a cycle, RETURNING after; beyond when the maximum period is passed; and the recommendation. The fee engine, registration readings, dashboards and reports read it.';

-- a fee line for a PG stage, or for fresh or returning PG students, reaches only them
CREATE OR REPLACE FUNCTION finance.pg_stage_line(p_line_stage text, p_line_category text, p_stage text, p_category text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT (p_line_stage IS NULL OR p_line_stage = p_stage) AND (p_line_category IS NULL OR p_line_category = p_category)
$$;

-- ── fee lines by PG stage and category ──
ALTER TABLE finance.fee_schedule ADD COLUMN pg_stage text REFERENCES admissions.pg_stage(code);
ALTER TABLE finance.fee_schedule ADD COLUMN fee_category text CHECK (fee_category IS NULL OR fee_category IN ('FRESH', 'RETURNING'));
COMMENT ON COLUMN finance.fee_schedule.pg_stage IS 'V651: the postgraduate stage the line is for (800B — Year 2); its level is the stage''s qualification level, its category the stage''s (FRESH at the first stage).';
COMMENT ON COLUMN finance.fee_schedule.fee_category IS 'V651: FRESH (the first stage of a PG cycle) or RETURNING; on a postgraduate line only.';

CREATE OR REPLACE FUNCTION finance.trg_fee_line_pg()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE st admissions.pg_stage; v_level int;
BEGIN
    IF NEW.pg_stage IS NOT NULL THEN
        SELECT * INTO st FROM admissions.pg_stage WHERE code = NEW.pg_stage;
        SELECT q.level INTO v_level FROM admissions.pg_qualification q WHERE q.code = st.qualification;
        IF TG_OP = 'INSERT' AND NOT st.active THEN
            RAISE EXCEPTION 'FEE_PG_STAGE: % is not a stage in use', st.label USING ERRCODE = '23514';
        END IF;
        NEW.level := coalesce(NEW.level, v_level);
        IF NEW.level <> v_level THEN
            RAISE EXCEPTION 'FEE_PG_STAGE_LEVEL: % is a % Level stage, not % Level', st.label, v_level, NEW.level USING ERRCODE = '23514';
        END IF;
        IF NEW.spillover THEN
            RAISE EXCEPTION 'FEE_PG_STAGE_SPILLOVER: a postgraduate stage line is not a spillover line' USING ERRCODE = '23514';
        END IF;
        -- a stage line names a postgraduate programme (one of the School's, or one a postgraduate student is on)
        IF NEW.programme_code IS NOT NULL AND NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = NEW.programme_code AND p.category = 'POST GRADUATE')
           AND NOT EXISTS (SELECT 1 FROM people.student x WHERE x.programme_code = NEW.programme_code AND x.entry_mode = 'POSTGRADUATE') THEN
            RAISE EXCEPTION 'FEE_PG_STAGE_PROGRAMME: % is not a postgraduate programme', NEW.programme_code USING ERRCODE = '23514';
        END IF;
        IF NEW.programme_code IS NOT NULL AND admissions.pg_qualification_of(NEW.programme_code) IS DISTINCT FROM st.qualification THEN
            RAISE EXCEPTION 'FEE_PG_STAGE_PROGRAMME: % is not a stage of the programme''s qualification', st.label USING ERRCODE = '23514';
        END IF;
        IF NEW.fee_category IS NOT NULL AND NEW.fee_category <> (CASE WHEN st.sequence = 1 THEN 'FRESH' ELSE 'RETURNING' END) THEN
            RAISE EXCEPTION 'FEE_PG_STAGE_CATEGORY: % is %', st.label, (CASE WHEN st.sequence = 1 THEN 'the first stage: its students are FRESH' ELSE 'a later stage: its students are RETURNING' END)
                USING ERRCODE = '23514';
        END IF;
        NEW.fee_category := CASE WHEN st.sequence = 1 THEN 'FRESH' ELSE 'RETURNING' END;
    ELSIF NEW.fee_category IS NOT NULL
          AND NOT (coalesce(NEW.level, 0) IN (700, 800, 900) OR NEW.entry_mode IS NOT DISTINCT FROM 'POSTGRADUATE'
                   OR EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = NEW.programme_code AND p.category = 'POST GRADUATE')
                   OR EXISTS (SELECT 1 FROM ref.fee_group g WHERE g.code = NEW.fee_group AND g.applies_category = 'POST GRADUATE')) THEN
        RAISE EXCEPTION 'FEE_PG_CATEGORY: fresh and returning are postgraduate categories — the line names a PG level, the Postgraduate entry mode, a PG programme or the PG group'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_fee_line_pg BEFORE INSERT OR UPDATE OF pg_stage, fee_category, level, spillover ON finance.fee_schedule
    FOR EACH ROW EXECUTE FUNCTION finance.trg_fee_line_pg();

-- ═══ the fee functions restated (V651): the PG stage and category read beside every other fact a line is matched on ═══

-- charges_of_as: restated with the student's PG stage and category (V651)
CREATE OR REPLACE FUNCTION finance.charges_of_as(p_student uuid, p_session text, p_kinds text[], p_programme text, p_any_semester boolean DEFAULT false)
 RETURNS TABLE(id uuid, item text, amount numeric, ord integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS MATERIALIZED (   -- V451: read once, not once per fee line
        SELECT s.id, coalesce(p_programme, s.programme_code) AS programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               finance.spill(s.id, s.current_level, coalesce(p_programme, s.programme_code), s.status) AS is_spill,
               finance.spill_year(s.id, s.current_level, coalesce(p_programme, s.programme_code), s.status) AS spill_year,   -- V613: SP1, SP2, SP3 (NULL when not in spillover)
               finance.final_level(coalesce(p_programme, s.programme_code)) AS final_level,   -- V613: the level a spillover line names
               finance.reg_semesters(s.id, p_session) AS reg_sems,   -- V616: the semesters the student has registered a course in
               (SELECT finance.fee_source_of(pp.faculty_code, p_session) FROM ref.programme pp
                 WHERE pp.code = coalesce(p_programme, s.programme_code) AND s.entry_mode IS DISTINCT FROM 'CCE'
                   AND NOT people.is_postgraduate(s.entry_mode, pp.category)) AS src,   -- V451: the faculty charged as, while a rule is in force
               pgs.stage_code AS pg_stage, pgs.category AS pg_category   -- V651: the student's PG stage and fresh/returning in the session
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          LEFT JOIN LATERAL (SELECT x.stage_code, x.category FROM admissions.pg_stages_of(p_session, ARRAY[s.id]) x) pgs ON true   -- V651
         WHERE s.id = p_student)
    SELECT f.id,
           replace(replace(replace(f.item,
               '(semester 1)', '(First Semester)'),
               '(semester 2)', '(Second Semester)'),
               '(semester 3)', '(Third Semester)') AS item,
           f.amount, f.ord
      FROM finance.fee_schedule f
      CROSS JOIN me
      JOIN ref.programme p ON p.code = me.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
      CROSS JOIN home
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND f.kind = ANY (p_kinds)
       AND f.spillover = me.is_spill
       AND (f.level IS NULL OR f.level = CASE WHEN me.is_spill THEN me.final_level ELSE me.current_level END)   -- V613: on a spillover line the level is the programme's final level
       AND (f.spill_year IS NULL OR f.spill_year = me.spill_year)   -- V613: SP1, SP2, SP3, or any spillover year
       AND (p_any_semester OR finance.spill_line_applies(me.is_spill, f.semester, me.reg_sems))   -- V616: a spillover student is charged a semester's line once they register a course in it; a whole-session line once any
       AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code OR (f.faculty_code = me.src AND f.programme_code IS NULL))
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND finance.pg_line(me.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)   -- V391: a full-time line never reaches a postgraduate student
       AND finance.pg_stage_line(f.pg_stage, f.fee_category, me.pg_stage, me.pg_category)   -- V651: a line for a PG stage, or for fresh or returning PG students, reaches only them
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)))
       AND (f.semester IS NULL
            OR f.semester <= coalesce((SELECT max(sm.number) FROM policy.semester sm
                                        WHERE sm.session = p_session AND sm.state = 'OPEN'), 3))
     ORDER BY f.ord, f.item;
$function$;

-- fee_stated: restated with the student's PG stage and category (V651)
CREATE OR REPLACE FUNCTION finance.fee_stated(p_student uuid, p_session text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS MATERIALIZED (   -- V451: read once, not once per fee line
        SELECT s.id, s.programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               finance.spill(s.id, s.current_level, s.programme_code, s.status) AS is_spill,
               finance.spill_year(s.id, s.current_level, s.programme_code, s.status) AS spill_year,   -- V613: SP1, SP2, SP3 (NULL when not in spillover)
               finance.final_level(s.programme_code) AS final_level,   -- V613: the level a spillover line names
               (SELECT finance.fee_source_of(pp.faculty_code, p_session) FROM ref.programme pp
                 WHERE pp.code = s.programme_code AND s.entry_mode IS DISTINCT FROM 'CCE'
                   AND NOT people.is_postgraduate(s.entry_mode, pp.category)) AS src,   -- V451: the faculty charged as, while a rule is in force
               pgs.stage_code AS pg_stage, pgs.category AS pg_category   -- V651: the student's PG stage and fresh/returning in the session
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          LEFT JOIN LATERAL (SELECT x.stage_code, x.category FROM admissions.pg_stages_of(p_session, ARRAY[s.id]) x) pgs ON true   -- V651
         WHERE s.id = p_student)
    SELECT (p_session < coalesce(finance.schedule_from(), p_session) AND (SELECT me.entry_mode FROM me) IS DISTINCT FROM 'CCE')
        OR EXISTS (
        SELECT 1
          FROM finance.fee_schedule f
          CROSS JOIN me
          JOIN ref.programme p ON p.code = me.programme_code
          LEFT JOIN ref.fee_group g ON g.code = f.fee_group
          LEFT JOIN home ON true
         WHERE f.session = p_session AND f.ended_at IS NULL AND f.kind = 'FEE'
           AND f.spillover = me.is_spill
           AND (f.level IS NULL OR f.level = CASE WHEN me.is_spill THEN me.final_level ELSE me.current_level END)   -- V613: on a spillover line the level is the programme's final level
           AND (f.spill_year IS NULL OR f.spill_year = me.spill_year)   -- V613: SP1, SP2, SP3, or any spillover year
           AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
           AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code OR (f.faculty_code = me.src AND f.programme_code IS NULL))
           AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
           AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
           AND finance.pg_line(me.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)   -- V391: a full-time line never reaches a postgraduate student
           AND finance.pg_stage_line(f.pg_stage, f.fee_category, me.pg_stage, me.pg_category)   -- V651: a line for a PG stage, or for fresh or returning PG students, reaches only them
           AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state))))
$function$;

-- due_for_semester: restated with the student's PG stage and category (V651)
CREATE OR REPLACE FUNCTION finance.due_for_semester(p_student uuid, p_session text, p_semester integer)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS MATERIALIZED (   -- V451: read once, not once per fee line
        SELECT s.id, s.programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               finance.spill(s.id, s.current_level, s.programme_code, s.status) AS is_spill,
               finance.spill_year(s.id, s.current_level, s.programme_code, s.status) AS spill_year,   -- V613: SP1, SP2, SP3 (NULL when not in spillover)
               finance.final_level(s.programme_code) AS final_level,   -- V613: the level a spillover line names
               finance.reg_semesters(s.id, p_session) AS reg_sems,   -- V616
               (SELECT finance.fee_source_of(pp.faculty_code, p_session) FROM ref.programme pp
                 WHERE pp.code = s.programme_code AND s.entry_mode IS DISTINCT FROM 'CCE'
                   AND NOT people.is_postgraduate(s.entry_mode, pp.category)) AS src,   -- V451: the faculty charged as, while a rule is in force
               pgs.stage_code AS pg_stage, pgs.category AS pg_category   -- V651: the student's PG stage and fresh/returning in the session
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          LEFT JOIN LATERAL (SELECT x.stage_code, x.category FROM admissions.pg_stages_of(p_session, ARRAY[s.id]) x) pgs ON true   -- V651
         WHERE s.id = p_student)
    SELECT coalesce(sum(f.amount), 0)
      FROM finance.fee_schedule f
      CROSS JOIN me
      JOIN ref.programme p ON p.code = me.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
      CROSS JOIN home
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND f.spillover = me.is_spill
       AND (f.level IS NULL OR f.level = CASE WHEN me.is_spill THEN me.final_level ELSE me.current_level END)   -- V613: on a spillover line the level is the programme's final level
       AND (f.spill_year IS NULL OR f.spill_year = me.spill_year)   -- V613: SP1, SP2, SP3, or any spillover year
       AND finance.spill_line_applies(me.is_spill, f.semester, me.reg_sems)   -- V616: a spillover student is charged a semester's line once they register a course in it; a whole-session line once any
       AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code OR (f.faculty_code = me.src AND f.programme_code IS NULL))
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND finance.pg_line(me.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)   -- V391: a full-time line never reaches a postgraduate student
       AND finance.pg_stage_line(f.pg_stage, f.fee_category, me.pg_stage, me.pg_category)   -- V651: a line for a PG stage, or for fresh or returning PG students, reaches only them
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)))
       AND (f.semester IS NULL OR f.semester <= p_semester);
$function$;

-- session_fee_total: restated with the student's PG stage and category (V651)
CREATE OR REPLACE FUNCTION finance.session_fee_total(p_student uuid, p_session text)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS MATERIALIZED (   -- V451: read once, not once per fee line
        SELECT s.id, s.programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               (SELECT finance.fee_source_of(pp.faculty_code, p_session) FROM ref.programme pp
                 WHERE pp.code = s.programme_code AND s.entry_mode IS DISTINCT FROM 'CCE'
                   AND NOT people.is_postgraduate(s.entry_mode, pp.category)) AS src,   -- V451: the faculty charged as, while a rule is in force
               pgs.stage_code AS pg_stage, pgs.category AS pg_category   -- V651: the student's PG stage and fresh/returning in the session
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          LEFT JOIN LATERAL (SELECT x.stage_code, x.category FROM admissions.pg_stages_of(p_session, ARRAY[s.id]) x) pgs ON true   -- V651
         WHERE s.id = p_student)
    SELECT coalesce(sum(f.amount), 0)
      FROM finance.fee_schedule f
      CROSS JOIN me
      JOIN ref.programme p ON p.code = me.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
      CROSS JOIN home
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND (f.level IS NULL OR f.level = me.current_level)
       AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code OR (f.faculty_code = me.src AND f.programme_code IS NULL))
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND finance.pg_line(me.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)   -- V391: a full-time line never reaches a postgraduate student
       AND finance.pg_stage_line(f.pg_stage, f.fee_category, me.pg_stage, me.pg_category)   -- V651: a line for a PG stage, or for fresh or returning PG students, reaches only them
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)));
$function$;

-- fee_profiles: a profile carries the PG stage and category (V651); the result gains two columns, so the functions are made again
DROP FUNCTION finance.fee_profiles();
DROP FUNCTION finance.fee_profiles(text);
CREATE FUNCTION finance.fee_profiles(p_session text)
 RETURNS TABLE(student_id uuid, status text, programme_code text, faculty_code text, category text, current_level integer, entry_mode text, state text, is_spill boolean, spill_year integer, final_level integer, reg_sems integer[], pg_stage text, pg_category text, profile_key text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V537: each programme's final level read once (456 calls), not twice for every student: on a connection the portal has
    -- used a while, PostgreSQL 18 reads finance.final_level by a cached generic plan that costs about seven times as much a call
    WITH fl AS MATERIALIZED (SELECT pr.code, finance.final_level(pr.code) AS final FROM ref.programme pr),
    -- V571: the Bursary's basis for the spillover lines, read once (LEVEL: above the final level; COHORT: the cohort engine's spillover)
    basis AS MATERIALIZED (SELECT finance.spill_basis() AS b),
    -- V616: the semesters each student has registered a course in, for the session asked — read once over the session's registrations
    regs AS MATERIALIZED (
        SELECT cr.student_id, array_agg(DISTINCT cr.semester ORDER BY cr.semester) AS sems
          FROM registration.course_registration cr
         WHERE cr.session = p_session AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))
         GROUP BY cr.student_id),
    -- V651: each PG student's stage and fresh/returning in the session, read once for all
    pgs AS MATERIALIZED (SELECT x.student_id, x.stage_code, x.category FROM admissions.pg_stages_of(p_session, NULL) x)
    SELECT s.id, s.status, s.programme_code, p.faculty_code, p.category, s.current_level, s.entry_mode,
           lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
           (s.status <> 'GRADUATED' AND CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                                                ELSE coalesce(s.current_level > fl.final OR (s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%'), false) END) AS is_spill,
           CASE WHEN s.status = 'GRADUATED' THEN NULL
                WHEN basis.b = 'COHORT' THEN CASE WHEN ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END
                WHEN s.current_level > fl.final THEN least((s.current_level - fl.final) / 100, 3)
                     WHEN s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END AS spill_year,   -- V613
           fl.final AS final_level,   -- V613
           CASE WHEN s.status <> 'GRADUATED' AND CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                                                    ELSE coalesce(s.current_level > fl.final OR (s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%'), false) END
                THEN coalesce(rg.sems, '{}'::int[]) END AS reg_sems,   -- V616: NULL for a student not in spillover
           pgs.stage_code AS pg_stage, pgs.category AS pg_category,   -- V651
           concat_ws('|', s.programme_code, s.current_level, s.entry_mode,
                     lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))),
                     (s.status <> 'GRADUATED' AND CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                                                ELSE coalesce(s.current_level > fl.final OR (s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%'), false) END),
                     CASE WHEN s.status = 'GRADUATED' THEN NULL
                          WHEN basis.b = 'COHORT' THEN CASE WHEN ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END
                          WHEN s.current_level > fl.final THEN least((s.current_level - fl.final) / 100, 3)
                     WHEN s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END,
                     CASE WHEN s.status <> 'GRADUATED' AND CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                                                              ELSE coalesce(s.current_level > fl.final OR (s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%'), false) END
                          THEN coalesce(rg.sems, '{}'::int[])::text END,
                     pgs.stage_code, pgs.category) AS profile_key   -- V613: the spillover year, V616: the registered semesters, are part of a spillover profile
      FROM people.student s
      JOIN ref.programme p ON p.code = s.programme_code
      JOIN fl ON fl.code = s.programme_code
      CROSS JOIN basis
      LEFT JOIN people.academic_position ap ON ap.student_id = s.id
      LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
      LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
      LEFT JOIN regs rg ON rg.student_id = s.id
      LEFT JOIN pgs ON pgs.student_id = s.id
$function$;

CREATE FUNCTION finance.fee_profiles()
 RETURNS TABLE(student_id uuid, status text, programme_code text, faculty_code text, category text, current_level integer, entry_mode text, state text, is_spill boolean, spill_year integer, final_level integer, reg_sems integer[], pg_stage text, pg_category text, profile_key text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT * FROM finance.fee_profiles(policy.university_current_session())
$function$;

-- fee_sums: restated with the profile's PG stage and category (V651)
CREATE OR REPLACE FUNCTION finance.fee_sums(p_session text, p_semester integer)
 RETURNS TABLE(profile_key text, due_before numeric, due_upto numeric, fee numeric, late_payment numeric, late_registration numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT lower(home_state) AS home_state FROM finance.fee_setting WHERE id = 1),
    open_max AS (SELECT coalesce((SELECT max(sm.number) FROM policy.semester sm WHERE sm.session = p_session AND sm.state = 'OPEN'), 3) AS n),
    prof AS MATERIALIZED (SELECT x.*, fs.source_code AS src   -- V451: the faculty a profile is charged as, while a rule is in force
               FROM (SELECT DISTINCT pr.profile_key, pr.programme_code, pr.faculty_code, pr.category, pr.current_level, pr.entry_mode, pr.state, pr.is_spill, pr.spill_year, pr.final_level, pr.reg_sems, pr.pg_stage, pr.pg_category
                       FROM finance.fee_profiles(p_session) pr) x
               LEFT JOIN finance.fee_sources(p_session) fs ON fs.faculty_code = x.faculty_code AND x.entry_mode IS DISTINCT FROM 'CCE' AND NOT people.is_postgraduate(x.entry_mode, x.category)),
    matched AS (
        SELECT pr.profile_key, f.kind, f.semester, f.amount
          FROM prof pr
          CROSS JOIN home
          JOIN finance.fee_schedule f ON f.session = p_session AND f.ended_at IS NULL
          LEFT JOIN ref.fee_group g ON g.code = f.fee_group
         WHERE f.spillover = pr.is_spill
           AND (f.level IS NULL OR f.level = CASE WHEN pr.is_spill THEN pr.final_level ELSE pr.current_level END)   -- V613: on a spillover line the level is the programme's final level
           AND (f.spill_year IS NULL OR f.spill_year = pr.spill_year)   -- V613: SP1, SP2, SP3, or any spillover year
           AND finance.spill_line_applies(pr.is_spill, f.semester, coalesce(pr.reg_sems, '{}'::int[]))   -- V616: a spillover student is charged a semester's line once they register a course in it; a whole-session line once any
           AND ((f.entry_mode IS NULL AND pr.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = pr.entry_mode)   -- V379
           AND (f.faculty_code IS NULL OR f.faculty_code = pr.faculty_code OR (f.faculty_code = pr.src AND f.programme_code IS NULL))
           AND (f.programme_code IS NULL OR f.programme_code = pr.programme_code)
           AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = pr.category)
           AND finance.pg_line(pr.entry_mode = 'POSTGRADUATE' OR pr.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)   -- V391: a full-time line never reaches a postgraduate student
           AND finance.pg_stage_line(f.pg_stage, f.fee_category, pr.pg_stage, pr.pg_category)   -- V651
           AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (pr.state = home.home_state)))
    SELECT m.profile_key,
           CASE WHEN p_semester IS NULL OR p_semester <= 1 THEN 0
                ELSE coalesce(sum(m.amount) FILTER (WHERE m.semester IS NULL OR m.semester <= p_semester - 1), 0) END,
           CASE WHEN p_semester IS NULL THEN coalesce(sum(m.amount) FILTER (WHERE m.semester IS NULL OR m.semester <= 3), 0)
                ELSE coalesce(sum(m.amount) FILTER (WHERE m.semester IS NULL OR m.semester <= p_semester), 0) END,
           coalesce(sum(m.amount) FILTER (WHERE m.kind = 'FEE' AND (m.semester IS NULL OR m.semester <= (SELECT n FROM open_max))), 0),
           coalesce(sum(m.amount) FILTER (WHERE m.kind = 'LATE_PAYMENT' AND (m.semester IS NULL OR m.semester <= (SELECT n FROM open_max))), 0),
           coalesce(sum(m.amount) FILTER (WHERE m.kind = 'LATE_REGISTRATION' AND (m.semester IS NULL OR m.semester <= (SELECT n FROM open_max))), 0)
      FROM matched m
     GROUP BY m.profile_key
$function$;

-- fee_positions_of: alike students share the PG stage and category too (V651)
CREATE OR REPLACE FUNCTION finance.fee_positions_of(p_session text, p_students uuid[])
 RETURNS TABLE(student_id uuid, stated boolean, due numeric, paid numeric, balance numeric, instalments_paid integer, paid_in_full boolean, has_arrears boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH them AS MATERIALIZED (SELECT DISTINCT x AS id FROM unnest(p_students) x WHERE x IS NOT NULL),
    prof AS MATERIALIZED (   -- the fee schedule's answers depend only on the fee profile (V524)
        SELECT t.id AS student_id,
               CASE WHEN fp.student_id IS NULL THEN t.id::text
                    ELSE row(fp.programme_code, fp.current_level, fp.entry_mode, fp.state, fp.is_spill, fp.spill_year, fp.reg_sems, fp.pg_stage, fp.pg_category)::text END AS k   -- V613/V616: the year and the registered semesters tell spillover profiles apart
          FROM them t LEFT JOIN finance.fee_profiles(p_session) fp ON fp.student_id = t.id),
    said AS MATERIALIZED (
        SELECT r.k, finance.fee_stated(r.student_id, p_session) AS stated
          FROM (SELECT DISTINCT ON (p.k) p.k, p.student_id FROM prof p ORDER BY p.k, p.student_id) r),
    pos AS MATERIALIZED (SELECT f.* FROM finance.session_fee_positions(p_session) f WHERE f.student_id IN (SELECT t.id FROM them t))
    SELECT pf.student_id, sd.stated, coalesce(p.due, 0), coalesce(p.paid, 0), coalesce(p.balance, 0), coalesce(p.instalments_paid, 2),
           coalesce(p.paid_in_full, true), coalesce(p.has_arrears, false)
      FROM prof pf JOIN said sd ON sd.k = pf.k LEFT JOIN pos p ON p.student_id = pf.student_id
$function$;

-- fee_line_usage: the students a line charges now read with their PG stage and category (V651)
CREATE OR REPLACE FUNCTION finance.fee_line_usage(p_lines uuid[])
 RETURNS TABLE(line_id uuid, session text, active boolean, stated_at timestamp with time zone, students integer, references_generated integer, references_open integer, references_paid integer, amount_paid numeric, ledger_entries integer, used_by text, removable boolean, message text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH l AS MATERIALIZED (
        SELECT f.id, f.session, f.item, f.level, f.entry_mode, f.faculty_code, f.programme_code, f.fee_group, f.indigene, f.spillover,
               f.spill_year, f.ended_at, f.pg_stage, f.fee_category, g.applies_category,
               (SELECT min(e.occurred_at) FROM audit.entries e
                 WHERE e.subject_type = 'finance.fee_schedule' AND e.subject_id = f.id AND e.action = 'INSERT') AS stated_at
          FROM finance.fee_schedule f
          LEFT JOIN ref.fee_group g ON g.code = f.fee_group
         WHERE f.id = ANY (p_lines)),
    sess AS MATERIALIZED (SELECT DISTINCT l.session FROM l),
    home AS (SELECT lower(fs.home_state) AS home_state FROM finance.fee_setting fs WHERE fs.id = 1),
    basis AS MATERIALIZED (SELECT finance.spill_basis() AS b),
    fl AS MATERIALIZED (SELECT pr.code, finance.final_level(pr.code) AS final FROM ref.programme pr),
    src AS MATERIALIZED (SELECT s.session, x.faculty_code, x.source_code FROM sess s CROSS JOIN LATERAL finance.fee_sources(s.session) x),
    -- now: the students each line charges, by the charge engine's own match (finance.fee_sums), every semester, as if it stood
    keys AS MATERIALIZED (
        SELECT s.session, fp.profile_key, fp.programme_code, fp.faculty_code, fp.category, fp.current_level, fp.entry_mode, fp.state,
               fp.is_spill, fp.spill_year, fp.final_level, fp.pg_stage, fp.pg_category, count(*)::int AS n
          FROM sess s CROSS JOIN LATERAL finance.fee_profiles(s.session) fp
         WHERE fp.status NOT IN ('GRADUATED', 'WITHDRAWN', 'EXPELLED', 'TRANSFERRED_OUT', 'DECEASED', 'VOLUNTARY_WITHDRAWAL')
         GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13),
    now_ AS (
        SELECT l.id, sum(k.n)::int AS n
          FROM l
          JOIN keys k ON k.session = l.session
          LEFT JOIN src ON src.session = l.session AND src.faculty_code = k.faculty_code
                       AND k.entry_mode IS DISTINCT FROM 'CCE' AND NOT people.is_postgraduate(k.entry_mode, k.category)
          CROSS JOIN home
         WHERE l.spillover = k.is_spill
           AND (l.level IS NULL OR l.level = CASE WHEN k.is_spill THEN k.final_level ELSE k.current_level END)
           AND (l.spill_year IS NULL OR l.spill_year = k.spill_year)
           AND ((l.entry_mode IS NULL AND k.entry_mode IS DISTINCT FROM 'CCE') OR l.entry_mode = k.entry_mode)
           AND (l.faculty_code IS NULL OR l.faculty_code = k.faculty_code OR (l.faculty_code = src.source_code AND l.programme_code IS NULL))
           AND (l.programme_code IS NULL OR l.programme_code = k.programme_code)
           AND (l.fee_group IS NULL OR l.applies_category IS NULL OR l.applies_category = k.category)
           AND finance.pg_line(k.entry_mode = 'POSTGRADUATE' OR k.category = 'POST GRADUATE', l.entry_mode, l.level, l.programme_code, l.applies_category)
           AND (l.indigene IS NULL OR (l.indigene = 'INDIGENE') = (k.state = home.home_state))
           AND finance.pg_stage_line(l.pg_stage, l.fee_category, k.pg_stage, k.pg_category)   -- V651
         GROUP BY l.id),
    -- then: the session's school-fees references and payments (old-portal ones included)
    refs AS MATERIALIZED (
        SELECT r.id, r.student_id, r.session, r.reference, r.amount, r.generated_at, r.confirmed_at, r.expires_at
          FROM finance.payment_reference r
         WHERE r.session IN (SELECT sess.session FROM sess) AND r.purpose LIKE 'School fees%'),
    -- each payer at every level the session knows them at: the record, the session's enrolment, its course registration
    lv AS MATERIALIZED (
        SELECT DISTINCT ps.session, ps.student_id, v.level
          FROM (SELECT DISTINCT refs.session, refs.student_id FROM refs) ps
          JOIN people.student s ON s.id = ps.student_id
          CROSS JOIN LATERAL (SELECT s.current_level AS level
                              UNION SELECT e.level FROM people.enrolment e WHERE e.student_id = ps.student_id AND e.session = ps.session
                              UNION SELECT cr.level FROM registration.course_registration cr WHERE cr.student_id = ps.student_id AND cr.session = ps.session) v
         WHERE v.level IS NOT NULL),
    payer AS MATERIALIZED (
        SELECT lv.session, lv.student_id, lv.level, s.programme_code, p.faculty_code, p.category, s.entry_mode, fl.final,
               CASE WHEN s.entry_mode IS DISTINCT FROM 'CCE' AND NOT people.is_postgraduate(s.entry_mode, p.category) THEN src.source_code END AS source_code,
               concat_ws('|', lv.session, s.programme_code, lv.level, coalesce(s.entry_mode, '-')) AS k
          FROM lv
          JOIN people.student s ON s.id = lv.student_id
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN fl ON fl.code = s.programme_code
          LEFT JOIN src ON src.session = lv.session AND src.faculty_code = p.faculty_code),
    -- the payers' distinct profiles (session, programme, level, entry mode): the scope is matched once per profile, not per payer
    pkey AS MATERIALIZED (
        SELECT DISTINCT ON (py.k) py.k, py.session, py.programme_code, py.faculty_code, py.category, py.entry_mode, py.level, py.final, py.source_code
          FROM payer py ORDER BY py.k),
    -- within the line's scope: its programme, faculty (or the faculty charged as), entry mode, group and level; a spillover line's
    -- level is the final level. Read generously: what the line might have charged counts.
    khit AS MATERIALIZED (
        SELECT l.id AS line_id, k.k
          FROM l
          JOIN pkey k ON k.session = l.session
          CROSS JOIN basis
         WHERE ((l.entry_mode IS NULL AND k.entry_mode IS DISTINCT FROM 'CCE') OR l.entry_mode = k.entry_mode)
           AND (l.faculty_code IS NULL OR l.faculty_code = k.faculty_code OR (l.faculty_code = k.source_code AND l.programme_code IS NULL))
           AND (l.programme_code IS NULL OR l.programme_code = k.programme_code)
           AND (l.fee_group IS NULL OR l.applies_category IS NULL OR l.applies_category = k.category)
           AND finance.pg_line(k.entry_mode = 'POSTGRADUATE' OR k.category = 'POST GRADUATE', l.entry_mode, l.level, l.programme_code, l.applies_category)
           AND CASE WHEN l.spillover THEN (l.level IS NULL OR l.level = k.final) AND (basis.b = 'COHORT' OR k.level >= k.final)
                    ELSE (l.level IS NULL OR l.level = k.level) AND (basis.b = 'COHORT' OR k.level <= k.final OR k.category = 'POST GRADUATE') END),
    hit AS MATERIALIZED (
        SELECT DISTINCT kh.line_id, py.student_id FROM khit kh JOIN payer py ON py.k = kh.k),
    -- generated or recorded while the line stood
    used AS MATERIALIZED (
        SELECT h.line_id, r.id, r.reference, r.amount, r.confirmed_at, r.expires_at
          FROM hit h
          JOIN l ON l.id = h.line_id
          JOIN refs r ON r.student_id = h.student_id AND r.session = l.session
         WHERE r.generated_at >= coalesce(l.stated_at, '-infinity'::timestamptz)
           AND (l.ended_at IS NULL OR r.generated_at <= l.ended_at)),
    posted AS MATERIALIZED (
        SELECT split_part(j.source_ref, '#', 1) AS reference, count(*)::int AS n
          FROM finance.gl_journal j
         WHERE j.source_type IN ('PAYMENT', 'PAYMENT_RESET') AND j.source_ref IS NOT NULL
           AND split_part(j.source_ref, '#', 1) IN (SELECT u.reference FROM used u)
         GROUP BY 1),
    tally AS (
        SELECT u.line_id, count(DISTINCT u.id)::int AS generated,
               count(DISTINCT u.id) FILTER (WHERE u.confirmed_at IS NULL AND u.expires_at > now())::int AS open_,
               count(DISTINCT u.id) FILTER (WHERE u.confirmed_at IS NOT NULL)::int AS paid,
               coalesce(sum(u.amount) FILTER (WHERE u.confirmed_at IS NOT NULL), 0) AS amount_paid,
               coalesce(sum(p.n), 0)::int AS ledger
          FROM used u LEFT JOIN posted p ON p.reference = u.reference
         GROUP BY u.line_id),
    out AS (
        SELECT l.id, l.session, l.ended_at IS NULL AS active, l.stated_at, coalesce(n.n, 0) AS students,
               coalesce(t.generated, 0) AS generated, coalesce(t.open_, 0) AS open_, coalesce(t.paid, 0) AS paid,
               coalesce(t.amount_paid, 0) AS amount_paid, coalesce(t.ledger, 0) AS ledger
          FROM l LEFT JOIN now_ n ON n.id = l.id LEFT JOIN tally t ON t.line_id = l.id)
    SELECT o.id, o.session, o.active, o.stated_at, o.students, o.generated, o.open_, o.paid, o.amount_paid, o.ledger,
           x.used_by, x.used_by = 'NONE',
           CASE x.used_by
               WHEN 'NONE' THEN 'Never used: no student is charged by it, and no invoice, payment or ledger entry was made under it.'
               WHEN 'STUDENTS' THEN format('Part of what %s student%s owe now; no invoice or payment has been made under it.', o.students, CASE WHEN o.students = 1 THEN '' ELSE 's' END)
               ELSE format('This fee structure has already been used: %s school-fees invoice%s generated in %s by students within its scope while it stood%s%s.',
                           o.generated, CASE WHEN o.generated = 1 THEN '' ELSE 's' END, o.session,
                           CASE WHEN o.paid > 0 THEN format(', %s paid (₦%s)', o.paid, to_char(o.amount_paid, 'FM999,999,999,990.00')) ELSE '' END,
                           CASE WHEN o.ledger > 0 THEN format(', %s ledger entr%s', o.ledger, CASE WHEN o.ledger = 1 THEN 'y' ELSE 'ies' END) ELSE '' END)
           END
      FROM out o
      CROSS JOIN LATERAL (SELECT CASE WHEN o.ledger > 0 THEN 'LEDGER' WHEN o.paid > 0 THEN 'PAYMENT' WHEN o.generated > 0 THEN 'INVOICE'
                                      WHEN o.students > 0 AND o.active THEN 'STUDENTS' ELSE 'NONE' END AS used_by) x
$function$;

-- fee_line_same_scope: the PG stage and category are part of a line's scope (V651)
CREATE OR REPLACE FUNCTION finance.fee_line_same_scope(x finance.fee_schedule, s finance.fee_schedule)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT lower(btrim(x.item)) = lower(btrim(s.item)) AND x.kind = s.kind
       AND x.level IS NOT DISTINCT FROM s.level AND x.entry_mode IS NOT DISTINCT FROM s.entry_mode
       AND x.faculty_code IS NOT DISTINCT FROM s.faculty_code AND x.programme_code IS NOT DISTINCT FROM s.programme_code
       AND x.fee_group IS NOT DISTINCT FROM s.fee_group AND x.semester IS NOT DISTINCT FROM s.semester
       AND x.indigene IS NOT DISTINCT FROM s.indigene AND x.spillover = s.spillover
       AND x.spill_year IS NOT DISTINCT FROM s.spill_year   -- V613
       AND x.pg_stage IS NOT DISTINCT FROM s.pg_stage AND x.fee_category IS NOT DISTINCT FROM s.fee_category   -- V651
$function$;

-- copy_session_fees: a copied line keeps its PG stage and category (V651)
CREATE OR REPLACE FUNCTION finance.copy_session_fees(p_from text, p_to text, p_apply boolean)
 RETURNS TABLE(item text, kind text, amount numeric, level integer, entry_mode text, faculty_code text, programme_code text, fee_group text, semester integer, indigene text, spillover boolean, spill_year integer, ord integer, target_amount numeric, action text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_from IS NULL OR p_to IS NULL OR p_from = p_to THEN
        RAISE EXCEPTION 'FEE_COPY_SESSIONS: copy from one session into another' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_to) THEN
        RAISE EXCEPTION 'FEE_COPY_SESSION: % is not a session on the calendar', p_to USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM finance.fee_schedule f WHERE f.session = p_from AND f.ended_at IS NULL) THEN
        RAISE EXCEPTION 'FEE_COPY_EMPTY: % states no fee line to copy', p_from USING ERRCODE = '23514';
    END IF;
    IF p_apply AND nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'FEE_COPY_ACTOR: fees are copied by a person' USING ERRCODE = '23514';
    END IF;
    -- what each line of the source is to the target (read before anything is copied, so the answer says what the copy did);
    -- a preview writes nothing, and reads in a read-only transaction
    RETURN QUERY
    SELECT s.item, s.kind, s.amount, s.level, s.entry_mode, s.faculty_code, s.programme_code, s.fee_group, s.semester, s.indigene, s.spillover, s.spill_year, s.ord,
           t.amount, CASE WHEN t.amount IS NULL THEN 'COPY' ELSE 'KEPT' END
      FROM finance.fee_schedule s
      LEFT JOIN LATERAL (SELECT x.amount FROM finance.fee_schedule x WHERE x.session = p_to AND x.ended_at IS NULL AND finance.fee_line_same_scope(x, s) LIMIT 1) t ON true
     WHERE s.session = p_from AND s.ended_at IS NULL
     ORDER BY s.kind, s.ord, s.item, s.faculty_code NULLS FIRST, s.programme_code NULLS FIRST, s.level NULLS FIRST, s.semester NULLS FIRST;
    IF p_apply THEN
        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, ord, fee_group, semester, indigene, spillover, spill_year, kind, pg_stage, fee_category)
        SELECT p_to, s.item, s.amount, s.level, s.entry_mode, s.faculty_code, s.programme_code, s.ord, s.fee_group, s.semester, s.indigene, s.spillover, s.spill_year, s.kind, s.pg_stage, s.fee_category
          FROM finance.fee_schedule s
         WHERE s.session = p_from AND s.ended_at IS NULL
           AND NOT EXISTS (SELECT 1 FROM finance.fee_schedule x WHERE x.session = p_to AND x.ended_at IS NULL AND finance.fee_line_same_scope(x, s));
    END IF;
END $function$;

-- copy_faculty_fees: a copied line keeps its PG stage and category (V651)
CREATE OR REPLACE FUNCTION finance.copy_faculty_fees(p_from text, p_to text, p_session text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
    IF p_from IS NULL OR p_to IS NULL OR p_from = p_to
       OR NOT EXISTS (SELECT 1 FROM ref.faculty WHERE code = p_from) OR NOT EXISTS (SELECT 1 FROM ref.faculty WHERE code = p_to) THEN
        RETURN 0;
    END IF;
    -- a faculty the Bursary has already stated for the session is left as it is
    IF EXISTS (SELECT 1 FROM finance.fee_schedule f WHERE f.session = p_session AND f.faculty_code = p_to AND f.ended_at IS NULL) THEN
        RETURN 0;
    END IF;
    INSERT INTO finance.fee_schedule (id, session, item, amount, level, entry_mode, faculty_code, programme_code, ord, fee_group, semester, indigene, spillover, spill_year, kind, pg_stage, fee_category)
    SELECT gen_random_uuid(), f.session, f.item, f.amount, f.level, f.entry_mode, p_to, NULL, f.ord, f.fee_group, f.semester, f.indigene, f.spillover, f.spill_year, f.kind, f.pg_stage, f.fee_category
      FROM finance.fee_schedule f
     WHERE f.session = p_session AND f.faculty_code = p_from AND f.programme_code IS NULL AND f.ended_at IS NULL;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $function$;

-- programme_level_lines: a PG stage's (or category's) line is not a level's line (V651)
CREATE OR REPLACE FUNCTION finance.programme_level_lines(p_session text, p_programme text, p_level integer)
 RETURNS TABLE(item text, kind text, amount numeric, entry_mode text, faculty_code text, fee_group text, semester integer, indigene text, ord integer, tier text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH p AS (SELECT faculty_code FROM ref.programme WHERE code = p_programme),
    l AS (
        SELECT f.item, f.kind, f.amount, f.entry_mode, f.faculty_code, f.fee_group, f.semester, f.indigene, f.ord,
               CASE WHEN f.programme_code = p_programme THEN 1 WHEN f.faculty_code IS NOT NULL THEN 2 ELSE 3 END AS rank
          FROM finance.fee_schedule f, p
         WHERE f.session = p_session AND f.level = p_level AND NOT f.spillover AND f.ended_at IS NULL
           AND f.pg_stage IS NULL AND f.fee_category IS NULL   -- V651: a PG stage's line is not a level's line
           AND (f.programme_code = p_programme OR (f.programme_code IS NULL AND (f.faculty_code = p.faculty_code OR f.faculty_code IS NULL)))
    )
    SELECT l.item, l.kind, l.amount, l.entry_mode, l.faculty_code, l.fee_group, l.semester, l.indigene, l.ord,
           CASE l.rank WHEN 1 THEN 'PROGRAMME' WHEN 2 THEN 'FACULTY' ELSE 'UNIVERSITY' END
      FROM l WHERE l.rank = (SELECT min(rank) FROM l)
     ORDER BY l.kind, l.ord, l.item, l.semester NULLS FIRST, l.indigene NULLS FIRST, l.entry_mode NULLS FIRST
$function$;

-- finance.pg_unstated (V447): alike PG students share the stage and category as well, the facts fee_stated now reads (V651)
CREATE OR REPLACE FUNCTION finance.pg_unstated(p_session text)
 RETURNS TABLE(level integer, programme_code text, programme text, students bigint)
 LANGUAGE sql
 STABLE
AS $function$
    -- the stage and category tell students apart only when the session states a line by them (else the groups stay as V447's)
    WITH staged AS MATERIALIZED (SELECT EXISTS (SELECT 1 FROM finance.fee_schedule f WHERE f.session = p_session AND f.ended_at IS NULL
                                                AND (f.pg_stage IS NOT NULL OR f.fee_category IS NOT NULL)) AS y),
    pgs AS MATERIALIZED (SELECT x.student_id, x.stage_code, x.category FROM admissions.pg_stages_of(p_session, NULL) x, staged WHERE staged.y),
    live AS (
        -- the live PG students, with the facts finance.fee_stated reads of a student (the state of origin as it reads it, V651 the stage)
        SELECT s.id, s.current_level, s.programme_code, p.name, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) = lower(h.home_state) AS indigene,
               pgs.stage_code, pgs.category
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          LEFT JOIN finance.fee_setting h ON h.id = 1
          LEFT JOIN pgs ON pgs.student_id = s.id
         WHERE people.is_postgraduate(s.entry_mode, p.category)
           AND s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
    alike AS (
        -- one student of each group of alike students, asked the real question
        SELECT g.programme_code, g.current_level, g.entry_mode, g.indigene, g.stage_code, g.category, finance.fee_stated(g.one, p_session) AS stated
          FROM (SELECT l.programme_code, l.current_level, l.entry_mode, l.indigene, l.stage_code, l.category, (array_agg(l.id))[1] AS one
                  FROM live l
                 GROUP BY l.programme_code, l.current_level, l.entry_mode, l.indigene, l.stage_code, l.category) g)
    SELECT l.current_level, l.programme_code, l.name, count(*)
      FROM live l
      JOIN alike a ON a.programme_code = l.programme_code
                  AND a.current_level IS NOT DISTINCT FROM l.current_level
                  AND a.entry_mode IS NOT DISTINCT FROM l.entry_mode
                  AND a.indigene IS NOT DISTINCT FROM l.indigene
                  AND a.stage_code IS NOT DISTINCT FROM l.stage_code
                  AND a.category IS NOT DISTINCT FROM l.category
     WHERE NOT a.stated
     GROUP BY l.current_level, l.programme_code, l.name
     ORDER BY l.current_level, l.programme_code;
$function$;

-- finance.edit_fee_line (V648): the PG stage and category edited with the rest, kept on a versioned line (V651)
CREATE OR REPLACE FUNCTION finance.edit_fee_line(p_id uuid, p_line jsonb, p_reason text)
RETURNS TABLE(outcome text, line_id uuid, previous_id uuid, used_by text, message text)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
    v_office text := nullif(current_setting('moaum.actor_office', true), '');
    v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_old finance.fee_schedule;
    v_new_id uuid;
    v_item text := btrim(coalesce(p_line ->> 'item', ''));
    v_amount numeric := (p_line ->> 'amount')::numeric;
    v_level integer := (nullif(p_line ->> 'level', ''))::integer;
    v_mode text := nullif(btrim(coalesce(p_line ->> 'entry_mode', '')), '');
    v_fac text := nullif(btrim(coalesce(p_line ->> 'faculty_code', '')), '');
    v_prog text := nullif(btrim(coalesce(p_line ->> 'programme_code', '')), '');
    v_group text := nullif(btrim(coalesce(p_line ->> 'fee_group', '')), '');
    v_sem integer := (nullif(p_line ->> 'semester', ''))::integer;
    v_ord integer := coalesce((nullif(p_line ->> 'ord', ''))::integer, 0);
    v_kind text;
    v_spill boolean := coalesce((nullif(p_line ->> 'spillover', ''))::boolean, false) OR nullif(p_line ->> 'spill_year', '') IS NOT NULL;
    v_spill_year integer := (nullif(p_line ->> 'spill_year', ''))::integer;
    v_stage text;
    v_cat text;
    -- the edit's own reason, else the request's (moaum.reason, the X-Reason the screen sends)
    v_reason text := coalesce(nullif(btrim(coalesce(p_reason, '')), ''), nullif(current_setting('moaum.reason', true), ''));
    u record;
BEGIN
    PERFORM finance.fee_setup_require('EDIT_FEE_STRUCTURE');
    SELECT * INTO v_old FROM finance.fee_schedule f WHERE f.id = p_id AND f.ended_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'FEE_GONE: that fee line is not on the current schedule' USING ERRCODE = '23514';
    END IF;
    IF v_item = '' OR v_amount IS NULL OR v_amount < 0 THEN
        RAISE EXCEPTION 'FEE_LINE_INCOMPLETE: a fee line has an item and an amount of zero or more' USING ERRCODE = '23514';
    END IF;
    v_kind := coalesce(nullif(btrim(coalesce(p_line ->> 'kind', '')), ''), v_old.kind);
    -- V651: the PG stage and category as the edit states them, else as the line had them
    v_stage := CASE WHEN p_line ? 'pg_stage' THEN nullif(btrim(coalesce(p_line ->> 'pg_stage', '')), '') ELSE v_old.pg_stage END;
    v_cat := CASE WHEN p_line ? 'fee_category' THEN nullif(btrim(coalesce(p_line ->> 'fee_category', '')), '') ELSE v_old.fee_category END;
    IF v_stage IS NOT NULL THEN
        v_cat := NULL;   -- the stage's own category is set by the line's guard (finance.trg_fee_line_pg)
    END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NOT NULL THEN
        PERFORM set_config('moaum.reason', btrim(p_reason), true);
    END IF;

    IF (v_old.item, v_old.amount, v_old.level, v_old.entry_mode, v_old.faculty_code, v_old.programme_code, v_old.fee_group, v_old.semester,
        v_old.ord, v_old.kind, v_old.spillover, v_old.spill_year, v_old.pg_stage)
       IS NOT DISTINCT FROM (v_item, v_amount, v_level, v_mode, v_fac, v_prog, v_group, v_sem, v_ord, v_kind, v_spill, v_spill_year, v_stage)
       AND (v_stage IS NOT NULL OR v_old.fee_category IS NOT DISTINCT FROM v_cat) THEN
        outcome := 'UNCHANGED'; line_id := p_id; previous_id := NULL; used_by := NULL; message := 'Nothing changed.';
        RETURN NEXT;
        RETURN;
    END IF;

    SELECT * INTO u FROM finance.fee_line_usage(ARRAY[p_id]);
    used_by := u.used_by;
    IF u.used_by IN ('INVOICE', 'PAYMENT', 'LEDGER') THEN
        -- the line an invoice or a payment was made under stays on record, ended; the corrected one is stated beside it
        UPDATE finance.fee_schedule f SET ended_at = now() WHERE f.id = p_id;
        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, fee_group, semester, ord, kind,
                                          spillover, spill_year, indigene, pg_stage, fee_category)
        VALUES (v_old.session, v_item, v_amount, v_level, v_mode, v_fac, v_prog, v_group, v_sem, v_ord, v_kind, v_spill, v_spill_year, v_old.indigene, v_stage, v_cat)
        RETURNING id INTO v_new_id;
        INSERT INTO finance.fee_line_change (line_id, session, action, reason_code, reason, before_state, after_state, usage, replaced_by, actor, actor_office)
        SELECT p_id, v_old.session, 'FEE_STRUCTURE_VERSIONED', NULL, v_reason, to_jsonb(v_old), to_jsonb(f), to_jsonb(u),
               v_new_id, v_actor, v_office
          FROM finance.fee_schedule f WHERE f.id = v_new_id;
        outcome := 'VERSIONED'; line_id := v_new_id; previous_id := p_id;
        message := u.message || ' The line it was is kept, ended, and the corrected line is in force from now; every invoice and payment keeps its amount.';
    ELSE
        UPDATE finance.fee_schedule f
           SET item = v_item, amount = v_amount, level = v_level, entry_mode = v_mode, faculty_code = v_fac, programme_code = v_prog,
               fee_group = v_group, semester = v_sem, ord = v_ord, kind = v_kind, spillover = v_spill, spill_year = v_spill_year,
               pg_stage = v_stage, fee_category = v_cat
         WHERE f.id = p_id;
        INSERT INTO finance.fee_line_change (line_id, session, action, reason_code, reason, before_state, after_state, usage, actor, actor_office)
        SELECT p_id, v_old.session, 'FEE_STRUCTURE_EDITED', NULL, v_reason, to_jsonb(v_old), to_jsonb(f), to_jsonb(u),
               v_actor, v_office
          FROM finance.fee_schedule f WHERE f.id = p_id;
        outcome := 'EDITED'; line_id := p_id; previous_id := NULL;
        message := 'Corrected in place: ' || lower(left(u.message, 1)) || substr(u.message, 2);
    END IF;
    RETURN NEXT;
END $$;

-- ── recording a stage: the School's word for a cycle in a session ──
CREATE OR REPLACE FUNCTION admissions.pg_record_stage(p_cycle uuid, p_session text, p_stage text, p_source text, p_reason text)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    c people.pg_cycle;
    st admissions.pg_stage;
    prev record;
    nxt record;
    v_max int;
    v_id uuid;
BEGIN
    IF p_source IS NULL OR p_source NOT IN ('RECONCILIATION', 'PROGRESSION', 'EXTENSION', 'RESTART', 'CORRECTION', 'ADMISSION') THEN
        RAISE EXCEPTION 'PG_STAGE_SOURCE: a stage is recorded by reconciliation, progression, extension, restart, admission or correction' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM people.pg_cycle WHERE id = p_cycle FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PG_CYCLE_UNKNOWN: no such postgraduate cycle' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO st FROM admissions.pg_stage WHERE code = p_stage;
    IF NOT FOUND OR NOT st.active OR st.qualification <> c.qualification THEN
        RAISE EXCEPTION 'PG_STAGE_QUALIFICATION: % is not a stage of this cycle''s qualification', coalesce(st.label, p_stage) USING ERRCODE = '23514';
    END IF;
    IF st.extension_number IS NOT NULL THEN
        PERFORM admissions.pg_require('APPROVE_PG_EXTENSION');
    ELSE
        PERFORM admissions.pg_require('MANAGE_PG_PROGRESSION');
    END IF;
    IF c.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'PG_CYCLE_CLOSED: cycle % is %; a new stage is recorded in an active cycle', c.cycle_no, lower(replace(c.status, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_session) THEN
        RAISE EXCEPTION 'PG_STAGE_SESSION: % is not a session on the calendar', p_session USING ERRCODE = '23514';
    END IF;
    IF policy.session_year(p_session) < policy.session_year(c.start_session) THEN
        RAISE EXCEPTION 'PG_STAGE_BEFORE_START: the cycle began in %', c.start_session USING ERRCODE = '23514';
    END IF;
    -- in order: never below the stage last recorded, never further ahead than the sessions since allow
    SELECT cs.session, s2.sequence INTO prev FROM people.pg_cycle_stage cs JOIN admissions.pg_stage s2 ON s2.code = cs.stage_code
     WHERE cs.cycle_id = c.id AND policy.session_year(cs.session) < policy.session_year(p_session)
     ORDER BY policy.session_year(cs.session) DESC LIMIT 1;
    v_max := CASE WHEN prev.session IS NOT NULL THEN prev.sequence + policy.sessions_elapsed(prev.session, p_session)
                  ELSE 1 + policy.sessions_elapsed(c.start_session, p_session) END;
    IF prev.session IS NOT NULL AND st.sequence < prev.sequence THEN
        RAISE EXCEPTION 'PG_STAGE_ORDER: the cycle was at a later stage in % already', prev.session USING ERRCODE = '23514';
    END IF;
    IF st.sequence > v_max THEN
        RAISE EXCEPTION 'PG_STAGE_AHEAD: % is further than the sessions since % allow', st.label, coalesce(prev.session, c.start_session) USING ERRCODE = '23514';
    END IF;
    SELECT cs.session, s2.sequence INTO nxt FROM people.pg_cycle_stage cs JOIN admissions.pg_stage s2 ON s2.code = cs.stage_code
     WHERE cs.cycle_id = c.id AND policy.session_year(cs.session) > policy.session_year(p_session)
     ORDER BY policy.session_year(cs.session) LIMIT 1;
    IF nxt.session IS NOT NULL AND nxt.sequence < st.sequence THEN
        RAISE EXCEPTION 'PG_STAGE_ORDER: the cycle is recorded at an earlier stage in %', nxt.session USING ERRCODE = '23514';
    END IF;
    IF p_source IN ('CORRECTION', 'EXTENSION') AND length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'PG_STAGE_REASON: give the reason (ten characters at least)' USING ERRCODE = '23514';
    END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NOT NULL THEN
        PERFORM set_config('moaum.reason', btrim(p_reason), true);
    END IF;
    INSERT INTO people.pg_cycle_stage (cycle_id, session, stage_code, source, reason, decided_by, decided_office)
    VALUES (c.id, p_session, st.code, p_source, nullif(btrim(coalesce(p_reason, '')), ''),
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    ON CONFLICT (cycle_id, session) DO UPDATE
       SET stage_code = EXCLUDED.stage_code, source = CASE WHEN people.pg_cycle_stage.stage_code = EXCLUDED.stage_code THEN people.pg_cycle_stage.source ELSE 'CORRECTION' END,
           reason = EXCLUDED.reason, decided_by = EXCLUDED.decided_by, decided_office = EXCLUDED.decided_office, at = now()
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;
COMMENT ON FUNCTION admissions.pg_record_stage(uuid, text, text, text, text) IS
  'V651: the stage of an active cycle in a session, as the School records it — a stage of the cycle''s qualification, in order (never below the last recorded, never further than the sessions since allow); an extension stage needs APPROVE_PG_EXTENSION, another MANAGE_PG_PROGRESSION; a second word for a session corrects it.';

-- ── progression: the calculated stage recorded for the students chosen, extension only with its approval ──
CREATE OR REPLACE FUNCTION admissions.pg_progress(p_students uuid[], p_session text, p_reason text)
RETURNS TABLE(student_id uuid, outcome text, stage_code text, stage_label text, message text)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE r record; v_ext boolean;
BEGIN
    PERFORM admissions.pg_require('MANAGE_PG_PROGRESSION');
    v_ext := admissions.pg_may(nullif(current_setting('moaum.actor_office', true), ''), 'APPROVE_PG_EXTENSION');
    FOR r IN SELECT x.* FROM admissions.pg_stages_of(p_session, p_students) x LOOP
        student_id := r.student_id; stage_code := r.stage_code; stage_label := r.stage_label;
        IF r.cycle_id IS NULL THEN
            outcome := 'NO_CYCLE'; message := 'No cycle is recorded yet: reconcile the student first.';
        ELSIF r.official THEN
            outcome := 'ALREADY'; message := 'The stage is recorded for ' || p_session || ' already.';
        ELSIF r.recommendation = 'NORMAL_PROGRESS' OR (r.recommendation = 'EXTENSION_REQUIRED' AND v_ext) THEN
            BEGIN
                PERFORM admissions.pg_record_stage(r.cycle_id, p_session, r.stage_code,
                                                   CASE WHEN r.is_extension THEN 'EXTENSION' ELSE 'PROGRESSION' END,
                                                   coalesce(nullif(btrim(coalesce(p_reason, '')), ''), CASE WHEN r.is_extension THEN 'Extension approved by the PG School' ELSE 'Progressed by the PG School' END));
                outcome := CASE WHEN r.is_extension THEN 'EXTENDED' ELSE 'PROGRESSED' END;
                message := 'Recorded at ' || r.stage_label || ' for ' || p_session || '.';
            EXCEPTION WHEN check_violation OR insufficient_privilege THEN
                outcome := 'REFUSED'; message := split_part(SQLERRM, ': ', 2);
            END;
        ELSIF r.recommendation = 'EXTENSION_REQUIRED' THEN
            outcome := 'NEEDS_APPROVAL'; message := r.stage_label || ' is an extension: the Dean of the PG School approves it.';
        ELSIF r.recommendation = 'MAXIMUM_PERIOD_REACHED' THEN
            outcome := 'MAXIMUM'; message := 'The maximum period is passed: close the cycle; a restart is a new cycle.';
        ELSE
            outcome := 'SKIPPED'; message := 'The cycle is ' || lower(replace(r.recommendation, '_', ' ')) || '.';
        END IF;
        RETURN NEXT;
    END LOOP;
END $$;

-- ── closing a cycle: completed, graduated, maximum period exhausted, or closed ──
CREATE OR REPLACE FUNCTION admissions.pg_close_cycle(p_cycle uuid, p_status text, p_reason text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE c people.pg_cycle; r record;
BEGIN
    PERFORM admissions.pg_require('MANAGE_PG_ACADEMIC_CYCLE');
    IF p_status IS NULL OR p_status NOT IN ('COMPLETED', 'GRADUATED', 'MAXIMUM_PERIOD_EXHAUSTED', 'CLOSED') THEN
        RAISE EXCEPTION 'PG_CYCLE_STATUS: a cycle closes as completed, graduated, maximum period exhausted or closed' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'PG_CYCLE_REASON: give the reason (ten characters at least)' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM people.pg_cycle WHERE id = p_cycle FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PG_CYCLE_UNKNOWN: no such postgraduate cycle' USING ERRCODE = '23514';
    END IF;
    IF c.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'PG_CYCLE_CLOSED: cycle % is % already', c.cycle_no, lower(replace(c.status, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF p_status = 'MAXIMUM_PERIOD_EXHAUSTED' THEN
        -- passed the maximum in the PG School's session, or recorded at the last stage
        SELECT x.* INTO r FROM admissions.pg_stages_of(admissions.pg_current_session(), ARRAY[c.student_id]) x;
        IF NOT (coalesce(r.beyond, false)
                OR EXISTS (SELECT 1 FROM people.pg_cycle_stage cs JOIN admissions.pg_stage s2 ON s2.code = cs.stage_code
                            WHERE cs.cycle_id = c.id
                              AND s2.sequence = (SELECT max(s3.sequence) FROM admissions.pg_stage s3 WHERE s3.qualification = c.qualification AND s3.active))) THEN
            RAISE EXCEPTION 'PG_CYCLE_NOT_EXHAUSTED: the cycle has not reached the end of its maximum period' USING ERRCODE = '23514';
        END IF;
    END IF;
    PERFORM set_config('moaum.reason', btrim(p_reason), true);
    UPDATE people.pg_cycle SET status = p_status, status_reason = btrim(p_reason), status_at = now(),
                               status_by = nullif(current_setting('moaum.actor_id', true), '')::uuid
     WHERE id = c.id;
    RETURN p_status;
END $$;

-- ── restart: requested, recommended by the department, approved by the School — a new cycle at its first stage ──
CREATE TABLE people.pg_restart_request (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference text NOT NULL UNIQUE CHECK (reference ~ '^PG-RST/[0-9]{4}/[0-9]{6}$'),
    student_id uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    cycle_id uuid NOT NULL REFERENCES people.pg_cycle(id) ON DELETE CASCADE,
    start_session text NOT NULL CHECK (start_session ~ '^[0-9]{4}/[0-9]{4}$'),
    reason text NOT NULL,
    state text NOT NULL DEFAULT 'REQUESTED' CHECK (state IN ('REQUESTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'CANCELLED')),
    requested_by uuid,
    requested_office text,
    requested_at timestamptz NOT NULL DEFAULT now(),
    dept_by uuid,
    dept_office text,
    dept_at timestamptz,
    dept_note text,
    decided_by uuid,
    decided_office text,
    decided_at timestamptz,
    decision_note text,
    new_cycle_id uuid REFERENCES people.pg_cycle(id)
);
CREATE UNIQUE INDEX ux_pg_restart_open ON people.pg_restart_request (cycle_id) WHERE state IN ('REQUESTED', 'UNDER_REVIEW');
SELECT audit.attach('people.pg_restart_request');
COMMENT ON TABLE people.pg_restart_request IS
  'V651: a postgraduate restart — PG-RST/YYYY/NNNNNN — requested once a cycle has exhausted its maximum period, recommended (or not) by the department, approved or rejected by the PG School; an approval opens the next cycle at its first stage (FRESH) and closes the old one, every record of it kept.';

CREATE OR REPLACE FUNCTION admissions.pg_restart_request(p_student uuid, p_start_session text, p_reason text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE c people.pg_cycle; r record; v_ref text; q admissions.pg_qualification;
BEGIN
    PERFORM admissions.pg_require('REQUEST_PG_RESTART');
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'PG_RESTART_REASON: give the reason (ten characters at least)' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM people.pg_cycle WHERE student_id = p_student ORDER BY cycle_no DESC LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PG_RESTART_NO_CYCLE: the student''s cycle is not recorded yet: reconcile first' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO q FROM admissions.pg_qualification WHERE code = c.qualification;
    IF NOT q.restart_allowed THEN
        RAISE EXCEPTION 'PG_RESTART_NOT_ALLOWED: a % is not restarted', q.label USING ERRCODE = '23514';
    END IF;
    IF c.status IN ('COMPLETED', 'GRADUATED') THEN
        RAISE EXCEPTION 'PG_RESTART_COMPLETED: the cycle was completed' USING ERRCODE = '23514';
    END IF;
    IF c.status = 'ACTIVE' THEN
        SELECT x.* INTO r FROM admissions.pg_stages_of(admissions.pg_current_session(), ARRAY[p_student]) x;
        IF NOT coalesce(r.beyond, false) THEN
            RAISE EXCEPTION 'PG_RESTART_NOT_DUE: the cycle has not exhausted its maximum period — an extension, not a restart' USING ERRCODE = '23514';
        END IF;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_start_session)
       OR policy.session_year(p_start_session) <= coalesce((SELECT max(policy.session_year(cs.session)) FROM people.pg_cycle_stage cs WHERE cs.cycle_id = c.id),
                                                          policy.session_year(c.start_session)) THEN
        RAISE EXCEPTION 'PG_RESTART_SESSION: the new cycle begins in a session on the calendar after the old cycle''s last' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM people.pg_restart_request x WHERE x.cycle_id = c.id AND x.state IN ('REQUESTED', 'UNDER_REVIEW')) THEN
        RAISE EXCEPTION 'PG_RESTART_OPEN: a restart is already requested for this cycle' USING ERRCODE = '23514';
    END IF;
    v_ref := 'PG-RST/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/'
             || lpad(platform.next_number('PG_RESTART', 'UNIVERSITY', to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY'))::text, 6, '0');
    PERFORM set_config('moaum.reason', btrim(p_reason), true);
    INSERT INTO people.pg_restart_request (reference, student_id, cycle_id, start_session, reason, requested_by, requested_office)
    VALUES (v_ref, p_student, c.id, p_start_session, btrim(p_reason), nullif(current_setting('moaum.actor_id', true), '')::uuid,
            nullif(current_setting('moaum.actor_office', true), ''));
    RETURN v_ref;
END $$;

CREATE OR REPLACE FUNCTION admissions.pg_restart_recommend(p_reference text, p_recommend boolean, p_note text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE x people.pg_restart_request;
BEGIN
    PERFORM admissions.pg_require('RECOMMEND_PG_RESTART');
    SELECT * INTO x FROM people.pg_restart_request WHERE reference = p_reference FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PG_RESTART_UNKNOWN: no such restart request' USING ERRCODE = '23514';
    END IF;
    IF x.state <> 'REQUESTED' THEN
        RAISE EXCEPTION 'PG_RESTART_STATE: the request is % — the department recommends a request just made', lower(replace(x.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF NOT p_recommend AND length(btrim(coalesce(p_note, ''))) < 10 THEN
        RAISE EXCEPTION 'PG_RESTART_NOTE: say why the department does not recommend it (ten characters at least)' USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', coalesce(nullif(btrim(coalesce(p_note, '')), ''), 'Restart recommended by the department'), true);
    UPDATE people.pg_restart_request
       SET state = CASE WHEN p_recommend THEN 'UNDER_REVIEW' ELSE 'REJECTED' END, dept_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
           dept_office = nullif(current_setting('moaum.actor_office', true), ''), dept_at = now(), dept_note = nullif(btrim(coalesce(p_note, '')), '')
     WHERE id = x.id;
    RETURN CASE WHEN p_recommend THEN 'UNDER_REVIEW' ELSE 'REJECTED' END;
END $$;

CREATE OR REPLACE FUNCTION admissions.pg_restart_decide(p_reference text, p_approve boolean, p_note text)
RETURNS TABLE(state text, new_cycle_id uuid, cycle_no integer, stage_code text)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE x people.pg_restart_request; old people.pg_cycle; v_new uuid; v_no int; v_first text; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    PERFORM admissions.pg_require('APPROVE_PG_RESTART');
    SELECT * INTO x FROM people.pg_restart_request r WHERE r.reference = p_reference FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PG_RESTART_UNKNOWN: no such restart request' USING ERRCODE = '23514';
    END IF;
    IF x.state <> 'UNDER_REVIEW' THEN
        RAISE EXCEPTION 'PG_RESTART_STATE: the request is % — the School decides a request the department recommended', lower(replace(x.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF v_actor IS NOT NULL AND v_actor = x.requested_by THEN
        RAISE EXCEPTION 'PG_RESTART_SAME_OFFICER: the officer who requested the restart does not approve it' USING ERRCODE = '23514';
    END IF;
    IF NOT p_approve AND length(btrim(coalesce(p_note, ''))) < 10 THEN
        RAISE EXCEPTION 'PG_RESTART_NOTE: say why the restart is not approved (ten characters at least)' USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', coalesce(nullif(btrim(coalesce(p_note, '')), ''), 'Restart ' || x.reference || ' approved'), true);
    IF NOT p_approve THEN
        UPDATE people.pg_restart_request r SET state = 'REJECTED', decided_by = v_actor, decided_office = nullif(current_setting('moaum.actor_office', true), ''),
               decided_at = now(), decision_note = btrim(p_note)
         WHERE r.id = x.id;
        state := 'REJECTED'; new_cycle_id := NULL; cycle_no := NULL; stage_code := NULL;
        RETURN NEXT;
        RETURN;
    END IF;
    SELECT * INTO old FROM people.pg_cycle c WHERE c.id = x.cycle_id FOR UPDATE;
    IF old.status = 'ACTIVE' THEN
        UPDATE people.pg_cycle c SET status = 'MAXIMUM_PERIOD_EXHAUSTED', status_reason = 'Restart ' || x.reference || ' approved', status_at = now(), status_by = v_actor
         WHERE c.id = old.id;
    END IF;
    SELECT coalesce(max(c.cycle_no), 0) + 1 INTO v_no FROM people.pg_cycle c WHERE c.student_id = x.student_id;
    INSERT INTO people.pg_cycle (student_id, cycle_no, qualification, programme_code, start_session, status, source, restart_of, created_by, created_office)
    SELECT x.student_id, v_no, old.qualification, s.programme_code, x.start_session, 'ACTIVE', 'RESTART', old.id, v_actor, nullif(current_setting('moaum.actor_office', true), '')
      FROM people.student s WHERE s.id = x.student_id
    RETURNING id INTO v_new;
    SELECT st.code INTO v_first FROM admissions.pg_stage st WHERE st.qualification = old.qualification AND st.sequence = 1;
    INSERT INTO people.pg_cycle_stage (cycle_id, session, stage_code, source, reason, decided_by, decided_office)
    VALUES (v_new, x.start_session, v_first, 'RESTART', 'Restart ' || x.reference, v_actor, nullif(current_setting('moaum.actor_office', true), ''));
    UPDATE people.pg_restart_request r SET state = 'APPROVED', decided_by = v_actor, decided_office = nullif(current_setting('moaum.actor_office', true), ''),
           decided_at = now(), decision_note = nullif(btrim(coalesce(p_note, '')), ''), new_cycle_id = v_new
     WHERE r.id = x.id;
    state := 'APPROVED'; new_cycle_id := v_new; cycle_no := v_no; stage_code := v_first;
    RETURN NEXT;
END $$;

CREATE OR REPLACE FUNCTION admissions.pg_restart_cancel(p_reference text, p_note text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE x people.pg_restart_request; v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    SELECT * INTO x FROM people.pg_restart_request WHERE reference = p_reference FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PG_RESTART_UNKNOWN: no such restart request' USING ERRCODE = '23514';
    END IF;
    IF NOT (admissions.pg_may(v_office, 'MANAGE_PG_ACADEMIC_CYCLE') OR (admissions.pg_may(v_office, 'REQUEST_PG_RESTART') AND v_office = x.requested_office)) THEN
        RAISE EXCEPTION 'PG_NOT_PERMITTED: the requesting office or the PG School withdraws a restart request' USING ERRCODE = '42501';
    END IF;
    IF x.state NOT IN ('REQUESTED', 'UNDER_REVIEW') THEN
        RAISE EXCEPTION 'PG_RESTART_STATE: the request is % already', lower(replace(x.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', coalesce(nullif(btrim(coalesce(p_note, '')), ''), 'Restart request withdrawn'), true);
    UPDATE people.pg_restart_request SET state = 'CANCELLED', decision_note = nullif(btrim(coalesce(p_note, '')), ''), decided_at = now(),
           decided_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, decided_office = v_office
     WHERE id = x.id;
    RETURN 'CANCELLED';
END $$;

-- ── the existing PG students: scanned, previewed, then committed as cycle 1 ──
CREATE OR REPLACE FUNCTION admissions.pg_cycle_scan(p_session text)
RETURNS TABLE(student_id uuid, qualification text, programme_code text, current_level integer, entry_session text, status text,
              stage_code text, stage_label text, category text, beyond boolean, recommendation text, confidence text, notes text[])
LANGUAGE sql
STABLE
AS $$
    SELECT s.id, x.qualification, s.programme_code, s.current_level, s.entry_session, s.status, x.stage_code, x.stage_label, x.category,
           x.beyond, x.recommendation,
           CASE WHEN x.qualification IS NULL OR s.entry_session IS NULL OR s.entry_session !~ '^[0-9]{4}/[0-9]{4}$' THEN 'LOW'
                WHEN s.current_level IS DISTINCT FROM q.level THEN 'MEDIUM'
                ELSE 'HIGH' END,
           array_remove(ARRAY[
               CASE WHEN x.qualification IS NULL THEN 'No qualification can be read from the programme' END,
               CASE WHEN s.entry_session IS NULL OR s.entry_session !~ '^[0-9]{4}/[0-9]{4}$' THEN 'No admission session on the record' END,
               CASE WHEN q.level IS NOT NULL AND s.current_level IS DISTINCT FROM q.level THEN 'The record is at ' || coalesce(s.current_level::text, 'no') || ' Level, the programme a ' || q.level || ' Level qualification' END,
               CASE WHEN x.beyond THEN 'Past the maximum period: the cycle is recorded as exhausted' END,
               CASE WHEN s.status = 'GRADUATED' THEN 'Graduated: the cycle is recorded as graduated' END], NULL)
      FROM admissions.pg_stages_of(p_session, NULL) x
      JOIN people.student s ON s.id = x.student_id
      LEFT JOIN admissions.pg_qualification q ON q.code = x.qualification
     WHERE x.cycle_id IS NULL
       AND NOT EXISTS (SELECT 1 FROM people.pg_cycle c WHERE c.student_id = s.id)
$$;
COMMENT ON FUNCTION admissions.pg_cycle_scan(text) IS
  'V651: the PG students with no cycle recorded — the qualification, the stage the calendar gives in the session, fresh or returning, the recommendation, and how sure the reading is (HIGH, MEDIUM where the record''s level is not the programme''s, LOW without a qualification or an admission session). Nothing is written.';

CREATE OR REPLACE FUNCTION admissions.pg_cycle_commit(p_students uuid[], p_session text, p_reason text)
RETURNS TABLE(student_id uuid, outcome text, cycle_id uuid, cycle_status text, stage_code text)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE r record; v_id uuid; v_status text; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    PERFORM admissions.pg_require('MANAGE_PG_ACADEMIC_CYCLE');
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_session) THEN
        RAISE EXCEPTION 'PG_STAGE_SESSION: % is not a session on the calendar', p_session USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Postgraduate cycles reconciled'), true);
    FOR r IN SELECT x.* FROM admissions.pg_cycle_scan(p_session) x WHERE x.student_id = ANY (p_students) LOOP
        student_id := r.student_id; cycle_id := NULL; cycle_status := NULL; stage_code := NULL;
        IF r.confidence = 'LOW' THEN
            outcome := 'SKIPPED_LOW_CONFIDENCE';
            RETURN NEXT;
            CONTINUE;
        END IF;
        v_status := CASE WHEN r.status = 'GRADUATED' THEN 'GRADUATED' WHEN r.beyond THEN 'MAXIMUM_PERIOD_EXHAUSTED' ELSE 'ACTIVE' END;
        INSERT INTO people.pg_cycle (student_id, cycle_no, qualification, programme_code, start_session, status, status_reason, status_at, status_by,
                                     source, created_by, created_office)
        VALUES (r.student_id, 1, r.qualification, r.programme_code, r.entry_session, v_status,
                CASE v_status WHEN 'ACTIVE' THEN NULL WHEN 'GRADUATED' THEN 'Graduated before the cycles were recorded'
                     ELSE 'Past the maximum period when the cycles were recorded (' || p_session || ')' END,
                CASE WHEN v_status <> 'ACTIVE' THEN now() END, CASE WHEN v_status <> 'ACTIVE' THEN v_actor END,
                'RECONCILIATION', v_actor, v_office)
        RETURNING id INTO v_id;
        IF v_status = 'ACTIVE' AND r.stage_code IS NOT NULL THEN
            INSERT INTO people.pg_cycle_stage (cycle_id, session, stage_code, source, reason, decided_by, decided_office)
            VALUES (v_id, p_session, r.stage_code, 'RECONCILIATION', 'Recorded when the PG cycles were reconciled', v_actor, v_office);
            stage_code := r.stage_code;
        END IF;
        outcome := 'RECORDED'; cycle_id := v_id; cycle_status := v_status;
        RETURN NEXT;
    END LOOP;
END $$;
COMMENT ON FUNCTION admissions.pg_cycle_commit(uuid[], text, text) IS
  'V651: the reconciliation committed for the PG students chosen — cycle 1 from the admission session, ACTIVE with the session''s stage recorded, or recorded as exhausted (past the maximum) or graduated; a LOW-confidence reading is skipped for the School to put right first. Nothing about the student record changes.';

-- ── what is wrong with the PG register, listed, never repaired by itself ──
CREATE OR REPLACE FUNCTION admissions.pg_data_quality(p_session text)
RETURNS TABLE(student_id uuid, issue text, detail text)
LANGUAGE sql
STABLE
AS $$
    WITH x AS MATERIALIZED (
        SELECT g.*, s.current_level, s.entry_session, s.status, q.level AS q_level
          FROM admissions.pg_stages_of(p_session, NULL) g
          JOIN people.student s ON s.id = g.student_id
          LEFT JOIN admissions.pg_qualification q ON q.code = g.qualification
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION'))
    SELECT x.student_id, 'NO_QUALIFICATION', 'No qualification can be read from the programme' FROM x WHERE x.qualification IS NULL
    UNION ALL
    SELECT x.student_id, 'LEVEL_MISMATCH', 'At ' || coalesce(x.current_level::text, 'no') || ' Level in a ' || x.q_level || ' Level qualification'
      FROM x WHERE x.q_level IS NOT NULL AND x.current_level IS DISTINCT FROM x.q_level
    UNION ALL
    SELECT x.student_id, 'NO_ADMISSION_SESSION', 'No admission session on the record' FROM x WHERE x.entry_session IS NULL OR x.entry_session !~ '^[0-9]{4}/[0-9]{4}$'
    UNION ALL
    SELECT x.student_id, 'NO_CYCLE', 'No cycle recorded: read as cycle 1 from ' || coalesce(x.start_session, 'no session') FROM x WHERE x.cycle_id IS NULL
    UNION ALL
    SELECT x.student_id, 'BEYOND_MAXIMUM', 'Past the maximum period in ' || p_session FROM x WHERE x.recommendation = 'MAXIMUM_PERIOD_REACHED'
    UNION ALL
    SELECT x.student_id, 'RESTART_REQUIRED', 'The cycle exhausted its maximum period and no restart is open'
      FROM x WHERE x.recommendation = 'RESTART_REQUIRED'
       AND NOT EXISTS (SELECT 1 FROM people.pg_restart_request r WHERE r.student_id = x.student_id AND r.state IN ('REQUESTED', 'UNDER_REVIEW'))
    UNION ALL
    SELECT x.student_id, 'NO_STAGE_RECORDED', 'The stage of ' || p_session || ' is calculated (' || coalesce(x.stage_label, '—') || '), not recorded'
      FROM x WHERE x.cycle_id IS NOT NULL AND x.cycle_status = 'ACTIVE' AND NOT x.official AND x.recommendation IN ('NORMAL_PROGRESS', 'EXTENSION_REQUIRED')
$$;

-- ── the counts by stage, for the School's dashboard and the department's ──
CREATE OR REPLACE FUNCTION admissions.pg_stage_counts(p_session text, p_faculty text DEFAULT NULL, p_dept text DEFAULT NULL)
RETURNS TABLE(qualification text, stage_code text, stage_label text, sequence integer, is_extension boolean, students bigint, male bigint, female bigint,
              fresh bigint, returning_ bigint, official bigint, registered bigint, paid bigint)
LANGUAGE sql
STABLE
AS $$
    WITH x AS MATERIALIZED (
        SELECT g.*, s.sex,
               EXISTS (SELECT 1 FROM registration.course_registration cr WHERE cr.student_id = g.student_id AND cr.session = p_session) AS registered,
               EXISTS (SELECT 1 FROM finance.payment_reference pr WHERE pr.student_id = g.student_id AND pr.session = p_session
                         AND pr.confirmed_at IS NOT NULL AND pr.purpose LIKE 'School fees%') AS paid
          FROM admissions.pg_stages_of(p_session, NULL) g
          JOIN people.student s ON s.id = g.student_id
          JOIN ref.programme p ON p.code = s.programme_code
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
           AND (p_faculty IS NULL OR p.faculty_code = p_faculty) AND (p_dept IS NULL OR p.dept_code = p_dept))
    SELECT st.qualification, st.code, st.label, st.sequence, st.extension_number IS NOT NULL,
           count(x.student_id), count(x.student_id) FILTER (WHERE upper(left(x.sex, 1)) = 'M'), count(x.student_id) FILTER (WHERE upper(left(x.sex, 1)) = 'F'),
           count(x.student_id) FILTER (WHERE x.category = 'FRESH'), count(x.student_id) FILTER (WHERE x.category = 'RETURNING'),
           count(x.student_id) FILTER (WHERE x.official), count(x.student_id) FILTER (WHERE x.registered), count(x.student_id) FILTER (WHERE x.paid)
      FROM admissions.pg_stage st
      LEFT JOIN x ON x.stage_code = st.code AND x.cycle_status IN ('ACTIVE', 'NOT_RECORDED')
     WHERE st.active
     GROUP BY st.qualification, st.code, st.label, st.sequence, st.extension_number
    UNION ALL
    -- the students past the maximum, and the cycles closed as exhausted awaiting a restart, under their qualification
    SELECT x.qualification, NULL, CASE x.recommendation WHEN 'MAXIMUM_PERIOD_REACHED' THEN 'Past the maximum period' ELSE 'Restart required' END, 99, false,
           count(*), count(*) FILTER (WHERE upper(left(x.sex, 1)) = 'M'), count(*) FILTER (WHERE upper(left(x.sex, 1)) = 'F'),
           0, count(*), count(*) FILTER (WHERE x.official), count(*) FILTER (WHERE x.registered), count(*) FILTER (WHERE x.paid)
      FROM x WHERE x.recommendation IN ('MAXIMUM_PERIOD_REACHED', 'RESTART_REQUIRED')
     GROUP BY x.qualification, x.recommendation
$$;

-- ── changing the structure: the normal and extension years and the labels of a qualification's stages ──
CREATE OR REPLACE FUNCTION admissions.pg_set_qualification(p_code text, p_label text, p_normal integer, p_extension integer, p_restart boolean, p_labels jsonb)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE q admissions.pg_qualification; n int; i int; v_code text; v_label text; v_short text; v_letter text;
BEGIN
    PERFORM admissions.pg_require('MANAGE_PG_LEVEL_STRUCTURE');
    SELECT * INTO q FROM admissions.pg_qualification WHERE code = p_code FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PG_QUALIFICATION_UNKNOWN: no such qualification' USING ERRCODE = '23514';
    END IF;
    IF p_normal IS NULL OR p_normal NOT BETWEEN 1 AND 6 OR p_extension IS NULL OR p_extension NOT BETWEEN 0 AND 4 OR p_normal + p_extension > 10 THEN
        RAISE EXCEPTION 'PG_QUALIFICATION_YEARS: one to six normal years and up to four extension years' USING ERRCODE = '23514';
    END IF;
    n := p_normal + p_extension;
    -- a stage taken out of use while students of the running session are recorded at it is refused
    IF EXISTS (SELECT 1 FROM people.pg_cycle_stage cs JOIN admissions.pg_stage st ON st.code = cs.stage_code JOIN people.pg_cycle c ON c.id = cs.cycle_id
                WHERE st.qualification = p_code AND st.sequence > n AND c.status = 'ACTIVE' AND cs.session = admissions.pg_current_session()) THEN
        RAISE EXCEPTION 'PG_STAGE_IN_USE: students are recorded this session at a stage the change would take out of use' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.pg_qualification SET label = coalesce(nullif(btrim(coalesce(p_label, '')), ''), label), normal_years = p_normal,
           extension_years = p_extension, restart_allowed = coalesce(p_restart, restart_allowed), updated_at = now()
     WHERE code = p_code;
    FOR i IN 1..n LOOP
        v_letter := chr(64 + i);
        v_code := q.level || v_letter;
        v_short := CASE WHEN p_normal = 1 AND n <= 2 THEN CASE WHEN i = 1 THEN q.level::text ELSE q.level || ' Extension' END ELSE q.level || ' ' || v_letter END;
        v_label := coalesce(nullif(btrim(coalesce(p_labels ->> (i - 1), '')), ''),
                            CASE WHEN p_normal = 1 AND n <= 2 THEN CASE WHEN i = 1 THEN q.level || ' Level' ELSE q.level || ' Extension' END
                                 WHEN i <= p_normal THEN v_short || ' — Year ' || i
                                 WHEN p_extension = 1 THEN v_short || ' — Extension'
                                 ELSE v_short || ' — Extension ' || (i - p_normal) END);
        INSERT INTO admissions.pg_stage (code, qualification, label, short_label, sequence, year_number, extension_number, active)
        VALUES (v_code, p_code, v_label, v_short, i, CASE WHEN i <= p_normal THEN i END, CASE WHEN i > p_normal THEN i - p_normal END, true)
        ON CONFLICT (code) DO UPDATE SET label = EXCLUDED.label, short_label = EXCLUDED.short_label, sequence = EXCLUDED.sequence,
               year_number = EXCLUDED.year_number, extension_number = EXCLUDED.extension_number, active = true;
    END LOOP;
    UPDATE admissions.pg_stage SET active = false WHERE qualification = p_code AND sequence > n AND active;
    RETURN n;
END $$;
COMMENT ON FUNCTION admissions.pg_set_qualification(text, text, integer, integer, boolean, jsonb) IS
  'V651: a qualification''s normal and extension years and its stages'' labels, as the PG School sets them; stages beyond the new total are taken out of use (kept, never deleted), refused while students of the running session are recorded at one.';

-- ── a PG student's school-fees reference names the cycle, stage and category it was raised under ──
CREATE TABLE finance.payment_pg_context (
    reference_id uuid PRIMARY KEY REFERENCES finance.payment_reference(id) ON DELETE CASCADE,
    student_id uuid NOT NULL,
    session text NOT NULL,
    cycle_id uuid REFERENCES people.pg_cycle(id) ON DELETE SET NULL,
    cycle_no integer,
    qualification text,
    stage_code text,
    category text,
    official boolean,
    recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_payment_pg_context_student ON finance.payment_pg_context (student_id, session);
SELECT audit.attach('finance.payment_pg_context');
COMMENT ON TABLE finance.payment_pg_context IS
  'V651: the postgraduate cycle, stage and fresh/returning category a PG student''s school-fees reference was raised under (as admissions.pg_stages_of read it then), so a payment is never taken for another cycle''s.';

CREATE OR REPLACE FUNCTION finance.trg_payment_pg_context()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO finance.payment_pg_context (reference_id, student_id, session, cycle_id, cycle_no, qualification, stage_code, category, official)
    SELECT NEW.id, NEW.student_id, NEW.session, x.cycle_id, x.cycle_no, x.qualification, x.stage_code, x.category, x.official
      FROM admissions.pg_stages_of(NEW.session, ARRAY[NEW.student_id]) x
    ON CONFLICT (reference_id) DO NOTHING;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_payment_pg_context AFTER INSERT ON finance.payment_reference
    FOR EACH ROW WHEN (NEW.purpose LIKE 'School fees%' AND NEW.student_id IS NOT NULL AND NEW.session IS NOT NULL)
    EXECUTE FUNCTION finance.trg_payment_pg_context();

COMMIT;
