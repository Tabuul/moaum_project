-- ═══════════════════════════════════════════════════════════════════════════
-- V344 — JUPEB: acting on the attendance minimum
--
--   V342 recorded the minimum attendance (attendance.policy) and judged each subject against it. V344 acts on it:
--
--   1. STANDING. attendance.jupeb_standing(session) gives every JUPEB student's rate per subject and semester, the verdict
--      against the minimum and two refinements the JUPEB Office sets on the same policy: a WARNING BAND (students above the
--      minimum by fewer than so many points are "at risk"; none when not set) and the MINIMUM CLASSES counted before anybody is
--      warned (a single absence in the first class is not a 0% to shout about). Nothing is invented: with no minimum set,
--      nobody is below it or at risk.
--   2. WARNINGS. A new reminder, ATTENDANCE_LOW, joins V343's: a student below the minimum in any subject (once the minimum
--      number of classes is counted) is told which subjects and by how much — on the JUPEB Office's rule (start, spacing,
--      cap, SMS) and at most one reminder a day, like the others; the office can also warn them at once. No sanction follows
--      from it here: what a shortfall means for the examination is the University's decision.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V344: JUPEB acting on the attendance minimum', true);

-- ── 1 · the policy's two refinements ─────────────────────────────────────────────────────────────
ALTER TABLE attendance.policy ADD COLUMN warn_band numeric(5,2) NULL CHECK (warn_band IS NULL OR warn_band BETWEEN 0 AND 50);
ALTER TABLE attendance.policy ADD COLUMN min_classes int NOT NULL DEFAULT 3 CHECK (min_classes BETWEEN 1 AND 50);
COMMENT ON COLUMN attendance.policy.warn_band IS 'V344: a student above the minimum by fewer than this many percentage points is at risk; NULL: nobody is flagged at risk';
COMMENT ON COLUMN attendance.policy.min_classes IS 'V344: the classes (not excused) counted in a subject before a student below the minimum is warned';

/* the policy in force for a session: its own row, else the default ('*') */
CREATE OR REPLACE FUNCTION attendance.policy_of(p_context text, p_session text)
RETURNS TABLE (min_percent numeric, warn_band numeric, min_classes int)
LANGUAGE sql STABLE AS $$
    SELECT p.min_percent, p.warn_band, p.min_classes FROM attendance.policy p
     WHERE p.context = p_context AND p.session IN (p_session, '*') ORDER BY (p.session = '*') LIMIT 1
$$;

-- ── 2 · a member's summary, with the classes counted and the at-risk flag ────────────────────────
DROP FUNCTION attendance.member_summary(text, uuid, text);
CREATE FUNCTION attendance.member_summary(p_context text, p_member uuid, p_session text)
RETURNS TABLE (session text, semester int, subject_ref uuid, total int, present int, absent int, late int, excused int, rate numeric, min_percent numeric,
               verdict text, counted int, at_risk boolean, warnable boolean)
LANGUAGE sql STABLE AS $$
    WITH m AS (SELECT r.session, r.semester, r.subject_ref, k.status
                 FROM attendance.mark k JOIN attendance.register r ON r.id = k.register_id
                WHERE r.context = p_context AND k.member_ref = p_member AND (p_session IS NULL OR r.session = p_session)),
    g AS (SELECT m.session, m.semester, m.subject_ref, count(*)::int AS total,
                 count(*) FILTER (WHERE status = 'PRESENT')::int AS present, count(*) FILTER (WHERE status = 'ABSENT')::int AS absent,
                 count(*) FILTER (WHERE status = 'LATE')::int AS late, count(*) FILTER (WHERE status = 'EXCUSED')::int AS excused
            FROM m GROUP BY m.session, m.semester, m.subject_ref),
    r AS (SELECT g.*, g.total - g.excused AS counted,
                 CASE WHEN g.total - g.excused > 0 THEN round(100.0 * (g.present + g.late) / (g.total - g.excused), 2) END AS rate,
                 pol.min_percent, pol.warn_band, coalesce(pol.min_classes, 3) AS min_classes
            FROM g LEFT JOIN LATERAL attendance.policy_of(p_context, g.session) pol ON true)
    SELECT r.session, r.semester, r.subject_ref, r.total, r.present, r.absent, r.late, r.excused, r.rate, r.min_percent,
           CASE WHEN r.min_percent IS NULL THEN NULL WHEN r.counted = 0 THEN 'REQUIRES_REVIEW'
                WHEN r.rate >= r.min_percent THEN 'ELIGIBLE' ELSE 'NOT_ELIGIBLE' END,
           r.counted,
           coalesce(r.min_percent IS NOT NULL AND r.warn_band IS NOT NULL AND r.counted > 0 AND r.rate >= r.min_percent AND r.rate < r.min_percent + r.warn_band, false),
           coalesce(r.min_percent IS NOT NULL AND r.counted >= r.min_classes AND r.rate < r.min_percent, false)
      FROM r
