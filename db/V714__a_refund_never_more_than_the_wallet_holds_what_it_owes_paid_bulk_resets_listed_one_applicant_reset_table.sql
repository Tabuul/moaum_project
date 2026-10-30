-- ════════════════════════════════════════════════════════════════════════
--  V714 · Follow-ups to V710: a refund never more than the wallet holds, what the wallet owes paid by the student, the bulk resets
--  listed with their rows, one reset table for applicants, V687's temporary password retired
-- ════════════════════════════════════════════════════════════════════════
--  The University's word of 30 October 2026 ("do 1-5").
--
--  1 · A wallet owing (V710: a credit moved to its owner after it was used) paid refunds: each source's available figure is floored at
--      nothing, so the debt never showed. finance.withdrawal_eligibility, finance.approve_withdrawal and finance.pay_withdrawal restated:
--      never more than the wallet holds in all — a wallet owing refunds nothing until it is settled (WALLET_REFUND_WALLET_OWES).
--  2 · The student pays what the wallet owes: finance.wallet_owed(student) (the amount, the swap that left it so, a reference still
--      open) and finance.wallet_debt_reference(student) — a reference for the amount owed, purpose "Wallet top-up — what the wallet
--      owes", which finance.confirm_payment credits to the wallet as a top-up once paid (an earlier unpaid one retired).
--  3 · The bulk resets listed: admissions.applicant_password_bulk_row keeps every row a committed bulk was given (what each number was
--      found to be and what was done); admissions.applicant_password_bulk_runs(kind, limit) — each bulk with its officer.
--      admissions.applicant_password_bulk_reset restated from V710 to keep its rows.
--  4 · One reset table for applicants: the applicant door's own "forgot password" and the Applicant Password Reset desk's link go on
--      iam.password_reset (APPLICANT) — the table the sign-in page's reset reads, as the general "Forgot password" (V058) already wrote —
--      not admissions.password_reset (V025), which is no longer written; the links still open there are carried over.
--      admissions.applicant_password_link restated (V687).
--  5 · V687's temporary password retired: admissions.applicant_password_temporary dropped (the API stopped giving one at V706); an
--      account still on a temporary password is put back on its number (the sentinel: the JAMB number, else the application number),
--      the change still required, and the applicant told.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V714: the follow-ups to V710', true);

-- ── 1 · a refund never more than the wallet holds ──

CREATE OR REPLACE FUNCTION finance.withdrawal_eligibility(p_student uuid, p_session text)
 RETURNS TABLE(eligible boolean, balance numeric, cleared boolean, arrears boolean, pending boolean, reason text, nelfund_refundable numeric, self_refundable numeric, grant_held numeric, nelfund_after_settlement boolean, refund_natures text[])
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE pos record; v_pending boolean; v_nel numeric := 0; v_self numeric := 0; v_grant numeric := 0; v_natures text[]; v_after boolean := false;
        v_total numeric; v_wallet numeric;
