-- ═══════════════════════════════════════
-- V412 — CCE: the readiness read, the documents an application still lacks (asked for in one click), and the CCE checking
--         fee named as such
--
--   1. admissions.cce_readiness(session) — whether CCE admission can run in the CCE session: the session on the calendar,
--      the three applicant fees stated by the Bursary for it (application, admission checking, acceptance — V404), the CCE
--      list loaded, programmes offered to CCE, the application window, and whether CCE is in use at all. Read only; the
--      Go-live readiness and /platform/status read it, so a CCE session whose fees the Bursary has not stated is seen before
--      applicants are stuck on it.
--   2. admissions.cce_required_documents / cce_missing_documents — the documents a CCE application needs (passport, each
--      sitting's O'Level result, birth certificate, certificate of state of origin) and those it lacks (not uploaded, or the
--      upload rejected). An application submitted before V404 may lack the two certificates. cce_ask_missing asks the
--      applicant for exactly those through the review's own REQUEST_DOCUMENTS step (cce_act: the Centre only, a submitted or
--      reviewed application, the applicant told by email and SMS); cce_ask_missing_all does it for every such application of
--      a session, leaving a recommended one alone (a recommendation is never undone in bulk).
--   3. admissions.confirm_fee names a CCE applicant's checking fee "CCE admission checking" on the receipt, email and SMS, and
--      tells them to read the outcome of their application.
--   4. admissions.status_checking_rows(session, cce) — the Director of ICT's admission checking report is the Post-UTME,
--      Direct Entry and transfer applicants' (status_checking_rows(session) now leaves CCE out, and so the summary): a CCE
--      applicant's checking is not the ICT window's (V404). The CCE ones are read with cce = true.
-- ═══════════════════════════════════════

