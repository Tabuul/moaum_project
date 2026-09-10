-- ═══════════════════════════════════════════════════════════════════════════
-- V080 — Quickteller PayDirect billers, routed by College
--
--   The University collects fees on two Interswitch PayDirect billers: one for
--   all departments (Benue State University, Makurdi — biller 04255101), and one
--   for the College of Health Sciences (04263001). A student pays by entering a
--   PRN — the reference this portal already generates — on the Quickteller page,
--   an ATM, USSD (*723*<biller>*Amount#) or at a bank; PayDirect settles to the
--   biller's account. The payment comes back to the portal two ways: the
--   collections report is imported and matched by PRN, and (when the merchant's
--   API credentials are set) the Transaction Query API is polled — both confirm
--   the reference through the same confirmation every payment passes.
--
--   Which biller a student pays is not a choice: it follows the College. A
--   programme whose faculty sits under the College of Health Sciences pays the
--   CHS biller; every other programme pays the main biller. Fees cannot be
--   routed to the wrong account by hand.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'bursar', true);
SELECT set_config('moaum.reason', 'Quickteller PayDirect billers, routed by College (V080)', true);

-- ── 1 · the billers (routing + what the student is shown; not a secret) ──────
CREATE TABLE finance.paydirect_biller (
    scope       text PRIMARY KEY,
    biller_code text NOT NULL,
    name        text NOT NULL,
    pay_link    text NULL,
    active      boolean NOT NULL DEFAULT true,
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_pdb_scope CHECK (scope IN ('MAIN','CHS')),
    CONSTRAINT ck_pdb_code CHECK (btrim(biller_code) <> '')
);
SELECT audit.attach('finance.paydirect_biller');

INSERT INTO finance.paydirect_biller (scope, biller_code, name, pay_link) VALUES
    ('MAIN', '04255101', 'Benue State University, Makurdi', 'https://www.quickteller.com/bsum'),
    ('CHS',  '04263001', 'College of Health Sciences, Benue', 'https://www.quickteller.com/chsbsu')
ON CONFLICT (scope) DO NOTHING;

CREATE OR REPLACE FUNCTION finance.set_paydirect_biller(p_scope text, p_code text, p_name text, p_link text, p_active boolean)
RETURNS finance.paydirect_biller
LANGUAGE plpgsql AS $$
DECLARE v_scope text := upper(btrim(coalesce(p_scope, ''))); r finance.paydirect_biller;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a biller is set by a person' USING ERRCODE = '23514';
    END IF;
    IF v_scope NOT IN ('MAIN','CHS') THEN RAISE EXCEPTION 'the scope is MAIN or CHS' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_code), '') = '' THEN RAISE EXCEPTION 'a biller has its Interswitch code' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_name), '') = '' THEN RAISE EXCEPTION 'a biller has a name' USING ERRCODE = '23514'; END IF;
    INSERT INTO finance.paydirect_biller (scope, biller_code, name, pay_link, active, updated_at)
    VALUES (v_scope, btrim(p_code), btrim(p_name), nullif(btrim(p_link), ''), coalesce(p_active, true), now())
    ON CONFLICT (scope) DO UPDATE SET biller_code = EXCLUDED.biller_code, name = EXCLUDED.name,
        pay_link = EXCLUDED.pay_link, active = EXCLUDED.active, updated_at = now()
    RETURNING * INTO r;
    RETURN r;
END $$;

-- which biller a student pays: the CHS biller for a College of Health Sciences programme, else the main one
CREATE OR REPLACE FUNCTION finance.paydirect_biller_for(p_student uuid)
RETURNS finance.paydirect_biller
LANGUAGE plpgsql STABLE AS $$
DECLARE v_scope text := 'MAIN'; r finance.paydirect_biller;
BEGIN
    SELECT CASE WHEN f.college_code = 'CHS' THEN 'CHS' ELSE 'MAIN' END INTO v_scope
      FROM people.student s
      JOIN ref.programme p ON p.code = s.programme_code
      JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE s.id = p_student;
    v_scope := coalesce(v_scope, 'MAIN');
    SELECT * INTO r FROM finance.paydirect_biller WHERE scope = v_scope AND active;
    IF NOT FOUND THEN SELECT * INTO r FROM finance.paydirect_biller WHERE scope = 'MAIN'; END IF;
    RETURN r;
