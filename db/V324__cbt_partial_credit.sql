-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V324 — partial credit for multiple-select questions, per examination
--
--   A multiple-select question (V322) earned its marks only when the chosen options were exactly its key. An
--   examination may now say otherwise: with partial credit on, each correctly chosen option earns an equal share
--   of the question's marks, each wrongly chosen option costs a share, and the question never scores below zero —
--   so partial knowledge counts and "select everything" earns nothing. Off by default: a paper already set scores
--   exactly as before. The rule is on the examination, not the question, so one paper is marked one way.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V324: partial credit for multiple-select questions, per examination', true);

ALTER TABLE assessment.cbt_exam ADD COLUMN IF NOT EXISTS partial_credit boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN assessment.cbt_exam.partial_credit IS
  'V324: how a multiple-select question is marked on this paper. Off: the marks only for exactly the key. On: each correct option chosen earns marks/|key|, each wrong one costs marks/|key|, never below zero.';

/* the marks one answer earns on one question, by the examination's rule */
CREATE OR REPLACE FUNCTION assessment.cbt_marks_for(p_kind text, p_key int[], p_chosen int[], p_marks int, p_partial boolean)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_chosen IS NULL OR cardinality(p_chosen) = 0 THEN 0
        WHEN p_chosen = p_key THEN p_marks::numeric
        WHEN p_partial AND p_kind = 'MULTI' AND cardinality(p_key) > 0 THEN
            round(greatest(0, p_marks::numeric * ((SELECT count(*) FROM unnest(p_chosen) c WHERE c = ANY (p_key))
                                                   - (SELECT count(*) FROM unnest(p_chosen) c WHERE NOT (c = ANY (p_key)))) / cardinality(p_key)), 2)
        ELSE 0 END
$$;
COMMENT ON FUNCTION assessment.cbt_marks_for(text, int[], int[], int, boolean) IS
  'The marks an answer earns (V324): all for exactly the key; with partial credit on a multiple-select question, (right − wrong) / |key| of the marks, never below zero; otherwise nothing.';

