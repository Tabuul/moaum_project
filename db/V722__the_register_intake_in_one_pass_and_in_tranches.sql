-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V722 · The register intake in one pass, and in tranches
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  On 11 November 2026 the Admissions dashboard's "Bring 2,359 candidates onto the register" stopped at the screen's read limit
--  ("This took longer than the portal allows a screen to read"). people.intake (V278) brought the admitted candidates onto the
--  register one by one, and every people.student it inserted fired trg_position_student_insert → people.position_touch →
--  people.refresh_academic_position for that one student: on the live-shaped copy 117 ms of each candidate's 125 ms went to that
--  refresh, so 2,359 candidates were some five minutes of one statement. V463 already defers the position triggers inside a
--  register upload (people.defer_positions / people.refresh_deferred_positions: the students noted, refreshed together at the end
--  in one statement — the positions of 2,400 students computed together in under two seconds on the same copy). The intake now
--  runs the same way, one run of a session at a time, and runs in tranches:
--
--    people.intake_tranche(p_session, p_limit) — the session's admitted candidates not yet on the register, by surname, at most
--        p_limit of them (NULL or under one: all), each brought on by people.intake_one as before; a per-session advisory lock so a
--        second run waits for the first and then takes what is still off the register; the position triggers deferred for the run
--        and the run's students refreshed together once; returns how many were brought on and how many remain.
--    people.intake(p_session) — as before (every candidate, the count brought on), now the one-pass run.
--
--  The API's POST /api/v1/student/intake/{session} takes ?limit and answers {broughtOnto, remaining}; the dashboard calls it in
--  tranches until none remain, showing the progress, so no single request runs longer than a screen is allowed. (The API's own
--  read limit is on read-only transactions alone; the cut on the live portal came from outside the API — a statement_timeout on the
--  database, a role or the connection options, or a cancel request — which the database's log line names.)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', false),
       set_config('moaum.actor_office', 'ict', false),
       set_config('moaum.reason', 'V722: the register intake in one pass and in tranches', false);

CREATE OR REPLACE FUNCTION people.intake_tranche(p_session text, p_limit int DEFAULT NULL)
RETURNS TABLE (brought int, remaining int)
LANGUAGE plpgsql AS $$
DECLARE c record; v_n int := 0; v_began boolean;
BEGIN
    -- one run of a session at a time: a second run (another officer, another tab, a resent request) waits for the first to commit
    -- and then reads what is still off the register, instead of racing it onto ux_student_candidate (V429) for the same candidate
    PERFORM pg_advisory_xact_lock(hashtext('people.intake:' || p_session));
    -- V463's deferral: each student the triggers would refresh is noted, and the run's students are refreshed together at the end
    v_began := people.defer_positions();
    FOR c IN
        SELECT a.id FROM admissions.candidate a
         WHERE a.session = p_session AND a.offer_state IN ('ADMITTED', 'ACCEPTED')
           AND NOT EXISTS (SELECT 1 FROM people.student s WHERE s.candidate_id = a.id)
         ORDER BY a.surname, a.other_names, a.id
         LIMIT CASE WHEN p_limit IS NULL OR p_limit < 1 THEN NULL ELSE p_limit END
    LOOP
        PERFORM people.intake_one(c.id);
        v_n := v_n + 1;
    END LOOP;
    IF v_began THEN PERFORM people.refresh_deferred_positions(); END IF;
    RETURN QUERY
        SELECT v_n,
               (SELECT count(*)::int FROM admissions.candidate a
                 WHERE a.session = p_session AND a.offer_state IN ('ADMITTED', 'ACCEPTED')
                   AND NOT EXISTS (SELECT 1 FROM people.student s WHERE s.candidate_id = a.id));
END $$;
COMMENT ON FUNCTION people.intake_tranche(text, int) IS
  'V722: the session''s admitted candidates not yet on the register brought on by surname, at most p_limit of them (NULL or under one: all), each by people.intake_one; one run of a session at a time (an advisory lock per session); the academic position triggers deferred for the run and the run''s students refreshed together once (V463). Returns how many were brought on and how many remain.';

-- the intake run as V278 declared it: every admitted candidate, the count brought on — now the one-pass run
CREATE OR REPLACE FUNCTION people.intake(p_session text)
RETURNS integer LANGUAGE sql AS $$
    SELECT t.brought FROM people.intake_tranche(p_session, NULL) t;
$$;
COMMENT ON FUNCTION people.intake(text) IS
  'V722: the session''s admitted candidates brought onto the register in one pass — people.intake_tranche with no limit — the academic positions refreshed together once, not once a student.';
