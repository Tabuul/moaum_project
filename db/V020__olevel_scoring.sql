-- ═══════════════════════════════════════════════════════════════════════════
-- V020 — the O'Level results JAMB sends, and the screening score they carry
--
-- JAMB uploads each candidate's O'Level results (WAEC, NECO, NABTEB), one
-- or two sittings, as one spreadsheet row per subject. The Academic Office
-- stated the rule the screening applies to them:
--
--   · a grade is worth points — A1 6, B2 5, B3 4, C4 3, C5 2, C6 1, and
--     D7, E8 and F9 nothing;
--   · the five subjects most relevant to the programme count, and where a
--     candidate sat twice the better grade in each subject is the one that
--     counts;
--   · a candidate who sat once gets a bonus of 10, a candidate who combined
--     two sittings a bonus of 6.
--
-- Those numbers are settings, stated per session by the Academic Office
-- and recorded against it, never constants in code. The sittings are kept
-- as JAMB sent them, one row per subject per sitting, derived from the
-- attachment that carried them and re-derivable from it at any time. The
-- score is computed, never stored, so it always reflects the settings and
-- the rule of the day.
--
-- The applicant sees their results as JAMB sent them; the score is the
-- Academic Office's. That is enforced at the API, and this file gives the
-- API two separate things to read: the sittings, and the score.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── the grading, per session ────────────────────────────────────────────
CREATE TABLE admissions.olevel_grading (
    session            text PRIMARY KEY,
    subjects_counted   int  NOT NULL DEFAULT 5,
    bonus_one_sitting  int  NOT NULL DEFAULT 10,
    bonus_two_sittings int  NOT NULL DEFAULT 6,
    stated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_olg_counted CHECK (subjects_counted BETWEEN 1 AND 9),
    CONSTRAINT ck_olg_bonus   CHECK (bonus_one_sitting BETWEEN 0 AND 100 AND bonus_two_sittings BETWEEN 0 AND 100)
);

CREATE TABLE admissions.olevel_grade_point (
    session text NOT NULL REFERENCES admissions.olevel_grading(session),
    grade   text NOT NULL,
    points  int  NOT NULL,
    PRIMARY KEY (session, grade),
    CONSTRAINT ck_olgp_grade  CHECK (grade IN ('A1','B2','B3','C4','C5','C6','D7','E8','F9')),
    CONSTRAINT ck_olgp_points CHECK (points BETWEEN 0 AND 20)
);

COMMENT ON TABLE admissions.olevel_grading IS
  'The Academic Office''s rule for turning O''Level grades into a screening '
  'score, per session: how many subjects count and the bonus for one or two '
  'sittings. The points per grade sit beside it. A session that has stated '
  'nothing is read under the defaults the Office gave when the rule was first '
  'written down (A1 6 … C6 1, D7 to F9 nothing; 5 subjects; 10 and 6).';

SELECT audit.attach('admissions.olevel_grading');
SELECT audit.attach('admissions.olevel_grade_point');

-- what a grade is worth this session: the session's own table, else the defaults
CREATE OR REPLACE FUNCTION admissions.olevel_points(p_session text, p_grade text)
RETURNS int
LANGUAGE sql
STABLE
AS $$
    SELECT CASE
             WHEN EXISTS (SELECT 1 FROM admissions.olevel_grading g WHERE g.session = p_session)
               THEN coalesce((SELECT gp.points FROM admissions.olevel_grade_point gp
                               WHERE gp.session = p_session AND gp.grade = upper(btrim(p_grade))), 0)
             ELSE CASE upper(btrim(p_grade))
                    WHEN 'A1' THEN 6 WHEN 'B2' THEN 5 WHEN 'B3' THEN 4
                    WHEN 'C4' THEN 3 WHEN 'C5' THEN 2 WHEN 'C6' THEN 1
                    ELSE 0 END
           END;
$$;

-- the session's rule, stated or default, in one row
CREATE OR REPLACE FUNCTION admissions.olevel_rule(p_session text)
RETURNS TABLE (stated boolean, subjects_counted int, bonus_one_sitting int, bonus_two_sittings int)
LANGUAGE sql
STABLE
AS $$
    SELECT true, g.subjects_counted, g.bonus_one_sitting, g.bonus_two_sittings
      FROM admissions.olevel_grading g WHERE g.session = p_session
    UNION ALL
    SELECT false, 5, 10, 6
     WHERE NOT EXISTS (SELECT 1 FROM admissions.olevel_grading g WHERE g.session = p_session);
$$;

