-- ═══════════════════════════════════════
-- V665 — graduation at the Bursar's final clearance, approved school-fee waivers, and clearance financial reconciliation runs
--
-- The University's master prompt of 26 October 2026 ("COMPREHENSIVE GRADUATION CLEARANCE, SCHOOL FEES RECONCILIATION & OUTSTANDING
-- BALANCE ENGINE"), with the University's answers: a student becomes GRADUATED at the Bursar's final clearance, and approved waivers
-- reduce what a student owes. Most of the engine stood: each graduate's and graduand's school fees by session and semester at the
-- fees of the period, a period with no structure for review and a historical assessment to settle it, the verified school-fee
-- payments (JAMB-named and reallocated included) allocated first semester first, the student's own view and online payment of an old
-- balance (V654); the FINAL clearance's Bursary stage reading that account at the moment of decision and refusing over anything owed
-- (V654 on V415); the record closed to new fees and registration once graduated (V602). What changes:
--
--   · graduation moves to the end of the final clearance. records.graduate_one (a graduation batch, the session's list approved) and
--     admissions.pg_award (a postgraduate award) approve the award on the Senate's minute (records.graduand.approved_at/_by) and start
--     the FINAL clearance — the status stays as it is; the student is told the award is approved and the clearance under way
--     (STUDENT_AWARD_APPROVED). The FINAL clearance's Bursary stage is now last; for an approved graduand not yet graduated its own
--     CLEARED is the Bursar's alone (CLR_BURSAR_ONLY; a Registry override with a reason clears the stage as before and graduates
--     nobody), refused while another office is pending (CLR_BURSARY_LAST), while anything is owed or under assessment
--     (CLR_OUTSTANDING, as before, read afresh), or while the academic record no longer holds (a carry-over owed, a result awaited);
--     accepted on a clearance already complete — and in the same transaction it graduates the student
--     (records.graduate_on_final_clearance: GRADUATED on the award's minute, the moment and the Bursar on the list entry and the
--     batch row, the student told: STUDENT_GRADUATED). clearance.final_check(process) says all of it before the Bursar confirms. A
--     student graduated before stays graduated; their FINAL clearance is financial as it was. No reconciliation graduates an
--     approved award: people.decide_cohort refuses it (COHORT_GRADUATION_CLEARANCE) and the R1 bulk act leaves such students out.
--   · an approved graduand awaiting final clearance is closed to a later session's school fees and course registration as a
--     graduate is (finance.closed_for_fees, registration.student_draft); the data-quality check "award approved, still in study"
--     no longer counts a graduand whose final clearance is under way.
--   · approved waivers and adjustments (finance.historical_waiver, HFW/YYYY/NNNNNN): proposed for a session and semester by the
--     Students Account Officer or the Bursar with a reason, the approval it rests on and its evidence, for no more than the period
--     still owes; approved or rejected by another officer of the Bursar's office (the amount read again), withdrawn while pending,
--     revoked by the Bursar with a reason, never edited; an approved one lowers the period's amount before the payments are
--     allocated (finance.historical_rows: waived, the column last), never below nothing; the student is told
--     (HISTORICAL_FEES_ADJUSTED). Never a payment, never "marked paid".
--   · clearance financial reconciliation runs (CLEARANCE-RECON/YYYY/NNNNNN): the approved graduands awaiting final clearance, the
--     students under final clearance, the graduates, or all of them, narrowed by faculty, department, programme and session, read at
--     once — assessed, paid, waived, outstanding, the periods owing, for review or pending, and the payments in an owing session that
--     are not school fees yet read like fees (an old-portal outstanding-fees payment, one named for tuition or JAMB: PAYMENT_REVIEW)
--     — kept as the run read them; nothing in the money is changed by a run.
-- ═══════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V665: graduation at the Bursar''s final clearance, approved school-fee waivers, clearance reconciliation runs', true);

-- ── 1 · the award approved apart from the graduation ─────────────────────────────────────────────────────────────────────
ALTER TABLE records.graduand ADD COLUMN IF NOT EXISTS approved_at timestamptz NULL;
ALTER TABLE records.graduand ADD COLUMN IF NOT EXISTS approved_by uuid NULL;
COMMENT ON COLUMN records.graduand.approved_at IS 'V665: when the award was approved on the Senate''s minute (a graduation batch, the session''s list, a postgraduate award)';
COMMENT ON COLUMN records.graduand.graduated_at IS 'V602, V665: when the student became GRADUATED — since V665 at the Bursar''s confirmation of the final clearance';
-- the awards approved before V665 graduated in the same act
UPDATE records.graduand SET approved_at = coalesce(approved_at, graduated_at), approved_by = coalesce(approved_by, graduated_by)
 WHERE senate_state = 'APPROVED' AND approved_at IS NULL;

-- ── 2 · the Bursary confirms last ─────────────────────────────────────────────────────────────────────────────────────────
UPDATE clearance.workflow_stage
   SET ord = (SELECT max(x.ord) + 1 FROM clearance.workflow_stage x WHERE x.workflow = 'FINAL'), waits = true, updated_at = now()
 WHERE workflow = 'FINAL' AND unit = 'BURSARY'
   AND ord < (SELECT max(x.ord) FROM clearance.workflow_stage x WHERE x.workflow = 'FINAL');

-- ── 3 · the notice: the award approved, the clearance under way ──────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('STUDENT_AWARD_APPROVED', 'Award approved — final clearance under way',
 'To the student when the award is approved on the Senate''s minute (a graduation batch, the session''s list, a postgraduate award): the final clearance begins, and the record reads GRADUATED once the Bursar confirms it',
 'Your award is approved — final clearance under way ([SESSION])',
 E'Dear [FIRST_NAME],\n\nYour award of [AWARD] in [PROGRAMME] ([DEPARTMENT], [FACULTY]) is approved under Senate minute [MINUTE], graduation session [SESSION].\n\nYour final clearance is [CLEARANCE]: each office clears you against your record, and the Bursary clears you last against your school fees for every session and semester of your studies. When the Bursar confirms your final clearance, your record (matriculation number [MATRIC]) reads GRADUATED.\n\nFollow your clearance, and settle anything outstanding, on your portal.',
 'MOAUM: your award of [AWARD] is approved under [MINUTE] ([SESSION]). Your final clearance is [CLEARANCE]; you graduate when the Bursar confirms it. See the portal.',
 'Award approved — final clearance under way',
 'Your award of [AWARD] in [PROGRAMME] is approved under Senate minute [MINUTE] (graduation session [SESSION]). Final clearance: [CLEARANCE]. You graduate when the Bursar confirms it.',
 ARRAY['FIRST_NAME','AWARD','PROGRAMME','DEPARTMENT','FACULTY','MINUTE','SESSION','MATRIC','CLEARANCE'], true, 'HIGH')
ON CONFLICT (key) DO NOTHING;
UPDATE platform.notice_template
   SET purpose = 'To the student when the Bursar confirms the final clearance and the record becomes GRADUATED (since V665; before, when the award was confirmed)'
 WHERE key = 'STUDENT_GRADUATED';
UPDATE platform.notice_template
   SET label = 'Approved graduands awaiting final clearance',
       purpose = 'To the Bursary and the Students Account Office when a graduation batch approves awards and the students'' final clearance begins (since V665 the Bursary''s confirmation, last, graduates them)',
       email_subject = '[COUNT] graduands of [SESSION] begin final clearance ([BATCH])',
       email_body = E'Dear [FIRST_NAME],\n\nThe Academic Office has approved the award of [COUNT] student(s) under graduation batch [BATCH] (session [SESSION], Senate minute [MINUTE]). Their final clearance is under way. The Bursary''s stage comes last: once the other offices have cleared a student, the office verifies the school fees of every session and semester, the payments and any approved waiver, and the Bursar''s clearance graduates the student. Nothing is deleted and nothing is marked paid: a student who owes is not cleared, with the reason.\n\nOpen Financial Clearance on the portal.',
       portal_title = 'Graduands begin final clearance',
       portal_body = '[COUNT] graduand(s) of [SESSION] under batch [BATCH] begin final clearance; the Bursar''s clearance, last, graduates each.'
 WHERE key = 'GRADUATION_CLEARANCE_WAITING';

-- ── 4 · an approved graduand awaiting final clearance is closed to a later session's fees and registration ───────────────
CREATE OR REPLACE FUNCTION records.awaiting_final_clearance(p_student uuid) RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT EXISTS (SELECT 1 FROM people.student s WHERE s.id = p_student AND s.status <> 'GRADUATED')
       AND EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = p_student AND g.senate_state = 'APPROVED')
$fn$;
COMMENT ON FUNCTION records.awaiting_final_clearance(uuid) IS
  'V665: whether the student''s award is approved and the record not yet GRADUATED — the final clearance under way, the Bursar''s confirmation to come';

