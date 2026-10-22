-- ═══════════════════════════════════════
-- V632 — the PUTME score shown to index-course applicants from the release
--
--   The University's word of 22 October 2026: on the Post-UTME applicant's Overview, a PUTME score card between the UTME score and
--   the stage, for the applicants who applied for index courses only. The index courses are the programmes the Academic Office
--   states sit the Post-UTME examination for the session (admissions.screening_exam_programme, admissions.screened_by_exam): for
--   2026/2027 LL.B (Law), MBBS, Doctor of Pharmacy, Nursing Sciences, Radiography and Radiation Science, Medical Laboratory Science.
--   Such an applicant reads the score as soon as the Academic Office releases the scores, before the admission decision; until then
--   the card says it is awaited (ApplicantService.view gives the applicant `putme`). Every other applicant has no card, and the
--   aggregate, the cut-off and the merit position are still shown with the admission decision alone (V617).
--   The notice admissions.release_scores sends said the score is shown with the admission decision, which is no longer so for an
--   index-course applicant. This migration restates admissions.release_scores exactly as V617 left it, with that one notice told
--   apart: an index-course applicant is told the score is on the portal's Overview now; every other applicant is told as before.
--   The release, the count and who is told (every seated or scored application) are unchanged.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V632: the PUTME score shown to index-course applicants from the release (the University, 22 October 2026)', true);

CREATE OR REPLACE FUNCTION admissions.release_scores(p_session text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int := 0; r record;
BEGIN
    FOR r IN SELECT ap.id,
                    -- V632: an index course — the programme, as JAMB recorded it, sits the Post-UTME examination this session
                    coalesce(admissions.screened_by_exam(ap.session,
                        (SELECT p.code FROM admissions.candidate c JOIN ref.programme p ON p.name = c.programme
                          WHERE c.id = ap.candidate_id ORDER BY p.archived, p.code LIMIT 1)), false) AS index_course
               FROM admissions.application ap
              WHERE ap.session = p_session AND ap.score_released_at IS NULL
                AND (ap.screening_batch_id IS NOT NULL OR ap.score_entered_at IS NOT NULL)
    LOOP
        UPDATE admissions.application SET score_released_at = now() WHERE id = r.id;
        n := n + 1;
        IF r.index_course THEN
            -- V632: the index-course applicant reads the score on the Overview from now on
            PERFORM admissions.notify_applicant(r.id, 'Post-UTME screening results released',
                'The post-UTME screening results for ' || p_session || ' have been released. Your Post-UTME score is now on your portal Overview. Where you stand and your admission decision follow, read through Admission Status Checking.',
                'MOAUM: the post-UTME screening results for ' || p_session || ' are released. Your Post-UTME score is now on your portal Overview.');
        ELSE
            -- V617: the score is the applicant's to read with the admission decision, not before; the notice says so and invites
            -- nobody to sign in and see a score
            PERFORM admissions.notify_applicant(r.id, 'Post-UTME screening results released',
                'The post-UTME screening results for ' || p_session || ' have been released to the Admissions Board. Your score and where you stand are shown on the portal with your admission decision, read through Admission Status Checking.',
                'MOAUM: the post-UTME screening results for ' || p_session || ' are released to the Admissions Board. Your score is shown on the portal with your admission decision.');
        END IF;
    END LOOP;
    RETURN n;
END $function$;

COMMENT ON FUNCTION admissions.release_scores(text) IS
    'V025, V059, V608, V610, V617, V632: releases every seated or scored application''s Post-UTME score for the session and tells each applicant — an index-course applicant (a programme that sits the Post-UTME examination) that the score is now on the portal''s Overview, every other applicant that the results are with the Admissions Board and the score is shown with the admission decision; a computed aggregate is shown to nobody';

COMMIT;
