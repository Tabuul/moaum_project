-- ═══════════════════════════════════════════════════════════════════════════
-- V090 — a computed Post-UTME score for candidates who do not sit the Post-UTME
--
--   Some candidates never sit the Post-UTME examination — Direct Entry entrants,
--   and any whose programme is not screened by examination and who entered no CBT
--   score. For them the Academic Office needs a screening figure all the same, so
--   the merit picture is complete. It is COMPUTED, not sat: the O'Level aggregate
--   (scaled to 100 under the session's grading) blended with the UTME aggregate
--   (scaled to 100) where the candidate has one; a Direct Entry candidate with no
--   UTME falls back to the O'Level figure alone.
--
--   This is a read-only report. It does not touch the sat screening score, the
--   merit engine or anyone's stored record — it is shown to the Academic Office.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION admissions.non_sitter_post_utme(p_session text)
RETURNS TABLE (jamb_reg_no text, name text, programme text, entry_mode text,
               olevel_total int, olevel_ceiling int, olevel_scaled numeric, utme int, computed numeric, source text)
LANGUAGE sql STABLE AS $$
    WITH apps AS (
        SELECT a.id AS app_id, a.session, a.screening_score, c.jamb_key, c.jamb_reg_no,
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
    SELECT jamb_reg_no, cand_name, prog_name, mode, ol_total, ceiling,
           CASE WHEN ol_total > 0 AND ceiling > 0 THEN round(ol_total::numeric / ceiling * 100, 2) ELSE 0 END,
           utme_agg,
           CASE WHEN ol_total > 0 AND ceiling > 0 AND utme_agg IS NOT NULL
                     THEN round((ol_total::numeric / ceiling * 100 + utme_agg / 400.0 * 100) / 2, 2)
                WHEN ol_total > 0 AND ceiling > 0 THEN round(ol_total::numeric / ceiling * 100, 2)
                WHEN utme_agg IS NOT NULL THEN round(utme_agg / 400.0 * 100, 2)
                ELSE NULL END,
           CASE WHEN utme_agg IS NOT NULL AND ol_total > 0 THEN 'O''Level + UTME'
                WHEN ol_total > 0 THEN 'O''Level'
                WHEN utme_agg IS NOT NULL THEN 'UTME'
                ELSE 'none' END
      FROM scored
     WHERE NOT by_exam AND screening_score IS NULL    -- did not sit the Post-UTME
     ORDER BY computed DESC NULLS LAST, cand_name;
$$;

COMMENT ON FUNCTION admissions.non_sitter_post_utme(text) IS
'Academic Office report: candidates who did not sit the Post-UTME (Direct Entry, and non-exam programmes with no CBT score), with a computed Post-UTME from the O''Level aggregate blended with the UTME where present. Read-only; does not alter the sat score or the merit engine.';

COMMIT;
