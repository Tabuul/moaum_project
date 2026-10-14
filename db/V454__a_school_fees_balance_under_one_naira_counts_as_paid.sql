-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V454 — A school-fees balance under one naira counts as paid
--
--   The Bursary's 2025/2026 second-semester lines carry kobo (₦53,488.42, ₦46,778.94, ₦85,294.86 …) while the old portal
--   charged and recorded whole naira (₦53,488.00): imported as the legacy payments, they leave thousands of students 42 or
--   86 kobo short. A shortfall, however small, kept a student from paid-in-full and from the semester's course registration,
--   counted as arrears in the sessions after, and offered a reference for ₦0.42 that Quickteller was asked to collect.
--
--   One test now decides: finance.fee_short(due, paid) — short by one naira or more. Under one naira is paid, wherever
--   school fees are judged:
--     finance.position              the balance (finance.fee_owed), the instalments, paid in full, the arrears of past sessions
--     finance.session_fee_positions the same, set-based, for the Bursary's lists
--     finance.semester_cleared      the semester's course-registration gate
--     finance.payment_position      the College payment report's status and outstanding
--     people.deferment_financials   its status read from finance.position
--     finance.paydirect_customer    a school-fees reference under one naira is refused to Quickteller: it pays nothing
--   Nothing is written off on the ledger and no payment or fee line is changed: what was paid and what is due are read as
--   they are; only whether the difference is owed changes. finance.new_reference already refuses more than the balance,
--   which is now nought for such a student.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V454: a school-fees balance under one naira counts as paid', true);

-- ── the one test ────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.fee_short(p_due numeric, p_paid numeric)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce(p_due, 0) - coalesce(p_paid, 0) >= 1
$$;
COMMENT ON FUNCTION finance.fee_short(numeric, numeric) IS
  'V454: whether school fees paid fall short of what is due by one naira or more. Short by under one naira (kobo: fee lines stated with kobo, paid and recorded in whole naira) counts as paid.';

CREATE FUNCTION finance.fee_owed(p_due numeric, p_paid numeric)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN finance.fee_short(p_due, p_paid) THEN p_due - p_paid ELSE 0 END
$$;
COMMENT ON FUNCTION finance.fee_owed(numeric, numeric) IS
  'V454: what is still owed of what is due, nought when short by under one naira (finance.fee_short).';

