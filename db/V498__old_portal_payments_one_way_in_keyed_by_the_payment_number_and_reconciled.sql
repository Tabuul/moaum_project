-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V498 — Old-portal payments: one way in, keyed by the old portal's payment number, and reconciled against the fee setup
--
--   Reported 16 Oct 2026: "legacy fees uploaded but not reconciling with the school fees setup, and duplicates seen on the
--   legacy upload"; "Payment History Upload and Old Fees History contradict each other". Read on the Bursary's export
--   ("payment latest download 14 OCT.xlsx", 337,258 rows, each with the old portal's own payment number, payref):
--
--   1 · Two doors wrote old payments to the same ledger, blind to each other. Payment History Upload (V120) keyed a row by the
--       file's reference or a hash of the row, read no payment item (every row school fees) and no semester; Old Fees History
--       keys MOAUM-LEG-<matric>-<session>[-S<n>][-<item>]. The same export through both counted every payment twice.
--       · finance.import_payments refuses (PAYMENT_HISTORY_RETIRED): Old Fees History is the one way in.
--       · finance.old_payment_doubles (section 1b) lists every payment on record twice: what the retired door wrote repeating a
--         record (the only references the portal never makes are that door's: every portal reference begins MOAUM-), and the
--         Old Fees History records the 15 Sep and 5 Oct uploads left twice (missed by V449, as the 15 Sep migration kept whole
--         naira or summed a semester); finance.withdraw_old_payment_doubles withdraws them as V449 withdrew the 5 Oct duplicates —
--         a posted ledger journal reversed, the record kept on finance.old_payment_withdrawn, then removed; one a deferment fee,
--         a refund or the GST reconciliation points at is left. The journal is also freed, as V499 frees a reset record's
--         (finance.gl_free_payment): a reference withdrawn here and loaded again after a reset is posted, once.
--   2 · Old Fees History kept one record per student, session, semester and item, so a second payment in the same semester —
--       SCHOOL FEES MAKE UP after SCHOOL FEES, or school fees paid in two parts — was taken for the first and skipped as
--       "already on record" (or overwrote its date): 1,492 payments, ₦55,996,058.57, 1,407 students in that export. Now the old
--       portal's payment number decides (finance.legacy_payref): a number seen before is that payment again; a new number
--       attaches to the record already there for its key when that record carries no number and has the same amount (the same
--       day first); otherwise it is another payment, recorded on its own (the key with -<payref>). A file without payment
--       numbers is read as before. Numbers already written in the records' notes ("old ref …") are taken in now.
--   2b · Seen on AWS: an upload carried the old portal's payment-item CODE (10048) where the export names the item (SCHOOL FEES),
--       so a paid first semester was recorded as "10048 (legacy)" and not counted. The codes (the export's payment_type sheet)
--       are kept in finance.legacy_item_code and the import reads a code as its item; finance.legacy_mislabelled lists what was
--       recorded under a code, or under a label the rules now read otherwise ("GST FEES (legacy)"), and
--       finance.put_right_legacy_items renames or relabels it (so school fees count), or withdraws it where the same payment is on
--       record under its item. Its ledger journal (posted under the other income account the code read as) is reversed and freed,
--       so the sync posts the record afresh under its item, once. The retired door's rows dated with the upload day are matched by the day their payment number
--       carries (PR<yyyymmdd>…).
--   3 · finance.old_fees_reconciliation(session): every student with an old-portal school-fees payment in the session — what the
--       fee setup says is due (finance.session_charges), what is paid (old portal by semester, the retired door, the portal),
--       the difference and a state: UNDER, OVER, MATCHED, or NO_FEE_STATED when the setup charges the student nothing.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V498: old-portal payments — one way in, keyed by the payment number, reconciled', true);

-- ── 1 · one way in ───────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.import_payments(p_rows jsonb)
RETURNS TABLE (rows int, imported int, duplicate int, no_student int, bad_amount int, skipped int, first_error text)
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'PAYMENT_HISTORY_RETIRED: old-portal payments are loaded on Old Fees History, which reads the payment item, the semester and the old portal''s payment number and never records a payment twice'
        USING ERRCODE = '23514', HINT = 'Finance → Old Fees History: upload the old portal''s export as it is.';
END $$;
COMMENT ON FUNCTION finance.import_payments(jsonb) IS
  'V120, retired by V498: Payment History Upload wrote old payments blind to Old Fees History; it now refuses (PAYMENT_HISTORY_RETIRED).';

-- ── 2 · the old portal's payment number decides ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.legacy_payref (
    payref      text PRIMARY KEY CHECK (payref = upper(btrim(payref)) AND payref <> ''),
    reference   text NOT NULL REFERENCES finance.payment_reference (reference) ON UPDATE CASCADE ON DELETE CASCADE,
    amount      numeric(14, 2) NULL,
    recorded_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON COLUMN finance.legacy_payref.amount IS
  'V498: the amount this payment accounts for on its record — the whole record, or its part of a record the 15 Sep 2026 migration summed from several payments ("2 school-fees payment(s), migrated")';
CREATE INDEX ix_legacy_payref_reference ON finance.legacy_payref (reference);
COMMENT ON TABLE finance.legacy_payref IS
  'V498: the old portal''s own payment number (payref) of each old-portal payment on record — one number, one payment; what the Old Fees History import recognises a payment by. Removed with its record.';

-- the numbers the records already carry in their notes (" · old ref <payref>")
INSERT INTO finance.legacy_payref (payref, reference, amount)
SELECT DISTINCT ON (k.payref) k.payref, k.reference, k.amount
  FROM (SELECT upper(substring(r.note FROM 'old ref ([^ ·]+)')) AS payref, r.reference, r.confirmed_at, r.amount
          FROM finance.payment_reference r
         WHERE r.channel = 'Legacy' AND r.reference LIKE 'MOAUM-LEG-%' AND r.note LIKE '%old ref %') k
 WHERE k.payref IS NOT NULL AND k.payref <> ''
 ORDER BY k.payref, k.confirmed_at, k.reference
ON CONFLICT (payref) DO NOTHING;
-- on the audit spine from here on (the numbers above are read from records the spine already holds)
SELECT audit.attach('finance.legacy_payref');

DROP FUNCTION finance.import_legacy_payments(jsonb);
CREATE FUNCTION finance.import_legacy_payments(p_rows jsonb)
RETURNS TABLE (rows int, cleared int, no_student int, no_due int, duplicates int, duplicate_sample text, corrected int, undated int,
               matched int, separate int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_session text; v_sem int; v_amount numeric; v_sid uuid; v_when timestamptz; v_given timestamptz;
        v_ref text; v_base text; v_base0 text; v_rcpt text; v_key text; v_tag text; v_note text; v_cnt int;
        v_level int; v_item text; v_free text; v_text text; v_other boolean; v_gst boolean; v_slug text;
        v_old_ref text; v_payref text; v_channel text; v_separate boolean; st people.student; ex finance.payment_reference;
        n int := 0; nc int := 0; nns int := 0; nnd int := 0; nd int := 0; nfix int := 0; nund int := 0; nm int := 0; nsep int := 0;
        v_dups text[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a legacy payment is recorded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the payments are rows: matriculation number, session, amount (or blank for cleared in full)' USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'matno', r->>'regNo', '')));
        v_session := btrim(coalesce(r->>'session', ''));
        IF v_matric = '' OR v_session !~ '^[0-9]{4}/[0-9]{4}$' THEN CONTINUE; END IF;
        IF v_matric ~* '^mat(ric|no)' THEN CONTINUE; END IF;   -- a header row
        n := n + 1;

        SELECT * INTO st FROM people.student WHERE upper(matric_no) = v_matric OR upper(admission_no) = v_matric LIMIT 1;
        IF st.id IS NULL THEN nns := nns + 1; CONTINUE; END IF;
        v_sid := st.id;

        v_sem := finance.legacy_semester(coalesce(r->>'semester', r->>'sem'));

        -- what the money was for: the old portal's payment item when the file carries one (it is what it says);
        -- else the free-text Note, which is another purpose only when it names one
        v_item := finance.legacy_item_of(coalesce(r->>'purpose', r->>'item', r->>'payItem', r->>'paymentItem', r->>'feeType', ''));   -- V498: a code is the item it names
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

        v_old_ref := btrim(coalesce(r->>'receiptNo', r->>'reference', r->>'receipt', r->>'payref', ''));
        v_payref := nullif(upper(v_old_ref), '');
        v_channel := btrim(coalesce(r->>'channel', ''));
        v_note := coalesce(nullif(v_free, ''), 'Imported from the old portal')
                  || CASE WHEN v_channel <> '' AND v_channel !~* '^(old record|legacy)$' THEN ' · ' || v_channel ELSE '' END
                  || CASE WHEN v_old_ref <> '' THEN ' · old ref ' || v_old_ref ELSE '' END;
        v_separate := false;

        IF v_payref IS NOT NULL THEN
            -- V498: the old portal's payment number decides. Seen before: that payment again, never a second one
            IF EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.payref = v_payref) THEN
                nd := nd + 1; v_dups := v_dups || v_payref;
                CONTINUE;
            END IF;
            -- a record already there for this key that this payment is (part of), recorded by an upload that did not keep the
            -- number: what the record holds beyond the payments already attached to it is this payment's amount (the same day
            -- first) — or, on a record the 15 Sep 2026 migration summed from several payments, has room for it. The same amount
            -- is within a naira: that migration kept whole naira (36,556.00 for the export's 36,555.80), as finance.fee_short reads
            SELECT x.* INTO ex FROM finance.payment_reference x
              LEFT JOIN LATERAL (SELECT count(*) AS n, coalesce(sum(coalesce(k.amount, x.amount)), 0) AS held
                                   FROM finance.legacy_payref k WHERE k.reference = x.reference) c ON true
             WHERE x.student_id = v_sid AND x.channel = 'Legacy'
               AND (x.reference = v_ref
                    OR (v_sem IS NULL AND v_slug IS NULL AND x.reference IN (v_base0 || '-S1', v_base0 || '-S2', v_base0 || '-S3')))
               AND CASE WHEN v_amount IS NULL THEN c.n = 0
                        WHEN x.note ~ '^[2-9][0-9]* school-fees payment\(s\), migrated' THEN x.amount - c.held - v_amount > -1
                        ELSE abs(x.amount - c.held - v_amount) < 1 END
             ORDER BY (v_given IS NOT NULL AND (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (v_given AT TIME ZONE 'Africa/Lagos')::date) DESC,
                      abs(x.amount - c.held - coalesce(v_amount, x.amount - c.held)), (x.reference = v_ref) DESC
             LIMIT 1;
            IF ex.id IS NOT NULL THEN
                INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, ex.reference, coalesce(v_amount, ex.amount));
                -- a summed record keeps its day; one payment's record takes the day the file gives
                IF v_given IS NOT NULL AND ex.note !~ '^[2-9][0-9]* school-fees payment\(s\), migrated'
                   AND (ex.confirmed_at AT TIME ZONE 'Africa/Lagos')::date IS DISTINCT FROM (v_given AT TIME ZONE 'Africa/Lagos')::date THEN
                    UPDATE finance.payment_reference SET confirmed_at = v_given, expires_at = v_given,
                           note = CASE WHEN note LIKE '%old ref %' THEN note ELSE v_note END
                     WHERE id = ex.id;
                    nfix := nfix + 1;
                ELSIF ex.note NOT LIKE '%old ref %' THEN
                    UPDATE finance.payment_reference SET note = v_note WHERE id = ex.id;
                END IF;
                nm := nm + 1;
                CONTINUE;
            END IF;
            -- the key is held by another payment (one with its own number, or another amount): this one is its own record
            IF EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = v_ref) THEN
                v_ref := v_ref || '-' || left(regexp_replace(v_payref, '[^0-9A-Z]', '', 'g'), 30);
                v_separate := true;
            END IF;
        ELSE
            -- a file without payment numbers, read as before: already on record, skip and report; the amount is never touched
            -- (a wrong date is put right)
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

            -- V449: this row names no semester and no other item, and an earlier upload already put the same money on the ledger
            -- per semester (this reference with -S1, -S2 or -S3), for the same amount and, when the file gives one, the same day
            IF v_sem IS NULL AND v_slug IS NULL AND v_amount IS NOT NULL
               AND EXISTS (SELECT 1 FROM finance.payment_reference x
                            WHERE x.reference IN (v_base0 || '-S1', v_base0 || '-S2', v_base0 || '-S3')
                              AND x.channel = 'Legacy' AND x.amount = v_amount
                              AND (v_given IS NULL OR (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (v_given AT TIME ZONE 'Africa/Lagos')::date)) THEN
                nd := nd + 1; v_dups := v_dups || v_ref;
                CONTINUE;
            END IF;
        END IF;

        -- the same money already on the ledger as school fees from an upload that could not tell more — without this row's
        -- semester, or without its item: put the semester on it, or relabel it; one row, not two (never for a payment that is
        -- its own record beside another of the same key, and never a record that already carries a payment number)
        IF NOT v_separate AND v_amount IS NOT NULL AND (v_sem IS NOT NULL OR v_slug IS NOT NULL) THEN
            SELECT * INTO ex FROM finance.payment_reference x
             WHERE x.reference IN (v_base0, v_base) AND x.reference <> v_ref AND x.channel = 'Legacy'
               AND x.purpose LIKE 'School fees%' AND abs(x.amount - v_amount) < 1
               AND NOT EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.reference = x.reference)
             ORDER BY (x.reference = v_base) DESC LIMIT 1;
            IF ex.id IS NOT NULL THEN
                v_when := coalesce(v_given, ex.confirmed_at);
                UPDATE finance.payment_reference
                   SET reference = v_ref, receipt_no = 'LEG-' || v_ref, purpose = v_tag, confirmed_at = v_when, expires_at = v_when,
                       note = CASE WHEN v_free <> '' OR v_old_ref <> '' THEN v_note ELSE note END
                 WHERE id = ex.id;
                IF v_payref IS NOT NULL THEN
                    INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, v_ref, ex.amount);
                END IF;
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
        IF v_cnt > 0 THEN
            nc := nc + 1;
            IF v_separate THEN nsep := nsep + 1; END IF;
            IF v_payref IS NOT NULL THEN
                INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, v_ref, v_amount);
            END IF;
        ELSE
            nd := nd + 1; v_dups := v_dups || coalesce(v_payref, v_ref);
        END IF;
    END LOOP;

    RETURN QUERY SELECT n, nc, nns, nnd, nd, array_to_string(v_dups, ', '), nfix, nund, nm, nsep;
END $$;
COMMENT ON FUNCTION finance.import_legacy_payments(jsonb) IS
  'The Old Fees History import (V087, V301–V305, V326, V449, V498): rows of matriculation number, session, semester (First/Second/1/2 or blank), level, amount (blank = cleared in full against the schedule), the old portal''s payment item, paid date, the old portal''s payment number (payref), channel, note. V498: the payment number decides — seen before, the same payment; new, it attaches to a record of its key that has none and the same amount, else it is its own record (a make-up or second part-payment beside the first). A file without numbers is read as before. A GST item is recorded as ''GST fee <session>''; any other explicit item is its own purpose.';

/* the day an old-portal payment number carries: PR<yyyymmdd>… (PR202610077052390 was paid on 7 Oct 2026) */
CREATE FUNCTION finance.payref_day(p text)
RETURNS date LANGUAGE plpgsql IMMUTABLE AS $fn$
BEGIN
    IF upper(btrim(coalesce(p, ''))) !~ '^PR20[0-9]{2}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])' THEN RETURN NULL; END IF;
    RETURN make_date(substr(btrim(p), 3, 4)::int, substr(btrim(p), 7, 2)::int, substr(btrim(p), 9, 2)::int);
EXCEPTION WHEN others THEN
    RETURN NULL;
END $fn$;

-- ── 1b · recorded twice ───────────────────────────────────────────────────────────────────────────────────────────────────────
-- Three kinds, one list, the same student, session, amount (within a naira) and Lagos day, nothing looser:
--   PAYMENT_HISTORY — what the retired Payment History Upload wrote (a reference the portal never makes: not MOAUM-…) repeating a
--                     payment on record (an Old Fees History record, or an earlier copy of its own);
--   WHOLE_SESSION   — a numbered whole-session record of the 5 Oct 2026 upload repeating the per-semester record of the same key
--                     (V449's case, missed there because the 15 Sep migration kept whole naira): the per-semester record stays and
--                     takes the payment number;
--   UNNUMBERED      — any other Old Fees History school-fees record without a payment number repeating a numbered payment (its part
--                     of a record the 15 Sep migration summed counts).
CREATE FUNCTION finance.old_payment_doubles()
RETURNS TABLE (double_id uuid, double_reference text, double_kind text, kept_reference text, kept_kind text, student_id uuid, number text, name text,
               session text, amount numeric, paid_on date, purpose text, kept_purpose text, linked text)
LANGUAGE sql STABLE AS $$
    SELECT o.id, o.reference, o.kind, k.reference, k.kind, o.student_id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names,
           o.session, o.amount, (o.confirmed_at AT TIME ZONE 'Africa/Lagos')::date, o.purpose, k.purpose,
           CASE WHEN EXISTS (SELECT 1 FROM people.deferment_fee f WHERE f.reference = o.reference) THEN 'DEFERMENT_FEE'
                WHEN EXISTS (SELECT 1 FROM finance.refund r WHERE r.source_reference = o.reference) THEN 'REFUND'
                WHEN EXISTS (SELECT 1 FROM finance.legacy_gst_reconciliation g WHERE g.payment_reference_id = o.id) THEN 'GST_RECONCILIATION'
           END
      FROM (
            -- the retired Payment History Upload's records
            SELECT r.*, 'PAYMENT_HISTORY'::text AS kind FROM finance.payment_reference r
             WHERE r.reference NOT LIKE 'MOAUM-%' AND r.confirmed_at IS NOT NULL
            UNION ALL
            -- numbered whole-session school-fees records (a per-semester record of the same key may stand for them)
            SELECT r.*, 'WHOLE_SESSION'::text FROM finance.payment_reference r
             WHERE r.reference LIKE 'MOAUM-LEG-%' AND r.reference NOT LIKE 'MOAUM-LEG-GST-%' AND r.channel = 'Legacy'
               AND r.purpose = 'School fees (legacy)' AND r.confirmed_at IS NOT NULL
               AND EXISTS (SELECT 1 FROM finance.legacy_payref p WHERE p.reference = r.reference)
            UNION ALL
            -- Old Fees History school-fees records that carry no payment number
            SELECT r.*, 'UNNUMBERED'::text FROM finance.payment_reference r
             WHERE r.reference LIKE 'MOAUM-LEG-%' AND r.reference NOT LIKE 'MOAUM-LEG-GST-%' AND r.channel = 'Legacy'
               AND r.purpose LIKE 'School fees%' AND r.confirmed_at IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM finance.legacy_payref p WHERE p.reference = r.reference)) o
      JOIN people.student s ON s.id = o.student_id
      CROSS JOIN LATERAL (
            SELECT x.reference, x.purpose,
                   CASE WHEN x.reference LIKE 'MOAUM-LEG-%' THEN 'OLD_FEES_HISTORY' ELSE 'PAYMENT_HISTORY' END AS kind
              FROM finance.payment_reference x
             WHERE x.student_id = o.student_id AND x.session = o.session AND x.id <> o.id AND x.confirmed_at IS NOT NULL
               AND ((x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (o.confirmed_at AT TIME ZONE 'Africa/Lagos')::date
                    -- the retired door dated a row it could not read the date of with the day of the upload; the old portal's
                    -- payment number carries the day paid (PR202610077052390: 7 Oct 2026), and names the payment outright
                    OR (o.kind = 'PAYMENT_HISTORY' AND (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = finance.payref_day(o.reference))
                    OR (o.kind = 'PAYMENT_HISTORY' AND EXISTS (SELECT 1 FROM finance.legacy_payref p WHERE p.payref = upper(btrim(o.reference)) AND p.reference = x.reference)))
               AND CASE WHEN o.kind = 'PAYMENT_HISTORY'
                        -- what the retired door wrote repeats an Old Fees History record, or an earlier copy of its own
                        THEN abs(x.amount - o.amount) < 1
                             AND ((x.reference LIKE 'MOAUM-LEG-%' AND x.channel = 'Legacy') OR (x.reference NOT LIKE 'MOAUM-%' AND x.reference < o.reference))
                        -- a numbered whole-session record repeats the per-semester record of its own key that has no number
                        WHEN o.kind = 'WHOLE_SESSION'
                        THEN x.reference IN (o.reference || '-S1', o.reference || '-S2', o.reference || '-S3') AND x.channel = 'Legacy'
                             AND abs(x.amount - o.amount) < 1
                             AND NOT EXISTS (SELECT 1 FROM finance.legacy_payref p WHERE p.reference = x.reference)
                        -- a record without a number repeats a payment the export numbered (its part of a summed record counts) —
                        -- not the per-semester record a numbered whole-session record of its key repeats (that one stays)
                        ELSE x.reference LIKE 'MOAUM-LEG-%' AND x.channel = 'Legacy' AND x.purpose LIKE 'School fees%'
                             AND NOT (o.reference ~ '-S[123]$' AND x.reference = regexp_replace(o.reference, '-S[123]$', ''))
                             AND EXISTS (SELECT 1 FROM finance.legacy_payref p
                                          WHERE p.reference = x.reference AND abs(coalesce(p.amount, x.amount) - o.amount) < 1) END
             ORDER BY (x.reference LIKE 'MOAUM-LEG-%') DESC, x.reference
             LIMIT 1) k
$$;
COMMENT ON FUNCTION finance.old_payment_doubles() IS
  'V498: every old-portal payment on record twice — PAYMENT_HISTORY: a record the retired Payment History Upload wrote (not MOAUM-…) repeating an Old Fees History record or an earlier copy of its own; WHOLE_SESSION: a numbered whole-session record repeating the unnumbered per-semester record of its key (which stays and takes the number); UNNUMBERED: another Old Fees History school-fees record without a payment number repeating a numbered payment — the same student, session, amount within a naira and Lagos day; with what points at it, if anything.';

CREATE TABLE finance.old_payment_withdrawn (
    id                uuid PRIMARY KEY,
    reference         text NOT NULL,
    double_kind       text NOT NULL CHECK (double_kind IN ('PAYMENT_HISTORY', 'WHOLE_SESSION', 'UNNUMBERED', 'MISLABELLED')),
    kept_reference    text NOT NULL,
    student_id        uuid NOT NULL,
    session           text NOT NULL,
    purpose           text NOT NULL,
    amount            numeric NOT NULL,
    confirmed_at      timestamptz NULL,
    channel           text NULL,
    receipt_no        text NULL,
    note              text NULL,
    ledger_journal    uuid NULL,
    reversal_journal  uuid NULL,
    withdrawn_at      timestamptz NOT NULL DEFAULT now(),
    withdrawn_by      uuid NULL,
    reason            text NOT NULL
);
COMMENT ON TABLE finance.old_payment_withdrawn IS
  'V498: every old-portal payment record withdrawn because it repeated another — which kind, what it said, the record it repeated, its ledger journal and the reversal posted for it.';
CREATE INDEX ix_old_payment_withdrawn_student ON finance.old_payment_withdrawn (student_id, session);
CREATE INDEX ix_old_payment_withdrawn_reference ON finance.old_payment_withdrawn (reference);
SELECT audit.attach('finance.old_payment_withdrawn');

/* a payment record's ledger journal let go: reversed when posted (finance.gl_reverse), then no longer the journal of its
   reference (source_type p_as, source_ref the reference and the record's id, as V499 marks a reset record's PAYMENT_RESET), so
   the sync posts the record afresh — renamed or relabelled, under its item; withdrawn, should the reference come back */
CREATE FUNCTION finance.gl_free_payment(p_reference text, p_id uuid, p_as text, p_memo text, OUT journal uuid, OUT reversal uuid)
LANGUAGE plpgsql AS $$
DECLARE v_status text;
BEGIN
    SELECT g.id, g.status INTO journal, v_status FROM finance.gl_journal g WHERE g.source_type = 'PAYMENT' AND g.source_ref = p_reference;
    IF journal IS NULL THEN RETURN; END IF;
    IF v_status = 'POSTED' THEN reversal := finance.gl_reverse(journal, p_memo); END IF;
    UPDATE finance.gl_journal SET source_type = p_as, source_ref = p_reference || '#' || p_id WHERE id = journal;
END $$;
COMMENT ON FUNCTION finance.gl_free_payment(text, uuid, text, text) IS
  'V498: lets a payment record''s ledger journal go — reversed if posted, then marked p_as (PAYMENT_WITHDRAWN, PAYMENT_CORRECTED) with the reference and the record''s id — so the sync posts the record (or its reference, should it come back) afresh, once. Returns the journal and the reversal.';

CREATE FUNCTION finance.withdraw_old_payment_doubles(p_reason text, p_limit int DEFAULT 5000)
RETURNS TABLE (withdrawn int, ledger_reversed int, left_linked int, remaining int)
LANGUAGE plpgsql AS $$
DECLARE d record; pr finance.payment_reference; gf record; n int := 0; nr int := 0; nl int := 0; v_left int := 0;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PAY_DOUBLE_ACTOR: a payment record is withdrawn by a person' USING ERRCODE = '23514'; END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'PAY_DOUBLE_REASON: say why the records are withdrawn (at least ten characters); it is kept with each one' USING ERRCODE = '23514';
    END IF;
    -- in batches (the screen asks again until none is left): a whole export loaded through the retired door is some 300,000
    FOR d IN SELECT * FROM finance.old_payment_doubles() x WHERE x.linked IS NULL LIMIT greatest(1, coalesce(p_limit, 5000)) LOOP
        -- the record it repeats is still there (an earlier copy may itself have gone as a double, the record it repeated then
        -- standing for both)
        IF NOT EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = d.kept_reference) THEN CONTINUE; END IF;
        SELECT * INTO pr FROM finance.payment_reference WHERE id = d.double_id FOR UPDATE;
        IF pr.id IS NULL THEN CONTINUE; END IF;
        SELECT * INTO gf FROM finance.gl_free_payment(pr.reference, pr.id, 'PAYMENT_WITHDRAWN',
                                                     'the payment ' || pr.reference || ' repeats ' || d.kept_reference || ': ' || v_reason);
        IF gf.reversal IS NOT NULL THEN nr := nr + 1; END IF;
        -- a whole-session record's payment number goes to the per-semester record that stands for it
        IF d.double_kind = 'WHOLE_SESSION' THEN
            UPDATE finance.legacy_payref SET reference = d.kept_reference WHERE reference = d.double_reference;
            UPDATE finance.payment_reference SET note = pr.note WHERE reference = d.kept_reference AND note NOT LIKE '%old ref %';
        END IF;
        INSERT INTO finance.old_payment_withdrawn (id, reference, double_kind, kept_reference, student_id, session, purpose, amount, confirmed_at, channel,
                                                   receipt_no, note, ledger_journal, reversal_journal, withdrawn_by, reason)
        VALUES (pr.id, pr.reference, d.double_kind, d.kept_reference, pr.student_id, pr.session, pr.purpose, pr.amount, pr.confirmed_at, pr.channel,
                pr.receipt_no, pr.note, gf.journal, gf.reversal, v_actor, v_reason);
        DELETE FROM finance.payment_reference WHERE id = pr.id;
        n := n + 1;
    END LOOP;
    SELECT count(*) FILTER (WHERE x.linked IS NOT NULL), count(*) FILTER (WHERE x.linked IS NULL) INTO nl, v_left FROM finance.old_payment_doubles() x;
    RETURN QUERY SELECT n, nr, nl, v_left;
END $$;
COMMENT ON FUNCTION finance.withdraw_old_payment_doubles(text, int) IS
  'V498: withdraws up to p_limit of the records finance.old_payment_doubles lists that nothing points at — each one''s ledger posting reversed and freed (finance.gl_free_payment), the record kept on finance.old_payment_withdrawn, then removed; returns what was withdrawn, reversed on the ledger, left because something points at it, and still to withdraw.';

-- ── 2b · the old portal's payment-item codes ────────────────────────────────────────────────────────────────────────────────
-- Seen on AWS, 16 Oct 2026: a student who paid the first semester (₦156,338) shown owing it — the upload had carried the old
-- portal's payment-item CODE (10048) where the export names the item (SCHOOL FEES), so the payment was recorded as "10048
-- (legacy)", another item, and not counted; 10144 (GST FEES) and 10137 (ADMISSION CHECKING) beside the same payments under their
-- names. The export's second sheet (payment_type: pcode, description) says what each code is. The codes are kept; the import
-- reads a code as its item; and what was recorded under a code — or under an older importer's label the rules now read
-- otherwise ("GST FEES (legacy)" is the GST fee) — is put right.
CREATE TABLE finance.legacy_item_code (
    code        text PRIMARY KEY CHECK (code ~ '^[0-9A-Za-z]+$'),
    description text NOT NULL CHECK (btrim(description) <> ''),
    school      text NULL,
    updated_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE finance.legacy_item_code IS
  'V498: the old portal''s payment-item codes (its payment_type sheet: pcode → description), as the Bursary''s export carries them; the Old Fees History import reads a code as the item it names.';
SELECT audit.attach('finance.legacy_item_code');

/* the codes from the export's payment_type sheet: [{code, description, school}], a code given again takes its new description */
CREATE FUNCTION finance.legacy_item_codes_set(p_rows jsonb)
RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE r jsonb; v_code text; v_desc text; n int := 0;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'LEGACY_CODES_ACTOR: the payment-item codes are loaded by a person' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) LOOP
        v_code := btrim(coalesce(r->>'code', r->>'pcode', ''));
        v_desc := btrim(coalesce(r->>'description', r->>'item', ''));
        IF v_code !~ '^[0-9A-Za-z]+$' OR v_desc = '' THEN CONTINUE; END IF;
        INSERT INTO finance.legacy_item_code (code, description, school) VALUES (v_code, v_desc, nullif(btrim(coalesce(r->>'school', '')), ''))
        ON CONFLICT (code) DO UPDATE SET description = EXCLUDED.description, school = EXCLUDED.school, updated_at = now()
         WHERE finance.legacy_item_code.description IS DISTINCT FROM EXCLUDED.description OR finance.legacy_item_code.school IS DISTINCT FROM EXCLUDED.school;
        n := n + 1;
    END LOOP;
    RETURN n;
END $fn$;

/* an item as the old portal wrote it: a code read as the item it names (the code itself when it is not known) */
CREATE FUNCTION finance.legacy_item_of(p text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN btrim(coalesce(p, '')) ~ '^[0-9]+$'
                THEN coalesce((SELECT c.description FROM finance.legacy_item_code c WHERE c.code = btrim(p)), btrim(p))
                ELSE btrim(coalesce(p, '')) END
$fn$;

/* what earlier uploads recorded under a code, or under a label the rules now read otherwise, and what it is */
CREATE FUNCTION finance.legacy_mislabelled()
RETURNS TABLE (id uuid, reference text, student_id uuid, number text, name text, session text, amount numeric, paid_on date,
               stored_purpose text, item text, known boolean, target_reference text, target_purpose text, action text)
LANGUAGE sql STABLE AS $fn$
    WITH r AS (
        SELECT p.*, regexp_replace(p.purpose, ' \(legacy\)( · semester [0-9])?$', '') AS text0,
               substring(p.purpose FROM ' · semester ([0-9])$')::int AS sem,
               substring(p.reference FROM '^(MOAUM-LEG-[0-9A-Z]+-[0-9]{4}-[0-9]{4})') AS base0
          FROM finance.payment_reference p
         WHERE p.reference LIKE 'MOAUM-LEG-%' AND p.reference NOT LIKE 'MOAUM-LEG-GST-%' AND p.channel = 'Legacy' AND p.confirmed_at IS NOT NULL
           AND p.purpose LIKE '% (legacy)%' AND p.purpose NOT LIKE 'School fees%' AND p.purpose NOT LIKE 'GST fee %'),
    c AS (
        SELECT r.*, (r.text0 ~ '^[0-9]+$') AS coded,
               CASE WHEN r.text0 ~ '^[0-9]+$' THEN (SELECT k.description FROM finance.legacy_item_code k WHERE k.code = r.text0) ELSE r.text0 END AS item0
          FROM r),
    k AS (
        SELECT c.*, coalesce(finance.legacy_gst_type_of(c.item0), '') = 'GST' AS gst,
               coalesce(finance.legacy_gst_type_of(c.item0), '') <> 'GST' AND c.item0 ~* '(school|tuition|semester fee|session fee)' AS school
          FROM c WHERE c.base0 IS NOT NULL),
    t AS (
        SELECT k.*,
               CASE WHEN k.item0 IS NULL THEN NULL
                    ELSE k.base0 || CASE WHEN k.sem IS NOT NULL THEN '-S' || k.sem ELSE '' END
                         || CASE WHEN k.gst THEN '-GST' WHEN k.school THEN '' ELSE '-' || left(regexp_replace(upper(k.item0), '[^0-9A-Z]', '', 'g'), 20) END END AS target_ref,
               CASE WHEN k.item0 IS NULL THEN NULL
                    WHEN k.gst THEN 'GST fee ' || k.session
                    ELSE (CASE WHEN k.school THEN 'School fees' ELSE k.item0 END) || ' (legacy)' || CASE WHEN k.sem IS NOT NULL THEN ' · semester ' || k.sem ELSE '' END END AS target_purpose
          FROM k WHERE k.coded OR k.gst OR k.school)
    SELECT t.id, t.reference, t.student_id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, t.session, t.amount,
           (t.confirmed_at AT TIME ZONE 'Africa/Lagos')::date, t.purpose, t.item0, t.item0 IS NOT NULL, t.target_ref, t.target_purpose,
           CASE WHEN t.item0 IS NULL THEN 'UNKNOWN_CODE'
                WHEN t.target_ref = t.reference THEN 'RELABEL'
                WHEN x.id IS NULL THEN 'RENAME'
                WHEN abs(x.amount - t.amount) < 1 AND (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (t.confirmed_at AT TIME ZONE 'Africa/Lagos')::date THEN 'DOUBLE'
                ELSE 'RELABEL' END
      FROM t
      JOIN people.student s ON s.id = t.student_id
      LEFT JOIN finance.payment_reference x ON x.reference = t.target_ref AND x.id <> t.id
$fn$;
COMMENT ON FUNCTION finance.legacy_mislabelled() IS
  'V498: Old Fees History records recorded under the old portal''s payment-item code ("10048 (legacy)") or under a label the rules now read otherwise ("GST FEES (legacy)" is the GST fee), with what the item is and what putting it right does: RENAME (to the record its item makes, so school fees count), RELABEL (the purpose only, the record''s place taken by another payment), DOUBLE (the same payment is on record under its item: withdrawn), UNKNOWN_CODE (the code list does not name it yet).';

CREATE TABLE finance.legacy_item_corrected (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id      uuid NOT NULL,
    old_reference   text NOT NULL,
    new_reference   text NOT NULL,
    old_purpose     text NOT NULL,
    new_purpose     text NOT NULL,
    action          text NOT NULL CHECK (action IN ('RENAME', 'RELABEL')),
    ledger_journal  uuid NULL,
    reversal_journal uuid NULL,
    corrected_at    timestamptz NOT NULL DEFAULT now(),
    corrected_by    uuid NULL,
    reason          text NOT NULL
);
COMMENT ON TABLE finance.legacy_item_corrected IS
  'V498: every old-portal record put right — renamed to the record its item makes, or relabelled — with what it was before, its ledger journal and the reversal posted for it (the sync posts it afresh under its item), and why.';
CREATE INDEX ix_legacy_item_corrected_payment ON finance.legacy_item_corrected (payment_id);
SELECT audit.attach('finance.legacy_item_corrected');

/* put right, in batches: renamed or relabelled (kept on the register), or withdrawn when the same payment is on record */
CREATE FUNCTION finance.put_right_legacy_items(p_reason text, p_limit int DEFAULT 5000)
RETURNS TABLE (renamed int, relabelled int, withdrawn int, ledger_reversed int, unknown_codes int, remaining int)
LANGUAGE plpgsql AS $fn$
DECLARE m record; pr finance.payment_reference; gf record; nre int := 0; nrl int := 0; nw int := 0; nr int := 0; nu int := 0; v_left int := 0;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PAY_DOUBLE_ACTOR: a payment record is put right by a person' USING ERRCODE = '23514'; END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'PAY_DOUBLE_REASON: say why the records are put right (at least ten characters); it is kept with each one' USING ERRCODE = '23514';
    END IF;
    FOR m IN SELECT * FROM finance.legacy_mislabelled() x WHERE x.action IN ('RENAME', 'RELABEL', 'DOUBLE') LIMIT greatest(1, coalesce(p_limit, 5000)) LOOP
        SELECT * INTO pr FROM finance.payment_reference WHERE id = m.id FOR UPDATE;
        IF pr.id IS NULL THEN CONTINUE; END IF;
        IF m.action = 'DOUBLE' THEN
            -- the same payment is on record under its item: this one goes, as a double does
            IF EXISTS (SELECT 1 FROM people.deferment_fee f WHERE f.reference = pr.reference)
               OR EXISTS (SELECT 1 FROM finance.refund r WHERE r.source_reference = pr.reference)
               OR EXISTS (SELECT 1 FROM finance.legacy_gst_reconciliation g WHERE g.payment_reference_id = pr.id) THEN CONTINUE; END IF;
            SELECT * INTO gf FROM finance.gl_free_payment(pr.reference, pr.id, 'PAYMENT_WITHDRAWN',
                                                         'the payment ' || pr.reference || ' repeats ' || m.target_reference || ': ' || v_reason);
            IF gf.reversal IS NOT NULL THEN nr := nr + 1; END IF;
            UPDATE finance.legacy_payref SET reference = m.target_reference
             WHERE reference = pr.reference AND NOT EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.reference = m.target_reference);
            INSERT INTO finance.old_payment_withdrawn (id, reference, double_kind, kept_reference, student_id, session, purpose, amount, confirmed_at, channel,
                                                       receipt_no, note, ledger_journal, reversal_journal, withdrawn_by, reason)
            VALUES (pr.id, pr.reference, 'MISLABELLED', m.target_reference, pr.student_id, pr.session, pr.purpose, pr.amount, pr.confirmed_at, pr.channel,
                    pr.receipt_no, pr.note, gf.journal, gf.reversal, v_actor, v_reason);
            DELETE FROM finance.payment_reference WHERE id = pr.id;
            nw := nw + 1;
        ELSIF m.action = 'RENAME' THEN
            -- taken since the list was read (two records of one item in this batch): the next batch reads it again
            IF EXISTS (SELECT 1 FROM finance.payment_reference x WHERE x.reference = m.target_reference OR x.receipt_no = 'LEG-' || m.target_reference) THEN CONTINUE; END IF;
            -- posted under the income account the code read as, and under the old reference: let go, so the sync posts the
            -- renamed record under its item, once (left standing, the renamed reference would have been posted a second time)
            SELECT * INTO gf FROM finance.gl_free_payment(pr.reference, pr.id, 'PAYMENT_CORRECTED',
                                                         'the payment ' || pr.reference || ' is ' || m.target_purpose || ' (' || m.target_reference || '): ' || v_reason);
            IF gf.reversal IS NOT NULL THEN nr := nr + 1; END IF;
            UPDATE finance.payment_reference SET reference = m.target_reference, receipt_no = 'LEG-' || m.target_reference, purpose = m.target_purpose
             WHERE id = pr.id;
            INSERT INTO finance.legacy_item_corrected (payment_id, old_reference, new_reference, old_purpose, new_purpose, action, ledger_journal, reversal_journal, corrected_by, reason)
            VALUES (pr.id, pr.reference, m.target_reference, pr.purpose, m.target_purpose, 'RENAME', gf.journal, gf.reversal, v_actor, v_reason);
            nre := nre + 1;
        ELSE
            -- the same reference under another item: posted afresh under its account
            SELECT * INTO gf FROM finance.gl_free_payment(pr.reference, pr.id, 'PAYMENT_CORRECTED',
                                                         'the payment ' || pr.reference || ' is ' || m.target_purpose || ': ' || v_reason);
            IF gf.reversal IS NOT NULL THEN nr := nr + 1; END IF;
            UPDATE finance.payment_reference SET purpose = m.target_purpose WHERE id = pr.id;
            INSERT INTO finance.legacy_item_corrected (payment_id, old_reference, new_reference, old_purpose, new_purpose, action, ledger_journal, reversal_journal, corrected_by, reason)
            VALUES (pr.id, pr.reference, pr.reference, pr.purpose, m.target_purpose, 'RELABEL', gf.journal, gf.reversal, v_actor, v_reason);
            nrl := nrl + 1;
        END IF;
    END LOOP;
    SELECT count(*) FILTER (WHERE x.action = 'UNKNOWN_CODE'), count(*) FILTER (WHERE x.action <> 'UNKNOWN_CODE') INTO nu, v_left FROM finance.legacy_mislabelled() x;
    RETURN QUERY SELECT nre, nrl, nw, nr, nu, v_left;
END $fn$;
COMMENT ON FUNCTION finance.put_right_legacy_items(text, int) IS
  'V498: puts right up to p_limit of the records finance.legacy_mislabelled lists — renamed to the record their item makes or relabelled (each kept on finance.legacy_item_corrected), or withdrawn when the same payment is on record under its item (finance.old_payment_withdrawn, kind MISLABELLED); either way its ledger journal reversed and freed (finance.gl_free_payment), so a renamed or relabelled record is posted afresh under its item; a code the list does not name waits.';

-- ── 3 · reconciled against the fee setup ─────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.old_fees_reconciliation(p_session text)
RETURNS TABLE (student_id uuid, number text, name text, programme_code text, faculty_code text, level int, due numeric, paid numeric,
               paid_old_s1 numeric, paid_old_s2 numeric, paid_old_session numeric, paid_payment_history numeric, paid_portal numeric,
               old_payments int, difference numeric, state text)
LANGUAGE sql STABLE AS $$
    WITH pay AS MATERIALIZED (
        SELECT r.student_id,
               sum(r.amount) AS paid,
               coalesce(sum(r.amount) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' AND r.purpose LIKE '% semester 1'), 0) AS s1,
               coalesce(sum(r.amount) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' AND r.purpose LIKE '% semester 2'), 0) AS s2,
               coalesce(sum(r.amount) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' AND r.purpose NOT LIKE '% semester _'), 0) AS whole,
               coalesce(sum(r.amount) FILTER (WHERE r.reference NOT LIKE 'MOAUM-%'), 0) AS hist,
               coalesce(sum(r.amount) FILTER (WHERE r.reference LIKE 'MOAUM-%' AND r.reference NOT LIKE 'MOAUM-LEG-%'), 0) AS portal,
               count(*) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' OR r.reference NOT LIKE 'MOAUM-%')::int AS old_n
          FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
         GROUP BY r.student_id
        HAVING count(*) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' OR r.reference NOT LIKE 'MOAUM-%') > 0),
    ch AS MATERIALIZED (SELECT c.student_id, c.total FROM finance.session_charges(p_session) c)
    SELECT p.student_id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, s.programme_code, pr.faculty_code,
           reporting.level_in_session(s.entry_level, s.entry_session, s.current_level, s.entry_mode, p_session),
           coalesce(ch.total, 0), p.paid, p.s1, p.s2, p.whole, p.hist, p.portal, p.old_n, p.paid - coalesce(ch.total, 0),
           CASE WHEN coalesce(ch.total, 0) <= 0 THEN 'NO_FEE_STATED'
                WHEN finance.fee_short(ch.total, p.paid) THEN 'UNDER'
                WHEN p.paid - ch.total >= 1 THEN 'OVER'
                ELSE 'MATCHED' END
      FROM pay p
      JOIN people.student s ON s.id = p.student_id
      LEFT JOIN ref.programme pr ON pr.code = s.programme_code
      LEFT JOIN ch ON ch.student_id = p.student_id
$$;
COMMENT ON FUNCTION finance.old_fees_reconciliation(text) IS
  'V498: every student with an old-portal school-fees payment in the session — due by the fee setup (finance.session_charges), paid (old portal by semester and whole session, the retired Payment History Upload, the portal), the difference and the state: UNDER, OVER, MATCHED, or NO_FEE_STATED when the setup charges the student nothing.';

COMMIT;
