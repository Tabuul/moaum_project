-- ═══════════════════════════════════════
-- V495 — The minimum course registration load by curriculum (CCMAS, BMAS), set by the Directorate of ICT
--
--   The University requires a student under CCMAS to register at least 15 credit units in a semester, and one under BMAS at
--   least 18. Until now the floor was one figure per level (policy.level_limit, 18 at every undergraduate level), the same for
--   both curricula. The curriculum is already the student's own (people.student.curriculum_version, set from the curriculum
--   track, V116/V235); nothing is guessed from a course code or a programme list.
--
--   The minimum is a rule of the registration engine, kept the way the approval rule is (V491): a standing rule per curriculum
--   (the row with no session), and, where a session or a semester differs, that session's or semester's own row. The semester's
--   row wins, then the session's, then the standing rule. Nothing about a minimum lives in code: the figures are rows, changed
--   by the Directorate of ICT (and super) with a reason, each change logged with the value before and after
--   (registration.unit_minimum_change) and on the audit spine. A change reaches the next submission, add or drop; a registration
--   already made is never rewritten.
--
--     · registration.unit_minimum, registration.unit_minimum_rule(curriculum, session, semester) — the rule and its lookup;
--     · registration.unit_rule(student, level, session, semester) — the course load that binds the student: the Centre for
--       Continuing Education's course load where it stated one for a CCE student (V380), else the curriculum's minimum for an
--       undergraduate, else the level's; the maximum and the probation ceiling stay the level's (or the CCE load's) as before;
--     · registration.unit_limit(student, level, session, semester) — the same, in the shape every caller reads; the two-argument
--       form reads the student's current session, so a caller not yet naming the session still sees the curriculum's minimum;
--     · registration.submit_checks restated — the floor is the student's own for the registration's session and semester, and a
--       registration below it is refused with the curriculum, the minimum and the units it carries (REG_UNITS_BELOW_MINIMUM). The
--       automatic approval runs these very checks (V491), so it never approves a registration below the minimum;
--     · registration.support_drop_checks restated — the advisory reads the same floor;
--     · registration.set_unit_minimum(curriculum, session, semester, units, reason) — set or remove a rule: a whole number from 1,
--       no higher than the lowest undergraduate maximum, a reason of ten characters; the standing rule is changed, never removed;
--     · registration.unit_minimum_in_force(session, semester), registration.below_minimum(session, semester) — what the screens read.
--
--   The standing rules now: CCMAS 15, BMAS 18 (BMAS as before; CCMAS three units lower). Postgraduate students (who carry a
--   curriculum label from their entry session) keep their level's load; so does the SIWES semester's exact load on the student's
--   screen (unchanged).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V495: the minimum course registration load by curriculum (CCMAS 15, BMAS 18), set by the Directorate of ICT', true);

-- ── the rule ──
CREATE TABLE registration.unit_minimum (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    curriculum  text NOT NULL,
    session     text NULL REFERENCES policy.academic_session (name),
    semester    integer NULL CHECK (semester BETWEEN 1 AND 3),
    min_units   integer NOT NULL CHECK (min_units BETWEEN 1 AND 60),
    reason      text NOT NULL CHECK (length(btrim(reason)) >= 10),
    set_by      uuid NULL,
    set_office  text NULL REFERENCES ref.office (code),
    set_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_unit_minimum_curriculum CHECK (curriculum IN ('CCMAS', 'BMAS')),
    CONSTRAINT ck_unit_minimum_semester CHECK (semester IS NULL OR session IS NOT NULL),
    CONSTRAINT uq_unit_minimum UNIQUE NULLS NOT DISTINCT (curriculum, session, semester)
);
COMMENT ON TABLE registration.unit_minimum IS
  'V495: the least number of credit units a course registration carries, by curriculum (CCMAS, BMAS) — the standing rule (no session), and a session''s or a semester''s own where it differs; set by the Directorate of ICT with a reason';
SELECT audit.attach('registration.unit_minimum');

-- every change, with the value before and after (the audit spine keeps the rows too)
CREATE TABLE registration.unit_minimum_change (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event          text NOT NULL CHECK (event IN ('COURSE_REGISTRATION_MIN_CREDIT_SET', 'COURSE_REGISTRATION_MIN_CREDIT_CHANGED', 'COURSE_REGISTRATION_MIN_CREDIT_REMOVED')),
    curriculum     text NOT NULL,
    session        text NULL,
    semester       integer NULL,
    before_units   integer NULL,
    after_units    integer NULL,
    reason         text NULL,
    changed_by     uuid NULL,
    changed_office text NULL,
    changed_at     timestamptz NOT NULL DEFAULT clock_timestamp()   -- the moment of each change, in order within one transaction
);
CREATE INDEX ix_unit_minimum_change_at ON registration.unit_minimum_change (changed_at DESC);
COMMENT ON TABLE registration.unit_minimum_change IS
  'V495: each change of a minimum course registration load — set, changed or removed — with the curriculum, session, semester, the units before and after, the reason, who and which office';
SELECT audit.attach('registration.unit_minimum_change');

CREATE FUNCTION registration.unit_minimum_logged() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.min_units = OLD.min_units THEN RETURN NEW; END IF;   -- the same figure stated again is no change
    INSERT INTO registration.unit_minimum_change (event, curriculum, session, semester, before_units, after_units, reason, changed_by, changed_office)
    VALUES (CASE TG_OP WHEN 'INSERT' THEN 'COURSE_REGISTRATION_MIN_CREDIT_SET' WHEN 'UPDATE' THEN 'COURSE_REGISTRATION_MIN_CREDIT_CHANGED'
                       ELSE 'COURSE_REGISTRATION_MIN_CREDIT_REMOVED' END,
            CASE WHEN TG_OP = 'DELETE' THEN OLD.curriculum ELSE NEW.curriculum END,
            CASE WHEN TG_OP = 'DELETE' THEN OLD.session ELSE NEW.session END,
            CASE WHEN TG_OP = 'DELETE' THEN OLD.semester ELSE NEW.semester END,
            CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.min_units END,
            CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE NEW.min_units END,
            CASE WHEN TG_OP = 'DELETE' THEN nullif(current_setting('moaum.reason', true), '') ELSE NEW.reason END,
            nullif(current_setting('moaum.actor_id', true), '')::uuid,
            (SELECT o.code FROM ref.office o WHERE o.code = nullif(current_setting('moaum.actor_office', true), '')));
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER trg_unit_minimum_logged AFTER INSERT OR UPDATE OR DELETE ON registration.unit_minimum
    FOR EACH ROW EXECUTE FUNCTION registration.unit_minimum_logged();

CREATE FUNCTION registration.unit_minimum_rule(p_curriculum text, p_session text, p_semester integer)
RETURNS registration.unit_minimum LANGUAGE sql STABLE AS $$
    SELECT u.* FROM registration.unit_minimum u
     WHERE u.curriculum = p_curriculum
       AND ((u.session = p_session AND (u.semester = p_semester OR u.semester IS NULL)) OR u.session IS NULL)
     ORDER BY (u.session IS NULL), (u.semester IS NULL) LIMIT 1
$$;
COMMENT ON FUNCTION registration.unit_minimum_rule(text, text, integer) IS
  'V495: the minimum course load rule of a curriculum for a session and semester — the semester''s row, else the session''s, else the standing rule';

-- ── the course load that binds a student ──
CREATE FUNCTION registration.unit_rule(p_student uuid, p_level integer, p_session text, p_semester integer)
RETURNS TABLE(level integer, min_units integer, max_units integer, probation_max_units integer, carryover_counts boolean,
              curriculum text, basis text, level_min_units integer, rule_session text, rule_semester integer, instrument text)
LANGUAGE sql STABLE AS $$
    WITH st AS (
        SELECT s.entry_mode,
               -- the curriculum binds an undergraduate; a postgraduate carries a label from the entry session, not a CCMAS/BMAS load
               CASE WHEN s.entry_mode IS DISTINCT FROM 'POSTGRADUATE' AND g.category IS DISTINCT FROM 'POST GRADUATE' THEN s.curriculum_version END AS curriculum
          FROM people.student s LEFT JOIN ref.programme g ON g.code = s.programme_code
         WHERE s.id = p_student),
    lv AS (SELECT l.* FROM policy.level_limit l WHERE l.level = p_level),
    cce AS (SELECT r.* FROM policy.route_level_limit r JOIN st ON st.entry_mode = 'CCE' WHERE r.route = 'CCE' AND r.level = p_level),
    cur AS (SELECT u.* FROM st CROSS JOIN LATERAL registration.unit_minimum_rule(st.curriculum, p_session, p_semester) u
             WHERE st.curriculum IS NOT NULL AND u.id IS NOT NULL)
    SELECT coalesce(c.level, l.level),
           coalesce(c.min_units, u.min_units, l.min_units),
           coalesce(c.max_units, l.max_units),
           CASE WHEN c.level IS NOT NULL THEN c.probation_max_units ELSE l.probation_max_units END,
           coalesce(l.carryover_counts, true),
           (SELECT st.curriculum FROM st),
           CASE WHEN c.level IS NOT NULL THEN 'CCE' WHEN u.id IS NOT NULL THEN 'CURRICULUM' ELSE 'LEVEL' END,
           l.min_units,
           CASE WHEN c.level IS NULL THEN u.session END,
           CASE WHEN c.level IS NULL THEN u.semester END,
           CASE WHEN c.level IS NOT NULL THEN c.instrument ELSE l.instrument END
      FROM (SELECT 1) one
      LEFT JOIN cce c ON true
      LEFT JOIN lv l ON true
      LEFT JOIN cur u ON true
     WHERE c.level IS NOT NULL OR l.level IS NOT NULL
$$;
COMMENT ON FUNCTION registration.unit_rule(uuid, integer, text, integer) IS
  'V495: the course load that binds a student at a level in a session and semester — the CCE course load for a CCE student where one is stated (V380), else the curriculum''s minimum for an undergraduate (registration.unit_minimum), else the level''s; the maximum and probation ceiling stay the level''s (or the CCE load''s). basis says which: CCE, CURRICULUM or LEVEL';

CREATE FUNCTION registration.unit_limit(p_student uuid, p_level integer, p_session text, p_semester integer)
RETURNS SETOF policy.level_limit LANGUAGE sql STABLE AS $$
    SELECT u.level,
           CASE u.basis WHEN 'CCE' THEN 'CCE (part-time)'
                        WHEN 'CURRICULUM' THEN u.curriculum || ' minimum course load'
                        ELSE (SELECT l.applies_to FROM policy.level_limit l WHERE l.level = u.level) END,
           u.min_units, u.max_units, u.carryover_counts, u.instrument, u.probation_max_units
      FROM registration.unit_rule(p_student, p_level, p_session, p_semester) u
$$;
COMMENT ON FUNCTION registration.unit_limit(uuid, integer, text, integer) IS
  'V495: the unit range that binds a student at a level in a session and semester (registration.unit_rule), in the shape of policy.level_limit';

CREATE OR REPLACE FUNCTION registration.unit_limit(p_student uuid, p_level integer)
RETURNS SETOF policy.level_limit LANGUAGE sql STABLE AS $$
    SELECT * FROM registration.unit_limit(p_student, p_level, people.student_current_session(p_student), NULL)
$$;
COMMENT ON FUNCTION registration.unit_limit(uuid, integer) IS
  'V380/V495: the unit range that binds a student at a level in the student''s current session (registration.unit_rule) — callers that know the session name it';

-- ── the submission's checks: the floor is the student's own for the registration's session and semester ──
CREATE OR REPLACE FUNCTION registration.submit_checks(p_registration uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; lim record; units int; st record; v_gate text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    -- V361: the school fees the student owes for the session must be stated before they can be paid, or cleared
    IF NOT finance.fee_stated(r.student_id, r.session) THEN
        SELECT p.name AS programme, s.current_level AS level INTO st
          FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = r.student_id;
        RAISE EXCEPTION 'REG_FEES_NOT_STATED: the school fees of % at % level for % are not stated yet, so they cannot be paid or cleared',
            coalesce(st.programme, 'the programme'), st.level, r.session
            USING ERRCODE = '23514',
            HINT = 'Course registration opens when the Bursary states the session''s school fees on Fee Setup and they are paid.';
    END IF;
    -- V461: and the semester's own: while no school-fee line of this semester (or of the whole session) reaches the
    -- student, though another semester's does, the semester reads as paid when it is not stated — refused until it is
    IF r.semester = ANY (finance.fee_unstated_semesters(r.student_id, r.session)) THEN
        SELECT p.name AS programme, s.current_level AS level INTO st
          FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = r.student_id;
        RAISE EXCEPTION 'REG_SEMESTER_FEES_NOT_STATED: the % semester school fees of % at % level for % are not stated yet, so they cannot be paid or cleared',
            CASE r.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' WHEN 3 THEN 'third' ELSE r.semester::text END,
            coalesce(st.programme, 'the programme'), st.level, r.session
            USING ERRCODE = '23514',
            HINT = 'Course registration for the semester opens when the Bursary states its school fees on Fee Setup and they are paid.';
    END IF;
    IF NOT finance.semester_cleared(r.student_id, r.session, r.semester) THEN
        RAISE EXCEPTION 'the % semester school fees for % are not fully paid',
            CASE r.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' WHEN 3 THEN 'third' ELSE r.semester::text END, r.session
            USING ERRCODE = '23514',
            HINT = 'Course registration for a semester opens when that semester''s school fees are cleared in full.';
    END IF;
    -- V314: where the University holds the whole registration on the GST fee, an unpaid student does not submit
    v_gate := registration.gst_gate(r.student_id, r.session, NULL);
    IF v_gate IS NOT NULL THEN
        RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; submission opens the moment the payment is confirmed.';
    END IF;
    -- and a GST/EPS course already on the draft is not submitted unpaid either
    SELECT registration.gst_gate(r.student_id, r.session, o.course_code) INTO v_gate
      FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST'
     WHERE e.registration_id = p_registration AND e.status <> 'DROPPED' AND registration.gst_gate(r.student_id, r.session, o.course_code) IS NOT NULL
     LIMIT 1;
    IF v_gate IS NOT NULL THEN
        RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS, or remove the GST/EPS courses from the registration.';
    END IF;
    units := registration.units_of(p_registration);
    -- V380: the CCE course load for a CCE student; V495: the curriculum's minimum for the registration's session and semester
    SELECT * INTO lim FROM registration.unit_rule(r.student_id, r.level, r.session, r.semester);
    IF FOUND AND units < lim.min_units THEN
        RAISE EXCEPTION 'REG_UNITS_BELOW_MINIMUM: Course registration cannot be submitted. The minimum required credit load % is % credit units. You currently have % credit unit%.',
            CASE lim.basis WHEN 'CURRICULUM' THEN 'for your curriculum (' || lim.curriculum || ')'
                           WHEN 'CCE' THEN 'for a CCE student at ' || r.level || ' level'
                           ELSE 'at ' || r.level || ' level' END,
            lim.min_units, units, CASE WHEN units = 1 THEN '' ELSE 's' END
        USING ERRCODE = '23514', HINT = 'Add ' || (lim.min_units - units) || ' more credit unit' || CASE WHEN lim.min_units - units = 1 THEN '' ELSE 's' END || ' of courses offered to you, then submit again.';
    END IF;
    IF FOUND AND units > lim.max_units THEN
        RAISE EXCEPTION 'the registration carries % units; at % level the range is % to %', units, r.level, lim.min_units, lim.max_units
        USING ERRCODE = '23514', HINT = 'Add or drop courses to bring it within the range, or obtain an overload approval from the Head of Department.';
    END IF;
    SELECT * INTO st FROM assessment.student_standing(r.student_id);
    IF FOUND AND st.standing IN ('PROBATION', 'ADVISED_TO_WITHDRAW') AND lim.probation_max_units IS NOT NULL AND units > lim.probation_max_units THEN
        RAISE EXCEPTION 'you are on probation (CGPA % after % % semester); the registration carries % units and the limit on probation at % level is %',
            st.cgpa, st.pronounced_session, CASE st.pronounced_semester WHEN 1 THEN 'first' ELSE 'second' END, units, r.level, lim.probation_max_units
        USING ERRCODE = '23514', HINT = 'Drop courses to bring the registration within the probation limit. The carryovers stay; choose fewer new courses.';
    END IF;
END $function$;
COMMENT ON FUNCTION registration.submit_checks(uuid) IS
  'V491/V495: the checks a submission passes — the fees stated and cleared, the GST gate, the unit range (the curriculum''s minimum for the registration''s session and semester, the level''s maximum), the probation ceiling — read by the submission and the automatic approval alike';

-- ── ICT Support's drop: the advisory reads the same floor ──
CREATE OR REPLACE FUNCTION registration.support_drop_checks(p_student uuid, p_session text, p_semester integer, p_offering uuid)
 RETURNS TABLE(ord integer, rule text, label text, passed boolean, overridable boolean, advisory boolean, message text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE r registration.course_registration; e registration.entry; v_closed text; v_status text; v_gate text; lim policy.level_limit; v_units int; v_code text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    v_closed := registration.semester_closed(p_student, p_session, p_semester);   -- V380: by the student's calendar
    IF r.id IS NOT NULL THEN SELECT * INTO e FROM registration.entry x WHERE x.registration_id = r.id AND x.offering_id = p_offering; END IF;
    SELECT o.course_code INTO v_code FROM catalogue.offering o WHERE o.id = p_offering;
    v_status := coalesce(r.status, 'NONE');
    overridable := false; advisory := false;

    ord := 1; rule := 'REGISTRATION_EXISTS'; label := 'A registration to change';
    passed := r.id IS NOT NULL; message := CASE WHEN passed THEN 'The registration is ' || lower(v_status) || '.' ELSE 'No registration to change.' END;
    RETURN NEXT;
    ord := 2; rule := 'REGISTRATION_STATE'; label := 'Registration not locked';
    passed := v_status <> 'LOCKED'; message := CASE WHEN passed THEN 'Not locked.' ELSE 'This registration is locked and cannot be changed.' END;
    RETURN NEXT;
    ord := 3; rule := 'SEMESTER_RECORDS'; label := 'Semester not closed';
    passed := v_closed IS NULL;
    message := CASE WHEN passed THEN 'Not closed.' ELSE 'The semester is ' || v_closed || '; its registrations are history and are not changed.' END;
    RETURN NEXT;
    ord := 4; rule := 'ON_REGISTRATION'; label := 'On the current registration';
    passed := e.offering_id IS NOT NULL AND e.status <> 'DROPPED';
    message := CASE WHEN passed THEN coalesce(v_code, 'The course') || ' is ' || lower(e.status) || ' (' || e.units || ' units).'
                    ELSE coalesce(v_code, 'That course') || ' is not on the registration.' END;
    RETURN NEXT;
    ord := 5; rule := 'NOT_CARRYOVER'; label := 'Not a carry-over or deferred course';
    passed := e.offering_id IS NULL OR e.entry_type NOT IN ('CARRYOVER', 'DEFERRED');
    message := CASE WHEN passed THEN 'A ' || lower(coalesce(e.entry_type, 'current')) || ' course.'
                    WHEN e.entry_type = 'CARRYOVER' THEN 'A carry-over cannot be dropped; it must be repeated.'
                    ELSE 'A deferred course cannot be dropped; it is taken in the semester it is due.' END;
    RETURN NEXT;
    ord := 6; rule := 'NO_MARK'; label := 'No mark recorded';
    passed := NOT EXISTS (SELECT 1 FROM assessment.score sc JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id WHERE sc.student_id = p_student AND sh.offering_id = p_offering);
    message := CASE WHEN passed THEN 'No mark is recorded.' ELSE 'A mark is already recorded in this course; it is examination history and is not dropped.' END;
    RETURN NEXT;
    ord := 7; rule := 'REGISTRATION_WINDOW'; label := 'Registration window and late registration'; overridable := true;
    v_gate := registration.registration_gate(p_student, p_session, p_semester);
    passed := v_gate IS NULL; message := coalesce(v_gate, 'Open.');
    RETURN NEXT;
    ord := 8; rule := 'ADD_DROP_PERIOD'; label := 'Add and drop period';
    IF v_status IN ('SUBMITTED', 'APPROVED') THEN
        passed := registration.add_drop_open(p_student, p_session, p_semester);
        message := CASE WHEN passed THEN 'Open.' ELSE 'Add and drop is not open for ' || p_session || ' semester ' || p_semester || '.' END;
    ELSE
        passed := true; message := 'Not needed: the registration is not yet submitted.';
    END IF;
    RETURN NEXT;
    overridable := false;
    ord := 9; rule := 'UNITS'; label := 'Minimum credit load'; advisory := true; passed := true;
    -- V380: the CCE course load; V495: the curriculum's minimum for the session and semester
    SELECT * INTO lim FROM registration.unit_limit(p_student, r.level, p_session, p_semester);
    v_units := CASE WHEN r.id IS NULL THEN 0 ELSE registration.units_of(r.id) - CASE WHEN e.status IS NOT NULL AND e.status <> 'DROPPED' THEN e.units ELSE 0 END END;
    message := CASE WHEN lim.level IS NULL THEN 'No unit limit is set for the level.'
                    WHEN v_units >= lim.min_units THEN v_units || ' units after the drop, within the minimum of ' || lim.min_units || '.'
                    ELSE v_units || ' units after the drop, under the minimum of ' || lim.min_units || '; a draft so short is refused at submission.' END;
    RETURN NEXT;
END $function$;

-- ── setting the rule ──
CREATE FUNCTION registration.set_unit_minimum(p_curriculum text, p_session text, p_semester integer, p_min integer, p_reason text)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_curr text := upper(btrim(coalesce(p_curriculum, ''))); v_session text := nullif(btrim(coalesce(p_session, '')), '');
        v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := btrim(coalesce(p_reason, '')); v_ceiling int; v_ceiling_level int; n int;
BEGIN
    IF v_office IS NULL OR v_office NOT IN ('ict', 'super') THEN
        RAISE EXCEPTION 'REG_MIN_UNITS_OFFICE: the minimum course registration load is set by the Directorate of ICT' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.curriculum_track t WHERE t.framework = v_curr) THEN
        RAISE EXCEPTION 'REG_MIN_UNITS_CURRICULUM: no curriculum is named %', coalesce(nullif(v_curr, ''), '(none)') USING ERRCODE = '23514',
            HINT = 'Choose a curriculum of the University''s curriculum tracks.';
    END IF;
    IF v_session IS NOT NULL AND NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = v_session) THEN
        RAISE EXCEPTION 'REG_MIN_UNITS_SESSION: no academic session is named %', v_session USING ERRCODE = '23514', HINT = 'Choose a session on the calendar.';
    END IF;
    IF p_semester IS NOT NULL AND (p_semester NOT BETWEEN 1 AND 3 OR v_session IS NULL) THEN
        RAISE EXCEPTION 'REG_MIN_UNITS_SEMESTER: a semester''s minimum is set within a session, for semester 1, 2 or 3' USING ERRCODE = '23514';
    END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'REG_MIN_UNITS_REASON: a change of the minimum course load states its reason (ten characters or more)' USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', left(v_reason, 500), true);
    IF p_min IS NULL THEN
        IF v_session IS NULL THEN
            RAISE EXCEPTION 'REG_MIN_UNITS_STANDING: the standing minimum of % is changed, never removed', v_curr USING ERRCODE = '23514';
        END IF;
        DELETE FROM registration.unit_minimum WHERE curriculum = v_curr AND session = v_session AND semester IS NOT DISTINCT FROM p_semester;
        GET DIAGNOSTICS n = ROW_COUNT;
        RETURN n;
    END IF;
    IF p_min < 1 THEN
        RAISE EXCEPTION 'REG_MIN_UNITS_POSITIVE: minimum credit units must be greater than zero' USING ERRCODE = '23514';
    END IF;
    -- no higher than the lowest undergraduate maximum, or no registration could be valid
    SELECT l.max_units, l.level INTO v_ceiling, v_ceiling_level FROM policy.level_limit l WHERE l.level BETWEEN 100 AND 600 ORDER BY l.max_units, l.level LIMIT 1;
    IF v_ceiling IS NOT NULL AND p_min > v_ceiling THEN
        RAISE EXCEPTION 'REG_MIN_UNITS_OVER_MAXIMUM: minimum credit units of % would exceed the maximum of % credit units at % level', p_min, v_ceiling, v_ceiling_level
            USING ERRCODE = '23514', HINT = 'State a minimum at or below the maximum, or raise the maximum on Session & Semester Setup first.';
    END IF;
    INSERT INTO registration.unit_minimum (curriculum, session, semester, min_units, reason, set_by, set_office)
    VALUES (v_curr, v_session, p_semester, p_min, v_reason, v_actor, (SELECT o.code FROM ref.office o WHERE o.code = v_office))
    ON CONFLICT ON CONSTRAINT uq_unit_minimum DO UPDATE SET min_units = EXCLUDED.min_units, reason = EXCLUDED.reason, set_by = EXCLUDED.set_by,
        set_office = EXCLUDED.set_office, set_at = now();
    RETURN 1;
END $$;
COMMENT ON FUNCTION registration.set_unit_minimum(text, text, integer, integer, text) IS
  'V495: set (or, with no units, remove a session''s or semester''s) minimum course registration load of a curriculum, by the Directorate of ICT or super, with a reason; a whole number from 1, no higher than the lowest undergraduate maximum; the standing rule is changed, never removed';

-- ── what the screens read ──
CREATE FUNCTION registration.unit_minimum_in_force(p_session text, p_semester integer)
RETURNS TABLE(curriculum text, min_units integer, applies_as text, rule_session text, rule_semester integer, reason text, set_at timestamptz,
              set_by uuid, set_office text, students integer)
LANGUAGE sql STABLE AS $$
    WITH fw AS (SELECT DISTINCT t.framework FROM policy.curriculum_track t),
    n AS (SELECT s.curriculum_version AS fw, count(*)::int AS students FROM people.student s LEFT JOIN ref.programme g ON g.code = s.programme_code
           WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION') AND s.entry_mode IS DISTINCT FROM 'POSTGRADUATE'
             AND g.category IS DISTINCT FROM 'POST GRADUATE' AND s.curriculum_version IS NOT NULL
           GROUP BY 1)
    SELECT fw.framework, u.min_units,
           CASE WHEN u.semester IS NOT NULL THEN 'SEMESTER' WHEN u.session IS NOT NULL THEN 'SESSION' WHEN u.id IS NOT NULL THEN 'STANDING' ELSE 'NONE' END,
           u.session, u.semester, u.reason, u.set_at, u.set_by, u.set_office, coalesce(n.students, 0)
      FROM fw LEFT JOIN LATERAL (SELECT * FROM registration.unit_minimum_rule(fw.framework, p_session, p_semester) x WHERE x.id IS NOT NULL) u ON true
      LEFT JOIN n ON n.fw = fw.framework
     ORDER BY fw.framework DESC
$$;
COMMENT ON FUNCTION registration.unit_minimum_in_force(text, integer) IS
  'V495: for each curriculum, the minimum course load in force for a session and semester, the row it comes from (SEMESTER, SESSION or STANDING) and the undergraduates in study under it';

CREATE FUNCTION registration.below_minimum(p_session text, p_semester integer)
RETURNS TABLE(registration_id uuid, student_id uuid, full_name text, matric_no text, programme text, dept_code text, level integer, semester integer,
              status text, curriculum text, basis text, min_units integer, max_units integer, units integer)
LANGUAGE sql STABLE AS $$
    WITH r AS MATERIALIZED (
        SELECT g.id, g.student_id, g.level, g.semester, g.status, coalesce(sum(e.units), 0)::int AS units
          FROM registration.course_registration g
          JOIN registration.entry e ON e.registration_id = g.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
         WHERE g.session = p_session AND (p_semester IS NULL OR g.semester = p_semester)
         GROUP BY g.id),
    -- only a registration under the highest floor that could bind anyone is judged one by one
    top AS (SELECT greatest((SELECT max(min_units) FROM registration.unit_minimum), (SELECT max(min_units) FROM policy.level_limit),
                            (SELECT max(min_units) FROM policy.route_level_limit)) AS m),
    c AS MATERIALIZED (SELECT r.* FROM r, top WHERE r.units < top.m)
    SELECT c.id, c.student_id, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''), s.matric_no, p.name, p.dept_code,
           c.level, c.semester, c.status, u.curriculum, u.basis, u.min_units, u.max_units, c.units
      FROM c
      JOIN people.student s ON s.id = c.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      CROSS JOIN LATERAL registration.unit_rule(c.student_id, c.level, p_session, c.semester) u
     WHERE c.units < u.min_units
$$;
COMMENT ON FUNCTION registration.below_minimum(text, integer) IS
  'V495: the course registrations of a session (and semester) carrying fewer units than the minimum that binds the student — a draft that cannot be submitted yet, or a registration approved before (never rewritten)';

-- ── the rule now: the University's minimum by curriculum ──
INSERT INTO registration.unit_minimum (curriculum, session, semester, min_units, reason) VALUES
    ('CCMAS', NULL, NULL, 15, 'V495: the University''s minimum course registration load under CCMAS'),
    ('BMAS',  NULL, NULL, 18, 'V495: the University''s minimum course registration load under BMAS');

COMMIT;