-- ── restated on it ──────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance."position"(p_student uuid, p_session text)
 RETURNS TABLE(due numeric, paid numeric, balance numeric, instalments_paid integer, paid_in_full boolean, has_arrears boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH d AS (SELECT coalesce(sum(c.amount), 0) AS due FROM finance.charges(p_student, p_session) c),
         p AS (SELECT coalesce(sum(r.amount), 0) AS paid FROM finance.payment_reference r
                WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'),
         arrears AS (
             SELECT EXISTS (
                 SELECT 1 FROM (SELECT DISTINCT f.session FROM finance.fee_schedule f WHERE f.session < p_session AND f.ended_at IS NULL) past
                  WHERE finance.fee_short((SELECT coalesce(sum(c.amount), 0) FROM finance.charges(p_student, past.session) c),
                                          (SELECT coalesce(sum(r.amount), 0) FROM finance.payment_reference r
                                            WHERE r.student_id = p_student AND r.session = past.session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'))) AS yes)
    -- V454: short by under one naira is paid (the half that is the first instalment likewise)
    SELECT d.due, p.paid, finance.fee_owed(d.due, p.paid),
           CASE WHEN d.due = 0 THEN 2 WHEN NOT finance.fee_short(d.due, p.paid) THEN 2 WHEN NOT finance.fee_short(d.due / 2, p.paid) THEN 1 ELSE 0 END,
           d.due = 0 OR NOT finance.fee_short(d.due, p.paid),
           arrears.yes
      FROM d, p, arrears;
$function$;

CREATE OR REPLACE FUNCTION finance.semester_cleared(p_student uuid, p_session text, p_semester integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    -- V454: short of the semester's cumulative due by under one naira is cleared
    SELECT finance.fee_stated(p_student, p_session)
       AND NOT finance.fee_short(finance.due_for_semester(p_student, p_session, p_semester),
                                 coalesce((SELECT sum(r.amount) FROM finance.payment_reference r
                                            WHERE r.student_id = p_student AND r.session = p_session
                                              AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'), 0));
$function$;

CREATE OR REPLACE FUNCTION finance.session_fee_positions(p_session text)
 RETURNS TABLE(student_id uuid, due numeric, paid numeric, balance numeric, instalments_paid integer, paid_in_full boolean, has_arrears boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH past AS (SELECT DISTINCT f.session FROM finance.fee_schedule f WHERE f.session < p_session AND f.ended_at IS NULL),
    past_paid AS (
        SELECT r.student_id, r.session, sum(r.amount) AS total
          FROM finance.payment_reference r JOIN past ON past.session = r.session
         WHERE r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
         GROUP BY r.student_id, r.session),
    arrears AS (
        SELECT DISTINCT c.student_id
          FROM past CROSS JOIN LATERAL finance.session_charges(past.session) c
          LEFT JOIN past_paid pp ON pp.student_id = c.student_id AND pp.session = past.session
         WHERE finance.fee_short(c.total, coalesce(pp.total, 0))),
    now_ AS (
        SELECT c.student_id, c.total AS due, coalesce(pay.total, 0) AS paid
          FROM finance.session_charges(p_session) c
          LEFT JOIN finance.session_payments(p_session) pay ON pay.student_id = c.student_id)
    -- V454: as finance.position, short by under one naira is paid
    SELECT n.student_id, n.due, n.paid, finance.fee_owed(n.due, n.paid),
           CASE WHEN n.due = 0 THEN 2 WHEN NOT finance.fee_short(n.due, n.paid) THEN 2 WHEN NOT finance.fee_short(n.due / 2, n.paid) THEN 1 ELSE 0 END,
           n.due = 0 OR NOT finance.fee_short(n.due, n.paid),
           EXISTS (SELECT 1 FROM arrears a WHERE a.student_id = n.student_id)
      FROM now_ n
$function$;

CREATE OR REPLACE FUNCTION finance.payment_position(p_student uuid, p_session text, p_semester integer)
 RETURNS TABLE(payable numeric, paid numeric, outstanding numeric, status text, last_paid_at timestamp with time zone, last_reference text, last_channel text, payments integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH due AS (
        SELECT finance.due_for_semester(p_student, p_session, 3) AS total,
               CASE WHEN p_semester IS NULL OR p_semester <= 1 THEN 0 ELSE finance.due_for_semester(p_student, p_session, p_semester - 1) END AS before,
               CASE WHEN p_semester IS NULL THEN finance.due_for_semester(p_student, p_session, 3) ELSE finance.due_for_semester(p_student, p_session, p_semester) END AS upto
    ),
    pay AS (
        SELECT coalesce(sum(r.amount), 0) AS total, count(*)::int AS n
          FROM finance.payment_reference r
         WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
    ),
    last AS (
        SELECT r.confirmed_at, r.reference, r.channel
          FROM finance.payment_reference r
         WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
         ORDER BY r.confirmed_at DESC LIMIT 1
    ),
    pos AS (
        SELECT greatest(due.upto - due.before, 0) AS payable,
               -- the session's payments cover the earlier semesters first; what is left applies to this one
               least(greatest(pay.total - due.before, 0), greatest(due.upto - due.before, 0)) AS applied,
               pay.total AS paid_all, pay.n
          FROM due, pay
    )
    SELECT pos.payable,
           CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END,
           finance.fee_owed(pos.payable, CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END),
           CASE WHEN pos.payable = 0 THEN 'NO_CHARGE'
                WHEN NOT finance.fee_short(pos.payable, CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END) THEN 'FULLY_PAID'
                WHEN (CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END) > 0 THEN 'PART_PAYMENT'
                ELSE 'NOT_PAID' END,
           last.confirmed_at, last.reference, last.channel, pos.n
      FROM pos LEFT JOIN last ON true;
$function$;

CREATE OR REPLACE FUNCTION people.deferment_financials(p_student uuid, p_session text)
 RETURNS TABLE(last_fee_amount numeric, last_fee_ref text, last_fee_at timestamp with time zone, last_fee_session text, last_fee_channel text, last_fee_receipt text, balance numeric, due numeric, paid numeric, balance_session text, position_status text, has_arrears boolean, found boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH last AS (
        SELECT r.amount, r.reference, r.confirmed_at, r.session, r.channel, r.receipt_no
          FROM finance.payment_reference r
         WHERE r.student_id = p_student AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
         ORDER BY r.confirmed_at DESC LIMIT 1),
    ses AS (SELECT coalesce(p_session, (SELECT name FROM policy.academic_session WHERE state = 'CURRENT')) AS name),
    pos AS (SELECT p.* FROM ses, LATERAL finance.position(p_student, ses.name) p)
    SELECT last.amount, last.reference, last.confirmed_at, last.session, last.channel, last.receipt_no,
           pos.balance, pos.due, pos.paid, ses.name,
           CASE WHEN pos.due = 0 THEN 'NO_CHARGE' WHEN pos.paid_in_full THEN 'FULLY_PAID' WHEN pos.paid > 0 THEN 'PART_PAYMENT' ELSE 'NOT_PAID' END,
           pos.has_arrears, last.reference IS NOT NULL
      FROM ses LEFT JOIN last ON true LEFT JOIN pos ON true;
$function$;

CREATE OR REPLACE FUNCTION finance.paydirect_customer(p_reference text)
 RETURNS TABLE(valid boolean, why text, reference text, surname text, other_names text, number text, amount numeric, description text, scope text, biller_code text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_ref text := upper(btrim(coalesce(p_reference, ''))); f admissions.fee_reference; a admissions.application; c admissions.candidate;
        pr finance.payment_reference; s people.student; g admissions.pg_fee_reference; pa admissions.pg_application; pp admissions.pg_applicant;
        b finance.paydirect_biller; v_why text;
BEGIN
    IF v_ref = '' THEN
        RETURN QUERY SELECT false, 'No reference was given', NULL::text, NULL::text, NULL::text, NULL::text, NULL::numeric, NULL::text, NULL::text, NULL::text;
        RETURN;
    END IF;
    b := finance.paydirect_biller_of_reference(v_ref);

    SELECT * INTO f FROM admissions.fee_reference x WHERE x.reference = v_ref;
    IF FOUND THEN
        SELECT * INTO a FROM admissions.application x WHERE x.id = f.application_id;
        SELECT * INTO c FROM admissions.candidate x WHERE x.id = a.candidate_id;
        v_why := CASE WHEN f.confirmed_at IS NOT NULL THEN 'Already paid'
                      WHEN f.expires_at < now() THEN 'Expired: a new reference is generated on the portal, free of charge'
                      WHEN f.kind = 'CHECKING' AND NOT coalesce((SELECT k.may_pay FROM admissions.status_checking(a.id) k), false)
                           THEN 'Admission status checking is closed, or the checking fee is already paid'
                 END;
        RETURN QUERY SELECT v_why IS NULL, v_why, f.reference, c.surname, c.other_names, a.application_no, f.amount,
            CASE f.kind WHEN 'APPLICATION' THEN 'Application fee' WHEN 'CHECKING' THEN 'Admission checking fee' ELSE 'Acceptance fee' END
                || ' ' || a.session, b.scope, b.biller_code;
        RETURN;
    END IF;

    SELECT * INTO pr FROM finance.payment_reference x WHERE x.reference = v_ref;
    IF FOUND THEN
        SELECT * INTO s FROM people.student x WHERE x.id = pr.student_id;
        v_why := CASE WHEN pr.confirmed_at IS NOT NULL THEN 'Already paid'
                      WHEN pr.expires_at < now() THEN 'Expired: a new reference is generated on the portal, free of charge'
                      -- V454: a school-fees balance under one naira counts as paid; a reference for it pays nothing
                      WHEN pr.amount < 1 AND pr.purpose LIKE 'School fees%' THEN 'Nothing to pay: a school-fees balance under one naira counts as paid' END;
        RETURN QUERY SELECT v_why IS NULL, v_why, pr.reference, s.surname, s.other_names, coalesce(s.matric_no, s.admission_no), pr.amount,
            pr.purpose || ' ' || pr.session, b.scope, b.biller_code;
        RETURN;
    END IF;

    SELECT * INTO g FROM admissions.pg_fee_reference x WHERE upper(x.reference) = v_ref;
    IF FOUND THEN
        SELECT * INTO pa FROM admissions.pg_application x WHERE x.id = g.application_id;
        SELECT * INTO pp FROM admissions.pg_applicant x WHERE x.id = pa.applicant_id;
        v_why := CASE WHEN g.confirmed_at IS NOT NULL THEN 'Already paid'
                      WHEN g.expires_at < now() THEN 'Expired: a new reference is generated on the portal, free of charge' END;
        RETURN QUERY SELECT v_why IS NULL, v_why, g.reference, pp.surname, pp.other_names, pa.application_no, g.amount,
            'Postgraduate ' || lower(g.kind) || ' fee ' || pa.session, b.scope, b.biller_code;
        RETURN;
    END IF;

    RETURN QUERY SELECT false, 'No reference like this was generated by the portal', v_ref, NULL::text, NULL::text, NULL::text, NULL::numeric,
                        NULL::text, NULL::text, NULL::text;
END $function$;

COMMENT ON FUNCTION finance.position(uuid, text) IS
  'A student''s school-fees position for a session: due, paid, the balance owed, instalments paid, paid in full, arrears of past sessions. V454: short by under one naira is paid (finance.fee_short).';

COMMIT;
