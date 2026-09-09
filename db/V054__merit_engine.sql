-- ═══════════════════════════════════════════════════════════════════════════
-- V054 — the merit engine: a proposed admission list that fills the quota
--
--   Until now a Board decision was entered one candidate at a time. This adds
--   admissions.merit_list(session, programme): the eligible pool for a
--   programme, ranked by the session's aggregate, with a proposed offer that
--   fills the programme's quota. It PROPOSES; the Board still enters and
--   releases the decision (admissions.decide_application), so the engine never
--   admits anybody on its own.
--
--   How the quota is filled:
--     · eligibility first — the candidate submitted, the screening score is
--       released, the UTME aggregate is at or above the programme's cut-off
--       (its own, else the faculty's), the compulsory O'Level credits are held
--       (V053), and the programme is not closed;
--     · the quota is split UTME:Direct-Entry by the ratio in force for the
--       faculty (V053 — 80:20, or Education's 60:40);
--     · each mode is filled by aggregate, best first;
--     · and it fills flexibly — a seat a mode cannot fill (too few eligible in
--       it) spills to the other mode by merit, so an approved seat is never
--       left empty while an eligible candidate waits.
--
--   The basis each proposed offer carries — Locality, State Merit or National
--   Merit — is read from the candidate's state and local government against the
--   catchment the Office states (admissions.catchment_lga). ELG's ceiling is
--   enforced on the settings (V053); the reserved-seat split by criterion is a
--   later layer that needs the full catchment/zone data, and until then the
--   fill is by merit with the basis recorded.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- a per-programme quota, so the faculty quota is the sum of its programmes'
ALTER TABLE admissions.programme_rule ADD COLUMN IF NOT EXISTS quota int NULL;
ALTER TABLE admissions.programme_rule
    DROP CONSTRAINT IF EXISTS ck_pr_quota,
    ADD CONSTRAINT ck_pr_quota CHECK (quota IS NULL OR quota >= 0);
COMMENT ON COLUMN admissions.programme_rule.quota IS
    'The programme''s own carrying capacity for the session. NULL means none is set, '
    'and the merit list proposes an offer to everyone eligible rather than filling to a number.';

-- the catchment local governments, for the Locality basis
CREATE TABLE admissions.catchment_lga (
    policy_id uuid NOT NULL REFERENCES admissions.session_policy(id),
    lga       text NOT NULL,
    PRIMARY KEY (policy_id, lga)
);
COMMENT ON TABLE admissions.catchment_lga IS
    'The local governments in the University''s immediate catchment, per policy. A '
    'candidate from one of these carries the Locality basis. Empty until the Office states it.';
SELECT audit.attach('admissions.catchment_lga');

-- the merit list for a programme: the eligible pool, ranked, with the proposed offer
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

COMMENT ON FUNCTION admissions.merit_list(text, text) IS
    'The eligible pool for a programme, ranked by the session aggregate, with a proposed '
    'offer that fills the programme quota UTME:DE by the faculty ratio and spills flexibly '
    'so no seat is left empty. It proposes; the Board decides.';

COMMIT;
