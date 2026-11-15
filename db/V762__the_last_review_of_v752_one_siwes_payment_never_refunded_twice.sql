-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V762 · the last review of V752: one SIWES payment never refunded twice
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V752 (SIWES registration and its ₦4,000 fee) went to main with the findings of its seventh review still open (docs/siwes-registration.md).
--  V752 is applied as it stands and is never edited, so the findings are answered here. Each function changed is restated from its
--  current text: V752's own SIWES functions in full (each checked first to be as V752 left it), the others by anchor, as V752 restated
--  theirs.
--
--    · d7-3 (medium) One ₦4,000 SIWES payment could be refunded twice on the refund desk when two refunds of it were raised at the same
--      moment (a double submit, or two officers). V350's sum read the refunds already raised before anything held the second proposal
--      back, and at approval V752's refusal refused a refund for less than what is left (REFUND_SIWES_PART), never one for more. Now the
--      refund desk takes the student's SIWES lock (finance.siwes_lock, through finance.siwes_lock_payment) before it reads anything of the
--      payment, in finance.propose_refund and finance.approve_refund. A second proposal or approval waits for the first and then sees it.
--      A refund for more than is left on a SIWES payment is refused, raised or approved (REFUND_SIWES_GIVEN_BACK, beside
--      REFUND_SIWES_PART). The Bursar's hand refund of a credit takes the same lock, so a refund raised on the desk and a hand refund of one
--      payment are never both made.
--    · d7-4 A SIWES registration made at the moment a Bursar approved the refund of the payment it rests on: both committed, and the
--      registration rested on money given back. Every door that refuses because a SIWES registration stands now reads that refusal under
--      the student's SIWES lock, taken first (finance.siwes_register takes the same lock): the refund desk, raised and approved
--      (REFUND_SIWES_REGISTERED), and the withdrawal of a record as never received, raised and decided (PAY_NOT_RECEIVED_SIWES_REGISTERED:
--      finance.propose_not_received, finance.decide_not_received). A refund approved reads it again under the lock
--      (finance.siwes_refund_follows): a SIWES registration standing on the payment, or more given back on it than was paid, undoes the
--      approval. The archive desk and the payment correction desk (finance.archive_payment, finance.payment_archive_decide,
--      finance.decide_payment_reallocation) take the lock too, before the payment's row, so the desks that act on one SIWES payment share
--      the registration's lock order: the student's row (finance.siwes_register locks it first; a desk takes it FOR KEY SHARE, as the row it
--      writes for the student would at its end), the student's SIWES lock, then the payment's row. In V752 a registration stopped halfway
--      (its SIWES lock held) deadlocked with the withdrawal of its payment, raised or decided, and with its archiving; and a desk that took
--      the SIWES lock first and then wrote its row for the student would deadlock with a registration that locked the student's row between
--      the two (db-test 10: R5, R6, R8 and R9-R12).
--    · d7-1 A SIWES payment that is itself an open credit coming back to stand (restored from the archive, a payment correction reversed)
--      applied no rule. Where the payment that settled the fee had been refunded or archived meanwhile, the fee stood paid by an open credit
--      the Bursar was offered to refund. Now the one rule is applied (finance.siwes_comes_to_stand): when nothing else settles the fee, the
--      oldest open credit settles it.
--    · d7-2 and the live rehearsal's finding: an old fees upload without payment numbers could move an old-portal SIWES record of a group
--      the bank check holds to another day. The record found never received left the reach of V561's re-check, or the record found
--      received was released by its own move and refunded while its partner waited. Now finance.import_legacy_payments keeps the day of an
--      old-portal SIWES record of such a group (finance.siwes_group_kept: a record a NOT_RECEIVED check names; a record of the day of a
--      NOT_RECEIVED check whose record never received is not yet withdrawn; a record of a day with a withdrawal as never received waiting
--      or rejected). It does so in both of its re-dating branches, as it keeps an archived record's day, and the row counts as already on
--      record. When two checks speak of a record (the NOT_RECEIVED check naming it and the check of its current day), the newer decides
--      (finance.siwes_found_not_received, finance.siwes_bank_hold): a record moved before V762 is released by a newer check of its new day
--      that found it received, and the record of its old day no longer waits on it.
--    · d7-5 The old fees reset deleted the records of such a group, and the reload could give the plain reference the finding names to the
--      other payment of the day; a withdrawal waiting at the reset could never be decided. Now finance.reset_legacy_payments keeps every
--      old-portal SIWES record of such a group (in its batch and in the count of those kept), as it keeps one the Bursar refunded by hand.
--
--  The review of V762 found three more:
--    · d62-3 (from V752) A gateway confirming a second SIWES payment took the student's SIWES lock and then wrote the student's credit,
--      whose key locks the student's row; the student's registration locks that row and then the SIWES lock. With a third door holding
--      the lock a moment, the two deadlocked and the confirmation was lost. Now finance.siwes_lock itself takes the student's row (FOR KEY
--      SHARE) before the lock, so everything that takes the SIWES lock — the gateway's confirmation, a payment moved, archived or deleted,
--      a credit settled or reopened, a withdrawal or bank check decided, the desks — takes the registration's order: the student's row,
--      then the SIWES lock.
--    · d62-2 An old fees upload re-dating an old-portal SIWES record could race the Bursary's bank check of the record's day: the check
--      read the possible double charges before anything held the upload back, and the upload decided the day (finance.siwes_group_kept)
--      before the check was there to see. Now the upload takes the record's student's SIWES lock before it decides the record's day (in
--      both re-dating branches, the record read again under the lock), and the bank check of a SIWES item takes the same lock before it
--      reads the possible double charges (finance.check_double_charge): the check sees the record on its new day, or the upload sees the
--      check and keeps the day.
--    · d62-1 The desks take the SIWES lock before the payment's row, while a write that changes a SIWES payment's row outside them (the old
--      fees reset's delete, an earlier row of an old fees upload, a gateway confirmation) locks the row first and takes the SIWES lock in
--      the payment's trigger, after it. Meeting on one payment at one instant, PostgreSQL ends one of the two with a deadlock error and
--      nothing of it is kept. The desks, the student's SIWES registration and the portal's own writers that lock the row first (the old
--      fees upload and reset, their check and approval) are run again by their doors in a fresh transaction a few times (the API's
--      DeadlockRetry), so the officer sees the answer, not the error. A confirmation of a payment (a gateway's, or the Bursary's by hand) is
--      not run again by the portal: one that loses keeps nothing, and the payment waits unconfirmed until it is confirmed again.
--
--  The second review of V762 found three more:
--    · d62b-1 (medium) The Bursary's bank list (finance.bank_list_apply, V684) records the same checks and raises the same withdrawals as the
--      bank check, from one read of the possible double charges of its days taken before any SIWES lock: an old fees upload re-dating a
--      SIWES record of a listed group could still split the record from its check. Now the list takes the SIWES locks of the students
--      whose SIWES groups it acts on before it reads the groups, in one order (the student, then the session, each through
--      finance.siwes_lock), and acts on a read made under them (a group re-dated into its days meanwhile: its lock taken and the list read
--      again): the list sees the record on its new day, or the upload sees the list's check and keeps the day. The decision of the
--      withdrawals a list raised (finance.decide_bank_list), whichever it is, takes their students' SIWES locks, in the same order,
--      before it decides any (after the withdrawals' rows: d62c-1; a rejection or a cancellation as an approval does: d62d-1).
--    · d62b-2 A deadlock met inside the list's loop or its decision's (a withdrawal raised or decided) was recorded as a group or a
--      withdrawal refused ('deadlock detected') and the rest committed. Now a deadlock (40P01), a serialization failure (40001) or a lock
--      not had in time (55P03) there ends the whole list or decision, nothing of it kept, and its door runs it again (DeadlockRetry).
--    · d62b-3 What DeadlockRetry runs again, exactly, under Spring Framework 7.0.9's translation of PostgreSQL's errors: a deadlock (40P01)
--      and a serialization failure (40001), which Spring makes a PessimisticLockingFailureException (the second a
--      CannotAcquireLockException), and a lock not had in time (55P03), which Spring leaves an UncategorizedSQLException and DeadlockRetry
--      runs again by its SQLSTATE; never a statement stopped for its time or cancelled (57014), a refusal, or any other failure.
--
--  The third review of V762 found one more:
--    · d62c-1 The approval of a list's withdrawals (d62b-1) took the students' SIWES locks and then each withdrawal's row, while a
--      withdrawal decided or cancelled alone (finance.decide_not_received, finance.cancel_not_received) locks its row and then its
--      student's SIWES lock (an approval in finance.siwes_lock_payment; a rejection or a cancellation in the withdrawal's trigger,
--      finance.siwes_bank_check_follows). The two deadlocked, and the cancellation's door, which was not run again, showed the officer
--      the error. Now the decision of a list's withdrawals, whichever it is, first locks the row of every withdrawal of the list that still
--      waits, in their numbers' order (the order it decides them in); only then does it take the SIWES locks (d62d-1). One order for the
--      withdrawals: the withdrawal's row, the student's row and SIWES lock, the payment's row; no other function locks several
--      withdrawals' rows. The cancellation's door is run again on a passing clash too (DeadlockRetry), as the withdrawal's other doors are.
--
--  The fourth review of V762 found two more:
--    · d62d-1 A rejection or a cancellation of a list's withdrawals took no SIWES lock up front: each withdrawal's trigger took its
--      student's lock as it was decided, in the withdrawals' numbers' order, which follows the students' names, while the list's recording
--      (finance.bank_list_apply) and the approval of a list's withdrawals take them by student, then session. Two lists over the same two
--      students, one recorded or approved while the other was rejected or cancelled, could wait on each other in a circle; PostgreSQL ended
--      one and its door ran it again (nothing was lost, but the clash was needless). Now the decision of a list's withdrawals, whichever it
--      is, takes their students' SIWES locks after their rows and before it decides any, by student, then session: the lock of each
--      withdrawal's own student and session, which its trigger takes, and of its payment's, which an approval takes (the same lock unless
--      the payment was moved since the withdrawal was raised). A list recorded and a list's withdrawals decided take several students'
--      SIWES locks in that one order; an old fees upload takes them in its file's order and, meeting a list, may still be ended and run
--      again (d62-1).
--    · d62d-2 No check held the decision's locks for a rejection or a cancellation: db/check.sql now requires the withdrawals' rows locked,
--      then the SIWES locks taken, both whatever the decision is (no condition around either), before any withdrawal is decided.
--
--  V762 replaces functions and adds two; it locks no table, and no writer of the portal waits on it.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V762: the last review of V752 — one SIWES payment never refunded twice', true);

-- ── 0 · V752's SIWES functions restated in full below are as V752 left them ──────────────────────────────────────────────────────
DO $$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('finance.siwes_found_not_received(uuid)'::regprocedure);
    IF position('JOIN finance.double_charge_check k ON k.student_id = r.student_id AND r.reference = ANY (k.not_received)' IN d) = 0 THEN
        RAISE EXCEPTION 'V762: finance.siwes_found_not_received is not as V752 left it';
    END IF;
    d := pg_get_functiondef('finance.siwes_bank_hold(uuid)'::regprocedure);
    IF position('    -- the bank check that names this very record never received, whatever its day now (the newest, should two name it); else the' IN d) = 0
       OR position('         WHERE k.student_id = r.student_id AND k.session = r.session AND k.purpose = r.purpose AND k.paid_on = v_day AND k.amount = round(r.amount);' IN d) = 0 THEN
        RAISE EXCEPTION 'V762: finance.siwes_bank_hold is not as V752 left it';
    END IF;
    d := pg_get_functiondef('finance.siwes_refund_refusal(text,numeric)'::regprocedure);
    IF position('    IF pr.id IS NOT NULL AND finance.is_siwes_purpose(pr.purpose) AND p_amount < pr.amount - finance.gst_refunded(pr.reference) THEN' IN d) = 0 THEN
        RAISE EXCEPTION 'V762: finance.siwes_refund_refusal is not as V752 left it';
    END IF;
    d := pg_get_functiondef('finance.siwes_refund_follows()'::regprocedure);
    IF position('    PERFORM finance.siwes_lock(pr.student_id, pr.session);' IN d) = 0
       OR position('    PERFORM finance.siwes_settles_instead(pr.student_id, pr.session, pr.reference, ''refunded on the refund desk ('' || NEW.reference || '')'');' IN d) = 0 THEN
        RAISE EXCEPTION 'V762: finance.siwes_refund_follows is not as V752 left it';
    END IF;
    d := pg_get_functiondef('finance.siwes_comes_to_stand(uuid)'::regprocedure);
    IF position('    -- not an open credit itself (a refunded one never stands here: finance.siwes_standing)' IN d) = 0 THEN
        RAISE EXCEPTION 'V762: finance.siwes_comes_to_stand is not as V752 left it';
    END IF;
    d := pg_get_functiondef('finance.siwes_lock(uuid,text)'::regprocedure);
    IF position(E' LANGUAGE sql\nAS $function$\n    SELECT pg_advisory_xact_lock(hashtextextended(''V752 SIWES '' || p_student::text || '' '' || coalesce(p_session, ''''), 0));\n$function$' IN d) = 0 THEN
        RAISE EXCEPTION 'V762: finance.siwes_lock is not as V752 left it';
    END IF;
END $$;

-- ── 1 · one SIWES payment decided at a time: the student's SIWES lock, taken before anything of the payment is read ──────────────
/* the student's SIWES lock: one student's SIWES fee of one session is settled, registered on, refunded, withdrawn, archived or corrected
   one at a time (V752). V762 (d62-3): the student's row first, FOR KEY SHARE, then the lock — the order the student's SIWES registration
   takes them (registration.siwes_register locks the student's row FOR UPDATE, then this lock). Whoever takes the lock has the student's row
   already, so a write it then makes for the student (a credit, a refund, a withdrawal, whose keys lock that row FOR KEY SHARE) never waits
   on a registration that came second and waits on the lock: that registration waits at the student's row, holding nothing. FOR KEY SHARE
   holds back only a registration and a delete of the student or a change of the record's keys; an edit of the student's details does not
   wait on it. Taken again in the same transaction, it is held already. */
CREATE OR REPLACE FUNCTION finance.siwes_lock(p_student uuid, p_session text) RETURNS void LANGUAGE sql AS $$
    SELECT 1 FROM people.student s WHERE s.id = p_student FOR KEY SHARE;
    SELECT pg_advisory_xact_lock(hashtextextended('V752 SIWES ' || p_student::text || ' ' || coalesce(p_session, ''), 0));
$$;
COMMENT ON FUNCTION finance.siwes_lock(uuid, text) IS
  'V752, V762: the student''s SIWES lock of a session (a transaction advisory lock), after the student''s row FOR KEY SHARE — the order the student''s SIWES registration takes them (its row FOR UPDATE, then this lock) — taken by every settling of the SIWES fee, the registration and the desks that act on a SIWES payment.';

/* the student's SIWES lock (finance.siwes_lock: the student and session a SIWES payment stands under) for a door that acts on one SIWES
   payment — the refund desk, the withdrawal of a record as never received, the archive desk, the payment correction desk, an old fees
   upload re-dating a record — taken before the door reads anything of the payment or locks its row. Every settling of a SIWES fee and the
   student's SIWES registration (registration.siwes_register) take the same lock, so whatever arrives at the same moment is decided one after
   the other, and each refusal (REFUND_SIWES_REGISTERED, REFUND_SIWES_GIVEN_BACK, PAY_NOT_RECEIVED_SIWES_REGISTERED) is read with what came
   first in sight. The registration's lock order: the student's row (finance.siwes_lock takes it first: FOR KEY SHARE, what the row a desk
   writes for the student takes at its end; the registration holds it FOR UPDATE), the student's SIWES lock, then the payment's row. A
   registration that comes second waits at the student's row holding nothing a desk needs, and the two never wait on each other in a
   circle. (A write that locks a SIWES payment's row first and takes the lock in the payment's trigger after it — the old fees reset's
   delete, a gateway confirmation — can still meet a desk on that one payment in a circle; PostgreSQL ends one of the two with a deadlock
   error, nothing of it kept; the desk, or the old fees reset or upload, is run again by its door, a confirmation is not.) A payment
   moved to another student or session while the lock was awaited is locked under its new owner too (read again once the lock is held).
   Not a SIWES payment, or none: nothing. */
CREATE FUNCTION finance.siwes_lock_payment(p_payment uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_student uuid; v_session text; v_held text[] := '{}';
BEGIN
    LOOP
        v_student := NULL; v_session := NULL;
        SELECT r.student_id, r.session INTO v_student, v_session FROM finance.payment_reference r
         WHERE r.id = p_payment AND finance.is_siwes_purpose(r.purpose);
        IF v_student IS NULL OR (v_student::text || ' ' || coalesce(v_session, '')) = ANY (v_held) THEN
            RETURN;
        END IF;
        PERFORM finance.siwes_lock(v_student, v_session);   -- the student's row first (FOR KEY SHARE), then the lock
        v_held := v_held || (v_student::text || ' ' || coalesce(v_session, ''));
    END LOOP;
END $$;
COMMENT ON FUNCTION finance.siwes_lock_payment(uuid) IS
  'V762: the student''s SIWES lock (finance.siwes_lock, after the student''s row FOR KEY SHARE) of a SIWES payment, taken by a door that acts on that one payment (the refund desk, the withdrawal as never received, the archive and payment correction desks, an old fees upload re-dating it) before it reads anything of it or locks its row: the registration''s order, its row, its SIWES lock, the payment''s row; read again once held, a payment moved meanwhile locked under its new owner too. Nothing for a payment that is not a SIWES payment.';

-- ── 2 · the refund desk never gives back more than is left on a SIWES payment ──────────────────────────────────────────────────
/* the refund desk's refusal (finance.propose_refund, finance.approve_refund, both under the student's SIWES lock since V762): nothing is
   refunded on the payment a standing SIWES registration was made on — the student would stay registered on money given back; the
   registration is undone first — nor on a payment whose SIWES credit the Bursar recorded refunded (or applied) by hand: that money is spent
   already. The settling of credits takes the other side (finance.siwes_credit_refusal: SIWES_CREDIT_REFUND_DESK), and a refund approved
   settles the credit itself (finance.siwes_refund_follows), so one payment is never given back twice, whichever desk comes first. The fee is
   all or nothing, so a SIWES payment is refunded whole — what is left on it, nothing being refunded on it already but a part approved
   before V752 — never in part (REFUND_SIWES_PART), and never for more than is left (REFUND_SIWES_GIVEN_BACK, V762: two refunds of one
   payment raised at the same moment, the first approved, the second refused). A part refunded would leave the rest held with nothing to
   settle or give it back. An old-portal SIWES payment that waits on the Bursary's bank check (finance.siwes_bank_check: a possible double
   charge not checked, a record of its day found never received and not yet withdrawn, a withdrawal waiting) is not refunded
   (REFUND_SIWES_CHECK_BANK, V561): the settling one as much as the credit, since a refund of either leaves the other settling the fee. */
CREATE OR REPLACE FUNCTION finance.siwes_refund_refusal(p_reference text, p_amount numeric) RETURNS void LANGUAGE plpgsql STABLE AS $$
DECLARE pr finance.payment_reference; v_bank text;
BEGIN
    IF EXISTS (SELECT 1 FROM finance.payment_reference r
                 JOIN registration.siwes_registration x ON r.id IN (x.payment_reference_id, x.legacy_payment_id)
                 JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                WHERE r.reference = upper(btrim(coalesce(p_reference, '')))) THEN
        RAISE EXCEPTION 'REFUND_SIWES_REGISTERED: payment % is the SIWES registration fee a SIWES course stands registered on; nothing is refunded on it while that registration stands',
            upper(btrim(p_reference)) USING ERRCODE = '23514', HINT = 'The Academic Office or ICT Support undoes the SIWES registration first.';
    END IF;
    IF EXISTS (SELECT 1 FROM finance.payment_reference r JOIN finance.siwes_credit c ON c.reference_id = r.id
                WHERE r.reference = upper(btrim(coalesce(p_reference, ''))) AND c.settled_kind = 'HAND_REFUND') THEN
        RAISE EXCEPTION 'REFUND_SIWES_CREDIT_SETTLED: the Bursar recorded the SIWES credit of payment % as refunded; that money is spent and is not refunded again',
            upper(btrim(p_reference)) USING ERRCODE = '23514', HINT = 'The Bursar reopens the credit first if it was recorded in error.';
    END IF;
    SELECT * INTO pr FROM finance.payment_reference r WHERE r.reference = upper(btrim(coalesce(p_reference, '')));
    -- V762: never more than is left on it: what a refund approved or paid on it already gives back is not given back again
    IF pr.id IS NOT NULL AND finance.is_siwes_purpose(pr.purpose) AND p_amount > pr.amount - finance.gst_refunded(pr.reference) THEN
        RAISE EXCEPTION 'REFUND_SIWES_GIVEN_BACK: payment % is a SIWES registration fee of NGN %; NGN % is left on it%, and a refund of NGN % would give back more than was paid',
            pr.reference, pr.amount, pr.amount - finance.gst_refunded(pr.reference),
            coalesce(' (refund ' || (SELECT string_agg(rf.reference, ', ' ORDER BY rf.proposed_at) FROM finance.refund rf
                                      WHERE rf.source_reference = pr.reference AND rf.state IN ('APPROVED', 'PAID')) || ' gave back the rest)', ''),
            p_amount USING ERRCODE = '23514', HINT = 'A SIWES payment is refunded once, whole: reject this refund.';
    END IF;
    IF pr.id IS NOT NULL AND finance.is_siwes_purpose(pr.purpose) THEN
        v_bank := finance.siwes_bank_check(pr.id);
        IF v_bank IS NOT NULL THEN
            RAISE EXCEPTION 'REFUND_SIWES_CHECK_BANK: %', v_bank USING ERRCODE = '23514',
                HINT = 'The Bursary records the bank''s answer on Old Fees History (possible double charges) first.';
        END IF;
    END IF;
    IF pr.id IS NOT NULL AND finance.is_siwes_purpose(pr.purpose) AND p_amount < pr.amount - finance.gst_refunded(pr.reference) THEN
        RAISE EXCEPTION 'REFUND_SIWES_PART: payment % is a SIWES registration fee; the fee is all or nothing, so it is refunded whole (NGN %), never in part (NGN % proposed)',
            pr.reference, pr.amount - finance.gst_refunded(pr.reference), p_amount USING ERRCODE = '23514',
            HINT = 'Raise the refund for the whole payment.';
    END IF;
END $$;
COMMENT ON FUNCTION finance.siwes_refund_refusal(text, numeric) IS
  'V752, V762: the refund desk''s refusals for a SIWES payment, read under the student''s SIWES lock — REFUND_SIWES_REGISTERED (a standing SIWES registration rests on it), REFUND_SIWES_CREDIT_SETTLED (its credit refunded by hand), REFUND_SIWES_GIVEN_BACK (more than is left on it), REFUND_SIWES_CHECK_BANK (V561''s bank check), REFUND_SIWES_PART (less than the whole).';

-- ── 3 · a refund approved on a SIWES payment reads its refusals again under the lock ───────────────────────────────────────────
/* a refund approved (or paid) on the refund desk against a SIWES payment (taken after the student's SIWES lock, as every settling is): read
   again under the lock (V762; the refund desk takes it first, so this is what a door that did not would meet) — a SIWES registration
   standing on the payment (REFUND_SIWES_REGISTERED) or more given back on it than was paid (REFUND_SIWES_GIVEN_BACK) undoes the approval;
   then an open SIWES credit on it — or the record that it settled the fee in another's absence — is the refund's (REFUNDED, 'Refunded on
   the refund desk: <refund>'), so the Bursar is never offered it to refund again nor to reopen — once the whole of it is refunded (the
   desk refunds a SIWES payment whole; a part approved before V752 leaves the credit open, the desk holding it, until the rest is); and when
   the payment refunded settled the fee, the oldest open credit settles it now (finance.siwes_settles_instead) */
CREATE OR REPLACE FUNCTION finance.siwes_refund_follows() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE pr finance.payment_reference;
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.state IN ('APPROVED', 'PAID') THEN RETURN NULL; END IF;   -- paid after approval: followed already
    SELECT * INTO pr FROM finance.payment_reference r WHERE r.reference = NEW.source_reference;
    IF pr.id IS NULL OR pr.student_id IS NULL OR NOT finance.is_siwes_purpose(pr.purpose) THEN RETURN NULL; END IF;
    -- V762: the student's SIWES lock (finance.siwes_lock), the payment read again once it is held
    PERFORM finance.siwes_lock_payment(pr.id);
    SELECT * INTO pr FROM finance.payment_reference r WHERE r.id = pr.id;
    IF pr.student_id IS NULL OR NOT finance.is_siwes_purpose(pr.purpose) THEN RETURN NULL; END IF;
    IF EXISTS (SELECT 1 FROM registration.siwes_registration x
                 JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                WHERE pr.id IN (x.payment_reference_id, x.legacy_payment_id)) THEN
        RAISE EXCEPTION 'REFUND_SIWES_REGISTERED: payment % is the SIWES registration fee a SIWES course stands registered on; refund % is not approved while that registration stands',
            pr.reference, NEW.reference USING ERRCODE = '23514', HINT = 'The Academic Office or ICT Support undoes the SIWES registration first.';
    END IF;
    IF finance.gst_refunded(pr.reference) > pr.amount THEN
        RAISE EXCEPTION 'REFUND_SIWES_GIVEN_BACK: payment % is a SIWES registration fee of NGN %; with refund % NGN % would be given back on it, more than was paid',
            pr.reference, pr.amount, NEW.reference, finance.gst_refunded(pr.reference) USING ERRCODE = '23514',
            HINT = 'A SIWES payment is refunded once, whole: reject this refund.';
    END IF;
    UPDATE finance.siwes_credit c
       SET state = 'REFUNDED', settled_kind = 'DESK_REFUND', settled_at = now(),
           settled_by = coalesce(NEW.approved_by, nullif(current_setting('moaum.actor_id', true), '')::uuid),
           settled_note = 'Refunded on the refund desk: ' || NEW.reference
     WHERE c.reference_id = pr.id AND c.student_id = pr.student_id AND c.session = pr.session
       AND (c.state = 'OPEN' OR c.settled_kind = 'SETTLES')
       AND finance.gst_refunded(pr.reference) >= c.amount;
    PERFORM finance.siwes_settles_instead(pr.student_id, pr.session, pr.reference, 'refunded on the refund desk (' || NEW.reference || ')');
    RETURN NULL;
END $$;

-- ── 4 · an open credit that comes back to stand: the one rule ────────────────────────────────────────────────────────────────────
/* the one rule for a SIWES payment that comes to stand for its student's session — moved back, restored from the archive, confirmed
   again, moved to its true owner, inserted confirmed (the old portal's, loaded by the import or loaded again after the old fees reset),
   or found on record beside another when V752 landed (finance.siwes_credit_second_payments): where another payment already settles the
   fee, it is that student's credit for the Bursary — one it carried before (one row a payment: applied by the move under the student it
   left, or settling in another's absence) is made this student's and open again; where only credits that settled in its absence stand,
   those are open again (it settles once more). A payment that is itself an open credit (restored from the archive, a payment correction
   reversed: V762) is put under the rule all the same: when nothing else settles the fee — the payment that settled it was refunded,
   archived or moved meanwhile — the oldest open credit settles it (finance.siwes_settles_instead), never a fee paid by an open credit the
   Bursar is offered to refund. Never applied twice, never lost. A session not on the calendar holds no SIWES fee and records no credit.
   The payment named as the one that settles is the first confirmed (by its reference when two share a moment, as the import names the
   first of a day by the plain key). */
CREATE OR REPLACE FUNCTION finance.siwes_comes_to_stand(p_payment uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE p finance.payment_reference; v_other record;
BEGIN
    SELECT * INTO p FROM finance.payment_reference WHERE id = p_payment;
    IF p.id IS NULL OR p.student_id IS NULL OR p.confirmed_at IS NULL OR p.archived_at IS NOT NULL OR NOT finance.is_siwes_purpose(p.purpose)
       OR NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p.session) THEN
        RETURN;
    END IF;
    PERFORM finance.siwes_lock(p.student_id, p.session);
    -- not an open credit itself (a refunded one never stands here: finance.siwes_standing)
    IF NOT EXISTS (SELECT 1 FROM finance.siwes_standing(p.student_id, p.session) x WHERE x.reference_id = p.id AND NOT x.open_credit) THEN
        -- V762: an open credit (or a payment that does not stand) came back: when nothing else settles the fee, the oldest open credit does
        PERFORM finance.siwes_settles_instead(p.student_id, p.session, NULL, p.reference || ' came to stand again');
        RETURN;
    END IF;
    SELECT x.reference, x.receipt_no INTO v_other FROM finance.siwes_standing(p.student_id, p.session) x
      LEFT JOIN finance.siwes_credit c ON c.reference_id = x.reference_id
     WHERE x.reference_id <> p.id AND NOT x.open_credit
       AND (x.registered OR c.settled_kind IS DISTINCT FROM 'SETTLES')
     ORDER BY x.registered DESC, x.confirmed_at, x.reference LIMIT 1;
    IF v_other.reference IS NULL THEN
        -- only credits that settled in its absence: open again
        UPDATE finance.siwes_credit c SET state = 'OPEN', settled_kind = NULL, settled_at = NULL, settled_by = NULL, settled_note = NULL
         WHERE c.student_id = p.student_id AND c.session = p.session AND c.reference_id <> p.id AND c.settled_kind = 'SETTLES';
    ELSE
        -- another settles already: this payment is the student's credit
        INSERT INTO finance.siwes_credit (student_id, session, reference_id, amount, reason)
        VALUES (p.student_id, p.session, p.id, p.amount,
                'The SIWES registration fee of ' || p.session || ' was already paid by ' || v_other.reference
                || coalesce(' (receipt ' || v_other.receipt_no || ')', '') || ' when this payment came to stand for it')
        ON CONFLICT (reference_id) DO UPDATE
           SET student_id = EXCLUDED.student_id, session = EXCLUDED.session, amount = EXCLUDED.amount,
               reason = CASE WHEN finance.siwes_credit.student_id = EXCLUDED.student_id AND finance.siwes_credit.session = EXCLUDED.session
                             THEN finance.siwes_credit.reason ELSE EXCLUDED.reason END,
               state = 'OPEN', settled_kind = NULL, settled_at = NULL, settled_by = NULL, settled_note = NULL
         WHERE finance.siwes_credit.settled_kind IN ('SETTLES', 'MOVED');
    END IF;
END $$;
COMMENT ON FUNCTION finance.siwes_comes_to_stand(uuid) IS
  'V752, V762: the one rule for a SIWES payment that comes to stand for its student''s session (the payment triggers and V752''s credit of the second payments already on record call it): another settles the fee — it is the student''s credit; only credits that settled in its absence — they are open again; itself an open credit (restored from the archive, a correction reversed) — when nothing else settles, the oldest open credit settles.';

-- ── 5 · the bank check: the newer of two checks decides; a group it holds keeps its day and its records ─────────────────────────
/* an old-portal record the Bursary's bank check found never received (V561). Two checks can speak of a record: a NOT_RECEIVED check that
   names it (finance.double_charge_check.not_received, whatever day an old fees upload gave the record since) and the check of its current
   Lagos day and amount. The newer decides (V762; at one moment, the one naming it): it names the record never received. A record moved
   before V762 (an upload no longer moves one the bank check holds: finance.siwes_group_kept) is released by a newer check of its new day
   that found it received, and stays found never received by the check naming it until then. It waits to be withdrawn; meanwhile it does
   not stand for the SIWES fee (finance.siwes_standing) and its credit, if any, waits off the credits list. The one test, wherever asked */
CREATE OR REPLACE FUNCTION finance.siwes_found_not_received(p_payment uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT k.verdict = 'NOT_RECEIVED' AND r.reference = ANY (k.not_received)
                       FROM finance.payment_reference r
                       JOIN finance.double_charge_check k
                         ON k.student_id = r.student_id
                        AND ((k.verdict = 'NOT_RECEIVED' AND r.reference = ANY (k.not_received))
                             OR (k.session = r.session AND k.purpose = r.purpose AND k.amount = round(r.amount)
                                 AND k.paid_on = (r.confirmed_at AT TIME ZONE 'Africa/Lagos')::date))
                      WHERE r.id = p_payment AND r.channel = 'Legacy'
                      ORDER BY k.checked_at DESC, (k.verdict = 'NOT_RECEIVED' AND r.reference = ANY (k.not_received)) DESC, k.id
                      LIMIT 1), false);
$$;
COMMENT ON FUNCTION finance.siwes_found_not_received(uuid) IS
  'V752, V762: whether the Bursary''s bank check found an old-portal record never received — of the NOT_RECEIVED check naming it (whatever its day now) and the check of its current day and amount, the newer decides. Such a record does not stand for the SIWES fee until it is withdrawn or found received.';

/* V561's standing rule for the old portal's records: one that may be a bank double charge is never carried or refunded until the
   Bursary has checked it with the bank (finance.check_double_charge). Whether an old-portal SIWES payment waits on the bank, in words
   (NULL: it does not), for every way its money would leave or move — the refund desk (REFUND_SIWES_CHECK_BANK), the Bursar's refund of
   a credit by hand (SIWES_CREDIT_CHECK_BANK, the credits list's bank_check) and the payment correction desk (REALLOC_SIWES_CHECK_BANK):
     · a withdrawal of it, or of another old-portal record of its day and amount, as never received waits for the second officer;
     · the bank check that speaks for it found a record never received that is not yet withdrawn (archived): every SIWES payment of that
       day waits — the one never received settles nothing meanwhile (finance.siwes_standing), and the one received is released only once
       the other is withdrawn (a withdrawal rejected or never raised leaves them waiting);
     · not checked, and V561 lists it (finance.double_charge_group).
   Checked RECEIVED, or every record found never received withdrawn: it waits no more. The check that speaks for a record is the newer
   (V762; at one moment, the one naming it) of a NOT_RECEIVED check that names it, whatever day an old fees upload gave it since, and the
   check of its day, read by the key V561 joins it on (the record's student, session, item, Lagos day and amount): finance
   .siwes_found_not_received's test. Which wait it is comes as a code beside the words, so a screen follows the code, never the words:
   PROPOSED (a withdrawal of a record of its day waits for the second officer), NOT_RECEIVED (the bank check found this very record never
   received: it waits to be withdrawn), NOT_RECEIVED_WAITING (the bank check found another record of its day never received: this one,
   received, waits until that is withdrawn), UNCHECKED (a possible bank double charge not yet checked); both NULL when it does not wait. */
CREATE OR REPLACE FUNCTION finance.siwes_bank_hold(p_payment uuid, OUT state text, OUT words text) LANGUAGE plpgsql STABLE AS $$
DECLARE r finance.payment_reference; v_day date; v_wait text; v_left text[]; v_grp text[]; c finance.double_charge_check;
BEGIN
    SELECT * INTO r FROM finance.payment_reference WHERE id = p_payment;
    IF r.id IS NULL OR r.student_id IS NULL OR r.confirmed_at IS NULL OR r.archived_at IS NOT NULL OR NOT finance.is_siwes_purpose(r.purpose)
       OR r.channel IS DISTINCT FROM 'Legacy' OR r.reference NOT LIKE 'MOAUM-LEG-%' THEN
        RETURN;
    END IF;
    v_day := (r.confirmed_at AT TIME ZONE 'Africa/Lagos')::date;
    -- a withdrawal as never received waiting for the second officer, of this record or another old-portal record of its day and amount
    SELECT string_agg(w.reference, ', ' ORDER BY w.reference) INTO v_wait
      FROM finance.payment_not_received w JOIN finance.payment_reference x ON x.reference = w.reference
     WHERE w.state = 'PROPOSED' AND x.student_id = r.student_id AND x.session = r.session AND x.purpose = r.purpose
       AND x.channel = 'Legacy' AND x.archived_at IS NULL AND (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = v_day AND round(x.amount) = round(r.amount);
    IF v_wait IS NOT NULL THEN
        state := 'PROPOSED';
        words := format('the withdrawal of %s as never received by the bank waits for a second Bursary officer (Payments not received); payment %s is not refunded or moved until it is decided',
                        v_wait, r.reference);
        RETURN;
    END IF;
    -- the bank check that speaks for this record (V762): the newer of a check that names it never received, whatever its day now, and
    -- the check of its day; at one moment, the one naming it
    SELECT * INTO c FROM finance.double_charge_check k
     WHERE k.student_id = r.student_id
       AND ((k.verdict = 'NOT_RECEIVED' AND r.reference = ANY (k.not_received))
            OR (k.session = r.session AND k.purpose = r.purpose AND k.paid_on = v_day AND k.amount = round(r.amount)))
     ORDER BY k.checked_at DESC, (k.verdict = 'NOT_RECEIVED' AND r.reference = ANY (k.not_received)) DESC, k.id
     LIMIT 1;
    IF c.id IS NOT NULL THEN
        IF c.verdict = 'NOT_RECEIVED' THEN
            -- the records the bank never received that still stand (not withdrawn) and are found so still (V762: not released by a
            -- newer check of a day an upload gave one before V762): the whole day waits on them
            SELECT array_agg(x.reference ORDER BY x.reference) INTO v_left FROM finance.payment_reference x
             WHERE x.reference = ANY (c.not_received) AND x.archived_at IS NULL AND finance.siwes_found_not_received(x.id);
            IF v_left IS NOT NULL THEN
                state := CASE WHEN r.reference = ANY (v_left) THEN 'NOT_RECEIVED' ELSE 'NOT_RECEIVED_WAITING' END;
                words := format('the bank check of %s (Old Fees History, possible double charges) found payment %s never received; until it is withdrawn (Payments not received), payment %s is not refunded or moved',
                                to_char(c.checked_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY'), array_to_string(v_left, ', '), r.reference);
            END IF;
        END IF;
        RETURN;
    END IF;
    -- not checked: a possible double charge as V561 lists it
    v_grp := finance.double_charge_group(r.id);
    IF v_grp IS NULL THEN RETURN; END IF;
    state := 'UNCHECKED';
    words := format('payment %s may be a bank double charge: %s, of the same day (%s) and amount, is under another payment number; check them with the bank first (Old Fees History, possible double charges)',
                    r.reference, array_to_string(array_remove(v_grp, r.reference), ', '), to_char(v_day, 'DD Mon YYYY'));
END $$;
COMMENT ON FUNCTION finance.siwes_bank_hold(uuid) IS
  'V752, V762: whether an old-portal SIWES payment waits on the Bursary''s bank check (V561), as a code — PROPOSED, NOT_RECEIVED (this record found never received), NOT_RECEIVED_WAITING (another record of its day found never received), UNCHECKED — and in words; both NULL when it does not wait. Of the check naming the record and the check of its day, the newer speaks.';

/* an old-portal SIWES record the Bursary's bank check holds together with its day's group (V561): a record a NOT_RECEIVED check names
   (whatever check of its day came since); a record of the day and amount of a NOT_RECEIVED check whose record never received is not yet
   withdrawn; or a record of a day and amount with a withdrawal as never received waiting for the second officer or rejected (of it or
   another record of that day). The check and the withdrawal name such records by their reference and day, so an old fees upload keeps
   the record's day (finance.import_legacy_payments, as it keeps an archived record's) and the old fees reset keeps the record
   (finance.reset_legacy_payments): the group stays together under the references and the day the check and the withdrawal name, the
   record received stays held while its partner waits, V561's check of that day can be recorded again, and a waiting withdrawal can be
   decided. A record withdrawn (archived) keeps its day and stays anyway. */
CREATE FUNCTION finance.siwes_group_kept(p_payment uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM finance.payment_reference r
         WHERE r.id = p_payment AND r.channel = 'Legacy' AND r.reference LIKE 'MOAUM-LEG-%' AND r.archived_at IS NULL AND r.student_id IS NOT NULL
           AND finance.is_siwes_purpose(r.purpose)
           AND (EXISTS (SELECT 1 FROM finance.double_charge_check k
                         WHERE k.student_id = r.student_id AND k.verdict = 'NOT_RECEIVED' AND r.reference = ANY (k.not_received))
                OR EXISTS (SELECT 1 FROM finance.double_charge_check k
                            WHERE k.student_id = r.student_id AND k.session = r.session AND k.purpose = r.purpose AND k.amount = round(r.amount)
                              AND k.paid_on = (r.confirmed_at AT TIME ZONE 'Africa/Lagos')::date AND k.verdict = 'NOT_RECEIVED'
                              AND EXISTS (SELECT 1 FROM finance.payment_reference y WHERE y.reference = ANY (k.not_received) AND y.archived_at IS NULL))
                OR EXISTS (SELECT 1 FROM finance.payment_not_received w JOIN finance.payment_reference x ON x.reference = w.reference
                            WHERE w.student_id = r.student_id AND w.session = r.session AND w.state IN ('PROPOSED', 'REJECTED')
                              AND x.student_id = r.student_id AND x.session = r.session AND x.purpose = r.purpose AND x.channel = 'Legacy'
                              AND x.archived_at IS NULL
                              AND (x.id = r.id OR (round(x.amount) = round(r.amount)
                                                   AND (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (r.confirmed_at AT TIME ZONE 'Africa/Lagos')::date)))));
$$;
COMMENT ON FUNCTION finance.siwes_group_kept(uuid) IS
  'V762: an old-portal SIWES record the Bursary''s bank check holds with its day''s group — named by a NOT_RECEIVED check, of the day of a NOT_RECEIVED check whose record never received is not yet withdrawn, or of a day with a withdrawal as never received waiting or rejected. An old fees upload keeps its day and the old fees reset keeps the record.';

-- ── 6 · the doors restated by anchor: the lock first (refund desk, withdrawal, archive, correction, bank check, bank list); the upload;
--        the reset
CREATE FUNCTION pg_temp.v762_once(p_def text, p_anchor text, p_what text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_anchor IS NULL OR length(p_anchor) = 0 OR (length(p_def) - length(replace(p_def, p_anchor, ''))) / length(p_anchor) <> 1 THEN
        RAISE EXCEPTION 'V762: % is not as it was left (an anchor is not there exactly once)', p_what;
    END IF;
END $$;

DO $v762$
DECLARE d text; a text; a2 text; b1 text; b2 text; lk text; nl text := E'\n';
BEGIN
    -- the refund desk (d7-3, d7-4): a refund raised on a SIWES payment waits on the student's SIWES lock before anything of the payment
    -- is read, so a second one raised at the same moment sees the first (REFUND_SIWES_GIVEN_BACK) and a SIWES registration or a hand
    -- refund made at the same moment is seen (REFUND_SIWES_REGISTERED, REFUND_SIWES_CREDIT_SETTLED)
    d := pg_get_functiondef('finance.propose_refund(uuid,text,text,numeric,text,text,text,text)'::regprocedure);
    a := $a$    v_src := nullif(upper(btrim(coalesce(p_source, ''))), '');$a$;
    a2 := $a$        IF p_amount + v_raised > st.amount THEN$a$;
    PERFORM pg_temp.v762_once(d, a, 'finance.propose_refund');
    PERFORM pg_temp.v762_once(d, a2, 'finance.propose_refund');
    PERFORM pg_temp.v762_once(d, $a$        PERFORM finance.siwes_refund_refusal(v_src, p_amount);$a$, 'finance.propose_refund (V752)');
    d := replace(d, a, a || $r$
    -- V762: a SIWES payment is decided one at a time: the student's SIWES lock (finance.siwes_lock_payment) before anything of it is read,
    -- so a second refund raised at the same moment waits for the first and sees it, as it sees a hand refund of its credit or a SIWES
    -- registration made on it meanwhile
    PERFORM finance.siwes_lock_payment((SELECT x.id FROM finance.payment_reference x WHERE x.reference = v_src));$r$);
    d := replace(d, a2, $r$        -- V762: a SIWES payment is refunded once, whole: a refund raised on it and not rejected stands for it already
        IF p_amount + v_raised > st.amount AND EXISTS (SELECT 1 FROM finance.payment_reference x WHERE x.reference = v_src AND finance.is_siwes_purpose(x.purpose)) THEN
            RAISE EXCEPTION 'REFUND_SIWES_GIVEN_BACK: payment % is a SIWES registration fee of NGN %; refund % stands raised on it for NGN %, and a SIWES payment is refunded once, whole',
                v_src, st.amount, (SELECT string_agg(f.reference, ', ' ORDER BY f.proposed_at) FROM finance.refund f WHERE f.source_reference = v_src AND f.state <> 'REJECTED'),
                v_raised USING ERRCODE = '23514', HINT = 'Approve or reject the refund raised on the refund desk; a second is not raised beside it.';
        END IF;
$r$ || a2);
    EXECUTE d;

    -- approved: the lock first, then the refund's row and every refusal (a second approval of the payment sees the first)
    d := pg_get_functiondef('finance.approve_refund(uuid)'::regprocedure);
    a := $a$    SELECT * INTO r FROM finance.refund WHERE id = p_id FOR UPDATE;$a$;
    PERFORM pg_temp.v762_once(d, a, 'finance.approve_refund');
    PERFORM pg_temp.v762_once(d, $a$    PERFORM finance.siwes_refund_refusal(r.source_reference, r.amount);   -- V752$a$, 'finance.approve_refund (V752)');
    d := replace(d, a, $r$    -- V762: the student's SIWES lock of the payment it refunds (finance.siwes_lock_payment), taken before anything is read: a second
    -- approval on that payment waits for the first and sees it (REFUND_SIWES_GIVEN_BACK), and a SIWES registration made on it at the same
    -- moment is seen (REFUND_SIWES_REGISTERED)
    PERFORM finance.siwes_lock_payment((SELECT x.id FROM finance.refund f JOIN finance.payment_reference x ON x.reference = f.source_reference WHERE f.id = p_id));
$r$ || a);
    EXECUTE d;

    -- the withdrawal of a record as never received (d7-4, V561), raised and decided: the lock before the payment's row and its refusal
    -- (PAY_NOT_RECEIVED_SIWES_REGISTERED: a SIWES registration made on it at the same moment is seen)
    d := pg_get_functiondef('finance.propose_not_received(text,text,text,uuid,text)'::regprocedure);
    a := $a$    SELECT * INTO r FROM finance.payment_reference WHERE reference = upper(btrim(p_reference)) FOR UPDATE;$a$;
    PERFORM pg_temp.v762_once(d, a, 'finance.propose_not_received');
    PERFORM pg_temp.v762_once(d, a || nl || $a$    PERFORM finance.raise_not_received(finance.not_received_refusal(r.id));$a$, 'finance.propose_not_received');
    d := replace(d, a, $r$    -- V762: the student's SIWES lock of a SIWES record (finance.siwes_lock_payment) before its row is locked and its refusal read
    PERFORM finance.siwes_lock_payment((SELECT x.id FROM finance.payment_reference x WHERE x.reference = upper(btrim(p_reference))));
$r$ || a);
    EXECUTE d;
    d := pg_get_functiondef('finance.decide_not_received(text,boolean,text)'::regprocedure);
    a := $a$    SELECT * INTO r FROM finance.payment_reference WHERE id = q.payment_id FOR UPDATE;$a$;
    PERFORM pg_temp.v762_once(d, a, 'finance.decide_not_received');
    PERFORM pg_temp.v762_once(d, a || nl || $a$    PERFORM finance.raise_not_received(finance.not_received_refusal(r.id));$a$, 'finance.decide_not_received');
    d := replace(d, a, $r$    -- V762: the student's SIWES lock of a SIWES record (finance.siwes_lock_payment) before its row is locked and its refusal read
    PERFORM finance.siwes_lock_payment(q.payment_id);
$r$ || a);
    EXECUTE d;

    -- the archive desk and the payment correction desk: the same lock before the payment's row, so the desks that act on one SIWES payment
    -- take their locks in one order (the student's SIWES lock, then the row) and never wait on each other in a circle
    d := pg_get_functiondef('finance.archive_payment(uuid,text,uuid,text,boolean)'::regprocedure);
    a := $a$    SELECT * INTO r FROM finance.payment_reference WHERE id = p_payment FOR UPDATE;   -- one archiving of a payment at a time$a$;
    PERFORM pg_temp.v762_once(d, a, 'finance.archive_payment');
    d := replace(d, a, $r$    PERFORM finance.siwes_lock_payment(p_payment);   -- V762: a SIWES payment's student SIWES lock before its row
$r$ || a);
    EXECUTE d;
    d := pg_get_functiondef('finance.payment_archive_decide(uuid,text,text,boolean)'::regprocedure);
    a := $a$    SELECT * INTO r FROM finance.payment_reference WHERE id = a.payment_id FOR UPDATE;$a$;
    PERFORM pg_temp.v762_once(d, a, 'finance.payment_archive_decide');
    d := replace(d, a, $r$    PERFORM finance.siwes_lock_payment(a.payment_id);   -- V762: a SIWES payment's student SIWES lock before its row
$r$ || a);
    EXECUTE d;
    d := pg_get_functiondef('finance.decide_payment_reallocation(uuid,text,text,boolean)'::regprocedure);
    a := $a$    SELECT * INTO r FROM finance.payment_reference WHERE id = x.payment_id FOR UPDATE;$a$;
    PERFORM pg_temp.v762_once(d, a, 'finance.decide_payment_reallocation');
    d := replace(d, a, $r$    PERFORM finance.siwes_lock_payment(x.payment_id);   -- V762: a SIWES payment's student SIWES lock before its row
$r$ || a);
    EXECUTE d;

    -- the bank check of a possible double charge (d62-2, V561): a SIWES item is checked under the student's SIWES lock, taken before the
    -- possible double charges are read, so an old fees upload re-dating one of its records (which takes the same lock) and the check are
    -- decided one after the other
    d := pg_get_functiondef('finance.check_double_charge(uuid,text,text,date,numeric,text,text,text,text[])'::regprocedure);
    a := $a$    SELECT * INTO d FROM finance.possible_double_charges(p_session) g$a$ || nl
         || $a$     WHERE g.student_id = p_student AND g.purpose = p_purpose AND g.paid_on = p_paid_on AND g.amount = round(p_amount);$a$;
    PERFORM pg_temp.v762_once(d, a, 'finance.check_double_charge');
    d := replace(d, a, $r$    -- V762: a SIWES item is checked under the student's SIWES lock (finance.siwes_lock: the student's row, then the lock) of each
    -- session its records stand under, taken before the possible double charges are read: an old fees upload re-dating one of its records
    -- takes the same lock, so the check sees the record on its new day, or the upload sees the check and keeps the record's day
    IF finance.is_siwes_purpose(p_purpose) THEN
        PERFORM finance.siwes_lock(p_student, v762s.session)
           FROM (SELECT DISTINCT r.session FROM finance.payment_reference r
                  WHERE r.student_id = p_student AND r.purpose = p_purpose AND (p_session IS NULL OR r.session = p_session)) v762s
          ORDER BY v762s.session;
    END IF;
$r$ || a);
    EXECUTE d;

    -- the Bursary's bank list (V684; the review of V762, d62b-1 and d62b-2): a SIWES group the list acts on is read under its student's
    -- SIWES lock, the locks taken first in one order (the student, then the session); a deadlock, a serialization failure or a lock not
    -- had in time inside its loop ends the whole list, nothing of it kept (its door runs it again), never a group recorded refused for it
    d := pg_get_functiondef('finance.bank_list_apply(text,date,date,jsonb,text,text,text,integer)'::regprocedure);
    a := $a$        v_recorded int := 0; v_raised_n int := 0; v_raised_amount numeric := 0;$a$;
    a2 := $a$    FOR g IN SELECT * FROM finance.bank_list_match(v_ses, p_from, p_to, p_numbers) m ORDER BY m.name, m.paid_on, m.purpose LOOP$a$;
    b1 := $a$            EXCEPTION WHEN OTHERS THEN$a$ || nl
          || $a$                -- V561 refuses the withdrawal (several payments in one record, linked, swapped, the excess decided): the group is left$a$;
    PERFORM pg_temp.v762_once(d, a, 'finance.bank_list_apply');
    PERFORM pg_temp.v762_once(d, a2, 'finance.bank_list_apply');
    PERFORM pg_temp.v762_once(d, b1, 'finance.bank_list_apply');
    d := replace(d, a, a || nl || $r$        v762_rows jsonb; v762_held text[] := '{}'; v762_more boolean; v762_l record;   -- V762$r$);
    d := replace(d, a2, $r$    -- V762 (its review, d62b-1): a SIWES group the list acts on (RECEIVED, NOT_RECEIVED) is read under its student's SIWES lock
    -- (finance.siwes_lock: the student's row, then the lock). An old fees upload re-dating one of its records takes the same lock before it
    -- decides the record's day, so it comes wholly before the read or wholly after the list: the list sees the record on its new day, or
    -- the upload sees the list's check and keeps the day. The locks are taken before the read, in one order (the student, then the
    -- session): first those of every student with two old-portal SIWES records of one session, item, day and amount in the list's days
    -- (every SIWES possible double charge the list can judge, and maybe a few more); then, should the read find a SIWES group to act on
    -- whose lock was not held before it (a record re-dated into those days meanwhile), its lock is taken and the list read again. The
    -- list acts on its last read, every SIWES group of which was read under its lock.
    FOR v762_l IN SELECT DISTINCT px.student_id, px.session
                    FROM (SELECT pr.student_id, pr.session FROM finance.payment_reference pr
                           WHERE pr.channel = 'Legacy' AND pr.reference LIKE 'MOAUM-LEG-%' AND pr.confirmed_at IS NOT NULL AND pr.archived_at IS NULL
                             AND pr.student_id IS NOT NULL AND finance.is_siwes_purpose(pr.purpose) AND (v_ses IS NULL OR pr.session = v_ses)
                             AND (pr.confirmed_at AT TIME ZONE 'Africa/Lagos')::date BETWEEN p_from AND p_to
                           GROUP BY pr.student_id, pr.session, pr.purpose, (pr.confirmed_at AT TIME ZONE 'Africa/Lagos')::date, round(pr.amount)
                          HAVING count(*) >= 2) px
                   ORDER BY px.student_id, px.session LOOP
        PERFORM finance.siwes_lock(v762_l.student_id, v762_l.session);
        v762_held := v762_held || (v762_l.student_id::text || ' ' || coalesce(v762_l.session, ''));
    END LOOP;
    LOOP
        v762_rows := (SELECT jsonb_agg(to_jsonb(m) ORDER BY m.name, m.paid_on, m.purpose) FROM finance.bank_list_match(v_ses, p_from, p_to, p_numbers) m);
        v762_more := false;
        FOR v762_l IN SELECT DISTINCT m.student_id, m.session
                        FROM jsonb_to_recordset(coalesce(v762_rows, '[]'::jsonb)) AS m(student_id uuid, session text, purpose text, outcome text)
                       WHERE m.outcome IN ('RECEIVED', 'NOT_RECEIVED') AND finance.is_siwes_purpose(m.purpose)
                         AND NOT ((m.student_id::text || ' ' || coalesce(m.session, '')) = ANY (v762_held))
                       ORDER BY m.student_id, m.session LOOP
            PERFORM finance.siwes_lock(v762_l.student_id, v762_l.session);
            v762_held := v762_held || (v762_l.student_id::text || ' ' || coalesce(v762_l.session, ''));
            v762_more := true;
        END LOOP;
        EXIT WHEN NOT v762_more;
    END LOOP;
    FOR g IN SELECT m.* FROM jsonb_array_elements(coalesce(v762_rows, '[]'::jsonb)) WITH ORDINALITY AS e(j, n)
               CROSS JOIN LATERAL jsonb_to_record(e.j) AS m(student_id uuid, number text, name text, programme_code text, session text, purpose text,
                                                         paid_on date, amount numeric, payments integer, refs text[], payrefs text[], outcome text,
                                                         found text[], missing text[])
              ORDER BY e.n LOOP$r$);
    d := replace(d, b1, $r$            EXCEPTION WHEN deadlock_detected OR serialization_failure OR lock_not_available THEN
                -- V762 (its review, d62b-2): a passing clash ends the whole list, nothing of it kept, and its door runs it again
                -- (DeadlockRetry): no group is recorded refused for it
                RAISE;
            WHEN OTHERS THEN$r$ || nl
          || $a$                -- V561 refuses the withdrawal (several payments in one record, linked, swapped, the excess decided): the group is left$a$);
    EXECUTE d;

    -- the decision of the withdrawals a list raised: every one that still waits locked first, in their numbers' order (the order each
    -- withdrawal's own decision and cancellation take one: its row, its student's SIWES lock, the payment's row); then, whatever the
    -- decision is (an approval, a rejection, a cancellation), their students' SIWES locks in the list's order (each withdrawal's own
    -- decision or cancellation takes its lock again, already held); a passing clash ends the whole decision
    d := pg_get_functiondef('finance.decide_bank_list(text,text,text)'::regprocedure);
    a := $a$        v_note text := nullif(btrim(coalesce(p_note, '')), ''); w record; nd int := 0; nr int := 0; v_refusals text[] := '{}';$a$;
    a2 := $a$    FOR w IN SELECT q.request_ref FROM finance.payment_not_received q$a$;
    b1 := $a$        EXCEPTION WHEN OTHERS THEN$a$ || nl || $a$            nr := nr + 1;$a$;
    PERFORM pg_temp.v762_once(d, a, 'finance.decide_bank_list');
    PERFORM pg_temp.v762_once(d, a2, 'finance.decide_bank_list');
    PERFORM pg_temp.v762_once(d, b1, 'finance.decide_bank_list');
    d := replace(d, a, a || nl || $r$        v762_l record;   -- V762$r$);
    d := replace(d, a2, $r$    -- V762 (its third review, d62c-1): the rows of the withdrawals the list raised that still wait, all locked first, in their numbers'
    -- order (the order the loop below decides them). A withdrawal decided or cancelled alone (finance.decide_not_received,
    -- finance.cancel_not_received) locks its row before its student's SIWES lock (an approval in finance.siwes_lock_payment; a rejection or
    -- a cancellation in the withdrawal's trigger, finance.siwes_bank_check_follows), so the list takes them in that order too: it never
    -- holds a SIWES lock while it waits on a withdrawal's row that such a decision holds while it waits on that lock
    PERFORM 1 FROM finance.payment_not_received q
      WHERE q.state = 'PROPOSED' AND q.request_ref IN (SELECT unnest(g.raised) FROM finance.bank_list_group g WHERE g.list_id = l.id)
      ORDER BY q.request_ref FOR UPDATE OF q;
    -- V762 (its review, d62b-1; its fourth, d62d-1): the withdrawals of SIWES records are decided under their students' SIWES locks
    -- (finance.siwes_lock), all taken next, whatever the decision is, before any withdrawal is decided, in the order the list takes them
    -- when it is recorded (the student, then the session): the lock of each withdrawal's own student and session, which its trigger
    -- (finance.siwes_bank_check_follows) takes as it is approved, rejected or cancelled, and that of its payment's, which an approval
    -- takes (finance.siwes_lock_payment) — the same lock unless the payment was moved since the withdrawal was raised. Two bank-list
    -- operations over the same students (a list recorded, its withdrawals decided) take those locks in one order
    FOR v762_l IN SELECT DISTINCT x.student_id, x.session
                    FROM finance.payment_not_received q LEFT JOIN finance.payment_reference pr ON pr.id = q.payment_id
                   CROSS JOIN LATERAL (VALUES (q.student_id, q.session, q.purpose), (pr.student_id, pr.session, pr.purpose)) AS x (student_id, session, purpose)
                   WHERE q.state = 'PROPOSED' AND q.request_ref IN (SELECT unnest(g.raised) FROM finance.bank_list_group g WHERE g.list_id = l.id)
                     AND x.student_id IS NOT NULL AND finance.is_siwes_purpose(x.purpose)
                   ORDER BY x.student_id, x.session LOOP
        PERFORM finance.siwes_lock(v762_l.student_id, v762_l.session);
    END LOOP;
$r$ || a2);
    d := replace(d, b1, $r$        EXCEPTION WHEN deadlock_detected OR serialization_failure OR lock_not_available THEN
            -- V762 (its review, d62b-2): a passing clash ends the whole decision, nothing of it kept, and its door runs it again
            -- (DeadlockRetry): no withdrawal is recorded refused for it
            RAISE;
        WHEN OTHERS THEN$r$ || nl || $a$            nr := nr + 1;$a$);
    EXECUTE d;

    -- the old fees upload (d7-2, the live finding): an old-portal SIWES record the bank check holds with its day's group
    -- (finance.siwes_group_kept) keeps its day in both re-dating branches, as an archived record keeps it (V670). With a payment number
    -- the number is attached (matched); without, the row is already on record (reported among the duplicates). d62-2: in each branch
    -- the record's student's SIWES lock (finance.siwes_lock_payment) is taken before its day is decided — before its payment number is
    -- attached, whose key locks the record's row — and the record is read again under it: a bank check of its day comes wholly before
    -- or wholly after
    d := pg_get_functiondef('finance.import_legacy_payments(jsonb)'::regprocedure);
    a := $a$                IF ex.archived_at IS NOT NULL THEN$a$ || nl
         || $a$                    NULL;   -- V670: an archived record keeps its day and note; its number is known now$a$;
    a2 := $a$                IF ex.channel = 'Legacy' AND ex.archived_at IS NULL AND v_given IS NOT NULL AND ex.confirmed_at IS DISTINCT FROM v_given$a$ || nl
          || $a$                   AND (v_amount IS NULL OR v_amount = ex.amount) THEN$a$;
    PERFORM pg_temp.v762_once(d, a, 'finance.import_legacy_payments');
    PERFORM pg_temp.v762_once(d, a2, 'finance.import_legacy_payments');
    b1 := $a$            IF ex.id IS NOT NULL THEN$a$ || nl
          || $a$                INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, ex.reference, coalesce(v_amount, ex.amount));$a$;
    b2 := $a$            IF ex.id IS NOT NULL THEN$a$ || nl || a2;
    PERFORM pg_temp.v762_once(d, b1, 'finance.import_legacy_payments (the payment number attached)');
    PERFORM pg_temp.v762_once(d, b2, 'finance.import_legacy_payments (already on record)');
    lk := $r$            IF ex.id IS NOT NULL AND finance.is_siwes_purpose(ex.purpose) THEN
                -- V762: an old-portal SIWES record's day is decided under its student's SIWES lock (the student's row, then the lock),
                -- the record read again once it is held (gone meanwhile: as if never found)
                PERFORM finance.siwes_lock_payment(ex.id);
                SELECT * INTO ex FROM finance.payment_reference WHERE id = ex.id;
            END IF;
$r$;
    d := replace(d, b1, lk || b1);
    d := replace(d, b2, lk || b2);
    d := replace(d, a, a || nl || $r$                ELSIF finance.is_siwes_purpose(ex.purpose) AND finance.siwes_group_kept(ex.id) THEN
                    -- V762: an old-portal SIWES record the bank check holds with its day's group keeps its day (the check and the
                    -- withdrawal name it there); its number is known now
                    IF ex.note NOT LIKE '%old ref %' THEN UPDATE finance.payment_reference SET note = v_note WHERE id = ex.id; END IF;$r$);
    d := replace(d, a2, $r$                IF ex.channel = 'Legacy' AND ex.archived_at IS NULL AND v_given IS NOT NULL AND ex.confirmed_at IS DISTINCT FROM v_given
                   AND (v_amount IS NULL OR v_amount = ex.amount)
                   AND NOT finance.siwes_group_kept(ex.id) THEN   -- V762: one the bank check holds with its day's group keeps its day$r$);
    EXECUTE d;

    -- the old fees reset (d7-5): an old-portal SIWES record the bank check holds with its day's group stays, in the batch and in the count
    -- of those kept, as one whose SIWES credit the Bursar refunded by hand does (V752): a reload never gives another payment of the day the
    -- reference the check or the withdrawal names, and a withdrawal waiting can still be decided
    d := pg_get_functiondef('finance.reset_legacy_payments(text,text,integer)'::regprocedure);
    a := $a$                   AND NOT EXISTS (SELECT 1 FROM finance.siwes_credit sc WHERE sc.reference_id = r.id AND sc.settled_kind = 'HAND_REFUND')$a$;
    a2 := $a$                    OR r.id IN (SELECT sc.reference_id FROM finance.siwes_credit sc WHERE sc.settled_kind = 'HAND_REFUND')) AS linked   -- V752$a$;
    PERFORM pg_temp.v762_once(d, a, 'finance.reset_legacy_payments');
    PERFORM pg_temp.v762_once(d, a2, 'finance.reset_legacy_payments');
    d := replace(d, a, a || $r$
                   -- V762: an old-portal SIWES record the bank check holds with its day's group stays
                   AND NOT (finance.is_siwes_purpose(r.purpose) AND finance.siwes_group_kept(r.id))$r$);
    d := replace(d, a2, $r$                    OR r.id IN (SELECT sc.reference_id FROM finance.siwes_credit sc WHERE sc.settled_kind = 'HAND_REFUND')   -- V752
                    OR (finance.is_siwes_purpose(r.purpose) AND finance.siwes_group_kept(r.id))) AS linked   -- V762$r$);
    EXECUTE d;
END $v762$;

COMMIT;
