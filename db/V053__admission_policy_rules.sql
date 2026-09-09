-- ═══════════════════════════════════════════════════════════════════════════
-- V053 — three admission-policy decisions made dynamic and enforced
--
--   The admission settings screen surfaced three open questions in the
--   University's guidelines. The Academic Office decided them (2026-09-09):
--
--   1. Equality of Local Government (ELG) is a share the Committee may set —
--      30% or otherwise — but it must never exceed the ceiling (elg_cap_pct,
--      2.11, default 50%). ELG > the ceiling is now a settings finding, so a
--      policy that crosses it cannot be put in force.
--
--   2. The 60:40 "Education exception" is the UTME:Direct-Entry ratio: 80:20
--      for every faculty, 60:40 for Education. It is now a per-faculty
--      override on faculty_quota, defaulting to the session's own ratio.
--
--   3. A credit in English and Mathematics is compulsory for ALL programmes;
--      a pass (D7/E8) is not a credit and is ignored. A programme may carry a
--      per-programme exception (accept a pass / waive the subject) for the few
--      rows whose own requirements differ. The compulsory set is data, per
--      session, falling back to English + Mathematics when a session states
--      nothing. An offer to a candidate whose recorded O'Level lacks a
--      compulsory credit is refused, with the missing subject named.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- the faculty_quota UPDATE below is on the audit spine; attribute it to the
-- system actor, the way the seed migrations do
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'academic', true);
SELECT set_config('moaum.reason', 'Admission-policy rules made dynamic and enforced (V053)', true);

-- ── 1. ELG never exceeds its ceiling ──────────────────────────────────────
-- built on the V022 body (a programme with no rule is skipped, not a finding —
-- a closed programme needs none), with the ELG ceiling added
CREATE OR REPLACE FUNCTION admissions.policy_findings(p_session text)
RETURNS TABLE (finding text, detail text, owner text)
LANGUAGE sql
STABLE
AS $$
    WITH pol AS (SELECT * FROM admissions.session_policy WHERE session = p_session)
    SELECT 'The selection criteria do not total 100%'::text,
           'National Merit, State Merit, Equality of Local Government and '
           'Locality total ' || coalesce(sum(c.percent), 0) || '%. The guidelines '
           'set 10 + 35 + 30 + 25.',
           'Central Admissions Committee'::text
      FROM pol p LEFT JOIN admissions.selection_criterion c ON c.policy_id = p.id
     GROUP BY p.id
    HAVING coalesce(sum(c.percent), 0) <> 100
  UNION ALL
    SELECT 'The faculty quotas do not total the NUC approved quota'::text,
           'Distributed ' || coalesce(sum(f.quota), 0) || ' of ' || p.nuc_quota ||
           '. ' || abs(p.nuc_quota - coalesce(sum(f.quota), 0))::text ||
           CASE WHEN coalesce(sum(f.quota), 0) < p.nuc_quota
                THEN ' places are unallocated.' ELSE ' places over the capacity.' END,
           'Deans of Faculties'::text
      FROM pol p LEFT JOIN admissions.faculty_quota f ON f.policy_id = p.id
     GROUP BY p.id, p.nuc_quota
    HAVING coalesce(sum(f.quota), 0) <> p.nuc_quota
  UNION ALL
    SELECT 'A faculty has no UTME cut-off'::text,
           string_agg(f.faculty_code, ', ' ORDER BY f.faculty_code) ||
           ' — a faculty with no cut-off admits on no rule at all.',
           'Central Admissions Committee'::text
      FROM pol p JOIN admissions.faculty_quota f ON f.policy_id = p.id
     WHERE f.cutoff IS NULL
     GROUP BY p.id
  UNION ALL
    SELECT 'A programme cut-off is below its faculty''s'::text,
           string_agg(r.programme_code || ' at ' || r.cutoff || ' under ' ||
                      g.faculty_code || ' at ' || f.cutoff, '; '),
           'Central Admissions Committee'::text
      FROM pol p
      JOIN admissions.programme_rule r ON r.policy_id = p.id
      JOIN ref.programme g ON g.code = r.programme_code
      JOIN admissions.faculty_quota f ON f.policy_id = p.id
                                     AND f.faculty_code = g.faculty_code
     WHERE r.cutoff IS NOT NULL AND f.cutoff IS NOT NULL AND r.cutoff < f.cutoff
     GROUP BY p.id
  UNION ALL
    -- 2.11 · Equality of Local Government must not exceed its ceiling
    SELECT 'Equality of Local Government exceeds its ceiling'::text,
           'ELG is set at ' || c.percent || '% but the ceiling is ' || p.elg_cap_pct ||
           '%. ELG may be any share up to the ceiling, never above it.',
           'Central Admissions Committee'::text
      FROM pol p JOIN admissions.selection_criterion c ON c.policy_id = p.id AND c.criterion = 'ELG'
     WHERE c.percent > p.elg_cap_pct
