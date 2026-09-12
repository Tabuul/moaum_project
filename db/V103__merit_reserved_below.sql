-- ═══════════════════════════════════════════════════════════════════════════
-- V103 — Merit first, the reserved categories from below the merit line
--
--   V102 filled National Merit from the top of the list (any origin), then State
--   Merit, ELG and Locality — correct. But it then did two things that put a
--   lower-ranked candidate on National Merit above a higher-ranked State Merit
--   one:
--     · eligible candidates beyond the four shares fell back to National Merit,
--       so a non-indigene ranked below the merit line was labelled NM; and
--     · the offer was filled by pure merit rank (UTME:DE), so those overflow
--       candidates were offered at all.
--
--   The rule now: National Merit is exactly the top of the ranked, eligible pool
--   up to its share — the highest aggregates, irrespective of nationality, state
--   or local government. State Merit (Benue), ELG and Locality are then filled
--   ONLY from candidates BELOW that merit line, each up to its share. So no
--   State Merit candidate ever outranks a National Merit one. A candidate below
--   the merit line who fits no reserved category is not offered here — the Board
--   works the waiting list. A programme with no quota set admits every eligible
--   candidate on merit.
--
--   The offer is now exactly the candidates who won a category seat; the seat
--   count per criterion is that criterion's share of the programme quota.
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
    -- ── National Merit: the top of the eligible pool by aggregate, any origin ──
    b0 AS (
        SELECT s.*,
               CASE WHEN s.is_eligible
                    THEN row_number() OVER (ORDER BY (NOT s.is_eligible), s.agg DESC NULLS LAST, s.surname, s.app_id)
               END AS mr
          FROM scored s
    ),
    b1 AS (
        SELECT b0.*, (b0.is_eligible AND (v_nm_q IS NULL OR b0.mr <= v_nm_q)) AS is_nm FROM b0
    ),
    -- ── State Merit: Benue indigenes from BELOW the merit line ──
    b2r AS (
        SELECT q.app_id, row_number() OVER (ORDER BY q.agg DESC NULLS LAST, q.surname, q.app_id) AS r
          FROM b1 q WHERE q.is_eligible AND NOT q.is_nm AND q.is_benue
    ),
    b2 AS (
        SELECT b1.*, (b1.is_eligible AND NOT b1.is_nm AND b1.is_benue AND v_sm_q IS NOT NULL AND b2r.r <= v_sm_q) AS is_sm
          FROM b1 LEFT JOIN b2r ON b2r.app_id = b1.app_id
    ),
    -- ── Equality of Local Government: catchment LGAs from below the merit line ──
    b3r AS (
        SELECT q.app_id, row_number() OVER (ORDER BY q.agg DESC NULLS LAST, q.surname, q.app_id) AS r
          FROM b2 q WHERE q.is_eligible AND NOT q.is_nm AND NOT q.is_sm AND q.is_catchment
    ),
    b3 AS (
        SELECT b2.*, (b2.is_eligible AND NOT b2.is_nm AND NOT b2.is_sm AND b2.is_catchment AND v_elg_q IS NOT NULL AND b3r.r <= v_elg_q) AS is_elg
          FROM b2 LEFT JOIN b3r ON b3r.app_id = b2.app_id
    ),
    -- ── Locality: the remaining catchment candidates ──
    b4r AS (
        SELECT q.app_id, row_number() OVER (ORDER BY q.agg DESC NULLS LAST, q.surname, q.app_id) AS r
          FROM b3 q WHERE q.is_eligible AND NOT q.is_nm AND NOT q.is_sm AND NOT q.is_elg AND q.is_catchment
    ),
    b4 AS (
        SELECT b3.*, (b3.is_eligible AND NOT b3.is_nm AND NOT b3.is_sm AND NOT b3.is_elg AND b3.is_catchment AND v_loc_q IS NOT NULL AND b4r.r <= v_loc_q) AS is_loc
          FROM b3 LEFT JOIN b4r ON b4r.app_id = b3.app_id
    ),
    assigned AS (
        SELECT b4.*,
               CASE WHEN b4.is_nm  THEN 'NM'
                    WHEN b4.is_sm  THEN 'SM'
                    WHEN b4.is_elg THEN 'ELG'
                    WHEN b4.is_loc THEN 'LOCALITY'
                    ELSE NULL END AS basis   -- eligible but below the line and in no reserved category: waiting list
          FROM b4
    )
    -- the offer is exactly the candidates who won a category seat; National Merit is the top block,
    -- the reserved categories are all below it, so no offer's basis outranks a National Merit offer
    SELECT (row_number() OVER (ORDER BY b.is_eligible DESC, b.agg DESC NULLS LAST, b.surname, b.app_id))::int AS rank,
           b.app_id, b.jamb_reg_no, b.surname, b.other_names, b.entry_mode, b.utme, b.putme, b.agg,
           b.state_of_origin, b.lga, b.meets_cutoff, b.meets_comp, b.is_eligible, b.basis,
           (b.basis IS NOT NULL) AS proposed_offer
      FROM assigned b
     ORDER BY rank;
END $$;

COMMENT ON FUNCTION admissions.merit_list(text, text) IS
    'The eligible pool for a programme, ranked by the session aggregate. National Merit is the top of the '
    'pool up to its share, any origin; State Merit, ELG and Locality are filled from below the merit line, '
    'each up to its share. The proposed offer is exactly those who won a category seat, so no offer''s basis '
    'outranks a National Merit offer. It proposes; the Board decides.';

COMMIT;
