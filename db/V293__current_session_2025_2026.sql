-- ═══════════════════════════════════════════════════════════════════════════
-- V293 — 2025/2026 is the University's session, in its second semester, not a completed one
--
-- V013 marked 2025/2026 CLOSED on every database it built ("the last session is
-- over"), an assumption made when the design expected 2026/2027 to be running by
-- now. It is not: the University is in the second semester of 2025/2026, and
-- 2026/2027 is planned. A database built fresh (a new host, as on AWS) therefore
-- read 2025/2026 as Completed, and the portal rightly refuses to make a completed
-- session current again from the calendar ("The session is completed and cannot
-- become current again"), so no screen could put it right.
--
-- The correction is made only where the record shows it is that assumption and
-- nothing a person did: 2025/2026 CLOSED with no completion recorded
-- (completed_at, which every real completion sets since V289), no session
-- current, and no transition out of 2025/2026 in the log. Then 2025/2026 is put
-- back to PLANNED, its first semester Completed and its second Open. It is not
-- made CURRENT here: a current session carries the Senate minute that resolved
-- to run it (ck_session_current_has_minute), and a migration does not invent
-- one. The Registrar makes 2025/2026 current on the Calendar, quoting the
-- minute, through the transition every session takes (V289): checked, one
-- transaction, logged. Anywhere a person has since run the calendar, nothing
-- changes.
--
-- The session's DATES are not changed here: the seeded 31 August 2026 end has
-- passed, and the Academic Office sets the real dates (2025/2026's end, and
-- 2026/2027's start after it) on the Calendar screen.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V293: 2025/2026 is the current session', true);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM policy.academic_session WHERE name = '2025/2026' AND state = 'CLOSED' AND completed_at IS NULL)
       AND NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE state = 'CURRENT')
       AND NOT EXISTS (SELECT 1 FROM policy.session_transition WHERE from_session = '2025/2026' AND outcome = 'DONE')
    THEN
        UPDATE policy.academic_session SET state = 'PLANNED' WHERE name = '2025/2026';
        INSERT INTO policy.semester (id, session, number, state) VALUES (gen_random_uuid(), '2025/2026', 1, 'CLOSED'), (gen_random_uuid(), '2025/2026', 2, 'OPEN')
        ON CONFLICT (session, number) DO UPDATE SET state = EXCLUDED.state;
        RAISE NOTICE 'V293: 2025/2026 is PLANNED again, first semester Completed, second Open; the Registrar makes it current on the Calendar with its Senate minute';
    ELSE
        RAISE NOTICE 'V293: nothing changed; the calendar here has been set by a person';
    END IF;
END $$;

COMMIT;
