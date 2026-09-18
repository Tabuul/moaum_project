-- ═══════════════════════════════════════════════════════════════════════════
-- V181 — non-index programmes enter the merit list on their computed screening
--
--   A non-index programme (e.g. Computer Science) had an empty merit list even
--   with candidates, because the merit pool required a RELEASED Post-UTME score
--   and those applicants never sit the Post-UTME. But the Screening register
--   already computes their screening figure — the O'Level scaled to 100, blended
--   with the UTME on the session weights (or the O'Level alone for Direct Entry).
--   The merit engine should trust that same figure.
--
--   So for an EXAM-screened (index) programme nothing changes: it still needs the
--   released Post-UTME score and ranks on aggregate_score. For a NON-index
--   programme the pool no longer requires a released score, and the aggregate is
--   computed like the register: an entered score wins; else UTME(70) + O'Level(30)
--   where both exist; else the O'Level alone; else the UTME alone. The UTME cut-off
--   does not exclude a candidate who has no UTME (Direct Entry). Everything after
--   the aggregate — eligibility, National/State Merit, Equality of LG, Locality —
--   is exactly as V180.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION admissions.merit_list(p_session text, p_programme text)
RETURNS TABLE (
    rank int, app_id uuid, jamb_reg_no text, surname text, other_names text,
    entry_mode text, utme int, putme numeric, aggregate numeric,
    state_of_origin text, lga text, meets_cutoff boolean, meets_compulsory boolean,
    eligible boolean, basis text, proposed_offer boolean)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_pol admissions.session_policy;
    v_faculty text;
    v_cutoff int;
    v_quota int;
    v_ru int; v_rd int; v_utme_q int; v_de_q int;
    v_nm_pct int; v_sm_pct int; v_elg_pct int; v_loc_pct int;
    v_closed boolean;
    v_by_exam boolean;
BEGIN
    v_pol := admissions.policy_in_force(p_session);
    SELECT g.faculty_code INTO v_faculty FROM ref.programme g WHERE g.code = p_programme;
    v_closed := admissions.programme_is_closed(p_session, p_programme);
    v_by_exam := admissions.screened_by_exam(p_session, p_programme);
    BEGIN
        v_cutoff := admissions.cutoff_for(p_session, p_programme);
    EXCEPTION WHEN no_data_found THEN v_cutoff := NULL;
    END;
    SELECT r.quota INTO v_quota FROM admissions.programme_rule r WHERE r.policy_id = v_pol.id AND r.programme_code = p_programme;
    SELECT fr.ratio_utme, fr.ratio_de INTO v_ru, v_rd FROM admissions.faculty_ratio(p_session, v_faculty) fr;
    v_ru := coalesce(v_ru, v_pol.ratio_utme);
    v_rd := coalesce(v_rd, v_pol.ratio_de);
    v_utme_q := CASE WHEN v_quota IS NULL THEN NULL ELSE round(v_quota * v_ru / 100.0)::int END;
    v_de_q   := CASE WHEN v_quota IS NULL THEN NULL ELSE v_quota - v_utme_q END;

    SELECT coalesce(sum(percent) FILTER (WHERE criterion = 'NATIONAL_MERIT'), 0),
           coalesce(sum(percent) FILTER (WHERE criterion = 'STATE_MERIT'), 0),
           coalesce(sum(percent) FILTER (WHERE criterion = 'ELG'), 0),
           coalesce(sum(percent) FILTER (WHERE criterion = 'LOCALITY'), 0)
      INTO v_nm_pct, v_sm_pct, v_elg_pct, v_loc_pct
      FROM admissions.selection_criterion WHERE policy_id = v_pol.id;

    RETURN QUERY
    WITH pool AS (
        SELECT a.id AS app_id, c.jamb_reg_no, c.jamb_key, c.surname, c.other_names,
               x.entry_mode, x.aggregate AS utme, a.screening_score AS putme,
               -- the aggregate the Board ranks on: index uses the released Post-UTME (aggregate_score);
               -- non-index is computed like the Screening register (entered score, else UTME+O'Level, else one)
               CASE
                 WHEN v_by_exam THEN admissions.aggregate_score(p_session, x.aggregate, a.screening_score)
                 WHEN a.screening_score IS NOT NULL AND x.aggregate IS NOT NULL
                      THEN round((x.aggregate / 400.0 * 100.0) * v_pol.weight_utme / 100.0 + a.screening_score * v_pol.weight_putme / 100.0, 2)
                 WHEN olv.ol_scaled IS NOT NULL AND x.aggregate IS NOT NULL
                      THEN round((x.aggregate / 400.0 * 100.0) * v_pol.weight_utme / 100.0 + olv.ol_scaled * v_pol.weight_putme / 100.0, 2)
                 WHEN a.screening_score IS NOT NULL THEN a.screening_score
                 WHEN olv.ol_scaled IS NOT NULL THEN olv.ol_scaled
                 WHEN x.aggregate IS NOT NULL THEN round(x.aggregate / 400.0 * 100.0, 2)
                 ELSE NULL
               END AS agg,
               x.state_of_origin, x.lga,
               (v_cutoff IS NULL OR x.aggregate IS NULL OR x.aggregate >= v_cutoff) AS meets_cutoff,
               admissions.olevel_meets_compulsory(p_session, c.jamb_key, p_programme) AS meets_comp
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          JOIN admissions.caps_row_live x ON x.session = a.session AND x.jamb_reg_no = c.jamb_reg_no
          LEFT JOIN LATERAL (
              SELECT CASE WHEN s.total > 0 AND cl.ceiling > 0 THEN round(s.total::numeric / cl.ceiling * 100, 2) END AS ol_scaled
                FROM admissions.olevel_score(p_session, c.jamb_key, p_programme) s
                CROSS JOIN (SELECT (r.subjects_counted * greatest(admissions.olevel_points(p_session, 'A1'), 1) + r.bonus_one_sitting) AS ceiling
                              FROM admissions.olevel_rule(p_session) r) cl
          ) olv ON true
         WHERE a.session = p_session
           AND (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) = p_programme
           AND a.submitted_at IS NOT NULL
           AND (NOT v_by_exam OR a.score_released_at IS NOT NULL)
    ),
    scored AS (
        SELECT p.*,
               (NOT v_closed AND p.agg IS NOT NULL AND p.meets_cutoff AND p.meets_comp) AS is_eligible,
               (p.state_of_origin ILIKE '%benue%') AS is_benue,
               EXISTS (SELECT 1 FROM admissions.catchment_lga cl
                        WHERE cl.policy_id = v_pol.id AND lower(cl.lga) = lower(p.lga)) AS is_catchment,
               CASE WHEN p.entry_mode = 'UTME' THEN v_utme_q ELSE v_de_q END AS mode_q
          FROM pool p
    ),
    b0 AS (
        SELECT s.*,
               CASE WHEN s.is_eligible
                    THEN row_number() OVER (PARTITION BY s.entry_mode ORDER BY (NOT s.is_eligible), s.agg DESC NULLS LAST, s.surname, s.app_id)
               END AS mr
          FROM scored s
    ),
    b1 AS (
        SELECT b0.*,
               (b0.is_eligible AND (v_quota IS NULL OR b0.mr <= round(b0.mode_q * v_nm_pct / 100.0))) AS is_nm
          FROM b0
    ),
    b2r AS (
        SELECT q.app_id, row_number() OVER (PARTITION BY q.entry_mode ORDER BY q.agg DESC NULLS LAST, q.surname, q.app_id) AS r
          FROM b1 q WHERE q.is_eligible AND NOT q.is_nm AND q.is_benue
    ),
    b2 AS (
        SELECT b1.*,
               (b1.is_eligible AND NOT b1.is_nm AND b1.is_benue AND v_quota IS NOT NULL AND b2r.r <= round(b1.mode_q * v_sm_pct / 100.0)) AS is_sm
          FROM b1 LEFT JOIN b2r ON b2r.app_id = b1.app_id
    ),
    b3lga AS (
        SELECT q.app_id, q.entry_mode, q.agg, q.surname,
               row_number() OVER (PARTITION BY q.entry_mode, lower(btrim(coalesce(q.lga, ''))) ORDER BY q.agg DESC NULLS LAST, q.surname, q.app_id) AS lga_rank
          FROM b2 q WHERE q.is_eligible AND NOT q.is_nm AND NOT q.is_sm AND q.is_benue
    ),
    b3r AS (
        SELECT bl.app_id,
               row_number() OVER (PARTITION BY bl.entry_mode ORDER BY bl.lga_rank ASC, bl.agg DESC NULLS LAST, bl.surname, bl.app_id) AS r
          FROM b3lga bl
    ),
    b3 AS (
        SELECT b2.*,
               (b2.is_eligible AND NOT b2.is_nm AND NOT b2.is_sm AND b2.is_benue AND v_quota IS NOT NULL AND b3r.r <= round(b2.mode_q * v_elg_pct / 100.0)) AS is_elg
          FROM b2 LEFT JOIN b3r ON b3r.app_id = b2.app_id
    ),
    b4r AS (
        SELECT q.app_id, row_number() OVER (PARTITION BY q.entry_mode ORDER BY q.agg DESC NULLS LAST, q.surname, q.app_id) AS r
          FROM b3 q WHERE q.is_eligible AND NOT q.is_nm AND NOT q.is_sm AND NOT q.is_elg AND q.is_catchment
    ),
    b4 AS (
        SELECT b3.*,
               (b3.is_eligible AND NOT b3.is_nm AND NOT b3.is_sm AND NOT b3.is_elg AND b3.is_catchment AND v_quota IS NOT NULL AND b4r.r <= round(b3.mode_q * v_loc_pct / 100.0)) AS is_loc
          FROM b3 LEFT JOIN b4r ON b4r.app_id = b3.app_id
    ),
    assigned AS (
        SELECT b4.*,
               CASE WHEN b4.is_nm  THEN 'NM'
                    WHEN b4.is_sm  THEN 'SM'
                    WHEN b4.is_elg THEN 'ELG'
                    WHEN b4.is_loc THEN 'LOCALITY'
                    ELSE NULL END AS basis
          FROM b4
    )
    SELECT (row_number() OVER (ORDER BY b.is_eligible DESC, b.agg DESC NULLS LAST, b.surname, b.app_id))::int AS rank,
           b.app_id, b.jamb_reg_no, b.surname, b.other_names, b.entry_mode, b.utme, b.putme, b.agg,
           b.state_of_origin, b.lga, b.meets_cutoff, b.meets_comp, b.is_eligible, b.basis,
           (b.basis IS NOT NULL) AS proposed_offer
      FROM assigned b
     ORDER BY rank;
END $$;

COMMIT;
