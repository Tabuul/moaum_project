-- ═══════════════════════════════════════════════════════════════════════════
-- V006 — the JAMB admission list, and where it actually lands
--
-- ── The finding ───────────────────────────────────────────────────────────
--
-- There is nowhere to upload it. Searching the whole prototype and the design
-- set for the CAPS admission list returns exactly two things:
--
--   · `t/api`      "JAMB CAPS · Admission list and candidate biodata ·
--                   https://api.jamb.gov.ng/caps · connected · Nightly 06:00"
--   · `t/admissions`  a read-only "JAMB reconciliation" panel with three
--                     hard-coded discrepancy rows and a Resolve button
--
-- So the design assumes the list ARRIVES BY ITSELF, over a nightly API. If
-- CAPS in practice means an officer logging in and downloading a file — which
-- is how every Nigerian institution the Directorate knows actually works —
-- then the single most consequential external list in the University has no
-- door into the system, and the nightly job is a description of something
-- that does not exist.
--
-- That endpoint is OUR ASSUMPTION and it must be confirmed with JAMB before
-- anything is built on it. This migration deliberately does not depend on the
-- answer: whether the rows arrive by API or by a person choosing a file, they
-- land in the same table and are reconciled the same way. Only the door
-- differs.
--
-- ── Why it is a reconciliation and not a load ─────────────────────────────
--
-- This system has met this shape three times already and answered it the same
-- way each time:
--
--   · the bulk score upload — read whole, validated whole, committed or
--     refused entirely, because a half-imported sheet looks finished;
--   · the NELFUND remittance — a bulk external sum split across named
--     students, with the unallocated remainder as a worked queue that carries
--     an owner rather than sitting in suspense;
--   · the CHS results crossing — a set arriving from another system is a
--     filtered subset BY CONSTRUCTION, so the crossing counts both
--     directions and waits until both are zero or explained.
--
-- The admission list is the same class and the gravest of the three, because
-- it is the origin of a person's entire record. Everything downstream —
-- matriculation number, fees, results, the degree in 2071 — hangs off a row
-- that entered here. A name silently missing produces a candidate who paid
-- and has no record; a name silently added produces a matriculation number
-- issued to somebody JAMB never admitted, which is the exact shape of the
-- admission-racket the CAPS system exists to prevent.
--
-- ── Who is the authority on what ──────────────────────────────────────────
--
-- CAPS is the authority on WHO WAS ADMITTED and to WHICH PROGRAMME. The
-- portal is the authority on everything that happens afterwards. Neither
-- overwrites the other silently, and the disagreements are worked by a named
-- office.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── the University's programmes, and what JAMB calls them ────────────────
-- Corrected 7 September 2026 against the University's own programme table.
--
-- I had this wrong. The design assumed JAMB and the University keep separate
-- course-code systems and that a mapping table had to join them. They do not:
-- the University's programme table is KEYED ON THE SAME C##### CODE. There is
-- one code system, and it is JAMB's.
--
-- What differs is only the NAME, and it differs for 56 of the 92 programmes:
--
--     C00061   JAMB: Medicine & Surgery        MOAUM: MBBS
--     C00033   JAMB: Law                       MOAUM: LL.B (LAW)
--     C00062   JAMB: Religion & Cultural…      MOAUM: B.A. RELIGIOUS STUDIES
--     C00019   JAMB: Accounting                MOAUM: B.Sc. ACCOUNTING
--
-- MBBS is the one that shows why this cannot be normalised away. It is not a
-- formatting difference or a missing award prefix — the two institutions use
-- different words for the same degree, and only one of them belongs on a
-- certificate. So the University's name is the label and JAMB's is an ALIAS:
-- kept as evidence of what was approved, and searchable, because an officer
-- holding a CAPS printout that says "Medicine & Surgery" must be able to find
-- the programme without already knowing it is called MBBS here.
--
-- The 36 that match today are not a rule. C00004 reads the same in both lists
-- and could diverge the next time either side edits a label, which is why the
-- alias is stored per code rather than derived by comparing strings.
--
-- The code also resolves the DEPARTMENT and FACULTY, which matriculation and
-- the Faculty Officer's list both need and neither could get from a name.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE ref.faculty (
    code text PRIMARY KEY,
    name text NOT NULL
);

CREATE TABLE ref.programme (
    code         text PRIMARY KEY,
    name         text NOT NULL,        -- the University's name. This is the label.
    dept_code    text NOT NULL,
    faculty_code text NOT NULL REFERENCES ref.faculty(code),
    min_score    int  NOT NULL,
    archived     boolean NOT NULL DEFAULT false,
    category     text NOT NULL,
    CONSTRAINT ck_prog_code CHECK (code ~ '^C[0-9]{5}$'),
    CONSTRAINT ck_prog_cat  CHECK (category IN ('UNDER GRADUATE','POST GRADUATE'))
);

