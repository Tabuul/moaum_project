-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V331 — where every student stands: the effective cohort, the programme's length, the expected completion, the
--        spillover, and a reconciliation of the register migrated from the old portal
--
--   The old portal's students arrived mixed: those still in study, those who graduated, those who passed the end of
--   their programme with courses outstanding, and those who left. Nothing here rewrites a student's history. The JAMB
--   year, the admission session, the matriculation number and the entry level stay as they are; what the portal
--   computes is the student's CURRENT academic position, from the register's own facts, and the Registry decides.
--     · a session can be CANCELLED and MERGED into another (2021/2022 into 2022/2023): the student's entry session
--       stays 2021/2022, the cohort that carries them is the merged-into session (policy.effective_session);
--     · a programme's length is configured on the programme (final_level for a level-based programme, duration_years for one
--       whose level does not advance), seeded for undergraduate programmes from the rule that was
--       in force, editable by the Registry; finance.final_level reads it first;
--     · the maximum spillover (two sessions) is a policy setting (policy.progression_setting);
--     · people.academic_position holds, for every student, the computed position and the proposed classification with
--       the rule that produced it and its confidence; recomputed on the events that move a student (status, level,
--       enrolment, registration, graduand, deferment, session), so no screen computes it on load;
--     · the Registry reviews the proposal, decides, overrides a cohort on evidence, and every decision is on the
--       record (people.cohort_decision) and on the student's status history (people.status_change).
--   Graduation stays the Senate's: a student is GRADUATED by records.approve_awards and nothing else. A student at the
--   end of their programme with the record incomplete is a SPILLOVER student — still ACTIVE on the register, carried
--   within the policy's limit, flagged for review beyond it; never graduated by the calendar.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V331: student cohorts, merged sessions, spillover and the reconciliation of the migrated register', true);

-- ── 1 · a session cancelled and merged into another ───────────────────────────────────────────────────────────
ALTER TABLE policy.academic_session DROP CONSTRAINT IF EXISTS ck_session_state;
ALTER TABLE policy.academic_session ADD CONSTRAINT ck_session_state CHECK (state IN ('DRAFT', 'PLANNED', 'CURRENT', 'CLOSED', 'ARCHIVED', 'CANCELLED'));
ALTER TABLE policy.academic_session
    ADD COLUMN IF NOT EXISTS merged_into   text NULL REFERENCES policy.academic_session(name),
    ADD COLUMN IF NOT EXISTS merged_reason text NULL,
    ADD COLUMN IF NOT EXISTS merged_minute text NULL,
    ADD COLUMN IF NOT EXISTS merged_on     date NULL,
    ADD COLUMN IF NOT EXISTS merged_by     uuid NULL;
ALTER TABLE policy.academic_session DROP CONSTRAINT IF EXISTS ck_session_merged;
ALTER TABLE policy.academic_session ADD CONSTRAINT ck_session_merged CHECK (merged_into IS NULL OR (state = 'CANCELLED' AND merged_into <> name));
ALTER TABLE policy.academic_session DROP CONSTRAINT IF EXISTS ck_session_cancelled_reason;
ALTER TABLE policy.academic_session ADD CONSTRAINT ck_session_cancelled_reason CHECK (state <> 'CANCELLED' OR merged_reason IS NOT NULL);
COMMENT ON COLUMN policy.academic_session.merged_into IS 'V331: the session this cancelled session was merged into; the students admitted in it belong to that cohort, their entry session unchanged.';

-- the cohort a session's students belong to: the session itself, or the one it was merged into, followed to the end
CREATE OR REPLACE FUNCTION policy.effective_session(p_session text)
RETURNS text
LANGUAGE sql STABLE AS $$
    WITH RECURSIVE chain AS (
        SELECT a.name, a.merged_into, 1 AS depth FROM policy.academic_session a WHERE a.name = p_session
        UNION ALL
        SELECT a.name, a.merged_into, c.depth + 1 FROM chain c JOIN policy.academic_session a ON a.name = c.merged_into WHERE c.depth < 6)
    SELECT coalesce((SELECT name FROM chain WHERE merged_into IS NULL ORDER BY depth DESC LIMIT 1), p_session)
$$;

-- a session's first year, read from its name (2021/2022 → 2021); NULL where the name is not a session
CREATE OR REPLACE FUNCTION policy.session_year(p_session text)
RETURNS int
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_session ~ '^[0-9]{4}/[0-9]{4}$' AND substr(p_session, 6, 4)::int = left(p_session, 4)::int + 1 THEN left(p_session, 4)::int END
$$;

-- the n-th session after a session, by arithmetic on the name, a session the calendar cancelled skipped: the calendar need
-- not reach that far, and a session older than the calendar still counts
CREATE OR REPLACE FUNCTION policy.session_after(p_session text, p_n int)
RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE y int := policy.session_year(p_session); left_to_count int := coalesce(p_n, 0); guard int := 0;
BEGIN
    IF y IS NULL THEN RETURN NULL; END IF;
    WHILE left_to_count > 0 AND guard < 40 LOOP
        y := y + 1; guard := guard + 1;
        IF NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = y || '/' || (y + 1) AND a.state = 'CANCELLED') THEN
            left_to_count := left_to_count - 1;
        END IF;
    END LOOP;
    RETURN y || '/' || (y + 1);
END $$;

