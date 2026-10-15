-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V480 — A payer's receipt for a Pay on Quickteller payment, and the list the Bursary sends Interswitch
--
--   · A payment made on Quickteller or at a bank (PayDirect) counts only when Interswitch reports it. When it is not reported,
--     the payer holds the one thing that finds it: the receipt's Payment Log Id. Until now they could only write to the
--     Bursary. Now a payer reports the receipt against their unconfirmed reference — the Payment Log Id, the day paid, the
--     amount and where — one report a reference, a new one replacing the last; an office may report it on the payer's behalf.
--     Nothing is confirmed by it: it tells the Bursary what to look for in the collections report, or what to ask
--     Interswitch to re-send.
--   · finance.paydirect_claims(days): the receipts reported, the reference's payer, what it asks, and whether it stands
--     confirmed now — for the hanging list.
--   · finance.paydirect_ask_list(days): what the Bursary sends Interswitch — every reference opened on Pay on Quickteller more
--     than an hour before and in the period with nothing confirmed, and every reported receipt still unconfirmed, with the
--     receipt's details where the payer gave them.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V480: a payer''s receipt for a Pay on Quickteller payment', true);

CREATE TABLE finance.paydirect_claim (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference       text NOT NULL,
    account_id      uuid NOT NULL,
    payment_log_id  text NOT NULL CHECK (length(btrim(payment_log_id)) BETWEEN 3 AND 40),
    paid_on         date NOT NULL,
    amount          numeric(14, 2) NULL CHECK (amount IS NULL OR amount > 0),
    channel         text NULL CHECK (channel IS NULL OR channel IN ('QUICKTELLER', 'BANK', 'OTHER')),
    note            text NULL CHECK (note IS NULL OR length(note) <= 500),
    claimed_at      timestamptz NOT NULL DEFAULT now(),
    claimed_by      uuid NULL,
    claimed_office  text NULL
);
CREATE UNIQUE INDEX ux_paydirect_claim_reference ON finance.paydirect_claim (reference);
SELECT audit.attach('finance.paydirect_claim');
COMMENT ON TABLE finance.paydirect_claim IS
  'V480: the receipt a payer reports against an unconfirmed reference paid on Quickteller or at a bank — one a reference, the latest kept; it confirms nothing, it tells the Bursary what to look for.';

/* the payer's report: the reference unconfirmed, the day paid not in the future nor before the reference existed */
CREATE OR REPLACE FUNCTION finance.paydirect_claim_set(p_reference text, p_account uuid, p_log_id text, p_paid_on date, p_amount numeric,
                                                      p_channel text, p_note text)
RETURNS finance.paydirect_claim LANGUAGE plpgsql AS $fn$
DECLARE v_ref text := upper(btrim(coalesce(p_reference, ''))); st record; c finance.paydirect_claim;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    SELECT * INTO st FROM finance.reference_state(v_ref);
    IF st.confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'PAY_CLAIM_CONFIRMED: % is already confirmed; its receipt is on the payment', v_ref USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_log_id, ''))) < 3 THEN
        RAISE EXCEPTION 'PAY_CLAIM_LOG_ID: the receipt''s Payment Log Id is what finds the payment' USING ERRCODE = '23514';
    END IF;
    -- the day paid as the receipt prints it: a Lagos calendar day, whatever the database's own time zone
    IF p_paid_on IS NULL OR p_paid_on > (now() AT TIME ZONE 'Africa/Lagos')::date OR p_paid_on < (now() AT TIME ZONE 'Africa/Lagos')::date - 120 THEN
        RAISE EXCEPTION 'PAY_CLAIM_DATE: the day paid is today or in the last four months, as the receipt shows' USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.paydirect_claim (reference, account_id, payment_log_id, paid_on, amount, channel, note, claimed_by, claimed_office)
    VALUES (v_ref, p_account, btrim(p_log_id), p_paid_on, p_amount, nullif(upper(btrim(coalesce(p_channel, ''))), ''),
            nullif(btrim(coalesce(p_note, '')), ''), v_actor, v_office)
    ON CONFLICT (reference) DO UPDATE SET account_id = EXCLUDED.account_id, payment_log_id = EXCLUDED.payment_log_id, paid_on = EXCLUDED.paid_on,
           amount = EXCLUDED.amount, channel = EXCLUDED.channel, note = EXCLUDED.note, claimed_at = now(),
           claimed_by = EXCLUDED.claimed_by, claimed_office = EXCLUDED.claimed_office
    RETURNING * INTO c;
    RETURN c;
END $fn$;

/* the receipts reported in the period, with the reference's payer, what it asks, and whether it stands confirmed now */
CREATE OR REPLACE FUNCTION finance.paydirect_claims(p_days int DEFAULT 30)
RETURNS TABLE(reference text, payer text, number text, due numeric, payment_log_id text, paid_on date, amount numeric, channel text, note text,
              claimed_at timestamptz, claimed_office text, confirmed_at timestamptz)
LANGUAGE sql STABLE AS $fn$
    SELECT cl.reference,
           coalesce(s.surname || ', ' || s.other_names, c.surname || ', ' || c.other_names),
           coalesce(s.matric_no, s.admission_no, ap.application_no),
           st.amount, cl.payment_log_id, cl.paid_on, cl.amount, cl.channel, cl.note, cl.claimed_at, cl.claimed_office, st.confirmed_at
      FROM finance.paydirect_claim cl
      LEFT JOIN LATERAL finance.reference_state(cl.reference) st ON true
      LEFT JOIN finance.payment_reference pr ON pr.reference = cl.reference
      LEFT JOIN people.student s ON s.id = pr.student_id
      LEFT JOIN admissions.fee_reference fr ON fr.reference = cl.reference
      LEFT JOIN admissions.application ap ON ap.id = fr.application_id
      LEFT JOIN admissions.candidate c ON c.id = ap.candidate_id
     WHERE cl.claimed_at > now() - make_interval(days => p_days)
     ORDER BY st.confirmed_at IS NOT NULL, cl.claimed_at
$fn$;
COMMENT ON FUNCTION finance.paydirect_claims(int) IS
  'V480: the receipts payers reported against Pay on Quickteller payments in the period — the unconfirmed first, with whether each stands confirmed now.';

/* what the Bursary sends Interswitch: the unreported Pay on Quickteller references and the unconfirmed reported receipts */
CREATE OR REPLACE FUNCTION finance.paydirect_ask_list(p_days int DEFAULT 14)
RETURNS TABLE(reference text, payer text, number text, due numeric, opened_at timestamptz, payment_log_id text, paid_on date, paid_amount numeric, channel text)
LANGUAGE sql STABLE AS $fn$
    WITH u AS (SELECT * FROM finance.paydirect_unreported(now(), 1, p_days)),
    cl AS (SELECT * FROM finance.paydirect_claims(p_days) x WHERE x.confirmed_at IS NULL)
    SELECT coalesce(u.reference, cl.reference), coalesce(u.payer, cl.payer), coalesce(u.number, cl.number), coalesce(u.amount, cl.due),
           u.opened_at, cl.payment_log_id, cl.paid_on, cl.amount, cl.channel
      FROM u FULL JOIN cl ON cl.reference = u.reference
     ORDER BY coalesce(u.opened_at, cl.claimed_at)
$fn$;
COMMENT ON FUNCTION finance.paydirect_ask_list(int) IS
  'V480: the list the Bursary sends Interswitch to re-send — references opened on Pay on Quickteller over an hour before and unconfirmed, and the receipts payers reported still unconfirmed.';

COMMIT;
