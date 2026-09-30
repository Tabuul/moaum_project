-- ═══════════════════════════════════════════════════════════════════════════
-- V299 — Pay on Quickteller: the payer is sent to the University's biller page
--        with the portal's own reference
--
--   Interswitch's answer to the University (30 September 2026): the portal
--   sends the payer to the biller's Quickteller page with the payment
--   reference in the cid parameter, and optionally the amount —
--
--       https://quickteller.com/bsum?cid=<reference>
--       https://quickteller.com/bsum?cid=<reference>&amount=<amount>
--
--   — and Quickteller validates the reference when the payer presses
--   Continue. The reference is the one this portal already generates
--   (MOAUM-APP-…, MOAUM-FEE-…, MOAUM-PGAPP-…), unchanged: the BSUM… number in
--   Interswitch's note is an example only.
--
--   The billers are V080's: the University's (04255101, quickteller.com/bsum)
--   for every department, and the College of Health Sciences' own (04263001)
--   for a payer whose programme is in the College — the same routing by
--   College as Interswitch WebPAY (V276), so a payment reaches the same
--   account whichever Interswitch channel the payer uses. Each biller gains
--   two switches: whether the portal sends payers to its page (off until the
--   Bursary turns it on, once Interswitch has pointed the biller's validation
--   and notification at the portal), and whether the amount rides in the link.
--   A pay link can only be an Interswitch page: nobody can point the payers of
--   the University at another site from the Bursary's screen.
--
--   Quickteller asks the portal about a reference (PayDirect customer
--   validation) and tells it about a payment (payment notification); what the
--   portal answers is read here, and every call is kept on the gateway log —
--   a reference check as its own source, a reversal as its own outcome. The
--   collections report import (V080) now leaves a short payment unconfirmed
--   and matches postgraduate references as well.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V299: Pay on Quickteller with the portal reference', true);

-- ── 1 · each biller: whether the portal sends payers to it, and whether the amount rides in the link ──
ALTER TABLE finance.paydirect_biller ADD COLUMN IF NOT EXISTS redirect boolean NOT NULL DEFAULT false;
ALTER TABLE finance.paydirect_biller ADD COLUMN IF NOT EXISTS with_amount boolean NOT NULL DEFAULT true;

-- the link in the form Interswitch gave, where the V080 seed still stands
UPDATE finance.paydirect_biller SET pay_link = 'https://quickteller.com/bsum', updated_at = now()
 WHERE scope = 'MAIN' AND pay_link = 'https://www.quickteller.com/bsum';
UPDATE finance.paydirect_biller SET pay_link = 'https://quickteller.com/chsbsu', updated_at = now()
 WHERE scope = 'CHS' AND pay_link = 'https://www.quickteller.com/chsbsu';

-- a pay link is an Interswitch page: https, a Quickteller or Interswitch host, a path, nothing after it
-- (the portal adds the query); NOT VALID so a link set by hand before is kept until it is next edited
ALTER TABLE finance.paydirect_biller DROP CONSTRAINT IF EXISTS ck_pdb_link;
ALTER TABLE finance.paydirect_biller ADD CONSTRAINT ck_pdb_link CHECK (pay_link IS NULL OR pay_link ~
    '^https://([a-z0-9-]+\.)*(quickteller\.com|quickteller\.net|interswitchng\.com|interswitchgroup\.com)(/[A-Za-z0-9._~-]+)*/?$') NOT VALID;
-- the portal sends payers only to a biller that is in use and has its link
ALTER TABLE finance.paydirect_biller DROP CONSTRAINT IF EXISTS ck_pdb_redirect;
ALTER TABLE finance.paydirect_biller ADD CONSTRAINT ck_pdb_redirect CHECK (NOT redirect OR (active AND pay_link IS NOT NULL));

DROP FUNCTION IF EXISTS finance.set_paydirect_biller(text, text, text, text, boolean);
CREATE OR REPLACE FUNCTION finance.set_paydirect_biller(p_scope text, p_code text, p_name text, p_link text, p_active boolean,
                                                        p_redirect boolean, p_with_amount boolean)
