-- ═══════════════════════════════════════════════════════════════════════════
-- V264 · Deferment, revised: the fee before the form, the Bursary first, the
--        DVC's word, the Senate Business Committee's act — and what an approved
--        deferment does to the academic record
--
--   V259 gave the University deferment on the record: the request, the desks
--   (department → faculty → Registry), the period held on every register, the
--   return. The Registry's revised procedure (September 2026) changes the
--   approval and adds the academic consequence, and both are enforced here, in
--   the database, whatever any screen shows:
--
--     · the DEFERMENT APPLICATION FEE (₦10,000 today; the Bursary states it) is
--       paid through the University's own payment reference before the form
--       opens; only a CONFIRMED payment opens it;
--     · the chain is Bursary (the last school-fee payment and the balance read
--       from the finance record, never typed) → Head of Department → Faculty →
--       Academic Office (sees every stage; downloads only what the faculty has
--       approved; forwards the approved list to the DVC in a numbered batch) →
--       DVC (with a comment) → WAITING SBC ACTION → the Senate Business
--       Committee's final act; each desk acts at its own stage only, and the
--       office is checked here as well as at the door;
--     · an approved deferment is not a failure: the courses of the deferred
--       period are marked DEFERRED (never F, never zero, never a carry-over),
--       the GPA and CGPA are untouched, the programme's expected completion is
--       extended by exactly the period deferred (the original duration and the
--       entry session are never overwritten), and when the student returns the
--       deferred courses become due courses on the registration form, distinct
--       from carry-overs and from the current courses.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V264: deferment workflow and academic effect', true);

-- ── 1 · the fee: stated by the Bursary, paid through the existing reference ─

ALTER TABLE people.deferment_setting
    ADD COLUMN IF NOT EXISTS fee            numeric(12,2) NOT NULL DEFAULT 10000,
    ADD COLUMN IF NOT EXISTS fee_updated_at timestamptz NULL,
    ADD COLUMN IF NOT EXISTS fee_updated_by uuid NULL,
    ADD CONSTRAINT ck_defset_fee CHECK (fee >= 0);

CREATE TABLE people.deferment_fee (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id    uuid NOT NULL REFERENCES people.student(id),
    session       text NOT NULL,
    reference     text NOT NULL UNIQUE REFERENCES finance.payment_reference(reference),
    amount        numeric(12,2) NOT NULL,
    state         text NOT NULL DEFAULT 'PENDING',
    created_at    timestamptz NOT NULL DEFAULT now(),
    confirmed_at  timestamptz NULL,
    receipt_no    text NULL,
    used_by       uuid NULL REFERENCES people.deferment(id),
    CONSTRAINT ck_deffee_state CHECK (state IN ('PENDING','CONFIRMED','EXPIRED','CANCELLED'))
);
CREATE INDEX ix_deferment_fee_student ON people.deferment_fee (student_id, created_at DESC);
SELECT audit.attach('people.deferment_fee');
COMMENT ON TABLE people.deferment_fee IS 'The deferment application fee: one payment reference per attempt, CONFIRMED by the same confirmation as every other payment, spent by one request.';

-- ── 2 · the request: the new stages, each desk''s word, the batch, the effect ─

ALTER TABLE people.deferment
    ADD COLUMN IF NOT EXISTS fee_id                    uuid NULL REFERENCES people.deferment_fee(id),
    ADD COLUMN IF NOT EXISTS bursary_at                timestamptz NULL,
    ADD COLUMN IF NOT EXISTS bursary_by                uuid NULL REFERENCES iam.person(id),
    ADD COLUMN IF NOT EXISTS bursary_note              text NULL,
    ADD COLUMN IF NOT EXISTS bursary_last_fee_amount   numeric(12,2) NULL,
    ADD COLUMN IF NOT EXISTS bursary_last_fee_ref      text NULL,
    ADD COLUMN IF NOT EXISTS bursary_last_fee_at       timestamptz NULL,
    ADD COLUMN IF NOT EXISTS bursary_last_fee_session  text NULL,
    ADD COLUMN IF NOT EXISTS bursary_balance           numeric(12,2) NULL,
    ADD COLUMN IF NOT EXISTS bursary_balance_session   text NULL,
    ADD COLUMN IF NOT EXISTS batch_id                  uuid NULL,
    ADD COLUMN IF NOT EXISTS forwarded_at              timestamptz NULL,
    ADD COLUMN IF NOT EXISTS forwarded_by              uuid NULL REFERENCES iam.person(id),
    ADD COLUMN IF NOT EXISTS dvc_at                    timestamptz NULL,
    ADD COLUMN IF NOT EXISTS dvc_by                    uuid NULL REFERENCES iam.person(id),
    ADD COLUMN IF NOT EXISTS dvc_note                  text NULL,
    ADD COLUMN IF NOT EXISTS returned_from_state       text NULL,
    ADD COLUMN IF NOT EXISTS returned_by_office        text NULL,
    ADD COLUMN IF NOT EXISTS extension_semesters       int NULL,
    ADD COLUMN IF NOT EXISTS courses_affected          int NULL,
    ADD COLUMN IF NOT EXISTS effect_applied_at         timestamptz NULL;

ALTER TABLE people.deferment DROP CONSTRAINT IF EXISTS ck_def_state;
ALTER TABLE people.deferment ADD CONSTRAINT ck_def_state CHECK (state IN (
    'DRAFT','SUBMITTED','CORRECTION_REQUIRED','BURSARY_APPROVED','DEPT_RECOMMENDED','FAC_RECOMMENDED','FORWARDED_TO_DVC','DVC_APPROVED',
    'APPROVED','ACTIVE','COMPLETED','REJECTED','CANCELLED'));

CREATE TABLE people.deferment_batch (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference     text NOT NULL UNIQUE,
    session       text NULL,
    semester      int  NULL,
    forwarded_at  timestamptz NOT NULL DEFAULT now(),
    forwarded_by  uuid NULL REFERENCES iam.person(id),
    office        text NULL,
    note          text NULL,
    count         int NOT NULL DEFAULT 0,
    CONSTRAINT ck_defbatch_ref CHECK (reference ~ '^DEF-DVC-[0-9]{4}-[0-9]{5}$')
);
SELECT audit.attach('people.deferment_batch');
ALTER TABLE people.deferment ADD CONSTRAINT fk_deferment_batch FOREIGN KEY (batch_id) REFERENCES people.deferment_batch(id);
CREATE INDEX ix_deferment_batch ON people.deferment (batch_id) WHERE batch_id IS NOT NULL;

/* the courses an approved deferment set aside: never failed, due again when the student returns */
CREATE TABLE people.deferred_course (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    deferment_id       uuid NOT NULL REFERENCES people.deferment(id),
    student_id         uuid NOT NULL REFERENCES people.student(id),
    course_code        text NOT NULL REFERENCES catalogue.course(code),
    offering_id        uuid NULL REFERENCES catalogue.offering(id),
    units              int  NOT NULL,
    entry_type         text NULL,
    original_session   text NOT NULL,
    original_semester  int  NOT NULL,
    source             text NOT NULL,
    created_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_defcourse_source CHECK (source IN ('REGISTRATION','CURRICULUM')),
    UNIQUE (deferment_id, course_code)
);
CREATE INDEX ix_deferred_course_student ON people.deferred_course (student_id);
SELECT audit.attach('people.deferred_course');
COMMENT ON TABLE people.deferred_course IS 'A course of a deferred period, as the record held it (the registration, else the curriculum): DEFERRED, not FAILED; due on the return.';

-- the register: an entry set aside by a deferment is DEFERRED, a course due from a deferment is registered as DEFERRED (not a carry-over)
ALTER TABLE registration.entry DROP CONSTRAINT IF EXISTS ck_entry_status;
ALTER TABLE registration.entry ADD CONSTRAINT ck_entry_status CHECK (status IN ('REGISTERED','DROPPED','APPROVED','WITHDRAWN','DEFERRED'));
ALTER TABLE registration.entry DROP CONSTRAINT IF EXISTS ck_entry_type;
ALTER TABLE registration.entry ADD CONSTRAINT ck_entry_type CHECK (entry_type IN ('CURRENT','CARRYOVER','REPEAT','ELECTIVE','GST','BORROWED','DEFERRED'));

