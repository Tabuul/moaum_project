-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V502 — What the retired Payment History Upload recorded, put right
--
--   V498 retired Payment History Upload and withdraws what it recorded twice — a payment it recorded that Old Fees History also
--   has. What it recorded alone was left as it wrote it, and it wrote every row its own way: the file's item as the purpose when
--   the file had a column it read for one ("SCHOOL FEES", "GST FEES", a code such as 10048), else "School fees <session>"; no
--   semester; and a date it could not read (the export's dates are spreadsheet day numbers) as the day of the upload. The fee
--   gate, the positions and the reconciliation count a payment as school fees by a purpose that begins "School fees", so a paid
--   semester recorded as "SCHOOL FEES" was shown as owed (seen on AWS, 16 Oct 2026: PR202610077052390 "did not reconcile").
--
--   1 · Old Fees History takes it over. When the old portal's export names a payment by its number (payref) and the retired door
--       recorded that payment under the number (as its reference, or its receipt) while no Old Fees History record has it, that
--       record becomes the one the row makes: its item, its semester, the day paid, the session; the number kept on
--       finance.legacy_payref; the change on finance.legacy_item_corrected (TAKEN_OVER, what it was before); its ledger posting
--       let go (finance.gl_free_payment), so the sync posts it again under its item. One record per payment, nothing to
--       withdraw. The import counts these (taken_over).
--   2 · What it recorded alone under the old portal's item name or code is listed with the records under a code
--       (finance.legacy_mislabelled) and relabelled by finance.put_right_legacy_items: school fees as "School fees <session>",
--       the GST fee as "GST fee <session>", another item by its name — so it counts as what it was. A record repeating another
--       is left to the doubles (withdrawn, not relabelled).
--   3 · finance.payment_history_left(): what the retired door recorded that nothing has matched — neither taken over nor a
--       double — with what it counts as now, for the Bursary's list.
--   And: a record something points at by its reference (a deferment fee, a refund, the GST reconciliation, the GST desk's
--   review, a gateway test reference) is never renamed — V498's put-right relabels it instead (a rename was refused by the
--   reference's foreign keys, and stopped the whole batch).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V502: what the retired Payment History Upload recorded, put right', true);

-- the register of what was put right takes the new act
ALTER TABLE finance.legacy_item_corrected DROP CONSTRAINT legacy_item_corrected_action_check;
ALTER TABLE finance.legacy_item_corrected ADD CONSTRAINT legacy_item_corrected_action_check CHECK (action IN ('RENAME', 'RELABEL', 'TAKEN_OVER'));
COMMENT ON TABLE finance.legacy_item_corrected IS
  'V498, V502: every old-portal record put right — renamed to the record its item makes, relabelled, or (V502) a record of the retired Payment History Upload taken over by Old Fees History — with what it was before, its ledger journal and the reversal posted for it (the sync posts it afresh under its item), and why.';

/* something points at a payment record by its reference (or its id): it is never renamed, nor taken over */
CREATE FUNCTION finance.payment_reference_linked(p_reference text, p_id uuid)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT EXISTS (SELECT 1 FROM people.deferment_fee f WHERE f.reference = p_reference)
        OR EXISTS (SELECT 1 FROM finance.refund r WHERE r.source_reference = p_reference)
        OR EXISTS (SELECT 1 FROM finance.legacy_gst_reconciliation g WHERE g.payment_reference_id = p_id)
        OR EXISTS (SELECT 1 FROM finance.gst_payment_review v WHERE v.reference = p_reference)
        OR EXISTS (SELECT 1 FROM finance.gateway_test_reference t WHERE t.reference = p_reference)
$fn$;
COMMENT ON FUNCTION finance.payment_reference_linked(text, uuid) IS
  'V502: whether a deferment fee, a refund, the GST reconciliation, the GST desk''s review or a gateway test reference points at the payment record — a record so pointed at keeps its reference.';

