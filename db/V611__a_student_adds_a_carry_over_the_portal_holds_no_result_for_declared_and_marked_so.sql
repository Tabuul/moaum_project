-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V611 — A student adds a carry-over the portal holds no result for, declared and marked so
--
--   A course was owed (a carry-over) only when a published result on the portal said F (registration.carryovers), and a course
--   registered before with no published result was refused (REG_RESULT_AWAITED, V504) lest a pass be pending. The registrations of
--   2022/2023 to 2024/2025 came from the old portal with their results left there: on the live-shaped copy 26,930 students hold
--   417,121 courses of 2024/2025 and 508 score sheets of that session were ever published here, so a continuing student's every
--   earlier course read "result pending" for ever and no carry-over could be registered without ICT Support.
--     · registration.course_context: a course registered in an earlier SESSION that holds NO RESULT of the student on the portal — no
--       score sheet of it, or a published sheet the student is not on (the result is on the old portal) — with no published result
--       since and not passed, is offered as a carry-over the student may declare (in carry, out of awaited). A result on its way here
--       stays awaited: a score sheet of it not yet published, a result held (withheld, malpractice), or a registration earlier in the
--       same session. The student in the report (BSU/AR/ENG/23/67049) held 35 earlier courses, none with a result of hers here.
--     · registration.course_check: such a carry-over is judged as one (category CARRY_OVER, the class of this semester, every
--       carry-over rule) and marked added_as CARRY_OVER_DECLARED with its why; a carry-over with a published F is unchanged.
--     · registration.entry.added_as admits CARRY_OVER_DECLARED, so the entry says the student declared it (the department, the record).
--     · A declared carry-over is the student's own, as a course added beside the list is: registration.student_choose keeps it only
--       while chosen (V518's body), registration.student_reset clears it with the chosen courses (V491's), and registration.student_drop
--       drops it in add and drop (V380's). A carry-over the results state stays where it was, never dropped.
--   Nothing else changes: the menu still puts on the registration only the carry-overs the results state (a declared one is added by
--   the student, under Add Other Course or the registration's Carry-over courses), the GST gate and GST/EPS carry-over hold, approval.
--   The functions are restated from their current definitions (V504's course_context, V590's course_check).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V611: a student adds a carry-over the portal holds no result for, declared and marked so', true);

-- ── 1 · the entry says the student declared it ──────────────────────────────────────────────────────────────────────────
ALTER TABLE registration.entry DROP CONSTRAINT entry_added_as_check;
ALTER TABLE registration.entry ADD CONSTRAINT entry_added_as_check
    CHECK (added_as IS NULL OR added_as IN ('PROGRAMME_OTHER_LEVEL', 'UNIVERSITY_GST', 'UNIVERSITY_EPS', 'DEPARTMENT', 'FACULTY', 'CARRY_OVER_DECLARED'));

-- ── 2 · what a course check reads of the student: the carry-overs the student may declare ────────────────────────────────
CREATE OR REPLACE FUNCTION registration.course_context(p_student uuid, p_session text, p_semester integer)
RETURNS TABLE (passed text[], awaited text[], carry text[], other_semester text[])
LANGUAGE sql STABLE AS $$
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
           AND NOT EXISTS (SELECT 1 FROM r y WHERE y.course_code = x.course_code AND y.published AND y.outcome = 'GRADED' AND y.points > 0))
    SELECT coalesce((SELECT array_agg(DISTINCT x.course_code) FROM r x WHERE x.published AND x.outcome = 'GRADED' AND x.points > 0), '{}'::text[]),
           coalesce((SELECT array_agg(DISTINCT x.course_code) FROM pending x WHERE x.course_code NOT IN (SELECT d.course_code FROM declared d)), '{}'::text[]),
           coalesce((SELECT array_agg(DISTINCT k.course_code)
                       FROM (SELECT cv.course_code FROM registration.carryovers(p_student) cv UNION SELECT d.course_code FROM declared d) k), '{}'::text[]),
           coalesce((SELECT array_agg(DISTINCT o.course_code)
                       FROM registration.course_registration cr
                       JOIN registration.entry e ON e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                       JOIN catalogue.offering o ON o.id = e.offering_id
                      WHERE cr.student_id = p_student AND cr.session = p_session AND cr.semester <> p_semester), '{}'::text[])
$$;
COMMENT ON FUNCTION registration.course_context(uuid, text, integer) IS
  'V504, V611: what a course check reads of the student once: the courses passed (a published graded pass), awaited (registered in an earlier semester with no published result, its result on its way here), owed (registration.carryovers, and the carry-overs the student may declare: registered in an earlier session with no result of the student on the portal), and registered in another semester of the session';

-- ── 3 · one course, one student, one semester: a declared carry-over marked so ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.course_check(p_student uuid, p_session text, p_semester integer, p_code text, p_passed text[], p_awaited text[], p_carry text[], p_other_semester text[])
 RETURNS TABLE(offering_id uuid, category text, added_as text, why text, refusal text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s people.student; p ref.programme; c catalogue.course; o catalogue.offering; pol registration.flex_policy;
        v_stream text; v_spec uuid; b record; v_unmet text[]; v_twin text; v_other_sems text; v_pg boolean;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    SELECT * INTO p FROM ref.programme WHERE code = s.programme_code;
    SELECT * INTO c FROM catalogue.course WHERE code = p_code;
    pol := registration.flex_rule();
    IF c.code IS NULL THEN refusal := 'REG_COURSE_UNKNOWN: there is no course ' || coalesce(p_code, ''); RETURN NEXT; RETURN; END IF;
    v_stream := people.student_stream(p_student);
    SELECT * INTO o FROM catalogue.offering x WHERE x.course_code = c.code AND x.session = p_session AND x.semester = p_semester AND x.stream = v_stream;
    offering_id := o.id;
    SELECT string_agg(CASE x.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END, ' and ' ORDER BY x.semester) INTO v_other_sems
      FROM catalogue.offering x WHERE x.course_code = c.code AND x.session = p_session AND x.stream = v_stream;
    IF c.code = ANY (p_carry) THEN category := 'CARRY_OVER'; END IF;
    IF c.state = 'ENDED' OR c.code LIKE 'DMO %' THEN
        refusal := 'REG_COURSE_INACTIVE: ' || c.code || ' is no longer taught'; RETURN NEXT; RETURN;
    END IF;
    IF registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NOT NULL THEN
        refusal := 'REG_SIWES_SEMESTER: only the SIWES / industrial training course is registered in this semester'; RETURN NEXT; RETURN;
    END IF;
    IF c.code = ANY (p_passed) THEN
        refusal := 'REG_ALREADY_PASSED: Course has already been successfully completed'; RETURN NEXT; RETURN;
    END IF;
    IF c.code = ANY (p_other_semester) THEN
        refusal := 'REG_ALREADY_REGISTERED: ' || c.code || ' is already on your registration for another semester of ' || p_session; RETURN NEXT; RETURN;
    END IF;
    -- registered before with no published result (or one held): not owed and not passed — never read as a failure.
    -- V611: one whose result is on its way here (a score sheet of it on the portal, or registered earlier this session); one registered in
    -- an earlier session with no score sheet here comes as a carry-over the student may declare (registration.course_context)
    IF c.code = ANY (p_awaited) AND NOT c.code = ANY (p_carry) THEN
        refusal := 'REG_RESULT_AWAITED: Result pending — your earlier registration of ' || c.code || ' has no published result yet, so it is not a carry-over; '
                || 'your department publishes the result, or ICT Support adds the course on your ticket';
        RETURN NEXT; RETURN;
    END IF;
    IF NOT pol.curriculum_open AND c.curriculum IS NOT NULL AND s.curriculum_version IS NOT NULL AND c.curriculum <> s.curriculum_version THEN   -- V590
        refusal := 'REG_OTHER_CURRICULUM: ' || c.code || ' belongs to the ' || c.curriculum || ' curriculum, not yours (' || s.curriculum_version || ')'; RETURN NEXT; RETURN;
    END IF;
    IF c.code = ANY (p_carry) THEN
        -- a carry-over is owed at whatever level it was failed; one that runs this semester the menu puts on the registration
        -- V611: one the student declares — registered in an earlier session, and the portal holds no score sheet of it (its result is
        -- on the old portal) — is marked so; a carry-over with a published F is the results' own
        IF NOT EXISTS (SELECT 1 FROM registration.course_registration cr
                         JOIN registration.entry e ON e.registration_id = cr.id AND e.status IN ('REGISTERED', 'APPROVED')
                         JOIN catalogue.offering ox ON ox.id = e.offering_id AND ox.course_code = c.code
                         CROSS JOIN LATERAL assessment.course_final(p_student, ox.id) cf
                        WHERE cr.student_id = p_student AND cr.status IN ('APPROVED', 'LOCKED')
                          AND cf.stage = 'PUBLISHED' AND cf.outcome IN ('GRADED', 'ABSENT') AND coalesce(cf.points, 0) = 0) THEN
            added_as := 'CARRY_OVER_DECLARED';
        END IF;
        IF o.id IS NULL THEN
            refusal := CASE WHEN v_other_sems IS NOT NULL
                            THEN 'REG_NOT_OFFERED_SEMESTER: Course is not offered in this semester; it runs in the ' || v_other_sems || ' semester of ' || p_session
                            ELSE 'REG_NOT_OFFERED_SESSION: Course is not offered in ' || p_session || ' yet' END;
        ELSIF added_as = 'CARRY_OVER_DECLARED' THEN
            why := 'Carry-over you declare: the portal holds no result of your earlier registration of ' || c.code;
        ELSE
            why := 'Carry-over: failed earlier and owed';
        END IF;
        RETURN NEXT; RETURN;
    END IF;
    v_pg := s.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE';
    IF NOT v_pg AND c.level >= 700 THEN
        refusal := 'REG_OTHER_CATEGORY: Course is restricted to postgraduate students'; RETURN NEXT; RETURN;
    END IF;
    -- the programme's own binding, at any level, as the menu reads it (track, specialisation)
    SELECT ss.specialisation_id INTO v_spec FROM people.student_specialisation ss
      JOIN catalogue.programme_specialisation ps ON ps.id = ss.specialisation_id AND ps.programme_code = s.programme_code WHERE ss.student_id = s.id;
    SELECT co.level, co.basis INTO b FROM catalogue.course_offer co
     WHERE co.course_code = c.code AND co.programme_code = s.programme_code
       AND (pol.curriculum_open OR co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
       AND (NOT EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code AND x.level = co.level)
            OR EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code
                          AND x.level = co.level AND x.specialisation_id = v_spec))
     ORDER BY (co.level = s.current_level) DESC, abs(co.level - s.current_level), co.level LIMIT 1;
    IF FOUND THEN
        category := CASE WHEN c.kind = 'GST' OR b.basis = 'GST' THEN 'GST' WHEN b.basis = 'Elective' THEN 'ELECTIVE' ELSE 'CORE' END;
        added_as := CASE WHEN b.level = s.current_level THEN NULL ELSE 'PROGRAMME_OTHER_LEVEL' END;
        why := CASE WHEN category = 'ELECTIVE' THEN 'Elective of your programme' WHEN category = 'GST' THEN 'GST/EPS course of your programme'
                    ELSE 'Course of your programme' END || ' (' || b.level || ' Level)';
    ELSIF c.kind = 'GST' AND c.general_office IN ('GST', 'EPS') THEN
        category := 'GST'; added_as := 'UNIVERSITY_' || c.general_office; why := 'University-wide ' || c.general_office || ' course';
    ELSIF pol.other_scope IN ('DEPARTMENT', 'FACULTY') AND c.dept_code = p.dept_code THEN
        category := CASE WHEN c.kind = 'Elective' THEN 'ELECTIVE' ELSE 'CORE' END; added_as := 'DEPARTMENT'; why := 'Course of your department';
    ELSIF pol.other_scope = 'FACULTY' AND (SELECT d.faculty_code FROM ref.department d WHERE d.code = c.dept_code) = p.faculty_code THEN
        category := CASE WHEN c.kind = 'Elective' THEN 'ELECTIVE' ELSE 'CORE' END; added_as := 'FACULTY'; why := 'Course of your faculty';
    ELSE
        refusal := 'REG_NOT_AVAILABLE: This course is not available for registration by your programme/level/session'; RETURN NEXT; RETURN;
    END IF;
    -- a course of a higher level than the student's waits for that level, unless the rule allows it
    IF added_as IS NOT NULL AND coalesce(b.level, c.level) > s.current_level AND NOT pol.allow_higher_levels THEN
        refusal := 'REG_HIGHER_LEVEL: ' || c.code || ' is taken at ' || coalesce(b.level, c.level) || ' Level; you are at ' || s.current_level || ' Level';
        RETURN NEXT; RETURN;
    END IF;
    IF added_as IS NOT NULL AND NOT pol.allow_other_courses THEN
        refusal := 'REG_OTHER_COURSES_OFF: courses beside your recommended list are not open to students now; ask your department'; RETURN NEXT; RETURN;
    END IF;
    IF o.id IS NULL THEN
        refusal := CASE WHEN v_other_sems IS NOT NULL
                        THEN 'REG_NOT_OFFERED_SEMESTER: Course is not offered in this semester; it runs in the ' || v_other_sems || ' semester of ' || p_session
                        ELSE 'REG_NOT_OFFERED_SESSION: Course is not offered in ' || p_session || ' yet' END;
        RETURN NEXT; RETURN;
    END IF;
    -- V402: a BSU- code and its MOAU- twin: the student's cohort registers its own family
    v_twin := catalogue.twin_by_code(c.code);
    IF catalogue.other_familys_code(p_student, c.code) AND v_twin IS NOT NULL
       AND EXISTS (SELECT 1 FROM catalogue.offering x WHERE x.course_code = v_twin AND x.session = p_session AND x.semester = p_semester AND x.stream = v_stream) THEN
        refusal := 'REG_OTHER_CODE_FAMILY: your cohort registers ' || v_twin || ' instead'; RETURN NEXT; RETURN;
    END IF;
    -- V482: where the Academic Office enforces prerequisites, one not passed holds the course
    IF registration.prerequisite_mode() = 'ENFORCED' THEN
        v_unmet := registration.prerequisites_unmet(p_student, c.code);
        IF cardinality(v_unmet) > 0 THEN
            refusal := 'REG_PREREQUISITE: ' || c.code || ' needs ' || array_to_string(v_unmet, ', ') || ' passed first'; RETURN NEXT; RETURN;
        END IF;
    END IF;
    RETURN NEXT;
END $function$;


-- ── 4 · a declared carry-over is the student's own: it leaves on saving without it, on a reset, by add and drop ───────────────
CREATE OR REPLACE FUNCTION registration.student_choose(p_registration uuid, p_offerings uuid[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; m record; n int := 0; v_gate text; v_unmet text[];
        v_added jsonb; v_menu uuid[]; v_code text; ctx record; v_ctx boolean := false; x record; v_units int;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status NOT IN ('DRAFT','RETURNED') THEN
        RAISE EXCEPTION 'this registration is %; it is not edited', lower(r.status) USING ERRCODE = '23514',
            HINT = 'A submitted registration is changed by the level adviser returning it.';
    END IF;
    -- V518: only the registration's own session and semester are chosen from: a screen switched from another semester could send that
    -- semester's courses with this one's (a first-semester course then refused as "already on your registration for another
    -- semester"); an offering of another session or semester is never this registration's, so it is left out rather than refused
    p_offerings := ARRAY(SELECT DISTINCT o.id FROM catalogue.offering o
                          WHERE o.id = ANY (coalesce(p_offerings, '{}'::uuid[])) AND o.session = r.session AND o.semester = r.semester);
    -- V504: when each course the student added beside the menu was first added, kept across saves
    SELECT coalesce(jsonb_object_agg(e.offering_id::text, e.student_added_at), '{}'::jsonb) INTO v_added
      FROM registration.entry e WHERE e.registration_id = p_registration AND e.student_added_at IS NOT NULL;
    -- V611: a carry-over the student declared is the student's choice, kept only while chosen; one the results state stays
    DELETE FROM registration.entry WHERE registration_id = p_registration AND support_override_at IS NULL
       AND (entry_type NOT IN ('CARRYOVER','DEFERRED') OR (added_as = 'CARRY_OVER_DECLARED' AND NOT offering_id = ANY (p_offerings)));
    -- V512: a GST/EPS carry-over put on the draft before the GST fee was paid comes off it while the fee is owed (not one ICT Support
    -- put on the student's ticket)
    DELETE FROM registration.entry e USING catalogue.offering o
     WHERE e.registration_id = p_registration AND o.id = e.offering_id AND e.entry_type IN ('CARRYOVER', 'DEFERRED') AND e.support_override_at IS NULL
       AND registration.gst_course_hold(r.student_id, r.session, o.course_code) IS NOT NULL;
    -- a deferred course or a carry-over that has since become due is added to a draft that predates it — a GST/EPS one once the fee is paid
    FOR m IN SELECT * FROM registration.student_menu(r.student_id, r.session, r.semester) WHERE carryover LOOP
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

CREATE OR REPLACE FUNCTION registration.student_reset(p_student uuid, p_session text, p_semester integer, p_reason text, p_source text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; v_courses jsonb; v_kept jsonb; n int; u int; removable int; v_id uuid; v_sem text; v_why text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester FOR UPDATE;
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
           count(*) FILTER (WHERE (e.entry_type NOT IN ('CARRYOVER', 'DEFERRED') OR e.added_as = 'CARRY_OVER_DECLARED') AND e.support_override_at IS NULL)
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
       AND (entry_type NOT IN ('CARRYOVER', 'DEFERRED') OR added_as = 'CARRY_OVER_DECLARED');
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

CREATE OR REPLACE FUNCTION registration.student_drop(p_student uuid, p_session text, p_semester integer, p_offering uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; e registration.entry;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF NOT FOUND THEN RAISE EXCEPTION 'no registration to change' USING ERRCODE = '23514'; END IF;
    IF r.status = 'LOCKED' THEN RAISE EXCEPTION 'this registration is locked and cannot be changed' USING ERRCODE = '23514'; END IF;
    IF NOT registration.add_drop_open(p_student, p_session, p_semester) THEN   -- V380: by the student's calendar
        RAISE EXCEPTION 'add and drop is not open for % semester %', p_session, p_semester USING ERRCODE = '23514';
    END IF;

    SELECT * INTO e FROM registration.entry WHERE registration_id = r.id AND offering_id = p_offering AND status <> 'DROPPED';
    IF NOT FOUND THEN RAISE EXCEPTION 'that course is not on your registration' USING ERRCODE = '23514'; END IF;
    -- V611: one the student declared (its result not on the portal) is dropped as it was added
    IF e.entry_type = 'CARRYOVER' AND e.added_as IS DISTINCT FROM 'CARRY_OVER_DECLARED' THEN
        RAISE EXCEPTION 'a carryover cannot be dropped; it must be repeated' USING ERRCODE = '23514';
    END IF;
    IF e.entry_type = 'DEFERRED' THEN
        RAISE EXCEPTION 'a deferred course cannot be dropped; it is taken in the semester it is due' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM assessment.score sc JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id
                WHERE sc.student_id = p_student AND sh.offering_id = p_offering) THEN
        RAISE EXCEPTION 'a mark is already recorded in this course; it cannot be dropped' USING ERRCODE = '23514';
    END IF;

    UPDATE registration.entry SET status = 'DROPPED' WHERE registration_id = r.id AND offering_id = p_offering;
    RETURN registration.units_of(r.id);
END $function$;

COMMENT ON FUNCTION registration.course_check(uuid, text, integer, text, text[], text[], text[], text[]) IS
  'V504, V590, V611: one course for one student and semester — the class, the category, why it may be added, or the refusal; a carry-over the student declares (no result of it on the portal) is marked added_as CARRY_OVER_DECLARED';
COMMENT ON FUNCTION registration.student_choose(uuid, uuid[]) IS
  'V504, V512, V518, V611: the student''s choice saved on a draft — the menu''s courses chosen, the carry-overs and deferred courses due kept or added, a course beside the menu kept while the engine allows it, a declared carry-over only while chosen';

COMMIT;
