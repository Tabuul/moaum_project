-- ═══════════════════════════════════════
-- V463 — Register uploads fast: a student's academic position refreshed once per batch, and only when it moved
--
--   A Students register of 50,000 rows took one to two hours in 400-row batches. Measured on the live-shaped copy, a batch of
--   400 students already on the register took 48 s, and 98 % of it was people.refresh_academic_position (V331): the position
--   trigger on people.student fires for every row the upload's upsert names its columns in, changed or not, and refreshes
--   one student at a time at about 110 ms each — the same body reads the whole register at about 10 ms a student.
--
--   1 · people.academic_position_rows_of(students[]) is V431's people.academic_position_rows with its five one-student filters
--       taking an array; people.academic_position_rows(student) now reads it (one body, the same rules for one and for
--       many). people.refresh_academic_positions(students[]) upserts many at once, as refresh_academic_position does one.
--   2 · The position triggers on people.student and registration.course_registration fire on insert as before, and on update
--       only when a column they watch actually changes (status, levels, entry session, programme, matriculation number; a
--       registration's status and level): an upsert that rewrites a student unchanged no longer recomputes them.
--   3 · Inside a register upload (people.import_students, people.import_biography, people.import_postgraduate) the trigger
--       notes the student instead (moaum.position_defer, local to the transaction), and the batch's students are refreshed
--       together when it ends — the same rows as before, written once. Everywhere else a student moved is refreshed at once.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V463: register uploads fast, the academic position refreshed once per batch', true);

-- ── 1 · the position, read and refreshed for many students at once ─────────────────────────────────────────────────────
CREATE FUNCTION people.academic_position_rows_of(p_students uuid[])
 RETURNS SETOF people.academic_position
 LANGUAGE sql
 STABLE
AS $function$
    WITH cur AS (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1),
    -- V381: a CCE student stands in the CCE session, for the CCE duration of the programme (six years unless stated)
    cce AS (SELECT policy.route_session('CCE') AS name),
    cfg AS (SELECT max_spillover_years FROM policy.progression_setting),
    st AS (
        SELECT s.id, s.matric_no, s.jamb_reg_no, s.entry_session, s.entry_level, s.programme_code, s.current_level, s.status, s.candidate_id, s.entry_mode,
               s.duplicate_of IS NOT NULL AS ended_duplicate,
               c.session AS candidate_session,
               CASE WHEN s.entry_mode = 'CCE' THEN rt.final_level ELSE p.final_level END AS configured_final,
               CASE WHEN s.entry_mode = 'CCE' THEN rt.duration_years ELSE p.duration_years END AS configured_years,
               CASE WHEN s.entry_mode = 'CCE' THEN rt.final_level ELSE finance.final_level(s.programme_code) END AS final_level,
               co.effective_cohort AS override_cohort, a.name AS entry_on_calendar, a.merged_into
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN LATERAL ref.programme_route_terms(s.programme_code, 'CCE') rt ON s.entry_mode = 'CCE'
          LEFT JOIN people.cohort_override co ON co.student_id = s.id
          LEFT JOIN policy.academic_session a ON a.name = s.entry_session
         WHERE p_students IS NULL OR s.id = ANY (p_students)),
    dups AS (SELECT matric_no FROM people.student WHERE matric_no IS NOT NULL GROUP BY matric_no HAVING count(*) > 1),
    defs AS (
        SELECT d.student_id,
               ceil(sum(coalesce(d.extension_semesters, people.deferment_semesters(d.kind, d.session)))::numeric / 2)::int AS sessions,
               bool_or(d.state = 'ACTIVE') AS live
          FROM people.deferment d
         WHERE d.state IN ('APPROVED','ACTIVE','COMPLETED') AND (p_students IS NULL OR d.student_id = ANY (p_students))
         GROUP BY d.student_id),
    reg AS (
        SELECT r.student_id,
               bool_or(r.session = cur.name AND r.status IN ('SUBMITTED','APPROVED','LOCKED')) AS cur_reg,
               bool_or(r.session = (SELECT name FROM cce) AND r.status IN ('SUBMITTED','APPROVED','LOCKED')) AS cce_reg,
               max(r.session) FILTER (WHERE r.status IN ('SUBMITTED','APPROVED','LOCKED')) AS last_reg
          FROM registration.course_registration r LEFT JOIN cur ON true
         WHERE p_students IS NULL OR r.student_id = ANY (p_students)
         GROUP BY r.student_id),
    enr AS (
        SELECT e.student_id, bool_or(e.session = cur.name) AS cur_enr, bool_or(e.session = (SELECT name FROM cce)) AS cce_enr, max(e.session) AS last_enr
          FROM people.enrolment e LEFT JOIN cur ON true
         WHERE p_students IS NULL OR e.student_id = ANY (p_students)
         GROUP BY e.student_id),
    grad AS (
        SELECT DISTINCT ON (g.student_id) g.student_id, g.session, g.senate_state, g.unmet
          FROM records.graduand g
         WHERE p_students IS NULL OR g.student_id = ANY (p_students)
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
               coalesce(CASE WHEN st.entry_mode = 'CCE' THEN r.cce_reg ELSE r.cur_reg END, false) AS registered_current, greatest(r.last_reg, e.last_enr) AS last_session,
               coalesce(CASE WHEN st.entry_mode = 'CCE' THEN e.cce_enr ELSE e.cur_enr END, false) AS enrolled_current,
               g.senate_state AS graduation_state, g.session AS graduation_session, g.unmet AS graduation_unmet, g.student_id IS NOT NULL AS has_graduand,
               st.matric_no IN (SELECT matric_no FROM dups) AS dup_matric,
               CASE WHEN st.entry_mode = 'CCE' THEN (SELECT name FROM cce) ELSE (SELECT name FROM cur) END AS current_session, (SELECT max_spillover_years FROM cfg) AS max_spill
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
                   CASE WHEN m.matric_no IS NULL AND m.status <> 'ADMITTED' AND NOT m.ended_duplicate THEN 'MISSING_MATRIC' END,
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
$function$;

CREATE OR REPLACE FUNCTION people.academic_position_rows(p_student uuid DEFAULT NULL::uuid)
 RETURNS SETOF people.academic_position
 LANGUAGE sql
 STABLE
AS $function$
    -- V463: one student, or every student (NULL), read by the one body that reads many
    SELECT * FROM people.academic_position_rows_of(CASE WHEN p_student IS NULL THEN NULL ELSE ARRAY[p_student] END)
$function$;

CREATE FUNCTION people.refresh_academic_positions(p_students uuid[])
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    IF p_students IS NULL OR cardinality(p_students) = 0 THEN RETURN 0; END IF;
    INSERT INTO people.academic_position AS ap
    SELECT * FROM people.academic_position_rows_of(p_students)
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
    RETURN n;
END $$;

COMMENT ON FUNCTION people.academic_position_rows_of(uuid[]) IS
  'V463: each listed student''s academic position as V431 reads it (every student when NULL) — the one body people.academic_position_rows reads.';
COMMENT ON FUNCTION people.refresh_academic_positions(uuid[]) IS
  'V463: the listed students'' academic positions recomputed and kept together, in one statement. Returns the positions written.';

CREATE OR REPLACE FUNCTION people.position_touch()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
    IF coalesce(current_setting('moaum.maintenance', true), '') = 'on' THEN RETURN NULL; END IF;
    -- each branch is its own statement, so the row type of the table firing is the only one read
    IF TG_TABLE_NAME = 'student' THEN v := NEW.id; ELSE v := NEW.student_id; END IF;
    IF v IS NULL THEN RETURN NULL; END IF;
    -- V463: inside a register upload, the student is noted and the batch's students refreshed together when it ends
    IF coalesce(current_setting('moaum.position_defer', true), '') = 'on' THEN
        PERFORM set_config('moaum.position_pending', coalesce(current_setting('moaum.position_pending', true), '') || v::text || ',', true);
        RETURN NULL;
    END IF;
    PERFORM people.refresh_academic_position(v);
    RETURN NULL;
END $$;

-- ── 2 · the triggers: on update, only a change they watch ────────────────────────────────────────────────────────────────
DROP TRIGGER trg_position_student ON people.student;
CREATE TRIGGER trg_position_student_insert AFTER INSERT ON people.student
    FOR EACH ROW EXECUTE FUNCTION people.position_touch();
CREATE TRIGGER trg_position_student AFTER UPDATE OF status, current_level, entry_session, entry_level, programme_code, matric_no ON people.student
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status OR OLD.current_level IS DISTINCT FROM NEW.current_level
          OR OLD.entry_session IS DISTINCT FROM NEW.entry_session OR OLD.entry_level IS DISTINCT FROM NEW.entry_level
          OR OLD.programme_code IS DISTINCT FROM NEW.programme_code OR OLD.matric_no IS DISTINCT FROM NEW.matric_no)
    EXECUTE FUNCTION people.position_touch();
DROP TRIGGER trg_position_registration ON registration.course_registration;
CREATE TRIGGER trg_position_registration_insert AFTER INSERT ON registration.course_registration
    FOR EACH ROW EXECUTE FUNCTION people.position_touch();
CREATE TRIGGER trg_position_registration AFTER UPDATE OF status, level ON registration.course_registration
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status OR OLD.level IS DISTINCT FROM NEW.level)
    EXECUTE FUNCTION people.position_touch();

