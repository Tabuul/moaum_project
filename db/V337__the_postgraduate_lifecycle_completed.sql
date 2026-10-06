-- ═══════════════════════════════════════════════════════════════════════════
-- V337 — the postgraduate lifecycle completed: correction, the School's final word, admission status
--        checking in its own window, physical screening, and matriculation that counts PG registration
--
--   The School's pipeline already runs from the apply form to the award (V201–V228, V255, V336): one
--   applicant account, the application fee, the department's recommendation, the faculty's vetting, the
--   School's offer, the checking and acceptance fees, admission to the register on the applicant's own
--   password, school fees on the student portal, coursework registration and Matriculation Management.
--   Inspected against the University's full lifecycle, these were missing or wrong, and only these change:
--
--   1. CORRECTION. A department could only recommend or decline. It may now RETURN a submitted application
--      to the applicant with what must be corrected; the applicant corrects it and resubmits. The School
--      may return a department's (or faculty's) recommendation to the department, which then decides again.
--      Every turn stays on the application's trail (V255); the department decides only an application
--      whose application fee is confirmed.
--   2. THE SCHOOL'S FINAL WORD. A recommendation is not an admission: the School now decides final
--      admission on an application the faculty recommended OR declined, or the department declined —
--      so "not recommended" reaches the School as a recommendation and is never the applicant's answer.
--   3. ADMISSION STATUS CHECKING. A window of its own, POSTGRADUATE_ADMISSION_STATUS_CHECKING, on V288's
--      architecture (the Director of ICT opens, closes, schedules, extends; the history kept). Unlike the
--      Post-UTME window it is OPEN until first configured, so what runs today keeps running. Any valid
--      applicant (application fee confirmed) pays the checking fee once while it is open — admitted, not
--      admitted or not yet decided — and checks as often as they like; admissions.pg_status_checking is
--      the one evaluation every path reads.
--   4. PHYSICAL SCREENING. After the acceptance fee, where the School's policy for the session requires it
--      (admissions.pg_screening_policy: venue, dates, instructions, the documents to bring), the applicant
--      is screened on the record they already gave — no second form. The screening officer schedules it
--      and decides CLEARED, NOT_CLEARED (with the reason) or CORRECTION_REQUIRED (with what to correct).
--      CLEARED admits the applicant to the register at once (pg_admit), which opens school fees on the
--      student portal; pg_admit refuses anyone screening has not cleared. Accepted before the policy
--      existed: not held.
--   5. MATRICULATION. Matriculation Management counted only the undergraduate course registration, so a
--      postgraduate could never be eligible for a number. An ENDORSED postgraduate registration of the
--      session now counts as registration; screening is part of the same gate (screening_ok_student).
--   6. The admitted student carries the applicant's state of origin and contact address.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'pgschool', true),
       set_config('moaum.reason', 'V337: the postgraduate lifecycle completed', true);

-- ── 1 · correction: the return, to the applicant or to the department ────────────────────────

ALTER TABLE admissions.pg_application
    ADD COLUMN return_note  text NULL,
    ADD COLUMN returned_at  timestamptz NULL,
    ADD COLUMN returned_by  uuid NULL,
    ADD COLUMN returned_to  text NULL,
    ADD CONSTRAINT ck_pg_app_returned_to CHECK (returned_to IS NULL OR returned_to IN ('APPLICANT', 'DEPARTMENT'));
COMMENT ON COLUMN admissions.pg_application.return_note IS
  'The last return (V337): what the department asked the applicant to correct, or why the School returned a recommendation to the department.';

ALTER TABLE admissions.pg_application DROP CONSTRAINT IF EXISTS ck_pg_app_state;
ALTER TABLE admissions.pg_application ADD CONSTRAINT ck_pg_app_state CHECK (state IN
    ('DRAFT','SUBMITTED','RETURNED','DEPT_RECOMMENDED','DEPT_DECLINED','FAC_RECOMMENDED','FAC_DECLINED',
     'OFFERED','NOT_OFFERED','ACCEPTED','ADMITTED'));

