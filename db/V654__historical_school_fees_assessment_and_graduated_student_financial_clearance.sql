-- V654: historical school fees assessment, graduated student financial clearance and the session/semester outstanding balance —
-- the University's master prompt of 25 October 2026 ("HISTORICAL SCHOOL FEES ASSESSMENT, GRADUATED STUDENT CLEARANCE &
-- SESSION/SEMESTER OUTSTANDING BALANCE"). A student who graduated without paying a semester's school fees returns for clearance;
-- the University must show what is owed, session by session and semester by semester, against the fees of that period — never
-- today's — and the Bursary clears the student financially only when it is settled. Graduation is never undone by a debt.
--
-- What stood: finance.position reads a session's fee lines for the student as the student is NOW (the level today, spillover
-- today), right for the current session and wrong for a past one (a 400 Level graduate read 400 Level lines in their 100 Level
-- year); the FINAL clearance's Bursary stage read it for every session enrolled in and skipped a session with no fee stated, so a
-- graduate cleared financially though a session's fees were never known; new_reference refuses a past session (its payment
-- window closed), so a graduate could not settle an old balance online; and there was no assessment where a session's fee
-- structure is missing or a student's fee was legitimately different.
--
--   · finance.historical_setting: the session historical fees are assessed from (the Bursar's choice; none set, the first session
--     the fee setup holds a line for) and whether graduates pay online.
--   · finance.historical_grant: who may view, create, submit, approve, return, reject, correct, process clearance, report.
--   · finance.historical_structure(student, session, level): a session's fee lines matched to the student AS THEY WERE in it — the
--     level of that session (people.level_in), spillover read from that level against the programme's final level — semester by
--     semester (the whole-session lines due with the first semester, as finance.due_for_semester reads them).
--   · finance.historical_assessment (HFA/YYYY/NNNNNN): an amount for a student's session and semester where the structure is
--     missing or the student's fee was different — its source (HISTORICAL_FEE_STRUCTURE … OTHER_APPROVED_SOURCE), components,
--     reason and evidence; created and submitted by the Students Account Officer, approved, returned or rejected by the Bursar (never
--     the officer who made it); approved, it is not edited — a correction is a new assessment that supersedes it; batches
--     (HFA-B/YYYY/NNNNNN) for a cohort, previewed before they are made.
--   · finance.historical_rows(students): the historical account — every session and semester from the start (or admission) to the
--     graduation session (to the session before the current one for a student still studying): the level, the amount assessed and
--     where it came from (an approved assessment, else the fee structure, else nothing: REQUIRES_REVIEW), the verified school-fee
--     payments of the session allocated first semester first, the outstanding and any credit; a pending assessment named, never
--     owed. finance.historical_summary keeps each student's totals and financial status (FINANCIALLY_CLEARED,
--     FINANCIAL_OBLIGATION, FINANCIAL_CLEARANCE_PENDING, HISTORICAL_FEE_REVIEW_REQUIRED) for the lists and dashboards, refreshed
--     when a payment is confirmed or an assessment decided, and on demand.
--   · finance.historical_reference: a graduate pays an approved historical balance online, outside the session's window, never more
--     than is owed; the payment is the session's school fees ("School fees 2021/2022 (historical)"), so every reader counts it.
--   · The FINAL clearance's Bursary stage reads the historical account: outstanding, review and pending named, never cleared over them.
-- Nothing here changes a student's status, level, programme, results, registrations or a payment.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V654: historical school fees assessment and graduated student financial clearance (the University, 25 October 2026)', true);

-- ── 1 · the setting ──
CREATE TABLE finance.historical_setting (
    id integer PRIMARY KEY CHECK (id = 1),
    assess_from text REFERENCES policy.academic_session (name),
    online_payment boolean NOT NULL DEFAULT true,
    set_by uuid,
    set_office text,
    set_at timestamptz,
    reason text,
    refreshed_at timestamptz
);
INSERT INTO finance.historical_setting (id) VALUES (1);
SELECT audit.attach('finance.historical_setting');
COMMENT ON TABLE finance.historical_setting IS
  'V654: the session historical school fees are assessed from (NULL: the first session the fee setup holds a line for — the University''s answer of 25 October 2026: nothing older is assessed or blocks a clearance until the Bursar moves the start back), whether graduates pay a historical balance online, and when the summary was last refreshed in full.';

CREATE OR REPLACE FUNCTION finance.historical_start()
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce((SELECT s.assess_from FROM finance.historical_setting s WHERE s.id = 1),
                    (SELECT min(f.session) FROM finance.fee_schedule f WHERE f.ended_at IS NULL AND f.kind = 'FEE'))
$$;
COMMENT ON FUNCTION finance.historical_start() IS 'V654: the first session historical school fees are assessed for — the Bursar''s, else the first session the fee setup holds a line for.';

-- ── 2 · who may do what ──
CREATE TABLE finance.historical_grant (
    office_code text NOT NULL,
    permission text NOT NULL CHECK (permission IN (
        'VIEW_HISTORICAL_FEE_ASSESSMENT', 'CREATE_HISTORICAL_FEE_ASSESSMENT', 'EDIT_HISTORICAL_FEE_ASSESSMENT', 'SUBMIT_HISTORICAL_FEE_ASSESSMENT',
        'REVIEW_HISTORICAL_FEE_ASSESSMENT', 'APPROVE_HISTORICAL_FEE_ASSESSMENT', 'REJECT_HISTORICAL_FEE_ASSESSMENT', 'RETURN_HISTORICAL_FEE_ASSESSMENT',
        'VIEW_FINANCIAL_CLEARANCE', 'PROCESS_FINANCIAL_CLEARANCE', 'APPROVE_FINANCIAL_CLEARANCE', 'VIEW_HISTORICAL_PAYMENT',
        'VIEW_HISTORICAL_FEE_REPORT', 'EXPORT_HISTORICAL_FEE_REPORT', 'CORRECT_HISTORICAL_ASSESSMENT', 'VIEW_ASSESSMENT_HISTORY',
        'SET_HISTORICAL_FEE_START')),
    granted_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (office_code, permission)
);
SELECT audit.attach('finance.historical_grant');
COMMENT ON TABLE finance.historical_grant IS
  'V654: what each office may do with historical school fees. The Bursar''s office approves, returns and rejects, sets the start and approves financial clearance; the Students Account Officer reviews, creates, edits, submits and proposes corrections; Internal Audit and the Registry read. Checked by the API and by the functions.';

INSERT INTO finance.historical_grant (office_code, permission)
SELECT o, p FROM unnest(ARRAY['bursar', 'super']) o
CROSS JOIN unnest(ARRAY['VIEW_HISTORICAL_FEE_ASSESSMENT', 'CREATE_HISTORICAL_FEE_ASSESSMENT', 'EDIT_HISTORICAL_FEE_ASSESSMENT', 'SUBMIT_HISTORICAL_FEE_ASSESSMENT',
                        'REVIEW_HISTORICAL_FEE_ASSESSMENT', 'APPROVE_HISTORICAL_FEE_ASSESSMENT', 'REJECT_HISTORICAL_FEE_ASSESSMENT', 'RETURN_HISTORICAL_FEE_ASSESSMENT',
                        'VIEW_FINANCIAL_CLEARANCE', 'PROCESS_FINANCIAL_CLEARANCE', 'APPROVE_FINANCIAL_CLEARANCE', 'VIEW_HISTORICAL_PAYMENT',
                        'VIEW_HISTORICAL_FEE_REPORT', 'EXPORT_HISTORICAL_FEE_REPORT', 'CORRECT_HISTORICAL_ASSESSMENT', 'VIEW_ASSESSMENT_HISTORY',
                        'SET_HISTORICAL_FEE_START']) p
UNION ALL
SELECT 'studentaccounts', p FROM unnest(ARRAY['VIEW_HISTORICAL_FEE_ASSESSMENT', 'CREATE_HISTORICAL_FEE_ASSESSMENT', 'EDIT_HISTORICAL_FEE_ASSESSMENT',
                                              'SUBMIT_HISTORICAL_FEE_ASSESSMENT', 'REVIEW_HISTORICAL_FEE_ASSESSMENT', 'VIEW_FINANCIAL_CLEARANCE',
                                              'PROCESS_FINANCIAL_CLEARANCE', 'VIEW_HISTORICAL_PAYMENT', 'VIEW_HISTORICAL_FEE_REPORT', 'EXPORT_HISTORICAL_FEE_REPORT',
                                              'CORRECT_HISTORICAL_ASSESSMENT', 'VIEW_ASSESSMENT_HISTORY']) p
UNION ALL
SELECT o, p FROM unnest(ARRAY['audit', 'deputyaudit']) o
CROSS JOIN unnest(ARRAY['VIEW_HISTORICAL_FEE_ASSESSMENT', 'VIEW_FINANCIAL_CLEARANCE', 'VIEW_HISTORICAL_PAYMENT', 'VIEW_HISTORICAL_FEE_REPORT',
                        'EXPORT_HISTORICAL_FEE_REPORT', 'VIEW_ASSESSMENT_HISTORY']) p
UNION ALL
SELECT o, p FROM unnest(ARRAY['registrar', 'dregistrar', 'academic', 'records', 'vc', 'dvc', 'ict', 'admin']) o
CROSS JOIN unnest(ARRAY['VIEW_HISTORICAL_FEE_ASSESSMENT', 'VIEW_FINANCIAL_CLEARANCE', 'VIEW_HISTORICAL_FEE_REPORT', 'VIEW_ASSESSMENT_HISTORY']) p
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION finance.historical_permissions(p_office text)
RETURNS text[]
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce((SELECT array_agg(g.permission ORDER BY g.permission) FROM finance.historical_grant g WHERE g.office_code = p_office), '{}')
$$;

