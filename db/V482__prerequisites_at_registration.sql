-- ═══════════════════════════════════════
-- V482 — Prerequisites at registration
--
-- A course's prerequisites (catalogue.course_prerequisite, V338) were shown and never checked: the ICT Support checks said
-- "The engine shows them; it does not refuse on them". Whether registration refuses a course whose prerequisite the student
-- has not passed is the Academic Office's rule, so it is a switch, and it starts where the University is today:
--
--   registration.prerequisite_policy   one row: ADVISORY (as before: shown, never refused) or ENFORCED, who set it, when, why.
--   registration.prerequisite_mode()   the rule in force (ADVISORY when no row).
--   registration.set_prerequisite_mode(mode, reason)   the Academic Office (academic, registrar, dregistrar, super) sets it.
--   registration.prerequisites_unmet(student, course)   the course's prerequisites the student has not passed: a published,
--       graded result above 0 points on the course itself, the code a merged course was absorbed from (course_alias) or its
--       BSU-/MOAU- twin; a prerequisite below the level the student entered at (a Direct Entry or postgraduate student never
--       took it) is met.
--
-- Under ENFORCED the student's own form (student_choose) and add/drop (student_add) refuse such a course with
-- REG_PREREQUISITE, naming the courses; carry-overs and deferred courses are never held to it. The ICT Support checks
-- (support_add_checks) read the same function: under ADVISORY the rule is advisory and says which are not yet passed; under
-- ENFORCED it is a rule the support override sets aside on the student's ticket (a pass not yet published, an exemption).
-- The three functions are restated from their current definitions with only these changes.
--
-- The switch is ADVISORY on deploy: nothing a student does is refused by this migration.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V482: prerequisites at registration', true);

CREATE TABLE registration.prerequisite_policy (
    id             boolean PRIMARY KEY DEFAULT true CHECK (id),
    mode           text NOT NULL DEFAULT 'ADVISORY' CHECK (mode IN ('ADVISORY', 'ENFORCED')),
    changed_by     uuid,
    changed_office text,
    changed_at     timestamptz NOT NULL DEFAULT now(),
    reason         text NOT NULL CHECK (btrim(reason) <> '')
);
INSERT INTO registration.prerequisite_policy (mode, reason) VALUES ('ADVISORY', 'V482: as before — prerequisites are shown at registration and never refused');
SELECT audit.attach('registration.prerequisite_policy');
COMMENT ON TABLE registration.prerequisite_policy IS
  'V482: whether registration refuses a course whose prerequisite the student has not passed — ADVISORY (shown, never refused) or ENFORCED; the Academic Office''s rule, one row.';

CREATE FUNCTION registration.prerequisite_mode() RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT p.mode FROM registration.prerequisite_policy p), 'ADVISORY')
$$;
COMMENT ON FUNCTION registration.prerequisite_mode() IS 'V482: ADVISORY or ENFORCED — whether registration refuses a course whose prerequisite is not passed.';