-- ── the sittings, as JAMB sent them ─────────────────────────────────────
CREATE TABLE admissions.olevel_sitting (
    id            uuid PRIMARY KEY,
    attachment_id uuid NOT NULL REFERENCES admissions.attachment(id),
    session       text NOT NULL,
    jamb_key      text NOT NULL,
    exam_body     text NOT NULL,        -- WAEC | NECO | NABTEB | OTHER, read from JAMB's ExamType
    exam_type_raw text NULL,            -- JAMB's words, exactly
    exam_year     text NULL,
    exam_number   text NULL,            -- what the result is verified against
    ord           int  NOT NULL DEFAULT 1,
    CONSTRAINT ck_ols_body CHECK (exam_body IN ('WAEC','NECO','NABTEB','OTHER')),
    CONSTRAINT uq_ols_per_attachment UNIQUE (attachment_id, ord)
);
CREATE INDEX ix_ols_candidate ON admissions.olevel_sitting (session, jamb_key);

CREATE TABLE admissions.olevel_grade (
    sitting_id  uuid NOT NULL REFERENCES admissions.olevel_sitting(id),
    subject     text NOT NULL,          -- normalised on the screen before it was recorded
    grade       text NOT NULL,          -- as JAMB sent it; a grade the table does not price is worth nothing
    raw_subject text NULL,
    PRIMARY KEY (sitting_id, subject)
);

SELECT audit.exempt('admissions.olevel_sitting',
    'Derived from admissions.attachment, which holds the file as it arrived; re-derived from it at any time, never edited by hand.');
SELECT audit.exempt('admissions.olevel_grade',
    'Derived from admissions.attachment, which holds the file as it arrived; re-derived from it at any time, never edited by hand.');

