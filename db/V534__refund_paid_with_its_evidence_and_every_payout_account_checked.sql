-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V534 — A refund marked paid with its evidence; every account money is paid out to checked against its bank
--
--   1 · Mark paid recorded only when it was pressed. A refund is now marked paid with the bank transfer reference and the date
--       the money left (finance.pay_refund(id, reference, paid on): a reference of 4 to 60 letters, digits and / . _ - : or
--       spaces; a date not after today and not before the refund was approved). The database refuses PAID without them
--       (REFUND_PAID_EVIDENCE). The student told that a refund of overpaid fees is paid, and a JUPEB candidate told theirs, are
--       given the reference and the date; the student's fees page and the JUPEB portal show them; the refunds desk shows them
--       and says when the same reference is on other refunds, so Internal Audit can match each refund to the bank statement.
--   2 · V533 checked the account of a refund. The other accounts money is paid out to — a withdrawn JUPEB candidate's refund
--       claim, a student's NELFUND wallet withdrawal — are checked the same way when they are given: ten digits, and at a bank
--       whose numbers are checked the NUBAN check digit (REFUND_ACCOUNT_NUMBER, REFUND_ACCOUNT_CHECK_DIGIT), the bank written as
--       it is listed. Accounts already on record are left as they are.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V534: a refund paid with its evidence; every payout account checked', true);

-- ── 1 · a refund marked paid with its evidence ────────────────────────────────────────────────────────────────────────────
ALTER TABLE finance.refund
    ADD COLUMN paid_reference text NULL,
    ADD COLUMN paid_on date NULL;
COMMENT ON COLUMN finance.refund.paid_reference IS 'V534: the bank transfer reference the refund was paid with (from the bank''s confirmation), for matching to the bank statement.';
COMMENT ON COLUMN finance.refund.paid_on IS 'V534: the date the money left the University''s account; paid_at is when it was recorded.';
CREATE INDEX ix_refund_paid_reference ON finance.refund (paid_reference) WHERE paid_reference IS NOT NULL;

DROP FUNCTION finance.pay_refund(uuid);
CREATE FUNCTION finance.pay_refund(p_id uuid, p_reference text, p_paid_on date)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE r finance.refund; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_ref text := btrim(coalesce(p_reference, ''));
        v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date;
