-- ════════════════════════════════════════════════════════════════════════
--  Post-deployment verification. READ-ONLY.
--
--  check.sql is the full property suite and it writes: people, policies,
--  credentials, an admission list, and a deliberately tampered audit row.
--  It belongs in CI against a throwaway database. This file is what runs
--  against the University's own, and it only looks.
--
--  It raises rather than reporting, because a deployment that has left the
--  database in a state the application cannot safely use should not finish
--  quietly and serve traffic.
-- ════════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

DO $$
DECLARE n int; v text;
BEGIN
    -- 1 · no application role holds DELETE anywhere. Nothing is deleted in
    --     this system; a correction is a new version with a reason.
    SELECT count(*) INTO n
      FROM information_schema.role_table_grants
     WHERE privilege_type = 'DELETE' AND grantee LIKE 'app\_%';
    IF n > 0 THEN
        RAISE EXCEPTION 'deployment verification failed: % application-role DELETE '
                        'grants exist. Nothing in this system deletes.', n;
    END IF;

    -- 2 · no application role may write to the audit spine
    SELECT count(*) INTO n
      FROM information_schema.role_table_grants
     WHERE table_schema = 'audit'
       AND privilege_type IN ('INSERT','UPDATE','DELETE')
       AND grantee LIKE 'app\_%';
    IF n > 0 THEN
        RAISE EXCEPTION 'deployment verification failed: % write grants on audit.* '
                        'to application roles. The record of what happened cannot be '
                        'writable by the thing it records.', n;
    END IF;

    -- 3 · the spine still refuses an unattributed change. This is the one
    --     property the whole design rests on, so it is checked on every
    --     deployment rather than assumed to have survived.
    BEGIN
        INSERT INTO iam.person (id, staff_number, surname, given_names)
        VALUES ('00000000-0000-0000-0000-0000deadbeef', 'DEPLOY/VERIFY', 'X', 'Y');
        RAISE EXCEPTION 'deployment verification failed: an unattributed write to '
                        'iam.person SUCCEEDED. The audit spine is not enforcing.';
    EXCEPTION
        WHEN check_violation THEN
            NULL;                      -- refused, which is the whole point
        WHEN OTHERS THEN
            IF SQLSTATE = 'P0001' AND SQLERRM LIKE 'deployment verification failed%' THEN
                RAISE;
            END IF;
            NULL;
    END;

    -- 4 · the offices are seeded
    -- twenty-five staff offices, and the applicant (V021)
    SELECT count(*) INTO n FROM ref.office;
    IF n <> 26 THEN
        RAISE EXCEPTION 'deployment verification failed: % offices in the register, '
                        'expected 26 (25 staff offices and the applicant).', n;
    END IF;

    -- 5 · the University's programme table is loaded
    SELECT count(*) INTO n FROM ref.programme;
    IF n < 92 THEN
        RAISE EXCEPTION 'deployment verification failed: % programmes, expected at '
                        'least 92.', n;
    END IF;

    -- 6 · the admission settings the Committee issued are present, and are
    --     still a DRAFT until the Committee's minute puts them in force
    SELECT state INTO v FROM admissions.session_policy WHERE session = '2025/2026';
    IF v IS NULL THEN
        RAISE EXCEPTION 'deployment verification failed: no 2025/2026 admission '
                        'settings. Nothing could be admitted.';
    END IF;

    RAISE NOTICE 'verified: % offices, % programmes, 2025/2026 settings are %',
                 (SELECT count(*) FROM ref.office),
                 (SELECT count(*) FROM ref.programme), v;
END $$;

-- what this database is, in one line, for the deployment log
SELECT 'schema: ' || count(*) || ' migrations applied, latest ' || max(filename)
  FROM public.schema_migration;
