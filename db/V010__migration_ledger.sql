-- ════════════════════════════════════════════════════════════════════════
--  V010  ·  The deployment ledger, and why it is exempt from the spine
--
--  Found on 7 September 2026 by the property suite itself, the first time
--  the migrations were run through the deployment runner rather than by
--  hand: check.sql reported
--
--      FAIL  Every state table is attached to the spine   public.schema_migration
--
--  which is the check doing exactly what it is for. db/migrate.sh creates
--  public.schema_migration before any migration runs, to record what has
--  been applied and the checksum of the file that was applied — and a new
--  table that nothing audits is precisely what that property exists to
--  catch.
--
--  It is exempted rather than attached, for a reason that has to be
--  written down rather than assumed:
--
--    · it is written by the DEPLOYMENT, not by an office. There is no
--      actor, no acting office and no instrument, because no member of
--      staff decided anything — a release did.
--
--    · it already carries its own account of itself: the filename, the
--      SHA-256 of the file, when it was applied and by which database
--      role. An audit row would record the same facts a second time.
--
--    · attaching it would make it unwritable. The spine REFUSES a write
--      with no audit context, and the migration runner has none to give:
--      it runs before the application, as a database role, with no person
--      behind it. The first migration of every deployment would fail.
--
--  The table is created here as well as by the runner so that a database
--  built by any other means still has it, and so that this exemption has
--  something to point at.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.schema_migration (
    filename    text PRIMARY KEY,
    sha256      text NOT NULL,
    applied_at  timestamptz NOT NULL DEFAULT now(),
    applied_by  text NOT NULL DEFAULT current_user
);

COMMENT ON TABLE public.schema_migration IS
'What has been applied to this database, and the checksum of the file that '
'was applied. A migration edited after the fact is caught here rather than '
'discovered later as a column that does not exist.';

SELECT audit.exempt('public.schema_migration',
    'Written by the deployment, not by an office: no actor, no acting office '
    'and no instrument, because no member of staff decided anything. It carries '
    'its own account of itself — filename, SHA-256, when, and by which database '
    'role — so an audit row would record the same facts twice. Attaching it '
    'would also make it unwritable: the spine refuses a write with no audit '
    'context, and a migration runner has none to give.');

COMMIT;
