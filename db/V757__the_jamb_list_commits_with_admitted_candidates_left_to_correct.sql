-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V757 · The JAMB list commits with admitted candidates left to correct
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  On 13 November 2026 the Academic Office's commit of the 2026/2027 UTME list (232 new candidates, 671 JAMB changed, 594 who
--  followed JAMB's new course) was refused for two candidates: "Matched, programme differs from CAPS — admitted (2)". JAMB changed
--  their course after the Board's offer was released. V636 leaves such a candidate as offered, never moved silently, and named for
--  an admission correction on Programme Changes (or the list row withdrawn) — and it also held the whole list until then.
--
--  Committing a list stamps the batch; it changes no candidate's programme, and the reconciliation is read from the register every
--  time, so the finding stays on the "Does the list reconcile?" panel after the commit, with its owner and what to do. From V757 that
--  finding no longer holds the commit, as "On the CAPS list, no candidate record" never did: admissions.commit_batch lets the list
--  through and records how many admitted candidates were left to correct (caps_batch.committed_admitted_left). Every other finding
--  still refuses the commit: an admission JAMB did not approve, a candidate JAMB moved who has not followed the course yet, a course
--  code the University does not run, a Direct Entry candidate at the wrong level.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V757: the JAMB list commits with admitted candidates left to correct', true);

ALTER TABLE admissions.caps_batch ADD COLUMN committed_admitted_left integer;
COMMENT ON COLUMN admissions.caps_batch.committed_admitted_left IS
    'V757: at the commit, the admitted candidates whose programme differs from the CAPS row (an offer released before JAMB changed the course), left as offered for an admission correction on Programme Changes; NULL before V757 or uncommitted.';

DO $$
DECLARE d text; n int;
    -- {anchor, replacement, times}
    edits text[][] := ARRAY[
      ARRAY['    pending bigint;',
            '    pending bigint;
    admitted_left bigint;', '1'],
      ARRAY['      INTO pending
      FROM admissions.reconcile(b.session) x;',
            '      INTO pending
      FROM admissions.reconcile(b.session) x;

    -- V757: an admitted candidate JAMB moved after the offer is corrected on Programme Changes; it is recorded, and the list goes through
    SELECT coalesce(sum(x.n) FILTER (WHERE x.finding = ''Matched, programme differs from CAPS — admitted''), 0)
      INTO admitted_left
      FROM admissions.reconcile(b.session) x;', '1'],
      ARRAY['WHERE x.n > 0 AND x.finding <> ''On the CAPS list, no candidate record'';',
            'WHERE x.n > 0 AND x.finding NOT IN (''On the CAPS list, no candidate record'', ''Matched, programme differs from CAPS — admitted'');', '1'],
      ARRAY['a ghost admission, a programme that differs from CAPS, a course code the University does not run, or a Direct Entry candidate at the wrong level. Fix or withdraw those rows; candidates not yet registered do not block the commit.',
            'a ghost admission, a candidate JAMB moved who has not followed the course yet, a course code the University does not run, or a Direct Entry candidate at the wrong level. Fix or withdraw those rows; candidates not yet registered, and admitted candidates to correct on Programme Changes, do not block the commit.', '1'],
      ARRAY['SET committed_at = now(), committed_pending = pending WHERE id = p_batch;',
            'SET committed_at = now(), committed_pending = pending, committed_admitted_left = admitted_left WHERE id = p_batch;', '1']];
    i int;
BEGIN
    d := pg_get_functiondef('admissions.commit_batch(uuid)'::regprocedure);
    FOR i IN 1 .. array_length(edits, 1) LOOP
        n := (length(d) - length(replace(d, edits[i][1], ''))) / length(edits[i][1]);
        IF n <> edits[i][3]::int THEN
            RAISE EXCEPTION 'V757: admissions.commit_batch is not as V636 left it (% found % times)', left(edits[i][1], 60), n;
        END IF;
        d := replace(d, edits[i][1], edits[i][2]);
    END LOOP;
    EXECUTE d;

    -- the finding says what it now does
    d := pg_get_functiondef('admissions.reconcile(text)'::regprocedure);
    n := (length(d) - length(replace(d, 'of: correct the admission on Programme Changes, or withdraw the row.', ''))) / length('of: correct the admission on Programme Changes, or withdraw the row.');
    IF n <> 1 THEN RAISE EXCEPTION 'V757: admissions.reconcile is not as V636 left it'; END IF;
    EXECUTE replace(d, 'of: correct the admission on Programme Changes, or withdraw the row.',
                       'of: correct the admission on Programme Changes. It does not hold up the commit of the list (V757); it stays here until corrected.');
END $$;

COMMIT;