$$;

-- ── 2. the 60:40 Education exception: per-faculty UTME:DE ──────────────────
ALTER TABLE admissions.faculty_quota
    ADD COLUMN IF NOT EXISTS ratio_utme int NULL,
    ADD COLUMN IF NOT EXISTS ratio_de   int NULL;
ALTER TABLE admissions.faculty_quota
    DROP CONSTRAINT IF EXISTS ck_fq_ratio,
    ADD CONSTRAINT ck_fq_ratio CHECK (
        (ratio_utme IS NULL AND ratio_de IS NULL)
        OR (ratio_utme BETWEEN 0 AND 100 AND ratio_de BETWEEN 0 AND 100 AND ratio_utme + ratio_de = 100));
COMMENT ON COLUMN admissions.faculty_quota.ratio_utme IS
    'The faculty''s own UTME:Direct-Entry split, where it differs from the session''s '
    'default (session_policy.ratio_utme/ratio_de). NULL on both means the default applies. '
    'Education keeps 60:40 where every other faculty is 80:20.';

-- Education admits 60:40 UTME:DE; every other faculty inherits the session default
UPDATE admissions.faculty_quota SET ratio_utme = 60, ratio_de = 40 WHERE faculty_code = 'ED';

-- the ratio in force for a faculty: its own override, else the session's
CREATE OR REPLACE FUNCTION admissions.faculty_ratio(p_session text, p_faculty text)
RETURNS TABLE (ratio_utme int, ratio_de int)
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce(f.ratio_utme, p.ratio_utme), coalesce(f.ratio_de, p.ratio_de)
      FROM admissions.session_policy p
      LEFT JOIN admissions.faculty_quota f ON f.policy_id = p.id AND f.faculty_code = p_faculty
     WHERE p.session = p_session
     LIMIT 1;
$$;

-- ── 3. compulsory O'Level credits, with per-programme exceptions ───────────
CREATE TABLE admissions.olevel_compulsory (
    session text NOT NULL,
    subject text NOT NULL,
    pattern text NOT NULL,      -- a regex (embed (?i) for case-insensitive) matched against the sat subject
    ord     int  NOT NULL DEFAULT 0,
    PRIMARY KEY (session, subject)
);
COMMENT ON TABLE admissions.olevel_compulsory IS
    'The O''Level subjects a credit is compulsory in, per session. A session that '
    'states nothing falls back to English Language and Mathematics. A pass is not a '
    'credit and never satisfies one of these.';
SELECT audit.attach('admissions.olevel_compulsory');

CREATE TABLE admissions.programme_olevel_allowance (
    policy_id      uuid NOT NULL REFERENCES admissions.session_policy(id),
    programme_code text NOT NULL,
    subject        text NOT NULL,   -- a compulsory subject this programme waives / accepts a pass in
    PRIMARY KEY (policy_id, programme_code, subject)
);
COMMENT ON TABLE admissions.programme_olevel_allowance IS
    'A per-programme exception to the compulsory O''Level credit: the programme accepts '
    'a pass in the named subject (or waives it). For the few programmes whose own '
    'requirements differ from the University''s general rule.';
SELECT audit.attach('admissions.programme_olevel_allowance');