END $$;

-- ── 2 · the collections report, imported and matched by PRN ──────────────────
CREATE TABLE finance.paydirect_collection (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    biller_code text NULL,
    prn         text NOT NULL,
    amount      numeric(14,2) NULL,
    paid_at     timestamptz NULL,
    channel     text NULL,
    rrn         text NULL,
    payer       text NULL,
    state       text NOT NULL DEFAULT 'UNMATCHED',
    reference   text NULL,
    why         text NULL,
    imported_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_pdc_state CHECK (state IN ('MATCHED','UNMATCHED','DUPLICATE'))
);
CREATE UNIQUE INDEX uq_pdc_txn ON finance.paydirect_collection (biller_code, rrn) WHERE rrn IS NOT NULL;
CREATE INDEX ix_pdc_state ON finance.paydirect_collection (state, imported_at);
SELECT audit.attach('finance.paydirect_collection');

-- a settlement/collections report loaded: each PRN matched to the reference this portal generated and confirmed
CREATE OR REPLACE FUNCTION finance.import_paydirect(p_rows jsonb)
RETURNS TABLE (imported int, matched int, unmatched int, duplicate int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_prn text; v_amt numeric; v_rrn text; v_bill text; v_chan text; v_payer text; v_paid timestamptz;
        v_state text; v_ref text; v_why text; n int := 0; nm int := 0; nu int := 0; nd int := 0;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a collections report is imported by a person' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the report is rows: PRN, amount, and a settlement reference' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_prn := upper(btrim(coalesce(r->>'prn', r->>'reference', r->>'paymentReference', r->>'PRN', '')));
        IF v_prn = '' THEN CONTINUE; END IF;
        v_amt := nullif(regexp_replace(coalesce(r->>'amount', ''), '[^0-9.]', '', 'g'), '')::numeric;
        v_rrn := nullif(btrim(coalesce(r->>'rrn', r->>'RRN', r->>'transactionRef', r->>'receipt', '')), '');
        v_bill := nullif(btrim(coalesce(r->>'billerCode', r->>'biller', '')), '');
        v_chan := nullif(btrim(coalesce(r->>'channel', 'Quickteller PayDirect')), '');
        v_payer := nullif(btrim(coalesce(r->>'payer', r->>'customer', '')), '');
        BEGIN v_paid := (r->>'paidAt')::timestamptz; EXCEPTION WHEN OTHERS THEN v_paid := NULL; END;

        -- a settlement transaction seen before is not imported twice
        IF v_rrn IS NOT NULL AND EXISTS (SELECT 1 FROM finance.paydirect_collection WHERE biller_code IS NOT DISTINCT FROM v_bill AND rrn = v_rrn) THEN
            nd := nd + 1; CONTINUE;
        END IF;

        v_state := 'UNMATCHED'; v_ref := NULL; v_why := NULL;
        IF EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = v_prn) THEN
            PERFORM finance.confirm_payment(v_prn, coalesce(v_chan, 'Quickteller PayDirect'),
                    'PayDirect collections import' || CASE WHEN v_rrn IS NULL THEN '' ELSE ' · ' || v_rrn END);
            v_state := 'MATCHED'; v_ref := v_prn;
        ELSIF EXISTS (SELECT 1 FROM admissions.fee_reference WHERE reference = v_prn) THEN
            PERFORM admissions.confirm_fee(v_prn, coalesce(v_chan, 'Quickteller PayDirect'),
                    'PayDirect collections import' || CASE WHEN v_rrn IS NULL THEN '' ELSE ' · ' || v_rrn END);
            v_state := 'MATCHED'; v_ref := v_prn;
        ELSE
            v_why := 'No reference matching this PRN was generated by the portal';
        END IF;

        INSERT INTO finance.paydirect_collection (biller_code, prn, amount, paid_at, channel, rrn, payer, state, reference, why)
        VALUES (v_bill, v_prn, v_amt, v_paid, v_chan, v_rrn, v_payer, v_state, v_ref, v_why);
        n := n + 1;
        IF v_state = 'MATCHED' THEN nm := nm + 1; ELSE nu := nu + 1; END IF;
    END LOOP;
    RETURN QUERY SELECT n, nm, nu, nd;
