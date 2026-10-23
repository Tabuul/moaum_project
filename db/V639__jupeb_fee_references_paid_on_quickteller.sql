-- V639: a JUPEB candidate's fee is paid on Quickteller — the University's report of 22 October 2026, a JUPEB applicant's page
-- reading "Card and USSD payment is not open yet" for the ₦15,000 application fee (MOAUM-JUPEBAPP-2026-000036).
--   Pay on Quickteller (V299) is the portal's card and USSD way, and the page offers it for a reference when finance.quickteller_link
--   gives the biller's page for it. The link, Quickteller's question about a reference (finance.paydirect_customer) and the
--   collections report (finance.import_paydirect) read the applicant's, the student's and the postgraduate applicant's references and
--   never a JUPEB candidate's (jupeb.fee_reference, V339): the page said card payment was not open, and Quickteller — or a bank
--   teller — given the reference would have been told no such reference was generated. The settlement of a notified payment already
--   confirms a JUPEB reference (jupeb.confirm_fee), as do the claims, the payer notices and the reference state.
--   Now the three read jupeb.fee_reference too. The University's biller takes it (a JUPEB candidate is not in the College of Health
--   Sciences); Quickteller is told the candidate's name, the application number, the amount and what the fee is, and is refused a
--   reference already paid, expired, or of a withdrawn application; the collections report confirms a JUPEB payment of the whole
--   amount and leaves a short one open, as for every other reference.
-- The three functions are restated exactly as they stand, with those additions.

BEGIN;

CREATE OR REPLACE FUNCTION finance.quickteller_link(p_reference text)
 RETURNS TABLE(url text, reference text, amount numeric, scope text, biller_code text, biller_name text, with_amount boolean)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_ref text := upper(btrim(coalesce(p_reference, ''))); v_stored text; v_amt numeric; b finance.paydirect_biller;
BEGIN
    SELECT x.reference, x.amount INTO v_stored, v_amt FROM (
        SELECT f.reference, f.amount FROM admissions.fee_reference f WHERE f.reference = v_ref
        UNION ALL SELECT r.reference, r.amount FROM finance.payment_reference r WHERE r.reference = v_ref
        UNION ALL SELECT g.reference, g.amount FROM admissions.pg_fee_reference g WHERE upper(g.reference) = v_ref
        -- V639: a JUPEB candidate's fee
        UNION ALL SELECT j.reference, j.amount FROM jupeb.fee_reference j WHERE upper(j.reference) = v_ref) x
     LIMIT 1;
    IF v_stored IS NULL THEN RETURN; END IF;
    b := finance.paydirect_biller_of_reference(v_stored);
    IF b.scope IS NULL OR NOT b.active OR NOT b.redirect OR b.pay_link IS NULL THEN RETURN; END IF;
    RETURN QUERY SELECT b.pay_link || CASE WHEN position('?' IN b.pay_link) > 0 THEN '&' ELSE '?' END
                        || 'cid=' || finance.url_part(v_stored)
                        || CASE WHEN b.with_amount THEN '&amount=' || finance.quickteller_amount(v_amt) ELSE '' END,
                        v_stored, v_amt, b.scope, b.biller_code, b.name, b.with_amount;
END $function$;

