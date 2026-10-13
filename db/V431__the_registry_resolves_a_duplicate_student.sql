-- ═══════════════════════════════════════
-- V431 — the Registry resolves a duplicate student (portal gap audit, GAP-002)
--
--   V429 listed the students who may be one person on the register twice and stopped intake making more. This lets the Registry
--   settle a pair: keep one record, end the other.
--
--   1. people.student.duplicate_of: the record an ended duplicate was the same student as. An ended duplicate is WITHDRAWN; it may be
--      so without a matriculation number (an admitted record never matriculated), which no other withdrawal may.
--   2. people.resolve_duplicate(keep, end, reason): refuses unless the two share the JAMB number, or every name, the programme and the
--      entry session; refuses when the record to end carries a matriculation number, a registration, a fee reference or a mark (the
--      history is moved first, a separate decision); moves the candidate link to the kept record; records the change of status with
--      the kept number as its instrument. Nothing is deleted, and the person is not told they were withdrawn: they are the kept record.
--   3. An ended duplicate is no longer listed as a possible duplicate, never taken by intake, and not flagged as a withdrawn record
--      missing its matriculation number in the cohort reconciliation.
-- ═══════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V431: the Registry resolves a duplicate student', true);

-- ── 1 · the record an ended duplicate was ──
ALTER TABLE people.student ADD COLUMN duplicate_of uuid REFERENCES people.student (id);
ALTER TABLE people.student ADD CONSTRAINT ck_student_duplicate_not_self CHECK (duplicate_of IS DISTINCT FROM id);
CREATE INDEX ix_student_duplicate_of ON people.student (duplicate_of) WHERE duplicate_of IS NOT NULL;
COMMENT ON COLUMN people.student.duplicate_of IS
  'V431: set when the Registry ended this record as the same student entered twice; the record kept. The ended record is WITHDRAWN and stays on the register.';

ALTER TABLE people.student DROP CONSTRAINT ck_student_active_has_matric;
ALTER TABLE people.student ADD CONSTRAINT ck_student_active_has_matric
    CHECK (status = 'ADMITTED' OR matric_no IS NOT NULL OR (status = 'WITHDRAWN' AND duplicate_of IS NOT NULL));

