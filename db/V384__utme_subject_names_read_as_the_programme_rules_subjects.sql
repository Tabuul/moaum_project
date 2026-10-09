-- ═══════════════════════════════════════════════════════════════════════════
-- V384 — JAMB's subject names read as the programme rules' subjects
--
--   The 2026/2027 template for B.A. Theatre Arts put all 701 registered
--   applicants out on "Incorrect Combination: [Literature in English]",
--   though 684 of them sat it. JAMB's CAPS rows name the subject
--   "Lit. in English" (and "Christian Rel. Know", "Agriculture", "Art (Fine
--   Art)", "Computer Studies" …); the Office's rules name it "Literature in
--   English" ("Christian Religious Studies", "CRS/IRS", "Agricultural
--   Science", "Fine Arts" …), some with a full stop after the last subject.
--   The merit list's UTME gate (V192) compared the two as lower-cased text, so
--   a candidate who sat the subject was refused for not sitting it; the
--   template's remark compared them again, in Java, its own way; and the merit
--   list did not say which of its tests had failed, so the template could only
--   write "Not qualified on the merit list".
--
--   1 · admissions.subject_key(text): one name per subject. Lower case, '&'
--       as 'and', punctuation and full stops dropped, then the spellings of the
--       SAME subject brought to one name — Lit./Literature in English; Use of
--       English/English Language; Maths/Mathematics (Further Mathematics stays
--       apart); Christian Rel. Know/Knowledge, CRK, CRS, Christian Religious
--       Studies; Islamic Rel. Know, IRK, IRS, Islamic Studies; Agriculture,
--       Agric, Agricultural Science; Art (Fine Art), Fine Art(s); Computer
--       Studies/Science; Principles of Accounts, Accounting; and the short forms
--       Govt, Econs, Geog, Chem, Phy, Bio, Comm, Hist, T.D. It never makes one
--       subject stand for another: that is admissions.subject_equivalence,
--       stated by the Secretariat, and still honoured.
--   2 · admissions.subject_same (V266, the eligibility engine's matcher for
--       O'Level, UTME and Direct Entry) compares those keys, and a stated
--       equivalence by its keys too — so the engine's verdicts and suggestions
--       read the same subjects the merit list does.
--   3 · admissions.utme_subjects(session, jamb_key): the CAPS row's subjects;
--       admissions.utme_combination_check(session, jamb_key, programme): each
--       UTME rule item (the V192 grammar: "X", "X/Y", "N of A/B/C"; English
--       always counted) with what the candidate offers toward it and, when short,
--       what is missing in the rule's own words. utme_meets_combination and the
--       new utme_combination_missing both read it, so the gate and the
--       template's "Correct/Incorrect Combination" can no longer disagree. Still
--       lenient: no rule passes; no subjects on the CAPS row passes (missing is
--       then NULL, "not checked").
--   4 · admissions.merit_list also returns meets_utme (dropped and created: a
--       new output column). Its callers read columns by name.
--   5 · every policy's rules_version moves on: a verdict the eligibility engine
--       stored under the old matcher is re-read on the next opening.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V384: UTME subject names read as the programme rules'' subjects', true);

-- ── 1 · one name per subject ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.subject_key(p_subject text)
RETURNS text LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE s text; c text;
BEGIN
    -- lower case, '&' read as 'and', every run of punctuation and space one space, the ends trimmed
    s := btrim(regexp_replace(replace(lower(coalesce(p_subject, '')), '&', ' and '), '[^a-z0-9]+', ' ', 'g'));
    IF s = '' THEN RETURN NULL; END IF;
    c := replace(s, ' ', '');   -- the letters alone: "C.R.K." is crk
    RETURN CASE
        WHEN s ~ '^(lit|literature)\M' OR s ~ '^eng(lish)? lit(erature)?\M'                  THEN 'literature in english'
        WHEN s ~ '^(use of )?eng(lish)?\M'                                                     THEN 'english language'
        WHEN s ~ '^(further|f) math'                                                           THEN 'further mathematics'
        WHEN s ~ '^(general )?math(s|ematics)?\M'                                              THEN 'mathematics'
        WHEN s ~ '^christian\M' OR c IN ('crk', 'crs', 'cre')                                  THEN 'christian religious studies'
        WHEN s ~ '^islam(ic)?\M' OR c IN ('irk', 'irs', 'ire')                                 THEN 'islamic studies'
        WHEN s ~ '^agric(ulture|ultural)?( sc(i|ience)?)?$'                                    THEN 'agricultural science'
        WHEN s ~ '^((fine|visual) )?arts?( (fine|visual) arts?)?$'                             THEN 'fine art'
        WHEN s ~ '^computer( (studies|study|science|sci))?$'                                   THEN 'computer studies'
        WHEN s ~ '^(principles? of )?accounts?$' OR s ~ '^(financial )?accounting$' OR c = 'poa' THEN 'principles of accounts'
        WHEN s ~ '^gov(t|ernment)?$'                                                           THEN 'government'
        WHEN s ~ '^econ(s|omics)?$'                                                            THEN 'economics'
        WHEN s ~ '^geo(g|graphy)?$'                                                            THEN 'geography'
        WHEN s ~ '^chem(istry)?$'                                                              THEN 'chemistry'
        WHEN s ~ '^phy(s|sics)?$'                                                              THEN 'physics'
        WHEN s ~ '^bio(logy)?$'                                                                THEN 'biology'
        WHEN s ~ '^comm(erce)?$'                                                               THEN 'commerce'
        WHEN s ~ '^hist(ory)?$'                                                                THEN 'history'
        WHEN s ~ '^tech(nical)? draw(ing)?$' OR c = 'td'                                       THEN 'technical drawing'
        WHEN s ~ '^home econ(s|omics)?$'                                                       THEN 'home economics'
        ELSE s
    END;
END $$;

COMMENT ON FUNCTION admissions.subject_key(text) IS
  'One name per subject, whoever spelt it: JAMB/CAPS ("Lit. in English", "Christian Rel. Know", "Agriculture", "Art (Fine Art)"), '
  'WAEC/NECO or a rule ("Literature in English", "CRS", "Agricultural Science", "Fine Arts", "Technical Drawing."). '
  'NULL for an empty name. Spellings of one subject only: a substitute subject is admissions.subject_equivalence.';

-- ── 2 · the eligibility engine's matcher, on the keys ─────────────────────
/* does the candidate's subject satisfy the subject a rule names — the same subject however spelt (Mathematics is
   never Further Mathematics), or a substitute the session's settings state */
CREATE OR REPLACE FUNCTION admissions.subject_same(p_cand text, p_req text, p_policy uuid, p_scope text)
RETURNS boolean LANGUAGE sql STABLE AS $$
    WITH n AS (SELECT admissions.subject_key(p_cand) AS c, admissions.subject_key(p_req) AS r)
    SELECT CASE
        WHEN n.c IS NULL OR n.r IS NULL THEN false
        WHEN n.c = n.r THEN true
        WHEN EXISTS (SELECT 1 FROM admissions.subject_equivalence e
                      WHERE e.policy_id = p_policy AND admissions.subject_key(e.subject) = n.r AND admissions.subject_key(e.equivalent) = n.c
                        AND (e.scope = 'ANY' OR e.scope = p_scope)) THEN true
        ELSE false END
      FROM n;
$$;

-- ── 3 · the UTME combination, item by item ────────────────────────────────
/* the candidate's UTME subjects as JAMB wrote them on the live CAPS row (Subject1..4, either layout) */
CREATE OR REPLACE FUNCTION admissions.utme_subjects(p_session text, p_jamb_key text)
RETURNS TABLE (subject text)
LANGUAGE sql STABLE AS $$
    SELECT btrim(e.value)
      FROM admissions.caps_row_live x
      CROSS JOIN LATERAL jsonb_each_text(x.raw) AS e(key, value)
     WHERE x.session = p_session AND x.jamb_key = upper(btrim(p_jamb_key))
       AND regexp_replace(lower(btrim(e.key)), '[^a-z0-9]', '', 'g')
           IN ('subject1', 'subject2', 'subject3', 'subject4', 'subj1', 'subj2', 'subj3', 'subj4')
       AND admissions.subject_key(e.value) IS NOT NULL
$$;

/* each UTME rule item of the programme under the session's policy in force, with how many distinct subjects the
   candidate offers toward it and, when short, what is missing in the rule's words: "Literature in English",
   "CRS/IRS", "1 more of Christian Religious Studies/History". The grammar is V192's: an item is "at least K
   distinct of a slash-set" ("/" or "or"), a plain or "X/Y" item K = 1, "N of A/B/C" (word or digit) K = N; English
   is always offered. A member matches by admissions.subject_key, or by a stated UTME equivalence — the same rule
   as admissions.subject_same, read here as a set so a merit list of hundreds is one pass. */
CREATE OR REPLACE FUNCTION admissions.utme_combination_check(p_session text, p_jamb_key text, p_programme text)
RETURNS TABLE (item text, need int, have int, missing text)
LANGUAGE sql STABLE AS $$
    -- the policy in force, read without policy_in_force's refusal: with none in force nothing is required here
    WITH pol AS (SELECT p.id FROM admissions.session_policy p WHERE p.session = p_session AND p.state = 'IN_FORCE'),
    raw AS (
        SELECT DISTINCT btrim(rs.subject) AS item
          FROM admissions.rule_subject rs
          JOIN admissions.rule_subject_group g ON g.id = rs.group_id
         WHERE g.policy_id = (SELECT id FROM pol) AND g.programme_code = p_programme AND g.scope = 'UTME'
           AND btrim(rs.subject) <> ''),
    norm AS (
        -- number words to digits and the noise word "any" dropped, the rule's own capitals kept for the answer
        SELECT item,
               regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
                 item, '\many\M', ' ', 'gi'), '\mone\M', '1', 'gi'), '\mtwo\M', '2', 'gi'), '\mthree\M', '3', 'gi'), '\mfour\M', '4', 'gi'), '\mfive\M', '5', 'gi') AS s
          FROM raw),
    parsed AS (
        SELECT item,
               CASE WHEN s ~* '\m\d+\s*of\M' THEN ((regexp_match(s, '(\d+)\s*of\M', 'i'))[1])::int ELSE 1 END AS need,
               CASE WHEN s ~* '\m\d+\s*of\M' THEN btrim(regexp_replace(s, '^.*?\d+\s*of\M[:\s]*', '', 'i')) ELSE s END AS setstr
          FROM norm),
    member AS (
        SELECT p.item, p.need, m.ord, btrim(m.opt, ' .,;:') AS opt, admissions.subject_key(m.opt) AS k
          FROM parsed p
          CROSS JOIN LATERAL regexp_split_to_table(p.setstr, '\s*/\s*|\s+or\s+', 'i') WITH ORDINALITY AS m(opt, ord)
         WHERE admissions.subject_key(m.opt) IS NOT NULL),
    cand AS (SELECT DISTINCT admissions.subject_key(s.subject) AS k FROM admissions.utme_subjects(p_session, p_jamb_key) s),
    eq AS (
        SELECT admissions.subject_key(e.subject) AS req, admissions.subject_key(e.equivalent) AS alt
          FROM admissions.subject_equivalence e
         WHERE e.policy_id = (SELECT id FROM pol) AND e.scope IN ('ANY', 'UTME')),
    met AS (
        SELECT mb.*,
               (mb.k = 'english language'                                    -- English is always offered in UTME
                OR EXISTS (SELECT 1 FROM cand c
                            WHERE c.k = mb.k OR EXISTS (SELECT 1 FROM eq WHERE eq.req = mb.k AND eq.alt = c.k))) AS sat
          FROM member mb),
    counted AS (
        SELECT m.item, m.need, (count(DISTINCT m.k) FILTER (WHERE m.sat))::int AS have,
               string_agg(m.opt, '/' ORDER BY m.ord) AS every_opt,
               string_agg(m.opt, '/' ORDER BY m.ord) FILTER (WHERE NOT m.sat) AS unmet
          FROM met m
         GROUP BY m.item, m.need)
    SELECT c.item, c.need, c.have,
           CASE WHEN c.have >= c.need THEN NULL
                WHEN c.need = 1 THEN c.every_opt
                ELSE (c.need - c.have) || ' more of ' || coalesce(c.unmet, c.every_opt)
           END
      FROM counted c
     ORDER BY c.need > 1, c.item
