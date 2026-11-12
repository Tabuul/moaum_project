-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V728 · The GST & EPS examination permit for carry-over courses
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's brief of 12 November 2026: students who register GST/EPS courses as carry-overs cannot print their GST/EPS
--  examination permits; a carry-over must not disqualify a student, the permit must carry every GST/EPS course registered — first
--  registrations and carry-overs — once each, classified, and no payment or examination requirement may be bypassed.
--  Investigated (four readers: twelve scenarios built through the registration functions the API calls, on a scratch database;
--  the carry-over registration and GST fee path; the student's door, the screens and the PDF; the data and the history): no rule
--  of the permit refuses a carry-over as such — registration.gst_eps_permit_courses and gst_eps_permit_state never read the entry's
--  type, and every scenario (GST and EPS carry-overs, results-stated and declared, first and second semester, 300 and 400 Level,
--  spillover) printed once the registration was submitted, the session's GST fee paid and the school fees paid. What stopped
--  students was around the permit:
--    · the screens: the Examinations page asked only for the open semester's permit (most carry-overs sit on the first semester's
--      registration) and showed no panel and no reason for a permit with no course listed — a draft holding the carry-over, a
--      semester without one; the permit page drew its course table only for an approved registration (V589 issues it on a
--      submitted one);
--    · a carry-over already registered in the first semester was placed again on the second semester's draft (the picker refuses
--      it — registration.course_check's other-semester rule — but the draft did not ask), a second registration of one course;
--    · the reasons: a student whose only GST fee was paid in an earlier session read "not yet confirmed as paid" with no word that
--      a carry-over examined this session asks this session's fee (V690, the University's word of 28 October).
--  V728, the existing implementation corrected (no new module): the permit's courses one row a course, each classified FIRST_TIME,
--  CARRY_OVER (a carry-over, a repeat, a declared carry-over, or a course the student registered in an earlier session) or DEFERRED;
--  the state carries the counts, the draft's courses (pending), the other semesters holding GST or EPS courses (named in the
--  reason) and whether the screens show the permit; the GST fee's reason says why a carry-over asks this session's fee; the issued
--  permit keeps each course's classification; the draft and the save never place a carry-over a second time in the session.
--  Every requirement stands: in study, a registration submitted, the course registered and not dropped, the GST fee as
--  registration.gst_gate asks it, the school fees as the examination card reads them, a withdrawn permit withdrawn.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V728: the GST & EPS examination permit for carry-over courses (the University''s brief of 12 November 2026)', true);

-- ── 1 · whether a course is already registered on another semester's registration of the session ──────────────────────────
CREATE OR REPLACE FUNCTION registration.registered_elsewhere(p_student uuid, p_session text, p_semester integer, p_course text)
 RETURNS boolean LANGUAGE sql STABLE AS $function$
    SELECT EXISTS (SELECT 1 FROM registration.course_registration r
                     JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED')
                     JOIN catalogue.offering o ON o.id = e.offering_id AND o.course_code = p_course
                    WHERE r.student_id = p_student AND r.session = p_session AND r.semester <> p_semester)
$function$;
COMMENT ON FUNCTION registration.registered_elsewhere(uuid, text, integer, text) IS
  'V728: whether the course is registered (not dropped, withdrawn or deferred) on the student''s registration of another semester of the session — a carry-over is not placed a second time.';

