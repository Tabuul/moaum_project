-- ═══════════════════════════════════════
-- V664 — a spillover student's registration held to the fee of the semester it is for
--
-- The University's master prompt of 26 October 2026 ("SEMESTER-SENSITIVE SPILLOVER PAYMENT, CARRY-OVER DETECTION & COURSE
-- REGISTRATION"): a spillover student who paid the first semester's spillover fee and registered first-semester carry-overs went on to
-- register second-semester courses without paying the second semester's. Most of the rule stood: a spillover student owes a semester's
-- spillover lines only once a course of it is on a registration, a whole-session line once any semester is (V616); the semester's due is
-- cumulative and every confirmed school-fee payment of the session counts once against it (finance.due_for_semester,
-- finance.semester_cleared), so the first semester's payment covers the second only where it was more than the first's; the submission
-- waits for the semester's fees (registration.submit_checks); carry-overs are found by the semester they were failed in and the minimum
-- does not hold a spillover student (V597, V615); the Fees page shows each semester's spillover fee (V637). The hole, two doors to it:
--   · registration.student_add, from V616, did not hold a spillover student's course for the fee — right on a draft, whose submission
--     waits for it, but a course added to a registration already submitted or approved (add and drop, the carry-over picker of V663,
--     ICT Support's add on a ticket) is registered at once, with no submission after it;
--   · registration.submit_checks let a spillover student submit a registration with no course on it (the minimum does not hold them,
--     V615), and with no course of the semester nothing of it was owed — so the second semester was approved empty and its courses came
--     after, in add and drop, unpaid.
-- What V664 does:
--   1 · finance.reg_semesters reads, beside the semesters registered, the one a check is reading as registered (moaum.registering, set
--       for the length of one call by finance.semester_position): the semester's fee as it stands once its course is on it.
--   2 · finance.semester_position(student, session, semester, registering): due up to the semester, paid, outstanding, cleared — the
--       registration gate's own figures (finance.semester_cleared); finance.naira words an amount.
--   3 · registration.semester_fee_gate: a spillover student's course on a submitted or approved registration waits for the semester's fee
--       (REG_SEMESTER_FEES_DUE with the amounts; REG_SEMESTER_FEES_NOT_STATED, REG_FEES_NOT_STATED where nothing is stated), read by
--       registration.student_add (restated) for every add path; a draft as before.
--   4 · registration.submit_checks (restated): the refusal says what is outstanding, due and paid (REG_SEMESTER_FEES_DUE), and for a
--       spillover student that the semester's own spillover fee is owed; a registration with no course is not submitted where no minimum
--       would stop it (REG_NO_COURSES).
--   5 · registration.support_add_checks (restated): the offices' preview reads the same semester fee.
--   6 · finance.spillover_panel (restated): each semester's own fee, the payments applied to it (the whole-session item first, then the
--       first semester, then the second — the order the gate reads them in), what is left, and its state (PAID, PART_PAID,
--       PAYMENT_REQUIRED, NOT_STATED, NOT_REGISTERED, NOTHING_OWED).
--   7 · a spillover student's registration submitted or approved with no course on it, in a semester not closed, is a draft again,
--       with a reset record saying why — the door it came in by is closed, and its courses wait for the semester's fee.
-- A whole-session spillover line, where the Bursary states one, is owed once any semester is registered and covers the session, as it
-- did; nothing is charged for a semester the student registers nothing in; a non-spillover student is charged and held as before.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V664: a spillover student''s registration held to the fee of the semester it is for', true);

-- ── 1 · the semesters a spillover student's fees are read against, with the one a check reads as registered ──
CREATE OR REPLACE FUNCTION finance.reg_semesters(p_student uuid, p_session text)
 RETURNS integer[]
 LANGUAGE sql
 STABLE
AS $function$
    SELECT coalesce(array_agg(DISTINCT x.semester ORDER BY x.semester), '{}'::int[])
      FROM (SELECT cr.semester
              FROM registration.course_registration cr
             WHERE cr.student_id = p_student AND cr.session = p_session
               AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))
            UNION ALL
            -- V664: the semester finance.semester_position reads as registered, for the length of that one call
            SELECT split_part(g.v, '|', 3)::int
              FROM (SELECT current_setting('moaum.registering', true) AS v) g
             WHERE g.v ~ '^[0-9a-f-]{36}\|[0-9]{4}/[0-9]{4}\|[0-9]$'
               AND split_part(g.v, '|', 1) = p_student::text AND split_part(g.v, '|', 2) = p_session) x
