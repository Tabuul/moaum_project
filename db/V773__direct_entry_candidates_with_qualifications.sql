-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V773 · Direct Entry candidates with their qualifications
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The user's decisions of 15 November 2026, on the University's two workbooks of Direct Entry candidates (Pharmacy's and Law's:
--  everyone on JAMB's Direct Entry list for the programme, the qualification read off CAPS's grade window, its points, a weighted
--  score, a Preliminary Fit and the O'Level held), "use this templates for DE admission templates", for every programme:
--    1. Upload and download. Direct Entry Screening reads a workbook in that layout and records every candidate's qualification at
--       once (admissions.de_upload_record: a preview that decides without writing, and the commit; a qualification typed by hand is
--       kept unless the file carries the same kind; the same file twice changes nothing); a new download, Direct Entry candidates
--       with qualifications, writes it (admissions.de_candidates). V764's return to JAMB stays.
--    2. Ranking by the workbook's rule everywhere: every qualification together, by its points as a percentage of its own maximum
--       (A-Level, IJMB and JUPEB the three subjects A 5 … E 1 plus 1 when none is a fail, of 16; a degree of 5; HND of 5; ND of 4;
--       University Diploma of 4; NCE three subjects of 15 — admissions.de_grade_points, admissions.de_award_scores), highest first,
--       ties by name — in the new sheet and in V764's admissions.de_template, which no longer puts the A-Level group first.
--    3. A Preliminary Fit per programme, held on the session's admission settings (admissions.de_fit_rule): the University's default
--       for every programme, a programme's own rule replacing it whole; a guide for the Admissions Committee that never changes the
--       rank, the qualified test or the decision (admissions.de_fit_of reads no table and nothing reads it but the sheet).
--    4. The rows are everyone on JAMB's live Direct Entry list for the programme (caps_row_live, by JAMB's code read through the
--       programme aliases), registered on the portal or not, with a column saying which.
--    5. Every Direct Entry programme: one workbook each or all of them, the default fit rule for every programme, each programme's
--       O'Level block its own O'Level subjects.
--  A degree, a University Diploma, an ND and an HND are held as a discipline and a class (no subject rows), so neither the Direct
--  Entry subject gate (V200) nor the eligibility engine (V268) reads a degree's name as an A-Level subject; both now count such an
--  award as captured. What CAPS's own columns said of a candidate (Qualification, Grade, Has 5 Credits?, IsCleared, Status, Age,
--  Age Qualified?, Admission Category) is kept as the last upload read it (admissions.de_caps_value).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V773: Direct Entry candidates with their qualifications', true);

