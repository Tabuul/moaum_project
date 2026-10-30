-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V711 · Spillover students are free of the automatic GST fee, and free to add elective courses
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's word of 30 October 2026, with a 400 Level spillover student's dashboard (B.Sc. (Ed) Computer Science, entered
--  2019/2020; GST & EPS: "Required for EPS 302 in 2025/2026", NOT PAID, PAY GST FEE): "spill over student should not automatically
--  see gst fee to pay except they are having carry over from the uploaded results, free all spill over student from auto gst fee
--  payment unless they add it as carry over"; and, in the same turn, "also allow spill over students to add elective courses".
--
--  Why they were asked: the GST/EPS engine (finance.gst_eps_rows, V366/V422) owes a student the GST fee for three reasons — a GST/EPS
--  course failed on the record (CARRYOVER), the programme's GST/EPS course at the student's level not yet passed (COURSE_OFFERING),
--  or one on this session's registration (REGISTERED). A spillover student sits at the final level (SP1/SP2) or above it, and the
--  programme binds GST/EPS courses there (EPS 302 at 400 Level): every one of them owed the fee for a course they never chose, and the
--  dashboard and the GST page asked for it (finance.gst_payable_courses, V643, shows the level's courses too).
--
--  1 · finance.gst_eps_rows: for a spillover student (finance.spill, in the session read at their current level), the programme's
--      GST/EPS course at their level is not owed (counts false, status NOT_OWED_SPILLOVER) unless it is on their registration. A
--      GST/EPS carry-over from their results is owed as before, and so is one they add. finance.gst_eps_rows_all, the desks
--      (finance.gst_population), eligibility, the gate and the GST fee all read this one engine.
--  2 · finance.gst_payable_courses: a spillover registration (registration.spillover_registration, V674) is shown no GST/EPS course to
--      pay for, so the dashboard does not ask. finance.gst_carry_payable (V690): the courses of their own level join the levels below —
--      the GST page offers the payment, the carry-over picker holds such a course until the fee is paid (registration.gst_gate_many)
--      and the fee is taken for it (finance.new_gst_reference, renew_reference): paid when they add one, never before.
--  3 · finance.gst_eps_reason gains the spillover word (SPILLOVER_NOT_OWED, after the three owed reasons); finance.gst_eps_eligibility
--      and finance.gst_population pass it.
--  4 · registration.entry_spillover_carry (V674): an elective stays an elective. V674 made every course a spillover student registers
--      a carry-over; an elective of the menu they choose now registers as an elective (a failed elective is an F, never a carry-over:
--      V689). The registration page shows a spillover student the menu's electives beside ADD CARRY-OVER.
--  The functions are changed in place from their live text (pg_get_functiondef), each change asserted to land exactly where meant.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V711: spillover students free of the automatic GST fee and free to add electives (the University''s word of 30 October 2026)', true);

CREATE FUNCTION pg_temp.v711_swap(p_text text, p_old text, p_new text, p_times integer) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE n integer := (length(p_text) - length(replace(p_text, p_old, ''))) / length(p_old);
BEGIN
    IF n <> p_times THEN
        RAISE EXCEPTION 'V711: "%" found % time(s), expected %', left(p_old, 90), n, p_times;
    END IF;
    RETURN replace(p_text, p_old, p_new);
END $fn$;

-- ── 1 · the engine: a spillover student's level courses owed only when registered ──
DO $do$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('finance.gst_eps_rows(text,uuid)'::regprocedure);
    d := pg_temp.v711_swap(d, $o$WITH cur AS (SELECT coalesce(max(name), '') AS name FROM policy.academic_session WHERE state = 'CURRENT'),$o$,
        $n$WITH cur AS (SELECT coalesce(max(name), '') AS name FROM policy.academic_session WHERE state = 'CURRENT'),
    -- V711: the Bursary's spillover basis (finance.spill_basis) and each undergraduate programme's final level, read once (only the
    -- student's own programme when one student is asked for)
    sb AS MATERIALIZED (SELECT finance.spill_basis() AS basis),
    fl AS MATERIALIZED (SELECT p.code, finance.final_level(p.code) AS final_level FROM ref.programme p
                         WHERE p.category = 'UNDER GRADUATE' AND (p_student IS NULL OR p.code = (SELECT st.programme_code FROM people.student st WHERE st.id = p_student))),$n$, 1);
    d := pg_temp.v711_swap(d, $o$AND s.entry_mode IS DISTINCT FROM 'CCE'),   -- V380: the GST/EPS fee is the full-time students'; the Bursary states CCE fees as CCE lines$o$,
        $n$AND s.entry_mode IS DISTINCT FROM 'CCE'),   -- V380: the GST/EPS fee is the full-time students'; the Bursary states CCE fees as CCE lines
    -- V711: the students in spillover in the session they are at now — finance.spill's rule (V571, V637) read over the register at once
    -- (asked student by student it cost the desk's whole-register read most of a second): on the cohort basis, the cohort engine's
    -- spillover state; on the level basis, above the programme's final level, or at it in a spillover state (SP1/SP2). The state is
    -- looked up only for a student it can decide. Kept apart from the engine's own reads so their plan is not touched.
    sp AS (SELECT c.id
             FROM (SELECT b.id, s.current_level, fl.final_level, sb.basis
                     FROM base b JOIN people.student s ON s.id = b.id JOIN fl ON fl.code = s.programme_code CROSS JOIN sb CROSS JOIN cur
                    WHERE p_session >= cur.name AND (sb.basis = 'COHORT' OR s.current_level >= fl.final_level)) c
            WHERE CASE WHEN c.basis <> 'COHORT' AND c.current_level > c.final_level THEN true
                       ELSE coalesce((SELECT ap.spillover_state LIKE 'SPILLOVER%' FROM people.academic_position ap WHERE ap.student_id = c.id), false) END),$n$, 1);
    d := pg_temp.v711_swap(d, $o$LEFT JOIN carry ca ON ca.student_id = o.student_id AND ca.course_code = o.course_code$o$,
        $n$LEFT JOIN carry ca ON ca.student_id = o.student_id AND ca.course_code = o.course_code
      LEFT JOIN sp ON sp.id = o.student_id AND o.source = 'COURSE_OFFERING'$n$, 1);
    -- V711: and is then owed for being on it (the source the reasons read), not for being the programme's
    d := pg_temp.v711_swap(d, $o$off.semesters, off.offering_id, o.source,$o$,
        $n$off.semesters, off.offering_id, CASE WHEN sp.id IS NOT NULL AND rg.course_code IS NOT NULL THEN 'REGISTERED' ELSE o.source END,$n$, 1);
    -- V711: the programme's course at a spillover student's level is owed only once it is on their registration
    d := pg_temp.v711_swap(d, $o$(o.source = 'CARRYOVER' OR NOT coalesce(ps.before, false))$o$,
                              $n$(o.source = 'CARRYOVER' OR (NOT coalesce(ps.before, false) AND sp.id IS NULL))$n$, 1);
    d := pg_temp.v711_swap(d, $o$WHEN off.course_code IS NULL THEN 'NOT_OFFERED'$o$,
                              $n$WHEN off.course_code IS NULL THEN 'NOT_OFFERED'
                WHEN sp.id IS NOT NULL THEN 'NOT_OWED_SPILLOVER'$n$, 1);
    EXECUTE d;
END $do$;
COMMENT ON FUNCTION finance.gst_eps_rows(text, uuid) IS
  'V366, V422, V711: the GST/EPS courses that concern each undergraduate of the session and whether each is owed — a carry-over from the record, the programme''s course at the student''s level not yet passed, or one on the registration; for a spillover student (finance.spill) the programme''s course at their level is owed only once registered (status NOT_OWED_SPILLOVER until then).';

-- ── 2 · nothing shown to pay for in spillover; the level's courses paid for when added as carry-overs ──
DO $do$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('finance.gst_payable_courses(uuid,text)'::regprocedure);
    d := pg_temp.v711_swap(d, $o$AND c.code NOT IN (SELECT pc.course_code FROM passed pc)$o$,
                              $n$AND c.code NOT IN (SELECT pc.course_code FROM passed pc)
       -- V711: a spillover student is shown no GST/EPS course to pay for; one they add as a carry-over is paid for then (gst_carry_payable)
       AND NOT registration.spillover_registration(p_student, p_session)$n$, 1);
    EXECUTE d;

    d := pg_get_functiondef('finance.gst_carry_payable(uuid,text)'::regprocedure);
    d := pg_temp.v711_swap(d, $o$registration.curriculum_open() AS open_all$o$,
                              $n$registration.curriculum_open() AS open_all, registration.spillover_registration(st.id, p_session) AS spill$n$, 1);
    -- V711: a spillover student adds the courses of their own level as carry-overs too (V674)
    d := pg_temp.v711_swap(d, $o$co.level < s.current_level AND co.level >= s.entry_level$o$,
                              $n$(co.level < s.current_level OR (s.spill AND co.level = s.current_level)) AND co.level >= s.entry_level$n$, 1);
    EXECUTE d;
END $do$;
COMMENT ON FUNCTION finance.gst_payable_courses(uuid, text) IS
  'V643, V711: the GST/EPS courses the registration page shows a student in a session — the programme''s at their level, offered in the session in the student''s stream, not already passed; an undergraduate in good standing, never CCE, never a spillover registration (who adds such a course as a carry-over: finance.gst_carry_payable). The GST fee is paid for them and they are held until it is.';
COMMENT ON FUNCTION finance.gst_carry_payable(uuid, text) IS
  'V690, V711: the GST/EPS courses a student may add as a carry-over — bound to the programme below their level (and, in spillover, at it) and at or above the entry level, not passed, not already payable: the GST fee is paid before one is added.';

-- ── 3 · why, in words: not owed in spillover ──
CREATE OR REPLACE FUNCTION finance.gst_eps_reason(p_office text, p_offering boolean, p_carry boolean, p_registered boolean, p_completed boolean,
                                                  p_not_offered boolean, p_spill boolean)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT p_office || CASE WHEN p_offering THEN '_REQUIRED_COURSE_OFFERING'
                            WHEN p_carry THEN '_REQUIRED_CARRYOVER'
                            WHEN p_registered THEN '_REQUIRED_REGISTERED'
                            WHEN p_spill THEN '_SPILLOVER_NOT_OWED'
                            WHEN p_completed THEN '_ALREADY_COMPLETED'
                            WHEN p_not_offered THEN '_COURSE_NOT_OFFERED'
                            ELSE '_NOT_APPLICABLE' END
$fn$;
COMMENT ON FUNCTION finance.gst_eps_reason(text, boolean, boolean, boolean, boolean, boolean, boolean) IS
  'V366, V711: why the office''s GST/EPS fee is owed or not — owed for the programme''s course, a carry-over or a registration; not owed in spillover (the level''s course not added), already completed, not run, or nothing that concerns the student.';

DO $do$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('finance.gst_eps_eligibility(uuid,text)'::regprocedure);
    d := pg_temp.v711_swap(d, $o$coalesce(bool_or(r.status = 'NOT_OFFERED'), false) AS not_offered,$o$,
                              $n$coalesce(bool_or(r.status = 'NOT_OFFERED'), false) AS not_offered,
                 coalesce(bool_or(r.status = 'NOT_OWED_SPILLOVER'), false) AS spill,$n$, 1);
    d := pg_temp.v711_swap(d, $o$g.done, g.not_offered)$o$, $n$g.done, g.not_offered, g.spill)$n$, 3);
    d := pg_temp.v711_swap(d, $o$e.done, e.not_offered)$o$, $n$e.done, e.not_offered, e.spill)$n$, 2);
    EXECUTE d;

    d := pg_get_functiondef('finance.gst_population(text,integer)'::regprocedure);
    d := pg_temp.v711_swap(d, $o$coalesce(bool_or(x.status = 'NOT_OFFERED') FILTER (WHERE x.office = 'GST'), false) AS g_none,$o$,
                              $n$coalesce(bool_or(x.status = 'NOT_OFFERED') FILTER (WHERE x.office = 'GST'), false) AS g_none,
                   coalesce(bool_or(x.status = 'NOT_OWED_SPILLOVER') FILTER (WHERE x.office = 'GST'), false) AS g_spill,$n$, 1);
    d := pg_temp.v711_swap(d, $o$coalesce(bool_or(x.status = 'NOT_OFFERED') FILTER (WHERE x.office = 'EPS'), false) AS e_none,$o$,
                              $n$coalesce(bool_or(x.status = 'NOT_OFFERED') FILTER (WHERE x.office = 'EPS'), false) AS e_none,
                   coalesce(bool_or(x.status = 'NOT_OWED_SPILLOVER') FILTER (WHERE x.office = 'EPS'), false) AS e_spill,$n$, 1);
    d := pg_temp.v711_swap(d, $o$q.g_none, q.g_complete$o$, $n$q.g_none, q.g_spill, q.g_complete$n$, 1);
    d := pg_temp.v711_swap(d, $o$q.e_none, q.e_complete$o$, $n$q.e_none, q.e_spill, q.e_complete$n$, 1);
    d := pg_temp.v711_swap(d, $o$coalesce(j.g_none, false))$o$, $n$coalesce(j.g_none, false), coalesce(j.g_spill, false))$n$, 1);
    d := pg_temp.v711_swap(d, $o$coalesce(j.e_none, false))$o$, $n$coalesce(j.e_none, false), coalesce(j.e_spill, false))$n$, 1);
    EXECUTE d;
END $do$;

-- ── 4 · a spillover student's elective stays an elective ──
CREATE OR REPLACE FUNCTION registration.entry_spillover_carry()
RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE v_student uuid; v_session text;
BEGIN
    -- V711: an elective the student chooses is an elective, in spillover too (a failed elective is an F, never a carry-over: V689)
    IF NEW.entry_type IN ('CARRYOVER', 'DEFERRED', 'REPEAT', 'ELECTIVE') THEN RETURN NEW; END IF;
    SELECT cr.student_id, cr.session INTO v_student, v_session FROM registration.course_registration cr WHERE cr.id = NEW.registration_id;
    IF registration.spillover_registration(v_student, v_session) THEN
        NEW.entry_type := 'CARRYOVER';
        NEW.added_as := 'CARRY_OVER_DECLARED';
    END IF;
    RETURN NEW;
END $fn$;
COMMENT ON FUNCTION registration.entry_spillover_carry() IS
  'V674, V711: a course entered on a spillover student''s registration of their current session (registration.spillover_registration) is a carry-over, declared — whoever enters it; a carry-over, deferred or repeated course is left as it is, and so is an elective (V711).';

COMMIT;
