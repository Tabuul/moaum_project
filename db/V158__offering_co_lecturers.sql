-- ===========================================================================
-- V158 - a course may be taught by more than one lecturer (co-teaching)
--
--   catalogue.offering carries one lecturer_id — the lead, who owns the score
--   sheet and submits it up the results chain, and one second examiner. A large
--   course is often taught by two or three lecturers together. This adds the
--   co-lecturers as a side table, so the lead and the single-lecturer logic that
--   hangs off offering.lecturer_id (the sheet, the dashboards, the class list)
--   are untouched, and a co-lecturer simply also sees the course and enters
--   scores on the one shared sheet.
--
--   State table, on the audit spine; assignment happens in an office action, so
--   its writes carry actor context.
-- ===========================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS catalogue.offering_teacher (
    offering_id uuid NOT NULL REFERENCES catalogue.offering(id) ON DELETE CASCADE,
    lecturer_id uuid NOT NULL REFERENCES iam.person(id),
    added_by    uuid NULL REFERENCES iam.person(id),
    added_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (offering_id, lecturer_id)
);
CREATE INDEX IF NOT EXISTS ix_offering_teacher_lecturer ON catalogue.offering_teacher (lecturer_id);

SELECT audit.attach('catalogue.offering_teacher');

COMMIT;
