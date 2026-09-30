-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V297 — the programme change register, and the admission corrected after the fees
--
--   Two things the Admissions Office asked for.
--
--   1 · THE LIST. Every applicant now on a programme other than the one they applied for,
--       with why. The changes were all on admissions.programme_change_request (V266, V284),
--       but nothing read them back as a list: the eligibility desk shows requests, not people.
--       admissions.programme_change_register(session) gives one row per applicant — the
--       programme applied for (the first approved change's "from"), the programme held now,
--       the reason and note, the stage the change was made at (before the decision, on the
--       applicant's request, at the screening, or an admission correction), who recommended it
--       and who approved it and when, the eligibility override where there was one, where the
--       admission stands today, the fee position, and every change in order.
--
--   2 · THE CORRECTION. After the Board's decision the programme could be changed only while
--       the University's screening was open (V284); once the screening was successful, or the
--       school fees paid, it could not be changed at all — even when an error in the admission
--       was discovered. Now it can, as an ADMISSION CORRECTION: a programme_change_request of
--       kind CORRECTION, recommended by the Academic Office (or the Registrar's office) with a
--       reason and a note describing the error, and decided by the Registrar, the Deputy
--       Registrar or the Vice-Chancellor's office — never by the officer who recommended it.
--       The approval re-reads the route and the eligibility at that moment and then:
--         · changes the candidate's and the student's programme (the original stays on the
--           request and the trail);
--         · keeps every payment: the acceptance fee stands; school fees already paid stay on
--           the student and count against the new programme's fees — the fee position before
--           and after is recorded on the correction, the applicant is told the balance to pay
--           or the excess, and the Bursary is told when the fees changed;
--         · drops the courses registered on the old programme and returns the registration to
--           the student to register the new programme's;
--         · drops a matriculation number proposed on the old programme from its batch (the
--           student is numbered with the new programme's);
--         · reissues the admission letter and the screening forms for the new programme (the
--           earlier versions answer REPLACED to the verifier);
--         · notes it on the screening form and both trails, and tells the applicant.
--       A matriculated student, or one with results recorded on the programme, is past a
--       correction: that is an inter-departmental transfer (SAIC, then Senate; V070).
--
--   The school fees for a programme not yet held are read by finance.charges_as — the fee
--   schedule's own reading (finance.charges_of) for a programme named, so the preview and the
--   position can never disagree.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V297: the programme change register and the admission corrected after the fees', true);

-- ── 1 · what a change records ────────────────────────────────────────────────────────────────
ALTER TABLE admissions.programme_change_request
    ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'CHANGE',
    ADD COLUMN IF NOT EXISTS admission_stage text,
    ADD COLUMN IF NOT EXISTS decided_office text,
    ADD COLUMN IF NOT EXISTS fee_session text,
    ADD COLUMN IF NOT EXISTS fees_paid numeric(14,2),
    ADD COLUMN IF NOT EXISTS fees_due_before numeric(14,2),
    ADD COLUMN IF NOT EXISTS fees_due_after numeric(14,2),
    ADD COLUMN IF NOT EXISTS registrations_returned integer,
    ADD COLUMN IF NOT EXISTS courses_dropped integer,
    ADD COLUMN IF NOT EXISTS matric_rows_dropped integer,
    ADD COLUMN IF NOT EXISTS letter_reissued boolean,
    ADD COLUMN IF NOT EXISTS forms_reissued boolean;
ALTER TABLE admissions.programme_change_request DROP CONSTRAINT IF EXISTS ck_pcr_kind;
ALTER TABLE admissions.programme_change_request ADD CONSTRAINT ck_pcr_kind CHECK (kind IN ('CHANGE', 'CORRECTION'));
ALTER TABLE admissions.programme_change_request DROP CONSTRAINT IF EXISTS ck_pcr_correction_note;
ALTER TABLE admissions.programme_change_request ADD CONSTRAINT ck_pcr_correction_note CHECK (kind <> 'CORRECTION' OR nullif(btrim(coalesce(note, '')), '') IS NOT NULL);
COMMENT ON COLUMN admissions.programme_change_request.kind IS
  'V297: CHANGE — the ordinary change (before the decision, or during the screening, V284); CORRECTION — an admission corrected after the decision, recommended with a note and decided by the Registrar''s office.';
COMMENT ON COLUMN admissions.programme_change_request.admission_stage IS 'V297: where the admission stood when the correction was recommended (admissions.admission_stage).';
COMMENT ON COLUMN admissions.programme_change_request.fees_due_before IS 'V297: the school fees due for fee_session on the old programme at the approval; fees_due_after on the new; fees_paid what had been paid — kept, and counted against the new.';

INSERT INTO admissions.programme_change_reason (code, label, ord, requires_note)
VALUES ('ADMISSION_ERROR', 'Error discovered in the admission', 6, true)
ON CONFLICT (code) DO NOTHING;

-- ── 2 · the fee schedule read for a programme not (yet) held ────────────────────────────────
-- finance.charges_of, with the programme named instead of read from the student; the original is now this with none named
CREATE OR REPLACE FUNCTION finance.charges_of_as(p_student uuid, p_session text, p_kinds text[], p_programme text)
RETURNS TABLE(id uuid, item text, amount numeric, ord integer)
LANGUAGE sql STABLE AS $$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS (
        SELECT s.id, coalesce(p_programme, s.programme_code) AS programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               coalesce(s.current_level > finance.final_level(coalesce(p_programme, s.programme_code)) AND s.status <> 'GRADUATED', false) AS is_spill
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.id = p_student)
    SELECT f.id,
           replace(replace(replace(f.item,
               '(semester 1)', '(First Semester)'),
               '(semester 2)', '(Second Semester)'),
               '(semester 3)', '(Third Semester)') AS item,
           f.amount, f.ord
      FROM finance.fee_schedule f
      CROSS JOIN me
      JOIN ref.programme p ON p.code = me.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
      CROSS JOIN home
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND f.kind = ANY (p_kinds)
       AND f.spillover = me.is_spill
       AND (me.is_spill OR f.level IS NULL OR f.level = me.current_level)
       AND (f.entry_mode IS NULL OR f.entry_mode = me.entry_mode)
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)))
       AND (f.semester IS NULL
            OR f.semester <= coalesce((SELECT max(sm.number) FROM policy.semester sm
                                        WHERE sm.session = p_session AND sm.state = 'OPEN'), 3))
     ORDER BY f.ord, f.item;
$$;

CREATE OR REPLACE FUNCTION finance.charges_of(p_student uuid, p_session text, p_kinds text[])
RETURNS TABLE(id uuid, item text, amount numeric, ord integer)
LANGUAGE sql STABLE AS $$
    SELECT x.id, x.item, x.amount, x.ord FROM finance.charges_of_as(p_student, p_session, p_kinds, NULL) x;
$$;

-- finance.charges, for a programme named: the fees, and the late charges where they apply
CREATE OR REPLACE FUNCTION finance.charges_as(p_student uuid, p_session text, p_programme text)
RETURNS TABLE(id uuid, item text, amount numeric, ord integer)
LANGUAGE sql STABLE AS $$
    SELECT c.id, c.item, c.amount, c.ord FROM finance.charges_of_as(p_student, p_session, ARRAY['FEE'], p_programme) c
    UNION ALL
    SELECT c.id, c.item, c.amount, c.ord FROM finance.charges_of_as(p_student, p_session, ARRAY['LATE_PAYMENT'], p_programme) c WHERE finance.late_payment_applies(p_student, p_session)
    UNION ALL
    SELECT c.id, c.item, c.amount, c.ord FROM finance.charges_of_as(p_student, p_session, ARRAY['LATE_REGISTRATION'], p_programme) c WHERE finance.late_registration_applies(p_student, p_session)
    ORDER BY ord, item
$$;

CREATE OR REPLACE FUNCTION finance.charges(p_student uuid, p_session text)
RETURNS TABLE(id uuid, item text, amount numeric, ord integer)
LANGUAGE sql STABLE AS $$
    SELECT x.id, x.item, x.amount, x.ord FROM finance.charges_as(p_student, p_session, NULL) x;
$$;

/* what the student would owe for the session on the programme named — what finance.position's "due" becomes once it is theirs */
CREATE OR REPLACE FUNCTION finance.due_as(p_student uuid, p_session text, p_programme text)
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT coalesce(sum(c.amount), 0) FROM finance.charges_as(p_student, p_session, p_programme) c;
$$;

-- ── 3 · where an admission stands, and which road a change of programme takes ────────────────
CREATE OR REPLACE FUNCTION admissions.naira(p numeric)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p IS NULL THEN '—'
                WHEN p = trunc(p) THEN 'NGN ' || to_char(p, 'FM999,999,999,990')
                ELSE 'NGN ' || to_char(p, 'FM999,999,999,990.00') END;
$$;

CREATE OR REPLACE FUNCTION admissions.admission_stage(p_app uuid)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE
             WHEN a.decision_released_at IS NULL THEN 'AWAITING_DECISION'
             WHEN coalesce(a.decision, '') <> 'OFFERED' THEN 'NOT_OFFERED'
             WHEN a.declined_at IS NOT NULL THEN 'DECLINED'
             WHEN st.matric_no IS NOT NULL THEN 'MATRICULATED'
             WHEN st.id IS NOT NULL AND EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = st.id AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) THEN 'COURSES_REGISTERED'
             WHEN st.id IS NOT NULL AND EXISTS (SELECT 1 FROM finance.payment_reference r WHERE r.student_id = st.id AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%') THEN 'SCHOOL_FEES_PAID'
             WHEN st.id IS NOT NULL THEN 'ON_REGISTER'
             WHEN EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = a.id AND f.state = 'SUCCESSFUL') THEN 'SCREENED'
             WHEN a.accepted_at IS NOT NULL THEN 'ACCEPTED'
             ELSE 'OFFERED'
           END
      FROM admissions.application a
      LEFT JOIN LATERAL (SELECT s.id, s.matric_no FROM people.student s WHERE s.candidate_id = a.candidate_id ORDER BY s.matric_no NULLS LAST LIMIT 1) st ON true
     WHERE a.id = p_app;
