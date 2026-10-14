-- ═══════════════════════════════════════
-- V449 — old-portal school-fees payments recorded twice, withdrawn; and never recorded twice again
--
-- The Old Fees History import (finance.import_legacy_payments) ran on two exports of the same old-portal payments: the first
-- (15 Sep 2026) gave each payment's semester and recorded it as MOAUM-LEG-<matric>-<session>-S1 (or -S2); the second (5 Oct)
-- gave no semester and recorded the same payment again as MOAUM-LEG-<matric>-<session> — same student, same amount, same
-- day. V326 folds a per-semester row into an earlier whole-session row, but never looked the other way. So the portal summed
-- both: on the 13 Oct copy of the live data some 30,000 payments counted twice (13,677 students in 2025/2026), and 8,288
-- students who had paid only the first semester were shown as fully paid, their second-semester fee hidden.
--
-- 1 · finance.legacy_duplicate_pairs lists each whole-session legacy school-fees record that repeats a per-semester one: the
--     same reference with -S1/-S2/-S3, same student, session and amount, confirmed the same day (Lagos). Nothing looser.
-- 2 · finance.withdraw_legacy_duplicates withdraws them: a record the ledger has posted is reversed there (finance.gl_reverse,
--     so the books lose the income they gained twice); the record itself is kept on finance.legacy_duplicate_withdrawn with
--     the reference it repeats, its ledger journal and the reversal, then removed (the removal is on the audit spine in the
--     migration's name, as the legacy-fees reset of V305 does). The per-semester record stays, as it was. A duplicate that a
--     deferment fee, a refund or the GST reconciliation points at is left in place and counted, for the Bursary to look at.
-- 3 · import_legacy_payments (V326) restated: a row with no semester is that payment again when a per-semester record of the
--     same reference base, amount and day already exists — reported as a duplicate, never recorded.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V449: old-portal school-fees payments recorded twice, withdrawn', true);

-- ── 1 · what was recorded twice ──────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.legacy_duplicate_pairs()
RETURNS TABLE (duplicate_id uuid, duplicate_reference text, kept_reference text, student_id uuid, session text, amount numeric,
               confirmed_at timestamptz, linked text)
LANGUAGE sql STABLE AS $$
    SELECT DISTINCT ON (a.id) a.id, a.reference, b.reference, a.student_id, a.session, a.amount, a.confirmed_at,
           CASE WHEN EXISTS (SELECT 1 FROM people.deferment_fee f WHERE f.reference = a.reference) THEN 'DEFERMENT_FEE'
                WHEN EXISTS (SELECT 1 FROM finance.refund r WHERE r.source_reference = a.reference) THEN 'REFUND'
                WHEN EXISTS (SELECT 1 FROM finance.legacy_gst_reconciliation g WHERE g.payment_reference_id = a.id) THEN 'GST_RECONCILIATION'
           END
      FROM finance.payment_reference a
      JOIN finance.payment_reference b
        ON b.reference IN (a.reference || '-S1', a.reference || '-S2', a.reference || '-S3')
       AND b.student_id = a.student_id AND b.session = a.session
     WHERE a.channel = 'Legacy' AND b.channel = 'Legacy'
       AND a.reference LIKE 'MOAUM-LEG-%' AND a.purpose = 'School fees (legacy)'
       AND b.purpose LIKE 'School fees (legacy) _ semester _'
       AND a.amount = b.amount
       AND a.confirmed_at IS NOT NULL AND b.confirmed_at IS NOT NULL
       AND (a.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (b.confirmed_at AT TIME ZONE 'Africa/Lagos')::date
     ORDER BY a.id, b.reference
$$;
COMMENT ON FUNCTION finance.legacy_duplicate_pairs() IS
  'V449: each whole-session old-portal school-fees record that repeats a per-semester one (same reference with -S1/-S2/-S3, student, session, amount and Lagos day), with what points at it (a deferment fee, a refund, the GST reconciliation) if anything.';

CREATE TABLE finance.legacy_duplicate_withdrawn (
    id                uuid PRIMARY KEY,
    reference         text NOT NULL UNIQUE,
    kept_reference    text NOT NULL,
    student_id        uuid NOT NULL,
    session           text NOT NULL,
    purpose           text NOT NULL,
    amount            numeric NOT NULL,
    confirmed_at      timestamptz NULL,
    receipt_no        text NULL,
    note              text NULL,
    ledger_journal    uuid NULL,
    reversal_journal  uuid NULL,
    withdrawn_at      timestamptz NOT NULL DEFAULT now(),
    withdrawn_by      uuid NULL,
    reason            text NOT NULL
);
COMMENT ON TABLE finance.legacy_duplicate_withdrawn IS
  'V449: every old-portal payment record withdrawn because it repeated another — what it said, the record it repeated, the ledger journal it had and the reversal posted for it.';
CREATE INDEX ix_legacy_dup_student ON finance.legacy_duplicate_withdrawn (student_id, session);
SELECT audit.attach('finance.legacy_duplicate_withdrawn');

-- ── 2 · withdrawn ────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.withdraw_legacy_duplicates(p_reason text)
RETURNS TABLE (withdrawn int, ledger_reversed int, left_linked int)
LANGUAGE plpgsql AS $$
DECLARE d record; pr finance.payment_reference; v_journal uuid; v_reversal uuid; n int := 0; nr int := 0; nl int := 0;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'recorded twice by the Old Fees History import');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a payment record is withdrawn by a person' USING ERRCODE = '23514'; END IF;
    FOR d IN SELECT * FROM finance.legacy_duplicate_pairs() LOOP
        IF d.linked IS NOT NULL THEN nl := nl + 1; CONTINUE; END IF;
        SELECT * INTO pr FROM finance.payment_reference WHERE id = d.duplicate_id FOR UPDATE;
        v_journal := NULL; v_reversal := NULL;
        SELECT g.id INTO v_journal FROM finance.gl_journal g
         WHERE g.source_type = 'PAYMENT' AND g.source_ref = d.duplicate_reference AND g.status = 'POSTED'
         ORDER BY g.posted_at LIMIT 1;
        IF v_journal IS NOT NULL THEN
            v_reversal := finance.gl_reverse(v_journal, 'the payment ' || d.duplicate_reference || ' repeats ' || d.kept_reference || ': ' || v_reason);
            nr := nr + 1;
        END IF;
        INSERT INTO finance.legacy_duplicate_withdrawn (id, reference, kept_reference, student_id, session, purpose, amount, confirmed_at, receipt_no, note,
                                                       ledger_journal, reversal_journal, withdrawn_by, reason)
        VALUES (pr.id, pr.reference, d.kept_reference, pr.student_id, pr.session, pr.purpose, pr.amount, pr.confirmed_at, pr.receipt_no, pr.note,
                v_journal, v_reversal, v_actor, v_reason);
        DELETE FROM finance.payment_reference WHERE id = pr.id;
        n := n + 1;
    END LOOP;
    RETURN QUERY SELECT n, nr, nl;
END $$;
COMMENT ON FUNCTION finance.withdraw_legacy_duplicates(text) IS
  'V449: withdraws every record finance.legacy_duplicate_pairs lists that nothing points at — its ledger posting reversed, the record kept on finance.legacy_duplicate_withdrawn, then removed; returns what was withdrawn, reversed on the ledger and left because something points at it.';

-- ── 3 · the importer: a row with no semester is never that payment twice ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.import_legacy_payments(p_rows jsonb)
RETURNS TABLE (rows int, cleared int, no_student int, no_due int, duplicates int, duplicate_sample text, corrected int, undated int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_session text; v_sem int; v_amount numeric; v_sid uuid; v_when timestamptz; v_given timestamptz;
        v_ref text; v_base text; v_base0 text; v_rcpt text; v_key text; v_tag text; v_note text; v_cnt int;
        v_level int; v_item text; v_free text; v_text text; v_other boolean; v_gst boolean; v_slug text;
        v_old_ref text; v_channel text; st people.student; ex finance.payment_reference;
        n int := 0; nc int := 0; nns int := 0; nnd int := 0; nd int := 0; nfix int := 0; nund int := 0; v_dups text[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a legacy payment is recorded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the payments are rows: matriculation number, session, amount (or blank for cleared in full)' USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'regNo', '')));
        v_session := btrim(coalesce(r->>'session', ''));
        IF v_matric = '' OR v_session !~ '^[0-9]{4}/[0-9]{4}$' THEN CONTINUE; END IF;
        IF v_matric ~* '^matric' THEN CONTINUE; END IF;   -- a header row
        n := n + 1;

        SELECT * INTO st FROM people.student WHERE upper(matric_no) = v_matric OR upper(admission_no) = v_matric LIMIT 1;
        IF st.id IS NULL THEN nns := nns + 1; CONTINUE; END IF;
        v_sid := st.id;

        v_sem := finance.legacy_semester(coalesce(r->>'semester', r->>'sem'));

        -- what the money was for: the old portal's payment item when the file carries one (it is what it says);
        -- else the free-text Note, which is another purpose only when it names one
        v_item := btrim(coalesce(r->>'purpose', r->>'item', r->>'payItem', r->>'paymentItem', r->>'feeType', ''));
        v_free := btrim(coalesce(r->>'note', ''));
        v_text := CASE WHEN v_item <> '' THEN v_item ELSE v_free END;
        v_gst := coalesce(finance.legacy_gst_type_of(v_text), '') = 'GST';
        v_other := NOT v_gst AND v_text <> '' AND v_text !~* '(school|tuition|semester fee|session fee)'
                   AND (v_item <> ''
                        OR v_text ~* '(^|[^a-z])(gst|gns|general stud|hostel|accommodation|transcript|library|deferment|transfer|wallet|acceptance|application|post-?utme|screening|medical|id card|convocation|late registration|clearance|siwes|certificate|verification|result|change of|add(-| )?drop|carry-?over|exam|fine|penalty|levy|dues|insurance|sports|development|laboratory|lab|studio|field|excursion|matriculation|thesis|project|supervision|bench|departmental|faculty)');
        v_slug := CASE WHEN v_gst THEN 'GST' WHEN v_other THEN left(regexp_replace(upper(v_text), '[^0-9A-Z]', '', 'g'), 20) END;

        v_key := replace(v_session, '/', '-');
        v_base0 := 'MOAUM-LEG-' || regexp_replace(v_matric, '[^0-9A-Z]', '', 'g') || '-' || v_key;      -- the whole-session school-fees reference
        v_base := v_base0 || CASE WHEN v_sem IS NOT NULL THEN '-S' || v_sem ELSE '' END;                -- this row's school-fees reference
        v_ref := v_base || CASE WHEN v_slug IS NOT NULL THEN '-' || v_slug ELSE '' END;

        -- the date the student paid, as the file gives it
        v_given := finance.legacy_date(coalesce(r->>'paidOn', r->>'paid_on', r->>'date'));
        v_amount := nullif(regexp_replace(coalesce(r->>'amount', r->>'amountPaid', r->>'paid', ''), '[^0-9.]', '', 'g'), '')::numeric;

        -- the purpose as the ledger names it: the GST fee is one per session, and is what the GST desk counts
        v_tag := CASE WHEN v_gst THEN 'GST fee ' || v_session
                      ELSE (CASE WHEN v_other THEN v_text ELSE 'School fees' END) || ' (legacy)'
                           || CASE WHEN v_sem IS NOT NULL THEN ' · semester ' || v_sem ELSE '' END END;

        v_old_ref := btrim(coalesce(r->>'receiptNo', r->>'reference', r->>'receipt', ''));
        v_channel := btrim(coalesce(r->>'channel', ''));
        v_note := coalesce(nullif(v_free, ''), 'Imported from the old portal')
                  || CASE WHEN v_channel <> '' AND v_channel !~* '^(old record|legacy)$' THEN ' · ' || v_channel ELSE '' END
                  || CASE WHEN v_old_ref <> '' THEN ' · old ref ' || v_old_ref ELSE '' END;

        -- already on record: skip and report; the amount is never touched (a wrong date is put right)
        SELECT * INTO ex FROM finance.payment_reference WHERE reference = v_ref;
        IF ex.id IS NOT NULL THEN
            IF ex.channel = 'Legacy' AND v_given IS NOT NULL AND ex.confirmed_at IS DISTINCT FROM v_given
               AND (v_amount IS NULL OR v_amount = ex.amount) THEN
                UPDATE finance.payment_reference SET confirmed_at = v_given, expires_at = v_given WHERE id = ex.id;
                nfix := nfix + 1;
            ELSE
                nd := nd + 1; v_dups := v_dups || v_ref;
            END IF;
            CONTINUE;
        END IF;

        -- V449: the reverse of the case below. This row names no semester and no other item, and an earlier upload already
        -- put the same money on the ledger per semester (this reference with -S1, -S2 or -S3), for the same amount and, when
        -- the file gives one, the same day: it is that payment again, never a second one (the 5 Oct 2026 upload recorded
        -- some 30,000 such payments twice)
        IF v_sem IS NULL AND v_slug IS NULL AND v_amount IS NOT NULL
           AND EXISTS (SELECT 1 FROM finance.payment_reference x
                        WHERE x.reference IN (v_base0 || '-S1', v_base0 || '-S2', v_base0 || '-S3')
                          AND x.channel = 'Legacy' AND x.amount = v_amount
                          AND (v_given IS NULL OR (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (v_given AT TIME ZONE 'Africa/Lagos')::date)) THEN
            nd := nd + 1; v_dups := v_dups || v_ref;
            CONTINUE;
        END IF;

        -- the same money already on the ledger as school fees from an upload that could not tell more — without
        -- this row's semester, or without its item: put the semester on it, or relabel it; one row, not two
        IF v_amount IS NOT NULL AND (v_sem IS NOT NULL OR v_slug IS NOT NULL) THEN
            SELECT * INTO ex FROM finance.payment_reference
             WHERE reference IN (v_base0, v_base) AND reference <> v_ref AND channel = 'Legacy'
               AND purpose LIKE 'School fees%' AND amount = v_amount
             ORDER BY (reference = v_base) DESC LIMIT 1;
            IF ex.id IS NOT NULL THEN
                v_when := coalesce(v_given, ex.confirmed_at);
                UPDATE finance.payment_reference
                   SET reference = v_ref, receipt_no = 'LEG-' || v_ref, purpose = v_tag, confirmed_at = v_when, expires_at = v_when,
                       note = CASE WHEN v_free <> '' OR v_old_ref <> '' THEN v_note ELSE note END
                 WHERE id = ex.id;
                nfix := nfix + 1;
                CONTINUE;
            END IF;
        END IF;

        IF v_amount IS NULL THEN
            -- the level the student was at in THAT session, unless the file says
            v_level := nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int;
            IF v_level IS NULL OR v_level NOT IN (100, 200, 300, 400, 500, 600) THEN
                v_level := reporting.level_in_session(st.entry_level, st.entry_session, st.current_level, st.entry_mode, v_session);
            END IF;
            SELECT coalesce(sum(f.amount), 0) INTO v_amount
              FROM finance.fee_schedule f
              JOIN ref.programme p ON p.code = st.programme_code
             WHERE f.session = v_session AND f.ended_at IS NULL
               AND (f.level IS NULL OR f.level = v_level)
               AND (f.entry_mode IS NULL OR f.entry_mode = st.entry_mode)
               AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
               AND (f.programme_code IS NULL OR f.programme_code = st.programme_code)
               AND (v_sem IS NULL OR f.semester IS NULL OR f.semester = v_sem)
               AND CASE WHEN v_gst THEN f.item ~* '(gst|gns|general stud)'
                        WHEN v_other THEN f.item ILIKE '%' || v_text || '%'
                        ELSE f.item ILIKE 'school fee%' END;
            IF v_gst AND (v_amount IS NULL OR v_amount <= 0) THEN
                SELECT g.amount INTO v_amount FROM finance.gst_fee_for(v_sid, v_session) g WHERE g.stated;
            END IF;
        END IF;
        IF v_amount IS NULL OR v_amount <= 0 THEN nnd := nnd + 1; CONTINUE; END IF;

        v_when := v_given;
        IF v_when IS NULL THEN v_when := now(); nund := nund + 1; END IF;
        v_rcpt := 'LEG-' || v_ref;

        INSERT INTO finance.payment_reference
            (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
        VALUES (v_sid, v_session, v_ref, v_tag, v_amount, v_when, v_when, v_actor, 'Legacy', v_rcpt, v_note)
        ON CONFLICT (reference) DO NOTHING;
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
        IF v_cnt > 0 THEN nc := nc + 1; ELSE nd := nd + 1; END IF;
    END LOOP;

    RETURN QUERY SELECT n, nc, nns, nnd, nd, array_to_string(v_dups, ', '), nfix, nund;
END $$;
COMMENT ON FUNCTION finance.import_legacy_payments(jsonb) IS
  'The Old Fees History import (V087, V301–V305, V326, V449): rows of matriculation number, session, semester (First/Second/1/2 or blank), level, amount (blank = cleared in full against the schedule), the old portal''s payment item, paid date, old reference, channel, note. A GST item is recorded as ''GST fee <session>'' and counts for the GST gate; any other explicit item is its own purpose; a row already on the ledger as school fees from an upload that could not tell more is corrected in place (semester put on, or relabelled), never doubled.';

-- ── the withdrawal, now ──────────────────────────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM finance.withdraw_legacy_duplicates('recorded twice by the Old Fees History import of 5 Oct 2026 (V449)');
    RAISE NOTICE 'V449: % old-portal payment record(s) withdrawn as duplicates, % reversed on the ledger, % left because something points at them',
        r.withdrawn, r.ledger_reversed, r.left_linked;
END $$;

COMMIT;
