-- ═══════════════════════════════════════════════════════════════════════════
-- V295 — admission status checking for every valid Post-UTME applicant,
--        opened and closed by the Director of ICT
--
--   V271 made the admission checking fee a payment of its own, but it could be
--   generated only once a decision had been released ("there is no decision to
--   check yet"), a decision not yet released showed as pending for nothing, and
--   the release notice itself told the applicant the decision by email and SMS.
--   In practice the service reached only the applicants the list or the Board
--   had already decided, and the result reached everyone without it. Admission
--   status is the output of checking, never its condition:
--
--   · who may check: an applicant with a valid Post-UTME application — the
--     application fee confirmed and the application submitted (an imported
--     applicant carries both) — admitted, not admitted or not yet decided;
--   · when: while the Director of ICT has ADMISSION_STATUS_CHECKING open for
--     the session, a third window on V288's architecture (open, close, reopen,
--     schedule, extend, shorten, edit, the history kept), session-wide, with no
--     late period, and CLOSED until first opened;
--   · for what: the admission checking fee the Bursary states (V271/V277), paid
--     once for the exercise on the existing reference, gateway and receipt; a
--     reference still open is reused rather than a second one issued; checking
--     again (pending today, admitted later) costs nothing more; failed or
--     unconfirmed payments do not count;
--   · the status comes from the released decision as before (admitted, waiting
--     list, not admitted, pending); paying generates nothing. Each check is kept
--     in admissions.status_check with the result it returned; the first reading
--     of an offer is stamped on the application and congratulated;
--   · an applicant who has read an offer and whose acceptance is under way
--     continues whatever the window; everyone else reads nothing of the
--     decision — status, tracker, document list or notice — until they may
--     check it, and the offer is paid for, accepted or declined only once it
--     has been read (ADMISSION_STATUS_NOT_CHECKED, the same answer whatever
--     the decision, so no refusal says whether there is an offer);
--   · opening, extending and closing are told to the session's valid applicants;
--     the release notice says a decision is released, not what it is.
--
--   admissions.status_checking(app) is the one evaluation every path reads:
--   the application, the window, the fee, whether it is paid, what may be done.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V295: admission status checking for every valid Post-UTME applicant', true);

-- ── 1 · the window: a third type, for the admission exercise of a session ────────────────────
ALTER TABLE policy.portal_window DROP CONSTRAINT IF EXISTS portal_window_window_type_check;
ALTER TABLE policy.portal_window ADD CONSTRAINT portal_window_window_type_check
    CHECK (window_type IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING'));
ALTER TABLE policy.portal_window ADD CONSTRAINT ck_window_checking_session
    CHECK (window_type <> 'ADMISSION_STATUS_CHECKING' OR (semester IS NULL AND late_until IS NULL AND NOT late_fee_enabled));

-- ── 2 · every check, with what it returned ────────────────────────────────────────────────────
CREATE TABLE admissions.status_check (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id       uuid NOT NULL REFERENCES admissions.application(id) ON DELETE CASCADE,
    session              text NOT NULL,
    checked_at           timestamptz NOT NULL DEFAULT now(),
    result               text NOT NULL,
    label                text,
    decision_released_at timestamptz,
    reference            text,
    window_state         text
);
CREATE INDEX ix_status_check_application ON admissions.status_check (application_id, checked_at DESC);
CREATE INDEX ix_status_check_session ON admissions.status_check (session, checked_at DESC);
COMMENT ON TABLE admissions.status_check IS 'Each time an applicant checked their admission status (V295): the status returned, the decision''s release it stood on, the checking reference that paid for it, the window. Insert-only; who and from where are on the audit spine.';
SELECT audit.attach('admissions.status_check');
GRANT SELECT, INSERT ON admissions.status_check TO app_admissions;
-- the admissions module reads the Director of ICT's window for the session (V288 granted it to the student module)
GRANT SELECT ON policy.portal_window, policy.portal_window_event TO app_admissions;

-- ── 3 · the one evaluation: the application, the window, the fee — never the decision ─────────
CREATE OR REPLACE FUNCTION admissions.status_checking(p_app uuid)
RETURNS TABLE (application_id uuid, session text, application_valid boolean, window_state text, window_open boolean,
               opens_at timestamptz, closes_at timestamptz, fee numeric, fee_required boolean,
               paid boolean, paid_at timestamptz, paid_reference text, open_reference text, open_reference_expires timestamptz,
               past boolean, may_pay boolean, may_check boolean, decision_visible boolean, reason text,
               checks bigint, last_checked_at timestamptz, last_result text)
LANGUAGE sql STABLE AS $fn$
    WITH a AS (SELECT * FROM admissions.application WHERE id = p_app),
    w AS (SELECT ws.state, ws.opens_at, ws.closes_at FROM a CROSS JOIN LATERAL policy.window_state('ADMISSION_STATUS_CHECKING', a.session, NULL) ws),
    f AS (SELECT coalesce((SELECT r.checking_fee FROM a CROSS JOIN LATERAL admissions.applicant_fee_rule(a.session) r), 0)::numeric AS fee),
    pay AS (SELECT min(r.confirmed_at) FILTER (WHERE r.kind = 'CHECKING') AS ck_at,
                   (array_agg(r.reference ORDER BY r.confirmed_at) FILTER (WHERE r.kind = 'CHECKING'))[1] AS ck_ref,
                   coalesce(bool_or(r.kind = 'ACCEPTANCE'), false) AS acc
              FROM admissions.fee_reference r WHERE r.application_id = p_app AND r.confirmed_at IS NOT NULL),
    o AS (SELECT r.reference, r.expires_at FROM admissions.fee_reference r
           WHERE r.application_id = p_app AND r.kind = 'CHECKING' AND r.confirmed_at IS NULL AND r.expires_at > now()
           ORDER BY r.generated_at DESC LIMIT 1),
    k AS (SELECT count(*) AS n, max(c.checked_at) AS last_at, (array_agg(c.result ORDER BY c.checked_at DESC))[1] AS last_result
            FROM admissions.status_check c WHERE c.application_id = p_app),
    x AS (
        SELECT a.id, a.session,
               (a.fee_confirmed_at IS NOT NULL AND a.submitted_at IS NOT NULL) AS valid,
               w.state AS wstate, w.state = 'OPEN' AS wopen, w.opens_at, w.closes_at,
               f.fee, f.fee > 0 AS required,
               -- an acceptance confirmed under the old rule (V148) included the checking fee: it counts as paid
               (a.checking_confirmed_at IS NOT NULL OR pay.ck_at IS NOT NULL OR a.acceptance_confirmed_at IS NOT NULL OR pay.acc) AS paid,
               coalesce(a.checking_confirmed_at, pay.ck_at) AS paid_at, pay.ck_ref,
               -- the offer has been read and the admission is under way: the workflow continues whatever the window
               (a.decision_released_at IS NOT NULL AND a.decision = 'OFFERED'
                AND (a.status_checked_at IS NOT NULL OR a.undertaking_at IS NOT NULL OR a.acceptance_confirmed_at IS NOT NULL
                     OR a.accepted_at IS NOT NULL OR a.declined_at IS NOT NULL OR pay.acc)) AS past
          FROM a, w, f, pay)
    SELECT x.id, x.session, x.valid, x.wstate, x.wopen, x.opens_at, x.closes_at, x.fee, x.required,
           x.paid, x.paid_at, x.ck_ref, (SELECT o.reference FROM o), (SELECT o.expires_at FROM o),
           x.past,
           x.valid AND x.wopen AND x.required AND NOT x.paid,
           x.valid AND x.wopen AND (x.paid OR NOT x.required),
           x.past OR (x.valid AND x.wopen AND (x.paid OR NOT x.required)),
           CASE WHEN x.past THEN NULL WHEN NOT x.valid THEN 'APPLICATION_INCOMPLETE' WHEN NOT x.wopen THEN 'CHECKING_CLOSED'
                WHEN x.required AND NOT x.paid THEN 'CHECKING_FEE_UNPAID' END,
           k.n, k.last_at, k.last_result
      FROM x, k
$fn$;
COMMENT ON FUNCTION admissions.status_checking(uuid) IS
  'Admission Status Checking for one application (V295): a valid Post-UTME application (fee confirmed, submitted), the Director of ICT''s window, the checking fee and whether it is paid; what may be paid, checked and seen. The admission decision is not a condition.';

/* the checking fee is owed before the status can be read: a valid application, a fee stated, not yet paid, no admission under way */
CREATE OR REPLACE FUNCTION admissions.checking_due(p_app uuid)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT c.application_valid AND c.fee_required AND NOT c.paid AND NOT c.past FROM admissions.status_checking(p_app) c), false);
$fn$;