$$;
COMMENT ON FUNCTION admissions.admission_stage(uuid) IS
  'V297: AWAITING_DECISION, NOT_OFFERED, DECLINED, OFFERED, ACCEPTED, SCREENED, ON_REGISTER, SCHOOL_FEES_PAID, COURSES_REGISTERED or MATRICULATED — read from the tables that own each step.';

/* CHANGE while the ordinary change applies (before the decision; while the screening is open or after an unsuccessful one, V284);
   CORRECTION once the decision is released on an offer not declined, up to matriculation; TRANSFER after it, or once results are
   recorded; CLOSED when there is no admission to correct */
CREATE OR REPLACE FUNCTION admissions.programme_change_route(p_app uuid)
RETURNS TABLE (route text, stage text, detail text)
LANGUAGE plpgsql STABLE AS $$
DECLARE a admissions.application; f admissions.screening_form; v_stage text; v_matric text; v_student uuid;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN; END IF;
    v_stage := admissions.admission_stage(p_app);
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    SELECT s.id, s.matric_no INTO v_student, v_matric FROM people.student s WHERE s.candidate_id = a.candidate_id ORDER BY s.matric_no NULLS LAST LIMIT 1;
    IF a.decision_released_at IS NULL THEN
        RETURN QUERY SELECT 'CHANGE'::text, v_stage, 'Before the Board''s decision the programme is changed the ordinary way, on Programme Eligibility.'::text;
        RETURN;
    END IF;
    IF f.application_id IS NOT NULL AND f.state IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED', 'UNSUCCESSFUL')
       AND NOT EXISTS (SELECT 1 FROM admissions.programme_change_request q
                        WHERE q.application_id = p_app AND q.state = 'APPROVED' AND f.decided_at IS NOT NULL AND q.decided_at >= f.decided_at) THEN
        RETURN QUERY SELECT 'CHANGE'::text, v_stage, 'The University''s screening of this admission is still open: the programme is changed from the screening desk.'::text;
        RETURN;
    END IF;
    IF coalesce(a.decision, '') <> 'OFFERED' THEN
        RETURN QUERY SELECT 'CLOSED'::text, v_stage, 'There is no admission to correct: the Board''s decision is ' || lower(replace(coalesce(a.decision, 'not recorded'), '_', ' ')) || '.';
        RETURN;
    END IF;
    IF a.declined_at IS NOT NULL THEN
        RETURN QUERY SELECT 'CLOSED'::text, v_stage, 'The offer was declined; there is no admission to correct.'::text;
        RETURN;
    END IF;
    IF v_matric IS NOT NULL THEN
        RETURN QUERY SELECT 'TRANSFER'::text, v_stage, 'The student is matriculated (' || v_matric || '): a change of programme is then an inter-departmental transfer, through SAIC and Senate.';
        RETURN;
    END IF;
    IF v_student IS NOT NULL AND (EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = v_student AND r.status = 'LOCKED')
                                  OR EXISTS (SELECT 1 FROM assessment.score sc WHERE sc.student_id = v_student)) THEN
        RETURN QUERY SELECT 'TRANSFER'::text, v_stage, 'Results are recorded, or the registration is locked, on the programme: a change is then an inter-departmental transfer, through SAIC and Senate.'::text;
        RETURN;
    END IF;
    RETURN QUERY SELECT 'CORRECTION'::text, v_stage, 'The Board''s decision is released: the programme is changed by an admission correction, recommended with the error found and approved by the Registrar''s office.'::text;
END $$;

