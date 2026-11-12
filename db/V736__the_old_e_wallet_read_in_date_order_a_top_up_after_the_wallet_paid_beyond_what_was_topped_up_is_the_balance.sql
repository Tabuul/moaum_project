-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V736 · The old e-wallet read in date order: a top-up after the wallet paid beyond what had been topped up is the balance
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's word of 12 November 2026, with the Bursar's screenshot of Old e-wallet balances: BSU/BM/RAD/23/3567 topped up
--  ₦61,700 on 7 October 2026 ("E-WALLET TOP-UP (legacy) · semester 2") and reads "Requires review", balance nil — "enable the
--  E-WALLET TOP-UP to be moved to student wallet to use and apply on the new portal, this is real wallet topup".
--  V583 read a student's old wallet as all the top-ups on file less all that was paid from it, so the ₦102,720 of 2025/2026 first
--  semester school fees paid from the wallet on 20 April 2026 was taken out of the ₦61,700 topped up six months after it. A payment
--  cannot draw on a later top-up: the April payment came from top-ups the old-fees export does not show, and the October top-up is
--  untouched. V736 reads the wallet in date order — top-ups in, wallet payments out, a day's top-ups before that day's payments (the
--  export carries the payment day only) —
--  and whatever the wallet paid beyond what had been topped up on file before it (paid_before_topups) is taken to have come from top-ups
--  the export does not show: it takes nothing of the later top-ups. The balance is topped up − paid + paid_before_topups, the running
--  balance floored at nil wherever the wallet paid more than it held on file; never more than was provably topped up and not paid out
--  after. On a copy of live (late October): 178 of the 3,878 students under review have a balance (₦3,229,633; the reported student
--  ₦61,700), 2 of the 285 computed balances rise (₦8,000), and 3,700 stay under review — the wallet paid more after their last top-up
--  than was on file, so their top-ups were spent and the old portal's statement still governs them.
--  Unchanged: a balance is computed, never trusted — one officer verifies it, another Bursar officer posts it (V583, V625); the old
--  portal's statement governs where entered; posted, rejected and frozen rows are kept; nothing is posted here. A verified balance the
--  date order reads otherwise goes back to be verified again; a posted one is marked CHANGED_AFTER_POSTING with both amounts.
--  A top-up whose day is not known — dated on or after the day it was recorded here: an undated row stamped at its import (V725),
--  or the retired upload's day kept (V502) — is counted before everything, so it is never taken for untouched money (none on the
--  copy). The old portal's statement entered is compared with the date-order balance (legacy_wallet_state), and the credit's note
--  says what was paid before the top-ups, so its figures add up to the amount (legacy_wallet_post). Reviewed (three finders, a
--  refuter each: four of sixteen stood, three fixed here, the fourth the same as one of them).
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V736: the old e-wallet read in date order (the University''s word of 12 November 2026)', true);

ALTER TABLE finance.legacy_wallet ADD COLUMN IF NOT EXISTS paid_before_topups numeric NOT NULL DEFAULT 0 CHECK (paid_before_topups >= 0);
COMMENT ON COLUMN finance.legacy_wallet.paid_before_topups IS
  'V736: what the old wallet paid beyond what had been topped up on file before each payment, read in date order — money from top-ups the old-fees export does not show; it takes nothing of the later top-ups, so the balance is topups - used + this.';

