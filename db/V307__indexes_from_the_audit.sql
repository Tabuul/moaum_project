-- V307 — indexes the production evidence asked for, and one it showed to be dead weight.
--
-- From pg_stat_statements and pg_stat_user_tables over 25 days of production (2026-09-07 to
-- 2026-10-02). Each index below is justified by queries that filter or join on the column with
-- nothing to use; nothing is added on a hunch.
--
--   people.student (candidate_id)        117,286 calls joining the register to admissions by
--                                        candidate, up to 2.9 s mean; the FK had no index
--   people.student (person_id)           111,961 calls looking a student up from the person
--   registration.entry (offering_id)     5,404 calls listing an offering's registrations, up to
--                                        5.4 s mean; the primary key starts with registration_id,
--                                        so each one scanned 191,458 rows
--   assessment.score (student_id)        a student's results and transcript: 363,445 rows scanned
--                                        per student without it
--   catalogue.course_offer (programme_code, level)
--                                        46,394 sequential scans reading 368 million rows: the
--                                        primary key starts with course_code
--   admissions.candidate (upper(jamb_reg_no)), (upper(jamb_key))
--                                        179,103 calls of the score-entry lookup
--                                        "upper(c.jamb_reg_no) = … OR upper(c.jamb_key) = …";
--                                        the plain indexes cannot serve an upper() comparison
--
--   DROPPED  people.student ix_student_name (upper(surname), upper(other_names)): 0 scans in 25
--            days (every name search is a '%term%' LIKE over the concatenated name, which no
--            btree can serve), 3.7 MB maintained on every write to the register.
--
-- Built CONCURRENTLY, outside a transaction, so no write is blocked while they build.

CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_student_candidate ON people.student (candidate_id) WHERE candidate_id IS NOT NULL;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_student_person ON people.student (person_id) WHERE person_id IS NOT NULL;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entry_offering ON registration.entry (offering_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_score_student ON assessment.score (student_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_course_offer_programme ON catalogue.course_offer (programme_code, level);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_candidate_upper_jamb ON admissions.candidate (upper(jamb_reg_no));
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_candidate_upper_key ON admissions.candidate (upper(jamb_key));
DROP INDEX CONCURRENTLY IF EXISTS people.ix_student_name;
