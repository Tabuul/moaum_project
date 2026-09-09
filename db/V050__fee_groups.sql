-- ═══════════════════════════════════════════════════════════════════════════
-- V050 — fee groups: charge by programme category, not one programme at a time
--
--   A fee schedule item can already be scoped to a level, an entry mode, a
--   faculty or a single programme. This adds a group — Undergraduate,
--   Postgraduate, General Studies (GST), Entrepreneurship (EPS) — so a charge
--   can be stated once for everyone in a category rather than programme by
--   programme. The groups are rows in ref.fee_group, so the set is data, not
--   code: adding a group with the category it targets is all it takes to make
--   it a choice on the fee-setup form and to have it applied in the position.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE ref.fee_group (
    code             text PRIMARY KEY,
    name             text NOT NULL,
    applies_category text NULL,     -- ref.programme.category it targets; NULL = every student
    ord              int  NOT NULL DEFAULT 0,
    CONSTRAINT ck_fee_group_cat CHECK (applies_category IS NULL OR applies_category IN ('UNDER GRADUATE','POST GRADUATE'))
);
-- seeded before the spine is attached, the way ref.programme is, so the seed needs no actor
INSERT INTO ref.fee_group (code, name, applies_category, ord) VALUES
    ('UG',  'Undergraduate',          'UNDER GRADUATE', 10),
    ('PG',  'Postgraduate',           'POST GRADUATE',  20),
    ('GST', 'General Studies (GST)',  'UNDER GRADUATE', 30),
    ('EPS', 'Entrepreneurship (EPS)', 'UNDER GRADUATE', 40);
SELECT audit.attach('ref.fee_group');

ALTER TABLE finance.fee_schedule
    ADD COLUMN IF NOT EXISTS fee_group text NULL REFERENCES ref.fee_group(code);

COMMENT ON COLUMN finance.fee_schedule.fee_group IS
    'The group of students the charge applies to (ref.fee_group). NULL means it is not '
    'scoped by group; when set, the charge applies only to students in the group''s category.';

-- charges now honour the group: an item scoped to a group applies to a student only
-- when the group targets their programme category (or targets every category)
CREATE OR REPLACE FUNCTION finance.charges(p_student uuid, p_session text)
RETURNS TABLE (id uuid, item text, amount numeric, ord int)
LANGUAGE sql STABLE AS $$
    SELECT f.id, f.item, f.amount, f.ord
      FROM finance.fee_schedule f, people.student s
      JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
     WHERE s.id = p_student AND f.session = p_session AND f.ended_at IS NULL
       AND (f.level IS NULL OR f.level = s.current_level)
       AND (f.entry_mode IS NULL OR f.entry_mode = s.entry_mode)
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
       AND (f.programme_code IS NULL OR f.programme_code = s.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
     ORDER BY f.ord, f.item;
$$;
