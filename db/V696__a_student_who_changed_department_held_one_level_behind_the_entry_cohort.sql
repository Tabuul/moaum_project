-- ═══════════════════════════════════════
-- V696 — a student who changed department held one level behind their entry cohort
--
-- The University's word of 29 October 2026, on the 2025/2026 school-fees receipt of a student who entered Accounting in 2023/2024
-- (matric …/ACC/23/…) and is now in B.Ed Guidance and Counselling, which read 300 Level: "student who change from one department to
-- another, usually step down 1 level behind the actual level they were admitted so any student that change from one department to
-- another should not be a level ahead of the current level they were stepped down to, do this for all the affected students".
--
-- Her record reads 200 Level; the receipt read 300. people.receipt_level (V672) prints the greater of the record and the session's
-- registration, enrolment or the count of sessions from entry — and with no 2025/2026 registration or enrolment, the count from
-- 2023/2024 gave 300. people.level_in falls back on the same count. Nothing on the portal knew she had changed department: the old
-- portal's transfers kept the old matric and were never migrated as transfers (V669).
--
-- On the live-shaped copy of 28 October 2026, 624 active undergraduates who entered before 2025/2026 have a matric naming another
-- department than their programme's; 405 of them have a level above one behind their entry cohort somewhere — 84 records (none in a
-- spillover year), 277 enrolments and 8 registrations of 2025/2026 (most made by the old-portal load of 14–16 September 2026), and
-- 323 receipts.
--
-- What changes:
--   · people.department_changed(student): the student's matric names a department (the third part of BSU/MS/ACC/23/…: a programme's
--     matric code or a department's code) and their programme is in none of them; or a transfer to their programme from another
--     department is recorded (a completed ACADEMIC_TRANSFER or APPROVED_TRANSFER_RESTORED swap, an old-portal transfer, an effected
--     transfer application). A matric that names no department is no evidence either way.
--   · people.hold_department_change(student, reason, batch): such a student (active or on probation, undergraduate, not CCE, entered
--     before the current session) is given an effective cohort one session after their entry (people.cohort_override, as the cohort
--     desk sets one, with a decision COHORT_DEPARTMENT_CHANGE) — the academic position then counts their expected level, completion
--     and spillover from it, and the level desk proposes nothing above it. The record above the level that cohort reaches in the
--     current session is lowered to it (a decision LEVEL_DEPARTMENT_CHANGE) and the current session's registrations and enrolment
--     above it with it (people.carry_level_to_session, V641). A student whose cohort is already set, or whose hold the Registry has
--     since taken off, is left as they are.
--   · people.hold_department_changes(reason, batch): every such student at once (the Academic Office, the Registry, super); run once
--     here as V696-DEPARTMENT-CHANGE, safe to run again.
--   · A transfer to another department (people.effect_transfer, approve_transfer, decide_programme_swap) holds the student the same
--     way as it is made (trigger trg_student_department_change), and so does an old-portal transfer recorded for a student already on
--     the programme (trg_prior_transfer_department_change); a correction that puts a student back into the department their matric
--     names does not. The transfer itself still reports the level it was made at (V686's MOVED/200); the hold follows it.
--   · people.cohort_cap(student, session): the level a set effective cohort reaches, in the current session and after; NULL without
--     one or for an earlier session (what a student registered before stands). people.receipt_level and people.level_in never read
--     above it.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V696: a student who changed department held one level behind their entry cohort', true);

-- ── whether a student changed department ──
CREATE OR REPLACE FUNCTION people.department_changed(p_student uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    WITH s AS (
        SELECT st.id, st.programme_code, p.dept_code,
               CASE WHEN st.matric_no ~ '^[A-Z]+/[A-Z]+/[A-Z]+/[0-9]{2}/' THEN split_part(st.matric_no, '/', 3) END AS seg
          FROM people.student st JOIN ref.programme p ON p.code = st.programme_code
         WHERE st.id = p_student),
    named AS (
        SELECT x.dept_code FROM s JOIN ref.programme x ON x.matric_code = s.seg
        UNION SELECT d.code FROM s JOIN ref.department d ON d.code = s.seg)
    SELECT coalesce((SELECT (EXISTS (SELECT 1 FROM named) AND NOT EXISTS (SELECT 1 FROM named WHERE named.dept_code = s.dept_code))
                         OR EXISTS (SELECT 1 FROM people.programme_swap w
                                     WHERE w.student_id = s.id AND w.status = 'COMPLETED' AND w.kind IN ('ACADEMIC_TRANSFER', 'APPROVED_TRANSFER_RESTORED')
                                       AND w.to_programme = s.programme_code AND w.from_dept IS DISTINCT FROM w.to_dept)
                         OR EXISTS (SELECT 1 FROM people.prior_transfer t JOIN ref.programme f ON f.code = t.from_programme
                                     WHERE t.student_id = s.id AND t.to_programme = s.programme_code AND f.dept_code <> s.dept_code)
                         OR EXISTS (SELECT 1 FROM people.transfer_application a JOIN ref.programme f ON f.code = a.from_programme_code
                                     WHERE a.student_id = s.id AND a.state = 'EFFECTED' AND a.to_programme_code = s.programme_code AND f.dept_code <> s.dept_code)
                       FROM s), false)
$$;
COMMENT ON FUNCTION people.department_changed(uuid) IS
  'V696: whether a student changed department — their matric names a department (a programme''s matric code or a department''s code) and their programme is in none of them, or a transfer to their programme from another department is recorded. A matric naming no department is no evidence.';

-- ── the level a set effective cohort reaches in a session ──
CREATE OR REPLACE FUNCTION people.cohort_cap(p_student uuid, p_session text)
RETURNS integer LANGUAGE sql STABLE AS $$
    SELECT least(600, greatest(st.entry_level, st.entry_level + 100 * (left(p_session, 4)::int - left(o.effective_cohort, 4)::int)))
      FROM people.cohort_override o
      JOIN people.student st ON st.id = o.student_id
      LEFT JOIN ref.programme p ON p.code = st.programme_code
     WHERE o.student_id = p_student
       AND p_session ~ '^[0-9]{4}/[0-9]{4}$' AND o.effective_cohort ~ '^[0-9]{4}/[0-9]{4}$' AND st.entry_level IS NOT NULL
       AND NOT people.is_postgraduate(st.entry_mode, p.category) AND st.entry_mode IS DISTINCT FROM 'CCE'
       AND left(p_session, 4)::int >= coalesce(left(coalesce(people.student_current_session(st.id), policy.university_current_session()), 4)::int, 0)
$$;
COMMENT ON FUNCTION people.cohort_cap(uuid, text) IS
  'V696: the level a student''s set effective cohort (people.cohort_override) reaches in a session — their entry level and a level for each session since that cohort — in the current session and after; NULL without one, for a postgraduate or CCE student, or for an earlier session.';

-- ── a receipt never reads above it (V672's rule otherwise as it was) ──
CREATE OR REPLACE FUNCTION people.receipt_level(p_student uuid, p_session text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE WHEN c.cap IS NULL THEN x.lvl ELSE least(c.cap, x.lvl) END
      FROM (SELECT greatest(
                people.record_level_in(p_student, p_session),
                coalesce(
                    (SELECT r.level FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = p_session
                      ORDER BY (r.status IN ('APPROVED', 'LOCKED')) DESC, r.semester LIMIT 1),
                    (SELECT e.level FROM people.enrolment e WHERE e.student_id = p_student AND e.session = p_session LIMIT 1),
                    (SELECT CASE WHEN p_session ~ '^[0-9]{4}/[0-9]{4}$' AND NOT people.is_postgraduate(st.entry_mode, p.category)   -- V455: a postgraduate's level is their own
                                 THEN least(600, greatest(100, st.entry_level + (left(p_session, 4)::int - left(st.entry_session, 4)::int) * 100))
                                 ELSE st.current_level END
                       FROM people.student st LEFT JOIN ref.programme p ON p.code = st.programme_code WHERE st.id = p_student))) AS lvl) x
      CROSS JOIN LATERAL (SELECT people.cohort_cap(p_student, p_session) AS cap) c
$function$;

-- ── nor the level a student is at in a session (V455's rule otherwise as it was) ──
CREATE OR REPLACE FUNCTION people.level_in(p_student uuid, p_session text, p_semester integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE WHEN c.cap IS NULL THEN x.lvl ELSE least(c.cap, x.lvl) END
      FROM (SELECT coalesce(
                (SELECT r.level FROM registration.course_registration r
                  WHERE r.student_id = p_student AND r.session = p_session AND (p_semester IS NULL OR r.semester = p_semester)
                  ORDER BY (r.status IN ('APPROVED','LOCKED')) DESC, r.semester LIMIT 1),
                (SELECT r.level FROM registration.course_registration r
                  WHERE r.student_id = p_student AND r.session = p_session
                  ORDER BY (r.status IN ('APPROVED','LOCKED')) DESC, r.semester LIMIT 1),
                (SELECT e.level FROM people.enrolment e WHERE e.student_id = p_student AND e.session = p_session),
                (SELECT CASE WHEN people.is_postgraduate(st.entry_mode, pp.category) THEN st.current_level   -- V455: a postgraduate's level is their own
                             WHEN es.starts_on IS NOT NULL AND cs.starts_on IS NOT NULL AND cs.starts_on >= es.starts_on
                             THEN least(600, st.entry_level + 100 * (SELECT count(*)::int FROM policy.academic_session a WHERE a.starts_on > es.starts_on AND a.starts_on <= cs.starts_on))
                        END
                   FROM people.student st
                   LEFT JOIN ref.programme pp ON pp.code = st.programme_code
                   LEFT JOIN policy.academic_session es ON es.name = st.entry_session
                   LEFT JOIN policy.academic_session cs ON cs.name = p_session
                  WHERE st.id = p_student),
                (SELECT st.current_level FROM people.student st WHERE st.id = p_student)) AS lvl) x
      CROSS JOIN LATERAL (SELECT people.cohort_cap(p_student, p_session) AS cap) c
$function$;

-- ── one student held ──
CREATE OR REPLACE FUNCTION people.hold_department_change(p_student uuid, p_reason text, p_batch text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE s people.student; v_pg boolean; v_cur text; v_cohort text; v_cap int; v_lowered boolean := false; r record;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_reason text := coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Changed department: held one level behind the entry cohort (V696)');
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RETURN 'NOT_FOUND'; END IF;
    SELECT people.is_postgraduate(s.entry_mode, p.category) INTO v_pg FROM ref.programme p WHERE p.code = s.programme_code;
    IF coalesce(v_pg, true) OR s.entry_mode = 'CCE' THEN RETURN 'NOT_UNDERGRADUATE'; END IF;
    IF s.status NOT IN ('ACTIVE', 'PROBATION') OR s.duplicate_of IS NOT NULL THEN RETURN 'NOT_ACTIVE'; END IF;
    IF NOT people.department_changed(p_student) THEN RETURN 'NOT_CHANGED'; END IF;
    IF EXISTS (SELECT 1 FROM people.cohort_override o WHERE o.student_id = p_student) THEN RETURN 'COHORT_SET'; END IF;
    -- a hold the Registry has since taken off (the cohort desk's removal) is not put back
    IF EXISTS (SELECT 1 FROM people.cohort_decision d WHERE d.student_id = p_student AND d.rule = 'COHORT_DEPARTMENT_CHANGE') THEN RETURN 'HELD_BEFORE'; END IF;
    v_cur := coalesce(people.student_current_session(s.id), policy.university_current_session());
    IF coalesce(s.entry_session, '') !~ '^[0-9]{4}/[0-9]{4}$' OR coalesce(v_cur, '') !~ '^[0-9]{4}/[0-9]{4}$'
       OR left(s.entry_session, 4)::int >= left(v_cur, 4)::int THEN
        RETURN 'ENTRY_SESSION';   -- a fresher, or no session to count from
    END IF;
    -- the session after the one they entered in, counted as the calendar counts it (2019/2020 was merged into 2020/2021, V661)
    v_cohort := policy.session_after(policy.effective_session(s.entry_session), 1);
    IF v_cohort IS NULL OR NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = v_cohort AND a.state <> 'CANCELLED') THEN
        RETURN 'NO_SESSION';
    END IF;

    INSERT INTO people.cohort_override (student_id, effective_cohort, reason, set_by, actor_office)
    VALUES (s.id, v_cohort, v_reason, v_actor, v_office);
    INSERT INTO people.cohort_decision (student_id, previous_status, final_status, previous_cohort, effective_cohort, rule, reason, officer, actor_office, batch_ref, session)
    VALUES (s.id, s.status, s.status, s.entry_session, v_cohort, 'COHORT_DEPARTMENT_CHANGE', v_reason, v_actor, v_office, p_batch, v_cur);

    v_cap := people.cohort_cap(s.id, v_cur);
    IF v_cap IS NOT NULL AND s.current_level > v_cap THEN
        INSERT INTO people.cohort_decision (student_id, previous_status, final_status, previous_cohort, effective_cohort, previous_level, new_level,
                                            rule, reason, officer, actor_office, batch_ref, session)
        VALUES (s.id, s.status, s.status, s.entry_session, v_cohort, s.current_level, v_cap,
                'LEVEL_DEPARTMENT_CHANGE', v_reason, v_actor, v_office, p_batch, v_cur);
        UPDATE people.student SET current_level = v_cap WHERE id = s.id;
        v_lowered := true;
    END IF;
    -- the current session's registrations and enrolment above it, with it
    IF v_cap IS NOT NULL THEN
        FOR r IN SELECT DISTINCT x.level FROM (
                     SELECT cr.level FROM registration.course_registration cr WHERE cr.student_id = s.id AND cr.session = v_cur AND cr.level > v_cap
                     UNION SELECT e.level FROM people.enrolment e WHERE e.student_id = s.id AND e.session = v_cur AND e.level > v_cap) x LOOP
            PERFORM people.carry_level_to_session(s.id, r.level, v_cap, v_cur);
            v_lowered := true;
        END LOOP;
    END IF;
    PERFORM people.refresh_academic_position(s.id);
    RETURN CASE WHEN v_lowered THEN 'LOWERED' ELSE 'HELD' END;
END $$;
COMMENT ON FUNCTION people.hold_department_change(uuid, text, text) IS
  'V696: a student who changed department (people.department_changed) given an effective cohort one session after their entry, and their record and the current session''s registrations and enrolment lowered to the level it reaches; NOT_CHANGED, COHORT_SET, HELD_BEFORE, ENTRY_SESSION, NO_SESSION, NOT_ACTIVE or NOT_UNDERGRADUATE leave them as they are. Returns HELD or LOWERED.';

-- ── every student at once ──
CREATE OR REPLACE FUNCTION people.hold_department_changes(p_reason text, p_batch text)
RETURNS TABLE (outcome text, students integer) LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); r record; v_out text; v_err text;
BEGIN
    IF coalesce(v_office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'LEVEL_CORRECTION_OFFICE: levels are corrected by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'LEVEL_CORRECTION_REASON: a level correction is recorded with its reason' USING ERRCODE = '23514';
    END IF;
    CREATE TEMP TABLE IF NOT EXISTS pg_temp.department_hold (outcome text) ON COMMIT DROP;
    TRUNCATE pg_temp.department_hold;
    FOR r IN SELECT st.id FROM people.student st
               JOIN ref.programme p ON p.code = st.programme_code
              WHERE st.status IN ('ACTIVE', 'PROBATION') AND st.duplicate_of IS NULL AND st.entry_mode IS DISTINCT FROM 'CCE'
                AND NOT people.is_postgraduate(st.entry_mode, p.category)
                AND NOT EXISTS (SELECT 1 FROM people.cohort_override o WHERE o.student_id = st.id)
                AND people.department_changed(st.id)
              ORDER BY st.id LOOP
        BEGIN
            v_out := people.hold_department_change(r.id, p_reason, p_batch);
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
            v_out := 'REFUSED';
            RAISE NOTICE 'V696: student % left as they are — %', r.id, v_err;
        END;
        INSERT INTO pg_temp.department_hold VALUES (v_out);
    END LOOP;
    RETURN QUERY SELECT h.outcome, count(*)::int FROM pg_temp.department_hold h GROUP BY h.outcome ORDER BY h.outcome;
END $$;
COMMENT ON FUNCTION people.hold_department_changes(text, text) IS
  'V696: every active undergraduate who changed department and has no effective cohort set, held one level behind their entry cohort (people.hold_department_change); the Academic Office, the Registry or super; counted by outcome. Safe to run again.';

-- ── a transfer to another department holds the student as it is made ──
CREATE OR REPLACE FUNCTION people.hold_on_department_change()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF (SELECT p.dept_code FROM ref.programme p WHERE p.code = OLD.programme_code)
       IS DISTINCT FROM (SELECT p.dept_code FROM ref.programme p WHERE p.code = NEW.programme_code) THEN
        PERFORM people.hold_department_change(NEW.id, 'Changed department: held one level behind the entry cohort (V696)', 'DEPARTMENT_CHANGE');
    END IF;
    RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS trg_student_department_change ON people.student;
CREATE TRIGGER trg_student_department_change AFTER UPDATE OF programme_code ON people.student
    FOR EACH ROW WHEN (OLD.programme_code IS DISTINCT FROM NEW.programme_code) EXECUTE FUNCTION people.hold_on_department_change();

-- ── and so does an old-portal transfer recorded for a student already on the programme (V669, V686: RECORDED) ──
CREATE OR REPLACE FUNCTION people.hold_on_prior_transfer()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM people.hold_department_change(NEW.student_id, 'Changed department on the old portal: held one level behind the entry cohort (V696)', 'DEPARTMENT_CHANGE');
    RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS trg_prior_transfer_department_change ON people.prior_transfer;
CREATE TRIGGER trg_prior_transfer_department_change AFTER INSERT ON people.prior_transfer
    FOR EACH ROW EXECUTE FUNCTION people.hold_on_prior_transfer();

-- ── the students who changed department so far ──
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT * FROM people.hold_department_changes(
                 'The University''s word of 29 October 2026: a student who changed department is held one level behind their entry cohort (V696)',
                 'V696-DEPARTMENT-CHANGE') LOOP
        RAISE NOTICE 'V696: % %', r.students, r.outcome;
    END LOOP;
END $$;

COMMIT;