/* the applicant's check: allowed only through the service, kept each time with its result; the first reading of an offer stamped and congratulated */
CREATE OR REPLACE FUNCTION admissions.admission_status_checked(p_app uuid)
RETURNS timestamptz LANGUAGE plpgsql AS $fn$
DECLARE c record; st record; a admissions.application; v timestamptz; first_offer boolean;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    SELECT * INTO c FROM admissions.status_checking(p_app);
    IF NOT c.may_check THEN
        -- an admission already under way is not checked again; it is continued
        IF c.past THEN RETURN a.status_checked_at; END IF;
        RAISE EXCEPTION '%', CASE c.reason
            WHEN 'APPLICATION_INCOMPLETE' THEN 'ADMISSION_CHECKING_NOT_ELIGIBLE: admission status checking is for applicants whose Post-UTME application is paid for and submitted'
            WHEN 'CHECKING_CLOSED' THEN 'ADMISSION_CHECKING_CLOSED: admission status checking is currently closed; please check back when the University opens it'
            ELSE 'ADMISSION_CHECKING_FEE_UNPAID: the admission checking fee is paid, and confirmed, before the admission status is checked' END
            USING ERRCODE = '23514';
    END IF;
    first_offer := a.status_checked_at IS NULL AND a.decision = 'OFFERED' AND a.decision_released_at IS NOT NULL;
    UPDATE admissions.application SET status_checked_at = coalesce(status_checked_at, now())
     WHERE id = p_app AND decision_released_at IS NOT NULL RETURNING status_checked_at INTO v;
    SELECT * INTO st FROM admissions.admission_status(p_app);
    INSERT INTO admissions.status_check (application_id, session, result, label, decision_released_at, reference, window_state)
    VALUES (p_app, a.session, st.status, st.label, a.decision_released_at, c.paid_reference, c.window_state);
    IF first_offer THEN
        PERFORM admissions.notify_applicant(p_app, 'Congratulations! You have been offered admission',
            'Congratulations! You have been offered provisional admission to Rev. Fr. Moses Orshio Adasu University, Makurdi, for the ' || a.session || ' session.' || chr(10) || chr(10)
            || 'Sign in to the applicant portal and open Admission Status to read the offer — programme, faculty, department — then accept it and pay the acceptance fee. An offer that lapses cannot be reinstated.',
            'MOAUM: Congratulations! You have been offered admission. Sign in to accept the offer.');
    END IF;
    RETURN coalesce(v, now());
END $fn$;
COMMENT ON FUNCTION admissions.admission_status_checked(uuid) IS
  'The applicant checks their admission status (V295): refused unless admissions.status_checking allows it (ADMISSION_CHECKING_NOT_ELIGIBLE, _CLOSED, _FEE_UNPAID); each check is kept with its result.';

