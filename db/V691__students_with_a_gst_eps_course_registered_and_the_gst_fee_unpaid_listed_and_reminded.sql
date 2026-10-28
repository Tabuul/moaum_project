-- ═══════════════════════════════════════
-- V691 — Students with a GST/EPS course registered while the GST fee is unpaid: listed for the GST office and the Bursary, with the
-- amount, and reminded
--
-- After V690 (28 October 2026: a 400 Level student registered EPS 202 as a declared carry-over without paying the GST fee), the students
-- who got through before it owe the fee already: the registration makes it owed. The GST desk counted them on its dashboard ("registered
-- without paying", V314) but listed them nowhere, the Bursar's menu had no way to them, and nothing told the students.
--
-- Now:
--   1. finance.gst_registered_unpaid(office, …): the one rule for the list and its figure — a GST course registered and owed, or an EPS
--      course registered and owed while the GST fee covers EPS; the fee not paid (nor exempt). The GST office's list holds both (one
--      payment covers GST and EPS); the EPS office's, its own courses.
--   2. The notice GST_FEE_UNPAID_REGISTERED: the courses on the registration, the session and the amount; one payment covers GST and EPS.
--   3. finance.gst_unpaid_remind(list, session, students): each student checked again — still on the list, no GST payment confirmed since,
--      a GST/EPS course still registered, the fee stated — and told at most once a day (the notice's event key carries the Lagos date);
--      the GST office, the EPS office and the Bursar (and super) send it (GST_REMIND_OFFICE otherwise); up to 5,000 at a time
--      (GST_REMIND_MANY). Each sending is written down in finance.gst_unpaid_reminder with what it came to.
--   4. registration.gst_gate_many(student, session, courses): the gate over many courses at once, the student's GST standing worked
--      out once — the ADD CARRY-OVER list flags each GST/EPS course the fee holds before it is ticked, and asking the gate course by
--      course worked the standing out again for each (some 1 s for 28 courses on a scratch database). registration.gst_gate is now
--      that function over one course: one rule, as V690 stated it.
-- Nothing is removed from a registration and no fee is charged here: the fee is owed by the registration already.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V691: students with a GST/EPS course registered and the GST fee unpaid, listed and reminded', true);

-- ── 1 · the rule ──────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.gst_registered_unpaid(p_office text, p_gst_registered boolean, p_eps_registered boolean,
                                              p_gst_required boolean, p_eps_required boolean, p_entitled boolean)
RETURNS boolean
LANGUAGE sql STABLE AS $fn$
    SELECT NOT coalesce(p_entitled, false)
       AND ((upper(p_office) = 'GST' AND coalesce(p_gst_registered, false) AND coalesce(p_gst_required, false))
            OR (coalesce(p_eps_registered, false) AND coalesce(p_eps_required, false)
                AND coalesce((SELECT g.covers_eps FROM finance.gst_setting g WHERE g.id = 1), false)))
$fn$;
COMMENT ON FUNCTION finance.gst_registered_unpaid(text, boolean, boolean, boolean, boolean, boolean) IS
  'V691: a student of the GST or EPS office''s population with a course registered while the GST fee is unpaid — a GST course registered and owed (the GST office''s list), or an EPS course registered and owed while the GST fee covers EPS (both lists); paid or exempt, never.';

-- ── 2 · the notice ────────────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('GST_FEE_UNPAID_REGISTERED', 'GST fee unpaid for registered courses',
 'To a student with a GST or EPS course on their course registration while the GST fee is not paid; sent by the GST office, the EPS office or the Bursary, at most once a day',
 'Pay the GST fee for [COURSES] ([SESSION])',
 E'Dear [FIRST_NAME],\n\n[COURSES] is on your course registration for [SESSION], but the GST fee of [AMOUNT] is not paid. One payment covers GST and EPS. Pay it on the GST & EPS page of your portal: [PORTAL_URL]\n\nYour examination card and the GST & EPS examination permit wait for the payment.\n\n[UNIVERSITY_SHORT] GST Office',
 '[UNIVERSITY_SHORT]: [COURSES] is on your [SESSION] registration but the GST fee of [AMOUNT] is not paid. Pay on the GST & EPS page of your portal.',
 'GST fee not paid',
 '[COURSES] is on your course registration for [SESSION], but the GST fee of [AMOUNT] is not paid. One payment covers GST and EPS: pay it on the GST & EPS page. Your examination card and the GST & EPS permit wait for it.',
 ARRAY['FIRST_NAME','COURSES','SESSION','AMOUNT','PORTAL_URL','UNIVERSITY_SHORT'], false, 'HIGH');

-- ── 3 · the reminder, written down ───────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.gst_unpaid_reminder (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session      text NOT NULL,
    list_office  text NOT NULL CHECK (list_office IN ('GST', 'EPS')),
    asked        int NOT NULL,
    sent         int NOT NULL,
    already      int NOT NULL,
    skipped      int NOT NULL,
    sent_by      uuid NULL,
    sent_office  text NULL,
    sent_at      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE finance.gst_unpaid_reminder IS
  'V691: each reminder sent to students with a GST/EPS course registered and the GST fee unpaid — the list it was sent from, how many were asked for, told, told already that day, and passed over (paid since, nothing registered, no fee stated, not on the list), who sent it and when.';
SELECT audit.attach('finance.gst_unpaid_reminder');

CREATE FUNCTION finance.gst_unpaid_remind(p_office text, p_session text, p_students uuid[])
RETURNS TABLE(student uuid, outcome text, courses text, amount numeric)
LANGUAGE plpgsql AS $fn$
#variable_conflict use_column
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        by_office text := lower(coalesce(nullif(current_setting('moaum.actor_office', true), ''), ''));
        v_list text := upper(btrim(coalesce(p_office, '')));
        v_key text := 'GST_FEE_UNPAID_REGISTERED:' || coalesce(p_session, '') || ':' || to_char((now() AT TIME ZONE 'Africa/Lagos')::date, 'YYYY-MM-DD');
        v_covers boolean := coalesce((SELECT g.covers_eps FROM finance.gst_setting g WHERE g.id = 1), false);
        r record; v_courses text; v_out text; v_amount numeric; n_sent int := 0; n_already int := 0; n_skipped int := 0; v_asked int;
BEGIN
    IF by_office NOT IN ('gst', 'eps', 'bursar', 'super') THEN
        RAISE EXCEPTION 'GST_REMIND_OFFICE: the GST office, the EPS office or the Bursary reminds a student of the GST fee' USING ERRCODE = '42501';
    END IF;
    IF v_list NOT IN ('GST', 'EPS') THEN
        RAISE EXCEPTION 'GST_REMIND_LIST: the list is the GST office''s or the EPS office''s' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session s WHERE s.name = p_session) THEN
        RAISE EXCEPTION 'GST_REMIND_SESSION: % is not a session on the calendar', coalesce(p_session, '—') USING ERRCODE = '22023';
    END IF;
    v_asked := (SELECT count(DISTINCT u) FROM unnest(coalesce(p_students, '{}'::uuid[])) u);
    IF v_asked = 0 THEN
        RAISE EXCEPTION 'GST_REMIND_NONE: choose the students to remind' USING ERRCODE = '22023';
    END IF;
    IF v_asked > 5000 THEN
        RAISE EXCEPTION 'GST_REMIND_MANY: % students at once; remind up to 5,000 at a time', v_asked USING ERRCODE = '22023';
    END IF;

    FOR r IN
        WITH ids AS (SELECT DISTINCT u AS id FROM unnest(p_students) u)
        SELECT ids.id, (k.student_id IS NOT NULL) AS listed,
               finance.gst_registered_unpaid(v_list, k.gst_registered, k.eps_registered, k.gst_required, k.eps_required, k.entitled) AS unpaid,
               coalesce(k.stated, false) AS stated, coalesce(k.fee, 0) AS fee, coalesce(k.paid, 0) AS paid,
               -- a payment confirmed since the population was worked out
               EXISTS (SELECT 1 FROM finance.payment_reference p
                        WHERE p.student_id = ids.id AND p.session = p_session AND p.purpose LIKE 'GST fee %' AND p.confirmed_at IS NOT NULL
                          AND p.archived_at IS NULL AND p.amount > finance.gst_refunded(p.reference)) AS paid_now
          FROM ids
          LEFT JOIN finance.gst_population_kept_of(p_session, NULL) k ON k.student_id = ids.id
         ORDER BY ids.id
    LOOP
        SELECT string_agg(DISTINCT o.course_code, ', ' ORDER BY o.course_code) INTO v_courses
          FROM registration.course_registration cr
          JOIN registration.entry e ON e.registration_id = cr.id AND e.status <> 'DROPPED'
          JOIN catalogue.offering o ON o.id = e.offering_id
          JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST'
                                 AND ((v_list = 'GST' AND c.general_office = 'GST') OR (c.general_office = 'EPS' AND v_covers))
         WHERE cr.student_id = r.id AND cr.session = p_session;
        v_amount := CASE WHEN r.stated THEN greatest(r.fee - r.paid, 0) END;
        v_out := CASE WHEN NOT r.listed THEN 'NOT_LISTED'
                      WHEN r.paid_now OR NOT r.unpaid THEN 'NOT_UNPAID'
                      WHEN v_courses IS NULL THEN 'NOT_REGISTERED'
                      WHEN NOT r.stated OR coalesce(v_amount, 0) <= 0 THEN 'FEE_NOT_STATED'
                      WHEN EXISTS (SELECT 1 FROM platform.notice x WHERE x.event_key = v_key AND x.about_kind = 'student' AND x.about_id = r.id)
                           THEN 'ALREADY_TODAY'
                      ELSE NULL END;
        IF v_out IS NULL THEN
            IF platform.tell_student(r.id, 'GST_FEE_UNPAID_REGISTERED', NULL,
                   jsonb_build_object('COURSES', v_courses, 'SESSION', p_session, 'AMOUNT', 'NGN ' || to_char(v_amount, 'FM999,999,999,990.00')),
                   v_key) > 0 THEN
                v_out := 'SENT';
            ELSE
                v_out := 'NO_CONTACT';
            END IF;
        END IF;
        IF v_out = 'SENT' THEN n_sent := n_sent + 1;
        ELSIF v_out = 'ALREADY_TODAY' THEN n_already := n_already + 1;
        ELSE n_skipped := n_skipped + 1; END IF;
        student := r.id; outcome := v_out; courses := v_courses; amount := v_amount;
        RETURN NEXT;
    END LOOP;

    INSERT INTO finance.gst_unpaid_reminder (session, list_office, asked, sent, already, skipped, sent_by, sent_office)
    VALUES (p_session, v_list, v_asked, n_sent, n_already, n_skipped, who, by_office);
END $fn$;
COMMENT ON FUNCTION finance.gst_unpaid_remind(text, text, uuid[]) IS
  'V691: the GST fee reminder to students with a GST/EPS course registered and the fee unpaid — each checked again (on the kept population, no GST payment confirmed since, a GST/EPS course still registered, the fee stated) and told at most once a day: SENT, ALREADY_TODAY, NOT_UNPAID, NOT_REGISTERED, FEE_NOT_STATED, NOT_LISTED or NO_CONTACT. The GST office, the EPS office or the Bursary (GST_REMIND_OFFICE); up to 5,000 at a time (GST_REMIND_MANY); each sending written down in finance.gst_unpaid_reminder.';

-- ── 4 · the gate over many courses at once ───────────────────────────────────────────────────────────────────────────────
-- V690's registration.gst_gate, word for word, over a list of courses: the setting and the student's entitlement read once; the
-- registration page's GST/EPS courses and those the student may add as a carry-over read once, and only if a course reaches them
CREATE FUNCTION registration.gst_gate_many(p_student uuid, p_session text, p_courses text[])
RETURNS TABLE(course_code text, message text)
LANGUAGE sql STABLE AS $fn$
    WITH want AS (SELECT DISTINCT u AS code FROM unnest(p_courses) u WHERE u IS NOT NULL),
         c AS (SELECT w.code, x.kind, x.general_office
                 FROM want w LEFT JOIN LATERAL (SELECT k.kind, k.general_office FROM catalogue.course k WHERE k.code = w.code LIMIT 1) x ON true),
         g AS (SELECT * FROM finance.gst_setting WHERE id = 1),
         e AS (SELECT * FROM finance.gst_entitlement(p_student, p_session)),
         payable AS MATERIALIZED (SELECT pc.course_code FROM finance.gst_payable_courses(p_student, p_session) pc),
         carry AS MATERIALIZED (SELECT cp.course_code FROM finance.gst_carry_payable(p_student, p_session) cp)
    SELECT c.code,
           CASE WHEN e.required AND e.stated AND e.fee > 0 AND NOT e.entitled
                     AND ((g.required_for_gst_eps AND c.kind = 'GST' AND c.general_office IS NOT NULL AND (c.general_office = 'GST' OR g.covers_eps))
                          OR g.required_for_all)
                -- V645: a GST/EPS course is held as before; any other course is held unless the student is at 400 Level and owes
                -- for their GST history only (read last, so the engine is asked only of a student it may concern)
                THEN CASE WHEN (c.kind = 'GST' AND c.general_office IS NOT NULL) OR NOT registration.gst_history_only(p_student, p_session)
                          THEN 'GST_PAYMENT_REQUIRED: you are required to pay the GST fee of NGN ' || to_char(e.fee, 'FM999,999,999,990.00') || ' for ' || p_session
                               || ' before you can register ' || CASE WHEN c.general_office IS NOT NULL THEN c.general_office || ' courses' ELSE 'your courses' END
                               || '. GST payment covers both GST and EPS requirements.' END
                -- V643: a GST/EPS course the registration page shows, not yet owed; V690: and one the student may add as a carry-over
                WHEN NOT e.required AND e.stated AND e.fee > 0 AND NOT e.entitled
                     AND c.kind = 'GST' AND c.general_office IS NOT NULL
                     AND ((g.required_for_gst_eps AND (c.general_office = 'GST' OR g.covers_eps)) OR g.required_for_all)
                THEN CASE WHEN EXISTS (SELECT 1 FROM payable pc WHERE pc.course_code = c.code)
                            OR EXISTS (SELECT 1 FROM carry cp WHERE cp.course_code = c.code)
                          THEN 'GST_PAYMENT_REQUIRED: you are required to pay the GST fee of NGN ' || to_char(e.fee, 'FM999,999,999,990.00') || ' for ' || p_session
                               || ' before you can register ' || c.general_office || ' courses. GST payment covers both GST and EPS requirements.' END
                ELSE NULL END
      FROM c CROSS JOIN g CROSS JOIN e
$fn$;
COMMENT ON FUNCTION registration.gst_gate_many(uuid, text, text[]) IS
  'V691: registration.gst_gate over many courses at once — each course with the refusal it would meet (GST_PAYMENT_REQUIRED and the amount), or NULL — the GST setting, the student''s entitlement, the registration page''s GST/EPS courses and those they may add as a carry-over each read once.';

CREATE OR REPLACE FUNCTION registration.gst_gate(p_student uuid, p_session text, p_course text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT m.message FROM registration.gst_gate_many(p_student, p_session, ARRAY[p_course]) m
$function$;
COMMENT ON FUNCTION registration.gst_gate(uuid, text, text) IS
  'The GST fee''s hold on one course (V314, V366, V643, V645, V690): the refusal GST_PAYMENT_REQUIRED with the amount, or NULL. V691: registration.gst_gate_many over the one course — one rule.';

COMMIT;
