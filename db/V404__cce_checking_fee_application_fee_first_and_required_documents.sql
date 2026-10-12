-- ═══════════════════════════════════════
-- V404 — CCE applicants: the admission checking fee the Bursary states, the application fee first, and the documents the Centre needs
--
--   V379 charged a CCE applicant two fees, both stated by the Bursary for the route (admissions.route_fee): the application fee
--   (with any portal charge) and the acceptance fee. The University also charges a CCE applicant the admission checking fee, so:
--
--   1. The Bursary states three CCE applicant fees for a session: application, admission checking and acceptance (route_fee gains
--      checking_fee; set_route_fee takes it and refuses a statement without it). A row stated before V404 has no checking fee
--      (NULL): owed, and not payable until the Bursary states it — the same rule as an application fee not stated.
--   2. Admission status checking for CCE runs through the ordinary engine (status_checking, new_fee_reference CHECKING,
--      confirm_fee, admission_status_checked): the CCE applicant pays the checking fee once and reads the outcome. There is still
--      no window of the Director of ICT's for CCE: checking opens to the applicant when the Centre's outcome of the application
--      is published (cce_publish releases it and tells them), so nobody pays to read "not yet decided". CCE_NO_CHECKING_FEE is
--      no longer raised.
--   3. The application fee comes first: after the Centre's list is loaded, the listed candidate registers, signs in and pays; the
--      form (details, O'Level, documents, programme) opens once the payment is confirmed, or at once where the Bursary charges
--      nothing (cce_fee_settled; CCE_FEE_FIRST). Documents are refused before then by the applicant API.
--   4. The documents of a CCE application: the passport, the O'Level result of each sitting, the birth certificate (or
--      declaration of age) and the certificate of state of origin — the last two required now.
--   Applications already submitted keep what they have; one sent back by the Centre is completed under these rules.
--   The amounts are the Bursary's (Bursary → CCE applicant fees); nothing here states an amount.
-- ═══════════════════════════════════════

ALTER TABLE admissions.route_fee ADD COLUMN checking_fee numeric(12,2) CHECK (checking_fee >= 0);
COMMENT ON COLUMN admissions.route_fee.checking_fee IS
    'V404: the admission checking fee of an applicant of the route (CCE), paid once to read the published outcome; NULL on a row stated before V404 (owed, not yet payable).';

-- the rule now carries the checking fee (a new column, so the function is created again)
DROP FUNCTION admissions.route_fee_rule(text, text);
CREATE FUNCTION admissions.route_fee_rule(p_session text, p_route text)
RETURNS TABLE(stated boolean, application_fee numeric, portal_charge numeric, acceptance_fee numeric, carried_from text, checking_fee numeric)
LANGUAGE sql STABLE AS $$
    WITH own AS (SELECT true, f.application_fee, f.portal_charge, f.acceptance_fee, NULL::text, f.checking_fee
                   FROM admissions.route_fee f WHERE f.session = p_session AND f.route = upper(btrim(p_route))),
         carried AS (SELECT false, f.application_fee, f.portal_charge, f.acceptance_fee, f.session, f.checking_fee
                       FROM admissions.route_fee f WHERE f.route = upper(btrim(p_route)) AND NOT EXISTS (SELECT 1 FROM own)
                      ORDER BY f.stated_at DESC, f.session DESC LIMIT 1)
    SELECT * FROM own UNION ALL SELECT * FROM carried
$$;
COMMENT ON FUNCTION admissions.route_fee_rule(text, text) IS
    'V379, V404: the applicant fees of a route for a session as the Bursary stated them (stated), or the last stated session''s carried forward (carried_from): application, portal charge, acceptance and admission checking.';

