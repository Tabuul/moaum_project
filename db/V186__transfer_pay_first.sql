-- ═══════════════════════════════════════════════════════════════════════════
-- V186 — inter-departmental transfer: pay first, then the approvals
--
--   The order changes: after a student applies, the next step is the payment.
--   The non-refundable processing fee is paid up front; only then does the
--   current department (and the offices after it) approve. The last approval,
--   by the Academic office, completes the transfer on the register — there is
--   no separate "approved, awaiting fee" step at the end any more.
--
--     Applied → Payment → Current department → New department → Registrar
--            → Academic office (completes it on the register)
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM set_config('moaum.reason', 'V186: transfer pay-first ordering', true);
END $seed$;

-- the fee reference may be generated as soon as the student has applied (pay-first), and stays available
-- through the approval chain; the old post-Senate states are kept permissive so historical rows still work
CREATE OR REPLACE FUNCTION people.transfer_fee_reference(p_id uuid)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE t people.transfer_application; v_name text; v_ref text;
BEGIN
    SELECT * INTO t FROM people.transfer_application WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR t.state NOT IN ('APPLIED','FROM_OK','TO_OK','REG_OK','RECOMMENDED','APPROVED') THEN
        RAISE EXCEPTION 'application % is not open for payment', p_id USING ERRCODE = '23514';
    END IF;
    IF t.fee_reference IS NOT NULL THEN RETURN t.fee_reference; END IF;
    SELECT name INTO v_name FROM ref.programme WHERE code = t.to_programme_code;
    v_ref := finance.new_purpose_reference(t.student_id, t.session, people.transfer_fee(),
                'Inter-departmental transfer to ' || coalesce(v_name, t.to_programme_code));
    UPDATE people.transfer_application SET fee_reference = v_ref WHERE id = p_id;
    RETURN v_ref;
END $$;

-- one desk's Approve. The current department cannot approve until the fee is confirmed (pay-first). The
-- Academic office's approval (the last step) completes the transfer on the register in the same act.
CREATE OR REPLACE FUNCTION people.approve_transfer(p_id uuid)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; t people.transfer_application; v_paid boolean := false;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a transfer is approved by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM people.transfer_application WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such transfer application' USING ERRCODE = '23503'; END IF;
    IF t.fee_reference IS NOT NULL THEN
        SELECT (fs.confirmed_at IS NOT NULL) INTO v_paid FROM finance.reference_state(t.fee_reference) fs;
    END IF;
    IF t.state = 'APPLIED' THEN
        IF NOT v_paid THEN
            RAISE EXCEPTION 'the non-refundable processing fee has not been paid' USING ERRCODE = '23514',
                HINT = 'The student pays the fee before the current department approves.';
        END IF;
        UPDATE people.transfer_application SET state = 'FROM_OK', from_dept_at = now(), from_dept_by = who WHERE id = p_id;
        RETURN 'FROM_OK';
    ELSIF t.state = 'FROM_OK' THEN
        UPDATE people.transfer_application SET state = 'TO_OK', to_dept_at = now(), to_dept_by = who WHERE id = p_id;
        RETURN 'TO_OK';
    ELSIF t.state = 'TO_OK' THEN
        UPDATE people.transfer_application SET state = 'REG_OK', reg_at = now(), reg_by = who WHERE id = p_id;
        RETURN 'REG_OK';
    ELSIF t.state = 'REG_OK' THEN
        IF NOT v_paid THEN
            RAISE EXCEPTION 'the processing fee is not confirmed' USING ERRCODE = '23514';
        END IF;
        UPDATE people.student SET programme_code = t.to_programme_code,
               current_level = coalesce(t.recommended_level, current_level)
         WHERE id = t.student_id;
        UPDATE people.transfer_application SET state = 'EFFECTED', acad_at = now(), acad_by = who,
               effected_at = now(), effected_by = who WHERE id = p_id;
        RETURN 'EFFECTED';
    ELSE
        RAISE EXCEPTION 'application % has no approval pending at this stage (%).', p_id, t.state USING ERRCODE = '23514';
    END IF;
END $$;

COMMIT;