-- ── 1 · Old Fees History takes over the retired door's record of a payment ────────────────────────────────────────────────
DROP FUNCTION finance.import_legacy_payments(jsonb);
CREATE FUNCTION finance.import_legacy_payments(p_rows jsonb)
RETURNS TABLE (rows int, cleared int, no_student int, no_due int, duplicates int, duplicate_sample text, corrected int, undated int,
               matched int, separate int, taken_over int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_session text; v_sem int; v_amount numeric; v_sid uuid; v_when timestamptz; v_given timestamptz;
        v_ref text; v_base text; v_base0 text; v_rcpt text; v_key text; v_tag text; v_note text; v_cnt int;
        v_level int; v_item text; v_free text; v_text text; v_other boolean; v_gst boolean; v_slug text;
        v_old_ref text; v_payref text; v_channel text; v_separate boolean; st people.student; ex finance.payment_reference;
        ph finance.payment_reference; gf record;
        v_reason text := coalesce(nullif(btrim(coalesce(current_setting('moaum.reason', true), '')), ''), 'the old portal''s export names this payment');
        n int := 0; nc int := 0; nns int := 0; nnd int := 0; nd int := 0; nfix int := 0; nund int := 0; nm int := 0; nsep int := 0; ntk int := 0;
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

        -- V502: the retired Payment History Upload recorded this payment under its number (as the reference, or the receipt) and
        -- no Old Fees History record has it: that record becomes the one this row makes — the item, the semester, the day paid,
        -- the session — so the payment is on record once. That door read every row as school fees whatever it was, without a
        -- semester, and dated a row it could not read with the day of the upload. Its ledger posting is let go (reversed and
        -- freed), so the sync posts the payment again under its item; a record something points at by its reference is left.
        IF v_payref IS NOT NULL THEN
            ph := NULL;
            SELECT x.* INTO ph FROM finance.payment_reference x
             WHERE x.student_id = v_sid AND x.reference NOT LIKE 'MOAUM-%' AND x.confirmed_at IS NOT NULL
               AND (upper(btrim(x.reference)) = v_payref OR upper(btrim(x.receipt_no)) = v_payref)
               AND NOT finance.payment_reference_linked(x.reference, x.id)
             ORDER BY (upper(btrim(x.reference)) = v_payref) DESC, x.reference
             LIMIT 1;
            IF ph.id IS NOT NULL THEN
                IF EXISTS (SELECT 1 FROM finance.payment_reference x WHERE (x.reference = v_ref OR x.receipt_no = 'LEG-' || v_ref) AND x.id <> ph.id) THEN
                    v_ref := v_ref || '-' || left(regexp_replace(v_payref, '[^0-9A-Z]', '', 'g'), 30);
                END IF;
                SELECT * INTO gf FROM finance.gl_free_payment(ph.reference, ph.id, 'PAYMENT_CORRECTED',
                    'the payment ' || ph.reference || ' recorded by Payment History Upload is ' || v_tag || ' (' || v_ref || '): ' || v_reason);
                v_when := coalesce(v_given, ph.confirmed_at);
                UPDATE finance.payment_reference
                   SET reference = v_ref, receipt_no = 'LEG-' || v_ref, purpose = v_tag, session = v_session,
                       amount = coalesce(v_amount, amount), confirmed_at = v_when, expires_at = v_when, channel = 'Legacy',
                       note = v_note || ' · first recorded by Payment History Upload as ' || ph.reference
                 WHERE id = ph.id;
                INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, v_ref, coalesce(v_amount, ph.amount));
                INSERT INTO finance.legacy_item_corrected (payment_id, old_reference, new_reference, old_purpose, new_purpose, action,
                                                           ledger_journal, reversal_journal, corrected_by, reason)
                VALUES (ph.id, ph.reference, v_ref, ph.purpose, v_tag, 'TAKEN_OVER', gf.journal, gf.reversal, v_actor, v_reason);
                ntk := ntk + 1;
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

    RETURN QUERY SELECT n, nc, nns, nnd, nd, array_to_string(v_dups, ', '), nfix, nund, nm, nsep, ntk;
END $$;
COMMENT ON FUNCTION finance.import_legacy_payments(jsonb) IS
  'The Old Fees History import (V087, V301–V305, V326, V449, V498, V502): rows of matriculation number, session, semester (First/Second/1/2 or blank), level, amount (blank = cleared in full against the schedule), the old portal''s payment item, paid date, the old portal''s payment number (payref), channel, note. V498: the payment number decides — seen before, the same payment; new, it attaches to a record of its key that has none and the same amount, else it is its own record (a make-up or second part-payment beside the first). V502: a payment the retired Payment History Upload recorded under its number, and no Old Fees History record has, is taken over — that record becomes this one (item, semester, day; its ledger posting let go) — counted as taken_over. A file without numbers is read as before. A GST item is recorded as ''GST fee <session>''; any other explicit item is its own purpose.';

-- ── 2 · what the retired door recorded alone under the old portal's item name or code, relabelled ─────────────────────────
CREATE OR REPLACE FUNCTION finance.legacy_mislabelled()
RETURNS TABLE (id uuid, reference text, student_id uuid, number text, name text, session text, amount numeric, paid_on date,
               stored_purpose text, item text, known boolean, target_reference text, target_purpose text, action text)
