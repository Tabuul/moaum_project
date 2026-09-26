-- ═══════════════════════════════════════════════════════════════════════════
-- V270 — the admission status is checked the moment the JAMB list is uploaded
--
--   V021's stage read the journey in one fixed order: fee, form, screening
--   slip, screening score, decision, acceptance, clearance, registration,
--   matriculation. A candidate admitted from the JAMB admission list (V081)
--   never had a CBT slip or a score on this portal, so the stage stayed at
--   "screening slip issued" with the offer already released, and the
--   Admission Status page kept saying the application was with the Board.
--   The decision, once released — from the JAMB list or by the Board — now
--   leads: the applicant checks the admission status, accepts, takes the
--   acceptance letter and proceeds to the online screening. The stages before
--   the decision are read only while no decision stands.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V270: admission status from the JAMB list', true);

CREATE OR REPLACE FUNCTION admissions.application_stage(p_app uuid)
RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT CASE
        -- the decision released leads, however the candidate was admitted
        WHEN a.decision_released_at IS NOT NULL THEN CASE
            WHEN a.accepted_at IS NULL THEN 5
            WHEN a.cleared_at IS NULL THEN 6
            WHEN NOT EXISTS (SELECT 1 FROM people.student s
                               JOIN registration.course_registration r ON r.student_id = s.id AND r.session = a.session
                              WHERE s.candidate_id = a.candidate_id AND r.status IN ('APPROVED','LOCKED')) THEN 7
            WHEN NOT EXISTS (SELECT 1 FROM people.student s WHERE s.candidate_id = a.candidate_id AND s.matric_no IS NOT NULL) THEN 8
            ELSE 9 END
        WHEN a.fee_confirmed_at IS NULL THEN 0
        WHEN a.submitted_at IS NULL THEN 1
        WHEN a.screening_batch_id IS NULL THEN 2
        WHEN a.score_released_at IS NULL THEN 3
        ELSE 4 END
      FROM admissions.application a WHERE a.id = p_app;
$$;
COMMENT ON FUNCTION admissions.application_stage(uuid) IS
    'The applicant''s milestone 0–9 (V021, V270): the released decision leads, so a candidate admitted from the JAMB list checks the admission status at once and proceeds to acceptance, the letter and the online screening without a CBT slip or score.';

COMMIT;
