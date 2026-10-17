-- V530: who opened a student's record.
--
-- The audit trail records changes and student searches, but not who looked at a student's record — the contacts, health, bank
-- details, fees and results held on it. Now each time an office opens a student's record (the student record, Student 360, or ICT
-- Support's record of the student) it is recorded: the student, the person and the office they acted in, which record, and when —
-- once for each person, office and record within ten minutes, so moving about the record's tabs is one view, not dozens. The
-- student's own reading of their portal is not a view of their record by an office and is not recorded.
--
-- Internal Audit (and the Deputy Director of Audit and super) read every view; the student sees, on their profile, which office
-- opened their record and when (data protection, V441), without the name of the officer — Internal Audit holds that.
--
-- The log is append-only (nothing is changed, and a row goes only with its student when a student record itself is removed) and
-- off the audit spine: it is itself the record of reads.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'super', true);
SELECT set_config('moaum.reason', 'V530: who opened a student''s record', true);

CREATE TABLE people.record_view (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    at         timestamptz NOT NULL DEFAULT now(),
    student_id uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    viewer_id  uuid NOT NULL,
    office     text NOT NULL REFERENCES ref.office (code),
    record     text NOT NULL CHECK (record IN ('STUDENT_RECORD', 'SUPPORT_RECORD'))
);
COMMENT ON TABLE people.record_view IS
  'V530: each time an office opened a student''s record (Student 360, or ICT Support''s record of the student) — the person, the office and when; once per person, office and record within ten minutes; append-only';
CREATE INDEX ix_record_view_student ON people.record_view (student_id, at DESC);
CREATE INDEX ix_record_view_viewer ON people.record_view (viewer_id, at DESC);
CREATE INDEX ix_record_view_at ON people.record_view (at DESC);
SELECT audit.exempt('people.record_view', 'the append-only log of who opened a student''s record — itself the record of reads, written on every record opened, read by Internal Audit and the student');

-- nothing is changed; a row goes only with its student, when a student record itself is removed (a cascade, from another trigger)
CREATE FUNCTION people.record_view_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' AND pg_trigger_depth() > 1 THEN
        RETURN OLD;
    END IF;
    RAISE EXCEPTION 'RECORD_VIEW_APPEND_ONLY: who opened a student''s record is kept as it was written'
        USING ERRCODE = '42501';
END $$;
CREATE TRIGGER trg_record_view_append_only BEFORE UPDATE OR DELETE ON people.record_view
    FOR EACH ROW EXECUTE FUNCTION people.record_view_append_only();

-- an office opened the student's record: recorded for the person and office acting, once within ten minutes
CREATE FUNCTION people.log_record_view(p_student uuid, p_record text)
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF v_actor IS NULL OR v_office IS NULL OR v_office IN ('student', 'applicant') OR p_student IS NULL
       OR p_record NOT IN ('STUDENT_RECORD', 'SUPPORT_RECORD')
       OR NOT EXISTS (SELECT 1 FROM people.student s WHERE s.id = p_student) THEN
        RETURN false;
    END IF;
    IF EXISTS (SELECT 1 FROM people.record_view v
                WHERE v.student_id = p_student AND v.viewer_id = v_actor AND v.office = v_office AND v.record = p_record
                  AND v.at > now() - interval '10 minutes') THEN
        RETURN false;
    END IF;
    INSERT INTO people.record_view (student_id, viewer_id, office, record) VALUES (p_student, v_actor, v_office, p_record);
    RETURN true;
END $$;

COMMIT;
