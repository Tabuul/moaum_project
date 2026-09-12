-- ═══════════════════════════════════════════════════════════════════════════
-- V106 — suggest programmes a non-qualified candidate could move to
--
--   A candidate not qualified for the programme they chose, but who holds five
--   O'Level credits (English, Mathematics and any three others), can often be
--   admitted to another programme whose requirements they DO meet. This finds
--   those programmes: the candidate's UTME score clears the programme's cut-off,
--   the programme's compulsory O'Level subjects are all credited, and the
--   programme still has an open seat. It suggests; the office decides and moves.
--
--   admissions.suggestion_sent records that a candidate was emailed their
--   suggestions, so the office can see who has been told and not tell them twice.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION admissions.programme_suggestions(p_session text, p_jamb_key text, p_exclude text)
RETURNS TABLE (code text, name text, cutoff int)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_pol admissions.session_policy;
    v_score int;
    v_credits int;
    v_has_eng boolean;
    v_has_math boolean;
BEGIN
    BEGIN
        v_pol := admissions.policy_in_force(p_session);
    EXCEPTION WHEN OTHERS THEN
        RETURN;   -- no settings in force: nothing to suggest
    END;

    -- the candidate's UTME score (the best UTME aggregate on the standing list)
    SELECT max(x.aggregate) INTO v_score
      FROM admissions.caps_row_live x
     WHERE x.session = p_session AND x.jamb_key = upper(btrim(p_jamb_key)) AND x.entry_mode = 'UTME';
    IF v_score IS NULL THEN RETURN; END IF;

    -- the O'Level gate: credits (points >= 1) in English, Mathematics and at least three others — five in all
    SELECT count(DISTINCT gr.subject) FILTER (WHERE admissions.olevel_points(p_session, gr.grade) >= 1),
           bool_or(gr.subject ~ '(?i)english'    AND admissions.olevel_points(p_session, gr.grade) >= 1),
           bool_or(gr.subject ~ '(?i)^\s*math'   AND admissions.olevel_points(p_session, gr.grade) >= 1)
      INTO v_credits, v_has_eng, v_has_math
      FROM admissions.olevel_sitting st
      JOIN admissions.olevel_grade gr ON gr.sitting_id = st.id
     WHERE st.session = p_session AND st.jamb_key = upper(btrim(p_jamb_key));
    IF coalesce(v_credits, 0) < 5 OR NOT coalesce(v_has_eng, false) OR NOT coalesce(v_has_math, false) THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT g.code, g.name, admissions.cutoff_or_null(p_session, g.code) AS cut
      FROM ref.programme g
     WHERE NOT g.archived
       AND g.code <> coalesce(p_exclude, '')
       AND NOT admissions.programme_is_closed(p_session, g.code)
       -- the candidate's score clears the programme's cut-off (or it has none)
       AND (admissions.cutoff_or_null(p_session, g.code) IS NULL OR v_score >= admissions.cutoff_or_null(p_session, g.code))
       -- the programme's compulsory O'Level subjects are all credited by the candidate
       AND admissions.olevel_meets_compulsory(p_session, p_jamb_key, g.code)
       -- the programme still has an open seat (its quota is not yet filled by admitted candidates)
       AND EXISTS (
           SELECT 1 FROM admissions.programme_rule r
             JOIN admissions.session_policy p ON p.id = r.policy_id
            WHERE p.session = p_session AND r.programme_code = g.code AND r.quota IS NOT NULL
              AND r.quota > (SELECT count(*) FROM admissions.candidate c
                              WHERE c.session = p_session AND c.offer_state IN ('ADMITTED', 'ACCEPTED')
                                AND (SELECT pc.code FROM ref.programme pc WHERE pc.name = c.programme
                                      ORDER BY pc.archived, pc.code LIMIT 1) = g.code))
     ORDER BY cut DESC NULLS LAST, g.name
     LIMIT 5;
END $$;

COMMENT ON FUNCTION admissions.programme_suggestions(text, text, text) IS
  'Programmes a candidate with five O''Level credits (English, Mathematics and three others) could be moved to: '
  'the UTME score clears the cut-off, the compulsory O''Level subjects are credited, and a seat is open. Suggests only.';

-- the record that a candidate has been emailed their suggestions
CREATE TABLE IF NOT EXISTS admissions.suggestion_sent (
    application_id uuid PRIMARY KEY REFERENCES admissions.application(id),
    programmes     text NOT NULL,
    sent_at        timestamptz NOT NULL DEFAULT now(),
    sent_by        uuid NULL
);
SELECT audit.exempt('admissions.suggestion_sent',
    'A log that a suggestion email was queued; the email itself is on the notice queue, the decision to move is on the spine.');

COMMIT;
