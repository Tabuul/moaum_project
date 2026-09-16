-- ===========================================================================
-- V156 - SIWES supervisors: a supervisor per student, who records the score
--
--   A SIWES / industrial-training course is not taught by one lecturer to a class;
--   each student is assigned a supervisor, and the supervisor records that
--   student's score after the attachment. Different students have different
--   supervisors, all on the one SIWES score sheet.
--
--     · a new office, 'siwes' (SIWES Coordinator, department-scoped) - it and the
--       Head of Department both assign supervisors to students.
--     · assessment.siwes_supervisor - the student -> supervisor map for an
--       offering, on the audit spine.
--     · assessment.assign_siwes_supervisor(offering, student, supervisor) -
--       validates the offering is an industrial-training course and the student
--       is registered for it, then records (or moves) the supervisor.
--
--   The score is entered on the existing score sheet through the results pipeline:
--   the supervisor records the assessment out of 40 (the ca part) for their own
--   students, and the SIWES coordinator records the report of the practicals out
--   of 60 (the exam part). The row is graded only once both parts are in; the
--   total (ca + exam) is out of 100.
--
--   ref.office is on the audit spine and a migration has no acting person, so the
--   one office row is inserted with the trigger lifted.
-- ===========================================================================

BEGIN;

-- 1. the SIWES Coordinator office (authority OFFICE_siwes is derived from the code)
ALTER TABLE ref.office DISABLE TRIGGER USER;
INSERT INTO ref.office (code, label, scope_kind) VALUES ('siwes', 'SIWES Coordinator', 'department')
ON CONFLICT (code) DO NOTHING;
ALTER TABLE ref.office ENABLE TRIGGER USER;

-- 2. the student -> supervisor map, per SIWES offering
CREATE TABLE IF NOT EXISTS assessment.siwes_supervisor (
    offering_id   uuid NOT NULL REFERENCES catalogue.offering(id),
    student_id    uuid NOT NULL REFERENCES people.student(id),
    supervisor_id uuid NOT NULL REFERENCES iam.person(id),
    assigned_by   uuid NULL REFERENCES iam.person(id),
    assigned_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (offering_id, student_id)
);
CREATE INDEX IF NOT EXISTS ix_siwes_supervisor_supervisor ON assessment.siwes_supervisor (supervisor_id);
SELECT audit.attach('assessment.siwes_supervisor');

-- 3. assign (or move) a supervisor to a SIWES student
CREATE OR REPLACE FUNCTION assessment.assign_siwes_supervisor(p_offering uuid, p_student uuid, p_supervisor uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                    WHERE o.id = p_offering AND c.industrial_training) THEN
        RAISE EXCEPTION 'offering % is not an industrial-training (SIWES) course', p_offering
        USING ERRCODE = '23514', HINT = 'A supervisor is assigned only on a SIWES / industrial-training offering.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM registration.entry e
                     JOIN registration.course_registration r ON r.id = e.registration_id
                    WHERE e.offering_id = p_offering AND r.student_id = p_student AND r.status = 'APPROVED') THEN
        RAISE EXCEPTION 'the student has no approved registration for this SIWES offering'
        USING ERRCODE = '23514', HINT = 'The student registers the SIWES course and is approved before a supervisor is assigned.';
    END IF;
    INSERT INTO assessment.siwes_supervisor (offering_id, student_id, supervisor_id, assigned_by)
    VALUES (p_offering, p_student, p_supervisor, who)
    ON CONFLICT (offering_id, student_id)
    DO UPDATE SET supervisor_id = EXCLUDED.supervisor_id, assigned_by = EXCLUDED.assigned_by, assigned_at = now();
END $$;

COMMIT;