-- ── 2 · keep one, end the other ──
CREATE FUNCTION people.resolve_duplicate(p_keep uuid, p_end uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql AS $fn$
DECLARE k people.student; e people.student; v_regs bigint; v_pays bigint; v_marks bigint; v_moved boolean := false;
BEGIN
    IF p_keep IS NULL OR p_end IS NULL OR p_keep = p_end THEN
        RAISE EXCEPTION 'DUPLICATE_SAME_RECORD: choose the record to keep and a different record to end' USING ERRCODE = '23514';
    END IF;
    IF p_reason IS NULL OR length(btrim(p_reason)) < 10 THEN
        RAISE EXCEPTION 'DUPLICATE_REASON_REQUIRED: say why the two records are one student, in at least ten characters' USING ERRCODE = '23514';
    END IF;
    -- both rows locked, in one order, so two decisions on one pair wait for each other
    PERFORM 1 FROM people.student WHERE id IN (p_keep, p_end) ORDER BY id FOR UPDATE;
    SELECT * INTO k FROM people.student WHERE id = p_keep;
    SELECT * INTO e FROM people.student WHERE id = p_end;
    IF k.id IS NULL OR e.id IS NULL THEN
        RAISE EXCEPTION 'DUPLICATE_NOT_FOUND: one of the two records is not on the register' USING ERRCODE = '23514';
    END IF;
    IF k.duplicate_of IS NOT NULL OR e.duplicate_of IS NOT NULL THEN
        RAISE EXCEPTION 'DUPLICATE_ALREADY_ENDED: % was already ended as a duplicate', coalesce(CASE WHEN k.duplicate_of IS NOT NULL THEN k.admission_no END, e.admission_no)
            USING ERRCODE = '23514';
    END IF;
    IF NOT ((k.jamb_reg_no IS NOT NULL AND e.jamb_reg_no IS NOT NULL AND upper(btrim(k.jamb_reg_no)) = upper(btrim(e.jamb_reg_no)))
            OR (upper(k.surname) = upper(e.surname) AND upper(k.other_names) = upper(e.other_names)
                AND k.programme_code = e.programme_code AND k.entry_session = e.entry_session)) THEN
        RAISE EXCEPTION 'DUPLICATE_NOT_A_PAIR: % and % share neither the JAMB number nor every name, the programme and the entry session',
            coalesce(k.matric_no, k.admission_no), coalesce(e.matric_no, e.admission_no) USING ERRCODE = '23514';
    END IF;
    IF e.matric_no IS NOT NULL THEN
        RAISE EXCEPTION 'DUPLICATE_END_MATRICULATED: % carries the matriculation number %; the matriculated record is the one to keep', e.admission_no, e.matric_no
            USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO v_regs FROM registration.course_registration r WHERE r.student_id = e.id;
    SELECT count(*) INTO v_pays FROM finance.payment_reference p WHERE p.student_id = e.id;
    SELECT count(*) INTO v_marks FROM assessment.score sc WHERE sc.student_id = e.id;
    IF v_regs + v_pays + v_marks > 0 THEN
        RAISE EXCEPTION 'DUPLICATE_HAS_HISTORY: % carries % registrations, % fee references and % marks; only a record with nothing on it is ended here, and moving a history is a decision of its own',
            e.admission_no, v_regs, v_pays, v_marks USING ERRCODE = '23514';
    END IF;
    -- the candidate stands behind the student who is kept
    IF e.candidate_id IS NOT NULL AND k.candidate_id IS NULL THEN
        UPDATE people.student SET candidate_id = NULL WHERE id = e.id;
        UPDATE people.student SET candidate_id = e.candidate_id WHERE id = k.id;
        v_moved := true;
    END IF;
    -- the change of status is recorded as every change is, on its instrument; no notice goes out — the person is the kept record
    INSERT INTO people.status_change (id, student_id, from_status, to_status, instrument, effective_on, reason)
    VALUES (gen_random_uuid(), e.id, e.status, 'WITHDRAWN', 'Registry: the same student entered twice; the record kept is ' || coalesce(k.matric_no, k.admission_no),
            current_date, btrim(p_reason));
    UPDATE people.student SET status = 'WITHDRAWN', duplicate_of = k.id WHERE id = e.id;
    RETURN jsonb_build_object('kept', k.id, 'keptNumber', coalesce(k.matric_no, k.admission_no), 'ended', e.id, 'endedNumber', e.admission_no,
                              'candidateMoved', v_moved);
END $fn$;
COMMENT ON FUNCTION people.resolve_duplicate(uuid, uuid, text) IS
  'V431: the Registry keeps one record of a duplicate pair and ends the other (WITHDRAWN, duplicate_of = the kept record). Only a record with no matriculation number, registration, fee reference or mark is ended; the candidate link moves to the kept record. Nothing is deleted.';

-- ── 3 · an ended duplicate is no longer a possible one ──
CREATE OR REPLACE FUNCTION people.duplicate_students()
RETURNS TABLE(kind text, match_key text, student_id uuid, number text, name text, programme_code text, entry_session text, status text,
              jamb_reg_no text, linked_candidate boolean, registrations bigint, payments bigint, marks bigint)
LANGUAGE sql STABLE AS $fn$
    WITH live AS (SELECT * FROM people.student WHERE duplicate_of IS NULL),
    by_jamb AS (
        SELECT 'SAME_JAMB'::text AS kind, upper(s.jamb_reg_no) AS match_key, s.id FROM live s
         WHERE s.jamb_reg_no IS NOT NULL AND upper(s.jamb_reg_no) IN (SELECT upper(x.jamb_reg_no) FROM live x WHERE x.jamb_reg_no IS NOT NULL
                                                                        GROUP BY 1 HAVING count(*) > 1)),
    by_name AS (
        SELECT 'SAME_NAME'::text, upper(s.surname) || ', ' || upper(s.other_names) || ' · ' || s.programme_code || ' · ' || s.entry_session, s.id
          FROM live s
         WHERE (upper(s.surname), upper(s.other_names), s.programme_code, s.entry_session) IN
               (SELECT upper(x.surname), upper(x.other_names), x.programme_code, x.entry_session FROM live x
                 GROUP BY 1, 2, 3, 4 HAVING count(*) > 1)
           AND s.id NOT IN (SELECT id FROM by_jamb)),
    found AS (SELECT * FROM by_jamb UNION ALL SELECT * FROM by_name)
    SELECT f.kind, f.match_key, s.id, coalesce(s.matric_no, s.admission_no), upper(s.surname) || ', ' || s.other_names, s.programme_code,
           s.entry_session, s.status, s.jamb_reg_no, s.candidate_id IS NOT NULL,
           (SELECT count(*) FROM registration.course_registration r WHERE r.student_id = s.id),
           (SELECT count(*) FROM finance.payment_reference p WHERE p.student_id = s.id),
           (SELECT count(*) FROM assessment.score sc WHERE sc.student_id = s.id)
      FROM found f JOIN people.student s ON s.id = f.id
     ORDER BY f.kind, f.match_key, coalesce(s.matric_no, s.admission_no)
$fn$;

-- ── 4 · intake never takes an ended duplicate (restated from V429) ──
CREATE OR REPLACE FUNCTION people.intake_one(p_candidate uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE c admissions.candidate; v_id uuid; v_code text; v_yy text; l admissions.cce_candidate; v_prev uuid; v_prev_prog text; v_busy boolean;
BEGIN
    SELECT * INTO c FROM admissions.candidate WHERE id = p_candidate;
    IF c.id IS NULL THEN RAISE EXCEPTION 'no such candidate' USING ERRCODE = '23503'; END IF;
    SELECT id INTO v_id FROM people.student WHERE candidate_id = c.id;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;
    IF c.offer_state NOT IN ('ADMITTED', 'ACCEPTED') THEN
        RAISE EXCEPTION 'only an admitted candidate is brought onto the register; % is %', c.jamb_reg_no, lower(coalesce(c.offer_state, 'not admitted')) USING ERRCODE = '23514';
    END IF;
    -- candidate.programme is the programme NAME; resolve it to a code, accepting a value that is already a code
    v_code := (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1);
    IF v_code IS NULL THEN
        IF EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = c.programme) THEN
            v_code := c.programme;
        ELSE
            RAISE EXCEPTION 'the programme "%" for candidate % is not one the University runs; it cannot be brought onto the register',
                c.programme, c.jamb_reg_no USING ERRCODE = '23503',
                HINT = 'Set the programme''s University name to match ref.programme, or correct the candidate''s programme.';
        END IF;
    END IF;
    -- V429: a student already on the register under the candidate's JAMB number for the same entry session, never linked to a candidate
    -- (taken on by an earlier list or by hand), IS the candidate: linked, never made a second time. Untouched yet (no registration,
    -- payment or mark), it takes the programme the admission names; with a history on another programme the Registry decides.
    SELECT s.id, s.programme_code INTO v_prev, v_prev_prog FROM people.student s
     WHERE s.candidate_id IS NULL AND s.duplicate_of IS NULL AND s.jamb_reg_no IS NOT NULL AND upper(s.jamb_reg_no) = upper(c.jamb_reg_no) AND s.entry_session = c.session
     ORDER BY s.admission_no NULLS LAST LIMIT 1;
    IF v_prev IS NOT NULL THEN
        IF v_prev_prog IS DISTINCT FROM v_code THEN
            v_busy := EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = v_prev)
                   OR EXISTS (SELECT 1 FROM finance.payment_reference p WHERE p.student_id = v_prev)
                   OR EXISTS (SELECT 1 FROM assessment.score sc WHERE sc.student_id = v_prev);
            IF v_busy THEN
                RAISE EXCEPTION 'INTAKE_DUPLICATE_JAMB: % is already on the register for % on another programme, with registrations, payments or marks; the Registry reconciles the two before the candidate is taken on', c.jamb_reg_no, c.session
                    USING ERRCODE = '23514';
            END IF;
            UPDATE people.student SET programme_code = v_code WHERE id = v_prev;
        END IF;
        UPDATE people.student SET candidate_id = c.id WHERE id = v_prev;
        RETURN v_prev;
    END IF;
    v_yy := substr(c.session, 3, 2);
    -- V379: a CCE candidate comes onto the register CCE and part-time, in the CCE session admitted for, with what the list gave
    SELECT * INTO l FROM admissions.cce_candidate WHERE id = c.cce_candidate_id;
    INSERT INTO people.student (id, candidate_id, admission_no, jamb_reg_no, surname, other_names,
                                programme_code, entry_mode, entry_session, entry_level, current_level, study_mode, date_of_birth, sex, state_of_origin)
    VALUES (gen_random_uuid(), c.id,
            'MOAUM/ADM/' || v_yy || '/' || lpad(platform.next_number('ADMISSION', 'UNIVERSITY', c.session)::text, 6, '0'),
            c.jamb_reg_no, c.surname, c.other_names, v_code,
            CASE WHEN c.entry_mode IN ('UTME', 'DIRECT_ENTRY', 'CCE') THEN c.entry_mode ELSE 'UTME' END,
            c.session, c.entry_level, c.entry_level,
            CASE WHEN c.entry_mode = 'CCE' THEN coalesce((SELECT r.study_mode FROM policy.study_route r WHERE r.code = 'CCE'), 'PART_TIME') ELSE 'FULL_TIME' END,
            l.date_of_birth, l.sex, l.state_of_origin)
    RETURNING id INTO v_id;
    IF c.entry_mode = 'CCE' THEN
        INSERT INTO people.biodata (student_id, field, value)
        SELECT v_id, x.field, x.value FROM admissions.screening_answer x JOIN admissions.application a ON a.id = x.application_id
         WHERE a.candidate_id = c.id AND btrim(x.value) <> ''
        ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value;
    END IF;
    -- the nationality JAMB's state implies, on the record from the first day (V282)
    PERFORM people.default_nationality(v_id);
    RETURN v_id;
END $function$;

-- ── 5 · the cohort reconciliation does not flag an ended duplicate as a withdrawal missing its matriculation number (restated from V381) ──
CREATE OR REPLACE FUNCTION people.academic_position_rows(p_student uuid DEFAULT NULL::uuid)
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
               bool_or(r.session = (SELECT name FROM cce) AND r.status IN ('SUBMITTED','APPROVED','LOCKED')) AS cce_reg,
               max(r.session) FILTER (WHERE r.status IN ('SUBMITTED','APPROVED','LOCKED')) AS last_reg
          FROM registration.course_registration r LEFT JOIN cur ON true
         WHERE p_student IS NULL OR r.student_id = p_student
         GROUP BY r.student_id),
    enr AS (
        SELECT e.student_id, bool_or(e.session = cur.name) AS cur_enr, bool_or(e.session = (SELECT name FROM cce)) AS cce_enr, max(e.session) AS last_enr
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

COMMIT;