CREATE OR REPLACE FUNCTION finance.historical_may(p_office text, p_permission text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (SELECT 1 FROM finance.historical_grant g WHERE g.office_code = coalesce(p_office, '') AND g.permission = p_permission)
$$;

-- the acting office (moaum.actor_office, set for every request) must hold the permission
CREATE OR REPLACE FUNCTION finance.historical_require(p_permission text)
RETURNS void
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF NOT finance.historical_may(nullif(current_setting('moaum.actor_office', true), ''), p_permission) THEN
        RAISE EXCEPTION 'HFA_NOT_PERMITTED: your office does not hold % for historical school fees', p_permission USING ERRCODE = '42501';
    END IF;
END $$;

-- ── 3 · the assessments, their batches, evidence and timeline ──
CREATE TABLE finance.historical_batch (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference text NOT NULL UNIQUE CHECK (reference ~ '^HFA-B/[0-9]{4}/[0-9]{6}$'),
    session text NOT NULL REFERENCES policy.academic_session (name),
    semester integer NOT NULL CHECK (semester BETWEEN 1 AND 3),
    scope jsonb NOT NULL DEFAULT '{}'::jsonb,
    amount numeric(14, 2) NOT NULL CHECK (amount > 0),
    components jsonb NOT NULL DEFAULT '[]'::jsonb,
    source text NOT NULL,
    source_reference text,
    reason text NOT NULL,
    students integer NOT NULL DEFAULT 0,
    state text NOT NULL DEFAULT 'PENDING_BURSAR_APPROVAL'
        CHECK (state IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION', 'APPROVED', 'REJECTED', 'CANCELLED')),
    created_by uuid NOT NULL,
    created_office text,
    created_at timestamptz NOT NULL DEFAULT now(),
    decided_by uuid,
    decided_office text,
    decided_at timestamptz,
    decision_note text
);
SELECT audit.attach('finance.historical_batch');
COMMENT ON TABLE finance.historical_batch IS
  'V654: a cohort''s historical assessment — one amount for the students chosen from a preview (session, semester, faculty, department, programme, level), each student''s assessment its own row; decided by the Bursar together.';

CREATE TABLE finance.historical_assessment (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference text NOT NULL UNIQUE CHECK (reference ~ '^HFA/[0-9]{4}/[0-9]{6}$'),
    student_id uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    session text NOT NULL REFERENCES policy.academic_session (name),
    semester integer NOT NULL CHECK (semester BETWEEN 1 AND 3),
    level integer,
    programme_code text REFERENCES ref.programme (code),
    faculty_code text,
    dept_code text,
    amount numeric(14, 2) NOT NULL CHECK (amount > 0),
    components jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(components) = 'array'),
    source text NOT NULL CHECK (source IN ('HISTORICAL_FEE_STRUCTURE', 'HISTORICAL_FEE_VERSION', 'COHORT_FEE_RECORD', 'STUDENT_SPECIFIC_APPROVED_FEE',
                                           'OFFICIAL_FEE_DOCUMENT', 'MANUAL_HISTORICAL_ASSESSMENT', 'LEGACY_MIGRATION', 'OTHER_APPROVED_SOURCE')),
    source_reference text,
    reason text NOT NULL CHECK (length(btrim(reason)) >= 20),
    remarks text,
    batch_id uuid REFERENCES finance.historical_batch (id),
    corrects uuid REFERENCES finance.historical_assessment (id),
    state text NOT NULL DEFAULT 'DRAFT'
        CHECK (state IN ('DRAFT', 'PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION', 'APPROVED', 'REJECTED', 'CANCELLED', 'SUPERSEDED')),
    created_by uuid NOT NULL,
    created_office text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    submitted_by uuid,
    submitted_at timestamptz,
    decided_by uuid,
    decided_office text,
    decided_at timestamptz,
    decision_note text,
    superseded_by uuid REFERENCES finance.historical_assessment (id),
    CONSTRAINT ck_hfa_two_officers CHECK (decided_by IS NULL OR state NOT IN ('APPROVED', 'SUPERSEDED') OR decided_by <> created_by)
);
-- one assessment in force, and one being made, for a student's session and semester
CREATE UNIQUE INDEX ux_hfa_approved ON finance.historical_assessment (student_id, session, semester) WHERE state = 'APPROVED';
CREATE UNIQUE INDEX ux_hfa_open ON finance.historical_assessment (student_id, session, semester)
    WHERE state IN ('DRAFT', 'PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION');
CREATE INDEX ix_hfa_state ON finance.historical_assessment (state, submitted_at);
CREATE INDEX ix_hfa_batch ON finance.historical_assessment (batch_id) WHERE batch_id IS NOT NULL;
SELECT audit.attach('finance.historical_assessment');
COMMENT ON TABLE finance.historical_assessment IS
  'V654: what a student should have paid for a past session''s semester where the fee structure is missing or the student''s fee was legitimately different — with its source, components, reason and evidence. Only an APPROVED assessment is owed; once approved it is never edited: a correction is a new assessment that supersedes it.';
-- a programme merge (V574) leaves the assessment's programme as it was when the period was assessed (an approved one is never changed)
INSERT INTO ref.programme_reference (tab, col, policy, note)
VALUES ('finance.historical_assessment', 'programme_code', 'KEEP', 'history: the programme the student was on when the period was assessed');

-- an approved assessment is kept as it was: only superseded by a correction
CREATE OR REPLACE FUNCTION finance.trg_hfa_kept()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.state IN ('APPROVED', 'SUPERSEDED', 'REJECTED', 'CANCELLED') AND current_setting('moaum.maintenance', true) IS DISTINCT FROM 'on' THEN
        IF NOT (OLD.state = 'APPROVED' AND NEW.state = 'SUPERSEDED' AND NEW.superseded_by IS NOT NULL)
           OR (NEW.amount, NEW.session, NEW.semester, NEW.student_id, NEW.components, NEW.source, NEW.reason)
              IS DISTINCT FROM (OLD.amount, OLD.session, OLD.semester, OLD.student_id, OLD.components, OLD.source, OLD.reason) THEN
            RAISE EXCEPTION 'HFA_KEPT: % is % and is kept as it is — a correction is a new assessment', OLD.reference, lower(OLD.state) USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_hfa_kept BEFORE UPDATE ON finance.historical_assessment FOR EACH ROW EXECUTE FUNCTION finance.trg_hfa_kept();

CREATE TABLE finance.historical_assessment_evidence (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id uuid NOT NULL REFERENCES finance.historical_assessment (id) ON DELETE CASCADE,
    filename text NOT NULL,
    content_type text NOT NULL,
    size_bytes bigint NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 5242880),
    content bytea NULL,
    object_id uuid NULL REFERENCES platform.file_object (id),
    added_by uuid NOT NULL,
    added_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_hfa_evidence_where CHECK (num_nonnulls(content, object_id) = 1)
);
CREATE INDEX ix_hfa_evidence ON finance.historical_assessment_evidence (assessment_id);
COMMENT ON TABLE finance.historical_assessment_evidence IS 'V654: a file supporting a historical assessment (an approved fee schedule, a circular, an old record) — in the file store where there is one, else here';
SELECT audit.exempt('finance.historical_assessment_evidence', 'V654: file bytes; who added which file and when is the row itself, and the assessment it supports is on the audit spine');

