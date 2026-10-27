-- ═══════════════════════════════════════
-- V674 — A spillover student registers carry-overs only: every course on their registration is a carry-over, never a fresh course
--
-- The University's word of 27 October 2026, on the Fees & payments page of a 400 Level student in SP1 for 2025/2026 ("spill over
-- students add carry over is not yet stable, or perfect, allow students add only carry over, what spill over students are
-- registering are all carry over, and not current courses, all the selected courses or chosen courses should be all carry over and
-- not register as fress courses … ones they add any course it should atomatically be carry over course"). A spillover student (SP1/SP2
-- at the final level, or above it: finance.is_spillover) has finished the programme's years and is back only for what they still
-- owe. On this portal they registered as any student: the registration page offered their level's core, elective and GST courses
-- as fresh courses, and the add (registration.student_add, student_choose, the support desk's add, the old portal's upload) entered
-- a course of the student's own level as CURRENT; the carry-over picker (V663) listed only the levels below theirs, so the final-level
-- courses they owe — most of what a spillover student owes — could not be added as carry-overs at all.
--
-- Now:
--   1. registration.spillover_registration(student, session): the student is in spillover and the session is the one they are in
--      now (people.student_current_session, else policy.university_current_session) or a later one.
--   2. A trigger on registration.entry (trg_entry_spillover_carry): a course entered on such a registration — by the student, the
--      support desk, the engine or an upload — is a carry-over (entry_type CARRYOVER), declared (added_as CARRY_OVER_DECLARED: the
--      student's choice, removable and droppable as V611 has it) unless it already is a carry-over, a deferred or a repeated course.
--      Its units, status and class are as entered; the semester's spillover fee is owed once it is on (V616), as for any course.
--   3. registration.course_context: for such a student, the courses of the level they are at are owed like those of the levels
--      below (V663's no-record carry-overs): the carry-over picker lists them, and adds them as carry-overs.
--   4. registration.carry_over_candidates: the picker lists the student's own level beside the levels below.
--   5. finance.spillover_panel: each semester's registeredCourses — the courses on its registration this session — for the fee card.
--   6. registration.support_drop_checks: a declared carry-over is dropped at the desk as the student drops it (V611); one a published
--      result states is still repeated, not dropped.
--   7. Put right: a course already entered as a fresh course on a spillover student's registration of their current session is a
--      carry-over (declared).
-- The registration page (Screens3) shows such a student the carry-over route alone: no fresh core, elective or GST list, no
-- "add other course"; GET /me/registration says carryOnly.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V674: a spillover student registers carry-overs only', true);

-- ── 1. a spillover registration ─────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION registration.spillover_registration(p_student uuid, p_session text)
RETURNS boolean
LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(finance.is_spillover(p_student)
                    AND p_session >= coalesce(people.student_current_session(p_student), policy.university_current_session()), false)
$fn$;
COMMENT ON FUNCTION registration.spillover_registration(uuid, text) IS
  'V674: the student is in spillover (finance.is_spillover) and the session is the one they are in now (people.student_current_session, '
  'else policy.university_current_session) or a later one: every course on their registration for it is a carry-over.';

-- ── 2. every course a spillover student registers is a carry-over ───────────────────────────────────────────────────────
CREATE FUNCTION registration.entry_spillover_carry()
RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE v_student uuid; v_session text;
BEGIN
    IF NEW.entry_type IN ('CARRYOVER', 'DEFERRED', 'REPEAT') THEN RETURN NEW; END IF;
    SELECT cr.student_id, cr.session INTO v_student, v_session FROM registration.course_registration cr WHERE cr.id = NEW.registration_id;
    IF registration.spillover_registration(v_student, v_session) THEN
        NEW.entry_type := 'CARRYOVER';
        NEW.added_as := 'CARRY_OVER_DECLARED';
    END IF;
    RETURN NEW;
END $fn$;
COMMENT ON FUNCTION registration.entry_spillover_carry() IS
  'V674: a course entered on a spillover student''s registration of their current session (registration.spillover_registration) is '
  'a carry-over, declared — whoever enters it; a carry-over, deferred or repeated course is left as it is.';
CREATE TRIGGER trg_entry_spillover_carry BEFORE INSERT OR UPDATE OF entry_type ON registration.entry
    FOR EACH ROW EXECUTE FUNCTION registration.entry_spillover_carry();

-- ── 3. the courses owed: a spillover student's own level among them (V663's definition, the level the only change) ──────────
CREATE OR REPLACE FUNCTION registration.course_context(p_student uuid, p_session text, p_semester integer, p_declare boolean)
 RETURNS TABLE(passed text[], awaited text[], carry text[], other_semester text[])
 LANGUAGE sql
 STABLE
AS $function$
    WITH r AS MATERIALIZED (SELECT * FROM assessment.student_results(p_student)),
    -- registered before, with no published result yet (or one held): not owed, not passed — never read as a failure
    pending AS MATERIALIZED (
        SELECT x.* FROM r x
         WHERE (x.session, x.semester) < (p_session, p_semester)
           AND (NOT x.published OR x.outcome IS NULL OR x.outcome NOT IN ('GRADED', 'ABSENT'))
           AND NOT EXISTS (SELECT 1 FROM r y WHERE y.course_code = x.course_code AND y.published AND y.outcome IN ('GRADED', 'ABSENT')
                             AND (y.session, y.semester) >= (x.session, x.semester))),
    -- V611: of those, a course every pending registration of which is of an earlier session and holds no result of the student on the
    -- portal — no score sheet of it, or a published sheet without them (its result is on the old portal) — and not passed: a carry-over
    -- the student may declare. A sheet not yet published, a result held, a registration earlier this session: the result is awaited
    declared AS MATERIALIZED (
        SELECT DISTINCT x.course_code FROM pending x
         WHERE NOT EXISTS (SELECT 1 FROM pending z WHERE z.course_code = x.course_code
                              AND (z.stage NOT IN ('NO_SHEET', 'NO_RESULT') OR z.session >= p_session))
           AND NOT EXISTS (SELECT 1 FROM r y WHERE y.course_code = x.course_code AND y.published AND y.outcome = 'GRADED' AND y.points > 0)),
    -- V663: no record — a course the student's programme binds below the level they are at (and not below the level they entered at:
    -- a direct-entry student owes nothing beneath it), core, required, borrowed or GST/EPS (never an elective they did not choose), of
    -- the student's track and specialisation, of which the portal holds no registration and no result of the student, nor of its
    -- BSU-/MOAU- twin: its record is on the old portal, and a carry-over the student may declare (the University's word of 26 October 2026)
    unrecorded AS MATERIALIZED (
        SELECT DISTINCT co.course_code
          FROM people.student s
          CROSS JOIN registration.flex_rule() pol
          JOIN catalogue.course_offer co ON co.programme_code = s.programme_code
                                         -- V674: a spillover student owes the courses of the level they are at too: every course they register is a carry-over
                                         AND (co.level < s.current_level OR (co.level = s.current_level AND registration.spillover_registration(s.id, p_session)))
                                         AND co.level >= coalesce(s.entry_level, 100)
                                         AND coalesce(co.basis, 'Core') NOT IN ('Elective', 'Deficiency', 'Research')
          JOIN catalogue.course c ON c.code = co.course_code AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
         WHERE p_declare AND s.id = p_student
           AND (pol.curriculum_open OR co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
           AND (NOT EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code AND x.level = co.level)
                OR EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x JOIN people.student_specialisation ss ON ss.specialisation_id = x.specialisation_id AND ss.student_id = s.id
                            WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code AND x.level = co.level))
           AND NOT EXISTS (SELECT 1 FROM r x WHERE x.course_code = co.course_code)
           AND NOT EXISTS (SELECT 1 FROM catalogue.course_twin t JOIN r x ON x.course_code IN (t.bsu_code, t.moau_code)
                            WHERE t.unlinked_at IS NULL AND co.course_code IN (t.bsu_code, t.moau_code)))
    SELECT coalesce((SELECT array_agg(DISTINCT x.course_code) FROM r x WHERE x.published AND x.outcome = 'GRADED' AND x.points > 0), '{}'::text[]),
           coalesce((SELECT array_agg(DISTINCT x.course_code) FROM pending x WHERE x.course_code NOT IN (SELECT d.course_code FROM declared d)), '{}'::text[]),
           coalesce((SELECT array_agg(DISTINCT k.course_code)
                       FROM (SELECT cv.course_code FROM registration.carryovers(p_student) cv UNION SELECT d.course_code FROM declared d
                             UNION SELECT u.course_code FROM unrecorded u) k), '{}'::text[]),
           coalesce((SELECT array_agg(DISTINCT o.course_code)
                       FROM registration.course_registration cr
                       JOIN registration.entry e ON e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                       JOIN catalogue.offering o ON o.id = e.offering_id
                      WHERE cr.student_id = p_student AND cr.session = p_session AND cr.semester <> p_semester), '{}'::text[])
