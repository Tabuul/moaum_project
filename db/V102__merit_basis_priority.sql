-- ═══════════════════════════════════════════════════════════════════════════
-- V102 — National Merit is merit, not origin; the bases fill in priority order
--
--   The merit engine labelled each candidate's selection basis by origin alone:
--     · a catchment LGA          → LOCALITY
--     · state of origin = Benue   → STATE MERIT
--     · everyone else            → NATIONAL MERIT
--
--   That handed National Merit to non-indigenes by definition and denied it to
--   Benue indigenes — even the highest scorers — which is the opposite of what
--   National Merit means. National Merit is the top of the list irrespective of
--   nationality, state or local government.
--
--   The basis is now an ALLOCATION, filled in priority order against each
--   criterion's share of the programme quota (admissions.selection_criterion):
--     1. NATIONAL MERIT  — the highest aggregates, any origin, fills first
--     2. STATE MERIT     — Benue indigenes not already taken on merit
--     3. ELG             — candidates from the stated catchment LGAs
--     4. LOCALITY        — the remaining catchment candidates
--   Anyone eligible beyond the four shares is merit (NM). The OFFER selection
--   (who fills the quota, UTME:DE by the faculty ratio, with the flexible fill)
--   is unchanged — only the basis each offer is recorded under changes.
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
    v_ru int; v_rd int;
    v_closed boolean;
    v_nm_pct int; v_sm_pct int; v_elg_pct int; v_loc_pct int;
    v_nm_q int; v_sm_q int; v_elg_q int; v_loc_q int;
