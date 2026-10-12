-- ═══════════════════════════════════════
-- V420 — an applicant fee confirmed by hand in error, reversed by the Bursary
--
--   A bank payment confirmed against the wrong applicant's reference could only be put right in the database. Now the Bursary
--   reverses the confirmation, with its reason, on Payment Investigation (admissions.reverse_fee_confirmation):
--
--     · only a confirmation made by hand: one the payment gateway settled is money that reached the University on that
--       reference, and is refunded, never reversed (FEE_REVERSAL_GATEWAY);
--     · only while nothing has been done on it: an application fee once the application was submitted, a checking fee once
--       the status was read, an acceptance fee once the offer was accepted, cannot be reversed (FEE_REVERSAL_IN_USE);
--     · by the Bursar (or super), with a reason of at least ten characters (FEE_REVERSAL_OFFICE, FEE_REVERSAL_REASON).
--
--   The reversal is kept (admissions.fee_reversal: the reference, what it was, who confirmed it and when, the receipt, who
--   reversed it, when and why); the reference loses its confirmation and its receipt number and can no longer be paid (the
--   applicant generates a new one); the application's mark for that fee is cleared unless another reference of the same kind
--   stands confirmed; a payment already posted to the general ledger is reversed there (finance.gl_reverse); the applicant is
--   told by email and SMS. It applies to every applicant fee (Post-UTME, Direct Entry, transfer, CCE).
-- ═══════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V420: an applicant fee confirmed in error, reversed by the Bursary', true);

CREATE TABLE admissions.fee_reversal (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    fee_reference_id uuid NOT NULL REFERENCES admissions.fee_reference(id) ON DELETE CASCADE,
    application_id  uuid NOT NULL REFERENCES admissions.application(id) ON DELETE CASCADE,
    reference       text NOT NULL,
    kind            text NOT NULL,
    amount          numeric(12,2) NOT NULL,
    confirmed_at    timestamptz NOT NULL,
    confirmed_by    uuid NULL,
    channel         text NULL,
    receipt_no      text NULL,
    reason          text NOT NULL CHECK (length(btrim(reason)) >= 10),
    reversed_by     uuid NOT NULL,
    reversed_office text NOT NULL REFERENCES ref.office(code),
    reversed_at     timestamptz NOT NULL DEFAULT now(),
    ledger_journal  uuid NULL
);
CREATE INDEX ix_fee_reversal_reference ON admissions.fee_reversal (reference);
SELECT audit.attach('admissions.fee_reversal');
COMMENT ON TABLE admissions.fee_reversal IS
  'V420: an applicant fee confirmation reversed by the Bursary — what it was (reference, kind, amount, who confirmed it, when, the receipt), who reversed it, when and why, and the general-ledger reversal if the payment had been posted.';

-- whether a reference's confirmation may be reversed, and if not why — read by the Bursary's screen before it asks for a reason
CREATE FUNCTION admissions.fee_reversal_check(p_reference text)
RETURNS TABLE(reference text, kind text, amount numeric, application_no text, applicant text, route text, session text, confirmed_at timestamptz,
              channel text, receipt_no text, reversible boolean, why_not text)
LANGUAGE sql STABLE AS $fn$
    WITH r AS (SELECT f.* FROM admissions.fee_reference f WHERE f.reference = upper(btrim(p_reference))),
         a AS (SELECT ap.*, c.surname || ', ' || c.other_names AS applicant, c.entry_mode
                 FROM admissions.application ap JOIN admissions.candidate c ON c.id = ap.candidate_id JOIN r ON r.application_id = ap.id),
         x AS (
            SELECT r.reference, r.kind, r.amount, a.application_no, a.applicant, a.entry_mode, a.session, r.confirmed_at, r.channel, r.receipt_no,
                   CASE WHEN r.confirmed_at IS NULL THEN 'The reference is not confirmed: there is nothing to reverse'
                        WHEN EXISTS (SELECT 1 FROM finance.gateway_event g WHERE g.reference = r.reference AND g.outcome IN ('SETTLED', 'ALREADY_SETTLED'))
                            THEN 'The payment gateway settled it: the money reached the University on this reference. Refund it instead'
                        WHEN r.kind = 'APPLICATION' AND (a.submitted_at IS NOT NULL
                                 OR EXISTS (SELECT 1 FROM admissions.cce_review v WHERE v.application_id = a.id AND v.state <> 'DRAFT'))
                            THEN 'The application was submitted on this payment'
                        WHEN r.kind = 'CHECKING' AND (a.status_checked_at IS NOT NULL
                                 OR EXISTS (SELECT 1 FROM admissions.status_check k WHERE k.application_id = a.id AND k.checked_at >= r.confirmed_at))
                            THEN 'The admission status was read on this payment'
                        WHEN r.kind = 'ACCEPTANCE' AND (a.accepted_at IS NOT NULL
                                 OR EXISTS (SELECT 1 FROM people.student s WHERE s.candidate_id = a.candidate_id))
                            THEN 'The offer was accepted on this payment'
                   END AS why_not
              FROM r JOIN a ON true)
    SELECT x.reference, x.kind, x.amount, x.application_no, x.applicant, x.entry_mode, x.session, x.confirmed_at, x.channel, x.receipt_no,
           x.why_not IS NULL, x.why_not
      FROM x;
