-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V533 — Refunds paid only into a full, checked account
--
--   1 · The banks. finance.bank lists the Nigerian banks a refund is paid into, each with the code the Central Bank gave it.
--       For a commercial bank whose code is certain, the account number's tenth digit is checked against the bank (the CBN's
--       NUBAN check digit: bank code and serial, weights 3-7-3, ten less the sum's last digit), so a mistyped number, or one
--       given with the wrong bank, is refused as it is given (REFUND_ACCOUNT_CHECK_DIGIT). A bank whose numbers do not follow
--       the check (a payment service bank whose account number is the phone number, a microfinance bank, a newer bank whose
--       code is not yet confirmed) is listed but not checked; the Bursary switches the check on or off, renames or adds a bank
--       on Refunds & Credits. A bank not on the list may still be typed; its number is then checked for ten digits only.
--   2 · One account rule for every refund. V528 kept the full account for a refund of overpaid fees given by the student; a
--       refund raised at the desk kept only the last four digits, a JUPEB refund its claim's. Now the desk records the full
--       account too (finance.desk_refund_account, when raising a refund or later), a JUPEB refund takes its claim's account,
--       and finance.refund_account holds the account every refund is paid into, with where it came from (STUDENT, DESK, JUPEB).
--       The database refuses PAID for a refund with no account there (REFUND_NO_ACCOUNT). The desk may record or change the
--       account while the refund awaits approval; on an approved refund the account it records goes back for approval (by
--       another officer than the one who recorded it, REFUND_ACCOUNT_SAME_OFFICER) unless it only completes the account the
--       approver saw (the same last four digits and bank). The student's rule (V528) stands: while it awaits approval, or once
--       after approval when none was given.
--   3 · The refunds desk is told when the name on the account shares no word with the student's (or the JUPEB candidate's,
--       or the payer's) name — a warning, never a refusal.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V533: refunds paid only into a full, checked account', true);

-- ── 1 · the banks ─────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.bank (
    code        text PRIMARY KEY CHECK (code ~ '^[0-9A-Z]{3,8}$'),
    name        text NOT NULL UNIQUE CHECK (btrim(name) <> ''),
    aliases     text[] NOT NULL DEFAULT '{}',
    kind        text NOT NULL CHECK (kind IN ('COMMERCIAL', 'NON_INTEREST', 'MERCHANT', 'MICROFINANCE', 'PAYMENT_SERVICE')),
    nuban_check boolean NOT NULL DEFAULT false,
    active      boolean NOT NULL DEFAULT true,
    -- the NUBAN check digit is the banks' (a three-digit code); a microfinance or payment service bank's numbers do not follow it
    CONSTRAINT ck_bank_checked_code CHECK (NOT nuban_check OR (code ~ '^[0-9]{3}$' AND kind IN ('COMMERCIAL', 'NON_INTEREST', 'MERCHANT')))
);
COMMENT ON TABLE finance.bank IS
  'V533: the banks a refund is paid into — the code the Central Bank gave the bank, its name and the other names people write it by (lower case), its kind, and whether its account numbers are checked by the NUBAN check digit (a commercial, non-interest or merchant bank with a three-digit code only). Kept by the Bursary.';
SELECT audit.attach('finance.bank');

