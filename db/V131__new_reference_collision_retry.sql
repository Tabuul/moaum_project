-- ═══════════════════════════════════════════════════════════════════════════
-- V131 — finance.new_reference: retry on a duplicate reference
--
--   The reference is MOAUM-FEE-<trailing matric digits>-<random 4 digits>. Two
--   students whose matriculation numbers share the same trailing digits differ
--   only by the random suffix, so the 4-digit suffix can collide (1 in 10 000),
--   and the demo seed — which mints a reference per student in a tight loop —
--   hit exactly that: "duplicate key value violates unique constraint
--   payment_reference_reference_key". A single unlucky draw failed the whole run.
--
--   The fix wraps the INSERT in a bounded retry: on a unique_violation the
--   suffix is redrawn and tried again (up to 20 times). Nothing else changes —
--   same reference shape, same validation, same guards. V026 defined this and is
--   already applied, so the new body goes here rather than editing V026.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION finance.new_reference(p_student uuid, p_session text, p_amount numeric, p_purpose text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE pos record; v_ref text; v_matric text; v_stem text; v_try int := 0;
BEGIN
    SELECT * INTO pos FROM finance.position(p_student, p_session);
    IF pos.due = 0 THEN
        RAISE EXCEPTION 'no charge is stated for % yet', p_session USING ERRCODE = '23514',
            HINT = 'The Bursar states the session''s fee schedule before anything is paid against it.';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'a payment is for an amount' USING ERRCODE = '23514';
    END IF;
    IF p_amount > pos.balance THEN
        RAISE EXCEPTION 'the amount % is more than the balance of %', p_amount, pos.balance USING ERRCODE = '23514',
            HINT = 'Pay the balance, or part of it; nothing is taken beyond what is owed.';
    END IF;
    SELECT coalesce(matric_no, admission_no, 'X') INTO v_matric FROM people.student WHERE id = p_student;
    v_stem := 'MOAUM-FEE-' || regexp_replace(right(v_matric, 7), '[^0-9A-Z]', '', 'g') || '-';
    LOOP
        v_try := v_try + 1;
        v_ref := v_stem || lpad((floor(random() * 10000))::int::text, 4, '0');
        BEGIN
            INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at)
            VALUES (p_student, p_session, v_ref, coalesce(p_purpose, 'School fees ' || p_session), p_amount, now() + interval '24 hours');
            RETURN v_ref;
        EXCEPTION WHEN unique_violation THEN
            IF v_try >= 20 THEN
                RAISE EXCEPTION 'could not mint a unique reference for % after % tries', v_matric, v_try USING ERRCODE = '23514';
            END IF;
        END;
    END LOOP;
END $$;

COMMIT;
