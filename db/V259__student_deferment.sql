-- ═══════════════════════════════════════════════════════════════════════════
-- V259 · Deferment: a semester or a session set aside, on the record
--
--   A student who cannot study for a semester or a session asks to defer it.
--   The request goes to the department, the faculty and the Registry in turn;
--   approved, it holds the period: the student cannot register for it on any
--   of the University's registers (the course form, the Postgraduate School's
--   form, the College's enrolment), the status reads DEFERRED while the period
--   runs, the semester does not count toward voluntary withdrawal, and the
--   return session and semester are named from the calendar. When the period
--   ends the desk confirms the return and the status is restored. Nothing on
--   the student's record is deleted: registrations, payments, results and
--   research stay as they were; the deferment is one more thing the record
--   holds, with every turn it took.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V259: student deferment', true);

-- ── 1 · what the University manages: the reasons and the limits ───────────

CREATE TABLE people.deferment_reason (
    code            text PRIMARY KEY,
    label           text NOT NULL,
    needs_document  boolean NOT NULL DEFAULT false,
    needs_words     boolean NOT NULL DEFAULT false,
    ord             int NOT NULL DEFAULT 0,
    active          boolean NOT NULL DEFAULT true
);
SELECT audit.attach('people.deferment_reason');
INSERT INTO people.deferment_reason (code, label, needs_document, needs_words, ord) VALUES
    ('MEDICAL',     'Medical',                true,  false, 1),
    ('FINANCIAL',   'Financial',              false, true,  2),
    ('FAMILY',      'Family circumstances',   false, true,  3),
    ('MATERNITY',   'Pregnancy or childbirth', true, false, 4),
    ('EMPLOYMENT',  'Employment',             true,  false, 5),
    ('RELOCATION',  'Relocation',             false, true,  6),
    ('BEREAVEMENT', 'Bereavement',            false, true,  7),
    ('PERSONAL',    'Personal reasons',       false, true,  8),
    ('OTHER',       'Other',                  false, true,  9);

CREATE TABLE people.deferment_setting (
    id                    int PRIMARY KEY CHECK (id = 1),
    max_sessions          numeric(3,1) NOT NULL DEFAULT 2,     -- the most a student may defer in all: a session counts 1, a semester 0.5
    allow_extension       boolean NOT NULL DEFAULT true,
    reminder_days         int NOT NULL DEFAULT 14,
    overdue_after_days    int NOT NULL DEFAULT 30
);
SELECT audit.attach('people.deferment_setting');
INSERT INTO people.deferment_setting (id) VALUES (1);

-- ── 2 · the request, the documents, the trail ─────────────────────────────

CREATE TABLE people.deferment (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference        text NOT NULL UNIQUE,
    student_id       uuid NOT NULL REFERENCES people.student(id),
    kind             text NOT NULL,
    session          text NOT NULL REFERENCES policy.academic_session(name),
    semester         int  NULL,
    reason_code      text NOT NULL REFERENCES people.deferment_reason(code),
    explanation      text NULL,
    declared         boolean NOT NULL DEFAULT false,
    state            text NOT NULL DEFAULT 'DRAFT',
    extension_of     uuid NULL REFERENCES people.deferment(id),
    -- the period, and the return the calendar names
    period_from      date NULL,
    return_session   text NULL,
    return_semester  int  NULL,
    return_on        date NULL,
    -- each desk's word
    submitted_at     timestamptz NULL,
    dept_at          timestamptz NULL, dept_by uuid NULL REFERENCES iam.person(id), dept_note text NULL,
    fac_at           timestamptz NULL, fac_by  uuid NULL REFERENCES iam.person(id), fac_note  text NULL,
    decided_at       timestamptz NULL, decided_by uuid NULL REFERENCES iam.person(id), decision_note text NULL,
    correction_note  text NULL,
    cancel_note      text NULL,
    -- the period in force, and the return
    prior_status     text NULL,
    activated_at     timestamptz NULL,
    reminder_sent_at timestamptz NULL,
    returned_at      timestamptz NULL, returned_by uuid NULL REFERENCES iam.person(id), return_note text NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_def_ref      CHECK (reference ~ '^DEF-[0-9]{4}-[0-9]{5}$'),
    CONSTRAINT ck_def_kind     CHECK (kind IN ('SEMESTER','SESSION')),
    CONSTRAINT ck_def_semester CHECK ((kind = 'SESSION' AND semester IS NULL) OR (kind = 'SEMESTER' AND semester BETWEEN 1 AND 3)),
    CONSTRAINT ck_def_state    CHECK (state IN ('DRAFT','SUBMITTED','CORRECTION_REQUIRED','DEPT_RECOMMENDED','FAC_RECOMMENDED',
                                                'APPROVED','ACTIVE','COMPLETED','REJECTED','CANCELLED'))
);
CREATE INDEX ix_deferment_student ON people.deferment (student_id, created_at DESC);
CREATE INDEX ix_deferment_state ON people.deferment (state, session);
-- one live request per student and period: a second is refused by the index, whatever the screen says
CREATE UNIQUE INDEX uq_deferment_live_period ON people.deferment (student_id, session, coalesce(semester, 0))
    WHERE state NOT IN ('REJECTED','CANCELLED','COMPLETED');
