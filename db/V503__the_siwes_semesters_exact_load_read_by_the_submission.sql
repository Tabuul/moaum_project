-- ═══════════════════════════════════════
-- V503 — The SIWES semester: the attachment semester read alike by the screen, the Head of Department and the submission
--
--   A semester was a "SIWES semester" (registration.siwes_units) whenever the programme offers an industrial-training course in
--   it; the student's screen then asked for exactly that course's units and the Head of Department's approval accepted exactly
--   that — but the submission's own check (registration.submit_checks, which the automatic approval runs too) applied the level's or
--   the curriculum's minimum (V495: CCMAS 15, BMAS 18): a student on attachment who registered the 6-unit SIWES course alone was
--   refused, and could never be approved automatically.
--
--   And "industrial training" is two things on the register (the live-shaped copy, 13 Oct 2026): in 12 programme semesters the
--   SIWES course (6 units) is the only required course — the student is away on attachment; in 24 the course (2 to 6 units: a
--   practicum, a clinical posting, a block-course debrief) sits beside other required courses of 3 to 56 units, and the students
--   register them all (15 to 25 units). Asking those for the SIWES course alone was wrong on the screen and at the Head's desk.
--
--     · registration.siwes_units restated: a SIWES semester is one in which the programme offers no other required (Core or GST)
--       course at the level — the attachment semester; a practicum beside required courses is an ordinary course of an ordinary
--       semester, with the curriculum's minimum;
--     · registration.unit_rule answers a SIWES semester with the SIWES course's units as both the minimum and the maximum, basis
--       SIWES, no probation ceiling; registration.unit_limit names it; registration.submit_checks refuses anything else with the
--       SIWES words (REG_SIWES_UNITS). The screen and the Head's approval read the same function, so all four agree.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V503: the SIWES (attachment) semester read alike by the screen, the Head and the submission', true);

CREATE OR REPLACE FUNCTION registration.siwes_units(p_programme text, p_level integer, p_semester integer)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT max(c.units)::int
      FROM catalogue.course_offer co
      JOIN catalogue.course c ON c.code = co.course_code
     WHERE co.programme_code = p_programme AND co.level = p_level
       AND catalogue.runs_in(c.semester, c.both_semesters, p_semester) AND c.industrial_training AND c.state <> 'ENDED'
       -- V503: the attachment semester — the programme offers no other required course at the level in it; a practicum beside
       -- required courses is an ordinary course of an ordinary semester
       AND NOT EXISTS (SELECT 1 FROM catalogue.course_offer o2 JOIN catalogue.course c2 ON c2.code = o2.course_code
                        WHERE o2.programme_code = p_programme AND o2.level = p_level AND o2.basis IN ('Core', 'GST')
                          AND NOT c2.industrial_training AND c2.state <> 'ENDED'
                          AND catalogue.runs_in(c2.semester, c2.both_semesters, p_semester));
$function$;
COMMENT ON FUNCTION registration.siwes_units(text, integer, integer) IS
  'V155/V503: the SIWES course''s units where the semester is the programme''s attachment semester at the level (an industrial-training course and no other required course in it), else NULL — read by the student''s screen, the Head of Department''s approval and the submission alike';

CREATE OR REPLACE FUNCTION registration.unit_rule(p_student uuid, p_level integer, p_session text, p_semester integer)
RETURNS TABLE(level integer, min_units integer, max_units integer, probation_max_units integer, carryover_counts boolean,
              curriculum text, basis text, level_min_units integer, rule_session text, rule_semester integer, instrument text)
