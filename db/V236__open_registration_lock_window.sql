-- ═══════════════════════════════════════════════════════════════════════════
-- V236 — opening registration holds the offerings table for milliseconds, not seconds
--
--   registration.open_course_registration disables the offerings audit trigger
--   while it inserts (an audit-light bulk, by design). DISABLE TRIGGER takes an
--   ACCESS EXCLUSIVE lock on catalogue.offering that lasts to the end of the
--   transaction — and in V127 the INSERT … SELECT that decides which courses to
--   offer ran INSIDE that window. V235 made that decision look at the register
--   (a course of a track is offered while a student of that track remains), and
--   on a register of tens of thousands the decision took seconds. Every other
--   write to an offering — a Head of Department allocating a lecturer — waited
--   behind it, and a Save timed out.
--
--   Now the decision is taken first, into a temporary table, with the index it
--   wants; the trigger is disabled only for the insert of the rows already
--   chosen, and re-enabled at once.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE INDEX IF NOT EXISTS ix_student_programme_track
    ON people.student (programme_code, curriculum_track)
 WHERE status IN ('ACTIVE','PROBATION','ADMITTED');

CREATE OR REPLACE FUNCTION registration.open_course_registration(p_session text, p_semester int)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, catalogue, registration, ref, policy
AS $$
DECLARE v_count int;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'course registration is opened by a person' USING ERRCODE = '23514';
    END IF;
    IF p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN
        RAISE EXCEPTION 'no academic session % on the calendar — open the session first', p_session USING ERRCODE = '23503';
    END IF;

    -- 1 · decide, before any lock: the courses of this semester that some structure row offers for any
    --     track, or for a track that still has a student in that programme
    CREATE TEMP TABLE IF NOT EXISTS to_offer (course_code text PRIMARY KEY) ON COMMIT DROP;
    TRUNCATE to_offer;
    WITH live AS (
        SELECT DISTINCT st.programme_code, st.curriculum_track
          FROM people.student st
         WHERE st.status IN ('ACTIVE','PROBATION','ADMITTED')
    )
    INSERT INTO to_offer (course_code)
    SELECT DISTINCT c.code
      FROM catalogue.course c
      JOIN catalogue.course_offer co ON co.course_code = c.code
     WHERE c.semester = p_semester
       AND c.state <> 'ENDED'
       AND (co.track IS NULL
            OR EXISTS (SELECT 1 FROM live l WHERE l.programme_code = co.programme_code AND l.curriculum_track = co.track))
       AND NOT EXISTS (SELECT 1 FROM catalogue.offering o
                        WHERE o.course_code = c.code AND o.session = p_session AND o.semester = p_semester);

    -- 2 · insert the rows already chosen, with the audit trigger off for exactly that long
    ALTER TABLE catalogue.offering DISABLE TRIGGER trg_audit_catalogue_offering;
    INSERT INTO catalogue.offering (id, course_code, session, semester)
    SELECT gen_random_uuid(), t.course_code, p_session, p_semester FROM to_offer t;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ALTER TABLE catalogue.offering ENABLE TRIGGER trg_audit_catalogue_offering;

    RETURN v_count;
END $$;

COMMIT;
