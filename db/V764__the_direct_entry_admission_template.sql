-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V764 · The Direct Entry admission template — the list that goes back to JAMB, for Direct Entry
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's decisions of 14 November 2026: the Direct Entry template mirrors the UTME one (an admission summary, the merit
--  list, the other qualified cases, the non-qualified cases and a ranked sheet, per programme and for every programme); every
--  registered Direct Entry applicant of the programme is a row, qualified or not, a non-qualified case with its reason; and the
--  applicants are ranked by points from their qualification's grades — A-Level, IJMB and JUPEB first (A = 5, B = 4, C = 3, D = 2,
--  E = 1; a Cambridge A* counts as A), then ND, HND and NCE (Distinction 4, Upper Credit 3, Credit or Lower Credit 2, Merit or Pass 1;
--  a letter grade A–E read as for A-Level), the three best subjects of the qualification that counts summed, ties by name. A grade
--  written so that it cannot be read counts nothing and is named on the row (GRADES NOT READ), for the officer to correct.
--
--  Qualified: submitted, on JAMB's current Direct Entry list, the session's admission settings in force, the programme admitting,
--  a Direct Entry qualification captured with its subjects, those subjects meeting the programme's Direct Entry requirement where
--  one is set (admissions.de_meets_combination, V200), and the O'Level uploaded with a credit in each compulsory subject
--  (admissions.olevel_compulsory_missing). The Board's recorded decision places a row: OFFERED on the merit list, WAITING among the
--  other qualified, NOT_OFFERED among the non-qualified (its note, else the reasons); a qualified applicant with no decision yet is
--  among the other qualified, an unqualified one among the non-qualified with the reasons.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V764: the Direct Entry admission template', true);

-- ── the points of one subject grade of a Direct Entry qualification ──────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.de_grade_points(p_basis text, p_grade text)
RETURNS integer
LANGUAGE sql IMMUTABLE AS $$
    -- the grade read as written: its letters and signs without spaces (A, B+, A*), or its words without punctuation (UPPER CREDIT,
    -- CREDIT UPPER, U C, DIST); no grade 0; a grade that is none of these NULL — not read, for the officer to correct
    SELECT CASE
             WHEN x.compact IS NULL THEN 0
             WHEN x.compact ~ '^[A-E][*+-]?$' THEN 5 - (ascii(left(x.compact, 1)) - ascii('A'))   -- A 5 … E 1; A* counts as A
             WHEN x.words ~ '^DIST' THEN 4
             WHEN x.words ~ '^(UPPER CREDIT|CREDIT UPPER|U C|UC)( |$)' THEN 3
             WHEN x.words ~ '^(LOWER CREDIT|CREDIT LOWER|L C|LC|CREDIT)( |$)' THEN 2
             WHEN x.words ~ '^(MERIT|PASS)( |$)' THEN 1
             WHEN x.compact ~ '^[FUO]$' OR x.words ~ '^(FAIL|FAILED|ABS|ABSENT)( |$)' THEN 0   -- a fail (or absent) read as such
             ELSE NULL END
      FROM (SELECT nullif(regexp_replace(upper(coalesce(p_grade, '')), '\s+', '', 'g'), '') AS compact,
                   btrim(regexp_replace(upper(coalesce(p_grade, '')), '[^A-Z]+', ' ', 'g')) AS words) x
$$;
COMMENT ON FUNCTION admissions.de_grade_points(text, text) IS
    'V764: the points of one subject grade of a Direct Entry qualification — a letter grade A 5, B 4, C 3, D 2, E 1 (A* counts as A; A-Level, IJMB, JUPEB, and a diploma graded so); Distinction 4, Upper Credit 3, Credit or Lower Credit 2, Merit or Pass 1 (read whatever the punctuation: Upper-Credit, U/C, Dist., Credit (Upper)); a fail or absence (F, U, O, Fail, Absent) and no grade 0; a grade that is none of these NULL — not read.';

-- ── every registered Direct Entry applicant of a programme (or of all), ranked, qualified or not with the reasons ────────────────
CREATE FUNCTION admissions.de_template(p_session text, p_programme text DEFAULT NULL)
RETURNS TABLE (rank integer, app_id uuid, application_no text, jamb_reg_no text, jamb_key text, surname text, other_names text,
               sex text, state_of_origin text, lga text, programme text, programme_code text, entry_level integer,
               qualification text, institution text, awarded_year integer, subjects jsonb, other_qualifications text,
               points integer, points_group integer, unread_grades text, de_status text, olevel_uploaded boolean, olevel_missing text,
               english text, mathematics text, sittings integer,
               recorded_decision text, decision text, decision_basis text, decision_note text, released boolean,
               qualified boolean, reason text)
