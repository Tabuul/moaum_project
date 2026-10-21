-- ═══════════════════════════════════════
-- V608 — the notice on the release of the Post-UTME scores invites nobody to see a score before an offer of admission
--
--   From 21 October 2026 the applicant's own view (ApplicantService.view, GET /api/v1/applicant/me) shows the Post-UTME score and the
--   full result only with a released offer of admission the applicant may read — Admission Status Checking paid and checked, or the
--   admission under way — and only where the score is the Post-UTME examination's (the CBT, or the written examination of an index
--   programme); the aggregate computed from the O'Level result for a programme screened without the examination is never shown to
--   the applicant, and an applicant not offered a place never sees a score, nor that scores were released. The programme eligibility
--   (V266) is the admitted applicant's on the same terms (AdmissionEligibilityController: available=false and ELIG_NOT_ADMITTED to
--   anyone else). Nothing in the database decides that — the API does, on the released decision and admissions.status_checking —
--   but the notice admissions.release_scores sent every seated or scored applicant (V025, V059) said "Sign in to see your score and
--   where you stand", which is no longer true for most of them. The function is restated from its current definition with the
--   words of the notice changed and nothing else: the release, the count and who is told are as they were.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V608: the notice on the release of the Post-UTME scores invites nobody to see a score before an offer of admission', true);

CREATE OR REPLACE FUNCTION admissions.release_scores(p_session text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int := 0; r record;
BEGIN
    FOR r IN SELECT id FROM admissions.application
              WHERE session = p_session AND score_released_at IS NULL
                AND (screening_batch_id IS NOT NULL OR score_entered_at IS NOT NULL)
    LOOP
        UPDATE admissions.application SET score_released_at = now() WHERE id = r.id;
        n := n + 1;
        -- V608: the score is shown to the applicant with an offer of admission, never before — the notice says so
        PERFORM admissions.notify_applicant(r.id, 'Post-UTME screening results released',
            'The post-UTME screening results for ' || p_session || ' have been released to the Admissions Board. Your score and where you stand are shown on the portal with an offer of admission; the admission decision follows and is read through Admission Status Checking.',
            'MOAUM: the post-UTME screening results for ' || p_session || ' are released. Your score is shown on the portal with an offer of admission; the admission decision follows.');
    END LOOP;
    RETURN n;
END $function$;

COMMENT ON FUNCTION admissions.release_scores(text) IS
    'V025, V059, V608: releases every seated or scored application''s Post-UTME score for the session and tells each applicant the results are released — since V608 that the score is shown on the portal with an offer of admission, never before (the applicant''s view gives a score only to the admitted sitter of the examination)';

COMMIT;
