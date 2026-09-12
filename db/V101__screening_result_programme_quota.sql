-- ═══════════════════════════════════════════════════════════════════════════
-- V101 — the applicant's standing shows the programme's quota, not the faculty's
--
--   admissions.screening_result returns the candidate's merit position, the
--   number who applied, and the number of places. The places came from the
--   faculty-level admissions.faculty_quota, but quotas are per programme now
--   (admissions.programme_rule.quota — what the merit engine fills to). So a
--   candidate's standing showed the whole faculty's places, an old value that
--   no longer matches the merit list or the JAMB template.
--
--   Only the places subquery changes; everything else is exactly as V021 left
--   it. (The faculty-level ratio and cut-off still come from faculty_quota; the
--   quota is the per-programme figure.)
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION admissions.screening_result(p_app uuid)
RETURNS TABLE (utme int, utme_scaled numeric, screening numeric, screening_source text, weight_utme int, weight_putme int,
               aggregate numeric, cutoff int, merit_position int, applied int, places int)
LANGUAGE sql STABLE AS $$
    WITH me AS (
        SELECT a.*, c.programme AS programme_name, r.aggregate AS utme_raw,
               (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) AS code
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE a.id = p_app),
    w AS (
        SELECT coalesce((SELECT p.weight_utme FROM admissions.session_policy p, me WHERE p.session = me.session), 70) AS wu,
               coalesce((SELECT p.weight_putme FROM admissions.session_policy p, me WHERE p.session = me.session), 30) AS wp),
    mine AS (SELECT * FROM admissions.screening_component(p_app)),
    agg AS (
        SELECT a.id,
               round((coalesce(r.aggregate, 0) / 400.0 * 100 * w.wu / 100.0 + sc.screening * w.wp / 100.0)::numeric, 2) AS total
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          CROSS JOIN LATERAL admissions.screening_component(a.id) sc, w, me
         WHERE a.session = me.session AND a.score_released_at IS NOT NULL AND sc.screening IS NOT NULL
           AND c.programme = me.programme_name),
    ranked AS (SELECT id, rank() OVER (ORDER BY total DESC) AS pos, count(*) OVER () AS applied FROM agg)
    SELECT me.utme_raw,
           round(me.utme_raw / 400.0 * 100, 1),
           mine.screening, mine.source,
           w.wu, w.wp,
           CASE WHEN mine.screening IS NULL OR me.utme_raw IS NULL THEN NULL
                ELSE round((me.utme_raw / 400.0 * 100 * w.wu / 100.0 + mine.screening * w.wp / 100.0)::numeric, 2) END,
           admissions.cutoff_or_null(me.session, me.code),
           (SELECT pos::int FROM ranked WHERE ranked.id = me.id),
           (SELECT applied::int FROM ranked WHERE ranked.id = me.id),
           (SELECT r.quota FROM admissions.programme_rule r JOIN admissions.session_policy p ON p.id = r.policy_id
             WHERE p.session = me.session AND r.programme_code = me.code)
      FROM me, w, mine;
$$;

COMMIT;
