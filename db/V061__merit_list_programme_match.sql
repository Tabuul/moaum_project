-- ═══════════════════════════════════════════════════════════════════════════
-- V061 — the merit list matches its programme, so its pool is no longer empty
--
--   admissions.merit_list (V054) drew the pool with `c.programme = p_programme`.
--   But admissions.candidate.programme holds the programme's NAME (it is set to
--   the CAPS row's programme name — V021 — and everywhere else the code is
--   RESOLVED from it, e.g. screening_component/screening_result:
--       (SELECT p.code FROM ref.programme p WHERE p.name = c.programme
--         ORDER BY p.archived, p.code LIMIT 1)).
--   merit_list is called with the programme CODE (from the picker), so it was
--   comparing a name to a code and the pool was ALWAYS empty — every programme
--   showed Pool 0 even with submitted, released, CAPS-listed applicants.
--
--   The same slip fed the O'Level compulsory-credit check the programme NAME
--   where olevel_compulsory_missing expects the CODE (it matches
--   programme_olevel_allowance.programme_code), so a per-programme pass
--   exception could never apply. Both are fixed here; nothing else changes.
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
    v_utme_q int; v_de_q int;
    v_closed boolean;
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

    RETURN QUERY
    WITH pool AS (
        SELECT a.id AS app_id, c.jamb_reg_no, c.jamb_key, c.surname, c.other_names,
               x.entry_mode, x.aggregate AS utme, a.screening_score AS putme,
               admissions.aggregate_score(p_session, x.aggregate, a.screening_score) AS agg,
               x.state_of_origin, x.lga,
               (v_cutoff IS NULL OR x.aggregate >= v_cutoff) AS meets_cutoff,
               admissions.olevel_meets_compulsory(p_session, c.jamb_key, p_programme) AS meets_comp
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          JOIN admissions.caps_row_live x ON x.session = a.session AND x.jamb_reg_no = c.jamb_reg_no
         WHERE a.session = p_session
           AND (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) = p_programme
           AND a.submitted_at IS NOT NULL AND a.score_released_at IS NOT NULL
    ),
    scored AS (
        SELECT p.*,
               (NOT v_closed AND p.agg IS NOT NULL AND p.meets_cutoff AND p.meets_comp) AS is_eligible,
               CASE
                 WHEN EXISTS (SELECT 1 FROM admissions.catchment_lga cl
                               WHERE cl.policy_id = v_pol.id AND lower(cl.lga) = lower(p.lga)) THEN 'LOCALITY'
                 WHEN p.state_of_origin ILIKE '%benue%' THEN 'SM'
                 ELSE 'NM'
               END AS basis
          FROM pool p
    ),
    ranked AS (
        SELECT s.*,
               row_number() OVER (PARTITION BY s.is_eligible, s.entry_mode ORDER BY s.agg DESC NULLS LAST, s.surname, s.app_id) AS mode_rank
          FROM scored s
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

COMMIT;