CREATE FUNCTION registration.set_prerequisite_mode(p_mode text, p_reason text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v_mode text := upper(btrim(coalesce(p_mode, ''))); v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF v_mode NOT IN ('ADVISORY', 'ENFORCED') THEN
        RAISE EXCEPTION 'PREREQUISITE_MODE_UNKNOWN: the rule is ADVISORY or ENFORCED' USING ERRCODE = '23514';
    END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'PREREQUISITE_MODE_REASON: say why the rule changes' USING ERRCODE = '23514';
    END IF;
    IF v_office IS NULL OR v_office NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'PREREQUISITE_MODE_OFFICE: the Academic Office sets whether prerequisites are enforced' USING ERRCODE = '23514';
    END IF;
    INSERT INTO registration.prerequisite_policy (id, mode, changed_by, changed_office, changed_at, reason)
    VALUES (true, v_mode, nullif(current_setting('moaum.actor_id', true), '')::uuid, v_office, now(), btrim(p_reason))
    ON CONFLICT (id) DO UPDATE SET mode = EXCLUDED.mode, changed_by = EXCLUDED.changed_by, changed_office = EXCLUDED.changed_office,
                                   changed_at = EXCLUDED.changed_at, reason = EXCLUDED.reason;
    RETURN v_mode;
END $$;
COMMENT ON FUNCTION registration.set_prerequisite_mode(text, text) IS 'V482: the Academic Office sets prerequisites ADVISORY or ENFORCED, with the reason.';

CREATE FUNCTION registration.prerequisites_unmet(p_student uuid, p_course text) RETURNS text[]
LANGUAGE sql STABLE AS $$
    WITH req AS (SELECT p.requires_code FROM catalogue.course_prerequisite p WHERE p.course_code = p_course),
    st AS (SELECT s.programme_code, s.entry_level FROM people.student s WHERE s.id = p_student),
    passed AS (SELECT DISTINCT f.course_code FROM assessment.student_results(p_student) f
                WHERE EXISTS (SELECT 1 FROM req) AND f.published AND f.outcome = 'GRADED' AND f.points > 0)
    SELECT coalesce(array_agg(q.requires_code ORDER BY q.requires_code), '{}'::text[])
      FROM req q
     WHERE NOT EXISTS (SELECT 1 FROM passed x
                        WHERE x.course_code = q.requires_code
                           OR x.course_code = catalogue.twin_by_code(q.requires_code)
                           OR x.course_code IN (SELECT a.alias_code FROM catalogue.course_alias a WHERE a.course_code = q.requires_code))
       -- below the level the student entered at: a Direct Entry or postgraduate student never took it
       AND NOT EXISTS (SELECT 1 FROM st, catalogue.course c
                        WHERE c.code = q.requires_code AND st.entry_level IS NOT NULL
                          AND coalesce((SELECT min(co.level) FROM catalogue.course_offer co WHERE co.course_code = c.code AND co.programme_code = st.programme_code), c.level) < st.entry_level)
$$;
COMMENT ON FUNCTION registration.prerequisites_unmet(uuid, text) IS
  'V482: the course''s prerequisites the student has not passed (a published graded result above 0 points on it, its twin or a code merged into it); one below the student''s entry level is met.';

CREATE OR REPLACE FUNCTION registration.student_choose(p_registration uuid, p_offerings uuid[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; m record; n int := 0; v_gate text; v_unmet text[];
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status NOT IN ('DRAFT','RETURNED') THEN
        RAISE EXCEPTION 'this registration is %; it is not edited', lower(r.status) USING ERRCODE = '23514',
            HINT = 'A submitted registration is changed by the level adviser returning it.';
    END IF;
    DELETE FROM registration.entry WHERE registration_id = p_registration AND entry_type NOT IN ('CARRYOVER','DEFERRED') AND support_override_at IS NULL;
    -- a deferred course or a carry-over that has since become due is added to a draft that predates it
    FOR m IN SELECT * FROM registration.student_menu(r.student_id, r.session, r.semester) WHERE carryover LOOP
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (p_registration, m.offering_id, m.units, CASE WHEN m.deferred THEN 'DEFERRED' ELSE 'CARRYOVER' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
    END LOOP;
    FOR m IN SELECT * FROM registration.student_menu(r.student_id, r.session, r.semester) WHERE NOT carryover AND offering_id = ANY(p_offerings) LOOP
        -- V314: a GST or EPS course is registered only by a student whose GST fee is paid
        v_gate := registration.gst_gate(r.student_id, r.session, m.course_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; registration opens the moment the payment is confirmed.';
        END IF;
        -- V482: where the Academic Office enforces prerequisites, a course whose prerequisite the student has not passed is refused
        IF registration.prerequisite_mode() = 'ENFORCED' THEN
            v_unmet := registration.prerequisites_unmet(r.student_id, m.course_code);
            IF cardinality(v_unmet) > 0 THEN
                RAISE EXCEPTION 'REG_PREREQUISITE: % needs % passed first; no published pass is on your record', m.course_code, array_to_string(v_unmet, ', ')
                    USING ERRCODE = '23514', HINT = 'If you passed it and the result is not yet published, or were exempted, your department asks ICT Support to add the course on your ticket.';
            END IF;
        END IF;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (p_registration, m.offering_id, m.units,
                CASE WHEN m.basis = 'GST' OR m.kind = 'GST' THEN 'GST' WHEN m.basis = 'Borrowed' THEN 'BORROWED'
                     WHEN m.basis = 'Elective' OR m.kind = 'Elective' THEN 'ELECTIVE' ELSE 'CURRENT' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        n := n + 1;
    END LOOP;
    RETURN registration.units_of(p_registration);
END $function$;

CREATE OR REPLACE FUNCTION registration.student_add(p_student uuid, p_session text, p_semester integer, p_offering uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; m record; lim policy.level_limit; v_units int; v_type text; v_status text; v_gate text; v_unmet text[];
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF NOT FOUND THEN RAISE EXCEPTION 'register first, then add or drop' USING ERRCODE = '23514'; END IF;
    IF r.status = 'LOCKED' THEN RAISE EXCEPTION 'this registration is locked and cannot be changed' USING ERRCODE = '23514'; END IF;
    IF NOT registration.add_drop_open(p_student, p_session, p_semester) THEN   -- V380: by the student's calendar
        RAISE EXCEPTION 'add and drop is not open for % semester %', p_session, p_semester USING ERRCODE = '23514',
            HINT = 'It runs while the semester is open, up to the late-registration deadline set by the Registry.';
    END IF;
    IF NOT finance.clears(p_student, p_session, 'REGISTRATION') THEN
        RAISE EXCEPTION 'the Bursary has not cleared you for registration in %', p_session USING ERRCODE = '23514';
    END IF;

    SELECT * INTO m FROM registration.student_menu(p_student, p_session, p_semester) WHERE offering_id = p_offering AND NOT carryover;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'that course is not offered to your programme at your level this semester' USING ERRCODE = '23514';
    END IF;
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
                   WHEN m.basis = 'Elective' OR m.kind = 'Elective' THEN 'ELECTIVE' ELSE 'CURRENT' END;
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
        UPDATE registration.entry SET status = v_status, units = v_units, entry_type = v_type
         WHERE registration_id = r.id AND offering_id = p_offering;
    ELSE
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
        VALUES (r.id, p_offering, v_units, v_type, v_status);
    END IF;
    RETURN registration.units_of(r.id);
END $function$;

CREATE OR REPLACE FUNCTION registration.support_add_checks(p_student uuid, p_session text, p_semester integer, p_offering uuid)
 RETURNS TABLE(ord integer, rule text, label text, passed boolean, overridable boolean, advisory boolean, message text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s people.student; o catalogue.offering; c catalogue.course; r registration.course_registration; v_closed text; v_cal text; m record;
        lim policy.level_limit; v_status text; v_units int; v_add int; v_gate text; v_pre text; w text; v_mode text; v_unmet text[];
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
            passed := coalesce(finance.clears(p_student, p_session, 'REGISTRATION'), false);
            message := CASE WHEN passed THEN 'The Bursary clears the student for registration.' ELSE 'The Bursary has not cleared the student for registration in ' || p_session
                                                                                                   || '; refresh the payment entitlement if a payment is confirmed, else escalate to the Bursary.' END;
        EXCEPTION WHEN check_violation THEN
            passed := false; message := SQLERRM;
        END;
    ELSE
        advisory := true; passed := true;
        message := CASE WHEN finance.semester_cleared(p_student, p_session, p_semester) THEN 'The semester''s fees are cleared.'
                        ELSE 'The ' || w || ' semester''s fees are not cleared: the course goes on the draft, but the engine refuses the submission until they are.' END;
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

COMMIT;