-- the compulsory set for a session: stated rows, else the English + Mathematics default
CREATE OR REPLACE FUNCTION admissions.olevel_compulsory_subjects(p_session text)
RETURNS TABLE (subject text, pattern text)
LANGUAGE sql
STABLE
AS $$
    SELECT c.subject, c.pattern FROM admissions.olevel_compulsory c WHERE c.session = p_session
    UNION ALL
    SELECT d.subject, d.pattern
      FROM (VALUES ('English Language', '(?i)english'), ('Mathematics', '(?i)^\s*math')) d(subject, pattern)
     WHERE NOT EXISTS (SELECT 1 FROM admissions.olevel_compulsory c WHERE c.session = p_session);
$$;

-- which compulsory subjects a candidate is missing a credit in for a programme
CREATE OR REPLACE FUNCTION admissions.olevel_compulsory_missing(p_session text, p_jamb_key text, p_programme text)
RETURNS text[]
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce(array_agg(cs.subject ORDER BY cs.subject), ARRAY[]::text[])
      FROM admissions.olevel_compulsory_subjects(p_session) cs
     WHERE NOT EXISTS (
               -- a credit (points >= 1; a pass is 0 and does not count) in a subject matching the pattern
               SELECT 1 FROM admissions.olevel_sitting st
                 JOIN admissions.olevel_grade gr ON gr.sitting_id = st.id
                WHERE st.session = p_session AND st.jamb_key = upper(btrim(p_jamb_key))
                  AND gr.subject ~ cs.pattern
                  AND admissions.olevel_points(p_session, gr.grade) >= 1)
       AND NOT EXISTS (
               -- unless this programme waives it
               SELECT 1 FROM admissions.programme_olevel_allowance a
                 JOIN admissions.session_policy p ON p.id = a.policy_id
                WHERE p.session = p_session AND a.programme_code = p_programme AND a.subject = cs.subject);
$$;

CREATE OR REPLACE FUNCTION admissions.olevel_meets_compulsory(p_session text, p_jamb_key text, p_programme text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT array_length(admissions.olevel_compulsory_missing(p_session, p_jamb_key, p_programme), 1) IS NULL;
$$;

-- ── the gate: an offer needs the compulsory credits, when O'Level is on record ──
CREATE OR REPLACE FUNCTION admissions.decide_application(p_app uuid, p_decision text, p_note text, p_basis text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE a admissions.application; c admissions.candidate; v_has boolean; v_missing text[];
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF a.decision_released_at IS NOT NULL THEN
        RAISE EXCEPTION 'the decision was released on % and stands', a.decision_released_at::date USING ERRCODE = '23514',
            HINT = 'A released decision is not quietly changed; the Board minutes a new one.';
    END IF;
    IF a.score_released_at IS NULL THEN
        RAISE EXCEPTION 'the screening score has not been released' USING ERRCODE = '23514', HINT = 'The Board decides on released scores.';
    END IF;
    IF p_decision = 'OFFERED' AND p_basis IS NULL THEN
        RAISE EXCEPTION 'an offer is made on a basis' USING ERRCODE = '23514',
            HINT = 'National Merit, State Merit, Equality of Local Government, Locality or Persons Living With Disability — it is what goes back to JAMB.';
    END IF;
    IF p_decision = 'OFFERED' THEN
        SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
        -- the rule applies to the O'Level on record: when a candidate has sittings but no
        -- credit in a compulsory subject, the offer is refused; when none is on record, the
        -- rule cannot be read and does not block (that is a data-completeness matter).
        SELECT EXISTS (SELECT 1 FROM admissions.olevel_sitting st
                        WHERE st.session = a.session AND st.jamb_key = c.jamb_key) INTO v_has;
        IF v_has THEN
            v_missing := admissions.olevel_compulsory_missing(a.session, c.jamb_key, c.programme);
            IF array_length(v_missing, 1) IS NOT NULL THEN
                RAISE EXCEPTION 'a compulsory O''Level credit is missing: %', array_to_string(v_missing, ', ')
                    USING ERRCODE = '23514',
                    HINT = 'Credit passes in English and Mathematics are compulsory for all programmes; a pass does not count. '
                           'If this programme admits on a pass in a subject, record that exception in the admission settings.';
            END IF;
        END IF;
    END IF;
    UPDATE admissions.application SET decision = p_decision, decision_note = p_note, decision_basis = p_basis, decided_at = now() WHERE id = p_app;
    RETURN p_decision;
END $$;

COMMIT;
