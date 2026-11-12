-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V732 · The review of V731: a decision V729 let in may be corrected to NOT OFFERED; a programme that names no code needs a release
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V731 (322f7fda)'s review (two finders, a refuter a finding; three stood):
--    1. While V729 was live (86f50f4f → 322f7fda, 12 November 2026) the Applicants desk could record a decision, without a released
--       score, on an application the merit list never ranks — never submitted, or not a UTME candidate on JAMB's current list.
--       V731 refuses such decisions, every one, NOT OFFERED included: a decision recorded in that window could not be corrected,
--       and admissions.release_decisions (no score test) would still release it — an OFFERED one making the candidate ADMITTED.
--       Now the Board may always correct a decision already recorded and not released to NOT OFFERED (a step away from an offer,
--       whatever the score's release); the migration counts the decisions that stand without what the Board now needs to decide
--       them, and names how many in its output.
--    2. admissions.score_release_needed read a candidate's programme by its name; a name that resolves to no programme code (a
--       programme renamed after the intake: the candidate keeps the name it applied under) read "no release needed" even for an
--       examination programme, so the Board could decide without a released score an application no merit list ranks. Now an
--       unresolved name needs a released score (fail closed), as every application did before V729.
--    3. (the API test) AdmissionEligibilityIT's count of what a release would bring now applies the current-list test, as the
--       repository's count does, so applicants left over from earlier runs count alike on both sides.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V732: the review of V731 — a decision V729 let in corrected to NOT OFFERED; an unknown programme needs a release', true);

-- ── 1 · the release rule, failing closed on a programme name that resolves to no code ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.score_release_needed(p_app uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT a.score_entered_at IS NOT NULL
        OR v.code IS NULL                                   -- V732: a name no programme carries is ranked by no merit list
        OR admissions.screened_by_exam(a.session, v.code)
      FROM admissions.application a
      LEFT JOIN LATERAL (
          SELECT p.code FROM admissions.candidate c JOIN ref.programme p ON p.name = c.programme
           WHERE c.id = a.candidate_id ORDER BY p.archived, p.code LIMIT 1) v ON true
     WHERE a.id = p_app;
$$;
COMMENT ON FUNCTION admissions.score_release_needed(uuid) IS
  'V729: an application''s score is released before the Board decides when there is one to release — an index programme''s (the Post-UTME examination) or a score entered for it; a computed aggregate (V610: never released) needs none. V732: a programme name that resolves to no code needs one (fail closed).';

-- ── 2 · the Board's decision (V731's), a recorded decision always correctable to NOT OFFERED ────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.decide_application(p_app uuid, p_decision text, p_note text, p_basis text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application; c admissions.candidate; v_has boolean; v_missing text[]; v_code text; v_correcting boolean;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF a.decision_released_at IS NOT NULL THEN
        RAISE EXCEPTION 'the decision was released on % and stands', a.decision_released_at::date USING ERRCODE = '23514',
            HINT = 'The Board minutes a new decision.';
    END IF;
    -- V732: a decision recorded and not released may always be corrected to NOT OFFERED (one V729 let in among them)
    v_correcting := p_decision = 'NOT_OFFERED' AND a.decision IS NOT NULL;
    -- V729: a released score only where there is one to release (an index programme, or a score entered); a computed aggregate is never
    IF a.score_released_at IS NULL AND NOT v_correcting AND admissions.score_release_needed(p_app) THEN
        RAISE EXCEPTION 'the screening score has not been released' USING ERRCODE = '23514',
            HINT = 'The Board decides on released scores: release the screening results first (Admissions, Screening batches, Release results).';
    END IF;
    -- V731: and without a released score, only what the merit list ranks on a computed aggregate
    IF a.score_released_at IS NULL AND NOT v_correcting AND a.submitted_at IS NULL THEN
        RAISE EXCEPTION 'the application has not been submitted' USING ERRCODE = '23514',
            HINT = 'The Board decides on submitted applications.';
    END IF;
    IF a.score_released_at IS NULL AND NOT v_correcting AND NOT admissions.on_current_utme_list(p_app) THEN
        RAISE EXCEPTION 'the screening score has not been released' USING ERRCODE = '23514',
            HINT = 'Without a released score the Board decides only a UTME candidate on JAMB''s current list, as the merit list ranks them.';
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
            -- V731: the programme's allowances are held by its code, as the merit list reads them
            v_code := coalesce((SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1), c.programme);
            v_missing := admissions.olevel_compulsory_missing(a.session, c.jamb_key, v_code);
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
COMMENT ON FUNCTION admissions.decide_application(uuid, text, text, text) IS
  'The Board''s decision on an application (V053, V394). V729: a released score is needed where there is one to release (admissions.score_release_needed). V731: without one, only a submitted application of a UTME candidate on JAMB''s current list — what the merit list ranks on a computed aggregate; the O''Level allowance read by programme code. V732: a decision recorded and not released may always be corrected to NOT OFFERED.';

-- ── 3 · the decisions standing without what the Board now needs to decide them, counted ─────────────────────────────────────────
DO $$
DECLARE n_all bigint; n_offered bigint;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE a.decision = 'OFFERED') INTO n_all, n_offered
      FROM admissions.application a
     WHERE a.decision IS NOT NULL AND a.decision_released_at IS NULL AND a.score_released_at IS NULL
       AND (a.submitted_at IS NULL OR NOT admissions.on_current_utme_list(a.id) OR admissions.score_release_needed(a.id));
    RAISE NOTICE 'V732: % recorded decision(s) not released stand without a released score the Board would now need (% of them OFFERED); each may be corrected to NOT OFFERED on the Applicants desk before the decisions are released', n_all, n_offered;
END $$;

COMMIT;