-- ── 4 · what a correction would do, before anyone does it ────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.correction_preview(p_app uuid, p_to text)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE a admissions.application; c admissions.candidate; rt record; st people.student; pos record; cur record; tgt record; r record; oq admissions.programme_change_request;
        v_to text := nullif(upper(btrim(coalesce(p_to, ''))), ''); v_due numeric; o jsonb;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN NULL; END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    SELECT * INTO rt FROM admissions.programme_change_route(p_app);
    SELECT s.* INTO st FROM people.student s WHERE s.candidate_id = c.id ORDER BY s.matric_no NULLS LAST LIMIT 1;
    SELECT p.code, p.name, f.name AS faculty, d.name AS department INTO cur
      FROM ref.programme p LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code
     WHERE p.code = admissions.programme_code_of(c.programme);
    SELECT * INTO oq FROM admissions.programme_change_request q WHERE q.application_id = p_app AND q.state = 'REQUESTED' LIMIT 1;
    o := jsonb_build_object(
        'applicationId', a.id, 'applicationNo', a.application_no, 'jambRegNo', c.jamb_reg_no, 'name', c.surname || ', ' || c.other_names,
        'entryMode', c.entry_mode, 'session', a.session, 'route', rt.route, 'stage', rt.stage, 'detail', rt.detail,
        'current', jsonb_build_object('code', cur.code, 'name', coalesce(cur.name, c.programme), 'faculty', cur.faculty, 'department', cur.department),
        'student', CASE WHEN st.id IS NULL THEN NULL ELSE jsonb_build_object('id', st.id, 'admissionNo', st.admission_no, 'matricNo', st.matric_no) END,
        'registrations', coalesce((SELECT jsonb_agg(jsonb_build_object('session', x.session, 'semester', x.semester, 'status', x.status,
                                          'courses', (SELECT count(*) FROM registration.entry e WHERE e.registration_id = x.id AND e.status <> 'DROPPED')) ORDER BY x.session, x.semester)
                                     FROM registration.course_registration x WHERE st.id IS NOT NULL AND x.student_id = st.id), '[]'::jsonb),
        'matricRows', (SELECT count(*) FROM people.matric_batch_row br JOIN people.matric_batch b ON b.id = br.batch_id
                        WHERE st.id IS NOT NULL AND br.student_id = st.id AND br.state = 'PROPOSED' AND b.state IN ('GENERATED', 'READY_FOR_ISSUANCE')),
        'letterIssued', EXISTS (SELECT 1 FROM credentials.issued i WHERE i.application_id = a.id AND i.kind = 'ADMISSION_LETTER'),
        'formsIssued', EXISTS (SELECT 1 FROM credentials.issued i WHERE i.application_id = a.id AND i.kind = 'SCREENING_FORMS'),
        'openRequest', CASE WHEN oq.id IS NULL THEN NULL ELSE jsonb_build_object('id', oq.id, 'kind', oq.kind, 'to', oq.to_programme, 'requestedAt', oq.requested_at) END);
    IF st.id IS NOT NULL THEN
        SELECT * INTO pos FROM finance.position(st.id, a.session);
        o := o || jsonb_build_object('fees', jsonb_build_object('session', a.session, 'paid', pos.paid, 'dueNow', pos.due,
                                                                 'balanceNow', greatest(pos.due - pos.paid, 0), 'excessNow', greatest(pos.paid - pos.due, 0)));
    END IF;
    IF v_to IS NOT NULL THEN
        SELECT p.code, p.name, p.archived, f.name AS faculty, d.name AS department INTO tgt
          FROM ref.programme p LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code WHERE p.code = v_to;
        IF tgt.code IS NOT NULL THEN
            SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, v_to, c.entry_mode);
            o := o || jsonb_build_object('target', jsonb_build_object('code', tgt.code, 'name', tgt.name, 'faculty', tgt.faculty, 'department', tgt.department,
                                                                      'archived', tgt.archived, 'result', r.result, 'reasons', to_jsonb(coalesce(r.reasons, ARRAY[]::text[]))));
            IF st.id IS NOT NULL THEN
                v_due := finance.due_as(st.id, a.session, v_to);
                o := jsonb_set(o, '{fees}', (o -> 'fees') || jsonb_build_object('dueAfter', v_due, 'balanceAfter', greatest(v_due - pos.paid, 0), 'excessAfter', greatest(pos.paid - v_due, 0)));
            END IF;
        END IF;
    END IF;
    RETURN o;
END $$;