BEGIN
    SELECT * INTO pos FROM finance.position(p_student, p_session);
    SELECT ws.refund_natures INTO v_natures FROM finance.wallet_setting ws WHERE ws.one;
    v_pending := EXISTS (SELECT 1 FROM finance.wallet_withdrawal w WHERE w.student_id = p_student AND w.state IN ('REQUESTED', 'APPROVED'));
    SELECT coalesce(sum(greatest(b.available - b.held, 0)) FILTER (WHERE b.nature = 'LOAN' AND 'LOAN' = ANY (v_natures)), 0),
           coalesce(sum(greatest(b.available - b.held, 0)) FILTER (WHERE b.nature = 'SELF' AND 'SELF' = ANY (v_natures)), 0),
           coalesce(sum(b.available) FILTER (WHERE b.nature = 'GRANT'), 0)
      INTO v_nel, v_self, v_grant
      FROM finance.wallet_balances_session(p_student, p_session) b;
    -- the Fund's money arrived after the session's fees were settled by other means: nothing of it was applied
    v_after := pos.paid_in_full AND v_nel > 0
               AND NOT EXISTS (SELECT 1 FROM finance.wallet_entry e WHERE e.student_id = p_student AND e.session = p_session AND e.kind = 'APPLIED' AND e.source_code = 'NELFUND');
    -- nothing is refundable until the session's fees are settled and nothing is in arrears: the wallet pays them first
    IF NOT pos.paid_in_full OR pos.has_arrears THEN v_nel := 0; v_self := 0; END IF;
    -- V714: never more than the wallet holds in all: a wallet owing — a credit moved to its owner after it was used (V710), each source's
    -- own figure floored at nothing — refunds nothing until what it owes is settled
    v_wallet := finance.wallet_balance(p_student);
    IF v_nel + v_self > greatest(v_wallet, 0) THEN
        v_nel := least(v_nel, greatest(v_wallet, 0));
        v_self := least(v_self, greatest(v_wallet, 0) - v_nel);
    END IF;
    v_total := v_nel + v_self;
    RETURN QUERY SELECT
        (pos.paid_in_full AND NOT pos.has_arrears AND v_total > 0 AND NOT v_pending),
        v_total, pos.paid_in_full, pos.has_arrears, v_pending,
        CASE WHEN v_pending THEN 'A refund is already awaiting the Bursary.'
             WHEN NOT pos.paid_in_full THEN 'The ' || p_session || ' fees are not yet cleared in full; the wallet pays them first.'
             WHEN pos.has_arrears THEN 'There are fees owed from a previous session.'
             WHEN v_wallet < 0 THEN 'Your wallet owes NGN ' || to_char(-v_wallet, 'FM999,999,999,990.00') || '; nothing is refunded until it is settled.'
             WHEN v_total <= 0 AND v_grant > 0 THEN 'What remains in the wallet is a grant, which is not refunded to the student.'
             WHEN v_total <= 0 THEN 'The wallet holds nothing that may be refunded for ' || p_session || '.'
             ELSE 'NGN ' || v_total::text || ' may be refunded to your own bank account.' END,
        v_nel, v_self, v_grant, v_after, v_natures;
END $function$;

CREATE OR REPLACE FUNCTION finance.approve_withdrawal(p_id uuid)
 RETURNS finance.wallet_withdrawal
 LANGUAGE plpgsql
AS $function$
DECLARE r finance.wallet_withdrawal; elig record; v_cap numeric; reach record;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a withdrawal is approved by a person' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM finance.wallet_withdrawal WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state <> 'REQUESTED' THEN RAISE EXCEPTION 'withdrawal % is not awaiting a decision', p_id USING ERRCODE = '23514'; END IF;
    IF r.requested_by = current_setting('moaum.actor_id', true)::uuid THEN
        RAISE EXCEPTION 'WALLET_REFUND_TWO_PEOPLE: the person who requested a refund does not approve it' USING ERRCODE = '23514';
    END IF;
    -- the money and the clearance must still hold at the moment of approval, for this source and this session
    PERFORM pg_advisory_xact_lock(hashtext('wallet:' || r.student_id::text));
    SELECT * INTO elig FROM finance.withdrawal_eligibility(r.student_id, r.session);
    v_cap := CASE WHEN r.source_code = 'SELF' THEN elig.self_refundable WHEN r.source_code IS NULL THEN finance.wallet_balance(r.student_id) ELSE elig.nelfund_refundable END + r.amount;   -- its own hold is counted back
    IF NOT elig.cleared OR elig.arrears THEN
        RAISE EXCEPTION 'WALLET_REFUND_NOT_AVAILABLE: %', elig.reason USING ERRCODE = '23514';
    END IF;
    -- V714: and never more than the wallet holds in all (a wallet owing refunds nothing)
    IF finance.wallet_balance(r.student_id) < r.amount THEN
        RAISE EXCEPTION 'WALLET_REFUND_WALLET_OWES: the wallet holds NGN % in all, less than the NGN % to refund; what it owes is settled first',
            finance.wallet_balance(r.student_id), r.amount USING ERRCODE = '23514';
    END IF;
    IF v_cap < r.amount THEN
        RAISE EXCEPTION 'WALLET_REFUND_ABOVE_REFUNDABLE: the wallet no longer holds NGN % of %', r.amount, coalesce(r.source_code, 'funding') USING ERRCODE = '23514';
    END IF;
    UPDATE finance.wallet_withdrawal SET state = 'APPROVED', decided_at = now(),
           decided_by = current_setting('moaum.actor_id', true)::uuid WHERE id = p_id
    RETURNING * INTO r;
    SELECT * INTO reach FROM people.student_reach(r.student_id);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your refund is approved',
        'Your refund of NGN ' || r.amount::text || ' for ' || r.session || ' is approved and awaits payment to ' || r.bank_name || ' ' || r.account_no || '.', 'student', r.student_id);
    RETURN r;
