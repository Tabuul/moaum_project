-- ═══════════════════════════════════════
-- V432 — the foreign-key indexes that measured worth it (portal gap audit, GAP-012)
--
--   The audit counted 352 foreign keys with no index on the referencing column. Only those on large tables that the portal reads by
--   that column were timed, on the live-shaped copy (54,573 students), without and with the index:
--
--     admissions.attachment.object_id      removing one orphaned file object (the hourly sweep removes up to 100):  83 ms →  7 ms
--     people.enrolment.session             the calendar's students per session:                                     31 ms →  5 ms
--     registration.course_registration.session   a session's registrations:                                  5–8 ms → 0.1 ms
--
--   Not indexed, because the reading does not need it: catalogue.offering.lecturer_id (a lecturer's classes, 0.7 ms → 0.04 ms on 10,687
--   classes), assessment.result_query.sheet_id, people.status_change.student_id and credentials.certificate.student_id (two rows or
--   none yet), clearance.item.unit and superseded_by (read through the partial indexes of V416), people.biodata.field (read whole),
--   finance.gl_journal.reverses (never read by it), people.student.matriculation_run (no run on the live register yet).
--
--   The tables are small enough (at most 110,000 rows) for a plain CREATE INDEX inside the migration's transaction.
-- ═══════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V432: foreign-key indexes that measured worth it', true);

CREATE INDEX IF NOT EXISTS ix_attachment_object ON admissions.attachment (object_id) WHERE object_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_enrolment_session ON people.enrolment (session);
CREATE INDEX IF NOT EXISTS ix_course_registration_session ON registration.course_registration (session);

COMMENT ON INDEX admissions.ix_attachment_object IS 'V432: removing a file object checks this table by object_id (83 ms to 7 ms on the live-shaped copy)';
COMMENT ON INDEX people.ix_enrolment_session IS 'V432: the calendar counts each session''s enrolments (31 ms to 5 ms)';
COMMENT ON INDEX registration.ix_course_registration_session IS 'V432: a session''s registrations read without a student (5–8 ms to 0.1 ms)';

COMMIT;