-- ── 3 · deferred inside a register upload ──────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.defer_positions()
RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
    -- already deferred by an outer upload: that one refreshes
    IF coalesce(current_setting('moaum.position_defer', true), '') = 'on' THEN RETURN false; END IF;
    PERFORM set_config('moaum.position_defer', 'on', true), set_config('moaum.position_pending', '', true);
    RETURN true;
END $$;
COMMENT ON FUNCTION people.defer_positions() IS
  'V463: from now until people.refresh_deferred_positions, in this transaction, a student the position triggers would refresh is noted instead. Returns whether this call began the deferral (an outer one already deferring returns false and refreshes itself).';

CREATE FUNCTION people.refresh_deferred_positions()
RETURNS int LANGUAGE plpgsql AS $$
DECLARE v_ids uuid[];
BEGIN
    v_ids := ARRAY(SELECT DISTINCT x::uuid FROM unnest(string_to_array(coalesce(current_setting('moaum.position_pending', true), ''), ',')) x WHERE x <> '');
    PERFORM set_config('moaum.position_defer', '', true), set_config('moaum.position_pending', '', true);
    RETURN people.refresh_academic_positions(v_ids);
END $$;
COMMENT ON FUNCTION people.refresh_deferred_positions() IS
  'V463: ends the deferral people.defer_positions began and refreshes the students noted meanwhile, together. Returns the positions written.';