END $function$;

CREATE OR REPLACE FUNCTION finance.pay_withdrawal(p_id uuid, p_ref text, p_paid_on date)
 RETURNS finance.wallet_withdrawal
 LANGUAGE plpgsql
AS $function$
DECLARE r finance.wallet_withdrawal; v_actor uuid; v_entry uuid; v_avail numeric; reach record; v_ref text := btrim(coalesce(p_ref, ''));
        v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date; v_day text;
BEGIN
    v_actor := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a payout is made by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM finance.wallet_withdrawal WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state <> 'APPROVED' THEN RAISE EXCEPTION 'withdrawal % is not approved for payment', p_id USING ERRCODE = '23514'; END IF;
    IF r.decided_by = v_actor THEN
        RAISE EXCEPTION 'the officer who approved a withdrawal does not also pay it' USING ERRCODE = '23514',
            HINT = 'A second officer records the payout.';
    END IF;
    -- V540: the evidence — the bank transfer reference and the date the money left
    IF length(v_ref) NOT BETWEEN 4 AND 60 OR v_ref !~ '^[A-Za-z0-9][A-Za-z0-9/._: -]*$' THEN
        RAISE EXCEPTION 'WALLET_PAID_REFERENCE: give the bank transfer reference the refund was paid with (4 to 60 letters and digits)' USING ERRCODE = '23514',
            HINT = 'It is on the bank''s confirmation of the transfer; Internal Audit matches it to the bank statement.';
    END IF;
    IF p_paid_on IS NULL OR p_paid_on > v_today THEN
        RAISE EXCEPTION 'WALLET_PAID_DATE: give the date the money left, today or before' USING ERRCODE = '23514';
    END IF;
    IF p_paid_on < (r.decided_at AT TIME ZONE 'Africa/Lagos')::date THEN
        RAISE EXCEPTION 'WALLET_PAID_DATE: the withdrawal was approved on %; it was not paid before that', to_char(r.decided_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY')
            USING ERRCODE = '23514';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('wallet:' || r.student_id::text));
    IF r.source_code IS NULL THEN
        v_avail := finance.wallet_balance(r.student_id);
    ELSE
        SELECT coalesce(sum(b.available), 0) INTO v_avail FROM finance.wallet_balances(r.student_id) b WHERE b.source_code = r.source_code;
    END IF;
    -- V714: and never more than the wallet holds in all (a wallet owing pays nothing out)
    IF finance.wallet_balance(r.student_id) < r.amount THEN
        RAISE EXCEPTION 'WALLET_REFUND_WALLET_OWES: the wallet holds NGN % in all, less than the NGN % to pay out; what it owes is settled first',
            finance.wallet_balance(r.student_id), r.amount USING ERRCODE = '23514';
    END IF;
    IF v_avail < r.amount THEN
        RAISE EXCEPTION 'the wallet no longer holds NGN % of %', r.amount, coalesce(r.source_code, 'funding') USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note, source_code)
    VALUES (r.student_id, r.session, 'REFUND', r.amount, v_ref,
            'Refunded to ' || r.bank_name || ' ' || r.account_no || CASE WHEN r.source_code IS NOT NULL THEN ' from ' || r.source_code ELSE '' END, r.source_code)
    RETURNING id INTO v_entry;
    UPDATE finance.wallet_withdrawal SET state = 'PAID', paid_at = now(), paid_by = v_actor, paid_ref = v_ref, paid_on = p_paid_on, entry_id = v_entry
     WHERE id = p_id
    RETURNING * INTO r;
    v_day := to_char(p_paid_on, 'FMDD FMMonth YYYY');
    SELECT * INTO reach FROM people.student_reach(r.student_id);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your refund is paid',
        'NGN ' || r.amount::text || ' for ' || r.session || ' was paid to ' || r.bank_name || ' ' || r.account_no || ' on ' || v_day
        || ' (bank transfer reference ' || v_ref || '). Quote the reference to your bank if the money has not arrived.', 'student', r.student_id);
    PERFORM platform.queue_notice('SMS', reach.phone, 'Your refund is paid',
        'MOAUM: refund of NGN ' || r.amount::text || ' paid to ' || r.bank_name || ' on ' || v_day || ', ref ' || v_ref || '.', 'student', r.student_id);
    RETURN r;
