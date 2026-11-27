-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V787 · the Summer Semester no longer refuses a course whose result of this session is awaited
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The user's word (27 November 2026): "remove result awaited policy from summer registration so student pick any course and register,
--  no restriction for summer registration". V779's pool (registration.summer_selectable) read a course the student registered in the First
--  or Second Semester of the session, with no published result yet, as RESULT_AWAITED and refused it (SUMMER_COURSE_REFUSED: result awaited);
--  the page showed it with no tick box. From V787 it is selectable like any other course of the pool. Its evidence still reads Result awaited
--  — for the Academic Office, who verifies a selection no result confirms (PENDING_VERIFICATION, charged as STUDENT_SELECTED) — and the rest
--  is as V779 made it: a pass on record (the course or its twin) is never selectable, nor is a course already selected or registered, decided
--  by the Office, ended or a SIWES course. A selection whose result then publishes as a pass is taken back or flagged by the reconcile, as
--  any selection is.
--  Restated by one fragment of the live text, exactly once, behind a presence check of V779's text.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V787: the Summer registration no longer refuses a course whose result is awaited', true);

DO $$
BEGIN
    IF (SELECT md5(replace(p.prosrc, E'\r', '')) FROM pg_proc p WHERE p.oid = to_regprocedure('registration.summer_selectable(uuid,text)')) IS DISTINCT FROM '0fbefb6985304c3cdc1fc7225e1df203' THEN
        RAISE EXCEPTION 'V787: registration.summer_selectable(uuid,text) is not as V779 left it (restate this migration from its live text)';
    END IF;
END $$;

DO $v787$
DECLARE d text := replace(pg_get_functiondef('registration.summer_selectable(uuid,text)'::regprocedure), E'\r', '');
        a text := $a$                    WHEN x.ev = 'RESULT_PASSED' THEN 'PASSED'
                    WHEN x.ev = 'RESULT_AWAITED' THEN 'RESULT_AWAITED' END AS why$a$;
BEGIN
    IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN
        RAISE EXCEPTION 'V787: registration.summer_selectable(uuid,text) is not as it was left (the anchor is not there exactly once)';
    END IF;
    EXECUTE replace(d, a, $r$                    WHEN x.ev = 'RESULT_PASSED' THEN 'PASSED' END AS why$r$);
END $v787$;

COMMENT ON FUNCTION registration.summer_selectable(uuid,text) IS
  'V779: the courses a student may select for the Summer of a session, each with the evidence the results give, the units the programme gives it, the course as it was taken (V771), the selection and its verification, selectable or why not (COURSE_UNKNOWN, COURSE_ENDED, ALREADY_REGISTERED, ALREADY_SELECTED, DECIDED_NOT_OUTSTANDING, DECIDED_REJECTED, SIWES_OWN_PAGE, PASSED) and the fee. The pool is the programme''s structure up to its final level (never bounded by the level on record), the courses detected as owed and the courses the Academic Office named. A missing result is never a pass and never proof of nothing owed. A course whose result of this session is awaited is selectable like any other (V787): the evidence says RESULT_AWAITED, nothing refuses it.';

COMMIT;