-- ── 4 · the applicants told when checking opens, is extended or closes ────────────────────────
CREATE OR REPLACE FUNCTION admissions.tell_status_checking(p_session text, p_action text)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE n int := 0; r record; w record; subj text; body text; sms text;
BEGIN
    SELECT * INTO w FROM policy.window_state('ADMISSION_STATUS_CHECKING', p_session, NULL);
    IF p_action = 'CLOSE' THEN
        subj := 'Admission Status Checking is closed';
        body := 'Admission status checking for the ' || p_session || ' admission exercise is closed from now.' || coalesce(' ' || w.reason, '')
                || ' An admission checking fee already paid stands: you will not pay again when checking reopens.';
        sms := 'MOAUM: Admission Status Checking is closed. A checking fee already paid stands.';
    ELSE
        subj := CASE WHEN p_action = 'EXTEND' THEN 'Admission Status Checking has been extended' ELSE 'Admission Status Checking is now open' END;
        body := 'Admission Status Checking is ' || CASE WHEN p_action = 'EXTEND' THEN 'extended' ELSE 'now open' END || ' for the ' || p_session || ' admission exercise'
                || CASE WHEN w.closes_at IS NOT NULL THEN ', until ' || to_char(w.closes_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY "at" HH24:MI') ELSE '' END
                || '. Sign in to the applicant portal, pay the admission checking fee once, and check your admission status.';
        sms := 'MOAUM: Admission Status Checking is ' || CASE WHEN p_action = 'EXTEND' THEN 'extended' ELSE 'now open' END || '. Sign in, pay the checking fee once and check your status.';
    END IF;
    -- the session's valid applicants, less those who have read an offer and are on their way: checking no longer concerns them
    FOR r IN SELECT a.id FROM admissions.application a
              WHERE a.session = p_session AND a.fee_confirmed_at IS NOT NULL AND a.submitted_at IS NOT NULL
                AND NOT coalesce((SELECT k.past FROM admissions.status_checking(a.id) k), false) LOOP
        PERFORM admissions.notify_applicant(r.id, subj, body, sms);
        n := n + 1;
    END LOOP;
    RETURN n;
END $fn$;

-- ── 5 · what ICT and Admissions read: every application of a session, and the counts ──────────
CREATE OR REPLACE FUNCTION admissions.status_checking_rows(p_session text)
RETURNS TABLE (application_id uuid, application_no text, jamb_reg_no text, name text, sex text, programme text, programme_code text,
               faculty_code text, faculty text, dept_code text, department text, valid boolean, paid boolean, paid_at timestamptz,
               reference text, amount numeric, checked boolean, checks bigint, first_checked_at timestamptz, last_checked_at timestamptz,
               last_result text, result text)
LANGUAGE sql STABLE AS $fn$
    SELECT a.id, a.application_no, c.jamb_reg_no, c.surname || ', ' || c.other_names, r.sex, c.programme, p.code,
           p.faculty_code, fa.name, p.dept_code, d.name,
           (a.fee_confirmed_at IS NOT NULL AND a.submitted_at IS NOT NULL),
           (a.checking_confirmed_at IS NOT NULL OR ck.confirmed_at IS NOT NULL OR a.acceptance_confirmed_at IS NOT NULL),
           coalesce(a.checking_confirmed_at, ck.confirmed_at), ck.reference, ck.amount,
           (k.n > 0 OR a.status_checked_at IS NOT NULL), k.n, coalesce(k.first_at, a.status_checked_at), coalesce(k.last_at, a.status_checked_at), k.last_result,
           CASE WHEN a.decision_released_at IS NULL OR a.decision IS NULL THEN 'PENDING'
                WHEN a.decision = 'OFFERED' THEN 'ADMITTED' WHEN a.decision = 'WAITING' THEN 'WAITING_LIST' ELSE 'NOT_ADMITTED' END
      FROM admissions.application a
      JOIN admissions.candidate c ON c.id = a.candidate_id
      LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
      LEFT JOIN ref.programme p ON p.code = admissions.programme_code_of(c.programme)
      LEFT JOIN ref.faculty fa ON fa.code = p.faculty_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN LATERAL (SELECT x.reference, x.amount, x.confirmed_at FROM admissions.fee_reference x
                          WHERE x.application_id = a.id AND x.kind = 'CHECKING' AND x.confirmed_at IS NOT NULL ORDER BY x.confirmed_at LIMIT 1) ck ON true
      LEFT JOIN LATERAL (SELECT count(*) AS n, min(s.checked_at) AS first_at, max(s.checked_at) AS last_at,
                                (array_agg(s.result ORDER BY s.checked_at DESC))[1] AS last_result
                           FROM admissions.status_check s WHERE s.application_id = a.id) k ON true
     WHERE a.session = p_session
$fn$;
COMMENT ON FUNCTION admissions.status_checking_rows(text) IS
  'Every application of an admission session with its checking fee, its checks and its authoritative result (ADMITTED, WAITING_LIST, NOT_ADMITTED, PENDING) — the Admission Status Checking report (V295).';

CREATE OR REPLACE FUNCTION admissions.status_checking_summary(p_session text)
RETURNS TABLE (applicants bigint, eligible bigint, paid bigint, unpaid bigint, checked bigint, not_checked bigint,
               admitted bigint, not_admitted bigint, waiting bigint, pending bigint, revenue numeric, checks bigint)
LANGUAGE sql STABLE AS $fn$
    SELECT count(*), count(*) FILTER (WHERE valid), count(*) FILTER (WHERE valid AND paid), count(*) FILTER (WHERE valid AND NOT paid),
           count(*) FILTER (WHERE valid AND checked), count(*) FILTER (WHERE valid AND NOT checked),
           count(*) FILTER (WHERE valid AND result = 'ADMITTED'), count(*) FILTER (WHERE valid AND result = 'NOT_ADMITTED'),
           count(*) FILTER (WHERE valid AND result = 'WAITING_LIST'), count(*) FILTER (WHERE valid AND result = 'PENDING'),
           coalesce(sum(amount) FILTER (WHERE paid), 0), coalesce(sum(checks), 0)
      FROM admissions.status_checking_rows(p_session)
$fn$;

-- ── 6 · the functions that follow: the window, the reference, the receipt, the status, the tracker, the release ──
CREATE OR REPLACE FUNCTION policy.window_state(p_type text, p_session text, p_semester integer)
 RETURNS TABLE(configured boolean, state text, phase text, opens_at timestamp with time zone, closes_at timestamp with time zone, late_until timestamp with time zone, late_fee_enabled boolean, forced text, reason text, window_id uuid, semester integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH w AS (
        SELECT * FROM policy.portal_window
         WHERE window_type = p_type AND session = p_session AND superseded_at IS NULL
           AND (semester = p_semester OR semester IS NULL)
         ORDER BY (semester IS NOT NULL) DESC LIMIT 1)
    SELECT w.id IS NOT NULL,
           CASE WHEN w.id IS NULL THEN CASE WHEN p_type = 'ADMISSION_STATUS_CHECKING' THEN 'CLOSED' ELSE 'OPEN' END
                WHEN w.forced = 'CLOSED' THEN 'CLOSED'
                WHEN w.forced = 'OPEN' THEN 'OPEN'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'SCHEDULED'
                WHEN w.closes_at IS NULL OR now() <= w.closes_at THEN 'OPEN'
                WHEN w.late_until IS NOT NULL AND now() <= w.late_until THEN 'OPEN'
                ELSE 'EXPIRED' END,
           CASE WHEN w.id IS NULL THEN CASE WHEN p_type = 'ADMISSION_STATUS_CHECKING' THEN 'NONE' ELSE 'NORMAL' END
                WHEN w.forced = 'OPEN' THEN CASE WHEN w.late_fee_enabled THEN 'LATE' ELSE 'NORMAL' END
                WHEN w.forced = 'CLOSED' THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at AND w.late_until IS NOT NULL AND now() <= w.late_until THEN 'LATE'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at THEN 'NONE'
                ELSE 'NORMAL' END,
           w.opens_at, w.closes_at, w.late_until, coalesce(w.late_fee_enabled, false), w.forced, w.reason, w.id, w.semester
      FROM (SELECT 1) one LEFT JOIN w ON true
$function$;

CREATE OR REPLACE FUNCTION policy.window_act(p_type text, p_session text, p_semester integer, p_action text, p_opens timestamp with time zone, p_closes timestamp with time zone, p_late_until timestamp with time zone, p_late_fee boolean, p_reason text, p_actor uuid, p_office text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE cur policy.portal_window; prev record; v_forced text; v_opens timestamptz; v_closes timestamptz; v_late timestamptz; v_fee boolean; v_id uuid; nxt record;
BEGIN
    IF p_type NOT IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING') THEN RAISE EXCEPTION 'no such portal window %', p_type USING ERRCODE = '23514'; END IF;
    -- V295: admission status checking runs over the admission exercise of a session: no semester, no late period, no late fee
    IF p_type = 'ADMISSION_STATUS_CHECKING' AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_CHECKING_SESSION: admission status checking opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN RAISE EXCEPTION 'no academic session % on the calendar', p_session USING ERRCODE = '23503'; END IF;
    IF p_action NOT IN ('OPEN', 'CLOSE', 'REOPEN', 'SCHEDULE', 'EXTEND', 'SHORTEN', 'EDIT') THEN RAISE EXCEPTION 'unknown action %', p_action USING ERRCODE = '23514'; END IF;
    IF p_action IN ('CLOSE', 'REOPEN', 'SHORTEN') AND nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'the reason for % is recorded, and none was given', lower(p_action) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO cur FROM policy.portal_window WHERE window_type = p_type AND session = p_session AND coalesce(semester, 0) = coalesce(p_semester, 0) AND superseded_at IS NULL FOR UPDATE;
    SELECT * INTO prev FROM policy.window_state(p_type, p_session, p_semester);
    v_opens := coalesce(p_opens, cur.opens_at); v_closes := coalesce(p_closes, cur.closes_at); v_late := coalesce(p_late_until, cur.late_until);
    v_fee := coalesce(p_late_fee, cur.late_fee_enabled, false);
    CASE p_action
        WHEN 'OPEN', 'REOPEN' THEN v_forced := CASE WHEN p_opens IS NULL AND p_closes IS NULL THEN 'OPEN' ELSE NULL END;
                                   IF p_opens IS NULL AND p_closes IS NOT NULL THEN v_opens := now(); END IF;
        WHEN 'CLOSE' THEN v_forced := 'CLOSED';
        WHEN 'SCHEDULE' THEN IF p_opens IS NULL THEN RAISE EXCEPTION 'a schedule names when the window opens' USING ERRCODE = '23514'; END IF; v_forced := NULL;
        WHEN 'EXTEND' THEN IF p_closes IS NULL AND p_late_until IS NULL THEN RAISE EXCEPTION 'an extension names the new closing' USING ERRCODE = '23514'; END IF;
                           IF cur.id IS NOT NULL AND p_closes IS NOT NULL AND cur.closes_at IS NOT NULL AND p_closes < cur.closes_at THEN RAISE EXCEPTION 'that closing is earlier than before; shorten the window instead' USING ERRCODE = '23514'; END IF;
                           v_forced := CASE WHEN cur.forced = 'CLOSED' THEN NULL ELSE cur.forced END;
        WHEN 'SHORTEN' THEN IF p_closes IS NULL THEN RAISE EXCEPTION 'a shortening names the new closing' USING ERRCODE = '23514'; END IF; v_forced := cur.forced;
        WHEN 'EDIT' THEN v_forced := cur.forced;
    END CASE;
    IF v_closes IS NOT NULL AND v_opens IS NOT NULL AND v_closes < v_opens THEN RAISE EXCEPTION 'the window closes before it opens' USING ERRCODE = '23514'; END IF;
    IF v_late IS NOT NULL AND v_closes IS NOT NULL AND v_late < v_closes THEN RAISE EXCEPTION 'the late period ends before the window closes' USING ERRCODE = '23514'; END IF;
    IF cur.id IS NOT NULL THEN UPDATE policy.portal_window SET superseded_at = now() WHERE id = cur.id; END IF;
    INSERT INTO policy.portal_window (window_type, session, semester, opens_at, closes_at, late_until, late_fee_enabled, forced, reason, created_by, created_office)
    VALUES (p_type, p_session, p_semester, v_opens, v_closes, v_late, v_fee, v_forced, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office)
    RETURNING id INTO v_id;
    SELECT * INTO nxt FROM policy.window_state(p_type, p_session, p_semester);
    INSERT INTO policy.portal_window_event (window_id, window_type, session, semester, action, previous_state, new_state, previous_opens_at, previous_closes_at, previous_late_until,
                                            new_opens_at, new_closes_at, new_late_until, late_fee_enabled, reason, actor, office)
    VALUES (v_id, p_type, p_session, p_semester, p_action, CASE WHEN prev.configured THEN prev.state WHEN p_type = 'ADMISSION_STATUS_CHECKING' THEN 'CLOSED (default)' ELSE 'OPEN (default)' END, nxt.state, cur.opens_at, cur.closes_at, cur.late_until,
            v_opens, v_closes, v_late, v_fee, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office);
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION admissions.new_fee_reference(p_app uuid, p_kind text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application; fee record; v_ref text; v_amount numeric; c record;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF p_kind = 'APPLICATION' AND a.fee_confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'the application fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed for the application.';
    END IF;
    IF p_kind = 'CHECKING' THEN
        -- V295: the checking fee is open to every applicant with a valid Post-UTME application while the Director of ICT has
        -- admission status checking open — admitted, not admitted or not yet decided alike; the decision is what the check reveals
        SELECT * INTO c FROM admissions.status_checking(p_app);
        IF c.paid THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_PAID: the admission checking fee is already confirmed; it is paid once, and nothing more is owed to check your admission status' USING ERRCODE = '23514';
        END IF;
        IF NOT c.application_valid THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_NOT_ELIGIBLE: admission status checking is for applicants whose Post-UTME application is paid for and submitted' USING ERRCODE = '23514';
        END IF;
        IF NOT c.window_open THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_CLOSED: admission status checking is closed; the admission checking fee is paid while the University has it open' USING ERRCODE = '23514';
        END IF;
        -- a reference still open is the one to pay: the same service is never charged twice
        IF c.open_reference IS NOT NULL THEN RETURN c.open_reference; END IF;
    END IF;
    IF p_kind = 'ACCEPTANCE' THEN
        -- V295: the acceptance fee follows an offer the applicant has read through Admission Status Checking; before that the
        -- answer is the same whatever the decision, so no path here says whether there is an offer
        IF NOT (SELECT k.past FROM admissions.status_checking(p_app) k) THEN
            RAISE EXCEPTION 'ADMISSION_STATUS_NOT_CHECKED: an offer is paid for, accepted or declined only after you have checked your admission status and read it' USING ERRCODE = '23514';
        END IF;
        IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
            RAISE EXCEPTION 'there is no offer to accept' USING ERRCODE = '23514', HINT = 'The acceptance fee follows an offer of admission.';
        END IF;
        IF a.acceptance_confirmed_at IS NOT NULL THEN
            RAISE EXCEPTION 'the acceptance fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed to accept.';
        END IF;
    END IF;
    SELECT * INTO fee FROM admissions.applicant_fee_rule(a.session);
    -- each fee on its own reference (V271): the checking fee is never folded into the acceptance fee
    v_amount := CASE p_kind
                    WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge
                    WHEN 'CHECKING' THEN coalesce(fee.checking_fee, 0)
                    ELSE fee.acceptance_fee END;
    IF v_amount <= 0 THEN RAISE EXCEPTION 'no % fee is stated for %', lower(p_kind), a.session USING ERRCODE = '23514', HINT = 'The Bursary states the applicant fees on Fee Setup.'; END IF;
    v_ref := 'MOAUM-' || CASE p_kind WHEN 'APPLICATION' THEN 'APP' WHEN 'CHECKING' THEN 'CHK' ELSE 'ACC' END || '-' || right(a.application_no, 6) || '-'
             || lpad((floor(random() * 10000))::int::text, 4, '0');
    INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at)
    VALUES (gen_random_uuid(), p_app, p_kind, v_ref, v_amount, now() + interval '24 hours');
    RETURN v_ref;
END $function$;

CREATE OR REPLACE FUNCTION admissions.confirm_fee(p_reference text, p_channel text, p_note text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE r admissions.fee_reference; a admissions.application; v_no text; v_purpose text; v_action text; v_sms_action text;
BEGIN
    SELECT * INTO r FROM admissions.fee_reference WHERE reference = upper(btrim(p_reference));
    IF NOT FOUND THEN RAISE EXCEPTION 'no reference % was generated by this portal', p_reference USING ERRCODE = '23503',
        HINT = 'Only a reference this portal generated is confirmed; money sent anywhere else did not reach the University.'; END IF;
    IF r.confirmed_at IS NOT NULL THEN RETURN 'already confirmed'; END IF;
    IF admissions.acting_person() IS NULL THEN
        RAISE EXCEPTION 'a payment is confirmed by a person' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO a FROM admissions.application WHERE id = r.application_id;

    v_no := 'RCT-' || left(a.session, 4) || '-' || lpad(platform.next_number('RECEIPT', 'UNIVERSITY', a.session)::text, 5, '0');
    UPDATE admissions.fee_reference SET confirmed_at = now(), confirmed_by = admissions.acting_person(),
           channel = p_channel, note = p_note, receipt_no = v_no WHERE id = r.id;

    IF r.kind = 'APPLICATION' THEN
        UPDATE admissions.application SET fee_confirmed_at = coalesce(fee_confirmed_at, now()) WHERE id = a.id;
        v_purpose := 'Application & Post-UTME';
        v_action := 'Your application form is now open: sign in and complete it.';
        v_sms_action := 'Your application form is open.';
    ELSIF r.kind = 'CHECKING' THEN
        -- V295: the fee grants the checking service; the status is read, and recorded, when the applicant checks it
        UPDATE admissions.application SET checking_confirmed_at = coalesce(checking_confirmed_at, now()) WHERE id = a.id;
        v_purpose := 'Admission checking';
        v_action := 'Your Admission Checking Fee payment has been verified. You can now check your admission status: sign in and open Admission Status.';
        v_sms_action := 'Admission checking fee verified. You can now check your admission status.';
    ELSE
        UPDATE admissions.application SET acceptance_confirmed_at = coalesce(acceptance_confirmed_at, now()) WHERE id = a.id;
        v_purpose := 'Acceptance';
        v_action := 'Your acceptance of the offer is settled. Sign in to continue to clearance.';
        v_sms_action := 'Acceptance settled.';
        PERFORM admissions.settle_acceptance(a.id);
    END IF;

    PERFORM admissions.notify_applicant(a.id, 'Your payment receipt · ' || v_no,
        'This is your official receipt from Rev. Fr. Moses Orshio Adasu University, Makurdi.' || chr(10) || chr(10)
        || 'Receipt no:  ' || v_no || chr(10)
        || 'Reference:   ' || r.reference || chr(10)
        || 'Purpose:     ' || v_purpose || ' fee' || chr(10)
        || 'Session:     ' || a.session || chr(10)
        || 'Amount:      NGN ' || to_char(r.amount, 'FM999,999,990.00') || chr(10)
        || 'Confirmed:   ' || to_char(now(), 'FMDD FMMonth YYYY') || chr(10)
        || 'Channel:     ' || coalesce(p_channel, 'Bank') || chr(10) || chr(10)
        || v_action || chr(10) || chr(10)
        || 'Keep this receipt. It is verified against the University''s record by its receipt number, not by its appearance.',
        'MOAUM receipt ' || v_no || ': NGN ' || to_char(r.amount, 'FM999,999,990.00') || ' for ' || v_purpose || ' confirmed. ' || v_sms_action);

    RETURN 'confirmed';
END $function$;

CREATE OR REPLACE FUNCTION admissions.admission_status(p_app uuid)
 RETURNS TABLE(status text, label text, next_action text, next_href text, detail text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE a admissions.application; f admissions.screening_form; s people.student; q admissions.programme_change_request; req boolean; ent record; reg boolean; paid boolean; c record;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN QUERY SELECT 'NOT_FOUND', 'Not found', NULL, NULL, NULL; RETURN; END IF;
    -- V295: the status is read through Admission Status Checking — a valid Post-UTME application (paid for and submitted), checking
    -- open (the Director of ICT's window) and the checking fee paid; never through the decision, which is what the check reveals.
    -- An applicant who has read an offer and whose admission is under way continues whatever the window.
    SELECT * INTO c FROM admissions.status_checking(p_app);
    IF NOT c.decision_visible THEN
        IF NOT c.application_valid THEN
            RETURN QUERY SELECT 'APPLICATION_INCOMPLETE', 'Application not complete',
                CASE WHEN a.fee_confirmed_at IS NULL THEN 'Pay the application fee' ELSE 'Complete and submit your application' END,
                CASE WHEN a.fee_confirmed_at IS NULL THEN '/applicant/fee' ELSE '/applicant/apply' END,
                'Admission status checking is open to every applicant whose Post-UTME application is paid for and submitted.'; RETURN;
        END IF;
        IF NOT c.window_open THEN
            RETURN QUERY SELECT 'CHECKING_CLOSED', 'Admission status checking closed', NULL::text, '/applicant/admission',
                CASE WHEN c.window_state = 'SCHEDULED' AND c.opens_at IS NOT NULL
                     THEN 'Admission status checking opens on ' || to_char(c.opens_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY "at" HH24:MI') || '.'
                     ELSE 'Admission status checking is currently unavailable. Please check back when the University opens the admission checking portal.' END; RETURN;
        END IF;
        RETURN QUERY SELECT 'CHECKING_FEE_PENDING', 'Admission checking fee not paid', 'Pay the admission checking fee', '/applicant/admission',
            'Admission status checking is open. Pay the admission checking fee of ₦' || to_char(c.fee, 'FM999,999,990') || ' once, then check your admission status as often as you need while checking is open.'; RETURN;
    END IF;
    IF a.decision_released_at IS NULL OR a.decision IS NULL THEN
        RETURN QUERY SELECT 'PENDING', 'Admission pending', NULL::text, '/applicant/admission',
            'Your admission has not yet been finalised. Please check again when further admission processing has been completed; the checking fee is not charged again.'; RETURN;
    END IF;
    IF a.decision <> 'OFFERED' THEN
        RETURN QUERY SELECT 'NOT_ADMITTED', CASE WHEN a.decision = 'WAITING' THEN 'Waiting list' ELSE 'Not admitted' END, NULL::text, '/applicant/admission',
            coalesce(a.decision_note, CASE WHEN a.decision = 'WAITING'
                THEN 'You are above the cut-off, but the approved quota is full. You are offered a place only if an offered candidate fails to accept in time.'
                ELSE 'Your admission status for the ' || a.session || ' admission exercise is: not admitted. You may continue to monitor the University''s official admission updates.' END); RETURN;
    END IF;
    IF a.declined_at IS NOT NULL THEN RETURN QUERY SELECT 'DECLINED', 'Offer declined', NULL, '/applicant/status', 'A declined offer is not reinstated.'; RETURN; END IF;
    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);
    -- the applicant reads the admission status — the offer, its programme, faculty and session — before anything is accepted (V271)
    IF a.accepted_at IS NULL AND a.status_checked_at IS NULL AND NOT ent.paid AND a.undertaking_at IS NULL THEN
        RETURN QUERY SELECT 'ADMITTED', 'Admitted — check your admission status', 'Check your admission status', '/applicant/admission', 'Congratulations: read the offer and its details, then accept it and pay the acceptance fee.'; RETURN;
    END IF;
    IF a.accepted_at IS NULL THEN
        IF ent.paid OR a.undertaking_at IS NOT NULL THEN RETURN QUERY SELECT 'ACCEPTANCE_PENDING', 'Acceptance in progress', CASE WHEN ent.paid THEN 'Sign the undertaking' ELSE 'Pay the acceptance fee' END, '/applicant/accept', 'The undertaking and the acceptance fee together accept the offer.'; RETURN; END IF;
        RETURN QUERY SELECT 'ADMITTED', 'Admitted — offer to accept', 'Pay the acceptance fee', '/applicant/accept', 'Accept the offer and pay the acceptance fee; the acceptance letter follows.'; RETURN;
    END IF;
    req := admissions.screening_required(p_app);
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    SELECT * INTO q FROM admissions.programme_change_request x WHERE x.application_id = p_app ORDER BY x.requested_at DESC LIMIT 1;
    IF req AND NOT admissions.screening_ok(p_app) THEN
        -- the University screens on the record it holds (V280): the applicant waits (entering only the schools attended), or provides the one correction asked for
        -- V284: a change the Academic Office recommended during the screening awaits approval
        IF q.id IS NOT NULL AND q.state = 'REQUESTED' AND f.application_id IS NOT NULL AND f.state IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED') THEN
            RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_PENDING', 'Programme change under review', 'Wait for the Academic Office', '/applicant/admission',
                'During the screening the Academic Office recommended ' || q.to_programme || ' in place of ' || q.from_programme || '; the change takes effect when it is approved, and you will be told. Your acceptance fee is not paid again.';
            RETURN;
        END IF;
        IF f.application_id IS NULL OR f.state = 'PENDING' THEN RETURN QUERY SELECT 'SCREENING_PENDING', 'Accepted - awaiting screening', 'Wait for the University''s screening', '/applicant/clearance', 'Your information has been received. The University screens your admission on the information JAMB and your application already gave; the schools you attended are the only thing you enter. You will be told the outcome here and by email.'; RETURN; END IF;
        IF f.state = 'IN_REVIEW' THEN RETURN QUERY SELECT 'SCREENING_IN_REVIEW', 'Screening in progress', 'Wait for the screening officers', '/applicant/clearance', 'A screening officer opened your record' || coalesce(' on ' || to_char(f.review_started_at, 'DD Mon YYYY'), '') || '.'; RETURN; END IF;
        IF f.state = 'CORRECTION_REQUIRED' THEN RETURN QUERY SELECT 'SCREENING_CORRECTION', 'Screening: one correction required', 'Provide the correction', '/applicant/clearance', f.returned_note; RETURN; END IF;
        IF f.state = 'UNSUCCESSFUL' THEN
            IF q.id IS NOT NULL AND q.state = 'REQUESTED' AND q.requested_at >= f.decided_at THEN RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_PENDING', 'Change of programme requested', 'Wait for the Admissions Office', '/applicant/clearance', 'Requested ' || q.to_programme || ' on ' || to_char(q.requested_at, 'DD Mon YYYY') || '.'; RETURN; END IF;
            RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_REQUIRED', 'Screening unsuccessful', 'Apply for a change of programme', '/applicant/clearance', f.decision_reason; RETURN;
        END IF;
    END IF;
    SELECT * INTO s FROM people.student WHERE candidate_id = a.candidate_id LIMIT 1;
    IF s.id IS NULL THEN RETURN QUERY SELECT 'REGISTER_PENDING', CASE WHEN req THEN 'Screening successful' ELSE 'Accepted' END, 'Wait for the Registry to bring you onto the register', '/applicant/matric', 'School fees open once you are on the register under your admission number.'; RETURN; END IF;
    IF s.matric_no IS NOT NULL THEN RETURN QUERY SELECT 'MATRICULATED', 'Matriculated', NULL, '/applicant/matric', 'Matriculation number ' || s.matric_no || ', issued ' || to_char(s.matriculated_at, 'DD Mon YYYY') || '. It is now your sign-in.'; RETURN; END IF;
    paid := coalesce((SELECT fp.paid_in_full AND fp.due > 0 FROM finance.position(s.id, a.session) fp), false);
    reg := EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = a.session AND r.status IN ('APPROVED', 'LOCKED'));
    IF NOT paid THEN RETURN QUERY SELECT 'SCHOOL_FEES_PENDING', CASE WHEN q.id IS NOT NULL AND q.state = 'APPROVED' THEN 'Change of programme approved' WHEN req THEN 'Screening successful' ELSE 'Accepted' END, 'Pay school fees', '/student/fees', 'Sign in to the student portal with your admission number ' || coalesce(s.admission_no, '') || ' to pay.'; RETURN; END IF;
    IF NOT reg THEN RETURN QUERY SELECT 'COURSE_REGISTRATION_PENDING', 'School fees paid', 'Register your courses', '/student/registration', 'Registration is on the student portal.'; RETURN; END IF;
    RETURN QUERY SELECT 'MATRICULATION_PENDING', 'Ready for matriculation', 'Wait for the Academic Office to issue your number', '/applicant/matric', 'Your number is issued over the list of students who paid and registered.';
END $function$;

CREATE OR REPLACE FUNCTION admissions.admission_tracker(p_app uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE a admissions.application; f admissions.screening_form; s people.student; q admissions.programme_change_request; st record; req boolean; ent record; steps jsonb := '[]'::jsonb;
        paid boolean; reg boolean; offered boolean; accepted boolean; scr_done boolean; scr_failed boolean; chg_approved boolean; vis boolean; checked_any boolean;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO st FROM admissions.admission_status(p_app);
    -- V295: the decision shows in the tracker only where the applicant may read it (checked, or the admission under way)
    vis := coalesce((SELECT c.decision_visible FROM admissions.status_checking(p_app) c), false);
    checked_any := EXISTS (SELECT 1 FROM admissions.status_check k WHERE k.application_id = p_app);
    offered := a.decision = 'OFFERED' AND a.decision_released_at IS NOT NULL;
    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);
    accepted := a.accepted_at IS NOT NULL;
    req := admissions.screening_required(p_app);
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    SELECT * INTO q FROM admissions.programme_change_request x WHERE x.application_id = p_app AND x.state IN ('REQUESTED', 'APPROVED') ORDER BY x.requested_at DESC LIMIT 1;
    scr_done := coalesce(f.state = 'SUCCESSFUL', false); scr_failed := coalesce(f.state = 'UNSUCCESSFUL', false);
    chg_approved := scr_failed AND coalesce(q.state = 'APPROVED' AND q.decided_at >= f.decided_at, false);
    SELECT * INTO s FROM people.student WHERE candidate_id = a.candidate_id LIMIT 1;
    paid := s.id IS NOT NULL AND coalesce((SELECT fp.paid_in_full AND fp.due > 0 FROM finance.position(s.id, a.session) fp), false);
    reg := s.id IS NOT NULL AND EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = a.session AND r.status IN ('APPROVED', 'LOCKED'));
    steps := steps || admissions.tracker_step('ADMISSION', 'JAMB admission', CASE WHEN NOT vis THEN 'now' WHEN offered THEN 'done' WHEN a.decision_released_at IS NULL THEN 'now' ELSE 'failed' END);
    steps := steps || admissions.tracker_step('ADMISSION_STATUS', 'Admission status checked', CASE WHEN checked_any OR a.status_checked_at IS NOT NULL OR accepted OR ent.paid OR a.undertaking_at IS NOT NULL THEN 'done' WHEN a.fee_confirmed_at IS NOT NULL AND a.submitted_at IS NOT NULL THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('ACCEPTANCE_PAYMENT', 'Acceptance payment', CASE WHEN ent.paid THEN 'done' WHEN offered AND NOT admissions.checking_due(p_app) AND (a.status_checked_at IS NOT NULL OR a.undertaking_at IS NOT NULL) THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('ACCEPTANCE_LETTER', 'Acceptance letter', CASE WHEN accepted THEN 'done' WHEN ent.paid THEN 'now' ELSE 'todo' END);
    IF req THEN
        steps := steps || admissions.tracker_step('SCREENING', 'University screening', CASE WHEN coalesce(f.state, '') IN ('SUCCESSFUL', 'UNSUCCESSFUL') THEN 'done' WHEN accepted THEN 'now' ELSE 'todo' END);
        IF scr_failed THEN
            steps := steps || admissions.tracker_step('SCREENING_DECISION', 'Screening unsuccessful', 'failed');
            steps := steps || admissions.tracker_step('CHANGE_OF_PROGRAMME', 'Change of programme', CASE WHEN q.id IS NOT NULL AND q.requested_at >= f.decided_at THEN 'done' ELSE 'now' END);
            steps := steps || admissions.tracker_step('CHANGE_APPROVAL', 'Approval', CASE WHEN chg_approved THEN 'done' WHEN q.id IS NOT NULL AND q.state = 'REQUESTED' THEN 'now' ELSE 'todo' END);
        ELSE
            -- V284: a change recommended during the screening is a step of it, approved or awaiting approval
            IF q.id IS NOT NULL AND f.application_id IS NOT NULL AND q.requested_at >= f.opened_at THEN
                steps := steps || admissions.tracker_step('CHANGE_OF_PROGRAMME', 'Change of programme' || CASE WHEN q.state = 'APPROVED' THEN ' · ' || q.to_programme ELSE '' END, CASE WHEN q.state = 'APPROVED' THEN 'done' ELSE 'now' END);
                steps := steps || admissions.tracker_step('CHANGE_APPROVAL', 'Approval', CASE WHEN q.state = 'APPROVED' THEN 'done' WHEN q.state = 'REQUESTED' THEN 'now' ELSE 'todo' END);
            END IF;
            steps := steps || admissions.tracker_step('SCREENING_DECISION', 'Screening successful', CASE WHEN scr_done THEN 'done' WHEN coalesce(f.state, '') IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED') THEN 'now' ELSE 'todo' END);
            steps := steps || admissions.tracker_step('SCREENING_FORMS', 'Screening forms generated', CASE WHEN scr_done THEN 'done' ELSE 'todo' END);
        END IF;
    END IF;
    steps := steps || admissions.tracker_step('SCHOOL_FEES', 'School fees', CASE WHEN paid THEN 'done' WHEN st.status = 'SCHOOL_FEES_PENDING' OR st.status = 'REGISTER_PENDING' THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('STUDENT_ACCOUNT', 'Student portal active', CASE WHEN paid THEN 'done' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('COURSE_REGISTRATION', 'Course registration', CASE WHEN reg THEN 'done' WHEN st.status = 'COURSE_REGISTRATION_PENDING' THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('MATRICULATION', 'Matriculation', CASE WHEN s.matric_no IS NOT NULL THEN 'done' WHEN st.status = 'MATRICULATION_PENDING' THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('USERNAME', 'Sign-in changed to the matriculation number', CASE WHEN s.matric_no IS NOT NULL THEN 'done' ELSE 'todo' END);
    RETURN steps;
END $function$;

/* the undertaking and the declining of an offer follow the applicant's own check of it (V295): signed or declined unread, either
   would say whether there is an offer and would open the decision without Admission Status Checking */
CREATE OR REPLACE FUNCTION admissions.sign_undertaking(p_app uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF NOT (SELECT k.past FROM admissions.status_checking(p_app) k) THEN
        RAISE EXCEPTION 'ADMISSION_STATUS_NOT_CHECKED: an offer is paid for, accepted or declined only after you have checked your admission status and read it' USING ERRCODE = '23514';
    END IF;
    IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
        RAISE EXCEPTION 'there is nothing to accept yet' USING ERRCODE = '23514', HINT = 'This opens when the Admissions Board publishes an offer.';
    END IF;
    IF a.declined_at IS NOT NULL THEN
        RAISE EXCEPTION 'this offer was declined on %', a.declined_at::date USING ERRCODE = '23514', HINT = 'A declined offer is not reinstated.';
    END IF;
    UPDATE admissions.application SET undertaking_at = coalesce(undertaking_at, now()) WHERE id = p_app;
    PERFORM admissions.settle_acceptance(p_app);
    RETURN CASE WHEN (SELECT accepted_at FROM admissions.application WHERE id = p_app) IS NULL THEN 'undertaking signed' ELSE 'accepted' END;
END $function$;

CREATE OR REPLACE FUNCTION admissions.decline_offer(p_app uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF NOT (SELECT k.past FROM admissions.status_checking(p_app) k) THEN
        RAISE EXCEPTION 'ADMISSION_STATUS_NOT_CHECKED: an offer is paid for, accepted or declined only after you have checked your admission status and read it' USING ERRCODE = '23514';
    END IF;
    IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
        RAISE EXCEPTION 'there is no offer to decline' USING ERRCODE = '23514';
    END IF;
    IF a.accepted_at IS NOT NULL THEN
        RAISE EXCEPTION 'the offer was accepted on %; withdrawing is a change of status on the register', a.accepted_at::date USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.application SET declined_at = coalesce(declined_at, now()) WHERE id = p_app;
    UPDATE admissions.candidate SET offer_state = 'DECLINED' WHERE id = a.candidate_id AND offer_state IN ('PROPOSED','ADMITTED');
    RETURN 'declined';
END $function$;

CREATE OR REPLACE FUNCTION admissions.release_decisions(p_session text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int := 0; r record;
BEGIN
    UPDATE admissions.candidate c SET offer_state = 'ADMITTED'
      FROM admissions.application a
     WHERE a.candidate_id = c.id AND a.session = p_session AND a.decision = 'OFFERED' AND a.decision_released_at IS NULL
       AND c.offer_state = 'PROPOSED';
    FOR r IN SELECT id, decision FROM admissions.application
              WHERE session = p_session AND decision IS NOT NULL AND decision_released_at IS NULL
    LOOP
        UPDATE admissions.application SET decision_released_at = now() WHERE id = r.id;
        n := n + 1;
        -- V295: the notice says a decision is released, not what it is: the applicant reads it through Admission Status Checking
        -- (a valid application, checking open, the checking fee paid), which is the University's one channel for the result
        PERFORM admissions.notify_applicant(r.id,
            'Your admission status for ' || p_session,
            'The admission decision on your application for the ' || p_session || ' session has been released. Read it on the applicant portal under Admission Status: while the University has Admission Status Checking open, pay the admission checking fee once and check your status.',
            'MOAUM: the admission decision on your application is released. Check it on the portal under Admission Status when checking is open.');
    END LOOP;
    RETURN n;
END $function$;

COMMIT;
