-- V623: the audit trail screen (/audit) loads on a trail of any size. The University reported the screen failing to load ("This page
-- couldn't load", 21 October 2026). Every visit read the whole trail: the most recent entries were found by sorting every audit
-- entry and every student sign-in (audit.entries had no index on occurred_at, iam.student_event none on at), "Entries on the record"
-- counted every row, and the filters' counts grouped thirty days of entries — on the live trail longer than the gateway waits.
-- Now:
--   · audit.entries is indexed by occurred_at (on every monthly partition, built CONCURRENTLY so no write waits, as V306 built the
--     sealer's index; a partition made later by audit.ensure_partition inherits it), and iam.student_event by at: the most recent
--     entries and today's counts are read from the end of the indexes;
--   · the total is the chain's own count — audit.chain_head.last_seq is the number of entries sealed in each (period, shard), so their
--     sum plus the entries not yet sealed is every entry, without reading one (audit.entry_count());
--   · the filters, and the counts beside them, read the latest entries of the trail (AuditLogController), never the whole of it.
-- Nothing is written to the trail and nothing about what an entry records changes.

BEGIN;

CREATE OR REPLACE FUNCTION audit.entry_count()
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce((SELECT sum(last_seq) FROM audit.chain_head), 0)::bigint
         + (SELECT count(*) FROM audit.entries WHERE entry_hash IS NULL)
$$;
COMMENT ON FUNCTION audit.entry_count() IS
  'V623: every entry on the audit trail, counted from the chain: the entries sealed in each (period, shard) (chain_head.last_seq) '
  'plus those committed and not yet sealed (the sealer''s partial index). One statement, so one snapshot: an entry sealed meanwhile '
  'is counted once.';
GRANT EXECUTE ON FUNCTION audit.entry_count() TO app_auditor;

COMMIT;

-- the most recent student sign-ins, from the end of the index (the staff sign-ins have had theirs since V002: ix_sign_in_recent)
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_student_event_recent ON iam.student_event (at DESC);

-- the most recent entries of the trail: one index on the parent, built partition by partition without blocking a write
CREATE INDEX IF NOT EXISTS ix_entries_recent ON ONLY audit.entries (occurred_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202609 ON audit.entries_202609 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202609;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202610 ON audit.entries_202610 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202610;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202611 ON audit.entries_202611 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202611;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202612 ON audit.entries_202612 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202612;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202701 ON audit.entries_202701 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202701;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202702 ON audit.entries_202702 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202702;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202703 ON audit.entries_202703 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202703;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202704 ON audit.entries_202704 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202704;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202705 ON audit.entries_202705 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202705;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202706 ON audit.entries_202706 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202706;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202707 ON audit.entries_202707 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202707;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202708 ON audit.entries_202708 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202708;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202709 ON audit.entries_202709 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202709;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202710 ON audit.entries_202710 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202710;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202711 ON audit.entries_202711 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202711;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202712 ON audit.entries_202712 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202712;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202801 ON audit.entries_202801 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202801;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202802 ON audit.entries_202802 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202802;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202803 ON audit.entries_202803 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202803;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202804 ON audit.entries_202804 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202804;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202805 ON audit.entries_202805 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202805;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202806 ON audit.entries_202806 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202806;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202807 ON audit.entries_202807 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202807;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_recent_202808 ON audit.entries_202808 (occurred_at DESC);
ALTER INDEX audit.ix_entries_recent ATTACH PARTITION audit.ix_entries_recent_202808;
