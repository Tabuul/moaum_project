-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V319 — an office grant is amended, with the reason on the record
--
--   A grant made in error on Users & Roles — the wrong office, the wrong department or programme, a
--   misquoted instrument, a wrong date — could only be ended and made again, which left a false grant on
--   the record and a second one beside it. iam.amend_grant changes the office, the scope, the instrument
--   and the dates of a live grant in place. The person is never changed (a grant belongs to who it was
--   made to; a wrong person is an ending and a new grant), an ended grant stays as it was, a reason is
--   required and written into the audit trail beside the old and the new values, and the scope goes
--   through the same rule as a new grant (V316/V317: the register's code, or refused).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V319: a grant is amended with its reason', true);

CREATE OR REPLACE FUNCTION iam.amend_grant(p_grant uuid, p_office text, p_scope_kind text, p_scope_id text, p_instrument text,
                                           p_valid_from date, p_valid_to date, p_reason text)
RETURNS iam.office_assignment
LANGUAGE plpgsql AS $$
DECLARE g iam.office_assignment;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'IAM_AMEND_SAYS_WHY: a grant is amended with the reason on the record, and none was given'
            USING ERRCODE = 'check_violation', HINT = 'Say what was wrong with the grant as made; it is written beside the change.';
    END IF;
    SELECT * INTO g FROM iam.office_assignment WHERE id = p_grant FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no grant %', p_grant USING ERRCODE = 'no_data_found';
    END IF;
    IF g.valid_to IS NOT NULL AND g.valid_to < current_date THEN
        RAISE EXCEPTION 'IAM_GRANT_ENDED: the grant ended on %; an ended grant stays as it was', g.valid_to
            USING ERRCODE = 'check_violation', HINT = 'Make a new grant for what the person holds now.';
    END IF;
    IF p_instrument IS NULL OR btrim(p_instrument) = '' THEN
        RAISE EXCEPTION 'IAM_GRANT_NEEDS_INSTRUMENT: an office is held under a letter or minute, and none was given'
            USING ERRCODE = 'check_violation';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM ref.office WHERE code = coalesce(nullif(btrim(p_office), ''), g.office_code)) THEN
        RAISE EXCEPTION 'IAM_NO_SUCH_OFFICE: % is not one of the offices on the register', p_office USING ERRCODE = 'check_violation';
    END IF;
    -- the reason goes into the audit trail beside the old and the new values
    PERFORM set_config('moaum.reason', 'grant amended: ' || btrim(p_reason), true);
    UPDATE iam.office_assignment
       SET office_code = coalesce(nullif(btrim(p_office), ''), office_code),
           scope_kind  = coalesce(nullif(btrim(p_scope_kind), ''), scope_kind),
           scope_id    = nullif(btrim(p_scope_id), ''),
           instrument  = btrim(p_instrument),
           valid_from  = coalesce(p_valid_from, valid_from),
           valid_to    = p_valid_to
     WHERE id = p_grant
     RETURNING * INTO g;
    RETURN g;
END $$;
COMMENT ON FUNCTION iam.amend_grant(uuid, text, text, text, text, date, date, text) IS
  'V319: a live grant''s office, scope, instrument and dates changed in place, with the reason written into the audit trail; the person is never changed; an ended grant is refused; the scope goes through the register''s rule (V316/V317).';

COMMIT;