-- ── 1 · the uploads: one row per committed upload that changed something ────────────────────────────────────────────────────────
CREATE TABLE admissions.de_upload (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session         text NOT NULL,
    filename        text NULL CHECK (filename IS NULL OR char_length(filename) <= 255),
    file_sha256     bytea NULL CHECK (file_sha256 IS NULL OR octet_length(file_sha256) = 32),
    programme_code  text NULL,            -- the programme chosen on Direct Entry Screening when it was uploaded (none: any); no key, history
    rows_read       integer NOT NULL CHECK (rows_read >= 0),
    rows_recorded   integer NOT NULL CHECK (rows_recorded >= 0),
    rows_unchanged  integer NOT NULL CHECK (rows_unchanged >= 0),
    rows_skipped    integer NOT NULL CHECK (rows_skipped >= 0),
    rows_repeated   integer NOT NULL DEFAULT 0 CHECK (rows_repeated >= 0),   -- identical repeats of an earlier line (outcome REPEATED)
    uploaded_by     uuid NOT NULL,        -- no key onto iam.person (check.sql's cleanup deletes people)
    uploaded_office text NOT NULL CHECK (uploaded_office IN ('academic', 'registrar')),
    uploaded_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_de_upload_session ON admissions.de_upload (session, uploaded_at DESC);
SELECT audit.attach('admissions.de_upload');
COMMENT ON TABLE admissions.de_upload IS
  'V773: a workbook of Direct Entry candidates'' qualifications uploaded on Direct Entry Screening and committed — who loaded which file, for which programme, and how many of its lines were recorded, unchanged, skipped or repeated. Written only when the upload changed something; the awards and CAPS values it recorded point at it.';

-- ── 2 · the qualification: a degree or diploma by its discipline and class, a subject repeated where the award repeats it ───────
ALTER TABLE admissions.de_award DROP CONSTRAINT ck_de_basis;
ALTER TABLE admissions.de_award ADD CONSTRAINT ck_de_basis CHECK (basis IN
    ('A_LEVEL','IJMB','JUPEB','NCE','ND','HND','DEGREE','DEGREE_FOREIGN','UNIVERSITY_DIPLOMA','NOT_STATED','NOT_AVAILABLE'));
ALTER TABLE admissions.de_award
    ADD COLUMN discipline  text NULL CONSTRAINT ck_de_award_discipline CHECK (discipline IS NULL OR char_length(discipline) <= 200),
    ADD COLUMN award_class text NULL CONSTRAINT ck_de_award_class CHECK (award_class IS NULL OR char_length(award_class) <= 60),
    ADD COLUMN exam_no     text NULL CONSTRAINT ck_de_award_exam_no CHECK (exam_no IS NULL OR char_length(exam_no) <= 60),
    ADD COLUMN source      text NOT NULL DEFAULT 'MANUAL' CONSTRAINT ck_de_award_source CHECK (source IN ('MANUAL', 'UPLOAD')),
    ADD COLUMN upload_id   uuid NULL REFERENCES admissions.de_upload(id);
ALTER TABLE admissions.de_award ADD CONSTRAINT ck_de_award_upload CHECK ((source = 'UPLOAD') = (upload_id IS NOT NULL));
ALTER TABLE admissions.de_award_subject ADD COLUMN ord smallint NULL CONSTRAINT ck_de_award_subject_ord CHECK (ord IS NULL OR ord BETWEEN 1 AND 20);
-- a subject may repeat within an award (an NCE double major: "English: Merit; English: Merit; Education: Merit" is 9 of 15):
-- V200's one-row-per-subject rule kept only for the rows without a place (typed before V773)
ALTER TABLE admissions.de_award_subject DROP CONSTRAINT uq_de_award_subject;
CREATE UNIQUE INDEX uq_de_award_subject_ord ON admissions.de_award_subject (award_id, ord) WHERE ord IS NOT NULL;
CREATE UNIQUE INDEX uq_de_award_subject ON admissions.de_award_subject (award_id, subject) WHERE ord IS NULL;
-- V266's eligibility_touched marks a candidate's runs stale on every de_award / de_award_subject / O'Level write by
-- (session, jamb_key): without this index each firing walks the session's current runs (1.9–5 ms on the copy)
CREATE INDEX ix_elrun_key ON admissions.eligibility_run (session, jamb_key) WHERE superseded_at IS NULL;

COMMENT ON COLUMN admissions.de_award.basis IS
  'V773: the kind of qualification — A_LEVEL, IJMB, JUPEB, NCE, ND, HND; DEGREE (a first degree of a Nigerian university), DEGREE_FOREIGN (of another country''s), UNIVERSITY_DIPLOMA; NOT_STATED (the type CAPS left blank: "Not stated in CAPS"), NOT_AVAILABLE (CAPS''s grade window returned nothing). One award of each kind a candidate.';
COMMENT ON COLUMN admissions.de_award.discipline IS
  'V773: a degree''s, University Diploma''s, ND''s or HND''s discipline as written (such an award holds no subject rows); NULL for an A-Level, IJMB, JUPEB, NCE or a type not stated, whose subjects are rows';
COMMENT ON COLUMN admissions.de_award.award_class IS
  'V773: a degree''s, University Diploma''s, ND''s or HND''s class as written (2nd Class Upper, Distinction, Upper Credit…), read by admissions.de_grade_points on its own kind''s scale; NULL when not shown';
COMMENT ON COLUMN admissions.de_award.exam_no IS
  'V773: the qualification''s examination or matriculation number, as CAPS''s grade window gave it';
COMMENT ON COLUMN admissions.de_award.source IS
  'V773: MANUAL, typed on Direct Entry Screening (every award before V773); UPLOAD, recorded by a workbook upload — replaced by the next upload, which also removes an uploaded award of another kind';
COMMENT ON COLUMN admissions.de_award.upload_id IS
  'V773: the upload (admissions.de_upload) that recorded the award, when its source is UPLOAD';
COMMENT ON COLUMN admissions.de_award_subject.ord IS
  'V773: the subject''s place in the combination, 1-based, as written (an NCE may name a subject twice, each its own place); NULL for a subject typed before V773, read in the order of its name';

-- ── 3 · what CAPS said of the candidate, as the last upload read it ──────────────────────────────────────────────────────────────
CREATE TABLE admissions.de_caps_value (
    session            text NOT NULL,
    jamb_key           text NOT NULL,
    qualification      text NULL CHECK (qualification IS NULL OR char_length(qualification) <= 120),  -- CAPS's "Qualification", as written
    caps_grade         integer NULL CHECK (caps_grade IS NULL OR caps_grade BETWEEN 0 AND 99),          -- CAPS's "Grade" figure
    has_five_credits   boolean NULL,
    is_cleared         boolean NULL,                                                                    -- CLEARED true, NOT CLEARED false
    status             text NULL CHECK (status IS NULL OR char_length(status) <= 60),
    age                integer NULL CHECK (age IS NULL OR age BETWEEN 0 AND 120),
    age_qualified      boolean NULL,
    admission_category text NULL CHECK (admission_category IS NULL OR char_length(admission_category) <= 80),
    upload_id          uuid NOT NULL REFERENCES admissions.de_upload(id),
    recorded_by        uuid NOT NULL,
    recorded_at        timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (session, jamb_key)
);
SELECT audit.attach('admissions.de_caps_value');
COMMENT ON TABLE admissions.de_caps_value IS
  'V773: what CAPS''s own columns said of a Direct Entry candidate (Qualification, Grade, Has 5 Credits?, IsCleared, Status, Age, Age Qualified?, Admission Category), as the last workbook upload read them; the candidate''s, not a qualification''s. The portal''s CAPS download carries none of them; the Direct Entry candidates workbook shows these first and the portal''s own reading where the upload carried none.';

-- ── 4 · the Preliminary Fit rules: the University's default (programme NULL) and a programme's own, per session policy ───────────
CREATE TABLE admissions.de_fit_rule (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_id            uuid NOT NULL REFERENCES admissions.session_policy(id) ON DELETE CASCADE,
    programme_code       text NULL REFERENCES ref.programme(code),     -- NULL: the University's default for every programme
    kind                 text NOT NULL,
    core_disciplines     text[] NULL,      -- NULL: every discipline is core; '{}': none is. A_LEVEL: the subjects counted (NULL: the programme's DE set where one is set, else every subject)
    relevant_min         smallint NULL,    -- core: points on the kind's scale at or above which → Relevant (NULL: never). A_LEVEL: the grade points a "Relevant" pass needs
    partly_min           smallint NULL,    -- core: at or above (below relevant_min) → Partly relevant (NULL: never); below → Not relevant
    related_disciplines  text[] NOT NULL DEFAULT '{}',
    related_relevant_min smallint NULL,
    related_partly_min   smallint NULL,
    other_fit            text NOT NULL DEFAULT 'NOT_RELEVANT',          -- a discipline neither core nor related
    relevant_passes      smallint NULL,    -- A_LEVEL only: passes at relevant_min or better for Relevant
    partly_passes        smallint NULL,    -- A_LEVEL only: passes at partly_min or better for Partly relevant
    set_by               uuid NOT NULL,
    set_office           text NOT NULL,
    set_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_de_fit_kind  CHECK (kind IN ('DEGREE', 'UNIVERSITY_DIPLOMA', 'HND', 'ND', 'NCE', 'A_LEVEL')),
    CONSTRAINT ck_de_fit_other CHECK (other_fit IN ('RELEVANT', 'PARTLY_RELEVANT', 'NOT_RELEVANT', 'CHECK_MANUALLY')),
    CONSTRAINT ck_de_fit_range CHECK (
        greatest(coalesce(relevant_min, 0), coalesce(partly_min, 0), coalesce(related_relevant_min, 0), coalesce(related_partly_min, 0))
          <= CASE kind WHEN 'DEGREE' THEN 5 WHEN 'UNIVERSITY_DIPLOMA' THEN 4 WHEN 'HND' THEN 5 WHEN 'ND' THEN 4 WHEN 'NCE' THEN 15 ELSE 5 END
        AND least(coalesce(relevant_min, 0), coalesce(partly_min, 0), coalesce(related_relevant_min, 0), coalesce(related_partly_min, 0)) >= 0),
    CONSTRAINT ck_de_fit_order CHECK ((relevant_min IS NULL OR partly_min IS NULL OR relevant_min >= partly_min)
        AND (related_relevant_min IS NULL OR related_partly_min IS NULL OR related_relevant_min >= related_partly_min)),
    -- A_LEVEL states all four numbers (no "Never": the editor offers none), thresholds on the letter scale 1..5; no other kind has passes
    -- (coalesce: a CHECK whose expression is NULL passes, so a missing number must read false)
    CONSTRAINT ck_de_fit_passes CHECK (coalesce(CASE WHEN kind = 'A_LEVEL'
        THEN relevant_passes BETWEEN 1 AND 9 AND partly_passes BETWEEN 1 AND 9
             AND relevant_min BETWEEN 1 AND 5 AND partly_min BETWEEN 1 AND 5
             AND cardinality(related_disciplines) = 0 AND related_relevant_min IS NULL AND related_partly_min IS NULL
        ELSE relevant_passes IS NULL AND partly_passes IS NULL END, false)),
    CONSTRAINT ck_de_fit_lists CHECK (cardinality(related_disciplines) <= 60 AND (core_disciplines IS NULL OR cardinality(core_disciplines) <= 60)
        AND (kind <> 'A_LEVEL' OR core_disciplines IS NULL OR cardinality(core_disciplines) > 0))   -- an A'Level list names at least one subject
);
CREATE UNIQUE INDEX uq_de_fit_rule ON admissions.de_fit_rule (policy_id, (coalesce(programme_code, '')), kind);
SELECT audit.attach('admissions.de_fit_rule');
COMMENT ON TABLE admissions.de_fit_rule IS
  'V773: the Preliminary Fit rules of a session''s admission settings, one row per kind of qualification (DEGREE, UNIVERSITY_DIPLOMA, HND, ND, NCE, A_LEVEL): the University''s default for every programme (programme_code NULL) and a programme''s own, which replaces the default whole. Thresholds are points on the kind''s own scale (admissions.de_class_name). A guide for the Admissions Committee on the Direct Entry candidates workbook: it never changes the rank, the qualified test or the decision.';
INSERT INTO ref.programme_reference (tab, col, policy, note) VALUES
    ('admissions.de_fit_rule', 'programme_code', 'MOVE_UNLESS_HELD', 'a programme''s own Direct Entry Preliminary Fit rule (V773)'),
    ('admissions.de_upload', 'programme_code', 'KEEP', 'history: the programme a Direct Entry qualification upload was made for (V773)')
ON CONFLICT (tab, col) DO NOTHING;

-- ── 5 · the reads: a programme's live Direct Entry rows, and the dates of birth by candidate ─────────────────────────────────────
CREATE INDEX ix_caps_row_de_live ON admissions.caps_row (session, jamb_code) WHERE entry_mode = 'DIRECT_ENTRY' AND NOT withdrawn;
CREATE INDEX ix_att_kind_key ON admissions.attachment (session, kind, jamb_key);

-- ═══ the readers ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- ── no grade released: blank, or a dash ─────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.de_no_grade(p text)
RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
    SELECT nullif(regexp_replace(coalesce(p, ''), '[\s–—-]+', '', 'g'), '') IS NULL
$$;
COMMENT ON FUNCTION admissions.de_no_grade(text) IS
  'V773: whether a Direct Entry grade is no grade — blank, or a dash ("—", "–", "-": not released by CAPS).';

-- ── the points of a grade, on the scale of its qualification ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.de_grade_points(p_basis text, p_grade text)
RETURNS integer
LANGUAGE sql IMMUTABLE AS $$
    -- the grade read three ways: its letters and signs without spaces or dashes (A, B+, A*), its words without punctuation (UPPER
    -- CREDIT, CREDIT UPPER, U C, DIST), its words and figures (2ND CLASS UPPER, 2 1); no grade and a fail 0 on every scale; a grade
    -- its kind does not use NULL — not read, for the officer to correct
    SELECT CASE
             WHEN x.compact IS NULL THEN 0
             WHEN x.compact ~ '^[FUO]$' OR x.words ~ '^(FAIL|FAILED|ABS|ABSENT)( |$)' THEN 0
             WHEN x.scale = 'L' THEN
                  CASE WHEN x.compact ~ '^[A-E][*+]?$' THEN 5 - (ascii(left(x.compact, 1)) - ascii('A')) END   -- A 5 … E 1; A* counts as A
             WHEN x.scale = 'NCE' THEN CASE
                  WHEN x.compact ~ '^[A-E][*+]?$' THEN 5 - (ascii(left(x.compact, 1)) - ascii('A'))
                  WHEN x.words ~ '^DIST' THEN 5
                  WHEN x.words ~ '^(UPPER CREDIT|CREDIT UPPER|U C|UC|LOWER CREDIT|CREDIT LOWER|L C|LC|CREDIT)( |$)' THEN 4
                  WHEN x.words ~ '^MERIT( |$)' THEN 3
                  WHEN x.words ~ '^PASS( |$)' THEN 2 END
             WHEN x.scale = 'DEG' THEN CASE
                  WHEN x.digits ~ '^(1ST|FIRST)( |$)' THEN 5
                  WHEN x.digits ~ '^((2ND|SECOND) (CLASS )?UPPER|UPPER (2ND|SECOND))( |$)' OR x.digits = '2 1' THEN 4
                  WHEN x.digits ~ '^((2ND|SECOND) (CLASS )?LOWER|LOWER (2ND|SECOND))( |$)' OR x.digits = '2 2' THEN 3
                  WHEN x.digits ~ '^(3RD|THIRD)( |$)' THEN 2
                  WHEN x.digits ~ '^PASS( |$)' THEN 1 END
             WHEN x.scale IN ('ND', 'HND', 'UNIVERSITY_DIPLOMA') THEN CASE        -- a class in words; a letter is not a diploma's class
                  WHEN x.words ~ '^DIST' THEN CASE x.scale WHEN 'HND' THEN 5 ELSE 4 END
                  WHEN x.words ~ '^(UPPER CREDIT|CREDIT UPPER|U C|UC)( |$)' THEN CASE x.scale WHEN 'HND' THEN 4 ELSE 3 END
                  WHEN x.words ~ '^(LOWER CREDIT|CREDIT LOWER|L C|LC|CREDIT)( |$)' THEN CASE x.scale WHEN 'ND' THEN 2 ELSE 3 END
                  WHEN x.words ~ '^MERIT( |$)' THEN CASE x.scale WHEN 'ND' THEN 1 ELSE 2 END
                  WHEN x.words ~ '^PASS( |$)' THEN CASE x.scale WHEN 'HND' THEN 2 ELSE 1 END END
             END
      FROM (SELECT CASE WHEN p_basis IN ('A_LEVEL', 'IJMB', 'JUPEB', 'NOT_STATED') THEN 'L'
                        WHEN p_basis IN ('DEGREE', 'DEGREE_FOREIGN') THEN 'DEG'
                        WHEN p_basis IN ('NCE', 'ND', 'HND', 'UNIVERSITY_DIPLOMA') THEN p_basis
                        ELSE 'X' END AS scale,
                   nullif(regexp_replace(upper(coalesce(p_grade, '')), '[\s–—-]+', '', 'g'), '') AS compact,
                   btrim(regexp_replace(upper(coalesce(p_grade, '')), '[^A-Z]+', ' ', 'g')) AS words,
                   btrim(regexp_replace(upper(coalesce(p_grade, '')), '[^A-Z0-9]+', ' ', 'g')) AS digits) x
$$;
COMMENT ON FUNCTION admissions.de_grade_points(text, text) IS
  'V773: the points of one Direct Entry grade on the scale of its qualification (V764 read every kind on one scale) — A-Level, IJMB, JUPEB and a type not stated: A 5, B 4, C 3, D 2, E 1 (A* as A); a degree: First Class 5, 2nd Class Upper 4 (2:1, Second Class Upper, Upper Second), 2nd Class Lower 3 (2:2), 3rd Class 2, Pass 1; HND: Distinction 5, Upper Credit 4, Lower Credit or Credit 3, Merit or Pass 2; ND: Distinction 4, Upper Credit 3, Lower Credit or Credit 2, Merit or Pass 1; University Diploma: Distinction 4, Upper Credit or Credit 3, Merit 2, Pass 1; NCE, a subject: Distinction 5, a credit 4, Merit 3, Pass 2 (a letter as A-Level), whatever the punctuation (Upper-Credit, U/C, Dist., Credit (Upper)). A fail or absence (F, U, O, Fail, Absent) and no grade 0; a grade its kind does not use (a letter on a degree or diploma) NULL — not read.';

-- ── a kind's maximum, its classes, a basis in words ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.de_points_max(p_kind text)
RETURNS integer
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_kind WHEN 'A_LEVEL' THEN 16 WHEN 'NCE' THEN 15 WHEN 'ND' THEN 4 WHEN 'HND' THEN 5
                       WHEN 'UNIVERSITY_DIPLOMA' THEN 4 WHEN 'DEGREE' THEN 5 END
$$;
COMMENT ON FUNCTION admissions.de_points_max(text) IS
  'V773: the most points a kind of Direct Entry qualification can score — A-Level (IJMB, JUPEB) 16 (three subjects at A and 1 for no fail), NCE 15, ND 4, HND 5, University Diploma 4, degree 5; NULL for none.';

CREATE FUNCTION admissions.de_class_name(p_kind text, p_points integer)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_kind
             WHEN 'DEGREE' THEN CASE p_points WHEN 5 THEN 'First Class' WHEN 4 THEN '2nd Class Upper' WHEN 3 THEN '2nd Class Lower'
                                              WHEN 2 THEN '3rd Class' WHEN 1 THEN 'Pass' END
             WHEN 'UNIVERSITY_DIPLOMA' THEN CASE p_points WHEN 4 THEN 'Distinction' WHEN 3 THEN 'Credit' WHEN 2 THEN 'Merit' WHEN 1 THEN 'Pass' END
             WHEN 'ND' THEN CASE p_points WHEN 4 THEN 'Distinction' WHEN 3 THEN 'Upper Credit' WHEN 2 THEN 'Lower Credit' WHEN 1 THEN 'Pass' END
             WHEN 'HND' THEN CASE p_points WHEN 5 THEN 'Distinction' WHEN 4 THEN 'Upper Credit' WHEN 3 THEN 'Lower Credit' WHEN 2 THEN 'Pass' END
             WHEN 'NCE' THEN p_points || ' points'
             WHEN 'A_LEVEL' THEN CASE p_points WHEN 5 THEN 'A' WHEN 4 THEN 'B' WHEN 3 THEN 'C' WHEN 2 THEN 'D' WHEN 1 THEN 'E' END
           END
$$;
COMMENT ON FUNCTION admissions.de_class_name(text, integer) IS
  'V773: the class a kind of Direct Entry qualification gives a number of points — a degree First Class … Pass (5 … 1), a University Diploma Distinction, Credit, Merit, Pass (4 … 1), an ND Distinction, Upper Credit, Lower Credit, Pass (4 … 1), an HND Distinction, Upper Credit, Lower Credit, Pass (5 … 2), an NCE "<n> points", an A-Level grade A … E (5 … 1); NULL for none.';

CREATE FUNCTION admissions.de_threshold_words(p_kind text, p_points integer)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce(admissions.de_class_name(p_kind, p_points),
                    p_points || CASE WHEN p_points = 1 THEN ' point' ELSE ' points' END)
$$;
COMMENT ON FUNCTION admissions.de_threshold_words(text, integer) IS
  'V773: a fit threshold in words for a reason — the class the points name (admissions.de_class_name), or the points themselves where the kind names no class for them (an HND at 1 point), so a reason is never empty.';

CREATE FUNCTION admissions.de_basis_label(p_basis text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
             WHEN p_basis IS NULL THEN 'Not recorded'
             WHEN p_basis = 'A_LEVEL' THEN 'GCE A''Level'
             WHEN p_basis = 'IJMB' THEN 'IJMB - A''Level'
             WHEN p_basis = 'JUPEB' THEN 'JUPEB - A''Level'
             WHEN p_basis = 'NCE' THEN 'Nigeria Certificate in Education (NCE)'
             WHEN p_basis = 'ND' THEN 'National Diploma (ND)'
             WHEN p_basis = 'HND' THEN 'Higher National Diploma (HND)'
             WHEN p_basis = 'DEGREE' THEN '1st Degree (Nigeria Universities)'
             WHEN p_basis = 'DEGREE_FOREIGN' THEN '1st Degree (Other Country Universities)'
             WHEN p_basis = 'UNIVERSITY_DIPLOMA' THEN 'University Diploma'
             WHEN p_basis = 'NOT_STATED' THEN 'Not stated in CAPS'
             WHEN p_basis = 'NOT_AVAILABLE' THEN 'Not available'
             ELSE p_basis END
$$;
COMMENT ON FUNCTION admissions.de_basis_label(text) IS
  'V773: a Direct Entry qualification''s kind in CAPS''s words (GCE A''Level, JUPEB - A''Level, 1st Degree (Nigeria Universities), Not stated in CAPS…); "Not recorded" for none.';

-- ── words, lists, and whether a discipline is one a rule names ──────────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.de_words(p text)
RETURNS text[]
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN x.s = '' THEN '{}'::text[] ELSE regexp_split_to_array(x.s, ' ') END
      FROM (SELECT btrim(regexp_replace(replace(lower(coalesce(p, '')), '&', ' and '), '[^a-z0-9]+', ' ', 'g')) AS s) x
$$;
COMMENT ON FUNCTION admissions.de_words(text) IS
  'V773: a text''s words — lower case, "&" read as "and", every run of anything but letters and figures a break; empty for none.';

CREATE FUNCTION admissions.de_and_list(p text[])
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE coalesce(cardinality(p), 0)
             WHEN 0 THEN NULL
             WHEN 1 THEN p[1]
             ELSE array_to_string(p[1:cardinality(p) - 1], ', ') || ' and ' || p[cardinality(p)] END
$$;
COMMENT ON FUNCTION admissions.de_and_list(text[]) IS
  'V773: a list as a sentence names it — "A", "A and B", "A, B and C".';

CREATE FUNCTION admissions.de_discipline_matches(p_discipline text, p_item text)
RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
    -- an alternative's words a run of the discipline's words: "Industrial Chemistry" is Chemistry, "Biochemistry" is not
    SELECT EXISTS (
        SELECT 1
          FROM regexp_split_to_table(lower(coalesce(p_item, '')), '\s*/\s*|\s+or\s+') a(alt)
         CROSS JOIN LATERAL (SELECT array_to_string(admissions.de_words(a.alt), ' ') AS w) aw
         WHERE aw.w <> ''
           AND ' ' || array_to_string(admissions.de_words(p_discipline), ' ') || ' ' LIKE '% ' || aw.w || ' %')
$$;
COMMENT ON FUNCTION admissions.de_discipline_matches(text, text) IS
  'V773: whether a discipline is one a fit rule''s item names — some alternative of the item ("A/B", "A or B") whose words appear together, in order, among the discipline''s ("Industrial Chemistry" is Chemistry, "Biochemistry" is not; "Pharmaceutical Technology (Chemistry)" is Pharmaceutical Technology; "Science Laboratory Technology" is Laboratory Technology).';

CREATE FUNCTION admissions.de_names_programme(p_discipline text, p_programme_name text)
RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
    -- the programme's subject words: its name less the degree's own words (and a bracketed abbreviation where words stand outside it);
    -- the discipline's the same, less the small words; the two the same set
    WITH t AS (SELECT ARRAY['b', 'a', 'sc', 'ed', 'll', 'bachelor', 'doctor', 'of', 'in', 'and', 'the', 'for', 'with', 'language', 'studies'] AS deg,
                      ARRAY['of', 'in', 'and', 'the', 'for', 'with', 'a', 'an', 'language', 'studies'] AS stop),
    pw AS (SELECT CASE WHEN EXISTS (SELECT 1 FROM unnest(admissions.de_words(regexp_replace(coalesce(p_programme_name, ''), '\([^)]*\)', ' ', 'g'))) w(x)
                                     WHERE w.x <> ALL (t.deg))
                       THEN admissions.de_words(regexp_replace(coalesce(p_programme_name, ''), '\([^)]*\)', ' ', 'g'))
                       ELSE admissions.de_words(p_programme_name) END AS w
             FROM t),
    dw AS (SELECT CASE WHEN EXISTS (SELECT 1 FROM unnest(admissions.de_words(regexp_replace(coalesce(p_discipline, ''), '\([^)]*\)', ' ', 'g'))) w(x)
                                     WHERE w.x <> ALL (t.stop))
                       THEN admissions.de_words(regexp_replace(coalesce(p_discipline, ''), '\([^)]*\)', ' ', 'g'))
                       ELSE admissions.de_words(p_discipline) END AS w
             FROM t),
    ps AS (SELECT ARRAY(SELECT DISTINCT u.x FROM pw, t, unnest(pw.w) u(x) WHERE u.x <> ALL (t.deg) ORDER BY u.x) AS s),
    ds AS (SELECT ARRAY(SELECT DISTINCT u.x FROM dw, t, unnest(dw.w) u(x) WHERE u.x <> ALL (t.stop) ORDER BY u.x) AS s)
    SELECT cardinality(ps.s) > 0 AND ps.s = ds.s FROM ps, ds
$$;
COMMENT ON FUNCTION admissions.de_names_programme(text, text) IS
  'V773: whether a discipline is the programme''s own subject — the discipline''s words (less of, in, and, the, for, with, a, an, language, studies, and a bracketed part where words stand outside it) the same set as the programme name''s (less the degree''s words b, a, sc, ed, ll, bachelor, doctor and those, and a bracketed abbreviation): Law is LL.B (LAW), Pharmacy DOCTOR OF PHARMACY, English Language B.A. ENGLISH; Management is not B.Sc. BUSINESS MANAGEMENT, nor Chemistry B.Sc INDUSTRIAL CHEMISTRY.';

-- ── a CAPS row's programme: the code JAMB's list carries, read through the programme aliases ─────────────────────────────────────
CREATE FUNCTION admissions.de_programme_of(p_code text)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT a.programme_code FROM ref.programme_alias a
                      WHERE a.alias_code = p_code AND a.ended_at IS NULL ORDER BY a.created_at DESC LIMIT 1), p_code)
$$;
COMMENT ON FUNCTION admissions.de_programme_of(text) IS
  'V773: the programme a code on JAMB''s list stands for — the code itself, unless it is an alias in force of another programme (a merge, V574; an ICT code correction, V716), which then holds the rules.';

CREATE FUNCTION admissions.de_programme_codes(p_code text)
RETURNS text[]
LANGUAGE sql STABLE AS $$
    SELECT ARRAY[p_code] || ARRAY(SELECT a.alias_code FROM ref.programme_alias a WHERE a.programme_code = p_code AND a.ended_at IS NULL ORDER BY a.alias_code)
$$;
COMMENT ON FUNCTION admissions.de_programme_codes(text) IS
  'V773: the codes JAMB''s list may carry for a programme — its own and every alias of it in force.';

-- ── a subject's key and the keys the session's settings accept in its place ─────────────────────────────────────────────────────
CREATE FUNCTION admissions.de_subject_keys(p_policy uuid, p_subjects text[], p_scope text)
RETURNS text[]
LANGUAGE sql STABLE AS $$
    SELECT ARRAY(SELECT DISTINCT z.k FROM (
                   SELECT admissions.subject_key(s.x) AS k FROM unnest(p_subjects) s(x)
                   UNION
                   SELECT admissions.subject_key(e.equivalent) FROM admissions.subject_equivalence e
                    WHERE e.policy_id = p_policy AND e.scope IN (p_scope, 'ANY')
                      AND admissions.subject_key(e.subject) IN (SELECT admissions.subject_key(s2.x) FROM unnest(p_subjects) s2(x))) z
                  WHERE z.k IS NOT NULL ORDER BY z.k)
$$;
COMMENT ON FUNCTION admissions.de_subject_keys(uuid, text[], text) IS
  'V773: the subject keys (admissions.subject_key) of a rule''s subjects and of every subject the policy''s equivalences accept in their place, in that scope or ANY.';

-- ── every qualification recorded, scored on its own scale ───────────────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.de_award_scores(p_session text, p_keys text[] DEFAULT NULL)
RETURNS TABLE (award_id uuid, jamb_key text, basis text, kind text, source text,
               discipline text, award_class text, grades text, class_points text,
               subjects jsonb, combination jsonb,
               points integer, max_points integer, score numeric,
               graded boolean, unread text, captured boolean,
               institution text, awarded_year integer, exam_no text, counts boolean)
LANGUAGE sql STABLE AS $$
    WITH aw AS (
        SELECT d.id, d.jamb_key, d.basis, d.source, d.discipline, d.award_class, d.institution, d.awarded_year, d.exam_no,
               CASE WHEN d.basis = 'NOT_STATED' THEN 'A_LEVEL' ELSE d.basis END AS scale
          FROM admissions.de_award d
         WHERE d.session = p_session AND (p_keys IS NULL OR d.jamb_key = ANY (p_keys))),
    sub AS (
        -- each subject of an award (a blank subject is none), its grade read once: n best first, o in its place, a name's first place
        SELECT w.id AS award_id, y.subject, y.grade, z.p, z.ng,
               row_number() OVER (PARTITION BY w.id ORDER BY z.p DESC NULLS LAST, y.ord NULLS LAST, y.subject, y.id) AS n,
               row_number() OVER (PARTITION BY w.id ORDER BY y.ord NULLS LAST, y.subject, y.id) AS o,
               row_number() OVER (PARTITION BY w.id, lower(btrim(y.subject)) ORDER BY y.ord NULLS LAST, y.subject, y.id) AS named
          FROM aw w
          JOIN admissions.de_award_subject y ON y.award_id = w.id AND nullif(btrim(y.subject), '') IS NOT NULL
         CROSS JOIN LATERAL (SELECT admissions.de_grade_points(w.scale, y.grade) AS p, admissions.de_no_grade(y.grade) AS ng) z),
    agg AS (
        SELECT s.award_id, count(*)::int AS n_sub,
               bool_or(NOT s.ng) AS any_graded,
               bool_and(s.p IS NOT NULL OR s.ng) AS all_read,
               sum(coalesce(s.p, 0)) FILTER (WHERE s.n <= 3) AS best3,
               bool_and(coalesce(s.p >= 1, false) AND NOT s.ng) FILTER (WHERE s.n <= 3) AS best3_passed,
               (array_agg(s.subject ORDER BY s.n))[1] AS top_subject,
               (array_agg(s.grade ORDER BY s.n))[1] AS top_grade,
               string_agg(s.subject, ' / ' ORDER BY s.o) FILTER (WHERE s.named = 1) AS named_subjects,
               string_agg(s.subject || ': ' || CASE WHEN s.ng THEN '—' ELSE s.grade END, '; ' ORDER BY s.o) AS grades,
               string_agg(CASE WHEN s.ng THEN '—' ELSE s.grade END, ', ' ORDER BY s.o) AS grade_list,
               jsonb_agg(jsonb_build_object('subject', s.subject, 'grade', s.grade, 'points', s.p) ORDER BY s.n) AS subjects,
               jsonb_agg(jsonb_build_object('subject', s.subject, 'grade', s.grade, 'points', s.p) ORDER BY s.o) AS combination,
               string_agg(s.subject || ' ' || s.grade, ', ' ORDER BY s.subject) FILTER (WHERE s.p IS NULL AND NOT s.ng) AS unread
          FROM sub s
         GROUP BY s.award_id),
    k AS (
        SELECT w.id, w.jamb_key, w.basis, w.source, w.discipline AS d_discipline, w.award_class AS d_class, w.institution, w.awarded_year, w.exam_no,
               coalesce(a.n_sub, 0) AS n_sub, coalesce(a.any_graded, false) AS any_graded, a.all_read, a.best3, a.best3_passed,
               a.top_subject, a.top_grade, a.named_subjects, a.grades, a.grade_list, a.subjects, a.combination, a.unread,
               CASE WHEN w.basis IN ('A_LEVEL', 'IJMB', 'JUPEB') THEN 'A_LEVEL'
                    WHEN w.basis = 'NOT_STATED' THEN
                         CASE WHEN coalesce(a.n_sub, 0) >= 1 AND nullif(btrim(w.award_class), '') IS NULL AND a.all_read THEN 'A_LEVEL' ELSE 'NONE' END
                    WHEN w.basis IN ('DEGREE', 'DEGREE_FOREIGN') THEN 'DEGREE'
                    WHEN w.basis IN ('NCE', 'ND', 'HND', 'UNIVERSITY_DIPLOMA') THEN w.basis
                    ELSE 'NONE' END AS kind
          FROM aw w LEFT JOIN agg a ON a.award_id = w.id),
    c AS (
        -- a degree or diploma by its discipline and class (one typed as subject rows before V773: its best subject); the rest by
        -- their subjects
        SELECT k.*, k.kind IN ('DEGREE', 'UNIVERSITY_DIPLOMA', 'HND', 'ND') AS class_kind,
               CASE WHEN k.kind IN ('DEGREE', 'UNIVERSITY_DIPLOMA', 'HND', 'ND') THEN coalesce(nullif(btrim(k.d_discipline), ''), k.top_subject)
                    ELSE coalesce(k.named_subjects, nullif(btrim(k.d_discipline), '')) END AS disc,
               CASE WHEN k.kind IN ('DEGREE', 'UNIVERSITY_DIPLOMA', 'HND', 'ND') THEN coalesce(nullif(btrim(k.d_class), ''), k.top_grade) END AS cls
          FROM k),
    g AS (
        SELECT c.*,
               CASE WHEN c.class_kind THEN NOT admissions.de_no_grade(c.cls)
                    WHEN c.kind IN ('A_LEVEL', 'NCE') THEN c.any_graded
                    ELSE false END AS graded_
          FROM c),
    p AS (
        SELECT g.*,
               CASE WHEN g.kind = 'A_LEVEL' AND g.graded_ THEN (g.best3 + CASE WHEN g.best3_passed THEN 1 ELSE 0 END)::int
                    WHEN g.kind = 'NCE' AND g.graded_ THEN g.best3::int
                    WHEN g.class_kind AND g.graded_ THEN admissions.de_grade_points(g.basis, g.cls) END AS pts,
               admissions.de_points_max(g.kind) AS mx,
               (g.n_sub > 0 OR nullif(btrim(g.d_discipline), '') IS NOT NULL OR nullif(btrim(g.d_class), '') IS NOT NULL)
                   AND g.basis <> 'NOT_AVAILABLE' AS capt,
               CASE g.kind WHEN 'A_LEVEL' THEN 1 WHEN 'DEGREE' THEN 2 WHEN 'UNIVERSITY_DIPLOMA' THEN 3 WHEN 'HND' THEN 4
                           WHEN 'ND' THEN 5 WHEN 'NCE' THEN 6 ELSE 7 END AS kind_order
          FROM g),
    s AS (SELECT p.*, round(p.pts * 100.0 / p.mx, 2) AS sc FROM p)
    SELECT s.id, s.jamb_key, s.basis, s.kind, s.source,
           s.disc,
           s.cls,
           CASE WHEN s.class_kind THEN nullif(concat_ws(': ', s.disc, s.cls), '') ELSE s.grades END,
           CASE WHEN s.class_kind THEN s.cls WHEN s.kind = 'A_LEVEL' THEN s.pts::text WHEN s.kind = 'NCE' THEN s.grade_list END,
           CASE WHEN s.n_sub > 0 THEN s.subjects
                WHEN s.class_kind AND (s.disc IS NOT NULL OR s.cls IS NOT NULL)
                     THEN jsonb_build_array(jsonb_build_object('subject', s.disc, 'grade', s.cls, 'points', s.pts))
                ELSE '[]'::jsonb END,
           coalesce(s.combination, '[]'::jsonb),
           s.pts, s.mx, s.sc,
           s.graded_,
           CASE WHEN s.class_kind THEN CASE WHEN s.graded_ AND s.pts IS NULL THEN concat_ws(' ', s.disc, s.cls) END ELSE s.unread END,
           s.capt,
           s.institution, s.awarded_year, s.exam_no,
           row_number() OVER (PARTITION BY s.jamb_key ORDER BY s.capt DESC, s.sc DESC NULLS LAST, s.kind_order, s.basis, s.id) = 1
      FROM s
$$;
COMMENT ON FUNCTION admissions.de_award_scores(text, text[]) IS
  'V773: every Direct Entry qualification recorded for a session (or for the candidates given), scored on its own scale — its kind (A_LEVEL for A-Level, IJMB, JUPEB and a type not stated graded in letters; DEGREE for a Nigerian or foreign degree; UNIVERSITY_DIPLOMA, HND, ND, NCE; NONE otherwise), the discipline and class or the subjects and grades as the sheet writes them, the points (an A-Level''s three best subjects plus 1 when each is a pass, of 16; an NCE''s three best, of 15; a degree''s or diploma''s class on its own scale; none without grades), the maximum and the score (points as a percentage of the maximum, two decimals), the grades not read, whether anything was captured, and which counts: the highest score, one without a score only when nothing has one.';

-- ── the Preliminary Fit rules: the built-in default, the rules in force for a programme, and in words ──────────────────────────
CREATE FUNCTION admissions.de_fit_builtin()
RETURNS TABLE (kind text, core_disciplines text[], relevant_min smallint, partly_min smallint, related_disciplines text[],
               related_relevant_min smallint, related_partly_min smallint, other_fit text, relevant_passes smallint, partly_passes smallint)
LANGUAGE sql IMMUTABLE AS $$
    SELECT v.kind, v.core, v.rmin::smallint, v.pmin::smallint, '{}'::text[], NULL::smallint, NULL::smallint, v.other, v.rp::smallint, v.pp::smallint
      FROM (VALUES (1, 'DEGREE',             NULL::text[], 3,          2, 'NOT_RELEVANT',   NULL::int, NULL::int),
                   (2, 'UNIVERSITY_DIPLOMA', '{}'::text[], 3,          1, 'CHECK_MANUALLY', NULL,      NULL),
                   (3, 'HND',                NULL,         NULL,       2, 'NOT_RELEVANT',   NULL,      NULL),
                   (4, 'ND',                 NULL,         NULL,       1, 'NOT_RELEVANT',   NULL,      NULL),
                   (5, 'NCE',                NULL,         NULL,       1, 'NOT_RELEVANT',   NULL,      NULL),
                   (6, 'A_LEVEL',            NULL,         1,          1, 'NOT_RELEVANT',   3,         2)) v(o, kind, core, rmin, pmin, other, rp, pp)
     ORDER BY v.o
$$;
COMMENT ON FUNCTION admissions.de_fit_builtin() IS
  'V773: the University''s default Preliminary Fit, where a session''s settings state none — a degree in any discipline 2nd Class Lower or better Relevant, 3rd Class Partly; a University Diploma in the programme''s own discipline Credit or better Relevant, Pass Partly, any other Check manually; an HND, ND or NCE Partly relevant (to be confirmed by the Faculty); an A-Level 3 passes Relevant, 2 Partly.';

CREATE FUNCTION admissions.de_fit_rules(p_policy uuid, p_programme text)
RETURNS TABLE (source text, kind text, rule jsonb)
LANGUAGE sql STABLE AS $$
    WITH own AS (SELECT r.* FROM admissions.de_fit_rule r WHERE r.policy_id = p_policy AND r.programme_code = p_programme),
    dflt AS (SELECT r.* FROM admissions.de_fit_rule r WHERE r.policy_id = p_policy AND r.programme_code IS NULL),
    pick AS (
        SELECT 'PROGRAMME' AS src, o.kind, o.core_disciplines, o.relevant_min, o.partly_min, o.related_disciplines, o.related_relevant_min,
               o.related_partly_min, o.other_fit, o.relevant_passes, o.partly_passes
          FROM own o
        UNION ALL
        SELECT 'DEFAULT', d.kind, d.core_disciplines, d.relevant_min, d.partly_min, d.related_disciplines, d.related_relevant_min,
               d.related_partly_min, d.other_fit, d.relevant_passes, d.partly_passes
          FROM dflt d WHERE NOT EXISTS (SELECT 1 FROM own)
        UNION ALL
        SELECT 'BUILT_IN', b.kind, b.core_disciplines, b.relevant_min, b.partly_min, b.related_disciplines, b.related_relevant_min,
               b.related_partly_min, b.other_fit, b.relevant_passes, b.partly_passes
          FROM admissions.de_fit_builtin() b WHERE NOT EXISTS (SELECT 1 FROM own) AND NOT EXISTS (SELECT 1 FROM dflt))
    SELECT k.src, k.kind,
           jsonb_build_object('kind', k.kind, 'core_disciplines', k.core_disciplines, 'relevant_min', k.relevant_min, 'partly_min', k.partly_min,
                              'related_disciplines', k.related_disciplines, 'related_relevant_min', k.related_relevant_min,
                              'related_partly_min', k.related_partly_min, 'other_fit', k.other_fit, 'relevant_passes', k.relevant_passes,
                              'partly_passes', k.partly_passes, 'source', k.src)
      FROM pick k
     ORDER BY CASE k.kind WHEN 'DEGREE' THEN 1 WHEN 'UNIVERSITY_DIPLOMA' THEN 2 WHEN 'HND' THEN 3 WHEN 'ND' THEN 4 WHEN 'NCE' THEN 5 ELSE 6 END
$$;
COMMENT ON FUNCTION admissions.de_fit_rules(uuid, text) IS
  'V773: the Preliminary Fit rules in force for a programme under a session policy, one row per kind in the order DEGREE, UNIVERSITY_DIPLOMA, HND, ND, NCE, A_LEVEL: the programme''s own (PROGRAMME) where it has any, else the policy''s default (DEFAULT), else the built-in default (BUILT_IN, also without a policy); rule is the row as JSON (its column names) with its source.';

CREATE FUNCTION admissions.de_fit_label(p_fit text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_fit WHEN 'RELEVANT' THEN 'Relevant' WHEN 'PARTLY_RELEVANT' THEN 'Partly relevant'
                      WHEN 'NOT_RELEVANT' THEN 'Not relevant' WHEN 'CHECK_MANUALLY' THEN 'Check manually' END
$$;
COMMENT ON FUNCTION admissions.de_fit_label(text) IS
  'V773: a Preliminary Fit in words — Relevant, Partly relevant, Not relevant, Check manually.';

CREATE FUNCTION admissions.de_fit_ladder(p_kind text, p_r integer, p_p integer, p_other text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    -- the kind's classes from the highest: those at r or above Relevant, at p or above Partly relevant, the rest Not relevant; an NCE
    -- in points; neither threshold: what any other discipline reads
    WITH c AS (
        SELECT gs.pts, admissions.de_class_name(p_kind, gs.pts) AS nm
          FROM generate_series(coalesce(admissions.de_points_max(p_kind), 0), 1, -1) gs(pts)
         WHERE p_kind <> 'NCE' AND admissions.de_class_name(p_kind, gs.pts) IS NOT NULL),
    parts AS (
        SELECT 1 AS o, CASE WHEN count(*) = (SELECT count(*) FROM c) THEN 'Any class' ELSE string_agg(c.nm, '/' ORDER BY c.pts DESC) END
                       || ' = Relevant' AS t
          FROM c WHERE p_r IS NOT NULL AND c.pts >= p_r HAVING count(*) > 0
        UNION ALL
        SELECT 2, CASE WHEN count(*) = (SELECT count(*) FROM c) THEN 'Any class' ELSE string_agg(c.nm, '/' ORDER BY c.pts DESC) END
                  || ' = Partly relevant'
                  || CASE WHEN p_r IS NULL AND p_kind IN ('ND', 'HND') THEN ' (acceptance to be confirmed by the Faculty)' ELSE '' END
          FROM c WHERE p_p IS NOT NULL AND c.pts >= p_p AND (p_r IS NULL OR c.pts < p_r) HAVING count(*) > 0
        UNION ALL
        SELECT 3, string_agg(c.nm, '/' ORDER BY c.pts DESC) || ' = Not relevant'
          FROM c WHERE c.pts < coalesce(p_p, p_r) HAVING count(*) > 0
        UNION ALL
        SELECT 1, p_r || ' of 15 points or more = Relevant' WHERE p_kind = 'NCE' AND p_r IS NOT NULL
        UNION ALL
        SELECT 2, CASE WHEN p_p <= 6 AND p_r IS NULL THEN 'Any pass' ELSE p_p || ' of 15 points or more' END || ' = Partly relevant'
                  || CASE WHEN p_r IS NULL THEN ' (acceptance to be confirmed by the Faculty)' ELSE '' END
         WHERE p_kind = 'NCE' AND p_p IS NOT NULL AND (p_r IS NULL OR p_p < p_r)
        UNION ALL
        SELECT 3, 'fewer = Not relevant' WHERE p_kind = 'NCE' AND (p_p > 6 OR (p_p IS NULL AND p_r IS NOT NULL)))
    SELECT CASE WHEN p_r IS NULL AND p_p IS NULL THEN admissions.de_fit_label(p_other)
                ELSE (SELECT string_agg(parts.t, '; ' ORDER BY parts.o) FROM parts) END
$$;
COMMENT ON FUNCTION admissions.de_fit_ladder(text, integer, integer, text) IS
  'V773: a fit rule''s thresholds in words over the kind''s classes, highest first — "First Class/2nd Class Upper = Relevant; 2nd Class Lower = Partly relevant; 3rd Class/Pass = Not relevant", "Any class = Partly relevant (acceptance to be confirmed by the Faculty)"; an NCE in points of 15; neither threshold: the other disciplines'' fit.';

CREATE FUNCTION admissions.de_fit_criteria(p_session text, p_programme text)
RETURNS TABLE (ord integer, qualification text, rule_applied text, source text)
LANGUAGE sql STABLE AS $$
    WITH pol AS (
        SELECT p.id FROM admissions.session_policy p WHERE p.session = p_session ORDER BY (p.state = 'IN_FORCE') DESC LIMIT 1),
    r AS (
        SELECT f.source, f.kind,
               CASE f.kind WHEN 'DEGREE' THEN 1 WHEN 'UNIVERSITY_DIPLOMA' THEN 2 WHEN 'HND' THEN 3 WHEN 'ND' THEN 4 WHEN 'NCE' THEN 5 ELSE 6 END AS ko,
               CASE f.kind WHEN 'DEGREE' THEN '1st Degree (Nigerian or foreign)' WHEN 'UNIVERSITY_DIPLOMA' THEN 'University Diploma'
                           WHEN 'HND' THEN 'Higher National Diploma (HND)' WHEN 'ND' THEN 'National Diploma (ND)'
                           WHEN 'NCE' THEN 'Nigeria Certificate in Education (NCE)' END AS q,
               CASE WHEN f.kind = 'NCE' THEN ', any subjects' ELSE ', any discipline' END AS q_any,
               CASE WHEN jsonb_typeof(f.rule->'core_disciplines') = 'array' THEN ARRAY(SELECT jsonb_array_elements_text(f.rule->'core_disciplines')) END AS core,
               ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(f.rule->'related_disciplines') = 'array'
                                                           THEN f.rule->'related_disciplines' ELSE '[]'::jsonb END)) AS rel,
               (f.rule->>'relevant_min')::int AS rmin, (f.rule->>'partly_min')::int AS pmin,
               (f.rule->>'related_relevant_min')::int AS rrmin, (f.rule->>'related_partly_min')::int AS rpmin,
               f.rule->>'other_fit' AS other, (f.rule->>'relevant_passes')::int AS rpass, (f.rule->>'partly_passes')::int AS ppass
          FROM admissions.de_fit_rules((SELECT pol.id FROM pol), p_programme) f),
    lines AS (
        -- a degree, diploma or NCE: its core line (any discipline; the programme's own; those listed)
        SELECT r.ko, 1 AS so, r.source,
               r.q || CASE WHEN r.core IS NULL OR (cardinality(r.core) = 0 AND r.rmin IS NULL AND r.pmin IS NULL) THEN r.q_any
                           WHEN cardinality(r.core) = 0 THEN ' in the programme''s own discipline'
                           ELSE ' in ' || array_to_string(r.core, ', ') END AS q,
               CASE WHEN r.core IS NOT NULL AND cardinality(r.core) = 0 AND r.rmin IS NULL AND r.pmin IS NULL THEN admissions.de_fit_label(r.other)
                    ELSE admissions.de_fit_ladder(r.kind, r.rmin, r.pmin, r.other) END AS t
          FROM r WHERE r.kind <> 'A_LEVEL'
        UNION ALL
        -- the related disciplines
        SELECT r.ko, 2, r.source, r.q || ' in a related discipline (' || array_to_string(r.rel, ', ') || ')',
               admissions.de_fit_ladder(r.kind, r.rrmin, r.rpmin, r.other)
          FROM r WHERE r.kind <> 'A_LEVEL' AND r.core IS NOT NULL AND cardinality(r.rel) > 0
        UNION ALL
        -- any other discipline
        SELECT r.ko, 3, r.source, r.q || ' in any other discipline', admissions.de_fit_label(r.other)
          FROM r WHERE r.kind <> 'A_LEVEL' AND r.core IS NOT NULL AND NOT (cardinality(r.core) = 0 AND r.rmin IS NULL AND r.pmin IS NULL)
        UNION ALL
        -- the A-Level
        SELECT r.ko, 1, r.source,
               CASE WHEN r.core IS NULL THEN 'A''Level (GCE, IJMB, JUPEB): the programme''s Direct Entry subjects where set, else any'
                    ELSE 'A''Level (GCE, IJMB, JUPEB) in ' || admissions.de_and_list(r.core) END,
               r.rpass || CASE WHEN r.rpass = 1 THEN ' pass ' ELSE ' passes ' END
                   || CASE WHEN r.rmin = 1 THEN '(A–E)' ELSE 'at A–' || admissions.de_class_name('A_LEVEL', r.rmin) END || ' = Relevant; '
                   || r.ppass || CASE WHEN r.ppass = 1 THEN ' pass ' ELSE ' passes ' END
                   || CASE WHEN r.pmin = 1 THEN '(A–E)' ELSE 'at A–' || admissions.de_class_name('A_LEVEL', r.pmin) END || ' = Partly relevant; '
                   || 'fewer = Not relevant; F is a fail'
                   || CASE WHEN r.core IS NULL THEN '; where the programme has a Direct Entry subject set: its subjects all passed = Relevant, one short = Partly relevant' ELSE '' END
          FROM r WHERE r.kind = 'A_LEVEL'
        UNION ALL
        -- what every rule says alike
        SELECT 10, f.o, (SELECT r.source FROM r LIMIT 1), f.q, f.t
          FROM (VALUES (1, 'A''Level with no grades released', 'Check manually'),
                       (2, 'Qualification type / year blank in CAPS', 'Check manually, unless the grades already fail'),
                       (3, 'Grade window returned no data, or no qualification recorded', 'Check manually'),
                       (4, 'Foreign degree', 'Assessed as above; Other Notes flags that equivalence must be confirmed'),
                       (5, 'A degree or diploma in the programme''s own discipline', 'Assessed as a core discipline; the Reason notes it')) f(o, q, t))
    SELECT (row_number() OVER (ORDER BY l.ko, l.so))::int, l.q, l.t, l.source
      FROM lines l
     ORDER BY l.ko, l.so
$$;
COMMENT ON FUNCTION admissions.de_fit_criteria(text, text) IS
  'V773: the Preliminary Fit rules in force for a programme in a session, in words, for the Fit Criteria sheet and the settings screen — under the session''s policy (in force, else as it stands), each kind''s lines (a degree, University Diploma, HND, ND, NCE: its core disciplines, the related ones, any other; the A-Level: the subjects counted and the passes), then five lines every rule shares; each with the rule''s source (PROGRAMME, DEFAULT or BUILT_IN).';

-- ── the Preliminary Fit of the qualification that counts ───────────────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.de_fit_of(p_award jsonb, p_rule jsonb, p_de_set jsonb, p_programme text)
RETURNS TABLE (fit text, reason text)
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_basis text := p_award->>'basis';
    v_kind  text := p_award->>'kind';
    v_p     text := coalesce(nullif(btrim(p_programme), ''), 'the programme');
    v_points int := (p_award->>'points')::int;
    v_core text[]; v_rel text[]; v_whose text;
    v_rmin int := (p_rule->>'relevant_min')::int;      v_pmin int := (p_rule->>'partly_min')::int;
    v_rrmin int := (p_rule->>'related_relevant_min')::int; v_rpmin int := (p_rule->>'related_partly_min')::int;
    v_rpass int := (p_rule->>'relevant_passes')::int;  v_ppass int := (p_rule->>'partly_passes')::int;
    v_other text := p_rule->>'other_fit';
    v_fit text; v_reason text;
    -- the A-Level: the combination in its place order, what is counted
    c_sub text[]; c_grd text[]; c_pts int[]; c_key text[]; c_has boolean[];
    v_mode text; v_cnt int[] := ARRAY[]::int[]; v_items text[] := ARRAY[]::text[]; v_missing text[] := ARRAY[]::text[];
    v_keys text[]; v_pick int; v_n int; v_pr int; v_pp int; v_need int; v_graded_n int;
    v_failed text; v_weak text; v_comb text; v_unread text; v_names text[]; v_grades text[]; v_grp record;
    -- a degree, diploma or NCE
    v_d text; v_c text; v_k text; v_kd text; v_a text; v_match text; v_named boolean;
BEGIN
    IF p_award IS NULL OR jsonb_typeof(p_award) <> 'object' THEN
        RETURN QUERY SELECT 'Check manually'::text, 'No qualification recorded'::text; RETURN;
    END IF;
    IF v_basis = 'NOT_AVAILABLE' THEN
        RETURN QUERY SELECT 'Check manually'::text, 'Grade window returned no data on CAPS'::text; RETURN;
    END IF;
    IF v_kind IS NULL OR v_kind = 'NONE' THEN
        RETURN QUERY SELECT 'Check manually'::text, 'Qualification type missing in CAPS; check the certificate'::text; RETURN;
    END IF;
    IF p_rule IS NULL OR jsonb_typeof(p_rule) <> 'object' THEN
        RETURN QUERY SELECT 'Check manually'::text, 'No Preliminary Fit rule for this qualification'::text; RETURN;
    END IF;
    v_core := CASE WHEN jsonb_typeof(p_rule->'core_disciplines') = 'array' THEN ARRAY(SELECT jsonb_array_elements_text(p_rule->'core_disciplines')) END;
    v_rel := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_rule->'related_disciplines') = 'array'
                                                         THEN p_rule->'related_disciplines' ELSE '[]'::jsonb END));
    v_whose := CASE WHEN p_rule->>'source' = 'PROGRAMME' THEN v_p || '''s own rule'
                    ELSE 'the University''s default rule (no rule of its own for ' || v_p || ')' END;

    IF v_kind = 'A_LEVEL' THEN
        SELECT coalesce(array_agg(x.e->>'subject' ORDER BY x.o), '{}'), coalesce(array_agg(x.e->>'grade' ORDER BY x.o), '{}'),
               coalesce(array_agg((x.e->>'points')::int ORDER BY x.o), '{}'), coalesce(array_agg(admissions.subject_key(x.e->>'subject') ORDER BY x.o), '{}'),
               coalesce(array_agg(NOT admissions.de_no_grade(x.e->>'grade') ORDER BY x.o), '{}')
          INTO c_sub, c_grd, c_pts, c_key, c_has
          FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_award->'combination') = 'array' THEN p_award->'combination' ELSE '[]'::jsonb END)
               WITH ORDINALITY x(e, o);
        -- (a) what is counted: the listed subjects (each item's best), the programme's Direct Entry subjects, or every subject
        v_mode := CASE WHEN v_core IS NOT NULL THEN 'LIST'
                       WHEN jsonb_typeof(p_de_set) = 'array' AND jsonb_array_length(p_de_set) > 0 THEN 'SET'
                       ELSE 'ANY' END;
        IF v_mode = 'LIST' THEN
            FOR v_i IN 1 .. coalesce(array_length(v_core, 1), 0) LOOP
                v_items := v_items || btrim((regexp_split_to_array(btrim(v_core[v_i]), '\s*/\s*|\s+or\s+'))[1]);
                v_keys := ARRAY(SELECT admissions.subject_key(a.alt) FROM regexp_split_to_table(v_core[v_i], '\s*/\s*|\s+or\s+') a(alt) WHERE btrim(a.alt) <> '');
                v_pick := NULL;
                SELECT u.j INTO v_pick FROM generate_subscripts(c_sub, 1) u(j)
                 WHERE c_key[u.j] = ANY (v_keys) AND NOT (u.j = ANY (v_cnt))
                 ORDER BY c_pts[u.j] DESC NULLS LAST, u.j LIMIT 1;
                IF v_pick IS NULL THEN v_missing := v_missing || v_items[v_i]; ELSE v_cnt := v_cnt || v_pick; END IF;
            END LOOP;
        ELSIF v_mode = 'SET' THEN
            v_cnt := ARRAY(SELECT u.j FROM generate_subscripts(c_sub, 1) u(j)
                            WHERE EXISTS (SELECT 1 FROM jsonb_array_elements(p_de_set) ds(grp)
                                           WHERE c_key[u.j] IN (SELECT jsonb_array_elements_text(ds.grp->'keys')))
                            ORDER BY u.j);
        ELSE
            v_cnt := ARRAY(SELECT u.j FROM generate_subscripts(c_sub, 1) u(j) ORDER BY u.j);
        END IF;
        v_n := cardinality(v_cnt);

        IF v_mode = 'LIST' AND cardinality(v_missing) > 0 THEN
            -- (b) a subject missing decides, whatever the grades
            v_fit := 'Not relevant';
            v_reason := 'Does not offer ' || array_to_string(v_missing, ', ') || '; ' || v_p || ' DE asks for ' || admissions.de_and_list(v_items);
        ELSIF v_n = 0 AND v_mode = 'SET' THEN
            v_fit := 'Not relevant'; v_reason := 'None of the programme''s Direct Entry subjects offered';
        ELSIF v_n = 0 THEN
            v_fit := 'Check manually'; v_reason := 'No subjects recorded; check manually';
        ELSE
            -- (c) the grades of what is counted
            SELECT count(*) FILTER (WHERE c_has[u.j]) INTO v_graded_n FROM unnest(v_cnt) u(j);
            v_unread := (SELECT string_agg(c_sub[u.j] || ' ' || c_grd[u.j], ', ' ORDER BY u.j) FROM unnest(v_cnt) u(j) WHERE c_has[u.j] AND c_pts[u.j] IS NULL);
            v_comb := (SELECT string_agg(c_sub[u.j], ' / ' ORDER BY u.j) FROM unnest(v_cnt) u(j));
            v_failed := (SELECT string_agg(c_sub[u.j], ', ' ORDER BY u.j) FROM unnest(v_cnt) u(j) WHERE c_pts[u.j] < v_pmin);
            IF v_graded_n = 0 THEN
                v_fit := 'Check manually';
                v_reason := CASE WHEN v_mode = 'LIST' THEN array_to_string(v_items, '/') || ' combination is right, but no grades released in CAPS yet'
                                 ELSE 'Subject combination shown but no grades released in CAPS yet' END;
            ELSIF v_graded_n < v_n THEN
                v_fit := 'Check manually'; v_reason := 'Grades not all released in CAPS yet; check manually';
            ELSIF v_unread IS NOT NULL THEN
                v_fit := 'Check manually'; v_reason := 'Grade not read: ' || v_unread || '; check manually';
            ELSIF v_mode = 'SET' THEN
                -- (e) the set's own requirement: every group's `choose` passed is Relevant, one short Partly relevant
                v_need := 0; v_pr := 0; v_pp := 0;
                FOR v_grp IN SELECT (ds.grp->>'choose')::int AS choose, ARRAY(SELECT jsonb_array_elements_text(ds.grp->'keys')) AS keys
                               FROM jsonb_array_elements(p_de_set) ds(grp) LOOP
                    v_need := v_need + v_grp.choose;
                    v_pr := v_pr + least(v_grp.choose, (SELECT count(DISTINCT c_key[u.j]) FROM unnest(v_cnt) u(j) WHERE c_key[u.j] = ANY (v_grp.keys) AND c_pts[u.j] >= v_rmin)::int);
                    v_pp := v_pp + least(v_grp.choose, (SELECT count(DISTINCT c_key[u.j]) FROM unnest(v_cnt) u(j) WHERE c_key[u.j] = ANY (v_grp.keys) AND c_pts[u.j] >= v_pmin)::int);
                END LOOP;
                IF v_pr >= v_need THEN
                    v_fit := 'Relevant'; v_reason := 'Passed the programme''s Direct Entry subjects (' || v_comb || ')';
                ELSIF v_pp = v_need OR (v_need >= 2 AND v_pp = v_need - 1) THEN
                    v_fit := 'Partly relevant';
                    v_reason := 'Passed ' || v_pp || ' of the ' || v_need || ' Direct Entry subjects ' || v_p || ' asks for (' || v_comb || ')' || coalesce('; failed ' || v_failed, '');
                ELSE
                    v_fit := 'Not relevant';
                    v_reason := 'Short of the programme''s Direct Entry subjects: ' || v_pp || ' of ' || v_need || ' passed (' || v_comb || ')' || coalesce('; failed ' || v_failed, '');
                END IF;
            ELSE
                -- (d) the rule's pass counts
                v_pr := (SELECT count(*) FROM unnest(v_cnt) u(j) WHERE c_pts[u.j] >= v_rmin);
                v_pp := (SELECT count(*) FROM unnest(v_cnt) u(j) WHERE c_pts[u.j] >= v_pmin);
                IF v_mode = 'LIST' THEN
                    -- named in the order the rule lists them
                    v_names := ARRAY(SELECT c_sub[u.j] FROM unnest(v_cnt) WITH ORDINALITY u(j, o) ORDER BY u.o);
                    v_grades := ARRAY(SELECT c_grd[u.j] FROM unnest(v_cnt) WITH ORDINALITY u(j, o) ORDER BY u.o);
                    v_weak := (SELECT string_agg(c_sub[u.j], ', ' ORDER BY u.o) FROM unnest(v_cnt) WITH ORDINALITY u(j, o) WHERE c_pts[u.j] < v_rmin);
                    IF v_pr >= v_rpass THEN
                        v_fit := 'Relevant';
                        v_reason := 'Passed ' || admissions.de_and_list(v_names) || ' (' || array_to_string(v_grades, ', ') || '); points ' || coalesce(v_points::text, '-');
                    ELSIF v_pp >= v_ppass THEN
                        v_fit := 'Partly relevant';
                        v_reason := CASE WHEN v_failed IS NULL THEN 'Passed all ' || v_n || coalesce(' but with weak grade(s) in ' || v_weak, '')
                                         ELSE 'Passed ' || v_pp || ' of ' || v_n || '; failed ' || v_failed END
                                    || '; points ' || coalesce(v_points::text, '-');
                    ELSE
                        v_fit := 'Not relevant';
                        v_reason := coalesce('Failed ' || v_failed, 'Passed ' || v_pp || ' of ' || v_n) || '; points ' || coalesce(v_points::text, '-');
                    END IF;
                ELSE
                    -- no subjects named and no Direct Entry set: the passes only, the combination not checked
                    IF v_pr >= v_rpass THEN
                        v_fit := 'Relevant';
                        v_reason := CASE WHEN v_pr = v_n THEN 'Passed all ' || v_n || ' subjects (' || v_comb || ')'
                                         ELSE 'Passed ' || v_pr || ' of ' || v_n || ' subjects (' || v_comb || ')' END
                                    || '; combination not checked: no Direct Entry subject set for ' || v_p;
                    ELSIF v_pp >= v_ppass THEN
                        v_fit := 'Partly relevant';
                        v_reason := 'Passed ' || v_pp || ' of ' || v_n || coalesce('; failed ' || v_failed, ' (' || v_comb || ')');
                    ELSE
                        v_fit := 'Not relevant';
                        v_reason := CASE v_pp WHEN 0 THEN 'No A''Level pass' WHEN 1 THEN 'Only 1 A''Level pass' ELSE 'Only ' || v_pp || ' A''Level passes' END
                                    || coalesce('; failed ' || v_failed, '');
                    END IF;
                END IF;
            END IF;
        END IF;
        -- (f) the type CAPS left blank: good grades are checked by hand, poor ones say so
        IF v_basis = 'NOT_STATED' THEN
            IF v_fit IN ('Relevant', 'Partly relevant') THEN
                v_fit := 'Check manually';
                v_reason := 'Grades look good but qualification type/year missing in CAPS — ' || v_reason;
            ELSE
                v_reason := 'Qualification type/year missing in CAPS; ' || v_reason;
            END IF;
        END IF;
        RETURN QUERY SELECT v_fit, v_reason; RETURN;
    END IF;

    -- a degree, a diploma or an NCE: its discipline (an NCE's subjects as one) and its class (an NCE's grades)
    v_d := nullif(btrim(p_award->>'discipline'), '');
    v_c := CASE WHEN v_kind = 'NCE'
                THEN (SELECT string_agg(CASE WHEN admissions.de_no_grade(x.e->>'grade') THEN '—' ELSE x.e->>'grade' END, ', ' ORDER BY x.o)
                        FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_award->'combination') = 'array' THEN p_award->'combination' ELSE '[]'::jsonb END)
                             WITH ORDINALITY x(e, o))
                ELSE nullif(btrim(p_award->>'class'), '') END;
    v_k := CASE v_basis WHEN 'DEGREE' THEN 'Degree' WHEN 'DEGREE_FOREIGN' THEN 'Foreign degree' WHEN 'UNIVERSITY_DIPLOMA' THEN 'Diploma'
                        WHEN 'ND' THEN 'National Diploma' WHEN 'HND' THEN 'Higher National Diploma' WHEN 'NCE' THEN 'NCE' ELSE v_basis END;
    v_kd := v_k || coalesce(' in ' || v_d, '');
    v_a := CASE v_kind WHEN 'ND' THEN 'ND/HND' WHEN 'HND' THEN 'ND/HND' WHEN 'NCE' THEN 'NCE' WHEN 'UNIVERSITY_DIPLOMA' THEN 'University Diploma' ELSE 'degree' END;
    IF NOT coalesce((p_award->>'graded')::boolean, false) THEN
        RETURN QUERY SELECT 'Check manually'::text, v_kd || ': class not shown; check manually'; RETURN;
    END IF;
    IF v_points IS NULL THEN
        RETURN QUERY SELECT 'Check manually'::text, v_kd || ': class "' || coalesce(v_c, '') || '" not read; check manually'; RETURN;
    END IF;
    IF v_core IS NOT NULL AND v_d IS NULL THEN
        RETURN QUERY SELECT 'Check manually'::text, v_k || ' (' || coalesce(v_c, '') || '): discipline not recorded; check manually'; RETURN;
    END IF;
    v_named := admissions.de_names_programme(v_d, p_programme);
    v_match := CASE WHEN v_core IS NULL OR v_named OR EXISTS (SELECT 1 FROM unnest(v_core) i(item) WHERE admissions.de_discipline_matches(v_d, i.item)) THEN 'CORE'
                    WHEN EXISTS (SELECT 1 FROM unnest(v_rel) i(item) WHERE admissions.de_discipline_matches(v_d, i.item)) THEN 'RELATED'
                    ELSE 'OTHER' END;
    -- a match with neither threshold is read as any other discipline
    IF v_match = 'CORE' AND v_rmin IS NULL AND v_pmin IS NULL THEN v_match := 'OTHER'; END IF;
    IF v_match = 'RELATED' AND v_rrmin IS NULL AND v_rpmin IS NULL THEN v_match := 'OTHER'; END IF;
    IF v_match = 'CORE' THEN
        IF v_rmin IS NOT NULL AND v_points >= v_rmin THEN
            v_fit := 'Relevant';
            v_reason := CASE WHEN v_named THEN v_kd || ' at ' || v_c || '; directly related to the programme'
                             WHEN v_core IS NULL THEN v_kd || ' (' || v_c || '); any discipline accepted under ' || v_whose
                             ELSE v_kd || ' (' || v_c || '): a core discipline for ' || v_p || ' DE' END;
        ELSIF v_pmin IS NOT NULL AND v_points >= v_pmin AND v_rmin IS NULL THEN
            v_fit := 'Partly relevant';
            v_reason := CASE WHEN v_core IS NULL AND NOT v_named
                             THEN v_kd || ' (' || v_c || '); ' || v_a || ' acceptance for ' || v_p || ' DE must be confirmed by the Faculty'
                             ELSE v_kd || ' (' || v_c || '): directly related, but ' || v_a || ' acceptance for ' || v_p || ' DE must be confirmed by the Faculty' END;
        ELSIF v_pmin IS NOT NULL AND v_points >= v_pmin THEN
            v_fit := 'Partly relevant';
            v_reason := v_kd || ' but ' || v_c || '; below the usual '
                        || CASE WHEN v_kind = 'NCE' THEN v_rmin || ' of 15 points' ELSE admissions.de_threshold_words(v_kind, v_rmin) END || ' threshold for ' || v_p || ' DE';
        ELSE
            v_fit := 'Not relevant';
            v_reason := v_kd || ' but ' || v_c || '; below the '
                        || CASE WHEN v_kind = 'NCE' THEN coalesce(v_pmin, v_rmin) || ' of 15 points' ELSE admissions.de_threshold_words(v_kind, coalesce(v_pmin, v_rmin)) END
                        || ' minimum for ' || v_p || ' DE';
        END IF;
    ELSIF v_match = 'RELATED' THEN
        IF v_rrmin IS NOT NULL AND v_points >= v_rrmin THEN
            v_fit := 'Relevant'; v_reason := v_kd || ' (' || v_c || '): a related discipline for ' || v_p || ' DE';
        ELSIF v_rpmin IS NOT NULL AND v_points >= v_rpmin THEN
            v_fit := 'Partly relevant'; v_reason := v_kd || ' (' || v_c || '): a related discipline, not a core one for ' || v_p || ' DE';
        ELSE
            v_fit := 'Not relevant';
            v_reason := v_kd || ' but ' || v_c || '; a related discipline below the '
                        || CASE WHEN v_kind = 'NCE' THEN coalesce(v_rpmin, v_rrmin) || ' of 15 points' ELSE admissions.de_threshold_words(v_kind, coalesce(v_rpmin, v_rrmin)) END
                        || ' minimum for ' || v_p || ' DE';
        END IF;
    ELSE
        v_fit := coalesce(admissions.de_fit_label(v_other), 'Not relevant');
        v_reason := CASE v_other
                      WHEN 'RELEVANT' THEN v_kd || ' (' || v_c || '); accepted under ' || v_whose
                      WHEN 'PARTLY_RELEVANT' THEN v_kd || ' (' || v_c || '): not a core discipline for ' || v_p || ' DE'
                      WHEN 'CHECK_MANUALLY' THEN v_kd || ' (' || v_c || '): to be assessed by the Faculty for ' || v_p || ' DE'
                      ELSE v_kd || ' (' || v_c || '): not a discipline ' || v_p || ' DE accepts' END;
    END IF;
    -- a degree in the programme's own subject is noted, whatever its fit
    IF v_kind = 'DEGREE' AND v_named THEN
        v_reason := 'Already holds a degree in ' || v_d || ' (' || v_c || '); confirm why a second ' || v_p || ' degree is sought';
    END IF;
    RETURN QUERY SELECT v_fit, v_reason;
END $$;
COMMENT ON FUNCTION admissions.de_fit_of(jsonb, jsonb, jsonb, text) IS
  'V773: the Preliminary Fit of the qualification that counts (from admissions.de_award_scores: basis, kind, discipline, class, points, graded, combination) under the fit rule of its kind (admissions.de_fit_rules, with its source), the programme''s Direct Entry subject set ([{choose, keys}]) and the programme''s name — Relevant, Partly relevant, Not relevant or Check manually, with the reason in words, saying only what was checked. Reads no table; a guide only: nothing else reads it.';

-- ── the programme's O'Level subjects, and what the O'Level check requires ───────────────────────────────────────────────────────
CREATE FUNCTION admissions.de_olevel_set(p_session text, p_programme text)
RETURNS TABLE (ord integer, item text, need integer, member_keys text[])
LANGUAGE sql STABLE AS $$
    WITH pol AS (
        SELECT p.id FROM admissions.session_policy p WHERE p.session = p_session ORDER BY (p.state = 'IN_FORCE') DESC LIMIT 1),
    txt AS (
        SELECT lower(coalesce((SELECT pr.olevel_text FROM admissions.programme_rule pr
                                WHERE pr.policy_id = (SELECT pol.id FROM pol) AND pr.programme_code = p_programme), '')) AS t),
    its AS (
        SELECT DISTINCT ON (lower(x.item)) x.item, x.need, x.members,
               admissions.de_subject_keys((SELECT pol.id FROM pol), x.members, 'OLEVEL') AS member_keys
          FROM (SELECT btrim(regexp_replace(btrim(i.slot), '[.;:,]+$', '')) AS item, i.need, i.members
                  FROM admissions.rule_subject_group g CROSS JOIN LATERAL admissions.rule_items(g.id) i
                 WHERE g.policy_id = (SELECT pol.id FROM pol) AND g.programme_code = p_programme AND g.scope = 'OLEVEL') x
         ORDER BY lower(x.item), x.item),
    o AS (
        -- English Language, Mathematics, then the order the programme's O'Level requirement names them in, then by subject
        SELECT its.item, its.need, its.member_keys,
               CASE WHEN 'english language' = ANY (its.member_keys) THEN 0 WHEN 'mathematics' = ANY (its.member_keys) THEN 1 ELSE 2 END AS pri,
               (SELECT min(strpos(txt.t, btrim(regexp_replace(m.x, '[.;:,]+$', ''))))
                  FROM unnest(its.members) m(x), txt
                 WHERE btrim(regexp_replace(m.x, '[.;:,]+$', '')) <> '' AND strpos(txt.t, btrim(regexp_replace(m.x, '[.;:,]+$', ''))) > 0) AS pos
          FROM its)
    SELECT (row_number() OVER (ORDER BY o.pri, o.pos NULLS LAST, admissions.subject_key(o.item), o.item))::int, o.item, o.need, o.member_keys
      FROM o
    UNION ALL
    SELECT d.o, d.item, 1, ARRAY[d.k]
      FROM (VALUES (1, 'English Language', 'english language'), (2, 'Mathematics', 'mathematics')) d(o, item, k)
     WHERE NOT EXISTS (SELECT 1 FROM its)
     ORDER BY 1
$$;
COMMENT ON FUNCTION admissions.de_olevel_set(text, text) IS
  'V773: a programme''s O''Level subjects (its OLEVEL groups under the session''s policy) for the Direct Entry candidates workbook, one column each: the item as the rule writes it (a trailing full stop dropped), how many of its members it needs, and the subject keys that meet it (with the policy''s O''Level equivalences); English Language and Mathematics first, then in the order the programme''s O''Level requirement names them, then by subject; English Language and Mathematics where none is set.';

CREATE FUNCTION admissions.de_olevel_required(p_session text, p_programme text)
RETURNS TABLE (ord integer, item text, need integer, member_keys text[], max_rank integer)
LANGUAGE sql STABLE AS $$
    WITH pol AS (
        SELECT p.id FROM admissions.session_policy p WHERE p.session = p_session ORDER BY (p.state = 'IN_FORCE') DESC LIMIT 1),
    comp AS (
        SELECT c.subject, c.ord AS o FROM admissions.olevel_compulsory c WHERE c.session = p_session
        UNION ALL
        SELECT d.subject, d.o FROM (VALUES ('English Language', 1), ('Mathematics', 2)) d(subject, o)
         WHERE NOT EXISTS (SELECT 1 FROM admissions.olevel_compulsory c WHERE c.session = p_session)),
    ck AS (SELECT comp.subject, comp.o, admissions.subject_key(comp.subject) AS k FROM comp),
    lines AS (
        -- the session's compulsory credits, matched by their subject's key (English Language is not Literature in English); a pass
        -- where the programme accepts one
        SELECT 1 AS part, row_number() OVER (ORDER BY ck.o, ck.subject) AS n, ck.subject AS item, 1 AS need,
               admissions.de_subject_keys((SELECT pol.id FROM pol), ARRAY[ck.subject], 'OLEVEL') AS member_keys,
               CASE WHEN EXISTS (SELECT 1 FROM admissions.programme_olevel_allowance a
                                  WHERE a.policy_id = (SELECT pol.id FROM pol) AND a.programme_code = p_programme
                                    AND admissions.subject_key(a.subject) = ck.k) THEN 8 ELSE 6 END AS max_rank
          FROM ck
        UNION ALL
        -- then the programme's required subjects, less one that is a compulsory subject again
        SELECT 2, row_number() OVER (ORDER BY x.item), x.item, x.need,
               admissions.de_subject_keys((SELECT pol.id FROM pol), x.members, 'OLEVEL'), x.max_rank
          FROM (SELECT btrim(regexp_replace(btrim(i.slot), '[.;:,]+$', '')) AS item, i.need, i.members,
                       admissions.grade_rank(coalesce(g.min_grade, 'C6')) AS max_rank
                  FROM admissions.rule_subject_group g CROSS JOIN LATERAL admissions.rule_items(g.id) i
                 WHERE g.policy_id = (SELECT pol.id FROM pol) AND g.programme_code = p_programme AND g.scope = 'OLEVEL_REQUIRED'
                   AND NOT (cardinality(i.members) = 1 AND admissions.subject_key(i.members[1]) IN (SELECT ck.k FROM ck))) x)
    SELECT (row_number() OVER (ORDER BY l.part, l.n))::int, l.item, l.need, l.member_keys, l.max_rank
      FROM lines l
     ORDER BY l.part, l.n
$$;
COMMENT ON FUNCTION admissions.de_olevel_required(text, text) IS
  'V773: what the Direct Entry candidates workbook''s O''Level check requires of a programme — the session''s compulsory subjects (admissions.olevel_compulsory by its order; English Language and Mathematics where none is stated), each matched by its subject key and the policy''s equivalences, a credit (a pass where the programme accepts one); then the programme''s OLEVEL_REQUIRED items at their minimum grade, less one naming a compulsory subject alone. The eligibility engine keeps its own reading.';

-- ── the rows of the Direct Entry candidates workbook ────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.de_candidates(p_session text, p_programme text DEFAULT NULL,
                                         p_on date DEFAULT ((now() AT TIME ZONE 'Africa/Lagos')::date))
RETURNS TABLE (rank integer, list_no integer, programme_code text, programme text,
               jamb_reg_no text, jamb_key text, name text, state_of_origin text, lga text, sex text,
               caps_qualification text, caps_grade integer, has_five_credits boolean, is_cleared text, status text,
               age integer, age_qualified boolean, admission_category text, registered boolean,
               award_id uuid, basis text, qualification_type text, discipline text, grades text,
               points integer, max_points integer, score numeric, class_points text, institution text, awarded_year integer, exam_no text,
               fit text, reason text, other_notes text,
               olevel_results text, olevel_sittings text, sittings integer, olevel_grades jsonb,
               key_credits integer, key_of integer, total_credits integer, olevel_check text, olevel_check_kind text)
LANGUAGE sql STABLE AS $$
    WITH pol AS MATERIALIZED (
        SELECT p.id FROM admissions.session_policy p WHERE p.session = p_session ORDER BY (p.state = 'IN_FORCE') DESC LIMIT 1),
    rws AS MATERIALIZED (
        -- everyone on JAMB's live Direct Entry list of the programme (its code, or an alias of it in force), placed on the programme
        -- the code stands for
        SELECT x.jamb_reg_no, x.jamb_key, x.surname, x.other_names, x.state_of_origin, x.lga, x.sex, x.raw->>'IsDECleared' AS cleared_raw,
               admissions.de_programme_of(x.jamb_code) AS code
          FROM admissions.caps_row_live x
         WHERE x.session = p_session AND x.entry_mode = 'DIRECT_ENTRY'
           AND (p_programme IS NULL OR x.jamb_code = ANY (admissions.de_programme_codes(p_programme)))),
    keys AS MATERIALIZED (SELECT ARRAY(SELECT r.jamb_key FROM rws r) AS k),
    progs AS MATERIALIZED (
        SELECT DISTINCT r.code, pg.name FROM rws r LEFT JOIN ref.programme pg ON pg.code = r.code),
    prule AS MATERIALIZED (
        SELECT g.code, coalesce(pr.olevel_credits, 5) AS credits, greatest(1, coalesce(pr.olevel_sittings, 2)) AS allowed
          FROM progs g LEFT JOIN admissions.programme_rule pr ON pr.policy_id = (SELECT pol.id FROM pol) AND pr.programme_code = g.code),
    oset AS MATERIALIZED (SELECT g.code, s.ord, s.item, s.need, s.member_keys FROM progs g CROSS JOIN LATERAL admissions.de_olevel_set(p_session, g.code) s),
    oreq AS MATERIALIZED (SELECT g.code, s.ord, s.item, s.need, s.member_keys, s.max_rank FROM progs g CROSS JOIN LATERAL admissions.de_olevel_required(p_session, g.code) s),
    deset AS MATERIALIZED (
        SELECT g.code,
               coalesce((SELECT jsonb_agg(jsonb_build_object('choose', sg.choose,
                                                             'keys', to_jsonb(admissions.de_subject_keys(sg.policy_id,
                                                                     ARRAY(SELECT m.x FROM admissions.rule_items(sg.id) i CROSS JOIN unnest(i.members) m(x)), 'UTME')))
                                          ORDER BY sg.id)
                           FROM admissions.rule_subject_group sg
                          WHERE sg.policy_id = (SELECT pol.id FROM pol) AND sg.programme_code = g.code AND sg.scope = 'DE'), '[]'::jsonb) AS grps
          FROM progs g),
    frules AS MATERIALIZED (SELECT g.code, f.kind, f.rule FROM progs g CROSS JOIN LATERAL admissions.de_fit_rules((SELECT pol.id FROM pol), g.code) f),
    cand AS MATERIALIZED (
        SELECT c.jamb_key, c.offer_state, a.id AS app_id, a.decision, a.decision_basis
          FROM admissions.candidate c LEFT JOIN admissions.application a ON a.candidate_id = c.id
         WHERE c.session = p_session AND c.jamb_key = ANY ((SELECT keys.k FROM keys)::text[])),
    capsv AS MATERIALIZED (
        SELECT v.* FROM admissions.de_caps_value v WHERE v.session = p_session AND v.jamb_key = ANY ((SELECT keys.k FROM keys)::text[])),
    ja AS MATERIALIZED (
        SELECT DISTINCT ON (upper(btrim(j.jamb_reg_no))) upper(btrim(j.jamb_reg_no)) AS jamb_key, j.status, j.category
          FROM admissions.jamb_admission j WHERE j.session = p_session
         ORDER BY upper(btrim(j.jamb_reg_no)), j.loaded_at DESC),
    dob AS MATERIALIZED (
        SELECT DISTINCT ON (t.jamb_key) t.jamb_key, platform.read_date(t.payload->>'dob') AS dob
          FROM admissions.attachment t
         WHERE t.session = p_session AND t.kind = 'DATE_OF_BIRTH' AND t.jamb_key = ANY ((SELECT keys.k FROM keys)::text[])
         ORDER BY t.jamb_key, t.arrived_at DESC),
    -- the O'Level: the sittings (one sitting on two attachments is one: V100's identity), each grade read once
    sit0 AS MATERIALIZED (
        SELECT st.id, st.jamb_key, st.exam_body, st.exam_year, st.exam_number, st.ord
          FROM admissions.olevel_sitting st WHERE st.session = p_session AND st.jamb_key = ANY ((SELECT keys.k FROM keys)::text[])),
    g0 AS MATERIALIZED (
        SELECT g.sitting_id, g.subject, g.grade, admissions.subject_key(g.subject) AS key, admissions.grade_rank(g.grade) AS rnk,
               admissions.olevel_awaiting_grade(g.grade) AS awaiting
          FROM admissions.olevel_grade g WHERE g.sitting_id IN (SELECT s.id FROM sit0 s)),
    gsig AS (
        SELECT g.sitting_id, string_agg(g.subject || '=' || g.grade, ',' ORDER BY g.subject, g.grade) AS gs FROM g0 g GROUP BY g.sitting_id),
    sig AS MATERIALIZED (
        SELECT s.id, s.jamb_key, s.exam_body, s.exam_year, s.exam_number, s.ord,
               coalesce(nullif(upper(btrim(s.exam_number)), ''), s.exam_body || '|' || coalesce(s.exam_year, '') || '|' || coalesce(gg.gs, '')) AS sg
          FROM sit0 s LEFT JOIN gsig gg ON gg.sitting_id = s.id),
    dsit AS MATERIALIZED (
        SELECT DISTINCT ON (s.jamb_key, s.sg) s.jamb_key, s.sg, s.exam_body, s.exam_year, s.exam_number, s.ord
          FROM sig s ORDER BY s.jamb_key, s.sg, s.exam_year NULLS LAST, s.ord),
    gr AS MATERIALIZED (
        SELECT s.jamb_key, s.sg, g.subject, g.grade, g.key, g.rnk, g.awaiting FROM g0 g JOIN sig s ON s.id = g.sitting_id),
    best AS MATERIALIZED (
        -- the best grade of each subject over every sitting
        SELECT DISTINCT ON (r.jamb_key, r.key) r.jamb_key, r.key, btrim(r.subject) AS subject, upper(btrim(r.grade)) AS grade, r.rnk
          FROM gr r WHERE r.key IS NOT NULL ORDER BY r.jamb_key, r.key, r.rnk, r.subject),
    ol AS MATERIALIZED (
        SELECT d.jamb_key, count(*)::int AS n,
               string_agg(CASE WHEN d.exam_body IN ('WAEC', 'NECO', 'NABTEB') THEN d.exam_body ELSE 'Others' END
                          || coalesce(' ' || nullif(btrim(d.exam_year), ''), '') || coalesce(' (' || nullif(btrim(d.exam_number), '') || ')', ''),
                          '; ' ORDER BY d.exam_year NULLS LAST, d.ord, d.sg) AS sittings_text
          FROM dsit d GROUP BY d.jamb_key),
    res AS MATERIALIZED (
        SELECT b.jamb_key, string_agg(b.subject || ': ' || b.grade, '; ' ORDER BY lower(b.subject), b.key) AS results,
               (count(*) FILTER (WHERE b.rnk <= 6))::int AS total_credits
          FROM best b GROUP BY b.jamb_key),
    -- the credits within the sittings a programme allows: the best single sitting, the best pair
    cred AS MATERIALIZED (SELECT DISTINCT r.jamb_key, r.sg, r.key FROM gr r WHERE r.rnk <= 6 AND r.key IS NOT NULL),
    one AS (
        SELECT c.jamb_key, max(c.n)::int AS c_one FROM (SELECT x.jamb_key, x.sg, count(*) AS n FROM cred x GROUP BY x.jamb_key, x.sg) c GROUP BY c.jamb_key),
    two AS (
        SELECT q.jamb_key, max(q.n)::int AS c_two
          FROM (SELECT a.jamb_key, a.sg AS s1, b.sg AS s2, count(DISTINCT c.key) AS n
                  FROM dsit a JOIN dsit b ON b.jamb_key = a.jamb_key AND b.sg >= a.sg
                  JOIN cred c ON c.jamb_key = a.jamb_key AND c.sg IN (a.sg, b.sg)
                 GROUP BY a.jamb_key, a.sg, b.sg) q
         GROUP BY q.jamb_key),
    -- a grade for each of the programme's O'Level subjects
    itemg AS MATERIALIZED (
        SELECT r.jamb_key, o.ord, o.item, o.need,
               (array_agg(b.grade ORDER BY b.rnk, b.grade) FILTER (WHERE b.key IS NOT NULL))[1] AS grade,
               count(DISTINCT b.key) FILTER (WHERE b.rnk <= 6) >= o.need AS credit
          FROM rws r JOIN oset o ON o.code = r.code
          LEFT JOIN best b ON b.jamb_key = r.jamb_key AND b.key = ANY (o.member_keys)
         GROUP BY r.jamb_key, o.ord, o.item, o.need),
    items AS MATERIALIZED (
        SELECT i.jamb_key,
               jsonb_agg(jsonb_build_object('subject', i.item,
                                            'grade', CASE WHEN l.n IS NULL THEN NULL ELSE coalesce(i.grade, '—') END,
                                            'credit', l.n IS NOT NULL AND i.credit) ORDER BY i.ord) AS grades,
               (count(*) FILTER (WHERE l.n IS NOT NULL AND i.credit))::int AS key_credits, count(*)::int AS key_of
          FROM itemg i LEFT JOIN ol l ON l.jamb_key = i.jamb_key
         GROUP BY i.jamb_key),
    -- what the check requires: met, awaiting
    reqg AS MATERIALIZED (
        SELECT r.jamb_key, q.ord, q.item,
               count(DISTINCT b.key) FILTER (WHERE b.rnk <= q.max_rank) >= q.need AS met
          FROM rws r JOIN oreq q ON q.code = r.code
          LEFT JOIN best b ON b.jamb_key = r.jamb_key AND b.key = ANY (q.member_keys)
         GROUP BY r.jamb_key, q.ord, q.item, q.need),
    awk AS MATERIALIZED (SELECT DISTINCT r.jamb_key, r.key FROM gr r WHERE r.awaiting AND r.key IS NOT NULL),
    reqaw AS MATERIALIZED (
        SELECT r.jamb_key, q.ord, bool_or(a.key IS NOT NULL) AS awaiting
          FROM rws r JOIN oreq q ON q.code = r.code
          LEFT JOIN awk a ON a.jamb_key = r.jamb_key AND a.key = ANY (q.member_keys)
         GROUP BY r.jamb_key, q.ord),
    req AS MATERIALIZED (
        SELECT g.jamb_key,
               string_agg(g.item, ', ' ORDER BY g.ord) FILTER (WHERE NOT g.met AND w.awaiting) AS awaiting_items,
               string_agg(g.item, ', ' ORDER BY g.ord) FILTER (WHERE NOT g.met) AS missing_items,
               array_agg(g.item ORDER BY g.ord) AS all_items
          FROM reqg g JOIN reqaw w ON w.jamb_key = g.jamb_key AND w.ord = g.ord
         GROUP BY g.jamb_key),
    -- the qualifications recorded, the one that counts, the others
    sc AS MATERIALIZED (SELECT * FROM admissions.de_award_scores(p_session, (SELECT keys.k FROM keys))),
    also AS MATERIALIZED (
        SELECT s.jamb_key,
               string_agg(admissions.de_basis_label(s.basis) || CASE WHEN s.score IS NULL THEN ' (no score)' ELSE ' (' || s.score::text || '%)' END,
                          ', ' ORDER BY s.score DESC NULLS LAST, s.basis) AS others
          FROM sc s WHERE NOT s.counts AND s.captured GROUP BY s.jamb_key),
    base AS (
        SELECT r.jamb_reg_no, r.jamb_key, r.surname, r.other_names, r.state_of_origin, r.lga, r.sex, r.cleared_raw, r.code,
               pg.name AS programme_name, pu.credits, pu.allowed,
               cv.qualification AS cv_qualification, cv.caps_grade AS cv_grade, cv.has_five_credits AS cv_five, cv.is_cleared AS cv_cleared,
               cv.status AS cv_status, cv.age AS cv_age, cv.age_qualified AS cv_age_qualified, cv.admission_category AS cv_category,
               cd.offer_state, cd.app_id, cd.decision, cd.decision_basis, j.status AS ja_status, j.category AS ja_category, d.dob,
               l.n AS n_sit, l.sittings_text, rs.results, rs.total_credits, o1.c_one, o2.c_two,
               it.grades AS ol_grades, it.key_credits, it.key_of, rq.awaiting_items, rq.missing_items, rq.all_items,
               a.award_id, a.basis, a.kind, a.discipline, a.award_class, a.grades, a.points, a.max_points, a.score, a.class_points,
               a.institution, a.awarded_year, a.exam_no, a.graded, a.combination, al.others, ds.grps AS de_set, fr.rule
          FROM rws r
          LEFT JOIN progs pg ON pg.code = r.code
          LEFT JOIN prule pu ON pu.code = r.code
          LEFT JOIN capsv cv ON cv.jamb_key = r.jamb_key
          LEFT JOIN cand cd ON cd.jamb_key = r.jamb_key
          LEFT JOIN ja j ON j.jamb_key = r.jamb_key
          LEFT JOIN dob d ON d.jamb_key = r.jamb_key
          LEFT JOIN ol l ON l.jamb_key = r.jamb_key
          LEFT JOIN res rs ON rs.jamb_key = r.jamb_key
          LEFT JOIN one o1 ON o1.jamb_key = r.jamb_key
          LEFT JOIN two o2 ON o2.jamb_key = r.jamb_key
          LEFT JOIN items it ON it.jamb_key = r.jamb_key
          LEFT JOIN req rq ON rq.jamb_key = r.jamb_key
          LEFT JOIN sc a ON a.jamb_key = r.jamb_key AND a.counts
          LEFT JOIN also al ON al.jamb_key = r.jamb_key
          LEFT JOIN deset ds ON ds.code = r.code
          LEFT JOIN frules fr ON fr.code = r.code AND fr.kind = a.kind),
    h AS (
        SELECT b.*,
               coalesce(b.cv_five,
                        CASE WHEN b.n_sit IS NULL THEN false
                             ELSE CASE WHEN b.n_sit <= b.allowed OR b.allowed >= 3 THEN coalesce(b.total_credits, 0)
                                       WHEN b.allowed = 1 THEN coalesce(b.c_one, 0)
                                       ELSE coalesce(b.c_two, 0) END >= b.credits END) AS five,
               CASE WHEN b.cv_cleared IS NOT NULL THEN CASE WHEN b.cv_cleared THEN 'CLEARED' ELSE 'NOT CLEARED' END
                    WHEN btrim(b.cleared_raw) = '1' THEN 'CLEARED'
                    WHEN btrim(b.cleared_raw) = '0' THEN 'NOT CLEARED' END AS cleared,
               b.app_id IS NOT NULL AS is_registered,
               CASE WHEN b.n_sit IS NULL THEN 'NONE'
                    WHEN b.awaiting_items IS NOT NULL OR b.n_sit > b.allowed OR b.missing_items IS NOT NULL
                         OR coalesce(b.total_credits, 0) < b.credits THEN 'PROBLEM'
                    ELSE 'PASS' END AS check_kind
          FROM base b),
    fitted AS (
        SELECT h.*, f.fit AS fit_, f.reason AS reason_
          FROM h
         CROSS JOIN LATERAL admissions.de_fit_of(
                 CASE WHEN h.award_id IS NOT NULL
                      THEN jsonb_build_object('basis', h.basis, 'kind', h.kind, 'discipline', h.discipline, 'class', h.award_class,
                                              'points', h.points, 'graded', h.graded, 'combination', h.combination) END,
                 h.rule, h.de_set, h.programme_name) f)
    SELECT (row_number() OVER (PARTITION BY f.code ORDER BY f.score DESC NULLS LAST, (f.award_id IS NULL), f.surname, f.other_names, f.jamb_reg_no))::int,
           (row_number() OVER (PARTITION BY f.code ORDER BY upper(concat_ws(' ', f.surname, f.other_names)), f.jamb_reg_no))::int,
           f.code, f.programme_name,
           f.jamb_reg_no, f.jamb_key, concat_ws(' ', f.surname, f.other_names), f.state_of_origin, f.lga, f.sex,
           f.cv_qualification, f.cv_grade, f.five, f.cleared,
           coalesce(f.cv_status, f.ja_status,
                    CASE f.offer_state WHEN 'ADMITTED' THEN 'Admitted' WHEN 'ACCEPTED' THEN 'Admitted (accepted)' WHEN 'DECLINED' THEN 'Offer declined'
                                       WHEN 'LAPSED' THEN 'Offer lapsed' WHEN 'WITHDRAWN' THEN 'Offer withdrawn' ELSE 'Not Admitted' END),
           coalesce(f.cv_age, CASE WHEN f.dob IS NOT NULL AND f.dob <= p_on THEN date_part('year', age(p_on::timestamp, f.dob::timestamp))::int END),
           f.cv_age_qualified,
           coalesce(f.cv_category, f.ja_category,
                    CASE WHEN f.decision = 'OFFERED' THEN
                         CASE f.decision_basis WHEN 'NM' THEN 'National Merit' WHEN 'SM' THEN 'State Merit' WHEN 'ELG' THEN 'Equality of LG'
                                               WHEN 'LOCALITY' THEN 'Locality' WHEN 'PLWD' THEN 'PLWD' WHEN 'OTHER' THEN 'Other' END END),
           f.is_registered,
           f.award_id, f.basis, admissions.de_basis_label(f.basis), f.discipline, f.grades,
           f.points, f.max_points, f.score, f.class_points,
           CASE WHEN nullif(btrim(f.institution), '') IS NOT NULL THEN btrim(f.institution)
                WHEN f.award_id IS NOT NULL THEN
                     CASE WHEN strpos(coalesce(f.exam_no, ''), '/') > 0 AND btrim(split_part(f.exam_no, '/', 1)) ~ '^[A-Za-z]+$'
                          THEN 'Not shown (exam no. starts "' || upper(btrim(split_part(f.exam_no, '/', 1))) || '")'
                          ELSE 'Not shown in CAPS' END END,
           f.awarded_year, f.exam_no,
           f.fit_, f.reason_,
           nullif(concat_ws('; ',
               CASE WHEN f.basis = 'NOT_STATED' THEN 'Qualification type and exam year blank in CAPS; verify certificate' END,
               CASE WHEN f.basis = 'DEGREE_FOREIGN' THEN 'Foreign degree: equivalence to be confirmed' END,
               CASE WHEN f.five = false THEN 'O''Level ' || f.credits || ' credits not confirmed' END,
               CASE WHEN f.cleared = 'NOT CLEARED' THEN 'Candidate NOT CLEARED in CAPS' END,
               CASE WHEN NOT f.is_registered THEN 'Not registered on the portal' END,
               CASE WHEN f.others IS NOT NULL THEN 'Also recorded: ' || f.others END), ''),
           f.results, f.sittings_text, coalesce(f.n_sit, 0), f.ol_grades,
           CASE WHEN f.n_sit IS NULL THEN 0 ELSE coalesce(f.key_credits, 0) END, coalesce(f.key_of, 0), coalesce(f.total_credits, 0),
           CASE WHEN f.n_sit IS NULL THEN 'No O''Level on record: candidate must upload/verify results'
                WHEN f.awaiting_items IS NOT NULL THEN 'Awaiting result (A/R) in ' || f.awaiting_items
                WHEN f.n_sit > f.allowed THEN 'Credits spread over ' || f.n_sit || ' sittings (max ' || f.allowed || ' allowed)'
                WHEN f.missing_items IS NOT NULL THEN 'No credit in ' || f.missing_items
                WHEN coalesce(f.total_credits, 0) < f.credits
                     THEN 'Only ' || coalesce(f.total_credits, 0) || CASE WHEN coalesce(f.total_credits, 0) = 1 THEN ' credit' ELSE ' credits' END
                          || '; ' || f.credits || ' required'
                ELSE 'Credits in ' || admissions.de_and_list(f.all_items) || ' (' || f.n_sit || CASE WHEN f.n_sit = 1 THEN ' sitting)' ELSE ' sittings)' END
           END,
           f.check_kind
      FROM fitted f
     ORDER BY f.code, 1
$$;
COMMENT ON FUNCTION admissions.de_candidates(text, text, date) IS
  'V773: the rows of the Direct Entry candidates workbook — everyone on JAMB''s live Direct Entry list for the programme (by JAMB''s code, through the programme aliases; NULL for every programme), registered on the portal or not: CAPS''s values as the last upload read them, else the portal''s (IsCleared from the list, the age from the date of birth on p_on, Has 5 Credits from the O''Level within the sittings allowed, the status from JAMB''s admission list or the offer, the category from JAMB or the decision), the qualification that counts (admissions.de_award_scores) with its points, maximum and score, its Preliminary Fit (admissions.de_fit_of, a guide only), the other notes, and the O''Level held with a grade for each of the programme''s O''Level subjects and the check in words. Ranked within the programme by score, ties by name, the unscored after, the unrecorded last; list_no the candidate''s place on the list as CAPS shows it (alphabetical).';

-- ── V764's template, ranked by score (decision 2) ───────────────────────────────────────────────────────────────────────────────
DROP FUNCTION admissions.de_template(text, text);
CREATE FUNCTION admissions.de_template(p_session text, p_programme text DEFAULT NULL)
RETURNS TABLE (rank integer, app_id uuid, application_no text, jamb_reg_no text, jamb_key text, surname text, other_names text,
               sex text, state_of_origin text, lga text, programme text, programme_code text, entry_level integer,
               qualification text, institution text, awarded_year integer, subjects jsonb, other_qualifications text,
               points integer, points_group integer, unread_grades text, de_status text, olevel_uploaded boolean, olevel_missing text,
               english text, mathematics text, sittings integer,
               recorded_decision text, decision text, decision_basis text, decision_note text, released boolean,
               qualified boolean, reason text, max_points integer, score numeric)
LANGUAGE sql STABLE AS $$
    WITH pol AS (
        SELECT p.id FROM admissions.session_policy p WHERE p.session = p_session AND p.state = 'IN_FORCE'),
    prog AS (
        SELECT admissions.candidate_programme_code(p_programme) AS code),
    app AS (
        -- V773: the candidate's programme read as its code (V769), on both sides of the filter; a text no programme carries is still
        -- listed under that text, as V764 listed it ("Programme not on the University's list of programmes")
        SELECT a.id, a.application_no, c.jamb_reg_no, c.jamb_key, c.surname, c.other_names, c.programme, c.entry_level,
               coalesce(r.sex, c.sex) AS sex, r.state_of_origin, r.lga, a.submitted_at,
               admissions.candidate_programme_code(c.programme) AS code,
               (SELECT x.entry_mode FROM admissions.caps_row_live x WHERE x.session = a.session AND x.jamb_reg_no = c.jamb_reg_no
                 ORDER BY (x.entry_mode = 'DIRECT_ENTRY') DESC LIMIT 1) AS live_mode,
               a.decision, a.decision_basis, a.decision_note, a.decision_released_at IS NOT NULL AS released
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE a.session = p_session AND c.entry_mode = 'DIRECT_ENTRY'
           AND (p_programme IS NULL OR c.programme = p_programme
                OR admissions.candidate_programme_code(c.programme) = (SELECT prog.code FROM prog))),
    sc AS MATERIALIZED (
        -- every qualification of the listed applicants, scored on its own scale (admissions.de_award_scores)
        SELECT * FROM admissions.de_award_scores(p_session, ARRAY(SELECT app.jamb_key FROM app))),
    best AS (
        -- the qualification that counts: the highest score of those captured
        SELECT s.* FROM sc s WHERE s.counts AND s.captured),
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
        SELECT app.*, b.basis, b.institution, b.awarded_year, b.subjects AS subj, b.points AS pts,
               CASE WHEN b.award_id IS NULL THEN NULL WHEN b.kind = 'A_LEVEL' THEN 1 ELSE 2 END AS grp,
               b.max_points AS mx, b.score AS sco,
               -- the grades not read on every qualification recorded, each by its qualification (one that does not count may be
               -- the one a misread grade kept from counting)
               (SELECT string_agg(CASE o.basis WHEN 'A_LEVEL' THEN 'A-Level' ELSE o.basis END || ': ' || o.unread, '; ' ORDER BY o.score DESC NULLS LAST, o.basis)
                  FROM sc o WHERE o.jamb_key = app.jamb_key AND o.unread IS NOT NULL) AS unread_all,
               (SELECT string_agg(CASE o.basis WHEN 'A_LEVEL' THEN 'A-Level' ELSE o.basis END || coalesce(' ' || o.awarded_year, '') || ' ('
                                  || (SELECT string_agg(e->>'subject' || coalesce(' ' || (e->>'grade'), ''), ', ') FROM jsonb_array_elements(o.subjects) e) || ')',
                                  '; ' ORDER BY o.score DESC NULLS LAST, o.basis)
                  FROM sc o WHERE o.jamb_key = app.jamb_key AND o.captured AND o.award_id IS DISTINCT FROM b.award_id) AS others,
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
    SELECT (row_number() OVER (PARTITION BY coalesce(r.code, r.programme)
                               ORDER BY (r.basis IS NULL), r.sco DESC NULLS LAST, r.surname, r.other_names, r.jamb_reg_no))::int,
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
           r.released, r.why IS NULL, r.why,
           r.mx, r.sco
      FROM reasoned r
     ORDER BY coalesce(r.code, r.programme), 1
$$;
COMMENT ON FUNCTION admissions.de_template(text, text) IS
    'V773: the rows of the Direct Entry admission template (V764) for a programme (by name or code; NULL for every programme): every registered Direct Entry applicant, ranked within the programme by the score of the qualification that counts (its points as a percentage of its own maximum, admissions.de_award_scores — every qualification together, the highest score counting; ties by name; no qualification captured last), with the qualification, its subjects and grades (a degree or diploma its discipline and class), the points, the maximum and the score, the grades not read, the other qualifications, the Direct Entry requirement''s verdict (NO_RULE, UNVERIFIED, MET, SHORT), the O''Level English and Mathematics and compulsory credits, whether qualified and the reasons if not, the recorded decision and the template''s (OFFERED merit list, WAITING other qualified, NOT_OFFERED non-qualified).';

-- ── V200's screening: a degree or diploma is a captured award, and the candidate's programme is read as its code ────────────────
CREATE OR REPLACE FUNCTION admissions.de_screening(p_session text, p_programme text)
RETURNS TABLE (app_id uuid, jamb_reg_no text, jamb_key text, surname text, other_names text,
               entry_level int, has_data boolean, meets_de boolean, status text)
LANGUAGE sql STABLE AS $$
    WITH has_rule AS (
        SELECT EXISTS (SELECT 1 FROM admissions.rule_subject_group g
                        WHERE g.policy_id = (admissions.policy_in_force(p_session)).id
                          AND g.programme_code = p_programme AND g.scope = 'DE') AS v)
    SELECT a.id AS app_id, c.jamb_reg_no, c.jamb_key, c.surname, c.other_names, c.entry_level,
           EXISTS (SELECT 1 FROM admissions.de_award d
                    WHERE d.session = p_session AND d.jamb_key = c.jamb_key
                      AND (nullif(btrim(d.discipline), '') IS NOT NULL OR nullif(btrim(d.award_class), '') IS NOT NULL
                           OR EXISTS (SELECT 1 FROM admissions.de_award_subject ds WHERE ds.award_id = d.id))) AS has_data,
           admissions.de_meets_combination(p_session, c.jamb_key, p_programme) AS meets_de,
           CASE
             WHEN NOT (SELECT v FROM has_rule) THEN 'NO_RULE'
             WHEN NOT EXISTS (SELECT 1 FROM admissions.de_award d
                               WHERE d.session = p_session AND d.jamb_key = c.jamb_key
                                 AND (nullif(btrim(d.discipline), '') IS NOT NULL OR nullif(btrim(d.award_class), '') IS NOT NULL
                                      OR EXISTS (SELECT 1 FROM admissions.de_award_subject ds WHERE ds.award_id = d.id))) THEN 'UNVERIFIED'
             WHEN admissions.de_meets_combination(p_session, c.jamb_key, p_programme) THEN 'MET'
             ELSE 'SHORT'
           END AS status
      FROM admissions.application a
      JOIN admissions.candidate c ON c.id = a.candidate_id
      JOIN admissions.caps_row_live x ON x.session = a.session AND x.jamb_reg_no = c.jamb_reg_no
     WHERE a.session = p_session
       AND admissions.candidate_programme_code(c.programme) = p_programme
       AND a.submitted_at IS NOT NULL
       AND x.entry_mode = 'DIRECT_ENTRY'
     ORDER BY c.surname, c.other_names
$$;
COMMENT ON FUNCTION admissions.de_screening(text, text) IS
  'V773: per-programme Direct Entry screening (V200) — each submitted Direct Entry applicant of the programme (the candidate''s programme read as its code, admissions.candidate_programme_code) with the DE subject gate''s verdict (MET / SHORT / UNVERIFIED / NO_RULE); a qualification is captured when it has subjects, or (a degree or diploma) a discipline or a class. Screening-only — it does not gate the offer decision.';

-- ── V268's evaluator: a degree or diploma holder is not read as having no award where the programme has a Direct Entry set ─────
CREATE OR REPLACE FUNCTION admissions.evaluate_programme(p_session text, p_jamb_key text, p_programme text, p_entry_mode text)
RETURNS TABLE (result text, checks jsonb, reasons text[])
LANGUAGE plpgsql STABLE AS $$
DECLARE pol admissions.session_policy; pr admissions.programme_rule; g ref.programme; v_checks jsonb := '[]'::jsonb; v_best jsonb; v_best_met int := -1; v_met int;
        v_key text := upper(btrim(p_jamb_key)); sit uuid[]; combo uuid[]; i int; j int; n int; allowed int; c jsonb; v_quota int; v_taken int; v_closed text;
        cand text[]; grp record; it record; v_have int; v_agg int; v_req int; v_fac int; v_load int; v_prog_cut int; v_status text; ok boolean; v_res text;
        v_unverified boolean := false; v_failed boolean := false; v_reasons text[] := ARRAY[]::text[]; v_add text;
        v_class text;
BEGIN
    SELECT * INTO g FROM ref.programme WHERE code = p_programme;
    IF g.code IS NULL THEN
        RETURN QUERY SELECT 'NOT_ELIGIBLE'::text, jsonb_build_array(jsonb_build_object('kind','PROGRAMME','label','Programme','requirement','A programme the University runs','candidate',p_programme,'status','NOT_MET','mandatory',true)), ARRAY['No such programme']::text[]; RETURN;
    END IF;
    SELECT * INTO pol FROM admissions.session_policy p WHERE p.session = p_session ORDER BY (p.state = 'IN_FORCE') DESC LIMIT 1;
    IF pol.id IS NULL THEN
        RETURN QUERY SELECT 'UNVERIFIED'::text, jsonb_build_array(jsonb_build_object('kind','POLICY','label','Admission settings','requirement','Settings for ' || p_session,'candidate','None exist','status','UNVERIFIED','mandatory',true)), ARRAY['No admission settings exist for ' || p_session]::text[]; RETURN;
    END IF;
    IF pol.state <> 'IN_FORCE' THEN
        v_checks := v_checks || jsonb_build_object('kind','POLICY','label','Admission settings','requirement','In force for ' || p_session,'candidate','Draft settings (provisional reading)','status','INFO','mandatory',false);
    END IF;
    -- the programme: active, stated, open, with a place
    SELECT * INTO pr FROM admissions.programme_rule r WHERE r.policy_id = pol.id AND r.programme_code = p_programme;
    IF g.archived THEN
        v_checks := v_checks || jsonb_build_object('kind','PROGRAMME','label','Programme active','requirement','An active programme','candidate','Archived','status','NOT_MET','mandatory',true); v_failed := true; v_reasons := v_reasons || 'The programme is not active'::text;
    END IF;
    IF pr.programme_code IS NULL THEN
        v_checks := v_checks || jsonb_build_object('kind','PROGRAMME','label','Admission rule stated','requirement','A rule for ' || p_session,'candidate','None stated','status','NOT_MET','mandatory',true); v_failed := true; v_reasons := v_reasons || 'No admission rule is stated for the programme this session'::text;
        RETURN QUERY SELECT 'NOT_ELIGIBLE'::text, v_checks, v_reasons; RETURN;
    END IF;
    SELECT c1.reason INTO v_closed FROM admissions.programme_closed c1 WHERE c1.policy_id = pol.id AND c1.programme_code = p_programme;
    IF v_closed IS NOT NULL THEN
        v_checks := v_checks || jsonb_build_object('kind','PROGRAMME','label','Open for admission','requirement','Open this session','candidate','Closed: ' || v_closed,'status','NOT_MET','mandatory',true); v_failed := true; v_reasons := v_reasons || ('The programme is closed for ' || p_session);
    ELSE
        v_checks := v_checks || jsonb_build_object('kind','PROGRAMME','label','Open for admission','requirement','Open this session','candidate','Open','status','MET','mandatory',true);
    END IF;
    IF pr.quota IS NOT NULL THEN
        SELECT count(*) INTO v_taken FROM admissions.candidate cc WHERE cc.session = p_session AND cc.offer_state IN ('ADMITTED','ACCEPTED') AND cc.programme = g.name;
        IF v_taken >= pr.quota THEN
            v_checks := v_checks || jsonb_build_object('kind','PROGRAMME','label','Places','requirement',pr.quota || ' place(s)','candidate',v_taken || ' admitted — none remains','status','NOT_MET','mandatory',true); v_failed := true; v_reasons := v_reasons || 'No place remains on the programme'::text;
        ELSE
            v_checks := v_checks || jsonb_build_object('kind','PROGRAMME','label','Places','requirement',pr.quota || ' place(s)','candidate',(pr.quota - v_taken) || ' remaining','status','MET','mandatory',true);
        END IF;
    END IF;
    -- O'Level: the best combination of sittings the programme allows
    SELECT array_agg(st.id ORDER BY st.exam_year NULLS LAST, st.ord) INTO sit FROM admissions.olevel_sitting st WHERE st.session = p_session AND st.jamb_key = v_key;
    IF sit IS NULL THEN
        v_unverified := true;
        v_checks := v_checks || jsonb_build_object('kind','OLEVEL','label','O''Level result','requirement','A result on record','candidate','No O''Level result on record','status','UNVERIFIED','mandatory',true);
        v_reasons := v_reasons || 'Unverified: no O''Level result is on record'::text;
    ELSE
        n := array_length(sit, 1); allowed := greatest(1, coalesce(pr.olevel_sittings, 2));
        IF n <= allowed OR allowed >= 3 THEN
            v_best := admissions.olevel_checks(p_session, pol.id, p_programme, sit, pr);
            combo := sit;
        ELSIF allowed = 1 THEN
            FOR i IN 1..n LOOP
                c := admissions.olevel_checks(p_session, pol.id, p_programme, ARRAY[sit[i]], pr);
                SELECT count(*) INTO v_met FROM jsonb_array_elements(c) e WHERE e->>'status' = 'MET';
                IF v_met > v_best_met THEN v_best := c; v_best_met := v_met; combo := ARRAY[sit[i]]; END IF;
            END LOOP;
        ELSE
            FOR i IN 1..n LOOP FOR j IN (i+1)..n LOOP
                c := admissions.olevel_checks(p_session, pol.id, p_programme, ARRAY[sit[i], sit[j]], pr);
                SELECT count(*) INTO v_met FROM jsonb_array_elements(c) e WHERE e->>'status' = 'MET';
                IF v_met > v_best_met THEN v_best := c; v_best_met := v_met; combo := ARRAY[sit[i], sit[j]]; END IF;
            END LOOP; END LOOP;
        END IF;
        v_checks := v_checks || jsonb_build_object('kind','OLEVEL_SITTINGS','label','Sittings','requirement',CASE WHEN allowed = 1 THEN 'One sitting only' ELSE 'At most ' || allowed || ' sittings combined' END,
            'candidate', n || ' sitting' || CASE WHEN n = 1 THEN '' ELSE 's' END || ' on record' || CASE WHEN array_length(combo, 1) < n THEN ' — read on the best ' || array_length(combo, 1) ELSE '' END,
            'status','MET','mandatory',true);
        v_checks := v_checks || v_best;
    END IF;
    -- UTME: the subject combination and the score
    IF p_entry_mode = 'UTME' THEN
        SELECT array_agg(lower(btrim(e.value))) INTO cand
          FROM admissions.caps_row_live x CROSS JOIN LATERAL jsonb_each_text(x.raw) AS e(key, value)
         WHERE x.session = p_session AND x.jamb_key = v_key
           AND regexp_replace(lower(btrim(e.key)), '[^a-z0-9]', '', 'g') IN ('subject1','subject2','subject3','subject4','subj1','subj2','subj3','subj4')
           AND nullif(btrim(e.value), '') IS NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM admissions.rule_subject_group gg WHERE gg.policy_id = pol.id AND gg.programme_code = p_programme AND gg.scope = 'UTME') THEN
            v_checks := v_checks || jsonb_build_object('kind','UTME_COMBINATION','label','UTME subject combination','requirement','None configured','candidate',coalesce(array_to_string(cand, ', '), '—'),'status','INFO','mandatory',false);
        ELSIF cand IS NULL THEN
            v_unverified := true; v_reasons := v_reasons || 'Unverified: no UTME subjects are on the candidate''s record'::text;
            v_checks := v_checks || jsonb_build_object('kind','UTME_COMBINATION','label','UTME subject combination','requirement','As configured','candidate','No UTME subjects on record','status','UNVERIFIED','mandatory',true);
        ELSE
            FOR grp IN SELECT gg.* FROM admissions.rule_subject_group gg WHERE gg.policy_id = pol.id AND gg.programme_code = p_programme AND gg.scope = 'UTME' LOOP
                FOR it IN SELECT * FROM admissions.rule_items(grp.id) LOOP
                    SELECT count(DISTINCT m.opt) INTO v_have FROM unnest(it.members) AS m(opt)
                     WHERE m.opt LIKE 'english%' OR EXISTS (SELECT 1 FROM unnest(cand) AS cs(subj) WHERE admissions.subject_same(cs.subj, m.opt, pol.id, 'UTME'));
                    v_status := CASE WHEN coalesce(v_have, 0) >= it.need THEN 'MET' ELSE 'NOT_MET' END;
                    IF v_status = 'NOT_MET' THEN v_failed := true; v_reasons := v_reasons || ('Required UTME subject not offered: ' || it.slot); END IF;
                    v_checks := v_checks || jsonb_build_object('kind','UTME_COMBINATION','label',it.slot,
                        'requirement', CASE WHEN it.need > 1 THEN it.need || ' of ' || array_to_string(it.members, ' / ') ELSE array_to_string(it.members, ' or ') END,
                        'candidate', CASE WHEN v_status = 'MET' THEN 'Offered' ELSE 'Not offered (' || array_to_string(cand, ', ') || ')' END, 'status', v_status, 'mandatory', true);
                END LOOP;
            END LOOP;
        END IF;
        SELECT max(x.aggregate) INTO v_agg FROM admissions.caps_row_live x WHERE x.session = p_session AND x.jamb_key = v_key AND x.entry_mode = 'UTME';
        SELECT f.cutoff INTO v_fac FROM admissions.faculty_quota f WHERE f.policy_id = pol.id AND f.faculty_code = g.faculty_code;
        v_load := admissions.load_cutoff_for(p_session);
        v_prog_cut := pr.cutoff;
        v_req := greatest(coalesce(v_prog_cut, v_fac), v_load);
        IF v_req IS NULL THEN
            v_checks := v_checks || jsonb_build_object('kind','UTME_SCORE','label','UTME score','requirement','No minimum configured','candidate',coalesce(v_agg::text, 'Not on record'),'status','INFO','mandatory',false);
        ELSIF v_agg IS NULL THEN
            v_unverified := true; v_reasons := v_reasons || 'Unverified: no UTME score is on record'::text;
            v_checks := v_checks || jsonb_build_object('kind','UTME_SCORE','label','UTME score','requirement','Minimum ' || v_req,'candidate','Not on record','status','UNVERIFIED','mandatory',true);
        ELSE
            v_status := CASE WHEN v_agg >= v_req THEN 'MET' ELSE 'NOT_MET' END;
            IF v_status = 'NOT_MET' THEN v_failed := true; v_reasons := v_reasons || ('UTME score ' || v_agg || ' is below the minimum of ' || v_req); END IF;
            v_checks := v_checks || jsonb_build_object('kind','UTME_SCORE','label','UTME score','requirement','Minimum ' || v_req || ' (programme ' || coalesce(v_prog_cut::text, '—') || ' · faculty ' || coalesce(v_fac::text, '—') || ' · session ' || coalesce(v_load::text, '—') || ')',
                'candidate', v_agg::text, 'status', v_status, 'mandatory', true);
        END IF;
    ELSIF p_entry_mode = 'DIRECT_ENTRY' THEN
        SELECT array_agg(lower(btrim(s.subject))) INTO cand FROM admissions.de_award a JOIN admissions.de_award_subject s ON s.award_id = a.id WHERE a.session = p_session AND a.jamb_key = v_key AND nullif(btrim(s.subject), '') IS NOT NULL;
        -- V773: a degree or diploma is held by its discipline and class, with no subjects
        SELECT string_agg(admissions.de_basis_label(a.basis) || coalesce(' in ' || nullif(btrim(a.discipline), ''), '')
                          || coalesce(' (' || nullif(btrim(a.award_class), '') || ')', ''), '; ' ORDER BY a.basis)
          INTO v_class FROM admissions.de_award a
         WHERE a.session = p_session AND a.jamb_key = v_key
           AND a.basis IN ('DEGREE', 'DEGREE_FOREIGN', 'UNIVERSITY_DIPLOMA', 'ND', 'HND')
           AND (nullif(btrim(a.discipline), '') IS NOT NULL OR nullif(btrim(a.award_class), '') IS NOT NULL);
        IF NOT EXISTS (SELECT 1 FROM admissions.rule_subject_group gg WHERE gg.policy_id = pol.id AND gg.programme_code = p_programme AND gg.scope = 'DE') THEN
            v_checks := v_checks || jsonb_build_object('kind','DE_COMBINATION','label','Direct Entry subjects','requirement','None configured','candidate',coalesce(array_to_string(cand, ', '), '—'),'status','INFO','mandatory',false);
        ELSIF cand IS NULL AND v_class IS NOT NULL THEN
            v_checks := v_checks || jsonb_build_object('kind','DE_COMBINATION','label','Direct Entry subjects','requirement','As configured',
                'candidate', v_class || ' — a degree or diploma: the A''Level subjects are not checked','status','INFO','mandatory',false);
        ELSIF cand IS NULL THEN
            v_unverified := true; v_reasons := v_reasons || 'Unverified: no Direct Entry award is captured'::text;
            v_checks := v_checks || jsonb_build_object('kind','DE_COMBINATION','label','Direct Entry subjects','requirement','As configured','candidate','No award captured','status','UNVERIFIED','mandatory',true);
        ELSE
            FOR grp IN SELECT gg.* FROM admissions.rule_subject_group gg WHERE gg.policy_id = pol.id AND gg.programme_code = p_programme AND gg.scope = 'DE' LOOP
                SELECT count(DISTINCT m.opt) INTO v_have
                  FROM admissions.rule_items(grp.id) it2 CROSS JOIN unnest(it2.members) AS m(opt)
                 WHERE EXISTS (SELECT 1 FROM unnest(cand) AS cs(subj) WHERE admissions.subject_same(cs.subj, m.opt, pol.id, 'UTME'));
                v_status := CASE WHEN coalesce(v_have, 0) >= grp.choose THEN 'MET' ELSE 'NOT_MET' END;
                IF v_status = 'NOT_MET' THEN v_failed := true; v_reasons := v_reasons || ('Direct Entry subjects short of ' || grp.choose || ' required'); END IF;
                v_checks := v_checks || jsonb_build_object('kind','DE_COMBINATION','label','Direct Entry subjects','requirement',grp.choose || ' of ' || (SELECT string_agg(rs.subject, ', ') FROM admissions.rule_subject rs WHERE rs.group_id = grp.id),
                    'candidate', array_to_string(cand, ', '), 'status', v_status, 'mandatory', true);
            END LOOP;
        END IF;
    END IF;
    -- any O'Level check that failed
    FOR c IN SELECT e FROM jsonb_array_elements(v_checks) e WHERE e->>'status' = 'NOT_MET' AND (e->>'kind') LIKE 'OLEVEL%' LOOP
        v_failed := true;
        v_reasons := v_reasons || ('Required O''Level ' || (c->>'label') || ' not satisfied (' || (c->>'requirement') || '; candidate: ' || (c->>'candidate') || ')');
    END LOOP;
    -- more than the academic requirements
    v_add := nullif(btrim(coalesce(pr.additional_screening, '')), '');
    IF v_add IS NOT NULL THEN
        v_checks := v_checks || jsonb_build_object('kind','SCREENING','label','Additional screening','requirement',v_add,'candidate','To be scheduled','status','INFO','mandatory',false);
    END IF;
    v_res := CASE WHEN v_failed THEN 'NOT_ELIGIBLE' WHEN v_unverified THEN 'UNVERIFIED' WHEN v_add IS NOT NULL THEN 'ELIGIBLE_SCREENING' ELSE 'ELIGIBLE' END;
    RETURN QUERY SELECT v_res, v_checks, v_reasons;
END $$;
COMMENT ON FUNCTION admissions.evaluate_programme(text, text, text, text) IS
  'V773: one candidate against one programme (V266, V268) under the session''s admission settings: the programme''s standing, the O''Level compulsory credits, required subjects (OLEVEL_REQUIRED groups, min grade), credits and sittings, the UTME combination and the effective cut-off (programme, faculty, session), or the Direct Entry subjects (a degree or diploma, held without subjects, an INFO check: the A''Level subjects are not checked). Every check explained; ELIGIBLE, ELIGIBLE_SCREENING, NOT_ELIGIBLE or UNVERIFIED.';

-- ── the upload: every line decided (the preview), and on the commit the lines that change something recorded ───────────────────
CREATE FUNCTION admissions.de_upload_record(p_session text, p_programme text, p_rows jsonb, p_filename text, p_sha256 bytea,
                                            p_actor uuid, p_office text, p_commit boolean)
RETURNS TABLE (line integer, reg_no text, jamb_key text, name text, programme_code text, programme text,
               outcome text, problems jsonb, upload_id uuid)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
    v_bases   constant text[] := ARRAY['A_LEVEL', 'IJMB', 'JUPEB', 'NCE', 'ND', 'HND', 'DEGREE', 'DEGREE_FOREIGN', 'UNIVERSITY_DIPLOMA',
                                       'NOT_STATED', 'NOT_AVAILABLE'];
    v_classes constant text[] := ARRAY['DEGREE', 'DEGREE_FOREIGN', 'UNIVERSITY_DIPLOMA', 'ND', 'HND'];
    v_chosen text; v_dup jsonb; v_out jsonb[] := ARRAY[]::jsonb[]; v_upload uuid;
    v_r record; v_s record; v_t jsonb; v_cv record; v_cv_found boolean;
    v_key text; v_dinfo jsonb; v_mode text; v_jcode text; v_name text; v_code text; v_pname text; v_basis text;
    v_err text[]; v_w_prog text[]; v_w_grade text[]; v_w_given text[]; v_w_twice text[]; v_w_kind text[]; v_w_rep text[]; v_w_notes text[];
    v_disc text; v_class text; v_inst text; v_year int; v_exam text; v_subj jsonb; v_seen text[]; v_n int; v_g text;
    v_cq text; v_cg int; v_c5 boolean; v_ccl boolean; v_cst text; v_cage int; v_caq boolean; v_ccat text; v_carries boolean;
    v_aw uuid; v_src text; v_odisc text; v_oclass text; v_oinst text; v_oyear int; v_oexam text; v_osubj jsonb;
    v_same_subj boolean; v_same_award boolean; v_others boolean; v_same_caps boolean; v_outcome text; v_problems jsonb;
    v_recorded int := 0; v_unchanged int := 0; v_skipped int := 0; v_repeated int := 0; v_lines int := 0;
BEGIN
    -- one commit at a time for a session: a second officer's (or a double press's) commit waits here, then reads what the first
    -- recorded and answers UNCHANGED instead of meeting uq_de_award. The preview takes no lock: it writes nothing
    IF p_commit THEN
        PERFORM pg_advisory_xact_lock(hashtextextended('V773 DE upload ' || coalesce(p_session, ''), 0));
    END IF;
    SELECT p.name INTO v_chosen FROM ref.programme p WHERE p.code = p_programme;
    -- the same REG NO. on several lines: identical (a repeat) or not (none recorded)
    SELECT jsonb_object_agg(q.k, jsonb_build_object('n', q.n, 'lines', q.lines, 'first', q.first))
      INTO v_dup
      FROM (SELECT upper(btrim(coalesce(x.e->>'regNo', ''))) AS k, count(DISTINCT (x.e - 'line' - 'notes' - 'regNo')) AS n,
                   string_agg(coalesce(x.e->>'line', '?'), ', ' ORDER BY x.o) AS lines, min(x.o) AS first
              FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) WITH ORDINALITY x(e, o)
             GROUP BY 1) q;

    -- ── the first pass: every line decided, nothing written ──
    FOR v_r IN SELECT x.e, x.o FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) WITH ORDINALITY x(e, o) ORDER BY x.o LOOP
        v_lines := v_lines + 1;
        v_key := upper(btrim(coalesce(v_r.e->>'regNo', '')));
        v_dinfo := v_dup->v_key;
        v_basis := v_r.e->>'basis';
        v_err := ARRAY[]::text[]; v_w_prog := ARRAY[]::text[]; v_w_grade := ARRAY[]::text[]; v_w_given := ARRAY[]::text[];
        v_w_twice := ARRAY[]::text[]; v_w_kind := ARRAY[]::text[]; v_w_rep := ARRAY[]::text[];
        v_w_notes := ARRAY(SELECT n.x FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(v_r.e->'notes') = 'array' THEN v_r.e->'notes' ELSE '[]'::jsonb END) n(x)
                            WHERE btrim(n.x) <> '');
        -- the candidate on JAMB's live list
        v_mode := NULL; v_jcode := NULL; v_name := NULL; v_code := NULL; v_pname := NULL;
        SELECT x.entry_mode, x.jamb_code, concat_ws(' ', x.surname, x.other_names) INTO v_mode, v_jcode, v_name
          FROM admissions.caps_row_live x WHERE x.session = p_session AND x.jamb_key = v_key;
        IF v_jcode IS NOT NULL THEN
            v_code := admissions.de_programme_of(v_jcode);
            SELECT p.name INTO v_pname FROM ref.programme p WHERE p.code = v_code;
        END IF;
        IF v_mode IS NULL THEN
            v_err := v_err || ('Not on JAMB''s live Direct Entry list for ' || p_session);
        ELSIF v_mode <> 'DIRECT_ENTRY' THEN
            v_err := v_err || ('On JAMB''s list for ' || p_session || ' as ' || v_mode || ', not Direct Entry');
        END IF;
        IF v_basis IS NULL OR NOT (v_basis = ANY (v_bases)) THEN
            v_err := v_err || ('Qualification type not read: ' || coalesce(v_r.e->>'typeText', ''));
            v_basis := NULL;
        END IF;
        IF coalesce((v_dinfo->>'n')::int, 1) > 1 THEN
            v_err := v_err || ('REG NO. on lines ' || (v_dinfo->>'lines') || ' with different details; none of them recorded');
        END IF;
        IF p_programme IS NOT NULL AND v_mode = 'DIRECT_ENTRY' AND v_code IS DISTINCT FROM p_programme THEN
            v_w_prog := v_w_prog || ('On JAMB''s list under ' || coalesce(v_pname, v_code) || ' (' || v_code || '), not ' || coalesce(v_chosen, p_programme));
        END IF;

        -- what the line records: a degree or diploma its discipline and class, the rest their subjects in their places
        v_disc := NULL; v_class := NULL; v_subj := '[]'::jsonb; v_seen := ARRAY[]::text[]; v_n := 0;
        IF v_basis = ANY (v_classes) THEN
            v_disc := nullif(btrim(v_r.e->>'discipline'), '');
            v_class := CASE WHEN admissions.de_no_grade(v_r.e->>'awardClass') THEN NULL ELSE btrim(v_r.e->>'awardClass') END;
            IF v_class IS NOT NULL AND admissions.de_grade_points(v_basis, v_class) IS NULL THEN
                v_w_grade := v_w_grade || ('Class not read: ' || v_class);
            END IF;
            IF v_disc IS NULL THEN v_w_given := v_w_given || 'Discipline not given'::text; END IF;
            IF v_class IS NULL THEN v_w_given := v_w_given || 'Class not given'::text; END IF;
        ELSIF v_basis IN ('A_LEVEL', 'IJMB', 'JUPEB', 'NCE', 'NOT_STATED') THEN
            FOR v_s IN SELECT btrim(coalesce(y.e->>'subject', '')) AS subject, y.e->>'grade' AS grade
                         FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v_r.e->'subjects') = 'array' THEN v_r.e->'subjects' ELSE '[]'::jsonb END)
                              WITH ORDINALITY y(e, o)
                        ORDER BY y.o LOOP
                CONTINUE WHEN v_s.subject = '';
                -- an NCE keeps a subject named twice (a double major); any other kind the first (named as it was first written)
                IF v_basis <> 'NCE' AND lower(v_s.subject) = ANY (v_seen) THEN
                    v_w_twice := v_w_twice || ((SELECT y.e->>'subject' FROM jsonb_array_elements(v_subj) y(e) WHERE lower(y.e->>'subject') = lower(v_s.subject) LIMIT 1)
                                               || ' named twice; the first recorded');
                    CONTINUE;
                END IF;
                v_seen := v_seen || lower(v_s.subject);
                v_n := v_n + 1;
                v_g := CASE WHEN admissions.de_no_grade(v_s.grade) THEN NULL ELSE btrim(v_s.grade) END;
                v_subj := v_subj || jsonb_build_array(jsonb_build_object('ord', v_n, 'subject', v_s.subject, 'grade', v_g));
                IF v_g IS NOT NULL AND admissions.de_grade_points(v_basis, v_g) IS NULL THEN
                    v_w_grade := v_w_grade || ('Grade not read: ' || v_s.subject || ' ' || v_g);
                END IF;
            END LOOP;
        END IF;
        IF v_basis = 'NOT_STATED' THEN v_w_kind := v_w_kind || 'Qualification type blank in CAPS (recorded as Not stated)'::text; END IF;
        IF v_basis = 'NOT_AVAILABLE' THEN v_w_kind := v_w_kind || 'Grade window empty in CAPS (recorded as Not available)'::text; END IF;
        v_inst := nullif(btrim(v_r.e->>'institution'), '');
        v_year := (v_r.e->>'year')::int;
        v_exam := nullif(btrim(v_r.e->>'examNo'), '');
        -- CAPS's own values for the candidate
        v_cq := nullif(btrim(v_r.e->>'capsQualification'), '');
        v_cg := (v_r.e->>'capsGrade')::int;
        v_c5 := (v_r.e->>'hasFiveCredits')::boolean;
        v_ccl := (v_r.e->>'isCleared')::boolean;
        v_cst := nullif(btrim(v_r.e->>'status'), '');
        v_cage := (v_r.e->>'age')::int;
        v_caq := (v_r.e->>'ageQualified')::boolean;
        v_ccat := nullif(btrim(v_r.e->>'admissionCategory'), '');
        v_carries := v_cq IS NOT NULL OR v_cg IS NOT NULL OR v_c5 IS NOT NULL OR v_ccl IS NOT NULL OR v_cst IS NOT NULL
                     OR v_cage IS NOT NULL OR v_caq IS NOT NULL OR v_ccat IS NOT NULL;

        v_aw := NULL; v_same_subj := false; v_same_award := false; v_others := false; v_same_caps := false;
        IF cardinality(v_err) > 0 THEN
            v_outcome := 'SKIPPED';
        ELSIF (v_dinfo->>'first')::int < v_r.o THEN
            v_outcome := 'REPEATED';
            v_w_rep := ARRAY['Repeated row: recorded once'];
        ELSE
            -- what is recorded already: the award of the same kind, an uploaded award of another, CAPS's values
            v_src := NULL; v_odisc := NULL; v_oclass := NULL; v_oinst := NULL; v_oyear := NULL; v_oexam := NULL;
            SELECT d.id, d.source, d.discipline, d.award_class, d.institution, d.awarded_year, d.exam_no
              INTO v_aw, v_src, v_odisc, v_oclass, v_oinst, v_oyear, v_oexam
              FROM admissions.de_award d WHERE d.session = p_session AND d.jamb_key = v_key AND d.basis = v_basis;
            IF v_aw IS NOT NULL THEN
                SELECT coalesce(jsonb_agg(jsonb_build_object('ord', y.ord, 'subject', y.subject, 'grade', y.grade) ORDER BY y.ord NULLS LAST, y.subject, y.id), '[]'::jsonb)
                  INTO v_osubj FROM admissions.de_award_subject y WHERE y.award_id = v_aw;
                v_same_subj := v_osubj = v_subj;
                v_same_award := v_src = 'UPLOAD' AND v_same_subj
                                AND v_odisc IS NOT DISTINCT FROM v_disc AND v_oclass IS NOT DISTINCT FROM v_class
                                AND v_oinst IS NOT DISTINCT FROM v_inst AND v_oyear IS NOT DISTINCT FROM v_year AND v_oexam IS NOT DISTINCT FROM v_exam;
            END IF;
            v_others := EXISTS (SELECT 1 FROM admissions.de_award d
                                 WHERE d.session = p_session AND d.jamb_key = v_key AND d.source = 'UPLOAD' AND d.basis <> v_basis);
            SELECT v.qualification, v.caps_grade, v.has_five_credits, v.is_cleared, v.status, v.age, v.age_qualified, v.admission_category
              INTO v_cv FROM admissions.de_caps_value v WHERE v.session = p_session AND v.jamb_key = v_key;
            v_cv_found := FOUND;
            v_same_caps := CASE WHEN v_cv_found
                                THEN v_cv.qualification IS NOT DISTINCT FROM v_cq AND v_cv.caps_grade IS NOT DISTINCT FROM v_cg
                                     AND v_cv.has_five_credits IS NOT DISTINCT FROM v_c5 AND v_cv.is_cleared IS NOT DISTINCT FROM v_ccl
                                     AND v_cv.status IS NOT DISTINCT FROM v_cst AND v_cv.age IS NOT DISTINCT FROM v_cage
                                     AND v_cv.age_qualified IS NOT DISTINCT FROM v_caq AND v_cv.admission_category IS NOT DISTINCT FROM v_ccat
                                ELSE NOT v_carries END;
            v_outcome := CASE WHEN v_same_award AND NOT v_others AND v_same_caps THEN 'UNCHANGED' ELSE 'RECORDED' END;
        END IF;
        CASE v_outcome WHEN 'RECORDED' THEN v_recorded := v_recorded + 1; WHEN 'UNCHANGED' THEN v_unchanged := v_unchanged + 1;
                       WHEN 'SKIPPED' THEN v_skipped := v_skipped + 1; ELSE v_repeated := v_repeated + 1; END CASE;

        SELECT coalesce(jsonb_agg(jsonb_build_object('level', z.lvl, 'text', z.msg) ORDER BY z.o), '[]'::jsonb) INTO v_problems
          FROM (SELECT 'ERROR' AS lvl, e.x AS msg, e.o FROM unnest(v_err) WITH ORDINALITY e(x, o)
                UNION ALL
                SELECT 'WARNING', w.x, 100 + w.o
                  FROM unnest(v_w_prog || v_w_grade || v_w_given || v_w_twice || v_w_kind || v_w_rep || v_w_notes) WITH ORDINALITY w(x, o)) z;
        v_out := v_out || jsonb_build_object(
            'line', v_r.e->'line', 'regNo', v_r.e->>'regNo', 'key', v_key, 'name', v_name, 'code', v_code, 'programme', v_pname,
            'outcome', v_outcome, 'problems', v_problems,
            'basis', v_basis, 'discipline', v_disc, 'awardClass', v_class, 'institution', v_inst, 'year', v_year, 'examNo', v_exam,
            'subjects', v_subj, 'award', v_aw, 'sameSubjects', v_same_subj, 'writeCaps', NOT v_same_caps,
            'caps', jsonb_build_object('qualification', v_cq, 'grade', v_cg, 'five', v_c5, 'cleared', v_ccl, 'status', v_cst,
                                       'age', v_cage, 'ageQualified', v_caq, 'category', v_ccat));
    END LOOP;

    -- ── the commit: only the lines that change something, and nothing at all when none does ──
    IF p_commit AND v_recorded > 0 THEN
        INSERT INTO admissions.de_upload (session, filename, file_sha256, programme_code, rows_read, rows_recorded, rows_unchanged, rows_skipped,
                                          rows_repeated, uploaded_by, uploaded_office)
        VALUES (p_session, nullif(btrim(p_filename), ''), p_sha256, p_programme, v_lines, v_recorded, v_unchanged, v_skipped, v_repeated, p_actor, p_office)
        RETURNING id INTO v_upload;
        FOREACH v_t IN ARRAY v_out LOOP
            CONTINUE WHEN v_t->>'outcome' <> 'RECORDED';
            v_key := v_t->>'key';
            v_basis := v_t->>'basis';
            v_aw := (v_t->>'award')::uuid;
            IF v_aw IS NOT NULL THEN
                -- the award of the same kind, whoever recorded it, replaced in place
                UPDATE admissions.de_award d
                   SET discipline = v_t->>'discipline', award_class = v_t->>'awardClass', institution = v_t->>'institution',
                       awarded_year = (v_t->>'year')::int, exam_no = v_t->>'examNo',
                       source = 'UPLOAD', upload_id = v_upload, recorded_by = p_actor, recorded_at = now()
                 WHERE d.id = v_aw;
                IF NOT (v_t->>'sameSubjects')::boolean THEN
                    DELETE FROM admissions.de_award_subject y WHERE y.award_id = v_aw;
                    INSERT INTO admissions.de_award_subject (award_id, subject, grade, ord)
                    SELECT v_aw, s.e->>'subject', s.e->>'grade', (s.e->>'ord')::smallint FROM jsonb_array_elements(v_t->'subjects') s(e);
                END IF;
            ELSE
                v_aw := gen_random_uuid();
                INSERT INTO admissions.de_award (id, session, jamb_key, basis, awarded_year, institution, recorded_by, recorded_at,
                                                 discipline, award_class, exam_no, source, upload_id)
                VALUES (v_aw, p_session, v_key, v_basis, (v_t->>'year')::int, v_t->>'institution', p_actor, now(),
                        v_t->>'discipline', v_t->>'awardClass', v_t->>'examNo', 'UPLOAD', v_upload);
                INSERT INTO admissions.de_award_subject (award_id, subject, grade, ord)
                SELECT v_aw, s.e->>'subject', s.e->>'grade', (s.e->>'ord')::smallint FROM jsonb_array_elements(v_t->'subjects') s(e);
            END IF;
            -- an earlier upload's award of another kind goes; one typed by hand stays
            DELETE FROM admissions.de_award d
             WHERE d.session = p_session AND d.jamb_key = v_key AND d.source = 'UPLOAD' AND d.basis <> v_basis;
            IF (v_t->>'writeCaps')::boolean THEN
                INSERT INTO admissions.de_caps_value AS v (session, jamb_key, qualification, caps_grade, has_five_credits, is_cleared, status, age,
                                                           age_qualified, admission_category, upload_id, recorded_by, recorded_at)
                VALUES (p_session, v_key, v_t->'caps'->>'qualification', (v_t->'caps'->>'grade')::int, (v_t->'caps'->>'five')::boolean,
                        (v_t->'caps'->>'cleared')::boolean, v_t->'caps'->>'status', (v_t->'caps'->>'age')::int,
                        (v_t->'caps'->>'ageQualified')::boolean, v_t->'caps'->>'category', v_upload, p_actor, now())
                ON CONFLICT ON CONSTRAINT de_caps_value_pkey DO UPDATE
                   SET qualification = excluded.qualification, caps_grade = excluded.caps_grade, has_five_credits = excluded.has_five_credits,
                       is_cleared = excluded.is_cleared, status = excluded.status, age = excluded.age, age_qualified = excluded.age_qualified,
                       admission_category = excluded.admission_category, upload_id = excluded.upload_id, recorded_by = excluded.recorded_by,
                       recorded_at = excluded.recorded_at;
            END IF;
        END LOOP;
    END IF;

    RETURN QUERY
    SELECT (u.t->>'line')::int, u.t->>'regNo', u.t->>'key', u.t->>'name', u.t->>'code', u.t->>'programme', u.t->>'outcome', u.t->'problems', v_upload
      FROM unnest(v_out) WITH ORDINALITY u(t, o)
     ORDER BY u.o;
END $$;
COMMENT ON FUNCTION admissions.de_upload_record(text, text, jsonb, text, bytea, uuid, text, boolean) IS
  'V773: a workbook of Direct Entry candidates'' qualifications (the API''s rows, one per line) recorded for the candidates on JAMB''s live Direct Entry list — each line RECORDED, UNCHANGED, SKIPPED (an error: not on the list, on it as UTME, a type not read, the same REG NO. on lines with different details) or REPEATED (an identical repeat), with every problem (errors, and warnings: another programme than the one chosen, a grade or class not read, a discipline or class not given, a subject named twice, a type blank or a grade window empty, a repeat, the reader''s notes). p_commit false decides only and writes nothing (the preview); true writes the RECORDED lines alone — the award of the same kind replaced (an earlier upload''s of another kind removed, one typed by hand kept), CAPS''s values for the candidate — under one admissions.de_upload row, none when nothing changes: the same file twice changes nothing.';

-- ── the seed: the University's default and Pharmacy's own rule for 2026/2027 ────────────────────────────────────────────────────
DO $$
DECLARE v_pol uuid := (SELECT p.id FROM admissions.session_policy p WHERE p.session = '2026/2027');
BEGIN
    IF v_pol IS NULL THEN RETURN; END IF;
    INSERT INTO admissions.de_fit_rule (policy_id, programme_code, kind, core_disciplines, relevant_min, partly_min, related_disciplines,
                                        related_relevant_min, related_partly_min, other_fit, relevant_passes, partly_passes, set_by, set_office)
    SELECT v_pol, NULL, b.kind, b.core_disciplines, b.relevant_min, b.partly_min, b.related_disciplines, b.related_relevant_min,
           b.related_partly_min, b.other_fit, b.relevant_passes, b.partly_passes, '00000000-0000-0000-0000-000000000000', 'academic'
      FROM admissions.de_fit_builtin() b
    ON CONFLICT (policy_id, (coalesce(programme_code, '')), kind) DO NOTHING;
    -- DOCTOR OF PHARMACY's own, from its Fit Criteria sheet (its A-Level item as its own Direct Entry requirement writes it)
    IF EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C73770') THEN
        INSERT INTO admissions.de_fit_rule (policy_id, programme_code, kind, core_disciplines, relevant_min, partly_min, related_disciplines,
                                            related_relevant_min, related_partly_min, other_fit, relevant_passes, partly_passes, set_by, set_office)
        VALUES
            (v_pol, 'C73770', 'DEGREE',
             ARRAY['Chemistry', 'Biochemistry', 'Pharmacology', 'Microbiology', 'Physiology', 'Anatomy', 'Medical Laboratory Science', 'Nursing', 'Biology', 'Zoology'],
             4, 3,
             ARRAY['Physics', 'Forestry', 'Botany/Plant Science', 'Agriculture/Agricultural Science', 'Food Science', 'Biomedical Technology', 'Laboratory Technology'],
             NULL, 3, 'NOT_RELEVANT', NULL, NULL, '00000000-0000-0000-0000-000000000000', 'academic'),
            (v_pol, 'C73770', 'UNIVERSITY_DIPLOMA', '{}', NULL, NULL, '{}', NULL, NULL, 'CHECK_MANUALLY', NULL, NULL, '00000000-0000-0000-0000-000000000000', 'academic'),
            (v_pol, 'C73770', 'HND', ARRAY['Pharmaceutical Technology/Pharmacy Technician'], NULL, 2, '{}', NULL, NULL, 'NOT_RELEVANT', NULL, NULL,
             '00000000-0000-0000-0000-000000000000', 'academic'),
            (v_pol, 'C73770', 'ND', ARRAY['Pharmaceutical Technology/Pharmacy Technician'], NULL, 1, '{}', NULL, NULL, 'NOT_RELEVANT', NULL, NULL,
             '00000000-0000-0000-0000-000000000000', 'academic'),
            (v_pol, 'C73770', 'NCE', '{}', NULL, NULL, '{}', NULL, NULL, 'CHECK_MANUALLY', NULL, NULL, '00000000-0000-0000-0000-000000000000', 'academic'),
            (v_pol, 'C73770', 'A_LEVEL', ARRAY['Biology/Zoology/Botany', 'Chemistry', 'Physics'], 3, 1, '{}', NULL, NULL, 'NOT_RELEVANT', 3, 3,
             '00000000-0000-0000-0000-000000000000', 'academic')
        ON CONFLICT (policy_id, (coalesce(programme_code, '')), kind) DO NOTHING;
    END IF;
END $$;

COMMIT;