INSERT INTO finance.bank (code, name, aliases, kind, nuban_check) VALUES
    ('044', 'Access Bank', ARRAY['access', 'access bank plc'], 'COMMERCIAL', true),
    ('063', 'Access Bank (Diamond)', ARRAY['diamond', 'diamond bank'], 'COMMERCIAL', true),
    ('023', 'Citibank Nigeria', ARRAY['citibank', 'citi'], 'COMMERCIAL', true),
    ('050', 'Ecobank Nigeria', ARRAY['ecobank', 'eco bank'], 'COMMERCIAL', true),
    ('070', 'Fidelity Bank', ARRAY['fidelity'], 'COMMERCIAL', true),
    ('011', 'First Bank of Nigeria', ARRAY['first bank', 'firstbank', 'fbn', 'first bank plc'], 'COMMERCIAL', true),
    ('214', 'First City Monument Bank', ARRAY['fcmb'], 'COMMERCIAL', true),
    ('058', 'Guaranty Trust Bank', ARRAY['gtbank', 'gtb', 'gt bank', 'guaranty trust', 'gtco'], 'COMMERCIAL', true),
    ('082', 'Keystone Bank', ARRAY['keystone'], 'COMMERCIAL', true),
    ('076', 'Polaris Bank', ARRAY['polaris', 'skye bank'], 'COMMERCIAL', true),
    ('221', 'Stanbic IBTC Bank', ARRAY['stanbic', 'stanbic ibtc', 'ibtc'], 'COMMERCIAL', true),
    ('068', 'Standard Chartered Bank', ARRAY['standard chartered'], 'COMMERCIAL', true),
    ('232', 'Sterling Bank', ARRAY['sterling'], 'COMMERCIAL', true),
    ('032', 'Union Bank of Nigeria', ARRAY['union bank', 'union'], 'COMMERCIAL', true),
    ('033', 'United Bank for Africa', ARRAY['uba'], 'COMMERCIAL', true),
    ('215', 'Unity Bank', ARRAY['unity'], 'COMMERCIAL', true),
    ('035', 'Wema Bank', ARRAY['wema', 'alat', 'alat by wema'], 'COMMERCIAL', true),
    ('057', 'Zenith Bank', ARRAY['zenith'], 'COMMERCIAL', true),
    -- newer commercial banks: listed, their numbers not yet checked
    ('103', 'Globus Bank', ARRAY['globus'], 'COMMERCIAL', false),
    ('101', 'Providus Bank', ARRAY['providus'], 'COMMERCIAL', false),
    ('100', 'SunTrust Bank', ARRAY['suntrust'], 'COMMERCIAL', false),
    ('102', 'Titan Trust Bank', ARRAY['titan', 'titan trust'], 'COMMERCIAL', false),
    ('105', 'PremiumTrust Bank', ARRAY['premium trust', 'premiumtrust'], 'COMMERCIAL', false),
    ('104', 'Parallex Bank', ARRAY['parallex'], 'COMMERCIAL', false),
    ('107', 'Optimus Bank', ARRAY['optimus'], 'COMMERCIAL', false),
    ('106', 'Signature Bank', ARRAY['signature'], 'COMMERCIAL', false),
    ('301', 'Jaiz Bank', ARRAY['jaiz'], 'NON_INTEREST', false),
    ('302', 'TAJBank', ARRAY['taj', 'taj bank'], 'NON_INTEREST', false),
    ('303', 'Lotus Bank', ARRAY['lotus'], 'NON_INTEREST', false),
    -- payment service and microfinance banks: an account number is often the phone number, never checked
    ('999992', 'OPay', ARRAY['opay', 'paycom', 'opay digital services'], 'PAYMENT_SERVICE', false),
    ('999991', 'PalmPay', ARRAY['palmpay', 'palm pay'], 'PAYMENT_SERVICE', false),
    ('50515', 'Moniepoint Microfinance Bank', ARRAY['moniepoint', 'moniepoint mfb'], 'MICROFINANCE', false),
    ('50211', 'Kuda Microfinance Bank', ARRAY['kuda', 'kuda bank', 'kuda mfb'], 'MICROFINANCE', false),
    ('51318', 'FairMoney Microfinance Bank', ARRAY['fairmoney', 'fair money'], 'MICROFINANCE', false),
    ('566', 'VFD Microfinance Bank', ARRAY['vfd', 'vbank', 'v bank'], 'MICROFINANCE', false),
    ('565', 'Carbon', ARRAY['carbon', 'one finance'], 'MICROFINANCE', false);

/* the NUBAN check digit: the three-digit bank code and the nine-digit serial, weighted 3, 7, 3 in turn; ten less the last digit
   of the sum (0 for 10). The Central Bank's own example: bank 011, serial 000001457 → 0000014579 */
CREATE FUNCTION finance.nuban_check_digit(p_code text, p_serial text)
RETURNS int LANGUAGE sql IMMUTABLE AS $fn$
    SELECT (10 - (sum(substr(p_code || p_serial, i, 1)::int * (ARRAY[3,7,3,3,7,3,3,7,3,3,7,3])[i]) % 10)::int) % 10
      FROM generate_series(1, 12) i