-- ── 5 · the recommendation ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.recommend_admission_correction(p_app uuid, p_to text, p_reason text, p_note text, p_actor uuid, p_office text, p_override boolean, p_override_reason text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE a admissions.application; c admissions.candidate; g ref.programme; rs admissions.programme_change_reason; f admissions.screening_form; r record; rt record;
        v_run uuid; v_id uuid; v_from text; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_to text := upper(btrim(coalesce(p_to, ''))); o text;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF coalesce(p_office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'CORRECTION_RECOMMENDER: an admission correction is recommended by the Academic Office or the Registrar''s office' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO rt FROM admissions.programme_change_route(p_app);
    IF rt.route = 'CHANGE' THEN
        RAISE EXCEPTION 'CORRECTION_NOT_NEEDED: %', rt.detail USING ERRCODE = '23514',
              HINT = 'Use Request Change on Programme Eligibility, or the change of programme on the screening desk.';
    ELSIF rt.route = 'TRANSFER' THEN
        RAISE EXCEPTION 'CORRECTION_TRANSFER: %', rt.detail USING ERRCODE = '23514', HINT = 'The student applies through Inter-Departmental Transfer.';
    ELSIF rt.route IS DISTINCT FROM 'CORRECTION' THEN
        RAISE EXCEPTION 'CORRECTION_NO_ADMISSION: %', coalesce(rt.detail, 'there is no admission to correct') USING ERRCODE = '23514';
    END IF;
    SELECT * INTO rs FROM admissions.programme_change_reason WHERE code = upper(btrim(coalesce(p_reason, ''))) AND active;
    IF rs.code IS NULL THEN RAISE EXCEPTION 'CORRECTION_REASON: an admission correction carries one of the configured reasons' USING ERRCODE = '23514'; END IF;
    IF v_note IS NULL THEN
        RAISE EXCEPTION 'CORRECTION_NOTE_REQUIRED: describe the error found in the admission and how it was found' USING ERRCODE = '23514',
              HINT = 'The note is what the Registrar decides on, and it stays on the record.';
    END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    SELECT * INTO g FROM ref.programme WHERE code = v_to;
    IF g.code IS NULL OR g.archived THEN RAISE EXCEPTION 'no such active programme %', v_to USING ERRCODE = '23514'; END IF;
    v_from := admissions.programme_code_of(c.programme);
    IF v_from = v_to THEN RAISE EXCEPTION 'that is the programme the candidate holds' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM admissions.programme_change_request q WHERE q.application_id = p_app AND q.state = 'REQUESTED') THEN
        RAISE EXCEPTION 'a change of programme is already recommended and awaits approval' USING ERRCODE = '23514';
    END IF;
    -- the engine, read again now against the session's settings
    v_run := admissions.eligibility_current(p_app, p_actor);
    SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, v_to, c.entry_mode);
    IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN
        IF NOT coalesce(p_override, false) THEN
            RAISE EXCEPTION 'the candidate is not eligible for %: %', g.name, array_to_string(r.reasons, '; ') USING ERRCODE = '23514',
                  HINT = 'Only a programme the engine finds the candidate eligible for is recommended; an override is reserved to the Registrar.';
        END IF;
        IF nullif(btrim(coalesce(p_override_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'an eligibility override carries its reason' USING ERRCODE = '23514'; END IF;
    END IF;
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    INSERT INTO admissions.programme_change_request (application_id, candidate_id, session, from_programme_code, from_programme, to_programme_code, to_programme, run_id, eligibility_at_request,
                                                     requested_by_kind, requested_by, note, reason_code, recommended_office, override, override_reason, original_eligibility,
                                                     screening_state_at_request, kind, admission_stage)
    VALUES (p_app, c.id, a.session, v_from, c.programme, v_to, g.name, v_run, r.result, 'OFFICE', p_actor, v_note, rs.code, p_office,
            r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING'), nullif(btrim(coalesce(p_override_reason, '')), ''), r.result, f.state, 'CORRECTION', rt.stage)
    RETURNING id INTO v_id;
    PERFORM admissions.eligibility_log(p_app, v_run, 'ADMISSION_CORRECTION_RECOMMENDED', v_to, r.result,
        'From ' || c.programme || ' to ' || g.name || ' · ' || rs.label || ' · ' || v_note || ' · by the ' || p_office || ' · admission ' || lower(replace(rt.stage, '_', ' '))
        || CASE WHEN r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN ' · OVERRIDE: ' || coalesce(p_override_reason, '') ELSE '' END);
    IF f.application_id IS NOT NULL THEN
        PERFORM admissions.screening_log(p_app, 'ADMISSION_CORRECTION_RECOMMENDED', 'From ' || c.programme || ' to ' || g.name || ' · ' || rs.label || ' · awaiting the Registrar''s approval');
    END IF;
    -- the applicant is told when it is decided, not while it may yet be refused; the Registrar's office is told now
    FOREACH o IN ARRAY ARRAY['registrar', 'dregistrar'] LOOP
        PERFORM admissions.tell_office(o, 'An admission correction awaits approval',
            'Applicant ' || c.surname || ', ' || c.other_names || ' (' || c.jamb_reg_no || ', ' || a.application_no || '): the ' || p_office
            || ' recommends correcting the admission from ' || c.programme || ' to ' || g.name || ' · ' || rs.label || ' · ' || v_note
            || ' · the admission stands at: ' || lower(replace(rt.stage, '_', ' ')) || ' · the engine finds the candidate ' || lower(replace(r.result, '_', ' '))
            || CASE WHEN coalesce(p_override, false) THEN ' (override)' ELSE '' END || '. Decide it on Programme Changes.', p_app);
    END LOOP;
    RETURN v_id;
END $fn$;

-- ── 6 · the decision on a correction ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.decide_admission_correction(p_req uuid, p_decision text, p_note text, p_actor uuid)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE q admissions.programme_change_request; a admissions.application; c admissions.candidate; f admissions.screening_form; st people.student; rs admissions.programme_change_reason;
        r record; rt record; reg record; mrow record; v_prog record;
        v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_due_before numeric; v_paid numeric; v_due_after numeric; v_regs int := 0; v_entries int := 0; v_matric int := 0; n int;
        v_letter boolean := false; v_forms boolean := false; v_reason text; v_fees text := ''; v_more text := '';
BEGIN
    SELECT * INTO q FROM admissions.programme_change_request WHERE id = p_req FOR UPDATE;
    IF q.id IS NULL OR q.kind <> 'CORRECTION' THEN RAISE EXCEPTION 'no such admission correction' USING ERRCODE = '23503'; END IF;
    IF q.state <> 'REQUESTED' THEN RAISE EXCEPTION 'the correction is already %', lower(q.state) USING ERRCODE = '23514'; END IF;
    IF v_office IS NULL OR v_office NOT IN ('registrar', 'dregistrar', 'vc', 'super') THEN
        RAISE EXCEPTION 'CORRECTION_APPROVER: an admission correction is decided by the Registrar, the Deputy Registrar or the Vice-Chancellor''s office' USING ERRCODE = '23514',
              HINT = 'The Academic Office recommends the correction; the Registrar''s office approves or rejects it.';
    END IF;
    IF p_actor IS NOT NULL AND p_actor = q.requested_by THEN
        RAISE EXCEPTION 'CORRECTION_SAME_OFFICER: the officer who recommended the correction does not also decide it' USING ERRCODE = '23514',
              HINT = 'Another officer of the Registrar''s office decides it.';
    END IF;
    SELECT * INTO a FROM admissions.application WHERE id = q.application_id;
    SELECT * INTO c FROM admissions.candidate WHERE id = q.candidate_id;
    SELECT * INTO rs FROM admissions.programme_change_reason WHERE code = q.reason_code;
    v_reason := coalesce(rs.label, q.reason_code, 'correction');

    IF p_decision = 'REJECT' THEN
        IF v_note IS NULL THEN RAISE EXCEPTION 'a rejection carries its reason' USING ERRCODE = '23514'; END IF;
        UPDATE admissions.programme_change_request SET state = 'REJECTED', decided_at = now(), decided_by = p_actor, decided_office = v_office, decision_note = v_note WHERE id = q.id;
        PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'ADMISSION_CORRECTION_REJECTED', q.to_programme_code, NULL, v_note);
        IF EXISTS (SELECT 1 FROM admissions.screening_form x WHERE x.application_id = a.id) THEN
            PERFORM admissions.screening_log(a.id, 'ADMISSION_CORRECTION_REJECTED', 'To ' || q.to_programme || ' · ' || v_note);
        END IF;
        IF q.recommended_office IS NOT NULL THEN
            PERFORM admissions.tell_office(q.recommended_office, 'Admission correction not approved',
                c.surname || ', ' || c.other_names || ' (' || c.jamb_reg_no || '): the correction from ' || q.from_programme || ' to ' || q.to_programme
                || ' was not approved by the ' || v_office || '. Reason: ' || v_note || ' The admission stands as it was.', a.id);
        END IF;
        RETURN 'REJECTED';
    ELSIF p_decision IS DISTINCT FROM 'APPROVE' THEN
        RAISE EXCEPTION 'unknown decision %', p_decision USING ERRCODE = '23514';
    END IF;

    -- the admission may have moved on since the recommendation: its road and its programme are read again
    SELECT * INTO rt FROM admissions.programme_change_route(a.id);
    IF rt.route IS DISTINCT FROM 'CORRECTION' THEN
        RAISE EXCEPTION '%: %', CASE rt.route WHEN 'TRANSFER' THEN 'CORRECTION_TRANSFER' WHEN 'CHANGE' THEN 'CORRECTION_NOT_NEEDED' ELSE 'CORRECTION_NO_ADMISSION' END,
              coalesce(rt.detail, 'there is no admission to correct') USING ERRCODE = '23514';
    END IF;
    IF admissions.programme_code_of(c.programme) IS DISTINCT FROM q.from_programme_code THEN
        RAISE EXCEPTION 'CORRECTION_STALE: the admission is no longer for %; recommend the correction again', q.from_programme USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, q.to_programme_code, c.entry_mode);
    IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') AND NOT q.override THEN
        RAISE EXCEPTION 'on the current settings the candidate is no longer eligible for %: %', q.to_programme, array_to_string(r.reasons, '; ') USING ERRCODE = '23514';
    END IF;
    IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN
        PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'ELIGIBILITY_OVERRIDE_APPLIED', q.to_programme_code, r.result,
            'Correction approved by override: ' || coalesce(q.override_reason, '') || ' · engine: ' || array_to_string(r.reasons, '; '));
    END IF;

    SELECT s.* INTO st FROM people.student s WHERE s.candidate_id = c.id AND s.matric_no IS NULL LIMIT 1;
    IF st.id IS NOT NULL THEN
        SELECT p.due, p.paid INTO v_due_before, v_paid FROM finance.position(st.id, a.session) p;
    END IF;

    -- the admission follows the correction; the programme it was made for stays on the request and the trail
    UPDATE admissions.candidate SET programme = q.to_programme WHERE id = c.id;
    IF st.id IS NOT NULL THEN
        UPDATE people.student SET programme_code = q.to_programme_code WHERE id = st.id;
        -- the courses registered on the old programme are dropped; the registration goes back to the student for the new programme's
        FOR reg IN SELECT x.id, x.status FROM registration.course_registration x WHERE x.student_id = st.id AND x.status <> 'LOCKED' ORDER BY x.session, x.semester LOOP
            UPDATE registration.entry SET status = 'DROPPED' WHERE registration_id = reg.id AND status <> 'DROPPED';
            GET DIAGNOSTICS n = ROW_COUNT;
            v_entries := v_entries + n;
            UPDATE registration.course_registration
               SET status = CASE WHEN reg.status IN ('SUBMITTED', 'APPROVED') THEN 'RETURNED' ELSE reg.status END,
                   approved_at = CASE WHEN reg.status IN ('SUBMITTED', 'APPROVED') THEN NULL ELSE approved_at END,
                   approved_by = CASE WHEN reg.status IN ('SUBMITTED', 'APPROVED') THEN NULL ELSE approved_by END,
                   returned_comment = 'Your admission was corrected from ' || q.from_programme || ' to ' || q.to_programme || '. The courses registered for '
                                      || q.from_programme || ' were dropped: register the courses of ' || q.to_programme || ' and submit again.'
             WHERE id = reg.id;
            v_regs := v_regs + 1;
        END LOOP;
        -- a matriculation number proposed on the old programme is released from its batch; the student is numbered with the new programme's
        FOR mrow IN SELECT br.id FROM people.matric_batch_row br JOIN people.matric_batch b ON b.id = br.batch_id
                     WHERE br.student_id = st.id AND br.state = 'PROPOSED' AND b.state IN ('GENERATED', 'READY_FOR_ISSUANCE') LOOP
            PERFORM people.matric_batch_drop_row(mrow.id, 'Admission corrected to ' || q.to_programme || ' (' || v_reason || ')');
            v_matric := v_matric + 1;
        END LOOP;
        SELECT p.due INTO v_due_after FROM finance.position(st.id, a.session) p;
    END IF;

    UPDATE admissions.programme_change_request
       SET state = 'APPROVED', decided_at = now(), decided_by = p_actor, decided_office = v_office, decision_note = v_note, eligibility_at_decision = r.result,
           fee_session = CASE WHEN st.id IS NOT NULL THEN a.session END, fees_paid = v_paid, fees_due_before = v_due_before, fees_due_after = v_due_after,
           registrations_returned = v_regs, courses_dropped = v_entries, matric_rows_dropped = v_matric
     WHERE id = q.id;

    -- the screening form says so; the documents drawn from the admission are issued again for the new programme
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = a.id;
    IF f.application_id IS NOT NULL THEN
        IF f.state = 'SUCCESSFUL' THEN
            UPDATE admissions.screening_form
               SET remarks = concat_ws(' · ', nullif(remarks, ''), 'Admission corrected from ' || q.from_programme || ' to ' || q.to_programme || ' (' || v_reason || ') on the approval of the ' || v_office),
                   updated_at = now()
             WHERE application_id = a.id;
        END IF;
        PERFORM admissions.screening_log(a.id, 'ADMISSION_CORRECTED', 'From ' || q.from_programme || ' to ' || q.to_programme || ' · ' || v_reason || ' · approved by the ' || v_office
            || CASE WHEN st.id IS NOT NULL THEN ' · school fees paid ' || admissions.naira(v_paid) || ' kept against the new programme' ELSE '' END);
    END IF;
    IF a.accepted_at IS NOT NULL AND EXISTS (SELECT 1 FROM credentials.issued i WHERE i.application_id = a.id AND i.kind = 'ADMISSION_LETTER') THEN
        PERFORM admissions.issue_admission_letter(a.id);
        v_letter := true;
    END IF;
    IF f.state = 'SUCCESSFUL' AND EXISTS (SELECT 1 FROM credentials.issued i WHERE i.application_id = a.id AND i.kind = 'SCREENING_FORMS') THEN
        PERFORM admissions.issue_screening_forms(a.id);
        v_forms := true;
    END IF;
    UPDATE admissions.programme_change_request SET letter_reissued = v_letter, forms_reissued = v_forms WHERE id = q.id;

    PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'ADMISSION_CORRECTED', q.to_programme_code, r.result,
        'From ' || q.from_programme || ' to ' || q.to_programme || ' · ' || v_reason || coalesce(' · ' || v_note, '') || ' · approved by the ' || v_office);
    PERFORM admissions.evaluate_application(q.application_id, 'PROGRAMME_CHANGE', p_actor);

    -- the applicant, the recommending office and — when the fees moved — the Bursary are told
    SELECT p.name, fa.name AS faculty, d.name AS department INTO v_prog
      FROM ref.programme p LEFT JOIN ref.faculty fa ON fa.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code WHERE p.code = q.to_programme_code;
    IF st.id IS NOT NULL AND coalesce(v_paid, 0) > 0 THEN
        v_fees := E'\n\nSchool fees for ' || a.session || E':\nPaid: ' || admissions.naira(v_paid) || E'\nDue on ' || q.to_programme || ': ' || admissions.naira(v_due_after)
                  || CASE WHEN v_due_after > v_paid THEN E'\nBalance to pay: ' || admissions.naira(v_due_after - v_paid) || '. Pay it on the portal.'
                          WHEN v_paid > v_due_after THEN E'\nPaid above the new programme''s fees: ' || admissions.naira(v_paid - v_due_after) || '. The Bursary credits it to your wallet or refunds it.'
                          ELSE E'\nYour payment covers the new programme''s fees.' END;
    END IF;
    IF v_regs > 0 THEN v_more := v_more || E'\n\nYour course registration was returned to you: register the courses of ' || q.to_programme || ' and submit it again.'; END IF;
    IF v_letter THEN v_more := v_more || E'\n\nYour admission letter has been reissued for ' || q.to_programme || '; the earlier letter is no longer valid.'; END IF;
    PERFORM admissions.notify_applicant(a.id, 'Your admission has been corrected: ' || q.to_programme,
        'The University has corrected your admission.' || E'\n\nPrevious programme: ' || q.from_programme || E'\nNew programme: ' || coalesce(v_prog.name, q.to_programme)
        || coalesce(E'\nFaculty: ' || v_prog.faculty, '') || coalesce(E'\nDepartment: ' || v_prog.department, '') || E'\nReason: ' || v_reason
        || v_fees || v_more || E'\n\nYour acceptance fee, already paid, stands and is not paid again.',
        'MOAUM: your admission is corrected to ' || q.to_programme || '. See your portal for the fee position and the next steps.');
    IF q.recommended_office IS NOT NULL THEN
        PERFORM admissions.tell_office(q.recommended_office, 'Admission correction approved',
            c.surname || ', ' || c.other_names || ' (' || c.jamb_reg_no || '): corrected from ' || q.from_programme || ' to ' || q.to_programme || ' by the ' || v_office || '.', a.id);
    END IF;
    IF st.id IS NOT NULL AND coalesce(v_paid, 0) > 0 AND v_due_after IS DISTINCT FROM v_due_before THEN
        PERFORM admissions.tell_office('bursar', 'Admission corrected after school fees: the fee position changed',
            c.surname || ', ' || c.other_names || ' (' || coalesce(st.admission_no, c.jamb_reg_no) || '): corrected from ' || q.from_programme || ' to ' || q.to_programme
            || '. School fees ' || a.session || ': paid ' || admissions.naira(v_paid) || ', due before ' || admissions.naira(v_due_before) || ', due now ' || admissions.naira(v_due_after)
            || CASE WHEN v_paid > v_due_after THEN '. Paid above the new fees: ' || admissions.naira(v_paid - v_due_after) || ' — to credit to the student''s wallet or refund.'
                    WHEN v_due_after > v_paid THEN '. Balance the student now owes: ' || admissions.naira(v_due_after - v_paid) || '.'
                    ELSE '.' END, a.id);
    END IF;
    RETURN 'APPROVED';
