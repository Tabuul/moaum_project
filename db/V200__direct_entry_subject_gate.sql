-- ═══════════════════════════════════════════════════════════════════════════
-- V200 — Direct Entry subject gate, separate from UTME
--
--   Direct Entry candidates come in on a prior qualification — 'A' Level (IJMB,
--   JUPEB, Cambridge), NCE, ND or HND — and carry no CAPS aggregate and no CAPS
--   subjects. The UTME subject gate (V189/V192) reads the CAPS row and never sees
--   them; the merit pool sets DE aside entirely. So DE eligibility on subjects has
--   never been checkable.
--
--   This adds a SEPARATE DE gate that touches nothing on the UTME path:
--     • a 'DE' scope on rule_subject_group, so a programme's DE subject set is
--       stored structurally beside its UTME and O'Level sets (the de_text prose
--       stays as it was);
--     • a place to capture what a DE candidate actually offers — an award (the
--       basis) and its subjects and grades, entered by an officer from the
--       certificate at screening (hand-entered and audited, not derived);
--     • admissions.de_meets_combination(), the mirror of utme_meets_combination
--       one set higher: "at least N distinct of a set", slash-alternatives, and
--       Mathematics <> Further Mathematics — but English is NOT auto-satisfied
--       (it is not a compulsory 'A' Level), and the candidate's subjects are read
--       from the captured award, not from a CAPS row.
--
--   Lenient, like the UTME gate: no configured DE requirement → pass; no captured
--   DE subjects → pass (cannot check, so do not reject). It is screening-only —
--   the offer decision (decide_application) is untouched; the DE status is surfaced
--   on a screening list for the officer to act on.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1 · a 'DE' scope on the structured subject groups (additive) ────────────
ALTER TABLE admissions.rule_subject_group DROP CONSTRAINT ck_grp_scope;
ALTER TABLE admissions.rule_subject_group
    ADD CONSTRAINT ck_grp_scope CHECK (scope IN ('UTME', 'OLEVEL', 'DE'));

-- ── 2 · the DE candidate's prior qualification and its subjects ─────────────
-- One award per basis a candidate holds (a few hold two, e.g. NCE and an 'A'
-- Level). Unlike O'Level — which is read from the JAMB attachment and re-derived
-- at will — a DE award is read off a certificate by an officer, so it is entered
-- by hand and kept on the audit spine.
CREATE TABLE admissions.de_award (
    id           uuid PRIMARY KEY,
    session      text NOT NULL,
    jamb_key     text NOT NULL,
    basis        text NOT NULL,          -- A_LEVEL | IJMB | JUPEB | NCE | ND | HND
    awarded_year int  NULL,
    institution  text NULL,
    recorded_by  uuid NULL REFERENCES iam.person(id),
    recorded_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_de_basis CHECK (basis IN ('A_LEVEL', 'IJMB', 'JUPEB', 'NCE', 'ND', 'HND')),
    CONSTRAINT ck_de_year CHECK (awarded_year IS NULL OR awarded_year BETWEEN 1960 AND 2100),
    CONSTRAINT uq_de_award UNIQUE (session, jamb_key, basis)
);
CREATE INDEX ix_de_award_candidate ON admissions.de_award (session, jamb_key);

CREATE TABLE admissions.de_award_subject (
    id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    award_id uuid NOT NULL REFERENCES admissions.de_award(id) ON DELETE CASCADE,
    subject  text NOT NULL,              -- normalised on the screen before it was recorded
    grade    text NULL,                  -- 'A'..'E' for 'A' Level; Distinction/Credit/Merit for the diplomas
    CONSTRAINT uq_de_award_subject UNIQUE (award_id, subject)
);

SELECT audit.attach('admissions.de_award');
SELECT audit.attach('admissions.de_award_subject');

