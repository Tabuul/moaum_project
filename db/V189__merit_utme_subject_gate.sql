-- ═══════════════════════════════════════════════════════════════════════════
-- V189 — the merit list considers the UTME subject combination
--
--   Policy: a candidate must offer the programme's required UTME subjects before
--   they can be admitted. Opt-in per programme: when a programme has a structured
--   list of required UTME subjects (rule_subject_group scope 'UTME'), a candidate
--   is eligible only if every listed subject is among their JAMB subjects
--   (raw s1/s2/s3; English is always sat, so an "English" requirement is met by
--   definition). A programme with no list behaves exactly as before, and a
--   candidate with no subject data on the CAPS row is not rejected on this ground
--   (we cannot check, so we do not fail them). Direct Entry is out of the pool for
--   now, so this affects the UTME stream only.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- true when the candidate offers the programme's required UTME subjects (or the programme has none)
CREATE OR REPLACE FUNCTION admissions.utme_meets_combination(p_session text, p_jamb_key text, p_programme text)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    WITH req AS (
        SELECT lower(btrim(rs.subject)) AS subj
          FROM admissions.rule_subject rs
          JOIN admissions.rule_subject_group g ON g.id = rs.group_id
         WHERE g.policy_id = (admissions.policy_in_force(p_session)).id
           AND g.programme_code = p_programme AND g.scope = 'UTME'),
    cand AS (
        SELECT lower(btrim(v)) AS subj
          FROM admissions.caps_row_live x
          CROSS JOIN LATERAL (VALUES (x.raw->>'s1'), (x.raw->>'s2'), (x.raw->>'s3')) AS s(v)
         WHERE x.session = p_session AND x.jamb_key = upper(btrim(p_jamb_key))
           AND nullif(btrim(v), '') IS NOT NULL)
    SELECT CASE
        WHEN NOT EXISTS (SELECT 1 FROM req)  THEN true   -- opt-in: no requirement configured → pass
        WHEN NOT EXISTS (SELECT 1 FROM cand) THEN true   -- no subject data to check → do not reject on this ground
        ELSE NOT EXISTS (
            SELECT 1 FROM req r
             WHERE r.subj NOT LIKE 'english%'            -- English is always offered in UTME
               AND NOT EXISTS (
                    SELECT 1 FROM cand c
                     WHERE c.subj = r.subj
                        OR (r.subj LIKE 'math%' AND r.subj NOT LIKE 'further%' AND c.subj LIKE 'math%' AND c.subj NOT LIKE 'further%')))
    END
$$;

COMMENT ON FUNCTION admissions.utme_meets_combination(text, text, text) IS
  'True when the candidate offers every required UTME subject for the programme (rule_subject scope UTME), '
  'or the programme has no requirement, or the CAPS row carries no subjects to check. English is always met.';

-- merit_list, V182 verbatim, with the UTME-subject gate added to the eligibility test
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
               admissions.olevel_meets_compulsory(p_session, c.jamb_key, p_programme) AS meets_comp,
               admissions.utme_meets_combination(p_session, c.jamb_key, p_programme) AS meets_utme
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
           AND x.entry_mode = 'UTME'                       -- UTME only for now; Direct Entry set aside
           AND (NOT v_by_exam OR a.score_released_at IS NOT NULL)
    ),
    scored AS (
        SELECT p.*,
               (NOT v_closed AND p.agg IS NOT NULL AND p.meets_cutoff AND p.meets_comp AND p.meets_utme) AS is_eligible,
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
