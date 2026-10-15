-- ═══════════════════════════════════════
-- V474 — PAYDirect answered on time: each notified payment recorded first, settled after
--
-- On 15 Oct 2026 Interswitch logged "Read timed out" for a PaymentNotificationRequest: it waited about 50 seconds for the
-- portal's answer and gave up. The portal's own work for a notification takes about half a second on the live-shaped copy
-- (the reference found in 0.1 s, the payment settled in 0.4 s, the log in 0.03 s); what it cannot do is wait for a database
-- connection while the portal's ten are busy — each of the notification's steps may wait up to 30 seconds for one, and the
-- steps add up past Interswitch's patience. The API now answers Interswitch from a small pool of its own and records each
-- believed payment before it settles it:
--
--   · finance.paydirect_inbox — one row for each payment Interswitch reports (by its PaymentLogId; a repeat of the same
--     payment counted on its row, a reversal its own row), what Interswitch said (never a secret), and where its settlement
--     stands: RECEIVED, SETTLED (with the settlement's outcome), FAILED (with the error; retried);
--   · finance.paydirect_receive records a payment, finance.paydirect_claim takes it for settling (never twice at once),
--     finance.paydirect_done records how it ended; finance.paydirect_open lists what still waits to be settled.
--
-- The settling itself is unchanged (finance.confirm_payment and its siblings, finance.gateway_event): the answer waits for it
-- up to a time budget, and a payment not settled within it is answered "received" — it is recorded — and settled after the
-- answer, a sweeper retrying anything left. No payment, reference or event already on record is changed.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V474: PAYDirect answered on time — each notified payment recorded first, settled after', true);

CREATE TABLE finance.paydirect_inbox (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_log_id     text,
    is_reversal        boolean NOT NULL DEFAULT false,
    reference          text,
    amount             numeric(14,2),
    payment            jsonb NOT NULL CHECK (jsonb_typeof(payment) = 'object'),
    received_at        timestamptz NOT NULL DEFAULT clock_timestamp(),
    last_received_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
    repeats            integer NOT NULL DEFAULT 0,
    state              text NOT NULL DEFAULT 'RECEIVED' CHECK (state IN ('RECEIVED', 'SETTLED', 'FAILED')),
    attempts           integer NOT NULL DEFAULT 0,
    claimed_at         timestamptz,
    settled_at         timestamptz,
    outcome            text,
    last_error         text
);
COMMENT ON TABLE finance.paydirect_inbox IS
  'V474: each payment Interswitch reported (PAYDirect payment notification), recorded before it is settled so the answer never waits on a busy portal: what Interswitch said (no secret), repeats counted, and where the settlement stands.';
CREATE UNIQUE INDEX ux_paydirect_inbox_log ON finance.paydirect_inbox (payment_log_id, is_reversal) WHERE payment_log_id IS NOT NULL;
CREATE INDEX ix_paydirect_inbox_open ON finance.paydirect_inbox (last_received_at) WHERE state <> 'SETTLED';
CREATE INDEX ix_paydirect_inbox_reference ON finance.paydirect_inbox (reference);
SELECT audit.exempt('finance.paydirect_inbox',
  'the PAYDirect notifications'' working state, written on every call before the answer; what Interswitch said and what the portal did with it are on finance.gateway_event, which is audited');

/* a payment Interswitch reported: recorded once by its PaymentLogId (and whether it is a reversal); a repeat is counted */
CREATE FUNCTION finance.paydirect_receive(p_log_id text, p_reversal boolean, p_reference text, p_amount numeric, p_payment jsonb)
RETURNS uuid
LANGUAGE sql AS $fn$
    INSERT INTO finance.paydirect_inbox (payment_log_id, is_reversal, reference, amount, payment)
    VALUES (nullif(btrim(p_log_id), ''), coalesce(p_reversal, false), nullif(upper(btrim(p_reference)), ''), p_amount, coalesce(p_payment, '{}'::jsonb))
    ON CONFLICT (payment_log_id, is_reversal) WHERE payment_log_id IS NOT NULL
    DO UPDATE SET repeats = finance.paydirect_inbox.repeats + 1, last_received_at = clock_timestamp(),
                  payment = EXCLUDED.payment, reference = coalesce(EXCLUDED.reference, finance.paydirect_inbox.reference),
                  amount = coalesce(EXCLUDED.amount, finance.paydirect_inbox.amount)
    RETURNING id
$fn$;
COMMENT ON FUNCTION finance.paydirect_receive(text, boolean, text, numeric, jsonb) IS
  'V474: a notified payment recorded before it is settled — once by its PaymentLogId and reversal flag; a repeat counted on its row.';

/* the payment taken for settling: never by two at once (a claim older than two minutes is a settler that died) */
CREATE FUNCTION finance.paydirect_claim(p_id uuid)
RETURNS jsonb
LANGUAGE sql AS $fn$
    UPDATE finance.paydirect_inbox
       SET claimed_at = clock_timestamp(), attempts = attempts + 1
     WHERE id = p_id AND (claimed_at IS NULL OR claimed_at < clock_timestamp() - interval '2 minutes')
    RETURNING payment
$fn$;
COMMENT ON FUNCTION finance.paydirect_claim(uuid) IS 'V474: a recorded payment taken for settling; NULL when another settler holds it.';

/* how the settling ended: SETTLED with the outcome, or FAILED with the error (retried by the sweeper) */
CREATE FUNCTION finance.paydirect_done(p_id uuid, p_settled boolean, p_outcome text, p_error text)
RETURNS void
LANGUAGE sql AS $fn$
    UPDATE finance.paydirect_inbox
       SET state = CASE WHEN p_settled THEN 'SETTLED' WHEN state = 'SETTLED' THEN 'SETTLED' ELSE 'FAILED' END,
           outcome = CASE WHEN p_settled THEN left(p_outcome, 200) ELSE outcome END,
           settled_at = CASE WHEN p_settled THEN coalesce(settled_at, clock_timestamp()) ELSE settled_at END,
           last_error = CASE WHEN p_settled THEN NULL ELSE left(p_error, 2000) END,
           claimed_at = NULL
     WHERE id = p_id
$fn$;
COMMENT ON FUNCTION finance.paydirect_done(uuid, boolean, text, text) IS
  'V474: how a recorded payment''s settling ended — SETTLED and its outcome, or FAILED and the error for the sweeper to retry; a payment once settled stays settled.';

/* what still waits to be settled, the oldest first: not held by a settler, last heard of at least p_quiet ago */
CREATE FUNCTION finance.paydirect_open(p_quiet interval, p_limit integer)
RETURNS SETOF uuid
LANGUAGE sql STABLE AS $fn$
    SELECT id FROM finance.paydirect_inbox
     WHERE state <> 'SETTLED' AND attempts < 50
       AND (claimed_at IS NULL OR claimed_at < clock_timestamp() - interval '2 minutes')
       AND last_received_at < clock_timestamp() - p_quiet
     ORDER BY received_at
     LIMIT p_limit
$fn$;
COMMENT ON FUNCTION finance.paydirect_open(interval, integer) IS 'V474: the recorded payments still to be settled, for the sweeper (fifty attempts at most).';

COMMIT;