-- the Bursary states the checking fee with the others; a statement without it is refused
DROP FUNCTION admissions.set_route_fee(text, text, numeric, numeric, numeric);
CREATE FUNCTION admissions.set_route_fee(p_session text, p_route text, p_application numeric, p_portal numeric, p_acceptance numeric, p_checking numeric)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['bursar', 'super'], 'stating the CCE applicant fees');
    IF p_application IS NULL OR p_acceptance IS NULL OR p_checking IS NULL
       OR p_application < 0 OR p_acceptance < 0 OR p_checking < 0 OR coalesce(p_portal, 0) < 0 THEN
        RAISE EXCEPTION 'CCE_FEE_AMOUNT: the application, admission checking and acceptance fees are stated, and none is negative' USING ERRCODE = '23514';
    END IF;
    INSERT INTO admissions.route_fee (session, route, application_fee, portal_charge, acceptance_fee, checking_fee, stated_by, stated_office)
    VALUES (p_session, upper(btrim(p_route)), p_application, coalesce(p_portal, 0), p_acceptance, p_checking,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, current_setting('moaum.actor_office', true))
    ON CONFLICT (session, route) DO UPDATE SET application_fee = EXCLUDED.application_fee, portal_charge = EXCLUDED.portal_charge,
        acceptance_fee = EXCLUDED.acceptance_fee, checking_fee = EXCLUDED.checking_fee, stated_by = EXCLUDED.stated_by,
        stated_office = EXCLUDED.stated_office, stated_at = now();
END $$;
COMMENT ON FUNCTION admissions.set_route_fee(text, text, numeric, numeric, numeric, numeric) IS
    'V379, V404: the Bursary states a route''s applicant fees for a session — application, portal charge, acceptance and admission checking.';

