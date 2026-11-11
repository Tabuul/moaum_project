-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V726 · Legacy school-fee payment duplicates on all six fields, permanently deleted on deployment
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's brief of 11 November 2026, "AUTOMATIC LEGACY SCHOOL FEES PAYMENT DUPLICATE DETECTION AND PERMANENT DELETION ON
--  DEPLOYMENT": a legacy school-fee payment record is a duplicate of another only when all six match — the payment reference number,
--  the payment date, the student's matriculation number, the academic level, the semester and the academic session. One record of
--  each group is kept; the others are deleted for good (no archive, no hiding), automatically when this file is applied, and the run
--  is recorded with actual counts.
--
--  The six fields, on the model as it stands:
--    1 the payment reference number — the old portal's payment number (payref): held in finance.legacy_payref (its key: one record
--      at most), and written at the end of each record's note (' · old ref <number>'), where a second record of the same payment
--      carries it; compared upper-cased and trimmed, as the importer stores it;
--    2 the payment date — the Lagos day of confirmed_at (the day the old portal's file gives; every earlier tool reads it so);
--    3 the matriculation number — the student the record belongs to (student_id → people.student.matric_no), never the number
--      written inside the reference; two records of one student match, two student records sharing a number do not;
--    4 the academic level — people.receipt_level(student, session): no legacy payment stores a level, so it is the student's level
--      in that session, and it follows from 3 and 6;
--    5 the semester — from the purpose ('School fees (legacy) · semester n'); a whole-session record matches only a whole-session one;
--    6 the session — payment_reference.session.
--
--  The scope (legacy-imported school-fee records alone): channel 'Legacy', a reference 'MOAUM-LEG-…' (not 'MOAUM-LEG-GST-…'),
--  confirmed, and the purpose 'School fees (legacy)' or 'School fees (legacy) · semester 1–3' — never a portal or gateway payment,
--  an acceptance, application, GST/EPS, outstanding-fees, hostel or any other item.
--
--  Kept, of each group (deterministically): the record with VERIFIED payment evidence (V683); else the record the number is linked
--  to in finance.legacy_payref; else the record posted to the ledger; else the record with an identity (V647); else the earliest
--  imported (generated_at), then the lowest reference, then the lowest id.
--
--  A group is left whole and reported (never guessed) when: its amounts differ; a record is archived (V670) or under review; VERIFIED
--  evidence names two of its records, or evidence names one to be deleted; a record to be deleted carries another payment number, or
--  belongs to another group; a record is tied to a deferment fee, the GST reconciliation, a refund, a swap, a reallocation, an
--  outstanding-fees credit or an archived payment; the student and session have an overpayment decision, a credit request, a
--  double-charge check or a bank-list outcome; or a record to be deleted was paid from the old e-wallet whose balance has been
--  verified, posted, frozen or rejected.
--
--  For each record deleted: its ledger journal moves to the kept record when that one has none, or is reversed and let go
--  (finance.gl_free_payment, as V498 does) when both were posted; the group's payment number is sealed on the kept record in
--  finance.legacy_payref, so a re-upload is refused as "already on record"; an identity (V647) or held row (V647) moves to the kept
--  record; then the record is deleted. Afterwards the students' historical-fees summaries are marked stale and an old e-wallet
--  touched is worked out again. Checks then hold the result: every planned record deleted and only those, each group down to its
--  kept record, each student's paid total for the session lower by exactly the deleted records' amounts, every number sealed on the
--  kept record, no ledger journal left naming a deleted record, no identity left on one, no group left that could be deleted. If any
--  check fails, nothing is changed (the work is undone) and the run is recorded FAILED with the reason: the deployment goes on, the
--  data stays as it was, and the run says so.
--
--  The run is recorded in finance.legacy_fee_duplicate_run: when, on which database, how many records were inspected, how many
--  groups found, kept, deleted and skipped (by reason), the amount, the students, the ledger and number work, each check, the status
--  and any error — counts only, no copy of a deleted payment. The audit trail (audit.entries) records each delete as it records every
--  change to a payment (V002: "nothing is deleted from the record of what was done"); that trail is the University's evidence of who
--  changed what, not an archive of payments: the records are gone from every payment table, statement, report and figure.
--
--  Prevention: every route that writes a legacy school-fee record goes through finance.import_legacy_payments, which refuses a number
--  already held in finance.legacy_payref; a second record of the same payment arose where the number was held only in a note. A
--  BEFORE INSERT trigger (trg_pref_legacy_fee_once) now refuses, quietly, a legacy school-fee record whose number, day, student,
--  semester and session match one on record — the importer then counts it among those already on record — and never one that
--  differs in level, semester or session. A unique index is not used: a group left whole for the Bursary would stop it being built.
--
--  Applied once by db/migrate.sh on each database (Railway, AWS); a later deployment finds nothing more to delete. The function stays
--  for a later migration to run again, and the Bursary reads the run and any group left whole on Old Fees History.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V726: legacy school-fee payment duplicates on all six fields permanently deleted on deployment', true);

-- ── 1 · the run record ──────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.legacy_fee_duplicate_run (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_ref          text NOT NULL UNIQUE,
    run_by           text NOT NULL,
    database_name    text NOT NULL DEFAULT current_database(),
    started_at       timestamptz NOT NULL,
    finished_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
    status           text NOT NULL CHECK (status IN ('DELETED', 'NOTHING_TO_DELETE', 'FAILED')),
    inspected        integer NOT NULL DEFAULT 0 CHECK (inspected >= 0),
    groups_found     integer NOT NULL DEFAULT 0 CHECK (groups_found >= 0),
    groups_cleaned   integer NOT NULL DEFAULT 0 CHECK (groups_cleaned >= 0),
    retained         integer NOT NULL DEFAULT 0 CHECK (retained >= 0),
    deleted          integer NOT NULL DEFAULT 0 CHECK (deleted >= 0),
    groups_skipped   integer NOT NULL DEFAULT 0 CHECK (groups_skipped >= 0),
    records_skipped  integer NOT NULL DEFAULT 0 CHECK (records_skipped >= 0),
    skipped_by_reason jsonb NOT NULL DEFAULT '{}'::jsonb,
    amount_deleted   numeric(16, 2) NOT NULL DEFAULT 0,
    students         integer NOT NULL DEFAULT 0,
    numbers_sealed   integer NOT NULL DEFAULT 0,
    ledger_moved     integer NOT NULL DEFAULT 0,
    ledger_released  integer NOT NULL DEFAULT 0,
    identities_moved integer NOT NULL DEFAULT 0,
    receipts_voided  integer NOT NULL DEFAULT 0,
    reconciliation   text NOT NULL CHECK (reconciliation IN ('PASSED', 'FAILED', 'NOT_RUN')),
    integrity        text NOT NULL CHECK (integrity IN ('PASSED', 'FAILED', 'NOT_RUN')),
    checks           jsonb NOT NULL DEFAULT '{}'::jsonb,
    error            text NULL,
    CONSTRAINT ck_ldr_deleted CHECK (status <> 'DELETED' OR deleted > 0),
    CONSTRAINT ck_ldr_failed CHECK ((status = 'FAILED') = (error IS NOT NULL))
);
COMMENT ON TABLE finance.legacy_fee_duplicate_run IS
  'V726: each run of the legacy school-fee duplicate cleanup (finance.legacy_fee_duplicates_remove) — when, on which database, the records inspected, the six-field groups found, kept, deleted and left whole (by reason), the amount, the students, the ledger and payment-number work, each integrity and reconciliation check, the status and any error. Counts only: no copy of a deleted payment.';
CREATE INDEX ix_ldr_finished ON finance.legacy_fee_duplicate_run (finished_at DESC);
SELECT audit.attach('finance.legacy_fee_duplicate_run');

-- the old portal's numbers looked up as the importer stores them, upper-cased and trimmed (the cleanup seals and checks them so)
CREATE INDEX ix_legacy_payref_number ON finance.legacy_payref (upper(btrim(payref)));

-- ── 2 · the scope and the six fields ───────────────────────────────────────────────────────────────────────────────────────────
/* a legacy school-fee record, in the scope of the cleanup */
CREATE FUNCTION finance.legacy_fee_in_scope(p_channel text, p_reference text, p_purpose text, p_confirmed timestamptz)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT p_channel = 'Legacy' AND p_confirmed IS NOT NULL
       AND p_purpose IN ('School fees (legacy)', 'School fees (legacy) · semester 1', 'School fees (legacy) · semester 2', 'School fees (legacy) · semester 3')
       AND p_reference LIKE 'MOAUM-LEG-%' AND p_reference NOT LIKE 'MOAUM-LEG-GST-%';
$$;
COMMENT ON FUNCTION finance.legacy_fee_in_scope(text, text, text, timestamptz) IS
  'V726: a legacy-imported school-fee record (channel Legacy, a MOAUM-LEG- reference other than MOAUM-LEG-GST-, confirmed, purpose School fees (legacy) with or without a semester) — the cleanup''s scope.';

/* the old portal's payment number a record's note carries at its end (' · old ref <number>'), upper-cased and trimmed */
CREATE FUNCTION finance.legacy_note_payref(p_note text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN strpos(p_note, '· old ref ') > 0
                THEN nullif(upper(btrim(substr(p_note, strpos(p_note, '· old ref ') + length('· old ref ')))), '') END;
$$;

/* the semester a legacy school-fee purpose names; 0 for a whole-session record */
CREATE FUNCTION finance.legacy_fee_semester(p_purpose text) RETURNS integer LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_purpose LIKE '% · semester _' THEN right(p_purpose, 1)::int ELSE 0 END;
$$;

-- ── 3 · the plan: every group, the record kept, the records deleted, the groups left whole and why ─────────────────────────────
CREATE FUNCTION finance.legacy_fee_duplicate_plan()
RETURNS TABLE (group_key text, payment_id uuid, reference text, student_id uuid, matric_no text, session text, level integer, semester integer,
               paid_on date, payref text, amount numeric, receipt_no text, role text, reason text, kept_reference text, kept_id uuid)
LANGUAGE sql STABLE AS $$
    WITH s AS MATERIALIZED (   -- read once: the scope, each record's semester, Lagos day and the number its note carries
        SELECT r.id, r.reference, r.student_id, r.session, r.amount, r.generated_at, r.archived_at, r.note, r.receipt_no,
               finance.legacy_fee_semester(r.purpose) AS semester, (r.confirmed_at AT TIME ZONE 'Africa/Lagos')::date AS paid_on,
               finance.legacy_note_payref(r.note) AS note_payref
          FROM finance.payment_reference r
         WHERE r.channel = 'Legacy' AND finance.legacy_fee_in_scope(r.channel, r.reference, r.purpose, r.confirmed_at)),
    nums AS (   -- each record's payment numbers: linked in legacy_payref, and at the end of its note
        SELECT x.id, x.payref, bool_or(x.linked) AS linked
          FROM (SELECT s.id, upper(btrim(k.payref)) AS payref, true AS linked FROM s JOIN finance.legacy_payref k ON k.reference = s.reference
                UNION ALL
                SELECT s.id, s.note_payref, false FROM s WHERE s.note_payref IS NOT NULL) x
         WHERE x.payref <> ''
         GROUP BY x.id, x.payref),
    grp AS (    -- the six-field groups: the same number, day, student, semester and session (the level follows from student and session)
        SELECT n.payref, s.paid_on, s.student_id, s.semester, s.session,
               n.payref || '|' || s.paid_on || '|' || s.student_id || '|' || s.semester || '|' || s.session AS group_key
          FROM nums n JOIN s ON s.id = n.id
         GROUP BY n.payref, s.paid_on, s.student_id, s.semester, s.session
        HAVING count(DISTINCT s.id) > 1),
    mem AS (    -- each group's members, and whether a member stands in two groups
        SELECT g.group_key, g.payref, g.paid_on, g.student_id, g.semester, g.session, s.id, s.reference, s.amount, s.generated_at,
               s.archived_at, s.note, s.receipt_no, count(*) OVER (PARTITION BY s.id) > 1 AS in_two_groups
          FROM grp g
          JOIN nums n ON n.payref = g.payref
          JOIN s ON s.id = n.id AND s.paid_on = g.paid_on AND s.student_id = g.student_id AND s.semester = g.semester AND s.session = g.session),
    fact AS (   -- what each member is tied to, read once a member (indexed lookups)
        SELECT m.*,
               EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.reference = m.reference AND upper(btrim(k.payref)) = m.payref) AS holds_number,
               EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.reference = m.reference AND upper(btrim(k.payref)) <> m.payref) AS holds_other_number,
               EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'PAYMENT' AND j.source_ref = m.reference AND j.status = 'POSTED') AS posted,
               EXISTS (SELECT 1 FROM finance.payment_identity i WHERE i.payment_id = m.id) AS has_identity,
               EXISTS (SELECT 1 FROM finance.historical_payment_evidence e WHERE e.payment_id = m.id AND e.state = 'VERIFIED') AS verified,
               EXISTS (SELECT 1 FROM finance.historical_payment_evidence e WHERE e.payment_id = m.id AND e.state NOT IN ('REJECTED', 'WITHDRAWN')) AS evidenced,
               (m.archived_at IS NOT NULL OR EXISTS (SELECT 1 FROM finance.payment_archive a WHERE a.payment_id = m.id)) AS archived,
               (EXISTS (SELECT 1 FROM people.deferment_fee d WHERE d.reference = m.reference)
                OR EXISTS (SELECT 1 FROM finance.legacy_gst_reconciliation g WHERE g.payment_reference_id = m.id)
                OR EXISTS (SELECT 1 FROM finance.refund f WHERE f.source_reference = m.reference)
                OR EXISTS (SELECT 1 FROM finance.payment_swap w WHERE w.payment_id = m.id)
                OR EXISTS (SELECT 1 FROM finance.payment_reallocation l WHERE l.payment_id = m.id)
                OR EXISTS (SELECT 1 FROM finance.legacy_outstanding_payment o WHERE o.payment_id = m.id)
                OR EXISTS (SELECT 1 FROM finance.payment_archive a WHERE a.related_payment_id = m.id)) AS linked,
               (EXISTS (SELECT 1 FROM finance.overpayment_decision d WHERE d.student_id = m.student_id AND d.session = m.session)
                OR EXISTS (SELECT 1 FROM finance.legacy_credit_request c WHERE c.student_id = m.student_id AND c.session = m.session)
                OR EXISTS (SELECT 1 FROM finance.double_charge_check c WHERE c.student_id = m.student_id AND c.session = m.session)
                OR EXISTS (SELECT 1 FROM finance.bank_list_group b WHERE b.student_id = m.student_id AND b.session = m.session)) AS money_decision,
               finance.legacy_wallet_method(m.note) = 'E-Wallet' AS from_wallet,
               EXISTS (SELECT 1 FROM finance.legacy_wallet w WHERE w.student_id = m.student_id AND w.status IN ('VERIFIED', 'POSTED', 'FROZEN', 'REJECTED')) AS wallet_settled
          FROM mem m),
    ranked AS (
        SELECT f.*, row_number() OVER (PARTITION BY f.group_key
                                       ORDER BY f.verified DESC, f.holds_number DESC, f.posted DESC, f.has_identity DESC, f.generated_at, f.reference, f.id) AS rank
          FROM fact f),
    judged AS (   -- each group's record kept, and the first reason that leaves the group whole — read in one pass, by window
        SELECT r.*,
               first_value(r.reference) OVER kept AS kept_reference, first_value(r.id) OVER kept AS kept_id,
               CASE WHEN min(r.amount) OVER whole <> max(r.amount) OVER whole THEN 'AMOUNTS_DIFFER'
                    WHEN bool_or(r.archived) OVER whole THEN 'ARCHIVED_OR_UNDER_REVIEW'
                    WHEN count(*) FILTER (WHERE r.verified) OVER whole > 1 THEN 'EVIDENCE_ON_TWO_RECORDS'
                    WHEN bool_or(r.evidenced AND r.rank > 1) OVER whole THEN 'EVIDENCE_ON_A_DUPLICATE'
                    WHEN bool_or(r.in_two_groups OR (r.holds_other_number AND r.rank > 1)) OVER whole THEN 'ANOTHER_PAYMENT_NUMBER'
                    WHEN bool_or(r.linked) OVER whole THEN 'LINKED_RECORD'
                    WHEN bool_or(r.money_decision) OVER whole THEN 'MONEY_DECISION'
                    WHEN bool_or(r.from_wallet AND r.rank > 1 AND r.wallet_settled) OVER whole THEN 'OLD_WALLET_SETTLED'
                    ELSE NULL END AS skip_reason
          FROM ranked r
        WINDOW kept AS (PARTITION BY r.group_key ORDER BY r.rank), whole AS (PARTITION BY r.group_key))
    SELECT j.group_key, j.id, j.reference, j.student_id, st.matric_no, j.session, people.receipt_level(j.student_id, j.session), j.semester,
           j.paid_on, j.payref, j.amount, j.receipt_no,
           CASE WHEN j.skip_reason IS NOT NULL THEN 'SKIP' WHEN j.rank = 1 THEN 'KEEP' ELSE 'DELETE' END,
           j.skip_reason, j.kept_reference, j.kept_id
      FROM judged j
      LEFT JOIN people.student st ON st.id = j.student_id
     ORDER BY j.group_key, j.rank;
