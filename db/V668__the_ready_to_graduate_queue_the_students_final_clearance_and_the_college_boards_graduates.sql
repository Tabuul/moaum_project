-- ═══════════════════════════════════════
-- V668 — the Bursar's ready-to-graduate queue, the student's final clearance in their own words, and the College Board's
--        graduates through the final clearance
--
-- The word of 26 October 2026, after V665 (graduation at the Bursar's final clearance), with the University's answers: the College
-- Academic Board's "Graduate" after the Final MBBS goes through the final clearance like every other award; the reconciliation of
-- students outside the maximum academic period (V638) stays as it is, any balance staying owed on their historical school fees; the
-- Registry's general change of status refuses GRADUATED (the API).
--
--   · clearance.ready_to_graduate(faculty, department, programme, search, limit): every student whose award is approved, whose
--     record is not yet GRADUATED and whose final clearance waits only on the Bursary — every other office cleared, the Bursary's
--     stage open — with the school-fee account read afresh (assessed, paid, waived, outstanding, the periods owing, for review or
--     pending) and READY where nothing is owed, for review or pending. The Bursar works the list; each confirmation still goes
--     through clearance.decide, read again.
--   · clearance.student_final_position(student): what the student is told of their final clearance — whether the award is approved
--     and awaits it, the award, the minute, the offices still to clear, the Bursary's stage, and the school fees owed by session and
--     semester (official amounts only: a period being assessed is never shown as owed).
--   · records.graduand.basis: SENATE (as before) or COLLEGE_BOARD; an award of the College Academic Board carries no CGPA (the
--     professional examinations decide it), so the approval's check allows it without one.
--   · college.confirm_decisions (V606 restated): a confirmed GRADUATE no longer changes the status. records.college_award writes
--     the award (the programme's award, with Honours where the Board found them) on the Board's minute, approves it, starts the final
--     clearance and tells the student (STUDENT_AWARD_APPROVED); the Bursar's confirmation of the final clearance graduates them.
--   · clearance.final_check and records.graduate_on_final_clearance (V665 restated): an award of the College Board is read on the
--     Board's decision, not on the course record.
-- ═══════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V668: the ready-to-graduate queue, the student''s final clearance, the College Board''s graduates through the final clearance', true);

-- ── 1 · an award of the College Academic Board ──────────────────────────────────────────────────────────────────────────────
ALTER TABLE records.graduand ADD COLUMN IF NOT EXISTS basis text NOT NULL DEFAULT 'SENATE';
ALTER TABLE records.graduand DROP CONSTRAINT IF EXISTS ck_graduand_basis;
ALTER TABLE records.graduand ADD CONSTRAINT ck_graduand_basis CHECK (basis IN ('SENATE', 'COLLEGE_BOARD'));
ALTER TABLE records.graduand DROP CONSTRAINT ck_grad_approved;
ALTER TABLE records.graduand ADD CONSTRAINT ck_grad_approved
    CHECK (senate_state <> 'APPROVED' OR (senate_minute IS NOT NULL AND unmet IS NULL AND (cgpa IS NOT NULL OR basis = 'COLLEGE_BOARD')));
COMMENT ON COLUMN records.graduand.basis IS
  'V668: who approved the award — SENATE (the degree audit''s list on the Senate minute) or COLLEGE_BOARD (the College Academic Board''s confirmation of the Final MBBS, which carries no CGPA)';

CREATE OR REPLACE FUNCTION records.college_award(p_student uuid, p_session text, p_minute text, p_honours boolean, p_actor uuid, p_office text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE s people.student; pr record; v_award text; v_g uuid; v_proc uuid; v_clear text; v_err text; reach record;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'GRAD_NO_STUDENT: no such student' USING ERRCODE = '23503'; END IF;
    IF s.status = 'GRADUATED' THEN RETURN jsonb_build_object('outcome', 'ALREADY_GRADUATED'); END IF;
    SELECT p.name, coalesce(nullif(btrim(p.pg_award), ''), p.name) AS award, d.name AS dept_name, f.name AS faculty_name INTO pr
      FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE p.code = s.programme_code;
    v_award := coalesce(pr.award, s.programme_code) || CASE WHEN coalesce(p_honours, false) THEN ' with Honours' ELSE '' END;
    INSERT INTO records.graduand (id, student_id, session, cgpa, award, unmet, senate_state, senate_minute, approved_at, approved_by, actor_office,
                                  final_level, basis)
    VALUES (gen_random_uuid(), p_student, p_session, NULL, v_award, NULL, 'APPROVED', btrim(p_minute), now(), p_actor, p_office, s.current_level, 'COLLEGE_BOARD')
    ON CONFLICT (student_id, session) DO UPDATE
       SET award = EXCLUDED.award, unmet = NULL, senate_state = 'APPROVED', senate_minute = EXCLUDED.senate_minute, basis = 'COLLEGE_BOARD',
           approved_at = coalesce(records.graduand.approved_at, EXCLUDED.approved_at), approved_by = coalesce(records.graduand.approved_by, EXCLUDED.approved_by),
           actor_office = EXCLUDED.actor_office, final_level = EXCLUDED.final_level
    RETURNING id INTO v_g;
    SELECT q.id INTO v_proc FROM clearance.process q WHERE q.workflow = 'FINAL' AND q.student_id = p_student AND q.cancelled_at IS NULL ORDER BY q.started_at DESC LIMIT 1;
    IF v_proc IS NOT NULL THEN
        v_clear := 'under way';
    ELSE
        BEGIN
            v_proc := clearance.start('FINAL', p_student, p_session, 'ELIGIBLE', NULL, p_actor, p_office);
            v_clear := 'under way';
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
            v_clear := 'to be started by the Registry';
        END;
    END IF;
    SELECT * INTO reach FROM people.student_reach(p_student);
    PERFORM platform.notify('STUDENT_AWARD_APPROVED', NULL, jsonb_build_object(
                'FIRST_NAME', coalesce(nullif(split_part(coalesce(s.other_names, ''), ' ', 1), ''), s.surname),
                'AWARD', v_award, 'PROGRAMME', coalesce(pr.name, s.programme_code), 'DEPARTMENT', coalesce(pr.dept_name, ''), 'FACULTY', coalesce(pr.faculty_name, ''),
                'MINUTE', btrim(p_minute), 'SESSION', p_session, 'MATRIC', coalesce(s.matric_no, s.admission_no, ''), 'CLEARANCE', v_clear),
            'student', p_student, reach.email, reach.phone, 'award-approved:' || p_student || ':' || p_session);
    RETURN jsonb_build_object('outcome', 'APPROVED', 'graduand_id', v_g, 'process', v_proc, 'clearance', v_clear);
END $fn$;
COMMENT ON FUNCTION records.college_award(uuid, text, text, boolean, uuid, text) IS
  'V668: the College Academic Board''s confirmed GRADUATE written as an approved award on the Board''s minute (the programme''s award, with Honours where found; no CGPA), the final clearance started and the student told (STUDENT_AWARD_APPROVED); the status stays until the Bursar confirms the final clearance';

-- the Board's confirmation (V606 restated): GRADUATE approves the award and starts the final clearance; the status follows the Bursar
CREATE OR REPLACE FUNCTION college.confirm_decisions(p_exam text, p_session text, p_minute text)
 RETURNS integer
 LANGUAGE plpgsql
AS $fn$
DECLARE e college.professional_exam; d record; n int := 0; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_hon boolean; v_instrument text;
BEGIN
    SELECT * INTO e FROM college.professional_exam WHERE code = upper(p_exam);
    IF NOT FOUND THEN RAISE EXCEPTION 'no such examination %', p_exam USING ERRCODE = '23503'; END IF;
    IF p_minute IS NULL OR btrim(p_minute) = '' THEN
        RAISE EXCEPTION 'the Board confirms on a minute, and none was cited' USING ERRCODE = '23514';
    END IF;
    v_instrument := 'College Academic Board minute ' || btrim(p_minute) || ' (' || e.name || ', ' || p_session || ')';
    FOR d IN SELECT * FROM college.progression_decision WHERE session = p_session AND from_level = e.level AND state = 'PROVISIONAL'
                AND outcome NOT IN ('CARRY_OVER_PENDING', 'MIN_YEARS_PENDING') LOOP   -- a held graduation is confirmed once what holds it is cleared (V285)
        v_hon := CASE WHEN d.outcome = 'GRADUATE' THEN college.honours(d.student_id) END;
        UPDATE college.progression_decision SET state = 'CONFIRMED', confirmed_on = current_date, confirmed_by = who,
               minute = coalesce(minute, btrim(p_minute)), honours = v_hon WHERE id = d.id;
        IF d.outcome = 'RESIT' THEN
            UPDATE college.enrolment SET state = 'RESIT', resit_subjects = d.resit_subjects
             WHERE student_id = d.student_id AND level = e.level AND session = p_session;
        ELSE
            UPDATE college.enrolment SET state = 'CLOSED', closed_on = current_date
             WHERE student_id = d.student_id AND level = e.level AND session = p_session;
        END IF;
        IF d.outcome = 'PROMOTE' THEN
            UPDATE people.student st SET current_level = e.level + 100
             WHERE st.id = d.student_id AND college.runs_programme(st.programme_code);   -- V606: the College's own programmes
        ELSIF d.outcome IN ('WITHDRAW_ADVISED', 'WITHDRAW_REQUIRED') THEN
            PERFORM people.change_status(d.student_id, 'WITHDRAWN', v_instrument, current_date,
                CASE d.outcome WHEN 'WITHDRAW_ADVISED' THEN 'Advised to withdraw from the MBBS programme: ' ELSE 'Required to withdraw from the MBBS programme: ' END || coalesce(d.rule_ref, ''));
        ELSIF d.outcome = 'GRADUATE' THEN
            -- V668: the award approved on the Board's minute and the final clearance started; the Bursar's confirmation of it graduates
            PERFORM records.college_award(d.student_id, p_session, btrim(p_minute), coalesce(v_hon, false), who,
                                          nullif(current_setting('moaum.actor_office', true), ''));
        END IF;
        -- the carry-overs the decision names go on the register (V285): GST and EPS only, cleared when passed
        INSERT INTO college.carry_over (student_id, code, from_session, note)
        SELECT d.student_id, upper(btrim(x)), p_session, 'Carried from ' || e.name || ' · ' || v_instrument
          FROM unnest(coalesce(d.carry_overs, '{}')) x WHERE btrim(x) <> ''
        ON CONFLICT (student_id, code) DO NOTHING;
        PERFORM college.tell_decision(d.student_id, e.code, d.outcome, coalesce(v_hon, false), p_session, btrim(p_minute));
        n := n + 1;
    END LOOP;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION college.confirm_decisions(text, text, text) IS
  'V248, V285, V606, V668: the College Academic Board confirms the provisional decisions of a professional examination on its minute — promote, resit, withdraw, and for the Final MBBS graduate: since V668 the award is approved and the final clearance started (records.college_award); the Bursar''s confirmation of the final clearance graduates the student';

-- ── 2 · the Bursar's queue: every final clearance that waits only on the Bursary's confirmation ─────────────────────────────
CREATE OR REPLACE FUNCTION clearance.ready_to_graduate(p_fac text, p_dept text, p_prog text, p_q text, p_limit integer DEFAULT 500)
RETURNS TABLE(process_id uuid, reference text, session text, student_id uuid, surname text, other_names text, matric_no text, programme text,
              department text, faculty text, award text, minute text, award_session text, basis text, bursary_state text, assessed numeric,
              paid numeric, waived numeric, outstanding numeric, review_periods integer, pending_periods integer, owing text, ready boolean)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_pids uuid[]; v_ids uuid[]; v_states text[]; v_all_p uuid[]; v_all_s uuid[]; v_map jsonb;
BEGIN
    -- the candidates: a live final clearance, an approved award, the record not GRADUATED, within the filters, in name order
    SELECT coalesce(array_agg(x.pid ORDER BY x.surname, x.other_names, x.pid), '{}'::uuid[]), coalesce(array_agg(x.sid ORDER BY x.surname, x.other_names, x.pid), '{}'::uuid[])
      INTO v_all_p, v_all_s
      FROM (SELECT q.id AS pid, q.student_id AS sid, s.surname, s.other_names
              FROM clearance.process q
              JOIN people.student s ON s.id = q.student_id
              JOIN ref.programme p ON p.code = s.programme_code
             WHERE q.workflow = 'FINAL' AND q.cancelled_at IS NULL AND s.status NOT IN ('GRADUATED', 'WITHDRAWN', 'EXPELLED', 'DECEASED', 'TRANSFERRED_OUT')
               AND EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED')
               AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog)
               AND (p_q IS NULL OR s.matric_no ILIKE '%' || p_q || '%' OR q.reference ILIKE '%' || p_q || '%'
                    OR (s.surname || ' ' || s.other_names) ILIKE '%' || p_q || '%' OR (s.other_names || ' ' || s.surname) ILIKE '%' || p_q || '%')) x;
    -- the Bursary's stage of every candidate read in one pass (a final clearance is not per session), kept as a map by process
    SELECT coalesce(jsonb_object_agg(r.process_id::text, r.state), '{}'::jsonb) INTO v_map
      FROM clearance.stage_rows((SELECT w.purpose FROM clearance.workflow w WHERE w.code = 'FINAL'), NULL, v_all_s) r
     WHERE r.unit = 'BURSARY' AND r.opened AND r.process_id IS NOT NULL;
    -- those whose Bursary stage is open: every other office has cleared them
    SELECT coalesce(array_agg(u.pid ORDER BY u.ord), '{}'::uuid[]), coalesce(array_agg(u.sid ORDER BY u.ord), '{}'::uuid[]),
           coalesce(array_agg(v_map ->> u.pid::text ORDER BY u.ord), '{}'::text[])
      INTO v_pids, v_ids, v_states
      FROM (SELECT a.pid, a.sid, a.ord FROM unnest(v_all_p, v_all_s) WITH ORDINALITY AS a(pid, sid, ord)
             WHERE v_map ? a.pid::text ORDER BY a.ord LIMIT greatest(1, least(coalesce(p_limit, 500), 5000))) u;
    RETURN QUERY
    WITH c AS (SELECT u.pid, u.sid, u.bstate, u.ord FROM unnest(v_pids, v_ids, v_states) WITH ORDINALITY AS u(pid, sid, bstate, ord)),
    acct AS (
        SELECT x.student_id AS sid, coalesce(sum(x.assessed), 0) AS assessed, coalesce(sum(x.paid), 0) AS paid, coalesce(sum(x.waived), 0) AS waived,
               coalesce(sum(x.outstanding), 0) AS outstanding,
               count(*) FILTER (WHERE x.status = 'REQUIRES_REVIEW')::int AS review, count(*) FILTER (WHERE x.status = 'PENDING_APPROVAL')::int AS pending,
               string_agg(x.session || ' ' || finance.semester_words(x.semester) || ' (' || clearance.naira(x.outstanding) || ')', '; ' ORDER BY x.session, x.semester)
                   FILTER (WHERE x.outstanding > 0) AS owing
          FROM finance.historical_rows(v_ids) x GROUP BY x.student_id)
    SELECT c.pid, q.reference, q.session, c.sid, s.surname, s.other_names, s.matric_no, p.name, d.name, f.name,
           g.award, g.senate_minute, g.session, g.basis, c.bstate,
           coalesce(a.assessed, 0), coalesce(a.paid, 0), coalesce(a.waived, 0), coalesce(a.outstanding, 0), coalesce(a.review, 0), coalesce(a.pending, 0),
           a.owing,
           coalesce(a.outstanding, 0) = 0 AND coalesce(a.review, 0) = 0 AND coalesce(a.pending, 0) = 0
      FROM c
      JOIN clearance.process q ON q.id = c.pid
      JOIN people.student s ON s.id = c.sid
      JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN LATERAL (SELECT gg.award, gg.senate_minute, gg.session, gg.basis FROM records.graduand gg
                          WHERE gg.student_id = c.sid AND gg.senate_state = 'APPROVED' ORDER BY gg.session DESC LIMIT 1) g ON true
      LEFT JOIN acct a ON a.sid = c.sid
     ORDER BY (coalesce(a.outstanding, 0) = 0 AND coalesce(a.review, 0) = 0 AND coalesce(a.pending, 0) = 0) DESC, c.ord;
END $fn$;
COMMENT ON FUNCTION clearance.ready_to_graduate(text, text, text, text, integer) IS
  'V668: the Bursar''s queue — every student whose award is approved, not yet GRADUATED, whose final clearance waits only on the Bursary (every other office cleared, the Bursary''s stage open), within a faculty, department or programme and a search, with the school-fee account read afresh and READY where nothing is owed, for review or pending; ready first';

-- ── 3 · the student's own reading of their final clearance ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION clearance.student_final_position(p_student uuid) RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE s people.student; g records.graduand; q record; v_others jsonb; v_bursary text; a record; v_owing jsonb;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RETURN NULL; END IF;
    SELECT * INTO g FROM records.graduand WHERE student_id = p_student AND senate_state = 'APPROVED' ORDER BY session DESC LIMIT 1;
    SELECT p.*, w.purpose FROM clearance.process p JOIN clearance.workflow w ON w.code = p.workflow
     WHERE p.workflow = 'FINAL' AND p.student_id = p_student AND p.cancelled_at IS NULL ORDER BY p.started_at DESC LIMIT 1 INTO q;
    IF g.id IS NULL AND q.id IS NULL THEN RETURN NULL; END IF;
    IF q.id IS NOT NULL THEN
        SELECT coalesce(jsonb_agg(jsonb_build_object('unit', r.unit, 'label', r.label, 'state', r.state) ORDER BY r.ord), '[]'::jsonb) INTO v_others
          FROM clearance.stage_rows(q.purpose, q.session, ARRAY[p_student]) r
         WHERE r.unit <> 'BURSARY' AND r.required AND r.applies AND r.state NOT IN ('CLEARED', 'NOT_APPLICABLE');
        SELECT r.state INTO v_bursary FROM clearance.stage_rows(q.purpose, q.session, ARRAY[p_student]) r WHERE r.unit = 'BURSARY';
    END IF;
    -- the official amounts only: a period being assessed is never shown as owed
    SELECT coalesce(sum(x.assessed) FILTER (WHERE x.status NOT IN ('REQUIRES_REVIEW', 'PENDING_APPROVAL')), 0) AS assessed,
           coalesce(sum(x.paid), 0) AS paid, coalesce(sum(x.waived), 0) AS waived, coalesce(sum(x.outstanding), 0) AS outstanding,
           count(*) FILTER (WHERE x.status IN ('REQUIRES_REVIEW', 'PENDING_APPROVAL'))::int AS being_assessed
      INTO a FROM finance.historical_rows(ARRAY[p_student]) x;
    SELECT coalesce(jsonb_agg(jsonb_build_object('session', x.session, 'semester', x.semester, 'outstanding', x.outstanding) ORDER BY x.session, x.semester), '[]'::jsonb)
      INTO v_owing FROM finance.historical_rows(ARRAY[p_student]) x WHERE x.outstanding > 0;
    RETURN jsonb_build_object(
        'awaiting', s.status <> 'GRADUATED' AND g.id IS NOT NULL, 'graduated', s.status = 'GRADUATED', 'status', s.status,
        'award', g.award, 'minute', g.senate_minute, 'awardSession', g.session, 'basis', g.basis,
        'process', q.id, 'reference', q.reference, 'othersPending', coalesce(v_others, '[]'::jsonb), 'bursaryState', v_bursary,
        'assessed', a.assessed, 'paid', a.paid, 'waived', a.waived, 'outstanding', a.outstanding, 'beingAssessed', a.being_assessed, 'owing', v_owing,
        'onlinePayment', coalesce((SELECT online_payment FROM finance.historical_setting WHERE id = 1), false));
END $fn$;
COMMENT ON FUNCTION clearance.student_final_position(uuid) IS
  'V668: what the student is told of their final clearance — the award approved and awaiting it (or graduated), the award and minute, the offices still to clear, the Bursary''s stage, and the school fees by session and semester at the official amounts (a period being assessed never shown as owed), with whether they may pay online';

-- ── 4 · the final check and the Bursar's graduation read a College Board award on the Board's decision (V665 restated) ──────
CREATE OR REPLACE FUNCTION clearance.final_check(p_process uuid) RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE q record; s people.student; g records.graduand; a record; c record; v_others jsonb; v_bursary text; v_block text[] := '{}'; v_grad boolean;
        v_pending_waivers int; v_other_payments jsonb;
BEGIN
    SELECT p.*, w.purpose, w.code AS wf FROM clearance.process p JOIN clearance.workflow w ON w.code = p.workflow WHERE p.id = p_process INTO q;
    IF q.id IS NULL THEN RAISE EXCEPTION 'CLR_NO_PROCESS: no such clearance' USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO s FROM people.student WHERE id = q.student_id;
    SELECT * INTO g FROM records.graduand WHERE student_id = q.student_id AND senate_state = 'APPROVED' ORDER BY session DESC LIMIT 1;
    v_grad := q.wf = 'FINAL' AND s.status <> 'GRADUATED' AND g.id IS NOT NULL;
    -- the school-fee account, read afresh: every session and semester of the record at the fees of the period
    SELECT coalesce(sum(x.assessed), 0) AS assessed, coalesce(sum(x.paid), 0) AS paid, coalesce(sum(x.waived), 0) AS waived,
           coalesce(sum(x.outstanding), 0) AS outstanding, coalesce(sum(x.credit), 0) AS credit, count(*)::int AS periods,
           count(*) FILTER (WHERE x.status = 'REQUIRES_REVIEW')::int AS review, count(*) FILTER (WHERE x.status = 'PENDING_APPROVAL')::int AS pending,
           coalesce(jsonb_agg(jsonb_build_object('session', x.session, 'semester', x.semester, 'level', x.level, 'assessed', x.assessed, 'paid', x.paid,
                                                 'waived', x.waived, 'outstanding', x.outstanding, 'status', x.status) ORDER BY x.session, x.semester)
                    FILTER (WHERE x.outstanding > 0 OR x.status IN ('REQUIRES_REVIEW', 'PENDING_APPROVAL')), '[]'::jsonb) AS unsettled,
           string_agg(x.session || ' ' || finance.semester_words(x.semester) || ' — ' || clearance.naira(x.outstanding), '; ' ORDER BY x.session, x.semester)
               FILTER (WHERE x.outstanding > 0) AS owing_words,
           string_agg(x.session || ' ' || finance.semester_words(x.semester), ', ' ORDER BY x.session, x.semester) FILTER (WHERE x.status = 'REQUIRES_REVIEW') AS review_words,
           string_agg(x.session || ' ' || finance.semester_words(x.semester), ', ' ORDER BY x.session, x.semester) FILTER (WHERE x.status = 'PENDING_APPROVAL') AS pending_words
      INTO a FROM finance.historical_rows(ARRAY[q.student_id]) x;
    v_pending_waivers := (SELECT count(*) FROM finance.historical_waiver w WHERE w.student_id = q.student_id AND w.state = 'PENDING_BURSAR_APPROVAL');
    v_other_payments := (SELECT coalesce(jsonb_agg(to_jsonb(o) ORDER BY o.session, o.confirmed_at), '[]'::jsonb) FROM finance.historical_other_payments(ARRAY[q.student_id]) o);
    -- the other offices of the clearance, and the Bursary's own stage
    SELECT coalesce(jsonb_agg(jsonb_build_object('unit', r.unit, 'label', r.label, 'state', r.state) ORDER BY r.ord), '[]'::jsonb) INTO v_others
      FROM clearance.stage_rows(q.purpose, q.session, ARRAY[q.student_id]) r
     WHERE r.unit <> 'BURSARY' AND r.required AND r.applies AND r.state NOT IN ('CLEARED', 'NOT_APPLICABLE');
    SELECT r.state INTO v_bursary FROM clearance.stage_rows(q.purpose, q.session, ARRAY[q.student_id]) r WHERE r.unit = 'BURSARY';
    -- the academic record, as the award rests on it
    -- V668: an award of the College Academic Board rests on the Board's own decision (the professional examinations), not the course record
    IF g.basis IS DISTINCT FROM 'COLLEGE_BOARD' THEN
        SELECT * INTO c FROM people.lifecycle_completion_rows(ARRAY[q.student_id]);
    ELSE
        SELECT NULL::text AS completion, NULL::text AS outstanding_courses, NULL::text AS awaiting_courses INTO c;
    END IF;
    IF a.outstanding > 0 THEN v_block := v_block || ('Outstanding school fees: ' || clearance.naira(a.outstanding) || ' (' || a.owing_words || ')'); END IF;
    IF a.review > 0 THEN v_block := v_block || ('Historical fee assessment required for ' || a.review_words); END IF;
    IF a.pending > 0 THEN v_block := v_block || ('A historical fee assessment awaits the Bursar''s approval for ' || a.pending_words); END IF;
    IF jsonb_array_length(v_others) > 0 THEN
        v_block := v_block || ('Still to clear: ' || (SELECT string_agg(o->>'label', ', ') FROM jsonb_array_elements(v_others) o));
    END IF;
    IF v_grad AND c.completion = 'OUTSTANDING_COURSES' THEN v_block := v_block || ('A carry-over is still owed: ' || coalesce(c.outstanding_courses, '')); END IF;
    IF v_grad AND c.completion = 'AWAITING_RESULT' THEN v_block := v_block || ('A result is still awaited: ' || coalesce(c.awaiting_courses, '')); END IF;
    IF q.cancelled_at IS NOT NULL THEN v_block := v_block || 'The clearance was cancelled'::text; END IF;
    RETURN jsonb_build_object(
        'process', q.id, 'reference', q.reference, 'workflow', q.wf, 'graduates', v_grad, 'status', s.status, 'bursaryState', v_bursary,
        'graduand', CASE WHEN g.id IS NULL THEN NULL ELSE jsonb_build_object('session', g.session, 'award', g.award, 'minute', g.senate_minute, 'approvedAt', g.approved_at) END,
        'assessed', a.assessed, 'paid', a.paid, 'waived', a.waived, 'outstanding', a.outstanding, 'credit', a.credit, 'periods', a.periods,
        'reviewPeriods', a.review, 'pendingPeriods', a.pending, 'unsettled', a.unsettled, 'pendingWaivers', v_pending_waivers, 'otherPayments', v_other_payments,
        'othersPending', v_others,
        'academic', jsonb_build_object('ok', coalesce(c.completion, '') NOT IN ('OUTSTANDING_COURSES', 'AWAITING_RESULT'), 'completion', c.completion,
                                       'outstandingCourses', c.outstanding_courses, 'awaitingCourses', c.awaiting_courses),
        'blockers', to_jsonb(v_block), 'ready', cardinality(v_block) = 0);
END $fn$;
COMMENT ON FUNCTION clearance.final_check(uuid) IS
  'V665, V668 (a College Board award read on the Board''s decision): what the Bursar''s confirmation of a final clearance rests on, read afresh — whether it graduates the student (an approved award, the record not yet GRADUATED), the school-fee account (assessed, paid, waived, outstanding, the periods owing or unsettled), waivers pending, other payments in an owing session, the other offices still to clear, the academic record, and the blockers in words; ready when there are none';

-- ── 8 · the Bursar's confirmation graduates the student ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION records.graduate_on_final_clearance(p_process uuid, p_actor uuid, p_office text, p_override boolean)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE q clearance.process; s people.student; g records.graduand; c record; pr record; reach record; v_who text; v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date;
BEGIN
    SELECT * INTO q FROM clearance.process WHERE id = p_process;
    IF q.id IS NULL THEN RAISE EXCEPTION 'CLR_NO_PROCESS: no such clearance' USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO s FROM people.student WHERE id = q.student_id FOR UPDATE;
    IF s.status = 'GRADUATED' THEN RETURN jsonb_build_object('outcome', 'ALREADY_GRADUATED'); END IF;
    SELECT * INTO g FROM records.graduand WHERE student_id = q.student_id AND senate_state = 'APPROVED' ORDER BY session DESC LIMIT 1 FOR UPDATE;
    IF g.id IS NULL THEN RETURN jsonb_build_object('outcome', 'NO_APPROVED_AWARD'); END IF;
    IF s.status NOT IN ('ACTIVE', 'PROBATION') THEN
        RAISE EXCEPTION 'GRAD_STATUS: a student who is % is not graduated', lower(replace(s.status, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    -- V668: an award of the College Academic Board rests on the Board's own decision (the professional examinations), not the course record
    IF g.basis IS DISTINCT FROM 'COLLEGE_BOARD' THEN
        SELECT * INTO c FROM people.lifecycle_completion_rows(ARRAY[q.student_id]);
    ELSE
        SELECT NULL::text AS completion, NULL::text AS outstanding_courses, NULL::text AS awaiting_courses INTO c;
    END IF;
    IF c.completion = 'OUTSTANDING_COURSES' THEN
        RAISE EXCEPTION 'GRAD_CARRY_OVER: a carry-over is still owed: %', coalesce(c.outstanding_courses, '') USING ERRCODE = '23514';
    END IF;
    IF c.completion = 'AWAITING_RESULT' THEN
        RAISE EXCEPTION 'GRAD_RESULT_AWAITED: a result is still awaited: %', coalesce(c.awaiting_courses, '') USING ERRCODE = '23514';
    END IF;
    v_who := coalesce(helpdesk.person_name(p_actor), p_office);
    PERFORM people.change_status(q.student_id, 'GRADUATED', g.senate_minute, v_today,
        'Final clearance ' || q.reference || ' completed: the Bursary''s clearance confirmed by ' || coalesce(v_who, 'the Bursar')
        || CASE WHEN coalesce(p_override, false) THEN ' (an override by ' || coalesce(p_office, 'the Registry') || ')' ELSE '' END);
    UPDATE records.graduand SET graduated_at = now(), graduated_by = p_actor, actor_office = p_office WHERE id = g.id;
    UPDATE records.graduation_batch_row SET graduated_at = now() WHERE graduand_id = g.id AND graduated_at IS NULL;
    INSERT INTO finance.historical_stale (student_id) VALUES (q.student_id) ON CONFLICT (student_id) DO UPDATE SET marked_at = now();
    SELECT p.name, d.name AS dept_name, f.name AS faculty_name INTO pr
      FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code WHERE p.code = s.programme_code;
    SELECT * INTO reach FROM people.student_reach(q.student_id);
    PERFORM platform.notify('STUDENT_GRADUATED', NULL, jsonb_build_object(
                'FIRST_NAME', coalesce(nullif(split_part(coalesce(s.other_names, ''), ' ', 1), ''), s.surname),
                'AWARD', g.award, 'PROGRAMME', coalesce(pr.name, s.programme_code), 'DEPARTMENT', coalesce(pr.dept_name, ''), 'FACULTY', coalesce(pr.faculty_name, ''),
                'MINUTE', g.senate_minute, 'SESSION', g.session, 'MATRIC', coalesce(s.matric_no, s.admission_no, ''),
                'CLEARANCE', 'complete — every office has cleared you (' || q.reference || ')'),
            'student', q.student_id, reach.email, reach.phone, 'graduated:' || q.student_id);
    RETURN jsonb_build_object('outcome', 'GRADUATED', 'graduand_id', g.id, 'session', g.session, 'minute', g.senate_minute, 'date', v_today);
END $fn$;
COMMENT ON FUNCTION records.graduate_on_final_clearance(uuid, uuid, text, boolean) IS
  'V665, V668 (a College Board award read on the Board''s decision, not the course record): the Bursar''s confirmation of a final clearance graduates a student whose award is approved — the academic record checked again, GRADUATED on the award''s minute with the clearance and the Bursar in the reason, the moment and the officer on the list entry and the batch row, the historical summary marked to be worked out again, the student told (STUDENT_GRADUATED); a graduated student or one with no approved award is left as they are';


COMMIT;
