-- ═══════════════════════════════════════
-- V676 — The records left at 100 Level corrected to the level the cohort engine computes
--
-- The University's word of 27 October 2026 ("correct the 100 level records"), after V672 found them: the old portal's students came
-- over at 100 Level and most were never raised. On the live-shaped copy of 21 October 2026, 10,454 active undergraduate records held
-- 100 Level below the level the cohort engine (V331) computes for them — entered from 2007/2008 to 2024/2025, 5,238 of them registered
-- above 100 since — and every document, fee line, gate and receipt that reads the record read 100 for a student in their final year
-- or in spillover.
--
-- The correction is V475's (people.level_correction, people.apply_level_corrections), never a raw update: the level the engine
-- computes — the programme's final level for a student past the programme's length (SPILLOVER: SP1, SP2 or the limit reached), the
-- level the student's own registrations reach (REGISTRATION), or the count of sessions from the entry (ARITHMETIC) — never lowered,
-- each change on the cohort decision history (rule LEVEL_<basis>, batch V676-LEVELS-100) and carried into the current session's
-- registration and enrolment at the level corrected from (V641). On the copy: SPILLOVER 10,317 (SP1 5,016, SP2 3,395, the limit
-- reached 1,906), REGISTRATION 15, ARITHMETIC 122; to 400 Level 8,759, 500 1,333, 600 338, 300 11, 200 13.
--
-- Now:
--   1. people.correct_levels_from(level, reason, batch): every record at that level the engine computes higher is corrected by
--      apply_level_corrections, a batch of 500 at a time, on all three bases; then the current session's registrations below the level
--      on record are raised to it (V673, people.raise_registrations_to_record), and the courses already on the registration of a
--      student now in spillover, in their current session, are carry-overs they declared (V674). Returns the students corrected (by
--      basis), the registrations raised and the courses made carry-overs. Academic Office, Registry, the platform; safe to run again.
--   2. Run once now for 100 Level.
-- Nothing else changes: status, programme, matriculation and entry are the record's; a student past the spillover limit stays as the
-- Registry leaves them (V558); the spillover fee is owed only for a semester registered (V616). The fees follow the level: on the
-- copy, of 200 corrected students drawn at random, 195 were charged 2025/2026 school fees at 100 Level (₦34,423,027.66 due, all) and
-- are charged ₦537,150.00 once corrected — in spillover nothing until a semester is registered. On the copy the run takes 83 seconds
-- (21 batches; 13 courses on 2025/2026 registrations made carry-overs).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V676: the records left at 100 Level corrected to the level the cohort engine computes', true);

CREATE FUNCTION people.correct_levels_from(p_from_level integer, p_reason text, p_batch text)
RETURNS TABLE(students integer, spillover integer, registration integer, arithmetic integer, registrations_raised integer, entries_carried integer)
LANGUAGE plpgsql AS $fn$
DECLARE r record; rr record; n_batches int := 0; n_done int := 0; n_carried int;
BEGIN
    IF p_from_level IS NULL THEN
        RAISE EXCEPTION 'LEVEL_CORRECTION_LEVEL: name the level on record to correct' USING ERRCODE = '23514';
    END IF;
    -- V475: the Academic Office's correction (its office, its reason, its history), a batch at a time until none is left
    LOOP
        SELECT * INTO r FROM people.apply_level_corrections(NULL, ARRAY['SPILLOVER', 'REGISTRATION', 'ARITHMETIC'], NULL, NULL, NULL,
                                                            p_reason, p_batch, 500, false, NULL, NULL, NULL, p_from_level);
        n_done := n_done + r.corrected;
        n_batches := n_batches + 1;
        EXIT WHEN r.corrected = 0 OR r.remaining = 0 OR n_batches >= 1000;
    END LOOP;
    SELECT count(*) FILTER (WHERE d.rule = 'LEVEL_SPILLOVER'), count(*) FILTER (WHERE d.rule = 'LEVEL_REGISTRATION'), count(*) FILTER (WHERE d.rule = 'LEVEL_ARITHMETIC')
      INTO spillover, registration, arithmetic
      FROM people.cohort_decision d WHERE d.batch_ref = p_batch AND d.decided_at = now();
    students := n_done;
    -- V673: the current session's registrations below the level now on record
    SELECT * INTO rr FROM people.raise_registrations_to_record();
    registrations_raised := rr.registrations;
    -- V674: a spillover student registers carry-overs only — the courses already on a registration of theirs in their current session
    WITH sp AS (SELECT st.id FROM people.student st
                 WHERE st.status NOT IN ('GRADUATED') AND finance.spill(st.id, st.current_level, st.programme_code, st.status)),
    moved AS (
        UPDATE registration.entry e SET entry_type = 'CARRYOVER', added_as = 'CARRY_OVER_DECLARED'
          FROM registration.course_registration cr
         WHERE cr.id = e.registration_id AND cr.student_id IN (SELECT sp.id FROM sp)
           AND e.entry_type NOT IN ('CARRYOVER', 'DEFERRED', 'REPEAT') AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
           AND registration.spillover_registration(cr.student_id, cr.session)
        RETURNING e.registration_id)
    SELECT count(*) INTO n_carried FROM moved;
    entries_carried := n_carried;
    RETURN NEXT;
END $fn$;
COMMENT ON FUNCTION people.correct_levels_from(integer, text, text) IS
  'V676: every record at the level named that the cohort engine computes higher corrected by people.apply_level_corrections (V475: '
  'SPILLOVER, REGISTRATION and ARITHMETIC; never lowered; each change on the cohort decision history under the batch named), a batch '
  'of 500 at a time; then the current session''s registrations below the level on record raised (V673) and a spillover student''s '
  'courses of their current session made carry-overs (V674). Academic Office, Registry, the platform. Safe to run again.';

DO $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM people.correct_levels_from(100,
        'The University''s word of 27 October 2026: the records left at 100 Level corrected to the level the cohort engine computes (V676)',
        'V676-LEVELS-100');
    RAISE NOTICE 'V676: % record(s) corrected from 100 Level (spillover %, registration %, arithmetic %); % registration(s) raised; % course(s) made carry-overs',
        r.students, r.spillover, r.registration, r.arithmetic, r.registrations_raised, r.entries_carried;
END $$;

COMMIT;
