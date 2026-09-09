-- ═══════════════════════════════════════════════════════════════════════════
-- V059 — releasing scores covers the ones uploaded in bulk, not only seated ones
--
--   release_scores released only applications seated into a screening batch
--   (screening_batch_id IS NOT NULL). Post-UTME scores are now also uploaded in
--   bulk (V056/score upload) against candidates who were never seated in the
--   portal, so their scores were entered but could never be released — they
--   stayed "held", and the Board could not decide on them ("the screening score
--   has not been released"). Releasing now covers any application in the session
--   that carries an entered score, seated or not.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION admissions.release_scores(p_session text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int := 0; r record;
BEGIN
    FOR r IN SELECT id FROM admissions.application
              WHERE session = p_session AND score_released_at IS NULL
                AND (screening_batch_id IS NOT NULL OR score_entered_at IS NOT NULL)
    LOOP
        UPDATE admissions.application SET score_released_at = now() WHERE id = r.id;
        n := n + 1;
        PERFORM admissions.notify_applicant(r.id, 'Your screening result is released',
            'The post-UTME screening results for ' || p_session || ' have been released. Sign in to see your score and where you stand.',
            'MOAUM: your screening result is on the portal. Sign in to see it.');
    END LOOP;
    RETURN n;
END $$;