END $function$;

COMMENT ON FUNCTION finance.withdrawal_eligibility(uuid, text) IS
  'V327 …, V714: what a student may have refunded for a session — and never more than the wallet holds in all (a wallet owing refunds nothing)';

-- ── 2 · what the wallet owes, paid by the student ──

CREATE OR REPLACE FUNCTION finance.wallet_owed(p_student uuid)
RETURNS TABLE (owed numeric, swap_ref text, reference text, amount numeric, expires_at timestamptz)
LANGUAGE sql STABLE AS $fn$
    SELECT greatest(-finance.wallet_balance(p_student), 0),
           (SELECT x.swap_ref FROM finance.payment_swap x
             WHERE x.from_student = p_student AND x.wallet_entry_id IS NOT NULL AND x.status = 'COMPLETED' ORDER BY x.executed_at DESC NULLS LAST LIMIT 1),
           r.reference, r.amount, r.expires_at
      FROM (SELECT 1) one
      LEFT JOIN LATERAL (SELECT pr.reference, pr.amount, pr.expires_at FROM finance.payment_reference pr
                          WHERE pr.student_id = p_student AND pr.purpose LIKE 'Wallet top-up — what the wallet owes%'
                            AND pr.confirmed_at IS NULL AND pr.expires_at > now()
                          ORDER BY pr.generated_at DESC LIMIT 1) r ON true
$fn$;
COMMENT ON FUNCTION finance.wallet_owed(uuid) IS
  'V714: what a student''s wallet owes (nought when it owes nothing), the payment swap that left it so, and the reference to pay it still open';

CREATE OR REPLACE FUNCTION finance.wallet_debt_reference(p_student uuid)
RETURNS TABLE (reference text, amount numeric, session text)
LANGUAGE plpgsql AS $fn$
#variable_conflict use_column
DECLARE v_owed numeric; v_ses text := policy.university_current_session(); v_ref text;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('wallet:' || p_student::text));
    v_owed := -finance.wallet_balance(p_student);
    IF v_owed <= 0 THEN
        RAISE EXCEPTION 'WALLET_NOTHING_OWED: the wallet owes nothing' USING ERRCODE = '23514';
    END IF;
    -- an earlier unpaid one is retired: what is owed is worked out afresh each time
    UPDATE finance.payment_reference SET expires_at = now()
     WHERE student_id = p_student AND purpose LIKE 'Wallet top-up — what the wallet owes%' AND confirmed_at IS NULL AND expires_at > now();
    -- a top-up of the wallet: confirmed, finance.confirm_payment credits it (TOPUP), settling what is owed
    v_ref := finance.new_purpose_reference(p_student, v_ses, v_owed, 'Wallet top-up — what the wallet owes');
    UPDATE finance.payment_reference
       SET note = 'What the wallet owes after a payment correction: NGN ' || to_char(v_owed, 'FM999,999,999,990.00')
                  || coalesce(' (' || (SELECT x.swap_ref FROM finance.payment_swap x WHERE x.from_student = p_student AND x.wallet_entry_id IS NOT NULL
                                         AND x.status = 'COMPLETED' ORDER BY x.executed_at DESC NULLS LAST LIMIT 1) || ')', '')
     WHERE reference = v_ref;
    RETURN QUERY SELECT v_ref, v_owed, v_ses;
END $fn$;
COMMENT ON FUNCTION finance.wallet_debt_reference(uuid) IS
  'V714: the student''s reference to pay what the wallet owes (WALLET_NOTHING_OWED otherwise) — a wallet top-up, credited to the wallet once confirmed; an earlier unpaid one retired';

