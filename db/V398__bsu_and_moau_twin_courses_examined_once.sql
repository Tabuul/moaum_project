-- ═══════════════════════════════════════
-- V398 — a BSU- course and its MOAU- twin are examined once
--
--   V396 linked the pair (catalogue.course_twin) and made it one class for allocation, timetable and register. The
--   examination stayed per code: the paper's slot was set twice and each code needed its own CBT examination. Now:
--     · the examination slot set on either class of a pair is the slot of both — the Examinations Office's slot is written
--       to both classes (QueriesController), and linking a pair copies a slot already set on one class to the other;
--     · a CBT examination set on either class seats the candidates of both: the candidate list, its count, the notices, the
--       student's own list of examinations and the eligibility check read the pair (catalogue.offering_family); the
--       attendance bar is the student's own class's; each candidate's score goes to the score sheet of the code they
--       registered on, by that course's continuous-assessment maximum (assessment.cbt_to_sheet);
--     · one examination of a kind per pair: a second examination of the same type on the twin class is refused
--       (CBT_TWIN_EXAMINED), so no candidate is seated twice.
--   Score sheets, results and transcripts stay per code.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V398: BSU-/MOAU- twin courses examined once', true);

-- ── 1 · one examination of a kind per pair ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION assessment.cbt_twin_guard()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE other record;
BEGIN
    IF NEW.offering_id IS NULL OR NEW.state = 'CANCELLED' THEN RETURN NEW; END IF;
    SELECT x.reference, o.course_code INTO other
      FROM catalogue.offering_family(NEW.offering_id) f
      JOIN assessment.cbt_exam x ON x.offering_id = f
      JOIN catalogue.offering o ON o.id = f
     WHERE f <> NEW.offering_id AND x.exam_type = NEW.exam_type AND x.state <> 'CANCELLED' AND x.id <> NEW.id
     LIMIT 1;
    IF other.reference IS NOT NULL THEN
        RAISE EXCEPTION 'CBT_TWIN_EXAMINED: % is examined with % on %; its candidates sit that examination',
            (SELECT o.course_code FROM catalogue.offering o WHERE o.id = NEW.offering_id), other.course_code, other.reference
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS trg_cbt_twin_guard ON assessment.cbt_exam;
CREATE TRIGGER trg_cbt_twin_guard BEFORE INSERT OR UPDATE OF offering_id, exam_type ON assessment.cbt_exam
    FOR EACH ROW EXECUTE FUNCTION assessment.cbt_twin_guard();