COMMENT ON COLUMN ref.programme.archived IS
  'A retired programme keeps its code for ever — BR-007 applies to a course '
  'code as it applies to a matriculation number — and stops accepting '
  'admissions. Deleting the row would orphan every graduate who holds it.';

-- JAMB's name for the same code. An alias, never a label.
CREATE TABLE ref.jamb_alias (
    code      text PRIMARY KEY,
    jamb_name text NOT NULL,
    CONSTRAINT ck_alias_code CHECK (code ~ '^C[0-9]{5}$'),
    CONSTRAINT ck_alias_name CHECK (length(btrim(jamb_name)) > 0)
);

COMMENT ON TABLE ref.jamb_alias IS
  'What JAMB calls each course. Deliberately NOT a foreign key to '
  'ref.programme: JAMB sends codes the University does not run — C99256, '
  '"MA RELIGION AND PEACE STUDIES", is a postgraduate code sitting in the '
  'undergraduate alias list — and the alias has to be able to name a code in '
  'order for the intake to explain why it was refused.';

INSERT INTO ref.faculty (code, name) VALUES
    ('AC', 'Architecture'),
    ('AR', 'Arts'),
    ('BAMS', 'Basic and Applied Medical Sciences'),
    ('CM', 'Communication and Media Studies'),
    ('ED', 'Education'),
    ('ES', 'Environmental Sciences'),
    ('LW', 'Law'),
    ('MS', 'Management Sciences'),
    ('PS', 'Pharmaceutical Sciences'),
    ('SC', 'Science'),
    ('SS', 'Social Sciences'),
    ('TI', 'Technology and Industrial Studies');