-- ── 3 · the words: what each state is called, and whose desk it waits at ──

CREATE OR REPLACE FUNCTION people.deferment_stage_label(p_state text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_state
        WHEN 'DRAFT' THEN 'DRAFT'
        WHEN 'SUBMITTED' THEN 'WAITING BURSARY ACTION'
        WHEN 'BURSARY_APPROVED' THEN 'WAITING HOD ACTION'
        WHEN 'DEPT_RECOMMENDED' THEN 'WAITING FACULTY ACTION'
        WHEN 'FAC_RECOMMENDED' THEN 'WAITING ACADEMIC OFFICE ACTION'
        WHEN 'FORWARDED_TO_DVC' THEN 'FORWARDED TO DVC'
        WHEN 'DVC_APPROVED' THEN 'WAITING SBC ACTION'
        WHEN 'APPROVED' THEN 'APPROVED'
        WHEN 'ACTIVE' THEN 'APPROVED · IN FORCE'
        WHEN 'COMPLETED' THEN 'COMPLETED'
        WHEN 'REJECTED' THEN 'REJECTED'
        WHEN 'CORRECTION_REQUIRED' THEN 'RETURNED FOR CORRECTION'
        WHEN 'CANCELLED' THEN 'CANCELLED'
        ELSE p_state END;
$$;

/* the offices whose act a state waits for (super may act at every stage) */
CREATE OR REPLACE FUNCTION people.deferment_stage_offices(p_state text)
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_state
        WHEN 'SUBMITTED' THEN ARRAY['bursar']
        WHEN 'BURSARY_APPROVED' THEN ARRAY['hod']
        WHEN 'DEPT_RECOMMENDED' THEN ARRAY['dean','facultyofficer']
        WHEN 'FAC_RECOMMENDED' THEN ARRAY['academic','registrar','dregistrar']
        WHEN 'FORWARDED_TO_DVC' THEN ARRAY['dvc']
        WHEN 'DVC_APPROVED' THEN ARRAY['registrar','dregistrar']
        ELSE ARRAY[]::text[] END;
$$;

CREATE OR REPLACE FUNCTION people.deferment_stage_office_label(p_state text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_state
        WHEN 'SUBMITTED' THEN 'Bursary' WHEN 'BURSARY_APPROVED' THEN 'Head of Department' WHEN 'DEPT_RECOMMENDED' THEN 'Faculty'
        WHEN 'FAC_RECOMMENDED' THEN 'Academic Office' WHEN 'FORWARDED_TO_DVC' THEN 'Deputy Vice-Chancellor (Academic)' WHEN 'DVC_APPROVED' THEN 'Senate Business Committee'
        WHEN 'CORRECTION_REQUIRED' THEN 'Student' WHEN 'DRAFT' THEN 'Student' ELSE NULL END;
$$;

CREATE OR REPLACE FUNCTION people.deferment_office_may(p_office text, p_state text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT p_office = 'super' OR p_office = ANY (people.deferment_stage_offices(p_state));
$$;

-- ── 4 · the fee before the form ───────────────────────────────────────────

/* the student's fee as it stands: the latest attempt, its state read against the reference's expiry */
CREATE OR REPLACE FUNCTION people.deferment_fee_view(p_student uuid)
RETURNS TABLE (id uuid, reference text, amount numeric, state text, created_at timestamptz, expires_at timestamptz, confirmed_at timestamptz, receipt_no text, used_by uuid, fee_now numeric)
LANGUAGE sql STABLE AS $$
    SELECT f.id, f.reference, f.amount,
           CASE WHEN f.state = 'PENDING' AND pr.expires_at < now() THEN 'EXPIRED' ELSE f.state END,
           f.created_at, pr.expires_at, f.confirmed_at, f.receipt_no, f.used_by,
           (SELECT fee FROM people.deferment_setting WHERE id = 1)
      FROM people.deferment_fee f JOIN finance.payment_reference pr ON pr.reference = f.reference
     WHERE f.student_id = p_student
     ORDER BY (f.state = 'CONFIRMED' AND f.used_by IS NULL) DESC, f.created_at DESC
     LIMIT 1;
$$;

/* the reference for the fee: a confirmed unspent one is returned, a live pending one is returned, else a new one is generated */
CREATE OR REPLACE FUNCTION people.deferment_fee_start(p_student uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE e record; st people.deferment_setting; v record; v_ref text; v_id uuid; v_session text;
BEGIN
    SELECT * INTO e FROM people.deferment_eligibility(p_student);
    IF NOT e.eligible THEN RAISE EXCEPTION '%', e.reason USING ERRCODE = '23514', HINT = 'Deferment request not available.'; END IF;
    SELECT * INTO st FROM people.deferment_setting WHERE id = 1;
    SELECT * INTO v FROM people.deferment_fee_view(p_student);
    IF v.id IS NOT NULL AND v.state = 'CONFIRMED' AND v.used_by IS NULL THEN RETURN v.id; END IF;
    IF v.id IS NOT NULL AND v.state = 'PENDING' THEN RETURN v.id; END IF;
    IF st.fee <= 0 THEN
        -- no fee stated: the attempt is recorded as confirmed without a payment, so the same door opens
        v_session := coalesce((SELECT name FROM policy.academic_session WHERE state = 'CURRENT'), to_char(now(), 'YYYY') || '/' || to_char(now() + interval '1 year', 'YYYY'));
        v_ref := finance.new_purpose_reference(p_student, v_session, 1, 'Deferment application fee (waived)');
        INSERT INTO people.deferment_fee (student_id, session, reference, amount, state, confirmed_at) VALUES (p_student, v_session, v_ref, 0, 'CONFIRMED', now()) RETURNING id INTO v_id;
        RETURN v_id;
    END IF;
    v_session := coalesce((SELECT name FROM policy.academic_session WHERE state = 'CURRENT'), (SELECT entry_session FROM people.student WHERE id = p_student));
    v_ref := finance.new_purpose_reference(p_student, v_session, st.fee, 'Deferment application fee');
    INSERT INTO people.deferment_fee (student_id, session, reference, amount) VALUES (p_student, v_session, v_ref, st.fee) RETURNING id INTO v_id;
    RETURN v_id;
END $$;

/* the confirmation of the reference (finance.confirm_payment, whichever door it came through) confirms the fee */
CREATE OR REPLACE FUNCTION people.deferment_fee_confirmed()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE f people.deferment_fee; reach record;
BEGIN
    IF NEW.confirmed_at IS NOT NULL AND OLD.confirmed_at IS NULL AND NEW.purpose LIKE 'Deferment application fee%' THEN
        UPDATE people.deferment_fee SET state = 'CONFIRMED', confirmed_at = NEW.confirmed_at, receipt_no = NEW.receipt_no
         WHERE reference = NEW.reference AND state = 'PENDING' RETURNING * INTO f;
        IF f.id IS NOT NULL THEN
            IF f.used_by IS NOT NULL THEN PERFORM people.deferment_log(f.used_by, 'FEE_PAID', NULL, NULL, 'Deferment application fee confirmed · ' || NEW.reference || ' · receipt ' || coalesce(NEW.receipt_no, '')); END IF;
            SELECT * INTO reach FROM people.student_reach(f.student_id);
            PERFORM platform.queue_notice('EMAIL', reach.email, 'Your deferment application fee is confirmed',
                'Your deferment application fee of NGN ' || f.amount::text || ' is confirmed (receipt ' || coalesce(NEW.receipt_no, '') || '). The deferment application form is now open to you on the portal: complete it and submit it to the Bursary.'
                || E'\n\nOffice of the Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi', 'student', f.student_id);
            PERFORM platform.queue_notice('SMS', reach.phone, 'Your deferment application fee is confirmed', 'MOAUM: deferment fee confirmed, receipt ' || coalesce(NEW.receipt_no, '') || '. The application form is open on the portal.', 'student', f.student_id);
        END IF;
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_deferment_fee_confirmed ON finance.payment_reference;
CREATE TRIGGER trg_deferment_fee_confirmed AFTER UPDATE OF confirmed_at ON finance.payment_reference
FOR EACH ROW EXECUTE FUNCTION people.deferment_fee_confirmed();

-- ── 5 · the request: opened on a confirmed fee; resubmitted to the desk that returned it ─

CREATE OR REPLACE FUNCTION people.deferment_save(p_student uuid, p_id uuid, p_kind text, p_session text, p_semester int, p_reason text, p_explanation text, p_declared boolean, p_extension_of uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE d people.deferment; e record; v_id uuid; v_sem int; v_ret record; st people.deferment_setting; fee record;
BEGIN
    SELECT * INTO st FROM people.deferment_setting WHERE id = 1;
    SELECT * INTO e FROM people.deferment_eligibility(p_student);
    v_sem := CASE WHEN p_kind = 'SEMESTER' THEN p_semester ELSE NULL END;
    IF p_kind NOT IN ('SEMESTER','SESSION') THEN RAISE EXCEPTION 'a deferment is of a semester or of a session' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN RAISE EXCEPTION 'no such session %', p_session USING ERRCODE = '23514'; END IF;
    IF p_kind = 'SEMESTER' AND (v_sem IS NULL OR v_sem > coalesce((SELECT semesters FROM policy.academic_session WHERE name = p_session), 2)) THEN
        RAISE EXCEPTION 'choose the semester of % to defer', p_session USING ERRCODE = '23514';
    END IF;
    IF p_session < (SELECT name FROM policy.academic_session WHERE state = 'CURRENT') THEN
        RAISE EXCEPTION 'a session that has passed is not deferred' USING ERRCODE = '23514', HINT = 'Choose the current session or a coming one.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM people.deferment_reason WHERE code = p_reason AND active) THEN RAISE EXCEPTION 'choose a reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO v_ret FROM people.deferment_return(p_kind, p_session, v_sem);
    IF p_id IS NULL THEN
        IF NOT e.eligible THEN RAISE EXCEPTION '%', e.reason USING ERRCODE = '23514', HINT = 'Deferment request not available.'; END IF;
        -- the fee before the form: a CONFIRMED, unspent payment of the deferment application fee
        SELECT * INTO fee FROM people.deferment_fee_view(p_student);
        IF fee.id IS NULL OR fee.state <> 'CONFIRMED' OR fee.used_by IS NOT NULL THEN
            RAISE EXCEPTION 'the deferment application fee of NGN % is paid before the application form opens', st.fee USING ERRCODE = '23514',
                  HINT = 'Generate the fee reference on the Deferment screen, pay it, and the form opens the moment the payment is confirmed.';
        END IF;
        IF p_extension_of IS NOT NULL THEN
            IF NOT st.allow_extension THEN RAISE EXCEPTION 'an extension of a deferment is not granted' USING ERRCODE = '23514'; END IF;
            IF NOT EXISTS (SELECT 1 FROM people.deferment x WHERE x.id = p_extension_of AND x.student_id = p_student AND x.state IN ('ACTIVE','APPROVED')) THEN
                RAISE EXCEPTION 'an extension follows a deferment in force' USING ERRCODE = '23514';
            END IF;
        END IF;
        IF (people.deferment_used(p_student) + (CASE WHEN p_kind = 'SESSION' THEN 1 ELSE 0.5 END)) > st.max_sessions THEN
            RAISE EXCEPTION 'this would take your deferments to more than the % session(s) the University allows', st.max_sessions USING ERRCODE = '23514';
        END IF;
        INSERT INTO people.deferment (reference, student_id, kind, session, semester, reason_code, explanation, declared, extension_of,
                                      period_from, return_session, return_semester, return_on, fee_id)
        VALUES (people.deferment_new_reference(), p_student, p_kind, p_session, v_sem, p_reason, nullif(btrim(coalesce(p_explanation, '')), ''), coalesce(p_declared, false), p_extension_of,
                people.period_start(p_session, v_sem), v_ret.return_session, v_ret.return_semester, v_ret.return_on, fee.id)
        RETURNING id INTO v_id;
        UPDATE people.deferment_fee SET used_by = v_id WHERE id = fee.id;
        PERFORM people.deferment_log(v_id, 'FEE_PAID', NULL, NULL, 'Deferment application fee NGN ' || fee.amount::text || ' confirmed ' || to_char(fee.confirmed_at, 'DD Mon YYYY') || ' · ' || fee.reference || coalesce(' · receipt ' || fee.receipt_no, ''));
        PERFORM people.deferment_log(v_id, 'CREATED', NULL, 'DRAFT', 'Request opened for ' || p_session || coalesce(' semester ' || v_sem, ''));
        RETURN v_id;
    END IF;
    SELECT * INTO d FROM people.deferment WHERE id = p_id AND student_id = p_student FOR UPDATE;
    IF d.id IS NULL THEN RAISE EXCEPTION 'no such deferment request' USING ERRCODE = '23503'; END IF;
    IF d.state NOT IN ('DRAFT','CORRECTION_REQUIRED') THEN RAISE EXCEPTION 'the request is %; it is no longer yours to change', lower(replace(d.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
    UPDATE people.deferment SET kind = p_kind, session = p_session, semester = v_sem, reason_code = p_reason,
           explanation = nullif(btrim(coalesce(p_explanation, '')), ''), declared = coalesce(p_declared, false),
           period_from = people.period_start(p_session, v_sem), return_session = v_ret.return_session, return_semester = v_ret.return_semester, return_on = v_ret.return_on,
           updated_at = now()
     WHERE id = d.id;
    PERFORM people.deferment_log(d.id, 'UPDATED', d.state, d.state, NULL);
    RETURN d.id;
END $$;

CREATE OR REPLACE FUNCTION people.deferment_submit(p_student uuid, p_id uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE d people.deferment; r people.deferment_reason; v_docs int; v_to text; fee record;
BEGIN
    SELECT * INTO d FROM people.deferment WHERE id = p_id AND student_id = p_student FOR UPDATE;
    IF d.id IS NULL THEN RAISE EXCEPTION 'no such deferment request' USING ERRCODE = '23503'; END IF;
    IF d.state NOT IN ('DRAFT','CORRECTION_REQUIRED') THEN RETURN 'already ' || lower(replace(d.state, '_', ' ')); END IF;
    SELECT * INTO r FROM people.deferment_reason WHERE code = d.reason_code;
    IF (r.needs_words OR d.reason_code = 'OTHER') AND coalesce(length(d.explanation), 0) < 20 THEN
        RAISE EXCEPTION 'explain the reason in a few sentences' USING ERRCODE = '23514', HINT = 'At least twenty characters.';
    END IF;
    SELECT count(*) INTO v_docs FROM people.deferment_document WHERE deferment_id = d.id;
    IF r.needs_document AND v_docs = 0 THEN
        RAISE EXCEPTION 'a % deferment is supported by a document', lower(r.label) USING ERRCODE = '23514', HINT = 'Upload the medical report, letter or evidence, then submit.';
    END IF;
    IF NOT d.declared THEN RAISE EXCEPTION 'confirm the declaration before submitting' USING ERRCODE = '23514'; END IF;
    -- the fee is confirmed (a request opened before V264 carries none; it is submitted as it was)
    IF d.fee_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM people.deferment_fee f WHERE f.id = d.fee_id AND f.state = 'CONFIRMED') THEN
        RAISE EXCEPTION 'the deferment application fee is not confirmed' USING ERRCODE = '23514', HINT = 'The form is submitted once the payment is confirmed.';
    END IF;
    -- a corrected request goes back to the desk that returned it; a new one to the Bursary
    v_to := CASE WHEN d.state = 'CORRECTION_REQUIRED' AND d.returned_from_state IN ('SUBMITTED','BURSARY_APPROVED','DEPT_RECOMMENDED','FAC_RECOMMENDED','FORWARDED_TO_DVC','DVC_APPROVED')
                 THEN d.returned_from_state ELSE 'SUBMITTED' END;
    UPDATE people.deferment SET state = v_to, submitted_at = coalesce(submitted_at, now()), correction_note = NULL, updated_at = now() WHERE id = d.id;
    PERFORM people.deferment_log(d.id, CASE WHEN d.state = 'CORRECTION_REQUIRED' THEN 'RESUBMITTED' ELSE 'SUBMITTED' END, d.state, v_to, NULL);
    IF v_to = 'SUBMITTED' THEN
        PERFORM people.deferment_tell(d.id, 'Your deferment request has been received',
            'Your request to defer ' || d.session || coalesce(' semester ' || d.semester, ' (the whole session)') || ' has been submitted. It is with the Bursary for financial verification; you will be told at each turn.');
        PERFORM people.deferment_tell_desk(d.id, 'bursar', 'A deferment request awaits financial verification',
            'A student has submitted a deferment request with the application fee paid. Open the deferments desk on the portal to verify the last school-fee payment and decide.');
    ELSE
        PERFORM people.deferment_tell(d.id, 'Your corrected deferment request has been received',
            'Your corrected request ' || d.reference || ' is back with the ' || people.deferment_stage_office_label(v_to) || '. You will be told of the decision.');
        PERFORM people.deferment_tell_desk(d.id, (people.deferment_stage_offices(v_to))[1], 'A corrected deferment request is back at your desk',
            'The student has corrected and resubmitted deferment request ' || d.reference || '. Open the deferments desk to decide.');
    END IF;
    RETURN 'submitted';
END $$;

-- ── 6 · the programme timeline: the original duration, the approved extension, the adjusted completion ─

CREATE OR REPLACE FUNCTION people.session_plus(p_session text, p_years int)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT (left(p_session, 4)::int + p_years)::text || '/' || (left(p_session, 4)::int + p_years + 1)::text;
$$;

/* the day a period ends: the semester's examinations or lectures, else the session's end (or its first half) */
CREATE OR REPLACE FUNCTION people.period_end(p_session text, p_semester int)
RETURNS date LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT coalesce(sm.exams_to, sm.lectures_to) FROM policy.semester sm WHERE sm.session = p_session AND sm.number = p_semester),
        CASE WHEN p_semester >= coalesce((SELECT semesters FROM policy.academic_session WHERE name = p_session), 2)
             THEN (SELECT ends_on FROM policy.academic_session WHERE name = p_session)
             ELSE (SELECT (starts_on + interval '5 months')::date FROM policy.academic_session WHERE name = p_session) END,
        CASE WHEN p_semester >= 2 THEN make_date(left(p_session, 4)::int + 1, 8, 31) ELSE make_date(left(p_session, 4)::int + 1, 2, 28) END);
$$;

/* the semesters an approved deferment adds: a session its semesters, a semester one */
CREATE OR REPLACE FUNCTION people.deferment_semesters(p_kind text, p_session text)
RETURNS int LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN p_kind = 'SESSION' THEN coalesce((SELECT semesters FROM policy.academic_session WHERE name = p_session), 2) ELSE 1 END;
$$;

/* the student's programme timeline: computed, never typed — the original never overwritten, the extension only from approved deferments */
CREATE OR REPLACE FUNCTION people.programme_timeline(p_student uuid)
RETURNS TABLE (entry_session text, entry_level int, final_level int, semesters_per_session int,
               original_semesters int, original_completion_session text, original_completion_semester int, original_completion_on date,
               approved_semesters int, approved_sessions numeric, approved_count int,
               adjusted_semesters int, adjusted_completion_session text, adjusted_completion_semester int, adjusted_completion_on date,
               live_state text, live_return_session text, live_return_semester int, live_return_on date)
LANGUAGE plpgsql STABLE AS $$
DECLARE s people.student; v_final int; v_sps int; v_years int; v_orig int; v_ext int := 0; v_n int := 0; v_idx int; live people.deferment;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF s.id IS NULL THEN RETURN; END IF;
    v_final := coalesce(finance.final_level(s.programme_code), 400);
    v_sps := coalesce((SELECT a.semesters FROM policy.academic_session a WHERE a.name = s.entry_session), 2);
    v_years := greatest((v_final - coalesce(s.entry_level, 100)) / 100 + 1, 1);
    v_orig := v_years * v_sps;
    SELECT coalesce(sum(coalesce(d.extension_semesters, people.deferment_semesters(d.kind, d.session))), 0), count(*)
      INTO v_ext, v_n
      FROM people.deferment d WHERE d.student_id = p_student AND d.state IN ('APPROVED','ACTIVE','COMPLETED');
    SELECT * INTO live FROM people.deferment d WHERE d.student_id = p_student AND d.state IN ('APPROVED','ACTIVE') ORDER BY d.return_on DESC NULLS LAST LIMIT 1;
    v_idx := v_orig + v_ext - 1;   -- zero-based index of the last semester, counted from the entry session's first
    RETURN QUERY SELECT s.entry_session, s.entry_level, v_final, v_sps,
        v_orig, people.session_plus(s.entry_session, v_years - 1), v_sps, people.period_end(people.session_plus(s.entry_session, v_years - 1), v_sps),
        v_ext, round(v_ext::numeric / v_sps, 1), v_n,
        v_orig + v_ext, people.session_plus(s.entry_session, v_idx / v_sps), (v_idx % v_sps) + 1, people.period_end(people.session_plus(s.entry_session, v_idx / v_sps), (v_idx % v_sps) + 1),
        live.state, live.return_session, live.return_semester, live.return_on;
END $$;

-- ── 7 · the academic effect of a final approval ───────────────────────────

/* the courses of the deferred period: the student's own registration where one exists, else the curriculum for their level and the
   semester (core and general studies; an elective is a choice, not a debt); marked DEFERRED, never failed */
CREATE OR REPLACE FUNCTION people.deferment_apply_effect(p_id uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE d people.deferment; s people.student; v_sems int; v_sem int; v_level int; reg registration.course_registration; n int := 0; m int; e record; c record;
        tl_after record; v_ext int;
BEGIN
    SELECT * INTO d FROM people.deferment WHERE id = p_id FOR UPDATE;
    IF d.effect_applied_at IS NOT NULL THEN RETURN d.courses_affected; END IF;
    SELECT * INTO s FROM people.student WHERE id = d.student_id;
    v_sems := coalesce((SELECT semesters FROM policy.academic_session WHERE name = d.session), 2);
    v_level := coalesce((SELECT en.level FROM people.enrolment en WHERE en.student_id = s.id AND en.session = d.session), s.current_level);
    FOR v_sem IN 1..v_sems LOOP
        IF d.kind = 'SEMESTER' AND v_sem <> d.semester THEN CONTINUE; END IF;
        m := 0;
        SELECT * INTO reg FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = d.session AND r.semester = v_sem;
        IF reg.id IS NOT NULL THEN
            FOR e IN SELECT en.*, o.course_code FROM registration.entry en JOIN catalogue.offering o ON o.id = en.offering_id
                      WHERE en.registration_id = reg.id AND en.status IN ('REGISTERED','APPROVED') LOOP
                UPDATE registration.entry SET status = 'DEFERRED' WHERE registration_id = e.registration_id AND offering_id = e.offering_id;
                INSERT INTO people.deferred_course (deferment_id, student_id, course_code, offering_id, units, entry_type, original_session, original_semester, source)
                VALUES (d.id, s.id, e.course_code, e.offering_id, e.units, e.entry_type, d.session, v_sem, 'REGISTRATION')
                ON CONFLICT (deferment_id, course_code) DO NOTHING;
                m := m + 1;
            END LOOP;
        END IF;
        IF m = 0 THEN
            FOR c IN SELECT DISTINCT ON (cc.code) cc.code, cc.units
                       FROM catalogue.course_offer co
                       JOIN catalogue.course cc ON cc.code = co.course_code AND cc.state <> 'ENDED' AND cc.code NOT LIKE 'DMO %'
                      WHERE co.programme_code = s.programme_code AND co.level = v_level
                        AND (co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
                        AND (cc.curriculum IS NULL OR s.curriculum_version IS NULL OR cc.curriculum = s.curriculum_version)
                        AND cc.semester = v_sem
                        AND coalesce(co.basis, cc.kind) IN ('Core','GST','Compulsory','Required')
                      ORDER BY cc.code LOOP
                INSERT INTO people.deferred_course (deferment_id, student_id, course_code, units, original_session, original_semester, source)
                VALUES (d.id, s.id, c.code, c.units, d.session, v_sem, 'CURRICULUM')
                ON CONFLICT (deferment_id, course_code) DO NOTHING;
                m := m + 1;
            END LOOP;
        END IF;
        n := n + m;
    END LOOP;
    v_ext := people.deferment_semesters(d.kind, d.session);
    UPDATE people.deferment SET extension_semesters = v_ext, courses_affected = n, effect_applied_at = now(), updated_at = now() WHERE id = d.id;
    SELECT * INTO tl_after FROM people.programme_timeline(s.id);
    PERFORM people.deferment_log(d.id, 'EFFECT_APPLIED', 'APPROVED', 'APPROVED',
        'Period ' || d.session || coalesce(' semester ' || d.semester, ' (whole session)') || ' marked DEFERRED · ' || n || ' course(s) set aside, none failed · '
        || 'programme timeline +' || v_ext || ' semester(s): ' || tl_after.original_semesters || ' → ' || tl_after.adjusted_semesters
        || ' semesters, expected completion ' || tl_after.original_completion_session || ' semester ' || tl_after.original_completion_semester
        || ' → ' || tl_after.adjusted_completion_session || ' semester ' || tl_after.adjusted_completion_semester
        || ' · entry session ' || s.entry_session || ' and matriculation number unchanged');
    RETURN n;
END $$;

/* the courses a student holds as DEFERRED, with where each stands now: still deferred, registered again, or completed */
CREATE OR REPLACE FUNCTION people.deferred_courses(p_student uuid)
RETURNS TABLE (id uuid, deferment_id uuid, reference text, deferment_state text, course_code text, title text, units int, original_session text, original_semester int,
               source text, status text, taken_session text, taken_semester int, grade text, due boolean)
LANGUAGE sql STABLE AS $$
    WITH dc AS (
        SELECT x.*, d.reference, d.state AS dstate, d.return_session, d.return_semester, d.return_on
          FROM people.deferred_course x JOIN people.deferment d ON d.id = x.deferment_id
         WHERE x.student_id = p_student AND d.state IN ('APPROVED','ACTIVE','COMPLETED')),
    later AS (
        SELECT r.course_code, r.session, r.semester, r.grade, r.published, r.outcome, r.points
          FROM assessment.student_results(p_student) r)
    SELECT dc.id, dc.deferment_id, dc.reference, dc.dstate, dc.course_code, c.title, dc.units, dc.original_session, dc.original_semester, dc.source,
           CASE WHEN EXISTS (SELECT 1 FROM later l WHERE l.course_code = dc.course_code AND l.published AND l.outcome = 'GRADED' AND l.points > 0
                                AND (l.session, l.semester) > (dc.original_session, dc.original_semester)) THEN 'COMPLETED'
                WHEN EXISTS (SELECT 1 FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id JOIN catalogue.offering o ON o.id = e.offering_id
                              WHERE r.student_id = p_student AND o.course_code = dc.course_code AND e.status IN ('REGISTERED','APPROVED')
                                AND (r.session, r.semester) > (dc.original_session, dc.original_semester)) THEN 'REGISTERED'
                ELSE 'DEFERRED' END,
           (SELECT l.session FROM later l WHERE l.course_code = dc.course_code AND (l.session, l.semester) > (dc.original_session, dc.original_semester) ORDER BY l.session DESC, l.semester DESC LIMIT 1),
           (SELECT l.semester FROM later l WHERE l.course_code = dc.course_code AND (l.session, l.semester) > (dc.original_session, dc.original_semester) ORDER BY l.session DESC, l.semester DESC LIMIT 1),
           (SELECT l.grade FROM later l WHERE l.course_code = dc.course_code AND l.published AND (l.session, l.semester) > (dc.original_session, dc.original_semester) ORDER BY l.session DESC, l.semester DESC LIMIT 1),
           dc.dstate = 'COMPLETED' OR (dc.dstate = 'ACTIVE' AND dc.return_on IS NOT NULL AND current_date >= dc.return_on)
      FROM dc JOIN catalogue.course c ON c.code = dc.course_code
     ORDER BY dc.original_session, dc.original_semester, dc.course_code;
$$;

-- ── 8 · the desks: Bursary → HOD → Faculty → Academic Office → DVC → SBC ──

/* what the finance record says of the student: the last school-fee payment and the balance — read, never typed */
CREATE OR REPLACE FUNCTION people.deferment_financials(p_student uuid, p_session text)
RETURNS TABLE (last_fee_amount numeric, last_fee_ref text, last_fee_at timestamptz, last_fee_session text, last_fee_channel text, last_fee_receipt text,
               balance numeric, due numeric, paid numeric, balance_session text, position_status text, has_arrears boolean, found boolean)
LANGUAGE sql STABLE AS $$
    WITH last AS (
        SELECT r.amount, r.reference, r.confirmed_at, r.session, r.channel, r.receipt_no
          FROM finance.payment_reference r
         WHERE r.student_id = p_student AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
         ORDER BY r.confirmed_at DESC LIMIT 1),
    ses AS (SELECT coalesce(p_session, (SELECT name FROM policy.academic_session WHERE state = 'CURRENT')) AS name),
    pos AS (SELECT p.* FROM ses, LATERAL finance.position(p_student, ses.name) p)
    SELECT last.amount, last.reference, last.confirmed_at, last.session, last.channel, last.receipt_no,
           pos.balance, pos.due, pos.paid, ses.name,
           CASE WHEN pos.due = 0 THEN 'NO_CHARGE' WHEN pos.paid >= pos.due THEN 'FULLY_PAID' WHEN pos.paid > 0 THEN 'PART_PAYMENT' ELSE 'NOT_PAID' END,
           pos.has_arrears, last.reference IS NOT NULL
      FROM ses LEFT JOIN last ON true LEFT JOIN pos ON true;
$$;

CREATE OR REPLACE FUNCTION people.deferment_decide(p_id uuid, p_action text, p_note text, p_actor uuid, p_office text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE d people.deferment; v_from text; v_to text; v_note text := nullif(btrim(coalesce(p_note, '')), ''); fin record; tl record; v_off text := lower(coalesce(p_office, ''));
BEGIN
    SELECT * INTO d FROM people.deferment WHERE id = p_id FOR UPDATE;
    IF d.id IS NULL THEN RAISE EXCEPTION 'no such deferment request' USING ERRCODE = '23503'; END IF;
    v_from := d.state;
    CASE p_action
        WHEN 'BURSARY_APPROVE' THEN
            IF d.state <> 'SUBMITTED' THEN RAISE EXCEPTION 'the Bursary verifies a submitted request; this one is %', lower(people.deferment_stage_label(d.state)) USING ERRCODE = '23514'; END IF;
            IF NOT people.deferment_office_may(v_off, d.state) THEN RAISE EXCEPTION 'the Bursary''s approval is the Bursary''s; % does not give it', v_off USING ERRCODE = '23514'; END IF;
            SELECT * INTO fin FROM people.deferment_financials(d.student_id, d.session);
            v_to := 'BURSARY_APPROVED';
            UPDATE people.deferment SET state = v_to, bursary_at = now(), bursary_by = p_actor, bursary_note = v_note,
                   bursary_last_fee_amount = fin.last_fee_amount, bursary_last_fee_ref = fin.last_fee_ref, bursary_last_fee_at = fin.last_fee_at, bursary_last_fee_session = fin.last_fee_session,
                   bursary_balance = fin.balance, bursary_balance_session = fin.balance_session, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_tell(d.id, 'Your deferment request has passed financial verification', 'The Bursary has verified your financial record and approved your request; it is now with your Head of Department.');
            PERFORM people.deferment_tell_desk(d.id, 'hod', 'A deferment request awaits the department', 'The Bursary has approved a deferment request of a student of your department. Open the deferments desk on the portal to review and decide.');
        WHEN 'RECOMMEND' THEN
            IF d.state <> 'BURSARY_APPROVED' THEN RAISE EXCEPTION 'the department decides after the Bursary; this request is %', lower(people.deferment_stage_label(d.state)) USING ERRCODE = '23514'; END IF;
            IF NOT people.deferment_office_may(v_off, d.state) THEN RAISE EXCEPTION 'the department''s approval is the Head of Department''s; % does not give it', v_off USING ERRCODE = '23514'; END IF;
            v_to := 'DEPT_RECOMMENDED';
            UPDATE people.deferment SET state = v_to, dept_at = now(), dept_by = p_actor, dept_note = v_note, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_tell(d.id, 'Your deferment request is approved by the department', 'Your Head of Department has approved your request; it is now with the faculty.');
            PERFORM people.deferment_tell_desk(d.id, 'dean', 'A deferment request awaits the faculty', 'The department has approved a student''s deferment request; the faculty''s decision is next on the deferments desk.');
        WHEN 'FAC_RECOMMEND' THEN
            IF d.state <> 'DEPT_RECOMMENDED' THEN RAISE EXCEPTION 'the faculty decides after the department; this request is %', lower(people.deferment_stage_label(d.state)) USING ERRCODE = '23514'; END IF;
            IF NOT people.deferment_office_may(v_off, d.state) THEN RAISE EXCEPTION 'the faculty''s approval is the Dean''s or the Faculty Officer''s; % does not give it', v_off USING ERRCODE = '23514'; END IF;
            v_to := 'FAC_RECOMMENDED';
            UPDATE people.deferment SET state = v_to, fac_at = now(), fac_by = p_actor, fac_note = v_note, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_tell(d.id, 'Your deferment request is approved by the faculty', 'The faculty has approved your request; it is with the Academic Office, which forwards approved requests to the Deputy Vice-Chancellor (Academic).');
            PERFORM people.deferment_tell_desk(d.id, 'academic', 'A faculty-approved deferment request is ready to forward', 'A deferment request approved by the Bursary, the department and the faculty awaits the Academic Office; it may be downloaded and forwarded to the DVC.');
        WHEN 'DVC_APPROVE' THEN
            IF d.state <> 'FORWARDED_TO_DVC' THEN RAISE EXCEPTION 'the DVC decides a request the Academic Office has forwarded; this one is %', lower(people.deferment_stage_label(d.state)) USING ERRCODE = '23514'; END IF;
            IF NOT people.deferment_office_may(v_off, d.state) THEN RAISE EXCEPTION 'the DVC''s approval is the Deputy Vice-Chancellor''s; % does not give it', v_off USING ERRCODE = '23514'; END IF;
            v_to := 'DVC_APPROVED';
            UPDATE people.deferment SET state = v_to, dvc_at = now(), dvc_by = p_actor, dvc_note = v_note, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_tell(d.id, 'Your deferment request is approved by the Deputy Vice-Chancellor', 'The Deputy Vice-Chancellor (Academic) has approved your request' || coalesce(': ' || v_note, '') || '. It now awaits the Senate Business Committee''s action.');
            PERFORM people.deferment_tell_desk(d.id, 'registrar', 'A deferment request awaits the Senate Business Committee', 'The DVC has approved deferment request ' || d.reference || '; it is WAITING SBC ACTION on the deferments desk.');
        WHEN 'SBC_APPROVE' THEN
            IF d.state <> 'DVC_APPROVED' THEN RAISE EXCEPTION 'the Senate Business Committee acts on a request the DVC has approved; this one is %', lower(people.deferment_stage_label(d.state)) USING ERRCODE = '23514'; END IF;
            IF NOT people.deferment_office_may(v_off, d.state) THEN RAISE EXCEPTION 'the Senate Business Committee''s act is recorded by the Registry; % does not record it', v_off USING ERRCODE = '23514'; END IF;
            v_to := 'APPROVED';
            UPDATE people.deferment SET state = v_to, decided_at = now(), decided_by = p_actor, decision_note = v_note, updated_at = now() WHERE id = d.id;
            -- the academic effect, in this transaction: the period marked deferred, the courses set aside, the timeline extended; if it fails, nothing is approved
            PERFORM people.deferment_apply_effect(d.id);
            SELECT * INTO tl FROM people.programme_timeline(d.student_id);
            SELECT * INTO d FROM people.deferment WHERE id = p_id;
            PERFORM people.deferment_tell(d.id, 'DEFERMENT APPROVED · ' || d.reference,
                'Your deferment request has been approved by the Senate Business Committee.'
                || E'\nDeferred period: ' || d.session || coalesce(' — semester ' || d.semester, ' — the whole session')
                || E'\nDuration: ' || d.extension_semesters || ' semester(s)'
                || E'\nExpected return: ' || d.return_session || ' — semester ' || d.return_semester
                || E'\nCourses affected: ' || d.courses_affected
                || E'\nYour programme completion timeline has automatically been extended by ' || d.extension_semesters || ' semester(s); your expected completion is now '
                || tl.adjusted_completion_session || ' semester ' || tl.adjusted_completion_semester || '. Your CGPA is not affected; the deferred courses are not failed.'
                || E'\nYour deferred courses will become available as deferred courses on your registration form when you resume. You cannot register for the deferred period. Download your approval letter from the portal.');
            -- the period already begun holds at once
            PERFORM people.deferments_tick();
        WHEN 'REJECT' THEN
            IF d.state NOT IN ('SUBMITTED','BURSARY_APPROVED','DEPT_RECOMMENDED','FAC_RECOMMENDED','FORWARDED_TO_DVC','DVC_APPROVED') THEN RAISE EXCEPTION 'a request in review is rejected; this one is %', lower(people.deferment_stage_label(d.state)) USING ERRCODE = '23514'; END IF;
            IF NOT people.deferment_office_may(v_off, d.state) THEN RAISE EXCEPTION 'this request is %; % does not decide it at this stage', lower(people.deferment_stage_label(d.state)), v_off USING ERRCODE = '23514'; END IF;
            IF v_note IS NULL THEN RAISE EXCEPTION 'a rejection carries its reason' USING ERRCODE = '23514', HINT = 'Say why the request is refused; the student reads it.'; END IF;
            v_to := 'REJECTED';
            UPDATE people.deferment SET state = v_to, decided_at = now(), decided_by = p_actor, decision_note = v_note, returned_from_state = d.state, returned_by_office = v_off, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_tell(d.id, 'Your deferment request has been rejected', 'Your request to defer ' || d.session || coalesce(' semester ' || d.semester, '') || ' was not approved by the ' || coalesce(people.deferment_stage_office_label(d.state), 'desk') || '. Reason: ' || v_note);
        WHEN 'CORRECTION' THEN
            IF d.state NOT IN ('SUBMITTED','BURSARY_APPROVED','DEPT_RECOMMENDED','FAC_RECOMMENDED','FORWARDED_TO_DVC','DVC_APPROVED') THEN RAISE EXCEPTION 'a request in review is returned for correction; this one is %', lower(people.deferment_stage_label(d.state)) USING ERRCODE = '23514'; END IF;
            IF NOT people.deferment_office_may(v_off, d.state) THEN RAISE EXCEPTION 'this request is %; % does not decide it at this stage', lower(people.deferment_stage_label(d.state)), v_off USING ERRCODE = '23514'; END IF;
            IF v_note IS NULL THEN RAISE EXCEPTION 'say what the student must correct' USING ERRCODE = '23514'; END IF;
            v_to := 'CORRECTION_REQUIRED';
            UPDATE people.deferment SET state = v_to, correction_note = v_note, returned_from_state = d.state, returned_by_office = v_off, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_tell(d.id, 'Your deferment request requires correction', 'Your request has been returned to you by the ' || coalesce(people.deferment_stage_office_label(d.state), 'desk') || ': ' || v_note || ' Correct it on the portal and submit it again; it returns to the same desk.');
        WHEN 'CANCEL' THEN
            IF d.state NOT IN ('DRAFT','SUBMITTED','CORRECTION_REQUIRED','BURSARY_APPROVED','DEPT_RECOMMENDED','FAC_RECOMMENDED','FORWARDED_TO_DVC','DVC_APPROVED','APPROVED') THEN
                RAISE EXCEPTION 'a deferment in force is not cancelled; the student returns from it' USING ERRCODE = '23514';
            END IF;
            IF v_off NOT IN ('student','academic','registrar','dregistrar','super') THEN RAISE EXCEPTION 'a request is cancelled by the student or the Registry' USING ERRCODE = '23514'; END IF;
            IF v_note IS NULL THEN RAISE EXCEPTION 'a cancellation carries its reason' USING ERRCODE = '23514'; END IF;
            v_to := 'CANCELLED';
            UPDATE people.deferment SET state = v_to, cancel_note = v_note, updated_at = now() WHERE id = d.id;
            IF d.state <> 'DRAFT' THEN
                PERFORM people.deferment_tell(d.id, 'Your deferment request has been cancelled', 'The deferment request ' || d.reference || ' is cancelled: ' || v_note);
            END IF;
        WHEN 'APPROVE' THEN
            RAISE EXCEPTION 'a deferment is approved in its order: the Bursary, the department, the faculty, the Academic Office''s forwarding, the DVC, then the Senate Business Committee; no stage is skipped'
                USING ERRCODE = '23514', HINT = 'Act at your own stage; the request reaches the next desk on its own.';
        ELSE RAISE EXCEPTION 'unknown action %', p_action USING ERRCODE = '23514';
    END CASE;
    PERFORM people.deferment_log(d.id, p_action, v_from, v_to, v_note);
    RETURN v_to;
END $$;

/* the Academic Office forwards the faculty-approved requests to the DVC in one numbered batch — nothing is duplicated, every member named */
CREATE OR REPLACE FUNCTION people.deferment_forward(p_ids uuid[], p_session text, p_semester int, p_note text, p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_batch uuid; v_ref text; n int := 0; d record; v_off text := lower(coalesce(p_office, ''));
BEGIN
    IF v_off NOT IN ('academic','registrar','dregistrar','super') THEN RAISE EXCEPTION 'the Academic Office forwards approved requests to the DVC; % does not', v_off USING ERRCODE = '23514'; END IF;
    v_ref := 'DEF-DVC-' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '-' || lpad(platform.next_number('DEFERMENT_BATCH', 'UNIVERSITY', to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY'))::text, 5, '0');
    INSERT INTO people.deferment_batch (reference, session, semester, forwarded_by, office, note) VALUES (v_ref, nullif(btrim(coalesce(p_session, '')), ''), p_semester, p_actor, v_off, nullif(btrim(coalesce(p_note, '')), ''))
    RETURNING id INTO v_batch;
    FOR d IN
        SELECT x.id, x.reference FROM people.deferment x
         WHERE x.state = 'FAC_RECOMMENDED'
           AND (p_ids IS NULL OR x.id = ANY (p_ids))
           AND (nullif(btrim(coalesce(p_session, '')), '') IS NULL OR x.session = p_session)
           AND (p_semester IS NULL OR x.semester = p_semester)
         ORDER BY x.fac_at
         FOR UPDATE
    LOOP
        UPDATE people.deferment SET state = 'FORWARDED_TO_DVC', batch_id = v_batch, forwarded_at = now(), forwarded_by = p_actor, updated_at = now() WHERE id = d.id;
        PERFORM people.deferment_log(d.id, 'FORWARD', 'FAC_RECOMMENDED', 'FORWARDED_TO_DVC', 'Forwarded to the DVC in batch ' || v_ref || coalesce(' · ' || nullif(btrim(coalesce(p_note, '')), ''), ''));
        PERFORM people.deferment_tell(d.id, 'Your deferment request has been forwarded to the Deputy Vice-Chancellor', 'The Academic Office has forwarded your request ' || d.reference || ' to the Deputy Vice-Chancellor (Academic) in batch ' || v_ref || '.');
        n := n + 1;
    END LOOP;
    IF n = 0 THEN RAISE EXCEPTION 'no faculty-approved request is waiting to be forwarded' USING ERRCODE = '23514', HINT = 'Only a request the faculty has approved and the Academic Office has not yet forwarded goes in a batch.'; END IF;
    UPDATE people.deferment_batch SET count = n WHERE id = v_batch;
    PERFORM people.deferment_tell_desk((SELECT id FROM people.deferment WHERE batch_id = v_batch LIMIT 1), 'dvc', 'Deferment batch ' || v_ref || ' awaits your decision',
        'The Academic Office has forwarded ' || n || ' deferment application(s) in batch ' || v_ref || '. Open the deferments desk on the portal to review, comment and decide each.');
    RETURN v_batch;
END $$;

/* a desk's reading of a request or a document, once per actor per stage, on the trail */
CREATE OR REPLACE FUNCTION people.deferment_viewed(p_id uuid, p_action text, p_note text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE d people.deferment; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO d FROM people.deferment WHERE id = p_id;
    IF d.id IS NULL OR v_actor IS NULL THEN RETURN; END IF;
    IF NOT EXISTS (SELECT 1 FROM people.deferment_event e WHERE e.deferment_id = p_id AND e.action = p_action AND e.actor_id = v_actor AND e.from_state = d.state AND coalesce(e.note, '') = coalesce(p_note, '')) THEN
        PERFORM people.deferment_log(p_id, p_action, d.state, d.state, p_note);
    END IF;
END $$;

/* the return confirmed: the status restored, the deferred courses become due, the record told */
CREATE OR REPLACE FUNCTION people.deferment_confirm_return(p_id uuid, p_note text, p_actor uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE d people.deferment; s people.student; v_back text; n int;
BEGIN
    SELECT * INTO d FROM people.deferment WHERE id = p_id FOR UPDATE;
    IF d.id IS NULL THEN RAISE EXCEPTION 'no such deferment' USING ERRCODE = '23503'; END IF;
    IF d.state NOT IN ('ACTIVE','APPROVED') THEN RAISE EXCEPTION 'a return is confirmed on a deferment in force; this one is %', lower(replace(d.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM people.student WHERE id = d.student_id;
    v_back := coalesce(d.prior_status, 'ACTIVE');
    IF v_back NOT IN ('ACTIVE','PROBATION','ADMITTED') THEN v_back := 'ACTIVE'; END IF;
    UPDATE people.deferment SET state = 'COMPLETED', returned_at = now(), returned_by = p_actor, return_note = nullif(btrim(coalesce(p_note, '')), ''), updated_at = now() WHERE id = d.id;
    IF s.status = 'DEFERRED' THEN
        PERFORM people.change_status(s.id, v_back, d.reference, current_date, 'Returned from deferment');
    END IF;
    SELECT count(*) INTO n FROM people.deferred_courses(s.id) x WHERE x.deferment_id = d.id AND x.status = 'DEFERRED';
    PERFORM people.deferment_log(d.id, 'RETURNED', d.state, 'COMPLETED',
        coalesce(nullif(btrim(coalesce(p_note, '')), '') || ' · ', '') || 'Resumed for ' || d.return_session || ' semester ' || d.return_semester || ' · ' || n || ' deferred course(s) now due');
    PERFORM people.deferment_tell(d.id, 'Welcome back — your return from deferment is confirmed',
        'Your return for ' || d.return_session || ' semester ' || d.return_semester || ' is confirmed. Pay your school fees and register your courses for the period on the portal as usual; '
        || n || ' course(s) from the deferred period appear on your form as deferred courses and are registered in their semester.');
    RETURN 'returned';
END $$;

-- ── 9 · the deferred courses on the registration form: distinct from the carry-overs and the current courses ─

DROP FUNCTION IF EXISTS registration.student_menu(uuid, text, int);
CREATE OR REPLACE FUNCTION registration.student_menu(p_student uuid, p_session text, p_semester int)
RETURNS TABLE (offering_id uuid, course_code text, title text, units int, kind text, basis text, owner_dept text,
               carryover boolean, failed_in text, lecturer text, deferred boolean, deferred_from text)
LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT * FROM people.student WHERE id = p_student),
    eligible AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, co.basis, c.dept_code
          FROM s
          JOIN catalogue.course_offer co ON co.programme_code = s.programme_code AND co.level = s.current_level
                                        AND (co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
          JOIN catalogue.course c ON c.code = co.course_code AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
         WHERE c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version),
    carry AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, 'Carryover'::text AS basis, c.dept_code, cv.failed_in
          FROM registration.carryovers(p_student) cv
          JOIN catalogue.course c ON c.code = cv.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
          CROSS JOIN s
         WHERE registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)),
    -- a course set aside by an approved deferment, due since the student returned, offered this semester and not yet passed
    deferred AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, 'Deferred'::text AS basis, c.dept_code,
               dc.original_session || ' semester ' || dc.original_semester AS deferred_from
          FROM people.deferred_courses(p_student) dc
          JOIN catalogue.course c ON c.code = dc.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
          CROSS JOIN s
         WHERE dc.status = 'DEFERRED' AND dc.due
           AND (dc.original_session, dc.original_semester) < (p_session, p_semester)
           AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.code = c.code))
    SELECT x.offering_id, x.code, x.title, x.units, x.kind, x.basis, d.name,
           (x.basis IN ('Carryover','Deferred')), x.failed_in, p.surname || ', ' || p.given_names,
           (x.basis = 'Deferred'), x.deferred_from
      FROM (SELECT e.*, NULL::text AS failed_in, NULL::text AS deferred_from FROM eligible e
            WHERE NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.offering_id = e.offering_id)
              AND NOT EXISTS (SELECT 1 FROM deferred df WHERE df.offering_id = e.offering_id)
            UNION ALL SELECT cv.*, NULL::text AS deferred_from FROM carry cv
            UNION ALL SELECT df.offering_id, df.code, df.title, df.units, df.kind, df.basis, df.dept_code, NULL::text, df.deferred_from FROM deferred df) x
      JOIN ref.department d ON d.code = x.dept_code
      JOIN catalogue.offering o ON o.id = x.offering_id
      LEFT JOIN iam.person p ON p.id = o.lecturer_id
     ORDER BY (x.basis = 'Carryover') DESC, (x.basis = 'Deferred') DESC, x.kind, x.code;
$$;

-- the draft carries the carry-overs and the deferred courses from the start, each under its own name
CREATE OR REPLACE FUNCTION registration.student_draft(p_student uuid, p_session text, p_semester int)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid; s people.student; m record;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
    SELECT id INTO v FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF v IS NOT NULL THEN RETURN v; END IF;
    v := gen_random_uuid();
    INSERT INTO registration.course_registration (id, student_id, session, semester, level)
    VALUES (v, p_student, p_session, p_semester, s.current_level);
    FOR m IN SELECT * FROM registration.student_menu(p_student, p_session, p_semester) WHERE carryover LOOP
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (v, m.offering_id, m.units, CASE WHEN m.deferred THEN 'DEFERRED' ELSE 'CARRYOVER' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
    END LOOP;
    RETURN v;
END $$;

-- the student's choice, replaced whole: the carry-overs and the deferred courses stay, everything else is what was named
CREATE OR REPLACE FUNCTION registration.student_choose(p_registration uuid, p_offerings uuid[])
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; m record; n int := 0;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status NOT IN ('DRAFT','RETURNED') THEN
        RAISE EXCEPTION 'this registration is %; it is not edited', lower(r.status) USING ERRCODE = '23514',
            HINT = 'A submitted registration is changed by the level adviser returning it.';
    END IF;
    DELETE FROM registration.entry WHERE registration_id = p_registration AND entry_type NOT IN ('CARRYOVER','DEFERRED');
    -- a deferred course or a carry-over that has since become due is added to a draft that predates it
    FOR m IN SELECT * FROM registration.student_menu(r.student_id, r.session, r.semester) WHERE carryover LOOP
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (p_registration, m.offering_id, m.units, CASE WHEN m.deferred THEN 'DEFERRED' ELSE 'CARRYOVER' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
    END LOOP;
    FOR m IN SELECT * FROM registration.student_menu(r.student_id, r.session, r.semester) WHERE NOT carryover AND offering_id = ANY(p_offerings) LOOP
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (p_registration, m.offering_id, m.units,
                CASE WHEN m.basis = 'GST' OR m.kind = 'GST' THEN 'GST' WHEN m.basis = 'Borrowed' THEN 'BORROWED'
                     WHEN m.basis = 'Elective' OR m.kind = 'Elective' THEN 'ELECTIVE' ELSE 'CURRENT' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        n := n + 1;
    END LOOP;
    RETURN registration.units_of(p_registration);
END $$;

-- a deferred course is no more dropped than a carry-over: it is taken
CREATE OR REPLACE FUNCTION registration.student_drop(p_student uuid, p_session text, p_semester int, p_offering uuid)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; e registration.entry;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF NOT FOUND THEN RAISE EXCEPTION 'no registration to change' USING ERRCODE = '23514'; END IF;
    IF r.status = 'LOCKED' THEN RAISE EXCEPTION 'this registration is locked and cannot be changed' USING ERRCODE = '23514'; END IF;
    IF NOT registration.add_drop_open(p_session, p_semester) THEN
        RAISE EXCEPTION 'add and drop is not open for % semester %', p_session, p_semester USING ERRCODE = '23514';
    END IF;

    SELECT * INTO e FROM registration.entry WHERE registration_id = r.id AND offering_id = p_offering AND status <> 'DROPPED';
    IF NOT FOUND THEN RAISE EXCEPTION 'that course is not on your registration' USING ERRCODE = '23514'; END IF;
    IF e.entry_type = 'CARRYOVER' THEN
        RAISE EXCEPTION 'a carryover cannot be dropped; it must be repeated' USING ERRCODE = '23514';
    END IF;
    IF e.entry_type = 'DEFERRED' THEN
        RAISE EXCEPTION 'a deferred course cannot be dropped; it is taken in the semester it is due' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM assessment.score sc JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id
                WHERE sc.student_id = p_student AND sh.offering_id = p_offering) THEN
        RAISE EXCEPTION 'a mark is already recorded in this course; it cannot be dropped' USING ERRCODE = '23514';
    END IF;

    UPDATE registration.entry SET status = 'DROPPED' WHERE registration_id = r.id AND offering_id = p_offering;
    RETURN registration.units_of(r.id);
END $$;

-- ── 10 · what each screen reads in one call ────────────────────────────────

/* the academic effect of one deferment, for the student's record and the desks */
CREATE OR REPLACE FUNCTION people.deferment_effect(p_id uuid)
RETURNS TABLE (kind text, period text, duration_semesters int, courses_affected int, effect_applied_at timestamptz, cgpa numeric,
               extension_semesters int, original_semesters int, adjusted_semesters int,
               original_completion text, adjusted_completion text, adjusted_completion_on date, expected_return text, entry_session text, matric_no text, applied boolean)
LANGUAGE sql STABLE AS $$
    SELECT d.kind, d.session || coalesce(' — semester ' || d.semester, ' — whole session'),
           coalesce(d.extension_semesters, people.deferment_semesters(d.kind, d.session)),
           coalesce(d.courses_affected, (SELECT count(*)::int FROM people.deferred_course x WHERE x.deferment_id = d.id)),
           d.effect_applied_at,
           (SELECT g.cgpa FROM assessment.student_gpa(d.student_id) g WHERE g.cgpa IS NOT NULL ORDER BY g.session DESC, g.semester DESC LIMIT 1),
           coalesce(d.extension_semesters, people.deferment_semesters(d.kind, d.session)),
           t.original_semesters, t.adjusted_semesters,
           t.original_completion_session || ' semester ' || t.original_completion_semester,
           t.adjusted_completion_session || ' semester ' || t.adjusted_completion_semester, t.adjusted_completion_on,
           d.return_session || ' — semester ' || d.return_semester, s.entry_session, s.matric_no,
           d.effect_applied_at IS NOT NULL
      FROM people.deferment d JOIN people.student s ON s.id = d.student_id CROSS JOIN LATERAL people.programme_timeline(d.student_id) t
     WHERE d.id = p_id;
$$;

-- ── grants ────────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE ON people.deferment_fee, people.deferment_batch, people.deferred_course TO app_student;
GRANT SELECT ON people.deferment_fee, people.deferment_batch, people.deferred_course TO app_auditor;

COMMIT;