RETURNS finance.paydirect_biller
LANGUAGE plpgsql AS $$
DECLARE v_scope text := upper(btrim(coalesce(p_scope, ''))); v_link text := nullif(btrim(coalesce(p_link, '')), ''); v_host text;
        v_active boolean := coalesce(p_active, true); v_redirect boolean := coalesce(p_redirect, false); r finance.paydirect_biller;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'QUICKTELLER_BILLER_ACTOR: a biller is set by a person' USING ERRCODE = '23514';
    END IF;
    IF v_scope NOT IN ('MAIN', 'CHS') THEN
        RAISE EXCEPTION 'QUICKTELLER_BILLER_SCOPE: the biller is MAIN (every department) or CHS (the College of Health Sciences)' USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_code), '') = '' THEN RAISE EXCEPTION 'QUICKTELLER_BILLER_CODE: a biller has its Interswitch biller code' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_name), '') = '' THEN RAISE EXCEPTION 'QUICKTELLER_BILLER_NAME: a biller has a name' USING ERRCODE = '23514'; END IF;
    IF v_link IS NOT NULL THEN
        -- the host is read without regard to case; the path is kept as written
        v_host := substring(v_link from '^[A-Za-z]+://[^/?#]+');
        IF v_host IS NOT NULL THEN v_link := lower(v_host) || substr(v_link, length(v_host) + 1); END IF;
        v_link := regexp_replace(v_link, '/+$', '');
        IF v_link !~ '^https://([a-z0-9-]+\.)*(quickteller\.com|quickteller\.net|interswitchng\.com|interswitchgroup\.com)(/[A-Za-z0-9._~-]+)*$' THEN
            RAISE EXCEPTION 'QUICKTELLER_LINK: the pay link is the biller''s own Quickteller page, such as https://quickteller.com/bsum — https, a Quickteller or Interswitch address, and nothing after the path'
                USING ERRCODE = '23514', HINT = 'The portal adds ?cid=<reference> (and the amount) itself; a link to any other site is refused.';
        END IF;
    END IF;
    IF v_redirect AND (NOT v_active OR v_link IS NULL) THEN
        RAISE EXCEPTION 'QUICKTELLER_REDIRECT_NEEDS_LINK: the portal sends payers only to a biller that is in use and has its pay link'
            USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.paydirect_biller (scope, biller_code, name, pay_link, active, redirect, with_amount, updated_at)
    VALUES (v_scope, btrim(p_code), btrim(p_name), v_link, v_active, v_redirect, coalesce(p_with_amount, true), now())
    ON CONFLICT (scope) DO UPDATE SET biller_code = EXCLUDED.biller_code, name = EXCLUDED.name, pay_link = EXCLUDED.pay_link,
        active = EXCLUDED.active, redirect = EXCLUDED.redirect, with_amount = EXCLUDED.with_amount, updated_at = now()
    RETURNING * INTO r;
    RETURN r;
END $$;

-- ── 2 · the biller a reference is paid to: routed by the payer's College, whoever the payer is ──
-- the College of Health Sciences' own biller when the payer's programme is in the College and that biller
-- is in use; the University's otherwise — an applicant by the programme on the candidate, a student by the
-- programme on the register, a postgraduate applicant by the programme applied for (as WebPAY, V276)
CREATE OR REPLACE FUNCTION finance.paydirect_biller_of_reference(p_reference text)
RETURNS finance.paydirect_biller
LANGUAGE plpgsql STABLE AS $$
DECLARE v_ref text := upper(btrim(coalesce(p_reference, ''))); v_code text; v_college text; r finance.paydirect_biller;
BEGIN
    SELECT x.code INTO v_code FROM (
        SELECT admissions.programme_code_of(c.programme) AS code
          FROM admissions.fee_reference fr JOIN admissions.application a ON a.id = fr.application_id JOIN admissions.candidate c ON c.id = a.candidate_id
         WHERE fr.reference = v_ref
        UNION ALL
        SELECT s.programme_code FROM finance.payment_reference pr JOIN people.student s ON s.id = pr.student_id WHERE pr.reference = v_ref
        UNION ALL
        SELECT pa.programme_code FROM admissions.pg_fee_reference fr JOIN admissions.pg_application pa ON pa.id = fr.application_id
         WHERE upper(fr.reference) = v_ref) x
     LIMIT 1;
    SELECT f.college_code INTO v_college FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code WHERE p.code = v_code;
    IF v_college = 'CHS' THEN
        SELECT * INTO r FROM finance.paydirect_biller WHERE scope = 'CHS' AND active;
        IF FOUND THEN RETURN r; END IF;
    END IF;
    SELECT * INTO r FROM finance.paydirect_biller WHERE scope = 'MAIN';
    RETURN r;
END $$;

-- ── 3 · the link itself ──────────────────────────────────────────────────────
-- a value as it may stand in a query string: letters, digits and - . _ ~ as they are, anything else escaped
CREATE OR REPLACE FUNCTION finance.url_part(p text)
RETURNS text
LANGUAGE sql IMMUTABLE STRICT AS $$
    SELECT coalesce(string_agg(CASE WHEN ch ~ '^[A-Za-z0-9._~-]$' THEN ch
                                    ELSE (SELECT string_agg('%' || upper(lpad(to_hex(get_byte(convert_to(ch, 'UTF8'), i)), 2, '0')), '' ORDER BY i)
                                            FROM generate_series(0, octet_length(convert_to(ch, 'UTF8')) - 1) i) END, '' ORDER BY n), '')
      FROM regexp_split_to_table(p, '') WITH ORDINALITY AS t(ch, n)
$$;