$function$;

-- ── 4. the carry-over picker (V663's definition, a spillover student's own level listed) ────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.carry_over_candidates(p_student uuid, p_session text, p_semester integer)
 RETURNS TABLE(course_id uuid, course_code text, shown_code text, title text, units integer, level integer, course_semester integer, both_semesters boolean, course_group text, status text, origin_session text, origin_semester integer, last_grade text, offering_id uuid, selectable boolean, reason text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s people.student; ctx record; v_failed text[]; v_spill boolean;
BEGIN
    SELECT * INTO s FROM people.student x WHERE x.id = p_student;
    IF NOT FOUND THEN RETURN; END IF;
    -- V674: a spillover student registers carry-overs only, those of the level they are at among them
    v_spill := registration.spillover_registration(p_student, p_session);
    SELECT * INTO ctx FROM registration.course_context(p_student, p_session, p_semester, true);   -- the picker owes the no-record ones too
    v_failed := ARRAY(SELECT cv.course_code FROM registration.carryovers(p_student) cv);
    RETURN QUERY
    WITH r AS MATERIALIZED (SELECT * FROM assessment.student_results(p_student)),
    mine AS (SELECT DISTINCT o.course_code
               FROM registration.course_registration cr
               JOIN registration.entry e ON e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
               JOIN catalogue.offering o ON o.id = e.offering_id
              WHERE cr.student_id = p_student AND cr.session = p_session AND cr.semester = p_semester),
    -- the programme's courses below the student's level (and not below the level they entered at)
    bound AS (SELECT DISTINCT ON (co.course_code) co.course_code, co.level
                FROM catalogue.course_offer co
               WHERE co.programme_code = s.programme_code AND (co.level < s.current_level OR (v_spill AND co.level = s.current_level)) AND co.level >= coalesce(s.entry_level, 100)
               ORDER BY co.course_code, co.level),
    codes AS (SELECT x.course_code FROM r x WHERE (x.session, x.semester) < (p_session, p_semester)
              UNION SELECT b.course_code FROM bound b
              UNION SELECT unnest(ctx.carry)),
    -- the latest earlier registration of each, and its latest published grade
    last AS (SELECT DISTINCT ON (x.course_code) x.course_code, x.session, x.semester
               FROM r x WHERE (x.session, x.semester) < (p_session, p_semester)
              ORDER BY x.course_code, x.session DESC, x.semester DESC),
    graded AS (SELECT DISTINCT ON (x.course_code) x.course_code, x.grade
                 FROM r x WHERE x.published AND x.grade IS NOT NULL
                ORDER BY x.course_code, x.session DESC, x.semester DESC),
    judged AS (SELECT k.course_code, ch.offering_id, ch.category, ch.refusal
                 FROM codes k
                 CROSS JOIN LATERAL registration.course_check(p_student, p_session, p_semester, k.course_code,
                                                              ctx.passed, ctx.awaited, ctx.carry, ctx.other_semester) ch),
    shaped AS (
        SELECT c.id AS cid, c.code, c.title AS ctitle, coalesce(catalogue.units_for(c.code, s.programme_code, b.level), c.units) AS cunits,
               coalesce(b.level, c.level) AS clevel, c.semester AS csem, coalesce(c.both_semesters, false) AS cboth,
               CASE WHEN c.kind = 'GST' AND c.general_office = 'EPS' THEN 'EPS' WHEN c.kind = 'GST' THEN 'GST' ELSE 'OTHER' END AS cgroup,
               CASE WHEN c.code = ANY (ctx.passed) THEN 'CLEARED'
                    WHEN c.code IN (SELECT m.course_code FROM mine m) OR c.code = ANY (ctx.other_semester) THEN 'ALREADY_REGISTERED'
                    WHEN c.code = ANY (v_failed) THEN 'OUTSTANDING'
                    WHEN c.code = ANY (ctx.carry) AND EXISTS (SELECT 1 FROM r x WHERE x.course_code = c.code) THEN 'NO_RESULT'
                    WHEN c.code = ANY (ctx.carry) THEN 'NO_RECORD'
                    WHEN c.code = ANY (ctx.awaited) THEN 'AWAITED'
                    ELSE 'NOT_OWED' END AS cstatus,
               l.session AS osession, l.semester AS osemester, g.grade AS ograde, j.offering_id AS coffering, j.category AS ccategory, j.refusal AS crefusal
          FROM judged j
          JOIN catalogue.course c ON c.code = j.course_code
          LEFT JOIN bound b ON b.course_code = c.code
          LEFT JOIN last l ON l.course_code = c.code
          LEFT JOIN graded g ON g.course_code = c.code
         -- the other BSU-/MOAU- family's code of a course is never the student's: its twin is listed instead
         WHERE coalesce(j.refusal, '') NOT LIKE 'REG_OTHER_CODE_FAMILY%')
    SELECT x.cid, x.code, catalogue.shown_code(x.code), x.ctitle, x.cunits, x.clevel, x.csem, x.cboth, x.cgroup, x.cstatus,
           x.osession, x.osemester, x.ograde, x.coffering,
           x.cstatus IN ('OUTSTANDING', 'NO_RESULT', 'NO_RECORD') AND x.crefusal IS NULL AND x.ccategory = 'CARRY_OVER',
           CASE WHEN x.cstatus = 'CLEARED' THEN 'Cleared: passed on a published result'
                WHEN x.cstatus = 'ALREADY_REGISTERED' THEN 'Already registered in ' || p_session
                WHEN x.crefusal IS NOT NULL THEN regexp_replace(x.crefusal, '^[A-Z_]+: ', '')
                WHEN x.cstatus = 'OUTSTANDING' THEN 'Failed on a published result' || coalesce(' (' || x.osession || ')', '')
                WHEN x.cstatus = 'NO_RESULT' THEN 'Registered in ' || coalesce(x.osession, 'an earlier session') || '; no result on this portal'
                WHEN x.cstatus = 'NO_RECORD' THEN 'No record on this portal; add it only if you did not pass it'
                WHEN x.cstatus = 'AWAITED' THEN 'Result pending: your department publishes it'
                ELSE 'Not a carry-over of yours' END
      FROM shaped x
     WHERE (x.clevel < s.current_level OR (v_spill AND x.clevel = s.current_level) OR x.cstatus IN ('OUTSTANDING', 'NO_RESULT', 'AWAITED'))
       -- a course the student never took and does not owe (an elective not chosen) is not theirs to see here
       AND NOT (x.cstatus = 'NOT_OWED' AND x.osession IS NULL)
     ORDER BY x.clevel, x.csem, x.code;
END $function$;

-- ── 5. the spillover panel (V670's definition, each semester's registered courses added) ────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.spillover_panel(p_student uuid, p_session text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH s AS (
        SELECT st.id, finance.spill(st.id, st.current_level, st.programme_code, st.status) AS spill,
               finance.spill_year(st.id, st.current_level, st.programme_code, st.status) AS yr
          FROM people.student st WHERE st.id = p_student),
    ap AS (SELECT a.spillover_state FROM people.academic_position a WHERE a.student_id = p_student),
    rs AS (SELECT coalesce(finance.reg_semesters(p_student, p_session), '{}'::int[]) AS sems),
    -- each semester's spillover lines as they would apply once a course is registered in it (V616: p_any_semester)
    lines AS (
        SELECT f.semester, sum(c.amount) AS amount
          FROM finance.charges_of_as(p_student, p_session, ARRAY['FEE'], NULL, true) c
          JOIN finance.fee_schedule f ON f.id = c.id
         GROUP BY f.semester),
    -- the carry-overs the published results state, by the session and semester they were failed in
    co AS (
        SELECT split_part(c.failed_in, ' semester ', 1) AS session, nullif(split_part(c.failed_in, ' semester ', 2), '')::int AS semester,
               c.course_code, c.title, c.units
          FROM registration.carryovers(p_student) c),
    pos AS (SELECT * FROM finance.position(p_student, p_session)),
    -- V664: what the registration gate reads — the session's confirmed school-fee payments against the cumulative due: the whole-session
    -- item (semester 0) first, then the first semester, then the second; each semester's own amount is its step in that sum
    paid AS (SELECT coalesce(sum(r.amount), 0) AS p FROM finance.payment_reference r
              WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'),
    cum AS (SELECT n, finance.due_for_semester(p_student, p_session, n) AS c FROM unnest(ARRAY[0, 1, 2]) n),
    sem AS (
        SELECT k.n, c1.c - c0.c AS owed,
               least(greatest(paid.p - c0.c, 0), c1.c - c0.c) AS applied,
               CASE WHEN finance.fee_short(c1.c, paid.p) THEN (c1.c - c0.c) - least(greatest(paid.p - c0.c, 0), c1.c - c0.c) ELSE 0 END AS left_over,
               -- what is still to pay for the semester to be cleared: anything earlier left unpaid, and its own
               CASE WHEN finance.fee_short(c1.c, paid.p) THEN c1.c - paid.p ELSE 0 END AS to_clear
          FROM unnest(ARRAY[1, 2]) AS k(n)
          JOIN cum c1 ON c1.n = k.n
          JOIN cum c0 ON c0.n = k.n - 1
          CROSS JOIN paid)
    SELECT CASE WHEN NOT s.spill THEN NULL ELSE jsonb_build_object(
        'session', p_session,
        'state', (SELECT ap.spillover_state FROM ap),
        'year', s.yr,
        'label', CASE WHEN s.yr IS NOT NULL THEN 'SP' || s.yr ELSE 'Spillover' END,
        'registeredSemesters', to_jsonb(rs.sems),
        'semesters', (SELECT jsonb_agg(jsonb_build_object(
                          'semester', x.n,
                          'fee', coalesce((SELECT l.amount FROM lines l WHERE l.semester = x.n), 0),
                          'registered', x.n = ANY (rs.sems),
                          'carryovers', (SELECT count(*) FROM co WHERE co.semester = x.n),
                          -- V674: the carry-over courses on the semester's registration this session (every course a spillover student registers)
                          'registeredCourses', (SELECT count(*) FROM registration.course_registration cr
                                                  JOIN registration.entry e ON e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                                                 WHERE cr.student_id = p_student AND cr.session = p_session AND cr.semester = x.n),
                          'courses', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', co.course_code, 'title', co.title, 'units', co.units, 'session', co.session)
                                                                ORDER BY co.session, co.course_code), '[]'::jsonb) FROM co WHERE co.semester = x.n),
                          -- V664: the semester's own obligation, the payments applied to it, what is left, and where it stands
                          'owed', CASE WHEN x.n = ANY (rs.sems) THEN x.owed ELSE 0 END,
                          'paid', CASE WHEN x.n = ANY (rs.sems) THEN x.applied ELSE 0 END,
                          'outstanding', CASE WHEN x.n = ANY (rs.sems) THEN x.left_over ELSE 0 END,
                          'toClear', CASE WHEN x.n = ANY (rs.sems) THEN x.to_clear ELSE 0 END,
                          'cleared', CASE WHEN x.n = ANY (rs.sems) THEN finance.semester_cleared(p_student, p_session, x.n) ELSE true END,
                          -- registered: ready only when the gate clears it (a whole-session item unpaid holds every semester); a semester
                          -- with no line of its own and no whole-session item is not stated
                          'status', CASE WHEN x.n = ANY (rs.sems) THEN
                                             CASE WHEN x.owed <= 0 AND coalesce((SELECT l.amount FROM lines l WHERE l.semester = x.n), 0) <= 0
                                                       AND coalesce((SELECT l.amount FROM lines l WHERE l.semester IS NULL), 0) <= 0 THEN 'NOT_STATED'
                                                  WHEN finance.semester_cleared(p_student, p_session, x.n) THEN 'PAID'
                                                  WHEN x.applied > 0 THEN 'PART_PAID'
                                                  ELSE 'PAYMENT_REQUIRED' END
                                         WHEN (SELECT count(*) FROM co WHERE co.semester = x.n) > 0 THEN 'NOT_REGISTERED'
                                         ELSE 'NOTHING_OWED' END)
                          ORDER BY x.n) FROM sem x),
        'sessionFee', coalesce((SELECT l.amount FROM lines l WHERE l.semester IS NULL), 0),
        'sessionOwed', (SELECT c FROM cum WHERE n = 0),
        'sessionPaid', least((SELECT p FROM paid), (SELECT c FROM cum WHERE n = 0)),
        'due', pos.due, 'paid', pos.paid, 'balance', greatest(pos.balance, 0)) END
      FROM s CROSS JOIN rs CROSS JOIN pos