-- ── 3 · the bulk resets listed, with their rows ──

CREATE TABLE admissions.applicant_password_bulk_row (
    bulk_id uuid NOT NULL REFERENCES admissions.applicant_password_bulk (id) ON DELETE CASCADE,
    row_no integer NOT NULL,
    given text NOT NULL,
    outcome text NOT NULL,
    account_id uuid,
    applicant text,
    default_number text,
    detail text,
    PRIMARY KEY (bulk_id, row_no)
);
COMMENT ON TABLE admissions.applicant_password_bulk_row IS
  'V714: every row a committed bulk reset was given — the number or email, what it was found to be (RESET, NOT_FOUND, AMBIGUOUS, REPEATED, REFUSED), the applicant, the number reset to, why — written once with the bulk';
SELECT audit.exempt('admissions.applicant_password_bulk_row',
    'V714: the rows of a bulk reset, written once with it; the bulk itself and each reset it made are audited (admissions.applicant_password_bulk, applicant_password_reset, pg_applicant_password_reset).');

CREATE OR REPLACE FUNCTION admissions.applicant_password_bulk_keep(p_bulk uuid, p_row integer, p_given text, p_outcome text, p_account uuid,
                                                                  p_applicant text, p_default text, p_detail text)
RETURNS void LANGUAGE sql AS $fn$
    INSERT INTO admissions.applicant_password_bulk_row (bulk_id, row_no, given, outcome, account_id, applicant, default_number, detail)
    VALUES (p_bulk, p_row, p_given, p_outcome, p_account, p_applicant, p_default, p_detail)
$fn$;

CREATE OR REPLACE FUNCTION admissions.applicant_password_bulk_runs(p_kind text, p_limit integer DEFAULT 100)
RETURNS TABLE (id uuid, reference text, kind text, reason text, asked integer, reset integer, passed_over integer, done_at timestamptz,
               done_office text, done_by_name text)
LANGUAGE sql STABLE AS $fn$
    SELECT b.id, b.reference, b.kind, b.reason, b.asked, b.reset, b.passed_over, b.done_at, b.done_office,
           coalesce(p.surname || ', ' || p.given_names, 'Unknown officer')
      FROM admissions.applicant_password_bulk b
      LEFT JOIN iam.person p ON p.id = b.done_by
     WHERE b.kind = upper(btrim(coalesce(p_kind, '')))
     ORDER BY b.done_at DESC
     LIMIT greatest(least(coalesce(p_limit, 100), 100000), 1)
$fn$;
COMMENT ON FUNCTION admissions.applicant_password_bulk_runs(text, integer) IS
  'V714: the bulk resets of a kind (UNDERGRADUATE, POSTGRADUATE), newest first, with the officer, the reason and how many were asked, reset and passed over';

-- the bulk reset (V710), each row kept
CREATE OR REPLACE FUNCTION admissions.applicant_password_bulk_reset(p_kind text, p_numbers text[], p_reason text, p_commit boolean DEFAULT false)
 RETURNS TABLE(row_no integer, given text, outcome text, account_id uuid, applicant text, default_number text, detail text, bulk_ref text)
 LANGUAGE plpgsql
AS $function$
DECLARE v_kind text := upper(btrim(coalesce(p_kind, ''))); v_by uuid; v_reason text; v_bulk uuid; v_ref text; v_sealed text;
        v_keys text[] := '{}'; v_accounts uuid[] := '{}'; i integer := 0; v_n text; v_k text; v_ids uuid[]; v_id uuid;
        v_asked integer := 0; v_reset integer := 0; v_over integer := 0; v_err text;
