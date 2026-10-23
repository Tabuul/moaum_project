-- ═══════════════════════════════════════
-- V645 — A 400 Level student registers their courses whatever their GST history
--
-- The University's word of 23 October 2026, on a 400 Level student refused her second-semester courses ("you are required to pay
-- the GST fee of NGN 4,000.00 for 2025/2026 before you can register your courses"): "ignore all GST course registration history
-- and allow all 400 level students who doesn't register their GST in the past to go ahead and register their courses".
--
-- What a student owes for GST/EPS is read by finance.gst_eps_rows (V366, V422): the programme's GST/EPS courses at the student's
-- level offered in the session, a GST/EPS course failed before (a carry-over), and a GST/EPS course on the session's
-- registration. A 400 Level student who never took a 100- or 200-level GST course and puts it on this session's registration
-- (GST 111, say) owes the session's GST fee for it, as every student does; and where the Bursary holds every course on the fee
-- (finance.gst_setting.required_for_all) the registration gate (registration.gst_gate) then refused every other course of the
-- session — the departmental courses of the final year — until it was paid.
--
-- Now:
--   · registration.gst_history_only(student, session): the student is at 400 Level and every GST/EPS course that makes the fee
--     owed is of their history — a carry-over, or a course of an earlier level — none of their own level;
--   · registration.gst_gate: for such a student the fee no longer holds any course but a GST/EPS course. Their departmental
--     courses register, and the registration submits, as if nothing were owed.
-- Unchanged: what is owed and paid (the GST desk, the fee, the student's GST & EPS page); a GST/EPS course itself is held until the
-- fee is paid, so the GST & EPS examination permit (V589, read through the gate on each GST/EPS course) prints only once paid;
-- a 400 Level student who owes for a GST/EPS course of their own level, and a student at any other level, are held as before.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V645: a 400 Level student registers their courses whatever their GST history (the University, 23 October 2026)', true);

-- ── 1 · a 400 Level student whose GST fee is owed for their GST history only ─────────────────────────────────────────────
CREATE FUNCTION registration.gst_history_only(p_student uuid, p_session text)
RETURNS boolean LANGUAGE sql STABLE AS $$
    -- the level the session reads the student at, as finance.gst_eps_rows reads it
    WITH lv AS (SELECT CASE WHEN p_session >= coalesce((SELECT max(name) FROM policy.academic_session WHERE state = 'CURRENT'), '')
                            THEN s.current_level
                            ELSE (SELECT max(cr.level) FROM registration.course_registration cr WHERE cr.student_id = s.id AND cr.session = p_session) END AS level
                  FROM people.student s WHERE s.id = p_student),
         owed AS MATERIALIZED (SELECT r.source, r.level FROM finance.gst_eps_rows(p_session, p_student) r WHERE r.counts)
    SELECT coalesce((SELECT level FROM lv) = 400, false)
       AND EXISTS (SELECT 1 FROM owed)
       AND NOT EXISTS (SELECT 1 FROM owed o, lv WHERE o.source <> 'CARRYOVER' AND (o.level IS NULL OR o.level >= lv.level))
$$;
COMMENT ON FUNCTION registration.gst_history_only(uuid, text) IS
  'V645: the student is at 400 Level and every GST/EPS course that makes the session''s GST fee owed (finance.gst_eps_rows) is of their '
  'history — a carry-over, or a course of an earlier level — none of their own level. Such a student''s GST fee holds no course but a '
  'GST/EPS course (registration.gst_gate).';

-- ── 2 · the gate: such a student registers every course but a GST/EPS course before paying ───────────────────────────────
CREATE OR REPLACE FUNCTION registration.gst_gate(p_student uuid, p_session text, p_course text)
RETURNS text LANGUAGE sql STABLE AS $$
    WITH c AS (SELECT kind, general_office FROM catalogue.course WHERE code = p_course),
         g AS (SELECT * FROM finance.gst_setting WHERE id = 1),
         e AS (SELECT * FROM finance.gst_entitlement(p_student, p_session))
    SELECT CASE WHEN e.required AND e.stated AND e.fee > 0 AND NOT e.entitled
                     AND ((g.required_for_gst_eps AND c.kind = 'GST' AND c.general_office IS NOT NULL AND (c.general_office = 'GST' OR g.covers_eps))
                          OR g.required_for_all)
                -- V645: a GST/EPS course is held as before; any other course is held unless the student is at 400 Level and owes
                -- for their GST history only (read last, so the engine is asked only of a student it may concern)
                THEN CASE WHEN (c.kind = 'GST' AND c.general_office IS NOT NULL) OR NOT registration.gst_history_only(p_student, p_session)
                          THEN 'GST_PAYMENT_REQUIRED: you are required to pay the GST fee of NGN ' || to_char(e.fee, 'FM999,999,999,990.00') || ' for ' || p_session
                               || ' before you can register ' || CASE WHEN c.general_office IS NOT NULL THEN c.general_office || ' courses' ELSE 'your courses' END
                               || '. GST payment covers both GST and EPS requirements.' END
                -- V643: a GST/EPS course the registration page shows, not yet owed (taken, it would be): paid for first, so the save is
                -- never refused on the course after it
                WHEN NOT e.required AND e.stated AND e.fee > 0 AND NOT e.entitled
                     AND c.kind = 'GST' AND c.general_office IS NOT NULL
                     AND ((g.required_for_gst_eps AND (c.general_office = 'GST' OR g.covers_eps)) OR g.required_for_all)
                THEN CASE WHEN EXISTS (SELECT 1 FROM finance.gst_payable_courses(p_student, p_session) pc WHERE pc.course_code = p_course)
                          THEN 'GST_PAYMENT_REQUIRED: you are required to pay the GST fee of NGN ' || to_char(e.fee, 'FM999,999,999,990.00') || ' for ' || p_session
                               || ' before you can register ' || c.general_office || ' courses. GST payment covers both GST and EPS requirements.' END
                ELSE NULL END
      FROM g CROSS JOIN e LEFT JOIN c ON true
$$;
COMMENT ON FUNCTION registration.gst_gate(uuid, text, text) IS
  'V314/V366/V367/V643/V645: why the GST fee holds a course from the student''s registration, or NULL — owed and not paid, a GST/EPS '
  'course (or every course under the Bursary''s required-for-all, except (V645) for a 400 Level student who owes for their GST history '
  'only, a carry-over or a course of an earlier level: only the GST/EPS course is held); (V643) a GST/EPS course the registration page '
  'shows the student, not yet owed, until the fee is paid.';

COMMIT;