LANGUAGE sql STABLE AS $$
    WITH pol AS (
        SELECT p.id FROM admissions.session_policy p WHERE p.session = p_session AND p.state = 'IN_FORCE'),
    app AS (
        SELECT a.id, a.application_no, c.jamb_reg_no, c.jamb_key, c.surname, c.other_names, c.programme, c.entry_level,
               coalesce(r.sex, c.sex) AS sex, r.state_of_origin, r.lga, a.submitted_at,
               (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) AS code,
               (SELECT x.entry_mode FROM admissions.caps_row_live x WHERE x.session = a.session AND x.jamb_reg_no = c.jamb_reg_no
                 ORDER BY (x.entry_mode = 'DIRECT_ENTRY') DESC LIMIT 1) AS live_mode,
               a.decision, a.decision_basis, a.decision_note, a.decision_released_at IS NOT NULL AS released
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE a.session = p_session AND c.entry_mode = 'DIRECT_ENTRY' AND (p_programme IS NULL OR c.programme = p_programme)),
    scored AS MATERIALIZED (
        -- each subject of the listed applicants' qualifications, its grade read once, ordered best first (a blank subject is none)
        SELECT d.id AS award_id, y.subject, y.grade, z.p,
               row_number() OVER (PARTITION BY d.id ORDER BY z.p DESC NULLS LAST, y.subject) AS n
          FROM admissions.de_award d
          JOIN admissions.de_award_subject y ON y.award_id = d.id AND nullif(btrim(y.subject), '') IS NOT NULL
          CROSS JOIN LATERAL (SELECT admissions.de_grade_points(d.basis, y.grade) AS p) z
         WHERE d.session = p_session AND d.jamb_key IN (SELECT app.jamb_key FROM app)),
    award AS MATERIALIZED (
        -- each qualification captured with a subject: its subjects best first, the points of its three best, the grades not read
        SELECT d.jamb_key, d.id, d.basis, d.institution, d.awarded_year,
               CASE WHEN d.basis IN ('A_LEVEL', 'IJMB', 'JUPEB') THEN 1 ELSE 2 END AS grp,
               jsonb_agg(jsonb_build_object('subject', sc.subject, 'grade', sc.grade, 'points', sc.p) ORDER BY sc.n) AS subj,
               (coalesce(sum(sc.p) FILTER (WHERE sc.n <= 3), 0))::int AS pts,
               string_agg(sc.subject || ' ' || sc.grade, ', ' ORDER BY sc.subject)
                   FILTER (WHERE sc.p IS NULL AND nullif(btrim(sc.grade), '') IS NOT NULL) AS unread
          FROM admissions.de_award d JOIN scored sc ON sc.award_id = d.id
         GROUP BY d.jamb_key, d.id, d.basis, d.institution, d.awarded_year),
    best AS (
        -- the qualification that counts: the A-Level group's best, else the diplomas' best
        SELECT DISTINCT ON (w.jamb_key) w.* FROM award w ORDER BY w.jamb_key, w.grp, w.pts DESC, w.basis),
    olev AS (
        -- the best grade of English Language and of Mathematics on the O'Level sittings uploaded
        SELECT st.jamb_key,
               (array_agg(g.grade ORDER BY admissions.olevel_points(p_session, g.grade) DESC, g.grade)
                    FILTER (WHERE g.subject ~* '^english'))[1] AS english,
               (array_agg(g.grade ORDER BY admissions.olevel_points(p_session, g.grade) DESC, g.grade)
                    FILTER (WHERE g.subject ~* '^math' AND g.subject !~* 'further'))[1] AS mathematics
          FROM admissions.olevel_sitting st JOIN admissions.olevel_grade g ON g.sitting_id = st.id
         WHERE st.session = p_session AND st.jamb_key IN (SELECT app.jamb_key FROM app)
         GROUP BY st.jamb_key),
    judged AS MATERIALIZED (
        SELECT app.*, b.basis, b.institution, b.awarded_year, b.subj, b.pts, b.grp, b.unread,
               -- the grades not read on every qualification captured, each by its qualification (one that does not count may be
               -- the one a misread grade kept from counting)
               (SELECT string_agg(CASE o.basis WHEN 'A_LEVEL' THEN 'A-Level' ELSE o.basis END || ': ' || o.unread, '; ' ORDER BY o.grp, o.pts DESC, o.basis)
                  FROM award o WHERE o.jamb_key = app.jamb_key AND o.unread IS NOT NULL) AS unread_all,
               (SELECT string_agg(CASE o.basis WHEN 'A_LEVEL' THEN 'A-Level' ELSE o.basis END || coalesce(' ' || o.awarded_year, '') || ' ('
                                  || (SELECT string_agg(e->>'subject' || coalesce(' ' || (e->>'grade'), ''), ', ') FROM jsonb_array_elements(o.subj) e) || ')',
                                  '; ' ORDER BY o.grp, o.pts DESC, o.basis)
                  FROM award o WHERE o.jamb_key = app.jamb_key AND o.id IS DISTINCT FROM b.id) AS others,
               EXISTS (SELECT 1 FROM pol) AS in_force,
               EXISTS (SELECT 1 FROM admissions.rule_subject_group g JOIN pol ON pol.id = g.policy_id
                        WHERE g.programme_code = app.code AND g.scope = 'DE') AS has_rule,
               admissions.programme_is_closed(p_session, app.code) AS closed,
               EXISTS (SELECT 1 FROM admissions.olevel_sitting st WHERE st.session = p_session AND st.jamb_key = app.jamb_key) AS ol_uploaded,
               array_to_string(admissions.olevel_compulsory_missing(p_session, app.jamb_key, app.code), ', ') AS ol_missing,
               admissions.olevel_sittings(p_session, app.jamb_key) AS ol_sittings,
               ol.english, ol.mathematics
          FROM app
          LEFT JOIN best b ON b.jamb_key = app.jamb_key
          LEFT JOIN olev ol ON ol.jamb_key = app.jamb_key),
    status AS MATERIALIZED (
        SELECT j.*,
               CASE WHEN j.basis IS NULL THEN 'UNVERIFIED'
                    WHEN NOT j.has_rule THEN 'NO_RULE'
                    WHEN admissions.de_meets_combination(p_session, j.jamb_key, j.code) THEN 'MET'
                    ELSE 'SHORT' END AS de_st
          FROM judged j),
    reasoned AS MATERIALIZED (
        SELECT s.*,
               nullif(concat_ws('; ',
                   CASE WHEN s.submitted_at IS NULL THEN 'Application not submitted' END,
                   CASE WHEN s.code IS NULL THEN 'Programme not on the University''s list of programmes' END,
                   CASE WHEN s.live_mode IS NULL THEN 'Not on JAMB''s current list for the session'
                        WHEN s.live_mode <> 'DIRECT_ENTRY' THEN 'On JAMB''s list as ' || s.live_mode END,
                   CASE WHEN NOT s.in_force THEN 'No admission settings in force for the session' END,
                   CASE WHEN s.closed THEN 'Programme not admitting this session' END,
                   CASE WHEN s.basis IS NULL THEN 'Direct Entry qualification not captured' END,
                   CASE WHEN s.de_st = 'SHORT' THEN 'Direct Entry subjects short of the programme''s requirement' END,
                   CASE WHEN NOT s.ol_uploaded THEN 'O''Level result not uploaded'
                        WHEN s.ol_missing <> '' THEN 'No O''Level credit in ' || s.ol_missing END), '') AS why
          FROM status s)
    SELECT (row_number() OVER (PARTITION BY r.programme
                               ORDER BY (r.basis IS NULL), r.grp, r.pts DESC NULLS LAST, r.surname, r.other_names, r.jamb_reg_no))::int,
           r.id, r.application_no, r.jamb_reg_no, r.jamb_key, r.surname, r.other_names, r.sex, r.state_of_origin, r.lga,
           r.programme, r.code, r.entry_level,
           r.basis, r.institution, r.awarded_year, coalesce(r.subj, '[]'::jsonb), r.others,
           r.pts, r.grp, r.unread_all, r.de_st, r.ol_uploaded, nullif(r.ol_missing, ''), r.english, r.mathematics, r.ol_sittings,
           r.decision,
           CASE WHEN r.decision IN ('OFFERED', 'WAITING', 'NOT_OFFERED') THEN r.decision
                WHEN r.why IS NULL THEN 'WAITING'
                ELSE 'NOT_OFFERED' END,
           r.decision_basis,
           CASE WHEN r.decision = 'NOT_OFFERED' THEN coalesce(nullif(btrim(r.decision_note), ''), r.why, 'Not recommended')
                WHEN r.decision IS NULL AND r.why IS NULL THEN 'Qualified: no decision recorded yet'
                WHEN r.decision IS NULL THEN r.why
                ELSE nullif(btrim(r.decision_note), '') END,
           r.released, r.why IS NULL, r.why
      FROM reasoned r
     ORDER BY r.programme, 1
$$;
COMMENT ON FUNCTION admissions.de_template(text, text) IS
    'V764: the rows of the Direct Entry admission template for a programme (by name; NULL for every programme): every registered Direct Entry applicant, ranked within the programme by the points of the qualification that counts (the A-Level group before the diplomas, the three best subjects summed, admissions.de_grade_points; ties by name; no qualification captured last), with the qualification, its subjects and grades, the grades not read, the other qualifications, the Direct Entry requirement''s verdict (NO_RULE, UNVERIFIED, MET, SHORT), the O''Level English and Mathematics and compulsory credits, whether qualified and the reasons if not, the recorded decision and the template''s (OFFERED merit list, WAITING other qualified, NOT_OFFERED non-qualified).';

COMMIT;