CREATE OR REPLACE FUNCTION finance.legacy_wallet_compute(p_student uuid DEFAULT NULL::uuid)
 RETURNS TABLE(students integer, with_balance integer, review integer, no_balance integer, posted integer, available numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE n_students int; n_with int; n_review int; n_none int; n_posted int; v_avail numeric;
BEGIN
    WITH legacy AS MATERIALIZED (
        SELECT pr.student_id, pr.amount, pr.confirmed_at, pr.session, pr.note, pr.reference,
               -- V736: dated on or after the day it was recorded here — an undated row stamped at its import (V725), or the retired
               -- upload's day kept (V502): its real day is unknown
               (pr.confirmed_at AT TIME ZONE 'Africa/Lagos')::date >= (pr.generated_at AT TIME ZONE 'Africa/Lagos')::date AS undated,
               finance.legacy_wallet_is_topup(pr.purpose) AS is_topup,
               finance.legacy_wallet_method(pr.note) = 'E-Wallet' AS from_wallet
          FROM finance.payment_reference pr
         WHERE pr.channel = 'Legacy' AND pr.confirmed_at IS NOT NULL AND pr.archived_at IS NULL AND pr.student_id IS NOT NULL
           AND (p_student IS NULL OR pr.student_id = p_student)
           AND (finance.legacy_wallet_is_topup(pr.purpose) OR finance.legacy_wallet_method(pr.note) = 'E-Wallet')),
    -- V736: the wallet read in date order — top-ups in, wallet payments out, a day's top-ups before that day's payments (the export
    -- carries the day only, stamped at midnight; a top-up the same day may have funded the payment, so it is counted first; a
    -- top-up whose day is not known — dated on or after the day it was recorded here — is counted before everything). The
    -- running sum's lowest point below nil is what the wallet paid beyond what had been topped up on file before it: money from
    -- top-ups the export does not show. Only later payments draw on later top-ups (balance = S_N - min(0, min_k S_k))
    run AS (
        SELECT l.student_id,
               sum(CASE WHEN l.is_topup THEN l.amount ELSE -l.amount END)
                   OVER (PARTITION BY l.student_id ORDER BY CASE WHEN l.is_topup AND l.undated THEN '-infinity'::date ELSE (l.confirmed_at AT TIME ZONE 'Africa/Lagos')::date END,
                                                l.is_topup DESC, l.confirmed_at, l.reference ROWS UNBOUNDED PRECEDING) AS s
          FROM legacy l WHERE l.is_topup OR l.from_wallet),
    low AS (SELECT r.student_id, -least(0, min(r.s)) AS paid_before FROM run r GROUP BY r.student_id),
    per0 AS (
        SELECT l.student_id,
               coalesce(sum(l.amount) FILTER (WHERE l.is_topup), 0) AS topups, count(*) FILTER (WHERE l.is_topup) AS topup_count,
               coalesce(sum(l.amount) FILTER (WHERE l.from_wallet AND NOT l.is_topup), 0) AS used, count(*) FILTER (WHERE l.from_wallet AND NOT l.is_topup) AS used_count,
               min(l.confirmed_at) FILTER (WHERE l.is_topup) AS first_topup_at, max(l.confirmed_at) FILTER (WHERE l.is_topup) AS last_topup_at,
               (array_agg(l.reference ORDER BY l.confirmed_at DESC) FILTER (WHERE l.is_topup))[1] AS last_topup_ref,
               (array_agg(l.session ORDER BY l.confirmed_at DESC) FILTER (WHERE l.is_topup))[1] AS session
          FROM legacy l GROUP BY l.student_id
        HAVING count(*) FILTER (WHERE l.is_topup) > 0),
    per AS (
        SELECT p.*, coalesce(lo.paid_before, 0) AS paid_before, p.topups - p.used + coalesce(lo.paid_before, 0) AS balance
          FROM per0 p LEFT JOIN low lo ON lo.student_id = p.student_id),
    credited AS (   -- a credit already on the wallet (posted here, or by hand under the same source): the row reads POSTED
        SELECT e.student_id, e.id AS entry FROM finance.wallet_entry e WHERE e.kind = 'CREDIT' AND e.source_code = 'LEGACY_WALLET'),
    up AS (
        INSERT INTO finance.legacy_wallet AS w (student_id, topups, topup_count, used, used_count, first_topup_at, last_topup_at, last_topup_ref, session, available, status, reason_code, reason, computed_at, wallet_entry_id, paid_before_topups)
        SELECT p.student_id, p.topups, p.topup_count, p.used, p.used_count, p.first_topup_at, p.last_topup_at, p.last_topup_ref, p.session,
               -- V736: the balance read in date order (topped up − paid + what was paid beyond the top-ups on file before it)
               p.balance,
               CASE WHEN c.entry IS NOT NULL THEN 'POSTED' WHEN p.balance > 0 THEN 'COMPUTED' WHEN p.paid_before > 0 THEN 'REQUIRES_REVIEW' ELSE 'NO_BALANCE' END,
               CASE WHEN c.entry IS NOT NULL THEN NULL WHEN p.balance > 0 AND p.paid_before > 0 THEN 'PAID_BEFORE_TOPUPS' WHEN p.balance <= 0 AND p.paid_before > 0 THEN 'USED_EXCEEDS_TOPUPS' END,
               CASE WHEN c.entry IS NOT NULL THEN NULL
                    WHEN p.balance > 0 AND p.paid_before > 0
                    THEN format('%s was paid from the old wallet beyond what had been topped up on file before it — from top-ups the export does not show, so it took nothing of the later top-ups; the %s topped up and not paid out since is the balance', p.paid_before, p.balance)
                    WHEN p.balance <= 0 AND p.paid_before > 0
                    THEN format('%s paid from the old wallet beyond what had been topped up on file before it, and nothing topped up since is left (%s topped up, %s paid from it): the old wallet held money the export does not show', p.paid_before, p.topups, p.used) END,
               now(), c.entry, p.paid_before
          FROM per p LEFT JOIN credited c ON c.student_id = p.student_id
        ON CONFLICT (student_id) DO UPDATE SET
               topups = EXCLUDED.topups, topup_count = EXCLUDED.topup_count, used = EXCLUDED.used, used_count = EXCLUDED.used_count,
               paid_before_topups = EXCLUDED.paid_before_topups,
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
                             WHEN w.status = 'VERIFIED' AND (w.topups, w.used) = (EXCLUDED.topups, EXCLUDED.used) AND w.available = EXCLUDED.available THEN 'VERIFIED'
                             ELSE EXCLUDED.status END,
               reason_code = CASE WHEN w.status = 'POSTED' AND ((w.topups, w.used) <> (EXCLUDED.topups, EXCLUDED.used) OR (w.stated_balance IS NULL AND w.available <> EXCLUDED.available)) THEN 'CHANGED_AFTER_POSTING'
                                  WHEN w.status IN ('POSTED', 'REJECTED', 'FROZEN') THEN w.reason_code
                                  WHEN w.status = 'VERIFIED' AND w.stated_balance IS NULL AND ((w.topups, w.used) <> (EXCLUDED.topups, EXCLUDED.used) OR w.available <> EXCLUDED.available) THEN 'CHANGED_AFTER_VERIFICATION'
                                  WHEN w.status = 'VERIFIED' AND (w.topups, w.used) <> (EXCLUDED.topups, EXCLUDED.used) THEN 'CHANGED_AFTER_VERIFICATION'
                                  WHEN w.stated_balance IS NOT NULL AND w.stated_balance <> EXCLUDED.available THEN 'STATEMENT_DIFFERS'
                                  ELSE EXCLUDED.reason_code END,
               reason = CASE WHEN w.status = 'POSTED' AND (w.topups, w.used) <> (EXCLUDED.topups, EXCLUDED.used)
                                  THEN format('the imported payments changed after the posting (top-ups %s, used %s now)', EXCLUDED.topups, EXCLUDED.used)
                             WHEN w.status = 'POSTED' AND w.stated_balance IS NULL AND w.available <> EXCLUDED.available
                                  THEN format('read in date order the balance is %s; %s was posted', EXCLUDED.available, w.available)
                             WHEN w.status IN ('POSTED', 'REJECTED', 'FROZEN') THEN w.reason
                             WHEN w.status = 'VERIFIED' AND (w.topups, w.used) <> (EXCLUDED.topups, EXCLUDED.used) THEN 'the imported payments changed after the verification; verify again'
                             WHEN w.status = 'VERIFIED' AND w.stated_balance IS NULL AND w.available <> EXCLUDED.available
                                  THEN format('read in date order the balance is %s, not the %s verified; verify again', EXCLUDED.available, w.available)
                             WHEN w.stated_balance IS NOT NULL AND w.stated_balance <> EXCLUDED.available
                                  THEN format('the old portal''s statement says %s; the imported payments leave %s', w.stated_balance, EXCLUDED.available)
                             ELSE EXCLUDED.reason END
        RETURNING w.status, w.available)
    SELECT count(*), count(*) FILTER (WHERE u.status IN ('COMPUTED', 'VERIFIED')), count(*) FILTER (WHERE u.status = 'REQUIRES_REVIEW'),
           count(*) FILTER (WHERE u.status = 'NO_BALANCE'), count(*) FILTER (WHERE u.status = 'POSTED'), coalesce(sum(u.available) FILTER (WHERE u.status IN ('COMPUTED', 'VERIFIED')), 0)
      INTO n_students, n_with, n_review, n_none, n_posted, v_avail
      FROM up u;
    RETURN QUERY SELECT n_students, n_with, n_review, n_none, n_posted, v_avail;
END $function$;
COMMENT ON FUNCTION finance.legacy_wallet_compute(uuid) IS
  'V583, V670, V736: every student''s old e-wallet balance from the imported old-portal payments, read in date order: a payment from the wallet beyond what had been topped up on file before it came from top-ups the export does not show and takes nothing of the later top-ups; the old portal''s statement governs where entered; posted, rejected and frozen rows kept.';

DROP FUNCTION finance.legacy_wallet_rows(text, text, text, text, integer);
CREATE FUNCTION finance.legacy_wallet_rows(p_status text, p_q text, p_fac text, p_dept text, p_limit integer DEFAULT 500)
 RETURNS TABLE(id uuid, student_id uuid, student text, matric_no text, jamb_reg_no text, student_status text, programme text, dept_code text, department text, faculty_code text, faculty text, topups numeric, topup_count integer, used numeric, used_count integer, first_topup_at timestamp with time zone, last_topup_at timestamp with time zone, last_topup_ref text, session text, stated_topups numeric, stated_used numeric, stated_refunds numeric, stated_reversed numeric, stated_balance numeric, stated_source text, stated_note text, stated_by text, stated_at timestamp with time zone, available numeric, status text, reason_code text, reason text, computed_at timestamp with time zone, verified_by text, verified_office text, verified_at timestamp with time zone, verify_note text, posted_by text, posted_office text, posted_at timestamp with time zone, batch_ref text, decided_by text, decided_at timestamp with time zone, decision_note text, wallet_reference text, applied numeric, refunded numeric, remaining numeric, paid_before_topups numeric)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT w.id, w.student_id, s.surname || ', ' || s.other_names, s.matric_no, s.jamb_reg_no, s.status, p.name, p.dept_code, d.name, p.faculty_code, f.name,
           w.topups, w.topup_count, w.used, w.used_count, w.first_topup_at, w.last_topup_at, w.last_topup_ref, w.session,
           w.stated_topups, w.stated_used, w.stated_refunds, w.stated_reversed, w.stated_balance, w.stated_source, w.stated_note, helpdesk.person_name(w.stated_by), w.stated_at,
           w.available, w.status, w.reason_code, w.reason, w.computed_at,
           helpdesk.person_name(w.verified_by), w.verified_office, w.verified_at, w.verify_note, helpdesk.person_name(w.posted_by), w.posted_office, w.posted_at, w.batch_ref,
           helpdesk.person_name(w.decided_by), w.decided_at, w.decision_note, e.reference,
           coalesce(x.applied, 0), coalesce(x.refunded, 0), CASE WHEN e.id IS NULL THEN NULL ELSE e.amount - coalesce(x.applied, 0) - coalesce(x.refunded, 0) END,
           w.paid_before_topups
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
$function$;

CREATE OR REPLACE FUNCTION finance.legacy_wallet_figures()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH w AS (SELECT * FROM finance.legacy_wallet),
    applied AS (SELECT coalesce(sum(e.amount) FILTER (WHERE e.kind = 'APPLIED'), 0) AS applied, coalesce(sum(e.amount) FILTER (WHERE e.kind = 'REFUND'), 0) AS refunded,
                       coalesce(sum(e.amount) FILTER (WHERE e.kind = 'CREDIT'), 0) AS credited
                  FROM finance.wallet_entry e WHERE e.source_code = 'LEGACY_WALLET'),
    orphan AS (   -- paid from the old wallet with no top-up on file
        SELECT count(DISTINCT pr.student_id) AS students, coalesce(sum(pr.amount), 0) AS amount
          FROM finance.payment_reference pr
         WHERE pr.channel = 'Legacy' AND pr.confirmed_at IS NOT NULL AND pr.archived_at IS NULL AND finance.legacy_wallet_method(pr.note) = 'E-Wallet' AND NOT finance.legacy_wallet_is_topup(pr.purpose)
           AND NOT EXISTS (SELECT 1 FROM finance.legacy_wallet lw WHERE lw.student_id = pr.student_id AND lw.topup_count > 0))
    SELECT jsonb_build_object(
        'students', (SELECT count(*) FROM w),
        'topups', (SELECT coalesce(sum(topups), 0) FROM w), 'topupCount', (SELECT coalesce(sum(topup_count), 0) FROM w),
        'used', (SELECT coalesce(sum(used), 0) FROM w),
        'computed', (SELECT count(*) FROM w WHERE status = 'COMPUTED'), 'computedAmount', (SELECT coalesce(sum(available), 0) FROM w WHERE status = 'COMPUTED'),
        'verified', (SELECT count(*) FROM w WHERE status = 'VERIFIED'), 'verifiedAmount', (SELECT coalesce(sum(available), 0) FROM w WHERE status = 'VERIFIED'),
        'returned', (SELECT count(*) FROM w WHERE status = 'RETURNED'), 'returnedAmount', (SELECT coalesce(sum(available), 0) FROM w WHERE status = 'RETURNED'),
        'posted', (SELECT count(*) FROM w WHERE status = 'POSTED'), 'postedAmount', (SELECT credited FROM applied),
        'applied', (SELECT applied FROM applied), 'refunded', (SELECT refunded FROM applied),
        'remaining', (SELECT credited - applied - refunded FROM applied),
        'review', (SELECT count(*) FROM w WHERE status = 'REQUIRES_REVIEW'), 'reviewUsed', (SELECT coalesce(sum(used - topups), 0) FROM w WHERE status = 'REQUIRES_REVIEW'),
        'noBalance', (SELECT count(*) FROM w WHERE status = 'NO_BALANCE'),
        -- V736: balances owed to the date order (the wallet paid beyond the top-ups on file before them), to verify or to post
        'paidBefore', (SELECT count(*) FROM w WHERE status IN ('COMPUTED', 'VERIFIED', 'RETURNED') AND paid_before_topups > 0),
        'paidBeforeAmount', (SELECT coalesce(sum(available), 0) FROM w WHERE status IN ('COMPUTED', 'VERIFIED', 'RETURNED') AND paid_before_topups > 0),
        'rejected', (SELECT count(*) FROM w WHERE status = 'REJECTED'), 'frozen', (SELECT count(*) FROM w WHERE status = 'FROZEN'),
        'stated', (SELECT count(*) FROM w WHERE stated_balance IS NOT NULL), 'differs', (SELECT count(*) FROM w WHERE reason_code = 'STATEMENT_DIFFERS'),
        'changed', (SELECT count(*) FROM w WHERE reason_code IN ('CHANGED_AFTER_POSTING', 'CHANGED_AFTER_VERIFICATION')),
        'orphanStudents', (SELECT students FROM orphan), 'orphanAmount', (SELECT amount FROM orphan),
        'lastComputed', (SELECT max(computed_at) FROM w),
        'batches', (SELECT coalesce(json_agg(b ORDER BY b.posted_at DESC), '[]'::json)::jsonb FROM (
                        SELECT b.ref, b.posted_at, b.students, b.amount, b.skipped, helpdesk.person_name(b.posted_by) AS posted_by, b.office FROM finance.legacy_wallet_batch b ORDER BY b.posted_at DESC LIMIT 50) b))
$function$;

-- ── the statement entered compared with the date-order balance; the credit's note saying what was paid before ──
CREATE OR REPLACE FUNCTION finance.legacy_wallet_state(p_student uuid, p_topups numeric, p_used numeric, p_refunds numeric, p_reversed numeric, p_balance numeric, p_source text, p_note text)
 RETURNS finance.legacy_wallet
 LANGUAGE plpgsql
AS $function$
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
           -- V736: compared with the balance the imported payments leave read in date order, as the computation compares it
           reason_code = CASE WHEN w.topup_count = 0 THEN 'NO_TOPUP_ON_FILE' WHEN p_balance <> greatest(w.topups - w.used + w.paid_before_topups, 0) THEN 'STATEMENT_DIFFERS' END,
           reason = CASE WHEN w.topup_count = 0 THEN 'no top-up on file; the balance rests on the old portal''s statement'
                         WHEN p_balance <> greatest(w.topups - w.used + w.paid_before_topups, 0) THEN format('the old portal''s statement says %s; the imported payments leave %s', p_balance, greatest(w.topups - w.used + w.paid_before_topups, 0)) END
     WHERE student_id = p_student
    RETURNING * INTO w;
    RETURN w;
END $function$;

CREATE OR REPLACE FUNCTION finance.legacy_wallet_post(p_ids uuid[], p_note text)
 RETURNS TABLE(batch_ref text, posted integer, amount numeric, skipped integer, skipped_why jsonb)
 LANGUAGE plpgsql
AS $function$
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
                                                        ELSE 'topped up NGN ' || w.topups || ' (' || w.topup_count || '), paid from it NGN ' || w.used || ' (' || w.used_count || ')'
                                                             -- V736: what was paid before the top-ups, so the note adds up to the credit
                                                             || CASE WHEN w.paid_before_topups > 0 THEN ', NGN ' || w.paid_before_topups || ' of it before these top-ups (read in date order)' ELSE '' END END
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
END $function$;

-- ── the reconciliation run again where it has been run: the balances the date order gives are there to verify at once ──────────
DO $$
DECLARE v_before int; v_review_before int; r record; v_now int;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE status = 'REQUIRES_REVIEW') INTO v_before, v_review_before FROM finance.legacy_wallet;
    IF v_before = 0 THEN
        RAISE NOTICE 'V736: the old e-wallet reconciliation has not been run here; it reads in date order when it is';
        RETURN;
    END IF;
    SELECT * INTO r FROM finance.legacy_wallet_compute(NULL);
    SELECT count(*) INTO v_now FROM finance.legacy_wallet WHERE paid_before_topups > 0 AND status IN ('COMPUTED', 'VERIFIED', 'RETURNED');
    RAISE NOTICE 'V736: % students, % with a balance to verify or post (% of them read in date order, owed to top-ups after the wallet paid beyond what was on file), % under review (% before), % with no balance, % posted; % to verify',
        r.students, r.with_balance, v_now, r.review, v_review_before, r.no_balance, r.posted, r.available;
END $$;

COMMIT;
