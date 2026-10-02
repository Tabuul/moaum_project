-- V305 — start the old-portal fees import over.
--
-- finance.legacy_payment_count counts what the import has loaded; finance.reset_legacy_payments deletes it.
-- Only the import's own records are ever touched: channel 'Legacy' AND a MOAUM-LEG- reference. A payment made
-- through the gateway, the bank or the Bursary desk is never in scope, and a record a deferment fee points at is
-- left alone. Every deleted row is on the audit spine (the table is audited), in the caller's name.
-- The caller must pass the word RESET, so a stray call cannot wipe the history.

BEGIN;

CREATE OR REPLACE FUNCTION finance.legacy_payment_count(p_session text DEFAULT NULL)
RETURNS TABLE (payments bigint, students bigint, total numeric, sessions text)
LANGUAGE sql STABLE AS $$
    SELECT count(*), count(DISTINCT student_id), coalesce(sum(amount), 0),
           coalesce(string_agg(DISTINCT session, ', ' ORDER BY session), '')
      FROM finance.payment_reference
     WHERE channel = 'Legacy' AND reference LIKE 'MOAUM-LEG-%'
       AND (p_session IS NULL OR session = p_session);
$$;

CREATE OR REPLACE FUNCTION finance.reset_legacy_payments(p_session text, p_confirm text)
RETURNS TABLE (deleted bigint, kept_in_use bigint)
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_del bigint; v_kept bigint;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'the imported payment history is reset by a person' USING ERRCODE = '23514'; END IF;
    IF p_confirm IS DISTINCT FROM 'RESET' THEN
        RAISE EXCEPTION 'type RESET to confirm that the imported payment history is to be deleted' USING ERRCODE = '23514';
    END IF;
    IF p_session IS NOT NULL AND p_session !~ '^[0-9]{4}/[0-9]{4}$' THEN
        RAISE EXCEPTION 'a session looks like 2022/2023' USING ERRCODE = '23514';
    END IF;

    SELECT count(*) INTO v_kept FROM finance.payment_reference r
     WHERE r.channel = 'Legacy' AND r.reference LIKE 'MOAUM-LEG-%' AND (p_session IS NULL OR r.session = p_session)
       AND EXISTS (SELECT 1 FROM people.deferment_fee d WHERE d.reference = r.reference);

    WITH gone AS (
        DELETE FROM finance.payment_reference r
         WHERE r.channel = 'Legacy' AND r.reference LIKE 'MOAUM-LEG-%' AND (p_session IS NULL OR r.session = p_session)
           AND NOT EXISTS (SELECT 1 FROM people.deferment_fee d WHERE d.reference = r.reference)
        RETURNING 1)
    SELECT count(*) INTO v_del FROM gone;

    RETURN QUERY SELECT v_del, v_kept;
END $$;

COMMIT;