LANGUAGE sql STABLE AS $$
    WITH st AS (
        SELECT s.entry_mode, s.programme_code,
               -- the curriculum binds an undergraduate; a postgraduate carries a label from the entry session, not a CCMAS/BMAS load
               CASE WHEN s.entry_mode IS DISTINCT FROM 'POSTGRADUATE' AND g.category IS DISTINCT FROM 'POST GRADUATE' THEN s.curriculum_version END AS curriculum
          FROM people.student s LEFT JOIN ref.programme g ON g.code = s.programme_code
         WHERE s.id = p_student),
    -- V503: the industrial-training (SIWES) semester carries exactly the SIWES course's units, as the student's screen and the
    -- Head of Department's approval already say: the SIWES course alone, no other course and no carry-over
    siw AS (SELECT registration.siwes_units(st.programme_code, p_level, p_semester) AS units FROM st WHERE p_semester IS NOT NULL),
    lv AS (SELECT l.* FROM policy.level_limit l WHERE l.level = p_level),
    cce AS (SELECT r.* FROM policy.route_level_limit r JOIN st ON st.entry_mode = 'CCE' WHERE r.route = 'CCE' AND r.level = p_level),
    cur AS (SELECT u.* FROM st CROSS JOIN LATERAL registration.unit_minimum_rule(st.curriculum, p_session, p_semester) u
             WHERE st.curriculum IS NOT NULL AND u.id IS NOT NULL)
    SELECT coalesce(c.level, l.level),
           coalesce(w.units, c.min_units, u.min_units, l.min_units),
           coalesce(w.units, c.max_units, l.max_units),
           CASE WHEN w.units IS NOT NULL THEN NULL WHEN c.level IS NOT NULL THEN c.probation_max_units ELSE l.probation_max_units END,
           coalesce(l.carryover_counts, true),
           (SELECT st.curriculum FROM st),
           CASE WHEN w.units IS NOT NULL THEN 'SIWES' WHEN c.level IS NOT NULL THEN 'CCE' WHEN u.id IS NOT NULL THEN 'CURRICULUM' ELSE 'LEVEL' END,
           l.min_units,
           CASE WHEN w.units IS NULL AND c.level IS NULL THEN u.session END,
           CASE WHEN w.units IS NULL AND c.level IS NULL THEN u.semester END,
           CASE WHEN c.level IS NOT NULL THEN c.instrument ELSE l.instrument END
      FROM (SELECT 1) one
      LEFT JOIN cce c ON true
      LEFT JOIN lv l ON true
      LEFT JOIN cur u ON true
      LEFT JOIN siw w ON true
     WHERE c.level IS NOT NULL OR l.level IS NOT NULL
$$;
COMMENT ON FUNCTION registration.unit_rule(uuid, integer, text, integer) IS
  'V495/V503: the course load that binds a student at a level in a session and semester — in a SIWES semester exactly the SIWES course''s units (basis SIWES); else the CCE course load for a CCE student where one is stated (V380), else the curriculum''s minimum for an undergraduate (registration.unit_minimum), else the level''s; the maximum and probation ceiling stay the level''s (or the CCE load''s). basis says which: SIWES, CCE, CURRICULUM or LEVEL';

CREATE OR REPLACE FUNCTION registration.unit_limit(p_student uuid, p_level integer, p_session text, p_semester integer)
RETURNS SETOF policy.level_limit LANGUAGE sql STABLE AS $$
    SELECT u.level,
           CASE u.basis WHEN 'SIWES' THEN 'SIWES (industrial training)' WHEN 'CCE' THEN 'CCE (part-time)'
                        WHEN 'CURRICULUM' THEN u.curriculum || ' minimum course load'
                        ELSE (SELECT l.applies_to FROM policy.level_limit l WHERE l.level = u.level) END,
           u.min_units, u.max_units, u.carryover_counts, u.instrument, u.probation_max_units
      FROM registration.unit_rule(p_student, p_level, p_session, p_semester) u
$$;

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
    -- V503: the SIWES semester is the SIWES course alone, exactly its units
    IF FOUND AND lim.basis = 'SIWES' AND units <> lim.min_units THEN
        RAISE EXCEPTION 'REG_SIWES_UNITS: The industrial-training (SIWES) semester carries exactly % credit units: the SIWES course alone, no other course. This registration carries % credit unit%.',
            lim.min_units, units, CASE WHEN units = 1 THEN '' ELSE 's' END
        USING ERRCODE = '23514', HINT = 'Register only the SIWES / industrial-training course this semester, then submit again.';
    END IF;
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
  'V491/V495/V503: the checks a submission passes — the fees stated and cleared, the GST gate, the unit range (exactly the SIWES course in a SIWES semester; else the curriculum''s minimum for the registration''s session and semester and the level''s maximum), the probation ceiling — read by the submission and the automatic approval alike';

COMMIT;