$$;

COMMENT ON FUNCTION admissions.utme_combination_check(text, text, text) IS
  'The programme''s UTME rule items (policy in force) against the candidate''s CAPS subjects: per item the count needed, '
  'the distinct subjects offered toward it (by admissions.subject_key, or a stated UTME equivalence; English always), and '
  'what is missing in the rule''s words when short. Read by utme_meets_combination and utme_combination_missing.';

-- true when the candidate offers the programme's required UTME subjects (or none is required, or none is on record)
CREATE OR REPLACE FUNCTION admissions.utme_meets_combination(p_session text, p_jamb_key text, p_programme text)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN count(*) = 0 THEN true                                                                          -- no requirement configured → pass
        WHEN NOT EXISTS (SELECT 1 FROM admissions.utme_subjects(p_session, p_jamb_key)) THEN true          -- no subject data → do not reject on this ground
        ELSE bool_and(k.have >= k.need)                                                                     -- any item short of its count → violated
    END
      FROM admissions.utme_combination_check(p_session, p_jamb_key, p_programme) k
$$;

COMMENT ON FUNCTION admissions.utme_meets_combination(text, text, text) IS
  'True when the candidate offers the programme''s required UTME subjects, read item by item by '
  'admissions.utme_combination_check (subjects matched by admissions.subject_key or a stated equivalence; English always met; '
  'Mathematics <> Further Mathematics), or the programme has no requirement, or the CAPS row carries no subjects to check.';