$$;

/* every JUPEB student of a session, subject by subject: the rate, the verdict, at risk, and whether a warning is due */
CREATE OR REPLACE FUNCTION attendance.jupeb_standing(p_session text)
RETURNS TABLE (member_ref uuid, application_no text, name text, exam_no text, class_name text, semester int, subject_ref uuid, code text, title text,
               total int, counted int, absent int, rate numeric, min_percent numeric, verdict text, at_risk boolean, warnable boolean)
LANGUAGE sql STABLE AS $$
    SELECT a.id, a.application_no, a.surname || ', ' || a.first_name || coalesce(' ' || a.middle_name, ''), a.exam_no, cl.name, m.semester, m.subject_ref, s.code, s.title,
           m.total, m.counted, m.absent, m.rate, m.min_percent, m.verdict, m.at_risk, m.warnable
      FROM jupeb.application a
      CROSS JOIN LATERAL attendance.member_summary('JUPEB', a.id, p_session) m
      JOIN jupeb.subject s ON s.id = m.subject_ref
      LEFT JOIN jupeb.class cl ON cl.id = a.class_id
     WHERE a.session = p_session AND a.state IN ('STUDENT', 'COMPLETED')
$$;

-- ── 3 · the warning, one of V343's reminders ─────────────────────────────────────────────────────
ALTER TABLE jupeb.reminder_rule DROP CONSTRAINT reminder_rule_kind_check;
ALTER TABLE jupeb.reminder_rule ADD CONSTRAINT reminder_rule_kind_check
    CHECK (kind IN ('FEE_UNPAID', 'SUBMIT_PENDING', 'PASSPORT_MISSING', 'CHECKING_OPEN', 'ACCEPTANCE_UNPAID', 'SCHOOL_FEE_UNPAID', 'ATTENDANCE_LOW'));
INSERT INTO jupeb.reminder_rule (kind, first_after_days, every_days, max_count, ord) VALUES ('ATTENDANCE_LOW', 0, 7, 4, 7);