-- ── 3 · the gate ───────────────────────────────────────────────────────────
-- True when the candidate offers the programme's required DE subjects. Each DE
-- group is "at least `choose` distinct of a set"; a set member may be written
-- "X/Y" (or "X or Y") as alternatives. Mathematics <> Further Mathematics.
-- English is NOT auto-satisfied here. Lenient: no rule, or no captured subjects,
-- passes.
CREATE OR REPLACE FUNCTION admissions.de_meets_combination(p_session text, p_jamb_key text, p_programme text)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    WITH grp AS (
        SELECT g.id, g.choose
          FROM admissions.rule_subject_group g
         WHERE g.policy_id = (admissions.policy_in_force(p_session)).id
           AND g.programme_code = p_programme AND g.scope = 'DE'),
    cand AS (
        SELECT lower(btrim(s.subject)) AS subj
          FROM admissions.de_award a
          JOIN admissions.de_award_subject s ON s.award_id = a.id
         WHERE a.session = p_session AND a.jamb_key = upper(btrim(p_jamb_key))
           AND nullif(btrim(s.subject), '') IS NOT NULL),
    eval AS (
        SELECT g.id, g.choose,
               COUNT(DISTINCT m.opt) FILTER (WHERE EXISTS (
                   SELECT 1 FROM cand c
                    WHERE c.subj = m.opt
                       OR (m.opt LIKE 'math%' AND m.opt NOT LIKE 'further%'
                           AND c.subj LIKE 'math%' AND c.subj NOT LIKE 'further%'))
               ) AS have
          FROM grp g
          JOIN admissions.rule_subject rs ON rs.group_id = g.id
          CROSS JOIN LATERAL regexp_split_to_table(lower(btrim(rs.subject)), '\s*/\s*|\s+or\s+') AS m(opt)
         GROUP BY g.id, g.choose)
    SELECT CASE
        WHEN NOT EXISTS (SELECT 1 FROM grp)  THEN true   -- opt-in: no DE requirement configured → pass
        WHEN NOT EXISTS (SELECT 1 FROM cand) THEN true   -- no captured DE subjects → cannot check, do not reject
        ELSE NOT EXISTS (SELECT 1 FROM eval WHERE have < choose)  -- any group short of its count → violated
    END
$$;

COMMENT ON FUNCTION admissions.de_meets_combination(text, text, text) IS
  'True when the Direct Entry candidate offers the programme''s required DE subjects (rule_subject scope DE), '
  'or the programme has no DE requirement, or no DE subjects were captured. Each group needs `choose` distinct '
  'members of its set; "X/Y" members are alternatives; Mathematics <> Further Mathematics; English is not auto-met.';

-- ── 4 · the screening read ─────────────────────────────────────────────────
-- One row per submitted DE applicant to this programme, with the gate's verdict.
-- Screening-only: status is MET / SHORT / UNVERIFIED (no subjects captured yet) /
-- NO_RULE (the programme has no structured DE requirement).
CREATE OR REPLACE FUNCTION admissions.de_screening(p_session text, p_programme text)
RETURNS TABLE (app_id uuid, jamb_reg_no text, jamb_key text, surname text, other_names text,
               entry_level int, has_data boolean, meets_de boolean, status text)
LANGUAGE sql STABLE AS $$
    WITH has_rule AS (
        SELECT EXISTS (SELECT 1 FROM admissions.rule_subject_group g
                        WHERE g.policy_id = (admissions.policy_in_force(p_session)).id
                          AND g.programme_code = p_programme AND g.scope = 'DE') AS v)
    SELECT a.id AS app_id, c.jamb_reg_no, c.jamb_key, c.surname, c.other_names, c.entry_level,
           EXISTS (SELECT 1 FROM admissions.de_award d JOIN admissions.de_award_subject ds ON ds.award_id = d.id
                    WHERE d.session = p_session AND d.jamb_key = c.jamb_key) AS has_data,
           admissions.de_meets_combination(p_session, c.jamb_key, p_programme) AS meets_de,
           CASE
             WHEN NOT (SELECT v FROM has_rule) THEN 'NO_RULE'
             WHEN NOT EXISTS (SELECT 1 FROM admissions.de_award d JOIN admissions.de_award_subject ds ON ds.award_id = d.id
                               WHERE d.session = p_session AND d.jamb_key = c.jamb_key) THEN 'UNVERIFIED'
             WHEN admissions.de_meets_combination(p_session, c.jamb_key, p_programme) THEN 'MET'
             ELSE 'SHORT'
           END AS status
      FROM admissions.application a
      JOIN admissions.candidate c ON c.id = a.candidate_id
      JOIN admissions.caps_row_live x ON x.session = a.session AND x.jamb_reg_no = c.jamb_reg_no
     WHERE a.session = p_session
       AND (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) = p_programme
       AND a.submitted_at IS NOT NULL
       AND x.entry_mode = 'DIRECT_ENTRY'
     ORDER BY c.surname, c.other_names
$$;

COMMENT ON FUNCTION admissions.de_screening(text, text) IS
  'Per-programme Direct Entry screening: each submitted DE applicant with the DE subject gate''s verdict '
  '(MET / SHORT / UNVERIFIED / NO_RULE). Screening-only — it does not gate the offer decision.';

COMMIT;
