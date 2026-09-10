-- ═══════════════════════════════════════════════════════════════════════════
-- reset-jamb-list.sql — delete the uploaded JAMB (CAPS) list and O'Level, and the
--                       applicant intake built on it; keep the admission
--                       configuration AND any students already on the register
--
--   Use this to clear a test upload and start the intake again without losing the
--   admission policy you configured, and without disturbing students who were
--   already admitted and matriculated.
--
--   DELETES:
--     • the CAPS batches and rows (the JAMB list), the candidates on them, their
--       photographs, attachments and O'Level results;
--     • the applicant intake: applicant accounts, applications and their documents,
--       fee references, screening batches, clearance documents and password resets.
--
--   KEEPS:
--     • admission settings and policy: cut-offs, faculty quotas, selection criteria,
--       programme and subject rules, closed programmes, catchment LGAs, the O'Level
--       grading scale and compulsory subjects, the application-fee amount, and which
--       programmes require post-UTME;
--     • every student already on the register and all their records — each is simply
--       detached from the candidate row being deleted (its candidate link is cleared);
--     • the academic structure, staff, payroll, finance and the gateway keys.
--
--   NOT a Flyway migration. Take a backup, then run it yourself:
--
--       psql "$DATABASE_URL" -v confirm=WIPE -f db/reset-jamb-list.sql
--
--   Then upload a fresh CAPS list on the portal (JAMB admission lists). Everything
--   runs in one transaction: any error rolls the whole thing back.
-- ═══════════════════════════════════════════════════════════════════════════

\set ON_ERROR_STOP on

\if :{?confirm}
\else
  \echo ''
  \echo '****  REFUSING TO RUN  ****'
  \echo 'This deletes the uploaded JAMB list, O''Level and applicant intake.'
  \echo 'Take a backup, then re-run with:'
  \echo '    psql "$DATABASE_URL" -v confirm=WIPE -f db/reset-jamb-list.sql'
  \echo ''
  \quit
\endif

SELECT (:'confirm' = 'WIPE') AS ok \gset
\if :ok
\else
  \echo 'The confirm value must be exactly WIPE. Nothing was changed.'
  \quit
\endif

BEGIN;

-- every deletion is an attributed act on the audit spine (V002)
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'academic', true);
SELECT set_config('moaum.reason', 'reset-jamb-list.sql: cleared the JAMB list, O''Level and applicant intake; kept config and students', true);

-- keep students on the register; detach them from the candidate rows being deleted
UPDATE people.student SET candidate_id = NULL WHERE candidate_id IS NOT NULL;

-- ── the applicant intake (built on the JAMB list) ──
DELETE FROM admissions.password_reset;
DELETE FROM admissions.clearance_document;
DELETE FROM admissions.application_document_blob;
DELETE FROM admissions.application_document;
DELETE FROM admissions.fee_reference;
DELETE FROM platform.session WHERE active_office = 'applicant';
DELETE FROM admissions.application;
DELETE FROM admissions.applicant_account;
DELETE FROM admissions.applicant_event;
DELETE FROM admissions.screening_batch;

-- ── the O'Level, then the JAMB (CAPS) list itself ──
DELETE FROM admissions.olevel_grade;
DELETE FROM admissions.olevel_sitting;
DELETE FROM admissions.candidate_photo;
DELETE FROM admissions.attachment;
DELETE FROM admissions.candidate;
DELETE FROM admissions.caps_row;
DELETE FROM admissions.caps_row_excluded;
DELETE FROM admissions.caps_batch;

DO $$
BEGIN
    RAISE NOTICE 'JAMB list reset: % candidates, % applications, % CAPS rows remain; % students kept',
        (SELECT count(*) FROM admissions.candidate),
        (SELECT count(*) FROM admissions.application),
        (SELECT count(*) FROM admissions.caps_row),
        (SELECT count(*) FROM people.student);
END $$;

COMMIT;
