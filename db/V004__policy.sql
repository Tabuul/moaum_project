-- ═══════════════════════════════════════════════════════════════════════════
-- V004 — effective-dated policy, and the shape D-Q4's answer drops into
--
-- ADR-015 and ADR-019: policy is versioned, effective-dated DATA — "rows with
-- date ranges and exclusion constraints, not settings". P4: policy is data.
--
-- The reason is not tidiness. A transcript printed in 2041 for a 1994 degree
-- must classify that degree under the scheme Senate had in force in 1994, and
-- a student's entitlement in September 2026 is a question about the schedule
-- in force then. A settings table holds one answer; this holds the answer for
-- any date you ask about.
--
-- ── The one property this file exists for ─────────────────────────────────
--
-- D-Q4 — which services each fee instalment unlocks — has been with the
-- Bursar four weeks. `policy.clearance_scheme` therefore ships EMPTY, and the
-- loader below REFUSES when nothing is in force.
--
-- That is the whole point, and it is worth being explicit about why. An empty
-- policy table that defaulted to "allowed" would mean four weeks of silence
-- had quietly let unpaid students register — the failure would be invisible,
-- and it would look exactly like the system working. Policy fails CLOSED.
-- An unanswered question stops the queue; it does not open the gate.
--
-- When the marked page comes back from the Bursary it is an INSERT, not a
-- build. That is what makes it safe to have shipped the shape ahead of the
-- answer.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ── the session, which policy hangs off ───────────────────────────────────
-- `policy` is the one shared schema a real foreign key may point at (DBD
-- §4.2): every module reads it, only the owner writes it.
CREATE TABLE policy.academic_session (
    id          uuid PRIMARY KEY,
    name        text NOT NULL UNIQUE,        -- '2026/2027'
    starts_on   date NOT NULL,
    ends_on     date NOT NULL,
    CONSTRAINT ck_session_dates CHECK (ends_on > starts_on),
    CONSTRAINT ck_session_name  CHECK (name ~ '^[0-9]{4}/[0-9]{4}$')
);

INSERT INTO policy.academic_session (id, name, starts_on, ends_on) VALUES
    (gen_random_uuid(), '2025/2026', date '2025-10-01', date '2026-08-31'),
    (gen_random_uuid(), '2026/2027', date '2026-10-01', date '2027-08-31');

-- ── what a policy version looks like, whatever it holds ───────────────────
-- One shape for every effective-dated policy in the University, so the
-- overlap rule is written once and cannot be forgotten on the sixth one.
CREATE TABLE policy.version (
    id          uuid     PRIMARY KEY,
    kind        text     NOT NULL,           -- 'clearance' | 'grading' | 'fees' | …
    scope       text     NOT NULL,           -- 'UNIVERSITY' | 'FACULTY:sci' | …
    validity    daterange NOT NULL,
    instrument  text     NOT NULL,           -- the resolution that made it policy
    decided_by  text     NOT NULL REFERENCES ref.office(code),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_version_instrument CHECK (length(btrim(instrument)) > 0),

    -- I-FIN-8. Two versions of one policy for one scope may not overlap in
    -- time. Without this, "which scheme was in force on 14 March" has two
    -- answers, and the transcript printed that day cannot be reproduced.
    CONSTRAINT ex_version_no_overlap
        EXCLUDE USING gist (kind WITH =, scope WITH =, validity WITH &&)
);

COMMENT ON COLUMN policy.version.instrument IS
  'The Council or Senate resolution the policy rests on. A policy nobody '
  'decided is a setting somebody typed, and this column is the difference.';

-- ── the clearance scheme: D-Q4's shape ────────────────────────────────────

CREATE TABLE ref.clearance_purpose (
    code   text PRIMARY KEY,
    label  text NOT NULL,
    note   text
);

INSERT INTO ref.clearance_purpose (code, label, note) VALUES
 ('REGISTRATION', 'Course registration',              'The gate in front of everything below'),
 ('ID_CARD',      'Identity card',                    'Issued once, on the matriculation number'),
 ('LIBRARY',      'Library borrowing',                'The Library also clears at graduation'),
 ('HOSTEL',       'Hostel allocation',                'Charged separately from the session charge'),
 ('EXAMINATION',  'Sitting an examination',           'The docket, and a CBT paper'),
 ('RESULTS',      'Semester result release',          'Seeing a mark already approved by Senate'),
 ('TRANSCRIPT',   'Transcript issue',                 'Requested at any time, including years later'),
 ('CONVOCATION',  'Convocation and the certificate',  'Checked before convocation, not after');

