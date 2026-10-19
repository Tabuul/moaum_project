-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V567 — The examination card for every student who has paid and registered courses (the University's instruction, 19 Oct 2026)
--
--   Students who had paid and registered could not print the examination card: V501's rule asked more of them — the registration
--   approved, the Bursary's clearance scheme satisfied (an instalment or the whole session paid, nothing owed from an earlier session,
--   the session's fee lines stated), the cards released with the timetable, the record in study. The University's instruction: no
--   restriction on a student who has made the payment and registered courses. The card now asks only that:
--     · a course registration for the semester, submitted (or returned, approved, locked — not a draft never submitted), carrying a
--       course;
--     · a school-fees payment for the session confirmed — any amount, through any channel the portal records it by (a gateway,
--       Quickteller, a bank credit, the NELFUND wallet applied, the old portal's history, a migration; reporting.payments classifies
--       each as SCHOOL_FEES).
--   registration.exam_card_state is restated with that rule (its answer the same shape); the withheld list
--   (registration.exam_cards_withheld) and its reminder (registration.remind_exam_cards_withheld) read the same rule and words.
--   The GST & EPS permit keeps its own rule (the GST fee).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V567: the examination card for every student who has paid and registered', true);

/* whether a student has paid school fees for a session: a confirmed school-fees payment of any amount, through any channel */
CREATE FUNCTION registration.exam_card_paid(p_student uuid, p_session text)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT EXISTS (SELECT 1 FROM reporting.payments p
                    WHERE p.student_id = p_student AND p.session = p_session AND p.confirmed_at IS NOT NULL
                      AND p.purpose_code = 'SCHOOL_FEES' AND p.amount > 0)
$fn$;
COMMENT ON FUNCTION registration.exam_card_paid(uuid, text) IS
  'V567: whether the student has a confirmed school-fees payment for the session (any amount, any channel: a gateway, Quickteller, a bank credit, the wallet applied, the old portal, a migration) — what the examination card asks of the money.';

CREATE OR REPLACE FUNCTION registration.exam_card_state(p_student uuid, p_session text, p_semester integer)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE s people.student; r registration.course_registration; ci registration.exam_card_issue;
        v_courses jsonb := '[]'::jsonb; v_n int := 0; v_units int := 0; v_gst int := 0;
        v_code text; v_reason text; v_paid boolean; v_sem text;
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
    v_paid := registration.exam_card_paid(p_student, p_session);

    -- V567: registered courses and paid — nothing else is asked
    IF r.id IS NULL THEN
        v_code := 'EXAM_CARD_NO_REGISTRATION';
        v_reason := 'You have not registered courses for ' || v_sem || '. Register your courses, and the examination card is yours once your school fees are paid.';
    ELSIF r.status = 'DRAFT' THEN
        v_code := 'EXAM_CARD_NOT_SUBMITTED';
        v_reason := 'Your course registration for ' || v_sem || ' is not yet submitted. Submit it, and the examination card is yours once your school fees are paid.';
    ELSIF v_n = 0 THEN
        v_code := 'EXAM_CARD_NO_COURSES';
        v_reason := 'Your course registration for ' || v_sem || ' carries no course.';
    ELSIF NOT v_paid THEN
        v_code := 'EXAM_CARD_NOT_PAID';
        v_reason := 'Your examination card is issued once your school fees for ' || p_session || ' are paid. A payment made at a bank or on Quickteller shows here once Interswitch reports it.';
    END IF;

    RETURN jsonb_build_object(
        'available', v_code IS NULL, 'code', v_code, 'reason', v_reason,
        'session', p_session, 'semester', p_semester,
        'registration', CASE WHEN r.id IS NULL THEN NULL ELSE jsonb_build_object('status', r.status, 'level', r.level, 'approvedAt', r.approved_at,
                                                                                'approvalMode', r.approval_mode) END,
        'courses', v_courses, 'count', v_n, 'units', v_units, 'gstEpsCount', v_gst, 'cleared', v_paid,
        'issued', CASE WHEN ci.student_id IS NULL THEN NULL ELSE jsonb_build_object('times', ci.times, 'firstAt', ci.first_at, 'lastAt', ci.last_at) END);
END $$;
COMMENT ON FUNCTION registration.exam_card_state(uuid, text, integer) IS
  'V501, V567: whether a student''s examination card for the session and semester may be issued — a course registration submitted with a course on it, and a school-fees payment for the session (registration.exam_card_paid); nothing else (no approval, release, instalment, arrears or status test, the University''s instruction) — with every course on the registration and how often the card was issued';

/* the registrations of a session whose card is withheld, with the card's own code and words, the session's payers read in one pass */
CREATE OR REPLACE FUNCTION registration.exam_cards_withheld(p_session text, p_semester integer)
RETURNS TABLE(registration_id uuid, student_id uuid, full_name text, matric_no text, programme text, dept_code text, faculty_code text,
              level integer, semester integer, code text, reason text)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    WITH r AS MATERIALIZED (
        SELECT g.id, g.student_id, g.level, g.semester, g.status, s.programme_code,
               upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS full_name, s.matric_no
          FROM registration.course_registration g JOIN people.student s ON s.id = g.student_id
         WHERE g.session = p_session AND (p_semester IS NULL OR g.semester = p_semester)),
    n AS MATERIALIZED (
        SELECT e.registration_id, count(*) AS courses FROM registration.entry e
         WHERE e.registration_id IN (SELECT id FROM r) AND e.status NOT IN ('DROPPED', 'WITHDRAWN') GROUP BY 1),
    -- V567: the session's school-fees payers among the registered, as registration.exam_card_paid reads each
    paid AS MATERIALIZED (
        SELECT DISTINCT p.student_id FROM reporting.payments p
         WHERE p.session = p_session AND p.confirmed_at IS NOT NULL AND p.purpose_code = 'SCHOOL_FEES' AND p.amount > 0
           AND p.student_id = ANY (ARRAY(SELECT DISTINCT r.student_id FROM r))),
    k AS (
        SELECT r.*, CASE WHEN r.status = 'DRAFT' THEN 'EXAM_CARD_NOT_SUBMITTED'
                         WHEN coalesce(n.courses, 0) = 0 THEN 'EXAM_CARD_NO_COURSES'
                         WHEN NOT EXISTS (SELECT 1 FROM paid WHERE paid.student_id = r.student_id) THEN 'EXAM_CARD_NOT_PAID' END AS code
          FROM r LEFT JOIN n ON n.registration_id = r.id)
    SELECT k.id, k.student_id, k.full_name, k.matric_no, p.name, p.dept_code, coalesce(d.faculty_code, p.faculty_code), k.level, k.semester, k.code,
           CASE k.code WHEN 'EXAM_CARD_NOT_SUBMITTED' THEN 'The course registration is not yet submitted'
                       WHEN 'EXAM_CARD_NO_COURSES' THEN 'The registration carries no course'
                       ELSE 'No school-fees payment for the session on record' END
      FROM k
      LEFT JOIN ref.programme p ON p.code = k.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
     WHERE k.code IS NOT NULL;
END $$;
COMMENT ON FUNCTION registration.exam_cards_withheld(text, integer) IS
  'V505, V515, V567: every course registration of a session (and semester) whose examination card the card''s rule (registration.exam_card_state) withholds, with its code and words — not submitted, no course, no school-fees payment for the session (the session''s payers read in one pass)';

/* the students whose cards are withheld told why (V505), in the words of the rule as it now is */
CREATE OR REPLACE FUNCTION registration.remind_exam_cards_withheld(p_session text, p_semester integer, p_code text)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); x record; n int := 0;
BEGIN
    IF v_office IS NULL OR v_office NOT IN ('records', 'bursar', 'registrar', 'dregistrar', 'academic', 'super') THEN
        RAISE EXCEPTION 'EXAM_CARD_REMIND_OFFICE: the students whose cards are withheld are reminded by Exams & Records, the Bursary or the Registry' USING ERRCODE = '42501';
    END IF;
    FOR x IN SELECT * FROM registration.exam_cards_withheld(p_session, p_semester) w WHERE p_code IS NULL OR w.code = p_code LOOP
        PERFORM platform.tell_student(x.student_id, 'EXAM_CARD_WITHHELD', NULL,
            jsonb_build_object('SESSION', p_session, 'SEMESTER', CASE x.semester WHEN 1 THEN 'first semester' WHEN 2 THEN 'second semester' ELSE 'third semester' END,
                               'REASON', CASE x.code WHEN 'EXAM_CARD_NOT_PAID' THEN 'no school-fees payment for the session is on record yet; once it is paid (a bank or Quickteller payment once Interswitch reports it) the card is yours'
                                                     WHEN 'EXAM_CARD_NOT_SUBMITTED' THEN 'your course registration is not yet submitted; submit it'
                                                     ELSE 'your registration carries no course' END),
            'EXAM_CARD_WITHHELD:' || x.registration_id || ':' || x.code || ':' || current_date);
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

COMMIT;
