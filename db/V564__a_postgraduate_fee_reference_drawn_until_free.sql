-- ═══════════════════════════════════════
-- V564 — A postgraduate fee reference is drawn until a free one is found
--
--   Reported 19 Oct 2026: the postgraduate application refused new applicants with "An application already exists for this
--   email", though they had never applied. A postgraduate fee reference reads MOAUM-PGAPP-000123 (PGCHK for checking, PGACC for
--   acceptance): its number comes from a series kept for each session (platform.next_number('PG_FEEREF', 'UNIVERSITY', session)),
--   but the reference carries no session. When the postgraduate intake moved to 2026/2027 (V452) that session's series began at 1
--   and drew MOAUM-PGAPP-000001 again — a reference 2025/2026 had already issued. The unique reference refused it, the whole
--   application rolled back (the series with it, so the next applicant drew 000001 again), and the apply door read any duplicate
--   as an application already made on the email. On the Railway copy 2025/2026 had issued numbers up to 19; every applicant of
--   2026/2027 would be refused until that number was passed, which it never could be.
--
--   admissions.pg_new_fee_reference now inserts the reference ON CONFLICT DO NOTHING and, when it is taken, carries the
--   session's series past every number a postgraduate fee reference has used, then draws again (fifty times at most, as V390
--   does for the undergraduate reference). The format, the amounts and the expiry stand. The apply door (PgApplyController) says
--   "already exists" only when the applicant's own email or application is the duplicate.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V564: a postgraduate fee reference drawn until free', true);

CREATE OR REPLACE FUNCTION admissions.pg_new_fee_reference(p_application uuid, p_kind text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE v_session text; v_amt numeric; v_ref text; v_rule record; v_try int; v_top bigint;
BEGIN
    SELECT session INTO v_session FROM admissions.pg_application WHERE id = p_application;
    IF v_session IS NULL THEN
        RAISE EXCEPTION 'no such postgraduate application';
    END IF;
    SELECT * INTO v_rule FROM admissions.pg_fee_rule(v_session);
    v_amt := CASE p_kind WHEN 'ACCEPTANCE' THEN v_rule.acceptance_fee
                         WHEN 'CHECKING'   THEN v_rule.checking_fee
                         ELSE v_rule.application_fee END;
    -- V564: the series is the session's but the reference names no session, so a new session's series draws numbers an earlier
    -- one issued: a taken reference carries the series past every postgraduate fee reference's number, and is drawn again
    FOR v_try IN 1..50 LOOP
        v_ref := 'MOAUM-PG' || CASE p_kind WHEN 'ACCEPTANCE' THEN 'ACC' WHEN 'CHECKING' THEN 'CHK' ELSE 'APP' END || '-'
                 || lpad(platform.next_number('PG_FEEREF', 'UNIVERSITY', v_session)::text, 6, '0');
        INSERT INTO admissions.pg_fee_reference (application_id, kind, reference, amount, expires_at)
        VALUES (p_application, p_kind, v_ref, v_amt, now() + interval '24 hours')
        ON CONFLICT (reference) DO NOTHING;
        IF FOUND THEN RETURN v_ref; END IF;
        SELECT max(substring(f.reference FROM '-([0-9]+)$')::bigint) INTO v_top
          FROM admissions.pg_fee_reference f WHERE f.reference ~ '^MOAUM-PG(APP|CHK|ACC)-[0-9]+$';
        UPDATE platform.number_series SET next_value = greatest(next_value, coalesce(v_top, 0) + 1)
         WHERE kind = 'PG_FEEREF' AND scope = 'UNIVERSITY' AND session = v_session;
    END LOOP;
    RAISE EXCEPTION 'PG_FEE_REFERENCE_EXHAUSTED: no free % reference was found in fifty draws', lower(p_kind) USING ERRCODE = '23514',
        HINT = 'Try again; if it persists, tell the Directorate of ICT.';
END;
$function$;
COMMENT ON FUNCTION admissions.pg_new_fee_reference(uuid, text) IS
  'V202, V223, V564: a postgraduate fee reference (MOAUM-PGAPP/PGCHK/PGACC-NNNNNN) for the application''s session and kind, at the session''s fee; a reference already taken — the series is the session''s, the reference names none — carries the series past every number used and is drawn again.';

COMMIT;