/* V343's, knowing the attendance warning, and able to answer for one kind (the office warning at once) before the one-a-day choice */
DROP FUNCTION jupeb.due_reminders(timestamptz);
CREATE FUNCTION jupeb.due_reminders(p_now timestamptz, p_kind text DEFAULT NULL)
RETURNS TABLE (application_id uuid, application_no text, name text, kind text, sent_before int, last_sent timestamptz, detail jsonb)
LANGUAGE sql STABLE AS $$
    WITH a AS (
        SELECT x.id, x.state, x.session, x.created_at, x.fee_confirmed_at, x.returned_at, x.submitted_at, x.activated_at, x.screening_state,
               w.state AS app_window, w.closes_at AS app_closes, ck.valid, ck.window_open AS chk_open, ck.paid AS chk_paid, ck.paid_at AS chk_paid_at,
               ck.may_check, ck.status AS adm_status, jupeb.paid_at(x.id, 'ACCEPTANCE') AS acc_at
          FROM jupeb.application x
          CROSS JOIN LATERAL policy.window_state('JUPEB_APPLICATION', x.session, NULL) w
          CROSS JOIN LATERAL jupeb.status_checking(x.id) ck
         WHERE x.state IN ('DRAFT', 'RETURNED', 'SUBMITTED', 'ELIGIBLE', 'PENDING', 'ADMITTED', 'STUDENT')
    ), cand AS (
        SELECT a.id, 'FEE_UNPAID'::text AS kind, a.created_at AS anchor, jsonb_build_object('closes', a.app_closes) AS detail
          FROM a WHERE a.state = 'DRAFT' AND a.fee_confirmed_at IS NULL AND a.app_window = 'OPEN'
        UNION ALL
        SELECT a.id, 'SUBMIT_PENDING', greatest(a.fee_confirmed_at, coalesce(a.returned_at, a.fee_confirmed_at)), jsonb_build_object('closes', a.app_closes, 'returned', a.state = 'RETURNED')
          FROM a WHERE a.state IN ('DRAFT', 'RETURNED') AND a.fee_confirmed_at IS NOT NULL AND a.app_window = 'OPEN'
        UNION ALL
        SELECT a.id, 'PASSPORT_MISSING', a.created_at, jsonb_build_object('closes', a.app_closes)
          FROM a WHERE a.state IN ('DRAFT', 'RETURNED') AND a.app_window = 'OPEN'
           AND NOT EXISTS (SELECT 1 FROM jupeb.document d WHERE d.application_id = a.id AND d.kind = 'PASSPORT' AND d.status NOT IN ('REJECTED', 'REPLACEMENT_REQUIRED'))
        UNION ALL
        SELECT a.id, 'CHECKING_OPEN', a.submitted_at, '{}'::jsonb
          FROM a WHERE a.valid AND a.chk_open AND NOT a.chk_paid AND a.state NOT IN ('STUDENT')
        UNION ALL
        SELECT a.id, 'ACCEPTANCE_UNPAID', a.chk_paid_at, '{}'::jsonb
          FROM a WHERE a.state = 'ADMITTED' AND a.may_check AND a.adm_status = 'ADMITTED' AND a.acc_at IS NULL
        UNION ALL
        SELECT a.id, 'SCHOOL_FEE_UNPAID', a.acc_at, jsonb_build_object('first', true)
          FROM a WHERE a.state = 'ADMITTED' AND a.acc_at IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM jupeb.fee_reference f WHERE f.application_id = a.id AND f.kind LIKE 'SCHOOL%' AND f.confirmed_at IS NOT NULL)
           AND (NOT (jupeb.setting_of(a.session)).screening_required OR a.screening_state = 'CLEARED')
        UNION ALL
        SELECT a.id, 'SCHOOL_FEE_UNPAID', a.activated_at, jsonb_build_object('first', false, 'outstanding', sf.outstanding)
          FROM a CROSS JOIN LATERAL jupeb.school_fees(a.id) sf WHERE a.state = 'STUDENT' AND sf.outstanding > 0
        UNION ALL
        /* V344: below the attendance minimum in a subject, once enough classes are counted */
        SELECT a.id, 'ATTENDANCE_LOW', coalesce(a.activated_at, a.submitted_at, a.created_at), '{}'::jsonb
          FROM a WHERE a.state = 'STUDENT' AND EXISTS (SELECT 1 FROM attendance.member_summary('JUPEB', a.id, a.session) m WHERE m.warnable)
    ), due AS (
        SELECT DISTINCT ON (c.id) c.id, c.kind, c.detail, s.n, s.last
          FROM cand c
          JOIN jupeb.reminder_rule r ON r.kind = c.kind AND r.enabled
          CROSS JOIN LATERAL (SELECT count(*)::int AS n, max(l.sent_at) AS last FROM jupeb.reminder_log l WHERE l.application_id = c.id AND l.kind = c.kind) s
         WHERE (p_kind IS NULL OR c.kind = p_kind)
           AND c.anchor IS NOT NULL AND c.anchor + make_interval(days => r.first_after_days) <= p_now
           AND s.n < r.max_count AND (s.last IS NULL OR s.last + make_interval(days => r.every_days) <= p_now)
           AND NOT EXISTS (SELECT 1 FROM jupeb.reminder_log l WHERE l.application_id = c.id AND l.sent_at > p_now - interval '20 hours')
         ORDER BY c.id, r.ord
    )
    SELECT d.id, x.application_no, x.surname || ', ' || x.first_name || coalesce(' ' || x.middle_name, ''), d.kind, d.n, d.last, d.detail
      FROM due d JOIN jupeb.application x ON x.id = d.id
     ORDER BY x.application_no
$$;

