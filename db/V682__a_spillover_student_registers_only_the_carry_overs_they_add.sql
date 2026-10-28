-- ═══════════════════════════════════════
-- V682 — A spillover student registers only the carry-overs they add, and sees the semester's spillover fee as they pick them
--
-- The University's word of 28 October 2026: "spill over student should never see list of courses to register, they should only
-- see a button to add carry overs, and let all the courses they are adding should carry a status carry over, ones a course is
-- selected they must see a the amount they are supposed to pay for that semester". Asked whether the carry-overs a spillover
-- student's published results state should still go on the registration by themselves, the University chose: the student picks
-- each one.
--
-- Since V674 every course on a spillover student's registration of their current session is a carry-over, and the page offers no
-- fresh course. But the registration still listed the carry-overs the published results state ("added automatically, cannot be
-- removed"), and the draft placed them all on it as soon as it was made — the student adding one course through ADD CARRY-OVER got
-- every failed course of the semester with it, and could not take one off. The picker never said what the semester would cost.
--
-- Now, for a spillover registration (registration.spillover_registration, V674):
--   1. registration.student_draft makes it empty: no carry-over is placed on it by itself. The picker lists the courses the
--      results state first (ONLY OUTSTANDING); the student ticks the ones they register.
--   2. registration.student_choose (a save) places no carry-over either, and a course the student no longer chooses comes off,
--      a carry-over the results state among them (only ICT Support's ticketed additions stay, as for everyone).
--   3. registration.student_reset clears every course of it (ticketed additions stay).
--   4. finance.spillover_semester_quote(student, session, semester): what registering a course in the semester costs — the
--      semester's own spillover fee, the whole-session spillover item where no semester is registered yet, what the semester's
--      registration then needs paid (finance.semester_position read as registered, V664: anything earlier left unpaid and its own,
--      less the session's school-fee payments), whether it is already owed, whether a fee is stated. Null for anyone else.
--      GET /me/registration/carry-overs carries it; the picker shows it as soon as a course is ticked.
-- Unchanged: a student not in spillover (their results' carry-overs placed and kept, V504/V611); add and drop (a carry-over the
-- results state is still repeated, not dropped); the trigger that makes every spillover course a carry-over (V674); the fee rules
-- (V616, V637, V664). A spillover draft made before this keeps what is on it; the student can now take a course off it.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V682: a spillover student registers only the carry-overs they add', true);

-- ── 1. the draft ───────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.student_draft(p_student uuid, p_session text, p_semester integer)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v uuid; s people.student; m record;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
    -- V602/V604: a graduated record is closed to course registration (and so to carry-overs) on every path; every other status is
    -- judged where it always was — the student's own doors in the API, the deferment and support engines in theirs
    IF s.status = 'GRADUATED' THEN
        RAISE EXCEPTION 'REG_STUDENT_NOT_ELIGIBLE: Course registration is unavailable because this academic record has been graduated.'
            USING ERRCODE = '23514';
    END IF;
    -- V665: and so is a record whose award is approved, for a session after its graduation session: the final clearance is under way
    IF records.awaiting_final_clearance(p_student) AND p_session > records.graduation_session(p_student) THEN
        RAISE EXCEPTION 'REG_STUDENT_NOT_ELIGIBLE: Course registration is unavailable: the award is approved and the final clearance is under way.'
            USING ERRCODE = '23514';
    END IF;
    SELECT id INTO v FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF v IS NOT NULL THEN RETURN v; END IF;
    v := gen_random_uuid();
    INSERT INTO registration.course_registration (id, student_id, session, semester, level)
    VALUES (v, p_student, p_session, p_semester, s.current_level);
    -- V682: a spillover student's registration holds only the courses they add with ADD CARRY-OVER: the carry-overs the published
    -- results state are listed first in the picker, and none is placed here on its own
    IF registration.spillover_registration(p_student, p_session) THEN RETURN v; END IF;
    FOR m IN SELECT * FROM registration.student_menu(p_student, p_session, p_semester) WHERE carryover LOOP
        -- V512: a GST/EPS carry-over waits for the GST fee: being a carry-over does not pass it
        IF registration.gst_course_hold(p_student, p_session, m.course_code) IS NOT NULL THEN CONTINUE; END IF;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (v, m.offering_id, m.units, CASE WHEN m.deferred THEN 'DEFERRED' ELSE 'CARRYOVER' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        IF FOUND THEN PERFORM registration.gst_course_registered(v, m.offering_id); END IF;
    END LOOP;
    RETURN v;
END $function$;

COMMENT ON FUNCTION registration.student_draft(uuid, text, integer) IS
  'The student''s registration for the session and semester, made where there is none: the carry-overs and deferred courses due placed on it (a GST/EPS one once the GST fee is paid; V512); refused for a graduated record (V602/V604) and, after the graduation session, a record awaiting the final clearance (V665). V682: a spillover registration (V674) is made empty — the student adds each course with ADD CARRY-OVER.';

-- ── 2. a save ────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.student_choose(p_registration uuid, p_offerings uuid[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; m record; n int := 0; v_gate text; v_unmet text[];
        v_added jsonb; v_menu uuid[]; v_code text; ctx record; v_ctx boolean := false; x record; v_units int; v_spill boolean;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status NOT IN ('DRAFT','RETURNED') THEN
        RAISE EXCEPTION 'this registration is %; it is not edited', lower(r.status) USING ERRCODE = '23514',
            HINT = 'A submitted registration is changed by the level adviser returning it.';
    END IF;
    -- V682: a spillover student's registration (V674) holds only the courses they chose: a carry-over the results state is not
    -- placed on it by a save, and one they no longer choose comes off it like any other course
    v_spill := registration.spillover_registration(r.student_id, r.session);
    -- V518: only the registration's own session and semester are chosen from: a screen switched from another semester could send that
    -- semester's courses with this one's (a first-semester course then refused as "already on your registration for another
    -- semester"); an offering of another session or semester is never this registration's, so it is left out rather than refused
    p_offerings := ARRAY(SELECT DISTINCT o.id FROM catalogue.offering o
                          WHERE o.id = ANY (coalesce(p_offerings, '{}'::uuid[])) AND o.session = r.session AND o.semester = r.semester);
    -- V504: when each course the student added beside the menu was first added, kept across saves
    SELECT coalesce(jsonb_object_agg(e.offering_id::text, e.student_added_at), '{}'::jsonb) INTO v_added
      FROM registration.entry e WHERE e.registration_id = p_registration AND e.student_added_at IS NOT NULL;
    -- V611: a carry-over the student declared is the student's choice, kept only while chosen; one the results state stays
    -- V620: an entry already on the registration and still chosen is kept as it was registered — its units, its type and the
    -- programme's basis for the course at the time (registration.entry.basis) — whatever its binding has become since, or whether it
    -- is still bound at all; only an entry the student no longer chooses goes
    -- V621: a course dropped (or withdrawn) stays on the registration as it is through a save that leaves it out — never deleted —
    -- and a dropped one chosen again is restored in place, as it was registered (the support desk's restore and the student's own tick)
    DELETE FROM registration.entry WHERE registration_id = p_registration AND support_override_at IS NULL
       AND NOT offering_id = ANY (p_offerings)
       AND status NOT IN ('DROPPED', 'WITHDRAWN')
       AND (entry_type NOT IN ('CARRYOVER','DEFERRED') OR added_as = 'CARRY_OVER_DECLARED' OR v_spill);
    UPDATE registration.entry SET status = 'REGISTERED'
     WHERE registration_id = p_registration AND offering_id = ANY (p_offerings) AND status = 'DROPPED';
    -- V512: a GST/EPS carry-over put on the draft before the GST fee was paid comes off it while the fee is owed (not one ICT Support
    -- put on the student's ticket)
    DELETE FROM registration.entry e USING catalogue.offering o
     WHERE e.registration_id = p_registration AND o.id = e.offering_id AND e.entry_type IN ('CARRYOVER', 'DEFERRED') AND e.support_override_at IS NULL
       AND registration.gst_course_hold(r.student_id, r.session, o.course_code) IS NOT NULL;
    -- a deferred course or a carry-over that has since become due is added to a draft that predates it — a GST/EPS one once the fee is paid
    FOR m IN SELECT * FROM registration.student_menu(r.student_id, r.session, r.semester) WHERE carryover AND NOT v_spill LOOP
        IF registration.gst_course_hold(r.student_id, r.session, m.course_code) IS NOT NULL THEN CONTINUE; END IF;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (p_registration, m.offering_id, m.units, CASE WHEN m.deferred THEN 'DEFERRED' ELSE 'CARRYOVER' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        IF FOUND THEN PERFORM registration.gst_course_registered(p_registration, m.offering_id); END IF;
    END LOOP;
    SELECT coalesce(array_agg(mm.offering_id), '{}'::uuid[]) INTO v_menu FROM registration.student_menu(r.student_id, r.session, r.semester) mm;
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
        -- V504: the programme's own setup (course_offer.basis) types it, as registration.is_elective_for reads it — a course the
        -- programme takes as core is core here though its own department offers it as an elective
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (p_registration, m.offering_id, m.units,
                CASE WHEN m.basis = 'GST' OR m.kind = 'GST' THEN 'GST' WHEN m.basis = 'Borrowed' THEN 'BORROWED'
                     WHEN m.basis = 'Elective' OR (m.basis IS NULL AND m.kind = 'Elective') THEN 'ELECTIVE' ELSE 'CURRENT' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        IF FOUND AND m.kind = 'GST' THEN PERFORM registration.gst_course_registered(p_registration, m.offering_id); END IF;
        n := n + 1;
    END LOOP;
    -- V504: a course beside the menu is kept only when the engine still allows it (registration.course_check); the record is
    -- read once for all of them
    FOR v_code IN SELECT o.course_code FROM catalogue.offering o
                   WHERE o.id = ANY (p_offerings) AND NOT o.id = ANY (v_menu)
                     AND NOT EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = p_registration AND e.offering_id = o.id)
                   ORDER BY o.course_code LOOP
        IF NOT v_ctx THEN SELECT * INTO ctx FROM registration.course_context(r.student_id, r.session, r.semester); v_ctx := true; END IF;
        SELECT * INTO x FROM registration.course_check(r.student_id, r.session, r.semester, v_code, ctx.passed, ctx.awaited, ctx.carry, ctx.other_semester);
        IF x.refusal IS NOT NULL THEN
            RAISE EXCEPTION '%', x.refusal USING ERRCODE = '23514', HINT = 'Remove ' || v_code || ' from your selection and save again.';
        END IF;
        IF NOT x.offering_id = ANY (p_offerings) THEN CONTINUE; END IF;   -- another stream's class of the course: not the student's
        -- V314: the GST fee owed holds every course the student registers, as on the menu (registration.gst_gate)
        v_gate := registration.gst_gate(r.student_id, r.session, v_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; registration opens the moment the payment is confirmed.';
        END IF;
        SELECT catalogue.units_for(v_code, s.programme_code, NULL) INTO v_units FROM people.student s WHERE s.id = r.student_id;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, student_added_at, added_as)
        VALUES (p_registration, x.offering_id, v_units,
                CASE x.category WHEN 'CARRY_OVER' THEN 'CARRYOVER' WHEN 'GST' THEN 'GST' WHEN 'ELECTIVE' THEN 'ELECTIVE' ELSE 'CURRENT' END,
                coalesce((v_added ->> x.offering_id::text)::timestamptz, now()), x.added_as)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        IF FOUND THEN PERFORM registration.gst_course_registered(p_registration, x.offering_id); END IF;
        n := n + 1;
    END LOOP;
    RETURN registration.units_of(p_registration);
END $function$;

COMMENT ON FUNCTION registration.student_choose(uuid, uuid[]) IS
  'V504, V512, V518, V611, V620, V621: the student''s choice saved on a draft — the menu''s courses chosen, the carry-overs and deferred courses due kept or added, a course beside the menu kept while the engine allows it, a declared carry-over only while chosen; an entry already on the registration and still chosen is kept as it was registered, whatever its binding has become (V620); a dropped entry stays on the record and is restored in place when chosen again (V621). V682: on a spillover registration (V674) no carry-over is placed by a save, and every course no longer chosen comes off (a ticketed addition stays).';

-- ── 3. a reset ───────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.student_reset(p_student uuid, p_session text, p_semester integer, p_reason text, p_source text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; v_courses jsonb; v_kept jsonb; n int; u int; removable int; v_id uuid; v_sem text; v_why text; v_spill boolean;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester FOR UPDATE;
    -- V682: a spillover student's courses are all their own choice, the carry-overs the results state among them: a reset clears them all
    v_spill := registration.spillover_registration(p_student, p_session);
    v_why := registration.reset_refusal(p_student, p_session, p_semester, p_source);
    IF v_why IS NOT NULL THEN
        RAISE EXCEPTION '%', v_why USING ERRCODE = '23514',
            HINT = 'A registration with marks, a locked one or a closed semester''s is part of the record; ICT Support adds or drops a course on a ticket.';
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object('courseCode', o.course_code, 'title', c.title, 'units', e.units, 'entryType', e.entry_type,
                                                 'status', e.status, 'offeringId', e.offering_id, 'supportOverride', e.support_override_at IS NOT NULL)
                              ORDER BY o.course_code), '[]'::jsonb),
           count(*) FILTER (WHERE e.status NOT IN ('DROPPED', 'WITHDRAWN')),
           coalesce(sum(e.units) FILTER (WHERE e.status NOT IN ('DROPPED', 'WITHDRAWN')), 0),
           count(*) FILTER (WHERE (e.entry_type NOT IN ('CARRYOVER', 'DEFERRED') OR e.added_as = 'CARRY_OVER_DECLARED' OR v_spill) AND e.support_override_at IS NULL)
      INTO v_courses, n, u, removable
      FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id LEFT JOIN catalogue.course c ON c.code = o.course_code
     WHERE e.registration_id = r.id;
    -- a second reset of a registration already clear does nothing (a second click, a retried request)
    IF r.status = 'DRAFT' AND removable = 0 THEN
        RETURN jsonb_build_object('reset', false, 'alreadyClear', true, 'registrationId', r.id, 'courses', n);
    END IF;
    -- the chosen courses go exactly as choosing courses again removes them; carryovers, deferred courses and ICT Support's
    -- ticketed additions stay, back to REGISTERED. V611: a carry-over the student declared goes with the chosen courses
    DELETE FROM registration.entry WHERE registration_id = r.id AND support_override_at IS NULL
       AND (entry_type NOT IN ('CARRYOVER', 'DEFERRED') OR added_as = 'CARRY_OVER_DECLARED' OR v_spill);
    UPDATE registration.entry SET status = 'REGISTERED' WHERE registration_id = r.id AND status = 'APPROVED';
    SELECT coalesce(jsonb_agg(jsonb_build_object('courseCode', o.course_code, 'units', e.units, 'entryType', e.entry_type) ORDER BY o.course_code), '[]'::jsonb)
      INTO v_kept FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id WHERE e.registration_id = r.id;
    UPDATE registration.course_registration
       SET status = 'DRAFT', submitted_at = NULL, approved_at = NULL, approved_by = NULL, approval_mode = NULL, returned_comment = NULL
     WHERE id = r.id;
    UPDATE registration.approval_review SET cleared_at = now() WHERE registration_id = r.id AND cleared_at IS NULL;
    INSERT INTO registration.registration_reset (registration_id, student_id, session, semester, previous_status, previous_approval_mode, level,
                                                 courses, course_count, units, kept, reason, source, reset_by, reset_office)
    VALUES (r.id, r.student_id, r.session, r.semester, r.status, r.approval_mode, r.level, v_courses, n, u, v_kept,
            coalesce(nullif(btrim(p_reason), ''), 'Reset to register the courses again'), p_source,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    RETURNING id INTO v_id;
    v_sem := CASE r.semester WHEN 1 THEN 'first semester' WHEN 2 THEN 'second semester' ELSE 'third semester' END;
    PERFORM platform.tell_student(r.student_id, 'REG_RESET', NULL, jsonb_build_object('SESSION', r.session, 'SEMESTER', v_sem), 'REG_RESET:' || v_id);
    RETURN jsonb_build_object('reset', true, 'resetId', v_id, 'registrationId', r.id, 'previousStatus', r.status, 'courses', n, 'units', u,
                              'kept', jsonb_array_length(v_kept));
END $function$;

COMMENT ON FUNCTION registration.student_reset(uuid, text, integer, text, text) IS
  'V491: a course registration cleared to register again — never a locked one, a closed semester''s, or one with a mark entered; the registration as it stood kept on registration.registration_reset; the chosen courses removed as choosing again removes them (carryovers, deferred courses and ticketed additions stay); back to DRAFT; the student told. V682: on a spillover registration (V674) every course goes, the carry-overs the results state among them (ticketed additions stay).';

-- ── 4. what the semester costs once a course is registered in it ───────────────────────────────────────────────────────────
CREATE FUNCTION finance.spillover_semester_quote(p_student uuid, p_session text, p_semester integer)
RETURNS jsonb
LANGUAGE plpgsql AS $fn$
DECLARE sp jsonb; sem jsonb; fp record; v_fee numeric; v_ses numeric;
BEGIN
    IF NOT registration.spillover_registration(p_student, p_session) THEN RETURN NULL; END IF;
    sp := finance.spillover_panel(p_student, p_session);
    IF sp IS NULL THEN RETURN NULL; END IF;
    SELECT x INTO sem FROM jsonb_array_elements(sp -> 'semesters') x WHERE (x ->> 'semester')::int = p_semester;
    -- the semester read as registered (V664): its spillover lines, and a whole-session one, owed as they are once a course of it is on
    SELECT * INTO fp FROM finance.semester_position(p_student, p_session, p_semester, true);
    v_fee := coalesce((sem ->> 'fee')::numeric, 0);
    v_ses := CASE WHEN jsonb_array_length(coalesce(sp -> 'registeredSemesters', '[]'::jsonb)) = 0 THEN coalesce((sp ->> 'sessionFee')::numeric, 0) ELSE 0 END;
    RETURN jsonb_build_object(
        'session', p_session, 'semester', p_semester, 'label', sp ->> 'label',
        'registered', coalesce((sem ->> 'registered')::boolean, false),
        'fee', v_fee, 'sessionFee', v_ses, 'charge', v_fee + v_ses,
        'due', fp.due, 'paid', fp.paid, 'toPay', fp.outstanding, 'cleared', fp.cleared,
        'stated', v_fee + v_ses > 0 OR fp.due > 0);
END $fn$;
COMMENT ON FUNCTION finance.spillover_semester_quote(uuid, text, integer) IS
  'V682: for a spillover registration (V674), what registering a course in the semester costs: the semester''s own spillover fee (fee), the whole-session spillover item owed with the first semester registered (sessionFee), their sum (charge), the semester read as registered (finance.semester_position, V664): due up to it, the session''s school-fee payments, what is still to pay for its registration (toPay) and whether it is cleared; registered when a course of it is on the registration already (its fee owed); stated when any fee applies. Null for any other student. The carry-over picker shows it once a course is ticked.';

COMMIT;