-- the application fee is settled: paid and confirmed, or nothing charged
CREATE FUNCTION admissions.cce_fee_settled(p_app uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT a.fee_confirmed_at IS NOT NULL
           OR coalesce((SELECT f.application_fee + f.portal_charge = 0 FROM admissions.route_fee_rule(a.session, 'CCE') f), false)
      FROM admissions.application a WHERE a.id = p_app
$$;
COMMENT ON FUNCTION admissions.cce_fee_settled(uuid) IS
    'V404: a CCE application''s fee is settled — confirmed, or the Bursary charges nothing — so the form and the documents are open to the applicant.';

-- the form opens once the fee is settled
CREATE OR REPLACE FUNCTION admissions.cce_require_editable(p_app uuid)
RETURNS admissions.cce_review LANGUAGE plpgsql AS $$
DECLARE r admissions.cce_review;
BEGIN
    PERFORM admissions.cce_application(p_app);
    SELECT * INTO r FROM admissions.cce_review WHERE application_id = p_app FOR UPDATE;
    IF r.state NOT IN ('DRAFT', 'DOCUMENTS_PENDING', 'VERIFICATION_REQUIRED') THEN
        RAISE EXCEPTION 'CCE_NOT_EDITABLE: the application is % and is with the Centre; it is changed only when the Centre asks', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    -- V404: the application fee first
    IF NOT admissions.cce_fee_settled(p_app) THEN
        RAISE EXCEPTION 'CCE_FEE_FIRST: pay the CCE application fee first; the form opens once the payment is confirmed' USING ERRCODE = '23514';
    END IF;
    RETURN r;
END $$;

CREATE OR REPLACE FUNCTION admissions.cce_document_word(p_kind text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_kind WHEN 'PASSPORT' THEN 'passport photograph' WHEN 'OLEVEL_STATEMENT' THEN 'first sitting''s O''Level result'
                       WHEN 'OLEVEL_STATEMENT_2' THEN 'second sitting''s O''Level result' WHEN 'BIRTH_CERT' THEN 'birth certificate'
                       WHEN 'STATE_OF_ORIGIN' THEN 'certificate of state of origin'
                       ELSE lower(replace(coalesce(p_kind, 'document'), '_', ' ')) END
$$;

CREATE OR REPLACE FUNCTION admissions.cce_application_problems(p_app uuid)
 RETURNS TABLE(step text, field text, message text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH a AS (SELECT ap.*, c.cce_candidate_id FROM admissions.application ap JOIN admissions.candidate c ON c.id = ap.candidate_id WHERE ap.id = p_app),
         l AS (SELECT x.* FROM admissions.cce_candidate x JOIN a ON a.cce_candidate_id = x.id),
         r AS (SELECT x.* FROM admissions.cce_review x WHERE x.application_id = p_app),
         fee AS (SELECT f.* FROM a CROSS JOIN LATERAL admissions.route_fee_rule(a.session, 'CCE') f),
         ans AS (SELECT x.field, x.value FROM admissions.screening_answer x WHERE x.application_id = p_app),
         ol AS (SELECT x.* FROM admissions.screening_olevel x WHERE x.application_id = p_app AND x.active),
         sittings AS (SELECT count(DISTINCT sitting) AS n FROM ol),
         docs AS (SELECT d.* FROM admissions.application_document d WHERE d.application_id = p_app AND d.superseded_at IS NULL)
    -- V404: the fee comes first; the rest of the form opens once it is paid (or the Bursary charges nothing)
    SELECT 'PAYMENT', 'application_fee', CASE WHEN NOT EXISTS (SELECT 1 FROM fee) THEN 'The Bursary has not yet stated the CCE application fee for ' || (SELECT session FROM a) || '; the form opens once it is stated and paid'
                                              ELSE 'Pay the CCE application fee; the form opens once the payment is confirmed' END
     WHERE NOT admissions.cce_fee_settled(p_app)
    UNION ALL
    SELECT 'PERSONAL', f.field, 'Give your ' || replace(replace(replace(f.field, 'kin_', 'next of kin''s '), '_', ' '), 'lga', 'local government area')
      FROM admissions.cce_form_fields() f WHERE f.required AND NOT EXISTS (SELECT 1 FROM ans WHERE ans.field = f.field)
    UNION ALL
    SELECT 'OLEVEL', 'sittings', 'Give your O''Level results (one sitting or two)' WHERE (SELECT n FROM sittings) = 0
    UNION ALL
    SELECT 'OLEVEL', 'subjects', 'Give at least five subjects across your sittings' WHERE (SELECT n FROM sittings) > 0 AND (SELECT count(*) FROM ol) < 5
    UNION ALL
    SELECT 'OLEVEL', 'compulsory', cs.subject || ' is not among your O''Level subjects'
      FROM a CROSS JOIN LATERAL admissions.olevel_compulsory_subjects(a.session) cs
     WHERE (SELECT n FROM sittings) > 0 AND NOT EXISTS (SELECT 1 FROM ol WHERE ol.subject ~ cs.pattern)
    UNION ALL
    SELECT 'DOCUMENTS', 'PASSPORT', 'Upload your passport photograph' WHERE NOT EXISTS (SELECT 1 FROM docs WHERE docs.kind = 'PASSPORT')
    UNION ALL
    SELECT 'DOCUMENTS', 'OLEVEL_STATEMENT', CASE WHEN (SELECT n FROM sittings) = 2 THEN 'Upload the O''Level result of your first sitting' ELSE 'Upload your O''Level result' END
     WHERE NOT EXISTS (SELECT 1 FROM docs WHERE docs.kind = 'OLEVEL_STATEMENT')
    UNION ALL
    SELECT 'DOCUMENTS', 'OLEVEL_STATEMENT_2', 'Upload the O''Level result of your second sitting'
     WHERE (SELECT n FROM sittings) = 2 AND NOT EXISTS (SELECT 1 FROM docs WHERE docs.kind = 'OLEVEL_STATEMENT_2')
    UNION ALL
    SELECT 'DOCUMENTS', 'BIRTH_CERT', 'Upload your birth certificate (or declaration of age)' WHERE NOT EXISTS (SELECT 1 FROM docs WHERE docs.kind = 'BIRTH_CERT')
    UNION ALL
    SELECT 'DOCUMENTS', 'STATE_OF_ORIGIN', 'Upload your certificate of state of origin' WHERE NOT EXISTS (SELECT 1 FROM docs WHERE docs.kind = 'STATE_OF_ORIGIN')
    UNION ALL
    SELECT 'DOCUMENTS', d.kind, 'Replace your ' || admissions.cce_document_word(d.kind) || ', which the Centre could not accept: '
                                 || rtrim(coalesce(d.review_note, ''), '. ')
      FROM docs d WHERE d.status = 'REJECTED'
    UNION ALL
    SELECT 'PROGRAMME', 'programme', 'Confirm the programme you are applying for' WHERE (SELECT programme_confirmed_at FROM r) IS NULL
    UNION ALL
    SELECT 'PROGRAMME', 'programme', 'The Centre is not admitting into ' || (SELECT p.name FROM ref.programme p JOIN l ON l.programme_code = p.code) || ' at present'
     WHERE NOT coalesce((SELECT t.active FROM l CROSS JOIN LATERAL ref.programme_route_terms(l.programme_code, 'CCE') t), false)
$function$;

CREATE OR REPLACE FUNCTION admissions.status_checking(p_app uuid)
 RETURNS TABLE(application_id uuid, session text, application_valid boolean, window_state text, window_open boolean, opens_at timestamp with time zone, closes_at timestamp with time zone, fee numeric, fee_required boolean, paid boolean, paid_at timestamp with time zone, paid_reference text, open_reference text, open_reference_expires timestamp with time zone, past boolean, may_pay boolean, may_check boolean, decision_visible boolean, reason text, checks bigint, last_checked_at timestamp with time zone, last_result text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH a AS (SELECT * FROM admissions.application WHERE id = p_app),
    -- V404: a CCE applicant has no checking window of the Director of ICT's: checking opens to them when the Centre's outcome of
    -- their application is published (admissions.cce_publish releases it and tells them), and costs the CCE admission checking
    -- fee the Bursary stated for the route (NULL while it is not stated: owed, and not yet payable)
    cce AS (SELECT EXISTS (SELECT 1 FROM a JOIN admissions.candidate c ON c.id = a.candidate_id WHERE c.entry_mode = 'CCE') AS yes),
    w AS (SELECT CASE WHEN cce.yes THEN CASE WHEN a.decision_released_at IS NOT NULL THEN 'OPEN' ELSE 'CLOSED' END ELSE ws.state END AS state, CASE WHEN cce.yes THEN NULL ELSE ws.opens_at END AS opens_at,
                 CASE WHEN cce.yes THEN NULL ELSE ws.closes_at END AS closes_at
            FROM a CROSS JOIN cce CROSS JOIN LATERAL policy.window_state('ADMISSION_STATUS_CHECKING', a.session, NULL) ws),
    f AS (SELECT CASE WHEN (SELECT yes FROM cce) THEN (SELECT r.checking_fee FROM a CROSS JOIN LATERAL admissions.route_fee_rule(a.session, 'CCE') r)
                      ELSE coalesce((SELECT r.checking_fee FROM a CROSS JOIN LATERAL admissions.applicant_fee_rule(a.session) r), 0) END::numeric AS fee),
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
               f.fee, coalesce(f.fee > 0, (SELECT yes FROM cce)) AS required,
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
$function$;

CREATE OR REPLACE FUNCTION admissions.new_fee_reference(p_app uuid, p_kind text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application; fee record; v_ref text; v_amount numeric; c record; v_cce boolean; v_try int;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    v_cce := EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE');
    IF p_kind = 'APPLICATION' AND a.fee_confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'the application fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed for the application.';
    END IF;
    IF p_kind = 'CHECKING' THEN
        -- V295: the checking fee is open to every applicant with a valid Post-UTME application while the Director of ICT has
        -- admission status checking open — admitted, not admitted or not yet decided alike; the decision is what the check reveals
        SELECT * INTO c FROM admissions.status_checking(p_app);
        IF c.paid THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_PAID: the admission checking fee is already paid; nothing more is owed' USING ERRCODE = '23514';
        END IF;
        IF NOT c.application_valid THEN
            RAISE EXCEPTION '%', CASE WHEN v_cce THEN 'ADMISSION_CHECKING_NOT_ELIGIBLE: admission status checking follows a CCE application paid for and submitted'
                ELSE 'ADMISSION_CHECKING_NOT_ELIGIBLE: admission status checking is for applicants whose Post-UTME application is paid for and submitted' END USING ERRCODE = '23514';
        END IF;
        IF NOT c.window_open THEN
            -- V404: for CCE, checking opens when the Centre publishes the outcome of the application
            RAISE EXCEPTION '%', CASE WHEN v_cce THEN 'ADMISSION_CHECKING_CLOSED: the Centre for Continuing Education has not yet published the outcome of your application'
                ELSE 'ADMISSION_CHECKING_CLOSED: admission status checking is closed' END USING ERRCODE = '23514';
        END IF;
        -- a reference still open is the one to pay: the same service is never charged twice
        IF c.open_reference IS NOT NULL THEN RETURN c.open_reference; END IF;
    END IF;
    IF p_kind = 'ACCEPTANCE' THEN
        -- V295: the acceptance fee follows an offer the applicant has read through Admission Status Checking; before that the
        -- answer is the same whatever the decision, so no path here says whether there is an offer
        IF NOT (SELECT k.past FROM admissions.status_checking(p_app) k) THEN
            RAISE EXCEPTION 'ADMISSION_STATUS_NOT_CHECKED: check your admission status before paying for, accepting or declining the offer' USING ERRCODE = '23514';
        END IF;
        IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
            RAISE EXCEPTION 'there is no offer to accept' USING ERRCODE = '23514', HINT = 'The acceptance fee follows an offer of admission.';
        END IF;
        IF a.acceptance_confirmed_at IS NOT NULL THEN
            RAISE EXCEPTION 'the acceptance fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed to accept.';
        END IF;
    END IF;
    IF v_cce THEN
        -- V379: the CCE fees, as the Bursary stated them for the session (or last stated); never the Post-UTME figures.
        -- V404: the CCE admission checking fee among them
        SELECT r.application_fee, r.portal_charge, r.acceptance_fee, r.checking_fee INTO fee FROM admissions.route_fee_rule(a.session, 'CCE') r;
        v_amount := CASE p_kind WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge WHEN 'CHECKING' THEN fee.checking_fee ELSE fee.acceptance_fee END;
        IF v_amount IS NULL THEN
            RAISE EXCEPTION 'CCE_FEE_NOT_STATED: the Bursary has not stated the CCE % fee for %', lower(p_kind), a.session USING ERRCODE = '23514';
        END IF;
    ELSE
    SELECT * INTO fee FROM admissions.applicant_fee_rule(a.session);
    -- V401: where the Bursary refuses to carry a session's applicant fees forward, nothing is paid until they are stated
    IF NOT fee.stated AND admissions.applicant_fee_policy() = 'REFUSE' THEN
        RAISE EXCEPTION 'APPLICANT_FEE_NOT_STATED: the % fee for % is not stated yet', lower(p_kind), a.session USING ERRCODE = '23514',
            HINT = 'The Bursary states the applicant fees for the session on Fee Setup.';
    END IF;
    -- each fee on its own reference (V271): the checking fee is never folded into the acceptance fee
    v_amount := CASE p_kind
                    WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge
                    WHEN 'CHECKING' THEN coalesce(fee.checking_fee, 0)
                    ELSE fee.acceptance_fee END;
    END IF;
    IF v_amount <= 0 THEN RAISE EXCEPTION 'no % fee is stated for %', lower(p_kind), a.session USING ERRCODE = '23514', HINT = 'The Bursary states the applicant fees on Fee Setup.'; END IF;
    -- V390: the four random digits may repeat a reference another application drew (the last six digits of an application
    -- number are the session's running number, shared across sessions); a taken reference is drawn again, never answered as a clash
    FOR v_try IN 1..50 LOOP
        v_ref := 'MOAUM-' || CASE p_kind WHEN 'APPLICATION' THEN 'APP' WHEN 'CHECKING' THEN 'CHK' ELSE 'ACC' END || '-' || right(a.application_no, 6) || '-'
                 || lpad((floor(random() * 10000))::int::text, 4, '0');
        INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at)
        VALUES (gen_random_uuid(), p_app, p_kind, v_ref, v_amount, now() + interval '24 hours')
        ON CONFLICT (reference) DO NOTHING;
        IF FOUND THEN RETURN v_ref; END IF;
    END LOOP;
    RAISE EXCEPTION 'FEE_REFERENCE_EXHAUSTED: no free % reference was found for % in fifty draws', lower(p_kind), a.application_no USING ERRCODE = '23514',
        HINT = 'Try again; if it persists, the Directorate of ICT widens the reference.';
END $function$;

CREATE OR REPLACE FUNCTION admissions.admission_status_checked(p_app uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
AS $function$
DECLARE c record; st record; a admissions.application; v timestamptz; first_offer boolean;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    SELECT * INTO c FROM admissions.status_checking(p_app);
    IF NOT c.may_check THEN
        -- an admission already under way is not checked again; it is continued
        IF c.past THEN RETURN a.status_checked_at; END IF;
        -- V404: a CCE applicant is told in the Centre's terms
        RAISE EXCEPTION '%', CASE
            WHEN c.reason = 'APPLICATION_INCOMPLETE' AND EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE')
                THEN 'ADMISSION_CHECKING_NOT_ELIGIBLE: admission status checking follows a CCE application paid for and submitted'
            WHEN c.reason = 'CHECKING_CLOSED' AND EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE')
                THEN 'ADMISSION_CHECKING_CLOSED: the Centre for Continuing Education has not yet published the outcome of your application'
            WHEN c.reason = 'APPLICATION_INCOMPLETE' THEN 'ADMISSION_CHECKING_NOT_ELIGIBLE: admission status checking is for applicants whose Post-UTME application is paid for and submitted'
            WHEN c.reason = 'CHECKING_CLOSED' THEN 'ADMISSION_CHECKING_CLOSED: admission status checking is currently closed; please check back when the University opens it'
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
END $function$;

CREATE OR REPLACE FUNCTION admissions.admission_status(p_app uuid)
 RETURNS TABLE(status text, label text, next_action text, next_href text, detail text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE a admissions.application; f admissions.screening_form; s people.student; q admissions.programme_change_request; req boolean; ent record; reg boolean; paid boolean; c record; v_cce boolean;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN QUERY SELECT 'NOT_FOUND', 'Not found', NULL, NULL, NULL; RETURN; END IF;
    v_cce := EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE');
    -- V295: the status is read through Admission Status Checking — a valid Post-UTME application (paid for and submitted), checking
    -- open (the Director of ICT's window) and the checking fee paid; never through the decision, which is what the check reveals.
    -- An applicant who has read an offer and whose admission is under way continues whatever the window.
    SELECT * INTO c FROM admissions.status_checking(p_app);
    IF NOT c.decision_visible THEN
        IF NOT c.application_valid THEN
            RETURN QUERY SELECT 'APPLICATION_INCOMPLETE', 'Application not complete',
                CASE WHEN a.fee_confirmed_at IS NULL THEN 'Pay the application fee' ELSE 'Complete and submit your application' END,
                CASE WHEN EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE') THEN '/applicant/cce'
                     WHEN a.fee_confirmed_at IS NULL THEN '/applicant/fee' ELSE '/applicant/apply' END,
                CASE WHEN EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE')
                     THEN 'The Centre for Continuing Education reviews your application once it is complete and submitted.'
                     ELSE 'Admission status checking is open to every applicant whose Post-UTME application is paid for and submitted.' END; RETURN;
        END IF;
        IF NOT c.window_open THEN
            RETURN QUERY SELECT 'CHECKING_CLOSED', 'Admission status checking closed', NULL::text, '/applicant/admission',
                -- V404: a CCE applicant's checking opens when the Centre publishes the outcome of the application
                CASE WHEN v_cce THEN 'The Centre for Continuing Education has not yet published the outcome of your application. You are told by email and SMS when it does; then pay the admission checking fee and read it here.'
                     WHEN c.window_state = 'SCHEDULED' AND c.opens_at IS NOT NULL
                     THEN 'Admission status checking opens on ' || to_char(c.opens_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY "at" HH24:MI') || '.'
                     ELSE 'Admission status checking is currently unavailable. Please check back when the University opens the admission checking portal.' END; RETURN;
        END IF;
        RETURN QUERY SELECT 'CHECKING_FEE_PENDING', 'Admission checking fee not paid', 'Pay the admission checking fee', '/applicant/admission',
            CASE WHEN v_cce AND c.fee IS NULL
                 THEN 'The Centre for Continuing Education has published the outcome of your application. The Bursary has not yet stated the CCE admission checking fee for ' || a.session || '; pay it and read the outcome here once it does.'
                 WHEN v_cce
                 THEN 'The Centre for Continuing Education has published the outcome of your application. Pay the admission checking fee of ₦' || to_char(c.fee, 'FM999,999,990') || ' once, then read it here as often as you need.'
                 ELSE 'Admission status checking is open. Pay the admission checking fee of ₦' || to_char(c.fee, 'FM999,999,990') || ' once, then check your admission status as often as you need while checking is open.' END; RETURN;
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
    -- V358: an offer not accepted by its deadline, lapsed by the Admissions Office
    IF a.lapsed_at IS NOT NULL THEN
        RETURN QUERY SELECT 'LAPSED', 'Offer lapsed', NULL::text, '/applicant/admission',
            'Your offer was not accepted by ' || coalesce(to_char(admissions.offer_deadline_of(p_app), 'FMDD Month YYYY'), 'its deadline')
            || ' and has lapsed. A lapsed offer is not reinstated; write to the Admissions Office quoting your application number if you believe this is in error.'; RETURN;
    END IF;
    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);
    -- the applicant reads the admission status — the offer, its programme, faculty and session — before anything is accepted (V271)
    IF a.accepted_at IS NULL AND a.status_checked_at IS NULL AND NOT ent.paid AND a.undertaking_at IS NULL THEN
        RETURN QUERY SELECT 'ADMITTED', 'Admitted — check your admission status', 'Check your admission status', '/applicant/admission', 'Congratulations: read the offer and its details, then accept it and pay the acceptance fee.'; RETURN;
    END IF;
    IF a.accepted_at IS NULL THEN
        IF ent.paid OR a.undertaking_at IS NOT NULL THEN RETURN QUERY SELECT 'ACCEPTANCE_PENDING', 'Acceptance in progress', CASE WHEN ent.paid THEN 'Sign the undertaking' ELSE 'Pay the acceptance fee' END, '/applicant/accept', 'The undertaking and the acceptance fee together accept the offer.'; RETURN; END IF;
        RETURN QUERY SELECT 'ADMITTED', 'Admitted — offer to accept', 'Pay the acceptance fee', '/applicant/accept', 'Accept the offer and pay the acceptance fee; the acceptance letter follows.' || coalesce(' Accept it by ' || to_char(admissions.offer_deadline_of(p_app), 'FMDD Month YYYY') || '; an offer neither accepted nor paid for by then lapses.', ''); RETURN;
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

COMMENT ON FUNCTION admissions.cce_application_problems(uuid) IS
    'V379, V404: what a CCE application still needs before it is submitted — the fee first, then the details, the O''Level, the documents (passport, each sitting''s result, birth certificate, certificate of state of origin) and the programme.';