-- the uploads
CREATE OR REPLACE FUNCTION people.import_students(p_rows jsonb)
 RETURNS TABLE(rows integer, created integer, updated integer, no_programme integer, bad_number integer, skipped integer, first_error text)
 LANGUAGE plpgsql
AS $function$
DECLARE r record; v_mine boolean;
BEGIN
    v_mine := people.defer_positions();   -- V463: the batch's students refreshed once, together
    FOR r IN SELECT * FROM people.import_students_rows(p_rows) LOOP
        rows := r.rows; created := r.created; updated := r.updated; no_programme := r.no_programme;
        bad_number := r.bad_number; skipped := r.skipped; first_error := r.first_error;
        -- the students this payload brought over from the old portal arrive cleared (V231)
        PERFORM clearance.clear_on_migration(s.id)
           FROM people.student s
          WHERE s.matric_no IS NOT NULL AND s.matriculation_run IS NULL
            AND s.current_level BETWEEN 100 AND 400
            AND upper(s.matric_no) IN (
                SELECT upper(btrim(coalesce(x->>'matric', x->>'matricNo', x->>'matric_no', x->>'matno', x->>'regNo', '')))
                  FROM jsonb_array_elements(p_rows) x);
        RETURN NEXT;
    END LOOP;
    IF v_mine THEN PERFORM people.refresh_deferred_positions(); END IF;