BEGIN
    IF v_kind NOT IN ('UNDERGRADUATE', 'POSTGRADUATE') THEN
        RAISE EXCEPTION 'APW_BULK_KIND: a bulk reset is of undergraduate or postgraduate applicants, not %', p_kind USING ERRCODE = '22023';
    END IF;
    v_by := CASE WHEN v_kind = 'UNDERGRADUATE' THEN admissions.applicant_password_officer() ELSE admissions.pg_applicant_password_officer() END;
    v_reason := admissions.applicant_password_reason(p_reason);
    IF coalesce(cardinality(array_remove(array_remove(p_numbers, NULL), '')), 0) = 0 THEN
        RAISE EXCEPTION 'APW_BULK_EMPTY: give the numbers to reset, one to a line' USING ERRCODE = '23514';
    END IF;
    IF cardinality(p_numbers) > 2000 THEN
        RAISE EXCEPTION 'APW_BULK_TOO_MANY: at most 2,000 numbers at a time, not %', cardinality(p_numbers) USING ERRCODE = '23514';
    END IF;
    IF coalesce(p_commit, false) THEN
        v_ref := 'APW-BULK/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('admissions.applicant_password_bulk_seq')::text, 6, '0');
        INSERT INTO admissions.applicant_password_bulk (reference, kind, reason, done_by, done_office)
        VALUES (v_ref, v_kind, v_reason, v_by, current_setting('moaum.actor_office', true)) RETURNING id INTO v_bulk;
        PERFORM set_config('moaum.applicant_password_bulk', v_bulk::text, true);
        -- one sealed hash for the postgraduate bulk: the door opens on either number while the change is required (V709)
        IF v_kind = 'POSTGRADUATE' THEN v_sealed := crypt(gen_random_uuid()::text, gen_salt('bf', 12)); END IF;
    END IF;
    FOREACH v_n IN ARRAY p_numbers LOOP
        i := i + 1;
        v_n := btrim(coalesce(v_n, ''));
        CONTINUE WHEN v_n = '';
        v_asked := v_asked + 1;
        v_k := upper(regexp_replace(v_n, '\s+', '', 'g'));
        row_no := i; given := v_n; outcome := NULL; account_id := NULL; applicant := NULL; default_number := NULL; detail := NULL; bulk_ref := v_ref;
        IF v_k = ANY (v_keys) THEN
            outcome := 'REPEATED'; detail := 'already in the list'; v_over := v_over + 1; IF coalesce(p_commit, false) THEN PERFORM admissions.applicant_password_bulk_keep(v_bulk, row_no, given, outcome, account_id, applicant, default_number, detail); END IF; RETURN NEXT; CONTINUE;
        END IF;
        v_keys := v_keys || v_k;
        IF v_kind = 'UNDERGRADUATE' THEN
            SELECT array_agg(DISTINCT x.id) INTO v_ids
              FROM admissions.applicant_account x LEFT JOIN admissions.application ap ON ap.account_id = x.id
             WHERE upper(x.jamb_key) = v_k OR upper(ap.application_no) = v_k OR lower(x.email) = lower(v_n);
        ELSE
            SELECT array_agg(DISTINCT x.id) INTO v_ids
              FROM admissions.pg_applicant x
              LEFT JOIN admissions.pg_application ap ON ap.applicant_id = x.id
              LEFT JOIN admissions.pg_legacy_application lg ON lg.application_id = ap.id
             WHERE upper(ap.application_no) = v_k OR upper(regexp_replace(lg.legacy_application_no, '\s+', '', 'g')) = v_k OR lower(x.email) = lower(v_n);
        END IF;
        IF v_ids IS NULL THEN
            outcome := 'NOT_FOUND'; detail := 'no applicant has this number or email'; v_over := v_over + 1; IF coalesce(p_commit, false) THEN PERFORM admissions.applicant_password_bulk_keep(v_bulk, row_no, given, outcome, account_id, applicant, default_number, detail); END IF; RETURN NEXT; CONTINUE;
        END IF;
        IF cardinality(v_ids) > 1 THEN
            outcome := 'AMBIGUOUS'; detail := cardinality(v_ids) || ' applicants have it: reset each on the desk'; v_over := v_over + 1; IF coalesce(p_commit, false) THEN PERFORM admissions.applicant_password_bulk_keep(v_bulk, row_no, given, outcome, account_id, applicant, default_number, detail); END IF; RETURN NEXT; CONTINUE;
        END IF;
        v_id := v_ids[1];
        account_id := v_id;
        IF v_kind = 'UNDERGRADUATE' THEN
            SELECT c.surname || ', ' || c.other_names, admissions.applicant_default_number(x.id) INTO applicant, default_number
              FROM admissions.applicant_account x JOIN admissions.candidate c ON c.id = x.candidate_id WHERE x.id = v_id;
        ELSE
            SELECT x.surname || ', ' || x.other_names,
                   (SELECT ap.application_no FROM admissions.pg_application ap WHERE ap.applicant_id = x.id ORDER BY ap.created_at DESC LIMIT 1)
              INTO applicant, default_number
              FROM admissions.pg_applicant x WHERE x.id = v_id;
        END IF;
        IF v_id = ANY (v_accounts) THEN
            outcome := 'REPEATED'; detail := 'the same applicant is already in the list'; v_over := v_over + 1; IF coalesce(p_commit, false) THEN PERFORM admissions.applicant_password_bulk_keep(v_bulk, row_no, given, outcome, account_id, applicant, default_number, detail); END IF; RETURN NEXT; CONTINUE;
        END IF;
        v_accounts := v_accounts || v_id;
        IF default_number IS NULL THEN
            outcome := 'REFUSED';
            detail := CASE WHEN v_kind = 'UNDERGRADUATE' THEN 'neither a JAMB number nor an application number to reset to: send a link on the desk'
                           ELSE 'no application number to reset to' END;
            v_over := v_over + 1; IF coalesce(p_commit, false) THEN PERFORM admissions.applicant_password_bulk_keep(v_bulk, row_no, given, outcome, account_id, applicant, default_number, detail); END IF; RETURN NEXT; CONTINUE;
        END IF;
        IF NOT coalesce(p_commit, false) THEN
            outcome := 'WILL_RESET'; IF coalesce(p_commit, false) THEN PERFORM admissions.applicant_password_bulk_keep(v_bulk, row_no, given, outcome, account_id, applicant, default_number, detail); END IF; RETURN NEXT; CONTINUE;
        END IF;
        BEGIN
            IF v_kind = 'UNDERGRADUATE' THEN
                PERFORM admissions.applicant_password_default(v_id, v_reason);
            ELSE
                PERFORM admissions.pg_applicant_password_default(v_id, v_reason, v_sealed);
            END IF;
            outcome := 'RESET'; v_reset := v_reset + 1;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
            outcome := 'REFUSED'; detail := v_err; v_over := v_over + 1;
        END;
        IF coalesce(p_commit, false) THEN PERFORM admissions.applicant_password_bulk_keep(v_bulk, row_no, given, outcome, account_id, applicant, default_number, detail); END IF; RETURN NEXT;
    END LOOP;
    IF coalesce(p_commit, false) THEN
        UPDATE admissions.applicant_password_bulk SET asked = v_asked, reset = v_reset, passed_over = v_over WHERE id = v_bulk;
        PERFORM set_config('moaum.applicant_password_bulk', '', true);
    END IF;