BEGIN
    v_pol := admissions.policy_in_force(p_session);
    SELECT g.faculty_code INTO v_faculty FROM ref.programme g WHERE g.code = p_programme;
    v_closed := admissions.programme_is_closed(p_session, p_programme);
    BEGIN
        v_cutoff := admissions.cutoff_for(p_session, p_programme);
    EXCEPTION WHEN no_data_found THEN v_cutoff := NULL;   -- no cut-off set: nobody is below one
    END;
    SELECT r.quota INTO v_quota FROM admissions.programme_rule r WHERE r.policy_id = v_pol.id AND r.programme_code = p_programme;
    SELECT fr.ratio_utme, fr.ratio_de INTO v_ru, v_rd FROM admissions.faculty_ratio(p_session, v_faculty) fr;
    v_ru := coalesce(v_ru, v_pol.ratio_utme);
    v_rd := coalesce(v_rd, v_pol.ratio_de);

    -- each criterion's share of the programme quota; a null quota means no caps (all merit)
    SELECT coalesce(sum(percent) FILTER (WHERE criterion = 'NATIONAL_MERIT'), 0),
           coalesce(sum(percent) FILTER (WHERE criterion = 'STATE_MERIT'), 0),
           coalesce(sum(percent) FILTER (WHERE criterion = 'ELG'), 0),
           coalesce(sum(percent) FILTER (WHERE criterion = 'LOCALITY'), 0)
      INTO v_nm_pct, v_sm_pct, v_elg_pct, v_loc_pct
      FROM admissions.selection_criterion WHERE policy_id = v_pol.id;
    v_nm_q  := CASE WHEN v_quota IS NULL THEN NULL ELSE round(v_quota * v_nm_pct  / 100.0)::int END;
    v_sm_q  := CASE WHEN v_quota IS NULL THEN NULL ELSE round(v_quota * v_sm_pct  / 100.0)::int END;
    v_elg_q := CASE WHEN v_quota IS NULL THEN NULL ELSE round(v_quota * v_elg_pct / 100.0)::int END;
    v_loc_q := CASE WHEN v_quota IS NULL THEN NULL ELSE round(v_quota * v_loc_pct / 100.0)::int END;

    RETURN QUERY
    WITH pool AS (
        SELECT a.id AS app_id, c.jamb_reg_no, c.jamb_key, c.surname, c.other_names,
               x.entry_mode, x.aggregate AS utme, a.screening_score AS putme,
               admissions.aggregate_score(p_session, x.aggregate, a.screening_score) AS agg,
               x.state_of_origin, x.lga,
               (v_cutoff IS NULL OR x.aggregate >= v_cutoff) AS meets_cutoff,
               admissions.olevel_meets_compulsory(p_session, c.jamb_key, c.programme) AS meets_comp
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          JOIN admissions.caps_row_live x ON x.session = a.session AND x.jamb_reg_no = c.jamb_reg_no
         WHERE a.session = p_session AND c.programme = p_programme
           AND a.submitted_at IS NOT NULL AND a.score_released_at IS NOT NULL
    ),
    scored AS (
        SELECT p.*,
               (NOT v_closed AND p.agg IS NOT NULL AND p.meets_cutoff AND p.meets_comp) AS is_eligible,
               (p.state_of_origin ILIKE '%benue%') AS is_benue,
               EXISTS (SELECT 1 FROM admissions.catchment_lga cl
                        WHERE cl.policy_id = v_pol.id AND lower(cl.lga) = lower(p.lga)) AS is_catchment
          FROM pool p
    ),
    -- ── the basis, allocated in priority order against each criterion's share ──
    b0 AS (
        SELECT s.*,
               CASE WHEN s.is_eligible
                    THEN row_number() OVER (ORDER BY (NOT s.is_eligible), s.agg DESC NULLS LAST, s.surname, s.app_id)
               END AS mr
          FROM scored s
    ),
    b1 AS (  -- National Merit: the highest aggregates, any origin
        SELECT b0.*, (b0.is_eligible AND (v_nm_q IS NULL OR b0.mr <= v_nm_q)) AS is_nm FROM b0
    ),
    b2r AS (
        SELECT q.app_id, row_number() OVER (ORDER BY q.agg DESC NULLS LAST, q.surname, q.app_id) AS r
          FROM b1 q WHERE q.is_eligible AND NOT q.is_nm AND q.is_benue
    ),
    b2 AS (  -- State Merit: Benue indigenes not already taken on merit
        SELECT b1.*, (b1.is_eligible AND NOT b1.is_nm AND b1.is_benue AND (v_sm_q IS NULL OR b2r.r <= v_sm_q)) AS is_sm
          FROM b1 LEFT JOIN b2r ON b2r.app_id = b1.app_id
    ),
    b3r AS (
        SELECT q.app_id, row_number() OVER (ORDER BY q.agg DESC NULLS LAST, q.surname, q.app_id) AS r
          FROM b2 q WHERE q.is_eligible AND NOT q.is_nm AND NOT q.is_sm AND q.is_catchment
    ),
    b3 AS (  -- Equality of Local Government: candidates from the catchment LGAs
        SELECT b2.*, (b2.is_eligible AND NOT b2.is_nm AND NOT b2.is_sm AND b2.is_catchment AND (v_elg_q IS NULL OR b3r.r <= v_elg_q)) AS is_elg
          FROM b2 LEFT JOIN b3r ON b3r.app_id = b2.app_id
    ),
    b4r AS (
        SELECT q.app_id, row_number() OVER (ORDER BY q.agg DESC NULLS LAST, q.surname, q.app_id) AS r
          FROM b3 q WHERE q.is_eligible AND NOT q.is_nm AND NOT q.is_sm AND NOT q.is_elg AND q.is_catchment
    ),
    b4 AS (  -- Locality: the remaining catchment candidates
        SELECT b3.*, (b3.is_eligible AND NOT b3.is_nm AND NOT b3.is_sm AND NOT b3.is_elg AND b3.is_catchment AND (v_loc_q IS NULL OR b4r.r <= v_loc_q)) AS is_loc
          FROM b3 LEFT JOIN b4r ON b4r.app_id = b3.app_id
    ),
    assigned AS (
        SELECT b4.*,
               CASE WHEN b4.is_nm  THEN 'NM'
                    WHEN b4.is_sm  THEN 'SM'
                    WHEN b4.is_elg THEN 'ELG'
                    WHEN b4.is_loc THEN 'LOCALITY'
                    WHEN b4.is_eligible THEN 'NM'   -- eligible beyond the four shares is merit
                    ELSE NULL END AS basis
          FROM b4
    ),
    -- ── the offer selection, unchanged: the quota UTME:DE by the faculty ratio, then a flexible fill ──
    ranked AS (
        SELECT a.*,
               row_number() OVER (PARTITION BY a.is_eligible, a.entry_mode ORDER BY a.agg DESC NULLS LAST, a.surname, a.app_id) AS mode_rank
          FROM assigned a
    ),
    base AS (
        SELECT r.*,
               CASE WHEN NOT r.is_eligible THEN false
                    WHEN v_quota IS NULL THEN true
                    WHEN r.entry_mode = 'UTME' THEN r.mode_rank <= round(v_quota * v_ru / 100.0)
                    ELSE r.mode_rank <= v_quota - round(v_quota * v_ru / 100.0)
               END AS base_offer
          FROM ranked r
    ),
    leftover AS (
        SELECT CASE WHEN v_quota IS NULL THEN 0
                    ELSE greatest(v_quota - count(*) FILTER (WHERE base_offer), 0) END AS n
          FROM base
    ),
    fill AS (
        SELECT b.app_id,
               row_number() OVER (ORDER BY b.agg DESC NULLS LAST, b.surname, b.app_id) AS fr
          FROM base b
         WHERE b.is_eligible AND NOT b.base_offer
    )
    SELECT (row_number() OVER (ORDER BY b.is_eligible DESC, b.agg DESC NULLS LAST, b.surname, b.app_id))::int AS rank,
           b.app_id, b.jamb_reg_no, b.surname, b.other_names, b.entry_mode, b.utme, b.putme, b.agg,
           b.state_of_origin, b.lga, b.meets_cutoff, b.meets_comp, b.is_eligible, b.basis,
           (b.base_offer OR coalesce(f.fr <= (SELECT n FROM leftover), false)) AS proposed_offer
      FROM base b
      LEFT JOIN fill f ON f.app_id = b.app_id
     ORDER BY rank;
END $$;

COMMENT ON FUNCTION admissions.merit_list(text, text) IS
    'The eligible pool for a programme, ranked by the session aggregate. The basis is allocated in '
    'priority order against each criterion''s share of the quota — National Merit (any origin) first, '
    'then State Merit, ELG and Locality; eligible candidates beyond the shares are merit. The proposed '
    'offer fills the programme quota UTME:DE by the faculty ratio and spills flexibly. It proposes; the Board decides.';

COMMIT;
