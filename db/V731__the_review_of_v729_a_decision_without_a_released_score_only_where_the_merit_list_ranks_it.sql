-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V731 · The review of V729: a decision without a released score only where the merit list ranks it
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V729 (86f50f4f) let the Board decide an application whose computed aggregate is never released (a programme screened without the
--  Post-UTME examination, no score entered). Its review (three finders, a refuter a finding) found that the refusal V729 narrowed was
--  also what kept the Board from deciding applications the merit list never ranks:
--    an application never submitted (and so never paid for), or of a candidate not a UTME candidate on JAMB's current list, outside
--    an index programme and with no score entered, could be decided by hand on the Applicants desk ("Enter the decision"), released
--    by admissions.release_decisions (which has no score test) and the candidate made ADMITTED.
--  Now, without a released score, admissions.decide_application decides only what admissions.merit_list ranks on a computed
--  aggregate — a submitted application of a UTME candidate on JAMB's current list (caps_row_live); everything else is refused as it
--  was before V729.
--
--  And, found in the same review though as old as V053: the decision read the O'Level allowance (a programme admitting on a pass in a
--  subject, admissions.programme_olevel_allowance, held by programme CODE) with the candidate's programme NAME, so it never matched; the
--  merit list reads it by code. A candidate the merit list proposed on an allowance was refused the offer ("a compulsory O'Level
--  credit is missing"), and the refusal undid the whole programme's recording. The decision now resolves the code as the merit list
--  does (the programme's name to its code, the unarchived first), and falls back to the name as stored where no code matches.
--
--  The rest of the review is in the API (CapsRepository.awaitingRelease counts only what a release puts on the merit list, and the
--  examination programmes' applicants with no score apart; "Compute non-sitters" leaves an application the Board has decided on its
--  computed aggregate as it is) and the manual.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V731: the review of V729 — a decision without a released score only where the merit list ranks it', true);

/* whether a candidate's application is one the merit list ranks: a UTME candidate on JAMB's current list for the session (the merit
   list's own join, caps_row_live, and its entry mode) */
CREATE FUNCTION admissions.on_current_utme_list(p_app uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          JOIN admissions.caps_row_live x ON x.session = a.session AND x.jamb_reg_no = c.jamb_reg_no AND x.entry_mode = 'UTME'
         WHERE a.id = p_app);
$$;
COMMENT ON FUNCTION admissions.on_current_utme_list(uuid) IS
  'V731: the application is of a UTME candidate on JAMB''s current list for its session — the merit list''s own test (caps_row_live, entry mode UTME).';

CREATE OR REPLACE FUNCTION admissions.decide_application(p_app uuid, p_decision text, p_note text, p_basis text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application; c admissions.candidate; v_has boolean; v_missing text[]; v_code text;
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
    -- V731: and without a released score, only what the merit list ranks on a computed aggregate
    IF a.score_released_at IS NULL AND a.submitted_at IS NULL THEN
        RAISE EXCEPTION 'the application has not been submitted' USING ERRCODE = '23514',
            HINT = 'The Board decides on submitted applications.';
    END IF;
    IF a.score_released_at IS NULL AND NOT admissions.on_current_utme_list(p_app) THEN
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
  'The Board''s decision on an application (V053, V394). V729: a released score is needed where there is one to release (admissions.score_release_needed). V731: without one, only a submitted application of a UTME candidate on JAMB''s current list — what the merit list ranks on a computed aggregate; the O''Level allowance read by programme code, as the merit list reads it.';

COMMIT;
