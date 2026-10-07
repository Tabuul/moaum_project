-- V358: a published result corrected through the approval chain; offers that lapse and a waiting list that moves.
--
-- 1. An amendment of a published result: one student's mark on a published sheet, raised by the lecturer (or the
--    Programme Examinations Officer on the lecturer's behalf) with the reason — linked to the result query answered
--    CORRECTED that asked for it, when there is one — then approved stage by stage by each desk of the chain (V357's rule),
--    and applied by the Registrar on the Senate minute: a new version of the mark, the original kept, the student told
--    (no mark in the message), the documents already issued flagged as before. Any desk may refuse it with the reason;
--    the person who raised it may withdraw it. Nothing on the sheet itself changes.
-- 2. Offers that lapse and a waiting list that moves, decided by the Admissions Office: the session's acceptance deadline
--    (a date, or days after an offer's own release — never assumed: without one no offer lapses); the offers past it,
--    neither accepted nor paid for, lapsed when the office says so; each place freed by a lapse or a decline filled from the
--    waiting list in merit order by the office's choice, the place's quota basis shown; the promoted told as any decision
--    is. A lapsed offer is not taken up: its undertaking and a new acceptance fee are refused.
BEGIN;

-- ── 1 · amendments of a published result ────────────────────────────────────────────────────────────────────────
CREATE TABLE assessment.amendment (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref            text NOT NULL UNIQUE CHECK (ref ~ '^AMD-[0-9]{4}-[0-9]{5}$'),
    sheet_id       uuid NOT NULL REFERENCES assessment.score_sheet(id),
    student_id     uuid NOT NULL REFERENCES people.student(id),
    query_id       uuid NULL REFERENCES assessment.result_query(id),
    was_version    int NOT NULL,
    was_ca         int NULL,
    was_exam       int NULL,
    was_outcome    text NOT NULL,
    ca             int NULL CHECK (ca IS NULL OR ca BETWEEN 0 AND 100),
    exam           int NULL CHECK (exam IS NULL OR exam BETWEEN 0 AND 100),
    outcome        text NOT NULL CHECK (outcome IN ('GRADED', 'ABSENT', 'WITHHELD', 'INCOMPLETE', 'MALPRACTICE', 'EXEMPTED')),
    reason         text NOT NULL CHECK (length(btrim(reason)) >= 10),
    stage          text NOT NULL DEFAULT 'VERIFICATION'
                   CHECK (stage IN ('VERIFICATION', 'DEPT_BOARD', 'FACULTY_SCRUTINY', 'FACULTY_COMPILATION', 'FACULTY_BOARD', 'RECORDS', 'SENATE',
                                    'APPLIED', 'REFUSED', 'WITHDRAWN')),
    raised_by      uuid NULL,
    raised_office  text NULL,
    raised_at      timestamptz NOT NULL DEFAULT now(),
    senate_minute  text NULL,
    applied_at     timestamptz NULL,
    applied_version int NULL,
    closed_at      timestamptz NULL,
    closed_reason  text NULL,
    CONSTRAINT ck_amendment_graded CHECK (outcome <> 'GRADED' OR (ca IS NOT NULL AND exam IS NOT NULL AND ca + exam <= 100)),
    CONSTRAINT ck_amendment_applied CHECK ((stage = 'APPLIED') = (applied_at IS NOT NULL)),
    CONSTRAINT ck_amendment_closed CHECK ((stage IN ('REFUSED', 'WITHDRAWN')) = (closed_reason IS NOT NULL))
);
CREATE UNIQUE INDEX ux_amendment_open ON assessment.amendment (sheet_id, student_id) WHERE stage NOT IN ('APPLIED', 'REFUSED', 'WITHDRAWN');
CREATE INDEX ix_amendment_stage ON assessment.amendment (stage) WHERE stage NOT IN ('APPLIED', 'REFUSED', 'WITHDRAWN');
SELECT audit.attach('assessment.amendment');
COMMENT ON TABLE assessment.amendment IS 'V358: a correction of one student''s published mark — raised with its reason, approved by each desk of the chain, applied on the Senate minute as a new version of the mark; the original is kept.';

CREATE TABLE assessment.amendment_decision (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    amendment_id uuid NOT NULL REFERENCES assessment.amendment(id),
    from_stage   text NULL,
    to_stage     text NOT NULL,
    kind         text NOT NULL CHECK (kind IN ('RAISE', 'ADVANCE', 'APPLY', 'REFUSE', 'WITHDRAW')),
    actor_id     uuid NULL,
    actor_office text NULL,
    comment      text NULL,
    decided_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_amendment_decision ON assessment.amendment_decision (amendment_id, decided_at);
SELECT audit.attach('assessment.amendment_decision');

/* raised by the desk of entry on a published sheet, for a student with a mark on it, with something to change */
CREATE OR REPLACE FUNCTION assessment.raise_amendment(p_sheet uuid, p_student uuid, p_ca int, p_exam int, p_outcome text, p_reason text, p_query uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_stage text; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), ''); was record; v_out text := upper(coalesce(nullif(btrim(p_outcome), ''), 'GRADED'));
        v_ca int; v_exam int; v_ca_max int; v_code text; v_query uuid := p_query; v_id uuid; v_year text := to_char(current_date, 'YYYY');
BEGIN
    PERFORM assessment.require_stage_desk('ENTRY', v_office, 'raised');
    SELECT s.stage, c.ca_max, c.code INTO v_stage, v_ca_max, v_code
      FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id JOIN catalogue.course c ON c.code = o.course_code WHERE s.id = p_sheet;
    IF v_stage IS NULL THEN RAISE EXCEPTION 'no score sheet %', p_sheet USING ERRCODE = 'no_data_found'; END IF;
    IF v_stage <> 'PUBLISHED' THEN
        RAISE EXCEPTION 'RES_AMEND_NOT_PUBLISHED: the sheet is at %; before publication a mark is corrected by returning the sheet', lower(replace(v_stage, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO was FROM assessment.latest_scores(p_sheet) x WHERE x.student_id = p_student;
    IF was.student_id IS NULL THEN RAISE EXCEPTION 'RES_AMEND_NO_MARK: the student has no mark on this sheet' USING ERRCODE = '23514'; END IF;
    IF v_out NOT IN ('GRADED', 'ABSENT', 'WITHHELD', 'INCOMPLETE', 'MALPRACTICE', 'EXEMPTED') THEN
        RAISE EXCEPTION 'RES_AMEND_OUTCOME: no such outcome %', v_out USING ERRCODE = '23514';
    END IF;
    v_ca := CASE WHEN v_out = 'GRADED' THEN p_ca END;
    v_exam := CASE WHEN v_out = 'GRADED' THEN p_exam END;
    IF v_out = 'GRADED' AND (v_ca IS NULL OR v_exam IS NULL) THEN RAISE EXCEPTION 'RES_AMEND_MARKS: a graded mark carries both the CA and the examination' USING ERRCODE = '23514'; END IF;
    IF v_ca > v_ca_max OR v_exam > 100 - v_ca_max THEN
        RAISE EXCEPTION 'RES_AMEND_SPLIT: % assesses % and examines %', v_code, v_ca_max, 100 - v_ca_max USING ERRCODE = '23514';
    END IF;
    IF v_out = was.outcome AND v_ca IS NOT DISTINCT FROM was.ca AND v_exam IS NOT DISTINCT FROM was.exam THEN
        RAISE EXCEPTION 'RES_AMEND_SAME: the mark is already that' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'RES_AMEND_REASON: an amendment says why, in words Senate can read' USING ERRCODE = '23514';
    END IF;
    IF v_query IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM assessment.result_query q WHERE q.id = v_query AND q.sheet_id = p_sheet AND q.student_id = p_student AND q.state = 'CORRECTED') THEN
            RAISE EXCEPTION 'RES_AMEND_QUERY: that query is not this student''s on this sheet answered as corrected' USING ERRCODE = '23514';
        END IF;
    ELSE
        -- the query answered CORRECTED that asked for it, when there is one not yet carried by an amendment
        v_query := (SELECT q.id FROM assessment.result_query q WHERE q.sheet_id = p_sheet AND q.student_id = p_student AND q.state = 'CORRECTED'
                       AND NOT EXISTS (SELECT 1 FROM assessment.amendment m WHERE m.query_id = q.id AND m.stage <> 'WITHDRAWN')
                     ORDER BY q.answered_at DESC LIMIT 1);
    END IF;
    INSERT INTO assessment.amendment (ref, sheet_id, student_id, query_id, was_version, was_ca, was_exam, was_outcome, ca, exam, outcome, reason, raised_by, raised_office)
    VALUES ('AMD-' || v_year || '-' || lpad(platform.next_number('RESULT_AMENDMENT', 'UNIVERSITY', v_year)::text, 5, '0'),
            p_sheet, p_student, v_query, was.version, was.ca, was.exam, was.outcome, v_ca, v_exam, v_out, btrim(p_reason), v_actor, v_office)
    RETURNING id INTO v_id;
    INSERT INTO assessment.amendment_decision (amendment_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
    VALUES (v_id, NULL, 'VERIFICATION', 'RAISE', v_actor, v_office, btrim(p_reason));
    RETURN v_id;
END $$;

/* approved by the desk of its stage (not the person who took the last step); at Senate, applied on the minute */
CREATE OR REPLACE FUNCTION assessment.advance_amendment(p_amendment uuid, p_comment text, p_minute text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE m assessment.amendment; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_last uuid; v_next text; v_version int; v_course text;
BEGIN
    SELECT * INTO m FROM assessment.amendment WHERE id = p_amendment FOR UPDATE;
    IF m.id IS NULL THEN RAISE EXCEPTION 'no amendment %', p_amendment USING ERRCODE = 'no_data_found'; END IF;
    IF m.stage IN ('APPLIED', 'REFUSED', 'WITHDRAWN') THEN
        RAISE EXCEPTION 'RES_AMEND_CLOSED: the amendment is % already', lower(m.stage) USING ERRCODE = '23514';
    END IF;
    PERFORM assessment.require_stage_desk(m.stage, v_office, 'approved');
    SELECT d.actor_id INTO v_last FROM assessment.amendment_decision d WHERE d.amendment_id = p_amendment AND d.kind IN ('RAISE', 'ADVANCE')
     ORDER BY d.decided_at DESC LIMIT 1;
    IF v_last IS NOT NULL AND v_last = v_actor THEN
        RAISE EXCEPTION 'you took the previous step of this amendment; another desk must approve this one' USING ERRCODE = 'check_violation',
            HINT = 'BR-006. No one person moves a correction from raising to Senate alone.';
    END IF;
    v_next := assessment.stage_after(m.stage);
    IF v_next = 'PUBLISHED' THEN
        IF p_minute IS NULL OR btrim(p_minute) = '' THEN
            RAISE EXCEPTION 'an amendment is applied on the Senate minute that approved it, and none was cited' USING ERRCODE = 'check_violation';
        END IF;
        SELECT coalesce(max(version), 0) + 1 INTO v_version FROM assessment.score WHERE sheet_id = m.sheet_id AND student_id = m.student_id;
        INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, outcome, reason)
        VALUES (m.sheet_id, m.student_id, v_version, m.ca, m.exam, m.outcome,
                'Amendment ' || m.ref || ' on Senate minute ' || btrim(p_minute) || ': ' || m.reason);
        UPDATE assessment.amendment SET stage = 'APPLIED', senate_minute = btrim(p_minute), applied_at = now(), applied_version = v_version WHERE id = p_amendment;
        INSERT INTO assessment.amendment_decision (amendment_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
        VALUES (p_amendment, m.stage, 'APPLIED', 'APPLY', v_actor, v_office, nullif(btrim(coalesce(p_comment, '')), ''));
        SELECT o.course_code INTO v_course FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id WHERE s.id = m.sheet_id;
        PERFORM assessment.tell_amended(m.student_id, v_course, m.ref);
        RETURN 'APPLIED';
    END IF;
    UPDATE assessment.amendment SET stage = v_next WHERE id = p_amendment;
    INSERT INTO assessment.amendment_decision (amendment_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
    VALUES (p_amendment, m.stage, v_next, 'ADVANCE', v_actor, v_office, nullif(btrim(coalesce(p_comment, '')), ''));
    RETURN v_next;
END $$;

/* refused by the desk of its stage, with the reason; the raiser is told */
CREATE OR REPLACE FUNCTION assessment.refuse_amendment(p_amendment uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE m assessment.amendment; v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_email text;
BEGIN
    SELECT * INTO m FROM assessment.amendment WHERE id = p_amendment FOR UPDATE;
    IF m.id IS NULL THEN RAISE EXCEPTION 'no amendment %', p_amendment USING ERRCODE = 'no_data_found'; END IF;
    IF m.stage IN ('APPLIED', 'REFUSED', 'WITHDRAWN') THEN RAISE EXCEPTION 'RES_AMEND_CLOSED: the amendment is % already', lower(m.stage) USING ERRCODE = '23514'; END IF;
    PERFORM assessment.require_stage_desk(m.stage, v_office, 'refused');
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'RES_AMEND_REASON: a refusal says why' USING ERRCODE = '23514'; END IF;
    UPDATE assessment.amendment SET stage = 'REFUSED', closed_at = now(), closed_reason = btrim(p_reason) WHERE id = p_amendment;
    INSERT INTO assessment.amendment_decision (amendment_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
    VALUES (p_amendment, m.stage, 'REFUSED', 'REFUSE', nullif(current_setting('moaum.actor_id', true), '')::uuid, v_office, btrim(p_reason));
    SELECT p.email INTO v_email FROM iam.person p WHERE p.id = m.raised_by;
    PERFORM platform.queue_notice('EMAIL', v_email, 'Amendment ' || m.ref || ' was refused',
        'The amendment ' || m.ref || ' you raised was refused at ' || lower(replace(m.stage, '_', ' ')) || ': ' || btrim(p_reason)
        || E'\n\nThe published mark stands. Sign in to the portal to read the amendment''s record.', 'person', m.raised_by);
END $$;

/* withdrawn by the person who raised it, while it is open */
CREATE OR REPLACE FUNCTION assessment.withdraw_amendment(p_amendment uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE m assessment.amendment; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO m FROM assessment.amendment WHERE id = p_amendment FOR UPDATE;
    IF m.id IS NULL THEN RAISE EXCEPTION 'no amendment %', p_amendment USING ERRCODE = 'no_data_found'; END IF;
    IF m.stage IN ('APPLIED', 'REFUSED', 'WITHDRAWN') THEN RAISE EXCEPTION 'RES_AMEND_CLOSED: the amendment is % already', lower(m.stage) USING ERRCODE = '23514'; END IF;
    IF v_actor IS DISTINCT FROM m.raised_by THEN
        RAISE EXCEPTION 'RES_AMEND_NOT_YOURS: only the person who raised an amendment withdraws it; a desk refuses it with the reason' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'RES_AMEND_REASON: a withdrawal says why' USING ERRCODE = '23514'; END IF;
    UPDATE assessment.amendment SET stage = 'WITHDRAWN', closed_at = now(), closed_reason = btrim(p_reason) WHERE id = p_amendment;
    INSERT INTO assessment.amendment_decision (amendment_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
    VALUES (p_amendment, m.stage, 'WITHDRAWN', 'WITHDRAW', v_actor, nullif(current_setting('moaum.actor_office', true), ''), btrim(p_reason));
END $$;

/* the student told that a published result is amended — no mark in the message */
CREATE OR REPLACE FUNCTION assessment.tell_amended(p_student uuid, p_course text, p_ref text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record; v_from text := coalesce((SELECT name FROM platform.institution_profile LIMIT 1), 'the University');
BEGIN
    SELECT st.surname, st.other_names, rc.email, rc.phone INTO r FROM people.student st LEFT JOIN LATERAL people.student_reach(st.id) rc ON true WHERE st.id = p_student;
    PERFORM platform.queue_notice('EMAIL', r.email, 'Your result in ' || p_course || ' is amended',
        'Dear ' || r.surname || ', ' || r.other_names || E',\n\nYour published result in ' || p_course || ' has been amended on the Senate''s approval (' || p_ref || '). '
        || E'Sign in to the University portal to see it. Any transcript or statement issued before the amendment is superseded.\n\n' || v_from || ' — Examinations and Records',
        'student', p_student);
    PERFORM platform.queue_notice('SMS', r.phone, 'Result amended', 'MOAUM: your result in ' || p_course || ' is amended. Sign in to the portal to see it.', 'student', p_student);
END $$;

/* a sheet's amendments, with the student and the decisions */
CREATE OR REPLACE FUNCTION assessment.amendments_of(p_sheet uuid)
RETURNS TABLE (id uuid, ref text, sheet_id uuid, student_id uuid, number text, name text, query_ref text, was_ca int, was_exam int, was_outcome text,
               ca int, exam int, outcome text, reason text, stage text, raised_by uuid, raised_by_name text, raised_office text, raised_at timestamptz,
               senate_minute text, applied_at timestamptz, closed_reason text, last_actor uuid, decisions jsonb)
LANGUAGE sql STABLE AS $$
    SELECT m.id, m.ref, m.sheet_id, m.student_id, coalesce(st.matric_no, st.admission_no), upper(st.surname) || ', ' || st.other_names, q.ref,
           m.was_ca, m.was_exam, m.was_outcome, m.ca, m.exam, m.outcome, m.reason, m.stage, m.raised_by, p.surname || ', ' || p.given_names, m.raised_office, m.raised_at,
           m.senate_minute, m.applied_at, m.closed_reason,
           (SELECT d.actor_id FROM assessment.amendment_decision d WHERE d.amendment_id = m.id AND d.kind IN ('RAISE', 'ADVANCE') ORDER BY d.decided_at DESC LIMIT 1),
           (SELECT coalesce(jsonb_agg(jsonb_build_object('kind', d.kind, 'from', d.from_stage, 'to', d.to_stage, 'office', d.actor_office, 'comment', d.comment,
                                                         'at', d.decided_at, 'by', (SELECT x.surname || ', ' || x.given_names FROM iam.person x WHERE x.id = d.actor_id))
                                       ORDER BY d.decided_at), '[]'::jsonb)
              FROM assessment.amendment_decision d WHERE d.amendment_id = m.id)
      FROM assessment.amendment m JOIN people.student st ON st.id = m.student_id
      LEFT JOIN assessment.result_query q ON q.id = m.query_id LEFT JOIN iam.person p ON p.id = m.raised_by
     WHERE m.sheet_id = p_sheet
     ORDER BY m.raised_at DESC
$$;

-- ── 2 · offers that lapse and a waiting list that moves ─────────────────────────────────────────────────────────
ALTER TABLE admissions.application ADD COLUMN lapsed_at timestamptz NULL;
ALTER TABLE admissions.application ADD COLUMN promoted_for uuid NULL REFERENCES admissions.application(id);
ALTER TABLE admissions.application ADD COLUMN promoted_at timestamptz NULL;
CREATE UNIQUE INDEX ux_application_promoted_for ON admissions.application (promoted_for) WHERE promoted_for IS NOT NULL;
COMMENT ON COLUMN admissions.application.lapsed_at IS 'V358: the offer was neither accepted nor paid for by its deadline, and the Admissions Office lapsed it.';
COMMENT ON COLUMN admissions.application.promoted_for IS 'V358: promoted from the waiting list to the place this (lapsed or declined) offer left — one place, one promotion.';

/* the session's acceptance deadline, as the Admissions Office sets it — none set, no offer lapses */
CREATE TABLE admissions.offer_deadline (
    session            text PRIMARY KEY CHECK (session ~ '^[0-9]{4}/[0-9]{4}$'),
    accept_by          date NULL,
    days_after_release int NULL CHECK (days_after_release IS NULL OR days_after_release BETWEEN 1 AND 120),
    note               text NULL CHECK (note IS NULL OR length(note) <= 500),
    set_by             uuid NULL,
    set_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_offer_deadline_some CHECK (accept_by IS NOT NULL OR days_after_release IS NOT NULL)
);
SELECT audit.attach('admissions.offer_deadline');
COMMENT ON TABLE admissions.offer_deadline IS 'V358: by when an offer of the session is accepted — a date, days after the offer''s own release, or the later of the two; set by the Admissions Office, never assumed.';

/* an offer's deadline: the later of the session's date and its own release plus the days allowed (either alone when the other is not set) */
CREATE OR REPLACE FUNCTION admissions.offer_deadline_of(p_app uuid)
RETURNS date LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN d.session IS NULL OR a.decision_released_at IS NULL THEN NULL
                WHEN d.accept_by IS NOT NULL AND d.days_after_release IS NOT NULL
                     THEN greatest(d.accept_by, (a.decision_released_at AT TIME ZONE 'Africa/Lagos')::date + d.days_after_release)
                WHEN d.accept_by IS NOT NULL THEN d.accept_by
                ELSE (a.decision_released_at AT TIME ZONE 'Africa/Lagos')::date + d.days_after_release END
      FROM admissions.application a LEFT JOIN admissions.offer_deadline d ON d.session = a.session
     WHERE a.id = p_app
$$;

/* the released offers of a session past their deadline, neither accepted, nor declined, nor paid for (a fee paid is never lapsed) */
CREATE OR REPLACE FUNCTION admissions.offers_past_deadline(p_session text)
RETURNS TABLE (app_id uuid, application_no text, name text, programme text, programme_name text, released_on date, deadline date, undertaking boolean)
LANGUAGE sql STABLE AS $$
    SELECT a.id, a.application_no, upper(c.surname) || ', ' || c.other_names, pc.code, c.programme,
           (a.decision_released_at AT TIME ZONE 'Africa/Lagos')::date, admissions.offer_deadline_of(a.id), a.undertaking_at IS NOT NULL
      FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
      -- the candidate carries the programme by its name, as the merit list reads it
      LEFT JOIN LATERAL (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) pc ON true
     WHERE a.session = p_session AND a.decision = 'OFFERED' AND a.decision_released_at IS NOT NULL
       AND a.accepted_at IS NULL AND a.declined_at IS NULL AND a.lapsed_at IS NULL AND a.acceptance_confirmed_at IS NULL
       AND NOT coalesce((SELECT e.paid FROM admissions.acceptance_entitlement(a.id) e), false)
       AND admissions.offer_deadline_of(a.id) < (now() AT TIME ZONE 'Africa/Lagos')::date
     ORDER BY pc.code, a.application_no
$$;

/* the offers past their deadline lapsed — all of them, or those named — and each applicant told */
CREATE OR REPLACE FUNCTION admissions.lapse_offers(p_session text, p_apps uuid[])
RETURNS int LANGUAGE plpgsql AS $$
DECLARE r record; n int := 0;
BEGIN
    FOR r IN SELECT * FROM admissions.offers_past_deadline(p_session) o WHERE coalesce(cardinality(p_apps), 0) = 0 OR o.app_id = ANY (p_apps) LOOP
        UPDATE admissions.application SET lapsed_at = now() WHERE id = r.app_id;
        UPDATE admissions.candidate c SET offer_state = 'LAPSED' FROM admissions.application a
         WHERE a.id = r.app_id AND c.id = a.candidate_id AND c.offer_state IN ('PROPOSED', 'ADMITTED')
           AND c.admitted_from IS NOT NULL;   -- a candidate's state beyond PROPOSED rests on its CAPS row (ck_candidate_needs_caps); the lapse is the application's
        PERFORM admissions.notify_applicant(r.app_id, 'Your offer of admission has lapsed',
            'Your offer of admission was not accepted by ' || to_char(r.deadline, 'FMDD Month YYYY') || ', the deadline for accepting it, and has lapsed. '
            || 'A lapsed offer is not reinstated. If you believe this is in error, write to the Admissions Office quoting your application number.',
            'MOAUM: your offer of admission was not accepted by ' || to_char(r.deadline, 'FMDD Mon YYYY') || ' and has lapsed.');
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

/* a lapsed offer is not taken up: its undertaking is refused; a fee confirmed after the lapse does not accept it */
CREATE OR REPLACE FUNCTION admissions.lapsed_offer_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.lapsed_at IS NOT NULL THEN
        IF NEW.undertaking_at IS DISTINCT FROM OLD.undertaking_at THEN
            RAISE EXCEPTION 'ADMISSION_OFFER_LAPSED: this offer lapsed on %; a lapsed offer is not accepted', (OLD.lapsed_at AT TIME ZONE 'Africa/Lagos')::date
                USING ERRCODE = '23514';
        END IF;
        NEW.accepted_at := OLD.accepted_at;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_application_lapsed_guard BEFORE UPDATE ON admissions.application FOR EACH ROW EXECUTE FUNCTION admissions.lapsed_offer_guard();

CREATE OR REPLACE FUNCTION admissions.lapsed_offer_no_fee()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.kind = 'ACCEPTANCE' AND EXISTS (SELECT 1 FROM admissions.application a WHERE a.id = NEW.application_id AND a.lapsed_at IS NOT NULL) THEN
        RAISE EXCEPTION 'ADMISSION_OFFER_LAPSED: the offer has lapsed; no acceptance fee is owed on it' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_fee_reference_lapsed BEFORE INSERT ON admissions.fee_reference FOR EACH ROW EXECUTE FUNCTION admissions.lapsed_offer_no_fee();

/* the places freed in a session — a released offer lapsed or declined — and not yet filled from the waiting list */
CREATE OR REPLACE FUNCTION admissions.vacancies(p_session text)
RETURNS TABLE (vacated_id uuid, application_no text, name text, programme text, programme_name text, basis text, why text, freed_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT a.id, a.application_no, upper(c.surname) || ', ' || c.other_names, pc.code, c.programme, a.decision_basis,
           CASE WHEN a.lapsed_at IS NOT NULL THEN 'LAPSED' ELSE 'DECLINED' END, coalesce(a.lapsed_at, a.declined_at)
      FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
      LEFT JOIN LATERAL (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) pc ON true
     WHERE a.session = p_session AND a.decision = 'OFFERED' AND a.decision_released_at IS NOT NULL AND a.accepted_at IS NULL
       AND (a.lapsed_at IS NOT NULL OR a.declined_at IS NOT NULL)
       AND NOT EXISTS (SELECT 1 FROM admissions.application x WHERE x.promoted_for = a.id)
     ORDER BY pc.code, coalesce(a.lapsed_at, a.declined_at), a.application_no
$$;

/* a programme's waiting list in merit order, with what the quota bases turn on */
CREATE OR REPLACE FUNCTION admissions.waiting_list(p_session text, p_programme text)
RETURNS TABLE (rank int, app_id uuid, application_no text, jamb_reg_no text, name text, entry_mode text, aggregate numeric, state_of_origin text, lga text)
LANGUAGE sql STABLE AS $$
    SELECT m.rank, m.app_id, a.application_no, m.jamb_reg_no, upper(m.surname) || ', ' || m.other_names, m.entry_mode, m.aggregate, m.state_of_origin, m.lga
      FROM admissions.merit_list(p_session, p_programme) m JOIN admissions.application a ON a.id = m.app_id
     WHERE a.decision = 'WAITING' AND a.lapsed_at IS NULL AND m.eligible
     ORDER BY m.rank
$$;

/* the waiting candidates the Admissions Office chooses, promoted to the programme's freed places in the order they were freed */
CREATE OR REPLACE FUNCTION admissions.promote_waiting(p_session text, p_programme text, p_apps uuid[], p_actor uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE v record; app uuid; i int := 0; d admissions.offer_deadline; v_free int;
BEGIN
    IF coalesce(cardinality(p_apps), 0) = 0 THEN RAISE EXCEPTION 'ADMISSION_PROMOTE_NONE: choose whom to promote' USING ERRCODE = '23514'; END IF;
    v_free := (SELECT count(*) FROM admissions.vacancies(p_session) x WHERE x.programme = p_programme);
    IF cardinality(p_apps) > v_free THEN
        RAISE EXCEPTION 'ADMISSION_NO_VACANCY: % chosen for % place(s) freed in this programme', cardinality(p_apps), v_free USING ERRCODE = '23514';
    END IF;
    SELECT * INTO d FROM admissions.offer_deadline WHERE session = p_session;
    IF d.session IS NOT NULL AND d.days_after_release IS NULL AND d.accept_by < (now() AT TIME ZONE 'Africa/Lagos')::date THEN
        RAISE EXCEPTION 'ADMISSION_DEADLINE_DAYS: the session''s acceptance date has passed; set the days allowed after an offer''s release before promoting'
            USING ERRCODE = '23514';
    END IF;
    FOREACH app IN ARRAY p_apps LOOP
        IF NOT EXISTS (SELECT 1 FROM admissions.waiting_list(p_session, p_programme) w WHERE w.app_id = app) THEN
            RAISE EXCEPTION 'ADMISSION_NOT_WAITING: % is not on this programme''s waiting list', coalesce((SELECT application_no FROM admissions.application WHERE id = app), app::text)
                USING ERRCODE = '23514';
        END IF;
        SELECT * INTO v FROM admissions.vacancies(p_session) x WHERE x.programme = p_programme ORDER BY x.freed_at, x.application_no LIMIT 1;
        UPDATE admissions.application
           SET decision = 'OFFERED', decision_basis = v.basis, decided_at = now(), decision_released_at = now(), promoted_for = v.vacated_id, promoted_at = now(),
               decision_note = 'Promoted from the waiting list to the place of ' || v.application_no || ' (' || lower(v.why) || ')'
         WHERE id = app;
        UPDATE admissions.candidate c SET offer_state = 'ADMITTED' FROM admissions.application a
         WHERE a.id = app AND c.id = a.candidate_id AND c.offer_state = 'PROPOSED' AND c.admitted_from IS NOT NULL;
        PERFORM admissions.notify_applicant(app, 'Your admission status for ' || p_session,
            'The admission decision on your application for the ' || p_session || ' session has changed. Read it on the applicant portal under Admission Status: '
            || 'while the University has Admission Status Checking open, check your status there.',
            'MOAUM: the admission decision on your application has changed. Check it on the portal under Admission Status.');
        i := i + 1;
    END LOOP;
    RETURN i;
END $$;
COMMENT ON FUNCTION admissions.promote_waiting(text, text, uuid[], uuid) IS 'V358: waiting candidates chosen by the Admissions Office promoted to a programme''s places freed by a lapse or a decline — each to one place, in the order the places were freed.';

GRANT SELECT ON assessment.amendment, assessment.amendment_decision, admissions.offer_deadline TO app_auditor;

-- the applicant's admission status (V295), with a lapsed offer and the deadline said
CREATE OR REPLACE FUNCTION admissions.admission_status(p_app uuid)
 RETURNS TABLE(status text, label text, next_action text, next_href text, detail text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE a admissions.application; f admissions.screening_form; s people.student; q admissions.programme_change_request; req boolean; ent record; reg boolean; paid boolean; c record;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN QUERY SELECT 'NOT_FOUND', 'Not found', NULL, NULL, NULL; RETURN; END IF;
    -- V295: the status is read through Admission Status Checking — a valid Post-UTME application (paid for and submitted), checking
    -- open (the Director of ICT's window) and the checking fee paid; never through the decision, which is what the check reveals.
    -- An applicant who has read an offer and whose admission is under way continues whatever the window.
    SELECT * INTO c FROM admissions.status_checking(p_app);
    IF NOT c.decision_visible THEN
        IF NOT c.application_valid THEN
            RETURN QUERY SELECT 'APPLICATION_INCOMPLETE', 'Application not complete',
                CASE WHEN a.fee_confirmed_at IS NULL THEN 'Pay the application fee' ELSE 'Complete and submit your application' END,
                CASE WHEN a.fee_confirmed_at IS NULL THEN '/applicant/fee' ELSE '/applicant/apply' END,
                'Admission status checking is open to every applicant whose Post-UTME application is paid for and submitted.'; RETURN;
        END IF;
        IF NOT c.window_open THEN
            RETURN QUERY SELECT 'CHECKING_CLOSED', 'Admission status checking closed', NULL::text, '/applicant/admission',
                CASE WHEN c.window_state = 'SCHEDULED' AND c.opens_at IS NOT NULL
                     THEN 'Admission status checking opens on ' || to_char(c.opens_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY "at" HH24:MI') || '.'
                     ELSE 'Admission status checking is currently unavailable. Please check back when the University opens the admission checking portal.' END; RETURN;
        END IF;
        RETURN QUERY SELECT 'CHECKING_FEE_PENDING', 'Admission checking fee not paid', 'Pay the admission checking fee', '/applicant/admission',
            'Admission status checking is open. Pay the admission checking fee of ₦' || to_char(c.fee, 'FM999,999,990') || ' once, then check your admission status as often as you need while checking is open.'; RETURN;
    END IF;
    IF a.decision_released_at IS NULL OR a.decision IS NULL THEN
        RETURN QUERY SELECT 'PENDING', 'Admission pending', NULL::text, '/applicant/admission',
            'Your admission has not yet been finalised. Please check again when further admission processing has been completed; the checking fee is not charged again.'; RETURN;
    END IF;
    IF a.decision <> 'OFFERED' THEN
        RETURN QUERY SELECT 'NOT_ADMITTED', CASE WHEN a.decision = 'WAITING' THEN 'Waiting list' ELSE 'Not admitted' END, NULL::text, '/applicant/admission',
            coalesce(a.decision_note, CASE WHEN a.decision = 'WAITING'
                THEN 'You are above the cut-off, but the approved quota is full. You are offered a place only if an offered candidate fails to accept in time.'
                ELSE 'Your admission status for the ' || a.session || ' admission exercise is: not admitted. You may continue to monitor the University''s official admission updates.' END); RETURN;
    END IF;
    IF a.declined_at IS NOT NULL THEN RETURN QUERY SELECT 'DECLINED', 'Offer declined', NULL, '/applicant/status', 'A declined offer is not reinstated.'; RETURN; END IF;
    -- V358: an offer not accepted by its deadline, lapsed by the Admissions Office
    IF a.lapsed_at IS NOT NULL THEN
        RETURN QUERY SELECT 'LAPSED', 'Offer lapsed', NULL::text, '/applicant/admission',
            'Your offer was not accepted by ' || coalesce(to_char(admissions.offer_deadline_of(p_app), 'FMDD Month YYYY'), 'its deadline')
            || ' and has lapsed. A lapsed offer is not reinstated; write to the Admissions Office quoting your application number if you believe this is in error.'; RETURN;
    END IF;
    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);
    -- the applicant reads the admission status — the offer, its programme, faculty and session — before anything is accepted (V271)
    IF a.accepted_at IS NULL AND a.status_checked_at IS NULL AND NOT ent.paid AND a.undertaking_at IS NULL THEN
        RETURN QUERY SELECT 'ADMITTED', 'Admitted — check your admission status', 'Check your admission status', '/applicant/admission', 'Congratulations: read the offer and its details, then accept it and pay the acceptance fee.'; RETURN;
    END IF;
    IF a.accepted_at IS NULL THEN
        IF ent.paid OR a.undertaking_at IS NOT NULL THEN RETURN QUERY SELECT 'ACCEPTANCE_PENDING', 'Acceptance in progress', CASE WHEN ent.paid THEN 'Sign the undertaking' ELSE 'Pay the acceptance fee' END, '/applicant/accept', 'The undertaking and the acceptance fee together accept the offer.'; RETURN; END IF;
        RETURN QUERY SELECT 'ADMITTED', 'Admitted — offer to accept', 'Pay the acceptance fee', '/applicant/accept', 'Accept the offer and pay the acceptance fee; the acceptance letter follows.' || coalesce(' Accept it by ' || to_char(admissions.offer_deadline_of(p_app), 'FMDD Month YYYY') || '; an offer neither accepted nor paid for by then lapses.', ''); RETURN;
    END IF;
    req := admissions.screening_required(p_app);
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    SELECT * INTO q FROM admissions.programme_change_request x WHERE x.application_id = p_app ORDER BY x.requested_at DESC LIMIT 1;
    IF req AND NOT admissions.screening_ok(p_app) THEN
        -- the University screens on the record it holds (V280): the applicant waits (entering only the schools attended), or provides the one correction asked for
        -- V284: a change the Academic Office recommended during the screening awaits approval
        IF q.id IS NOT NULL AND q.state = 'REQUESTED' AND f.application_id IS NOT NULL AND f.state IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED') THEN
            RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_PENDING', 'Programme change under review', 'Wait for the Academic Office', '/applicant/admission',
                'During the screening the Academic Office recommended ' || q.to_programme || ' in place of ' || q.from_programme || '; the change takes effect when it is approved, and you will be told. Your acceptance fee is not paid again.';
            RETURN;
        END IF;
        IF f.application_id IS NULL OR f.state = 'PENDING' THEN RETURN QUERY SELECT 'SCREENING_PENDING', 'Accepted - awaiting screening', 'Wait for the University''s screening', '/applicant/clearance', 'Your information has been received. The University screens your admission on the information JAMB and your application already gave; the schools you attended are the only thing you enter. You will be told the outcome here and by email.'; RETURN; END IF;
        IF f.state = 'IN_REVIEW' THEN RETURN QUERY SELECT 'SCREENING_IN_REVIEW', 'Screening in progress', 'Wait for the screening officers', '/applicant/clearance', 'A screening officer opened your record' || coalesce(' on ' || to_char(f.review_started_at, 'DD Mon YYYY'), '') || '.'; RETURN; END IF;
        IF f.state = 'CORRECTION_REQUIRED' THEN RETURN QUERY SELECT 'SCREENING_CORRECTION', 'Screening: one correction required', 'Provide the correction', '/applicant/clearance', f.returned_note; RETURN; END IF;
        IF f.state = 'UNSUCCESSFUL' THEN
            IF q.id IS NOT NULL AND q.state = 'REQUESTED' AND q.requested_at >= f.decided_at THEN RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_PENDING', 'Change of programme requested', 'Wait for the Admissions Office', '/applicant/clearance', 'Requested ' || q.to_programme || ' on ' || to_char(q.requested_at, 'DD Mon YYYY') || '.'; RETURN; END IF;
            RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_REQUIRED', 'Screening unsuccessful', 'Apply for a change of programme', '/applicant/clearance', f.decision_reason; RETURN;
        END IF;
    END IF;
    SELECT * INTO s FROM people.student WHERE candidate_id = a.candidate_id LIMIT 1;
    IF s.id IS NULL THEN RETURN QUERY SELECT 'REGISTER_PENDING', CASE WHEN req THEN 'Screening successful' ELSE 'Accepted' END, 'Wait for the Registry to bring you onto the register', '/applicant/matric', 'School fees open once you are on the register under your admission number.'; RETURN; END IF;
    IF s.matric_no IS NOT NULL THEN RETURN QUERY SELECT 'MATRICULATED', 'Matriculated', NULL, '/applicant/matric', 'Matriculation number ' || s.matric_no || ', issued ' || to_char(s.matriculated_at, 'DD Mon YYYY') || '. It is now your sign-in.'; RETURN; END IF;
    paid := coalesce((SELECT fp.paid_in_full AND fp.due > 0 FROM finance.position(s.id, a.session) fp), false);
    reg := EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = a.session AND r.status IN ('APPROVED', 'LOCKED'));
    IF NOT paid THEN RETURN QUERY SELECT 'SCHOOL_FEES_PENDING', CASE WHEN q.id IS NOT NULL AND q.state = 'APPROVED' THEN 'Change of programme approved' WHEN req THEN 'Screening successful' ELSE 'Accepted' END, 'Pay school fees', '/student/fees', 'Sign in to the student portal with your admission number ' || coalesce(s.admission_no, '') || ' to pay.'; RETURN; END IF;
    IF NOT reg THEN RETURN QUERY SELECT 'COURSE_REGISTRATION_PENDING', 'School fees paid', 'Register your courses', '/student/registration', 'Registration is on the student portal.'; RETURN; END IF;
    RETURN QUERY SELECT 'MATRICULATION_PENDING', 'Ready for matriculation', 'Wait for the Academic Office to issue your number', '/applicant/matric', 'Your number is issued over the list of students who paid and registered.';
END $function$;

-- the clean slate (V327) reaches the amendments too
CREATE OR REPLACE FUNCTION platform.reset_operational_data(p_confirm text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        r jsonb;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a data reset is made by a person' USING ERRCODE = '23514'; END IF;
    IF upper(btrim(coalesce(p_confirm, ''))) <> 'RESET' THEN
        RAISE EXCEPTION 'type RESET to confirm clearing all uploaded data' USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'a data reset names its reason' USING ERRCODE = '23514';
    END IF;

    SELECT jsonb_build_object(
        'students',     (SELECT count(*) FROM people.student),
        'candidates',   (SELECT count(*) FROM admissions.candidate),
        'applications', (SELECT count(*) FROM admissions.application),
        'results',      (SELECT count(*) FROM assessment.score),
        'courses',      (SELECT count(*) FROM catalogue.course),
        'fee_lines',    (SELECT count(*) FROM finance.fee_schedule),
        'payments',     (SELECT count(*) FROM finance.payment_reference),
        'wallet_entries', (SELECT count(*) FROM finance.wallet_entry),
        'staff_profiles', (SELECT count(*) FROM hrm.staff_profile),
        'pg_applications', (SELECT count(*) FROM admissions.pg_application),
        'college_enrolments', (SELECT count(*) FROM college.enrolment),
        'deferments', (SELECT count(*) FROM people.deferment)
    ) INTO r;

    PERFORM set_config('moaum.maintenance', 'on', true);
    UPDATE people.deferment SET fee_id = NULL WHERE fee_id IS NOT NULL;
    UPDATE credentials.issued SET request_id = NULL WHERE request_id IS NOT NULL;
    DELETE FROM admissions.caps_row_excluded;
    DELETE FROM admissions.eligibility_event;
    DELETE FROM admissions.programme_change_request;
    DELETE FROM admissions.eligibility_run;
    DELETE FROM admissions.pg_fee_reference;
    DELETE FROM admissions.pg_application;
    DELETE FROM admissions.pg_registration;
    DELETE FROM extexam.event;
    DELETE FROM extexam.assessment_score;
    DELETE FROM extexam.assessment;
    DELETE FROM extexam.assignment;
    DELETE FROM extexam.project_document_blob;
    DELETE FROM extexam.project_document;
    DELETE FROM extexam.project;
    DELETE FROM admissions.pg_research;
    DELETE FROM admissions.putme_event;
    DELETE FROM admissions.screening_answer;
    DELETE FROM admissions.screening_assignment;
    DELETE FROM admissions.screening_event;
    DELETE FROM admissions.screening_form;
    DELETE FROM admissions.screening_institution;
    DELETE FROM admissions.screening_olevel;
    DELETE FROM assessment.held_script;
    DELETE FROM assessment.siwes_supervisor;
    DELETE FROM college.assessment_score;
    DELETE FROM college.attendance_record;
    DELETE FROM college.carry_over;
    DELETE FROM college.case_clerking;
    DELETE FROM college.enrolment_semester;
    DELETE FROM college.enrolment;
    DELETE FROM college.event_attendance;
    DELETE FROM college.exam_result;
    DELETE FROM college.posting_allocation;
    DELETE FROM college.procedure_log;
    DELETE FROM college.progression_decision;
    DELETE FROM college.project;
    DELETE FROM credentials.delivery;
    DELETE FROM hostel.sanction;
    DELETE FROM hostel.incident;
    DELETE FROM hostel.swap_request;
    DELETE FROM hostel.transfer_request;
    DELETE FROM people.deferred_course;
    DELETE FROM people.deferment_fee;
    DELETE FROM people.deferment;
    DELETE FROM people.student_username_change;
    DELETE FROM people.matric_batch_edit;
    DELETE FROM people.matric_broadcast;
    DELETE FROM people.matric_reservation;
    DELETE FROM people.matric_batch_row;
    DELETE FROM people.matric_batch;
    DELETE FROM people.matric_history;

    DELETE FROM credentials.certificate;
    DELETE FROM credentials.stationery_batch;
    DELETE FROM credentials.transcript_request;
    DELETE FROM records.graduand;
    DELETE FROM clearance.item;

    DELETE FROM lms.submission_blob;
    DELETE FROM lms.submission;
    DELETE FROM lms.access;
    DELETE FROM lms.material_blob;
    DELETE FROM lms.material;
    DELETE FROM lms.assignment;
    DELETE FROM platform.request_document_blob;
    DELETE FROM platform.request_document;
    DELETE FROM platform.service_request;

    DELETE FROM health.note;
    DELETE FROM health.record_access;
    DELETE FROM health.visit;
    DELETE FROM health.appointment;
    DELETE FROM health.profile;

    -- the wallet and its funding trail (the funding SOURCES and the wallet POLICY, settings, are kept)
    DELETE FROM finance.paydirect_collection;
    DELETE FROM finance.wallet_withdrawal;
    DELETE FROM finance.legacy_nelfund_reconciliation;   -- V327: the reconciliation hangs on the wallet entries and the students
    DELETE FROM finance.wallet_entry;
    DELETE FROM finance.legacy_nelfund_payment;
    DELETE FROM finance.legacy_nelfund_import;
    DELETE FROM finance.nelfund_row;
    DELETE FROM finance.nelfund_batch;
    DELETE FROM finance.nelfund_status;

    DELETE FROM library.reservation;
    DELETE FROM library.loan;

    DELETE FROM hostel.maintenance_request;
    DELETE FROM hostel.allocation;
    DELETE FROM hostel.application;

    -- V358: the amendments of published results, and their decisions, before the queries and sheets they hang on
    DELETE FROM assessment.amendment_decision;
    DELETE FROM assessment.amendment;
    DELETE FROM assessment.result_query;
    DELETE FROM assessment.exam_timetable;
    DELETE FROM registration.attendance;
    DELETE FROM catalogue.class_slot;
    DELETE FROM credentials.identity_card;

    DELETE FROM finance.gateway_event;
    DELETE FROM finance.gateway_attempt;
    DELETE FROM finance.bank_credit;
    DELETE FROM finance.payment_reconciliation;
    DELETE FROM finance.refund;
    DELETE FROM finance.legacy_gst_reconciliation;
    DELETE FROM finance.legacy_gst_payment;
    DELETE FROM finance.legacy_gst_import;
    DELETE FROM finance.legacy_student_crosswalk;
    DELETE FROM finance.payment_reference;
    DELETE FROM finance.fee_schedule;

    DELETE FROM iam.student_account;
    DELETE FROM iam.student_event;
    DELETE FROM people.student_contact;
    DELETE FROM platform.session WHERE active_office IN ('student', 'applicant');

    DELETE FROM hrm.staff_photo;
    DELETE FROM hrm.staff_profile;

    DELETE FROM assessment.sheet_upload;
    DELETE FROM assessment.score;
    DELETE FROM assessment.decision;
    DELETE FROM assessment.score_sheet;
    DELETE FROM assessment.exam_session;
    DELETE FROM assessment.cbt_event;
    DELETE FROM assessment.cbt_answer;
    DELETE FROM assessment.cbt_result;
    DELETE FROM assessment.cbt_attempt;
    DELETE FROM assessment.cbt_exam_question;
    DELETE FROM assessment.cbt_exam;
    DELETE FROM assessment.question;
    DELETE FROM registration.entry;
    DELETE FROM registration.course_registration;
    DELETE FROM catalogue.offering;
    DELETE FROM catalogue.course_offer;
    DELETE FROM catalogue.course;

    DELETE FROM people.faculty_list_query;
    DELETE FROM people.faculty_list;
    DELETE FROM people.biodata_change;
    DELETE FROM people.biodata;
    DELETE FROM people.document;
    DELETE FROM people.status_change;
    DELETE FROM people.enrolment;
    DELETE FROM people.search_log;
    DELETE FROM people.transfer_application;
    DELETE FROM people.student;
    DELETE FROM people.matriculation_run;

    DELETE FROM credentials.revocation;
    DELETE FROM credentials.issued;
    DELETE FROM credentials.lookup_miss;

    DELETE FROM platform.notice;
    DELETE FROM admissions.password_reset;
    DELETE FROM admissions.clearance_document;
    DELETE FROM admissions.application_document_blob;
    DELETE FROM admissions.application_document;
    DELETE FROM admissions.fee_reference;
    DELETE FROM admissions.suggestion_sent;
    DELETE FROM admissions.application;
    DELETE FROM admissions.applicant_account;
    DELETE FROM admissions.applicant_event;
    DELETE FROM admissions.screening_batch;
    DELETE FROM admissions.jamb_admission;
    DELETE FROM admissions.olevel_grade;
    DELETE FROM admissions.olevel_sitting;
    DELETE FROM admissions.candidate_photo;
    DELETE FROM admissions.attachment;
    DELETE FROM admissions.candidate;
    DELETE FROM admissions.caps_row;
    DELETE FROM admissions.caps_batch;

    PERFORM set_config('moaum.maintenance', '', true);
    RETURN r || jsonb_build_object('reset', true, 'reason', btrim(p_reason));
END $function$;

COMMIT;