-- JAMB's ExamType, read as the examining body
CREATE OR REPLACE FUNCTION admissions.exam_body(p_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
             WHEN upper(coalesce(p_type, '')) LIKE '%NECO%'   THEN 'NECO'
             WHEN upper(coalesce(p_type, '')) LIKE '%NABTEB%' THEN 'NABTEB'
             WHEN upper(coalesce(p_type, '')) LIKE '%WAEC%'
               OR upper(coalesce(p_type, '')) LIKE '%WASSCE%'
               OR upper(coalesce(p_type, '')) LIKE '%WASC%'   THEN 'WAEC'
             ELSE 'OTHER'
           END;
$$;

-- The sittings an attachment carries, derived from its payload. Two shapes
-- arrive: the one the screen records now — {sittings: [{type, year,
-- examNumber, subjects: [{subject, grade, raw}]}]} — and the earlier one,
-- one sitting flattened into {type, year, examNumber, subjects}. Both are
-- read; running it again reads the same file again and lands on the same rows.
CREATE OR REPLACE FUNCTION admissions.olevel_from_attachment(p_attachment uuid)
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
    a admissions.attachment;
    sittings jsonb;
    s jsonb;
    sub jsonb;
    v_sitting uuid;
    v_ord int := 0;
BEGIN
    SELECT * INTO a FROM admissions.attachment WHERE id = p_attachment;
    IF NOT FOUND OR a.kind <> 'OLEVEL' OR a.jamb_key IS NULL THEN
        RETURN 0;
    END IF;
    DELETE FROM admissions.olevel_grade g USING admissions.olevel_sitting st
     WHERE g.sitting_id = st.id AND st.attachment_id = p_attachment;
    DELETE FROM admissions.olevel_sitting WHERE attachment_id = p_attachment;

    IF jsonb_typeof(a.payload -> 'sittings') = 'array' THEN
        sittings := a.payload -> 'sittings';
    ELSE
        sittings := jsonb_build_array(a.payload);
    END IF;

    FOR s IN SELECT * FROM jsonb_array_elements(sittings) LOOP
        v_ord := v_ord + 1;
        v_sitting := gen_random_uuid();
        INSERT INTO admissions.olevel_sitting (id, attachment_id, session, jamb_key, exam_body, exam_type_raw, exam_year, exam_number, ord)
        VALUES (v_sitting, a.id, a.session, a.jamb_key, admissions.exam_body(s ->> 'type'),
                nullif(btrim(s ->> 'type'), ''), nullif(btrim(s ->> 'year'), ''), nullif(btrim(s ->> 'examNumber'), ''), v_ord);
        FOR sub IN SELECT * FROM jsonb_array_elements(coalesce(s -> 'subjects', '[]'::jsonb)) LOOP
            IF nullif(btrim(sub ->> 'subject'), '') IS NOT NULL THEN
                INSERT INTO admissions.olevel_grade AS og (sitting_id, subject, grade, raw_subject)
                VALUES (v_sitting, btrim(sub ->> 'subject'), upper(btrim(coalesce(sub ->> 'grade', ''))), sub ->> 'raw')
                ON CONFLICT (sitting_id, subject) DO UPDATE
                    SET grade = CASE WHEN admissions.olevel_points(a.session, EXCLUDED.grade)
                                          > admissions.olevel_points(a.session, og.grade)
                                     THEN EXCLUDED.grade ELSE og.grade END;
            END IF;
        END LOOP;
    END LOOP;
    RETURN v_ord;
END $$;

-- ── the score ───────────────────────────────────────────────────────────
-- The best grade per subject across the candidate's sittings, priced under
-- the session's table; the programme's relevant O'Level subjects where the
-- rule names them (admissions.rule_subject, scope OLEVEL), else every
-- subject sat; the top N of those; and the bonus for how many sittings it
-- took. relevant_known says whether the programme's subjects were stated —
-- a score over "every subject" is a provisional one, and the screen says so.
CREATE OR REPLACE FUNCTION admissions.olevel_score(p_session text, p_jamb_key text, p_programme text)
RETURNS TABLE (sittings int, relevant_known boolean, counted jsonb, points int, bonus int, total int)
LANGUAGE sql
STABLE
AS $$
    WITH rule AS (SELECT * FROM admissions.olevel_rule(p_session)),
    relevant AS (
        SELECT DISTINCT rs.subject
          FROM admissions.rule_subject rs
          JOIN admissions.rule_subject_group g ON g.id = rs.group_id AND g.scope = 'OLEVEL'
          JOIN admissions.session_policy p ON p.id = g.policy_id
         WHERE p.session = p_session AND g.programme_code = p_programme
    ),
    sat AS (
        SELECT st.id AS sitting_id, gr.subject, gr.grade, admissions.olevel_points(p_session, gr.grade) AS pts
          FROM admissions.olevel_sitting st
          JOIN admissions.olevel_grade gr ON gr.sitting_id = st.id
         WHERE st.session = p_session AND st.jamb_key = upper(btrim(p_jamb_key))
    ),
    best AS (
        SELECT s.subject, max(s.pts) AS pts,
               (array_agg(s.grade ORDER BY s.pts DESC, s.grade))[1] AS grade
          FROM sat s
         WHERE NOT EXISTS (SELECT 1 FROM relevant) OR s.subject IN (SELECT subject FROM relevant)
         GROUP BY s.subject
    ),
    top AS (
        SELECT b.subject, b.grade, b.pts
          FROM best b, rule r
         ORDER BY b.pts DESC, b.subject
         LIMIT (SELECT r.subjects_counted FROM rule r)
    ),
    n AS (SELECT count(DISTINCT sitting_id)::int AS sittings FROM sat)
    SELECT n.sittings,
           EXISTS (SELECT 1 FROM relevant) AS relevant_known,
           coalesce((SELECT jsonb_agg(jsonb_build_object('subject', t.subject, 'grade', t.grade, 'points', t.pts)
                                       ORDER BY t.pts DESC, t.subject) FROM top t), '[]'::jsonb) AS counted,
           coalesce((SELECT sum(t.pts) FROM top t), 0)::int AS points,
           CASE WHEN n.sittings = 0 THEN 0
                WHEN n.sittings = 1 THEN r.bonus_one_sitting
                ELSE r.bonus_two_sittings END AS bonus,
           (coalesce((SELECT sum(t.pts) FROM top t), 0)
              + CASE WHEN n.sittings = 0 THEN 0
                     WHEN n.sittings = 1 THEN r.bonus_one_sitting
                     ELSE r.bonus_two_sittings END)::int AS total
      FROM n, rule r;
$$;

COMMENT ON FUNCTION admissions.olevel_score(text, text, text) IS
  'The O''Level component of the screening score, computed under the '
  'session''s grading and the programme''s relevant subjects. Never stored; '
  'the Academic Office''s to see, and not the applicant''s.';

-- ── the results already recorded, read into sittings ────────────────────
DO $backfill$
DECLARE r record; n int := 0;
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM set_config('moaum.reason', 'O''Level results already recorded, read into sittings (V020)', true);
    FOR r IN SELECT id FROM admissions.attachment WHERE kind = 'OLEVEL' AND jamb_key IS NOT NULL LOOP
        n := n + admissions.olevel_from_attachment(r.id);
    END LOOP;
    RAISE NOTICE 'V020: % O''Level sittings read from the results already recorded', n;
END $backfill$;

COMMIT;