$$;
COMMENT ON FUNCTION finance.legacy_fee_duplicate_plan() IS
  'V726: the legacy school-fee records that repeat another on all six fields (payment number, Lagos day, student, level, semester, session) — each group''s record KEPT, its records to DELETE, or every record SKIP with the reason the group is left whole. Reads only.';

-- ── 4 · the cleanup ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.legacy_fee_duplicates_remove(p_run_by text)
RETURNS finance.legacy_fee_duplicate_run
LANGUAGE plpgsql AS $$
DECLARE
    v_started timestamptz := clock_timestamp();
    v_run finance.legacy_fee_duplicate_run;
    v_inspected int; v_groups int; v_cleaned int; v_retained int; v_planned int; v_deleted int := 0; v_gskip int; v_rskip int;
    v_reasons jsonb; v_amount numeric := 0; v_students int := 0; v_sealed int := 0; v_moved int := 0; v_released int := 0;
    v_ids int := 0; v_receipts int := 0; v_checks jsonb := '{}'::jsonb; v_failed text[] := '{}'; v_err text; v_status text;
    v_recon text := 'NOT_RUN'; v_integrity text := 'NOT_RUN'; d record; g record; j record; v_n int; v_s uuid;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL OR nullif(current_setting('moaum.actor_office', true), '') IS NULL THEN
        RAISE EXCEPTION 'LEGACY_DUPLICATES_UNATTRIBUTED: the cleanup runs on the audit spine (moaum.actor_id and moaum.actor_office)' USING ERRCODE = '23514';
    END IF;
    IF btrim(coalesce(p_run_by, '')) = '' THEN
        RAISE EXCEPTION 'LEGACY_DUPLICATES_RUN_BY: a run names what ran it (a migration, a check)' USING ERRCODE = '23514';
    END IF;
    -- one run at a time
    PERFORM pg_advisory_xact_lock(hashtext('finance.legacy_fee_duplicates_remove'));

    SELECT count(*) INTO v_inspected FROM finance.payment_reference r WHERE finance.legacy_fee_in_scope(r.channel, r.reference, r.purpose, r.confirmed_at);

    DROP TABLE IF EXISTS pg_temp.ldr_plan;
    DROP TABLE IF EXISTS pg_temp.ldr_before;
    BEGIN
        CREATE TEMP TABLE ldr_plan AS SELECT * FROM finance.legacy_fee_duplicate_plan();
        IF EXISTS (SELECT 1 FROM ldr_plan) THEN
            -- the members of every group held still while the cleanup works, then the plan read again under that hold
            PERFORM 1 FROM finance.payment_reference r WHERE r.id IN (SELECT p.payment_id FROM ldr_plan p) FOR UPDATE;
            TRUNCATE ldr_plan;
            INSERT INTO ldr_plan SELECT * FROM finance.legacy_fee_duplicate_plan();
        END IF;

        SELECT count(DISTINCT p.group_key), count(DISTINCT p.group_key) FILTER (WHERE p.role <> 'SKIP'),
               count(*) FILTER (WHERE p.role = 'KEEP'), count(*) FILTER (WHERE p.role = 'DELETE'),
               count(DISTINCT p.group_key) FILTER (WHERE p.role = 'SKIP'), count(*) FILTER (WHERE p.role = 'SKIP'),
               coalesce(sum(p.amount) FILTER (WHERE p.role = 'DELETE'), 0), count(DISTINCT p.student_id) FILTER (WHERE p.role = 'DELETE'),
               count(*) FILTER (WHERE p.role = 'DELETE' AND p.receipt_no IS NOT NULL)
          INTO v_groups, v_cleaned, v_retained, v_planned, v_gskip, v_rskip, v_amount, v_students, v_receipts
          FROM ldr_plan p;
        SELECT coalesce(jsonb_object_agg(x.reason, x.n), '{}'::jsonb) INTO v_reasons
          FROM (SELECT p.reason, count(DISTINCT p.group_key) AS n FROM ldr_plan p WHERE p.role = 'SKIP' GROUP BY p.reason) x;

        -- each student's paid school fees for the session, before
        CREATE TEMP TABLE ldr_before AS
            SELECT r.student_id, r.session, sum(r.amount) AS paid
              FROM finance.payment_reference r
             WHERE (r.student_id, r.session) IN (SELECT p.student_id, p.session FROM ldr_plan p WHERE p.role = 'DELETE')
               AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
             GROUP BY r.student_id, r.session;

        IF v_planned > 0 THEN
            FOR d IN SELECT p.* FROM ldr_plan p WHERE p.role = 'DELETE' ORDER BY p.group_key, p.reference LOOP
                -- the ledger: the deleted record's journal moves to the kept record, or is reversed and let go when both were posted
                SELECT x.id, x.status INTO j FROM finance.gl_journal x WHERE x.source_type = 'PAYMENT' AND x.source_ref = d.reference;
                IF j.id IS NOT NULL THEN
                    IF EXISTS (SELECT 1 FROM finance.gl_journal x WHERE x.source_type = 'PAYMENT' AND x.source_ref = d.kept_reference) THEN
                        PERFORM finance.gl_free_payment(d.reference, d.payment_id, 'PAYMENT_DUPLICATE_DELETED',
                            'V726: legacy school-fee record ' || d.reference || ' deleted as a duplicate of ' || d.kept_reference);
                        v_released := v_released + 1;
                    ELSE
                        UPDATE finance.gl_journal SET source_ref = d.kept_reference WHERE id = j.id;
                        v_moved := v_moved + 1;
                    END IF;
                END IF;
                -- the identity (V647) and a held row (V647) follow the payment to the kept record
                IF EXISTS (SELECT 1 FROM finance.payment_identity i WHERE i.payment_id = d.payment_id)
                   AND NOT EXISTS (SELECT 1 FROM finance.payment_identity i WHERE i.payment_id = d.kept_id) THEN
                    UPDATE finance.payment_identity SET payment_id = d.kept_id WHERE payment_id = d.payment_id;
                    v_ids := v_ids + 1;
                END IF;
                UPDATE finance.legacy_payment_held SET payment_id = d.kept_id WHERE payment_id = d.payment_id;
            END LOOP;

            -- the group's payment number sealed on the kept record: a re-upload of it is "already on record"
            FOR g IN SELECT DISTINCT p.payref, p.kept_reference, k.amount FROM ldr_plan p JOIN ldr_plan k ON k.payment_id = p.kept_id AND k.group_key = p.group_key
                      WHERE p.role = 'DELETE' LOOP
                UPDATE finance.legacy_payref SET reference = g.kept_reference WHERE upper(btrim(payref)) = g.payref AND reference <> g.kept_reference;
                GET DIAGNOSTICS v_n = ROW_COUNT;
                IF NOT EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE upper(btrim(k.payref)) = g.payref) THEN
                    INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (g.payref, g.kept_reference, g.amount);
                    v_n := v_n + 1;
                END IF;
                v_sealed := v_sealed + least(v_n, 1);
            END LOOP;

            -- the duplicates, deleted for good
            DELETE FROM finance.payment_reference r WHERE r.id IN (SELECT p.payment_id FROM ldr_plan p WHERE p.role = 'DELETE');
            GET DIAGNOSTICS v_deleted = ROW_COUNT;

            -- what is worked out from payments: the historical-fees summary marked stale; an old e-wallet touched worked out again
            FOR v_s IN SELECT DISTINCT p.student_id FROM ldr_plan p WHERE p.role = 'DELETE' LOOP
                PERFORM finance.historical_mark(v_s);
            END LOOP;
            FOR v_s IN SELECT DISTINCT p.student_id FROM ldr_plan p
                        WHERE p.role = 'DELETE' AND EXISTS (SELECT 1 FROM finance.legacy_wallet w WHERE w.student_id = p.student_id) LOOP
                PERFORM finance.legacy_wallet_compute(v_s);
            END LOOP;
        END IF;

        -- the checks: integrity
        v_checks := v_checks || jsonb_build_object('planned_deleted', jsonb_build_object('ok', v_deleted = v_planned, 'planned', v_planned, 'deleted', v_deleted));
        SELECT count(*) INTO v_n FROM ldr_plan p WHERE p.role = 'DELETE' AND EXISTS (SELECT 1 FROM finance.payment_reference r WHERE r.id = p.payment_id);
        v_checks := v_checks || jsonb_build_object('none_left', jsonb_build_object('ok', v_n = 0, 'left', v_n));
        SELECT count(*) INTO v_n FROM ldr_plan p WHERE p.role IN ('KEEP', 'SKIP') AND NOT EXISTS (SELECT 1 FROM finance.payment_reference r WHERE r.id = p.payment_id);
        v_checks := v_checks || jsonb_build_object('kept_kept', jsonb_build_object('ok', v_n = 0, 'missing', v_n));
        v_n := CASE WHEN v_planned > 0 THEN (SELECT count(*) FROM finance.legacy_fee_duplicate_plan() p WHERE p.role = 'DELETE') ELSE 0 END;
        v_checks := v_checks || jsonb_build_object('no_group_left', jsonb_build_object('ok', v_n = 0, 'deletable', v_n));
        SELECT count(*) INTO v_n FROM (SELECT DISTINCT p.payref, p.kept_reference FROM ldr_plan p WHERE p.role = 'DELETE') x
         WHERE NOT EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE upper(btrim(k.payref)) = x.payref AND k.reference = x.kept_reference);
        v_checks := v_checks || jsonb_build_object('numbers_sealed', jsonb_build_object('ok', v_n = 0, 'unsealed', v_n));
        SELECT count(*) INTO v_n FROM finance.gl_journal x WHERE x.source_type = 'PAYMENT' AND x.source_ref IN (SELECT p.reference FROM ldr_plan p WHERE p.role = 'DELETE');
        v_checks := v_checks || jsonb_build_object('ledger_clear', jsonb_build_object('ok', v_n = 0, 'journals_on_deleted', v_n));
        SELECT count(*) INTO v_n FROM finance.payment_identity i WHERE i.payment_id IN (SELECT p.payment_id FROM ldr_plan p WHERE p.role = 'DELETE');
        v_checks := v_checks || jsonb_build_object('identities_clear', jsonb_build_object('ok', v_n = 0, 'left', v_n));
        v_integrity := CASE WHEN (SELECT bool_and((v.value ->> 'ok')::boolean) FROM jsonb_each(v_checks) v) THEN 'PASSED' ELSE 'FAILED' END;

        -- the checks: reconciliation — each student's paid school fees for the session lower by exactly the deleted records' amounts,
        -- and the kept record of each group still confirmed at the group's amount
        SELECT count(*) INTO v_n
          FROM ldr_before b
          LEFT JOIN (SELECT p.student_id, p.session, sum(p.amount) AS gone FROM ldr_plan p WHERE p.role = 'DELETE' GROUP BY p.student_id, p.session) x
                 ON x.student_id = b.student_id AND x.session = b.session
          LEFT JOIN (SELECT r.student_id, r.session, sum(r.amount) AS paid FROM finance.payment_reference r
                      WHERE r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
                        AND (r.student_id, r.session) IN (SELECT b2.student_id, b2.session FROM ldr_before b2)
                      GROUP BY r.student_id, r.session) a
                 ON a.student_id = b.student_id AND a.session = b.session
         WHERE coalesce(a.paid, 0) <> b.paid - coalesce(x.gone, 0);
        v_checks := v_checks || jsonb_build_object('paid_totals', jsonb_build_object('ok', v_n = 0, 'students_sessions_off', v_n,
                        'students_sessions', (SELECT count(*) FROM ldr_before)));
        SELECT count(*) INTO v_n FROM ldr_plan p
         WHERE p.role = 'KEEP' AND NOT EXISTS (SELECT 1 FROM finance.payment_reference r WHERE r.id = p.payment_id AND r.confirmed_at IS NOT NULL AND r.amount = p.amount);
        v_checks := v_checks || jsonb_build_object('kept_paid', jsonb_build_object('ok', v_n = 0, 'changed', v_n));
        v_recon := CASE WHEN (v_checks -> 'paid_totals' ->> 'ok')::boolean AND (v_checks -> 'kept_paid' ->> 'ok')::boolean THEN 'PASSED' ELSE 'FAILED' END;

        SELECT coalesce(array_agg(v.key ORDER BY v.key), '{}') INTO v_failed FROM jsonb_each(v_checks) v WHERE NOT (v.value ->> 'ok')::boolean;
        IF cardinality(v_failed) > 0 THEN
            RAISE EXCEPTION 'LEGACY_DUPLICATES_CHECK_FAILED: % — nothing was changed', array_to_string(v_failed, ', ') USING ERRCODE = '23514';
        END IF;
        v_status := CASE WHEN v_deleted > 0 THEN 'DELETED' ELSE 'NOTHING_TO_DELETE' END;
    EXCEPTION WHEN OTHERS THEN
        -- everything the cleanup did is undone with this block; the run is recorded as failed, with the reason
        GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
        v_status := 'FAILED';
        v_deleted := 0; v_sealed := 0; v_moved := 0; v_released := 0; v_ids := 0;
        IF v_integrity = 'NOT_RUN' THEN v_integrity := 'FAILED'; END IF;
        IF v_recon = 'NOT_RUN' THEN v_recon := 'FAILED'; END IF;
        RAISE WARNING 'V726 legacy school-fee duplicate cleanup FAILED, nothing changed: %', v_err;
    END;

    INSERT INTO finance.legacy_fee_duplicate_run (run_ref, run_by, started_at, status, inspected, groups_found, groups_cleaned, retained, deleted,
                                                  groups_skipped, records_skipped, skipped_by_reason, amount_deleted, students, numbers_sealed,
                                                  ledger_moved, ledger_released, identities_moved, receipts_voided, reconciliation, integrity, checks, error)
    VALUES ('LDR-' || to_char(v_started AT TIME ZONE 'Africa/Lagos', 'YYYYMMDD-HH24MISS-US'), btrim(p_run_by), v_started, v_status, coalesce(v_inspected, 0),
            coalesce(v_groups, 0), CASE WHEN v_status = 'FAILED' THEN 0 ELSE coalesce(v_cleaned, 0) END,
            CASE WHEN v_status = 'FAILED' THEN 0 ELSE coalesce(v_retained, 0) END, v_deleted, coalesce(v_gskip, 0), coalesce(v_rskip, 0),
            coalesce(v_reasons, '{}'::jsonb), CASE WHEN v_status = 'FAILED' THEN 0 ELSE coalesce(v_amount, 0) END,
            CASE WHEN v_status = 'FAILED' THEN 0 ELSE coalesce(v_students, 0) END, v_sealed, v_moved, v_released, v_ids,
            CASE WHEN v_status = 'FAILED' THEN 0 ELSE coalesce(v_receipts, 0) END, v_recon, v_integrity, v_checks,
            CASE WHEN v_status = 'FAILED' THEN coalesce(v_err, 'unknown') END)
    RETURNING * INTO v_run;
    DROP TABLE IF EXISTS pg_temp.ldr_plan;
    DROP TABLE IF EXISTS pg_temp.ldr_before;
    RETURN v_run;