CREATE OR REPLACE FUNCTION finance.closed_for_fees(p_student uuid, p_session text) RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT (s.status = 'GRADUATED' OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED'))
           AND (gs.name IS NULL OR p_session > gs.name)
      FROM people.student s
      LEFT JOIN LATERAL (SELECT records.graduation_session(s.id) AS name) gs ON true
     WHERE s.id = p_student
$fn$;
COMMENT ON FUNCTION finance.closed_for_fees(uuid, text) IS
  'V602, V665: whether a session''s school fees are closed on the record — a graduated record, or one whose award is approved and final clearance under way, owes nothing for a session after its graduation session; sessions up to it keep their history and may be settled';

CREATE OR REPLACE FUNCTION registration.student_draft(p_student uuid, p_session text, p_semester integer)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v uuid; s people.student; m record;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
    -- V602/V604: a graduated record is closed to course registration (and so to carry-overs) on every path; every other status is
    -- judged where it always was — the student's own doors in the API, the deferment and support engines in theirs
    IF s.status = 'GRADUATED' THEN
        RAISE EXCEPTION 'REG_STUDENT_NOT_ELIGIBLE: Course registration is unavailable because this academic record has been graduated.'
            USING ERRCODE = '23514';
    END IF;
    -- V665: and so is a record whose award is approved, for a session after its graduation session: the final clearance is under way
    IF records.awaiting_final_clearance(p_student) AND p_session > records.graduation_session(p_student) THEN
        RAISE EXCEPTION 'REG_STUDENT_NOT_ELIGIBLE: Course registration is unavailable: the award is approved and the final clearance is under way.'
            USING ERRCODE = '23514';
    END IF;
    SELECT id INTO v FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF v IS NOT NULL THEN RETURN v; END IF;
    v := gen_random_uuid();
    INSERT INTO registration.course_registration (id, student_id, session, semester, level)
    VALUES (v, p_student, p_session, p_semester, s.current_level);
    FOR m IN SELECT * FROM registration.student_menu(p_student, p_session, p_semester) WHERE carryover LOOP
        -- V512: a GST/EPS carry-over waits for the GST fee: being a carry-over does not pass it
        IF registration.gst_course_hold(p_student, p_session, m.course_code) IS NOT NULL THEN CONTINUE; END IF;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (v, m.offering_id, m.units, CASE WHEN m.deferred THEN 'DEFERRED' ELSE 'CARRYOVER' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        IF FOUND THEN PERFORM registration.gst_course_registered(v, m.offering_id); END IF;
    END LOOP;
    RETURN v;
END $function$;

-- the data-quality check "award approved, still in study": a graduand whose final clearance is under way is where V665 puts them
CREATE OR REPLACE FUNCTION reporting.data_quality_rows(p_fac text, p_dept text, p_prog text, p_session text, p_semester int)
RETURNS TABLE (kind text, student_id uuid, detail text)
LANGUAGE sql STABLE AS $fn$
    WITH st AS MATERIALIZED (
        SELECT s.id, s.status, s.matric_no, s.jamb_reg_no, s.entry_session, s.entry_level, s.current_level, s.programme_code,
               p.code AS p_code, p.archived AS p_archived, p.dept_code, p.faculty_code, d.code AS d_code, f.code AS f_code,
               s.status <> ALL (ARRAY['GRADUATED', 'COMPLETED', 'WITHDRAWN', 'VOLUNTARY_WITHDRAWAL', 'EXPELLED', 'TRANSFERRED_OUT', 'DECEASED', 'PROGRESSED', 'MERGED']) AS live
          FROM people.student s
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN ref.department d ON d.code = p.dept_code
          LEFT JOIN ref.faculty f ON f.code = p.faculty_code
         WHERE s.duplicate_of IS NULL
           AND (p_fac IS NULL OR p.faculty_code = p_fac)
           AND (p_dept IS NULL OR p.dept_code = p_dept)
           AND (p_prog IS NULL OR p.code = p_prog)),
    ap AS MATERIALIZED (
        SELECT a.student_id, a.issues, a.spillover_years, a.current_session, a.current_level, a.computed_level
          FROM people.academic_position a WHERE a.student_id IN (SELECT st.id FROM st)),
    cfg AS (SELECT max_spillover_years FROM policy.progression_setting WHERE row_no)
    SELECT 'INVALID_PROGRAMME', st.id, coalesce('programme ' || st.programme_code || ' is archived', 'programme ' || coalesce(st.programme_code, '—') || ' is not on the register')
      FROM st WHERE st.live AND (st.p_code IS NULL OR st.p_archived)
    UNION ALL
    SELECT 'MISSING_FACULTY_DEPARTMENT', st.id, 'programme ' || st.programme_code || ' has ' || CASE WHEN st.d_code IS NULL THEN 'no department' ELSE 'no faculty' END
      FROM st WHERE st.live AND st.p_code IS NOT NULL AND (st.d_code IS NULL OR st.f_code IS NULL)
    UNION ALL
    SELECT 'MISSING_ENTRY_SESSION', st.id, coalesce('entry session ' || st.entry_session || ' is not a session of the University', 'no entry session')
      FROM st WHERE st.live AND (st.entry_session IS NULL OR NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = st.entry_session))
    UNION ALL
    SELECT 'INVALID_LEVEL', st.id, 'level on record ' || coalesce(st.current_level::text, 'none') || coalesce(', entry level ' || st.entry_level, '')
      FROM st WHERE st.live AND (st.current_level IS NULL OR st.current_level % 100 <> 0 OR st.current_level NOT BETWEEN 100 AND 900
                                 OR (st.entry_level IS NOT NULL AND st.current_level < st.entry_level))
    UNION ALL
    SELECT 'MISSING_MATRIC', st.id, 'in study as ' || lower(st.status) || ' with no matriculation number'
      FROM st WHERE st.status IN ('ACTIVE', 'PROBATION') AND nullif(btrim(coalesce(st.matric_no, '')), '') IS NULL
    UNION ALL
    SELECT 'DUPLICATE_MATRIC', st.id, 'matriculation number ' || st.matric_no || ' is held by ' || x.n || ' records'
      FROM st JOIN (SELECT upper(btrim(s2.matric_no)) AS k, count(*) AS n FROM people.student s2
                     WHERE s2.duplicate_of IS NULL AND nullif(btrim(coalesce(s2.matric_no, '')), '') IS NOT NULL
                     GROUP BY 1 HAVING count(*) > 1) x ON x.k = upper(btrim(st.matric_no))
    UNION ALL
    SELECT 'DUPLICATE_JAMB', st.id, 'JAMB number ' || st.jamb_reg_no || ' is held by ' || x.n || ' records'
      FROM st JOIN (SELECT upper(btrim(s2.jamb_reg_no)) AS k, count(*) AS n FROM people.student s2
                     WHERE s2.duplicate_of IS NULL AND nullif(btrim(coalesce(s2.jamb_reg_no, '')), '') IS NOT NULL
                     GROUP BY 1 HAVING count(*) > 1) x ON x.k = upper(btrim(st.jamb_reg_no))
    UNION ALL
    SELECT 'UNCLASSIFIED', st.id, coalesce('requires classification: ' || sc.classification_issue, 'no programme type')
      FROM st LEFT JOIN people.student_classification sc ON sc.student_id = st.id
     WHERE st.live AND (sc.student_id IS NULL OR sc.programme_type IS NULL)
    UNION ALL
    SELECT 'CONFLICTING_STATUS', st.id, array_to_string(ARRAY(SELECT i FROM unnest(ap.issues) i WHERE i IN ('GRADUATED_WITHOUT_APPROVAL', 'DEFERRED_WITHOUT_LIVE_DEFERMENT')), ', ')
      FROM st JOIN ap ON ap.student_id = st.id
     WHERE ap.issues && ARRAY['GRADUATED_WITHOUT_APPROVAL', 'DEFERRED_WITHOUT_LIVE_DEFERMENT']
    UNION ALL
    SELECT 'GRADUATED_STILL_ACTIVE', st.id, 'the award is approved, no final clearance is under way, and the record reads ' || lower(st.status)
      FROM st JOIN ap ON ap.student_id = st.id
     WHERE 'APPROVED_NOT_GRADUATED' = ANY (ap.issues)
       AND NOT EXISTS (SELECT 1 FROM clearance.process q WHERE q.student_id = st.id AND q.workflow = 'FINAL' AND q.cancelled_at IS NULL AND q.completed_at IS NULL)
    UNION ALL
    SELECT 'LEVEL_INCONSISTENT', st.id, 'level on record ' || coalesce(ap.current_level::text, '—') || ', computed ' || coalesce(ap.computed_level::text, '—')
      FROM st JOIN ap ON ap.student_id = st.id WHERE st.live AND 'LEVEL_CONFLICT' = ANY (ap.issues)
    UNION ALL
    SELECT 'BEYOND_MAXIMUM_PERIOD', st.id, ap.spillover_years || ' sessions beyond the expected completion; ' || cfg.max_spillover_years || ' allowed'
      FROM st JOIN ap ON ap.student_id = st.id CROSS JOIN cfg
     WHERE st.status IN ('ACTIVE', 'PROBATION') AND ap.current_session IS NOT NULL AND ap.spillover_years > cfg.max_spillover_years
       AND NOT records.awaiting_final_clearance(st.id)
    UNION ALL
    SELECT CASE r.readiness WHEN 'PAID_NOT_REGISTERED' THEN 'PAID_NOT_REGISTERED' ELSE 'REGISTERED_NOT_PAID' END, r.student_id,
           p_session || ' semester ' || p_semester || ': ' || CASE r.readiness WHEN 'PAID_NOT_REGISTERED' THEN 'school fees paid, no registration with courses'
                                                                ELSE 'registered, no school-fees payment (₦' || r.outstanding || ' outstanding)' END
      FROM reporting.exam_readiness(p_session, p_semester, p_fac, p_dept, p_prog, NULL, NULL, NULL, 'CARD') r
     WHERE p_session IS NOT NULL AND p_semester IS NOT NULL
       AND (r.readiness = 'PAID_NOT_REGISTERED' OR (r.readiness = 'NOT_PAID' AND r.registered))
$fn$;
COMMENT ON FUNCTION reporting.data_quality_rows(text, text, text, text, int) IS
  'V640, V665: each record of the scope with a data fault, by kind — invalid programme, missing faculty or department, missing or invalid entry session, invalid level, missing or duplicate matriculation number, duplicate JAMB number, unclassified, conflicting statuses, graduated still active (an approved award with no final clearance under way), level inconsistent, beyond the maximum period (not an approved graduand awaiting final clearance), and for a session and semester paid not registered and registered not paid';

-- ── 5 · the award approved on the Senate's minute: the final clearance begins, the status stays (V602 restated) ────────────
CREATE OR REPLACE FUNCTION records.graduate_one(p_student uuid, p_session text, p_minute text, p_batch_ref text, p_reason text, p_actor uuid, p_office text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE s people.student; g records.graduand; c record; ap record; pr record; reach record; v_clear text; v_minute text; v_proc uuid; v_err text;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'GRAD_NO_STUDENT: no such student' USING ERRCODE = '23503'; END IF;
    IF s.status = 'GRADUATED' THEN
        RETURN jsonb_build_object('outcome', 'ALREADY_GRADUATED', 'graduand_id', (SELECT id FROM records.graduand WHERE student_id = p_student AND senate_state = 'APPROVED' ORDER BY session DESC LIMIT 1));
    END IF;
    IF s.status NOT IN ('ACTIVE', 'PROBATION') THEN
        RAISE EXCEPTION 'GRAD_STATUS: a student who is % is not graduated', lower(replace(s.status, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO g FROM records.graduand WHERE student_id = p_student AND session = p_session FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'GRAD_NOT_ON_LIST: not on the graduation list of %', p_session USING ERRCODE = '23514'; END IF;
    IF g.senate_state = 'REFERRED' THEN RAISE EXCEPTION 'GRAD_REFERRED: referred by Senate on the graduation list of %', p_session USING ERRCODE = '23514'; END IF;
    -- V665: an award approved before and still awaiting its final clearance is not approved twice; its clearance is made sure of
    IF g.senate_state = 'APPROVED' THEN
        SELECT q.id INTO v_proc FROM clearance.process q WHERE q.workflow = 'FINAL' AND q.student_id = p_student AND q.cancelled_at IS NULL ORDER BY q.started_at DESC LIMIT 1;
        IF v_proc IS NULL THEN
            BEGIN
                v_proc := clearance.start('FINAL', p_student, p_session, 'ELIGIBLE', NULL, p_actor, p_office);
                v_clear := 'started';
            EXCEPTION WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
                v_clear := 'not started — ' || left(v_err, 160);
            END;
        ELSE
            v_clear := 'under way';
        END IF;
        RETURN jsonb_build_object('outcome', 'AWAITING_FINAL_CLEARANCE', 'graduand_id', g.id, 'clearance', v_clear, 'process', v_proc, 'minute', g.senate_minute);
    END IF;
    IF g.unmet IS NOT NULL OR g.cgpa IS NULL THEN
        RAISE EXCEPTION 'GRAD_NOT_ELIGIBLE: %', coalesce(g.unmet, 'no published result on the record') USING ERRCODE = '23514';
    END IF;
    v_minute := coalesce(nullif(btrim(coalesce(g.senate_minute, '')), ''), nullif(btrim(coalesce(p_minute, '')), ''));
    IF v_minute IS NULL THEN
        RAISE EXCEPTION 'GRAD_MINUTE_REQUIRED: an award is confirmed on a Senate minute, and none was cited' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM people.lifecycle_completion_rows(ARRAY[p_student]);
    IF c.completion = 'OUTSTANDING_COURSES' THEN
        RAISE EXCEPTION 'GRAD_CARRY_OVER: a carry-over is still owed: %', coalesce(c.outstanding_courses, '') USING ERRCODE = '23514';
    END IF;
    IF c.completion = 'AWAITING_RESULT' THEN
        RAISE EXCEPTION 'GRAD_RESULT_AWAITED: a result is still awaited: %', coalesce(c.awaiting_courses, '') USING ERRCODE = '23514';
    END IF;
    SELECT a.spillover_state INTO ap FROM people.academic_position a WHERE a.student_id = p_student;
    SELECT p.duration_years, p.name, p.dept_code, d.name AS dept_name, f.name AS faculty_name INTO pr
      FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE p.code = s.programme_code;
    UPDATE records.graduand
       SET senate_state = 'APPROVED', senate_minute = v_minute, batch_ref = coalesce(p_batch_ref, batch_ref), approved_at = now(), approved_by = p_actor,
           actor_office = p_office, final_level = records.final_level_of(p_student), duration_years = pr.duration_years,
           spillover_state = ap.spillover_state, entry_session = s.entry_session
     WHERE id = g.id;
    -- V665: the status stays; the final clearance begins where none is under way (an engine refusal is recorded, never fatal) and the
    -- Bursar's confirmation of it, last, graduates the student (records.graduate_on_final_clearance)
    SELECT q.id INTO v_proc FROM clearance.process q WHERE q.workflow = 'FINAL' AND q.student_id = p_student AND q.cancelled_at IS NULL ORDER BY q.started_at DESC LIMIT 1;
    IF v_proc IS NOT NULL THEN
        v_clear := 'under way';
    ELSE
        BEGIN
            v_proc := clearance.start('FINAL', p_student, p_session, 'ELIGIBLE', NULL, p_actor, p_office);
            v_clear := 'started';
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
            v_clear := 'not started — ' || left(v_err, 160);
        END;
    END IF;
    SELECT * INTO reach FROM people.student_reach(p_student);
    PERFORM platform.notify('STUDENT_AWARD_APPROVED', NULL, jsonb_build_object(
                'FIRST_NAME', coalesce(nullif(split_part(coalesce(s.other_names, ''), ' ', 1), ''), s.surname),
                'AWARD', g.award, 'PROGRAMME', coalesce(pr.name, s.programme_code), 'DEPARTMENT', coalesce(pr.dept_name, ''), 'FACULTY', coalesce(pr.faculty_name, ''),
                'MINUTE', v_minute, 'SESSION', p_session, 'MATRIC', coalesce(s.matric_no, s.admission_no, ''),
                'CLEARANCE', CASE WHEN v_clear IN ('started', 'under way') THEN 'under way' ELSE 'to be started by the Registry' END),
            'student', p_student, reach.email, reach.phone, 'award-approved:' || p_student || ':' || p_session);
    RETURN jsonb_build_object('outcome', 'APPROVED', 'graduand_id', g.id, 'clearance', v_clear, 'process', v_proc, 'minute', v_minute);
END $fn$;
COMMENT ON FUNCTION records.graduate_one(uuid, text, text, text, text, uuid, text) IS
  'V602, V665: one student''s award approved, all or nothing — revalidated (in study, on the session''s list with nothing unmet or Senate-approved, no carry-over owed, no result awaited, a minute cited), the list entry approved with the batch and the moment, the final clearance started, the student told (STUDENT_AWARD_APPROVED); the status stays until the Bursar confirms the final clearance (records.graduate_on_final_clearance). A graduated student is returned ALREADY_GRADUATED, an award approved before AWAITING_FINAL_CLEARANCE (its clearance made sure of)';

CREATE OR REPLACE FUNCTION records.approve_awards(p_session text, p_minute text) RETURNS integer LANGUAGE plpgsql AS $function$
DECLARE n int := 0; g record; v_actor uuid; v_office text; r jsonb;
BEGIN
    IF p_minute IS NULL OR btrim(p_minute) = '' THEN
        RAISE EXCEPTION 'the graduation list is approved on a Senate minute, and none was cited'
        USING ERRCODE = '23514', HINT = 'Cite the minute of the Senate that approved the awards.';
    END IF;
    v_actor := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_office := nullif(current_setting('moaum.actor_office', true), '');
    -- V602/V665: every audited graduand with nothing unmet has the award approved by the one act (its final clearance started); one
    -- approved earlier but still awaiting has its final clearance made sure of
    FOR g IN
        SELECT gr.student_id
          FROM records.graduand gr JOIN people.student s ON s.id = gr.student_id
         WHERE gr.session = p_session AND gr.unmet IS NULL AND gr.cgpa IS NOT NULL
           AND (gr.senate_state = 'AWAITING' OR (gr.senate_state = 'APPROVED' AND s.status <> 'GRADUATED'))
         ORDER BY s.surname, s.other_names
    LOOP
        r := records.graduate_one(g.student_id, p_session, btrim(p_minute), NULL, 'Award approved by Senate', v_actor, v_office);
        IF r->>'outcome' = 'APPROVED' THEN n := n + 1; END IF;
    END LOOP;
    RETURN n;
END $function$;
COMMENT ON FUNCTION records.approve_awards(text, text) IS
  'V029/V602/V665: the session''s graduation list approved on a Senate minute — each audited graduand with nothing unmet has the award approved by records.graduate_one (the final clearance started, the student told); returns how many were approved. The record reads GRADUATED once the Bursar confirms each final clearance';

-- a batch counts the awards it approved (outcome APPROVED) beside those graduated before V665
CREATE OR REPLACE FUNCTION records.graduation_batch_tally(p_ref text) RETURNS void LANGUAGE sql AS $fn$
    UPDATE records.graduation_batch b
       SET selected = t.selected, eligible = t.eligible, graduated = t.graduated, rejected = t.rejected, review = t.review
      FROM (SELECT count(*)::int AS selected,
                   count(*) FILTER (WHERE r.verdict = 'ELIGIBLE')::int AS eligible,
                   count(*) FILTER (WHERE r.outcome IN ('GRADUATED', 'APPROVED'))::int AS graduated,
                   count(*) FILTER (WHERE r.verdict NOT IN ('ELIGIBLE', 'REQUIRES_REVIEW', 'ALREADY_GRADUATED') OR r.outcome = 'REFUSED')::int AS rejected,
                   count(*) FILTER (WHERE r.verdict = 'REQUIRES_REVIEW')::int AS review
              FROM records.graduation_batch_row r JOIN records.graduation_batch bb ON bb.id = r.batch_id WHERE bb.batch_ref = p_ref) t
     WHERE b.batch_ref = p_ref
$fn$;
COMMENT ON COLUMN records.graduation_batch.graduated IS 'V602, V665: the awards the batch approved (graduated in the same act before V665; since V665 graduated at the Bursar''s final clearance)';

-- ── 6 · a postgraduate award likewise approved, the final clearance begun (V255 restated) ─────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_award(p_research uuid, p_minute text, p_session text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE r admissions.pg_research; s people.student; v_award text; v_cgpa numeric; v_session text; v_g uuid; v_proc uuid; v_clear text; v_err text;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        pr record; reach record;
BEGIN
    IF p_minute IS NULL OR btrim(p_minute) = '' THEN
        RAISE EXCEPTION 'an award is recorded on a Senate minute, and none was cited'
        USING ERRCODE = '23514', HINT = 'Cite the minute of the Senate that approved the award.';
    END IF;
    SELECT * INTO r FROM admissions.pg_research WHERE id = p_research;
    IF r.id IS NULL THEN RAISE EXCEPTION 'no such research record' USING ERRCODE = '23503'; END IF;
    IF r.stage NOT IN ('AWARD_RECOMMENDED', 'AWARDED') THEN
        RAISE EXCEPTION 'the award follows the School Board''s recommendation; this record is at %', lower(replace(r.stage, '_', ' '))
        USING ERRCODE = '23514', HINT = 'Record the Board''s recommendation first.';
    END IF;
    SELECT * INTO s FROM people.student WHERE id = r.student_id;
    IF s.matric_no IS NULL THEN
        RAISE EXCEPTION 'an award is recorded for a matriculated student; % has no matriculation number', s.surname
        USING ERRCODE = '23514', HINT = 'Matriculate the student (fees and registration) before the award is recorded.';
    END IF;
    SELECT coalesce(nullif(btrim(g.pg_award), ''), g.name) INTO v_award FROM ref.programme g WHERE g.code = s.programme_code;
    v_cgpa := coalesce(admissions.pg_cgpa(s.id), 0);
    -- the graduation session must be one the register knows; the PG School's calendar name is used when it is
    v_session := coalesce(
        (SELECT name FROM policy.academic_session WHERE name = nullif(btrim(p_session), '')),
        (SELECT name FROM policy.academic_session WHERE name = admissions.pg_current_session()),
        (SELECT name FROM policy.academic_session WHERE state = 'CURRENT'),
        (SELECT name FROM policy.academic_session ORDER BY name DESC LIMIT 1));

    UPDATE admissions.pg_research SET stage = 'AWARDED', awarded_at = coalesce(awarded_at, now()), updated_at = now() WHERE id = r.id;
    INSERT INTO admissions.pg_research_event (research_id, stage, note)
    VALUES (r.id, 'AWARDED', 'Award of ' || v_award || ' approved by Senate under minute ' || btrim(p_minute));

    INSERT INTO records.graduand (id, student_id, session, cgpa, award, unmet, senate_state, senate_minute, approved_at, approved_by, actor_office)
    VALUES (gen_random_uuid(), s.id, v_session, least(v_cgpa, 5), v_award, NULL, 'APPROVED', btrim(p_minute), now(), v_actor, v_office)
    ON CONFLICT (student_id, session) DO UPDATE
       SET cgpa = EXCLUDED.cgpa, award = EXCLUDED.award, unmet = NULL, senate_state = 'APPROVED', senate_minute = EXCLUDED.senate_minute,
           approved_at = coalesce(records.graduand.approved_at, EXCLUDED.approved_at), approved_by = coalesce(records.graduand.approved_by, EXCLUDED.approved_by)
    RETURNING id INTO v_g;

    -- V665: the status stays; the final clearance begins, and the Bursar's confirmation of it graduates the student
    IF s.status <> 'GRADUATED' THEN
        SELECT q.id INTO v_proc FROM clearance.process q WHERE q.workflow = 'FINAL' AND q.student_id = s.id AND q.cancelled_at IS NULL ORDER BY q.started_at DESC LIMIT 1;
        IF v_proc IS NULL THEN
            BEGIN
                v_proc := clearance.start('FINAL', s.id, v_session, 'ELIGIBLE', NULL, v_actor, v_office);
                v_clear := 'under way';
            EXCEPTION WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
                v_clear := 'to be started by the Registry';
            END;
        ELSE
            v_clear := 'under way';
        END IF;
        SELECT p.name, d.name AS dept_name, f.name AS faculty_name INTO pr
          FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code WHERE p.code = s.programme_code;
        SELECT * INTO reach FROM people.student_reach(s.id);
        PERFORM platform.notify('STUDENT_AWARD_APPROVED', NULL, jsonb_build_object(
                    'FIRST_NAME', coalesce(nullif(split_part(coalesce(s.other_names, ''), ' ', 1), ''), s.surname),
                    'AWARD', v_award, 'PROGRAMME', coalesce(pr.name, s.programme_code), 'DEPARTMENT', coalesce(pr.dept_name, ''), 'FACULTY', coalesce(pr.faculty_name, ''),
                    'MINUTE', btrim(p_minute), 'SESSION', v_session, 'MATRIC', coalesce(s.matric_no, ''), 'CLEARANCE', v_clear),
                'student', s.id, reach.email, reach.phone, 'award-approved:' || s.id || ':' || v_session);
    END IF;
    RETURN v_g;
END $$;
COMMENT ON FUNCTION admissions.pg_award(uuid, text, text) IS
  'V255, V665: Senate''s award of a postgraduate degree, recorded once on the research desk: the stage AWARDED, the graduand row approved on the minute, the final clearance started and the student told; the student becomes GRADUATED when the Bursar confirms the final clearance.';

-- ── 7 · what the Bursar's confirmation rests on, said before it is given ───────────────────────────────────────────────────
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
    SELECT * INTO c FROM people.lifecycle_completion_rows(ARRAY[q.student_id]);
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
  'V665: what the Bursar''s confirmation of a final clearance rests on, read afresh — whether it graduates the student (an approved award, the record not yet GRADUATED), the school-fee account (assessed, paid, waived, outstanding, the periods owing or unsettled), waivers pending, other payments in an owing session, the other offices still to clear, the academic record, and the blockers in words; ready when there are none';

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
    SELECT * INTO c FROM people.lifecycle_completion_rows(ARRAY[q.student_id]);
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
  'V665: the Bursar''s confirmation of a final clearance graduates a student whose award is approved — the academic record checked again, GRADUATED on the award''s minute with the clearance and the Bursar in the reason, the moment and the officer on the list entry and the batch row, the historical summary marked to be worked out again, the student told (STUDENT_GRADUATED); a graduated student or one with no approved award is left as they are';

-- ── 9 · an office's word on a stage (V415 restated): the Bursary's CLEARED on a final clearance that graduates ──────────────
CREATE OR REPLACE FUNCTION clearance.decide(p_process uuid, p_unit text, p_state text, p_item text, p_note text,
                                            p_internal text, p_override boolean, p_actor uuid, p_office text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE q record; r record; v_ev jsonb; v_block text; v_unit text := upper(btrim(p_unit)); v_state text := upper(btrim(p_state));
        v_item text := nullif(btrim(coalesce(p_item, '')), ''); v_overall text; v_before text; v_next text; v_subject text; v_body text;
        v_who text; v_label text; v_override boolean := coalesce(p_override, false); v_fc jsonb; v_graduate boolean := false; v_grad jsonb;
BEGIN
    SELECT p.*, w.purpose, w.label AS wf_label, w.complete_word, w.code AS wf FROM clearance.process p
      JOIN clearance.workflow w ON w.code = p.workflow WHERE p.id = p_process FOR UPDATE OF p INTO q;
    IF q.id IS NULL THEN RAISE EXCEPTION 'CLR_NO_PROCESS: no such clearance' USING ERRCODE = '23503'; END IF;
    IF q.cancelled_at IS NOT NULL THEN RAISE EXCEPTION 'CLR_CANCELLED: % was cancelled', q.reference USING ERRCODE = '23514'; END IF;
    IF v_state NOT IN ('CLEARED', 'UNDER_REVIEW', 'NOT_CLEARED', 'REQUIRES_ACTION', 'REJECTED', 'NOT_APPLICABLE') THEN
        RAISE EXCEPTION 'CLR_STATE: % is not a word a stage takes', p_state USING ERRCODE = '23514';
    END IF;
    IF v_state = 'NOT_APPLICABLE' AND NOT v_override THEN
        RAISE EXCEPTION 'CLR_OVERRIDE_ONLY: a stage is made not applicable only by an override, with a reason' USING ERRCODE = '23514';
    END IF;
    IF (v_state IN ('NOT_CLEARED', 'REQUIRES_ACTION', 'REJECTED') OR v_override) AND v_item IS NULL THEN
        RAISE EXCEPTION 'CLR_REASON: % needs a reason the student can act on', CASE WHEN v_override THEN 'an override' ELSE lower(replace(v_state, '_', ' ')) END
            USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM clearance.stage_rows(q.purpose, q.session, ARRAY[q.student_id]) x WHERE x.unit = v_unit;
    IF r.unit IS NULL THEN RAISE EXCEPTION 'CLR_NO_STAGE: % has no % stage', lower(q.wf_label), lower(v_unit) USING ERRCODE = '23514'; END IF;
    -- V665: the Bursary's own CLEARED (never an override) on a final clearance of a student whose award is approved graduates them
    IF q.wf = 'FINAL' AND v_unit = 'BURSARY' AND v_state = 'CLEARED' AND NOT v_override THEN
        v_fc := clearance.final_check(p_process);
        v_graduate := coalesce((v_fc->>'graduates')::boolean, false);
    END IF;
    IF q.completed_at IS NOT NULL AND NOT v_override AND NOT v_graduate THEN
        RAISE EXCEPTION 'CLR_COMPLETED: % is complete; a change now is an override', q.reference USING ERRCODE = '23514';
    END IF;
    IF NOT r.applies AND NOT v_override THEN
        RAISE EXCEPTION 'CLR_NOT_APPLICABLE: the % stage does not apply to this student', lower(r.label) USING ERRCODE = '23514';
    END IF;
    IF NOT r.opened AND r.applies AND NOT v_override THEN
        SELECT string_agg(x.label, ', ' ORDER BY x.ord) INTO v_before FROM clearance.stage_rows(q.purpose, q.session, ARRAY[q.student_id]) x
         WHERE x.ord < r.ord AND x.required AND x.applies AND x.state <> 'CLEARED';
        RAISE EXCEPTION 'CLR_STAGE_WAITING: % comes after %', r.label, coalesce(v_before, 'the earlier stages') USING ERRCODE = '23514';
    END IF;
    -- V665: that word is the Bursar's alone, the last once every other office has cleared, on an academic record that holds; a Registry
    -- override clears the stage as before and graduates nobody (the Bursar's own confirmation, afterwards, does)
    IF v_graduate THEN
        IF coalesce(p_office, '') <> 'bursar' THEN
            RAISE EXCEPTION 'CLR_BURSAR_ONLY: the Bursar confirms the final clearance that graduates the student' USING ERRCODE = '42501';
        END IF;
        IF jsonb_array_length(v_fc->'othersPending') > 0 THEN
            RAISE EXCEPTION 'CLR_BURSARY_LAST: the Bursary confirms the final clearance last; still to clear: %',
                (SELECT string_agg(o->>'label', ', ') FROM jsonb_array_elements(v_fc->'othersPending') o) USING ERRCODE = '23514';
        END IF;
        IF NOT (v_fc->'academic'->>'ok')::boolean THEN
            RAISE EXCEPTION 'GRAD_ACADEMIC: the award no longer holds on the record: %',
                coalesce(v_fc->'academic'->>'outstandingCourses', v_fc->'academic'->>'awaitingCourses', lower(v_fc->'academic'->>'completion')) USING ERRCODE = '23514';
        END IF;
    END IF;
    v_ev := clearance.evidence(p_process, v_unit);
    IF v_state = 'CLEARED' AND NOT v_override THEN
        v_block := clearance.blocker(p_process, v_unit, v_ev);
        IF v_block IS NOT NULL THEN
            RAISE EXCEPTION 'CLR_OUTSTANDING: %', v_block USING ERRCODE = '23514';
        END IF;
    END IF;
    INSERT INTO clearance.item (id, student_id, purpose, unit, state, item, officer_id, decided_at, note, process_id, internal_note,
                                override, previous_state, office, evidence)
    VALUES (gen_random_uuid(), q.student_id, q.purpose, v_unit, v_state, v_item, p_actor, clock_timestamp(),
            nullif(btrim(coalesce(p_note, '')), ''), q.id, nullif(btrim(coalesce(p_internal, '')), ''), v_override, r.state, p_office,
            CASE WHEN v_graduate THEN coalesce(v_ev, '{}'::jsonb) || jsonb_build_object('finalCheck', v_fc) ELSE v_ev END);

    v_overall := clearance.overall(q.id);
    IF v_overall = q.complete_word AND q.completed_at IS NULL THEN
        UPDATE clearance.process SET completed_at = clock_timestamp() WHERE id = q.id;
    ELSIF v_overall <> q.complete_word AND q.completed_at IS NOT NULL THEN
        UPDATE clearance.process SET completed_at = NULL WHERE id = q.id;   -- an override reopened it
    END IF;
    -- V665: the graduation, in the same transaction as the Bursar's word
    IF v_graduate THEN
        v_grad := records.graduate_on_final_clearance(q.id, p_actor, p_office, false);
    END IF;

    -- the student is told: cleared, not cleared, action required, rejected; never a medical detail
    IF v_state <> 'UNDER_REVIEW' THEN
        SELECT surname || ', ' || other_names INTO v_who FROM people.student WHERE id = q.student_id;
        v_label := r.label;
        SELECT string_agg(x.label, ', ' ORDER BY x.ord) INTO v_next FROM clearance.stage_rows(q.purpose, q.session, ARRAY[q.student_id]) x
         WHERE x.opened AND x.applies AND x.state IN ('PENDING') AND x.unit <> v_unit;
        v_subject := v_label || ' clearance: ' || CASE v_state WHEN 'CLEARED' THEN 'cleared' WHEN 'NOT_CLEARED' THEN 'not cleared'
                                                              WHEN 'REQUIRES_ACTION' THEN 'action required' WHEN 'REJECTED' THEN 'rejected'
                                                              ELSE 'not applicable' END || ' (' || q.reference || ')';
        v_body := 'Dear ' || coalesce(v_who, 'student') || ',' || E'\n\n'
               || CASE v_state
                    WHEN 'CLEARED' THEN 'The ' || v_label || ' has cleared you for your ' || lower(q.wf_label) || '.'
                    WHEN 'NOT_APPLICABLE' THEN 'The ' || v_label || ' stage of your ' || lower(q.wf_label) || ' no longer applies to you.'
                    ELSE 'The ' || v_label || ' has not cleared you for your ' || lower(q.wf_label) || '.'
                         || CASE WHEN v_unit = 'HEALTH' THEN ' Please see the Health Centre.'
                                 ELSE E'\n\n' || CASE v_state WHEN 'REQUIRES_ACTION' THEN 'What to do: ' WHEN 'REJECTED' THEN 'Reason: ' ELSE 'Outstanding: ' END || v_item END
                  END
               || CASE WHEN v_overall = q.complete_word THEN E'\n\n' || 'Every office has cleared you: your ' || lower(q.wf_label) || ' is ' || lower(q.complete_word) || '.'
                       WHEN v_next IS NOT NULL THEN E'\n\n' || 'Open now: ' || v_next || '.' ELSE '' END
               || CASE WHEN v_grad->>'outcome' = 'GRADUATED' THEN E'\n\n' || 'Your record now reads GRADUATED.' ELSE '' END
               || E'\n\n' || 'See My Clearance on the portal (reference ' || q.reference || ').' || E'\n\n' || clearance.signature();
        PERFORM clearance.tell(q.student_id, v_subject, v_body,
            'MOAUM: ' || v_label || ' clearance ' || CASE v_state WHEN 'CLEARED' THEN 'cleared' WHEN 'REQUIRES_ACTION' THEN 'needs your action'
                                                               WHEN 'REJECTED' THEN 'rejected' WHEN 'NOT_CLEARED' THEN 'not cleared' ELSE 'updated' END
            || CASE WHEN v_overall = q.complete_word THEN '; your ' || lower(q.wf_label) || ' is ' || lower(q.complete_word) ELSE '' END
            || '. See My Clearance on the portal.');
    END IF;
    RETURN v_overall;
END $$;
COMMENT ON FUNCTION clearance.decide(uuid, text, text, text, text, text, boolean, uuid, text) IS
  'V415, V665: an office''s word on a stage — refused when the clearance is cancelled or complete, the stage does not apply or is not yet open, or (for CLEARED) the record shows something outstanding; an override passes those checks with a reason and is kept as one, with the state it replaced. A reason is required for not cleared, action required and rejected. The evidence read is kept with the word; the process completes (or reopens) on the overall word; the student is told. Since V665 the Bursary''s own CLEARED (not an override) on a final clearance of a student whose award is approved is the Bursar''s alone, the last word (accepted on a clearance already complete), on an academic record that holds, and graduates the student in the same transaction (records.graduate_on_final_clearance).';

-- ── 9b · no reconciliation graduates a student whose award is approved: the Bursar's confirmation of the final clearance does (V331 restated) ──
CREATE OR REPLACE FUNCTION people.decide_cohort(p_student uuid, p_final_status text, p_reason text, p_batch text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        s people.student; pos people.academic_position; v uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a cohort decision is taken by a person' USING ERRCODE = '23514'; END IF;
    IF btrim(coalesce(p_reason, '')) = '' THEN RAISE EXCEPTION 'COHORT_REASON: a decision on a student''s standing says why' USING ERRCODE = '23514', HINT = 'Cite the evidence: the result, the minute, the letter.'; END IF;
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no student %', p_student USING ERRCODE = 'no_data_found'; END IF;
    IF p_final_status NOT IN ('ADMITTED','ACTIVE','PROBATION','DEFERRED','SUSPENDED','RUSTICATED','WITHDRAWN','EXPELLED','TRANSFERRED_OUT','GRADUATED','DECEASED','DORMANT','VOLUNTARY_WITHDRAWAL') THEN
        RAISE EXCEPTION 'COHORT_STATUS: % is not a student status', p_final_status USING ERRCODE = '23514';
    END IF;
    IF p_final_status = 'GRADUATED' AND NOT EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = p_student AND g.senate_state = 'APPROVED') THEN
        RAISE EXCEPTION 'COHORT_GRADUATION_SENATE: a student is graduated by the Senate''s approval of the award, not by a reconciliation' USING ERRCODE = '23514',
            HINT = 'Audit the graduation list for the session and approve the awards on the minute; the status follows.';
    END IF;
    -- V665: an approved award graduates at the Bursar's confirmation of the final clearance, never by a reconciliation
    IF p_final_status = 'GRADUATED' AND s.status <> 'GRADUATED' AND records.awaiting_final_clearance(p_student) THEN
        RAISE EXCEPTION 'COHORT_GRADUATION_CLEARANCE: the award is approved; the student is graduated when the Bursar confirms the final clearance' USING ERRCODE = '23514',
            HINT = 'Follow the student''s final clearance on the clearance desk; the Bursar''s clearance, last, graduates.';
    END IF;
    PERFORM people.refresh_academic_position(p_student);
    SELECT * INTO pos FROM people.academic_position WHERE student_id = p_student;
    IF p_final_status <> s.status THEN
        PERFORM people.change_status(p_student, p_final_status, 'Cohort reconciliation' || coalesce(' · ' || p_batch, ''), current_date, btrim(p_reason));
    END IF;
    INSERT INTO people.cohort_decision (student_id, previous_status, proposed_status, final_status, classification, previous_cohort, effective_cohort, previous_level, new_level, rule, reason, officer, actor_office, batch_ref)
    VALUES (p_student, s.status, pos.proposed_status, p_final_status, pos.classification, pos.entry_session, pos.effective_cohort, s.current_level, s.current_level, pos.rule, btrim(p_reason), who, office, nullif(btrim(coalesce(p_batch, '')), ''))
    RETURNING id INTO v;
    PERFORM people.refresh_academic_position(p_student);
    RETURN v;
END $$;
COMMENT ON FUNCTION people.decide_cohort(uuid, text, text, text) IS 'The Registry''s decision on one student''s standing (V331, V665): the status changed through people.change_status where it differs, the decision recorded with the proposal it answered. GRADUATED is refused without the Senate''s approved award, and refused for an approved award awaiting final clearance — the Bursar''s confirmation of it graduates (COHORT_GRADUATION_CLEARANCE).';

-- the Registry's bulk act on R1 leaves out every approved award awaiting final clearance: since V665 none is graduated by it
CREATE OR REPLACE FUNCTION people.apply_cohort_rule(p_rule text, p_reason text, p_batch text, p_dry_run boolean DEFAULT true)
RETURNS TABLE (considered int, applied int)
LANGUAGE plpgsql AS $$
DECLARE r record; n int := 0; k int := 0;
BEGIN
    IF p_rule <> 'R1' THEN
        RAISE EXCEPTION 'COHORT_RULE: only the Senate''s approved awards (R1) are applied in bulk; every other standing is decided one student at a time' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT ap.student_id FROM people.academic_position ap
              WHERE ap.rule = p_rule AND ap.confidence = 'VALIDATED' AND ap.proposed_status <> ap.existing_status
                AND NOT records.awaiting_final_clearance(ap.student_id)
              ORDER BY ap.student_id LOOP
        n := n + 1;
        IF NOT p_dry_run THEN
            PERFORM people.decide_cohort(r.student_id, 'GRADUATED', coalesce(nullif(btrim(p_reason), ''), 'Award approved by Senate; status reconciled'), p_batch);
            k := k + 1;
        END IF;
    END LOOP;
    RETURN QUERY SELECT n, k;
END $$;
COMMENT ON FUNCTION people.apply_cohort_rule(text, text, text, boolean) IS
  'V331, V665: the Registry applies the Senate''s approved awards (R1) in one act, or counts what it would do — leaving out every approved award awaiting final clearance (the Bursar''s confirmation of it graduates), so since V665 it graduates nobody';

-- ── 10 · a waiver or adjustment of a past period's school fees: proposed, approved by another officer, never "marked paid" ──────────
CREATE TABLE finance.historical_waiver (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference text NOT NULL UNIQUE CHECK (reference ~ '^HFW/[0-9]{4}/[0-9]{6}$'),
    student_id uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    session text NOT NULL REFERENCES policy.academic_session (name),
    semester integer NOT NULL CHECK (semester BETWEEN 1 AND 3),
    kind text NOT NULL CHECK (kind IN ('WAIVER', 'ADJUSTMENT')),
    amount numeric(14, 2) NOT NULL CHECK (amount > 0),
    reason text NOT NULL CHECK (length(btrim(reason)) >= 20),
    authority text NOT NULL CHECK (length(btrim(authority)) >= 3),
    state text NOT NULL DEFAULT 'PENDING_BURSAR_APPROVAL' CHECK (state IN ('PENDING_BURSAR_APPROVAL', 'APPROVED', 'REJECTED', 'WITHDRAWN', 'REVOKED')),
    created_by uuid NOT NULL,
    created_office text,
    created_at timestamptz NOT NULL DEFAULT now(),
    decided_by uuid,
    decided_office text,
    decided_at timestamptz,
    decision_note text,
    revoked_by uuid,
    revoked_at timestamptz,
    revoke_reason text,
    CONSTRAINT ck_hfw_two_officers CHECK (decided_by IS NULL OR state NOT IN ('APPROVED', 'REVOKED') OR decided_by <> created_by),
    CONSTRAINT ck_hfw_revoked CHECK ((state = 'REVOKED') = (revoked_at IS NOT NULL))
);
-- one proposal at a time for a student's session and semester
CREATE UNIQUE INDEX ux_hfw_pending ON finance.historical_waiver (student_id, session, semester) WHERE state = 'PENDING_BURSAR_APPROVAL';
CREATE INDEX ix_hfw_student ON finance.historical_waiver (student_id, session, semester) WHERE state = 'APPROVED';
CREATE INDEX ix_hfw_state ON finance.historical_waiver (state, created_at);
SELECT audit.attach('finance.historical_waiver');
COMMENT ON TABLE finance.historical_waiver IS
  'V665: an approved reduction of what a student owes for a past session''s semester — a WAIVER (the University forgoes it: a scholarship, a Council concession) or an ADJUSTMENT (the amount assessed was too high and the record is put right short of a new assessment) — with its reason and the authority it rests on. Proposed by the Students Account Officer or the Bursar, approved or rejected by another Bursar officer; an approved one is revoked with a reason, never edited. It reduces the period''s amount owed; it is never a payment.';

CREATE TABLE finance.historical_waiver_evidence (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    waiver_id uuid NOT NULL REFERENCES finance.historical_waiver (id) ON DELETE CASCADE,
    filename text NOT NULL,
    content_type text NOT NULL,
    size_bytes bigint NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 5242880),
    content bytea NULL,
    object_id uuid NULL REFERENCES platform.file_object (id),
    added_by uuid NOT NULL,
    added_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_hfw_evidence_where CHECK (num_nonnulls(content, object_id) = 1)
);
CREATE INDEX ix_hfw_evidence ON finance.historical_waiver_evidence (waiver_id);
COMMENT ON TABLE finance.historical_waiver_evidence IS 'V665: a file supporting a waiver or adjustment (the approval letter, the Council minute, the scholarship award) — in the file store where there is one, else here';
SELECT audit.exempt('finance.historical_waiver_evidence', 'V665: file bytes; who added which file and when is the row itself, and the waiver it supports is on the audit spine');

-- an approved waiver is kept as it was: only revoked, with a reason
CREATE OR REPLACE FUNCTION finance.trg_hfw_kept()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.state IN ('APPROVED', 'REJECTED', 'WITHDRAWN', 'REVOKED') AND current_setting('moaum.maintenance', true) IS DISTINCT FROM 'on' THEN
        IF NOT (OLD.state = 'APPROVED' AND NEW.state = 'REVOKED')
           OR (NEW.amount, NEW.session, NEW.semester, NEW.student_id, NEW.kind, NEW.reason, NEW.authority, NEW.created_by, NEW.decided_by)
              IS DISTINCT FROM (OLD.amount, OLD.session, OLD.semester, OLD.student_id, OLD.kind, OLD.reason, OLD.authority, OLD.created_by, OLD.decided_by) THEN
            RAISE EXCEPTION 'HFW_KEPT: % is % and is kept as it is', OLD.reference, lower(OLD.state) USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_hfw_kept BEFORE UPDATE ON finance.historical_waiver FOR EACH ROW EXECUTE FUNCTION finance.trg_hfw_kept();

-- ── 11 · the historical account, the approved waivers netted off (V654 restated; the read gains the column waived, last) ─────────
DROP FUNCTION finance.historical_account(uuid);
DROP FUNCTION finance.historical_rows(uuid[]);
DROP FUNCTION finance.historical_rows_read(uuid[]);

CREATE FUNCTION finance.historical_rows_read(p_students uuid[])
RETURNS TABLE(student_id uuid, session text, semester integer, level integer, programme_code text, assessed numeric, source text, source_ref text,
              assessment_id uuid, structure_amount numeric, structure_lines integer, pending_id uuid, pending_ref text, pending_amount numeric,
              paid numeric, outstanding numeric, credit numeric, status text, waived numeric)
LANGUAGE sql
STABLE
AS $$
    WITH home AS MATERIALIZED (SELECT lower(home_state) AS home_state FROM finance.fee_setting WHERE id = 1),
    bounds AS MATERIALIZED (SELECT finance.historical_start() AS start,
                                   (SELECT max(a.name) FROM policy.academic_session a
                                     WHERE a.state NOT IN ('CANCELLED', 'DRAFT') AND a.name < coalesce(policy.university_current_session(), '9999/9999')) AS before_current),
    -- the calendar's order, as people.level_in counts the sessions since admission (every session row, by its start)
    cal AS MATERIALIZED (SELECT a.name, a.state, a.semesters, row_number() OVER (ORDER BY a.starts_on, a.name) AS idx FROM policy.academic_session a),
    st AS MATERIALIZED (
        SELECT s.id, s.programme_code, p.faculty_code, p.category, s.entry_mode, s.entry_session, s.entry_level, s.current_level,
               people.is_postgraduate(s.entry_mode, p.category) AS pg,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) = (SELECT h.home_state FROM home h) AS indigene,
               greatest(s.entry_session, b.start) AS first_session,
               CASE WHEN s.status = 'GRADUATED' OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED')
                    THEN records.graduation_session(s.id) ELSE b.before_current END AS last_session
          FROM unnest(p_students) u(id)
          JOIN people.student s ON s.id = u.id
          JOIN ref.programme p ON p.code = s.programme_code
          CROSS JOIN bounds b
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.entry_session IS NOT NULL),
    -- the programme's final level read once a programme
    fl AS MATERIALIZED (SELECT d.programme_code, finance.final_level(d.programme_code) AS final_level FROM (SELECT DISTINCT st.programme_code FROM st) d),
    per0 AS MATERIALIZED (
        -- the sessions of the record, each semester of each, a deferred session or semester left out
        SELECT st.*, fl.final_level, a.name AS session, sm.n AS semester, a.idx AS ses_idx
          FROM st
          JOIN fl ON fl.programme_code = st.programme_code
          JOIN cal a ON a.name >= st.first_session AND a.name <= st.last_session AND a.state NOT IN ('CANCELLED', 'DRAFT')
          CROSS JOIN LATERAL generate_series(1, a.semesters) sm(n)
         WHERE st.last_session IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM people.deferment d
                            WHERE d.student_id = st.id AND d.session = a.name AND d.state IN ('APPROVED', 'ACTIVE', 'COMPLETED')
                              AND (d.kind = 'SESSION' OR d.semester = sm.n))),
    -- the level of each period, read as people.level_in reads it — the semester's registration, else the session's, else the
    -- enrolment, else counted from admission (a postgraduate's own level) — for every student at once
    reg AS MATERIALIZED (SELECT r.student_id, r.session, r.semester, r.level, r.status IN ('APPROVED', 'LOCKED') AS ok
                           FROM registration.course_registration r WHERE r.student_id = ANY (p_students)),
    reg_sem AS (SELECT DISTINCT ON (g.student_id, g.session, g.semester) g.student_id, g.session, g.semester, g.level FROM reg g
                 ORDER BY g.student_id, g.session, g.semester, g.ok DESC),
    reg_ses AS (SELECT DISTINCT ON (g.student_id, g.session) g.student_id, g.session, g.level FROM reg g ORDER BY g.student_id, g.session, g.ok DESC, g.semester),
    enr AS (SELECT DISTINCT ON (e.student_id, e.session) e.student_id, e.session, e.level FROM people.enrolment e WHERE e.student_id = ANY (p_students)
             ORDER BY e.student_id, e.session),
    per AS MATERIALIZED (
        SELECT p0.*, coalesce(rs.level, rx.level, en.level,
                              CASE WHEN p0.pg THEN p0.current_level
                                   WHEN es.idx IS NOT NULL AND p0.ses_idx >= es.idx THEN least(600, p0.entry_level + 100 * (p0.ses_idx - es.idx)::int) END,
                              p0.current_level) AS level
          FROM per0 p0
          LEFT JOIN cal es ON es.name = p0.entry_session
          LEFT JOIN reg_sem rs ON rs.student_id = p0.id AND rs.session = p0.session AND rs.semester = p0.semester
          LEFT JOIN reg_ses rx ON rx.student_id = p0.id AND rx.session = p0.session
          LEFT JOIN enr en ON en.student_id = p0.id AND en.session = p0.session),
    ses AS MATERIALIZED (
        -- one profile a session: the student as they were in its first semester on the record
        SELECT DISTINCT ON (pe.id, pe.session) pe.* FROM per pe ORDER BY pe.id, pe.session, pe.semester),
    -- the faculty a faculty is charged as, read once a faculty and session; a PG student's stage read once a session
    src AS MATERIALIZED (SELECT d.faculty_code, d.session, finance.fee_source_of(d.faculty_code, d.session) AS src
                           FROM (SELECT DISTINCT x.faculty_code, x.session FROM ses x WHERE x.entry_mode IS DISTINCT FROM 'CCE' AND NOT x.pg) d),
    pgs AS MATERIALIZED (SELECT y.student_id, d.session, y.stage_code, y.category
                           FROM (SELECT x.session, array_agg(x.id) AS ids FROM ses x WHERE x.pg GROUP BY x.session) d
                           CROSS JOIN LATERAL admissions.pg_stages_of(d.session, d.ids) y),
    prof AS MATERIALIZED (
        -- the student as they were in the session: spillover read from its level against the programme's final level
        SELECT pe.*, coalesce(pe.level > pe.final_level, false) AS is_spill,
               CASE WHEN pe.level > pe.final_level THEN least((pe.level - pe.final_level) / 100, 3) END AS spill_year,
               CASE WHEN pe.level > pe.final_level THEN finance.reg_semesters(pe.id, pe.session) END AS reg_sems,   -- V616: read for a spillover student only
               sr.src, pg.stage_code AS pg_stage, pg.category AS pg_category
          FROM ses pe
          LEFT JOIN src sr ON sr.faculty_code = pe.faculty_code AND sr.session = pe.session AND pe.entry_mode IS DISTINCT FROM 'CCE' AND NOT pe.pg
          LEFT JOIN pgs pg ON pg.student_id = pe.id AND pg.session = pe.session),
    matched AS (
        -- the session's fee lines that reach the student as they were; a whole-session line is due with the first semester
        SELECT pr.id AS student_id, pr.session, coalesce(f.semester, 1) AS semester, f.amount
          FROM prof pr
          JOIN finance.fee_schedule f ON f.session = pr.session AND f.ended_at IS NULL AND f.kind = 'FEE'
          LEFT JOIN ref.fee_group g ON g.code = f.fee_group
         WHERE f.spillover = pr.is_spill
           AND (f.level IS NULL OR f.level = CASE WHEN pr.is_spill THEN pr.final_level ELSE pr.level END)
           AND (f.spill_year IS NULL OR f.spill_year = pr.spill_year)
           AND finance.spill_line_applies(pr.is_spill, f.semester, pr.reg_sems)
           AND ((f.entry_mode IS NULL AND pr.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = pr.entry_mode)
           AND (f.faculty_code IS NULL OR f.faculty_code = pr.faculty_code OR (f.faculty_code = pr.src AND f.programme_code IS NULL))
           AND (f.programme_code IS NULL OR f.programme_code = pr.programme_code)
           AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = pr.category)
           AND finance.pg_line(pr.entry_mode = 'POSTGRADUATE' OR pr.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)
           AND finance.pg_stage_line(f.pg_stage, f.fee_category, pr.pg_stage, pr.pg_category)
           AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = pr.indigene)),
    struct AS (SELECT m.student_id, m.session, m.semester, sum(m.amount) AS amount, count(*)::int AS lines FROM matched m GROUP BY 1, 2, 3),
    stated AS (SELECT DISTINCT m.student_id, m.session FROM matched m),
    apr AS (SELECT a.id, a.reference, a.student_id, a.session, a.semester, a.amount FROM finance.historical_assessment a
             WHERE a.student_id = ANY (p_students) AND a.state = 'APPROVED'),
    pend AS (SELECT a.id, a.reference, a.student_id, a.session, a.semester, a.amount FROM finance.historical_assessment a
              WHERE a.student_id = ANY (p_students) AND a.state IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION', 'DRAFT')),
    -- V665: the approved waivers and adjustments of each period
    wv AS (SELECT w.student_id, w.session, w.semester, sum(w.amount) AS waived FROM finance.historical_waiver w
            WHERE w.student_id = ANY (p_students) AND w.state = 'APPROVED' GROUP BY 1, 2, 3),
    pay AS (SELECT r.student_id, r.session, sum(r.amount) AS paid FROM finance.payment_reference r
             WHERE r.student_id = ANY (p_students) AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
             GROUP BY 1, 2),
    base0 AS (
        SELECT pr.id AS student_id, pr.session, pr.semester, pr.level, pr.programme_code,
               coalesce(ap.amount, CASE WHEN sd.session IS NOT NULL THEN coalesce(sr.amount, 0) END) AS assessed,
               CASE WHEN ap.id IS NOT NULL THEN 'ASSESSMENT' WHEN sd.session IS NOT NULL THEN 'STRUCTURE' ELSE 'NONE' END AS source,
               CASE WHEN ap.id IS NOT NULL THEN ap.reference
                    WHEN sd.session IS NOT NULL THEN pr.session || ' fee structure' || CASE WHEN sr.lines IS NULL THEN ' (nothing due this semester)'
                                                                                          ELSE ' (' || sr.lines || CASE WHEN sr.lines = 1 THEN ' line)' ELSE ' lines)' END END END AS source_ref,
               ap.id AS assessment_id, sr.amount AS structure_amount, coalesce(sr.lines, 0) AS structure_lines,
               pn.id AS pending_id, pn.reference AS pending_ref, pn.amount AS pending_amount,
               coalesce(py.paid, 0) AS session_paid, coalesce(w.waived, 0) AS waived
          FROM per pr
          LEFT JOIN struct sr ON sr.student_id = pr.id AND sr.session = pr.session AND sr.semester = pr.semester
          LEFT JOIN stated sd ON sd.student_id = pr.id AND sd.session = pr.session
          LEFT JOIN apr ap ON ap.student_id = pr.id AND ap.session = pr.session AND ap.semester = pr.semester
          LEFT JOIN pend pn ON pn.student_id = pr.id AND pn.session = pr.session AND pn.semester = pr.semester
          LEFT JOIN pay py ON py.student_id = pr.id AND py.session = pr.session
          LEFT JOIN wv w ON w.student_id = pr.id AND w.session = pr.session AND w.semester = pr.semester),
    -- what the period is owed on: the amount assessed less the approved waivers (never below nothing)
    base AS (SELECT b0.*, CASE WHEN b0.assessed IS NULL THEN NULL ELSE greatest(b0.assessed - b0.waived, 0) END AS net FROM base0 b0),
    alloc AS (
        -- the session's payments fill the assessed semesters in order (each on what it is owed on); what is left goes to the first
        -- semester not yet assessed, else stands as a credit on the session's last semester
        SELECT b.*,
               coalesce(sum(b.net) OVER (PARTITION BY b.student_id, b.session ORDER BY b.semester ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS before_me,
               coalesce(sum(b.net) OVER (PARTITION BY b.student_id, b.session), 0) AS session_assessed,
               min(b.semester) FILTER (WHERE b.assessed IS NULL) OVER (PARTITION BY b.student_id, b.session) AS first_unassessed,
               max(b.semester) OVER (PARTITION BY b.student_id, b.session) AS last_semester
          FROM base b),
    fin AS (
        SELECT a.*,
               CASE WHEN a.net IS NOT NULL THEN least(greatest(a.session_paid - a.before_me, 0), a.net)
                    WHEN a.semester = a.first_unassessed THEN greatest(a.session_paid - a.session_assessed, 0)
                    ELSE 0 END AS paid_here,
               CASE WHEN a.first_unassessed IS NULL AND a.semester = a.last_semester THEN greatest(a.session_paid - a.session_assessed, 0) ELSE 0 END AS credit_here
          FROM alloc a)
    SELECT f.student_id, f.session, f.semester, f.level, f.programme_code, f.assessed, f.source, f.source_ref, f.assessment_id,
           f.structure_amount, f.structure_lines, f.pending_id, f.pending_ref, f.pending_amount,
           f.paid_here + f.credit_here AS paid,
           CASE WHEN f.net IS NULL THEN NULL ELSE finance.fee_owed(f.net, f.paid_here) END AS outstanding,
           f.credit_here AS credit,
           CASE WHEN f.net IS NULL THEN CASE WHEN f.pending_id IS NOT NULL THEN 'PENDING_APPROVAL' ELSE 'REQUIRES_REVIEW' END
                WHEN f.credit_here >= 1 THEN 'CREDIT'
                WHEN finance.fee_owed(f.net, f.paid_here) = 0 THEN 'CLEARED'
                WHEN f.paid_here > 0 THEN 'PARTIALLY_PAID'
                ELSE 'OUTSTANDING' END AS status,
           f.waived
      FROM fin f
$$;

-- the one entry: PL/pgSQL on purpose, so a caller's query never folds the read into its own plan
CREATE FUNCTION finance.historical_rows(p_students uuid[])
RETURNS TABLE(student_id uuid, session text, semester integer, level integer, programme_code text, assessed numeric, source text, source_ref text,
              assessment_id uuid, structure_amount numeric, structure_lines integer, pending_id uuid, pending_ref text, pending_amount numeric,
              paid numeric, outstanding numeric, credit numeric, status text, waived numeric)
LANGUAGE plpgsql
STABLE
ROWS 1000
AS $$
BEGIN
    RETURN QUERY SELECT * FROM finance.historical_rows_read(p_students) x ORDER BY x.student_id, x.session, x.semester;
END $$;
COMMENT ON FUNCTION finance.historical_rows(uuid[]) IS
  'V654, V665: the historical account of the students given — each session and semester from the start (finance.historical_start, or admission) to the graduation session (the session before the current one for a student still studying), a deferred period left out: the level of the period, the amount assessed (an approved assessment, else the session''s fee lines matched to the student as they were then, else nothing: REQUIRES_REVIEW or PENDING_APPROVAL), the approved waivers and adjustments (waived) netted off it, the confirmed school-fee payments of the session allocated first semester first, the outstanding and any credit.';

CREATE FUNCTION finance.historical_account(p_student uuid)
RETURNS TABLE(session text, semester integer, level integer, programme_code text, assessed numeric, source text, source_ref text, assessment_id uuid,
              structure_amount numeric, structure_lines integer, pending_id uuid, pending_ref text, pending_amount numeric,
              paid numeric, outstanding numeric, credit numeric, status text, waived numeric)
LANGUAGE sql
STABLE
AS $$
    SELECT x.session, x.semester, x.level, x.programme_code, x.assessed, x.source, x.source_ref, x.assessment_id, x.structure_amount, x.structure_lines,
           x.pending_id, x.pending_ref, x.pending_amount, x.paid, x.outstanding, x.credit, x.status, x.waived
      FROM finance.historical_rows(ARRAY[p_student]) x
$$;
COMMENT ON FUNCTION finance.historical_account(uuid) IS 'V654, V665: one student''s historical account (finance.historical_rows), the waivers netted off';

-- the summary carries the waived total
ALTER TABLE finance.historical_summary ADD COLUMN waived numeric(14, 2) NOT NULL DEFAULT 0;
COMMENT ON COLUMN finance.historical_summary.waived IS 'V665: the approved waivers and adjustments across the record';

CREATE OR REPLACE FUNCTION finance.historical_refresh(p_students uuid[] DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE v_ids uuid[]; n int;
BEGIN
    v_ids := coalesce(p_students, (SELECT array_agg(s.id) FROM people.student s
                                    WHERE s.status = 'GRADUATED'
                                       OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED')));
    IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
        IF p_students IS NULL THEN UPDATE finance.historical_setting SET refreshed_at = now() WHERE id = 1; END IF;
        RETURN 0;
    END IF;
    WITH hr AS (SELECT * FROM finance.historical_rows(v_ids)),
    agg AS (
        SELECT r.student_id, min(r.session) AS first_session, max(r.session) AS last_session, count(*)::int AS periods,
               coalesce(sum(r.assessed), 0) AS assessed, coalesce(sum(r.paid), 0) AS paid, coalesce(sum(r.outstanding), 0) AS outstanding,
               coalesce(sum(r.credit), 0) AS credit, coalesce(sum(r.waived), 0) AS waived,
               count(*) FILTER (WHERE r.outstanding > 0)::int AS owing_periods,
               count(*) FILTER (WHERE r.status = 'REQUIRES_REVIEW')::int AS review_periods,
               count(*) FILTER (WHERE r.status = 'PENDING_APPROVAL')::int AS pending_periods,
               count(*) FILTER (WHERE r.status = 'PARTIALLY_PAID')::int AS partial_periods,
               string_agg(r.session || ' S' || r.semester, ', ' ORDER BY r.session, r.semester) FILTER (WHERE r.outstanding > 0) AS owing
          FROM hr r GROUP BY r.student_id),
    ids AS (SELECT DISTINCT unnest(v_ids) AS student_id),
    up AS (
        INSERT INTO finance.historical_summary AS h (student_id, first_session, last_session, periods, assessed, paid, outstanding, credit, owing_periods,
                                                     review_periods, pending_periods, partial_periods, owing, financial_status, last_payment_at, refreshed_at, waived)
        SELECT i.student_id, a.first_session, a.last_session, coalesce(a.periods, 0), coalesce(a.assessed, 0), coalesce(a.paid, 0), coalesce(a.outstanding, 0),
               coalesce(a.credit, 0), coalesce(a.owing_periods, 0), coalesce(a.review_periods, 0), coalesce(a.pending_periods, 0), coalesce(a.partial_periods, 0), a.owing,
               CASE WHEN coalesce(a.periods, 0) = 0 THEN 'NO_HISTORICAL_PERIOD'
                    WHEN a.review_periods > 0 THEN 'HISTORICAL_FEE_REVIEW_REQUIRED'
                    WHEN a.pending_periods > 0 THEN 'FINANCIAL_CLEARANCE_PENDING'
                    WHEN a.outstanding > 0 THEN 'FINANCIAL_OBLIGATION'
                    ELSE 'FINANCIALLY_CLEARED' END,
               (SELECT max(r.confirmed_at) FROM finance.payment_reference r WHERE r.student_id = i.student_id AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'),
               now(), coalesce(a.waived, 0)
          FROM ids i LEFT JOIN agg a ON a.student_id = i.student_id
        ON CONFLICT (student_id) DO UPDATE SET first_session = EXCLUDED.first_session, last_session = EXCLUDED.last_session, periods = EXCLUDED.periods,
            assessed = EXCLUDED.assessed, paid = EXCLUDED.paid, outstanding = EXCLUDED.outstanding, credit = EXCLUDED.credit,
            owing_periods = EXCLUDED.owing_periods, review_periods = EXCLUDED.review_periods, pending_periods = EXCLUDED.pending_periods,
            partial_periods = EXCLUDED.partial_periods, owing = EXCLUDED.owing, financial_status = EXCLUDED.financial_status,
            last_payment_at = EXCLUDED.last_payment_at, refreshed_at = EXCLUDED.refreshed_at, waived = EXCLUDED.waived
        RETURNING 1)
    SELECT count(*) INTO n FROM up;
    DELETE FROM finance.historical_stale x WHERE x.student_id = ANY (v_ids);
    IF p_students IS NULL THEN UPDATE finance.historical_setting SET refreshed_at = now() WHERE id = 1; END IF;
    RETURN n;
END $$;
COMMENT ON FUNCTION finance.historical_refresh(uuid[]) IS
  'V654, V665: works out the historical summary of the students given (NULL: every graduate and graduand) from finance.historical_rows — the waived total with the rest — and takes them off the stale list.';

-- ── 12 · a waiver proposed, decided, withdrawn, revoked ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.historical_waiver_propose(p_student uuid, p_session text, p_semester integer, p_kind text, p_amount numeric,
                                                             p_reason text, p_authority text)
RETURNS finance.historical_waiver
LANGUAGE plpgsql
AS $$
DECLARE per record; w finance.historical_waiver; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_kind text := upper(btrim(coalesce(p_kind, '')));
        v_year text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY');
BEGIN
    PERFORM finance.historical_require('CREATE_HISTORICAL_FEE_ASSESSMENT');
    IF v_actor IS NULL THEN RAISE EXCEPTION 'HFW_ACTOR: a waiver is proposed by a named officer' USING ERRCODE = '42501'; END IF;
    IF v_kind NOT IN ('WAIVER', 'ADJUSTMENT') THEN
        RAISE EXCEPTION 'HFW_KIND: a reduction is a waiver or an adjustment' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 20 THEN
        RAISE EXCEPTION 'HFW_REASON: say why, in twenty characters at least' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_authority, ''))) < 3 THEN
        RAISE EXCEPTION 'HFW_AUTHORITY: name the approval it rests on (the letter, the minute, the award)' USING ERRCODE = '23514';
    END IF;
    PERFORM 1 FROM people.student s WHERE s.id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'HFW_NO_STUDENT: no such student' USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO per FROM finance.historical_account(p_student) x WHERE x.session = p_session AND x.semester = p_semester;
    IF per.session IS NULL THEN
        RAISE EXCEPTION 'HFW_PERIOD: % % is not a period of the student''s record', p_session, lower(finance.semester_words(p_semester)) USING ERRCODE = '23514';
    END IF;
    IF per.assessed IS NULL THEN
        RAISE EXCEPTION 'HFW_NOT_ASSESSED: % % has no amount yet — it is assessed first', p_session, lower(finance.semester_words(p_semester)) USING ERRCODE = '23514';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount > coalesce(per.outstanding, 0) THEN
        RAISE EXCEPTION 'HFW_AMOUNT: a waiver is more than nothing and at most what the period still owes (%)', clearance.naira(coalesce(per.outstanding, 0))
            USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM finance.historical_waiver x WHERE x.student_id = p_student AND x.session = p_session AND x.semester = p_semester
                AND x.state = 'PENDING_BURSAR_APPROVAL') THEN
        RAISE EXCEPTION 'HFW_PENDING: a waiver of % % already awaits the Bursar', p_session, lower(finance.semester_words(p_semester)) USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.historical_waiver (reference, student_id, session, semester, kind, amount, reason, authority, created_by, created_office)
    VALUES ('HFW/' || v_year || '/' || lpad(platform.next_number('HISTORICAL_FEE_WAIVER', 'finance', v_year)::text, 6, '0'),
            p_student, p_session, p_semester, v_kind, round(p_amount, 2), btrim(p_reason), btrim(p_authority), v_actor, v_office)
    RETURNING * INTO w;
    RETURN w;
END $$;
COMMENT ON FUNCTION finance.historical_waiver_propose(uuid, text, integer, text, numeric, text, text) IS
  'V665: a waiver or adjustment of a past period proposed — by an office holding CREATE_HISTORICAL_FEE_ASSESSMENT, on an assessed period of the record, for more than nothing and no more than it still owes, with a reason (twenty characters at least) and the authority it rests on; one awaiting the Bursar at a time a period';

CREATE OR REPLACE FUNCTION finance.historical_waiver_decide(p_id uuid, p_decision text, p_note text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE w finance.historical_waiver; per record; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_dec text := upper(btrim(coalesce(p_decision, ''))); v_owed numeric;
BEGIN
    IF v_dec NOT IN ('APPROVE', 'REJECT') THEN
        RAISE EXCEPTION 'HFW_DECISION: a waiver is approved or rejected' USING ERRCODE = '23514';
    END IF;
    PERFORM finance.historical_require(CASE v_dec WHEN 'APPROVE' THEN 'APPROVE_HISTORICAL_FEE_ASSESSMENT' ELSE 'REJECT_HISTORICAL_FEE_ASSESSMENT' END);
    SELECT * INTO w FROM finance.historical_waiver x WHERE x.id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'HFW_NOT_FOUND: no such waiver' USING ERRCODE = 'P0002'; END IF;
    IF w.state <> 'PENDING_BURSAR_APPROVAL' THEN
        RAISE EXCEPTION 'HFW_NOT_PENDING: % is % — only a waiver awaiting the Bursar is decided', w.reference, lower(replace(w.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF v_actor IS NULL OR v_actor = w.created_by THEN
        RAISE EXCEPTION 'HFW_SAME_OFFICER: a waiver is decided by an officer other than the one who proposed it' USING ERRCODE = '23514';
    END IF;
    IF v_dec = 'REJECT' AND length(btrim(coalesce(p_note, ''))) < 10 THEN
        RAISE EXCEPTION 'HFW_NOTE: say why, in ten characters at least' USING ERRCODE = '23514';
    END IF;
    PERFORM 1 FROM people.student s WHERE s.id = w.student_id FOR UPDATE;
    IF v_dec = 'APPROVE' THEN
        -- read afresh: a payment since the proposal may have left less to waive
        SELECT * INTO per FROM finance.historical_account(w.student_id) x WHERE x.session = w.session AND x.semester = w.semester;
        IF per.outstanding IS NULL OR w.amount > per.outstanding THEN
            RAISE EXCEPTION 'HFW_AMOUNT: % waives %, more than the period now owes (%) — reject it and propose it again',
                w.reference, clearance.naira(w.amount), clearance.naira(coalesce(per.outstanding, 0)) USING ERRCODE = '23514';
        END IF;
        UPDATE finance.historical_waiver x SET state = 'APPROVED', decided_by = v_actor, decided_office = v_office, decided_at = now(),
               decision_note = nullif(btrim(coalesce(p_note, '')), '')
         WHERE x.id = p_id;
    ELSE
        UPDATE finance.historical_waiver x SET state = 'REJECTED', decided_by = v_actor, decided_office = v_office, decided_at = now(), decision_note = btrim(p_note)
         WHERE x.id = p_id;
    END IF;
    PERFORM finance.historical_refresh(ARRAY[w.student_id]);
    IF v_dec = 'APPROVE' THEN
        SELECT x.outstanding INTO v_owed FROM finance.historical_account(w.student_id) x WHERE x.session = w.session AND x.semester = w.semester;
        PERFORM platform.tell_student(w.student_id, 'HISTORICAL_FEES_ADJUSTED', NULL,
            jsonb_build_object('SESSION', w.session, 'SEMESTER', finance.semester_words(w.semester), 'AMOUNT', 'NGN ' || to_char(w.amount, 'FM999,999,999,990.00'),
                               'KIND', lower(w.kind), 'REFERENCE', w.reference,
                               'OUTSTANDING', CASE WHEN coalesce(v_owed, 0) > 0 THEN 'NGN ' || to_char(v_owed, 'FM999,999,999,990.00') || ' outstanding' ELSE 'nothing outstanding' END),
            'HISTORICAL_FEES_ADJUSTED:' || w.id);
    END IF;
    RETURN CASE v_dec WHEN 'APPROVE' THEN 'APPROVED' ELSE 'REJECTED' END;
END $$;
COMMENT ON FUNCTION finance.historical_waiver_decide(uuid, text, text) IS
  'V665: a waiver awaiting the Bursar approved (no more than the period owes when it is approved; the account and summary worked out again; the student told) or rejected with a reason — never by the officer who proposed it';

CREATE OR REPLACE FUNCTION finance.historical_waiver_withdraw(p_id uuid, p_note text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE w finance.historical_waiver; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO w FROM finance.historical_waiver x WHERE x.id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'HFW_NOT_FOUND: no such waiver' USING ERRCODE = 'P0002'; END IF;
    IF NOT (w.created_by = v_actor OR finance.historical_may(nullif(current_setting('moaum.actor_office', true), ''), 'APPROVE_HISTORICAL_FEE_ASSESSMENT')) THEN
        RAISE EXCEPTION 'HFW_NOT_PERMITTED: a waiver is withdrawn by the officer who proposed it or the Bursar' USING ERRCODE = '42501';
    END IF;
    IF w.state <> 'PENDING_BURSAR_APPROVAL' THEN
        RAISE EXCEPTION 'HFW_NOT_PENDING: % is % and is kept', w.reference, lower(replace(w.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    UPDATE finance.historical_waiver x SET state = 'WITHDRAWN', decision_note = nullif(btrim(coalesce(p_note, '')), ''), decided_at = now(),
           decided_office = nullif(current_setting('moaum.actor_office', true), '')
     WHERE x.id = p_id;
    RETURN 'WITHDRAWN';
END $$;
COMMENT ON FUNCTION finance.historical_waiver_withdraw(uuid, text) IS 'V665: a waiver awaiting the Bursar withdrawn by the officer who proposed it or the Bursar';

CREATE OR REPLACE FUNCTION finance.historical_waiver_revoke(p_id uuid, p_reason text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE w finance.historical_waiver; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    PERFORM finance.historical_require('APPROVE_HISTORICAL_FEE_ASSESSMENT');
    SELECT * INTO w FROM finance.historical_waiver x WHERE x.id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'HFW_NOT_FOUND: no such waiver' USING ERRCODE = 'P0002'; END IF;
    IF w.state <> 'APPROVED' THEN
        RAISE EXCEPTION 'HFW_NOT_APPROVED: % is % — only an approved waiver is revoked', w.reference, lower(replace(w.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF v_actor IS NULL THEN RAISE EXCEPTION 'HFW_ACTOR: a waiver is revoked by a named officer' USING ERRCODE = '42501'; END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 20 THEN
        RAISE EXCEPTION 'HFW_REASON: say why, in twenty characters at least' USING ERRCODE = '23514';
    END IF;
    UPDATE finance.historical_waiver x SET state = 'REVOKED', revoked_by = v_actor, revoked_at = now(), revoke_reason = btrim(p_reason) WHERE x.id = p_id;
    PERFORM finance.historical_refresh(ARRAY[w.student_id]);
    RETURN 'REVOKED';
END $$;
COMMENT ON FUNCTION finance.historical_waiver_revoke(uuid, text) IS
  'V665: an approved waiver revoked by the Bursar''s office with a reason — the amount owed again, the account worked out again (a graduated student stays graduated)';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('HISTORICAL_FEES_ADJUSTED', 'Historical school fees reduced',
 'To a student once the Bursar approves a waiver or adjustment of a past session''s school fees',
 'Your school fees for [SESSION] [SEMESTER] are reduced',
 E'Dear [FIRST_NAME],\n\nThe Bursary has approved a [KIND] of [AMOUNT] on your school fees for [SESSION], [SEMESTER] (reference [REFERENCE]). On your account this period now shows [OUTSTANDING]. Your historical school fees are on your portal: [PORTAL_URL]\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: a [KIND] of [AMOUNT] on your [SESSION] [SEMESTER] school fees is approved ([REFERENCE]); [OUTSTANDING]. See your portal.',
 'School fees reduced for [SESSION]',
 'The Bursary has approved a [KIND] of [AMOUNT] on your school fees for [SESSION], [SEMESTER] (reference [REFERENCE]): [OUTSTANDING].',
 ARRAY['FIRST_NAME','SESSION','SEMESTER','AMOUNT','KIND','REFERENCE','OUTSTANDING','PORTAL_URL','UNIVERSITY_SHORT'], true, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

-- ── 13 · the Bursary stage's evidence carries the waivers (V654 restated, the FINAL Bursary branch with waived per period and in total) ──
CREATE OR REPLACE FUNCTION clearance.evidence(p_process uuid, p_unit text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE q record; v jsonb := '{}'::jsonb;
BEGIN
    SELECT p.*, w.purpose, w.code AS wf FROM clearance.process p JOIN clearance.workflow w ON w.code = p.workflow
     WHERE p.id = p_process INTO q;
    IF q.id IS NULL THEN RETURN NULL; END IF;
    CASE upper(p_unit)
    WHEN 'BURSARY' THEN
        IF q.wf = 'FINAL' THEN
            -- V654: the historical account — each session and semester assessed as the student was then (an approved assessment, else
            -- the session's fee lines at the session's level), the verified payments allocated, a period with no amount named for review;
            -- V665: the approved waivers netted off
            SELECT jsonb_build_object(
                     'historical', true, 'start', finance.historical_start(),
                     'periods', coalesce(jsonb_agg(jsonb_build_object('session', x.session, 'semester', x.semester, 'level', x.level, 'assessed', x.assessed,
                                                                      'paid', x.paid, 'outstanding', x.outstanding, 'credit', x.credit, 'status', x.status,
                                                                      'source', x.source_ref, 'pending', x.pending_ref, 'waived', x.waived) ORDER BY x.session, x.semester), '[]'::jsonb),
                     'assessed', coalesce(sum(x.assessed), 0),
                     'paid', coalesce(sum(x.paid), 0),
                     'waived', coalesce(sum(x.waived), 0),
                     'outstanding', coalesce(sum(x.outstanding), 0),
                     'credit', coalesce(sum(x.credit), 0),
                     'review', count(*) FILTER (WHERE x.status = 'REQUIRES_REVIEW'),
                     'pending', count(*) FILTER (WHERE x.status = 'PENDING_APPROVAL'),
                     'owingPeriods', string_agg(x.session || ' ' || finance.semester_words(x.semester), ', ' ORDER BY x.session, x.semester) FILTER (WHERE x.outstanding > 0),
                     'reviewPeriods', string_agg(x.session || ' ' || finance.semester_words(x.semester), ', ' ORDER BY x.session, x.semester) FILTER (WHERE x.status = 'REQUIRES_REVIEW'),
                     'pendingPeriods', string_agg(x.session || ' ' || finance.semester_words(x.semester), ', ' ORDER BY x.session, x.semester) FILTER (WHERE x.status = 'PENDING_APPROVAL'))
              INTO v
              FROM finance.historical_rows(ARRAY[q.student_id]) x;
        ELSE
            SELECT jsonb_build_object('session', q.session, 'stated', finance.fee_stated(q.student_id, q.session),
                                      'due', pos.due, 'paid', pos.paid, 'balance', pos.balance,
                                      'outstanding', CASE WHEN finance.fee_stated(q.student_id, q.session) THEN greatest(pos.balance, 0) ELSE NULL END)
              INTO v FROM finance.position(q.student_id, q.session) pos;
        END IF;
    WHEN 'LIBRARY' THEN
        SELECT jsonb_build_object(
                 'openLoans', count(*) FILTER (WHERE l.returned_at IS NULL),
                 'loans', coalesce(jsonb_agg(jsonb_build_object('accession', l.accession, 'title', i.title, 'dueOn', l.due_on) ORDER BY l.due_on)
                                   FILTER (WHERE l.returned_at IS NULL), '[]'::jsonb),
                 'unpaidFines', count(*) FILTER (WHERE coalesce(l.fine, 0) > 0 AND l.fine_settled_at IS NULL AND l.fine_waived_at IS NULL),
                 'fines', coalesce(sum(l.fine) FILTER (WHERE coalesce(l.fine, 0) > 0 AND l.fine_settled_at IS NULL AND l.fine_waived_at IS NULL), 0))
          INTO v
          FROM library.loan l
          LEFT JOIN library.copy c ON c.accession = l.accession
          LEFT JOIN library.item i ON i.id = c.item_id
         WHERE l.student_id = q.student_id;
    WHEN 'HOSTEL' THEN
        SELECT jsonb_build_object(
                 'stays', coalesce(jsonb_agg(jsonb_build_object('reference', al.reference_no, 'session', al.session, 'state', al.state,
                                                                'feeStatus', al.fee_status, 'checkedOut', al.checked_out_at IS NOT NULL,
                                                                'clearance', hc.state) ORDER BY al.session) , '[]'::jsonb),
                 'checkedIn', count(*) FILTER (WHERE al.state = 'CHECKED_IN'),
                 'clearancePending', count(*) FILTER (WHERE al.state = 'CHECKED_OUT' AND coalesce(hc.state, 'PENDING') <> 'CLEARED'),
                 'unsettledCharges', (SELECT count(*) FROM hostel.damage_charge dc JOIN hostel.allocation a2 ON a2.id = dc.allocation_id
                                       WHERE a2.student_id = q.student_id AND dc.settled_at IS NULL AND dc.waived_at IS NULL AND coalesce(dc.charge, 0) > 0),
                 'charges', (SELECT coalesce(sum(dc.charge), 0) FROM hostel.damage_charge dc JOIN hostel.allocation a2 ON a2.id = dc.allocation_id
                              WHERE a2.student_id = q.student_id AND dc.settled_at IS NULL AND dc.waived_at IS NULL))
          INTO v
          FROM hostel.allocation al
          LEFT JOIN hostel.clearance hc ON hc.allocation_id = al.id
         WHERE al.student_id = q.student_id AND al.state IN ('HELD', 'CONFIRMED', 'ACCEPTED', 'CHECKED_IN', 'CHECKED_OUT', 'TRANSFERRED');
    WHEN 'HEALTH' THEN
        -- the fitness finding and its date only: never a diagnosis, a visit or an allergy
        SELECT jsonb_build_object('fitness', hp.fitness, 'fitnessOn', hp.fitness_on) INTO v
          FROM health.profile hp WHERE hp.student_id = q.student_id;
        v := coalesce(v, jsonb_build_object('fitness', NULL, 'fitnessOn', NULL));
    WHEN 'DEPARTMENT' THEN
        IF q.wf = 'FINAL' THEN
            SELECT jsonb_build_object('graduand', jsonb_build_object('session', g.session, 'cgpa', g.cgpa, 'award', g.award, 'unmet', g.unmet,
                                                                     'senate', g.senate_state))
              INTO v FROM records.graduand g WHERE g.student_id = q.student_id ORDER BY g.session DESC LIMIT 1;
            v := coalesce(v, jsonb_build_object('graduand', NULL));
        ELSE
            SELECT jsonb_build_object('registrations', coalesce(jsonb_agg(jsonb_build_object('semester', r.semester, 'status', r.status) ORDER BY r.semester), '[]'::jsonb))
              INTO v FROM registration.course_registration r WHERE r.student_id = q.student_id AND r.session = q.session;
        END IF;
    WHEN 'ALUMNI' THEN
        SELECT jsonb_build_object('email', coalesce(btrim(c.email), '') <> '', 'phone', coalesce(btrim(c.phone), '') <> '',
                                  'address', coalesce(btrim(c.address), '') <> '',
                                  'confirmed', ap.confirmed_at IS NOT NULL, 'confirmedAt', ap.confirmed_at,
                                  'member', coalesce(ap.association_member, false))
          INTO v
          FROM people.student s
          LEFT JOIN people.student_contact c ON c.student_id = s.id
          LEFT JOIN clearance.alumni_profile ap ON ap.student_id = s.id
         WHERE s.id = q.student_id;
    ELSE
        v := '{}'::jsonb;
    END CASE;
    -- every stage: the documents it holds, by state
    v := coalesce(v, '{}'::jsonb) || jsonb_build_object('documents',
           (SELECT coalesce(jsonb_object_agg(d.label, d.state), '{}'::jsonb) FROM clearance.document d
             WHERE d.process_id = p_process AND d.unit = upper(p_unit) AND d.superseded_by IS NULL));
    RETURN v;
END $function$;

-- ── 14 · payments outside school fees in a session the student owes: shown beside the account, for the Bursary to look at ────────
CREATE OR REPLACE FUNCTION finance.historical_other_payments(p_students uuid[])
RETURNS TABLE(student_id uuid, payment_id uuid, reference text, session text, purpose text, amount numeric, confirmed_at timestamptz, channel text,
              kind text, desk_status text)
LANGUAGE sql
STABLE
AS $$
    WITH owe AS (SELECT DISTINCT x.student_id, x.session FROM finance.historical_rows(p_students) x WHERE x.outstanding > 0)
    SELECT r.student_id, r.id, r.reference, r.session, r.purpose, r.amount, r.confirmed_at, r.channel,
           CASE WHEN r.channel = 'Legacy' AND r.purpose ~* '^outstanding' THEN 'OUTSTANDING_FEES' ELSE 'OTHER' END,
           lo.status
      FROM finance.payment_reference r
      JOIN owe o ON o.student_id = r.student_id AND o.session = r.session
      LEFT JOIN finance.legacy_outstanding_payment lo ON lo.payment_id = r.id
     WHERE r.student_id = ANY (p_students) AND r.confirmed_at IS NOT NULL
       AND r.purpose NOT LIKE 'School fees%'
       AND r.purpose ~* '(outstanding|tuition|school|jamb|utme)'
$$;
COMMENT ON FUNCTION finance.historical_other_payments(uuid[]) IS
  'V665: the confirmed payments of the students given, in a session they owe school fees for, that are not school-fee payments yet read like fees — the old portal''s outstanding fees (V631, with their desk status), a payment named by a JAMB number or for tuition; shown beside the account and in a reconciliation run, never counted as school fees by themselves';

-- ── 15 · a reconciliation run: the financial clearance of a population worked out at once, kept as it was found ────────────────────
CREATE TABLE finance.clearance_recon_run (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference text NOT NULL UNIQUE CHECK (reference ~ '^CLEARANCE-RECON/[0-9]{4}/[0-9]{6}$'),
    population text NOT NULL CHECK (population IN ('AWAITING_GRADUATION', 'UNDER_CLEARANCE', 'GRADUATES', 'ALL')),
    scope jsonb NOT NULL DEFAULT '{}'::jsonb,
    students integer NOT NULL DEFAULT 0,
    capped boolean NOT NULL DEFAULT false,
    cleared integer NOT NULL DEFAULT 0,
    owing integer NOT NULL DEFAULT 0,
    review integer NOT NULL DEFAULT 0,
    pending integer NOT NULL DEFAULT 0,
    payment_review integer NOT NULL DEFAULT 0,
    no_period integer NOT NULL DEFAULT 0,
    assessed numeric(16, 2) NOT NULL DEFAULT 0,
    paid numeric(16, 2) NOT NULL DEFAULT 0,
    waived numeric(16, 2) NOT NULL DEFAULT 0,
    outstanding numeric(16, 2) NOT NULL DEFAULT 0,
    run_by uuid NOT NULL,
    run_office text,
    run_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz
);
CREATE INDEX ix_crr_run_at ON finance.clearance_recon_run (run_at DESC);
SELECT audit.attach('finance.clearance_recon_run');
COMMENT ON TABLE finance.clearance_recon_run IS
  'V665: a run of the financial-clearance reconciliation (CLEARANCE-RECON/YYYY/NNNNNN) — the population (awaiting graduation, under final clearance, graduated, or all), the filters, who ran it and when, and the totals; its rows keep each student''s standing as the run found it';

CREATE TABLE finance.clearance_recon_row (
    run_id uuid NOT NULL REFERENCES finance.clearance_recon_run (id) ON DELETE CASCADE,
    student_id uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    status text NOT NULL CHECK (status IN ('CLEARED', 'OWING', 'REQUIRES_REVIEW', 'PENDING_APPROVAL', 'PAYMENT_REVIEW', 'NO_PERIOD')),
    student_status text NOT NULL,
    awaiting_graduation boolean NOT NULL DEFAULT false,
    graduation_session text,
    periods integer NOT NULL DEFAULT 0,
    assessed numeric(14, 2) NOT NULL DEFAULT 0,
    paid numeric(14, 2) NOT NULL DEFAULT 0,
    waived numeric(14, 2) NOT NULL DEFAULT 0,
    outstanding numeric(14, 2) NOT NULL DEFAULT 0,
    credit numeric(14, 2) NOT NULL DEFAULT 0,
    owing text,
    review_periods text,
    pending_periods text,
    other_payments integer NOT NULL DEFAULT 0,
    other_amount numeric(14, 2) NOT NULL DEFAULT 0,
    process_id uuid,
    clearance_ref text,
    bursary_state text,
    PRIMARY KEY (run_id, student_id)
);
CREATE INDEX ix_crr_row_status ON finance.clearance_recon_row (run_id, status);
SELECT audit.exempt('finance.clearance_recon_row', 'V665: a snapshot worked out by a reconciliation run from the historical account; nothing in it is decided by a person, and the run that wrote it is on the audit spine');
COMMENT ON TABLE finance.clearance_recon_row IS
  'V665: one student in a reconciliation run as the run found them — CLEARED, OWING, REQUIRES_REVIEW (a period with no amount), PENDING_APPROVAL (an assessment awaiting the Bursar), PAYMENT_REVIEW (owing, with a payment outside school fees in an owing session to look at) or NO_PERIOD — with the account in totals and the final clearance';

CREATE OR REPLACE FUNCTION finance.clearance_recon_start(p_scope jsonb)
RETURNS finance.clearance_recon_run
LANGUAGE plpgsql
AS $$
DECLARE v_scope jsonb := coalesce(p_scope, '{}'::jsonb); v_pop text; v_ids uuid[]; v_n int; v_cap int := 5000; run finance.clearance_recon_run;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_year text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY');
        f_fac text; f_dept text; f_prog text; f_adm text; f_grad text;
BEGIN
    PERFORM finance.historical_require('PROCESS_FINANCIAL_CLEARANCE');
    IF v_actor IS NULL THEN RAISE EXCEPTION 'HFR_ACTOR: a reconciliation is run by a named officer' USING ERRCODE = '42501'; END IF;
    v_pop := upper(coalesce(nullif(btrim(v_scope->>'population'), ''), 'AWAITING_GRADUATION'));
    IF v_pop NOT IN ('AWAITING_GRADUATION', 'UNDER_CLEARANCE', 'GRADUATES', 'ALL') THEN
        RAISE EXCEPTION 'HFR_POPULATION: a run covers the students awaiting graduation, under final clearance, graduated, or all of them' USING ERRCODE = '23514';
    END IF;
    f_fac := nullif(btrim(v_scope->>'faculty'), ''); f_dept := nullif(btrim(v_scope->>'dept'), ''); f_prog := nullif(btrim(v_scope->>'programme'), '');
    f_adm := nullif(btrim(v_scope->>'admission'), ''); f_grad := nullif(btrim(v_scope->>'graduation'), '');
    -- the population, narrowed by the filters (at most 5,000 students a run, the rest said to be left out)
    SELECT array_agg(x.id), count(*) INTO v_ids, v_n FROM (
        SELECT s.id FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
         WHERE CASE v_pop
                 WHEN 'AWAITING_GRADUATION' THEN s.status <> 'GRADUATED'
                      AND EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED')
                 WHEN 'UNDER_CLEARANCE' THEN EXISTS (SELECT 1 FROM clearance.process q WHERE q.student_id = s.id AND q.workflow = 'FINAL'
                                                       AND q.cancelled_at IS NULL AND q.completed_at IS NULL)
                 WHEN 'GRADUATES' THEN s.status = 'GRADUATED'
                 ELSE s.status = 'GRADUATED'
                      OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED')
                      OR EXISTS (SELECT 1 FROM clearance.process q WHERE q.student_id = s.id AND q.workflow = 'FINAL' AND q.cancelled_at IS NULL)
               END
           AND (f_fac IS NULL OR p.faculty_code = f_fac) AND (f_dept IS NULL OR p.dept_code = f_dept) AND (f_prog IS NULL OR p.code = f_prog)
           AND (f_adm IS NULL OR s.entry_session = f_adm)
           AND (f_grad IS NULL OR records.graduation_session(s.id) = f_grad)
         ORDER BY s.surname, s.other_names, s.id
         LIMIT v_cap + 1) x;
    v_ids := coalesce(v_ids, '{}'::uuid[]);
    IF coalesce(v_n, 0) > v_cap THEN v_ids := v_ids[1:v_cap]; END IF;
    INSERT INTO finance.clearance_recon_run (reference, population, scope, capped, run_by, run_office)
    VALUES ('CLEARANCE-RECON/' || v_year || '/' || lpad(platform.next_number('CLEARANCE_RECON', 'finance', v_year)::text, 6, '0'),
            v_pop, jsonb_strip_nulls(jsonb_build_object('faculty', f_fac, 'dept', f_dept, 'programme', f_prog, 'admission', f_adm, 'graduation', f_grad)),
            coalesce(v_n, 0) > v_cap, v_actor, v_office)
    RETURNING * INTO run;
    IF cardinality(v_ids) > 0 THEN
        WITH hr AS (SELECT * FROM finance.historical_rows(v_ids)),
        agg AS (
            SELECT r.student_id, count(*)::int AS periods, coalesce(sum(r.assessed), 0) AS assessed, coalesce(sum(r.paid), 0) AS paid,
                   coalesce(sum(r.waived), 0) AS waived, coalesce(sum(r.outstanding), 0) AS outstanding, coalesce(sum(r.credit), 0) AS credit,
                   count(*) FILTER (WHERE r.status = 'REQUIRES_REVIEW')::int AS review, count(*) FILTER (WHERE r.status = 'PENDING_APPROVAL')::int AS pending,
                   string_agg(r.session || ' ' || finance.semester_words(r.semester) || ' (' || clearance.naira(r.outstanding) || ')', '; ' ORDER BY r.session, r.semester)
                       FILTER (WHERE r.outstanding > 0) AS owing,
                   string_agg(r.session || ' ' || finance.semester_words(r.semester), ', ' ORDER BY r.session, r.semester) FILTER (WHERE r.status = 'REQUIRES_REVIEW') AS review_periods,
                   string_agg(r.session || ' ' || finance.semester_words(r.semester), ', ' ORDER BY r.session, r.semester) FILTER (WHERE r.status = 'PENDING_APPROVAL') AS pending_periods
              FROM hr r GROUP BY r.student_id),
        oth AS (SELECT o.student_id, count(*)::int AS n, coalesce(sum(o.amount), 0) AS amount
                  FROM finance.historical_other_payments(v_ids) o WHERE coalesce(o.desk_status, '') <> 'REJECTED' GROUP BY o.student_id),
        pq AS (SELECT DISTINCT ON (q.student_id) q.student_id, q.id, q.reference, q.session, w.purpose
                 FROM clearance.process q JOIN clearance.workflow w ON w.code = q.workflow
                WHERE q.workflow = 'FINAL' AND q.cancelled_at IS NULL AND q.student_id = ANY (v_ids)
                ORDER BY q.student_id, q.started_at DESC)
        INSERT INTO finance.clearance_recon_row (run_id, student_id, status, student_status, awaiting_graduation, graduation_session, periods, assessed, paid,
                                                 waived, outstanding, credit, owing, review_periods, pending_periods, other_payments, other_amount,
                                                 process_id, clearance_ref, bursary_state)
        SELECT run.id, s.id,
               CASE WHEN coalesce(a.periods, 0) = 0 THEN 'NO_PERIOD'
                    WHEN a.review > 0 THEN 'REQUIRES_REVIEW'
                    WHEN a.pending > 0 THEN 'PENDING_APPROVAL'
                    WHEN a.outstanding > 0 AND coalesce(o.n, 0) > 0 THEN 'PAYMENT_REVIEW'
                    WHEN a.outstanding > 0 THEN 'OWING'
                    ELSE 'CLEARED' END,
               s.status, s.status <> 'GRADUATED' AND EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED'),
               records.graduation_session(s.id), coalesce(a.periods, 0), coalesce(a.assessed, 0), coalesce(a.paid, 0), coalesce(a.waived, 0),
               coalesce(a.outstanding, 0), coalesce(a.credit, 0), a.owing, a.review_periods, a.pending_periods, coalesce(o.n, 0), coalesce(o.amount, 0),
               pq.id, pq.reference,
               (SELECT r.state FROM clearance.stage_rows(pq.purpose, pq.session, ARRAY[s.id]) r WHERE r.unit = 'BURSARY')
          FROM unnest(v_ids) u(id)
          JOIN people.student s ON s.id = u.id
          LEFT JOIN agg a ON a.student_id = s.id
          LEFT JOIN oth o ON o.student_id = s.id
          LEFT JOIN pq ON pq.student_id = s.id;
    END IF;
    UPDATE finance.clearance_recon_run x
       SET students = t.students, cleared = t.cleared, owing = t.owing, review = t.review, pending = t.pending, payment_review = t.payment_review,
           no_period = t.no_period, assessed = t.assessed, paid = t.paid, waived = t.waived, outstanding = t.outstanding, finished_at = clock_timestamp()
      FROM (SELECT count(*)::int AS students, count(*) FILTER (WHERE r.status = 'CLEARED')::int AS cleared, count(*) FILTER (WHERE r.status = 'OWING')::int AS owing,
                   count(*) FILTER (WHERE r.status = 'REQUIRES_REVIEW')::int AS review, count(*) FILTER (WHERE r.status = 'PENDING_APPROVAL')::int AS pending,
                   count(*) FILTER (WHERE r.status = 'PAYMENT_REVIEW')::int AS payment_review, count(*) FILTER (WHERE r.status = 'NO_PERIOD')::int AS no_period,
                   coalesce(sum(r.assessed), 0) AS assessed, coalesce(sum(r.paid), 0) AS paid, coalesce(sum(r.waived), 0) AS waived,
                   coalesce(sum(r.outstanding), 0) AS outstanding
              FROM finance.clearance_recon_row r WHERE r.run_id = run.id) t
     WHERE x.id = run.id
    RETURNING x.* INTO run;
    -- the summaries of the students run brought up to date with what the run found
    PERFORM finance.historical_refresh(v_ids) WHERE cardinality(v_ids) > 0;
    RETURN run;
END $$;
COMMENT ON FUNCTION finance.clearance_recon_start(jsonb) IS
  'V665: a reconciliation run (CLEARANCE-RECON/YYYY/NNNNNN) by an office holding PROCESS_FINANCIAL_CLEARANCE — the population (AWAITING_GRADUATION by default, UNDER_CLEARANCE, GRADUATES or ALL) narrowed by faculty, department, programme, admission and graduation session, at most 5,000 students (capped said); every student''s account read afresh from finance.historical_rows and kept as a row with its status, the payments outside school fees to look at and the final clearance; the totals on the run; the summaries brought up to date';

COMMIT;
