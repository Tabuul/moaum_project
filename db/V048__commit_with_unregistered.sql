-- ═══════════════════════════════════════════════════════════════════════════
-- V048 — a real admission list commits with candidates not yet registered
--
--   The reconcile finding "On the CAPS list, no candidate record" counts admitted
--   people who have not yet registered. Candidates are created when an applicant
--   registers against the loaded list, so on a real list that finding is normal
--   and, at 100% registration or nothing, never zero — requiring it to be zero
--   meant a real list could never commit. It no longer blocks the commit; the
--   count is recorded on the batch instead, so the list does not silently look
--   complete. The dangerous findings still block, because each is an error, not
--   a person who simply has not registered yet:
--       · Admitted here, not on the CAPS list      (a ghost admission)
--       · Matched, programme differs from CAPS     (the wrong degree)
--       · JAMB course code the University does not run
--       · Direct Entry candidate at the wrong level
--   Registration against the list still works after it is committed, so an
--   admitted candidate who registers later is found, not lost.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE admissions.caps_batch
    ADD COLUMN IF NOT EXISTS committed_pending int NULL;

COMMENT ON COLUMN admissions.caps_batch.committed_pending IS
    'How many CAPS rows had no candidate record when the list was committed — admitted '
    'people who had not yet registered. Recorded so a committed list carries its own '
    'incompleteness rather than looking complete at the desks it passes.';

CREATE OR REPLACE FUNCTION admissions.commit_batch(p_batch uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    b admissions.caps_batch;
    outstanding text;
    blocking bigint;
    pending bigint;
BEGIN
    SELECT * INTO b FROM admissions.caps_batch WHERE id = p_batch;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no such batch' USING ERRCODE = '23503';
    END IF;
    IF b.committed_at IS NOT NULL THEN
        RETURN 'already committed';           -- idempotent, not an error
    END IF;
    IF b.withdrawn_at IS NOT NULL THEN
        RAISE EXCEPTION 'the list was withdrawn on %: %', b.withdrawn_at::date, b.withdrawn_reason
        USING ERRCODE = '23514',
              HINT = 'A withdrawn list is kept as evidence of what was loaded and is never '
                     'committed. Load the list that should have been loaded, and commit that.';
    END IF;

    -- admitted people not yet registered do not block; they are recorded, not hidden
    SELECT coalesce(sum(x.n) FILTER (WHERE x.finding = 'On the CAPS list, no candidate record'), 0)
      INTO pending
      FROM admissions.reconcile(b.session) x;

    -- the dangerous findings still block
    SELECT string_agg(x.finding || ' (' || x.n || ')', '; '), coalesce(sum(x.n), 0)
      INTO outstanding, blocking
      FROM admissions.reconcile(b.session) x
     WHERE x.n > 0 AND x.finding <> 'On the CAPS list, no candidate record';

    IF blocking > 0 THEN
        RAISE EXCEPTION 'the admission list does not reconcile: %', outstanding
        USING ERRCODE = '23514',
              HINT = 'These are errors, not people who have simply not registered yet: a ghost '
                     'admission, a programme that differs from CAPS, a course code the University '
                     'does not run, or a Direct Entry candidate at the wrong level. Each is a named '
                     'person and carries an office. Fix or withdraw those rows; candidates not yet '
                     'registered do not block the commit.';
    END IF;

    UPDATE admissions.caps_batch SET committed_at = now(), committed_pending = pending WHERE id = p_batch;
    RETURN CASE WHEN pending > 0 THEN 'committed with ' || pending || ' not yet registered' ELSE 'committed' END;
END $$;
