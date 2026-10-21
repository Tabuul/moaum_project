-- ═══════════════════════════════════════
-- V624 — a course taken off a programme's broadsheet by the department
--
--   A broadsheet (by programme, level, session, semester and stream) has a column for every course any student of the class has
--   on an approved registration. On Environmental Management and Toxicology's 100 Level sheet that brought in a Linguistics and
--   a Political Science load (LIN 101, BSU-LIN 107, REL 105, POL 203 …) that the department does not offer — a few students'
--   registrations: a registration made in error, or a student placed in the wrong programme (21 October 2026: "remove those
--   courses from the broadsheet"). No rule can tell such a course from one a few of the class rightly take (an Education
--   student's teaching subject, a borrowed elective), so the department says which: a course taken off a sheet is recorded here
--   with its reason, by whom and when; the broadsheet leaves it out before anything is counted — its column, the semester figures,
--   the remark, the coverage — and lists it under the sheet with the students who carry it, for the record to be put right
--   (Programme Swap, or the course dropped from the registration). Putting it back removes the row. The student's own record —
--   results, transcript, CGPA — is never touched: this is the sheet's, not the registration's.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V624: a course taken off a programme''s broadsheet by the department', true);

CREATE TABLE assessment.broadsheet_omission (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    programme_code text NOT NULL,
    level          int NOT NULL CHECK (level BETWEEN 100 AND 900),
    session        text NOT NULL,
    semester       int NOT NULL CHECK (semester IN (1, 2, 3)),
    stream         text NOT NULL DEFAULT 'REGULAR' CHECK (stream IN ('REGULAR', 'CCE', 'PG')),
    course_code    text NOT NULL,
    reason         text NOT NULL CHECK (length(btrim(reason)) >= 3),
    omitted_by     uuid,
    omitted_office text,
    omitted_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (programme_code, level, session, semester, stream, course_code)
);
COMMENT ON TABLE assessment.broadsheet_omission IS
    'V624: a course the department took off one broadsheet (programme, level, session, semester, stream), with its reason — left out of the sheet before anything is counted and listed under it with the students who carry it; the registrations and results are untouched. Putting it back deletes the row (the audit spine keeps it)';
SELECT audit.attach('assessment.broadsheet_omission');
GRANT SELECT ON assessment.broadsheet_omission TO app_auditor, app_acrecords, app_reporting;

COMMIT;
