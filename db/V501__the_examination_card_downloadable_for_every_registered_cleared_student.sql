-- ═══════════════════════════════════════
-- V501 — The examination card downloadable for every student who registered and is cleared, with every registered course
--
--   Reported 16 Oct 2026: "if you want to download exam card it will route you to GST & EPS permit … exam card is for all the
--   students that paid and registered their courses, so exams card should come with all the courses registered including GST
--   courses too". The GST & EPS permit (V492) has one rule, asked by the database (registration.gst_eps_permit_state). The
--   examination card had none of its own: the student's Examinations page decided from the docket — and hid the card's buttons
--   once the examination timetable was out unless the Bursary's answer was a plain yes (a "not stated" answer the permit takes
--   as no refusal), or where the card waits for the release and the student had no paper on the timetable yet. So the permit
--   could be downloaded while the card, the University's full examination permit, could not.
--
--   registration.exam_card_state(student, session, semester) is now the card's rule, the permit's own order without what is the
--   GST's alone: a student in study, a course registration made, approved, carrying a course; the Bursary's clearance for the
--   examination not refused (finance.clears_or_null, as the permit); the card released — on approval where the semester's rule
--   offers it (V491), or with the examination cards. It answers with every course on the registration — departmental, GST and
--   EPS, carry-overs and deferred courses — and how often the card was issued. The page and the card's PDF read it, and the card's
--   check code is signed only when it says the card is available.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V501: the examination card downloadable for every registered, cleared student, with every registered course', true);

CREATE FUNCTION registration.exam_card_state(p_student uuid, p_session text, p_semester integer)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE s people.student; r registration.course_registration; v_rule registration.approval_policy; ci registration.exam_card_issue;
        v_courses jsonb := '[]'::jsonb; v_n int := 0; v_units int := 0; v_gst int := 0;
        v_code text; v_reason text; v_clear boolean; v_sem text;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'EXAM_CARD_NO_STUDENT: no such student' USING ERRCODE = '23503'; END IF;
    v_sem := p_session || ' ' || CASE p_semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END || ' semester';
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    SELECT * INTO ci FROM registration.exam_card_issue WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    -- every course on the registration: departmental, GST and EPS, carry-overs and deferred courses — never a dropped one
    IF r.id IS NOT NULL THEN
        SELECT coalesce(jsonb_agg(jsonb_build_object('course_code', c.code, 'title', c.title, 'units', e.units, 'entry_type', e.entry_type,
                                                     'gst_eps', c.kind = 'GST', 'general_office', c.general_office)
                                  ORDER BY (e.entry_type IN ('CARRYOVER', 'DEFERRED')) DESC, c.code), '[]'::jsonb),
               count(*), coalesce(sum(e.units), 0), count(*) FILTER (WHERE c.kind = 'GST')
          INTO v_courses, v_n, v_units, v_gst
          FROM registration.entry e
          JOIN catalogue.offering o ON o.id = e.offering_id
          JOIN catalogue.course c ON c.code = o.course_code
         WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN');
    END IF;

    IF s.status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') THEN
        v_code := 'EXAM_CARD_NOT_IN_STUDY';
        v_reason := 'Your student record is ' || lower(replace(s.status, '_', ' ')) || '; an examination card is issued to a student in study.';
    ELSIF r.id IS NULL THEN
        v_code := 'EXAM_CARD_NO_REGISTRATION';
        v_reason := 'You have not registered courses for ' || v_sem || '. The examination card follows an approved course registration.';
    ELSIF r.status NOT IN ('APPROVED', 'LOCKED') THEN
        v_code := 'EXAM_CARD_NOT_APPROVED';
        v_reason := 'Your course registration for ' || v_sem || ' is ' || CASE r.status WHEN 'DRAFT' THEN 'not yet submitted' WHEN 'SUBMITTED' THEN 'awaiting approval'
                    WHEN 'RETURNED' THEN 'returned to you' ELSE lower(r.status) END || '; the examination card is issued for an approved course registration.';
    ELSIF v_n = 0 THEN
        v_code := 'EXAM_CARD_NO_COURSES';
        v_reason := 'Your course registration for ' || v_sem || ' carries no course.';
    ELSE
        v_clear := finance.clears_or_null(p_student, p_session, 'EXAMINATION');
        v_rule := registration.approval_rule(p_session, p_semester);
        IF v_clear IS FALSE THEN
            v_code := 'EXAM_CARD_NOT_CLEARED';
            v_reason := 'Your examination card is issued when the Bursary clears you for the examination. Settle the fees the scheme requires.';
        ELSIF NOT (coalesce(v_rule.card_on_approval, true)
                   OR EXISTS (SELECT 1 FROM assessment.exam_session x WHERE x.session = p_session AND x.semester = p_semester AND x.state <> 'DRAFT'
                                 AND x.cards_released_at IS NOT NULL AND x.stream = people.student_stream(p_student))) THEN
            v_code := 'EXAM_CARD_NOT_RELEASED';
            v_reason := 'Examination cards for ' || v_sem || ' are released with the examination timetable.';
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'available', v_code IS NULL, 'code', v_code, 'reason', v_reason,
        'session', p_session, 'semester', p_semester,
        'registration', CASE WHEN r.id IS NULL THEN NULL ELSE jsonb_build_object('status', r.status, 'level', r.level, 'approvedAt', r.approved_at,
                                                                                'approvalMode', r.approval_mode) END,
        'courses', v_courses, 'count', v_n, 'units', v_units, 'gstEpsCount', v_gst, 'cleared', v_clear,
        'issued', CASE WHEN ci.student_id IS NULL THEN NULL ELSE jsonb_build_object('times', ci.times, 'firstAt', ci.first_at, 'lastAt', ci.last_at) END);
END $$;
COMMENT ON FUNCTION registration.exam_card_state(uuid, text, integer) IS
  'V501: whether a student''s examination card for the session and semester may be issued (the first rule that fails, with its code and words: in study, registered, approved, a course on it, not refused by the Bursary''s clearance, released), every course on the registration (departmental, GST and EPS, carry-over and deferred) and how often it was issued';

COMMIT;
