-- ═══════════════════════════════════════════════════════════════════════════
-- V022 — programmes screened by examination, and the passport at any time
--
-- Two things the Academic Office asked for after the first walk-through:
--
--   · Some programmes sit the post-UTME examination. For those, the screening
--     component is the examination score alone; the O'Level grading (V020)
--     does not apply to them and their candidates are not scored on it. The
--     Office names those programmes per session, and the naming is an act
--     on the record.
--   · The passport photograph arrives whenever the applicant has one. It is
--     no longer a gate on submitting the application, and it may be replaced
--     after submission — it is the one document that is not part of what
--     the applicant declared.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE admissions.screening_exam_programme (
    session        text NOT NULL,
    programme_code text NOT NULL REFERENCES ref.programme(code),
    stated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (session, programme_code)
);
SELECT audit.attach('admissions.screening_exam_programme');

COMMENT ON TABLE admissions.screening_exam_programme IS
  'The programmes a session screens by the post-UTME examination. Their '
  'screening component is the examination score alone; the O''Level grading '
  'is not applied to them.';

-- whether a programme is screened by examination this session
CREATE OR REPLACE FUNCTION admissions.screened_by_exam(p_session text, p_programme text)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT p_programme IS NOT NULL AND EXISTS (
        SELECT 1 FROM admissions.screening_exam_programme e WHERE e.session = p_session AND e.programme_code = p_programme);
$$;

-- the screening component (V021), now with the examination programmes:
-- 'EXAM' for those, score present or not; else the CBT score if one was
-- entered, else the O'Level score under the session's grading, scaled.
CREATE OR REPLACE FUNCTION admissions.screening_component(p_app uuid)
RETURNS TABLE (screening numeric, source text, olevel_total int, olevel_ceiling int)
LANGUAGE sql STABLE AS $$
    WITH a AS (
        SELECT ap.screening_score, ap.session, c.jamb_key,
               (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) AS code
          FROM admissions.application ap JOIN admissions.candidate c ON c.id = ap.candidate_id WHERE ap.id = p_app),
    rule AS (SELECT r.* FROM a, admissions.olevel_rule(a.session) r),
    ceiling AS (
        SELECT (rule.subjects_counted * greatest(admissions.olevel_points(a.session, 'A1'), 1) + rule.bonus_one_sitting) AS top
          FROM a, rule),
    ol AS (SELECT s.total FROM a, admissions.olevel_score(a.session, a.jamb_key, a.code) s),
    ex AS (SELECT admissions.screened_by_exam(a.session, a.code) AS by_exam FROM a)
    SELECT CASE WHEN ex.by_exam THEN a.screening_score
                WHEN a.screening_score IS NOT NULL THEN a.screening_score
                WHEN ol.total > 0 THEN round((ol.total::numeric / ceiling.top) * 100, 2)
                ELSE NULL END,
           CASE WHEN ex.by_exam THEN 'EXAM'
                WHEN a.screening_score IS NOT NULL THEN 'CBT'
                WHEN ol.total > 0 THEN 'OLEVEL'
                ELSE 'NONE' END,
           CASE WHEN ex.by_exam THEN NULL ELSE ol.total END,
           ceiling.top
      FROM a, ol, ceiling, ex;
$$;

-- submitting (V021): four documents are needed; the passport comes whenever it comes
CREATE OR REPLACE FUNCTION admissions.submit_application(p_app uuid, p_ip text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE a admissions.application; missing text; rejected text;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF a.submitted_at IS NOT NULL THEN RETURN 'already submitted'; END IF;
    IF a.fee_confirmed_at IS NULL THEN
        RAISE EXCEPTION 'the form opens when the application fee is confirmed' USING ERRCODE = '23514',
            HINT = 'Pay against the reference this portal generated; the Bursary confirms it against the bank''s record.';
    END IF;
    IF a.next_of_kin IS NULL OR btrim(a.next_of_kin) = '' THEN
        RAISE EXCEPTION 'the next of kin is not given' USING ERRCODE = '23514', HINT = 'Name and phone number of your next of kin, under Biodata.';
    END IF;
    SELECT string_agg(k, ', ') INTO missing FROM unnest(ARRAY['OLEVEL_STATEMENT','BIRTH_CERT','LGA_ID','JAMB_SLIP']) k
     WHERE NOT EXISTS (SELECT 1 FROM admissions.application_document d WHERE d.application_id = p_app AND d.kind = k AND d.superseded_at IS NULL);
    IF missing IS NOT NULL THEN
        RAISE EXCEPTION 'documents not yet uploaded: %', missing USING ERRCODE = '23514', HINT = 'The four documents are uploaded before the application is submitted; the passport photograph can come at any time.';
    END IF;
    SELECT string_agg(d.kind, ', ') INTO rejected FROM admissions.application_document d
     WHERE d.application_id = p_app AND d.superseded_at IS NULL AND d.status = 'REJECTED' AND d.kind <> 'PASSPORT';
    IF rejected IS NOT NULL THEN
        RAISE EXCEPTION 'a document was rejected and not replaced: %', rejected USING ERRCODE = '23514', HINT = 'Upload a replacement that meets the stated requirement.';
    END IF;
    UPDATE admissions.application SET submitted_at = now(), declaration_ip = p_ip WHERE id = p_app;
    RETURN 'submitted';
END $$;

-- ── a programme with no rule is skipped, not a finding ──────────────────
-- The Academic Office asked that settings be put in force over the programmes
-- that carry a rule, without waiting for every programme to have one: a
-- programme with no rule admits nobody until Senate states one, which the
-- cut-off and the loading already enforce. The finding is therefore dropped
-- from the gate; the other four stand, word for word (V008).
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
$$;

COMMIT;
