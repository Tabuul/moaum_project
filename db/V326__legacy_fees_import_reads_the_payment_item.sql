-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V326 — the Old Fees History import reads the old portal's payment item: a GST payment is the GST fee
--
--   The Bursary's old-portal export ("paymentRECENT with pay_item") carries a Purpose/Payment Item column — SCHOOL
--   FEES, GST FEES, POST UTME APPLICATION, ACCEPTANCE LETTER, ADMISSION CHECKING… — and a Semester column that says
--   First, Second or Session. The screen never read the item column and the importer read a semester only as a
--   digit, so every GST payment went onto the ledger as "School fees (legacy)" (which the GST gate does not count),
--   the second semester's school fees collided with the first's on one reference and were dropped as duplicates,
--   and admission-checking and acceptance money was filed as school fees too.
--
--   Now:
--     · the screen sends the item as `purpose`; an explicit item is what the money was for, whatever it says — only
--       a free-text Note still has to name another purpose to be read as one;
--     · an item the GST type map (V323) knows — GST, GNS, General Studies, EPS — is recorded as the GST fee of the
--       session the row names: purpose 'GST fee <session>', which finance.gst_entitlement counts, so the student's
--       GST gate opens and the GST desk reads PAID from the old portal;
--     · a semester reads as First/1st/1, Second/2nd/2, Third/3; Session, Full or blank is the whole session;
--     · a row already on the ledger from an earlier upload of the same export — as school fees without a semester,
--       because the screen could not tell — is corrected in place when this upload says more: the semester is put on
--       it, or it is relabelled to the item (GST fee, admission checking…). One ledger row, not two; the amount is
--       never touched. So re-uploading the export converges: nothing doubles, nothing is lost;
--     · the old portal's own reference and channel are kept on the note, for the eye and for V323's reconciliation.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V326: the Old Fees History import reads the old portal''s payment item; a GST payment is the GST fee', true);

/* a semester as an old-portal export writes it */
CREATE OR REPLACE FUNCTION finance.legacy_semester(p text)
RETURNS int LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN t ~* '^(first|1st)' OR t ~ '^(sem(ester)?\s*)?1$' OR t ~* '^(semester\s*)?(one)$' THEN 1
        WHEN t ~* '^(second|2nd)' OR t ~ '^(sem(ester)?\s*)?2$' OR t ~* '^(semester\s*)?(two)$' THEN 2
        WHEN t ~* '^(third|3rd)' OR t ~ '^(sem(ester)?\s*)?3$' OR t ~* '^(semester\s*)?(three)$' THEN 3
        WHEN t ~ '^[0-9]+$' AND t::int IN (1, 2, 3) THEN t::int
        ELSE NULL END
      FROM (SELECT lower(btrim(coalesce(p, ''))) AS t) x
$$;
COMMENT ON FUNCTION finance.legacy_semester(text) IS
  'V326: a semester as the old portal writes it — First/1st/1, Second/2nd/2, Third/3rd/3; Session, Full, blank or anything else is the whole session (NULL).';

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
  'The Old Fees History import (V087, V301–V305, V326): rows of matriculation number, session, semester (First/Second/1/2 or blank), level, amount (blank = cleared in full against the schedule), the old portal''s payment item, paid date, old reference, channel, note. A GST item is recorded as ''GST fee <session>'' and counts for the GST gate; any other explicit item is its own purpose; a row already on the ledger as school fees from an upload that could not tell more is corrected in place (semester put on, or relabelled), never doubled.';

COMMIT;