END $$;

-- ── 3 · admit 'paydirect' to the encrypted secret store, for the query API creds ──
ALTER TABLE finance.gateway_credential DROP CONSTRAINT ck_gc_gateway;
ALTER TABLE finance.gateway_credential
    ADD CONSTRAINT ck_gc_gateway CHECK (gateway IN ('paystack','flutterwave','quickteller','paydirect'));

CREATE OR REPLACE FUNCTION finance.set_gateway_secret(p_gateway text, p_secret text, p_hash text, p_mode text, p_last4 text, p_key text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_existed boolean; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF p_gateway NOT IN ('paystack','flutterwave','quickteller','paydirect') THEN RAISE EXCEPTION 'no such gateway %', p_gateway USING ERRCODE = '23514'; END IF;
    IF p_key IS NULL OR length(p_key) < 8 THEN
        RAISE EXCEPTION 'no server passphrase to encrypt the key with' USING ERRCODE = '23514',
            HINT = 'Set MOAUM_CONFIG_KEY (or MOAUM_AUTH_HMAC_SECRET) on the API service; a key is never stored in the clear.';
    END IF;
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a gateway key is set by a person' USING ERRCODE = '23514'; END IF;
    IF p_secret IS NULL OR btrim(p_secret) = '' THEN RAISE EXCEPTION 'the secret key is blank' USING ERRCODE = '23514'; END IF;
    SELECT EXISTS (SELECT 1 FROM finance.gateway_credential WHERE gateway = p_gateway AND secret_enc IS NOT NULL) INTO v_existed;
    INSERT INTO finance.gateway_credential (gateway, secret_enc, hash_enc, mode, last4, set_by, set_at)
    VALUES (p_gateway, pgp_sym_encrypt(btrim(p_secret), p_key),
            CASE WHEN nullif(btrim(p_hash), '') IS NULL THEN NULL ELSE pgp_sym_encrypt(btrim(p_hash), p_key) END,
            p_mode, p_last4, v_actor, now())
    ON CONFLICT (gateway) DO UPDATE SET secret_enc = EXCLUDED.secret_enc,
        hash_enc = coalesce(EXCLUDED.hash_enc, finance.gateway_credential.hash_enc),
        mode = EXCLUDED.mode, last4 = EXCLUDED.last4, set_by = EXCLUDED.set_by, set_at = EXCLUDED.set_at;
    INSERT INTO finance.gateway_credential_event (gateway, kind, mode, last4, by_person)
    VALUES (p_gateway, CASE WHEN v_existed THEN 'ROTATED' ELSE 'SET' END, p_mode, p_last4, v_actor);
END $$;

CREATE OR REPLACE FUNCTION finance.gateway_config()
RETURNS TABLE (gateway text, configured boolean, has_hash boolean, mode text, last4 text, set_at timestamptz, set_by_name text)
LANGUAGE sql STABLE AS $$
    SELECT g.gateway, c.secret_enc IS NOT NULL, c.hash_enc IS NOT NULL, c.mode, c.last4, c.set_at,
           CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END
      FROM (VALUES ('paystack'), ('flutterwave'), ('quickteller'), ('paydirect')) g(gateway)
      LEFT JOIN finance.gateway_credential c ON c.gateway = g.gateway
      LEFT JOIN iam.person p ON p.id = c.set_by
     ORDER BY g.gateway
$$;

COMMIT;
