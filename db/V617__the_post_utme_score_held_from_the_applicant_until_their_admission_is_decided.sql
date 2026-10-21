-- ═══════════════════════════════════════
-- V617 — the Post-UTME score held from the applicant until their admission is decided
--
--   V610 (earlier on 21 October 2026) gave every sitter of the Post-UTME examination their score on the portal from the release,
--   whatever the Board then decided. The University's word the same afternoon: first the Screening result screen (the aggregate as
--   calculated, the cut-off, where the applicant stands on the merit list), then the Post-UTME score on the Overview too, are held
--   from every applicant until their admission is decided — a decision theirs to read (offered, waiting list or not offered, under
--   Admission Status Checking). The applicant's view (ApplicantService.view) gives the result and the release date only then; a
--   computed aggregate (OLEVEL) is still never shown; the Academic Office reads everything as before.
--   The notice admissions.release_scores sends invited the sitter to sign in and see the score; that would now find nothing. This
--   migration restates admissions.release_scores (V025, V059, V608, V610) from its current definition with the notice's words
--   changed — the results are released to the Admissions Board and the score is shown with the admission decision — and nothing
--   else: the release, the count and who is told (every seated or scored application) are as they were.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V617: the Post-UTME score held from the applicant until their admission is decided', true);

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
        -- V617: the score is the applicant's to read with the admission decision, not before; the notice says so and invites
        -- nobody to sign in and see a score
        PERFORM admissions.notify_applicant(r.id, 'Post-UTME screening results released',
            'The post-UTME screening results for ' || p_session || ' have been released to the Admissions Board. Your score and where you stand are shown on the portal with your admission decision, read through Admission Status Checking.',
            'MOAUM: the post-UTME screening results for ' || p_session || ' are released to the Admissions Board. Your score is shown on the portal with your admission decision.');
    END LOOP;
    RETURN n;
END $function$;

COMMENT ON FUNCTION admissions.release_scores(text) IS
    'V025, V059, V608, V610, V617: releases every seated or scored application''s Post-UTME score for the session and tells each applicant the results are with the Admissions Board — the applicant''s view gives the score with the admission decision, and a computed aggregate to nobody';

COMMIT;
