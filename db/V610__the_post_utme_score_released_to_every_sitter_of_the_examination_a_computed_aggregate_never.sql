-- ═══════════════════════════════════════
-- V610 — the Post-UTME score released to every sitter of the examination, a computed aggregate never
--
--   V608 (earlier on 21 October 2026) withheld the applicant's Post-UTME score until an offer of admission was theirs to read, and
--   reworded the notice admissions.release_scores sends accordingly. The University's word now: the scores are released to every
--   applicant of an index programme — those who sat the Post-UTME examination, the CBT or the written examination — on the release,
--   whatever the Board then decides; only a programme screened without the examination, whose aggregate is computed from the
--   O'Level result, shows no score. The applicant's view (ApplicantService.view) reads that rule: the result and the release date are
--   given when the scores are released and the result's source is the examination's (CBT or EXAM), and never for a computed
--   aggregate (OLEVEL) or none. The programme eligibility (V266) stays the admitted applicant's alone, as V608 made it.
--   This migration restates admissions.release_scores (V025, V059, V608) with the words V059 gave the notice — the sitter is
--   invited to sign in and see the score — and nothing else: the release, the count and who is told (every seated or scored
--   application, which a computed one never is) are as they were.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V610: the Post-UTME score released to every sitter of the examination, a computed aggregate never', true);

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
        -- V610: the sitter's score is on the portal from the release; the notice says so (the words of V059, restored)
        PERFORM admissions.notify_applicant(r.id, 'Your screening result is released',
            'The post-UTME screening results for ' || p_session || ' have been released. Sign in to see your score and where you stand.',
            'MOAUM: your screening result is on the portal. Sign in to see it.');
    END LOOP;
    RETURN n;
END $function$;

COMMENT ON FUNCTION admissions.release_scores(text) IS
    'V025, V059, V608, V610: releases every seated or scored application''s Post-UTME score for the session and tells each applicant to sign in and see it — the applicant''s view gives a score to every sitter of the examination from the release, and a computed aggregate to nobody';

COMMIT;