LANGUAGE sql STABLE AS $fn$
    WITH r AS (
        -- Old Fees History records under a code, or an older importer's label (V498)
        SELECT p.*, regexp_replace(p.purpose, ' \(legacy\)( · semester [0-9])?$', '') AS text0,
               substring(p.purpose FROM ' · semester ([0-9])$')::int AS sem,
               substring(p.reference FROM '^(MOAUM-LEG-[0-9A-Z]+-[0-9]{4}-[0-9]{4})') AS base0, false AS door
          FROM finance.payment_reference p
         WHERE p.reference LIKE 'MOAUM-LEG-%' AND p.reference NOT LIKE 'MOAUM-LEG-GST-%' AND p.channel = 'Legacy' AND p.confirmed_at IS NOT NULL
           AND p.purpose LIKE '% (legacy)%' AND p.purpose NOT LIKE 'School fees%' AND p.purpose NOT LIKE 'GST fee %'
        UNION ALL
        -- V502: the retired Payment History Upload's records under the old portal's item name or code ("SCHOOL FEES", "GST FEES",
        -- "10048") — not read as school fees by the fee gate; one that repeats another record (withdrawn as a double, by the
        -- same test finance.old_payment_doubles makes) is not relabelled
        SELECT p.*, btrim(p.purpose), NULL::int, NULL::text, true
          FROM finance.payment_reference p
         WHERE p.reference NOT LIKE 'MOAUM-%' AND p.confirmed_at IS NOT NULL
           AND p.purpose NOT LIKE 'School fees%' AND p.purpose NOT LIKE 'GST fee %'
           AND NOT EXISTS (SELECT 1 FROM finance.payment_reference x
                            WHERE x.student_id = p.student_id AND x.session = p.session AND x.id <> p.id AND x.confirmed_at IS NOT NULL
                              AND abs(x.amount - p.amount) < 1
                              AND ((x.reference LIKE 'MOAUM-LEG-%' AND x.channel = 'Legacy') OR (x.reference NOT LIKE 'MOAUM-%' AND x.reference < p.reference))
                              AND ((x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (p.confirmed_at AT TIME ZONE 'Africa/Lagos')::date
                                   OR (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = finance.payref_day(p.reference)
                                   OR EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.payref = upper(btrim(p.reference)) AND k.reference = x.reference)))),
    c AS (
        SELECT r.*, (r.text0 ~ '^[0-9]+$') AS coded,
               CASE WHEN r.text0 ~ '^[0-9]+$' THEN (SELECT k.description FROM finance.legacy_item_code k WHERE k.code = r.text0) ELSE r.text0 END AS item0
          FROM r WHERE r.base0 IS NOT NULL OR r.door),
    -- V502: what each item is, read once an item (some 90,000 records of a few dozen other items took 19 s read a record at a
    -- time on a live-sized copy: finance.legacy_gst_type_of matches the item against every pattern of the map)
    i AS MATERIALIZED (
        SELECT d.item0, coalesce(finance.legacy_gst_type_of(d.item0), '') = 'GST' AS gst,
               coalesce(finance.legacy_gst_type_of(d.item0), '') <> 'GST' AND d.item0 ~* '(school|tuition|semester fee|session fee)' AS school
          FROM (SELECT DISTINCT c.item0 FROM c WHERE c.item0 IS NOT NULL) d),
    k AS (
        SELECT c.*, coalesce(i.gst, false) AS gst, coalesce(i.school, false) AS school
          FROM c LEFT JOIN i ON i.item0 = c.item0),
    t AS (
        SELECT k.*,
               CASE WHEN k.item0 IS NULL THEN NULL
                    WHEN k.door THEN k.reference
                    ELSE k.base0 || CASE WHEN k.sem IS NOT NULL THEN '-S' || k.sem ELSE '' END
                         || CASE WHEN k.gst THEN '-GST' WHEN k.school THEN '' ELSE '-' || left(regexp_replace(upper(k.item0), '[^0-9A-Z]', '', 'g'), 20) END END AS target_ref,
               CASE WHEN k.item0 IS NULL THEN NULL
                    WHEN k.gst THEN 'GST fee ' || k.session
                    -- the retired door's own form for school fees (what it wrote when the file named no item)
                    WHEN k.door AND k.school THEN 'School fees ' || k.session
                    WHEN k.door THEN k.item0
                    ELSE (CASE WHEN k.school THEN 'School fees' ELSE k.item0 END) || ' (legacy)' || CASE WHEN k.sem IS NOT NULL THEN ' · semester ' || k.sem ELSE '' END END AS target_purpose
          FROM k WHERE k.coded OR k.gst OR k.school)
    SELECT t.id, t.reference, t.student_id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, t.session, t.amount,
           (t.confirmed_at AT TIME ZONE 'Africa/Lagos')::date, t.purpose, t.item0, t.item0 IS NOT NULL, t.target_ref, t.target_purpose,
           CASE WHEN t.item0 IS NULL THEN 'UNKNOWN_CODE'
                WHEN t.target_ref = t.reference THEN 'RELABEL'
                WHEN x.id IS NOT NULL AND abs(x.amount - t.amount) < 1
                     AND (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (t.confirmed_at AT TIME ZONE 'Africa/Lagos')::date THEN 'DOUBLE'
                -- V502: a record something points at keeps its reference: relabelled, not renamed
                WHEN x.id IS NULL AND NOT finance.payment_reference_linked(t.reference, t.id) THEN 'RENAME'
                ELSE 'RELABEL' END
      FROM t
      JOIN people.student s ON s.id = t.student_id
      LEFT JOIN finance.payment_reference x ON x.reference = t.target_ref AND x.id <> t.id
$fn$;
COMMENT ON FUNCTION finance.legacy_mislabelled() IS
  'V498, V502: records under the old portal''s payment-item code ("10048 (legacy)"), under a label the rules now read otherwise ("GST FEES (legacy)" is the GST fee), or (V502) recorded by the retired Payment History Upload under the old portal''s item name or code ("SCHOOL FEES") and repeating nothing — with what the item is and what putting it right does: RENAME (to the record its item makes, so school fees count), RELABEL (the purpose only: the retired door''s records, a record whose place is taken, or one something points at), DOUBLE (the same payment is on record under its item: withdrawn), UNKNOWN_CODE (the code list does not name it yet).';

/* put right in batches (V498), restated: a record something points at by its reference is never renamed */
CREATE OR REPLACE FUNCTION finance.put_right_legacy_items(p_reason text, p_limit int DEFAULT 5000)
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
            -- V502: pointed at by its reference since the list was read: the next batch reads it again (as a relabel)
            IF finance.payment_reference_linked(pr.reference, pr.id) THEN CONTINUE; END IF;
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
  'V498, V502: puts right up to p_limit of the records finance.legacy_mislabelled lists (V502: the retired Payment History Upload''s too, relabelled) — renamed to the record their item makes or relabelled (each kept on finance.legacy_item_corrected), or withdrawn when the same payment is on record under its item (finance.old_payment_withdrawn, kind MISLABELLED); either way its ledger journal reversed and freed (finance.gl_free_payment), so a renamed or relabelled record is posted afresh under its item; a code the list does not name waits.';

-- ── 3 · what the retired door recorded that nothing has matched ──────────────────────────────────────────────────────────────
CREATE FUNCTION finance.payment_history_left()
RETURNS TABLE (id uuid, reference text, student_id uuid, number text, name text, session text, amount numeric, paid_on date,
               number_day date, purpose text, counts_as text)
LANGUAGE sql STABLE AS $fn$
    WITH d AS MATERIALIZED (SELECT x.double_id FROM finance.old_payment_doubles() x WHERE x.double_kind = 'PAYMENT_HISTORY')
    SELECT p.id, p.reference, p.student_id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, p.session, p.amount,
           (p.confirmed_at AT TIME ZONE 'Africa/Lagos')::date, finance.payref_day(p.reference), p.purpose,
           CASE WHEN p.purpose LIKE 'School fees%' THEN 'SCHOOL_FEES' WHEN p.purpose LIKE 'GST fee %' THEN 'GST' ELSE 'OTHER' END
      FROM finance.payment_reference p
      JOIN people.student s ON s.id = p.student_id
     WHERE p.reference NOT LIKE 'MOAUM-%' AND p.confirmed_at IS NOT NULL
       AND p.id NOT IN (SELECT d.double_id FROM d)
$fn$;
COMMENT ON FUNCTION finance.payment_history_left() IS
  'V502: every record the retired Payment History Upload made that nothing has matched — not taken over by Old Fees History (the export did not name its number) and not a double of another record — with the day its payment number carries and what it counts as now (SCHOOL_FEES, GST, OTHER).';

COMMIT;
