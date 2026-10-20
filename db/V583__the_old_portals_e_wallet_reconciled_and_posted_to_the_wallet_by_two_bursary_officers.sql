-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V583 — The old portal's e-wallet reconciled: top-ups and wallet-paid fees already imported read per student, the balance
--        verified by one Bursary officer and posted to the wallet by another, usable on school fees through the wallet that exists
--
--   The old portal had an e-wallet: a student topped it up through the gateway and paid fees from it. The old-fees export brought
--   both halves into the portal as payments (V498): a top-up is a payment whose purpose reads "E-WALLET TOP-UP (legacy)", and a fee
--   paid from the wallet is a payment whose method, on the note, reads "E-Wallet". On the live-shaped copy: 2,992 top-ups
--   (₦73.8M) by 2,885 students; 8,667 school-fee payments (₦533M) made from the old wallet. Nothing credited the wallet the
--   portal keeps (finance.wallet_entry, V033/V327/V545), so a student whose old wallet still held money could not use it, and the
--   top-ups were read as other income (purpose OTHER), not as wallet deposits.
--
--   Now, on the wallet that exists — its ledger, its sources, its application to fees (finance.apply_wallet), its refunds, its
--   statement, its posting on the general ledger (V545):
--     · finance.legacy_wallet: one row a student who topped up the old wallet — the top-ups, what was paid from the wallet, and
--       the balance the two leave (finance.legacy_wallet_compute, set-based over the imported payments, run again at any time;
--       a row already posted is never recomputed into a second credit). Where the Bursary holds the old portal's own statement
--       for a student (top-ups, used, refunds, reversals, balance) it is entered on the row and governs; a difference from the
--       derived figures is noted.
--     · the balance is CLASSED, never trusted: used ≤ top-ups and something left → COMPUTED, for an officer to verify; used >
--       top-ups → REQUIRES_REVIEW (the old wallet was funded by something the export does not hold — an earlier balance, a
--       NELFUND credit — and nothing is posted on a guess); nothing left → NO_BALANCE. A student who paid from the old wallet
--       with no top-up on file is counted, not credited.
--     · finance.legacy_wallet_verify — the Students Account Officer or the Bursar marks the rows checked (VERIFIED);
--       finance.legacy_wallet_post — a Bursar officer OTHER than the one who verified posts them: one CREDIT on the wallet of
--       source LEGACY_WALLET (a funding source of the student's own nature: applied last, refundable as own money), dated the
--       last top-up, carrying the figures and the old reference, under a batch LEGACY-WALLET/YYYY/NNNNNN; once only (the row
--       and a unique index on the credit). The student is told (LEGACY_WALLET_POSTED) and applies it to the session's fees on the
--       wallet page, wholly or in part, the fees short settled through the gateway — exactly as a NELFUND or self top-up is.
--     · on the general ledger the credit is drawn from Opening balance / suspense (3900) into Student deposits & wallet (2100),
--       as V545 draws every old-portal credit: the top-ups' cash was booked when they were imported; the Bursary settles 3900
--       from Accounting → Wallet opening (V552). The top-up purpose is now classed WALLET_TOP_UP (a wallet deposit, as a gateway
--       top-up is), so the payments reports no longer read it as other income.
--     · finance.legacy_wallet_figures and finance.legacy_wallet_rows answer the desk: top-ups, used, available, posted, applied
--       to fees, remaining, under review, no balance, paid from the wallet with no top-up on file.
--   The payment swap (V527) already corrects a verified old-portal payment credited to the wrong student; nothing here is a second.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V583: the old portal''s e-wallet reconciled', true);

-- ── 1 · the source, the purpose, the ledger account ─────────────────────────────────────────────────────────────────────

INSERT INTO finance.funding_source (code, name, nature, sponsor, account, active, note, sort)
VALUES ('LEGACY_WALLET', 'Old-portal e-wallet balance', 'SELF', NULL, NULL, true,
        'What the student still held in the old portal''s e-wallet: top-ups less the fees paid from it, verified and posted by the Bursary (V583). The student''s own money: applied to fees after a loan or a grant, refundable as own money.', 80)
ON CONFLICT (code) DO NOTHING;

-- an old-portal top-up is a wallet deposit, as a gateway top-up is — not other income
UPDATE finance.payment_category SET pattern = '^(e-?wallet top-?up|wallet top-?up)' WHERE code = 'WALLET';
UPDATE finance.category_memo m SET code = finance.categorise(nullif(m.kind, ''), nullif(m.purpose, ''))
 WHERE m.purpose ~* '^e-?wallet top-?up';

-- a legacy-wallet credit is drawn from Opening balance / suspense, as V545 draws every old-portal credit (restated from V545)
CREATE OR REPLACE FUNCTION finance.gl_wallet_credit_account(p_source text, p_legacy boolean)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN p_legacy OR p_source = 'LEGACY_WALLET' THEN '3900'
                WHEN (SELECT fs.nature FROM finance.funding_source fs WHERE fs.code = p_source) = 'GRANT' THEN '5240'
                ELSE '1010' END
$$;

-- the statement names the old portal as the origin of a legacy-wallet credit (restated from V327/V545)
CREATE OR REPLACE FUNCTION finance.wallet_statement(p_student uuid)
RETURNS TABLE (id uuid, at timestamptz, session text, kind text, amount numeric, reference text, note text, source_code text, source_name text, nature text,
               balance numeric, origin text, legacy_reference text, legacy_paid_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT e.id, e.at, e.session, e.kind, e.amount, e.reference, e.note,
           e.source_code, fs.name, fs.nature,
           sum(CASE WHEN e.kind IN ('CREDIT', 'TOPUP') THEN e.amount ELSE -e.amount END) OVER (ORDER BY e.at, e.id),
           CASE WHEN e.legacy_payment_id IS NOT NULL OR (e.kind = 'CREDIT' AND e.source_code = 'LEGACY_WALLET') THEN 'OLD_PORTAL'
                WHEN e.kind = 'TOPUP' THEN 'GATEWAY'
                WHEN e.kind = 'CREDIT' AND EXISTS (SELECT 1 FROM finance.nelfund_batch b WHERE b.ref = e.reference) THEN 'REMITTANCE'
                WHEN e.kind = 'CREDIT' THEN 'BURSARY'
                ELSE 'WALLET' END,
           coalesce(lp.source_reference, lp.source_transaction_id, CASE WHEN e.kind = 'CREDIT' AND e.source_code = 'LEGACY_WALLET' THEN e.reference END),
           coalesce(lp.paid_at, CASE WHEN e.kind = 'CREDIT' AND e.source_code = 'LEGACY_WALLET' THEN e.at END)
      FROM finance.wallet_entry e
      LEFT JOIN finance.funding_source fs ON fs.code = e.source_code
      LEFT JOIN finance.legacy_nelfund_payment lp ON lp.id = e.legacy_payment_id
     WHERE e.student_id = p_student ORDER BY e.at, e.id
$$;

-- ── 2 · the reconciliation, one row a student ───────────────────────────────────────────────────────────────────────────

CREATE SEQUENCE finance.legacy_wallet_batch_seq;

CREATE TABLE finance.legacy_wallet_batch (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref       text NOT NULL UNIQUE CHECK (ref ~ '^LEGACY-WALLET/[0-9]{4}/[0-9]{6}$'),
    posted_by uuid NOT NULL,
    office    text,
    posted_at timestamptz NOT NULL DEFAULT now(),
    students  integer NOT NULL DEFAULT 0,
    amount    numeric(14,2) NOT NULL DEFAULT 0,
    skipped   integer NOT NULL DEFAULT 0,
    note      text
);
COMMENT ON TABLE finance.legacy_wallet_batch IS 'V583: a posting of verified old-portal e-wallet balances to the wallet (LEGACY-WALLET/YYYY/NNNNNN): who, when, how many, how much';
SELECT audit.attach('finance.legacy_wallet_batch');

CREATE TABLE finance.legacy_wallet (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id       uuid NOT NULL UNIQUE REFERENCES people.student (id) ON DELETE CASCADE,
    -- derived from the imported payments
    topups           numeric(14,2) NOT NULL DEFAULT 0,
    topup_count      integer NOT NULL DEFAULT 0,
    used             numeric(14,2) NOT NULL DEFAULT 0,
    used_count       integer NOT NULL DEFAULT 0,
    first_topup_at   timestamptz,
    last_topup_at    timestamptz,
    last_topup_ref   text,
    session          text,
    -- the old portal's own statement for the student, where the Bursary holds it: it governs
    stated_topups    numeric(14,2),
    stated_used      numeric(14,2),
    stated_refunds   numeric(14,2),
    stated_reversed  numeric(14,2),
    stated_balance   numeric(14,2),
    stated_source    text,
    stated_note      text,
    stated_by        uuid,
    stated_at        timestamptz,
    available        numeric(14,2) NOT NULL DEFAULT 0 CHECK (available >= 0),
    status           text NOT NULL DEFAULT 'COMPUTED'
                     CHECK (status IN ('COMPUTED', 'VERIFIED', 'POSTED', 'NO_BALANCE', 'REQUIRES_REVIEW', 'REJECTED', 'FROZEN')),
    reason_code      text,
    reason           text,
    computed_at      timestamptz NOT NULL DEFAULT now(),
    verified_by      uuid,
    verified_office  text,
    verified_at      timestamptz,
    verify_note      text,
    posted_by        uuid,
    posted_office    text,
    posted_at        timestamptz,
    batch_ref        text REFERENCES finance.legacy_wallet_batch (ref),
    wallet_entry_id  uuid REFERENCES finance.wallet_entry (id) ON DELETE CASCADE,   -- the go-live reset clears the credit and the row with it
    decided_by       uuid,
    decided_office   text,
    decided_at       timestamptz,
    decision_note    text,
    CONSTRAINT ck_legacy_wallet_posted CHECK (status <> 'POSTED' OR wallet_entry_id IS NOT NULL),
    CONSTRAINT ck_legacy_wallet_two_officers CHECK (posted_by IS NULL OR verified_by IS NULL OR posted_by <> verified_by)
);
CREATE INDEX ix_legacy_wallet_status ON finance.legacy_wallet (status);
COMMENT ON TABLE finance.legacy_wallet IS
  'V583: a student''s old-portal e-wallet reconciled — the top-ups and the fees paid from the wallet as the old-fees export brought them, the old portal''s own statement where the Bursary holds it, the balance they leave, its class (computed, verified, posted, no balance, requires review, rejected, frozen), who verified and who posted it (never the same officer), the credit it became';
SELECT audit.attach('finance.legacy_wallet');
-- one legacy-wallet credit a student, ever
CREATE UNIQUE INDEX ux_wallet_entry_legacy_wallet ON finance.wallet_entry (student_id) WHERE kind = 'CREDIT' AND source_code = 'LEGACY_WALLET';

CREATE FUNCTION finance.legacy_wallet_office_verifies(p_office text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT p_office IN ('bursar', 'studentaccounts', 'super') $$;
CREATE FUNCTION finance.legacy_wallet_office_posts(p_office text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT p_office IN ('bursar', 'super') $$;

/* the payments the old-fees export brought: a top-up by its purpose, a payment from the wallet by the method on its note */
CREATE FUNCTION finance.legacy_wallet_is_topup(p_purpose text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(p_purpose ~* '^e-?wallet top-?up', false) $$;
CREATE FUNCTION finance.legacy_wallet_method(p_note text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$ SELECT nullif(btrim(split_part(coalesce(p_note, ''), chr(183), 2)), '') $$;

-- ── 3 · compute: every student's old wallet from the imported payments (one student, or all) ─────────────────────────────

CREATE FUNCTION finance.legacy_wallet_compute(p_student uuid DEFAULT NULL)
RETURNS TABLE (students integer, with_balance integer, review integer, no_balance integer, posted integer, available numeric)
LANGUAGE plpgsql AS $fn$
DECLARE n_students int; n_with int; n_review int; n_none int; n_posted int; v_avail numeric;
BEGIN
    WITH legacy AS MATERIALIZED (
        SELECT pr.student_id, pr.amount, pr.confirmed_at, pr.session, pr.note, pr.reference,
               finance.legacy_wallet_is_topup(pr.purpose) AS is_topup,
               finance.legacy_wallet_method(pr.note) = 'E-Wallet' AS from_wallet
          FROM finance.payment_reference pr
         WHERE pr.channel = 'Legacy' AND pr.confirmed_at IS NOT NULL AND pr.student_id IS NOT NULL
           AND (p_student IS NULL OR pr.student_id = p_student)
           AND (finance.legacy_wallet_is_topup(pr.purpose) OR finance.legacy_wallet_method(pr.note) = 'E-Wallet')),
    per AS (
        SELECT l.student_id,
               coalesce(sum(l.amount) FILTER (WHERE l.is_topup), 0) AS topups, count(*) FILTER (WHERE l.is_topup) AS topup_count,
               coalesce(sum(l.amount) FILTER (WHERE l.from_wallet AND NOT l.is_topup), 0) AS used, count(*) FILTER (WHERE l.from_wallet AND NOT l.is_topup) AS used_count,
               min(l.confirmed_at) FILTER (WHERE l.is_topup) AS first_topup_at, max(l.confirmed_at) FILTER (WHERE l.is_topup) AS last_topup_at,
               (array_agg(l.reference ORDER BY l.confirmed_at DESC) FILTER (WHERE l.is_topup))[1] AS last_topup_ref,
               (array_agg(l.session ORDER BY l.confirmed_at DESC) FILTER (WHERE l.is_topup))[1] AS session
          FROM legacy l GROUP BY l.student_id
        HAVING count(*) FILTER (WHERE l.is_topup) > 0),
    credited AS (   -- a credit already on the wallet (posted here, or by hand under the same source): the row reads POSTED
        SELECT e.student_id, e.id AS entry FROM finance.wallet_entry e WHERE e.kind = 'CREDIT' AND e.source_code = 'LEGACY_WALLET'),
    up AS (
        INSERT INTO finance.legacy_wallet AS w (student_id, topups, topup_count, used, used_count, first_topup_at, last_topup_at, last_topup_ref, session, available, status, reason_code, reason, computed_at, wallet_entry_id)
        SELECT p.student_id, p.topups, p.topup_count, p.used, p.used_count, p.first_topup_at, p.last_topup_at, p.last_topup_ref, p.session,
               CASE WHEN c.entry IS NOT NULL THEN greatest(p.topups - p.used, 0) WHEN p.used > p.topups THEN 0 ELSE p.topups - p.used END,
               CASE WHEN c.entry IS NOT NULL THEN 'POSTED' WHEN p.used > p.topups THEN 'REQUIRES_REVIEW' WHEN p.topups - p.used <= 0 THEN 'NO_BALANCE' ELSE 'COMPUTED' END,
               CASE WHEN c.entry IS NOT NULL THEN NULL WHEN p.used > p.topups THEN 'USED_EXCEEDS_TOPUPS' END,
               CASE WHEN c.entry IS NOT NULL THEN NULL WHEN p.used > p.topups THEN format('%s paid from the old wallet against %s topped up on file: the old wallet held money the export does not show', p.used, p.topups) END,
               now(), c.entry
          FROM per p LEFT JOIN credited c ON c.student_id = p.student_id
        ON CONFLICT (student_id) DO UPDATE SET
               topups = EXCLUDED.topups, topup_count = EXCLUDED.topup_count, used = EXCLUDED.used, used_count = EXCLUDED.used_count,
               first_topup_at = EXCLUDED.first_topup_at, last_topup_at = EXCLUDED.last_topup_at, last_topup_ref = EXCLUDED.last_topup_ref, session = EXCLUDED.session,
               computed_at = now(),
               -- the old portal's own statement governs the balance where the Bursary holds it
               available = CASE WHEN w.status IN ('POSTED', 'REJECTED', 'FROZEN') THEN w.available
                                WHEN w.stated_balance IS NOT NULL THEN greatest(w.stated_balance, 0)
                                ELSE EXCLUDED.available END,
               wallet_entry_id = coalesce(w.wallet_entry_id, EXCLUDED.wallet_entry_id),
               status = CASE WHEN w.status IN ('POSTED', 'REJECTED', 'FROZEN') THEN w.status
                             WHEN EXCLUDED.wallet_entry_id IS NOT NULL THEN 'POSTED'
                             WHEN w.stated_balance IS NOT NULL THEN CASE WHEN w.stated_balance > 0 THEN CASE WHEN w.status = 'VERIFIED' AND (w.topups, w.used) = (EXCLUDED.topups, EXCLUDED.used) THEN 'VERIFIED' ELSE 'COMPUTED' END ELSE 'NO_BALANCE' END
                             WHEN w.status = 'VERIFIED' AND (w.topups, w.used) = (EXCLUDED.topups, EXCLUDED.used) THEN 'VERIFIED'
                             ELSE EXCLUDED.status END,
               reason_code = CASE WHEN w.status = 'POSTED' AND (w.topups, w.used) <> (EXCLUDED.topups, EXCLUDED.used) THEN 'CHANGED_AFTER_POSTING'
                                  WHEN w.status IN ('POSTED', 'REJECTED', 'FROZEN') THEN w.reason_code
                                  WHEN w.status = 'VERIFIED' AND (w.topups, w.used) <> (EXCLUDED.topups, EXCLUDED.used) THEN 'CHANGED_AFTER_VERIFICATION'
                                  WHEN w.stated_balance IS NOT NULL AND w.stated_balance <> EXCLUDED.available THEN 'STATEMENT_DIFFERS'
                                  ELSE EXCLUDED.reason_code END,
               reason = CASE WHEN w.status = 'POSTED' AND (w.topups, w.used) <> (EXCLUDED.topups, EXCLUDED.used)
                                  THEN format('the imported payments changed after the posting (top-ups %s, used %s now)', EXCLUDED.topups, EXCLUDED.used)
                             WHEN w.status IN ('POSTED', 'REJECTED', 'FROZEN') THEN w.reason
                             WHEN w.status = 'VERIFIED' AND (w.topups, w.used) <> (EXCLUDED.topups, EXCLUDED.used) THEN 'the imported payments changed after the verification; verify again'
                             WHEN w.stated_balance IS NOT NULL AND w.stated_balance <> EXCLUDED.available
                                  THEN format('the old portal''s statement says %s; the imported payments leave %s', w.stated_balance, EXCLUDED.available)
                             ELSE EXCLUDED.reason END
        RETURNING w.status, w.available)
    SELECT count(*), count(*) FILTER (WHERE u.status IN ('COMPUTED', 'VERIFIED')), count(*) FILTER (WHERE u.status = 'REQUIRES_REVIEW'),
           count(*) FILTER (WHERE u.status = 'NO_BALANCE'), count(*) FILTER (WHERE u.status = 'POSTED'), coalesce(sum(u.available) FILTER (WHERE u.status IN ('COMPUTED', 'VERIFIED')), 0)
      INTO n_students, n_with, n_review, n_none, n_posted, v_avail
      FROM up u;
    RETURN QUERY SELECT n_students, n_with, n_review, n_none, n_posted, v_avail;
END $fn$;
COMMENT ON FUNCTION finance.legacy_wallet_compute(uuid) IS
  'V583: every student''s old-portal e-wallet from the imported payments — top-ups (purpose E-WALLET TOP-UP) less the fees paid from the wallet (method E-Wallet) — classed COMPUTED, REQUIRES_REVIEW (used exceeds top-ups), NO_BALANCE or POSTED (a credit stands); a posted, rejected or frozen row keeps its state and is never credited twice; the old portal''s statement governs where entered';

-- ── 4 · the old portal's statement for one student, entered by the Bursary ──────────────────────────────────────────────

CREATE FUNCTION finance.legacy_wallet_state(p_student uuid, p_topups numeric, p_used numeric, p_refunds numeric, p_reversed numeric, p_balance numeric,
                                            p_source text, p_note text)
RETURNS finance.legacy_wallet LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        w finance.legacy_wallet;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_WALLET_ACTOR: the old portal''s statement is entered by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_wallet_office_verifies(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_WALLET_OFFICE: the old portal''s statement is entered by the Students Account Officer or the Bursar' USING ERRCODE = '42501';
    END IF;
    IF p_balance IS NULL OR p_balance < 0 THEN RAISE EXCEPTION 'LEGACY_WALLET_BALANCE: the balance the old portal states is zero or more' USING ERRCODE = '23514'; END IF;
    IF length(btrim(coalesce(p_source, ''))) < 3 THEN
        RAISE EXCEPTION 'LEGACY_WALLET_SOURCE: name what the statement is read from (the old portal''s wallet page, its export, a printout)' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO w FROM finance.legacy_wallet WHERE student_id = p_student FOR UPDATE;
    IF NOT FOUND THEN
        -- a student with no top-up on file: the old portal's statement is the only ground, and it is reviewed before it is posted
        INSERT INTO finance.legacy_wallet (student_id, status, reason_code, reason) VALUES (p_student, 'REQUIRES_REVIEW', 'NO_TOPUP_ON_FILE', 'no top-up on file; the balance rests on the old portal''s statement alone')
        ON CONFLICT (student_id) DO NOTHING;
        SELECT * INTO w FROM finance.legacy_wallet WHERE student_id = p_student FOR UPDATE;
    END IF;
    IF w.status IN ('POSTED', 'REJECTED', 'FROZEN') THEN
        RAISE EXCEPTION 'LEGACY_WALLET_STATE: this wallet is %; its statement is not changed', lower(w.status) USING ERRCODE = '23514';
    END IF;
    UPDATE finance.legacy_wallet
       SET stated_topups = p_topups, stated_used = p_used, stated_refunds = p_refunds, stated_reversed = p_reversed, stated_balance = p_balance,
           stated_source = btrim(p_source), stated_note = nullif(btrim(coalesce(p_note, '')), ''), stated_by = who, stated_at = now(),
           available = p_balance,
           status = CASE WHEN p_balance > 0 THEN 'COMPUTED' ELSE 'NO_BALANCE' END,
           verified_by = NULL, verified_office = NULL, verified_at = NULL, verify_note = NULL,
           reason_code = CASE WHEN w.topup_count = 0 THEN 'NO_TOPUP_ON_FILE' WHEN p_balance <> greatest(w.topups - w.used, 0) THEN 'STATEMENT_DIFFERS' END,
           reason = CASE WHEN w.topup_count = 0 THEN 'no top-up on file; the balance rests on the old portal''s statement'
                         WHEN p_balance <> greatest(w.topups - w.used, 0) THEN format('the old portal''s statement says %s; the imported payments leave %s', p_balance, greatest(w.topups - w.used, 0)) END
     WHERE student_id = p_student
    RETURNING * INTO w;
    RETURN w;
END $fn$;

-- ── 5 · verify, post, decide ────────────────────────────────────────────────────────────────────────────────────────────

CREATE FUNCTION finance.legacy_wallet_verify(p_ids uuid[], p_note text)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), ''); n int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_WALLET_ACTOR: a balance is verified by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_wallet_office_verifies(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_WALLET_OFFICE: a balance is verified by the Students Account Officer or the Bursar' USING ERRCODE = '42501';
    END IF;
    UPDATE finance.legacy_wallet w
       SET status = 'VERIFIED', verified_by = who, verified_office = office, verified_at = now(), verify_note = nullif(btrim(coalesce(p_note, '')), '')
     WHERE w.id = ANY (p_ids) AND w.status = 'COMPUTED' AND w.available > 0;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION finance.legacy_wallet_verify(uuid[], text) IS 'V583: computed balances marked checked by the Students Account Officer or the Bursar; a row under review, with nothing to post or already decided is left as it is';

CREATE FUNCTION finance.legacy_wallet_post(p_ids uuid[], p_note text)
RETURNS TABLE (batch_ref text, posted integer, amount numeric, skipped integer, skipped_why jsonb)
LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_ref text; w record; v_entry uuid; n int := 0; v_sum numeric := 0; nk int := 0; why jsonb := '[]'::jsonb; v_reason text; v_name text; v_first text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_WALLET_ACTOR: balances are posted by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_wallet_office_posts(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_WALLET_OFFICE: verified balances are posted to the wallet by the Bursar' USING ERRCODE = '42501';
    END IF;
    v_ref := 'LEGACY-WALLET/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('finance.legacy_wallet_batch_seq')::text, 6, '0');
    INSERT INTO finance.legacy_wallet_batch (ref, posted_by, office, note) VALUES (v_ref, who, office, nullif(btrim(coalesce(p_note, '')), ''));
    FOR w IN
        SELECT lw.*, s.surname, s.other_names, s.matric_no, s.admission_no, s.status AS student_status, s.duplicate_of
          FROM finance.legacy_wallet lw JOIN people.student s ON s.id = lw.student_id
         WHERE lw.id = ANY (p_ids) ORDER BY s.surname, s.other_names
         FOR UPDATE OF lw
    LOOP
        v_reason := CASE WHEN w.status <> 'VERIFIED' THEN 'not verified (' || lower(replace(w.status, '_', ' ')) || ')'
                         WHEN w.verified_by = who THEN 'verified by you: another Bursar officer posts it'
                         WHEN w.available <= 0 THEN 'nothing to post'
                         WHEN w.duplicate_of IS NOT NULL THEN 'a duplicate record, merged into another'
                         WHEN w.student_status = 'DECEASED' THEN 'the student is recorded as deceased'
                         WHEN EXISTS (SELECT 1 FROM finance.wallet_entry e WHERE e.student_id = w.student_id AND e.kind = 'CREDIT' AND e.source_code = 'LEGACY_WALLET') THEN 'a legacy-wallet credit already stands'
                         END;
        IF v_reason IS NOT NULL THEN
            nk := nk + 1;
            why := why || jsonb_build_object('id', w.id, 'student', w.surname || ', ' || w.other_names, 'number', coalesce(w.matric_no, w.admission_no), 'why', v_reason);
            CONTINUE;
        END IF;
        PERFORM pg_advisory_xact_lock(hashtext('wallet:' || w.student_id::text));
        INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note, source_code, at)
        VALUES (w.student_id, coalesce(w.session, policy.university_current_session()), 'CREDIT', w.available,
                'EWALLET-LEG-' || upper(left(replace(w.student_id::text, '-', ''), 12)),
                'Old-portal e-wallet balance: ' || CASE WHEN w.stated_balance IS NOT NULL THEN 'as the old portal states it (' || w.stated_source || ')'
                                                        ELSE 'topped up NGN ' || w.topups || ' (' || w.topup_count || '), paid from it NGN ' || w.used || ' (' || w.used_count || ')' END
                || coalesce(' · last top-up ' || to_char(w.last_topup_at, 'DD Mon YYYY') || ' ' || w.last_topup_ref, '') || ' · ' || v_ref,
                'LEGACY_WALLET', coalesce(w.last_topup_at, now()))
        RETURNING id INTO v_entry;
        UPDATE finance.legacy_wallet SET status = 'POSTED', posted_by = who, posted_office = office, posted_at = now(), batch_ref = v_ref, wallet_entry_id = v_entry,
               reason_code = NULL, reason = NULL
         WHERE id = w.id;
        n := n + 1; v_sum := v_sum + w.available;
        BEGIN
            PERFORM platform.tell_student(w.student_id, 'LEGACY_WALLET_POSTED', NULL,
                jsonb_build_object('AMOUNT', 'NGN ' || to_char(w.available, 'FM999,999,999,990.00'), 'SESSION', coalesce(w.session, policy.university_current_session())),
                'LEGACY_WALLET_POSTED:' || w.id::text);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'legacy wallet %: the student could not be told (%)', w.id, SQLERRM;
        END;
    END LOOP;
    UPDATE finance.legacy_wallet_batch SET students = n, amount = v_sum, skipped = nk WHERE ref = v_ref;
    RETURN QUERY SELECT v_ref, n, v_sum, nk, why;
END $fn$;
COMMENT ON FUNCTION finance.legacy_wallet_post(uuid[], text) IS
  'V583: verified old-portal e-wallet balances posted to the wallet by a Bursar officer other than the one who verified them — one LEGACY_WALLET credit a student, dated the last top-up, under a LEGACY-WALLET/YYYY/NNNNNN batch; a row not verified, verified by the poster, already credited, a merged duplicate or a deceased student is skipped and said';

CREATE FUNCTION finance.legacy_wallet_decide(p_id uuid, p_action text, p_reason text)
RETURNS finance.legacy_wallet LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        w finance.legacy_wallet;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_WALLET_ACTOR: a wallet is decided by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_wallet_office_posts(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_WALLET_OFFICE: a wallet is rejected, frozen or reopened by the Bursar' USING ERRCODE = '42501';
    END IF;
    IF p_action IS NULL OR p_action NOT IN ('REJECT', 'FREEZE', 'REOPEN') THEN
        RAISE EXCEPTION 'LEGACY_WALLET_ACTION: reject, freeze or reopen' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN RAISE EXCEPTION 'LEGACY_WALLET_REASON: say why, in ten characters or more' USING ERRCODE = '23514'; END IF;
    SELECT * INTO w FROM finance.legacy_wallet WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_WALLET_NOT_FOUND: no such wallet' USING ERRCODE = 'P0002'; END IF;
    IF w.status = 'POSTED' THEN RAISE EXCEPTION 'LEGACY_WALLET_POSTED: this balance is on the wallet; it is not decided here' USING ERRCODE = '23514'; END IF;
    IF p_action = 'REOPEN' THEN
        IF w.status NOT IN ('REJECTED', 'FROZEN') THEN RAISE EXCEPTION 'LEGACY_WALLET_STATE: only a rejected or frozen wallet is reopened' USING ERRCODE = '23514'; END IF;
        UPDATE finance.legacy_wallet SET status = 'COMPUTED', decided_by = who, decided_office = office, decided_at = now(), decision_note = btrim(p_reason),
               verified_by = NULL, verified_office = NULL, verified_at = NULL WHERE id = p_id RETURNING * INTO w;
        PERFORM finance.legacy_wallet_compute(w.student_id);
        SELECT * INTO w FROM finance.legacy_wallet WHERE id = p_id;
        RETURN w;
    END IF;
    UPDATE finance.legacy_wallet SET status = CASE p_action WHEN 'REJECT' THEN 'REJECTED' ELSE 'FROZEN' END, decided_by = who, decided_office = office, decided_at = now(),
           decision_note = btrim(p_reason), verified_by = NULL, verified_office = NULL, verified_at = NULL
     WHERE id = p_id RETURNING * INTO w;
    RETURN w;
END $fn$;

-- ── 6 · the desk's figures and rows ─────────────────────────────────────────────────────────────────────────────────────

CREATE FUNCTION finance.legacy_wallet_figures()
RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH w AS (SELECT * FROM finance.legacy_wallet),
    applied AS (SELECT coalesce(sum(e.amount) FILTER (WHERE e.kind = 'APPLIED'), 0) AS applied, coalesce(sum(e.amount) FILTER (WHERE e.kind = 'REFUND'), 0) AS refunded,
                       coalesce(sum(e.amount) FILTER (WHERE e.kind = 'CREDIT'), 0) AS credited
                  FROM finance.wallet_entry e WHERE e.source_code = 'LEGACY_WALLET'),
    orphan AS (   -- paid from the old wallet with no top-up on file
        SELECT count(DISTINCT pr.student_id) AS students, coalesce(sum(pr.amount), 0) AS amount
          FROM finance.payment_reference pr
         WHERE pr.channel = 'Legacy' AND pr.confirmed_at IS NOT NULL AND finance.legacy_wallet_method(pr.note) = 'E-Wallet' AND NOT finance.legacy_wallet_is_topup(pr.purpose)
           AND NOT EXISTS (SELECT 1 FROM finance.legacy_wallet lw WHERE lw.student_id = pr.student_id AND lw.topup_count > 0))
    SELECT jsonb_build_object(
        'students', (SELECT count(*) FROM w),
        'topups', (SELECT coalesce(sum(topups), 0) FROM w), 'topupCount', (SELECT coalesce(sum(topup_count), 0) FROM w),
        'used', (SELECT coalesce(sum(used), 0) FROM w),
        'computed', (SELECT count(*) FROM w WHERE status = 'COMPUTED'), 'computedAmount', (SELECT coalesce(sum(available), 0) FROM w WHERE status = 'COMPUTED'),
        'verified', (SELECT count(*) FROM w WHERE status = 'VERIFIED'), 'verifiedAmount', (SELECT coalesce(sum(available), 0) FROM w WHERE status = 'VERIFIED'),
        'posted', (SELECT count(*) FROM w WHERE status = 'POSTED'), 'postedAmount', (SELECT credited FROM applied),
        'applied', (SELECT applied FROM applied), 'refunded', (SELECT refunded FROM applied),
        'remaining', (SELECT credited - applied - refunded FROM applied),
        'review', (SELECT count(*) FROM w WHERE status = 'REQUIRES_REVIEW'), 'reviewUsed', (SELECT coalesce(sum(used - topups), 0) FROM w WHERE status = 'REQUIRES_REVIEW'),
        'noBalance', (SELECT count(*) FROM w WHERE status = 'NO_BALANCE'),
        'rejected', (SELECT count(*) FROM w WHERE status = 'REJECTED'), 'frozen', (SELECT count(*) FROM w WHERE status = 'FROZEN'),
        'stated', (SELECT count(*) FROM w WHERE stated_balance IS NOT NULL), 'differs', (SELECT count(*) FROM w WHERE reason_code = 'STATEMENT_DIFFERS'),
        'changed', (SELECT count(*) FROM w WHERE reason_code IN ('CHANGED_AFTER_POSTING', 'CHANGED_AFTER_VERIFICATION')),
        'orphanStudents', (SELECT students FROM orphan), 'orphanAmount', (SELECT amount FROM orphan),
        'lastComputed', (SELECT max(computed_at) FROM w),
        'batches', (SELECT coalesce(json_agg(b ORDER BY b.posted_at DESC), '[]'::json)::jsonb FROM (
                        SELECT b.ref, b.posted_at, b.students, b.amount, b.skipped, helpdesk.person_name(b.posted_by) AS posted_by, b.office FROM finance.legacy_wallet_batch b ORDER BY b.posted_at DESC LIMIT 20) b))
$$;

CREATE FUNCTION finance.legacy_wallet_rows(p_status text, p_q text, p_fac text, p_dept text, p_limit integer DEFAULT 500)
RETURNS TABLE (id uuid, student_id uuid, student text, matric_no text, jamb_reg_no text, student_status text, programme text, dept_code text, department text, faculty_code text, faculty text,
               topups numeric, topup_count integer, used numeric, used_count integer, first_topup_at timestamptz, last_topup_at timestamptz, last_topup_ref text, session text,
               stated_topups numeric, stated_used numeric, stated_refunds numeric, stated_reversed numeric, stated_balance numeric, stated_source text, stated_note text, stated_by text, stated_at timestamptz,
               available numeric, status text, reason_code text, reason text, computed_at timestamptz,
               verified_by text, verified_office text, verified_at timestamptz, verify_note text, posted_by text, posted_office text, posted_at timestamptz, batch_ref text,
               decided_by text, decided_at timestamptz, decision_note text, wallet_reference text, applied numeric, refunded numeric, remaining numeric)
LANGUAGE sql STABLE AS $$
    SELECT w.id, w.student_id, s.surname || ', ' || s.other_names, s.matric_no, s.jamb_reg_no, s.status, p.name, p.dept_code, d.name, p.faculty_code, f.name,
           w.topups, w.topup_count, w.used, w.used_count, w.first_topup_at, w.last_topup_at, w.last_topup_ref, w.session,
           w.stated_topups, w.stated_used, w.stated_refunds, w.stated_reversed, w.stated_balance, w.stated_source, w.stated_note, helpdesk.person_name(w.stated_by), w.stated_at,
           w.available, w.status, w.reason_code, w.reason, w.computed_at,
           helpdesk.person_name(w.verified_by), w.verified_office, w.verified_at, w.verify_note, helpdesk.person_name(w.posted_by), w.posted_office, w.posted_at, w.batch_ref,
           helpdesk.person_name(w.decided_by), w.decided_at, w.decision_note, e.reference,
           coalesce(x.applied, 0), coalesce(x.refunded, 0), CASE WHEN e.id IS NULL THEN NULL ELSE e.amount - coalesce(x.applied, 0) - coalesce(x.refunded, 0) END
      FROM finance.legacy_wallet w
      JOIN people.student s ON s.id = w.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN finance.wallet_entry e ON e.id = w.wallet_entry_id
      LEFT JOIN LATERAL (SELECT sum(a.amount) FILTER (WHERE a.kind = 'APPLIED') AS applied, sum(a.amount) FILTER (WHERE a.kind = 'REFUND') AS refunded
                           FROM finance.wallet_entry a WHERE a.student_id = w.student_id AND a.source_code = 'LEGACY_WALLET' AND a.kind IN ('APPLIED', 'REFUND')) x ON true
     WHERE (p_status IS NULL OR w.status = p_status)
       AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept)
       AND (p_q IS NULL OR s.matric_no ILIKE '%' || p_q || '%' OR s.jamb_reg_no ILIKE '%' || p_q || '%' OR (s.surname || ' ' || s.other_names) ILIKE '%' || p_q || '%'
            OR w.batch_ref ILIKE '%' || p_q || '%' OR w.last_topup_ref ILIKE '%' || p_q || '%')
     ORDER BY CASE w.status WHEN 'VERIFIED' THEN 0 WHEN 'COMPUTED' THEN 1 WHEN 'REQUIRES_REVIEW' THEN 2 WHEN 'POSTED' THEN 3 ELSE 4 END, w.available DESC, s.surname, s.other_names
     LIMIT greatest(1, least(coalesce(p_limit, 500), 5000))
$$;

-- the student's own view: what the old wallet held, what is posted, applied and left
CREATE FUNCTION finance.legacy_wallet_of(p_student uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN w.id IS NULL THEN NULL ELSE jsonb_build_object(
        'status', w.status, 'topups', w.topups, 'used', w.used, 'available', w.available, 'statedBalance', w.stated_balance,
        'postedAt', w.posted_at, 'batchRef', w.batch_ref, 'reference', e.reference,
        'posted', coalesce(e.amount, 0),
        'applied', coalesce((SELECT sum(a.amount) FROM finance.wallet_entry a WHERE a.student_id = p_student AND a.source_code = 'LEGACY_WALLET' AND a.kind = 'APPLIED'), 0),
        'refunded', coalesce((SELECT sum(a.amount) FROM finance.wallet_entry a WHERE a.student_id = p_student AND a.source_code = 'LEGACY_WALLET' AND a.kind = 'REFUND'), 0)) END
      FROM (SELECT 1) one
      LEFT JOIN finance.legacy_wallet w ON w.student_id = p_student
      LEFT JOIN finance.wallet_entry e ON e.id = w.wallet_entry_id
$$;

-- ── 7 · the student told ────────────────────────────────────────────────────────────────────────────────────────────────

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('LEGACY_WALLET_POSTED', 'Old-portal e-wallet balance on the wallet',
 'To a student whose unused old-portal e-wallet balance the Bursary has verified and posted to their wallet',
 'Your old e-wallet balance of [AMOUNT] is on your wallet',
 E'Dear [FIRST_NAME],\n\nThe [AMOUNT] you still held in the old portal''s e-wallet is now on your wallet on the portal. You can apply it to your [SESSION] school fees from the wallet page, and pay any shortfall through the gateway.\n\nSign in: [PORTAL_URL]\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: your old e-wallet balance of [AMOUNT] is on your wallet. Apply it to your [SESSION] fees on the portal.',
 'Your old e-wallet balance is on your wallet',
 'The [AMOUNT] you still held in the old portal''s e-wallet is on your wallet: apply it to your [SESSION] school fees from the wallet page.',
 ARRAY['FIRST_NAME','AMOUNT','SESSION','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

GRANT SELECT ON finance.legacy_wallet, finance.legacy_wallet_batch TO app_auditor, app_reporting;

COMMIT;
