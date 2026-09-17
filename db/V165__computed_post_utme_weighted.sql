-- ===========================================================================
-- V165 - the computed screening figure is UTME-weighted (70) + O'Level (30)
--
--   The computed Post-UTME (and the screening register's computed figure) blended
--   O'Level/100 and UTME/400x100 as a straight average. It should use the
--   session's admission weights instead — UTME 70, Post-UTME 30 by default — the
--   same split the merit aggregate uses:
--       computed = (UTME/400*100) * weight_utme/100  +  (O'Level/100) * weight_putme/100
--   O'Level alone (Direct Entry, no UTME) still shows the O'Level figure; UTME
--   alone shows the scaled UTME. Weights are read from the session policy with a
--   70/30 default, so it works before the policy is put in force.
-- ===========================================================================

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
         WHERE a.session = p_session AND a.submitted_at IS NOT NULL AND a.fee_confirmed_at IS NOT NULL
    ),
    scored AS (
        SELECT ap.*,
               admissions.screened_by_exam(ap.session, ap.code) AS by_exam,
               (SELECT s.total FROM admissions.olevel_score(ap.session, ap.jamb_key, ap.code) s) AS ol_total,
               (SELECT (r.subjects_counted * greatest(admissions.olevel_points(ap.session, 'A1'), 1) + r.bonus_one_sitting)
                  FROM admissions.olevel_rule(ap.session) r) AS ceiling,
               coalesce((SELECT weight_utme FROM admissions.session_policy WHERE session = ap.session ORDER BY (state = 'IN_FORCE') DESC LIMIT 1), 70) AS wu,
               coalesce((SELECT weight_putme FROM admissions.session_policy WHERE session = ap.session ORDER BY (state = 'IN_FORCE') DESC LIMIT 1), 30) AS wp
          FROM apps ap
    )
    SELECT jamb_reg_no, cand_name, prog_name, mode, ol_total, ceiling,
           CASE WHEN ol_total > 0 AND ceiling > 0 THEN round(ol_total::numeric / ceiling * 100, 2) ELSE 0 END,
           utme_agg,
           CASE WHEN ol_total > 0 AND ceiling > 0 AND utme_agg IS NOT NULL
                     THEN round((utme_agg / 400.0 * 100) * wu / 100.0 + (ol_total::numeric / ceiling * 100) * wp / 100.0, 2)
                WHEN ol_total > 0 AND ceiling > 0 THEN round(ol_total::numeric / ceiling * 100, 2)
                WHEN utme_agg IS NOT NULL THEN round(utme_agg / 400.0 * 100, 2)
                ELSE NULL END,
           CASE WHEN utme_agg IS NOT NULL AND ol_total > 0 THEN 'O''Level + UTME'
                WHEN ol_total > 0 THEN 'O''Level'
                WHEN utme_agg IS NOT NULL THEN 'UTME'
                ELSE 'none' END
      FROM scored
     WHERE NOT by_exam OR mode = 'DIRECT_ENTRY'
     ORDER BY 9 DESC NULLS LAST, 2;
$$;

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
                  FROM admissions.olevel_rule(ap.session) r) AS ceiling,
               coalesce((SELECT weight_utme FROM admissions.session_policy WHERE session = ap.session ORDER BY (state = 'IN_FORCE') DESC LIMIT 1), 70) AS wu,
               coalesce((SELECT weight_putme FROM admissions.session_policy WHERE session = ap.session ORDER BY (state = 'IN_FORCE') DESC LIMIT 1), 30) AS wp
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
                  THEN round((utme_agg / 400.0 * 100) * wu / 100.0 + (ol_total::numeric / ceiling * 100) * wp / 100.0, 2)
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

COMMIT;
