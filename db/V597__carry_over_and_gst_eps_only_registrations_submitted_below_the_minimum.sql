-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V597 — Carry-over and GST/EPS-only registrations submitted below the curriculum minimum (the University's brief, 20 Oct 2026)
--
--   The minimum credit load (policy.level_limit, the curriculum's registration.unit_minimum: CCMAS 15, BMAS 18 — V495) bound every
--   submission: a student with one 3-unit carry-over and nothing else to register was refused ("Course registration cannot be
--   submitted. The minimum required credit load … is 15 credit units"), and so was one with only GST/EPS courses to sit — and with no
--   submitted registration there was no examination card and no GST & EPS permit for them. Carry-overs come only from published
--   results (registration.carryovers, V504) and are put on the draft at every level, SP1, SP2 or not (registration.student_draft);
--   none of that changes. What changes is what the minimum binds:
--     · registration.load_kind(registration): NORMAL where a live entry is a current course of the programme (not a carry-over, a
--       deferred or a repeated course, not a GST/EPS course); else GST_EPS where a live entry is a current GST/EPS course; else
--       CARRY_OVER (carry-overs and deferred courses alone); an empty registration reads NORMAL;
--     · registration.submit_checks: the minimum is asked of a NORMAL registration only — a carry-over-only or GST/EPS-only one is
--       submitted at whatever it carries; the maximum, the probation ceiling, the SIWES semester, the fees and the GST fee bind as before;
--     · registration.below_minimum (the Academic Office's list, V505): a registration whose kind waives the minimum is not below it.
--   A registration with a current course of the programme is judged as before, carry-overs counted in (policy.level_limit.carryover_counts),
--   so a student with 6 units of current courses and a carry-over is still refused; the Head of Department's approval (V491) and the
--   examination card and permit (V567, V589) read the registration as submitted. Nothing is stored: the kind is read from the entries.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V597: carry-over and GST/EPS-only registrations submitted below the curriculum minimum', true);

/* the kind of load a registration carries, read from its live entries */
CREATE FUNCTION registration.load_kind(p_registration uuid)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN bool_or(x.cat = 'NORMAL') THEN 'NORMAL'
                WHEN bool_or(x.cat = 'GST') THEN 'GST_EPS'
                WHEN count(*) > 0 THEN 'CARRY_OVER'
                ELSE 'NORMAL' END
      FROM (SELECT CASE WHEN e.entry_type IN ('CARRYOVER', 'DEFERRED', 'REPEAT') THEN 'CARRY_OVER'
                        WHEN e.entry_type = 'GST' OR c.kind = 'GST' THEN 'GST'
                        ELSE 'NORMAL' END AS cat
              FROM registration.entry e
              JOIN catalogue.offering o ON o.id = e.offering_id
              JOIN catalogue.course c ON c.code = o.course_code
             WHERE e.registration_id = p_registration AND e.status NOT IN ('DROPPED', 'WITHDRAWN')) x
$fn$;
COMMENT ON FUNCTION registration.load_kind(uuid) IS
    'V597: NORMAL where a live entry is a current course of the programme, else GST_EPS where one is a current GST/EPS course, else CARRY_OVER '
    '(carry-overs and deferred courses alone); the minimum credit load binds a NORMAL registration only';

/* the submission (V361, V461, V314, V380, V495, V503, V508), the minimum now asked of a NORMAL registration only */
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
    -- V597: the minimum binds a registration with a current course of the programme; one of carry-overs (and deferred courses) alone,
    -- or of GST/EPS courses alone, is submitted at whatever it carries — the maximum still binds
    IF FOUND AND units < lim.min_units AND registration.load_kind(p_registration) = 'NORMAL' THEN
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
END $function$
;

COMMENT ON FUNCTION registration.submit_checks(uuid) IS
    'what a submission must satisfy: the session''s and the semester''s school fees stated and cleared, the GST fee where the University holds the '
    'registration on it, the curriculum''s or the level''s minimum load (V597: of a registration with a current course of the programme only), the '
    'maximum, the probation ceiling and the SIWES semester''s exact load';

/* the Academic Office's list of registrations below the minimum (V505), without those whose kind waives it */
CREATE OR REPLACE FUNCTION registration.below_minimum(p_session text, p_semester integer)
 RETURNS TABLE(registration_id uuid, student_id uuid, full_name text, matric_no text, programme text, dept_code text, level integer, semester integer, status text, curriculum text, basis text, min_units integer, max_units integer, units integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH r AS MATERIALIZED (
        SELECT g.id, g.student_id, g.level, g.semester, g.status, coalesce(sum(e.units), 0)::int AS units
          FROM registration.course_registration g
          JOIN registration.entry e ON e.registration_id = g.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
         WHERE g.session = p_session AND (p_semester IS NULL OR g.semester = p_semester)
         GROUP BY g.id),
    -- only a registration under the highest floor that could bind anyone is judged one by one
    top AS (SELECT greatest((SELECT max(min_units) FROM registration.unit_minimum), (SELECT max(min_units) FROM policy.level_limit),
                            (SELECT max(min_units) FROM policy.route_level_limit)) AS m),
    c AS MATERIALIZED (
        SELECT r.* FROM r, top WHERE r.units < top.m
           AND NOT EXISTS (SELECT 1 FROM registration.load_decision d WHERE d.registration_id = r.id AND d.decision = 'ACCEPTED' AND d.units = r.units))
    SELECT c.id, c.student_id, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''), s.matric_no, p.name, p.dept_code,
           c.level, c.semester, c.status, u.curriculum, u.basis, u.min_units, u.max_units, c.units
      FROM c
      JOIN people.student s ON s.id = c.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      CROSS JOIN LATERAL registration.unit_rule(c.student_id, c.level, p_session, c.semester) u
     WHERE c.units < u.min_units
       -- V597: a registration of carry-overs or of GST/EPS courses alone is not below any minimum
       AND registration.load_kind(c.id) = 'NORMAL'
$function$
;

COMMENT ON FUNCTION registration.below_minimum(text, integer) IS
    'V505/V597: the registrations of the session (and semester) carrying fewer units than the student''s minimum without an accepted load decision '
    '— a registration of carry-overs or of GST/EPS courses alone is not below any minimum and is not listed';

COMMIT;