-- ── 1 · whether CCE admission can run ─────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.cce_readiness(p_session text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
    WITH s AS (SELECT coalesce(p_session, policy.route_session('CCE')) AS name),
         x AS (SELECT s.name, cal.state AS session_state, f.stated, f.carried_from, f.application_fee, f.portal_charge, f.checking_fee, f.acceptance_fee,
                      win.state AS window_state
                 FROM s
                 LEFT JOIN policy.academic_session cal ON cal.name = s.name
                 LEFT JOIN LATERAL admissions.route_fee_rule(s.name, 'CCE') f ON true
                 LEFT JOIN LATERAL policy.window_state('CCE_APPLICATION', s.name, NULL) win ON true),
         lst AS (SELECT count(*) AS n FROM admissions.cce_candidate l, s WHERE l.session = s.name AND l.standing = 'LISTED'),
         prog AS (SELECT count(*) AS n FROM ref.programme_route pr WHERE pr.route = 'CCE' AND pr.active),
         apps AS (SELECT count(*) AS n FROM s, admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
                   WHERE a.session = s.name AND c.entry_mode = 'CCE')
    SELECT jsonb_build_object(
             'session', x.name, 'onCalendar', x.session_state IS NOT NULL, 'sessionState', x.session_state,
             'feesStated', coalesce(x.stated AND x.checking_fee IS NOT NULL, false), 'feesCarriedFrom', x.carried_from,
             'applicationFee', x.application_fee + x.portal_charge, 'checkingFee', x.checking_fee, 'acceptanceFee', x.acceptance_fee,
             'checkingStated', x.checking_fee IS NOT NULL,
             'listed', lst.n, 'programmes', prog.n, 'window', coalesce(x.window_state, 'CLOSED'), 'applications', apps.n,
             'inUse', lst.n > 0 OR x.window_state = 'OPEN' OR apps.n > 0,
             'ready', x.session_state IS NOT NULL AND coalesce(x.stated AND x.checking_fee IS NOT NULL, false) AND lst.n > 0 AND prog.n > 0)
      FROM x, lst, prog, apps;
$fn$;
COMMENT ON FUNCTION admissions.cce_readiness(text) IS
  'V412: whether CCE admission can run in a session (by default the CCE session) — on the calendar, the Bursary''s three CCE applicant fees stated for it, the CCE list loaded, programmes offered to CCE; with the application window and whether CCE is in use. Read only.';

-- ── 2 · the documents a CCE application needs, and those it lacks ─────────────────────────────────────────────────────
CREATE FUNCTION admissions.cce_required_documents(p_app uuid)
RETURNS text[] LANGUAGE sql STABLE AS $fn$
    SELECT ARRAY['PASSPORT', 'OLEVEL_STATEMENT']
           || CASE WHEN (SELECT count(DISTINCT o.sitting) FROM admissions.screening_olevel o WHERE o.application_id = p_app AND o.active) = 2
                   THEN ARRAY['OLEVEL_STATEMENT_2'] ELSE ARRAY[]::text[] END
           || ARRAY['BIRTH_CERT', 'STATE_OF_ORIGIN'];
$fn$;
COMMENT ON FUNCTION admissions.cce_required_documents(uuid) IS
  'V412: the documents a CCE application needs (V404): passport, the O''Level result of each sitting, birth certificate, certificate of state of origin.';

CREATE FUNCTION admissions.cce_missing_documents(p_app uuid)
RETURNS text[] LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(array_agg(r.k ORDER BY r.ord), ARRAY[]::text[])
      FROM unnest(admissions.cce_required_documents(p_app)) WITH ORDINALITY AS r(k, ord)
     WHERE NOT EXISTS (SELECT 1 FROM admissions.application_document d
                        WHERE d.application_id = p_app AND d.kind = r.k AND d.superseded_at IS NULL AND d.status <> 'REJECTED');
$fn$;
COMMENT ON FUNCTION admissions.cce_missing_documents(uuid) IS
  'V412: the documents a CCE application still lacks: not uploaded, or the upload rejected by the Centre.';

CREATE FUNCTION admissions.cce_ask_missing(p_app uuid)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v_missing text[]; v_words text[]; v_note text; n int;
BEGIN
    PERFORM admissions.cce_application(p_app);
    v_missing := admissions.cce_missing_documents(p_app);
    IF cardinality(v_missing) = 0 THEN
        RAISE EXCEPTION 'CCE_NOTHING_MISSING: every document the application needs is uploaded' USING ERRCODE = '23514';
    END IF;
    SELECT array_agg('your ' || admissions.cce_document_word(x.k) ORDER BY x.ord) INTO v_words FROM unnest(v_missing) WITH ORDINALITY AS x(k, ord);
    n := cardinality(v_words);
    v_note := 'Upload ' || CASE WHEN n = 1 THEN v_words[1] ELSE array_to_string(v_words[1:n - 1], ', ') || ' and ' || v_words[n] END
              || ', then send the application back to the Centre.';
    -- the review's own step: the Centre only, a submitted, reviewed or recommended application, the applicant told
    PERFORM admissions.cce_act(p_app, 'REQUEST_DOCUMENTS', v_note);
    RETURN v_note;
END $fn$;
COMMENT ON FUNCTION admissions.cce_ask_missing(uuid) IS
  'V412: the Centre asks a CCE applicant for exactly the documents the application lacks, through cce_act REQUEST_DOCUMENTS.';

CREATE FUNCTION admissions.cce_ask_missing_all(p_session text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE x record; n int := 0; kept int := 0;
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['cce', 'super'], 'asking CCE applicants for the documents they lack');
    FOR x IN SELECT r.application_id, r.state FROM admissions.cce_review r JOIN admissions.application a ON a.id = r.application_id
              WHERE a.session = p_session AND r.published_at IS NULL AND r.state IN ('SUBMITTED', 'UNDER_REVIEW', 'RECOMMENDED')
                AND cardinality(admissions.cce_missing_documents(r.application_id)) > 0
              ORDER BY a.application_no LOOP
        -- a recommendation is never undone in bulk: the Centre asks for that one on the application itself
        IF x.state = 'RECOMMENDED' THEN kept := kept + 1; CONTINUE; END IF;
        PERFORM admissions.cce_ask_missing(x.application_id);
        n := n + 1;
    END LOOP;
    RETURN jsonb_build_object('asked', n, 'recommendedLeft', kept);
END $fn$;
COMMENT ON FUNCTION admissions.cce_ask_missing_all(text) IS
  'V412: the Centre asks every submitted or reviewed CCE application of a session that lacks documents for exactly those; a recommended one is left for the Centre to ask on the application itself.';

-- ── 3 · the CCE checking fee named as such ──
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
        v_purpose := CASE WHEN EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE') THEN 'CCE application' ELSE 'Application & Post-UTME' END;
        v_action := 'Your application form is now open: sign in and complete it.';
        v_sms_action := 'Your application form is open.';
    ELSIF r.kind = 'CHECKING' THEN
        -- V295: the fee grants the checking service; the status is read, and recorded, when the applicant checks it
        UPDATE admissions.application SET checking_confirmed_at = coalesce(checking_confirmed_at, now()) WHERE id = a.id;
        -- V412: a CCE applicant's checking fee is the CCE admission checking fee, paid to read the published outcome
        IF EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE') THEN
            v_purpose := 'CCE admission checking';
            v_action := 'Your CCE admission checking fee payment has been verified. Sign in and open Admission Status to read the outcome of your application.';
            v_sms_action := 'CCE admission checking fee verified. Sign in to read the outcome of your application.';
        ELSE
            v_purpose := 'Admission checking';
            v_action := 'Your Admission Checking Fee payment has been verified. You can now check your admission status: sign in and open Admission Status.';
            v_sms_action := 'Admission checking fee verified. You can now check your admission status.';
        END IF;
    ELSE
        UPDATE admissions.application SET acceptance_confirmed_at = coalesce(acceptance_confirmed_at, now()) WHERE id = a.id;
        v_purpose := CASE WHEN EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE') THEN 'CCE acceptance' ELSE 'Acceptance' END;
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

-- ── 4 · the ICT report without CCE ──
CREATE FUNCTION admissions.status_checking_rows(p_session text, p_cce boolean)
 RETURNS TABLE(application_id uuid, application_no text, jamb_reg_no text, name text, sex text, programme text, programme_code text, faculty_code text, faculty text, dept_code text, department text, valid boolean, paid boolean, paid_at timestamp with time zone, reference text, amount numeric, checked boolean, checks bigint, first_checked_at timestamp with time zone, last_checked_at timestamp with time zone, last_result text, result text)
 LANGUAGE sql
 STABLE
AS $function$
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
       -- V412: the CCE applicants apart from the rest (their checking is not the ICT window's)
       AND (coalesce(c.entry_mode, '') = 'CCE') = coalesce(p_cce, false)
$function$;

CREATE OR REPLACE FUNCTION admissions.status_checking_rows(p_session text)
 RETURNS TABLE(application_id uuid, application_no text, jamb_reg_no text, name text, sex text, programme text, programme_code text, faculty_code text, faculty text, dept_code text, department text, valid boolean, paid boolean, paid_at timestamp with time zone, reference text, amount numeric, checked boolean, checks bigint, first_checked_at timestamp with time zone, last_checked_at timestamp with time zone, last_result text, result text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V412: the Director of ICT's report is the Post-UTME, Direct Entry and transfer applicants'; CCE is read with p_cce = true
    SELECT * FROM admissions.status_checking_rows(p_session, false)
$function$;

COMMENT ON FUNCTION admissions.status_checking_rows(text, boolean) IS
  'V412: the admission status checking rows of a session, the CCE applicants (p_cce) or the rest — the Director of ICT''s report reads the rest.';
COMMENT ON FUNCTION admissions.status_checking_rows(text) IS
  'V295, V412: the admission status checking rows of a session for the Director of ICT''s window — every applicant but CCE.';