END $function$;

CREATE OR REPLACE FUNCTION people.import_biography(p_rows jsonb)
 RETURNS TABLE(rows integer, created integer, updated integer, no_programme integer, bad_number integer, contacts integer, biography integer, accounts integer, skipped integer, first_error text)
 LANGUAGE plpgsql
AS $function$
DECLARE r record; v_mine boolean;
BEGIN
    v_mine := people.defer_positions();   -- V463: the batch's students refreshed once, together
    FOR r IN SELECT * FROM people.import_biography_rows(p_rows) LOOP
        rows := r.rows; created := r.created; updated := r.updated; no_programme := r.no_programme;
        bad_number := r.bad_number; contacts := r.contacts; biography := r.biography; accounts := r.accounts;
        skipped := r.skipped; first_error := r.first_error;
        PERFORM clearance.clear_on_migration(s.id)
           FROM people.student s
          WHERE s.matric_no IS NOT NULL AND s.matriculation_run IS NULL
            AND s.current_level BETWEEN 100 AND 400
            AND upper(s.matric_no) IN (
                SELECT upper(btrim(coalesce(x->>'matric', x->>'matricNo', x->>'matric_no', x->>'matno', x->>'regNo', '')))
                  FROM jsonb_array_elements(p_rows) x);
        RETURN NEXT;
    END LOOP;
    IF v_mine THEN PERFORM people.refresh_deferred_positions(); END IF;
END $function$;