/* the department decides a submitted application whose application fee is confirmed */
CREATE OR REPLACE FUNCTION admissions.pg_dept_decide(p_application uuid, p_recommend boolean, p_note text, p_actor uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE a admissions.pg_application;
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_application FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such postgraduate application' USING ERRCODE = '23503'; END IF;
    IF a.fee_confirmed_at IS NULL THEN
        RAISE EXCEPTION 'PG_FEE_UNCONFIRMED: the department considers an application once its application fee is confirmed' USING ERRCODE = '23514',
              HINT = 'The application reaches the department when the fee is paid and confirmed.';
    END IF;
    IF a.state <> 'SUBMITTED' THEN
        RAISE EXCEPTION 'PG_NOT_WITH_DEPARTMENT: the department decides a submitted application, and this one is %', lower(replace(a.state, '_', ' ')) USING ERRCODE = '23514',
              HINT = 'A recommendation once made is changed only after the School returns it to the department.';
    END IF;
    UPDATE admissions.pg_application
       SET state = CASE WHEN p_recommend THEN 'DEPT_RECOMMENDED' ELSE 'DEPT_DECLINED' END,
           dept_decided_at = now(), dept_decided_by = p_actor, dept_note = nullif(btrim(p_note), '')
     WHERE id = p_application;
END;
$$;

/* the department returns a submitted application to the applicant, saying what to correct */
CREATE OR REPLACE FUNCTION admissions.pg_dept_return(p_application uuid, p_note text, p_actor uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE a admissions.pg_application;
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_application FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such postgraduate application' USING ERRCODE = '23503'; END IF;
    IF nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN
        RAISE EXCEPTION 'PG_RETURN_NOTE_REQUIRED: say what the applicant must correct' USING ERRCODE = '23514',
              HINT = 'The applicant reads these words on the portal and in the email.';
    END IF;
    IF a.fee_confirmed_at IS NULL OR a.state <> 'SUBMITTED' THEN
        RAISE EXCEPTION 'PG_NOT_WITH_DEPARTMENT: only a submitted, paid application is returned to the applicant; this one is %', lower(replace(a.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.pg_application
       SET state = 'RETURNED', return_note = btrim(p_note), returned_at = now(), returned_by = p_actor, returned_to = 'APPLICANT'
     WHERE id = p_application;
END;
$$;

/* the applicant resubmits a returned application, corrected */
CREATE OR REPLACE FUNCTION admissions.pg_resubmit(p_application uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE a admissions.pg_application;
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_application FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such postgraduate application' USING ERRCODE = '23503'; END IF;
    IF a.state <> 'RETURNED' THEN
        RAISE EXCEPTION 'PG_NOT_RETURNED: only an application returned for correction is resubmitted' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.pg_application SET state = 'SUBMITTED' WHERE id = p_application;
END;
$$;

/* the School returns a recommendation to the department, which decides again; the trail keeps the first */
CREATE OR REPLACE FUNCTION admissions.pg_school_return(p_application uuid, p_note text, p_actor uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE a admissions.pg_application;
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_application FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such postgraduate application' USING ERRCODE = '23503'; END IF;
    IF nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN
        RAISE EXCEPTION 'PG_RETURN_NOTE_REQUIRED: say why the recommendation goes back to the department' USING ERRCODE = '23514';
    END IF;
    IF a.state NOT IN ('DEPT_RECOMMENDED', 'DEPT_DECLINED', 'FAC_RECOMMENDED', 'FAC_DECLINED') THEN
        RAISE EXCEPTION 'PG_NOTHING_TO_RETURN: a recommendation is returned to the department before the School decides; this application is %', lower(replace(a.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.pg_application
       SET state = 'SUBMITTED', return_note = btrim(p_note), returned_at = now(), returned_by = p_actor, returned_to = 'DEPARTMENT',
           dept_decided_at = NULL, dept_decided_by = NULL, dept_note = NULL,
           fac_decided_at = NULL, fac_decided_by = NULL, fac_note = NULL
     WHERE id = p_application;
END;
$$;

-- ── 2 · the School's final word, on every recommendation ─────────────────────────────────────

CREATE OR REPLACE FUNCTION admissions.pg_spgs_decide(p_application uuid, p_offer boolean, p_note text, p_actor uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE a admissions.pg_application;
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_application FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such postgraduate application' USING ERRCODE = '23503'; END IF;
    IF a.state NOT IN ('FAC_RECOMMENDED', 'FAC_DECLINED', 'DEPT_DECLINED') THEN
        RAISE EXCEPTION 'PG_NOT_WITH_SCHOOL: the School decides after the department and the faculty have made their recommendation; this application is %', lower(replace(a.state, '_', ' ')) USING ERRCODE = '23514',
              HINT = 'A department''s recommendation goes to the faculty first; a department''s "not recommended" comes straight to the School.';
    END IF;
    UPDATE admissions.pg_application
       SET state = CASE WHEN p_offer THEN 'OFFERED' ELSE 'NOT_OFFERED' END,
           spgs_decided_at = now(), spgs_decided_by = p_actor, spgs_note = nullif(btrim(p_note), '')
     WHERE id = p_application;
END;
$$;

-- ── 3 · admission status checking, in a window of its own ───────────────────────────────────

ALTER TABLE policy.portal_window DROP CONSTRAINT IF EXISTS portal_window_window_type_check;
ALTER TABLE policy.portal_window ADD CONSTRAINT portal_window_window_type_check
    CHECK (window_type IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION',
                           'POSTGRADUATE_APPLICATION', 'POSTGRADUATE_ADMISSION_STATUS_CHECKING'));

/* the one evaluation of a postgraduate applicant's admission status checking: whether the application is valid,
   the window, whether the fee is paid, what may be done, and the status checking returns. An applicant whose offer
   is accepted continues whatever the window. The status is the School's: a recommendation is never the answer. */
CREATE OR REPLACE FUNCTION admissions.pg_status_checking(p_application uuid)
RETURNS TABLE (valid boolean, window_state text, window_open boolean, paid boolean, may_pay boolean, may_check boolean,
               continuing boolean, status text)
LANGUAGE sql STABLE AS $$
    SELECT v.valid, w.state, w.state = 'OPEN', v.paid,
           v.valid AND NOT v.paid AND w.state = 'OPEN',
           v.valid AND v.paid AND (w.state = 'OPEN' OR v.continuing),
           v.continuing,
           CASE WHEN a.state IN ('OFFERED', 'ACCEPTED', 'ADMITTED') THEN 'ADMITTED'
                WHEN a.state = 'NOT_OFFERED' THEN 'NOT_ADMITTED'
                ELSE 'PENDING' END
      FROM admissions.pg_application a
      CROSS JOIN LATERAL (SELECT a.fee_confirmed_at IS NOT NULL AND a.submitted_at IS NOT NULL AND a.state <> 'DRAFT' AS valid,
                                 a.checking_confirmed_at IS NOT NULL AS paid,
                                 a.acceptance_confirmed_at IS NOT NULL OR a.state IN ('ACCEPTED', 'ADMITTED') AS continuing) v
      CROSS JOIN LATERAL policy.window_state('POSTGRADUATE_ADMISSION_STATUS_CHECKING', a.session, NULL) w
     WHERE a.id = p_application;
$$;
COMMENT ON FUNCTION admissions.pg_status_checking(uuid) IS
  'V337: may this postgraduate applicant pay the checking fee, and check their status: valid (application fee confirmed), '
  'the POSTGRADUATE_ADMISSION_STATUS_CHECKING window open (or the offer already accepted), the fee paid once. Status: ADMITTED, NOT_ADMITTED or PENDING.';

-- ── 4 · physical screening: the School's policy per session, and the screening of each applicant ──

CREATE TABLE admissions.pg_screening_policy (
    session            text PRIMARY KEY,
    required           boolean NOT NULL DEFAULT true,
    enabled_from       timestamptz NOT NULL DEFAULT now(),
    venue              text NULL,
    starts_on          date NULL,
    ends_on            date NULL,
    instructions       text NULL,
    required_documents text[] NOT NULL DEFAULT '{}',
    updated_by         uuid NULL,
    updated_office     text NULL,
    updated_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_pg_scrpol_dates CHECK (ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on),
    CONSTRAINT ck_pg_scrpol_venue CHECK (venue IS NULL OR length(venue) <= 300),
    CONSTRAINT ck_pg_scrpol_text  CHECK (instructions IS NULL OR length(instructions) <= 4000)
);
SELECT audit.attach('admissions.pg_screening_policy');
COMMENT ON TABLE admissions.pg_screening_policy IS
  'V337: whether the School screens the session''s accepted applicants physically, from when (applicants accepted before are not held), '
  'and what they are told: the venue, the dates, the instructions and the documents to bring.';

CREATE TABLE admissions.pg_screening (
    application_id     uuid PRIMARY KEY REFERENCES admissions.pg_application(id) ON DELETE CASCADE,
    state              text NOT NULL DEFAULT 'PENDING',
    venue              text NULL,
    scheduled_for      timestamptz NULL,
    verified_documents text[] NOT NULL DEFAULT '{}',
    missing_documents  text[] NOT NULL DEFAULT '{}',
    issues             text NULL,
    remarks            text NULL,
    reason             text NULL,
    officer_id         uuid NULL,
    officer_office     text NULL,
    decided_at         timestamptz NULL,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_pg_scr_state CHECK (state IN ('PENDING', 'SCHEDULED', 'IN_PROGRESS', 'CLEARED', 'NOT_CLEARED', 'CORRECTION_REQUIRED')),
    CONSTRAINT ck_pg_scr_reason CHECK (state NOT IN ('NOT_CLEARED', 'CORRECTION_REQUIRED') OR nullif(btrim(coalesce(reason, '')), '') IS NOT NULL)
);
CREATE INDEX ix_pg_screening_state ON admissions.pg_screening (state);
SELECT audit.attach('admissions.pg_screening');
COMMENT ON TABLE admissions.pg_screening IS
  'V337: the physical screening of an accepted postgraduate applicant, on the record they already gave: when and where, the documents '
  'verified and missing, the officer''s decision and its reason. CLEARED admits the applicant to the register.';

CREATE OR REPLACE FUNCTION admissions.pg_screening_required(p_application uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT sp.required AND (a.accepted_at IS NULL OR a.accepted_at >= sp.enabled_from)
                       FROM admissions.pg_application a JOIN admissions.pg_screening_policy sp ON sp.session = a.session
                      WHERE a.id = p_application), false);
$$;

CREATE OR REPLACE FUNCTION admissions.pg_screening_ok(p_application uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT NOT admissions.pg_screening_required(p_application)
        OR EXISTS (SELECT 1 FROM admissions.pg_screening sc WHERE sc.application_id = p_application AND sc.state = 'CLEARED');
$$;

/* the screening record of an accepted applicant, opened with the session's venue and first day */
CREATE OR REPLACE FUNCTION admissions.pg_screening_open(p_application uuid)
RETURNS admissions.pg_screening
LANGUAGE plpgsql AS $$
DECLARE a admissions.pg_application; sp admissions.pg_screening_policy; sc admissions.pg_screening;
BEGIN
    SELECT * INTO sc FROM admissions.pg_screening WHERE application_id = p_application;
    IF sc.application_id IS NOT NULL THEN RETURN sc; END IF;
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_application;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such postgraduate application' USING ERRCODE = '23503'; END IF;
    IF a.state NOT IN ('ACCEPTED', 'ADMITTED') THEN
        RAISE EXCEPTION 'PG_SCREENING_UNAVAILABLE: screening follows the acceptance of the offer' USING ERRCODE = '23514',
              HINT = 'The applicant pays the acceptance fee, which accepts the offer.';
    END IF;
    SELECT * INTO sp FROM admissions.pg_screening_policy WHERE session = a.session;
    INSERT INTO admissions.pg_screening (application_id, venue, scheduled_for)
    VALUES (p_application, sp.venue, CASE WHEN sp.starts_on IS NOT NULL THEN (sp.starts_on + time '09:00') AT TIME ZONE 'Africa/Lagos' END)
    RETURNING * INTO sc;
    PERFORM admissions.pg_app_event(p_application, 'SCREENING_PENDING', 'Physical screening opened'
            || coalesce(' · ' || sp.venue, '') || coalesce(' from ' || to_char(sp.starts_on, 'DD Mon YYYY'), ''));
    RETURN sc;
END $$;

/* the screening officer sets (or moves) when and where the applicant is screened */
CREATE OR REPLACE FUNCTION admissions.pg_screening_schedule(p_application uuid, p_venue text, p_at timestamptz, p_actor uuid, p_office text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE sc admissions.pg_screening;
BEGIN
    sc := admissions.pg_screening_open(p_application);
    IF sc.state = 'CLEARED' THEN
        RAISE EXCEPTION 'PG_SCREENING_DECIDED: the applicant is already cleared' USING ERRCODE = '23514';
    END IF;
    IF nullif(btrim(coalesce(p_venue, '')), '') IS NULL OR p_at IS NULL THEN
        RAISE EXCEPTION 'PG_SCREENING_WHEN_WHERE: a screening is scheduled at a venue, on a day and time' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.pg_screening
       SET state = 'SCHEDULED', venue = btrim(p_venue), scheduled_for = p_at, officer_id = p_actor, officer_office = p_office, updated_at = now()
     WHERE application_id = p_application;
    PERFORM admissions.pg_app_event(p_application, 'SCREENING_SCHEDULED',
            'Physical screening scheduled · ' || btrim(p_venue) || ' · ' || to_char(p_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY HH24:MI'));
    PERFORM admissions.pg_tell_applicant(p_application, 'Your postgraduate screening is scheduled',
        'Your physical screening is scheduled for ' || to_char(p_at AT TIME ZONE 'Africa/Lagos', 'FMDay DD Month YYYY "at" HH24:MI')
        || ' at ' || btrim(p_venue) || '. Bring the originals of the documents you uploaded and those listed on the applicant portal.');
END $$;

/* the screening officer's decision. CLEARED admits the applicant to the register in the same transaction */
CREATE OR REPLACE FUNCTION admissions.pg_screening_decide(p_application uuid, p_decision text, p_verified text[], p_missing text[],
                                                          p_issues text, p_remarks text, p_reason text, p_actor uuid, p_office text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE a admissions.pg_application; sc admissions.pg_screening; v_decision text := upper(btrim(coalesce(p_decision, '')));
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_application FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such postgraduate application' USING ERRCODE = '23503'; END IF;
    IF v_decision NOT IN ('IN_PROGRESS', 'CLEARED', 'NOT_CLEARED', 'CORRECTION_REQUIRED') THEN
        RAISE EXCEPTION 'PG_SCREENING_DECISION: a screening is in progress, cleared, not cleared, or needs correction' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.pg_screening WHERE application_id = p_application AND state = 'CLEARED') THEN
        RAISE EXCEPTION 'PG_SCREENING_DECIDED: the applicant is already cleared and on the register' USING ERRCODE = '23514';
    END IF;
    IF a.state <> 'ACCEPTED' THEN
        RAISE EXCEPTION 'PG_SCREENING_UNAVAILABLE: screening decides an accepted offer; this application is %', lower(replace(a.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF v_decision IN ('NOT_CLEARED', 'CORRECTION_REQUIRED') AND nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'PG_SCREENING_REASON: say why, and what the applicant must do next' USING ERRCODE = '23514',
              HINT = 'The applicant reads these words on the portal and in the email.';
    END IF;
    sc := admissions.pg_screening_open(p_application);
    IF sc.state = 'CLEARED' THEN
        RAISE EXCEPTION 'PG_SCREENING_DECIDED: the applicant is already cleared and on the register' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.pg_screening
       SET state = v_decision,
           verified_documents = coalesce(p_verified, verified_documents), missing_documents = coalesce(p_missing, missing_documents),
           issues = nullif(btrim(coalesce(p_issues, '')), ''), remarks = nullif(btrim(coalesce(p_remarks, '')), ''),
           reason = nullif(btrim(coalesce(p_reason, '')), ''),
           officer_id = p_actor, officer_office = p_office,
           decided_at = CASE WHEN v_decision = 'IN_PROGRESS' THEN decided_at ELSE now() END, updated_at = now()
     WHERE application_id = p_application;
    PERFORM admissions.pg_app_event(p_application, 'SCREENING_' || v_decision,
            CASE v_decision WHEN 'IN_PROGRESS' THEN 'Physical screening in progress'
                            WHEN 'CLEARED' THEN 'Cleared at physical screening'
                            WHEN 'NOT_CLEARED' THEN 'Not cleared at physical screening — ' || btrim(p_reason)
                            ELSE 'Correction required at physical screening — ' || btrim(p_reason) END);
    IF v_decision = 'NOT_CLEARED' THEN
        PERFORM admissions.pg_tell_applicant(p_application, 'Your postgraduate screening was not successful',
            'You were not cleared at physical screening. ' || btrim(p_reason) || ' Contact the School of Postgraduate Studies for the next step.');
    ELSIF v_decision = 'CORRECTION_REQUIRED' THEN
        PERFORM admissions.pg_tell_applicant(p_application, 'Your postgraduate screening needs a correction',
            'Your physical screening needs a correction before you can be cleared: ' || btrim(p_reason)
            || ' Make the correction and return to the screening desk; the applicant portal shows what is outstanding.');
    ELSIF v_decision = 'CLEARED' THEN
        PERFORM admissions.pg_admit(p_application);     -- the register, the student account and the notice: school fees are next
    END IF;
    RETURN v_decision;
END $$;

-- ── the applicant becomes the student only once screening has cleared them ───────────────────

CREATE OR REPLACE FUNCTION admissions.pg_admit(p_application uuid)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE a admissions.pg_application; p admissions.pg_applicant; v_student uuid; v_yy text;
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_application FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such postgraduate application' USING ERRCODE = '23503'; END IF;
    IF a.student_id IS NOT NULL THEN RETURN a.student_id; END IF;   -- idempotent
    IF a.state <> 'ACCEPTED' THEN
        RAISE EXCEPTION 'PG_NOT_ACCEPTED: only an accepted offer is admitted to the register (this application is %)', lower(replace(a.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF NOT admissions.pg_screening_ok(p_application) THEN
        RAISE EXCEPTION 'PG_SCREENING_NOT_CLEARED: the applicant is admitted to the register once physical screening has cleared them' USING ERRCODE = '23514',
              HINT = 'Record the screening decision; CLEARED admits the applicant at once.';
    END IF;
    SELECT * INTO p FROM admissions.pg_applicant WHERE id = a.applicant_id;
    v_yy := substr(a.session, 3, 2);

    INSERT INTO people.student (id, candidate_id, admission_no, surname, other_names, sex, date_of_birth, state_of_origin,
                               programme_code, entry_mode, entry_session, entry_level, current_level, status, school_id)
    VALUES (gen_random_uuid(), NULL,
            'MOAUM/ADM/' || v_yy || '/' || lpad(platform.next_number('ADMISSION', 'UNIVERSITY', a.session)::text, 6, '0'),
            p.surname, p.other_names, p.sex, p.date_of_birth, p.state_of_origin,
            a.programme_code, 'POSTGRADUATE', a.session, a.entry_level, a.entry_level, 'ADMITTED', 'S002')
    RETURNING id INTO v_student;

    -- the applicant's reach becomes the student's, so every notice from here finds them
    INSERT INTO people.student_contact (student_id, phone, email, address, updated_at)
    VALUES (v_student, p.phone, lower(p.email), p.contact_address, now())
    ON CONFLICT (student_id) DO NOTHING;

    -- the same password opens the student portal on the admission number: no second account to create
    INSERT INTO iam.student_account (id, student_id, password_hash, must_change)
    VALUES (gen_random_uuid(), v_student, p.password_hash, false)
    ON CONFLICT (student_id) DO NOTHING;

    UPDATE admissions.pg_application
       SET state = 'ADMITTED', admitted_at = now(), student_id = v_student
     WHERE id = p_application;
    RETURN v_student;
END;
$$;

COMMENT ON FUNCTION admissions.pg_admit(uuid) IS
  'Admits an accepted applicant whom screening has cleared (or whose session does not screen): the student row, the applicant''s '
  'contact and address as the student''s, the applicant''s password as the student portal account (sign-in on the admission number), '
  'and the application marked ADMITTED. V337.';

/* the student's side of the screening gate (school fees, course registration, matriculation) knows the postgraduate screening too */
CREATE OR REPLACE FUNCTION admissions.screening_ok_student(p_student uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT bool_and(admissions.screening_ok(a.id))
                       FROM people.student s JOIN admissions.application a ON a.candidate_id = s.candidate_id
                      WHERE s.id = p_student AND a.accepted_at IS NOT NULL), true)
       AND coalesce((SELECT bool_and(admissions.pg_screening_ok(g.id))
                       FROM admissions.pg_application g WHERE g.student_id = p_student), true);
$$;

-- ── the application's trail, with the new turns ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admissions.pg_application_trail()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_fee numeric; v_kind text; v_note text; sp admissions.pg_screening_policy;
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM admissions.pg_app_event(NEW.id, 'CREATED', 'Application opened for ' || NEW.programme_code || ' · ' || NEW.session);
        IF NEW.state = 'SUBMITTED' THEN
            PERFORM admissions.pg_app_event(NEW.id, 'SUBMITTED', 'Application submitted');
            SELECT application_fee INTO v_fee FROM admissions.pg_fee_rule(NEW.session);
            PERFORM admissions.pg_tell_applicant(NEW.id, 'Your MOAUM postgraduate application has been received',
                'Your application for ' || NEW.programme_code || ' in the ' || NEW.session || ' session has been received and numbered. '
                || 'Pay the application fee of ₦' || coalesce(v_fee::text, '') || ' on the applicant portal; once it is confirmed you complete your academic record, '
                || 'name your referees and upload your documents there. You can track the application on the portal at any time.');
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.state IS DISTINCT FROM OLD.state THEN
        IF NEW.state = 'SUBMITTED' AND OLD.state = 'RETURNED' THEN
            v_kind := 'RESUBMITTED'; v_note := 'Corrected and resubmitted by the applicant';
        ELSIF NEW.state = 'SUBMITTED' AND OLD.state IN ('DEPT_RECOMMENDED', 'DEPT_DECLINED', 'FAC_RECOMMENDED', 'FAC_DECLINED') THEN
            v_kind := 'RETURNED_TO_DEPARTMENT'; v_note := 'Returned to the department by the School' || coalesce(' — ' || NEW.return_note, '');
        ELSE
            v_kind := NEW.state;
            v_note := CASE NEW.state
                WHEN 'SUBMITTED'        THEN 'Application submitted'
                WHEN 'RETURNED'         THEN 'Returned to the applicant for correction' || coalesce(' — ' || NEW.return_note, '')
                WHEN 'DEPT_RECOMMENDED' THEN 'Recommended by the department' || coalesce(' — ' || NEW.dept_note, '')
                WHEN 'DEPT_DECLINED'    THEN 'Not recommended by the department' || coalesce(' — ' || NEW.dept_note, '')
                WHEN 'FAC_RECOMMENDED'  THEN 'Recommended by the faculty' || coalesce(' — ' || NEW.fac_note, '')
                WHEN 'FAC_DECLINED'     THEN 'Not recommended by the faculty' || coalesce(' — ' || NEW.fac_note, '')
                WHEN 'OFFERED'          THEN 'Admission offered by the School' || coalesce(' — ' || NEW.spgs_note, '')
                WHEN 'NOT_OFFERED'      THEN 'Admission not offered by the School' || coalesce(' — ' || NEW.spgs_note, '')
                WHEN 'ACCEPTED'         THEN 'Offer accepted'
                WHEN 'ADMITTED'         THEN 'Admitted to the register'
                ELSE NEW.state
            END;
        END IF;
        PERFORM admissions.pg_app_event(NEW.id, v_kind, v_note);

        IF NEW.state = 'SUBMITTED' AND OLD.state = 'DRAFT' THEN
            PERFORM admissions.pg_tell_applicant(NEW.id, 'Your MOAUM postgraduate application has been submitted',
                'Your application has been submitted to the department. You can track it on the applicant portal.');
        ELSIF NEW.state = 'RETURNED' THEN
            PERFORM admissions.pg_tell_applicant(NEW.id, 'Your postgraduate application has been returned for correction',
                'The department has returned your application for correction: ' || coalesce(NEW.return_note, '') || E'\n\n'
                || 'Sign in to the applicant portal, make the correction and resubmit the application.');
        ELSIF NEW.state = 'ACCEPTED' THEN
            IF admissions.pg_screening_required(NEW.id) THEN
                PERFORM admissions.pg_screening_open(NEW.id);
                SELECT * INTO sp FROM admissions.pg_screening_policy WHERE session = NEW.session;
                PERFORM admissions.pg_tell_applicant(NEW.id, 'Your offer of admission is accepted — physical screening is next',
                    'Your acceptance is recorded. Download your offer of admission from the applicant portal. You are next screened in person'
                    || coalesce(' at ' || sp.venue, '') || coalesce(' from ' || to_char(sp.starts_on, 'DD Month YYYY'), '')
                    || coalesce(' to ' || to_char(sp.ends_on, 'DD Month YYYY'), '') || '. '
                    || coalesce(sp.instructions || ' ', '')
                    || 'The applicant portal shows your screening, the documents to bring and, once you are cleared, how to pay your school fees.');
            ELSE
                PERFORM admissions.pg_tell_applicant(NEW.id, 'Your offer of admission is accepted',
                    'Your acceptance is recorded. Download your offer of admission from the applicant portal; the School now admits you to the register '
                    || 'and you will be told your admission number and how to sign in as a student.');
            END IF;
        ELSIF NEW.state = 'ADMITTED' THEN
            PERFORM admissions.pg_tell_applicant(NEW.id, 'You are admitted — your student record is open',
                'Your student record is on the University register. Your admission number is '
                || coalesce((SELECT admission_no FROM people.student WHERE id = NEW.student_id), '(issued shortly)')
                || '. Sign in to the student portal with that number and the password you chose as an applicant, pay your school fees and register your courses. '
                || 'Your matriculation number is issued by the Academic Office after registration, and becomes your username.');
        END IF;
    END IF;
    IF NEW.fee_confirmed_at IS NOT NULL AND OLD.fee_confirmed_at IS NULL THEN
        PERFORM admissions.pg_app_event(NEW.id, 'APPLICATION_FEE_CONFIRMED', 'Application fee confirmed');
        PERFORM admissions.pg_tell_applicant(NEW.id, 'Your application fee is confirmed',
            'Your application fee is confirmed. Complete your academic record, name your referees and upload your documents on the applicant portal; '
            || 'the department considers the application once these are in.');
    END IF;
    IF NEW.checking_confirmed_at IS NOT NULL AND OLD.checking_confirmed_at IS NULL THEN
        PERFORM admissions.pg_app_event(NEW.id, 'CHECKING_FEE_CONFIRMED', 'Checking fee confirmed; the admission status is open to the applicant');
        PERFORM admissions.pg_tell_applicant(NEW.id, 'Your admission status checking is paid',
            'Your checking fee is confirmed. Sign in to the applicant portal to check your admission status; you may check again at no further cost while checking is open.');
    END IF;
    IF NEW.acceptance_confirmed_at IS NOT NULL AND OLD.acceptance_confirmed_at IS NULL THEN
        PERFORM admissions.pg_app_event(NEW.id, 'ACCEPTANCE_FEE_CONFIRMED', 'Acceptance fee confirmed');
    END IF;
    RETURN NEW;
END $$;


-- ── 5 · the window act knows the postgraduate checking window ────────────────────────────────

CREATE OR REPLACE FUNCTION policy.window_act(p_type text, p_session text, p_semester integer, p_action text,
                                             p_opens timestamptz, p_closes timestamptz, p_late_until timestamptz, p_late_fee boolean,
                                             p_reason text, p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE cur policy.portal_window; prev record; v_forced text; v_opens timestamptz; v_closes timestamptz; v_late timestamptz; v_fee boolean; v_id uuid; nxt record;
BEGIN
    IF p_type NOT IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'POSTGRADUATE_ADMISSION_STATUS_CHECKING') THEN
        RAISE EXCEPTION 'no such portal window %', p_type USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('ADMISSION_STATUS_CHECKING', 'POSTGRADUATE_ADMISSION_STATUS_CHECKING') AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_CHECKING_SESSION: admission status checking opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION') AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_APPLICATION_SESSION: an application window opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN RAISE EXCEPTION 'no academic session % on the calendar', p_session USING ERRCODE = '23503'; END IF;
    IF p_action NOT IN ('OPEN', 'CLOSE', 'REOPEN', 'SCHEDULE', 'EXTEND', 'SHORTEN', 'EDIT') THEN RAISE EXCEPTION 'unknown action %', p_action USING ERRCODE = '23514'; END IF;
    IF p_action IN ('CLOSE', 'REOPEN', 'SHORTEN') AND nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'the reason for % is recorded, and none was given', lower(p_action) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO cur FROM policy.portal_window WHERE window_type = p_type AND session = p_session AND coalesce(semester, 0) = coalesce(p_semester, 0) AND superseded_at IS NULL FOR UPDATE;
    SELECT * INTO prev FROM policy.window_state(p_type, p_session, p_semester);
    v_opens := coalesce(p_opens, cur.opens_at); v_closes := coalesce(p_closes, cur.closes_at); v_late := coalesce(p_late_until, cur.late_until);
    v_fee := coalesce(p_late_fee, cur.late_fee_enabled, false);
    CASE p_action
        WHEN 'OPEN', 'REOPEN' THEN v_forced := CASE WHEN p_opens IS NULL AND p_closes IS NULL THEN 'OPEN' ELSE NULL END;
                                   IF p_opens IS NULL AND p_closes IS NOT NULL THEN v_opens := now(); END IF;
        WHEN 'CLOSE' THEN v_forced := 'CLOSED';
        WHEN 'SCHEDULE' THEN IF p_opens IS NULL THEN RAISE EXCEPTION 'a schedule names when the window opens' USING ERRCODE = '23514'; END IF; v_forced := NULL;
        WHEN 'EXTEND' THEN IF p_closes IS NULL AND p_late_until IS NULL THEN RAISE EXCEPTION 'an extension names the new closing' USING ERRCODE = '23514'; END IF;
                           IF cur.id IS NOT NULL AND p_closes IS NOT NULL AND cur.closes_at IS NOT NULL AND p_closes < cur.closes_at THEN RAISE EXCEPTION 'that closing is earlier than before; shorten the window instead' USING ERRCODE = '23514'; END IF;
                           v_forced := CASE WHEN cur.forced = 'CLOSED' THEN NULL ELSE cur.forced END;
        WHEN 'SHORTEN' THEN IF p_closes IS NULL THEN RAISE EXCEPTION 'a shortening names the new closing' USING ERRCODE = '23514'; END IF; v_forced := cur.forced;
        WHEN 'EDIT' THEN v_forced := cur.forced;
    END CASE;
    IF v_closes IS NOT NULL AND v_opens IS NOT NULL AND v_closes < v_opens THEN RAISE EXCEPTION 'the window closes before it opens' USING ERRCODE = '23514'; END IF;
    IF v_late IS NOT NULL AND v_closes IS NOT NULL AND v_late < v_closes THEN RAISE EXCEPTION 'the late period ends before the window closes' USING ERRCODE = '23514'; END IF;
    IF cur.id IS NOT NULL THEN UPDATE policy.portal_window SET superseded_at = now() WHERE id = cur.id; END IF;
    INSERT INTO policy.portal_window (window_type, session, semester, opens_at, closes_at, late_until, late_fee_enabled, forced, reason, created_by, created_office)
    VALUES (p_type, p_session, p_semester, v_opens, v_closes, v_late, v_fee, v_forced, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office)
    RETURNING id INTO v_id;
    SELECT * INTO nxt FROM policy.window_state(p_type, p_session, p_semester);
    INSERT INTO policy.portal_window_event (window_id, window_type, session, semester, action, previous_state, new_state, previous_opens_at, previous_closes_at, previous_late_until,
                                            new_opens_at, new_closes_at, new_late_until, late_fee_enabled, reason, actor, office)
    VALUES (v_id, p_type, p_session, p_semester, p_action, CASE WHEN prev.configured THEN prev.state ELSE prev.state || ' (default)' END, nxt.state, cur.opens_at, cur.closes_at, cur.late_until,
            v_opens, v_closes, v_late, v_fee, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office);
    RETURN v_id;
END $fn$;

-- ── 6 · matriculation: a postgraduate's endorsed registration is registration ──────────────────

CREATE OR REPLACE FUNCTION people.matric_candidates(p_session text, p_faculty text)
RETURNS TABLE (student_id uuid, admission_no text, surname text, other_names text, programme_code text, programme text, dept_code text, department text,
               faculty_code text, faculty text, entry_session text, status text, matric_no text, matriculated_at timestamptz,
               registered boolean, paid boolean, query_reason text, config_problem text, eligible boolean, reason text,
               batch_id uuid, batch_ref text, batch_state text, row_id uuid, proposed_no text, row_state text, problems text[], edited boolean, series_code text, sequence bigint)
LANGUAGE sql STABLE AS $$
    WITH base AS (
        SELECT s.id, s.admission_no, s.surname, s.other_names, p.code AS programme_code, p.name AS programme, p.dept_code, d.name AS department,
               f.code AS faculty_code, f.name AS faculty, s.entry_session, s.status, s.matric_no, s.matriculated_at,
               (EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = p_session AND r.status IN ('APPROVED', 'LOCKED'))
                OR EXISTS (SELECT 1 FROM admissions.pg_registration g WHERE g.student_id = s.id AND g.session = p_session AND g.state = 'ENDORSED')) AS registered,
               coalesce((SELECT fp.paid_in_full FROM finance.position(s.id, p_session) fp), false) AS paid,
               (SELECT q.reason FROM people.faculty_list l JOIN people.faculty_list_query q ON q.list_id = l.id AND q.student_id = s.id AND q.withdrawn_at IS NULL
                 WHERE l.session = p_session AND l.faculty_code = f.code LIMIT 1) AS query_reason,
               (SELECT c.problem FROM people.matric_components(s.id) c) AS config_problem
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN ref.faculty f ON f.code = p.faculty_code
          LEFT JOIN ref.department d ON d.code = p.dept_code
         WHERE f.code = p_faculty
           AND ((s.status = 'ADMITTED' AND s.matric_no IS NULL
                 AND (s.entry_session = p_session OR EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = p_session)
                     OR EXISTS (SELECT 1 FROM admissions.pg_registration g WHERE g.student_id = s.id AND g.session = p_session)))
                OR (s.matric_no IS NOT NULL AND (s.entry_session = p_session
                     OR EXISTS (SELECT 1 FROM people.matric_batch_row br JOIN people.matric_batch b ON b.id = br.batch_id WHERE br.student_id = s.id AND b.session = p_session AND br.state = 'ISSUED'))))
    ), judged AS (
        SELECT b.*,
               CASE WHEN b.matric_no IS NOT NULL THEN 'Already matriculated as ' || b.matric_no
                    WHEN b.status <> 'ADMITTED' THEN 'The student is ' || lower(b.status)
                    WHEN b.query_reason IS NOT NULL THEN 'Under query on the faculty list: ' || b.query_reason
                    WHEN NOT admissions.screening_ok_student(b.id) THEN 'Online screening not successful (or change of programme not yet approved)'
                    WHEN NOT b.registered THEN 'No approved course registration for ' || p_session
                    WHEN NOT b.paid THEN 'School fees for ' || p_session || ' not settled'
                    WHEN b.config_problem IS NOT NULL THEN b.config_problem
                    END AS reason
          FROM base b
    )
    SELECT j.id, j.admission_no, j.surname, j.other_names, j.programme_code, j.programme, j.dept_code, j.department, j.faculty_code, j.faculty, j.entry_session,
           j.status, j.matric_no, j.matriculated_at, j.registered, j.paid, j.query_reason, j.config_problem, j.reason IS NULL, j.reason,
           mb.id, mb.ref, mb.state, br.id, br.proposed_no, br.state, br.problems, br.edited, br.series_code, br.sequence
      FROM judged j
      LEFT JOIN people.matric_batch mb ON mb.session = p_session AND mb.faculty_code = j.faculty_code AND mb.state NOT IN ('ISSUED', 'CANCELLED')
      LEFT JOIN people.matric_batch_row br ON br.batch_id = mb.id AND br.student_id = j.id AND br.state <> 'DROPPED'
     ORDER BY j.surname, j.other_names;
$$;

-- ── grants: the API roles read and write the new tables as they do the application ──────────
GRANT SELECT, INSERT, UPDATE ON admissions.pg_screening, admissions.pg_screening_policy TO app_admissions;
GRANT SELECT ON admissions.pg_screening, admissions.pg_screening_policy TO app_iam, app_auditor, app_student, app_registration, app_finance;

COMMIT;
