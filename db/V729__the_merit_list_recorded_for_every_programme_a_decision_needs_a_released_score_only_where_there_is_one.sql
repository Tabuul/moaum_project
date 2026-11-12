-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V729 · The merit list recorded for every programme: a decision needs a released score only where there is one to release
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's word of 12 November 2026, with the Admissions dashboard's screenshot: "Record all programmes" answers
--  "Unprocessable Content — the screening score has not been released. What to do: The Board decides on released scores." and no
--  programme is recorded.
--
--  Why: since V610 a programme screened without the Post-UTME examination (not an index programme, admissions.screened_by_exam false)
--  ranks its applicants on an aggregate computed from the UTME score and the O'Level result, and that computed aggregate is never
--  released — admissions.release_scores releases the applications that sat (a screening batch) or were scored (score_entered_at),
--  and nothing else. The merit list (admissions.merit_list, V384) draws such a programme's whole submitted pool, released or not.
--  But the Board's decision (admissions.decide_application, V053 → V394) still refused every application whose score was not
--  released. So every applicant of a non-index programme was put on the merit list and then refused, and "Record all programmes"
--  ran every programme in one transaction: the first refusal undid all of them.
--
--  Now one rule, read the same way by the decision and the merit list: a score must be released before the Board decides when there
--  is a score to release — an index programme's (the examination), or a score entered for the application (an examination taken,
--  or a computed Post-UTME the Academic Office entered) — and a computed aggregate, which is never released, needs no release:
--    admissions.decide_application(p_app, p_decision, p_note, p_basis) restated from V394 with that rule;
--    admissions.merit_list(session, programme) draws its pool on it: a released score, or (outside an index programme) no entered
--      score — so an entered score waits for the release before its applicant is ranked, as an index programme's always has.
--  The Admissions dashboard's "Record all programmes" records programme by programme (each its own request and transaction), counts
--  them off, and says which programmes were refused and why, instead of one refusal undoing every programme; each programme's answer
--  says how many of its applicants await a released score.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V729: the merit list recorded for every programme — a decision needs a released score only where there is one', true);

-- ── 1 · the rule, once ──────────────────────────────────────────────────────────────────────────────────────────────────────────
/* whether an application's screening score must be released before the Board decides on it: there is a score to release — the
   programme is an index programme (the Post-UTME examination), or a score was entered for the application */
CREATE FUNCTION admissions.score_release_needed(p_app uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT a.score_entered_at IS NOT NULL
        OR coalesce(admissions.screened_by_exam(a.session,
               (SELECT p.code FROM admissions.candidate c JOIN ref.programme p ON p.name = c.programme
                 WHERE c.id = a.candidate_id ORDER BY p.archived, p.code LIMIT 1)), false)
      FROM admissions.application a WHERE a.id = p_app;
$$;
COMMENT ON FUNCTION admissions.score_release_needed(uuid) IS
  'V729: an application''s score is released before the Board decides when there is one to release — an index programme''s (the Post-UTME examination) or a score entered for it; a computed aggregate (V610: never released) needs no release.';

-- ── 2 · the Board's decision (V394, the release rule as above) ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.decide_application(p_app uuid, p_decision text, p_note text, p_basis text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application; c admissions.candidate; v_has boolean; v_missing text[];
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF a.decision_released_at IS NOT NULL THEN
        RAISE EXCEPTION 'the decision was released on % and stands', a.decision_released_at::date USING ERRCODE = '23514',
            HINT = 'The Board minutes a new decision.';
    END IF;
    -- V729: a released score only where there is one to release (an index programme, or a score entered); a computed aggregate is never
    IF a.score_released_at IS NULL AND admissions.score_release_needed(p_app) THEN
        RAISE EXCEPTION 'the screening score has not been released' USING ERRCODE = '23514',
            HINT = 'The Board decides on released scores: release the screening results first (Admissions, Screening batches, Release results).';
    END IF;
    IF p_decision = 'OFFERED' AND p_basis IS NULL THEN
        RAISE EXCEPTION 'an offer is made on a basis' USING ERRCODE = '23514',
            HINT = 'National Merit, State Merit, Equality of Local Government, Locality or Persons Living With Disability.';
    END IF;
    IF p_decision = 'OFFERED' THEN
        SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
        -- the rule applies to the O'Level on record: when a candidate has sittings but no
        -- credit in a compulsory subject, the offer is refused; when none is on record, the
        -- rule cannot be read and does not block (that is a data-completeness matter).
        SELECT EXISTS (SELECT 1 FROM admissions.olevel_sitting st
                        WHERE st.session = a.session AND st.jamb_key = c.jamb_key) INTO v_has;
        IF v_has THEN
            v_missing := admissions.olevel_compulsory_missing(a.session, c.jamb_key, c.programme);
            IF array_length(v_missing, 1) IS NOT NULL THEN
                RAISE EXCEPTION 'a compulsory O''Level credit is missing: %', array_to_string(v_missing, ', ')
                    USING ERRCODE = '23514',
                    HINT = 'Credit passes in English and Mathematics are compulsory for all programmes; a pass does not count. '
                           'If this programme admits on a pass in a subject, record that exception in the admission settings.';
            END IF;
        END IF;
    END IF;
    UPDATE admissions.application SET decision = p_decision, decision_note = p_note, decision_basis = p_basis, decided_at = now() WHERE id = p_app;
    RETURN p_decision;
END $function$;

-- ── 3 · the merit list's pool, on the same rule (V384's body, that one condition changed) ──────────────────────────────────────
DO $$
DECLARE
    d text := pg_get_functiondef('admissions.merit_list(text,text)'::regprocedure);
    v_old text := 'AND (NOT v_by_exam OR a.score_released_at IS NOT NULL)';
    v_new text := 'AND (a.score_released_at IS NOT NULL OR (NOT v_by_exam AND a.score_entered_at IS NULL))   -- V729: an entered score waits for its release';
BEGIN
    IF (length(d) - length(replace(d, v_old, ''))) / length(v_old) <> 1 THEN
        RAISE EXCEPTION 'V729: admissions.merit_list is not as V384 left it (the pool condition is not there once)';
    END IF;
    EXECUTE replace(d, v_old, v_new);
END $$;
COMMENT ON FUNCTION admissions.merit_list(text, text) IS
  'The merit list for a programme: the eligible pool ranked, with the proposed offer that fills the quota. V729: the pool holds the applications with a released score, and outside an index programme those with no entered score (a computed aggregate, never released) — the applications admissions.decide_application decides.';

COMMIT;