-- ── 2 · the restated functions (from their definitions after V397) ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.align_twin_classes(p_bsu text, p_moau text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r record; n int := 0;
BEGIN
    FOR r IN SELECT a.id AS a_id, b.id AS b_id, a.lecturer_id AS a_lec, b.lecturer_id AS b_lec
               FROM catalogue.offering a
               JOIN catalogue.offering b ON b.course_code = p_moau AND b.session = a.session AND b.semester = a.semester AND b.stream = a.stream
               JOIN policy.academic_session s ON s.name = a.session AND s.state NOT IN ('CLOSED', 'ARCHIVED', 'CANCELLED')
              WHERE a.course_code = p_bsu
    LOOP
        IF r.a_lec IS NOT NULL AND r.b_lec IS NULL THEN
            UPDATE catalogue.offering t SET lecturer_id = f.lecturer_id, second_examiner_id = f.second_examiner_id, allocated_on = f.allocated_on
              FROM catalogue.offering f WHERE f.id = r.a_id AND t.id = r.b_id;
            PERFORM catalogue.open_sheet_if_due(r.b_id);
            n := n + 1;
        ELSIF r.b_lec IS NOT NULL AND r.a_lec IS NULL THEN
            UPDATE catalogue.offering t SET lecturer_id = f.lecturer_id, second_examiner_id = f.second_examiner_id, allocated_on = f.allocated_on
              FROM catalogue.offering f WHERE f.id = r.b_id AND t.id = r.a_id;
            PERFORM catalogue.open_sheet_if_due(r.a_id);
            n := n + 1;
        END IF;
        INSERT INTO catalogue.offering_teacher (offering_id, lecturer_id, added_by, programme_code)
        SELECT x.other, t.lecturer_id, t.added_by, t.programme_code
          FROM (VALUES (r.a_id, r.b_id), (r.b_id, r.a_id)) AS x(src, other)
          JOIN catalogue.offering_teacher t ON t.offering_id = x.src
          JOIN catalogue.offering o ON o.id = x.other
         WHERE o.lecturer_id IS DISTINCT FROM t.lecturer_id
        ON CONFLICT (offering_id, lecturer_id) DO NOTHING;
        -- V398: the paper's slot set on one class is the slot of both
        INSERT INTO assessment.exam_timetable (offering_id, held_on, starts_at, ends_at, venue)
        SELECT x.other, t.held_on, t.starts_at, t.ends_at, t.venue
          FROM (VALUES (r.a_id, r.b_id), (r.b_id, r.a_id)) AS x(src, other)
          JOIN assessment.exam_timetable t ON t.offering_id = x.src
        ON CONFLICT (offering_id) DO NOTHING;
    END LOOP;
    RETURN n;
END $function$;

CREATE OR REPLACE FUNCTION assessment.cbt_candidates(p_exam uuid)
 RETURNS TABLE(student_id uuid, number text, surname text, other_names text, sex text, faculty_code text, faculty text, dept_code text, department text, programme_code text, programme text, level integer, student_status text, entitled boolean, eligible boolean, attempts integer, attempt_id uuid, attempt_status text, connection text, started_at timestamp with time zone, ends_at timestamp with time zone, submitted_at timestamp with time zone, time_left integer, last_activity_at timestamp with time zone, violations integer, answered integer, score numeric, max_marks integer, percentage numeric, grade text, passed boolean, outcome text, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE
AS $function$
    WITH e AS (SELECT x.*, c.general_office, c.kind FROM assessment.cbt_exam x LEFT JOIN catalogue.course c ON c.code = x.course_code WHERE x.id = p_exam),
    cfg AS (SELECT * FROM finance.gst_setting WHERE id = 1),
    reg AS (SELECT DISTINCT cr.student_id FROM e, registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
             WHERE e.office NOT IN ('JUPEB', 'POST_UTME') AND en.offering_id IN (SELECT catalogue.offering_family(e.offering_id)) AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')),
    base AS (SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names, s.sex, s.status, s.current_level AS level, s.entry_mode,
                    p.code AS programme_code, p.name AS programme, p.dept_code, d.name AS department, d.faculty_code, f.name AS faculty
               FROM reg JOIN people.student s ON s.id = reg.student_id
               JOIN ref.programme p ON p.code = s.programme_code JOIN ref.department d ON d.code = p.dept_code JOIN ref.faculty f ON f.code = d.faculty_code),
    pays AS (SELECT r.student_id, count(*) AS n FROM e, finance.payment_reference r
              WHERE e.office IN ('GST', 'EPS') AND r.session = e.session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.student_id IN (SELECT id FROM base)
                AND r.amount > finance.gst_refunded(r.reference)   -- V367
              GROUP BY r.student_id),
    fees AS (SELECT f.id, f.amount, f.level, f.entry_mode, f.faculty_code, f.programme_code, f.stated_at
               FROM e, finance.gst_fee f WHERE e.office IN ('GST', 'EPS') AND f.session = e.session AND f.superseded_at IS NULL AND f.effective_from <= current_date),
    att AS (SELECT DISTINCT ON (a.candidate_id) a.* FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam ORDER BY a.candidate_id, a.number DESC),
    cnt AS (SELECT a.candidate_id, count(*)::int AS attempts FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam GROUP BY a.candidate_id),
    ent AS (SELECT b.id,
                   CASE WHEN e.office IN ('GST', 'EPS')
                        THEN (coalesce(py.n, 0) > 0 OR (fr.id IS NOT NULL AND fr.amount = 0))
                        ELSE coalesce(finance.clears(b.id, e.session, 'EXAMINATION'), false) END AS entitled,
                   CASE WHEN e.office IN ('GST', 'EPS')
                        THEN NOT (fr.id IS NOT NULL AND fr.amount > 0 AND NOT (coalesce(py.n, 0) > 0)
                                  AND ((cfg.required_for_gst_eps AND e.kind = 'GST' AND e.general_office IS NOT NULL AND (e.general_office = 'GST' OR cfg.covers_eps))   -- V367
                                       OR (cfg.required_for_all AND finance.gst_required(b.id, e.session))))
                        ELSE coalesce(finance.clears(b.id, e.session, 'EXAMINATION'), false) END AS paid_up
              FROM e CROSS JOIN cfg CROSS JOIN base b
              LEFT JOIN pays py ON py.student_id = b.id
              LEFT JOIN LATERAL (SELECT f.id, f.amount FROM fees f
                                  WHERE (f.programme_code IS NULL OR f.programme_code = b.programme_code) AND (f.faculty_code IS NULL OR f.faculty_code = b.faculty_code)
                                    AND (f.level IS NULL OR f.level = b.level) AND (f.entry_mode IS NULL OR f.entry_mode = b.entry_mode)
                                  ORDER BY (f.programme_code IS NOT NULL) DESC, (f.faculty_code IS NOT NULL) DESC, (f.level IS NOT NULL) DESC, (f.entry_mode IS NOT NULL) DESC, f.stated_at DESC
                                  LIMIT 1) fr ON true),
    -- V365: a JUPEB examination's candidates â€” the JUPEB students registered for the subject in the session
    jreg AS (SELECT a.id, coalesce(a.exam_no, a.application_no) AS number, upper(a.surname) AS surname,
                    a.first_name || coalesce(' ' || a.middle_name, '') AS other_names, a.sex, a.state, cb.code AS combination, cb.name AS combination_name,
                    assessment.cbt_jupeb_fees_paid(a.id, e.semester) AS paid_up
               FROM e JOIN jupeb.subject_registration r ON r.subject_id = e.jupeb_subject_id AND r.session = e.session
               JOIN jupeb.application a ON a.id = r.application_id
               LEFT JOIN jupeb.combination cb ON cb.id = a.combination_id
              WHERE e.office = 'JUPEB'),
    -- V385: a Post-UTME examination's candidates â€” the session's submitted applicants, eligible on the record (V260) and not yet scored
    preg AS (SELECT a.id, c.jamb_reg_no AS number, upper(c.surname) AS surname, c.other_names, x.sex, el.status,
                    p.code AS programme_code, p.name AS programme, p.dept_code, d.name AS department, d.faculty_code, f.name AS faculty,
                    a.fee_confirmed_at IS NOT NULL AS paid,
                    el.status IN ('READY_FOR_SCHEDULING', 'SCHEDULED', 'RESCHEDULED', 'RESCHEDULE_REQUIRED', 'ABSENT') AND a.screening_score IS NULL AS ok
               FROM e JOIN admissions.application a ON a.session = e.putme_session AND a.submitted_at IS NOT NULL
               JOIN admissions.candidate c ON c.id = a.candidate_id AND c.entry_mode <> 'CCE'
               LEFT JOIN admissions.caps_row x ON x.id = c.admitted_from
               LEFT JOIN ref.programme p ON p.code = admissions.putme_programme_code(c.programme)
               LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = d.faculty_code
               CROSS JOIN LATERAL admissions.putme_eligibility(a.id) el
              WHERE e.office = 'POST_UTME'),
    everyone AS (
        SELECT b.id, b.number, b.surname, b.other_names, b.sex, b.faculty_code, b.faculty, b.dept_code, b.department, b.programme_code, b.programme, b.level, b.status,
               en.entitled, en.paid_up AND b.status IN ('ACTIVE', 'ADMITTED', 'PROBATION') AS eligible
          FROM base b JOIN ent en ON en.id = b.id
        UNION ALL
        SELECT j.id, j.number, j.surname, j.other_names, j.sex, 'JUPEB', 'JUPEB programme', NULL, NULL, j.combination, j.combination_name, NULL::int, j.state,
               j.paid_up, j.paid_up AND j.state = 'STUDENT'
          FROM jreg j
        UNION ALL
        SELECT q.id, q.number, q.surname, q.other_names, q.sex, q.faculty_code, q.faculty, q.dept_code, q.department, q.programme_code, q.programme, NULL::int, q.status,
               q.paid, q.ok
          FROM preg q)
    SELECT v.id, v.number, v.surname, v.other_names, v.sex, v.faculty_code, v.faculty, v.dept_code, v.department, v.programme_code, v.programme, v.level, v.status,
           v.entitled, v.eligible,
           coalesce(cn.attempts, 0), a.id,
           coalesce(a.status, 'NOT_STARTED'),
           CASE WHEN a.status = 'IN_PROGRESS' AND a.last_activity_at < now() - interval '60 seconds' THEN 'DISCONNECTED' WHEN a.status = 'IN_PROGRESS' THEN 'ONLINE' ELSE NULL END,
           a.started_at, a.ends_at, a.submitted_at,
           CASE WHEN a.status = 'IN_PROGRESS' THEN greatest(0, extract(epoch FROM a.ends_at - now()))::int ELSE NULL END,
           a.last_activity_at, coalesce(a.violations, 0), coalesce(a.answered, 0), a.score, a.max_marks, a.percentage, a.grade, a.passed, a.outcome, a.updated_at
      FROM everyone v
      LEFT JOIN att a ON a.candidate_id = v.id
      LEFT JOIN cnt cn ON cn.candidate_id = v.id
$function$;

CREATE OR REPLACE FUNCTION assessment.cbt_candidate_count(e assessment.cbt_exam)
 RETURNS bigint
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE e.office
             WHEN 'JUPEB' THEN (SELECT count(DISTINCT r.application_id) FROM jupeb.subject_registration r WHERE r.subject_id = e.jupeb_subject_id AND r.session = e.session)
             WHEN 'POST_UTME' THEN (SELECT count(*) FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
                                     WHERE a.session = e.putme_session AND a.submitted_at IS NOT NULL AND c.entry_mode <> 'CCE')
             ELSE (SELECT count(DISTINCT cr.student_id) FROM registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
                    WHERE en.offering_id IN (SELECT catalogue.offering_family(e.offering_id)) AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED'))
           END
$function$;

CREATE OR REPLACE FUNCTION assessment.cbt_notify_candidates(p_exam uuid, p_subject text, p_body text, p_only_sat boolean)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE e assessment.cbt_exam; r record; n int := 0;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    IF e.office = 'JUPEB' THEN
        -- V365: a JUPEB examination's candidates, at the email they applied with
        FOR r IN
            SELECT DISTINCT a.id, a.email FROM jupeb.subject_registration sr JOIN jupeb.application a ON a.id = sr.application_id
             WHERE sr.subject_id = e.jupeb_subject_id AND sr.session = e.session AND a.state = 'STUDENT' AND a.email IS NOT NULL
               AND (NOT p_only_sat OR EXISTS (SELECT 1 FROM assessment.cbt_attempt t WHERE t.exam_id = p_exam AND t.candidate_id = a.id AND t.status <> 'IN_PROGRESS'))
        LOOP
            PERFORM platform.queue_notice('EMAIL', r.email, p_subject, p_body || E'\n\nJUPEB Office, ' || (platform.institution() ->> 'name'), 'jupeb_application', r.id);
            n := n + 1;
        END LOOP;
        RETURN n;
    END IF;
    IF e.office = 'POST_UTME' THEN
        -- V385: the session's submitted Post-UTME applicants, by the e-mail and phone they registered with
        FOR r IN
            SELECT a.id FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
             WHERE a.session = e.putme_session AND a.submitted_at IS NOT NULL AND c.entry_mode <> 'CCE'
               AND (NOT p_only_sat OR EXISTS (SELECT 1 FROM assessment.cbt_attempt t WHERE t.exam_id = p_exam AND t.candidate_id = a.id AND t.status <> 'IN_PROGRESS'))
        LOOP
            PERFORM admissions.notify_applicant(r.id, p_subject, p_body || E'\n\nDirectorate of ICT, ' || (platform.institution() ->> 'name'), NULL);
            n := n + 1;
        END LOOP;
        RETURN n;
    END IF;
    FOR r IN
        SELECT DISTINCT cr.student_id FROM registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
         WHERE en.offering_id IN (SELECT catalogue.offering_family(e.offering_id)) AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')
           AND (NOT p_only_sat OR EXISTS (SELECT 1 FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam AND a.student_id = cr.student_id AND a.status <> 'IN_PROGRESS'))
    LOOP
        PERFORM platform.queue_notice('EMAIL', x.email, p_subject, p_body || E'\n\n' || CASE e.office WHEN 'EXAMS' THEN 'Examinations Office' ELSE e.office || ' Office' END || ', ' || (platform.institution() ->> 'name'), 'student', r.student_id)
          FROM people.student_reach(r.student_id) x WHERE x.email IS NOT NULL;
        n := n + 1;
    END LOOP;
    RETURN n;
END $function$;

CREATE OR REPLACE FUNCTION assessment.cbt_student_exams(p_student uuid, p_session text)
 RETURNS TABLE(exam_id uuid, reference text, office text, course_code text, course_title text, title text, session text, semester integer, instructions text, live_state text, starts_at timestamp with time zone, ends_at timestamp with time zone, duration_minutes integer, questions integer, security_mode text, venue text, attempt_limit integer, violation_limit integer, violation_action text, eligibility text, attempts integer, attempt_id uuid, attempt_status text, attempt_ends_at timestamp with time zone, submitted_at timestamp with time zone, result_published boolean, score numeric, max_marks integer, percentage numeric, grade text, passed boolean, pass_mark numeric, outcome text, partial_credit boolean, exam_type text, negative_marks numeric, allow_back boolean, allow_review boolean, fullscreen_required boolean, proctoring text, score_on_submit boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH mine AS (SELECT DISTINCT en.offering_id FROM registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
                   WHERE cr.student_id = p_student AND (p_session IS NULL OR cr.session = p_session)
                     AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')),
    att AS (SELECT DISTINCT ON (a.exam_id) a.* FROM assessment.cbt_attempt a WHERE a.student_id = p_student ORDER BY a.exam_id, a.number DESC),
    cnt AS (SELECT a.exam_id, count(*)::int AS attempts FROM assessment.cbt_attempt a WHERE a.student_id = p_student GROUP BY a.exam_id),
    v AS (SELECT e.*, assessment.cbt_live_state(e) AS live,
                 (e.results_state = 'PUBLISHED' OR (e.score_on_submit AND a.status IS NOT NULL AND a.status <> 'IN_PROGRESS')) AS shown, a.id AS a_id, a.status AS a_status,
                 a.ends_at AS a_ends_at, a.submitted_at AS a_submitted_at, a.score AS a_score, a.max_marks AS a_max, a.percentage AS a_pct, a.grade AS a_grade,
                 a.passed AS a_passed, a.outcome AS a_outcome, cn.attempts AS a_attempts
            FROM assessment.cbt_exam e JOIN mine m ON m.offering_id IN (SELECT catalogue.offering_family(e.offering_id))
            LEFT JOIN att a ON a.exam_id = e.id LEFT JOIN cnt cn ON cn.exam_id = e.id
           WHERE e.state IN ('PUBLISHED', 'CLOSED', 'COMPLETED'))
    SELECT v.id, v.reference, v.office, v.course_code, c.title, v.title, v.session, v.semester, v.instructions,
           v.live, v.starts_at, v.ends_at, v.duration_minutes,
           CASE WHEN v.selection = 'RANDOM' THEN v.total_questions ELSE (SELECT count(*)::int FROM assessment.cbt_pool(v.id)) END,
           v.security_mode, v.venue, v.attempt_limit, v.violation_limit, v.violation_action,
           CASE WHEN v.a_status = 'IN_PROGRESS' THEN NULL ELSE assessment.cbt_eligibility(v.id, p_student) END,
           coalesce(v.a_attempts, 0), v.a_id, v.a_status, v.a_ends_at, v.a_submitted_at,
           (v.results_state = 'PUBLISHED'),
           CASE WHEN v.shown THEN v.a_score END, CASE WHEN v.shown THEN v.a_max END, CASE WHEN v.shown THEN v.a_pct END, CASE WHEN v.shown THEN v.a_grade END,
           CASE WHEN v.shown THEN v.a_passed END, v.pass_mark, CASE WHEN v.shown THEN v.a_outcome END, v.partial_credit,
           v.exam_type, v.negative_marks, v.allow_back, v.allow_review, v.fullscreen_required, v.proctoring, v.score_on_submit
      FROM v JOIN catalogue.course c ON c.code = v.course_code
     ORDER BY v.starts_at DESC NULLS LAST, v.title
$function$;

CREATE OR REPLACE FUNCTION assessment.cbt_eligibility(p_exam uuid, p_student uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE e assessment.cbt_exam; st people.student; v_gate text; v_ready text; n int; v_enabled boolean;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    IF NOT FOUND THEN RETURN 'CBT_EXAM_NOT_FOUND: no such examination'; END IF;
    -- V365: a JUPEB examination's candidate is a JUPEB student, judged by the JUPEB rules
    IF e.office = 'JUPEB' THEN RETURN assessment.cbt_jupeb_eligibility(p_exam, p_student); END IF;
    IF e.state = 'CANCELLED' THEN RETURN 'CBT_EXAM_CANCELLED: this examination was cancelled'; END IF;
    IF e.state <> 'PUBLISHED' THEN RETURN 'CBT_EXAM_NOT_OPEN: this examination is not open to candidates'; END IF;
    SELECT cbt_enabled INTO v_enabled FROM catalogue.course WHERE code = e.course_code;
    IF NOT coalesce(v_enabled, false) THEN RETURN format('CBT_COURSE_NOT_ENABLED: %s is not a CBT course', e.course_code); END IF;
    SELECT * INTO st FROM people.student WHERE id = p_student;
    IF NOT FOUND OR st.status NOT IN ('ACTIVE', 'ADMITTED', 'PROBATION') THEN
        RETURN 'CBT_STUDENT_INACTIVE: only an active student sits an examination';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
                    WHERE cr.student_id = p_student AND en.offering_id IN (SELECT catalogue.offering_family(e.offering_id))
                      AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) THEN
        RETURN format('CBT_COURSE_NOT_REGISTERED: %s is not on your submitted registration for %s', e.course_code, e.session);
    END IF;
    -- V381: attendance below the class's minimum bars the examination where the class's attendance policy says so
    -- V398: for a linked BSU-/MOAU- pair, the attendance of the class the student registered on
    v_gate := attendance.exam_bar(p_student, coalesce(
        (SELECT en.offering_id FROM registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
          WHERE cr.student_id = p_student AND en.offering_id IN (SELECT catalogue.offering_family(e.offering_id)) AND en.status IN ('REGISTERED', 'APPROVED')
          ORDER BY (en.offering_id = e.offering_id) DESC LIMIT 1), e.offering_id));
    IF v_gate IS NOT NULL THEN RETURN v_gate; END IF;
    IF e.office IN ('GST', 'EPS') THEN
        v_gate := registration.gst_gate(p_student, e.session, e.course_code);
        IF v_gate IS NOT NULL THEN RETURN v_gate; END IF;
    ELSIF NOT coalesce(finance.clears(p_student, e.session, 'EXAMINATION'), false) THEN
        RETURN format('CBT_FEES_NOT_CLEARED: your %s school fees are not cleared for examinations', e.session);
    END IF;
    v_ready := assessment.cbt_paper_ready(p_exam);
    IF v_ready IS NOT NULL THEN RETURN v_ready; END IF;
    IF e.starts_at > now() THEN RETURN format('CBT_EXAM_NOT_STARTED: the examination opens at %s', to_char(e.starts_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY HH24:MI')); END IF;
    IF e.ends_at <= now() THEN RETURN 'CBT_EXAM_ENDED: the examination window has closed'; END IF;
    SELECT count(*) INTO n FROM assessment.cbt_attempt WHERE exam_id = p_exam AND candidate_id = p_student AND status <> 'IN_PROGRESS';
    IF n >= e.attempt_limit THEN RETURN format('CBT_ATTEMPT_LIMIT: you have used the %s attempt%s this examination allows', e.attempt_limit, CASE WHEN e.attempt_limit = 1 THEN '' ELSE 's' END); END IF;
    RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION assessment.cbt_to_sheet(p_exam uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE e assessment.cbt_exam; sh assessment.score_sheet; v_ca_max int; v_sheet assessment.score_sheet; v_cmax int; v_own uuid; r record; n int := 0; v_version int; v_ca int; v_old_exam int; v_new_ca int; v_new_exam int;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    IF e.office = 'JUPEB' THEN RETURN assessment.cbt_to_jupeb_ca(p_exam); END IF;
    IF e.sheet_component = 'NONE' THEN
        RAISE EXCEPTION 'CBT_NOT_FOR_SHEET: this examination is set not to count on the score sheet' USING ERRCODE = '23514';
    END IF;
    IF e.results_state NOT IN ('APPROVED', 'PUBLISHED') THEN RAISE EXCEPTION 'CBT_RESULTS_STATE: approve the results before they go onto the score sheet' USING ERRCODE = '23514'; END IF;
    SELECT * INTO sh FROM assessment.score_sheet WHERE offering_id = e.offering_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_NO_SHEET: the course has no score sheet yet; it opens with the examination session' USING ERRCODE = '23514'; END IF;
    IF sh.stage <> 'ENTRY' THEN RAISE EXCEPTION 'CBT_SHEET_NOT_AT_ENTRY: the score sheet is at %; scores are entered at entry', lower(replace(sh.stage, '_', ' ')) USING ERRCODE = '23514'; END IF;
    SELECT ca_max INTO v_ca_max FROM catalogue.course WHERE code = e.course_code;
    FOR r IN
        SELECT DISTINCT ON (a.student_id) a.student_id, a.percentage, a.outcome
          FROM assessment.cbt_attempt a WHERE a.exam_id = e.id AND a.status <> 'IN_PROGRESS' AND a.percentage IS NOT NULL
         ORDER BY a.student_id, a.percentage DESC, a.number DESC
    LOOP
        -- V398: a candidate of a linked BSU-/MOAU- pair registered on the twin code is scored on that code's own sheet
        v_sheet := sh; v_cmax := v_ca_max;
        SELECT f INTO v_own FROM catalogue.offering_family(e.offering_id) f
         WHERE f <> e.offering_id
           AND EXISTS (SELECT 1 FROM registration.entry en JOIN registration.course_registration cr ON cr.id = en.registration_id
                        WHERE en.offering_id = f AND cr.student_id = r.student_id AND en.status IN ('REGISTERED', 'APPROVED'))
         LIMIT 1;
        IF v_own IS NOT NULL THEN
            SELECT * INTO v_sheet FROM assessment.score_sheet WHERE offering_id = v_own;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'CBT_NO_SHEET: % has no score sheet yet; it opens with the examination session', (SELECT o.course_code FROM catalogue.offering o WHERE o.id = v_own)
                    USING ERRCODE = '23514';
            END IF;
            IF v_sheet.stage <> 'ENTRY' THEN
                RAISE EXCEPTION 'CBT_SHEET_NOT_AT_ENTRY: the score sheet of % is at %; scores are entered at entry', (SELECT o.course_code FROM catalogue.offering o WHERE o.id = v_own),
                    lower(replace(v_sheet.stage, '_', ' ')) USING ERRCODE = '23514';
            END IF;
            SELECT c.ca_max INTO v_cmax FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE o.id = v_own;
        END IF;
        v_version := NULL; v_ca := NULL; v_old_exam := NULL;
        SELECT l.version, l.ca, l.exam INTO v_version, v_ca, v_old_exam FROM assessment.latest_scores(v_sheet.id) l WHERE l.student_id = r.student_id;
        IF e.sheet_component = 'CA' THEN
            v_new_ca := CASE WHEN r.outcome = 'VOID' THEN 0 ELSE round(r.percentage * v_cmax / 100.0)::int END;
            v_new_exam := v_old_exam;
        ELSE
            v_new_ca := v_ca;
            v_new_exam := CASE WHEN r.outcome = 'VOID' THEN 0 ELSE round(r.percentage * (100 - v_cmax) / 100.0)::int END;
        END IF;
        IF v_version IS NOT NULL AND EXISTS (SELECT 1 FROM assessment.score s WHERE s.sheet_id = v_sheet.id AND s.student_id = r.student_id AND s.version = v_version
                                               AND s.ca IS NOT DISTINCT FROM v_new_ca AND s.exam IS NOT DISTINCT FROM v_new_exam AND s.reason LIKE 'CBT ' || e.reference || '%') THEN
            CONTINUE;
        END IF;
        INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, outcome, reason)
        VALUES (v_sheet.id, r.student_id, coalesce(v_version, 0) + 1, v_new_ca, v_new_exam,
                CASE WHEN v_new_ca IS NULL OR v_new_exam IS NULL THEN 'INCOMPLETE' ELSE 'GRADED' END,
                'CBT ' || e.reference || ': ' || e.title || ' — ' || CASE e.sheet_component WHEN 'CA' THEN 'continuous assessment' ELSE 'examination component' END
                || ' from the computer-based test');
        n := n + 1;
    END LOOP;
    RETURN n;
END $function$;

COMMIT;