END $$;
COMMENT ON FUNCTION finance.legacy_fee_duplicates_remove(text) IS
  'V726: deletes for good the legacy school-fee records that repeat another on all six fields, one kept per group (finance.legacy_fee_duplicate_plan), the ledger, payment number, identity and held rows moved to the kept record first; checks the result (integrity and each student''s paid total) and undoes everything if a check fails; records the run in finance.legacy_fee_duplicate_run and returns it.';

-- ── 5 · prevention: the same payment is never recorded twice ────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.legacy_fee_once() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_num text := finance.legacy_note_payref(NEW.note); v_sem int; v_day date;
BEGIN
    IF v_num IS NULL OR NOT finance.legacy_fee_in_scope(NEW.channel, NEW.reference, NEW.purpose, NEW.confirmed_at) THEN
        RETURN NEW;
    END IF;
    v_sem := finance.legacy_fee_semester(NEW.purpose);
    v_day := (NEW.confirmed_at AT TIME ZONE 'Africa/Lagos')::date;
    IF EXISTS (SELECT 1 FROM finance.payment_reference r
                WHERE r.student_id = NEW.student_id AND r.session = NEW.session AND r.id <> NEW.id
                  AND finance.legacy_fee_in_scope(r.channel, r.reference, r.purpose, r.confirmed_at)
                  AND finance.legacy_fee_semester(r.purpose) = v_sem
                  AND (r.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = v_day
                  AND (finance.legacy_note_payref(r.note) = v_num
                       OR EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.reference = r.reference AND upper(btrim(k.payref)) = v_num))) THEN
        RETURN NULL;   -- the same payment on record already: not recorded a second time (the importer counts it as already on record)
    END IF;
    RETURN NEW;