END $fn$;

-- ── 7 · the ordinary decision hands a correction on, and records who decided ─────────────────
CREATE OR REPLACE FUNCTION admissions.decide_programme_change(p_req uuid, p_decision text, p_note text, p_actor uuid)
RETURNS text LANGUAGE plpgsql AS $function$
DECLARE q admissions.programme_change_request; a admissions.application; c admissions.candidate; r record; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_prog text; v_fac text; v_dept text;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    SELECT * INTO q FROM admissions.programme_change_request WHERE id = p_req FOR UPDATE;
    IF q.id IS NULL THEN RAISE EXCEPTION 'no such request' USING ERRCODE = '23503'; END IF;
    IF q.state <> 'REQUESTED' THEN RAISE EXCEPTION 'the request is already %', lower(q.state) USING ERRCODE = '23514'; END IF;
    -- an admission correction (V297) is decided on its own terms
    IF q.kind = 'CORRECTION' THEN RETURN admissions.decide_admission_correction(p_req, p_decision, p_note, p_actor); END IF;
    SELECT * INTO a FROM admissions.application WHERE id = q.application_id;
    SELECT * INTO c FROM admissions.candidate WHERE id = q.candidate_id;
    IF p_decision = 'REJECT' THEN
        IF v_note IS NULL THEN RAISE EXCEPTION 'a rejection carries its reason' USING ERRCODE = '23514'; END IF;
        UPDATE admissions.programme_change_request SET state = 'REJECTED', decided_at = now(), decided_by = p_actor, decided_office = v_office, decision_note = v_note WHERE id = q.id;
        PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'PROGRAMME_CHANGE_REJECTED', q.to_programme_code, NULL, v_note);
        PERFORM admissions.notify_applicant(q.application_id, 'Your request to change programme was not approved', 'Your request to move to ' || q.to_programme || ' was not approved by the Admissions Office. Reason: ' || v_note || ' Your application for ' || q.from_programme || ' stands as it was.', NULL);
        RETURN 'REJECTED';
    ELSIF p_decision = 'APPROVE' THEN
        -- after the release a change is a screening decision (V269, V284): while the screening is open, or after an unsuccessful one
        IF a.decision_released_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = a.id AND f.state IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED', 'UNSUCCESSFUL')) THEN
            RAISE EXCEPTION 'the Board''s decision has been released; the programme is not changed under it' USING ERRCODE = '23514',
                  HINT = 'An error found in a released admission is corrected on Programme Changes (an admission correction).';
        END IF;
        -- eligibility read again at the moment of decision
        SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, q.to_programme_code, c.entry_mode);
        IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') AND NOT q.override THEN
            RAISE EXCEPTION 'on the current settings the candidate is no longer eligible for %: %', q.to_programme, array_to_string(r.reasons, '; ') USING ERRCODE = '23514';
        END IF;
        IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN
            -- the authorised override (V284): approved with the engine's verdict on the record, never hidden
            PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'ELIGIBILITY_OVERRIDE_APPLIED', q.to_programme_code, r.result, 'Approved by override: ' || coalesce(q.override_reason, '') || ' · engine: ' || array_to_string(r.reasons, '; '));
        END IF;
        UPDATE admissions.candidate SET programme = q.to_programme WHERE id = c.id;
        -- the student on the register, not yet matriculated, follows the programme (V269); the original stays on the request and the trail
        UPDATE people.student SET programme_code = q.to_programme_code WHERE candidate_id = c.id AND matric_no IS NULL;
        IF EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = a.id AND f.state IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED', 'UNSUCCESSFUL')) THEN
            -- the change is the screening's decision (V284): the record is screened successful on the new programme, the acceptance
            -- fee paid once stands, the forms are generated for the new programme, school fees open
            UPDATE admissions.screening_form
               SET state = 'SUCCESSFUL', decided_at = now(), decided_by = p_actor, decided_office = 'academic', decision_reason = NULL, returned_note = NULL,
                   remarks = concat_ws(' · ', nullif(remarks, ''), 'Programme changed from ' || q.from_programme || ' to ' || q.to_programme || ' on the approval of the change request'
                             || coalesce(' (' || (SELECT rs.label FROM admissions.programme_change_reason rs WHERE rs.code = q.reason_code) || ')', '')),
                   updated_at = now()
             WHERE application_id = a.id;
            UPDATE admissions.application SET cleared_at = coalesce(cleared_at, now()) WHERE id = a.id;
            PERFORM admissions.screening_log(a.id, 'PROGRAMME_CHANGED', 'From ' || q.from_programme || ' to ' || q.to_programme || ' on the approval of the change request; screened successful on the new programme; acceptance fee already paid, not charged again');
            SELECT p.name, f.name, d.name INTO v_prog, v_fac, v_dept FROM ref.programme p LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code WHERE p.code = q.to_programme_code;
            PERFORM admissions.notify_applicant(a.id, 'Programme change approved — next step: school fees',
                'Your programme change has been approved.' || E'\n\nPrevious programme: ' || q.from_programme || E'\nNew programme: ' || coalesce(v_prog, q.to_programme)
                || coalesce(E'\nFaculty: ' || v_fac, '') || coalesce(E'\nDepartment: ' || v_dept, '')
                || E'\n\nYour screening is recorded as successful on the new programme and your screening forms are available on your dashboard. Your acceptance fee, already paid, remains valid and is not paid again. Next step: pay your school fees on the portal.',
                'MOAUM: your change to ' || q.to_programme || ' is approved. Acceptance fee not charged again; next, school fees.');
        END IF;
        UPDATE admissions.programme_change_request SET state = 'APPROVED', decided_at = now(), decided_by = p_actor, decided_office = v_office, decision_note = v_note, eligibility_at_decision = r.result WHERE id = q.id;
        -- an approved change after an unsuccessful screening opens school fees: the register follows it (V278)
        PERFORM admissions.register_when_due(a.id);
        IF EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = a.id AND f.state = 'SUCCESSFUL' AND f.decided_at >= now() - interval '1 minute') THEN
            PERFORM admissions.issue_screening_forms(a.id);
        END IF;
        PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'PROGRAMME_CHANGE_APPROVED', q.to_programme_code, r.result, 'From ' || q.from_programme || ' to ' || q.to_programme || coalesce(' · ' || v_note, ''));
        PERFORM admissions.evaluate_application(q.application_id, 'PROGRAMME_CHANGE', p_actor);
        PERFORM admissions.notify_applicant(q.application_id, 'Your programme has been changed to ' || q.to_programme,
            'The Admissions Office has approved your request: your application is now for ' || q.to_programme || ' (' || r.result || ' on the current admission policy). This is not an offer of admission; the Admissions Board decides in the normal way.' || coalesce(' Note: ' || v_note, ''),
            'MOAUM: your application is now for ' || q.to_programme || '. This is not yet an offer of admission.');
        RETURN 'APPROVED';
    ELSE
        RAISE EXCEPTION 'unknown decision %', p_decision USING ERRCODE = '23514';
    END IF;
