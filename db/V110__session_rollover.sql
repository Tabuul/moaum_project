-- ── V110 — the session roll-over: promote continuing students into a new session ──
-- Between sessions the register moves up a year. Fresh students arrive through
-- admission at 100 level; the continuing students already on the register need
-- their level advanced and an enrolment opened for the new session. This does
-- that in one guarded call:
--
--   · opens the new session (and its semesters) if it does not exist yet, as a
--     PLANNED session — the Registry still makes it CURRENT under a Senate
--     minute when it is ready;
--   · advances every ACTIVE or PROBATION, matriculated student one level, up to
--     the programme's final level, and enrols them in the new session.
--
-- Left untouched: fresh (unmatriculated ADMITTED) students, final-year students
-- at their final level (they graduate), and anyone WITHDRAWN, SUSPENDED,
-- RUSTICATED, DEFERRED, TRANSFERRED_OUT, DORMANT, DECEASED or GRADUATED.
-- Arrears are not moved — finance.position derives them live from prior
-- sessions, so an unpaid year still shows and still gates. It is idempotent: a
-- student already enrolled in the new session is neither promoted again nor
-- enrolled twice.

CREATE OR REPLACE FUNCTION people.roll_over_session(p_to_session text, p_confirm text, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_created boolean := false; v_promoted int := 0; r record;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a session roll-over is made by a person' USING ERRCODE = '23514';
    END IF;
    IF upper(btrim(coalesce(p_confirm, ''))) <> 'ROLLOVER' THEN
        RAISE EXCEPTION 'type ROLLOVER to confirm promoting continuing students into %', p_to_session USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'a session roll-over names its reason' USING ERRCODE = '23514';
    END IF;
    IF p_to_session !~ '^[0-9]{4}/[0-9]{4}$' THEN
        RAISE EXCEPTION 'a session is named YYYY/YYYY, not %', p_to_session USING ERRCODE = '23514';
    END IF;

    -- open the target session (and its two semesters) if it is not there yet, as PLANNED
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_to_session) THEN
        PERFORM assessment.ensure_session(p_to_session);
        UPDATE policy.academic_session SET state = 'PLANNED' WHERE name = p_to_session;
        v_created := true;
    END IF;

    FOR r IN
        SELECT s.id, s.current_level + 100 AS new_level
          FROM people.student s
         WHERE s.status IN ('ACTIVE', 'PROBATION')
           AND s.matric_no IS NOT NULL
           AND s.current_level < coalesce(finance.final_level(s.programme_code), 400)
           AND NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.student_id = s.id AND e.session = p_to_session)
    LOOP
        UPDATE people.student SET current_level = r.new_level WHERE id = r.id;
        INSERT INTO people.enrolment (id, student_id, session, level)
        VALUES (gen_random_uuid(), r.id, p_to_session, r.new_level)
        ON CONFLICT (student_id, session) DO NOTHING;
        v_promoted := v_promoted + 1;
    END LOOP;

    RETURN jsonb_build_object('session', p_to_session, 'created_session', v_created,
                             'promoted', v_promoted, 'reason', btrim(p_reason));
END $$;

COMMENT ON FUNCTION people.roll_over_session(text, text, text) IS
'Promote continuing students one level into a new session and enrol them; opens the session as PLANNED if new. Guarded by an actor, the word ROLLOVER and a reason; idempotent.';