$fn$;
COMMENT ON FUNCTION finance.nuban_check_digit(text, text) IS
  'V533: the CBN NUBAN check digit of a nine-digit serial at a bank with a three-digit code (011 + 000001457 → 9).';

/* a bank as it was given: its code, its name or one of its other names (any case) */
CREATE FUNCTION finance.bank_of(p_bank text)
RETURNS finance.bank LANGUAGE sql STABLE AS $fn$
    SELECT b.* FROM finance.bank b
     WHERE b.code = upper(btrim(coalesce(p_bank, ''))) OR lower(b.name) = lower(btrim(coalesce(p_bank, '')))
        OR lower(btrim(coalesce(p_bank, ''))) = ANY (b.aliases)
     ORDER BY (b.code = upper(btrim(coalesce(p_bank, '')))) DESC, b.active DESC
     LIMIT 1
$fn$;

/* what is wrong with an account number for a bank, or NULL: ten digits (spaces and dashes ignored), and the check digit where
   the bank is checked */
CREATE FUNCTION finance.account_number_problem(p_bank text, p_number text)
RETURNS text LANGUAGE plpgsql STABLE AS $fn$
DECLARE d text := regexp_replace(coalesce(p_number, ''), '[\s-]', '', 'g'); b finance.bank := finance.bank_of(p_bank);
BEGIN
    IF d !~ '^[0-9]{10}$' THEN RETURN 'REFUND_ACCOUNT_NUMBER'; END IF;
    IF b.code IS NOT NULL AND b.nuban_check AND finance.nuban_check_digit(b.code, left(d, 9)) <> right(d, 1)::int THEN
        RETURN 'REFUND_ACCOUNT_CHECK_DIGIT';
    END IF;
    RETURN NULL;
END $fn$;
COMMENT ON FUNCTION finance.account_number_problem(text, text) IS
  'V533: REFUND_ACCOUNT_NUMBER (not ten digits) or REFUND_ACCOUNT_CHECK_DIGIT (the tenth digit does not match the bank) for an account number at a bank (its code or name), or NULL.';

