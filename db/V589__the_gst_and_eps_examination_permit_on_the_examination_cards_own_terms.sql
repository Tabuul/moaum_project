-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V589 — The GST & EPS examination permit on the examination card's own terms (the University's instruction, 20 Oct 2026)
--
--   Students who had paid their school fees and registered their courses printed the examination card (V567) but not the GST &
--   EPS permit: the permit's rule (V492) still asked what V567 took off the card — the registration approved (one submitted and
--   waiting for the Head was refused), the Bursary's clearance scheme satisfied for the examination (finance.clears_or_null,
--   which on the scheme in force means the session paid in full), and the cards released with the timetable or offered on
--   approval by the V491 rule. On the live-shaped copy of 20 Oct 2026, 145 students with the card in hand had the permit
--   withheld by the scheme and one by the approval. The instruction: a student who owes nothing prints both without effort.
--   The permit now asks what the card asks, and the GST fee besides:
--     · the student in study (admitted, active or on probation);
--     · a course registration for the semester, submitted (or returned, approved, locked — not a draft never submitted);
--     · a GST or EPS course on it (no empty permit is made);
--     · the permit not withdrawn by the GST or EPS office;
--     · the GST fee confirmed where the existing gate asks for it (registration.gst_gate, V366–V370; GST payment covers EPS);
--     · a school-fees payment for the session confirmed, as the card reads it (registration.exam_card_paid, V567: any amount,
--       through any channel the portal records it by).
--   No clearance scheme, no release switch, no approval. The codes GST_EPS_PERMIT_NOT_APPROVED, _NOT_CLEARED and _NOT_RELEASED
--   go; GST_EPS_PERMIT_NOT_SUBMITTED (a draft) and GST_EPS_PERMIT_NOT_PAID (the school fees) come, in the card's words.
--   registration.gst_eps_permit_courses lists the GST and EPS courses of any registration submitted, and the offices' roster
--   (registration.gst_eps_permit_roster) the same students, so the GST and EPS desks see whom the permit serves. The issue and
--   the withdrawal (registration.issue_gst_eps_permit, registration.revoke_gst_eps_permit) read the restated state and are not
--   touched; a permit already issued keeps its number and its counts. Nothing stored changes.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V589: the GST & EPS examination permit on the examination card''s own terms', true);

/* the GST and EPS courses on the student's submitted registration for the semester, each with its examination's slot */
CREATE OR REPLACE FUNCTION registration.gst_eps_permit_courses(p_student uuid, p_session text, p_semester integer)
RETURNS TABLE(offering_id uuid, course_code text, title text, units integer, course_type text, entry_type text, mode text, held_on date,
              starts_at time without time zone, ends_at time without time zone, venue text, seat_no integer, bar text)
LANGUAGE sql STABLE AS $fn$
    SELECT o.id, c.code, coalesce(o.title, c.title), e.units, c.general_office, e.entry_type,
           sl.mode, sl.held_on, sl.starts_at, sl.ends_at, sl.venue, sl.seat_no, attendance.exam_bar(p_student, o.id)
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
     ORDER BY c.general_office DESC, c.code
$fn$;
COMMENT ON FUNCTION registration.gst_eps_permit_courses(uuid, text, integer) IS
    'V492/V589: exactly the GST and EPS courses (catalogue.course kind GST, general_office GST or EPS) on the student''s submitted '
    'registration for the semester, with each examination''s slot — never a departmental course, another semester''s or one not registered';