$function$;
COMMENT ON FUNCTION finance.reg_semesters(uuid, text) IS 'V616, V664: the semesters of the session the student has registered a course in — a registration in any state holding a course not dropped — and the one finance.semester_position is reading as registered; a spillover student''s fee lines are read against it';

-- ── 2 · a semester's position, as the registration gate reads it ──
CREATE OR REPLACE FUNCTION finance.naira(p_amount numeric)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT '₦' || to_char(round(coalesce(p_amount, 0), 2), 'FM999,999,999,990.00')
$function$;
COMMENT ON FUNCTION finance.naira(numeric) IS 'V664: an amount in words for a message — ₦135,000.00';

CREATE OR REPLACE FUNCTION finance.semester_position(p_student uuid, p_session text, p_semester integer, p_registering boolean DEFAULT false)
 RETURNS TABLE(due numeric, paid numeric, outstanding numeric, cleared boolean)
 LANGUAGE plpgsql
AS $function$
DECLARE v_before text := current_setting('moaum.registering', true);
BEGIN
    -- with p_registering, the semester read as registered: its spillover lines (and a whole-session one) owed as they are once a course of
    -- it is on the registration — the setting is this call's alone, put back before it returns
    IF p_registering THEN
        PERFORM set_config('moaum.registering', p_student::text || '|' || p_session || '|' || p_semester::text, true);
    END IF;
    due := finance.due_for_semester(p_student, p_session, p_semester);
    paid := coalesce((SELECT sum(r.amount) FROM finance.payment_reference r
                       WHERE r.student_id = p_student AND r.session = p_session
                         AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'), 0);
    outstanding := CASE WHEN finance.fee_short(due, paid) THEN due - paid ELSE 0 END;
    cleared := finance.semester_cleared(p_student, p_session, p_semester);
    IF p_registering THEN
        PERFORM set_config('moaum.registering', coalesce(v_before, ''), true);
    END IF;
    RETURN NEXT;
END $function$;
COMMENT ON FUNCTION finance.semester_position(uuid, text, integer, boolean) IS
  'V664: a semester''s school fees as the registration gate reads them — due up to the semester (finance.due_for_semester), the session''s confirmed school-fee payments, what is outstanding (nothing under one naira) and whether the semester is cleared (finance.semester_cleared); with p_registering, as they stand once a course of the semester is registered (a spillover student''s semester lines owed)';

-- a spillover student's course on a registration already submitted or approved: the semester's fee first, said with its figures
CREATE OR REPLACE FUNCTION registration.semester_fee_gate(p_student uuid, p_session text, p_semester integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE fp record; w text; st record;
BEGIN
    SELECT * INTO fp FROM finance.semester_position(p_student, p_session, p_semester, true);
    IF fp.cleared THEN RETURN; END IF;
    w := CASE p_semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' WHEN 3 THEN 'third' ELSE p_semester::text END;
    SELECT p.name AS programme, s.current_level AS level INTO st
      FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = p_student;
    IF NOT finance.fee_stated(p_student, p_session) THEN
        RAISE EXCEPTION 'REG_FEES_NOT_STATED: the school fees of % at % level for % are not stated yet, so they cannot be paid or cleared',
            coalesce(st.programme, 'the programme'), st.level, p_session
            USING ERRCODE = '23514', HINT = 'Course registration opens when the Bursary states the session''s school fees on Fee Setup and they are paid.';
    END IF;
    IF fp.outstanding < 1 THEN
        RAISE EXCEPTION 'REG_SEMESTER_FEES_NOT_STATED: the % semester school fees of % at % level for % are not stated yet, so they cannot be paid or cleared',
            w, coalesce(st.programme, 'the programme'), st.level, p_session
            USING ERRCODE = '23514', HINT = 'Course registration for the semester opens when the Bursary states its school fees on Fee Setup and they are paid.';
    END IF;
    RAISE EXCEPTION 'REG_SEMESTER_FEES_DUE: % semester registration requires payment of the % semester spillover fee for %: % outstanding (% due up to the % semester, % paid). A payment for another semester does not cover it',
        initcap(w), w, p_session, finance.naira(fp.outstanding), finance.naira(fp.due), w, finance.naira(fp.paid)
        USING ERRCODE = '23514',
              HINT = 'Pay ' || finance.naira(fp.outstanding) || ' on Fees & payments; the course can be added the moment the payment is confirmed.';
END $function$;
COMMENT ON FUNCTION registration.semester_fee_gate(uuid, text, integer) IS
  'V664: a spillover student''s course added to a registration already submitted or approved (registered at once, with no submission after it) waits for the semester''s fee as it stands with the course on it — REG_SEMESTER_FEES_DUE with what is outstanding, due and paid; REG_FEES_NOT_STATED / REG_SEMESTER_FEES_NOT_STATED where nothing is stated';

-- ── 3 · a course added to a registration already submitted or approved: the spillover student's semester fee first ──
CREATE OR REPLACE FUNCTION registration.student_add(p_student uuid, p_session text, p_semester integer, p_offering uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; m record; lim policy.level_limit; v_units int; v_type text; v_status text; v_gate text; v_unmet text[];
        v_code text; x record; v_as text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF NOT FOUND THEN RAISE EXCEPTION 'register first, then add or drop' USING ERRCODE = '23514'; END IF;
    IF r.status = 'LOCKED' THEN RAISE EXCEPTION 'this registration is locked and cannot be changed' USING ERRCODE = '23514'; END IF;
    IF NOT registration.add_drop_open(p_student, p_session, p_semester) THEN   -- V380: by the student's calendar
        RAISE EXCEPTION 'add and drop is not open for % semester %', p_session, p_semester USING ERRCODE = '23514',
            HINT = 'It runs while the semester is open, up to the late-registration deadline set by the Registry.';
    END IF;
    -- V616: on a draft a spillover student's choice of courses is what makes the semester's fee due, so the choice is not held for
    -- the payment; the submission waits for it (submit_checks reads finance.semester_cleared) as for everyone.
    -- V664: a course added to a registration already submitted or approved is registered at once, with no submission after it — a
    -- spillover student's semester is read with the course on it, and its fee paid first; a payment for another semester never covers it
    IF finance.is_spillover(p_student) THEN
        IF r.status NOT IN ('DRAFT', 'RETURNED') THEN
            PERFORM registration.semester_fee_gate(p_student, p_session, p_semester);
        END IF;
    ELSIF NOT finance.clears(p_student, p_session, 'REGISTRATION') THEN
        RAISE EXCEPTION 'the Bursary has not cleared you for registration in %', p_session USING ERRCODE = '23514';
    END IF;
    -- V504: a course already on the registration is not added twice
    SELECT o.course_code INTO v_code FROM catalogue.offering o WHERE o.id = p_offering;
    IF EXISTS (SELECT 1 FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id
                WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN') AND o.course_code = v_code) THEN
        RAISE EXCEPTION 'REG_ALREADY_ADDED: Course already added' USING ERRCODE = '23514';
    END IF;

    SELECT * INTO m FROM registration.student_menu(p_student, p_session, p_semester) WHERE offering_id = p_offering AND NOT carryover;
    IF FOUND THEN
        -- V314: a GST or EPS course is added only by a student whose GST fee is paid
        v_gate := registration.gst_gate(p_student, p_session, m.course_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; it opens the moment the payment is confirmed.';
        END IF;
        -- V482: where the Academic Office enforces prerequisites, a course whose prerequisite the student has not passed is refused
        IF registration.prerequisite_mode() = 'ENFORCED' THEN
            v_unmet := registration.prerequisites_unmet(p_student, m.course_code);
            IF cardinality(v_unmet) > 0 THEN
                RAISE EXCEPTION 'REG_PREREQUISITE: % needs % passed first; no published pass is on your record', m.course_code, array_to_string(v_unmet, ', ')
                    USING ERRCODE = '23514', HINT = 'If you passed it and the result is not yet published, or were exempted, your department asks ICT Support to add the course on your ticket.';
            END IF;
        END IF;
        v_units := m.units;
        v_type := CASE WHEN m.basis = 'GST' OR m.kind = 'GST' THEN 'GST' WHEN m.basis = 'Borrowed' THEN 'BORROWED'
                       WHEN m.basis = 'Elective' OR (m.basis IS NULL AND m.kind = 'Elective') THEN 'ELECTIVE' ELSE 'CURRENT' END;
    ELSE
        -- V504: a course beside the menu, when the engine allows it (registration.course_check judges it; prerequisites included)
        SELECT * INTO x FROM registration.course_refusal(p_student, p_session, p_semester, p_offering);
        IF x.refusal IS NOT NULL THEN RAISE EXCEPTION '%', x.refusal USING ERRCODE = '23514'; END IF;
        -- V314: the GST fee owed holds every course the student registers, as on the menu (registration.gst_gate)
        v_gate := registration.gst_gate(p_student, p_session, v_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; it opens the moment the payment is confirmed.';
        END IF;
        SELECT catalogue.units_for(v_code, s.programme_code, NULL) INTO v_units FROM people.student s WHERE s.id = p_student;
        v_type := CASE x.category WHEN 'CARRY_OVER' THEN 'CARRYOVER' WHEN 'GST' THEN 'GST' WHEN 'ELECTIVE' THEN 'ELECTIVE' ELSE 'CURRENT' END;
        v_as := x.added_as;
    END IF;
    -- an approved registration has no further approval step, so the added course is examinable at once;
    -- a still-submitted one keeps REGISTERED and the HOD's approval flips it with the batch (RegistrationRepository)
    v_status := CASE WHEN r.status = 'APPROVED' THEN 'APPROVED' ELSE 'REGISTERED' END;

    -- would this exceed the level's maximum?
    SELECT * INTO lim FROM registration.unit_limit(p_student, r.level);   -- V380: the CCE course load for a CCE student
    IF FOUND AND registration.units_of(r.id) + v_units > lim.max_units THEN
        RAISE EXCEPTION 'adding this course puts you at % units, over the maximum of % at % level',
            registration.units_of(r.id) + v_units, lim.max_units, r.level USING ERRCODE = '23514',
            HINT = 'Drop a course first, or ask your Head of Department for an overload.';
    END IF;

    -- reinstate a dropped entry, or add a new one
    IF EXISTS (SELECT 1 FROM registration.entry WHERE registration_id = r.id AND offering_id = p_offering) THEN
        UPDATE registration.entry SET status = v_status, units = v_units, entry_type = v_type,
               student_added_at = CASE WHEN m.offering_id IS NULL THEN now() END, added_as = v_as
         WHERE registration_id = r.id AND offering_id = p_offering;
    ELSE
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status, student_added_at, added_as)
        VALUES (r.id, p_offering, v_units, v_type, v_status, CASE WHEN m.offering_id IS NULL THEN now() END, v_as);
    END IF;
    PERFORM registration.gst_course_registered(r.id, p_offering);   -- V512: the GST/EPS registration log
    RETURN registration.units_of(r.id);
END $function$;

-- ── 4 · the submission: the semester's figures in the refusal, and no empty registration where no minimum stops it ──
CREATE OR REPLACE FUNCTION registration.submit_checks(p_registration uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; lim record; units int; st record; v_gate text; fp record; w text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    w := CASE r.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' WHEN 3 THEN 'third' ELSE r.semester::text END;
    -- V664: a registration with no course on it is not submitted where no minimum load would stop it (a spillover student's): its
    -- semester's fee is owed only once a course of it is registered, so an empty one approved would take courses later unpaid
    IF NOT EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = p_registration AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))
       AND (registration.load_kind(p_registration) <> 'NORMAL' OR coalesce(finance.is_spillover(r.student_id), false)) THEN
        RAISE EXCEPTION 'REG_NO_COURSES: there is no course on this % semester registration to submit', w
            USING ERRCODE = '23514',
            HINT = 'Add the courses you are registering this semester — your carry-overs with ADD CARRY-OVER — then submit.';
    END IF;
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
        -- V664: with the semester's figures — what is owed up to it, what is paid, what is left — and, for a spillover student, that
        -- the semester's own spillover fee is owed and a payment for another semester does not cover it
        SELECT * INTO fp FROM finance.semester_position(r.student_id, r.session, r.semester, false);
        RAISE EXCEPTION 'REG_SEMESTER_FEES_DUE: the % semester school fees for % are not fully paid: % outstanding (% due up to the % semester, % paid)%',
            w, r.session, finance.naira(fp.outstanding), finance.naira(fp.due), w, finance.naira(fp.paid),
            CASE WHEN finance.is_spillover(r.student_id)
                 THEN '. ' || initcap(w) || ' semester registration requires payment of the ' || w || ' semester spillover fee; a payment for another semester does not cover it'
                 ELSE '' END
            USING ERRCODE = '23514',
            HINT = 'Pay ' || finance.naira(fp.outstanding) || ' on Fees & payments; the registration is submitted the moment the payment is confirmed. Your courses stay on the draft.';
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
END $function$;

-- ── 5 · ICT Support's and the offices' preview: the same semester fee ──
CREATE OR REPLACE FUNCTION registration.support_add_checks(p_student uuid, p_session text, p_semester integer, p_offering uuid)
 RETURNS TABLE(ord integer, rule text, label text, passed boolean, overridable boolean, advisory boolean, message text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s people.student; o catalogue.offering; c catalogue.course; r registration.course_registration; v_closed text; v_cal text; m record;
        lim policy.level_limit; v_status text; v_units int; v_add int; v_gate text; v_pre text; w text; v_mode text; v_unmet text[]; fp record;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    SELECT * INTO o FROM catalogue.offering WHERE id = p_offering;
    IF o.id IS NOT NULL THEN SELECT * INTO c FROM catalogue.course WHERE code = o.course_code; END IF;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    -- V380: the student's calendar (the CCE calendar for a CCE student)
    SELECT lower(x.state) INTO v_cal FROM registration.calendar_semester(p_student, p_session, p_semester) x;
    v_closed := registration.semester_closed(p_student, p_session, p_semester);
    v_status := coalesce(r.status, 'NONE');
    w := CASE p_semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END;
    SELECT * INTO m FROM registration.student_menu(p_student, p_session, p_semester) x WHERE x.offering_id = p_offering LIMIT 1;

    ord := 1; rule := 'STUDENT_ACTIVE'; label := 'Student is active'; overridable := false; advisory := false;
    passed := coalesce(s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION'), false);
    message := CASE WHEN s.id IS NULL THEN 'No such student.' WHEN passed THEN 'The student is ' || lower(s.status) || '.'
                    ELSE 'A student who is ' || lower(s.status) || ' does not register.' END;
    RETURN NEXT;

    ord := 2; rule := 'SESSION'; label := 'Correct academic session';
    passed := EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_session);
    message := CASE WHEN passed THEN p_session || '.' ELSE 'No academic session ' || coalesce(p_session, '') || ' is on the calendar.' END;
    RETURN NEXT;

    ord := 3; rule := 'SEMESTER_RECORDS'; label := 'Semester not closed';
    passed := v_closed IS NULL;
    message := CASE WHEN passed THEN 'The ' || w || ' semester is ' || replace(coalesce(v_cal, 'not on the calendar'), '_', ' ') || '.'
                    ELSE 'The ' || w || ' semester of ' || p_session || ' is ' || v_closed || '; its registrations are history and are not changed.' END;
    RETURN NEXT;

    ord := 4; rule := 'COURSE_EXISTS'; label := 'Course exists';
    passed := o.id IS NOT NULL AND c.code IS NOT NULL;
    message := CASE WHEN passed THEN c.code || ' ' || c.title || ' (' || coalesce(o.units, c.units) || ' units).' ELSE 'No such course offering.' END;
    RETURN NEXT;

    ord := 5; rule := 'OFFERING_PERIOD'; label := 'Offered this session and semester';
    -- V380: and on the student's stream: a CCE student's class is the Centre's, a full-time student's a full-time class
    passed := o.id IS NOT NULL AND o.session = p_session AND o.semester = p_semester AND o.stream = people.student_stream(p_student);
    message := CASE WHEN o.id IS NULL THEN 'No such course offering.'
                    WHEN passed THEN 'Offered in ' || o.session || ', ' || w || ' semester' || CASE WHEN o.stream = 'CCE' THEN ', a class of the Centre for Continuing Education.' ELSE '.' END
                    WHEN o.session = p_session AND o.semester = p_semester AND o.stream = 'CCE'
                         THEN c.code || ' is offered here as a class of the Centre for Continuing Education; a full-time student registers on the full-time class.'
                    WHEN o.session = p_session AND o.semester = p_semester
                         THEN c.code || ' is offered here as a full-time class; a student of the Centre for Continuing Education registers on the Centre''s class.'
                    ELSE c.code || ' is offered in ' || o.session || ', ' || CASE o.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END
                         || ' semester — not in this registration''s session and semester.' END;
    RETURN NEXT;

    ord := 6; rule := 'COURSE_ACTIVE'; label := 'Course offering is active';
    passed := c.code IS NOT NULL AND c.state <> 'ENDED';
    message := CASE WHEN c.code IS NULL THEN 'No such course.' WHEN passed THEN 'The course is ' || lower(c.state) || '.' ELSE c.code || ' has ended (' || c.ended_on || ').' END;
    RETURN NEXT;

    ord := 7; rule := 'REGISTRATION_STATE'; label := 'Registration not locked';
    passed := v_status <> 'LOCKED';
    message := CASE WHEN v_status = 'NONE' THEN 'No registration yet; the engine drafts one.' WHEN passed THEN 'The registration is ' || lower(v_status) || '.'
                    ELSE 'This registration is locked and cannot be changed.' END;
    RETURN NEXT;

    ord := 8; rule := 'NOT_REGISTERED'; label := 'Not already on the registration';
    passed := NOT EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = r.id AND e.offering_id = p_offering AND e.status <> 'DROPPED');
    message := CASE WHEN passed THEN CASE WHEN EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = r.id AND e.offering_id = p_offering)
                                          THEN 'Dropped earlier; adding it restores it.' ELSE 'Not on the registration.' END
                    ELSE coalesce(c.code, 'The course') || ' is already on the registration.' END;
    RETURN NEXT;

    ord := 9; rule := 'PROGRAMME_LEVEL'; label := 'Offered to the student''s programme and level'; overridable := true;
    passed := m.offering_id IS NOT NULL AND (NOT m.carryover OR v_status IN ('NONE', 'DRAFT', 'RETURNED'));
    message := CASE WHEN passed THEN coalesce(m.basis, c.kind, '') || ' for ' || s.programme_code || ' at ' || s.current_level || ' level.'
                    WHEN m.offering_id IS NOT NULL THEN 'A carry-over is placed by the engine when the registration is drafted; this registration is ' || lower(v_status) || '.'
                    WHEN c.code IS NULL THEN 'No such course.'
                    ELSE c.code || ' is not on the engine''s menu for ' || s.programme_code || ' at ' || s.current_level || ' level (a ' || c.level || ' level '
                         || lower(c.kind) || ' course of ' || c.dept_code || ').' END;
    RETURN NEXT;
    overridable := false;

    ord := 10; rule := 'UNITS'; label := 'Maximum credit load';
    SELECT * INTO lim FROM registration.unit_limit(p_student, coalesce(r.level, s.current_level));   -- V380: the CCE course load
    v_units := CASE WHEN r.id IS NULL THEN 0 ELSE registration.units_of(r.id) END;
    v_add := coalesce(m.units, o.units, c.units, 0);
    passed := lim.level IS NULL OR v_units + v_add <= lim.max_units;
    message := CASE WHEN lim.level IS NULL THEN 'No unit limit is set for the level.'
                    WHEN passed THEN v_units || ' + ' || v_add || ' units, within the maximum of ' || lim.max_units || '.'
                    ELSE 'Adding it puts the registration at ' || (v_units + v_add) || ' units, over the maximum of ' || lim.max_units || ' at ' || lim.level
                         || ' level; drop a course first, or the Head of Department approves an overload.' END;
    RETURN NEXT;

    ord := 11; rule := 'REGISTRATION_WINDOW'; label := 'Registration window and late registration'; overridable := true;
    v_gate := registration.registration_gate(p_student, p_session, p_semester);
    passed := v_gate IS NULL;
    message := coalesce(v_gate, 'Open.');
    RETURN NEXT;

    ord := 12; rule := 'ADD_DROP_PERIOD'; label := 'Add and drop period';
    IF v_status IN ('SUBMITTED', 'APPROVED') THEN
        passed := registration.add_drop_open(p_student, p_session, p_semester);
        message := CASE WHEN passed THEN 'Open.' ELSE 'Add and drop is not open for ' || p_session || ' semester ' || p_semester
                                                       || '; it runs while the semester is open, up to the late-registration deadline.' END;
    ELSE
        passed := true; message := 'Not needed: the registration is not yet submitted.';
    END IF;
    RETURN NEXT;
    overridable := false;

    ord := 13; rule := 'FEES'; label := 'Payment requirement';
    IF v_status IN ('SUBMITTED', 'APPROVED') THEN
        BEGIN
            IF coalesce(finance.is_spillover(p_student), false) THEN
                -- V664: a spillover student's semester read with the course on it — the course is registered at once, so its fee first
                SELECT * INTO fp FROM finance.semester_position(p_student, p_session, p_semester, true);
                passed := fp.cleared;
                message := CASE WHEN passed THEN 'The ' || w || ' semester''s spillover fee is paid.'
                                ELSE 'The ' || w || ' semester''s spillover fee is not paid: ' || finance.naira(fp.outstanding) || ' outstanding ('
                                     || finance.naira(fp.due) || ' due up to the ' || w || ' semester, ' || finance.naira(fp.paid)
                                     || ' paid). The student pays it before a course is added to a submitted or approved registration; a payment for another semester does not cover it.' END;
            ELSE
                passed := coalesce(finance.clears(p_student, p_session, 'REGISTRATION'), false);
                message := CASE WHEN passed THEN 'The Bursary clears the student for registration.' ELSE 'The Bursary has not cleared the student for registration in ' || p_session
                                                                                                       || '; refresh the payment entitlement if a payment is confirmed, else escalate to the Bursary.' END;
            END IF;
        EXCEPTION WHEN check_violation THEN
            passed := false; message := SQLERRM;
        END;
    ELSE
        advisory := true; passed := true;
        IF coalesce(finance.is_spillover(p_student), false) THEN
            SELECT * INTO fp FROM finance.semester_position(p_student, p_session, p_semester, true);
            message := CASE WHEN fp.cleared THEN 'The ' || w || ' semester''s spillover fee is paid.'
                            ELSE 'The ' || w || ' semester''s spillover fee (' || finance.naira(fp.outstanding) || ' outstanding once a course of it is on the draft) is not paid: '
                                 || 'the course goes on the draft, but the engine refuses the submission until it is.' END;
        ELSE
            message := CASE WHEN finance.semester_cleared(p_student, p_session, p_semester) THEN 'The semester''s fees are cleared.'
                            ELSE 'The ' || w || ' semester''s fees are not cleared: the course goes on the draft, but the engine refuses the submission until they are.' END;
        END IF;
    END IF;
    RETURN NEXT;
    advisory := false;

    ord := 14; rule := 'GST'; label := 'GST/EPS requirement';
    v_gate := CASE WHEN c.code IS NULL THEN NULL ELSE registration.gst_gate(p_student, p_session, c.code) END;
    passed := v_gate IS NULL;
    message := coalesce(v_gate, CASE WHEN c.kind = 'GST' OR c.general_office IS NOT NULL THEN 'The GST fee is paid.' ELSE 'Not a GST/EPS course.' END);
    RETURN NEXT;

    -- V482: checked against the student's passed courses; advisory, or a rule the support override may set aside where the
    -- Academic Office enforces prerequisites (a carry-over is a course already taken and is never held to them)
    ord := 15; rule := 'PREREQUISITES'; label := 'Prerequisites';
    v_mode := registration.prerequisite_mode();
    SELECT string_agg(p.requires_code, ', ' ORDER BY p.requires_code) INTO v_pre FROM catalogue.course_prerequisite p WHERE p.course_code = c.code;
    v_unmet := CASE WHEN v_pre IS NULL THEN '{}'::text[] ELSE registration.prerequisites_unmet(p_student, c.code) END;
    IF v_mode = 'ENFORCED' AND NOT coalesce(m.carryover, false) THEN
        advisory := false; overridable := true; passed := cardinality(v_unmet) = 0;
    ELSE
        advisory := true; overridable := false; passed := true;
    END IF;
    message := CASE WHEN v_pre IS NULL THEN 'None recorded.'
                    WHEN cardinality(v_unmet) = 0 THEN 'Recorded: ' || v_pre || '; each is passed, or below the level the student entered at.'
                    WHEN v_mode = 'ENFORCED' AND NOT coalesce(m.carryover, false)
                         THEN 'Not yet passed: ' || array_to_string(v_unmet, ', ') || '. The Academic Office enforces prerequisites; the override sets this aside where the student passed it and the result is not yet published, or was exempted.'
                    ELSE 'Not yet passed: ' || array_to_string(v_unmet, ', ') || '. Prerequisites are advisory: the engine shows them; it does not refuse on them.' END;
    RETURN NEXT;
    advisory := true; overridable := false; passed := true;

    ord := 16; rule := 'CORE_ELECTIVE'; label := 'Core or elective';
    message := CASE WHEN c.code IS NULL THEN '—' ELSE coalesce(m.basis, c.kind) || CASE WHEN c.kind = 'Elective' THEN ' — counts within the elective allowance.' ELSE '.' END END;
    RETURN NEXT;
END $function$;

-- ── 6 · the student's panel: each semester's own fee, the payments applied to it, what is left, and its state ──
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
              WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'),
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
COMMENT ON FUNCTION finance.spillover_panel(uuid, text) IS 'V637, V664: a spillover student''s position for a session as the Fees page, the dashboard and Course Registration show it — the SP year; each semester''s spillover fee (as it applies once a course is registered in it), whether one is, its carry-over courses by the session and semester they were failed in, and (V664) its own amount owed, the payments applied to it (the whole-session item first, then the first semester, then the second, as the registration gate reads them), what is left and its state — PAID, PART_PAID, PAYMENT_REQUIRED, NOT_STATED, NOT_REGISTERED (carry-overs, nothing registered), NOTHING_OWED; any whole-session spillover line; due, paid, balance. NULL for a student not in spillover.';

-- ── 7 · a spillover student's registration submitted or approved with no course on it: a draft again ──
-- The door V664 closes left such registrations behind: a course added to one now waits for the semester's fee, which is owed only once a
-- course of the semester is on a registration — so the student could neither add nor pay. As a draft its courses go on, the fee falls
-- due, it is paid, and the submission is judged as anyone's. A reset record keeps what it was; a locked registration, or one of a closed
-- semester, is left as it is.
WITH empty AS (
    SELECT cr.* FROM registration.course_registration cr
     WHERE cr.status IN ('SUBMITTED', 'APPROVED')
       AND NOT EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))
       AND coalesce(finance.is_spillover(cr.student_id), false)
       AND registration.semester_closed(cr.student_id, cr.session, cr.semester) IS NULL),
kept AS (
    INSERT INTO registration.registration_reset (registration_id, student_id, session, semester, previous_status, previous_approval_mode, level,
                                                 courses, course_count, units, kept, reason, source, reset_by, reset_office)
    SELECT e.id, e.student_id, e.session, e.semester, e.status, e.approval_mode, e.level,
           coalesce((SELECT jsonb_agg(jsonb_build_object('courseCode', o.course_code, 'units', x.units, 'entryType', x.entry_type, 'status', x.status) ORDER BY o.course_code)
                       FROM registration.entry x JOIN catalogue.offering o ON o.id = x.offering_id WHERE x.registration_id = e.id), '[]'::jsonb),
           0, 0, '[]'::jsonb,
           'V664: a spillover student''s registration submitted with no course on it is a draft again — its courses wait for the semester''s spillover fee',
           'ACADEMIC_OFFICE', NULL, 'academic'
      FROM empty e
    RETURNING registration_id)
UPDATE registration.course_registration cr
   SET status = 'DRAFT', submitted_at = NULL, approved_at = NULL, approved_by = NULL, approval_mode = NULL, returned_comment = NULL
  FROM kept WHERE cr.id = kept.registration_id;

COMMENT ON FUNCTION registration.student_add(uuid, text, integer, uuid) IS
  'A student''s course added to their registration — on a draft as chosen, on a registration submitted or approved during add and drop (registered at once); V664: a spillover student''s course on a submitted or approved registration waits for the semester''s spillover fee (registration.semester_fee_gate), on a draft the submission waits for it';
COMMENT ON FUNCTION registration.submit_checks(uuid) IS
    'what a submission must satisfy: the session''s and the semester''s school fees stated and cleared (V664: the refusal with what is outstanding, due and paid), the GST fee where the University holds the '
    'registration on it, a course on it where no minimum would stop an empty one (V664: REG_NO_COURSES), the curriculum''s or the level''s minimum load (V597: of a registration with a current course of the programme only), the '
    'maximum, the probation ceiling and the SIWES semester''s exact load';

COMMIT;