END $function$;

-- the University's link (V687), on iam.password_reset
CREATE OR REPLACE FUNCTION admissions.applicant_password_link(p_account uuid, p_token_hash text, p_reason text, p_sent_to text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE v_by uuid := admissions.applicant_password_officer(); v_reason text := admissions.applicant_password_reason(p_reason);
        v_until timestamptz := now() + interval '1 hour'; v_id uuid;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admissions.applicant_account WHERE id = p_account) THEN
        RAISE EXCEPTION 'APW_NO_ACCOUNT: no applicant account %', p_account USING ERRCODE = '23503';
    END IF;
    -- V714: the links go on iam.password_reset (APPLICANT), the one table of the sign-in page's reset, with the applicant's own from either door
    IF (SELECT count(*) FROM iam.password_reset r WHERE r.subject_kind = 'APPLICANT' AND r.subject_id = p_account AND r.created_at > now() - interval '1 hour') >= 3 THEN
        RAISE EXCEPTION 'APW_LINK_LIMIT: three reset links went to this applicant in the last hour' USING ERRCODE = '23514',
            HINT = 'Ask the applicant to use the latest link, or issue a temporary password.';
    END IF;
    INSERT INTO iam.password_reset (subject_kind, subject_id, token_hash, expires_at) VALUES ('APPLICANT', p_account, p_token_hash, v_until);
    INSERT INTO admissions.applicant_password_reset (account_id, method, reason, sent_to, expires_at, reset_by, reset_office)
    VALUES (p_account, 'RESET_LINK', v_reason, p_sent_to, v_until, v_by, current_setting('moaum.actor_office', true))
    RETURNING id INTO v_id;
    INSERT INTO admissions.applicant_event (account_id, identifier, outcome) VALUES (p_account, '', 'RESET_LINK_SENT_BY_UNIVERSITY');
    RETURN jsonb_build_object('id', v_id, 'expiresAt', v_until);