SELECT audit.attach('people.deferment');
COMMENT ON TABLE people.deferment IS
  'A student''s request to defer a semester or a session, the desks'' words on it, the period it holds once approved and the return the calendar names.';

CREATE TABLE people.deferment_document (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    deferment_id  uuid NOT NULL REFERENCES people.deferment(id) ON DELETE CASCADE,
    kind          text NOT NULL,
    filename      text NOT NULL,
    content_type  text NOT NULL,
    size_bytes    int  NOT NULL,
    uploaded_by   uuid NULL,
    uploaded_at   timestamptz NOT NULL DEFAULT now(),
    verified_at   timestamptz NULL,
    verified_by   uuid NULL REFERENCES iam.person(id),
    CONSTRAINT ck_defdoc_kind CHECK (kind IN ('MEDICAL','FINANCIAL','OFFICIAL_LETTER','EMPLOYER_LETTER','OTHER')),
    CONSTRAINT ck_defdoc_type CHECK (content_type IN ('application/pdf','image/jpeg','image/png')),
    CONSTRAINT ck_defdoc_size CHECK (size_bytes BETWEEN 1 AND 5242880)
);
CREATE INDEX ix_deferment_document ON people.deferment_document (deferment_id, uploaded_at);
SELECT audit.attach('people.deferment_document');

CREATE TABLE people.deferment_document_blob (
    document_id uuid PRIMARY KEY REFERENCES people.deferment_document(id) ON DELETE CASCADE,
    bytes       bytea NOT NULL
);
SELECT audit.exempt('people.deferment_document_blob', 'The bytes of a supporting document; the document row on the spine records who uploaded it and when.');

CREATE TABLE people.deferment_event (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    deferment_id  uuid NOT NULL REFERENCES people.deferment(id) ON DELETE CASCADE,
    action        text NOT NULL,
    from_state    text NULL,
    to_state      text NULL,
    actor_id      uuid NULL,
    actor_office  text NULL,
    note          text NULL,
    at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_deferment_event ON people.deferment_event (deferment_id, at);
SELECT audit.attach('people.deferment_event');

CREATE OR REPLACE FUNCTION people.deferment_history_is_written_once()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('moaum.maintenance', true) = 'on' THEN RETURN COALESCE(NEW, OLD); END IF;
    RAISE EXCEPTION 'the deferment trail is written once; it is not edited or removed' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_deferment_event_written_once BEFORE UPDATE OR DELETE ON people.deferment_event
FOR EACH ROW EXECUTE FUNCTION people.deferment_history_is_written_once();

CREATE OR REPLACE FUNCTION people.deferment_log(p_id uuid, p_action text, p_from text, p_to text, p_note text)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO people.deferment_event (deferment_id, action, from_state, to_state, actor_id, actor_office, note)
    VALUES (p_id, p_action, p_from, p_to, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''), p_note);
$$;