/* the required UTME subjects the candidate did not sit, in the rule's words — the merit list's own reading.
   An empty array when the combination is met or none is required; NULL when there is a requirement but the CAPS
   row carries no subjects to check it against (the gate then passes the candidate). */
CREATE OR REPLACE FUNCTION admissions.utme_combination_missing(p_session text, p_jamb_key text, p_programme text)
RETURNS text[]
LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN count(*) = 0 THEN ARRAY[]::text[]                                                              -- no requirement configured
        WHEN NOT EXISTS (SELECT 1 FROM admissions.utme_subjects(p_session, p_jamb_key)) THEN NULL          -- nothing on record to check
        ELSE coalesce(array_agg(k.missing ORDER BY k.need > 1, k.item) FILTER (WHERE k.have < k.need), ARRAY[]::text[])
    END
      FROM admissions.utme_combination_check(p_session, p_jamb_key, p_programme) k
$$;

COMMENT ON FUNCTION admissions.utme_combination_missing(text, text, text) IS
  'The required UTME subjects the candidate did not sit, in the rule''s words ("Literature in English", "1 more of CRS/History"), '
  'as the merit list''s gate reads them: empty when met or none is required, NULL when the CAPS row has no subjects to check.';

-- ── 4 · the merit list says which test failed ─────────────────────────────
-- V189 verbatim, with meets_utme returned beside meets_cutoff and meets_compulsory
DROP FUNCTION admissions.merit_list(text, text);
CREATE FUNCTION admissions.merit_list(p_session text, p_programme text)
RETURNS TABLE (
    rank int, app_id uuid, jamb_reg_no text, surname text, other_names text,
    entry_mode text, utme int, putme numeric, aggregate numeric,
    state_of_origin text, lga text, meets_cutoff boolean, meets_compulsory boolean, meets_utme boolean,
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
           b.state_of_origin, b.lga, b.meets_cutoff, b.meets_comp, b.meets_utme, b.is_eligible, b.basis,
           (b.basis IS NOT NULL) AS proposed_offer
      FROM assigned b
     ORDER BY rank;
END $$;

COMMENT ON FUNCTION admissions.merit_list(text, text) IS
  'The merit list for a programme under the session''s policy in force: the submitted UTME pool ranked, each with the tests '
  'it is eligible on (meets_cutoff, meets_compulsory O''Level, meets_utme subject combination), the basis (NM, SM, ELG, '
  'LOCALITY) and the proposed offer that fills the UTME quota.';

-- ── 5 · verdicts stored under the old matcher are re-read ─────────────────
UPDATE admissions.session_policy SET rules_version = rules_version + 1;

COMMIT;