-- the amount as the link carries it: naira, whole naira without decimals (51000), else two places (51000.50)
CREATE OR REPLACE FUNCTION finance.quickteller_amount(p numeric)
RETURNS text
LANGUAGE sql IMMUTABLE STRICT AS $$
    SELECT CASE WHEN p = trunc(p) THEN trunc(p)::bigint::text ELSE to_char(round(p, 2), 'FM999999999990.00') END
$$;

-- the Quickteller page a reference is paid on, or no row when the portal does not send its payer there
-- (an unknown reference, a biller not in use, the redirect off, no pay link)
CREATE OR REPLACE FUNCTION finance.quickteller_link(p_reference text)
RETURNS TABLE (url text, reference text, amount numeric, scope text, biller_code text, biller_name text, with_amount boolean)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_ref text := upper(btrim(coalesce(p_reference, ''))); v_stored text; v_amt numeric; b finance.paydirect_biller;
BEGIN
    SELECT x.reference, x.amount INTO v_stored, v_amt FROM (
        SELECT f.reference, f.amount FROM admissions.fee_reference f WHERE f.reference = v_ref
        UNION ALL SELECT r.reference, r.amount FROM finance.payment_reference r WHERE r.reference = v_ref
        UNION ALL SELECT g.reference, g.amount FROM admissions.pg_fee_reference g WHERE upper(g.reference) = v_ref) x
     LIMIT 1;
    IF v_stored IS NULL THEN RETURN; END IF;
    b := finance.paydirect_biller_of_reference(v_stored);
    IF b.scope IS NULL OR NOT b.active OR NOT b.redirect OR b.pay_link IS NULL THEN RETURN; END IF;
    RETURN QUERY SELECT b.pay_link || CASE WHEN position('?' IN b.pay_link) > 0 THEN '&' ELSE '?' END
                        || 'cid=' || finance.url_part(v_stored)
                        || CASE WHEN b.with_amount THEN '&amount=' || finance.quickteller_amount(v_amt) ELSE '' END,
                        v_stored, v_amt, b.scope, b.biller_code, b.name, b.with_amount;
END $$;

-- whether the portal sends anybody to Quickteller at all: the payer's button asks before it knows the reference
CREATE OR REPLACE FUNCTION finance.quickteller_redirect_on()
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM finance.paydirect_biller WHERE active AND redirect AND pay_link IS NOT NULL)
$$;

-- ── 4 · what Quickteller is told when it asks about a reference (PayDirect customer validation) ──
-- a reference is payable when the portal generated it, it is not paid, it has not expired, and — for the
-- admission checking fee — Admission Status Checking is open and the fee not yet paid (V295); the payer's
-- name and the amount owed are what the payer confirms on Quickteller's page before paying
CREATE OR REPLACE FUNCTION finance.paydirect_customer(p_reference text)
RETURNS TABLE (valid boolean, why text, reference text, surname text, other_names text, number text, amount numeric,
               description text, scope text, biller_code text)
LANGUAGE plpgsql STABLE AS $$
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
                      WHEN pr.expires_at < now() THEN 'Expired: a new reference is generated on the portal, free of charge' END;
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
END $$;

-- ── 5 · the gateway log keeps Quickteller's reference checks and its reversals ──
ALTER TABLE finance.gateway_event DROP CONSTRAINT IF EXISTS ck_ge_source;
ALTER TABLE finance.gateway_event ADD CONSTRAINT ck_ge_source CHECK (source IN ('WEBHOOK', 'VERIFY', 'SWEEP', 'TEST', 'RETURN', 'VALIDATE'));
ALTER TABLE finance.gateway_event DROP CONSTRAINT IF EXISTS ck_ge_outcome;
ALTER TABLE finance.gateway_event ADD CONSTRAINT ck_ge_outcome CHECK (outcome IN
    ('SETTLED', 'ALREADY_SETTLED', 'UNKNOWN_REFERENCE', 'SHORT_PAID', 'NOT_SUCCESSFUL', 'IGNORED', 'BAD_SIGNATURE', 'GATEWAY_ERROR',
     'REVERSED', 'VALID', 'INVALID'));

-- ── 6 · the collections report: a short payment stays open, a postgraduate reference is matched too ──
ALTER TABLE finance.paydirect_collection DROP CONSTRAINT IF EXISTS ck_pdc_state;
ALTER TABLE finance.paydirect_collection ADD CONSTRAINT ck_pdc_state CHECK (state IN ('MATCHED', 'UNMATCHED', 'DUPLICATE', 'SHORT_PAID'));

DROP FUNCTION IF EXISTS finance.import_paydirect(jsonb);
CREATE FUNCTION finance.import_paydirect(p_rows jsonb)
RETURNS TABLE (imported int, matched int, unmatched int, duplicate int, short_paid int)
LANGUAGE plpgsql AS $$
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
            UNION ALL SELECT g.amount, 'PG' FROM admissions.pg_fee_reference g WHERE upper(g.reference) = v_prn) x
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
END $$;

COMMIT;
