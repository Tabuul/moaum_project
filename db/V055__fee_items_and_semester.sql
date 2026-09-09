-- ═══════════════════════════════════════════════════════════════════════════
-- V055 — payment categories as data, and a fee item scoped to a semester
--
--   The fee-setup form typed the item name by hand. This makes the item a
--   choice from a managed set of payment categories (ref.fee_item) — School
--   Fees, Acceptance, Registration, Development Levy, and the rest — so the
--   same charge is named the same way every session, while still allowing a
--   one-off name where a category does not fit.
--
--   A fee item can now also be scoped to a semester (finance.fee_schedule
--   .semester): NULL is the whole session, 1 or 2 charges only in that
--   semester. finance.charges honours it against the session's OPEN semester
--   (policy.semester) — an existing item, which carries no semester, is
--   unaffected, so nothing a student already owes changes.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- the payment categories, as data (seeded before the spine is attached, like ref.programme)
CREATE TABLE ref.fee_item (
    code text PRIMARY KEY,
    name text NOT NULL,
    ord  int  NOT NULL DEFAULT 0
);
INSERT INTO ref.fee_item (code, name, ord) VALUES
    ('SCHOOL_FEES',    'School Fees',            10),
    ('ACCEPTANCE',     'Acceptance Fee',         20),
    ('REGISTRATION',   'Registration',           30),
    ('DEVELOPMENT',    'Development Levy',        40),
    ('LIBRARY',        'Library',                50),
    ('ICT',            'ICT / Technology',       60),
    ('MEDICAL',        'Medical',                70),
    ('SPORTS',         'Sports',                 80),
    ('EXAMINATION',    'Examination',            90),
    ('LABORATORY',     'Studio / Laboratory',   100),
    ('HOSTEL',         'Hostel / Accommodation',110),
    ('GST',            'General Studies (GST)',  120),
    ('EPS',            'Entrepreneurship (EPS)', 130),
    ('POST_UTME',      'Post-UTME Screening',    140),
    ('ID_CARD',        'Identity Card',          150),
    ('CONVOCATION',    'Convocation',            160);
SELECT audit.attach('ref.fee_item');

-- a fee item may be scoped to a semester; NULL is the whole session
ALTER TABLE finance.fee_schedule ADD COLUMN IF NOT EXISTS semester int NULL;
ALTER TABLE finance.fee_schedule
    DROP CONSTRAINT IF EXISTS ck_fee_semester,
    ADD CONSTRAINT ck_fee_semester CHECK (semester IS NULL OR semester IN (1, 2, 3));
COMMENT ON COLUMN finance.fee_schedule.semester IS
    'The semester the charge applies in (policy.semester.number). NULL is the whole '
    'session; 1 or 2 charges only while that semester is open.';

-- charges honour the semester against the session's OPEN semester; a NULL-semester
-- item (every item until now) applies whatever the semester
CREATE OR REPLACE FUNCTION finance.charges(p_student uuid, p_session text)
RETURNS TABLE (id uuid, item text, amount numeric, ord int)
LANGUAGE sql STABLE AS $$
    SELECT f.id, f.item, f.amount, f.ord
      FROM finance.fee_schedule f
      JOIN people.student s ON s.id = p_student
      JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND (f.level IS NULL OR f.level = s.current_level)
       AND (f.entry_mode IS NULL OR f.entry_mode = s.entry_mode)
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
       AND (f.programme_code IS NULL OR f.programme_code = s.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND (f.semester IS NULL
            OR f.semester = (SELECT sm.number FROM policy.semester sm
                              WHERE sm.session = p_session AND sm.state = 'OPEN'
                              ORDER BY sm.number LIMIT 1))
     ORDER BY f.ord, f.item;
$$;

COMMIT;