/* whether two names share a word of three letters or more — the account name against the student's: a warning only */
CREATE FUNCTION finance.names_share(p_a text, p_b text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $fn$
    SELECT EXISTS (SELECT 1 FROM regexp_split_to_table(lower(coalesce(p_a, '')), '[^a-z]+') x
                    WHERE length(x) >= 3 AND x = ANY (regexp_split_to_array(lower(coalesce(p_b, '')), '[^a-z]+')))
$fn$;

-- ── 2 · one account rule for every refund ────────────────────────────────────────────────────────────────────────────────
ALTER TABLE finance.refund_account
    ADD COLUMN bank_code text NULL REFERENCES finance.bank(code) ON UPDATE CASCADE,
    ADD COLUMN source text NOT NULL DEFAULT 'STUDENT' CHECK (source IN ('STUDENT', 'DESK', 'JUPEB'));
UPDATE finance.refund_account a SET bank_code = (finance.bank_of(a.bank_name)).code WHERE a.bank_code IS NULL;
COMMENT ON TABLE finance.refund_account IS
  'V528, V533: the account a refund is paid into — the bank (and its code where it is on finance.bank), the account name and the ten-digit number — and where it came from: the student (a refund of overpaid fees), the desk, or a JUPEB candidate''s claim. A refund is paid only with one; the refund keeps its own snapshot (bank, name, last four digits).';

/* the one place an account is recorded for a refund. The student (V528's rule): while the refund awaits approval, or once after
   approval when none was given. The desk: while it awaits approval; on an approved refund the account goes back for approval
   unless it only completes the one the approver saw (the same last four digits and bank). Never once paid or rejected. Returns
   the refund's state after. */
CREATE FUNCTION finance.record_refund_account(p_refund uuid, p_bank text, p_name text, p_number text, p_source text, p_by uuid)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r finance.refund; v_number text := regexp_replace(coalesce(p_number, ''), '[\s-]', '', 'g');
        v_bank text := btrim(coalesce(p_bank, '')); v_name text := btrim(coalesce(p_name, '')); b finance.bank; v_full boolean;
        v_problem text; v_state text; v_completes boolean;
BEGIN
    SELECT * INTO r FROM finance.refund WHERE id = p_refund FOR UPDATE;
    IF r.id IS NULL THEN RAISE EXCEPTION 'REFUND_NOT_FOUND: no such refund' USING ERRCODE = '23514'; END IF;
    v_full := EXISTS (SELECT 1 FROM finance.refund_account a WHERE a.refund_id = r.id);
    IF r.state IN ('PAID', 'REJECTED') OR (p_source = 'STUDENT' AND r.state = 'APPROVED' AND (v_full OR r.account_last4 IS NOT NULL)) THEN
        RAISE EXCEPTION 'REFUND_ACCOUNT_CLOSED: refund % is %; the account it is paid into is no longer changed here', r.reference, lower(r.state)
            USING ERRCODE = '23514', HINT = 'Contact the Bursary.';
    END IF;
    IF v_bank = '' OR v_name = '' THEN
        RAISE EXCEPTION 'REFUND_ACCOUNT_DETAILS: give the bank and the name on the account' USING ERRCODE = '23514';
    END IF;
    v_problem := finance.account_number_problem(v_bank, v_number);
    IF v_problem = 'REFUND_ACCOUNT_NUMBER' THEN
        RAISE EXCEPTION 'REFUND_ACCOUNT_NUMBER: an account number is ten digits (your NUBAN)' USING ERRCODE = '23514';
    ELSIF v_problem = 'REFUND_ACCOUNT_CHECK_DIGIT' THEN
        RAISE EXCEPTION 'REFUND_ACCOUNT_CHECK_DIGIT: % is not an account number at %; check the number and the bank', v_number, (finance.bank_of(v_bank)).name
            USING ERRCODE = '23514', HINT = 'The last digit of an account number is worked out from the bank and the other nine; one digit wrong, or another bank, shows here.';
    END IF;
    b := finance.bank_of(v_bank);
    INSERT INTO finance.refund_account (refund_id, bank_name, account_name, account_number, given_by, bank_code, source)
    VALUES (r.id, coalesce(b.name, v_bank), v_name, v_number, p_by, b.code, p_source)
    ON CONFLICT (refund_id) DO UPDATE SET bank_name = EXCLUDED.bank_name, account_name = EXCLUDED.account_name, account_number = EXCLUDED.account_number,
                                          given_at = now(), given_by = EXCLUDED.given_by, bank_code = EXCLUDED.bank_code, source = EXCLUDED.source;
    v_state := r.state;
    -- the desk on an approved refund: back for approval, unless it only completes the account the approver saw (no full number
    -- yet, the same last four digits, the same bank)
    v_completes := NOT v_full AND coalesce(r.account_last4 = right(v_number, 4), false)
                   AND coalesce(CASE WHEN b.code IS NOT NULL THEN (finance.bank_of(r.bank_name)).code = b.code
                                     ELSE lower(btrim(r.bank_name)) = lower(v_bank) END, false);
    IF p_source = 'DESK' AND r.state = 'APPROVED' AND NOT v_completes THEN
        v_state := 'PROPOSED';
    END IF;
    UPDATE finance.refund SET bank_name = coalesce(b.name, v_bank), account_name = v_name, account_last4 = right(v_number, 4),
                              state = v_state,
                              approved_by = CASE WHEN v_state = 'PROPOSED' THEN NULL ELSE approved_by END,
                              approved_at = CASE WHEN v_state = 'PROPOSED' THEN NULL ELSE approved_at END
     WHERE id = r.id;
    RETURN v_state;
END $fn$;
COMMENT ON FUNCTION finance.record_refund_account(uuid, text, text, text, text, uuid) IS
  'V533: the account a refund is paid into, recorded by the student (V528''s rule) or the desk (back for approval on an approved refund unless it completes the account the approver saw); the number checked for ten digits and, at a checked bank, its check digit. Returns the refund''s state after.';

-- the student's own (V528), now through the one rule and the bank's check digit
CREATE OR REPLACE FUNCTION finance.give_refund_account(p_student uuid, p_reference text, p_bank text, p_name text, p_number text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_id uuid;
BEGIN
    SELECT id INTO v_id FROM finance.refund WHERE reference = upper(btrim(coalesce(p_reference, ''))) AND student_id = p_student;
    IF v_id IS NULL THEN
        RAISE EXCEPTION 'REFUND_ACCOUNT_NOT_YOURS: no refund % is raised to you', p_reference USING ERRCODE = '23514';
    END IF;
    PERFORM finance.record_refund_account(v_id, p_bank, p_name, p_number, 'STUDENT', p_student);
END $fn$;
COMMENT ON FUNCTION finance.give_refund_account(uuid, text, text, text, text) IS
  'V528, V533: a student gives the bank account a refund raised to them is paid into — while it awaits approval (and may change it then), or once after approval when none was given; never once approved with one, paid or rejected; the number checked against the bank.';

/* the desk records the account of any refund, by the person acting */
CREATE FUNCTION finance.desk_refund_account(p_refund uuid, p_bank text, p_name text, p_number text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'an account is recorded by a person' USING ERRCODE = '23514'; END IF;
    RETURN finance.record_refund_account(p_refund, p_bank, p_name, p_number, 'DESK', who);
END $fn$;
COMMENT ON FUNCTION finance.desk_refund_account(uuid, text, text, text) IS
  'V533: the refunds desk records (or changes) the account a refund is paid into; on an approved refund it goes back for approval unless it completes the account the approver saw.';

/* paid only into an account on record; an account the desk recorded is approved by another officer */
CREATE FUNCTION finance.trg_refund_account_rules()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF NEW.state = 'PAID' AND OLD.state IS DISTINCT FROM 'PAID'
       AND NOT EXISTS (SELECT 1 FROM finance.refund_account a WHERE a.refund_id = NEW.id) THEN
        RAISE EXCEPTION 'REFUND_NO_ACCOUNT: refund % has no account to be paid into', NEW.reference USING ERRCODE = '23514',
            HINT = 'Record the bank, the account name and the ten-digit number first; a refund of overpaid fees takes the student''s.';
    END IF;
    IF NEW.state = 'APPROVED' AND OLD.state = 'PROPOSED'
       AND EXISTS (SELECT 1 FROM finance.refund_account a WHERE a.refund_id = NEW.id AND a.source = 'DESK' AND a.given_by = NEW.approved_by) THEN
        RAISE EXCEPTION 'REFUND_ACCOUNT_SAME_OFFICER: you recorded the account of refund %; another officer approves it', NEW.reference USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_refund_account_rules BEFORE UPDATE OF state ON finance.refund
    FOR EACH ROW EXECUTE FUNCTION finance.trg_refund_account_rules();

/* a JUPEB refund takes its claim's account (the candidate gave it on the JUPEB portal) */
CREATE FUNCTION jupeb.trg_claim_refund_account()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    INSERT INTO finance.refund_account (refund_id, bank_name, account_name, account_number, given_at, given_by, bank_code, source)
    SELECT NEW.refund_id, c.bank_name, c.account_name, c.account_number, coalesce(c.details_at, now()), NULL, (finance.bank_of(c.bank_name)).code, 'JUPEB'
      FROM jupeb.refund_claim c WHERE c.id = NEW.claim_id AND c.account_number IS NOT NULL
    ON CONFLICT (refund_id) DO NOTHING;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_claim_refund_account AFTER INSERT ON jupeb.refund_claim_refund
    FOR EACH ROW EXECUTE FUNCTION jupeb.trg_claim_refund_account();
INSERT INTO finance.refund_account (refund_id, bank_name, account_name, account_number, given_at, given_by, bank_code, source)
SELECT x.refund_id, c.bank_name, c.account_name, c.account_number, coalesce(c.details_at, now()), NULL, (finance.bank_of(c.bank_name)).code, 'JUPEB'
  FROM jupeb.refund_claim_refund x JOIN jupeb.refund_claim c ON c.id = x.claim_id
 WHERE c.account_number IS NOT NULL
ON CONFLICT (refund_id) DO NOTHING;

COMMIT;