END $function$;

-- the ordinary recommendation says where to go once it no longer applies
CREATE OR REPLACE FUNCTION admissions.recommend_programme_change(p_app uuid, p_to text, p_reason text, p_note text, p_actor uuid, p_office text, p_override boolean, p_override_reason text)
RETURNS uuid LANGUAGE plpgsql AS $function$
DECLARE a admissions.application; c admissions.candidate; g ref.programme; rs admissions.programme_change_reason; f admissions.screening_form; r record;
        v_run uuid; v_id uuid; v_from text; v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    SELECT * INTO rs FROM admissions.programme_change_reason WHERE code = p_reason AND active;
    IF rs.code IS NULL THEN RAISE EXCEPTION 'a change of programme carries one of the configured reasons' USING ERRCODE = '23514'; END IF;
    IF rs.requires_note AND v_note IS NULL THEN RAISE EXCEPTION 'the reason "%" is described in a note', rs.label USING ERRCODE = '23514'; END IF;
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    -- after the Board's decision the change is a screening act: while the screening is open, or after an unsuccessful one, once
    IF a.decision_released_at IS NOT NULL AND (f.application_id IS NULL OR f.state NOT IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED', 'UNSUCCESSFUL')) THEN
        RAISE EXCEPTION 'the Board''s decision on this application has been released; the programme is changed only during the University''s screening'
            USING ERRCODE = '23514', HINT = 'A screening already successful is not reopened by a change of programme; an error found in the admission is corrected on Programme Changes.';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.programme_change_request q0 WHERE q0.application_id = p_app AND q0.state = 'APPROVED' AND f.decided_at IS NOT NULL AND q0.decided_at >= f.decided_at) THEN
        RAISE EXCEPTION 'a change of programme has already been approved after the screening' USING ERRCODE = '23514',
              HINT = 'An error found in the admission since is corrected on Programme Changes.';
    END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    SELECT * INTO g FROM ref.programme WHERE code = p_to;
    IF g.code IS NULL OR g.archived THEN RAISE EXCEPTION 'no such active programme %', p_to USING ERRCODE = '23514'; END IF;
    v_from := admissions.programme_code_of(c.programme);
    IF v_from = p_to THEN RAISE EXCEPTION 'that is the programme the candidate holds' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM admissions.programme_change_request q WHERE q.application_id = p_app AND q.state = 'REQUESTED') THEN
        RAISE EXCEPTION 'a change of programme is already recommended and awaits approval' USING ERRCODE = '23514';
    END IF;
    -- the engine, read again now against the session's settings, never from a stale screen
    v_run := admissions.eligibility_current(p_app, p_actor);
    SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, p_to, c.entry_mode);
    IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN
        IF NOT coalesce(p_override, false) THEN
            RAISE EXCEPTION 'the candidate is not eligible for %: %', g.name, array_to_string(r.reasons, '; ') USING ERRCODE = '23514',
                  HINT = 'Only a programme the engine finds the candidate eligible for on the session''s admission settings is recommended; an override is reserved to the Registrar.';
        END IF;
        IF nullif(btrim(coalesce(p_override_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'an eligibility override carries its reason' USING ERRCODE = '23514'; END IF;
    END IF;
    INSERT INTO admissions.programme_change_request (application_id, candidate_id, session, from_programme_code, from_programme, to_programme_code, to_programme, run_id, eligibility_at_request,
                                                     requested_by_kind, requested_by, note, reason_code, recommended_office, override, override_reason, original_eligibility, screening_state_at_request)
    VALUES (p_app, c.id, a.session, v_from, c.programme, p_to, g.name, v_run, r.result, 'OFFICE', p_actor, v_note, rs.code, p_office,
            r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING'), nullif(btrim(coalesce(p_override_reason, '')), ''), r.result, f.state)
    RETURNING id INTO v_id;
    PERFORM admissions.eligibility_log(p_app, v_run, 'PROGRAMME_CHANGE_RECOMMENDED', p_to, r.result,
        'From ' || c.programme || ' to ' || g.name || ' · ' || rs.label || coalesce(' · ' || v_note, '') || ' · by the ' || coalesce(p_office, 'office')
        || CASE WHEN r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN ' · OVERRIDE: ' || coalesce(p_override_reason, '') ELSE '' END);
    IF f.application_id IS NOT NULL THEN
        PERFORM admissions.screening_log(p_app, 'PROGRAMME_CHANGE_RECOMMENDED', 'From ' || c.programme || ' to ' || g.name || ' · ' || rs.label || ' · awaiting approval');
    END IF;
    PERFORM admissions.notify_applicant(p_app, 'Your programme change is under review',
        'During the University''s screening the Academic Office has recommended that your admission be changed from ' || c.programme || ' to ' || g.name
        || ' (' || rs.label || '). The change takes effect only when it is approved; you will be told. Your acceptance fee, already paid, is not paid again.',
        'MOAUM: a change of your programme to ' || g.name || ' is under review; you will be told when it is decided.');
    PERFORM admissions.tell_office('academic', 'A programme change awaits approval',
        'Applicant ' || c.surname || ', ' || c.other_names || ' (' || c.jamb_reg_no || '): the ' || coalesce(p_office, 'office') || ' recommends ' || g.name || ' in place of ' || c.programme
        || ' · ' || rs.label || ' · the engine finds them ' || lower(replace(r.result, '_', ' ')) || CASE WHEN coalesce(p_override, false) THEN ' (override)' ELSE '' END, p_app);
    RETURN v_id;
END $function$;

-- ── 8 · the register ─────────────────────────────────────────────────────────────────────────
/* one row per applicant with an approved change of programme in the session: the programme applied for (the first change's
   "from"), the programme held now, the latest change's reason, stage, recommender and approver, where the admission stands,
   the fee position recorded by a correction and the position today, and every change in order (as JSON text) */
CREATE OR REPLACE FUNCTION admissions.programme_change_register(p_session text)
RETURNS TABLE (application_id uuid, application_no text, jamb_reg_no text, surname text, other_names text, entry_mode text,
               applied_code text, applied_programme text, applied_faculty text, applied_department text,
               current_code text, current_programme text, current_faculty text, current_department text,
               moved boolean, changes integer, change_id uuid, kind text, stage text, reason_code text, reason text, note text,
               requested_by_kind text, recommended_office text, recommended_by text, requested_at timestamptz,
               decided_at timestamptz, decided_by text, decided_office text, decision_note text,
               override boolean, override_reason text, eligibility text, stage_then text, stage_now text,
               fee_session text, fees_paid numeric, fees_due_before numeric, fees_due_after numeric, paid_now numeric, due_now numeric,
               registrations_returned integer, courses_dropped integer, matric_rows_dropped integer, letter_reissued boolean, forms_reissued boolean,
               history text)
LANGUAGE sql STABLE AS $$
    WITH ch AS (
        SELECT q.*,
               coalesce(q.from_programme_code, admissions.programme_code_of(q.from_programme)) AS from_code,
               CASE WHEN q.kind = 'CORRECTION' THEN 'CORRECTION'
                    WHEN q.screening_state_at_request IS NOT NULL THEN 'SCREENING'
                    WHEN q.requested_by_kind = 'APPLICANT' THEN 'APPLICANT_REQUEST'
                    ELSE 'BEFORE_DECISION' END AS change_stage,
               row_number() OVER (PARTITION BY q.application_id ORDER BY q.decided_at, q.requested_at, q.id) AS first_n,
               row_number() OVER (PARTITION BY q.application_id ORDER BY q.decided_at DESC, q.requested_at DESC, q.id DESC) AS last_n,
               count(*) OVER (PARTITION BY q.application_id) AS n
          FROM admissions.programme_change_request q
         WHERE q.session = p_session AND q.state = 'APPROVED'
    )
    SELECT a.id, a.application_no, c.jamb_reg_no, c.surname, c.other_names, c.entry_mode,
           fst.from_code, fst.from_programme, ff.name, fd.name,
           pc.code, c.programme, cf.name, cd.name,
           fst.from_code IS DISTINCT FROM pc.code, lst.n::int,
           lst.id, lst.kind, lst.change_stage, lst.reason_code, coalesce(rs.label, lst.reason_code), lst.note,
           lst.requested_by_kind, lst.recommended_office,
           (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = lst.requested_by), lst.requested_at,
           lst.decided_at, (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = lst.decided_by), lst.decided_office, lst.decision_note,
           lst.override, lst.override_reason, coalesce(lst.eligibility_at_decision, lst.eligibility_at_request), lst.admission_stage, admissions.admission_stage(a.id),
           lst.fee_session, lst.fees_paid, lst.fees_due_before, lst.fees_due_after, pos.paid, pos.due,
           lst.registrations_returned, lst.courses_dropped, lst.matric_rows_dropped, lst.letter_reissued, lst.forms_reissued,
           (SELECT jsonb_agg(jsonb_build_object('id', h.id, 'kind', h.kind, 'stage', h.change_stage, 'from', h.from_programme, 'to', h.to_programme,
                                                'reason', coalesce(r2.label, h.reason_code), 'note', h.note, 'recommendedOffice', h.recommended_office,
                                                'requestedAt', h.requested_at, 'decidedAt', h.decided_at, 'decidedOffice', h.decided_office,
                                                'override', h.override, 'overrideReason', h.override_reason) ORDER BY h.decided_at, h.requested_at)
              FROM ch h LEFT JOIN admissions.programme_change_reason r2 ON r2.code = h.reason_code WHERE h.application_id = a.id)::text
      FROM ch lst
      JOIN ch fst ON fst.application_id = lst.application_id AND fst.first_n = 1
      JOIN admissions.application a ON a.id = lst.application_id
      JOIN admissions.candidate c ON c.id = a.candidate_id
      LEFT JOIN ref.programme fp ON fp.code = fst.from_code
      LEFT JOIN ref.faculty ff ON ff.code = fp.faculty_code
      LEFT JOIN ref.department fd ON fd.code = fp.dept_code
      LEFT JOIN ref.programme pc ON pc.code = admissions.programme_code_of(c.programme)
      LEFT JOIN ref.faculty cf ON cf.code = pc.faculty_code
      LEFT JOIN ref.department cd ON cd.code = pc.dept_code
      LEFT JOIN admissions.programme_change_reason rs ON rs.code = lst.reason_code
      LEFT JOIN LATERAL (SELECT s.id FROM people.student s WHERE s.candidate_id = c.id ORDER BY s.matric_no NULLS LAST LIMIT 1) st ON true
      LEFT JOIN LATERAL (SELECT p.paid, p.due FROM finance.position(st.id, a.session) p) pos ON st.id IS NOT NULL
     WHERE lst.last_n = 1
     ORDER BY c.surname, c.other_names, a.application_no;
$$;
COMMENT ON FUNCTION admissions.programme_change_register(text) IS
  'V297: one row per applicant whose programme was changed in the session — applied for, held now, why, at what stage, by whom — with the fee position a correction recorded and every change in order.';

COMMIT;
