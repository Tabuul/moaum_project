-- ═══════════════════════════════════════════════════════════════════════════
-- V120 — import past students' payment (school-fees) history
--
--   The live payment flow (finance.new_reference → finance.confirm_payment) is
--   gated by the session's fee schedule and mints its own reference and
--   receipt. That is right for money paid THROUGH the portal, and wrong for
--   history carried over from the old portal: old sessions have no schedule,
--   and each payment already has its own reference, receipt, date and channel
--   that must be kept.
--
--   So this loads confirmed payment references directly. It is resilient (a bad
--   row is set aside, not fatal) and idempotent (a reference already present is
--   left alone), and it does NOT notify anyone — a migrated payment is a record,
--   not a fresh transaction. Attribution is the person running the import.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION finance.import_payments(p_rows jsonb)
RETURNS TABLE (rows int, imported int, duplicate int, no_student int, bad_amount int, skipped int, first_error text)
LANGUAGE plpgsql AS $$
DECLARE r jsonb;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_student uuid; v_session text; v_amount numeric; v_purpose text;
        v_date date; v_channel text; v_ref text; v_receipt text; v_note text; v_cnt int;
        n int := 0; ni int := 0; nd int := 0; nns int := 0; nba int := 0; ns int := 0; v_firsterr text := NULL;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a payment history is loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, session, amount, purpose, date' USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'matno', r->>'regNo', '')));
        IF v_matric = '' OR v_matric ~* '^matric' THEN CONTINUE; END IF;   -- blank or a header row
        n := n + 1;

        SELECT id INTO v_student FROM people.student
         WHERE upper(matric_no) = v_matric OR upper(admission_no) = v_matric OR upper(jamb_reg_no) = v_matric
         LIMIT 1;
        IF v_student IS NULL THEN nns := nns + 1; CONTINUE; END IF;

        v_amount := nullif(regexp_replace(coalesce(r->>'amount', r->>'amountPaid', r->>'amount_paid', r->>'paid', ''), '[^0-9.]', '', 'g'), '')::numeric;
        IF v_amount IS NULL OR v_amount <= 0 THEN nba := nba + 1; CONTINUE; END IF;

        BEGIN
            v_session := nullif(btrim(coalesce(r->>'session', r->>'academicSession', r->>'academic_session', '')), '');
            IF v_session IS NULL THEN v_session := 'LEGACY'; END IF;

            v_purpose := nullif(btrim(coalesce(r->>'purpose', r->>'paymentType', r->>'payment_type', r->>'category', r->>'feeType', r->>'fee', r->>'description', '')), '');
            IF v_purpose IS NULL THEN v_purpose := 'School fees ' || v_session; END IF;

            v_date := NULL;
            BEGIN v_date := (nullif(btrim(coalesce(r->>'date', r->>'paidOn', r->>'paid_on', r->>'paymentDate', r->>'payment_date', r->>'datePaid', '')), ''))::date;
            EXCEPTION WHEN OTHERS THEN v_date := NULL; END;
            IF v_date IS NULL THEN v_date := current_date; END IF;

            v_channel := upper(nullif(btrim(coalesce(r->>'channel', r->>'method', r->>'paymentMethod', r->>'payment_method', '')), ''));
            IF v_channel IS NULL THEN v_channel := 'MIGRATION'; END IF;

            v_note := nullif(btrim(coalesce(r->>'note', r->>'remark', r->>'narration', '')), '');
            IF v_note IS NULL THEN v_note := 'Migrated payment history'; END IF;

            -- keep the original reference/receipt when given; otherwise a stable one derived from the row
            v_ref := upper(nullif(btrim(coalesce(r->>'reference', r->>'ref', r->>'rrr', r->>'transactionRef', r->>'transaction_ref', r->>'receipt', r->>'receiptNo', r->>'receipt_no', '')), ''));
            IF v_ref IS NULL THEN
                v_ref := 'MIGR-' || coalesce(nullif(regexp_replace(v_matric, '[^0-9A-Z]', '', 'g'), ''), 'X') || '-' || upper(substr(md5(r::text), 1, 10));
            END IF;
            v_receipt := upper(nullif(btrim(coalesce(r->>'receipt', r->>'receiptNo', r->>'receipt_no', '')), ''));
            IF v_receipt IS NULL THEN v_receipt := 'RCT-MIGR-' || upper(substr(md5(v_ref), 1, 12)); END IF;

            INSERT INTO finance.payment_reference
                (student_id, session, reference, purpose, amount, generated_at, expires_at,
                 confirmed_at, confirmed_by, channel, note, receipt_no)
            VALUES (v_student, v_session, v_ref, v_purpose, v_amount,
                    v_date::timestamptz, v_date::timestamptz + interval '1 day',
                    v_date::timestamptz, v_actor, v_channel, v_note, v_receipt)
            ON CONFLICT (reference) DO NOTHING;

            GET DIAGNOSTICS v_cnt = ROW_COUNT;
            IF v_cnt > 0 THEN ni := ni + 1; ELSE nd := nd + 1; END IF;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_firsterr IS NULL THEN v_firsterr := left(v_matric || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
        END;
    END LOOP;

    RETURN QUERY SELECT n, ni, nd, nns, nba, ns, v_firsterr;
END $$;

COMMENT ON FUNCTION finance.import_payments(jsonb) IS
  'Bulk-load past students'' confirmed payment history, preserving the original '
  'reference, receipt, date and channel. Resilient and idempotent; sends no '
  'notice. Not for live payments — those go through confirm_payment.';

COMMIT;
