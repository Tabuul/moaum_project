-- V626: the audit history of one kind of record is read from the end of an index. Several screens show the latest changes to one
-- kind of record from the audit trail — the session policy's history, the biodata gate's, a session's fee schedule changes, the
-- College's recent changes and a College result sheet's trail. Each read the trail by subject_type and took the newest first, and
-- the one index that names subject_type (ix_entries_subject: subject_type, subject_id, occurred_at) cannot give one type's entries
-- in time order, so every entry of that type was read and sorted, more of them every day. Now audit.ix_entries_type_recent
-- (subject_type, occurred_at DESC) is on every monthly partition, built CONCURRENTLY so no write waits (as V306 and V623 built
-- theirs; a partition made later by audit.ensure_partition inherits it): the newest entries of one type come from the end of the
-- index, and a type and a time window ("the last 90 days of college.*") read only that window. Nothing about what an entry
-- records changes; each audited write keeps one more index entry, which the University accepted (21 October 2026).

CREATE INDEX IF NOT EXISTS ix_entries_type_recent ON ONLY audit.entries (subject_type, occurred_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202609 ON audit.entries_202609 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202609;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202610 ON audit.entries_202610 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202610;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202611 ON audit.entries_202611 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202611;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202612 ON audit.entries_202612 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202612;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202701 ON audit.entries_202701 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202701;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202702 ON audit.entries_202702 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202702;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202703 ON audit.entries_202703 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202703;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202704 ON audit.entries_202704 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202704;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202705 ON audit.entries_202705 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202705;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202706 ON audit.entries_202706 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202706;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202707 ON audit.entries_202707 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202707;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202708 ON audit.entries_202708 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202708;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202709 ON audit.entries_202709 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202709;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202710 ON audit.entries_202710 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202710;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202711 ON audit.entries_202711 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202711;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202712 ON audit.entries_202712 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202712;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202801 ON audit.entries_202801 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202801;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202802 ON audit.entries_202802 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202802;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202803 ON audit.entries_202803 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202803;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202804 ON audit.entries_202804 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202804;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202805 ON audit.entries_202805 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202805;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202806 ON audit.entries_202806 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202806;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202807 ON audit.entries_202807 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202807;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_type_recent_202808 ON audit.entries_202808 (subject_type, occurred_at DESC);
ALTER INDEX audit.ix_entries_type_recent ATTACH PARTITION audit.ix_entries_type_recent_202808;