$function$;

-- ── 6. the support desk's drop rules (V495's definition, a declared carry-over droppable) ──────────────────────────────────
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
    passed := e.offering_id IS NULL OR e.entry_type NOT IN ('CARRYOVER', 'DEFERRED') OR coalesce(e.added_as = 'CARRY_OVER_DECLARED', false);   -- V674: as registration.student_drop (V611)
    message := CASE WHEN passed AND e.added_as = 'CARRY_OVER_DECLARED' THEN 'A carry-over declared, not one a published result states: dropped as it was added.'
                    WHEN passed THEN 'A ' || lower(coalesce(e.entry_type, 'current')) || ' course.'
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

-- ── 7. put right: the fresh courses already on a spillover student's registration of their current session ───────────────
DO $$
DECLARE n_entries int; n_students int;
BEGIN
    WITH sp AS (SELECT st.id FROM people.student st
                 WHERE st.status NOT IN ('GRADUATED') AND finance.spill(st.id, st.current_level, st.programme_code, st.status)),
    moved AS (
        UPDATE registration.entry e SET entry_type = 'CARRYOVER', added_as = 'CARRY_OVER_DECLARED'
          FROM registration.course_registration cr
         WHERE cr.id = e.registration_id AND cr.student_id IN (SELECT sp.id FROM sp)
           AND e.entry_type NOT IN ('CARRYOVER', 'DEFERRED', 'REPEAT') AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
           AND registration.spillover_registration(cr.student_id, cr.session)
        RETURNING cr.student_id)
    SELECT count(*), count(DISTINCT student_id) INTO n_entries, n_students FROM moved;
    RAISE NOTICE 'V674: % course(s) of % spillover student(s) registered as carry-overs', n_entries, n_students;
END $$;

COMMIT;