-- ── 2 · the permit's courses: one row a course, classified; the state, the issue ───────────────────────────────────────────
DROP FUNCTION registration.gst_eps_permit_courses(uuid, text, integer);
CREATE FUNCTION registration.gst_eps_permit_courses(p_student uuid, p_session text, p_semester integer)
 RETURNS TABLE(offering_id uuid, course_code text, title text, units integer, course_type text, entry_type text, classification text, mode text,
               held_on date, starts_at time without time zone, ends_at time without time zone, venue text, seat_no integer, bar text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT y.offering_id, y.course_code, y.title, y.units, y.course_type, y.entry_type, y.classification, y.mode, y.held_on, y.starts_at, y.ends_at,
           y.venue, y.seat_no, y.bar
      FROM (
        -- V728: one row a course — a course registered twice on the registration (two classes of it) is listed once, the approved first
        SELECT DISTINCT ON (c.code) o.id AS offering_id, c.code AS course_code, coalesce(o.title, c.title) AS title, e.units, c.general_office AS course_type,
               e.entry_type,
               -- V728: a carry-over, a repeat, a declared carry-over, or a course the student registered in an earlier session (an
               -- old-portal carry-over typed CURRENT) is a CARRY_OVER; a deferred course DEFERRED; any other a FIRST_TIME registration
               CASE WHEN e.entry_type = 'DEFERRED' THEN 'DEFERRED'
                    WHEN e.entry_type IN ('CARRYOVER', 'REPEAT') OR e.added_as = 'CARRY_OVER_DECLARED'
                         OR EXISTS (SELECT 1 FROM registration.course_registration r0
                                      JOIN registration.entry e0 ON e0.registration_id = r0.id AND e0.status IN ('REGISTERED', 'APPROVED')
                                      JOIN catalogue.offering o0 ON o0.id = e0.offering_id AND o0.course_code = c.code
                                     WHERE r0.student_id = p_student AND r0.status <> 'DRAFT'
                                       AND policy.session_normal(r0.session) < policy.session_normal(p_session))
                    THEN 'CARRY_OVER' ELSE 'FIRST_TIME' END AS classification,
               sl.mode, sl.held_on, sl.starts_at, sl.ends_at, sl.venue, sl.seat_no, attendance.exam_bar(p_student, o.id) AS bar
          FROM registration.course_registration r
          JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED')
          JOIN catalogue.offering o ON o.id = e.offering_id
          JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' AND c.general_office IN ('GST', 'EPS') AND c.code NOT LIKE 'DMO %'
          -- the slot: the student's own CBT sitting and seat, else the examination timetable's slot, else the CBT examination's window
          LEFT JOIN LATERAL (
              SELECT z.mode, z.held_on, z.starts_at, z.ends_at, z.venue, z.seat_no FROM (
                  SELECT 1 AS rank, 'CBT'::text AS mode, (si.starts_at AT TIME ZONE 'Africa/Lagos')::date AS held_on,
                         (si.starts_at AT TIME ZONE 'Africa/Lagos')::time AS starts_at, (si.ends_at AT TIME ZONE 'Africa/Lagos')::time AS ends_at,
                         si.venue, se.seat_no
                    FROM assessment.cbt_exam x
                    JOIN assessment.cbt_seat se ON se.exam_id = x.id AND se.candidate_id = p_student
                    JOIN assessment.cbt_sitting si ON si.id = se.sitting_id
                   WHERE x.offering_id = o.id AND x.state IN ('SCHEDULED', 'PUBLISHED', 'CLOSED', 'COMPLETED')
                  UNION ALL
                  SELECT 2, 'WRITTEN', t.held_on, t.starts_at, t.ends_at, t.venue, NULL::integer
                    FROM assessment.exam_timetable t WHERE t.offering_id = o.id
                  UNION ALL
                  SELECT 3, 'CBT', (x.starts_at AT TIME ZONE 'Africa/Lagos')::date, (x.starts_at AT TIME ZONE 'Africa/Lagos')::time,
                         CASE WHEN (x.ends_at AT TIME ZONE 'Africa/Lagos')::date = (x.starts_at AT TIME ZONE 'Africa/Lagos')::date
                              THEN (x.ends_at AT TIME ZONE 'Africa/Lagos')::time END,
                         CASE WHEN x.venue = 'REMOTE' THEN 'Online (CBT)' END, NULL::integer
                    FROM assessment.cbt_exam x
                   WHERE x.offering_id = o.id AND x.state IN ('SCHEDULED', 'PUBLISHED', 'CLOSED', 'COMPLETED') AND x.starts_at IS NOT NULL
              ) z ORDER BY z.rank, z.held_on NULLS LAST LIMIT 1) sl ON true
         -- V589: any registration submitted — approved or not — as the examination card reads it; a draft never submitted carries nothing
         WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester AND r.status <> 'DRAFT'
         ORDER BY c.code, (e.status = 'APPROVED') DESC, o.id) y
     ORDER BY y.course_type DESC, y.course_code
$function$;
COMMENT ON FUNCTION registration.gst_eps_permit_courses(uuid, text, integer) IS
  'V492, V589, V728: the GST and EPS courses on the student''s submitted registration for the semester — first registrations and carry-overs alike, one row a course — each with its classification (FIRST_TIME, CARRY_OVER, DEFERRED) and its examination slot.';

CREATE OR REPLACE FUNCTION registration.gst_eps_permit_state(p_student uuid, p_session text, p_semester integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s people.student; r registration.course_registration; pm registration.gst_eps_permit;
        v_courses jsonb := '[]'::jsonb; v_n int := 0; v_gst int := 0; v_eps int := 0; v_units int := 0;
        v_carry int := 0; v_first int := 0; v_pending jsonb := '[]'::jsonb; v_other int[] := '{}'; v_elsewhere text := '';
        v_code text; v_reason text; v_paid boolean; v_sem text; v_prog record;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'GST_EPS_PERMIT_NO_STUDENT: no such student' USING ERRCODE = '23503'; END IF;
    v_sem := p_session || ' ' || CASE p_semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END || ' semester';
    SELECT p.name AS programme, d.name AS department, f.name AS faculty INTO v_prog
      FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, p.faculty_code)
     WHERE p.code = s.programme_code;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    SELECT * INTO pm FROM registration.gst_eps_permit WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF r.id IS NOT NULL AND r.status <> 'DRAFT' THEN
        SELECT coalesce(jsonb_agg(to_jsonb(x) - 'offering_id' ORDER BY x.course_type DESC, x.course_code), '[]'::jsonb), count(*), count(*) FILTER (WHERE x.course_type = 'GST'),
               count(*) FILTER (WHERE x.course_type = 'EPS'), coalesce(sum(x.units), 0),
               count(*) FILTER (WHERE x.classification = 'CARRY_OVER'), count(*) FILTER (WHERE x.classification = 'FIRST_TIME')
          INTO v_courses, v_n, v_gst, v_eps, v_units, v_carry, v_first
          FROM registration.gst_eps_permit_courses(p_student, p_session, p_semester) x;
    END IF;
    -- V728: a draft's GST and EPS courses — carry-overs among them — said while the registration waits to be submitted
    IF r.id IS NOT NULL AND r.status = 'DRAFT' THEN
        SELECT coalesce(jsonb_agg(jsonb_build_object('course_code', c.code, 'title', coalesce(o.title, c.title), 'course_type', c.general_office,
                                                     'entry_type', e.entry_type) ORDER BY c.general_office DESC, c.code), '[]'::jsonb)
          INTO v_pending
          FROM registration.entry e
          JOIN catalogue.offering o ON o.id = e.offering_id
          JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' AND c.general_office IN ('GST', 'EPS') AND c.code NOT LIKE 'DMO %'
         WHERE e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED');
    END IF;
    -- V728: with no GST or EPS course on this semester's registration, the other semesters of the session whose submitted
    -- registration carries one — a carry-over sits on the registration of the semester it was added in
    IF v_n = 0 THEN
        SELECT coalesce(array_agg(DISTINCT r2.semester ORDER BY r2.semester), '{}'::int[]) INTO v_other
          FROM registration.course_registration r2
          JOIN registration.entry e ON e.registration_id = r2.id AND e.status IN ('REGISTERED', 'APPROVED')
          JOIN catalogue.offering o ON o.id = e.offering_id
          JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' AND c.general_office IN ('GST', 'EPS') AND c.code NOT LIKE 'DMO %'
         WHERE r2.student_id = p_student AND r2.session = p_session AND r2.semester <> p_semester AND r2.status <> 'DRAFT';
        IF cardinality(v_other) > 0 THEN
            v_elsewhere := ' Your GST and EPS courses of ' || p_session || ' are on your '
                           || array_to_string(ARRAY(SELECT CASE x WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END FROM unnest(v_other) x ORDER BY x), ' and ')
                           || ' semester registration: choose that semester.';
        END IF;
    END IF;
    -- V589: the school fees as the examination card reads them (V567): a confirmed school-fees payment for the session, any amount
    v_paid := registration.exam_card_paid(p_student, p_session);

    -- V589: the card's terms (registered and paid) and the GST fee — no approval, no clearance scheme, no release switch
    IF s.status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') THEN
        v_code := 'GST_EPS_PERMIT_NOT_IN_STUDY';
        v_reason := 'Your student record is ' || lower(replace(s.status, '_', ' ')) || '; a GST & EPS examination permit is issued to a student in study.';
    ELSIF r.id IS NULL THEN
        v_code := 'GST_EPS_PERMIT_NO_REGISTRATION';
        v_reason := 'You have not registered courses for ' || v_sem || ', so no GST or EPS course is registered for the selected session and semester.' || v_elsewhere;
    ELSIF r.status = 'DRAFT' THEN
        v_code := 'GST_EPS_PERMIT_NOT_SUBMITTED';
        v_reason := 'Your course registration for ' || v_sem || ' is not yet submitted. Submit it, and the permit is yours once your school fees are paid.';
    ELSIF v_n = 0 THEN
        v_code := 'GST_EPS_PERMIT_NO_COURSES';
        v_reason := 'You have not registered any GST or EPS course for the selected session and semester.' || v_elsewhere;
    ELSIF pm.revoked_at IS NOT NULL THEN
        v_code := 'GST_EPS_PERMIT_REVOKED';
        v_reason := 'Your GST & EPS examination permit for ' || v_sem || ' was withdrawn by the ' || pm.revoked_office || ' office on '
                    || to_char(pm.revoked_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY') || ': ' || pm.revoked_reason;
    -- the gate answers by the course's office alone, so it is asked once for a GST course and once for an EPS course
    ELSIF EXISTS (SELECT 1 FROM (SELECT DISTINCT ON (x->>'course_type') x->>'course_code' AS code FROM jsonb_array_elements(v_courses) x ORDER BY x->>'course_type') q
                   WHERE registration.gst_gate(p_student, p_session, q.code) IS NOT NULL) THEN
        v_code := 'GST_EPS_PERMIT_GST_PAYMENT';
        v_reason := 'Your GST fee for ' || p_session || ' is not yet confirmed as paid. GST payment covers both GST and EPS; the permit is issued once the payment is confirmed.'
                    -- V728: a carry-over is examined in this session, so this session's fee is asked (V690); an earlier one does not cover it
                    || CASE WHEN v_carry > 0 THEN ' A carry-over GST or EPS course is examined in ' || p_session || ', so the GST fee of ' || p_session
                                                  || ' is asked; a GST fee paid in an earlier session does not cover it.' ELSE '' END;
    ELSIF NOT v_paid THEN
        v_code := 'GST_EPS_PERMIT_NOT_PAID';
        v_reason := 'Your GST & EPS examination permit is issued once your school fees for ' || p_session || ' are paid, as your examination card is. '
                    || 'A payment made at a bank or on Quickteller shows here once Interswitch reports it.';
    END IF;

    RETURN jsonb_build_object(
        'available', v_code IS NULL, 'code', v_code, 'reason', v_reason,
        'session', p_session, 'semester', p_semester,
        'student', jsonb_build_object('name', upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''),
                                      'matricNo', s.matric_no, 'number', coalesce(s.matric_no, s.admission_no), 'jambNo', s.jamb_reg_no,
                                      'faculty', v_prog.faculty, 'department', v_prog.department, 'programme', v_prog.programme,
                                      'level', coalesce(r.level, s.current_level), 'status', s.status),
        'registration', CASE WHEN r.id IS NULL THEN NULL ELSE jsonb_build_object('status', r.status, 'level', r.level, 'approvedAt', r.approved_at,
                                                                                'approvalMode', r.approval_mode) END,
        'courses', v_courses, 'gstCount', v_gst, 'epsCount', v_eps, 'units', v_units, 'cleared', v_paid,
        -- V728: how many of the courses are carry-overs and how many first registrations; the draft's courses; the other semesters
        -- holding GST or EPS courses; and whether the screens show the permit at all (courses, a draft holding some, or a permit)
        'carryOverCount', v_carry, 'firstTimeCount', v_first, 'pending', v_pending, 'otherSemesters', to_jsonb(v_other),
        'shown', (v_n > 0 OR jsonb_array_length(v_pending) > 0 OR pm.id IS NOT NULL),
        'permit', CASE WHEN pm.id IS NULL THEN NULL ELSE jsonb_build_object(
                      'reference', pm.reference, 'status', registration.gst_eps_permit_status(pm), 'generatedAt', pm.generated_at,
                      'lastIssuedAt', pm.last_issued_at, 'viewed', pm.viewed, 'downloaded', pm.downloaded, 'printed', pm.printed,
                      'revokedAt', pm.revoked_at, 'revokedOffice', pm.revoked_office, 'revokedReason', pm.revoked_reason) END);
END $function$;

COMMENT ON FUNCTION registration.gst_eps_permit_state(uuid, text, integer) IS
  'V492, V589, V728: the GST & EPS permit of a student''s semester — in study, a registration submitted, its GST and EPS courses (first registrations and carry-overs alike, one row a course, each classified), the GST fee as registration.gst_gate asks it, the school fees as the examination card reads them; the draft''s courses, the other semesters holding GST or EPS courses and whether the screens show it.';

CREATE OR REPLACE FUNCTION registration.issue_gst_eps_permit(p_student uuid, p_session text, p_semester integer, p_act text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE st jsonb; pm registration.gst_eps_permit; v_codes jsonb; v_action text;
BEGIN
    v_action := CASE p_act WHEN 'VIEW' THEN 'GST_EPS_PERMIT_VIEWED' WHEN 'DOWNLOAD' THEN 'GST_EPS_PERMIT_DOWNLOADED' WHEN 'PRINT' THEN 'GST_EPS_PERMIT_PRINTED' END;
    IF v_action IS NULL THEN
        RAISE EXCEPTION 'GST_EPS_PERMIT_ACT: a permit is viewed (VIEW), downloaded (DOWNLOAD) or printed (PRINT)' USING ERRCODE = '23514';
    END IF;
    -- one issue at a time for the student's semester, so a double click never makes two permits
    PERFORM pg_advisory_xact_lock(hashtextextended('gst_eps_permit:' || p_student || ':' || p_session || ':' || p_semester, 0));
    st := registration.gst_eps_permit_state(p_student, p_session, p_semester);
    IF NOT (st->>'available')::boolean THEN
        RAISE EXCEPTION '%', (st->>'code') || ': ' || (st->>'reason') USING ERRCODE = '23514';
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object('code', x->>'course_code', 'type', x->>'course_type', 'units', (x->>'units')::int, 'classification', x->>'classification')), '[]'::jsonb)
      INTO v_codes FROM jsonb_array_elements(st->'courses') x;
    SELECT * INTO pm FROM registration.gst_eps_permit WHERE student_id = p_student AND session = p_session AND semester = p_semester FOR UPDATE;
    IF NOT FOUND THEN
        INSERT INTO registration.gst_eps_permit (reference, student_id, session, semester, courses)
        VALUES ('GST-EPS/' || left(p_session, 4) || '/' || lpad(nextval('registration.gst_eps_permit_no')::text, 6, '0'), p_student, p_session, p_semester, v_codes)
        RETURNING * INTO pm;
        INSERT INTO registration.gst_eps_permit_event (permit_id, action, courses, actor_id, actor_office)
        VALUES (pm.id, 'GST_EPS_PERMIT_GENERATED', v_codes, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
    END IF;
    UPDATE registration.gst_eps_permit
       SET last_issued_at = now(), courses = v_codes,
           viewed = viewed + (p_act = 'VIEW')::int, downloaded = downloaded + (p_act = 'DOWNLOAD')::int, printed = printed + (p_act = 'PRINT')::int
     WHERE id = pm.id;
    INSERT INTO registration.gst_eps_permit_event (permit_id, action, courses, actor_id, actor_office)
    VALUES (pm.id, v_action, v_codes, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
    RETURN registration.gst_eps_permit_state(p_student, p_session, p_semester);
END $function$;

-- ── 3 · the draft and the save never place a carry-over a second time in the session ─────────────────────────────────
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
        -- V728: nor one already registered on another semester's registration of the session (the picker refuses it too)
        IF registration.registered_elsewhere(p_student, p_session, p_semester, m.course_code) THEN CONTINUE; END IF;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (v, m.offering_id, m.units, CASE WHEN m.deferred THEN 'DEFERRED' ELSE 'CARRYOVER' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        IF FOUND THEN PERFORM registration.gst_course_registered(v, m.offering_id); END IF;
    END LOOP;
    RETURN v;
END $function$;

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
        -- V728: nor one already registered on another semester's registration of the session (the picker refuses it too)
        IF registration.registered_elsewhere(r.student_id, r.session, r.semester, m.course_code) THEN CONTINUE; END IF;
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

-- ── 4 · told once: the courses already registered twice in a session, on two semesters' registrations (kept, as history) ────
DO $$
DECLARE v_twice int;
BEGIN
    SELECT count(*) INTO v_twice FROM (
        SELECT r.student_id, r.session, o.course_code
          FROM registration.course_registration r
          JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED')
          JOIN catalogue.offering o ON o.id = e.offering_id
         GROUP BY r.student_id, r.session, o.course_code
        HAVING count(DISTINCT r.semester) > 1) x;
    RAISE NOTICE 'V728: % courses are registered on two semesters'' registrations of one session by one student (kept as they are; a course that runs in both semesters may be among them)', v_twice;
END $$;

COMMIT;
