-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V743 · The review of V742 applied
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  A review of V742 (two readers, each finding put to a refuter) confirmed three; the database's are answered here, with one the review of
--  V743 found in V742 itself.
--    · registration.summer_course_outstanding read the pass through the pool's reason, and the pool names an ended (or unknown) course
--      before a passed one: a course the Academic Office authorised, passed since and then ended read as outstanding, so a payment
--      confirmed anyway paid for it (and the desk was told it had ended, not that it was passed). The pass is now tested itself, as the
--      pool tests it; an ended course not passed stays outstanding (once paid, the desk's issue, V739).
--    · The test costs a pool reading, yet carried the default cost: the planner ran it on every Summer course charge in the table before
--      narrowing to the reference's own (one payable test measured at 1.9 s with 48 charges in the table, once it had statistics), and
--      payable runs at checkout, at the gateways' validation and on the student's page. It is declared at its cost, and payable reads the
--      reference's own course charges first.
--    · V742's notice said the reallocations at the old count were "listed for the Bursary": they are counted, not listed and not changed.
--      The count is given again below in those words (the docs say so too).
--    · (the check's agreement of the bulk and per-student readers is made to bite in check.sql)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V743: the review of V742 applied', true);

-- COST: a pool reading and a results reading per call; declared so the planner calls it last, on the fewest rows (a later restatement
-- must repeat it: CREATE OR REPLACE without COST puts back the default)
CREATE OR REPLACE FUNCTION registration.summer_course_outstanding(p_student uuid, p_session text, p_course text) RETURNS boolean LANGUAGE sql STABLE COST 100000 AS $$
    SELECT EXISTS (SELECT 1 FROM registration.summer_courses(p_student, p_session) sc
                    WHERE sc.course_code = p_course AND coalesce(sc.reason, '') <> 'PASSED')
       -- V743: the pass itself, as summer_courses reads it — its reason names an ended or unknown course before a passed one
       AND NOT EXISTS (SELECT 1 FROM assessment.student_results(p_student) r
                        WHERE r.course_code = p_course AND r.published AND r.outcome = 'GRADED' AND r.points > 0);
$$;
COMMENT ON FUNCTION registration.summer_course_outstanding(uuid, text, text) IS
    'V742, V743: true while a course is in the student''s Summer pool and not passed (the pass read itself, whatever else the pool says of the course). A reference holding a course no longer outstanding is not payable, and a payment confirmed anyway takes the course back rather than pay it.';

-- ── a reference's own course charges are read first, then each tested (V743) ──
CREATE OR REPLACE FUNCTION registration.summer_reference_payable(p_reference text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((
        SELECT r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now() AND r.student_id IS NOT NULL
               AND registration.summer_open(r.session)
               AND EXISTS (SELECT 1 FROM registration.summer_reference_charge rc WHERE rc.reference_id = r.id)
               AND NOT EXISTS (SELECT 1 FROM registration.summer_reference_charge rc JOIN registration.summer_charge c ON c.id = rc.charge_id
                                WHERE rc.reference_id = r.id AND c.state <> 'DUE')
               AND NOT EXISTS (SELECT 1 FROM registration.summer_charge c
                                WHERE c.student_id = r.student_id AND c.session = r.session AND c.state = 'DUE'
                                  AND NOT EXISTS (SELECT 1 FROM registration.summer_reference_charge rc WHERE rc.reference_id = r.id AND rc.charge_id = c.id))
               AND NOT EXISTS (SELECT 1 FROM registration.summer_reference_charge rc JOIN registration.summer_charge c ON c.id = rc.charge_id
                                 JOIN catalogue.course k ON k.code = c.course_code
                                WHERE rc.reference_id = r.id AND k.state = 'ENDED')   -- V739
               AND NOT EXISTS (SELECT 1 FROM (SELECT c.student_id, c.session, c.course_code
                                                FROM registration.summer_reference_charge rc JOIN registration.summer_charge c ON c.id = rc.charge_id
                                               WHERE rc.reference_id = r.id AND c.kind = 'COURSE' OFFSET 0) x   -- V743: the reference's own, first
                                WHERE NOT registration.summer_course_outstanding(x.student_id, x.session, x.course_code))   -- V742: passed since
               AND r.amount = (SELECT sum(c.amount) FROM registration.summer_reference_charge rc JOIN registration.summer_charge c ON c.id = rc.charge_id
                                WHERE rc.reference_id = r.id)
          FROM finance.payment_reference r
         WHERE r.reference = upper(btrim(coalesce(p_reference, ''))) AND r.purpose LIKE 'Summer semester fees%'), false);
$$;

-- what is affected now: Summer course charges still owed for a course the student has passed (taken back at the next draw or payment)
DO $$
DECLARE n int; n_moves int;
BEGIN
    SELECT count(*) INTO n FROM registration.summer_charge c
     WHERE c.kind = 'COURSE' AND c.state = 'DUE' AND NOT registration.summer_course_outstanding(c.student_id, c.session, c.course_code);
    -- V742's count in the right words: counted, not listed, not changed
    SELECT count(*) INTO n_moves FROM finance.payment_reallocation r JOIN people.student st ON st.id = r.student_id
     WHERE st.entry_mode NOT IN ('CCE', 'POSTGRADUATE')
       AND EXISTS (SELECT 1 FROM policy.cohort_start cs WHERE cs.admission_session = policy.session_normal(st.entry_session))
       AND r.to_level IS DISTINCT FROM people.level_in(r.student_id, r.to_session);
    RAISE NOTICE 'V743: % Summer course charges still owed for a course no longer outstanding (taken back at the student''s next draw or payment); % payment reallocations of first-year-count students name a level other than the session''s count now (counted, not listed, not changed: V742''s notice said listed)',
        n, n_moves;
END $$;

COMMIT;