/* the permit's state: the examination card's terms and the GST fee — the first rule that fails, with its code and its words */
CREATE OR REPLACE FUNCTION registration.gst_eps_permit_state(p_student uuid, p_session text, p_semester integer)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE s people.student; r registration.course_registration; pm registration.gst_eps_permit;
        v_courses jsonb := '[]'::jsonb; v_n int := 0; v_gst int := 0; v_eps int := 0; v_units int := 0;
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
               count(*) FILTER (WHERE x.course_type = 'EPS'), coalesce(sum(x.units), 0)
          INTO v_courses, v_n, v_gst, v_eps, v_units
          FROM registration.gst_eps_permit_courses(p_student, p_session, p_semester) x;
    END IF;
    -- V589: the school fees as the examination card reads them (V567): a confirmed school-fees payment for the session, any amount
    v_paid := registration.exam_card_paid(p_student, p_session);

    -- V589: the card's terms (registered and paid) and the GST fee — no approval, no clearance scheme, no release switch
    IF s.status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') THEN
        v_code := 'GST_EPS_PERMIT_NOT_IN_STUDY';
        v_reason := 'Your student record is ' || lower(replace(s.status, '_', ' ')) || '; a GST & EPS examination permit is issued to a student in study.';
    ELSIF r.id IS NULL THEN
        v_code := 'GST_EPS_PERMIT_NO_REGISTRATION';
        v_reason := 'You have not registered courses for ' || v_sem || ', so no GST or EPS course is registered for the selected session and semester.';
    ELSIF r.status = 'DRAFT' THEN
        v_code := 'GST_EPS_PERMIT_NOT_SUBMITTED';
        v_reason := 'Your course registration for ' || v_sem || ' is not yet submitted. Submit it, and the permit is yours once your school fees are paid.';
    ELSIF v_n = 0 THEN
        v_code := 'GST_EPS_PERMIT_NO_COURSES';
        v_reason := 'You have not registered any GST or EPS course for the selected session and semester.';
    ELSIF pm.revoked_at IS NOT NULL THEN
        v_code := 'GST_EPS_PERMIT_REVOKED';
        v_reason := 'Your GST & EPS examination permit for ' || v_sem || ' was withdrawn by the ' || pm.revoked_office || ' office on '
                    || to_char(pm.revoked_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY') || ': ' || pm.revoked_reason;
    -- the gate answers by the course's office alone, so it is asked once for a GST course and once for an EPS course
    ELSIF EXISTS (SELECT 1 FROM (SELECT DISTINCT ON (x->>'course_type') x->>'course_code' AS code FROM jsonb_array_elements(v_courses) x ORDER BY x->>'course_type') q
                   WHERE registration.gst_gate(p_student, p_session, q.code) IS NOT NULL) THEN
        v_code := 'GST_EPS_PERMIT_GST_PAYMENT';
        v_reason := 'Your GST fee for ' || p_session || ' is not yet confirmed as paid. GST payment covers both GST and EPS; the permit is issued once the payment is confirmed.';
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
        'permit', CASE WHEN pm.id IS NULL THEN NULL ELSE jsonb_build_object(
                      'reference', pm.reference, 'status', registration.gst_eps_permit_status(pm), 'generatedAt', pm.generated_at,
                      'lastIssuedAt', pm.last_issued_at, 'viewed', pm.viewed, 'downloaded', pm.downloaded, 'printed', pm.printed,
                      'revokedAt', pm.revoked_at, 'revokedOffice', pm.revoked_office, 'revokedReason', pm.revoked_reason) END);
END $fn$;
COMMENT ON FUNCTION registration.gst_eps_permit_state(uuid, text, integer) IS
    'V492/V589: whether the GST & EPS examination permit may be issued for the semester and why not — the examination card''s own terms '
    '(a registration submitted carrying a GST or EPS course, the school fees paid as registration.exam_card_paid reads them) and the GST fee '
    'the gate asks for; the student in study, the permit not withdrawn. No approval, clearance scheme or release switch is asked (V589).';

/* the GST or EPS office's roster: the students a submitted registration of the semester carries the office's course for */
CREATE OR REPLACE FUNCTION registration.gst_eps_permit_roster(p_session text, p_semester integer, p_office text)
RETURNS TABLE(student_id uuid, number text, name text, programme_code text, programme text, dept_code text, faculty_code text, level integer,
              reg_status text, courses text, course_count integer, units integer, permit_id uuid, reference text, permit_status text,
              generated_at timestamptz, last_issued_at timestamptz, viewed integer, downloaded integer, printed integer, revoked_at timestamptz)
LANGUAGE sql STABLE AS $fn$
    WITH oc AS (SELECT o.id, o.course_code FROM catalogue.course c
                  JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session
                 WHERE c.kind = 'GST' AND c.code NOT LIKE 'DMO %' AND (c.general_office = p_office OR (p_office IS NULL AND c.general_office IN ('GST', 'EPS')))),
         reg AS (SELECT r.student_id, r.level, r.status, string_agg(oc.course_code, ', ' ORDER BY oc.course_code) AS courses,
                        count(*)::int AS n, sum(e.units)::int AS units
                   FROM oc
                   JOIN registration.entry e ON e.offering_id = oc.id AND e.status IN ('REGISTERED', 'APPROVED')
                   JOIN registration.course_registration r ON r.id = e.registration_id AND r.session = p_session AND r.semester = p_semester
                                                          AND r.status <> 'DRAFT'   -- V589: whom the permit serves
                  GROUP BY r.student_id, r.level, r.status)
    SELECT g.student_id, coalesce(s.matric_no, s.admission_no), upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''),
           s.programme_code, p.name, p.dept_code, p.faculty_code, g.level, g.status, g.courses, g.n, g.units,
           pm.id, pm.reference, registration.gst_eps_permit_status(pm), pm.generated_at, pm.last_issued_at,
           coalesce(pm.viewed, 0), coalesce(pm.downloaded, 0), coalesce(pm.printed, 0), pm.revoked_at
      FROM reg g
      JOIN people.student s ON s.id = g.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN registration.gst_eps_permit pm ON pm.student_id = g.student_id AND pm.session = p_session AND pm.semester = p_semester
$fn$;
COMMENT ON FUNCTION registration.gst_eps_permit_roster(text, integer, text) IS
    'V492/V589: the students whose submitted registration for the semester carries one of the office''s GST or EPS courses (both offices'' '
    'when the office is null), with their permit''s state and counts';

COMMIT;