CREATE OR REPLACE FUNCTION jupeb.reminder_words(p_app uuid, p_kind text, p_detail jsonb, p_portal text)
RETURNS text[] LANGUAGE plpgsql STABLE AS $$
DECLARE a jupeb.application; fs record; sf record; v_url text := rtrim(coalesce(p_portal, ''), '/') || '/jupeb/portal'; v_closes text;
        subj text; body text; v_list text; v_min numeric;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app;
    SELECT * INTO fs FROM jupeb.fee_setting_of(a.session);
    v_closes := CASE WHEN p_detail->>'closes' IS NOT NULL
                     THEN ' before the application window closes on ' || to_char(((p_detail->>'closes')::timestamptz AT TIME ZONE 'Africa/Lagos'), 'FMDD Mon YYYY') ELSE '' END;
    IF p_kind = 'FEE_UNPAID' THEN
        subj := 'Your JUPEB application: the application fee is not yet paid';
        body := 'Your JUPEB application is started, but the application fee of ₦' || to_char(fs.application_fee, 'FM999,999,990') || ' is not yet paid. '
             || 'Sign in at ' || v_url || ' to pay it and complete your application' || v_closes || '.';
    ELSIF p_kind = 'SUBMIT_PENDING' THEN
        subj := CASE WHEN (p_detail->>'returned')::boolean THEN 'Your JUPEB application: submit your correction' ELSE 'Your JUPEB application is not yet submitted' END;
        body := CASE WHEN (p_detail->>'returned')::boolean THEN 'The JUPEB Office returned your application for a correction and it is not yet resubmitted. '
                     ELSE 'Your application fee is paid, but your JUPEB application is not yet submitted. ' END
             || 'Sign in at ' || v_url || ', complete the remaining steps and submit' || v_closes || '.';
    ELSIF p_kind = 'PASSPORT_MISSING' THEN
        subj := 'Your JUPEB application: upload your passport photograph';
        body := 'Your JUPEB application has no passport photograph yet. Upload a clear, recent passport photograph (JPEG or PNG) at ' || v_url || v_closes || '.';
    ELSIF p_kind = 'CHECKING_OPEN' THEN
        subj := 'JUPEB admission status checking is open';
        body := 'Admission status checking is open. Sign in at ' || v_url || ' to check your admission status; the status checking fee of ₦'
             || to_char(fs.checking_fee, 'FM999,999,990') || ' is paid once.';
    ELSIF p_kind = 'ACCEPTANCE_UNPAID' THEN
        subj := 'Accept your JUPEB admission';
        body := 'You are offered admission into the JUPEB programme. Accept it by paying the acceptance fee of ₦' || to_char(fs.acceptance_fee, 'FM999,999,990')
             || ' at ' || v_url || '; your acceptance letter and school fees follow.';
    ELSIF p_kind = 'SCHOOL_FEE_UNPAID' THEN
        SELECT * INTO sf FROM jupeb.school_fees(p_app);
        IF coalesce((p_detail->>'first')::boolean, true) THEN
            subj := 'Pay your JUPEB school fee to begin';
            body := 'Your admission is accepted. Pay the first semester''s school fee of ₦' || to_char(sf.first_amount, 'FM999,999,990')
                 || ' at ' || v_url || ' to activate your studentship and register your subjects.';
        ELSE
            subj := 'Your JUPEB school fee balance';
            body := 'You have an outstanding JUPEB school fee balance of ₦' || to_char(sf.outstanding, 'FM999,999,990') || '. Pay it at ' || v_url || '.';
        END IF;
    ELSIF p_kind = 'ATTENDANCE_LOW' THEN
        SELECT string_agg(s.title || ' ' || trim(to_char(m.rate, 'FM990.##')) || '%' || CASE WHEN m.semester IS NOT NULL THEN ' (semester ' || m.semester || ')' ELSE '' END,
                          ', ' ORDER BY s.title, m.semester), max(m.min_percent)
          INTO v_list, v_min
          FROM attendance.member_summary('JUPEB', p_app, a.session) m JOIN jupeb.subject s ON s.id = m.subject_ref WHERE m.warnable;
        IF v_list IS NULL THEN RETURN NULL; END IF;
        subj := 'Your JUPEB attendance is below the minimum';
        body := 'Your attendance is below the University''s minimum of ' || trim(to_char(v_min, 'FM990.##')) || '% in: ' || v_list || '. '
             || 'Attend every class from now on. If you were absent for a good reason, see the JUPEB Office: an excused absence does not count against you. '
             || 'Your attendance, class by class, is at ' || v_url || '.';
    ELSE
        RETURN NULL;
    END IF;
    RETURN ARRAY[subj, body, subj || '. ' || v_url];
END $$;

/* V343's sender, with an optional kind: the JUPEB Office warns students below the attendance minimum at once */
DROP FUNCTION jupeb.send_reminders(timestamptz, text, int, text);
CREATE FUNCTION jupeb.send_reminders(p_now timestamptz, p_portal text, p_limit int, p_trigger text, p_kind text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE d record; w text[]; r jupeb.reminder_rule; n int := 0; v_by jsonb := '{}'::jsonb; a jupeb.application;
BEGIN
    FOR d IN SELECT * FROM jupeb.due_reminders(p_now, p_kind) LIMIT greatest(coalesce(p_limit, 500), 0) LOOP
        w := jupeb.reminder_words(d.application_id, d.kind, d.detail, p_portal);
        CONTINUE WHEN w IS NULL;
        SELECT * INTO r FROM jupeb.reminder_rule WHERE kind = d.kind;
        SELECT * INTO a FROM jupeb.application WHERE id = d.application_id;
        PERFORM jupeb.tell(d.application_id, w[1], w[2]);
        IF r.sms AND a.phone IS NOT NULL THEN
            PERFORM platform.queue_notice('SMS', a.phone, w[1], w[3], 'jupeb_application', d.application_id);
        END IF;
        INSERT INTO jupeb.reminder_log (application_id, kind, sent_at, by_sms, trigger)
        VALUES (d.application_id, d.kind, p_now, r.sms AND a.phone IS NOT NULL, coalesce(p_trigger, 'SCHEDULE'));
        n := n + 1;
        v_by := jsonb_set(v_by, ARRAY[d.kind], to_jsonb(coalesce((v_by->>d.kind)::int, 0) + 1));
    END LOOP;
    RETURN jsonb_build_object('sent', n, 'byKind', v_by);
END $$;

COMMIT;
