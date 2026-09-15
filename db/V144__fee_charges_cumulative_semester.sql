-- ═══════════════════════════════════════════════════════════════════════════
-- V144 — fee charge accumulates across the session's semesters
--
--   Since V055 finance.charges showed a fee item only when its semester was
--   NULL or equal to the CURRENTLY OPEN semester. So once second semester opens,
--   items tagged first-semester dropped out of the charge — a second-semester
--   student saw no fee (and any unpaid first-semester balance vanished). Fees
--   should accumulate, not disappear: an item shows once its semester has been
--   reached and stays on the charge for the rest of the session.
--
--   The only change from V088 is the semester clause: f.semester <= the highest
--   open/reached semester (whole-session items, semester NULL, always show; with
--   no semester open the whole session's items show). Everything else — level,
--   entry mode, faculty, programme, fee group, indigene, spillover — is unchanged.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION finance.charges(p_student uuid, p_session text)
RETURNS TABLE (id uuid, item text, amount numeric, ord int)
LANGUAGE sql STABLE AS $$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS (
        SELECT s.id, s.programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               coalesce(s.current_level > finance.final_level(s.programme_code) AND s.status <> 'GRADUATED', false) AS is_spill
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.id = p_student)
    SELECT f.id, f.item, f.amount, f.ord
      FROM finance.fee_schedule f
      CROSS JOIN me
      JOIN ref.programme p ON p.code = me.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
      CROSS JOIN home
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND f.spillover = me.is_spill
       AND (me.is_spill OR f.level IS NULL OR f.level = me.current_level)
       AND (f.entry_mode IS NULL OR f.entry_mode = me.entry_mode)
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)))
       AND (f.semester IS NULL
            OR f.semester <= coalesce((SELECT max(sm.number) FROM policy.semester sm
                                        WHERE sm.session = p_session AND sm.state = 'OPEN'), 3))
     ORDER BY f.ord, f.item;
$$;

COMMIT;