/* the student told, by email and text, from the same outbox as everything else */
CREATE OR REPLACE FUNCTION people.deferment_tell(p_id uuid, p_subject text, p_body text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE d people.deferment; reach record;
BEGIN
    SELECT * INTO d FROM people.deferment WHERE id = p_id;
    SELECT * INTO reach FROM people.student_reach(d.student_id);
    PERFORM platform.queue_notice('EMAIL', reach.email, p_subject, p_body || E'\n\nDeferment reference: ' || d.reference || E'\nOffice of the Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi', 'student', d.student_id);
    PERFORM platform.queue_notice('SMS', reach.phone, p_subject, 'MOAUM: ' || left(p_body, 120) || ' Ref ' || d.reference || '. See the portal.', 'student', d.student_id);
END $$;

/* the desk told: every holder of an office over the student's department (or faculty), by email */
CREATE OR REPLACE FUNCTION people.deferment_tell_desk(p_id uuid, p_office text, p_subject text, p_body text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE d people.deferment; v_dept text; v_fac text; r record;
BEGIN
    SELECT * INTO d FROM people.deferment WHERE id = p_id;
    SELECT p.dept_code, p.faculty_code INTO v_dept, v_fac FROM people.student s JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = d.student_id;
    FOR r IN
        SELECT DISTINCT pe.email FROM iam.office_assignment a JOIN iam.person pe ON pe.id = a.person_id
         WHERE a.office_code = p_office AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) AND pe.email IS NOT NULL
           AND (a.scope_id IS NULL OR btrim(a.scope_id) = '' OR upper(btrim(a.scope_id)) IN (upper(v_dept), upper(v_fac))
                OR lower(btrim(a.scope_id)) IN (SELECT lower(name) FROM ref.department WHERE code = v_dept UNION SELECT lower(name) FROM ref.faculty WHERE code = v_fac))
    LOOP
        PERFORM platform.queue_notice('EMAIL', r.email, p_subject, p_body || E'\n\nDeferment reference: ' || d.reference, 'deferment', d.id);
    END LOOP;
END $$;

-- ── 3 · the calendar: when the period begins, and when the student returns ─

/* the session after a session on the calendar, or its name computed when the calendar does not yet hold it */
CREATE OR REPLACE FUNCTION people.next_session(p_session text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT name FROM policy.academic_session WHERE name > p_session ORDER BY name LIMIT 1),
                    (left(p_session, 4)::int + 1)::text || '/' || (left(p_session, 4)::int + 2)::text);
$$;

/* the day a period begins: the semester's lectures or registration, else the session's start */
CREATE OR REPLACE FUNCTION people.period_start(p_session text, p_semester int)
RETURNS date LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT coalesce(sm.lectures_from, sm.registration_opens) FROM policy.semester sm WHERE sm.session = p_session AND sm.number = p_semester),
        CASE WHEN p_semester IS NULL OR p_semester = 1 THEN (SELECT starts_on FROM policy.academic_session WHERE name = p_session)
             ELSE (SELECT (starts_on + interval '5 months')::date FROM policy.academic_session WHERE name = p_session) END,
        make_date(left(p_session, 4)::int, 10, 1));
$$;

/* where a deferred period ends and the student returns: the next semester of the same session, or the next session's first */
CREATE OR REPLACE FUNCTION people.deferment_return(p_kind text, p_session text, p_semester int)
RETURNS TABLE (return_session text, return_semester int, return_on date)
LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT coalesce((SELECT semesters FROM policy.academic_session WHERE name = p_session), 2) AS n)
    SELECT CASE WHEN p_kind = 'SEMESTER' AND p_semester < s.n THEN p_session ELSE people.next_session(p_session) END,
           CASE WHEN p_kind = 'SEMESTER' AND p_semester < s.n THEN p_semester + 1 ELSE 1 END,
           people.period_start(CASE WHEN p_kind = 'SEMESTER' AND p_semester < s.n THEN p_session ELSE people.next_session(p_session) END,
                               CASE WHEN p_kind = 'SEMESTER' AND p_semester < s.n THEN p_semester + 1 ELSE 1 END)
      FROM s;
$$;

-- ── 4 · eligibility, the request, the desks ───────────────────────────────