CREATE OR REPLACE FUNCTION people.import_postgraduate(p_rows jsonb)
 RETURNS TABLE(rows integer, created integer, updated integer, no_programme integer, bad_number integer, contacts integer, biography integer, accounts integer, skipped integer, first_error text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    r jsonb;
    v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_matric text; v_prog text; v_prog_code text; v_sex text; v_dob date; v_jamb text;
    v_es text; v_yy text; v_el int; v_cl int; v_stated boolean; v_surname text; v_others text; v_school text;
    v_state text; v_phone text; v_email text; v_addr text; v_student uuid; v_exists boolean;
    v_fac text; v_dept text; v_award text; v_dname text;
    bf text; bv text; l_contact int; l_bio int; l_acct int;
    v_sealed text;   -- one hash per upload, made when the first account is opened (V294)
    n int := 0; nc int := 0; nu int := 0; nnp int := 0; nbn int := 0;
    ncontact int := 0; nbio int := 0; nacct int := 0; nerr int := 0; v_firsterr text := NULL;
        v_mine boolean;   -- V463
BEGIN
    v_mine := people.defer_positions();   -- V463: the batch's students refreshed once, together
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, name, programme, level, and the biography'
            USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'matno', r->>'regNo', '')));
        IF v_matric = '' THEN CONTINUE; END IF;
        n := n + 1;

        -- any institutional matriculation number: a 2–6 letter prefix (MOAU / MOAUM / BSU …) then 2–8 segments
        IF v_matric !~ '^[A-Z]{2,6}(/[A-Z0-9]{1,12}){2,8}$' THEN
            nbn := nbn + 1; CONTINUE;
        END IF;

        -- resolve the programme by code, then by name; create it as POST GRADUATE when it is not on record
        v_prog := btrim(coalesce(r->>'programme', r->>'programmeCode', r->>'programme_code', r->>'course', ''));
        v_prog_code := NULL;
        IF v_prog <> '' THEN
            SELECT code INTO v_prog_code FROM ref.programme WHERE upper(code) = upper(v_prog);
            IF v_prog_code IS NULL THEN
                SELECT code INTO v_prog_code FROM ref.programme WHERE upper(name) = upper(v_prog) ORDER BY archived, code LIMIT 1;
            END IF;
        END IF;
        IF v_prog_code IS NULL AND v_prog ~ '^C[0-9]{5}$' THEN
            -- the faculty, department and award to build the missing programme from
            v_fac  := upper(nullif(btrim(coalesce(r->>'faculty', split_part(v_matric, '/', 2))), ''));
            v_dept := upper(nullif(btrim(coalesce(r->>'department', split_part(v_matric, '/', 3))), ''));
            v_award := upper(nullif(btrim(split_part(v_matric, '/', 4)), ''));
            SELECT name INTO v_dname FROM ref.department WHERE upper(code) = v_dept;
            IF v_dept IS NOT NULL AND v_fac IS NOT NULL
               AND EXISTS (SELECT 1 FROM ref.department WHERE upper(code) = v_dept)
               AND EXISTS (SELECT 1 FROM ref.faculty WHERE upper(code) = v_fac) THEN
                INSERT INTO ref.programme (code, name, dept_code, faculty_code, min_score, archived, category, pg_research)
                VALUES (upper(v_prog), btrim(coalesce(v_award || ' ', '') || coalesce(v_dname, v_dept)),
                        (SELECT code FROM ref.department WHERE upper(code) = v_dept),
                        (SELECT code FROM ref.faculty WHERE upper(code) = v_fac),
                        0, false, 'POST GRADUATE', false)
                ON CONFLICT (code) DO NOTHING;
                v_prog_code := upper(v_prog);
            END IF;
        END IF;
        IF v_prog_code IS NULL THEN nnp := nnp + 1; CONTINUE; END IF;

        l_contact := 0; l_bio := 0; l_acct := 0;
        BEGIN
            v_surname := nullif(btrim(coalesce(r->>'surname', '')), '');
            v_others  := nullif(btrim(coalesce(r->>'otherNames', r->>'other_names', r->>'othernames', '')), '');
            IF v_surname IS NULL THEN
                DECLARE nm text := btrim(coalesce(r->>'name', r->>'fullName', ''));
                BEGIN
                    IF position(',' IN nm) > 0 THEN
                        v_surname := btrim(split_part(nm, ',', 1));
                        v_others  := btrim(substr(nm, position(',' IN nm) + 1));
                    ELSE
                        v_surname := split_part(nm, ' ', 1);
                        v_others  := nullif(btrim(substr(nm, length(split_part(nm, ' ', 1)) + 1)), '');
                    END IF;
                END;
            END IF;
            IF v_surname IS NULL OR v_surname = '' THEN v_surname := 'UNKNOWN'; END IF;
            v_others := coalesce(v_others, '');

            v_sex := upper(left(btrim(coalesce(r->>'sex', r->>'gender', '')), 1));
            IF v_sex NOT IN ('F', 'M') THEN v_sex := NULL; END IF;

            BEGIN v_dob := (r->>'dob')::date;
            EXCEPTION WHEN OTHERS THEN
                BEGIN v_dob := (r->>'dateOfBirth')::date; EXCEPTION WHEN OTHERS THEN v_dob := NULL; END;
            END;

            v_state := nullif(btrim(coalesce(r->>'state', r->>'stateOfOrigin', r->>'state_of_origin', '')), '');
            v_jamb := nullif(upper(btrim(coalesce(r->>'jamb', r->>'jambNo', r->>'jamb_no', r->>'jambRegNo', r->>'jamb_reg_no', ''))), '');

            -- this is the postgraduate importer: the entry mode is POSTGRADUATE, and the school defaults to S002
            v_school := upper(nullif(btrim(coalesce(r->>'schoolId', r->>'school_id', r->>'schoolid', '')), ''));
            IF v_school IS NULL THEN v_school := 'S002'; END IF;

            -- entry session from the file, else from the YY before the serial at the end of the matric
            v_es := nullif(btrim(coalesce(r->>'entrySession', r->>'entry_session', r->>'yoe', '')), '');
            IF v_es IS NULL OR v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN
                v_yy := substring(v_matric from '/([0-9]{2})/[0-9]{2,7}$');
                IF v_yy IS NOT NULL THEN
                    v_es := '20' || v_yy || '/20' || lpad((v_yy::int + 1)::text, 2, '0');
                ELSE
                    v_es := '2024/2025';
                END IF;
            END IF;
            IF v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN v_es := '2024/2025'; END IF;

            -- V459: the postgraduate levels (people.upload_levels, V455): the file's 700/800/900, else its entry level, else the
            -- programme's (a PhD 900, a postgraduate diploma 700, a Master's 800) — no longer a flat 800 for a row with no level
            SELECT u.entry_level, u.current_level, u.level_stated INTO v_el, v_cl, v_stated
              FROM people.upload_levels(v_prog_code, 'POSTGRADUATE', coalesce(r->>'entryLevel', r->>'entry_level', ''),
                                        coalesce(r->>'level', r->>'currentLevel', r->>'current_level', '')) u;

            SELECT true INTO v_exists FROM people.student WHERE upper(matric_no) = v_matric;
            INSERT INTO people.student (id, matric_no, surname, other_names, sex, date_of_birth, state_of_origin,
                                        jamb_reg_no, programme_code, entry_mode, entry_session, entry_level, current_level,
                                        status, matriculated_at, school_id)
            VALUES (gen_random_uuid(), v_matric, v_surname, v_others, v_sex, v_dob, v_state, v_jamb, v_prog_code, 'POSTGRADUATE',
                    v_es, v_el, v_cl, 'ACTIVE', now(), v_school)
            ON CONFLICT (matric_no) DO UPDATE SET
                surname = EXCLUDED.surname, other_names = EXCLUDED.other_names,
                sex = coalesce(EXCLUDED.sex, people.student.sex),
                date_of_birth = coalesce(EXCLUDED.date_of_birth, people.student.date_of_birth),
                state_of_origin = coalesce(EXCLUDED.state_of_origin, people.student.state_of_origin),
                jamb_reg_no = coalesce(EXCLUDED.jamb_reg_no, people.student.jamb_reg_no),
                programme_code = EXCLUDED.programme_code,
                -- V459: the level changes only when the file states one; a student re-filed postgraduate takes the row's levels
                current_level = people.upload_kept_level(people.student.entry_mode, people.student.current_level, 'POSTGRADUATE', EXCLUDED.current_level, v_stated),
                entry_level = CASE WHEN people.student.entry_mode IS DISTINCT FROM 'POSTGRADUATE' AND coalesce(people.student.entry_level, 0) < 700
                                   THEN EXCLUDED.entry_level ELSE people.student.entry_level END,
                entry_mode = 'POSTGRADUATE', school_id = coalesce(EXCLUDED.school_id, people.student.school_id)
            WHERE (people.student.surname, people.student.other_names, people.student.sex, people.student.date_of_birth,
                   people.student.state_of_origin, people.student.jamb_reg_no, people.student.programme_code, people.student.current_level,
                   people.student.entry_mode, people.student.school_id)
                  IS DISTINCT FROM (EXCLUDED.surname, EXCLUDED.other_names, coalesce(EXCLUDED.sex, people.student.sex),
                   coalesce(EXCLUDED.date_of_birth, people.student.date_of_birth), coalesce(EXCLUDED.state_of_origin, people.student.state_of_origin),
                   coalesce(EXCLUDED.jamb_reg_no, people.student.jamb_reg_no), EXCLUDED.programme_code,
                   people.upload_kept_level(people.student.entry_mode, people.student.current_level, 'POSTGRADUATE', EXCLUDED.current_level, v_stated),
                   'POSTGRADUATE', coalesce(EXCLUDED.school_id, people.student.school_id));
            SELECT id INTO v_student FROM people.student WHERE upper(matric_no) = v_matric;

            v_phone := regexp_replace(coalesce(r->>'phone', r->>'mobile', ''), '[^0-9]', '', 'g');
            IF length(v_phone) = 10 THEN v_phone := '0' || v_phone;
            ELSIF length(v_phone) = 13 AND left(v_phone, 3) = '234' THEN v_phone := '0' || right(v_phone, 10);
            END IF;
            IF v_phone !~ '^0[0-9]{10}$' THEN v_phone := NULL; END IF;

            v_email := lower(nullif(btrim(coalesce(r->>'email', r->>'loginemail', r->>'login_email', '')), ''));
            IF v_email IS NOT NULL AND v_email !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN v_email := NULL; END IF;

            v_addr := nullif(btrim(coalesce(r->>'address', '')), '');

            IF v_phone IS NOT NULL OR v_email IS NOT NULL OR v_addr IS NOT NULL THEN
                INSERT INTO people.student_contact (student_id, phone, email, address)
                VALUES (v_student, v_phone, v_email, v_addr)
                ON CONFLICT (student_id) DO UPDATE SET
                    phone = coalesce(EXCLUDED.phone, people.student_contact.phone),
                    email = coalesce(EXCLUDED.email, people.student_contact.email),
                    address = coalesce(EXCLUDED.address, people.student_contact.address),
                    updated_at = now()
                WHERE (people.student_contact.phone, people.student_contact.email, people.student_contact.address)
                      IS DISTINCT FROM (coalesce(EXCLUDED.phone, people.student_contact.phone),
                                        coalesce(EXCLUDED.email, people.student_contact.email),
                                        coalesce(EXCLUDED.address, people.student_contact.address));
                l_contact := 1;
            END IF;

            FOR bf, bv IN
                SELECT key, value FROM jsonb_each_text(jsonb_strip_nulls(jsonb_build_object(
                    'nationality',      nullif(btrim(coalesce(r->>'nationality', '')), ''),
                    'state_of_origin',  v_state,
                    'lga',              nullif(btrim(coalesce(r->>'lga', '')), ''),
                    'guardian_name',    nullif(btrim(coalesce(r->>'guardianName', r->>'guardianname', '')), ''),
                    'guardian_address', nullif(btrim(coalesce(r->>'guardianAddress', r->>'guardianaddress', '')), ''),
                    'sponsor_name',     nullif(btrim(coalesce(r->>'sponsorName', r->>'sponsorname', '')), ''),
                    'sponsor_address',  nullif(btrim(coalesce(r->>'sponsorAddress', r->>'sponsoraddress', '')), ''),
                    'kin_name',         nullif(btrim(coalesce(r->>'nokName', r->>'nokname', r->>'kinName', '')), ''),
                    'kin_address',      nullif(btrim(coalesce(r->>'nokAddress', r->>'nokaddress', r->>'kinAddress', '')), ''),
                    'extracurricular',  nullif(btrim(coalesce(r->>'extracurricular', '')), ''),
                    'legacy_appno',     nullif(btrim(coalesce(r->>'appno', r->>'applicationNo', '')), '')
                )))
            LOOP
                INSERT INTO people.biodata (student_id, field, value) VALUES (v_student, bf, bv)
                ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value
                WHERE people.biodata.value IS DISTINCT FROM EXCLUDED.value;
                l_bio := l_bio + 1;
            END LOOP;

            IF NOT EXISTS (SELECT 1 FROM iam.student_account WHERE student_id = v_student) THEN
                -- sealed: a cost-12 hash of a random secret nobody holds, made once for the upload rather than once a
                -- row; the student's first sign-in is their own number (must_change), never this
                IF v_sealed IS NULL THEN v_sealed := crypt(gen_random_uuid()::text, gen_salt('bf', 12)); END IF;
                INSERT INTO iam.student_account (id, student_id, password_hash, must_change)
                VALUES (gen_random_uuid(), v_student, v_sealed, true);
                l_acct := 1;
            END IF;

            IF coalesce(v_exists, false) THEN nu := nu + 1; ELSE nc := nc + 1; END IF;
            ncontact := ncontact + l_contact;
            nbio := nbio + l_bio;
            nacct := nacct + l_acct;
        EXCEPTION WHEN OTHERS THEN
            nerr := nerr + 1;
            IF v_firsterr IS NULL THEN
                v_firsterr := left(v_matric || ': ' || SQLSTATE || ' ' || SQLERRM, 300);
            END IF;
        END;
    END LOOP;

    IF v_mine THEN PERFORM people.refresh_deferred_positions(); END IF;
    RETURN QUERY SELECT n, nc, nu, nnp, nbn, ncontact, nbio, nacct, nerr, v_firsterr;
END $function$;

COMMIT;