END $function$;

COMMENT ON FUNCTION admissions.applicant_password_link(uuid, text, text, text) IS
  'V687, V714: a one-hour reset link the University sent an applicant (iam.password_reset, APPLICANT; at most three an hour, with the applicant''s own); the reset written down.';

-- ── 4 · the links still open on admissions.password_reset carried over to iam.password_reset ──

INSERT INTO iam.password_reset (subject_kind, subject_id, token_hash, expires_at, created_at)
SELECT 'APPLICANT', r.account_id, r.token_hash, r.expires_at, r.created_at
  FROM admissions.password_reset r
 WHERE r.used_at IS NULL AND r.expires_at > now()
   AND NOT EXISTS (SELECT 1 FROM iam.password_reset i WHERE i.token_hash = r.token_hash);
COMMENT ON TABLE admissions.password_reset IS
  'V025; V714: no longer written — an applicant''s reset links are on iam.password_reset (APPLICANT), the table the sign-in page''s reset reads; the links it held still open were carried there.';

-- ── 5 · V687's temporary password retired ──

DO $$
DECLARE a record; n integer := 0; v_jamb boolean; v_app uuid; v_appno text;
BEGIN
    FOR a IN
        SELECT x.* FROM admissions.applicant_account x
         WHERE x.must_change_password AND x.temp_expires_at IS NOT NULL AND x.password_hash <> 'SET_ON_FIRST_LOGIN'
           AND admissions.applicant_default_number(x.id) IS NOT NULL
         FOR UPDATE
    LOOP
        v_jamb := nullif(btrim(a.jamb_key), '') IS NOT NULL;
        -- back on the number, as a reset puts it (V706); the change still required at the sign-in
        UPDATE admissions.applicant_account SET password_hash = 'SET_ON_FIRST_LOGIN', temp_expires_at = NULL, failed_attempts = 0, locked_until = NULL
         WHERE id = a.id;
        UPDATE platform.session SET ended_at = now(), ended_reason = 'password reset' WHERE person_id = a.id AND ended_at IS NULL;
        INSERT INTO admissions.applicant_event (account_id, identifier, outcome) VALUES (a.id, '', 'TEMPORARY_RETIRED_TO_DEFAULT');
        SELECT p.id, p.application_no INTO v_app, v_appno FROM admissions.application p WHERE p.account_id = a.id ORDER BY p.created_at DESC NULLS LAST LIMIT 1;
        IF nullif(btrim(coalesce(a.email, '')), '') IS NOT NULL THEN
            PERFORM platform.queue_notice('EMAIL', a.email, 'Your MOAUM application password was reset',
                'The temporary password the University gave you for your application ' || coalesce(v_appno || ' ', '') || 'no longer works. Sign in with your '
                || CASE WHEN v_jamb THEN 'JAMB registration number' ELSE 'application number' END
                || ' as the password; you will choose your own password at once. If you did not ask for a reset, contact ICT Support.', 'application', v_app);
        END IF;
        IF nullif(btrim(coalesce(a.phone, '')), '') IS NOT NULL THEN
            PERFORM platform.queue_notice('SMS', a.phone, 'Your MOAUM application password was reset',
                'MOAUM: sign in with your ' || CASE WHEN v_jamb THEN 'JAMB number' ELSE 'application number' END || ' as the password and choose your own.', 'application', v_app);
        END IF;
        n := n + 1;
    END LOOP;
    RAISE NOTICE 'V714: % applicant account(s) still on a temporary password put back on their number', n;
END $$;

DROP FUNCTION IF EXISTS admissions.applicant_password_temporary(uuid, text, text, integer);

COMMIT;