CREATE OR REPLACE FUNCTION finance.paydirect_customer(p_reference text)
 RETURNS TABLE(valid boolean, why text, reference text, surname text, other_names text, number text, amount numeric, description text, scope text, biller_code text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_ref text := upper(btrim(coalesce(p_reference, ''))); f admissions.fee_reference; a admissions.application; c admissions.candidate;
        pr finance.payment_reference; s people.student; g admissions.pg_fee_reference; pa admissions.pg_application; pp admissions.pg_applicant;
        b finance.paydirect_biller; v_why text; jf jupeb.fee_reference; ja jupeb.application;
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

    -- V639: a JUPEB candidate's fee — application, status checking, acceptance, school fees
    SELECT * INTO jf FROM jupeb.fee_reference x WHERE upper(x.reference) = v_ref;
    IF FOUND THEN
        SELECT * INTO ja FROM jupeb.application x WHERE x.id = jf.application_id;
        v_why := CASE WHEN jf.confirmed_at IS NOT NULL THEN 'Already paid'
                      WHEN jf.expires_at < now() THEN 'Expired: a new reference is generated on the portal, free of charge'
                      WHEN ja.withdrawn_at IS NOT NULL OR ja.state = 'WITHDRAWN' THEN 'The JUPEB application was withdrawn' END;
        RETURN QUERY SELECT v_why IS NULL, v_why, jf.reference, ja.surname, btrim(coalesce(ja.first_name, '') || ' ' || coalesce(ja.middle_name, '')),
            ja.application_no, jf.amount,
            'JUPEB ' || CASE jf.kind WHEN 'APPLICATION' THEN 'application fee' WHEN 'STATUS_CHECKING' THEN 'admission status checking fee'
                                     WHEN 'ACCEPTANCE' THEN 'acceptance fee' WHEN 'SCHOOL_FIRST' THEN 'school fee, first semester'
                                     WHEN 'SCHOOL_SECOND' THEN 'school fee, second semester' ELSE 'school fee' END || ' ' || jf.session,
            b.scope, b.biller_code;
        RETURN;
    END IF;

    RETURN QUERY SELECT false, 'No reference like this was generated by the portal', v_ref, NULL::text, NULL::text, NULL::text, NULL::numeric,
                        NULL::text, NULL::text, NULL::text;
END $function$;

CREATE OR REPLACE FUNCTION finance.import_paydirect(p_rows jsonb)
 RETURNS TABLE(imported integer, matched integer, unmatched integer, duplicate integer, short_paid integer)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_prn text; v_amt numeric; v_rrn text; v_bill text; v_chan text; v_payer text; v_paid timestamptz; v_owed numeric; v_where text;
        v_state text; v_ref text; v_why text; v_note text; n int := 0; nm int := 0; nu int := 0; nd int := 0; ns int := 0;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'QUICKTELLER_IMPORT_ACTOR: a collections report is imported by a person' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'QUICKTELLER_IMPORT_ROWS: the report is rows: the reference (PRN), the amount, and a settlement reference' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_prn := upper(btrim(coalesce(r->>'prn', r->>'reference', r->>'paymentReference', r->>'PRN', r->>'custReference', r->>'cid', '')));
        IF v_prn = '' THEN CONTINUE; END IF;
        v_amt := nullif(regexp_replace(coalesce(r->>'amount', ''), '[^0-9.]', '', 'g'), '')::numeric;
        v_rrn := nullif(btrim(coalesce(r->>'rrn', r->>'RRN', r->>'transactionRef', r->>'receipt', r->>'paymentLogId', '')), '');
        v_bill := nullif(btrim(coalesce(r->>'billerCode', r->>'biller', '')), '');
        v_chan := nullif(btrim(coalesce(r->>'channel', '')), '');
        v_payer := nullif(btrim(coalesce(r->>'payer', r->>'customer', '')), '');
        BEGIN v_paid := (r->>'paidAt')::timestamptz; EXCEPTION WHEN OTHERS THEN v_paid := NULL; END;

        -- a settlement transaction seen before is not imported twice
        IF v_rrn IS NOT NULL AND EXISTS (SELECT 1 FROM finance.paydirect_collection WHERE biller_code IS NOT DISTINCT FROM v_bill AND rrn = v_rrn) THEN
            nd := nd + 1; CONTINUE;
        END IF;

        v_state := 'UNMATCHED'; v_ref := NULL; v_why := NULL; v_owed := NULL; v_where := NULL;
        SELECT x.amount, x.src INTO v_owed, v_where FROM (
            SELECT p.amount, 'STUDENT' AS src FROM finance.payment_reference p WHERE p.reference = v_prn
            UNION ALL SELECT f.amount, 'APPLICANT' FROM admissions.fee_reference f WHERE f.reference = v_prn
            UNION ALL SELECT g.amount, 'PG' FROM admissions.pg_fee_reference g WHERE upper(g.reference) = v_prn
            -- V639: a JUPEB candidate's fee
            UNION ALL SELECT j.amount, 'JUPEB' FROM jupeb.fee_reference j WHERE upper(j.reference) = v_prn) x
         LIMIT 1;
        v_note := 'Quickteller collections import' || CASE WHEN v_rrn IS NULL THEN '' ELSE ' · ' || v_rrn END;
        IF v_where IS NULL THEN
            v_why := 'No reference matching this PRN was generated by the portal';
        ELSIF v_amt IS NOT NULL AND v_amt < v_owed THEN
            -- money short of what the reference asks is not a payment of it: the Bursary settles the part by hand
            v_state := 'SHORT_PAID'; v_ref := v_prn;
            v_why := 'Paid ' || to_char(v_amt, 'FM999,999,990.00') || ' of the ' || to_char(v_owed, 'FM999,999,990.00') || ' the reference asks; not confirmed';
        ELSE
            IF v_where = 'STUDENT' THEN
                PERFORM finance.confirm_payment(v_prn, coalesce(v_chan, 'Quickteller PayDirect'), v_note);
            ELSIF v_where = 'APPLICANT' THEN
                PERFORM admissions.confirm_fee(v_prn, coalesce(v_chan, 'Quickteller PayDirect'), v_note);
            ELSIF v_where = 'JUPEB' THEN
                PERFORM jupeb.confirm_fee(v_prn, coalesce(v_chan, 'Quickteller PayDirect'));
            ELSE
                PERFORM admissions.pg_confirm_fee((SELECT g.reference FROM admissions.pg_fee_reference g WHERE upper(g.reference) = v_prn LIMIT 1),
                                                  coalesce(v_chan, 'Quickteller PayDirect'));
            END IF;
            v_state := 'MATCHED'; v_ref := v_prn;
        END IF;

        INSERT INTO finance.paydirect_collection (biller_code, prn, amount, paid_at, channel, rrn, payer, state, reference, why)
        VALUES (v_bill, v_prn, v_amt, v_paid, coalesce(v_chan, 'Quickteller PayDirect'), v_rrn, v_payer, v_state, v_ref, v_why);
        n := n + 1;
        IF v_state = 'MATCHED' THEN nm := nm + 1; ELSIF v_state = 'SHORT_PAID' THEN ns := ns + 1; ELSE nu := nu + 1; END IF;
    END LOOP;
    RETURN QUERY SELECT n, nm, nu, nd, ns;
END $function$;

COMMIT;