/* finalising, as V322, with the marking rule read from the examination */
CREATE OR REPLACE FUNCTION assessment.cbt_finalize(p_attempt uuid, p_status text, p_reason text)
RETURNS assessment.cbt_attempt LANGUAGE plpgsql AS $$
DECLARE a assessment.cbt_attempt; e assessment.cbt_exam; v_score numeric := 0; v_pct numeric; v_grade text;
BEGIN
    SELECT * INTO a FROM assessment.cbt_attempt WHERE id = p_attempt FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_ATTEMPT_NOT_FOUND: no such attempt' USING ERRCODE = '23503'; END IF;
    IF a.status <> 'IN_PROGRESS' THEN RETURN a; END IF;
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = a.exam_id;
    SELECT coalesce(sum(assessment.cbt_marks_for(q.kind, q.answers, an.chosen, p.marks, e.partial_credit)), 0) INTO v_score
      FROM unnest(a.question_ids) qid
      JOIN assessment.cbt_pool(a.exam_id) p ON p.question_id = qid
      JOIN assessment.question q ON q.id = qid
      LEFT JOIN assessment.cbt_answer an ON an.attempt_id = a.id AND an.question_id = qid;
    v_pct := round(v_score * 100.0 / greatest(a.max_marks, 1), 2);
    SELECT g.grade INTO v_grade FROM policy.grade_of(least(100, greatest(0, round(v_pct)))::int) g LIMIT 1;
    UPDATE assessment.cbt_attempt
       SET status = p_status, submitted_at = now(), score = v_score, percentage = v_pct, grade = v_grade, passed = (v_pct >= e.pass_mark),
           answered = (SELECT count(*) FROM assessment.cbt_answer WHERE attempt_id = a.id),
           finished_reason = nullif(btrim(coalesce(p_reason, '')), ''),
           finished_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, finished_office = nullif(current_setting('moaum.actor_office', true), ''),
           last_activity_at = now()
     WHERE id = a.id RETURNING * INTO a;
    INSERT INTO assessment.cbt_result (attempt_id, version, score, max_marks, percentage, grade, passed, changed_by, changed_office)
    VALUES (a.id, 1, v_score, a.max_marks, v_pct, v_grade, a.passed, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
    PERFORM assessment.cbt_log(a.id, CASE p_status WHEN 'SUBMITTED' THEN 'SUBMITTED' WHEN 'TIME_EXPIRED' THEN 'TIME_EXPIRED' ELSE 'TERMINATED' END, false,
                               format('%s of %s marks (%s%%, %s)%s%s', v_score, a.max_marks, v_pct, coalesce(v_grade, '—'),
                                      CASE WHEN e.partial_credit THEN ' · partial credit on multiple-select' ELSE '' END,
                                      CASE WHEN p_reason IS NULL THEN '' ELSE ' · ' || p_reason END), NULL);
    RETURN a;
END $$;

/* creating an examination with the marking rule; the V322 form stands and marks all-or-nothing */
CREATE OR REPLACE FUNCTION assessment.cbt_new_exam(p_office text, p_offering uuid, p_title text, p_instructions text, p_duration int, p_total int,
                                                    p_selection text, p_random_q boolean, p_random_o boolean, p_pass numeric, p_attempts int,
                                                    p_security text, p_venue text, p_violation_limit int, p_violation_action text, p_second_session text,
                                                    p_starts timestamptz, p_ends timestamptz, p_partial boolean)
RETURNS assessment.cbt_exam LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam;
BEGIN
    e := assessment.cbt_new_exam(p_office, p_offering, p_title, p_instructions, p_duration, p_total, p_selection, p_random_q, p_random_o, p_pass, p_attempts,
                                 p_security, p_venue, p_violation_limit, p_violation_action, p_second_session, p_starts, p_ends);
    UPDATE assessment.cbt_exam SET partial_credit = coalesce(p_partial, false) WHERE id = e.id RETURNING * INTO e;
    RETURN e;
END $$;

/* what the student reads, as V322, with the marking rule so the instructions can say it */
DROP FUNCTION IF EXISTS assessment.cbt_student_exams(uuid, text);
CREATE FUNCTION assessment.cbt_student_exams(p_student uuid, p_session text)
RETURNS TABLE (exam_id uuid, reference text, office text, course_code text, course_title text, title text, session text, semester int, instructions text,
               live_state text, starts_at timestamptz, ends_at timestamptz, duration_minutes int, questions int, security_mode text, venue text,
               attempt_limit int, violation_limit int, violation_action text, eligibility text, attempts int,
               attempt_id uuid, attempt_status text, attempt_ends_at timestamptz, submitted_at timestamptz,
               result_published boolean, score numeric, max_marks int, percentage numeric, grade text, passed boolean, pass_mark numeric, outcome text, partial_credit boolean)
LANGUAGE sql STABLE AS $$
    WITH mine AS (SELECT DISTINCT en.offering_id FROM registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
                   WHERE cr.student_id = p_student AND (p_session IS NULL OR cr.session = p_session)
                     AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')),
    att AS (SELECT DISTINCT ON (a.exam_id) a.* FROM assessment.cbt_attempt a WHERE a.student_id = p_student ORDER BY a.exam_id, a.number DESC),
    cnt AS (SELECT a.exam_id, count(*)::int AS attempts FROM assessment.cbt_attempt a WHERE a.student_id = p_student GROUP BY a.exam_id)
    SELECT e.id, e.reference, e.office, e.course_code, c.title, e.title, e.session, e.semester, e.instructions,
           assessment.cbt_live_state(e), e.starts_at, e.ends_at, e.duration_minutes,
           CASE WHEN e.selection = 'RANDOM' THEN e.total_questions ELSE (SELECT count(*)::int FROM assessment.cbt_pool(e.id)) END,
           e.security_mode, e.venue, e.attempt_limit, e.violation_limit, e.violation_action,
           CASE WHEN a.status = 'IN_PROGRESS' THEN NULL ELSE assessment.cbt_eligibility(e.id, p_student) END,
           coalesce(cn.attempts, 0), a.id, a.status, a.ends_at, a.submitted_at,
           (e.results_state = 'PUBLISHED'),
           CASE WHEN e.results_state = 'PUBLISHED' THEN a.score END, CASE WHEN e.results_state = 'PUBLISHED' THEN a.max_marks END,
           CASE WHEN e.results_state = 'PUBLISHED' THEN a.percentage END, CASE WHEN e.results_state = 'PUBLISHED' THEN a.grade END,
           CASE WHEN e.results_state = 'PUBLISHED' THEN a.passed END, e.pass_mark, CASE WHEN e.results_state = 'PUBLISHED' THEN a.outcome END,
           e.partial_credit
      FROM assessment.cbt_exam e JOIN mine m ON m.offering_id = e.offering_id JOIN catalogue.course c ON c.code = e.course_code
      LEFT JOIN att a ON a.exam_id = e.id LEFT JOIN cnt cn ON cn.exam_id = e.id
     WHERE e.state IN ('PUBLISHED', 'CLOSED', 'COMPLETED')
     ORDER BY e.starts_at DESC NULLS LAST, e.title
$$;

COMMIT;