CREATE OR REPLACE FUNCTION people.deferment_new_reference()
RETURNS text LANGUAGE sql AS $$
    SELECT 'DEF-' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '-'
        || lpad(platform.next_number('DEFERMENT', 'UNIVERSITY', to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY'))::text, 5, '0');
$$;

/* how much of the allowance a student has used: an approved, active or completed session counts one, a semester a half */
CREATE OR REPLACE FUNCTION people.deferment_used(p_student uuid)
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT coalesce(sum(CASE WHEN kind = 'SESSION' THEN 1 ELSE 0.5 END), 0)
      FROM people.deferment WHERE student_id = p_student AND state IN ('APPROVED','ACTIVE','COMPLETED');
$$;

/* may this student ask to defer now, and if not, why not — the rules the University applies, in one place */
CREATE OR REPLACE FUNCTION people.deferment_eligibility(p_student uuid)
RETURNS TABLE (eligible boolean, reason text, used numeric, allowed numeric, live_reference text)
LANGUAGE plpgsql STABLE AS $$
DECLARE s people.student; st people.deferment_setting; live people.deferment; v_used numeric;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    SELECT * INTO st FROM people.deferment_setting WHERE id = 1;
    v_used := people.deferment_used(p_student);
    SELECT * INTO live FROM people.deferment d WHERE d.student_id = p_student AND d.state NOT IN ('REJECTED','CANCELLED','COMPLETED')
     ORDER BY d.created_at DESC LIMIT 1;
    IF s.id IS NULL THEN RETURN QUERY SELECT false, 'No student record.', v_used, st.max_sessions, NULL::text; RETURN; END IF;
    IF s.status = 'GRADUATED' THEN RETURN QUERY SELECT false, 'A graduated student does not defer.', v_used, st.max_sessions, NULL::text; RETURN; END IF;
    IF s.status IN ('WITHDRAWN','VOLUNTARY_WITHDRAWAL','EXPELLED','TRANSFERRED_OUT','DECEASED','RUSTICATED') THEN
        RETURN QUERY SELECT false, 'A record that is ' || lower(replace(s.status, '_', ' ')) || ' does not defer.', v_used, st.max_sessions, NULL::text; RETURN;
    END IF;
    IF s.status = 'SUSPENDED' THEN RETURN QUERY SELECT false, 'A suspended student does not defer while the suspension runs.', v_used, st.max_sessions, NULL::text; RETURN; END IF;
    IF s.status = 'DEFERRED' AND live.id IS NOT NULL AND live.state = 'ACTIVE' THEN
        IF st.allow_extension THEN RETURN QUERY SELECT true, NULL::text, v_used, st.max_sessions, live.reference; RETURN; END IF;
        RETURN QUERY SELECT false, 'Your deferment ' || live.reference || ' is in force; a further period is not granted.', v_used, st.max_sessions, live.reference; RETURN;
    END IF;
    IF s.matric_no IS NULL THEN RETURN QUERY SELECT false, 'Deferment is asked for once you are matriculated (fees paid and courses registered for your first semester).', v_used, st.max_sessions, NULL::text; RETURN; END IF;
    IF live.id IS NOT NULL AND live.state <> 'ACTIVE' THEN
        RETURN QUERY SELECT false, 'You already have a deferment request ' || live.reference || ' (' || lower(replace(live.state, '_', ' ')) || ') for ' || live.session ||
            coalesce(' semester ' || live.semester, '') || '. One request is decided before another is made.', v_used, st.max_sessions, live.reference; RETURN;
    END IF;
    IF v_used >= st.max_sessions THEN
        RETURN QUERY SELECT false, 'You have deferred ' || v_used || ' session(s) in all; the University allows ' || st.max_sessions || '.', v_used, st.max_sessions, NULL::text; RETURN;
    END IF;
    RETURN QUERY SELECT true, NULL::text, v_used, st.max_sessions, live.reference;
END $$;

/* the student's draft: opened, or changed while it is theirs to change */
CREATE OR REPLACE FUNCTION people.deferment_save(p_student uuid, p_id uuid, p_kind text, p_session text, p_semester int, p_reason text, p_explanation text, p_declared boolean, p_extension_of uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE d people.deferment; e record; v_id uuid; v_sem int; v_ret record; st people.deferment_setting;
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
                                      period_from, return_session, return_semester, return_on)
        VALUES (people.deferment_new_reference(), p_student, p_kind, p_session, v_sem, p_reason, nullif(btrim(coalesce(p_explanation, '')), ''), coalesce(p_declared, false), p_extension_of,
                people.period_start(p_session, v_sem), v_ret.return_session, v_ret.return_semester, v_ret.return_on)
        RETURNING id INTO v_id;
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

/* the student submits: the reason is complete, the documents the reason needs are in, the declaration is made */
CREATE OR REPLACE FUNCTION people.deferment_submit(p_student uuid, p_id uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE d people.deferment; r people.deferment_reason; v_docs int;
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
    UPDATE people.deferment SET state = 'SUBMITTED', submitted_at = now(), correction_note = NULL, updated_at = now() WHERE id = d.id;
    PERFORM people.deferment_log(d.id, 'SUBMITTED', d.state, 'SUBMITTED', NULL);
    PERFORM people.deferment_tell(d.id, 'Your deferment request has been received',
        'Your request to defer ' || d.session || coalesce(' semester ' || d.semester, ' (the whole session)') || ' has been submitted to your department for review. You will be told at each turn.');
    PERFORM people.deferment_tell_desk(d.id, 'hod', 'A deferment request awaits the department',
        'A student of your department has submitted a request to defer ' || d.session || coalesce(' semester ' || d.semester, '') || '. Open the deferments desk on the portal to review it.');
    RETURN 'submitted';
END $$;

/* the desks' words: the department recommends, the faculty recommends, the Registry approves; each may return the request
   for correction or reject it with the reason; the student may cancel before the period is in force */
CREATE OR REPLACE FUNCTION people.deferment_decide(p_id uuid, p_action text, p_note text, p_actor uuid, p_office text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE d people.deferment; v_from text; v_to text; v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
    SELECT * INTO d FROM people.deferment WHERE id = p_id FOR UPDATE;
    IF d.id IS NULL THEN RAISE EXCEPTION 'no such deferment request' USING ERRCODE = '23503'; END IF;
    v_from := d.state;
    CASE p_action
        WHEN 'RECOMMEND' THEN
            IF d.state <> 'SUBMITTED' THEN RAISE EXCEPTION 'the department recommends a submitted request; this one is %', lower(replace(d.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
            v_to := 'DEPT_RECOMMENDED';
            UPDATE people.deferment SET state = v_to, dept_at = now(), dept_by = p_actor, dept_note = v_note, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_tell(d.id, 'Your deferment request is recommended by the department', 'The department has recommended your request; it is now with the faculty.');
            PERFORM people.deferment_tell_desk(d.id, 'dean', 'A deferment request awaits the faculty', 'The department has recommended a student''s deferment request; the faculty''s word is next on the deferments desk.');
        WHEN 'FAC_RECOMMEND' THEN
            IF d.state <> 'DEPT_RECOMMENDED' THEN RAISE EXCEPTION 'the faculty recommends a request the department has recommended; this one is %', lower(replace(d.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
            v_to := 'FAC_RECOMMENDED';
            UPDATE people.deferment SET state = v_to, fac_at = now(), fac_by = p_actor, fac_note = v_note, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_tell(d.id, 'Your deferment request is recommended by the faculty', 'The faculty has recommended your request; it is now with the Registry for approval.');
            PERFORM people.deferment_tell_desk(d.id, 'academic', 'A deferment request awaits approval', 'A deferment request recommended by the department and the faculty awaits the Registry''s approval on the deferments desk.');
        WHEN 'APPROVE' THEN
            IF d.state NOT IN ('FAC_RECOMMENDED','DEPT_RECOMMENDED') THEN RAISE EXCEPTION 'a request is approved after the department and the faculty have recommended it; this one is %', lower(replace(d.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
            v_to := 'APPROVED';
            UPDATE people.deferment SET state = v_to, decided_at = now(), decided_by = p_actor, decision_note = v_note, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_tell(d.id, 'Your deferment request ' || d.reference || ' has been approved',
                'Your deferment of ' || d.session || coalesce(' semester ' || d.semester, ' (the whole session)') || ' is approved. You cannot register courses for that period. Your expected return is '
                || d.return_session || ' semester ' || d.return_semester || '. Download your approval letter from the portal.');
            -- the period already begun holds at once
            PERFORM people.deferments_tick();
        WHEN 'REJECT' THEN
            IF d.state NOT IN ('SUBMITTED','DEPT_RECOMMENDED','FAC_RECOMMENDED') THEN RAISE EXCEPTION 'a request in review is rejected; this one is %', lower(replace(d.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
            IF v_note IS NULL THEN RAISE EXCEPTION 'a rejection carries its reason' USING ERRCODE = '23514', HINT = 'Say why the request is refused; the student reads it.'; END IF;
            v_to := 'REJECTED';
            UPDATE people.deferment SET state = v_to, decided_at = now(), decided_by = p_actor, decision_note = v_note, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_tell(d.id, 'Your deferment request has been rejected', 'Your request to defer ' || d.session || coalesce(' semester ' || d.semester, '') || ' was not approved. Reason: ' || v_note);
        WHEN 'CORRECTION' THEN
            IF d.state NOT IN ('SUBMITTED','DEPT_RECOMMENDED','FAC_RECOMMENDED') THEN RAISE EXCEPTION 'a request in review is returned for correction; this one is %', lower(replace(d.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
            IF v_note IS NULL THEN RAISE EXCEPTION 'say what the student must correct' USING ERRCODE = '23514'; END IF;
            v_to := 'CORRECTION_REQUIRED';
            UPDATE people.deferment SET state = v_to, correction_note = v_note, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_tell(d.id, 'Your deferment request requires correction', 'Your request has been returned to you: ' || v_note || ' Correct it on the portal and submit it again.');
        WHEN 'CANCEL' THEN
            IF d.state NOT IN ('DRAFT','SUBMITTED','CORRECTION_REQUIRED','DEPT_RECOMMENDED','FAC_RECOMMENDED','APPROVED') THEN
                RAISE EXCEPTION 'a deferment in force is not cancelled; the student returns from it' USING ERRCODE = '23514';
            END IF;
            IF v_note IS NULL THEN RAISE EXCEPTION 'a cancellation carries its reason' USING ERRCODE = '23514'; END IF;
            v_to := 'CANCELLED';
            UPDATE people.deferment SET state = v_to, cancel_note = v_note, updated_at = now() WHERE id = d.id;
            IF d.state IN ('SUBMITTED','DEPT_RECOMMENDED','FAC_RECOMMENDED','APPROVED') THEN
                PERFORM people.deferment_tell(d.id, 'Your deferment request has been cancelled', 'The deferment request ' || d.reference || ' is cancelled: ' || v_note);
            END IF;
        ELSE RAISE EXCEPTION 'unknown action %', p_action USING ERRCODE = '23514';
    END CASE;
    PERFORM people.deferment_log(d.id, p_action, v_from, v_to, v_note);
    RETURN v_to;
END $$;

/* the return confirmed by the desk: the status restored, the record told */
CREATE OR REPLACE FUNCTION people.deferment_confirm_return(p_id uuid, p_note text, p_actor uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE d people.deferment; s people.student; v_back text;
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
    PERFORM people.deferment_log(d.id, 'RETURNED', d.state, 'COMPLETED', nullif(btrim(coalesce(p_note, '')), ''));
    PERFORM people.deferment_tell(d.id, 'Welcome back — your return from deferment is confirmed',
        'Your return for ' || d.return_session || ' semester ' || d.return_semester || ' is confirmed. Pay your school fees and register your courses for the period on the portal as usual.');
    RETURN 'returned';
END $$;

-- ── 5 · the clock: the period holds when it begins; the return is reminded ──

CREATE OR REPLACE FUNCTION people.deferments_tick()
RETURNS int LANGUAGE plpgsql AS $$
DECLARE d record; st people.deferment_setting; n int := 0; s people.student;
BEGIN
    SELECT * INTO st FROM people.deferment_setting WHERE id = 1;
    -- approved, and the period has begun (or the session is the current one and the semester open): in force
    FOR d IN
        SELECT x.* FROM people.deferment x
         WHERE x.state = 'APPROVED'
           AND (current_date >= x.period_from
                OR EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = x.session AND a.state = 'CURRENT'
                             AND (x.kind = 'SESSION' OR EXISTS (SELECT 1 FROM policy.semester sm WHERE sm.session = x.session AND sm.number = x.semester AND sm.state = 'OPEN'))))
    LOOP
        SELECT * INTO s FROM people.student WHERE id = d.student_id;
        UPDATE people.deferment SET state = 'ACTIVE', activated_at = now(), prior_status = s.status, updated_at = now() WHERE id = d.id;
        IF s.status IN ('ACTIVE','PROBATION','ADMITTED') AND s.matric_no IS NOT NULL THEN
            PERFORM people.change_status(s.id, 'DEFERRED', d.reference, current_date, 'Deferment in force');
            UPDATE people.status_change SET expires_on = d.return_on WHERE id = (SELECT id FROM people.status_change WHERE student_id = s.id ORDER BY effective_on DESC, id DESC LIMIT 1);
        END IF;
        PERFORM people.deferment_log(d.id, 'ACTIVATED', 'APPROVED', 'ACTIVE', 'The deferred period has begun');
        PERFORM people.deferment_tell(d.id, 'Your deferment is now in force', 'Your deferment of ' || d.session || coalesce(' semester ' || d.semester, '') || ' is in force. Your expected return is ' || d.return_session || ' semester ' || d.return_semester || '.');
        n := n + 1;
    END LOOP;
    -- the return approaching: reminded once
    FOR d IN
        SELECT x.* FROM people.deferment x
         WHERE x.state = 'ACTIVE' AND x.reminder_sent_at IS NULL AND x.return_on IS NOT NULL AND x.return_on <= current_date + st.reminder_days
    LOOP
        UPDATE people.deferment SET reminder_sent_at = now() WHERE id = d.id;
        PERFORM people.deferment_tell(d.id, 'Your deferment is ending soon',
            'Your approved deferment ends on ' || to_char(d.return_on, 'DD Month YYYY') || '. Review your school fees and course registration for ' || d.return_session || ' semester ' || d.return_semester || '; the desk confirms your return.');
        PERFORM people.deferment_tell_desk(d.id, 'hod', 'A student is due to return from deferment', 'A student of your department is due to return from deferment on ' || to_char(d.return_on, 'DD Month YYYY') || '. Confirm the return on the deferments desk when they present themselves.');
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

/* where a deferment in force stands against its return date */
CREATE OR REPLACE FUNCTION people.deferment_return_status(p_state text, p_return_on date)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN p_state = 'COMPLETED' THEN 'RETURNED'
                WHEN p_state NOT IN ('ACTIVE','APPROVED') THEN NULL
                WHEN p_return_on IS NULL THEN 'UPCOMING'
                WHEN current_date > p_return_on + (SELECT overdue_after_days FROM people.deferment_setting WHERE id = 1) THEN 'OVERDUE'
                WHEN current_date >= p_return_on - (SELECT reminder_days FROM people.deferment_setting WHERE id = 1) THEN 'DUE'
                ELSE 'UPCOMING' END;
$$;

-- ── 6 · the period held on every register ─────────────────────────────────

/* true when an approved or active deferment covers the period (the whole session, or that semester) */
CREATE OR REPLACE FUNCTION people.deferment_covers(p_student uuid, p_session text, p_semester int)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM people.deferment d
                    WHERE d.student_id = p_student AND d.session = p_session AND d.state IN ('APPROVED','ACTIVE')
                      AND (d.kind = 'SESSION' OR p_semester IS NULL OR d.semester = p_semester));
$$;

CREATE OR REPLACE FUNCTION people.deferment_refuse(p_student uuid, p_session text, p_semester int)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('moaum.deferment_override', true) = 'on' THEN RETURN; END IF;
    IF people.deferment_covers(p_student, p_session, p_semester) THEN
        RAISE EXCEPTION 'REGISTRATION UNAVAILABLE: your deferment for % is approved; you cannot register for the deferred period',
            p_session || coalesce(' semester ' || p_semester, '')
            USING ERRCODE = '23514', HINT = 'The deferred period is held on the record. Registration resumes in your return session; the Registry may lift it on the record if the deferment is cancelled.';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION people.deferment_gate_course_registration()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' OR (NEW.status = 'SUBMITTED' AND NEW.status IS DISTINCT FROM OLD.status) THEN
        PERFORM people.deferment_refuse(NEW.student_id, NEW.session, NEW.semester);
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_deferment_gate_registration BEFORE INSERT OR UPDATE OF status ON registration.course_registration
FOR EACH ROW EXECUTE FUNCTION people.deferment_gate_course_registration();

CREATE OR REPLACE FUNCTION people.deferment_gate_pg_registration()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' OR (NEW.state = 'SUBMITTED' AND NEW.state IS DISTINCT FROM OLD.state) THEN
        PERFORM people.deferment_refuse(NEW.student_id, NEW.session, NEW.semester);
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_deferment_gate_pg_registration BEFORE INSERT OR UPDATE OF state ON admissions.pg_registration
FOR EACH ROW EXECUTE FUNCTION people.deferment_gate_pg_registration();

CREATE OR REPLACE FUNCTION people.deferment_gate_college_semester()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE e college.enrolment;
BEGIN
    IF NEW.registered_at IS NOT NULL AND OLD.registered_at IS NULL THEN
        SELECT * INTO e FROM college.enrolment WHERE id = NEW.enrolment_id;
        PERFORM people.deferment_refuse(e.student_id, e.session, NEW.ordinal);
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_deferment_gate_college_semester BEFORE UPDATE OF registered_at ON college.enrolment_semester
FOR EACH ROW EXECUTE FUNCTION people.deferment_gate_college_semester();

CREATE OR REPLACE FUNCTION people.deferment_gate_college_year()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.registered_at IS NOT NULL AND OLD.registered_at IS NULL THEN
        PERFORM people.deferment_refuse(NEW.student_id, NEW.session, NULL);
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_deferment_gate_college_year BEFORE UPDATE OF registered_at ON college.enrolment
FOR EACH ROW EXECUTE FUNCTION people.deferment_gate_college_year();

-- ── 7 · a deferred semester is not a missed one ───────────────────────────

CREATE OR REPLACE FUNCTION registration.semesters_unregistered(p_student uuid)
RETURNS TABLE (semesters int, last_registered text, first_missed text)
LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT * FROM people.student WHERE id = p_student),
    reg AS (SELECT r.session, r.semester FROM registration.course_registration r
             WHERE r.student_id = p_student AND r.status IN ('APPROVED','LOCKED')),
    missed AS (
        SELECT c.session, c.semester FROM registration.closed_semesters() c CROSS JOIN s
         WHERE c.session >= s.entry_session
           AND NOT EXISTS (SELECT 1 FROM reg WHERE (reg.session, reg.semester) >= (c.session, c.semester))
           -- a semester set aside by an approved deferment was not missed
           AND NOT EXISTS (SELECT 1 FROM people.deferment d WHERE d.student_id = p_student AND d.session = c.session
                             AND d.state IN ('APPROVED','ACTIVE','COMPLETED') AND (d.kind = 'SESSION' OR d.semester = c.semester))
    ),
    word AS (SELECT 1 AS n, 'first' AS w UNION ALL SELECT 2, 'second' UNION ALL SELECT 3, 'third')
    SELECT (SELECT count(*) FROM missed)::int,
           (SELECT r.session || ' ' || coalesce(w.w, r.semester::text) || ' semester' FROM reg r LEFT JOIN word w ON w.n = r.semester ORDER BY r.session DESC, r.semester DESC LIMIT 1),
           (SELECT m.session || ' ' || coalesce(w.w, m.semester::text) || ' semester' FROM missed m LEFT JOIN word w ON w.n = m.semester ORDER BY m.session, m.semester LIMIT 1)
$$;

-- ── grants ────────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE ON people.deferment, people.deferment_document, people.deferment_event, people.deferment_reason, people.deferment_setting TO app_student;
GRANT SELECT, INSERT ON people.deferment_document_blob TO app_student;
GRANT SELECT ON people.deferment, people.deferment_document, people.deferment_event, people.deferment_reason, people.deferment_setting TO app_auditor;

COMMIT;