INSERT INTO ref.programme (code, name, dept_code, faculty_code, min_score, archived, category) VALUES
    ('C00001', 'B.A. (ED) ENGLISH', 'ASS', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00002', 'B.A. ENGLISH', 'ENG', 'AR', 40, false, 'UNDER GRADUATE'),
    ('C00003', 'B.A. FRENCH', 'LAN', 'AR', 40, false, 'UNDER GRADUATE'),
    ('C00004', 'B.Sc. (ED) HUMAN KINETICS', 'HKH', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00005', 'B.A. LINGUISTICS', 'LAN', 'AR', 40, false, 'UNDER GRADUATE'),
    ('C00008', 'B.ED HISTORY', 'ASS', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00009', 'B.ED INTEGRATED SCIENCE', 'SME', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00010', 'B.ED PHYSICAL AND HEALTH EDUCATION', 'HKH', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00012', 'B.Sc. (ED) BIOLOGY', 'SME', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00014', 'B.Sc. (ED) CHEMISTRY', 'SME', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00015', 'B.Sc. (ED) ECONOMICS', 'ASS', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00016', 'B.Sc. (ED) MATHEMATICS', 'SME', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00017', 'B.Sc. (ED) PHYSICS', 'SME', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00019', 'B.Sc. ACCOUNTING', 'ACC', 'MS', 40, false, 'UNDER GRADUATE'),
    ('C00021', 'B.Sc. BUSINESS MANAGEMENT', 'BSM', 'MS', 40, false, 'UNDER GRADUATE'),
    ('C00022', 'B.Sc. CHEMISTRY', 'CHM', 'SC', 40, false, 'UNDER GRADUATE'),
    ('C00023', 'B.Sc. COMPUTER SCIENCE', 'MTC', 'SC', 40, false, 'UNDER GRADUATE'),
    ('C00024', 'B.Sc. ECONOMICS', 'ECO', 'SS', 40, false, 'UNDER GRADUATE'),
    ('C00025', 'B.Sc. GEOGRAPHY', 'GEO', 'ES', 40, false, 'UNDER GRADUATE'),
    ('C00028', 'B.Sc. MATHEMATICS', 'MTC', 'SC', 40, false, 'UNDER GRADUATE'),
    ('C00029', 'B.Sc. PHYSICS', 'PHY', 'SC', 40, false, 'UNDER GRADUATE'),
    ('C00030', 'B.Sc. POLITICAL SCIENCE', 'POL', 'SS', 40, false, 'UNDER GRADUATE'),
    ('C00031', 'B.Sc. PSYCHOLOGY', 'PSY', 'SS', 40, false, 'UNDER GRADUATE'),
    ('C00032', 'B.Sc. SOCIOLOGY', 'SOC', 'SS', 40, false, 'UNDER GRADUATE'),
    ('C00033', 'LL.B (LAW)', 'LAW', 'LW', 40, false, 'UNDER GRADUATE'),
    ('C00060', 'B.Sc. BIOLOGY', 'BIO', 'SC', 40, false, 'UNDER GRADUATE'),
    ('C00061', 'MBBS', 'MED', 'BAMS', 40, false, 'UNDER GRADUATE'),
    ('C00062', 'B.A. RELIGIOUS STUDIES', 'RAC', 'AR', 40, false, 'UNDER GRADUATE'),
    ('C00063', 'B.Sc. LIBRARY AND INFORMATION SCIENCE', 'LIS', 'SS', 40, false, 'UNDER GRADUATE'),
    ('C00064', 'B.Sc. MASS COMMUNICATION', 'MCM', 'CM', 40, false, 'UNDER GRADUATE'),
    ('C00065', 'B.ED PRE-PRIMARY AND PRIMARY EDUCATION', 'EDF', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00066', 'B.A.THEATRE ARTS', 'THE', 'AR', 40, false, 'UNDER GRADUATE'),
    ('C00067', 'B.A. HISTORY', 'HST', 'AR', 40, false, 'UNDER GRADUATE'),
    ('C00090', 'B.ED PRE-PRIMARY AND PRIMARY EDUCATION - SOCIAL STUDIES', 'EDF', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00091', 'B.ED PRE-PRIMARY AND PRIMARY EDUCATION - ENGLISH', 'EDF', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00092', 'B.ED PRE-PRIMARY AND PRIMARY EDUCATION - MATHMATICS', 'EDF', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00093', 'B.ED PRE-PRIMARY AND PRIMARY EDUCATION - SCIENCE', 'EDF', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00094', 'B.A. PHILOSOPHY', 'PHL', 'AR', 40, false, 'UNDER GRADUATE'),
    ('C00095', 'B.A. RELIGION AND PHILOSOPHY', 'RAP', 'AR', 40, false, 'UNDER GRADUATE'),
    ('C00096', 'B.Sc. (ED) TECHNOLOGY', 'IND', 'TI', 40, false, 'UNDER GRADUATE'),
    ('C00202', 'B.A. (ED) FRENCH', 'ASS', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00219', 'B.ED EDUCATIONAL MANAGEMENT', 'EDF', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C00220', 'B.ED GUIDANCE AND COUNSELLING', 'EDF', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C13707', 'B.Sc. ADVERTISING', 'ADV', 'CM', 40, false, 'UNDER GRADUATE'),
    ('C18115', 'B.Sc. HUMAN PHYSIOLOGY', 'PGY', 'BAMS', 40, false, 'UNDER GRADUATE'),
    ('C18753', 'B.Sc. (ED) TECHNOLOGY EDUCATION (WOOD WORK)', 'IND', 'TI', 40, false, 'UNDER GRADUATE'),
    ('C22229', 'B.Sc INDUSTRIAL CHEMISTRY', 'CHM', 'SC', 40, false, 'UNDER GRADUATE'),
    ('C22887', 'B.Sc. (ED) TECHNOLOGY EDUCATION (MECH)', 'IND', 'TI', 40, false, 'UNDER GRADUATE'),
    ('C24302', 'B.Sc. (ED) BUSINESS EDUCATION (ACCOUNTING)', 'BTE', 'TI', 40, false, 'UNDER GRADUATE'),
    ('C26841', 'B.ED GUIDANCE AND COUNSELLING-MATHEMATICS', 'EDF', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C27835', 'B. TECHNOLOGY EDUCATION', 'IND', 'TI', 40, false, 'UNDER GRADUATE'),
    ('C29132', 'B.Sc. HUMAN ANATOMY', 'ANT', 'BAMS', 40, false, 'UNDER GRADUATE'),
    ('C30468', 'B.URBAN AND REGIONAL PLANNING', 'URP', 'ES', 40, false, 'UNDER GRADUATE'),
    ('C34921', 'B.A. (ED) RELIGIOUS STUDIES', 'ASS', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C35147', 'BACHELOR OF NURSING SCIENCES', 'NUR', 'BAMS', 40, false, 'UNDER GRADUATE'),
    ('C40831', 'B. Sc. INTERIOR DESIGN', 'ARC', 'AC', 40, false, 'UNDER GRADUATE'),
    ('C43990', 'B.Sc. (ED) TECHNOLOGY EDUCATION (AUTOMOBILE)', 'IND', 'TI', 40, false, 'UNDER GRADUATE'),
    ('C44826', 'B.Sc. (ED) INTEGRATED SCIENCE', 'SME', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C44827', 'B.Sc. FINANCE', 'ACC', 'MS', 40, false, 'UNDER GRADUATE'),
    ('C44828', 'B.Sc. MARKETING', 'BSM', 'MS', 40, false, 'UNDER GRADUATE'),
    ('C44829', 'B.Sc. TAXATION', 'ACC', 'MS', 40, false, 'UNDER GRADUATE'),
    ('C47096', 'B.ED GUIDANCE AND COUNSELLING-SOCIAL STUDIES', 'EDF', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C48372', 'B.Sc. PUBLIC RELATIONS', 'PUR', 'CM', 40, false, 'UNDER GRADUATE'),
    ('C48455', 'B.Sc. (ED) BUSINESS EDUCATION (SECRETARIAL ST', 'BTE', 'TI', 40, false, 'UNDER GRADUATE'),
    ('C49411', 'B.Sc. RADIOGRAPHY AND RADIATION SCIENCE', 'RAD', 'BAMS', 40, false, 'UNDER GRADUATE'),
    ('C49412', 'BACHELOR OF MEDICAL LABORATORY SCIENCE (BMLS)', 'MLS', 'BAMS', 40, false, 'UNDER GRADUATE'),
    ('C49638', 'B.Sc. ZOOLOGY', 'BIO', 'SC', 40, false, 'UNDER GRADUATE'),
    ('C51691', 'B.Sc. PUBLIC ADMINISTRATION', 'PUB', 'MS', 40, false, 'UNDER GRADUATE'),
    ('C51900', 'B. Sc. ARCHITECTURE', 'ARC', 'AC', 40, false, 'UNDER GRADUATE'),
    ('C52295', 'B.Sc. MICROBIOLOGY', 'BIO', 'SC', 40, false, 'UNDER GRADUATE'),
    ('C52395', 'B.Sc. ENVIRONMENTAL MANAGEMENT AND TOXICOLOGY', 'CHM', 'SC', 40, false, 'UNDER GRADUATE'),
    ('C54323', 'B.Sc. (ED) TECHNOLOGY EDUCATION (BUILDING)', 'IND', 'TI', 40, false, 'UNDER GRADUATE'),
    ('C54804', 'B.ED GUIDANCE AND COUNSELLING-SCIENCE', 'EDF', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C55538', 'B.Sc. (ED) TECHNOLOGY EDUCATION (ELECT/ELECTR', 'IND', 'TI', 40, false, 'UNDER GRADUATE'),
    ('C56345', 'B.Sc. STATISTICS', 'MTC', 'SC', 40, false, 'UNDER GRADUATE'),
    ('C60514', 'B.Sc. BROADCASTING', 'BRC', 'CM', 40, false, 'UNDER GRADUATE'),
    ('C62073', 'B.Sc. DEVELOPMENT COMMUNICATION STUDIES', 'DCM', 'CM', 40, false, 'UNDER GRADUATE'),
    ('C62664', 'B.A. (ED) SOCIAL STUDIES', 'ASS', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C64548', 'B.Sc. BIOCHEMISTRY', 'BCH', 'BAMS', 40, false, 'UNDER GRADUATE'),
    ('C67773', 'B.Sc. (ED) BUSINESS EDUCATION', 'BTE', 'TI', 40, false, 'UNDER GRADUATE'),
    ('C67895', 'B.Sc. (ED) COMPUTER SCIENCE', 'SME', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C69405', 'B.A. ENGLISH STUDIES', 'ENG', 'AR', 40, false, 'UNDER GRADUATE'),
    ('C69819', 'B.Sc. (ED) BUSINESS EDUCATION (MARKETING)', 'BTE', 'TI', 40, false, 'UNDER GRADUATE'),
    ('C72222', 'B. Sc. LANDSCAPE ARCHITECTURE', 'ARC', 'AC', 40, false, 'UNDER GRADUATE'),
    ('C73770', 'DOCTOR OF PHARMACY', 'PHM', 'PS', 40, false, 'UNDER GRADUATE'),
    ('C78456', 'B.ED GUIDANCE AND COUNSELLING-ENGLISH', 'EDF', 'ED', 40, false, 'UNDER GRADUATE'),
    ('C78876', 'B.Sc. (ED) HOME ECONOMICS', 'ATC', 'TI', 40, false, 'UNDER GRADUATE'),
    ('C82347', 'B.Sc. PLANT SCIENCE AND BIOTECHNOLOGY', 'BIO', 'SC', 40, false, 'UNDER GRADUATE'),
    ('C89230', 'B.Sc. (ED) TECHNOLOGY EDUCATION (REFRIG/AC)', 'IND', 'TI', 40, false, 'UNDER GRADUATE'),
    ('C94958', 'B.Sc. JOURNALISM AND MEDIA STUDIES', 'JMS', 'CM', 40, false, 'UNDER GRADUATE'),
    ('C95933', 'B.A ENGLISH LITERATURE', 'ENG', 'AR', 40, false, 'UNDER GRADUATE'),
    ('C98602', 'B.Sc. STRATEGIC COMMUNICATIONS', 'SCM', 'CM', 40, false, 'UNDER GRADUATE');

INSERT INTO ref.jamb_alias (code, jamb_name) VALUES
    ('C00001', 'Education & English Language'),
    ('C00002', 'English Language'),
    ('C00003', 'French'),
    ('C00004', 'B.Sc. (ED) HUMAN KINETICS'),
    ('C00005', 'Linguistics'),
    ('C00008', 'B.ED HISTORY'),
    ('C00009', 'B.ED INTEGRATED SCIENCE'),
    ('C00010', 'Physical & Health Education'),
    ('C00012', 'Education & Biology'),
    ('C00014', 'Education & Chemistry'),
    ('C00015', 'B.Sc. (ED) ECONOMICS'),
    ('C00016', 'Education & Mathematics'),
    ('C00017', 'Education & Physics'),
    ('C00019', 'Accounting'),
    ('C00021', 'Business Management'),
    ('C00022', 'B.Sc. CHEMISTRY'),
    ('C00023', 'Computer Science'),
    ('C00024', 'Economics'),
    ('C00025', 'Geography'),
    ('C00028', 'B.Sc. MATHEMATICS'),
    ('C00029', 'Physics'),
    ('C00030', 'Political Science'),
    ('C00031', 'Psychology'),
    ('C00032', 'Sociology'),
    ('C00033', 'Law'),
    ('C00060', 'B.Sc. BIOLOGY'),
    ('C00061', 'Medicine & Surgery'),
    ('C00062', 'Religion & Cultural Studies'),
    ('C00063', 'Library & Information Science'),
    ('C00064', 'Mass Communication'),
    ('C00065', 'Pre-Primary & Primary Education'),
    ('C00066', 'Theatre Arts'),
    ('C00067', 'History'),
    ('C00090', 'B.ED PRE-PRIMARY AND PRIMARY EDUCATION - SOCIAL STUDIES'),
    ('C00091', 'B.ED PRE-PRIMARY AND PRIMARY EDUCATION - ENGLISH'),
    ('C00092', 'B.ED PRE-PRIMARY AND PRIMARY EDUCATION - MATHMATICS'),
    ('C00093', 'B.ED PRE-PRIMARY AND PRIMARY EDUCATION - SCIENCE'),
    ('C00094', 'Philosophy'),
    ('C00095', 'B.A. RELIGION AND PHILOSOPHY'),
    ('C00096', 'Educational Technology'),
    ('C00202', 'B.A. (ED) FRENCH'),
    ('C00219', 'Educational Management'),
    ('C00220', 'Guidance & Counselling'),
    ('C13707', 'Advertising'),
    ('C18115', 'Human Physiology'),
    ('C18753', 'B.Sc. (ED) TECHNOLOGY EDUCATION (WOOD WORK)'),
    ('C22229', 'Industrial Chemistry'),
    ('C22887', 'B.Sc. (ED) TECHNOLOGY EDUCATION (MECH)'),
    ('C24302', 'B.Sc. (ED) BUSINESS EDUCATION (ACCOUNTING)'),
    ('C26841', 'B.ED GUIDANCE AND COUNSELLING-MATHEMATICS'),
    ('C27835', 'B. TECHNOLOGY EDUCATION'),
    ('C29132', 'Anatomy'),
    ('C30468', 'Urban & Regional Planning'),
    ('C34921', 'Education & Religious Studies'),
    ('C35147', 'Nursing Science'),
    ('C40831', 'B. Sc. INTERIOR DESIGN'),
    ('C43990', 'B.Sc. (ED) TECHNOLOGY EDUCATION (AUTOMOBILE)'),
    ('C44826', 'Education & Integrated Science'),
    ('C44827', 'B.Sc. FINANCE'),
    ('C44828', 'Marketing'),
    ('C44829', 'Taxation'),
    ('C47096', 'B.ED GUIDANCE AND COUNSELLING-SOCIAL STUDIES'),
    ('C48372', 'Public Relations'),
    ('C48455', 'B.Sc. (ED) BUSINESS EDUCATION (SECRETARIAL ST'),
    ('C49411', 'Radiography & Radiation Science'),
    ('C49412', 'Medical Laboratory Science'),
    ('C49638', 'Zoology'),
    ('C51691', 'Public Administration'),
    ('C51900', 'Architecture'),
    ('C52295', 'Microbiology'),
    ('C52395', 'Environmental Management & Toxicology'),
    ('C54323', 'B.Sc. (ED) TECHNOLOGY EDUCATION (BUILDING)'),
    ('C54804', 'B.ED GUIDANCE AND COUNSELLING-SCIENCE'),
    ('C55538', 'B.Sc. (ED) TECHNOLOGY EDUCATION (ELECT/ELECTR'),
    ('C56345', 'Statistics'),
    ('C60514', 'B.Sc. BROADCASTING'),
    ('C62073', 'B.Sc. DEVELOPMENT COMMUNICATION STUDIES'),
    ('C62664', 'Social Studies'),
    ('C64548', 'Biochemistry'),
    ('C67773', 'Business Education'),
    ('C67895', 'Education & Computer Science'),
    ('C69405', 'B.A. ENGLISH STUDIES'),
    ('C69819', 'B.Sc. (ED) BUSINESS EDUCATION (MARKETING)'),
    ('C72222', 'B. Sc. LANDSCAPE ARCHITECTURE'),
    ('C73770', 'DOCTOR OF PHARMACY'),
    ('C78456', 'B.ED GUIDANCE AND COUNSELLING-ENGLISH'),
    ('C78876', 'Home Economics & Education'),
    ('C82347', 'Plant Science & Biotechnology'),
    ('C89230', 'B.Sc. (ED) TECHNOLOGY EDUCATION (REFRIG/AC)'),
    ('C94958', 'Journalism & Media Studies'),
    ('C95933', 'B.A ENGLISH LITERATURE'),
    ('C98602', 'B.Sc. STRATEGIC COMMUNICATIONS'),
    ('C99256', 'MA RELIGION AND PEACE STUDIES');

-- ── the file, as it arrived ───────────────────────────────────────────────
CREATE TABLE admissions.caps_batch (
    id            uuid        PRIMARY KEY,
    session       text        NOT NULL,
    source        text        NOT NULL,
    filename      text        NULL,
    file_sha256   bytea       NOT NULL,
    rows_read     int         NOT NULL,
    list_kind     text        NOT NULL,      -- declared BEFORE the file is read
    downloaded_on date        NOT NULL,      -- the date on the CAPS download
    uploaded_at   timestamptz NOT NULL DEFAULT now(),
    uploaded_by   uuid        NOT NULL,
    uploaded_office text      NOT NULL REFERENCES ref.office(code),
    committed_at  timestamptz NULL,
    CONSTRAINT ck_batch_source CHECK (source IN ('CAPS_DOWNLOAD','CAPS_API')),
    CONSTRAINT ck_batch_kind   CHECK (list_kind IN ('UTME','DIRECT_ENTRY')),
    -- Only the two offices that answer for admissions. Not ICT: the
    -- Directorate operates the door, it does not decide who came through it.
    CONSTRAINT ck_batch_office CHECK (uploaded_office IN ('academic','registrar')),
    CONSTRAINT ck_batch_rows   CHECK (rows_read >= 0)
);

COMMENT ON COLUMN admissions.caps_batch.file_sha256 IS
  'The hash of the file exactly as CAPS produced it. An officer downloads the '
  'list repeatedly through the season as it grows, and re-uploading a file '
  'already loaded must be a no-op rather than a second cohort — this is what '
  'makes that answerable without reading 4,000 rows.';

-- Every row as CAPS gave it, unedited, for ever. The candidate record below
-- is DERIVED from this; if the derivation is ever wrong, the evidence of what
-- JAMB actually sent is still here. The same discipline as the score roll:
-- the register is the thing, and the screen is a view of it.
CREATE TABLE admissions.caps_row (
    id            uuid  PRIMARY KEY,
    batch_id      uuid  NOT NULL REFERENCES admissions.caps_batch(id),
    session       text  NOT NULL,
    jamb_reg_no   text  NOT NULL,
    raw           jsonb NOT NULL,
    surname       text  NOT NULL,
    other_names   text  NOT NULL,
    -- JAMB's code, exactly as the file gave it. The programme is resolved
    -- through ref.programme, not stored here as a name somebody typed.
    jamb_code     text  NOT NULL,
    -- The aggregate, and NULL rather than 0 for Direct Entry. The real file
    -- sends 0 with four component scores of 0 and three NULL subject names;
    -- carrying that through as a number ranks twenty-six candidates bottom of
    -- the University on a paper they never sat. Zero is not a score — the same
    -- distinction as ABS on a score sheet, and the same damage.
    aggregate     int   NULL,
    sex           text  NULL,
    state_of_origin text NULL,
    lga           text  NULL,
    entry_mode    text  NOT NULL,
    CONSTRAINT ck_row_entry CHECK (entry_mode IN ('UTME','DIRECT_ENTRY','TRANSFER')),
    CONSTRAINT ck_row_agg CHECK (aggregate IS NULL OR aggregate BETWEEN 1 AND 400),
    CONSTRAINT ck_row_code CHECK (jamb_code ~ '^C[0-9]{5}$'),
    -- The match key is the JAMB registration number and never the name.
    -- Names arrive with the order swapped, with and without middle names, and
    -- spelled two ways in one file. A reconciliation keyed on a name is a
    -- reconciliation that invents people.
    CONSTRAINT uq_caps_row_per_session UNIQUE (session, jamb_reg_no)
);

CREATE INDEX ix_caps_row_batch ON admissions.caps_row (batch_id);

-- ── the two lists must not be loaded as one ───────────────────────────────
-- JAMB approves UTME and Direct Entry separately and they are downloaded as
-- separate files, weeks apart. The list kind is DECLARED on the batch before
-- the file is read, and a row that contradicts the declaration is refused
-- rather than quietly accepted.
--
-- The failure this prevents is specific and expensive. A Direct Entry list
-- loaded as a UTME batch puts four hundred candidates in the register at 100
-- Level with no score, each of them repeating a year they were admitted past
-- — and the error is invisible, because every row looks like a normal
-- admission. It surfaces at the end of the first session, when four hundred
-- students discover they are in the wrong year.
CREATE OR REPLACE FUNCTION admissions.assert_row_matches_batch()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE k text;
BEGIN
    SELECT list_kind INTO k FROM admissions.caps_batch WHERE id = NEW.batch_id;
    IF (k = 'UTME' AND NEW.entry_mode <> 'UTME')
       OR (k = 'DIRECT_ENTRY' AND NEW.entry_mode = 'UTME') THEN
        RAISE EXCEPTION
            'a % row in a batch declared %', NEW.entry_mode, k
        USING ERRCODE = '23514',
              HINT = 'The list kind is declared before the file is read. '
                     'A file whose rows contradict it is the wrong file, and '
                     'it is refused whole rather than loaded and corrected.';
    END IF;
    -- A UTME candidate without a score is a row from the wrong file that
    -- happens to carry the right word.
    IF k = 'UTME' AND NEW.aggregate IS NULL THEN
        RAISE EXCEPTION 'a UTME row with no aggregate' USING ERRCODE = '23514';
    END IF;
    IF k = 'DIRECT_ENTRY' AND NEW.aggregate IS NOT NULL THEN
        RAISE EXCEPTION 'a Direct Entry row carrying an aggregate of %', NEW.aggregate
        USING ERRCODE = '23514',
              HINT = 'Direct Entry candidates do not sit the UTME. An aggregate '
                     'here means the two files have been mixed.';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_row_matches_batch
    BEFORE INSERT OR UPDATE ON admissions.caps_row
    FOR EACH ROW EXECUTE FUNCTION admissions.assert_row_matches_batch();

-- ── the University's own record ───────────────────────────────────────────
CREATE TABLE admissions.candidate (
    id             uuid PRIMARY KEY,
    session        text NOT NULL,
    jamb_reg_no    text NOT NULL,
    admission_no   text NULL,          -- issued here; matriculation comes much later
    surname        text NOT NULL,
    other_names    text NOT NULL,
    programme      text NOT NULL,
    entry_mode     text NOT NULL,
    entry_level    int  NOT NULL,
    offer_state    text NOT NULL,
    admitted_from  uuid NULL REFERENCES admissions.caps_row(id),
    CONSTRAINT uq_candidate_per_session UNIQUE (session, jamb_reg_no),
    CONSTRAINT ck_candidate_state CHECK (offer_state IN
        ('PROPOSED','ADMITTED','ACCEPTED','DECLINED','LAPSED','WITHDRAWN')),
    -- A candidate is ADMITTED only on the strength of a CAPS row. There is no
    -- path in this schema by which somebody becomes admitted without one.
    CONSTRAINT ck_candidate_needs_caps
        CHECK (offer_state = 'PROPOSED' OR admitted_from IS NOT NULL),
    -- UTME enters at 100, Direct Entry at 200 (300 for an HND holder in the
    -- programmes that admit one). A DE candidate placed at 100 repeats a year
    -- the University already admitted him past, and nobody notices until the
    -- end of it.
    CONSTRAINT ck_candidate_level CHECK (
        (entry_mode = 'UTME' AND entry_level = 100) OR
        (entry_mode IN ('DIRECT_ENTRY','TRANSFER') AND entry_level IN (200, 300)))
);

-- ── the reconciliation, counted in both directions ────────────────────────
CREATE OR REPLACE FUNCTION admissions.reconcile(p_session text)
RETURNS TABLE (finding text, n bigint, owner text, what_it_means text)
LANGUAGE sql
STABLE
AS $$
    -- On the CAPS list and not on ours. JAMB admitted them; the University
    -- must honour it. Harmless to fix and fatal to miss.
    SELECT 'On the CAPS list, no candidate record'::text, count(*)::bigint,
           'Academic Office'::text,
           'JAMB admitted them and the University has no record. They arrive '
           'at registration with a CAPS printout and nobody can find them.'::text
      FROM admissions.caps_row r
     WHERE r.session = p_session
       AND NOT EXISTS (SELECT 1 FROM admissions.candidate c
                        WHERE c.session = r.session AND c.jamb_reg_no = r.jamb_reg_no)
    UNION ALL
    -- Ours and not JAMB's. THIS is the serious one.
    SELECT 'Admitted here, not on the CAPS list', count(*)::bigint,
           'Registrar',
           'An admission JAMB did not approve. Left alone it becomes a '
           'matriculation number issued to somebody who was never admitted, '
           'and that number is permanent.'
      FROM admissions.candidate c
     WHERE c.session = p_session
       AND c.offer_state IN ('ADMITTED','ACCEPTED')
       AND NOT EXISTS (SELECT 1 FROM admissions.caps_row r
                        WHERE r.session = c.session AND r.jamb_reg_no = c.jamb_reg_no)
    UNION ALL
    -- Matched, but JAMB admitted them to a different programme.
    SELECT 'Matched, programme differs from CAPS', count(*)::bigint,
           'Academic Office',
           'The candidate is admitted to the programme CAPS says, not the one '
           'we offered. A student taught for a year under the wrong programme '
           'graduates under a degree JAMB has no record of.'
      FROM admissions.candidate c
      JOIN admissions.caps_row r
        ON r.session = c.session AND r.jamb_reg_no = c.jamb_reg_no
      JOIN ref.programme j ON j.code = r.jamb_code
     WHERE c.session = p_session AND c.programme <> j.name
    UNION ALL
    -- A JAMB course code the University has never mapped. Until it is mapped
    -- nobody on that code can be admitted to anything, because there is no
    -- programme to admit them to.
    SELECT 'JAMB course code the University does not run', count(DISTINCT r.jamb_code)::bigint,
           'Academic Office',
           'The code is on the CAPS list and not in the University programme '
           'table, or is archived, or is not an undergraduate programme. '
           'It is refused rather than guessed: the candidate would otherwise '
           'be taught for a year under a programme nobody chose for them.'
      FROM admissions.caps_row r
     WHERE r.session = p_session
       AND NOT EXISTS (SELECT 1 FROM ref.programme p
                        WHERE p.code = r.jamb_code
                          AND NOT p.archived
                          AND p.category = 'UNDER GRADUATE')
    UNION ALL
    -- Matched, but entered at the wrong level for the list they came on.
    SELECT 'Direct Entry candidate entered at the wrong level', count(*)::bigint,
           'Academic Office',
           'A Direct Entry candidate at 100 Level repeats a year the University '
           'admitted them past, and it surfaces at the end of the session.'
      FROM admissions.candidate c
      JOIN admissions.caps_row r
        ON r.session = c.session AND r.jamb_reg_no = c.jamb_reg_no
     WHERE c.session = p_session
       AND r.entry_mode <> 'UTME' AND c.entry_level = 100;
$$;

-- A batch is committed only when every finding is zero or has been worked.
-- Same gate as the results crossing, and for the same reason: a set from
-- another system is a filtered subset by construction, so both counts must
-- close before it becomes the record.
CREATE OR REPLACE FUNCTION admissions.commit_batch(p_batch uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    b admissions.caps_batch;
    outstanding text;
    total bigint;
BEGIN
    SELECT * INTO b FROM admissions.caps_batch WHERE id = p_batch;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no such batch' USING ERRCODE = '23503';
    END IF;
    IF b.committed_at IS NOT NULL THEN
        RETURN 'already committed';           -- idempotent, not an error
    END IF;

    SELECT string_agg(x.finding || ' (' || x.n || ')', '; '), coalesce(sum(x.n), 0)
      INTO outstanding, total
      FROM admissions.reconcile(b.session) x WHERE x.n > 0;

    IF total > 0 THEN
        RAISE EXCEPTION 'the admission list does not reconcile: %', outstanding
        USING ERRCODE = '23514',
              HINT = 'Every finding is a named person and carries an office. '
                     'A list committed with either count non-zero looks '
                     'complete at every desk it passes afterwards.';
    END IF;

    UPDATE admissions.caps_batch SET committed_at = now() WHERE id = p_batch;
    RETURN 'committed';
END $$;

SELECT audit.attach('ref.faculty');
SELECT audit.attach('ref.programme');
SELECT audit.attach('ref.jamb_alias');
SELECT audit.attach('admissions.caps_batch');
SELECT audit.attach('admissions.candidate');

-- The received rows are evidence, not a record of an act: they are what JAMB
-- sent, and the act of receiving them is audited on the batch.
SELECT audit.exempt('admissions.caps_row',
    'The verbatim content of a file from JAMB. The ACT — who uploaded which '
    'file, when, in which office — is audited on admissions.caps_batch; '
    'auditing four thousand rows of somebody else''s list records nothing '
    'about anything the University did.');

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA admissions TO app_admissions;
GRANT SELECT ON ALL TABLES IN SCHEMA admissions TO app_auditor;