BEGIN
    SELECT * INTO r FROM finance.refund WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state <> 'APPROVED' THEN RAISE EXCEPTION 'refund % is not approved for payment', p_id USING ERRCODE = '23514'; END IF;
    IF who IS NULL THEN RAISE EXCEPTION 'a disbursement is recorded by a person' USING ERRCODE = '23514'; END IF;
    IF length(v_ref) NOT BETWEEN 4 AND 60 OR v_ref !~ '^[A-Za-z0-9][A-Za-z0-9/._: -]*$' THEN
        RAISE EXCEPTION 'REFUND_PAID_REFERENCE: give the bank transfer reference the refund was paid with (4 to 60 letters and digits)' USING ERRCODE = '23514',
            HINT = 'It is on the bank''s confirmation of the transfer; Internal Audit matches it to the bank statement.';
    END IF;
    IF p_paid_on IS NULL OR p_paid_on > v_today THEN
        RAISE EXCEPTION 'REFUND_PAID_DATE: give the date the money left, today or before' USING ERRCODE = '23514';
    END IF;
    IF p_paid_on < (r.approved_at AT TIME ZONE 'Africa/Lagos')::date THEN
        RAISE EXCEPTION 'REFUND_PAID_DATE: refund % was approved on %; it was not paid before that', r.reference, to_char(r.approved_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY')
            USING ERRCODE = '23514';
    END IF;
    UPDATE finance.refund SET state = 'PAID', paid_at = now(), paid_by = who, paid_reference = v_ref, paid_on = p_paid_on WHERE id = p_id;
END $fn$;
COMMENT ON FUNCTION finance.pay_refund(uuid, text, date) IS
  'V043, V534: an approved refund recorded paid by a person, with the bank transfer reference and the date the money left (not after today, not before approval).';

-- V533's rules on finance.refund, with the payment's evidence
CREATE OR REPLACE FUNCTION finance.trg_refund_account_rules()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF NEW.state = 'PAID' AND OLD.state IS DISTINCT FROM 'PAID'
       AND NOT EXISTS (SELECT 1 FROM finance.refund_account a WHERE a.refund_id = NEW.id) THEN
        RAISE EXCEPTION 'REFUND_NO_ACCOUNT: refund % has no account to be paid into', NEW.reference USING ERRCODE = '23514',
            HINT = 'Record the bank, the account name and the ten-digit number first; a refund of overpaid fees takes the student''s.';
    END IF;
    IF NEW.state = 'PAID' AND OLD.state IS DISTINCT FROM 'PAID' AND (NEW.paid_reference IS NULL OR NEW.paid_on IS NULL) THEN
        RAISE EXCEPTION 'REFUND_PAID_EVIDENCE: refund % is marked paid with the bank transfer reference and the date the money left', NEW.reference
            USING ERRCODE = '23514';
    END IF;
    IF NEW.state = 'APPROVED' AND OLD.state = 'PROPOSED'
       AND EXISTS (SELECT 1 FROM finance.refund_account a WHERE a.refund_id = NEW.id AND a.source = 'DESK' AND a.given_by = NEW.approved_by) THEN
        RAISE EXCEPTION 'REFUND_ACCOUNT_SAME_OFFICER: you recorded the account of refund %; another officer approves it', NEW.reference USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;

-- the student told of a refund of overpaid fees paid, with the reference and the date (V519's notice)
UPDATE platform.notice_template SET
    email_body = E'Dear [FIRST_NAME],\n\nThe refund of the [AMOUNT] you paid beyond your [SESSION_FROM] school fees has been paid (refund [REFUND]) into the account you gave, on [PAID_ON]. The bank transfer reference is [TRANSFER_REFERENCE]; quote it to your bank if the money has not arrived.\n\n[UNIVERSITY_SHORT] Bursary',
    sms_body = '[UNIVERSITY_SHORT]: your refund of [AMOUNT] (overpaid [SESSION_FROM] school fees, refund [REFUND]) was paid on [PAID_ON], transfer reference [TRANSFER_REFERENCE].',
    portal_body = 'The refund of the [AMOUNT] you paid beyond your [SESSION_FROM] school fees has been paid (refund [REFUND]) on [PAID_ON]; bank transfer reference [TRANSFER_REFERENCE].',
    variables = ARRAY['FIRST_NAME','SESSION_FROM','AMOUNT','REFUND','PAID_ON','TRANSFER_REFERENCE','PORTAL_URL','UNIVERSITY_SHORT']
 WHERE key = 'OVERPAYMENT_REFUND_PAID';

CREATE OR REPLACE FUNCTION finance.trg_overpayment_refund_paid()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE d finance.overpayment_decision;
BEGIN
    SELECT * INTO d FROM finance.overpayment_decision
     WHERE decision = 'REFUND' AND reference = NEW.reference AND superseded_at IS NULL LIMIT 1;
    IF d.id IS NOT NULL THEN
        PERFORM platform.tell_student(d.student_id, 'OVERPAYMENT_REFUND_PAID', NULL,
            jsonb_build_object('SESSION_FROM', d.session, 'AMOUNT', 'NGN ' || to_char(NEW.amount, 'FM999,999,990.00'), 'REFUND', NEW.reference,
                               'PAID_ON', to_char(coalesce(NEW.paid_on, (NEW.paid_at AT TIME ZONE 'Africa/Lagos')::date), 'FMDD FMMonth YYYY'),
                               'TRANSFER_REFERENCE', coalesce(NEW.paid_reference, '—')),
            'overpayment-refund-paid:' || NEW.reference);
    END IF;
    RETURN NEW;
END $fn$;

-- a JUPEB candidate told of a refund paid, with the reference and the date (never the amount or the account)
CREATE OR REPLACE FUNCTION jupeb.claim_refund_paid()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_app uuid;
BEGIN
    IF NEW.state = 'PAID' AND OLD.state IS DISTINCT FROM 'PAID' THEN
        v_app := (SELECT c.application_id FROM jupeb.refund_claim_refund x JOIN jupeb.refund_claim c ON c.id = x.claim_id WHERE x.refund_id = NEW.id);
        IF v_app IS NOT NULL THEN
            PERFORM jupeb.app_event(v_app, 'REFUND_PAID', 'Refund ' || NEW.reference || ' paid by the Bursary'
                || coalesce(' on ' || to_char(NEW.paid_on, 'FMDD FMMonth YYYY'), '') || coalesce(', transfer reference ' || NEW.paid_reference, ''));
            PERFORM jupeb.tell(v_app, 'Your JUPEB refund has been paid',
                'The Bursary has paid a refund of the JUPEB fees you paid into the account you gave'
                || coalesce(' on ' || to_char(NEW.paid_on, 'FMDD FMMonth YYYY'), '') || coalesce('; the bank transfer reference is ' || NEW.paid_reference, '')
                || '. Sign in to the JUPEB portal for the details.');
        END IF;
    END IF;
    RETURN NEW;
END $$;

-- the student's own overpayment decisions (V519, V528), with when and how a refund was paid
DROP FUNCTION finance.student_overpayments(uuid);
CREATE FUNCTION finance.student_overpayments(p_student uuid)
RETURNS TABLE (session text, amount numeric, decision text, to_session text, reference text, refund_state text, decided_at timestamptz,
               bank_name text, account_name text, account_last4 text, account_given_at timestamptz, account_open boolean,
               paid_on date, paid_reference text)
LANGUAGE sql STABLE AS $fn$
    SELECT d.session, d.amount, d.decision, d.to_session, d.reference, rf.state, d.decided_at,
           rf.bank_name, rf.account_name, rf.account_last4, ra.given_at,
           -- whether the student may give (or change) the account now
           d.decision = 'REFUND' AND (rf.state = 'PROPOSED' OR (rf.state = 'APPROVED' AND ra.refund_id IS NULL AND rf.account_last4 IS NULL)),
           rf.paid_on, rf.paid_reference
      FROM finance.overpayment_decision d
      LEFT JOIN finance.refund rf ON d.decision = 'REFUND' AND rf.reference = d.reference
      LEFT JOIN finance.refund_account ra ON ra.refund_id = rf.id
     WHERE d.student_id = p_student AND d.superseded_at IS NULL
     ORDER BY d.decided_at DESC
$fn$;
COMMENT ON FUNCTION finance.student_overpayments(uuid) IS
  'V519, V528, V534: a student''s overpaid school fees and what the Bursary decided (carried, or a refund raised with its state), the account given for a refund and whether it may be given now, and when a refund was paid with its transfer reference — what the student''s fees page shows.';

-- ── 2 · every account money is paid out to, checked against its bank ─────────────────────────────────────────────────────
/* an account as it is given: the number's digits, the bank as it is listed; refused when the number is not one at the bank */
CREATE FUNCTION finance.checked_account(p_bank text, p_number text)
RETURNS TABLE (bank_name text, account_number text) LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_problem text := finance.account_number_problem(p_bank, p_number); b finance.bank := finance.bank_of(p_bank);
BEGIN
    IF v_problem = 'REFUND_ACCOUNT_NUMBER' THEN
        RAISE EXCEPTION 'REFUND_ACCOUNT_NUMBER: an account number is ten digits (your NUBAN)' USING ERRCODE = '23514';
    ELSIF v_problem = 'REFUND_ACCOUNT_CHECK_DIGIT' THEN
        RAISE EXCEPTION 'REFUND_ACCOUNT_CHECK_DIGIT: % is not an account number at %; check the number and the bank', regexp_replace(p_number, '[\s-]', '', 'g'), b.name
            USING ERRCODE = '23514', HINT = 'The last digit of an account number is worked out from the bank and the other nine; one digit wrong, or another bank, shows here.';
    END IF;
    RETURN QUERY SELECT coalesce(b.name, btrim(p_bank)), regexp_replace(p_number, '[\s-]', '', 'g');
END $fn$;
COMMENT ON FUNCTION finance.checked_account(text, text) IS
  'V534: an account money is paid out to, as given: refused when the number is not ten digits or, at a checked bank, its check digit is wrong; the digits and the bank''s listed name otherwise.';

/* a withdrawn JUPEB candidate's claim: the account checked when it is given or changed */
CREATE FUNCTION jupeb.trg_claim_account_checked()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE c record;
BEGIN
    IF NEW.account_number IS NOT NULL
       AND (TG_OP = 'INSERT' OR NEW.account_number IS DISTINCT FROM OLD.account_number OR NEW.bank_name IS DISTINCT FROM OLD.bank_name) THEN
        SELECT * INTO c FROM finance.checked_account(NEW.bank_name, NEW.account_number);
        NEW.bank_name := c.bank_name;
        NEW.account_number := c.account_number;
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_claim_account_checked BEFORE INSERT OR UPDATE OF bank_name, account_number ON jupeb.refund_claim
    FOR EACH ROW EXECUTE FUNCTION jupeb.trg_claim_account_checked();

/* a student's NELFUND wallet withdrawal: the account checked when it is requested */
CREATE FUNCTION finance.trg_withdrawal_account_checked()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE c record;
BEGIN
    IF TG_OP = 'INSERT' OR NEW.account_no IS DISTINCT FROM OLD.account_no OR NEW.bank_name IS DISTINCT FROM OLD.bank_name THEN
        SELECT * INTO c FROM finance.checked_account(NEW.bank_name, NEW.account_no);
        NEW.bank_name := c.bank_name;
        NEW.account_no := c.account_number;
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_withdrawal_account_checked BEFORE INSERT OR UPDATE OF bank_name, account_no ON finance.wallet_withdrawal
    FOR EACH ROW EXECUTE FUNCTION finance.trg_withdrawal_account_checked();

COMMIT;