-- how many sessions lie from one session to another, cancelled sessions not counted (negative when p_to is earlier)
CREATE OR REPLACE FUNCTION policy.sessions_elapsed(p_from text, p_to text)
RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN policy.session_year(p_from) IS NULL OR policy.session_year(p_to) IS NULL THEN NULL
        WHEN policy.session_year(p_to) >= policy.session_year(p_from) THEN
            policy.session_year(p_to) - policy.session_year(p_from)
            - (SELECT count(*)::int FROM policy.academic_session a
                WHERE a.state = 'CANCELLED' AND policy.session_year(a.name) > policy.session_year(p_from) AND policy.session_year(a.name) <= policy.session_year(p_to))
        ELSE -(policy.session_year(p_from) - policy.session_year(p_to)
            - (SELECT count(*)::int FROM policy.academic_session a
                WHERE a.state = 'CANCELLED' AND policy.session_year(a.name) > policy.session_year(p_to) AND policy.session_year(a.name) <= policy.session_year(p_from))) END
$$;

-- the Registry cancels a session and merges it into another, on a reason and a minute; the current session is never cancelled
CREATE OR REPLACE FUNCTION policy.merge_session(p_session text, p_into text, p_reason text, p_minute text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; s policy.academic_session; t policy.academic_session;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a session is merged by a person' USING ERRCODE = '23514'; END IF;
    IF btrim(coalesce(p_reason, '')) = '' THEN RAISE EXCEPTION 'SESSION_MERGE_REASON: a session merger says why' USING ERRCODE = '23514', HINT = 'Cite the Senate decision that cancelled the session.'; END IF;
    SELECT * INTO s FROM policy.academic_session WHERE name = p_session FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'SESSION_UNKNOWN: no session is called %', p_session USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM policy.academic_session WHERE name = p_into;
    IF NOT FOUND THEN RAISE EXCEPTION 'SESSION_UNKNOWN: no session is called %', p_into USING ERRCODE = '23514'; END IF;
    IF s.state = 'CURRENT' THEN RAISE EXCEPTION 'SESSION_MERGE_CURRENT: the current session % is not cancelled', p_session USING ERRCODE = '23514', HINT = 'Make another session current first.'; END IF;
    IF t.state = 'CANCELLED' OR policy.effective_session(p_into) = p_session THEN
        RAISE EXCEPTION 'SESSION_MERGE_TARGET: % cannot take the students of %', p_into, p_session USING ERRCODE = '23514', HINT = 'Merge into a session that is itself in force.';
    END IF;
    UPDATE policy.academic_session
       SET state = 'CANCELLED', merged_into = p_into, merged_reason = btrim(p_reason), merged_minute = nullif(btrim(coalesce(p_minute, '')), ''),
           merged_on = current_date, merged_by = who
     WHERE name = p_session;
END $$;
COMMENT ON FUNCTION policy.merge_session(text, text, text, text) IS 'A session cancelled and merged into another (V331): the students admitted in it keep their entry session and are carried by the merged-into cohort. Reversed by policy.unmerge_session.';

CREATE OR REPLACE FUNCTION policy.unmerge_session(p_session text, p_reason text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a session merger is undone by a person' USING ERRCODE = '23514'; END IF;
    IF btrim(coalesce(p_reason, '')) = '' THEN RAISE EXCEPTION 'SESSION_MERGE_REASON: undoing a merger says why' USING ERRCODE = '23514'; END IF;
    UPDATE policy.academic_session SET state = 'CLOSED', merged_into = NULL, merged_reason = NULL, merged_minute = NULL, merged_on = NULL, merged_by = NULL
     WHERE name = p_session AND state = 'CANCELLED';
    IF NOT FOUND THEN RAISE EXCEPTION 'SESSION_NOT_MERGED: % is not a cancelled session', p_session USING ERRCODE = '23514'; END IF;
END $$;

-- a cancelled session is never made current, whatever path tries
CREATE OR REPLACE FUNCTION policy.session_cancelled_stays_so()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.state = 'CURRENT' AND (NEW.merged_into IS NOT NULL OR OLD.state = 'CANCELLED') THEN
        RAISE EXCEPTION 'SESSION_CANCELLED: % was cancelled and merged into %; it is not made current', NEW.name, NEW.merged_into USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_session_cancelled_stays_so ON policy.academic_session;
CREATE TRIGGER trg_session_cancelled_stays_so BEFORE UPDATE OF state ON policy.academic_session FOR EACH ROW EXECUTE FUNCTION policy.session_cancelled_stays_so();

-- ── 2 · the length of a programme is configured on the programme ──────────────────────────────────────────────
ALTER TABLE ref.programme
    ADD COLUMN IF NOT EXISTS final_level int NULL,
    ADD COLUMN IF NOT EXISTS duration_years int NULL,
    ADD COLUMN IF NOT EXISTS final_level_note text NULL;
ALTER TABLE ref.programme DROP CONSTRAINT IF EXISTS ck_programme_final_level;
ALTER TABLE ref.programme ADD CONSTRAINT ck_programme_final_level CHECK (final_level IS NULL OR final_level IN (300, 400, 500, 600, 700, 800, 900));
ALTER TABLE ref.programme DROP CONSTRAINT IF EXISTS ck_programme_duration;
ALTER TABLE ref.programme ADD CONSTRAINT ck_programme_duration CHECK (duration_years IS NULL OR duration_years BETWEEN 1 AND 8);
COMMENT ON COLUMN ref.programme.final_level IS 'V331: the last level of a level-based programme — 400 for four years from 100 Level, 500 for five, 600 for MBBS; a student''s length is (final level − entry level)/100 + 1 sessions. Seeded for undergraduate programmes from the rule in force; kept by the Registry.';
COMMENT ON COLUMN ref.programme.duration_years IS 'V331: the length in sessions of a programme whose level does not advance (a postgraduate programme), or a configured length that overrides the level arithmetic. Never guessed: set by the Registry, by award in one act where the programmes share one.';
-- undergraduate programmes are seeded from the rule that was in force, so nothing changes on the day and the Registry sees
-- what it inherits; a postgraduate programme's length is not a level and is not guessed: the Registry sets it, by award
UPDATE ref.programme p
   SET final_level = CASE WHEN p.code = 'C00061' THEN 600
                          WHEN upper(p.name) LIKE 'LL.B%' OR upper(p.name) LIKE '%PHARMACY%' THEN 500
                          ELSE 400 END,
       final_level_note = 'Seeded at V331 from the rule then in force (four years unless Law, Pharmacy or MBBS); confirm against the approved programme length'
 WHERE p.final_level IS NULL AND coalesce(p.category, '') <> 'POST GRADUATE';

CREATE OR REPLACE FUNCTION finance.final_level(p_programme text) RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT coalesce(p.final_level,
                    CASE WHEN p.category = 'POST GRADUATE' THEN 900
                         WHEN p.code = 'C00061' THEN 600
                         WHEN upper(p.name) LIKE 'LL.B%' OR upper(p.name) LIKE '%PHARMACY%' THEN 500
                         ELSE 400 END)
      FROM ref.programme p WHERE p.code = p_programme;
$$;
COMMENT ON FUNCTION finance.final_level(text) IS 'The last level of a programme: as configured on the programme (V331), else the rule that was in force before (four years; Law and Pharmacy five; MBBS six; a postgraduate programme 900).';

CREATE OR REPLACE FUNCTION ref.set_programme_length(p_code text, p_final_level int, p_years int, p_note text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a programme length is set by a person' USING ERRCODE = '23514'; END IF;
    IF p_final_level IS NULL AND p_years IS NULL THEN
        RAISE EXCEPTION 'PROGRAMME_LENGTH: a programme ends at a level (300 to 600; 700 to 900 postgraduate) or runs a number of sessions (1 to 8); say which' USING ERRCODE = '23514';
    END IF;
    IF p_final_level IS NOT NULL AND p_final_level NOT IN (300, 400, 500, 600, 700, 800, 900) THEN
        RAISE EXCEPTION 'PROGRAMME_LENGTH: a programme ends at 300, 400, 500, 600 or, for a postgraduate programme, 700 to 900' USING ERRCODE = '23514';
    END IF;
    IF p_years IS NOT NULL AND p_years NOT BETWEEN 1 AND 8 THEN
        RAISE EXCEPTION 'PROGRAMME_LENGTH: a programme runs one to eight sessions' USING ERRCODE = '23514';
    END IF;
    UPDATE ref.programme SET final_level = p_final_level, duration_years = p_years, final_level_note = nullif(btrim(coalesce(p_note, '')), '') WHERE code = p_code;
    IF NOT FOUND THEN RAISE EXCEPTION 'no programme is coded %', p_code USING ERRCODE = '23503'; END IF;
END $$;
COMMENT ON FUNCTION ref.set_programme_length(text, int, int, text) IS 'V331: the Registry sets a programme''s length — its last level (the length follows from the student''s entry level), its length in sessions (a postgraduate programme), or both.';

-- every programme of one postgraduate award (every PhD, every M.Sc.) takes its length in one act
CREATE OR REPLACE FUNCTION ref.set_programme_length_by_award(p_award text, p_years int, p_note text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; n int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a programme length is set by a person' USING ERRCODE = '23514'; END IF;
    IF p_years IS NULL OR p_years NOT BETWEEN 1 AND 8 THEN RAISE EXCEPTION 'PROGRAMME_LENGTH: a programme runs one to eight sessions' USING ERRCODE = '23514'; END IF;
    UPDATE ref.programme SET duration_years = p_years, final_level_note = nullif(btrim(coalesce(p_note, '')), '')
     WHERE upper(pg_award) = upper(btrim(p_award)) AND NOT coalesce(archived, false);
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n = 0 THEN RAISE EXCEPTION 'no programme carries the award %', p_award USING ERRCODE = '23503'; END IF;
    RETURN n;
END $$;

-- ── 3 · the spillover policy ───────────────────────────────────────────────────────────────────────────────────
CREATE TABLE policy.progression_setting (
    row_no              boolean PRIMARY KEY DEFAULT true CHECK (row_no),
    max_spillover_years int NOT NULL DEFAULT 2 CHECK (max_spillover_years BETWEEN 0 AND 6),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    updated_by          uuid NULL
);
INSERT INTO policy.progression_setting DEFAULT VALUES;
COMMENT ON TABLE policy.progression_setting IS 'Academic policy (V331): how many sessions beyond the programme''s length a student may remain in study as a spillover student before the Registry must review them.';
SELECT audit.attach('policy.progression_setting');

CREATE OR REPLACE FUNCTION policy.set_max_spillover(p_years int)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'the spillover policy is set by a person' USING ERRCODE = '23514'; END IF;
    UPDATE policy.progression_setting SET max_spillover_years = p_years, updated_at = now(), updated_by = who WHERE row_no;
END $$;

-- ── 4 · a cohort corrected on evidence, for one student ───────────────────────────────────────────────────────
CREATE TABLE people.cohort_override (
    student_id       uuid PRIMARY KEY REFERENCES people.student(id) ON DELETE CASCADE,
    effective_cohort text NOT NULL REFERENCES policy.academic_session(name),
    reason           text NOT NULL,
    set_by           uuid NULL,
    actor_office     text NULL,
    set_at           timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE people.cohort_override IS 'V331: the cohort the Registry assigns a student on evidence when the session rule does not fit (a re-entry, a transfer in); the entry session itself is never changed.';
SELECT audit.attach('people.cohort_override');

-- ── 5 · the computed position of every student ────────────────────────────────────────────────────────────────
CREATE TABLE people.academic_position (
    student_id          uuid PRIMARY KEY REFERENCES people.student(id) ON DELETE CASCADE,
    jamb_year           int NULL,
    matric_year         int NULL,
    entry_session       text NULL,
    effective_cohort    text NULL,
    cohort_source       text NULL,
    entry_level         int NULL,
    programme_code      text NULL,
    final_level         int NULL,
    duration_years      int NULL,
    current_session     text NULL,
    current_level       int NULL,
    computed_level      int NULL,
    expected_completion text NULL,
    deferred_sessions   int NOT NULL DEFAULT 0,
    elapsed_sessions    int NULL,
    spillover_years     int NOT NULL DEFAULT 0,
    spillover_state     text NOT NULL DEFAULT 'NORMAL',
    registered_current  boolean NOT NULL DEFAULT false,
    enrolled_current    boolean NOT NULL DEFAULT false,
    last_session        text NULL,
    graduation_state    text NULL,
    graduation_session  text NULL,
    existing_status     text NOT NULL,
    classification      text NOT NULL,
    proposed_status     text NOT NULL,
    rule                text NOT NULL,
    confidence          text NOT NULL,
    issues              text[] NOT NULL DEFAULT '{}',
    computed_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_position_spillover CHECK (spillover_state IN ('NORMAL','SPILLOVER_YEAR_1','SPILLOVER_YEAR_2','SPILLOVER_YEAR_3','SPILLOVER_LIMIT_REACHED','NOT_APPLICABLE')),
    CONSTRAINT ck_position_confidence CHECK (confidence IN ('VALIDATED','LIKELY','REVIEW'))
);
CREATE INDEX ix_position_classification ON people.academic_position (classification);
CREATE INDEX ix_position_cohort ON people.academic_position (effective_cohort);
CREATE INDEX ix_position_programme ON people.academic_position (programme_code);
CREATE INDEX ix_position_confidence ON people.academic_position (confidence) WHERE confidence <> 'VALIDATED';
CREATE INDEX ix_position_issues ON people.academic_position USING gin (issues);
COMMENT ON TABLE people.academic_position IS 'V331: where every student stands, computed from the register — the effective cohort, the programme''s length, the expected completion, the spillover, what the current session holds for them, the graduation record — and the classification proposed with the rule and its confidence. Derived: recomputed on the events that move a student; never typed.';
SELECT audit.exempt('people.academic_position', 'Derived from the register by people.academic_position_rows and recomputed on every relevant event; the decisions taken on it are recorded in people.cohort_decision and people.status_change.');

CREATE OR REPLACE FUNCTION people.academic_position_rows(p_student uuid DEFAULT NULL)
RETURNS SETOF people.academic_position
LANGUAGE sql STABLE AS $$
    WITH cur AS (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1),
    cfg AS (SELECT max_spillover_years FROM policy.progression_setting),
    st AS (
        SELECT s.id, s.matric_no, s.jamb_reg_no, s.entry_session, s.entry_level, s.programme_code, s.current_level, s.status, s.candidate_id,
               c.session AS candidate_session, p.final_level AS configured_final, p.duration_years AS configured_years, finance.final_level(s.programme_code) AS final_level,
               co.effective_cohort AS override_cohort, a.name AS entry_on_calendar, a.merged_into
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN people.cohort_override co ON co.student_id = s.id
          LEFT JOIN policy.academic_session a ON a.name = s.entry_session
         WHERE p_student IS NULL OR s.id = p_student),
    dups AS (SELECT matric_no FROM people.student WHERE matric_no IS NOT NULL GROUP BY matric_no HAVING count(*) > 1),
    defs AS (
        SELECT d.student_id,
               ceil(sum(coalesce(d.extension_semesters, people.deferment_semesters(d.kind, d.session)))::numeric / 2)::int AS sessions,
               bool_or(d.state = 'ACTIVE') AS live
          FROM people.deferment d
         WHERE d.state IN ('APPROVED','ACTIVE','COMPLETED') AND (p_student IS NULL OR d.student_id = p_student)
         GROUP BY d.student_id),
    reg AS (
        SELECT r.student_id,
               bool_or(r.session = cur.name AND r.status IN ('SUBMITTED','APPROVED','LOCKED')) AS cur_reg,
               max(r.session) FILTER (WHERE r.status IN ('SUBMITTED','APPROVED','LOCKED')) AS last_reg
          FROM registration.course_registration r LEFT JOIN cur ON true
         WHERE p_student IS NULL OR r.student_id = p_student
         GROUP BY r.student_id),
    enr AS (
        SELECT e.student_id, bool_or(e.session = cur.name) AS cur_enr, max(e.session) AS last_enr
          FROM people.enrolment e LEFT JOIN cur ON true
         WHERE p_student IS NULL OR e.student_id = p_student
         GROUP BY e.student_id),
    grad AS (
        SELECT DISTINCT ON (g.student_id) g.student_id, g.session, g.senate_state, g.unmet
          FROM records.graduand g
         WHERE p_student IS NULL OR g.student_id = p_student
         ORDER BY g.student_id, (g.senate_state = 'APPROVED') DESC, g.session DESC),
    base AS (
        SELECT st.*,
               coalesce(policy.session_year(st.candidate_session),
                        CASE WHEN st.jamb_reg_no ~ '^20[0-9]{2}[0-9]{8}[A-Z]{2}$' THEN left(st.jamb_reg_no, 4)::int END,
                        policy.session_year(st.entry_session)) AS jamb_year,
               CASE WHEN st.matric_no ~ '/[0-9]{2}/' THEN 2000 + (regexp_match(st.matric_no, '/([0-9]{2})/'))[1]::int END AS matric_year,
               coalesce(st.override_cohort, policy.effective_session(st.entry_session)) AS effective_cohort,
               CASE WHEN st.override_cohort IS NOT NULL THEN 'OVERRIDE' WHEN st.merged_into IS NOT NULL THEN 'MERGED' ELSE 'ENTRY' END AS cohort_source,
               coalesce(st.configured_years, CASE WHEN st.configured_final IS NOT NULL THEN greatest((st.configured_final - coalesce(st.entry_level, 100)) / 100 + 1, 1) END) AS duration_years,
               st.configured_final IS NOT NULL AS level_based,
               coalesce(d.sessions, 0) AS deferred_sessions, coalesce(d.live, false) AS live_deferment,
               coalesce(r.cur_reg, false) AS registered_current, greatest(r.last_reg, e.last_enr) AS last_session,
               coalesce(e.cur_enr, false) AS enrolled_current,
               g.senate_state AS graduation_state, g.session AS graduation_session, g.unmet AS graduation_unmet, g.student_id IS NOT NULL AS has_graduand,
               st.matric_no IN (SELECT matric_no FROM dups) AS dup_matric,
               (SELECT name FROM cur) AS current_session, (SELECT max_spillover_years FROM cfg) AS max_spill
          FROM st LEFT JOIN defs d ON d.student_id = st.id LEFT JOIN reg r ON r.student_id = st.id
               LEFT JOIN enr e ON e.student_id = st.id LEFT JOIN grad g ON g.student_id = st.id),
    timed AS (
        SELECT b.*,
               CASE WHEN b.duration_years IS NOT NULL THEN policy.session_after(b.effective_cohort, b.duration_years - 1 + b.deferred_sessions) END AS expected_completion,
               policy.sessions_elapsed(b.effective_cohort, b.current_session) AS elapsed_sessions
          FROM base b),
    measured AS (
        SELECT t.*,
               greatest(0, coalesce(policy.sessions_elapsed(t.expected_completion, t.current_session), 0)) AS spillover_years,
               CASE WHEN t.elapsed_sessions IS NULL THEN NULL
                    WHEN NOT t.level_based THEN coalesce(t.entry_level, t.current_level)
                    ELSE least(t.configured_final, coalesce(t.entry_level, 100) + 100 * greatest(0, t.elapsed_sessions - t.deferred_sessions)) END AS computed_level
          FROM timed t),
    ruled AS (
        SELECT m.*,
               CASE
                 WHEN m.graduation_state = 'APPROVED' OR m.status = 'GRADUATED' THEN 'R1'
                 WHEN m.status IN ('WITHDRAWN','VOLUNTARY_WITHDRAWAL','EXPELLED','DECEASED','TRANSFERRED_OUT','RUSTICATED','SUSPENDED','DORMANT','DEFERRED','ADMITTED') THEN 'R2'
                 WHEN m.entry_session IS NULL OR policy.session_year(m.effective_cohort) IS NULL OR m.duration_years IS NULL OR m.current_session IS NULL THEN 'R6'
                 WHEN m.has_graduand AND m.graduation_unmet IS NULL AND m.graduation_state <> 'APPROVED' THEN 'R5'
                 WHEN m.spillover_years > m.max_spill THEN 'R4L'
                 WHEN m.spillover_years > 0 THEN 'R4'
                 WHEN m.registered_current OR m.enrolled_current THEN 'R3'
                 WHEN m.last_session IS NULL THEN 'R6'
                 ELSE 'R3L' END AS rule,
               array_remove(ARRAY[
                   CASE WHEN m.entry_session IS NULL THEN 'MISSING_ENTRY_SESSION' END,
                   CASE WHEN m.entry_session IS NOT NULL AND policy.session_year(m.entry_session) IS NULL THEN 'ENTRY_SESSION_INVALID' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.elapsed_sessions < 0 THEN 'ENTRY_SESSION_AHEAD' END,
                   CASE WHEN m.matric_no IS NULL AND m.status <> 'ADMITTED' THEN 'MISSING_MATRIC' END,
                   CASE WHEN m.jamb_reg_no IS NULL THEN 'MISSING_JAMB' END,
                   CASE WHEN m.duration_years IS NULL THEN 'DURATION_NOT_CONFIGURED' END,
                   CASE WHEN m.dup_matric THEN 'DUPLICATE_MATRIC' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.computed_level IS NOT NULL AND m.computed_level <> m.current_level THEN 'LEVEL_CONFLICT' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND NOT m.registered_current AND NOT m.enrolled_current THEN 'NO_CURRENT_REGISTRATION' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.last_session IS NULL THEN 'NO_REGISTRATION_HISTORY' END,
                   CASE WHEN m.status = 'GRADUATED' AND m.graduation_state IS DISTINCT FROM 'APPROVED' THEN 'GRADUATED_WITHOUT_APPROVAL' END,
                   CASE WHEN m.status <> 'GRADUATED' AND m.graduation_state = 'APPROVED' THEN 'APPROVED_NOT_GRADUATED' END,
                   CASE WHEN m.status = 'DEFERRED' AND NOT m.live_deferment THEN 'DEFERRED_WITHOUT_LIVE_DEFERMENT' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.spillover_years > m.max_spill THEN 'SPILLOVER_LIMIT_REACHED' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.spillover_years > 0 THEN 'BEYOND_PROGRAMME_LENGTH' END
               ]::text[], NULL) AS issues
          FROM measured m)
    SELECT r.id,
           r.jamb_year, r.matric_year, r.entry_session, r.effective_cohort, r.cohort_source, r.entry_level, r.programme_code, r.final_level, r.duration_years,
           r.current_session, r.current_level, r.computed_level, r.expected_completion, r.deferred_sessions, r.elapsed_sessions, r.spillover_years,
           CASE WHEN r.status NOT IN ('ACTIVE','PROBATION') THEN 'NOT_APPLICABLE'
                WHEN r.spillover_years = 0 THEN 'NORMAL'
                WHEN r.spillover_years > r.max_spill THEN 'SPILLOVER_LIMIT_REACHED'
                ELSE 'SPILLOVER_YEAR_' || least(r.spillover_years, 3) END,
           r.registered_current, r.enrolled_current, r.last_session, r.graduation_state, r.graduation_session,
           r.status,
           CASE r.rule
             WHEN 'R1'  THEN 'GRADUATED'
             WHEN 'R2'  THEN r.status
             WHEN 'R5'  THEN 'GRADUATION_ELIGIBLE'
             WHEN 'R4L' THEN 'SPILLOVER_LIMIT_REACHED'
             WHEN 'R4'  THEN 'SPILLOVER'
             WHEN 'R3'  THEN 'ACTIVE'
             WHEN 'R3L' THEN 'ACTIVE'
             ELSE 'REQUIRES_REVIEW' END,
           CASE r.rule WHEN 'R1' THEN 'GRADUATED' WHEN 'R3' THEN CASE WHEN r.status IN ('ACTIVE','PROBATION') THEN r.status ELSE 'ACTIVE' END
                       WHEN 'R3L' THEN r.status WHEN 'R4' THEN r.status WHEN 'R5' THEN r.status ELSE r.status END,
           r.rule,
           CASE
             WHEN r.rule = 'R1' AND r.graduation_state = 'APPROVED' AND r.status IN ('GRADUATED','ACTIVE','PROBATION') THEN 'VALIDATED'
             WHEN r.rule = 'R1' THEN 'REVIEW'
             WHEN r.rule = 'R2' AND NOT (r.status = 'DEFERRED' AND NOT r.live_deferment) THEN 'VALIDATED'
             WHEN r.rule IN ('R6', 'R4L') THEN 'REVIEW'
             WHEN r.dup_matric OR (r.status IN ('ACTIVE','PROBATION') AND r.computed_level IS NOT NULL AND r.computed_level <> r.current_level AND r.spillover_years = 0) THEN 'REVIEW'
             WHEN r.rule IN ('R3', 'R5') THEN 'VALIDATED'
             WHEN r.rule = 'R4' AND (r.registered_current OR r.enrolled_current) THEN 'VALIDATED'
             ELSE 'LIKELY' END,
           r.issues,
           now()
      FROM ruled r
$$;
COMMENT ON FUNCTION people.academic_position_rows(uuid) IS 'Every student''s position computed from the register in one pass (V331), or one student''s. Rules, in order: R1 an approved award is GRADUATED; R2 an official status stands; R6 a record too thin to judge is REQUIRES_REVIEW; R5 an audited graduand with nothing unmet is GRADUATION_ELIGIBLE; R4 beyond the programme''s length is SPILLOVER, beyond the policy''s limit REQUIRES_REVIEW; R3 registered or enrolled in the current session is ACTIVE. The matriculation year is read, never used to decide.';

CREATE OR REPLACE FUNCTION people.refresh_academic_position(p_student uuid DEFAULT NULL)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    INSERT INTO people.academic_position AS ap
    SELECT * FROM people.academic_position_rows(p_student)
    ON CONFLICT (student_id) DO UPDATE SET
        jamb_year = EXCLUDED.jamb_year, matric_year = EXCLUDED.matric_year, entry_session = EXCLUDED.entry_session, effective_cohort = EXCLUDED.effective_cohort,
        cohort_source = EXCLUDED.cohort_source, entry_level = EXCLUDED.entry_level, programme_code = EXCLUDED.programme_code, final_level = EXCLUDED.final_level,
        duration_years = EXCLUDED.duration_years, current_session = EXCLUDED.current_session, current_level = EXCLUDED.current_level, computed_level = EXCLUDED.computed_level,
        expected_completion = EXCLUDED.expected_completion, deferred_sessions = EXCLUDED.deferred_sessions, elapsed_sessions = EXCLUDED.elapsed_sessions,
        spillover_years = EXCLUDED.spillover_years, spillover_state = EXCLUDED.spillover_state, registered_current = EXCLUDED.registered_current,
        enrolled_current = EXCLUDED.enrolled_current, last_session = EXCLUDED.last_session, graduation_state = EXCLUDED.graduation_state,
        graduation_session = EXCLUDED.graduation_session, existing_status = EXCLUDED.existing_status, classification = EXCLUDED.classification,
        proposed_status = EXCLUDED.proposed_status, rule = EXCLUDED.rule, confidence = EXCLUDED.confidence, issues = EXCLUDED.issues, computed_at = EXCLUDED.computed_at;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF p_student IS NULL THEN
        DELETE FROM people.academic_position ap WHERE NOT EXISTS (SELECT 1 FROM people.student s WHERE s.id = ap.student_id);
    END IF;
    RETURN n;
END $$;

-- recomputed on the events that move a student; a bulk load under maintenance recomputes afterwards in one pass
CREATE OR REPLACE FUNCTION people.position_touch()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
    IF coalesce(current_setting('moaum.maintenance', true), '') = 'on' THEN RETURN NULL; END IF;
    -- each branch is its own statement, so the row type of the table firing is the only one read
    IF TG_TABLE_NAME = 'student' THEN v := NEW.id; ELSE v := NEW.student_id; END IF;
    IF v IS NOT NULL THEN PERFORM people.refresh_academic_position(v); END IF;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_position_student AFTER INSERT OR UPDATE OF status, current_level, entry_session, entry_level, programme_code, matric_no ON people.student
    FOR EACH ROW EXECUTE FUNCTION people.position_touch();
CREATE TRIGGER trg_position_enrolment AFTER INSERT OR UPDATE ON people.enrolment FOR EACH ROW EXECUTE FUNCTION people.position_touch();
CREATE TRIGGER trg_position_registration AFTER INSERT OR UPDATE OF status, level ON registration.course_registration FOR EACH ROW EXECUTE FUNCTION people.position_touch();
CREATE TRIGGER trg_position_graduand AFTER INSERT OR UPDATE ON records.graduand FOR EACH ROW EXECUTE FUNCTION people.position_touch();
CREATE TRIGGER trg_position_deferment AFTER INSERT OR UPDATE OF state ON people.deferment FOR EACH ROW EXECUTE FUNCTION people.position_touch();
CREATE TRIGGER trg_position_override AFTER INSERT OR UPDATE ON people.cohort_override FOR EACH ROW EXECUTE FUNCTION people.position_touch();

-- a session made current, cancelled or merged moves everybody: the whole register is recomputed in one pass
CREATE OR REPLACE FUNCTION policy.position_recompute_all()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF coalesce(current_setting('moaum.maintenance', true), '') = 'on' THEN RETURN NULL; END IF;
    PERFORM people.refresh_academic_position(NULL);
    RETURN NULL;
END $$;
CREATE TRIGGER trg_position_session AFTER UPDATE OF state, merged_into ON policy.academic_session FOR EACH STATEMENT EXECUTE FUNCTION policy.position_recompute_all();
CREATE TRIGGER trg_position_programme AFTER UPDATE OF final_level, duration_years ON ref.programme FOR EACH STATEMENT EXECUTE FUNCTION policy.position_recompute_all();
CREATE TRIGGER trg_position_policy AFTER UPDATE ON policy.progression_setting FOR EACH STATEMENT EXECUTE FUNCTION policy.position_recompute_all();

-- ── 6 · the Registry's decisions, on the record ───────────────────────────────────────────────────────────────
CREATE TABLE people.cohort_decision (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id       uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    previous_status  text NOT NULL,
    proposed_status  text NULL,
    final_status     text NOT NULL,
    classification   text NULL,
    previous_cohort  text NULL,
    effective_cohort text NULL,
    previous_level   int NULL,
    new_level        int NULL,
    rule             text NULL,
    reason           text NOT NULL,
    officer          uuid NULL,
    actor_office     text NULL,
    batch_ref        text NULL,
    decided_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_cohort_decision_student ON people.cohort_decision (student_id, decided_at DESC);
CREATE INDEX ix_cohort_decision_batch ON people.cohort_decision (batch_ref) WHERE batch_ref IS NOT NULL;
COMMENT ON TABLE people.cohort_decision IS 'V331: every classification decision the Registry took on a student — what was proposed, what was decided, the cohort and level before and after, the rule, the officer, the reason and the batch — beside the status change it caused on people.status_change.';
SELECT audit.attach('people.cohort_decision');

CREATE OR REPLACE FUNCTION people.decide_cohort(p_student uuid, p_final_status text, p_reason text, p_batch text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        s people.student; pos people.academic_position; v uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a cohort decision is taken by a person' USING ERRCODE = '23514'; END IF;
    IF btrim(coalesce(p_reason, '')) = '' THEN RAISE EXCEPTION 'COHORT_REASON: a decision on a student''s standing says why' USING ERRCODE = '23514', HINT = 'Cite the evidence: the result, the minute, the letter.'; END IF;
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no student %', p_student USING ERRCODE = 'no_data_found'; END IF;
    IF p_final_status NOT IN ('ADMITTED','ACTIVE','PROBATION','DEFERRED','SUSPENDED','RUSTICATED','WITHDRAWN','EXPELLED','TRANSFERRED_OUT','GRADUATED','DECEASED','DORMANT','VOLUNTARY_WITHDRAWAL') THEN
        RAISE EXCEPTION 'COHORT_STATUS: % is not a student status', p_final_status USING ERRCODE = '23514';
    END IF;
    IF p_final_status = 'GRADUATED' AND NOT EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = p_student AND g.senate_state = 'APPROVED') THEN
        RAISE EXCEPTION 'COHORT_GRADUATION_SENATE: a student is graduated by the Senate''s approval of the award, not by a reconciliation' USING ERRCODE = '23514',
            HINT = 'Audit the graduation list for the session and approve the awards on the minute; the status follows.';
    END IF;
    PERFORM people.refresh_academic_position(p_student);
    SELECT * INTO pos FROM people.academic_position WHERE student_id = p_student;
    IF p_final_status <> s.status THEN
        PERFORM people.change_status(p_student, p_final_status, 'Cohort reconciliation' || coalesce(' · ' || p_batch, ''), current_date, btrim(p_reason));
    END IF;
    INSERT INTO people.cohort_decision (student_id, previous_status, proposed_status, final_status, classification, previous_cohort, effective_cohort, previous_level, new_level, rule, reason, officer, actor_office, batch_ref)
    VALUES (p_student, s.status, pos.proposed_status, p_final_status, pos.classification, pos.entry_session, pos.effective_cohort, s.current_level, s.current_level, pos.rule, btrim(p_reason), who, office, nullif(btrim(coalesce(p_batch, '')), ''))
    RETURNING id INTO v;
    PERFORM people.refresh_academic_position(p_student);
    RETURN v;
END $$;
COMMENT ON FUNCTION people.decide_cohort(uuid, text, text, text) IS 'The Registry''s decision on one student''s standing (V331): the status changed through people.change_status where it differs, the decision recorded with the proposal it answered. GRADUATED is refused without the Senate''s approved award.';

CREATE OR REPLACE FUNCTION people.set_cohort_override(p_student uuid, p_cohort text, p_reason text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), ''); s people.student;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a cohort is corrected by a person' USING ERRCODE = '23514'; END IF;
    IF btrim(coalesce(p_reason, '')) = '' THEN RAISE EXCEPTION 'COHORT_REASON: a cohort correction says why' USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'no student %', p_student USING ERRCODE = 'no_data_found'; END IF;
    IF p_cohort IS NULL THEN
        DELETE FROM people.cohort_override WHERE student_id = p_student;
        INSERT INTO people.cohort_decision (student_id, previous_status, final_status, previous_cohort, effective_cohort, rule, reason, officer, actor_office)
        VALUES (p_student, s.status, s.status, s.entry_session, policy.effective_session(s.entry_session), 'COHORT', 'Cohort override removed: ' || btrim(p_reason), who, office);
        PERFORM people.refresh_academic_position(p_student);
        RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_cohort AND state <> 'CANCELLED') THEN
        RAISE EXCEPTION 'COHORT_SESSION: % is not a session in force', p_cohort USING ERRCODE = '23514', HINT = 'A cohort is a session on the calendar that was not cancelled.';
    END IF;
    INSERT INTO people.cohort_override (student_id, effective_cohort, reason, set_by, actor_office)
    VALUES (p_student, p_cohort, btrim(p_reason), who, office)
    ON CONFLICT (student_id) DO UPDATE SET effective_cohort = EXCLUDED.effective_cohort, reason = EXCLUDED.reason, set_by = EXCLUDED.set_by, actor_office = EXCLUDED.actor_office, set_at = now();
    INSERT INTO people.cohort_decision (student_id, previous_status, final_status, previous_cohort, effective_cohort, rule, reason, officer, actor_office)
    VALUES (p_student, s.status, s.status, s.entry_session, p_cohort, 'COHORT', btrim(p_reason), who, office);
END $$;

-- the Registry applies a rule's validated proposals in one act, or counts what it would do
CREATE OR REPLACE FUNCTION people.apply_cohort_rule(p_rule text, p_reason text, p_batch text, p_dry_run boolean DEFAULT true)
RETURNS TABLE (considered int, applied int)
LANGUAGE plpgsql AS $$
DECLARE r record; n int := 0; k int := 0;
BEGIN
    IF p_rule <> 'R1' THEN
        RAISE EXCEPTION 'COHORT_RULE: only the Senate''s approved awards (R1) are applied in bulk; every other standing is decided one student at a time' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT ap.student_id FROM people.academic_position ap WHERE ap.rule = p_rule AND ap.confidence = 'VALIDATED' AND ap.proposed_status <> ap.existing_status ORDER BY ap.student_id LOOP
        n := n + 1;
        IF NOT p_dry_run THEN
            PERFORM people.decide_cohort(r.student_id, 'GRADUATED', coalesce(nullif(btrim(p_reason), ''), 'Award approved by Senate; status reconciled'), p_batch);
            k := k + 1;
        END IF;
    END LOOP;
    RETURN QUERY SELECT n, k;
END $$;

-- ── 7 · the first computation of the whole register ───────────────────────────────────────────────────────────
SELECT people.refresh_academic_position(NULL);

-- ── 8 · grants, as the schema's default privileges give them; the student reads their own position ──────────
GRANT SELECT ON people.academic_position TO app_student, app_auditor, app_acrecords, app_registration, app_reporting;
GRANT SELECT ON people.cohort_decision, people.cohort_override, policy.progression_setting TO app_auditor, app_acrecords, app_reporting;

COMMIT;