CREATE TABLE finance.historical_assessment_event (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id uuid NOT NULL REFERENCES finance.historical_assessment (id) ON DELETE CASCADE,
    action text NOT NULL CHECK (action IN ('CREATED', 'EDITED', 'SUBMITTED', 'RETURNED', 'APPROVED', 'REJECTED', 'CANCELLED', 'SUPERSEDED', 'EVIDENCE_ADDED')),
    actor uuid,
    office text,
    note text,
    amount numeric(14, 2),
    at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX ix_hfa_event ON finance.historical_assessment_event (assessment_id, at);
SELECT audit.attach('finance.historical_assessment_event');
COMMENT ON TABLE finance.historical_assessment_event IS 'V654: the timeline of a historical assessment, written once per act';

-- ── 4 · the summary the lists and dashboards read, and the students whose summary is to be worked out again ──
CREATE TABLE finance.historical_summary (
    student_id uuid PRIMARY KEY REFERENCES people.student (id) ON DELETE CASCADE,
    first_session text,
    last_session text,
    periods integer NOT NULL DEFAULT 0,
    assessed numeric(14, 2) NOT NULL DEFAULT 0,
    paid numeric(14, 2) NOT NULL DEFAULT 0,
    outstanding numeric(14, 2) NOT NULL DEFAULT 0,
    credit numeric(14, 2) NOT NULL DEFAULT 0,
    owing_periods integer NOT NULL DEFAULT 0,
    review_periods integer NOT NULL DEFAULT 0,
    pending_periods integer NOT NULL DEFAULT 0,
    partial_periods integer NOT NULL DEFAULT 0,
    owing text,
    financial_status text NOT NULL CHECK (financial_status IN ('FINANCIALLY_CLEARED', 'FINANCIAL_OBLIGATION', 'FINANCIAL_CLEARANCE_PENDING',
                                                                'HISTORICAL_FEE_REVIEW_REQUIRED', 'NO_HISTORICAL_PERIOD')),
    last_payment_at timestamptz,
    refreshed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_hsum_status ON finance.historical_summary (financial_status);
SELECT audit.exempt('finance.historical_summary', 'V654: a cache worked out from the fee lines, the approved assessments and the confirmed payments; nothing in it is decided by a person');
COMMENT ON TABLE finance.historical_summary IS
  'V654: each graduate''s (and graduand''s) historical account in totals — for the lists, the dashboards and the reports. Worked out by finance.historical_refresh; a confirmed school-fee payment or a decided assessment marks the student to be worked out again (finance.historical_stale).';

CREATE TABLE finance.historical_stale (
    student_id uuid PRIMARY KEY REFERENCES people.student (id) ON DELETE CASCADE,
    marked_at timestamptz NOT NULL DEFAULT now()
);
SELECT audit.exempt('finance.historical_stale', 'V654: a queue of summaries to work out again');

-- ── 5 · the historical account ──
-- the read for many students at once: every period (session, semester) from the start to the end of the record, the level of the
-- period, what is assessed and from where, what is paid (the session's verified school fees, first semester first) and owed
CREATE OR REPLACE FUNCTION finance.historical_rows_read(p_students uuid[])
RETURNS TABLE(student_id uuid, session text, semester integer, level integer, programme_code text, assessed numeric, source text, source_ref text,
              assessment_id uuid, structure_amount numeric, structure_lines integer, pending_id uuid, pending_ref text, pending_amount numeric,
              paid numeric, outstanding numeric, credit numeric, status text)
LANGUAGE sql
STABLE
AS $$
    WITH home AS MATERIALIZED (SELECT lower(home_state) AS home_state FROM finance.fee_setting WHERE id = 1),
    bounds AS MATERIALIZED (SELECT finance.historical_start() AS start,
                                   (SELECT max(a.name) FROM policy.academic_session a
                                     WHERE a.state NOT IN ('CANCELLED', 'DRAFT') AND a.name < coalesce(policy.university_current_session(), '9999/9999')) AS before_current),
    -- the calendar's order, as people.level_in counts the sessions since admission (every session row, by its start)
    cal AS MATERIALIZED (SELECT a.name, a.state, a.semesters, row_number() OVER (ORDER BY a.starts_on, a.name) AS idx FROM policy.academic_session a),
    st AS MATERIALIZED (
        SELECT s.id, s.programme_code, p.faculty_code, p.category, s.entry_mode, s.entry_session, s.entry_level, s.current_level,
               people.is_postgraduate(s.entry_mode, p.category) AS pg,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) = (SELECT h.home_state FROM home h) AS indigene,
               greatest(s.entry_session, b.start) AS first_session,
               CASE WHEN s.status = 'GRADUATED' OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED')
                    THEN records.graduation_session(s.id) ELSE b.before_current END AS last_session
          FROM unnest(p_students) u(id)
          JOIN people.student s ON s.id = u.id
          JOIN ref.programme p ON p.code = s.programme_code
          CROSS JOIN bounds b
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.entry_session IS NOT NULL),
    -- the programme's final level read once a programme
    fl AS MATERIALIZED (SELECT d.programme_code, finance.final_level(d.programme_code) AS final_level FROM (SELECT DISTINCT st.programme_code FROM st) d),
    per0 AS MATERIALIZED (
        -- the sessions of the record, each semester of each, a deferred session or semester left out
        SELECT st.*, fl.final_level, a.name AS session, sm.n AS semester, a.idx AS ses_idx
          FROM st
          JOIN fl ON fl.programme_code = st.programme_code
          JOIN cal a ON a.name >= st.first_session AND a.name <= st.last_session AND a.state NOT IN ('CANCELLED', 'DRAFT')
          CROSS JOIN LATERAL generate_series(1, a.semesters) sm(n)
         WHERE st.last_session IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM people.deferment d
                            WHERE d.student_id = st.id AND d.session = a.name AND d.state IN ('APPROVED', 'ACTIVE', 'COMPLETED')
                              AND (d.kind = 'SESSION' OR d.semester = sm.n))),
    -- the level of each period, read as people.level_in reads it — the semester's registration, else the session's, else the
    -- enrolment, else counted from admission (a postgraduate's own level) — for every student at once
    reg AS MATERIALIZED (SELECT r.student_id, r.session, r.semester, r.level, r.status IN ('APPROVED', 'LOCKED') AS ok
                           FROM registration.course_registration r WHERE r.student_id = ANY (p_students)),
    reg_sem AS (SELECT DISTINCT ON (g.student_id, g.session, g.semester) g.student_id, g.session, g.semester, g.level FROM reg g
                 ORDER BY g.student_id, g.session, g.semester, g.ok DESC),
    reg_ses AS (SELECT DISTINCT ON (g.student_id, g.session) g.student_id, g.session, g.level FROM reg g ORDER BY g.student_id, g.session, g.ok DESC, g.semester),
    enr AS (SELECT DISTINCT ON (e.student_id, e.session) e.student_id, e.session, e.level FROM people.enrolment e WHERE e.student_id = ANY (p_students)
             ORDER BY e.student_id, e.session),
    per AS MATERIALIZED (
        SELECT p0.*, coalesce(rs.level, rx.level, en.level,
                              CASE WHEN p0.pg THEN p0.current_level
                                   WHEN es.idx IS NOT NULL AND p0.ses_idx >= es.idx THEN least(600, p0.entry_level + 100 * (p0.ses_idx - es.idx)::int) END,
                              p0.current_level) AS level
          FROM per0 p0
          LEFT JOIN cal es ON es.name = p0.entry_session
          LEFT JOIN reg_sem rs ON rs.student_id = p0.id AND rs.session = p0.session AND rs.semester = p0.semester
          LEFT JOIN reg_ses rx ON rx.student_id = p0.id AND rx.session = p0.session
          LEFT JOIN enr en ON en.student_id = p0.id AND en.session = p0.session),
    ses AS MATERIALIZED (
        -- one profile a session: the student as they were in its first semester on the record
        SELECT DISTINCT ON (pe.id, pe.session) pe.* FROM per pe ORDER BY pe.id, pe.session, pe.semester),
    -- the faculty a faculty is charged as, read once a faculty and session; a PG student's stage read once a session
    src AS MATERIALIZED (SELECT d.faculty_code, d.session, finance.fee_source_of(d.faculty_code, d.session) AS src
                           FROM (SELECT DISTINCT x.faculty_code, x.session FROM ses x WHERE x.entry_mode IS DISTINCT FROM 'CCE' AND NOT x.pg) d),
    pgs AS MATERIALIZED (SELECT y.student_id, d.session, y.stage_code, y.category
                           FROM (SELECT x.session, array_agg(x.id) AS ids FROM ses x WHERE x.pg GROUP BY x.session) d
                           CROSS JOIN LATERAL admissions.pg_stages_of(d.session, d.ids) y),
    prof AS MATERIALIZED (
        -- the student as they were in the session: spillover read from its level against the programme's final level
        SELECT pe.*, coalesce(pe.level > pe.final_level, false) AS is_spill,
               CASE WHEN pe.level > pe.final_level THEN least((pe.level - pe.final_level) / 100, 3) END AS spill_year,
               CASE WHEN pe.level > pe.final_level THEN finance.reg_semesters(pe.id, pe.session) END AS reg_sems,   -- V616: read for a spillover student only
               sr.src, pg.stage_code AS pg_stage, pg.category AS pg_category
          FROM ses pe
          LEFT JOIN src sr ON sr.faculty_code = pe.faculty_code AND sr.session = pe.session AND pe.entry_mode IS DISTINCT FROM 'CCE' AND NOT pe.pg
          LEFT JOIN pgs pg ON pg.student_id = pe.id AND pg.session = pe.session),
    matched AS (
        -- the session's fee lines that reach the student as they were; a whole-session line is due with the first semester
        SELECT pr.id AS student_id, pr.session, coalesce(f.semester, 1) AS semester, f.amount
          FROM prof pr
          JOIN finance.fee_schedule f ON f.session = pr.session AND f.ended_at IS NULL AND f.kind = 'FEE'
          LEFT JOIN ref.fee_group g ON g.code = f.fee_group
         WHERE f.spillover = pr.is_spill
           AND (f.level IS NULL OR f.level = CASE WHEN pr.is_spill THEN pr.final_level ELSE pr.level END)
           AND (f.spill_year IS NULL OR f.spill_year = pr.spill_year)
           AND finance.spill_line_applies(pr.is_spill, f.semester, pr.reg_sems)
           AND ((f.entry_mode IS NULL AND pr.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = pr.entry_mode)
           AND (f.faculty_code IS NULL OR f.faculty_code = pr.faculty_code OR (f.faculty_code = pr.src AND f.programme_code IS NULL))
           AND (f.programme_code IS NULL OR f.programme_code = pr.programme_code)
           AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = pr.category)
           AND finance.pg_line(pr.entry_mode = 'POSTGRADUATE' OR pr.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)
           AND finance.pg_stage_line(f.pg_stage, f.fee_category, pr.pg_stage, pr.pg_category)
           AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = pr.indigene)),
    struct AS (SELECT m.student_id, m.session, m.semester, sum(m.amount) AS amount, count(*)::int AS lines FROM matched m GROUP BY 1, 2, 3),
    stated AS (SELECT DISTINCT m.student_id, m.session FROM matched m),
    apr AS (SELECT a.id, a.reference, a.student_id, a.session, a.semester, a.amount FROM finance.historical_assessment a
             WHERE a.student_id = ANY (p_students) AND a.state = 'APPROVED'),
    pend AS (SELECT a.id, a.reference, a.student_id, a.session, a.semester, a.amount FROM finance.historical_assessment a
              WHERE a.student_id = ANY (p_students) AND a.state IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION', 'DRAFT')),
    pay AS (SELECT r.student_id, r.session, sum(r.amount) AS paid FROM finance.payment_reference r
             WHERE r.student_id = ANY (p_students) AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
             GROUP BY 1, 2),
    base AS (
        SELECT pr.id AS student_id, pr.session, pr.semester, pr.level, pr.programme_code,
               coalesce(ap.amount, CASE WHEN sd.session IS NOT NULL THEN coalesce(sr.amount, 0) END) AS assessed,
               CASE WHEN ap.id IS NOT NULL THEN 'ASSESSMENT' WHEN sd.session IS NOT NULL THEN 'STRUCTURE' ELSE 'NONE' END AS source,
               CASE WHEN ap.id IS NOT NULL THEN ap.reference
                    WHEN sd.session IS NOT NULL THEN pr.session || ' fee structure' || CASE WHEN sr.lines IS NULL THEN ' (nothing due this semester)'
                                                                                          ELSE ' (' || sr.lines || CASE WHEN sr.lines = 1 THEN ' line)' ELSE ' lines)' END END END AS source_ref,
               ap.id AS assessment_id, sr.amount AS structure_amount, coalesce(sr.lines, 0) AS structure_lines,
               pn.id AS pending_id, pn.reference AS pending_ref, pn.amount AS pending_amount,
               coalesce(py.paid, 0) AS session_paid
          FROM per pr
          LEFT JOIN struct sr ON sr.student_id = pr.id AND sr.session = pr.session AND sr.semester = pr.semester
          LEFT JOIN stated sd ON sd.student_id = pr.id AND sd.session = pr.session
          LEFT JOIN apr ap ON ap.student_id = pr.id AND ap.session = pr.session AND ap.semester = pr.semester
          LEFT JOIN pend pn ON pn.student_id = pr.id AND pn.session = pr.session AND pn.semester = pr.semester
          LEFT JOIN pay py ON py.student_id = pr.id AND py.session = pr.session),
    alloc AS (
        -- the session's payments fill the assessed semesters in order; what is left goes to the first semester not yet assessed,
        -- else stands as a credit on the session's last semester
        SELECT b.*,
               coalesce(sum(b.assessed) OVER (PARTITION BY b.student_id, b.session ORDER BY b.semester ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS before_me,
               coalesce(sum(b.assessed) OVER (PARTITION BY b.student_id, b.session), 0) AS session_assessed,
               min(b.semester) FILTER (WHERE b.assessed IS NULL) OVER (PARTITION BY b.student_id, b.session) AS first_unassessed,
               max(b.semester) OVER (PARTITION BY b.student_id, b.session) AS last_semester
          FROM base b),
    fin AS (
        SELECT a.*,
               CASE WHEN a.assessed IS NOT NULL THEN least(greatest(a.session_paid - a.before_me, 0), a.assessed)
                    WHEN a.semester = a.first_unassessed THEN greatest(a.session_paid - a.session_assessed, 0)
                    ELSE 0 END AS paid_here,
               CASE WHEN a.first_unassessed IS NULL AND a.semester = a.last_semester THEN greatest(a.session_paid - a.session_assessed, 0) ELSE 0 END AS credit_here
          FROM alloc a)
    SELECT f.student_id, f.session, f.semester, f.level, f.programme_code, f.assessed, f.source, f.source_ref, f.assessment_id,
           f.structure_amount, f.structure_lines, f.pending_id, f.pending_ref, f.pending_amount,
           f.paid_here + f.credit_here AS paid,
           CASE WHEN f.assessed IS NULL THEN NULL ELSE finance.fee_owed(f.assessed, f.paid_here) END AS outstanding,
           f.credit_here AS credit,
           CASE WHEN f.assessed IS NULL THEN CASE WHEN f.pending_id IS NOT NULL THEN 'PENDING_APPROVAL' ELSE 'REQUIRES_REVIEW' END
                WHEN f.credit_here >= 1 THEN 'CREDIT'
                WHEN finance.fee_owed(f.assessed, f.paid_here) = 0 THEN 'CLEARED'
                WHEN f.paid_here > 0 THEN 'PARTIALLY_PAID'
                ELSE 'OUTSTANDING' END AS status
      FROM fin f
$$;

-- the one entry: PL/pgSQL on purpose, so a caller's query never folds the read into its own plan
CREATE OR REPLACE FUNCTION finance.historical_rows(p_students uuid[])
RETURNS TABLE(student_id uuid, session text, semester integer, level integer, programme_code text, assessed numeric, source text, source_ref text,
              assessment_id uuid, structure_amount numeric, structure_lines integer, pending_id uuid, pending_ref text, pending_amount numeric,
              paid numeric, outstanding numeric, credit numeric, status text)
LANGUAGE plpgsql
STABLE
ROWS 1000
AS $$
BEGIN
    RETURN QUERY SELECT * FROM finance.historical_rows_read(p_students) x ORDER BY x.student_id, x.session, x.semester;
END $$;
COMMENT ON FUNCTION finance.historical_rows(uuid[]) IS
  'V654: the historical account of the students given — each session and semester from the start (finance.historical_start, or admission) to the graduation session (the session before the current one for a student still studying), a deferred period left out: the level of the period, the amount assessed (an approved assessment, else the session''s fee lines matched to the student as they were then, else nothing: REQUIRES_REVIEW or PENDING_APPROVAL), the confirmed school-fee payments of the session allocated first semester first, the outstanding and any credit.';

CREATE OR REPLACE FUNCTION finance.historical_account(p_student uuid)
RETURNS TABLE(session text, semester integer, level integer, programme_code text, assessed numeric, source text, source_ref text, assessment_id uuid,
              structure_amount numeric, structure_lines integer, pending_id uuid, pending_ref text, pending_amount numeric,
              paid numeric, outstanding numeric, credit numeric, status text)
LANGUAGE sql
STABLE
AS $$
    SELECT x.session, x.semester, x.level, x.programme_code, x.assessed, x.source, x.source_ref, x.assessment_id, x.structure_amount, x.structure_lines,
           x.pending_id, x.pending_ref, x.pending_amount, x.paid, x.outstanding, x.credit, x.status
      FROM finance.historical_rows(ARRAY[p_student]) x
$$;

-- ── 6 · the summary: worked out for the students given, or every graduate and graduand ──
CREATE OR REPLACE FUNCTION finance.historical_refresh(p_students uuid[] DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE v_ids uuid[]; n int;
BEGIN
    v_ids := coalesce(p_students, (SELECT array_agg(s.id) FROM people.student s
                                    WHERE s.status = 'GRADUATED'
                                       OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED')));
    IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
        IF p_students IS NULL THEN UPDATE finance.historical_setting SET refreshed_at = now() WHERE id = 1; END IF;
        RETURN 0;
    END IF;
    WITH hr AS (SELECT * FROM finance.historical_rows(v_ids)),
    agg AS (
        SELECT r.student_id, min(r.session) AS first_session, max(r.session) AS last_session, count(*)::int AS periods,
               coalesce(sum(r.assessed), 0) AS assessed, coalesce(sum(r.paid), 0) AS paid, coalesce(sum(r.outstanding), 0) AS outstanding,
               coalesce(sum(r.credit), 0) AS credit,
               count(*) FILTER (WHERE r.outstanding > 0)::int AS owing_periods,
               count(*) FILTER (WHERE r.status = 'REQUIRES_REVIEW')::int AS review_periods,
               count(*) FILTER (WHERE r.status = 'PENDING_APPROVAL')::int AS pending_periods,
               count(*) FILTER (WHERE r.status = 'PARTIALLY_PAID')::int AS partial_periods,
               string_agg(r.session || ' S' || r.semester, ', ' ORDER BY r.session, r.semester) FILTER (WHERE r.outstanding > 0) AS owing
          FROM hr r GROUP BY r.student_id),
    ids AS (SELECT DISTINCT unnest(v_ids) AS student_id),
    up AS (
        INSERT INTO finance.historical_summary AS h (student_id, first_session, last_session, periods, assessed, paid, outstanding, credit, owing_periods,
                                                     review_periods, pending_periods, partial_periods, owing, financial_status, last_payment_at, refreshed_at)
        SELECT i.student_id, a.first_session, a.last_session, coalesce(a.periods, 0), coalesce(a.assessed, 0), coalesce(a.paid, 0), coalesce(a.outstanding, 0),
               coalesce(a.credit, 0), coalesce(a.owing_periods, 0), coalesce(a.review_periods, 0), coalesce(a.pending_periods, 0), coalesce(a.partial_periods, 0), a.owing,
               CASE WHEN coalesce(a.periods, 0) = 0 THEN 'NO_HISTORICAL_PERIOD'
                    WHEN a.review_periods > 0 THEN 'HISTORICAL_FEE_REVIEW_REQUIRED'
                    WHEN a.pending_periods > 0 THEN 'FINANCIAL_CLEARANCE_PENDING'
                    WHEN a.outstanding > 0 THEN 'FINANCIAL_OBLIGATION'
                    ELSE 'FINANCIALLY_CLEARED' END,
               (SELECT max(r.confirmed_at) FROM finance.payment_reference r WHERE r.student_id = i.student_id AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'),
               now()
          FROM ids i LEFT JOIN agg a ON a.student_id = i.student_id
        ON CONFLICT (student_id) DO UPDATE SET first_session = EXCLUDED.first_session, last_session = EXCLUDED.last_session, periods = EXCLUDED.periods,
            assessed = EXCLUDED.assessed, paid = EXCLUDED.paid, outstanding = EXCLUDED.outstanding, credit = EXCLUDED.credit,
            owing_periods = EXCLUDED.owing_periods, review_periods = EXCLUDED.review_periods, pending_periods = EXCLUDED.pending_periods,
            partial_periods = EXCLUDED.partial_periods, owing = EXCLUDED.owing, financial_status = EXCLUDED.financial_status,
            last_payment_at = EXCLUDED.last_payment_at, refreshed_at = EXCLUDED.refreshed_at
        RETURNING 1)
    SELECT count(*) INTO n FROM up;
    DELETE FROM finance.historical_stale x WHERE x.student_id = ANY (v_ids);
    IF p_students IS NULL THEN UPDATE finance.historical_setting SET refreshed_at = now() WHERE id = 1; END IF;
    RETURN n;
END $$;
COMMENT ON FUNCTION finance.historical_refresh(uuid[]) IS
  'V654: works out the historical summary of the students given (NULL: every graduate and graduand) from finance.historical_rows, and takes them off the stale list.';

-- the students marked stale worked out again, then the graduates and approved graduands never worked out (graduated since the last
-- full working-out), a few hundred at a time (the lists and the figures call it before they read)
CREATE OR REPLACE FUNCTION finance.historical_refresh_stale(p_limit integer DEFAULT 500)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE v_ids uuid[]; v_new uuid[]; v_lim int := greatest(p_limit, 1);
BEGIN
    SELECT array_agg(x.student_id) INTO v_ids
      FROM (SELECT h.student_id FROM finance.historical_stale h ORDER BY h.marked_at LIMIT v_lim FOR UPDATE SKIP LOCKED) x;
    IF coalesce(cardinality(v_ids), 0) < v_lim THEN
        SELECT array_agg(n.id) INTO v_new
          FROM (SELECT s.id FROM people.student s
                 WHERE (s.status = 'GRADUATED' OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED'))
                   AND NOT EXISTS (SELECT 1 FROM finance.historical_summary h WHERE h.student_id = s.id)
                   AND s.id <> ALL (coalesce(v_ids, '{}'::uuid[]))
                 LIMIT v_lim - coalesce(cardinality(v_ids), 0)) n;
        v_ids := coalesce(v_ids, '{}'::uuid[]) || coalesce(v_new, '{}'::uuid[]);
    END IF;
    IF cardinality(v_ids) = 0 THEN RETURN 0; END IF;
    RETURN finance.historical_refresh(v_ids);
END $$;
COMMENT ON FUNCTION finance.historical_refresh_stale(integer) IS
  'V654: works out again up to p_limit students — first those a payment marked stale, then graduates and approved graduands with no summary yet.';

-- a school-fee payment confirmed (or a confirmed one changed) marks a graduate's or graduand's summary stale
CREATE OR REPLACE FUNCTION finance.trg_historical_stale_payment()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.student_id IS NOT NULL AND NEW.purpose LIKE 'School fees%'
       AND EXISTS (SELECT 1 FROM finance.historical_summary h WHERE h.student_id = NEW.student_id) THEN
        INSERT INTO finance.historical_stale (student_id) VALUES (NEW.student_id) ON CONFLICT (student_id) DO NOTHING;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_historical_stale_payment_ins AFTER INSERT ON finance.payment_reference
    FOR EACH ROW WHEN (NEW.confirmed_at IS NOT NULL) EXECUTE FUNCTION finance.trg_historical_stale_payment();
CREATE TRIGGER trg_historical_stale_payment_upd AFTER UPDATE OF confirmed_at, amount, purpose, session, student_id ON finance.payment_reference
    FOR EACH ROW WHEN (NEW.confirmed_at IS DISTINCT FROM OLD.confirmed_at OR NEW.amount IS DISTINCT FROM OLD.amount OR NEW.purpose IS DISTINCT FROM OLD.purpose
                       OR NEW.session IS DISTINCT FROM OLD.session OR NEW.student_id IS DISTINCT FROM OLD.student_id)
    EXECUTE FUNCTION finance.trg_historical_stale_payment();

CREATE OR REPLACE FUNCTION finance.semester_words(p_semester integer)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE p_semester WHEN 1 THEN 'First semester' WHEN 2 THEN 'Second semester' WHEN 3 THEN 'Third semester' ELSE 'Semester ' || p_semester END
$$;

-- ── 7 · an assessment made, submitted, decided, cancelled ──
CREATE OR REPLACE FUNCTION finance.historical_event(p_assessment uuid, p_action text, p_note text, p_amount numeric)
RETURNS void
LANGUAGE sql
AS $$
    INSERT INTO finance.historical_assessment_event (assessment_id, action, actor, office, note, amount)
    VALUES (p_assessment, p_action, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''),
            p_note, p_amount)
$$;

CREATE OR REPLACE FUNCTION finance.historical_assessment_save(p_id uuid, p_student uuid, p_session text, p_semester integer, p_amount numeric, p_components jsonb,
                                                              p_source text, p_source_reference text, p_reason text, p_remarks text, p_corrects uuid,
                                                              p_submit boolean DEFAULT false)
RETURNS TABLE(id uuid, reference text, state text)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
        a finance.historical_assessment; c finance.historical_assessment; per record; v_sum numeric; v_bad int; v_id uuid; v_ref text; v_state text;
        v_year text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY'); v_prog record;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'HFA_PERSON: an assessment is made by a person' USING ERRCODE = '23514'; END IF;
    IF p_id IS NULL THEN
        PERFORM finance.historical_require('CREATE_HISTORICAL_FEE_ASSESSMENT');
        IF p_corrects IS NOT NULL THEN PERFORM finance.historical_require('CORRECT_HISTORICAL_ASSESSMENT'); END IF;
    ELSE
        PERFORM finance.historical_require('EDIT_HISTORICAL_FEE_ASSESSMENT');
        SELECT * INTO a FROM finance.historical_assessment x WHERE x.id = p_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'HFA_NOT_FOUND: no such assessment' USING ERRCODE = 'P0002'; END IF;
        IF a.state NOT IN ('DRAFT', 'RETURNED_FOR_CORRECTION') THEN
            RAISE EXCEPTION 'HFA_NOT_EDITABLE: % is % — only a draft or one returned for correction is changed', a.reference, lower(replace(a.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        p_student := a.student_id; p_session := a.session; p_semester := a.semester; p_corrects := a.corrects;
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'HFA_AMOUNT: an assessment is for an amount above nothing' USING ERRCODE = '23514';
    END IF;
    p_components := coalesce(p_components, '[]'::jsonb);
    IF jsonb_typeof(p_components) <> 'array' THEN RAISE EXCEPTION 'HFA_COMPONENTS: the components are a list of items and amounts' USING ERRCODE = '23514'; END IF;
    IF jsonb_array_length(p_components) > 0 THEN
        SELECT coalesce(sum((x->>'amount')::numeric), 0), count(*) FILTER (WHERE btrim(coalesce(x->>'item', '')) = '' OR coalesce((x->>'amount')::numeric, 0) <= 0)
          INTO v_sum, v_bad FROM jsonb_array_elements(p_components) x;
        IF v_bad > 0 THEN RAISE EXCEPTION 'HFA_COMPONENTS: each component names its item and an amount above nothing' USING ERRCODE = '23514'; END IF;
        IF v_sum <> p_amount THEN
            RAISE EXCEPTION 'HFA_COMPONENTS: the components add up to %, not the amount %', v_sum, p_amount USING ERRCODE = '23514';
        END IF;
    END IF;
    IF p_source IS NULL OR p_source NOT IN ('HISTORICAL_FEE_STRUCTURE', 'HISTORICAL_FEE_VERSION', 'COHORT_FEE_RECORD', 'STUDENT_SPECIFIC_APPROVED_FEE',
                                            'OFFICIAL_FEE_DOCUMENT', 'MANUAL_HISTORICAL_ASSESSMENT', 'LEGACY_MIGRATION', 'OTHER_APPROVED_SOURCE') THEN
        RAISE EXCEPTION 'HFA_SOURCE: name where the amount comes from — a historical fee structure or version, a cohort record, a student''s approved fee, an official fee document, a manual assessment, the old portal, or another approved source'
            USING ERRCODE = '23514';
    END IF;
    IF p_source IN ('STUDENT_SPECIFIC_APPROVED_FEE', 'OFFICIAL_FEE_DOCUMENT', 'OTHER_APPROVED_SOURCE', 'COHORT_FEE_RECORD')
       AND length(btrim(coalesce(p_source_reference, ''))) < 4 THEN
        RAISE EXCEPTION 'HFA_SOURCE_REFERENCE: name the document, approval or record the amount comes from' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 20 THEN
        RAISE EXCEPTION 'HFA_REASON: say why the amount is assessed, in twenty characters at least' USING ERRCODE = '23514';
    END IF;
    -- a period of the student's historical record: on the calendar, from the start to the graduation session, not deferred
    SELECT x.* INTO per FROM finance.historical_account(p_student) x WHERE x.session = p_session AND x.semester = p_semester;
    IF per.session IS NULL THEN
        RAISE EXCEPTION 'HFA_PERIOD: % % is not a period of the student''s historical record (before the assessment start, after the graduation session, deferred, or not on the calendar)',
            p_session, lower(finance.semester_words(p_semester)) USING ERRCODE = '23514';
    END IF;
    IF p_id IS NULL THEN
        IF EXISTS (SELECT 1 FROM finance.historical_assessment x WHERE x.student_id = p_student AND x.session = p_session AND x.semester = p_semester
                      AND x.state IN ('DRAFT', 'PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION')) THEN
            RAISE EXCEPTION 'HFA_OPEN_EXISTS: % already has an assessment being made for % %: %', p_student, p_session, lower(finance.semester_words(p_semester)),
                (SELECT x.reference FROM finance.historical_assessment x WHERE x.student_id = p_student AND x.session = p_session AND x.semester = p_semester
                    AND x.state IN ('DRAFT', 'PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION')) USING ERRCODE = '23514';
        END IF;
        IF p_corrects IS NULL AND per.assessment_id IS NOT NULL THEN
            RAISE EXCEPTION 'HFA_ALREADY_ASSESSED: % % is assessed by %, approved — correct it instead', p_session, lower(finance.semester_words(p_semester)), per.source_ref
                USING ERRCODE = '23514';
        END IF;
        IF p_corrects IS NOT NULL THEN
            SELECT * INTO c FROM finance.historical_assessment x WHERE x.id = p_corrects;
            IF c.id IS NULL OR c.state <> 'APPROVED' OR c.student_id <> p_student OR c.session <> p_session OR c.semester <> p_semester THEN
                RAISE EXCEPTION 'HFA_CORRECTS: a correction replaces the approved assessment of the same student, session and semester' USING ERRCODE = '23514';
            END IF;
        END IF;
        SELECT p.code, p.faculty_code, p.dept_code INTO v_prog FROM people.student s JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = p_student;
        v_ref := 'HFA/' || v_year || '/' || lpad(platform.next_number('HISTORICAL_FEE_ASSESSMENT', 'finance', v_year)::text, 6, '0');
        INSERT INTO finance.historical_assessment (reference, student_id, session, semester, level, programme_code, faculty_code, dept_code, amount, components,
                                                   source, source_reference, reason, remarks, corrects, created_by, created_office)
        VALUES (v_ref, p_student, p_session, p_semester, per.level, v_prog.code, v_prog.faculty_code, v_prog.dept_code, p_amount, p_components,
                p_source, nullif(btrim(p_source_reference), ''), btrim(p_reason), nullif(btrim(p_remarks), ''), p_corrects, v_actor, v_office)
        RETURNING finance.historical_assessment.id INTO v_id;
        PERFORM finance.historical_event(v_id, 'CREATED', CASE WHEN p_corrects IS NOT NULL THEN 'Correction of ' || c.reference END, p_amount);
    ELSE
        UPDATE finance.historical_assessment x SET amount = p_amount, components = p_components, source = p_source, source_reference = nullif(btrim(p_source_reference), ''),
               reason = btrim(p_reason), remarks = nullif(btrim(p_remarks), ''), updated_at = now()
         WHERE x.id = p_id;
        v_id := p_id; v_ref := a.reference;
        PERFORM finance.historical_event(v_id, 'EDITED', NULL, p_amount);
    END IF;
    v_state := (SELECT x.state FROM finance.historical_assessment x WHERE x.id = v_id);
    IF coalesce(p_submit, false) THEN
        PERFORM finance.historical_require('SUBMIT_HISTORICAL_FEE_ASSESSMENT');
        UPDATE finance.historical_assessment x SET state = 'PENDING_BURSAR_APPROVAL', submitted_by = v_actor, submitted_at = now(), updated_at = now() WHERE x.id = v_id;
        PERFORM finance.historical_event(v_id, 'SUBMITTED', NULL, p_amount);
        v_state := 'PENDING_BURSAR_APPROVAL';
    END IF;
    PERFORM finance.historical_refresh(ARRAY[p_student]);
    RETURN QUERY SELECT v_id, v_ref, v_state;
END $$;
COMMENT ON FUNCTION finance.historical_assessment_save(uuid, uuid, text, integer, numeric, jsonb, text, text, text, text, uuid, boolean) IS
  'V654: a historical assessment made (or a draft or returned one changed) for a period of the student''s historical record — an amount above nothing, components adding up to it, a source from the list (a document named where the source is a document or approval), a reason of twenty characters; one being made at a time, one in force; a correction names the approved assessment it replaces; submitted for the Bursar''s approval at once when asked.';

CREATE OR REPLACE FUNCTION finance.historical_assessment_submit(p_id uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE a finance.historical_assessment; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    PERFORM finance.historical_require('SUBMIT_HISTORICAL_FEE_ASSESSMENT');
    SELECT * INTO a FROM finance.historical_assessment x WHERE x.id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'HFA_NOT_FOUND: no such assessment' USING ERRCODE = 'P0002'; END IF;
    IF a.state NOT IN ('DRAFT', 'RETURNED_FOR_CORRECTION') THEN
        RAISE EXCEPTION 'HFA_NOT_EDITABLE: % is % — only a draft or one returned for correction is submitted', a.reference, lower(replace(a.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    UPDATE finance.historical_assessment x SET state = 'PENDING_BURSAR_APPROVAL', submitted_by = v_actor, submitted_at = now(), updated_at = now() WHERE x.id = p_id;
    PERFORM finance.historical_event(p_id, 'SUBMITTED', NULL, a.amount);
    PERFORM finance.historical_refresh(ARRAY[a.student_id]);
    RETURN 'PENDING_BURSAR_APPROVAL';
END $$;

CREATE OR REPLACE FUNCTION finance.historical_assessment_decide(p_id uuid, p_decision text, p_note text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE a finance.historical_assessment; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_dec text := upper(btrim(coalesce(p_decision, ''))); v_owed numeric;
BEGIN
    IF v_dec NOT IN ('APPROVE', 'RETURN', 'REJECT') THEN
        RAISE EXCEPTION 'HFA_DECISION: an assessment is approved, returned for correction or rejected' USING ERRCODE = '23514';
    END IF;
    PERFORM finance.historical_require(CASE v_dec WHEN 'APPROVE' THEN 'APPROVE_HISTORICAL_FEE_ASSESSMENT' WHEN 'RETURN' THEN 'RETURN_HISTORICAL_FEE_ASSESSMENT'
                                                  ELSE 'REJECT_HISTORICAL_FEE_ASSESSMENT' END);
    SELECT * INTO a FROM finance.historical_assessment x WHERE x.id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'HFA_NOT_FOUND: no such assessment' USING ERRCODE = 'P0002'; END IF;
    IF a.state <> 'PENDING_BURSAR_APPROVAL' THEN
        RAISE EXCEPTION 'HFA_NOT_PENDING: % is % — only an assessment awaiting the Bursar is decided', a.reference, lower(replace(a.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF v_actor IS NULL OR v_actor = a.created_by OR v_actor = a.submitted_by THEN
        RAISE EXCEPTION 'HFA_SAME_OFFICER: an assessment is decided by an officer other than the one who made or submitted it' USING ERRCODE = '23514';
    END IF;
    IF v_dec IN ('RETURN', 'REJECT') AND length(btrim(coalesce(p_note, ''))) < 10 THEN
        RAISE EXCEPTION 'HFA_NOTE: say why, in ten characters at least' USING ERRCODE = '23514';
    END IF;
    IF v_dec = 'APPROVE' THEN
        IF a.corrects IS NOT NULL THEN
            UPDATE finance.historical_assessment x SET state = 'SUPERSEDED', superseded_by = a.id, updated_at = now() WHERE x.id = a.corrects AND x.state = 'APPROVED';
            IF NOT FOUND THEN RAISE EXCEPTION 'HFA_CORRECTS: the assessment it corrects is no longer in force' USING ERRCODE = '23514'; END IF;
            PERFORM finance.historical_event(a.corrects, 'SUPERSEDED', 'Corrected by ' || a.reference, NULL);
        ELSIF EXISTS (SELECT 1 FROM finance.historical_assessment x WHERE x.student_id = a.student_id AND x.session = a.session AND x.semester = a.semester
                         AND x.state = 'APPROVED') THEN
            RAISE EXCEPTION 'HFA_ALREADY_ASSESSED: the period already has an approved assessment — a correction replaces it' USING ERRCODE = '23514';
        END IF;
        UPDATE finance.historical_assessment x SET state = 'APPROVED', decided_by = v_actor, decided_office = v_office, decided_at = now(),
               decision_note = nullif(btrim(p_note), ''), updated_at = now()
         WHERE x.id = p_id;
        PERFORM finance.historical_event(p_id, 'APPROVED', nullif(btrim(p_note), ''), a.amount);
    ELSE
        UPDATE finance.historical_assessment x SET state = CASE v_dec WHEN 'RETURN' THEN 'RETURNED_FOR_CORRECTION' ELSE 'REJECTED' END,
               decided_by = v_actor, decided_office = v_office, decided_at = now(), decision_note = btrim(p_note), updated_at = now()
         WHERE x.id = p_id;
        PERFORM finance.historical_event(p_id, CASE v_dec WHEN 'RETURN' THEN 'RETURNED' ELSE 'REJECTED' END, btrim(p_note), a.amount);
    END IF;
    PERFORM finance.historical_refresh(ARRAY[a.student_id]);
    IF v_dec = 'APPROVE' THEN
        -- the student is told once the amount is official: what the period now shows as owed
        SELECT x.outstanding INTO v_owed FROM finance.historical_account(a.student_id) x WHERE x.session = a.session AND x.semester = a.semester;
        PERFORM platform.tell_student(a.student_id, 'HISTORICAL_FEES_ASSESSED', NULL,
            jsonb_build_object('SESSION', a.session, 'SEMESTER', finance.semester_words(a.semester), 'AMOUNT', 'NGN ' || to_char(a.amount, 'FM999,999,999,990.00'),
                               'REFERENCE', a.reference,
                               'OUTSTANDING', CASE WHEN coalesce(v_owed, 0) > 0 THEN 'NGN ' || to_char(v_owed, 'FM999,999,999,990.00') || ' outstanding' ELSE 'nothing outstanding' END),
            'HISTORICAL_FEES_ASSESSED:' || a.id);
    END IF;
    RETURN CASE v_dec WHEN 'APPROVE' THEN 'APPROVED' WHEN 'RETURN' THEN 'RETURNED_FOR_CORRECTION' ELSE 'REJECTED' END;
END $$;
COMMENT ON FUNCTION finance.historical_assessment_decide(uuid, text, text) IS
  'V654: an assessment awaiting the Bursar approved (in force; a correction supersedes the one it replaces; the student told), returned for correction or rejected with a reason — never by the officer who made or submitted it.';

CREATE OR REPLACE FUNCTION finance.historical_assessment_cancel(p_id uuid, p_note text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE a finance.historical_assessment; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO a FROM finance.historical_assessment x WHERE x.id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'HFA_NOT_FOUND: no such assessment' USING ERRCODE = 'P0002'; END IF;
    IF NOT (a.created_by = v_actor OR finance.historical_may(nullif(current_setting('moaum.actor_office', true), ''), 'APPROVE_HISTORICAL_FEE_ASSESSMENT')) THEN
        RAISE EXCEPTION 'HFA_NOT_PERMITTED: an assessment is withdrawn by the officer who made it or the Bursar' USING ERRCODE = '42501';
    END IF;
    IF a.state NOT IN ('DRAFT', 'PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION') THEN
        RAISE EXCEPTION 'HFA_NOT_EDITABLE: % is % and is kept', a.reference, lower(replace(a.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    UPDATE finance.historical_assessment x SET state = 'CANCELLED', decision_note = nullif(btrim(p_note), ''), updated_at = now() WHERE x.id = p_id;
    PERFORM finance.historical_event(p_id, 'CANCELLED', nullif(btrim(p_note), ''), a.amount);
    PERFORM finance.historical_refresh(ARRAY[a.student_id]);
    RETURN 'CANCELLED';
END $$;

-- ── 8 · a cohort: previewed, then assessed in one batch the Bursar decides together ──
CREATE OR REPLACE FUNCTION finance.historical_bulk_preview(p_session text, p_semester integer, p_faculty text DEFAULT NULL, p_dept text DEFAULT NULL,
                                                           p_programme text DEFAULT NULL, p_level integer DEFAULT NULL, p_graduated_only boolean DEFAULT true,
                                                           p_limit integer DEFAULT 3000)
RETURNS TABLE(student_id uuid, verdict text, level integer, structure_amount numeric, assessed numeric, paid numeric, outstanding numeric, reference text)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE v_ids uuid[];
BEGIN
    PERFORM finance.historical_require('VIEW_HISTORICAL_FEE_ASSESSMENT');
    SELECT array_agg(s.id) INTO v_ids
      FROM (SELECT s.id FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
             WHERE (p_faculty IS NULL OR p.faculty_code = p_faculty) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_programme IS NULL OR p.code = p_programme)
               AND s.entry_session <= p_session
               AND (NOT coalesce(p_graduated_only, true) OR s.status = 'GRADUATED'
                    OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED'))
             ORDER BY s.id LIMIT greatest(p_limit, 1)) s;
    IF v_ids IS NULL THEN RETURN; END IF;
    RETURN QUERY
    SELECT x.student_id,
           CASE WHEN x.source = 'ASSESSMENT' THEN 'ALREADY_ASSESSED' WHEN x.pending_id IS NOT NULL THEN 'PENDING'
                WHEN x.source = 'STRUCTURE' THEN 'STRUCTURE_FOUND' ELSE 'REQUIRES_ASSESSMENT' END,
           x.level, x.structure_amount, x.assessed, x.paid, x.outstanding, coalesce(x.pending_ref, CASE WHEN x.source = 'ASSESSMENT' THEN x.source_ref END)
      FROM finance.historical_rows(v_ids) x
     WHERE x.session = p_session AND x.semester = p_semester AND (p_level IS NULL OR x.level = p_level);
END $$;
COMMENT ON FUNCTION finance.historical_bulk_preview(text, integer, text, text, text, integer, boolean, integer) IS
  'V654: the students of a scope (faculty, department, programme, the level of the session) for a session and semester, each with what the historical account reads: STRUCTURE_FOUND (assessed from the fee lines, nothing to make), ALREADY_ASSESSED, PENDING, REQUIRES_ASSESSMENT. Nothing is made.';

CREATE OR REPLACE FUNCTION finance.historical_bulk_create(p_students uuid[], p_session text, p_semester integer, p_amount numeric, p_components jsonb,
                                                          p_source text, p_source_reference text, p_reason text, p_scope jsonb DEFAULT '{}'::jsonb)
RETURNS TABLE(batch_id uuid, reference text, created integer, skipped integer)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_year text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY'); v_batch uuid; v_ref text; r record; n int := 0; k int := 0; v_saved record;
BEGIN
    PERFORM finance.historical_require('CREATE_HISTORICAL_FEE_ASSESSMENT');
    PERFORM finance.historical_require('SUBMIT_HISTORICAL_FEE_ASSESSMENT');
    IF p_students IS NULL OR cardinality(p_students) = 0 THEN
        RAISE EXCEPTION 'HFA_BATCH_EMPTY: choose the students to assess' USING ERRCODE = '23514';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'HFA_AMOUNT: an assessment is for an amount above nothing' USING ERRCODE = '23514'; END IF;
    v_ref := 'HFA-B/' || v_year || '/' || lpad(platform.next_number('HISTORICAL_FEE_BATCH', 'finance', v_year)::text, 6, '0');
    INSERT INTO finance.historical_batch (reference, session, semester, scope, amount, components, source, source_reference, reason, created_by, created_office)
    VALUES (v_ref, p_session, p_semester, coalesce(p_scope, '{}'::jsonb), p_amount, coalesce(p_components, '[]'::jsonb), p_source, nullif(btrim(p_source_reference), ''),
            btrim(coalesce(p_reason, '')), v_actor, v_office)
    RETURNING id INTO v_batch;
    -- only the students the account reads as still needing an amount for the period; every other is left as it is
    FOR r IN SELECT x.student_id FROM finance.historical_rows(p_students) x
              WHERE x.session = p_session AND x.semester = p_semester AND x.source = 'NONE' AND x.pending_id IS NULL LOOP
        SELECT * INTO v_saved FROM finance.historical_assessment_save(NULL, r.student_id, p_session, p_semester, p_amount, p_components, p_source,
                                                                      p_source_reference, p_reason, NULL, NULL, true);
        UPDATE finance.historical_assessment x SET batch_id = v_batch WHERE x.id = v_saved.id;
        n := n + 1;
    END LOOP;
    k := cardinality(p_students) - n;
    IF n = 0 THEN
        RAISE EXCEPTION 'HFA_BATCH_EMPTY: none of the students chosen needs an amount for % % — each is assessed, pending, or reads the fee structure',
            p_session, lower(finance.semester_words(p_semester)) USING ERRCODE = '23514';
    END IF;
    UPDATE finance.historical_batch x SET students = n WHERE x.id = v_batch;
    RETURN QUERY SELECT v_batch, v_ref, n, k;
END $$;
COMMENT ON FUNCTION finance.historical_bulk_create(uuid[], text, integer, numeric, jsonb, text, text, text, jsonb) IS
  'V654: one amount assessed for a cohort''s period: an assessment for each student chosen that the account still reads with no amount (none pending), each submitted for the Bursar''s approval under one batch HFA-B/YYYY/NNNNNN; every other student skipped.';

CREATE OR REPLACE FUNCTION finance.historical_batch_decide(p_batch uuid, p_decision text, p_note text)
RETURNS TABLE(decided integer, state text)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE b finance.historical_batch; r record; n int := 0; v_state text; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO b FROM finance.historical_batch x WHERE x.id = p_batch FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'HFA_NOT_FOUND: no such batch' USING ERRCODE = 'P0002'; END IF;
    IF b.state <> 'PENDING_BURSAR_APPROVAL' THEN
        RAISE EXCEPTION 'HFA_NOT_PENDING: % is %', b.reference, lower(replace(b.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF v_actor IS NULL OR v_actor = b.created_by THEN
        RAISE EXCEPTION 'HFA_SAME_OFFICER: a batch is decided by an officer other than the one who made it' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT x.id FROM finance.historical_assessment x WHERE x.batch_id = p_batch AND x.state = 'PENDING_BURSAR_APPROVAL' LOOP
        PERFORM finance.historical_assessment_decide(r.id, p_decision, p_note);
        n := n + 1;
    END LOOP;
    v_state := CASE upper(btrim(p_decision)) WHEN 'APPROVE' THEN 'APPROVED' WHEN 'RETURN' THEN 'RETURNED_FOR_CORRECTION' ELSE 'REJECTED' END;
    UPDATE finance.historical_batch x SET state = v_state, decided_by = v_actor, decided_office = nullif(current_setting('moaum.actor_office', true), ''),
           decided_at = now(), decision_note = nullif(btrim(p_note), '')
     WHERE x.id = p_batch;
    RETURN QUERY SELECT n, v_state;
END $$;

-- ── 9 · a graduate pays an approved historical balance online ──
CREATE OR REPLACE FUNCTION finance.historical_reference(p_student uuid, p_session text, p_amount numeric)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE v_owed numeric; v_ref text; v_matric text; v_status text;
BEGIN
    IF NOT coalesce((SELECT s.online_payment FROM finance.historical_setting s WHERE s.id = 1), false) THEN
        RAISE EXCEPTION 'HFA_ONLINE_OFF: historical school fees are settled with the Bursary' USING ERRCODE = '23514';
    END IF;
    SELECT s.status, coalesce(s.matric_no, s.admission_no, 'X') INTO v_status, v_matric FROM people.student s WHERE s.id = p_student;
    IF v_status IS DISTINCT FROM 'GRADUATED'
       AND NOT EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = p_student AND g.senate_state = 'APPROVED') THEN
        RAISE EXCEPTION 'HFA_PAY_GRADUATES: a historical balance is paid here by a graduate; a student still studying pays from the fees page' USING ERRCODE = '23514';
    END IF;
    SELECT sum(x.outstanding) INTO v_owed FROM finance.historical_account(p_student) x WHERE x.session = p_session AND x.outstanding > 0;
    IF coalesce(v_owed, 0) <= 0 THEN
        RAISE EXCEPTION 'HFA_NOTHING_OWED: nothing is owed for % on the approved historical account', p_session USING ERRCODE = '23514';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount > v_owed THEN
        RAISE EXCEPTION 'HFA_PAY_AMOUNT: pay up to % for %, the balance owed', to_char(v_owed, 'FM999,999,999,990.00'), p_session USING ERRCODE = '23514';
    END IF;
    FOR v_try IN 1..50 LOOP
        v_ref := 'MOAUM-FEE-' || regexp_replace(right(v_matric, 7), '[^0-9A-Z]', '', 'g') || '-' || lpad((floor(random() * 10000))::int::text, 4, '0');
        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at)
        VALUES (p_student, p_session, v_ref, 'School fees ' || p_session || ' (historical)', p_amount, now() + interval '24 hours')
        ON CONFLICT (reference) DO NOTHING;
        IF FOUND THEN RETURN v_ref; END IF;
    END LOOP;
    RAISE EXCEPTION 'FEE_REFERENCE_EXHAUSTED: no free payment reference was found for % in fifty draws', v_matric USING ERRCODE = '23514';
END $$;
COMMENT ON FUNCTION finance.historical_reference(uuid, text, numeric) IS
  'V654: a payment reference for a graduate''s approved historical balance of a session — outside the session''s payment window, never more than is owed; its purpose is the session''s school fees ("School fees 2021/2022 (historical)"), so the account, the fee position and the receipt read it as that session''s.';

-- ── 11 · the start, the data quality, the figures ──
CREATE OR REPLACE FUNCTION finance.historical_set_start(p_session text, p_reason text)
RETURNS integer
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM finance.historical_require('SET_HISTORICAL_FEE_START');
    IF p_session IS NOT NULL AND NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_session AND a.state NOT IN ('CANCELLED', 'DRAFT')) THEN
        RAISE EXCEPTION 'HFA_START: % is not a session on the calendar', p_session USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN RAISE EXCEPTION 'HFA_REASON: say why, in ten characters at least' USING ERRCODE = '23514'; END IF;
    PERFORM set_config('moaum.reason', btrim(p_reason), true);
    UPDATE finance.historical_setting SET assess_from = p_session, set_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
           set_office = nullif(current_setting('moaum.actor_office', true), ''), set_at = now(), reason = btrim(p_reason)
     WHERE id = 1;
    RETURN finance.historical_refresh(NULL);
END $$;

CREATE OR REPLACE FUNCTION finance.historical_quality(p_limit integer DEFAULT 2000)
RETURNS TABLE(issue text, student_id uuid, detail text)
LANGUAGE sql
STABLE
AS $$
    WITH grads AS (
        SELECT s.id, s.entry_session, s.programme_code, records.graduation_session(s.id) AS grad
          FROM people.student s
         WHERE s.status = 'GRADUATED' OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED'))
    SELECT * FROM (
        SELECT 'NO_ENTRY_SESSION'::text, g.id, 'No admission session on the record: the historical periods cannot be read' FROM grads g WHERE g.entry_session IS NULL
        UNION ALL
        SELECT 'NO_GRADUATION_SESSION', g.id, 'No graduation session (graduand list, reconciliation, enrolment or registration)' FROM grads g WHERE g.grad IS NULL
        UNION ALL
        SELECT 'MISSING_FEE_STRUCTURE', h.student_id, h.review_periods || ' period(s) with no fee structure or approved assessment'
          FROM finance.historical_summary h JOIN grads g ON g.id = h.student_id WHERE h.review_periods > 0
        UNION ALL
        SELECT 'PENDING_APPROVAL', h.student_id, h.pending_periods || ' period(s) awaiting the Bursar''s approval'
          FROM finance.historical_summary h JOIN grads g ON g.id = h.student_id WHERE h.pending_periods > 0
        UNION ALL
        SELECT 'OVERPAYMENT', h.student_id, 'Paid NGN ' || to_char(h.credit, 'FM999,999,999,990.00') || ' beyond what is assessed: for Refunds & Credits'
          FROM finance.historical_summary h JOIN grads g ON g.id = h.student_id WHERE h.credit >= 1
        UNION ALL
        SELECT DISTINCT 'PROGRAMME_CHANGED', m.student_id, 'Moved from ' || m.from_programme || ' to ' || m.to_programme || ': earlier sessions are read on the programme now held'
          FROM people.record_move m JOIN grads g ON g.id = m.student_id WHERE m.from_programme IS DISTINCT FROM m.to_programme) x(issue, student_id, detail)
     LIMIT greatest(p_limit, 1)
$$;
COMMENT ON FUNCTION finance.historical_quality(integer) IS
  'V654: the graduates and graduands whose historical account cannot be read as it stands — no admission or graduation session, periods with no fee structure or assessment, assessments awaiting approval, an overpayment, a programme changed (the earlier sessions read on the programme held now).';

-- ── 12 · the notice ──
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('HISTORICAL_FEES_ASSESSED', 'Historical school fees assessed',
 'To a student (usually a graduate) once the Bursar approves an assessment of a past session''s school fees',
 'Your school fees for [SESSION] [SEMESTER]',
 E'Dear [FIRST_NAME],\n\nThe Bursary has assessed your school fees for [SESSION], [SEMESTER]: [AMOUNT] (assessment [REFERENCE]). On your account this period now shows [OUTSTANDING]. Your historical school fees, and how to settle them, are on your portal: [PORTAL_URL]\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: your school fees for [SESSION] [SEMESTER] are assessed at [AMOUNT] ([REFERENCE]); [OUTSTANDING]. See your portal.',
 'School fees assessed for [SESSION]',
 'The Bursary has assessed your school fees for [SESSION], [SEMESTER], at [AMOUNT] (assessment [REFERENCE]): [OUTSTANDING].',
 ARRAY['FIRST_NAME','SESSION','SEMESTER','AMOUNT','REFERENCE','OUTSTANDING','PORTAL_URL','UNIVERSITY_SHORT'], true, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

-- ── 10 · the FINAL clearance's Bursary stage reads the historical account (clearance.evidence, clearance.blocker restated) ──
CREATE OR REPLACE FUNCTION clearance.evidence(p_process uuid, p_unit text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE q record; v jsonb := '{}'::jsonb;
BEGIN
    SELECT p.*, w.purpose, w.code AS wf FROM clearance.process p JOIN clearance.workflow w ON w.code = p.workflow
     WHERE p.id = p_process INTO q;
    IF q.id IS NULL THEN RETURN NULL; END IF;
    CASE upper(p_unit)
    WHEN 'BURSARY' THEN
        IF q.wf = 'FINAL' THEN
            -- V654: the historical account — each session and semester assessed as the student was then (an approved assessment, else
            -- the session's fee lines at the session's level), the verified payments allocated, a period with no amount named for review
            SELECT jsonb_build_object(
                     'historical', true, 'start', finance.historical_start(),
                     'periods', coalesce(jsonb_agg(jsonb_build_object('session', x.session, 'semester', x.semester, 'level', x.level, 'assessed', x.assessed,
                                                                      'paid', x.paid, 'outstanding', x.outstanding, 'credit', x.credit, 'status', x.status,
                                                                      'source', x.source_ref, 'pending', x.pending_ref) ORDER BY x.session, x.semester), '[]'::jsonb),
                     'outstanding', coalesce(sum(x.outstanding), 0),
                     'credit', coalesce(sum(x.credit), 0),
                     'review', count(*) FILTER (WHERE x.status = 'REQUIRES_REVIEW'),
                     'pending', count(*) FILTER (WHERE x.status = 'PENDING_APPROVAL'),
                     'owingPeriods', string_agg(x.session || ' ' || finance.semester_words(x.semester), ', ' ORDER BY x.session, x.semester) FILTER (WHERE x.outstanding > 0),
                     'reviewPeriods', string_agg(x.session || ' ' || finance.semester_words(x.semester), ', ' ORDER BY x.session, x.semester) FILTER (WHERE x.status = 'REQUIRES_REVIEW'),
                     'pendingPeriods', string_agg(x.session || ' ' || finance.semester_words(x.semester), ', ' ORDER BY x.session, x.semester) FILTER (WHERE x.status = 'PENDING_APPROVAL'))
              INTO v
              FROM finance.historical_rows(ARRAY[q.student_id]) x;
        ELSE
            SELECT jsonb_build_object('session', q.session, 'stated', finance.fee_stated(q.student_id, q.session),
                                      'due', pos.due, 'paid', pos.paid, 'balance', pos.balance,
                                      'outstanding', CASE WHEN finance.fee_stated(q.student_id, q.session) THEN greatest(pos.balance, 0) ELSE NULL END)
              INTO v FROM finance.position(q.student_id, q.session) pos;
        END IF;
    WHEN 'LIBRARY' THEN
        SELECT jsonb_build_object(
                 'openLoans', count(*) FILTER (WHERE l.returned_at IS NULL),
                 'loans', coalesce(jsonb_agg(jsonb_build_object('accession', l.accession, 'title', i.title, 'dueOn', l.due_on) ORDER BY l.due_on)
                                   FILTER (WHERE l.returned_at IS NULL), '[]'::jsonb),
                 'unpaidFines', count(*) FILTER (WHERE coalesce(l.fine, 0) > 0 AND l.fine_settled_at IS NULL AND l.fine_waived_at IS NULL),
                 'fines', coalesce(sum(l.fine) FILTER (WHERE coalesce(l.fine, 0) > 0 AND l.fine_settled_at IS NULL AND l.fine_waived_at IS NULL), 0))
          INTO v
          FROM library.loan l
          LEFT JOIN library.copy c ON c.accession = l.accession
          LEFT JOIN library.item i ON i.id = c.item_id
         WHERE l.student_id = q.student_id;
    WHEN 'HOSTEL' THEN
        SELECT jsonb_build_object(
                 'stays', coalesce(jsonb_agg(jsonb_build_object('reference', al.reference_no, 'session', al.session, 'state', al.state,
                                                                'feeStatus', al.fee_status, 'checkedOut', al.checked_out_at IS NOT NULL,
                                                                'clearance', hc.state) ORDER BY al.session) , '[]'::jsonb),
                 'checkedIn', count(*) FILTER (WHERE al.state = 'CHECKED_IN'),
                 'clearancePending', count(*) FILTER (WHERE al.state = 'CHECKED_OUT' AND coalesce(hc.state, 'PENDING') <> 'CLEARED'),
                 'unsettledCharges', (SELECT count(*) FROM hostel.damage_charge dc JOIN hostel.allocation a2 ON a2.id = dc.allocation_id
                                       WHERE a2.student_id = q.student_id AND dc.settled_at IS NULL AND dc.waived_at IS NULL AND coalesce(dc.charge, 0) > 0),
                 'charges', (SELECT coalesce(sum(dc.charge), 0) FROM hostel.damage_charge dc JOIN hostel.allocation a2 ON a2.id = dc.allocation_id
                              WHERE a2.student_id = q.student_id AND dc.settled_at IS NULL AND dc.waived_at IS NULL))
          INTO v
          FROM hostel.allocation al
          LEFT JOIN hostel.clearance hc ON hc.allocation_id = al.id
         WHERE al.student_id = q.student_id AND al.state IN ('HELD', 'CONFIRMED', 'ACCEPTED', 'CHECKED_IN', 'CHECKED_OUT', 'TRANSFERRED');
    WHEN 'HEALTH' THEN
        -- the fitness finding and its date only: never a diagnosis, a visit or an allergy
        SELECT jsonb_build_object('fitness', hp.fitness, 'fitnessOn', hp.fitness_on) INTO v
          FROM health.profile hp WHERE hp.student_id = q.student_id;
        v := coalesce(v, jsonb_build_object('fitness', NULL, 'fitnessOn', NULL));
    WHEN 'DEPARTMENT' THEN
        IF q.wf = 'FINAL' THEN
            SELECT jsonb_build_object('graduand', jsonb_build_object('session', g.session, 'cgpa', g.cgpa, 'award', g.award, 'unmet', g.unmet,
                                                                     'senate', g.senate_state))
              INTO v FROM records.graduand g WHERE g.student_id = q.student_id ORDER BY g.session DESC LIMIT 1;
            v := coalesce(v, jsonb_build_object('graduand', NULL));
        ELSE
            SELECT jsonb_build_object('registrations', coalesce(jsonb_agg(jsonb_build_object('semester', r.semester, 'status', r.status) ORDER BY r.semester), '[]'::jsonb))
              INTO v FROM registration.course_registration r WHERE r.student_id = q.student_id AND r.session = q.session;
        END IF;
    WHEN 'ALUMNI' THEN
        SELECT jsonb_build_object('email', coalesce(btrim(c.email), '') <> '', 'phone', coalesce(btrim(c.phone), '') <> '',
                                  'address', coalesce(btrim(c.address), '') <> '',
                                  'confirmed', ap.confirmed_at IS NOT NULL, 'confirmedAt', ap.confirmed_at,
                                  'member', coalesce(ap.association_member, false))
          INTO v
          FROM people.student s
          LEFT JOIN people.student_contact c ON c.student_id = s.id
          LEFT JOIN clearance.alumni_profile ap ON ap.student_id = s.id
         WHERE s.id = q.student_id;
    ELSE
        v := '{}'::jsonb;
    END CASE;
    -- every stage: the documents it holds, by state
    v := coalesce(v, '{}'::jsonb) || jsonb_build_object('documents',
           (SELECT coalesce(jsonb_object_agg(d.label, d.state), '{}'::jsonb) FROM clearance.document d
             WHERE d.process_id = p_process AND d.unit = upper(p_unit) AND d.superseded_by IS NULL));
    RETURN v;
END $function$;

CREATE OR REPLACE FUNCTION clearance.blocker(p_process uuid, p_unit text, p_evidence jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE q record; v_docs text;
BEGIN
    SELECT p.*, w.code AS wf FROM clearance.process p JOIN clearance.workflow w ON w.code = p.workflow WHERE p.id = p_process INTO q;
    -- a document the stage asks for and does not hold approved
    SELECT string_agg(x.label, ', ') INTO v_docs
      FROM clearance.workflow_stage ws CROSS JOIN LATERAL unnest(ws.documents) x(label)
     WHERE ws.workflow = q.wf AND ws.unit = upper(p_unit) AND ws.active
       AND NOT EXISTS (SELECT 1 FROM clearance.document d WHERE d.process_id = p_process AND d.unit = ws.unit
                        AND d.label = x.label AND d.superseded_by IS NULL AND d.state = 'APPROVED');
    IF v_docs IS NOT NULL THEN RETURN 'Not yet approved: ' || v_docs; END IF;
    CASE upper(p_unit)
    WHEN 'BURSARY' THEN
        IF q.wf = 'FINAL' THEN
            -- V654: not cleared over an outstanding historical school fee, a period no amount is known for, or an assessment awaiting the Bursar
            IF coalesce((p_evidence->>'outstanding')::numeric, 0) > 0 THEN
                RETURN 'Not cleared — outstanding school fees: ' || clearance.naira((p_evidence->>'outstanding')::numeric)
                       || coalesce(' (' || (p_evidence->>'owingPeriods') || ')', '');
            END IF;
            IF coalesce((p_evidence->>'review')::int, 0) > 0 THEN
                RETURN 'Historical fee review required: no fee structure or approved assessment for ' || coalesce(p_evidence->>'reviewPeriods', 'a period of the record');
            END IF;
            IF coalesce((p_evidence->>'pending')::int, 0) > 0 THEN
                RETURN 'A historical fee assessment awaits the Bursar''s approval for ' || coalesce(p_evidence->>'pendingPeriods', 'a period of the record');
            END IF;
        ELSE
            IF NOT coalesce((p_evidence->>'stated')::boolean, false) THEN
                RETURN 'The ' || q.session || ' fees are not stated for the student, so nothing can be verified';
            END IF;
            IF coalesce((p_evidence->>'outstanding')::numeric, 0) > 0 THEN
                RETURN 'Outstanding fees: ' || clearance.naira((p_evidence->>'outstanding')::numeric) || ' for ' || q.session;
            END IF;
        END IF;
    WHEN 'LIBRARY' THEN
        IF coalesce((p_evidence->>'openLoans')::int, 0) > 0 THEN
            RETURN (p_evidence->>'openLoans') || ' item(s) on loan not returned';
        END IF;
        IF coalesce((p_evidence->>'unpaidFines')::int, 0) > 0 THEN
            RETURN 'Library fines unpaid: ' || clearance.naira((p_evidence->>'fines')::numeric);
        END IF;
    WHEN 'HOSTEL' THEN
        IF coalesce((p_evidence->>'unsettledCharges')::int, 0) > 0 THEN
            RETURN 'Hostel damage charges unpaid: ' || clearance.naira((p_evidence->>'charges')::numeric);
        END IF;
        IF q.wf = 'FINAL' AND coalesce((p_evidence->>'checkedIn')::int, 0) > 0 THEN
            RETURN 'Still checked in: the stay must be checked out first';
        END IF;
        IF q.wf = 'FINAL' AND coalesce((p_evidence->>'clearancePending')::int, 0) > 0 THEN
            RETURN 'The hostel checkout clearance is not complete';
        END IF;
    WHEN 'ALUMNI' THEN
        IF NOT coalesce((p_evidence->>'confirmed')::boolean, false) THEN
            RETURN 'The student has not confirmed their alumni details';
        END IF;
    ELSE
        NULL;
    END CASE;
    RETURN NULL;
END $function$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Every graduate and approved graduand worked out once, so the figures read whole from the first time they are opened (on the
-- live-shaped copy a few seconds; afterwards a payment, an assessment, an opened account or a list read keeps them up to date)
-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
SELECT finance.historical_refresh(NULL);

COMMIT;
