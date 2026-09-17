-- ===========================================================================
-- V159 - the screening register: every screened candidate, one report
--
--   admissions.non_sitter_post_utme (V090) reports only the candidates who did
--   NOT sit the Post-UTME. The Academic Office also needs the whole picture in
--   one place: everyone with a submitted application for the session, the mark
--   each was screened by, and where it came from — the Post-UTME they sat, the
--   O'Level auto-screening (scaled, blended with the UTME), or Direct Entry.
--
--   Read-only report; it does not change the sat score or the merit engine.
--   JAMB number included; ordered by programme.
-- ===========================================================================

BEGIN;

CREATE OR REPLACE FUNCTION admissions.screening_register(p_session text)
RETURNS TABLE (jamb_reg_no text, name text, programme text, programme_code text, entry_mode text,
               utme int, olevel_scaled numeric, post_utme numeric, screening numeric, source text)
LANGUAGE sql STABLE AS $$
    WITH apps AS (
        SELECT a.session, a.screening_score, c.jamb_key, c.jamb_reg_no,
               c.surname || ', ' || c.other_names AS cand_name, c.programme AS prog_name,
               (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) AS code,
               x.entry_mode AS mode, x.aggregate AS utme_agg
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          JOIN admissions.caps_row_live x ON x.session = a.session AND x.jamb_reg_no = c.jamb_reg_no
         WHERE a.session = p_session AND a.submitted_at IS NOT NULL
    ),
    scored AS (
        SELECT ap.*,
               admissions.screened_by_exam(ap.session, ap.code) AS by_exam,
               (SELECT s.total FROM admissions.olevel_score(ap.session, ap.jamb_key, ap.code) s) AS ol_total,
               (SELECT (r.subjects_counted * greatest(admissions.olevel_points(ap.session, 'A1'), 1) + r.bonus_one_sitting)
                  FROM admissions.olevel_rule(ap.session) r) AS ceiling
          FROM apps ap
    )
    SELECT jamb_reg_no, cand_name, prog_name, code, mode,
           utme_agg,
           CASE WHEN ol_total > 0 AND ceiling > 0 THEN round(ol_total::numeric / ceiling * 100, 2) END AS olevel_scaled,
           screening_score::numeric AS post_utme,
           CASE
             WHEN screening_score IS NOT NULL THEN screening_score::numeric
             WHEN by_exam THEN NULL
             WHEN ol_total > 0 AND ceiling > 0 AND utme_agg IS NOT NULL
                  THEN round((ol_total::numeric / ceiling * 100 + utme_agg / 400.0 * 100) / 2, 2)
             WHEN ol_total > 0 AND ceiling > 0 THEN round(ol_total::numeric / ceiling * 100, 2)
             WHEN utme_agg IS NOT NULL THEN round(utme_agg / 400.0 * 100, 2)
             ELSE NULL END AS screening,
           CASE
             WHEN screening_score IS NOT NULL THEN 'Post-UTME'
             WHEN by_exam THEN 'Awaiting Post-UTME'
             WHEN ol_total > 0 AND utme_agg IS NOT NULL THEN 'O''Level + UTME'
             WHEN ol_total > 0 THEN 'O''Level'
             WHEN utme_agg IS NOT NULL THEN 'UTME'
             ELSE 'none' END AS source
      FROM scored
     ORDER BY prog_name, screening DESC NULLS LAST, cand_name;
$$;

COMMENT ON FUNCTION admissions.screening_register(text) IS
'Academic Office report: every candidate with a submitted application for the session, the mark they were screened by and its source (Post-UTME sat, O''Level auto-screening scaled/blended, or Direct Entry). Read-only.';

COMMIT;
