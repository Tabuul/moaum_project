-- ═══════════════════════════════════════
-- V414 — the University's current session is never a draft or cancelled one; what a CCE applicant still has to do
--
--   1. policy.university_current_session() fell back, when no session is CURRENT, to the latest session that is not PLANNED —
--      which took a DRAFT (still being prepared) or a CANCELLED one (merged into another, never run) as the session the
--      University runs in, and every default built on it with it (the route sessions, fee screens, desks; the CI demo once
--      picked a DRAFT left by the property suite). Now: the CURRENT session; else the latest that ran (CLOSED or ARCHIVED);
--      else the PLANNED session whose dates hold today (Africa/Lagos); else the latest PLANNED. A DRAFT or CANCELLED session
--      is never the answer. The CURRENT pick is unchanged.
--   2. admissions.cce_outstanding(application) — what a CCE applicant still has to do, in order, as one list the applicant's
--      own page shows at the top: the application fee (until it is settled), the form (while it is their draft), what the
--      Centre asked for (documents or verification), the CCE admission checking fee (once the outcome is published and until
--      it is paid; owed and not payable while the Bursary has not stated it), the acceptance fee (once the offer is read,
--      until it is paid, unless the offer was declined or lapsed). Read only.
-- ═══════════════════════════════════════

CREATE OR REPLACE FUNCTION policy.university_current_session()
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1),
                    -- the latest session that ran; never a DRAFT (not yet planned) or a CANCELLED one (merged, never run)
                    (SELECT max(name) FROM policy.academic_session WHERE state IN ('CLOSED', 'ARCHIVED')),
                    (SELECT max(name) FROM policy.academic_session
                      WHERE state = 'PLANNED' AND (now() AT TIME ZONE 'Africa/Lagos')::date BETWEEN starts_on AND ends_on),
                    (SELECT max(name) FROM policy.academic_session WHERE state = 'PLANNED'))
$fn$;
COMMENT ON FUNCTION policy.university_current_session() IS
  'V414: the session the University runs in — the CURRENT one; else the latest CLOSED or ARCHIVED; else the PLANNED one whose dates hold today; else the latest PLANNED. Never a DRAFT or CANCELLED session.';

CREATE FUNCTION admissions.cce_outstanding(p_app uuid)
RETURNS TABLE(item text, label text, detail text, amount numeric, href text) LANGUAGE sql STABLE AS $fn$
    WITH a AS (SELECT ap.* FROM admissions.application ap WHERE ap.id = p_app),
         r AS (SELECT x.* FROM admissions.cce_review x WHERE x.application_id = p_app),
         fee AS (SELECT f.* FROM a CROSS JOIN LATERAL admissions.route_fee_rule(a.session, 'CCE') f),
         k AS (SELECT c.* FROM admissions.status_checking(p_app) c),
         ent AS (SELECT e.* FROM admissions.acceptance_entitlement(p_app) e),
         todo AS (SELECT count(*) AS n FROM admissions.cce_application_problems(p_app) p WHERE p.step <> 'PAYMENT'),
         settled AS (SELECT admissions.cce_fee_settled(p_app) AS yes)
    -- 1 · the application fee, first
    SELECT 'APPLICATION_FEE', 'Pay the CCE application fee',
           CASE WHEN NOT EXISTS (SELECT 1 FROM fee) THEN 'The Bursary has not yet stated it; you can pay once it does'
                ELSE 'Your form opens once the payment is confirmed' END,
           (SELECT f.application_fee + f.portal_charge FROM fee f), '/applicant/cce'
      FROM settled WHERE NOT settled.yes AND EXISTS (SELECT 1 FROM r)
    UNION ALL
    -- 2 · the form, while it is the applicant's draft
    SELECT 'FORM', 'Complete and submit your application',
           CASE WHEN todo.n = 0 THEN 'Everything is in: read the declaration and submit'
                ELSE todo.n || CASE WHEN todo.n = 1 THEN ' thing' ELSE ' things' END || ' still to do on the form' END,
           NULL::numeric, '/applicant/cce'
      FROM settled, todo, r WHERE settled.yes AND r.state = 'DRAFT'
    UNION ALL
    -- 3 · what the Centre asked for
    SELECT 'CENTRE_ASKED', CASE r.state WHEN 'DOCUMENTS_PENDING' THEN 'The Centre asks for documents' ELSE 'The Centre asks for verification' END,
           r.request_note, NULL::numeric, '/applicant/cce'
      FROM r WHERE r.state IN ('DOCUMENTS_PENDING', 'VERIFICATION_REQUIRED')
    UNION ALL
    -- 4 · the CCE admission checking fee, once the outcome is published (V404)
    SELECT 'CHECKING_FEE', 'Pay the CCE admission checking fee',
           CASE WHEN k.fee IS NULL THEN 'The Centre has published the outcome of your application; the Bursary has not yet stated the checking fee'
                ELSE 'The Centre has published the outcome of your application; pay to read it' END,
           k.fee, '/applicant/admission'
      FROM k WHERE k.may_pay AND NOT k.past AND EXISTS (SELECT 1 FROM r)
    UNION ALL
    -- 5 · the acceptance fee, once the offer is read
    SELECT 'ACCEPTANCE_FEE', 'Pay the acceptance fee', 'You have read your offer; the acceptance fee accepts it',
           (SELECT f.acceptance_fee FROM fee f), '/applicant/accept'
      FROM a, ent WHERE EXISTS (SELECT 1 FROM r) AND a.decision = 'OFFERED' AND a.decision_released_at IS NOT NULL AND a.status_checked_at IS NOT NULL
                    AND NOT ent.paid AND a.accepted_at IS NULL AND a.declined_at IS NULL AND a.lapsed_at IS NULL;
$fn$;
COMMENT ON FUNCTION admissions.cce_outstanding(uuid) IS
  'V414: what a CCE applicant still has to do, in order — the application fee, the form, what the Centre asked for, the CCE admission checking fee, the acceptance fee. Read only.';
