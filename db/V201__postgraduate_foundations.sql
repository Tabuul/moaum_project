-- ═══════════════════════════════════════════════════════════════════════════
-- V201 — Postgraduate foundations (Phase 0)
--
--   The academic spine is built for undergraduates: study levels are the fixed
--   set 100–600, admissions runs off JAMB/CAPS, and a programme is distinguished
--   only by its name and its UNDER GRADUATE / POST GRADUATE category. This lays
--   the ground for postgraduate students without disturbing any of that:
--
--     • widen the study-level enums to admit the postgraduate levels 700, 800
--       and 900 — the convention is PGD → 700, a Master's → 800, a doctorate
--       (MPhil/PhD) → 900 — everywhere a level is checked;
--     • add the School of Postgraduate Studies' two offices at institution scope
--       (its Dean and its Secretary), alongside the existing offices;
--     • give ref.programme a structured postgraduate award and a research flag,
--       so a programme carries whether it is a PGD/MSc/PhD and whether it ends in
--       a thesis — the admission and classification code reads the structure, not
--       the free-text name;
--     • add unit bounds for the postgraduate levels;
--     • seed a handful of postgraduate programmes to admit into.
--
--   The offer path, the merit engine and every undergraduate rule are untouched.
--   Postgraduate admissions (Phase 1) is built on top of this, separately.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- the audit spine refuses a write with no actor, and ref.office, ref.programme and
-- policy.level_limit are on it; attribute this migration's seed rows to the system actor.
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'academic', true);
SELECT set_config('moaum.reason', 'Postgraduate foundations: levels, offices, awards, PG programmes (V201)', true);

-- ── 1 · widen the study-level enums to admit 700/800/900 ────────────────────
ALTER TABLE people.student      DROP CONSTRAINT ck_student_level;
ALTER TABLE people.student      ADD  CONSTRAINT ck_student_level
    CHECK (current_level IN (100,200,300,400,500,600,700,800,900)
       AND entry_level   IN (100,200,300,400,500,600,700,800,900));

ALTER TABLE people.enrolment    DROP CONSTRAINT ck_enrolment_level;
ALTER TABLE people.enrolment    ADD  CONSTRAINT ck_enrolment_level
    CHECK (level IN (100,200,300,400,500,600,700,800,900));

ALTER TABLE catalogue.course    DROP CONSTRAINT ck_course_level;
ALTER TABLE catalogue.course    ADD  CONSTRAINT ck_course_level
    CHECK (level IN (100,200,300,400,500,600,700,800,900));

ALTER TABLE policy.level_limit  DROP CONSTRAINT ck_level_limit_level;
ALTER TABLE policy.level_limit  ADD  CONSTRAINT ck_level_limit_level
    CHECK (level IN (100,200,300,400,500,600,700,800,900));

ALTER TABLE finance.fee_schedule DROP CONSTRAINT ck_fee_level;
ALTER TABLE finance.fee_schedule ADD  CONSTRAINT ck_fee_level
    CHECK (level IS NULL OR level IN (100,200,300,400,500,600,700,800,900));

-- ── 2 · the School of Postgraduate Studies' offices ─────────────────────────
INSERT INTO ref.office (code, label, scope_kind) VALUES
    ('pgschool',    'Dean, School of Postgraduate Studies',      'institution'),
    ('pgsecretary', 'Secretary, School of Postgraduate Studies', 'institution');

-- ── 3 · the postgraduate award and the research flag on a programme ─────────
-- Optional and value-checked, not required: the structure-upload (V091) may load
-- a postgraduate programme before an award is stated, and the free-text name still
-- carries it. The admission and classification code prefers the structured award.
ALTER TABLE ref.programme ADD COLUMN pg_award    text    NULL;
ALTER TABLE ref.programme ADD COLUMN pg_research boolean NOT NULL DEFAULT false;
ALTER TABLE ref.programme ADD CONSTRAINT ck_prog_pg_award
    CHECK (pg_award IS NULL OR pg_award IN ('PGD','MSC','MA','MBA','MPA','MED','LLM','MPHIL','PHD'));

COMMENT ON COLUMN ref.programme.pg_award IS
  'The postgraduate award a POST GRADUATE programme leads to (PGD/MSC/…/PHD); NULL for undergraduate '
  'programmes and for any postgraduate programme whose award has not been stated structurally yet.';
COMMENT ON COLUMN ref.programme.pg_research IS
  'True when the programme ends in a thesis/dissertation (a research or mixed degree), so admission '
  'requires a proposal and graduation requires an examined thesis. Always false for undergraduate programmes.';

-- ── 4 · unit bounds for the postgraduate levels ─────────────────────────────
-- Research years carry few or no taught units, so the floor is low; the ceiling is
-- generous to hold coursework plus a weighty thesis registration.
INSERT INTO policy.level_limit (level, applies_to, min_units, max_units) VALUES
    (700, 'Postgraduate Diploma',        9, 48),
    (800, 'Master''s degree',            6, 48),
    (900, 'MPhil / Doctoral degree',     0, 48);

-- ── 5 · a first set of postgraduate programmes to admit into ────────────────
-- Hung off existing departments and faculties (no separate postgraduate tier, by
-- design). min_score is a UTME cut-off and does not apply, so it is zero.
INSERT INTO ref.programme (code, name, dept_code, faculty_code, min_score, archived, category, pg_award, pg_research) VALUES
    ('C90001', 'Postgraduate Diploma in Computer Science', 'MTC', 'SC', 0, false, 'POST GRADUATE', 'PGD',   false),
    ('C90002', 'M.Sc. Computer Science',                   'MTC', 'SC', 0, false, 'POST GRADUATE', 'MSC',   true),
    ('C90003', 'Ph.D. Computer Science',                   'MTC', 'SC', 0, false, 'POST GRADUATE', 'PHD',   true),
    ('C90004', 'M.Sc. Economics',                          'ECO', 'SS', 0, false, 'POST GRADUATE', 'MSC',   true),
    ('C90005', 'Ph.D. Economics',                          'ECO', 'SS', 0, false, 'POST GRADUATE', 'PHD',   true);

COMMIT;