$fn$;
COMMENT ON FUNCTION admissions.fee_reversal_check(text) IS
  'V420: an applicant fee reference as the Bursary sees it before reversing its confirmation — and whether it may, and if not why.';

CREATE FUNCTION admissions.reverse_fee_confirmation(p_reference text, p_reason text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE r admissions.fee_reference; c record; a admissions.application; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_reason text := btrim(coalesce(p_reason, '')); v_journal uuid; v_gl uuid;
BEGIN
    IF v_actor IS NULL OR coalesce(v_office, '') NOT IN ('bursar', 'super') THEN
        RAISE EXCEPTION 'FEE_REVERSAL_OFFICE: a confirmation is reversed by the Bursary' USING ERRCODE = '23514';
    END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'FEE_REVERSAL_REASON: say why the confirmation was wrong (ten characters at least)' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM admissions.fee_reference WHERE reference = upper(btrim(p_reference)) FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'FEE_REVERSAL_UNKNOWN: no applicant fee reference % was generated by this portal', p_reference USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM admissions.fee_reversal_check(r.reference);
    IF NOT c.reversible THEN
        RAISE EXCEPTION '%', CASE WHEN r.confirmed_at IS NULL THEN 'FEE_REVERSAL_NOT_CONFIRMED: ' WHEN c.why_not LIKE 'The payment gateway%' THEN 'FEE_REVERSAL_GATEWAY: '
                                  ELSE 'FEE_REVERSAL_IN_USE: ' END || c.why_not USING ERRCODE = '23514';
    END IF;
    SELECT * INTO a FROM admissions.application WHERE id = r.application_id FOR UPDATE;

    -- the general ledger: a payment already posted there is reversed by a journal of its own
    SELECT j.id INTO v_journal FROM finance.gl_journal j WHERE j.source_type = 'PAYMENT' AND j.source_ref = r.reference AND j.status = 'POSTED' LIMIT 1;
    IF v_journal IS NOT NULL THEN
        v_gl := finance.gl_reverse(v_journal, 'Applicant fee confirmation reversed (' || r.reference || '): ' || v_reason);
    END IF;

    INSERT INTO admissions.fee_reversal (fee_reference_id, application_id, reference, kind, amount, confirmed_at, confirmed_by, channel, receipt_no, reason,
                                         reversed_by, reversed_office, ledger_journal)
    VALUES (r.id, r.application_id, r.reference, r.kind, r.amount, r.confirmed_at, r.confirmed_by, r.channel, r.receipt_no, v_reason, v_actor, v_office, v_gl);

    -- the reference: no confirmation, no receipt, no longer payable — the applicant generates a new one
    UPDATE admissions.fee_reference
       SET confirmed_at = NULL, confirmed_by = NULL, channel = NULL, note = NULL, receipt_no = NULL, expires_at = least(expires_at, now())
     WHERE id = r.id;

    -- the application's mark for the fee, unless another reference of that kind stands confirmed
    IF NOT EXISTS (SELECT 1 FROM admissions.fee_reference o WHERE o.application_id = a.id AND o.kind = r.kind AND o.confirmed_at IS NOT NULL) THEN
        UPDATE admissions.application
           SET fee_confirmed_at = CASE WHEN r.kind = 'APPLICATION' THEN NULL ELSE fee_confirmed_at END,
               checking_confirmed_at = CASE WHEN r.kind = 'CHECKING' THEN NULL ELSE checking_confirmed_at END,
               acceptance_confirmed_at = CASE WHEN r.kind = 'ACCEPTANCE' THEN NULL ELSE acceptance_confirmed_at END
         WHERE id = a.id;
    END IF;

    PERFORM admissions.notify_applicant(a.id, 'A payment recorded on your application was reversed',
        'A payment of NGN ' || to_char(r.amount, 'FM999,999,990.00') || ' recorded against your application ' || a.application_no
        || ' (reference ' || r.reference || coalesce(', receipt ' || r.receipt_no, '') || ') was recorded in error and has been reversed by the Bursary.' || chr(10) || chr(10)
        || 'The fee is still owed. Sign in, generate a new payment reference and pay it. If you paid this fee yourself, write to the Bursary with your bank teller or transfer receipt, quoting '
        || a.application_no || '.',
        'MOAUM: a payment recorded on application ' || a.application_no || ' was reversed in error correction; the fee is still owed. Sign in to pay it.');

    RETURN jsonb_build_object('reference', r.reference, 'kind', r.kind, 'amount', r.amount, 'ledgerReversed', v_gl IS NOT NULL);
END $fn$;
COMMENT ON FUNCTION admissions.reverse_fee_confirmation(text, text) IS
  'V420: the Bursary reverses an applicant fee confirmed by hand in error, with its reason — never one the gateway settled, never one already relied upon; the general ledger reversed too where it was posted; the applicant told.';

COMMIT;
