-- V311 — the student's passport photograph is found by index, not by a scan
--
-- A student with no admissions candidate (migrated from the old portal) has their passport in
-- admissions.attachment keyed by JAMB number. The portal's "has a passport" check and every
-- passport read look it up as
--     at.kind = 'PASSPORT' AND (at.candidate_id = s.candidate_id OR at.jamb_key = upper(btrim(s.jamb_reg_no)))
-- ix_att_candidate serves the first branch; nothing served the second, so PostgreSQL scanned all
-- 52,744 passport rows for every student dashboard (about 200 ms on a copy of production).
-- With this index the planner combines both branches (BitmapOr) in under a millisecond. 1.6 MB.

CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_att_passport_jamb ON admissions.attachment (jamb_key) WHERE kind = 'PASSPORT';