CREATE TABLE policy.clearance_scheme (
    version_id        uuid PRIMARY KEY REFERENCES policy.version(id) ON DELETE RESTRICT,
    arrears_block_all boolean NOT NULL
);

CREATE TABLE policy.clearance_rule (
    version_id  uuid NOT NULL REFERENCES policy.clearance_scheme(version_id) ON DELETE RESTRICT,
    purpose     text NOT NULL REFERENCES ref.clearance_purpose(code),
    releases_at text NOT NULL,
    PRIMARY KEY (version_id, purpose),
    CONSTRAINT ck_rule_releases CHECK (releases_at IN
        ('INSTALMENT_1','INSTALMENT_2','PAID_IN_FULL','NEVER_GATED'))
);

-- A scheme that names only some of the purposes is worse than none: the
-- unnamed ones would resolve to whatever the loader defaults to, which is the
-- silence this design keeps removing. A scheme is complete or it is not a
-- scheme.
CREATE OR REPLACE FUNCTION policy.assert_scheme_complete(p_version uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE missing text;
BEGIN
    SELECT string_agg(p.code, ', ' ORDER BY p.code) INTO missing
      FROM ref.clearance_purpose p
     WHERE NOT EXISTS (SELECT 1 FROM policy.clearance_rule r
                        WHERE r.version_id = p_version AND r.purpose = p.code);
    IF missing IS NOT NULL THEN
        RAISE EXCEPTION 'incomplete clearance scheme — no rule for: %', missing
        USING ERRCODE = '23514',
              HINT = 'Every purpose in ref.clearance_purpose must be named. '
                     'A purpose left out resolves to whatever the loader assumes, '
                     'and an assumption is what this table exists to replace.';
    END IF;
END $$;

-- ── the loader ────────────────────────────────────────────────────────────
-- One function answers "what was in force on this date", for every policy.
CREATE OR REPLACE FUNCTION policy.in_force(p_kind text, p_scope text, p_at date)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT v.id FROM policy.version v
     WHERE v.kind = p_kind AND v.scope = p_scope AND v.validity @> p_at;
$$;

-- ── the clearance predicate ───────────────────────────────────────────────
-- BR-001. Called synchronously by CRG, RES, CBT, CTP and SIM; never cached,
-- because the answer is a function of live data and a stale answer either
-- lets an unpaid student register or blocks one who has paid.
--
-- `p_instalments_paid` and `p_has_arrears` come from the finance module in
-- the same transaction. This function decides only what the POLICY says.
CREATE OR REPLACE FUNCTION policy.clears(
    p_purpose          text,
    p_instalments_paid int,
    p_paid_in_full     boolean,
    p_has_arrears      boolean,
    p_at               date DEFAULT current_date,
    p_scope            text DEFAULT 'UNIVERSITY')
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_version uuid;
    v_at      text;
    v_arrears boolean;
BEGIN
    v_version := policy.in_force('clearance', p_scope, p_at);

    -- FAIL CLOSED. This is the branch D-Q4 is sitting in.
    IF v_version IS NULL THEN
        RAISE EXCEPTION
            'no clearance scheme in force for % on % — D-Q4 is unanswered',
            p_scope, p_at
        USING ERRCODE = '23514',
              HINT = 'Which services each fee instalment unlocks is the Bursar''s '
                     'decision (D-Q4, memorandum ICT/MOAUMPP/2026/02). Until a '
                     'scheme is recorded, clearance refuses rather than assumes. '
                     'An unanswered question stops the queue; it does not open the gate.';
    END IF;

    SELECT r.releases_at, s.arrears_block_all INTO v_at, v_arrears
      FROM policy.clearance_rule r
      JOIN policy.clearance_scheme s ON s.version_id = r.version_id
     WHERE r.version_id = v_version AND r.purpose = p_purpose;

    IF v_at IS NULL THEN
        RAISE EXCEPTION 'no clearance rule for purpose % in the scheme in force', p_purpose
        USING ERRCODE = '23514';
    END IF;

    IF v_at = 'NEVER_GATED' THEN
        RETURN true;                       -- not withheld for money at all
    END IF;

    IF v_arrears AND p_has_arrears THEN
        RETURN false;                      -- a balance carried forward blocks everything
    END IF;

    RETURN CASE v_at
        WHEN 'INSTALMENT_1' THEN p_instalments_paid >= 1
        WHEN 'INSTALMENT_2' THEN p_instalments_paid >= 2
        WHEN 'PAID_IN_FULL' THEN p_paid_in_full
    END;
END $$;

COMMENT ON FUNCTION policy.clears(text,int,boolean,boolean,date,text) IS
  'BR-001. Refuses rather than assumes when no scheme is in force. Never '
  'cached: the answer is a function of live data, and a stale answer either '
  'lets an unpaid student register or blocks one who has paid.';

-- ── grading, to show the shape carries a second policy unchanged ──────────
CREATE TABLE policy.grade_band (
    version_id uuid NOT NULL REFERENCES policy.version(id) ON DELETE RESTRICT,
    grade      text NOT NULL,
    low        int  NOT NULL,
    high       int  NOT NULL,
    points     numeric(3,2) NOT NULL,
    PRIMARY KEY (version_id, grade),
    CONSTRAINT ck_band_range  CHECK (high >= low AND low >= 0 AND high <= 100),
    CONSTRAINT ck_band_points CHECK (points >= 0 AND points <= 5),
    -- a mark cannot fall in two bands, or in none
    CONSTRAINT ex_band_no_overlap
        EXCLUDE USING gist (version_id WITH =, int4range(low, high, '[]') WITH &&)
);

DO $$
DECLARE v uuid := gen_random_uuid();
BEGIN
    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
    VALUES (v, 'grading', 'UNIVERSITY', daterange(date '2015-10-01', NULL), 'SEN/2015/44', 'registrar');
    INSERT INTO policy.grade_band (version_id, grade, low, high, points) VALUES
        (v, 'A', 70, 100, 5.00), (v, 'B', 60, 69, 4.00), (v, 'C', 50, 59, 3.00),
        (v, 'D', 45, 49, 2.00),  (v, 'E', 40, 44, 1.00), (v, 'F',  0, 39, 0.00);
END $$;

CREATE OR REPLACE FUNCTION policy.grade_of(p_mark int, p_at date DEFAULT current_date)
RETURNS TABLE (grade text, points numeric)
LANGUAGE sql
STABLE
AS $$
    SELECT b.grade, b.points
      FROM policy.grade_band b
     WHERE b.version_id = policy.in_force('grading', 'UNIVERSITY', p_at)
       AND p_mark BETWEEN b.low AND b.high;
$$;

GRANT SELECT ON ALL TABLES IN SCHEMA policy, ref TO
    app_iam, app_student, app_admissions, app_registration, app_results,
    app_acrecords, app_credentials, app_finance, app_payments, app_expenditure,
    app_notification, app_governance, app_reporting, app_apimgmt, app_platform,
    app_auditor;

-- Only the Bursary's module writes the clearance scheme; only Senate's writes
-- grading. Enforced as grants, not as a convention.
GRANT INSERT, UPDATE ON policy.version, policy.clearance_scheme, policy.clearance_rule
    TO app_finance;
GRANT INSERT, UPDATE ON policy.version, policy.grade_band TO app_results;


-- ── policy and the register go on the spine ───────────────────────────────
-- Attached at the END of this migration, so the baseline above is established
-- by the migration itself and every change after it is attributed to a person
-- and an office. A quiet widening of what an instalment unlocks is precisely
-- the change this makes impossible to make anonymously.
SELECT audit.attach('ref.office');
SELECT audit.attach('ref.clearance_purpose');
SELECT audit.attach('policy.academic_session');
SELECT audit.attach('policy.version');
SELECT audit.attach('policy.clearance_scheme');
SELECT audit.attach('policy.clearance_rule');
SELECT audit.attach('policy.grade_band');