END $$;
COMMENT ON FUNCTION finance.legacy_fee_once() IS
  'V726: a legacy school-fee record whose payment number, Lagos day, student, semester and session match one on record is not inserted (the importer counts it among those already on record); a record differing in level, semester or session is.';
CREATE TRIGGER trg_pref_legacy_fee_once BEFORE INSERT ON finance.payment_reference
    FOR EACH ROW WHEN (NEW.channel = 'Legacy') EXECUTE FUNCTION finance.legacy_fee_once();

-- ── 6 · the run on deployment ───────────────────────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE r finance.legacy_fee_duplicate_run;
BEGIN
    r := finance.legacy_fee_duplicates_remove('DEPLOYMENT V726');
    RAISE NOTICE 'V726 legacy school-fee duplicates on %: % — inspected %, groups %, kept %, deleted % (₦%), left whole % groups (% records: %), students %, numbers sealed %, ledger moved %/released %, reconciliation %, integrity %',
        r.database_name, r.status, r.inspected, r.groups_found, r.retained, r.deleted, r.amount_deleted, r.groups_skipped, r.records_skipped,
        r.skipped_by_reason, r.students, r.numbers_sealed, r.ledger_moved, r.ledger_released, r.reconciliation,
        r.integrity || CASE WHEN r.error IS NULL THEN '' ELSE ' — ' || r.error END;
END $$;

COMMIT;
