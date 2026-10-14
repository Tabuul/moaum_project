-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V446 — The Preliminary Science Programme (2026/2027), a preliminary / remedial programme on the shared applicant stack
--
--   Preliminary Science is a preparatory programme for candidates seeking later admission into approved science-based degree
--   programmes. It is not an undergraduate degree, and choosing a target programme under it is not admission into that degree.
--   Nothing here is a second application, payment, O'Level, document, notification, student or session system:
--
--     the applicant        an ordinary admissions.candidate (entry_mode PRELIMINARY, no JAMB number: the route has none), with
--                          its applicant_account (signed in by email or application number) and admissions.application
--                          (application number from the same APPLICATION series, APP/yy/nnnnnn)
--     the route            policy.study_route PRELIMINARY_SCIENCE, its session named by the Academic Office (2026/2027)
--     the fee              admissions.route_fee for the route, stated per session (the application fee of the notice); the
--                          ordinary applicant fee references, gateway confirmation and receipts (admissions.fee_reference,
--                          admissions.confirm_fee); classified as programme type PRELIMINARY (V409)
--     the O'Level          admissions.screening_olevel, one sitting or two, as the CCE form keeps it; graded by the eligibility
--                          engine's own grade ranking and subject matching (admissions.grade_rank, admissions.subject_same)
--     the documents        admissions.application_document, the kinds the route requires configured in prelim_document
--     the window           policy.portal_window PRELIMINARY_SCIENCE_APPLICATION, opened and closed by the Director of ICT
--     the notices          the central templates (platform.notice_template PRELIMINARY_SCIENCE:*) sent by platform.tell_applicant
--     the decision         the ordinary admissions decision (application.decision, decision_released_at, candidate.offer_state),
--                          published by the Academic Office as for CCE (V379), and the ordinary admission letter (credentials)
--
--   Added for the route alone: its office (the Preliminary Science Office, which reviews; the Academic Office approves and
--   publishes), its configuration (prelim_programme: the description and the O'Level rule — four credits, at most two
--   sittings, at least three of Mathematics, Chemistry, Physics and Biology, never an awaiting result; prelim_target: the
--   target programmes, each an existing ref.programme; prelim_document), and its review (prelim_review: the target chosen,
--   the O'Level verification, the eligibility worked out by the backend, the remediation the completion rule asks for — five
--   credits with Mathematics, Physics, Chemistry and Biology — and the review steps; prelim_review_event, written once).
--
--   Kept apart from Post-UTME: a Preliminary Science application is submitted on its review (application.submitted_at stays
--   empty), so the screening, the Post-UTME CBT, admission status checking and their reminders never take it up; the window
--   guard on new applicant accounts checks each route's own window.
--
--   Not done here, for want of the University's word (docs/preliminary-science.md): the acceptance fee, school fees and other
--   charges; the programme's duration; the remediation examinations and their terms; the identity number of a Preliminary
--   Science student and the move onto the student register; Preliminary Science courses.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V446: the Preliminary Science Programme (2026/2027)', true);

-- ── 1 · the office ────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO ref.office (code, label, scope_kind) VALUES ('prelim', 'Preliminary Science Office', 'institution') ON CONFLICT (code) DO NOTHING;

-- ── 2 · the route: a programme before the first year, with its own session ───────────────────────────────────────
ALTER TABLE policy.study_route DROP CONSTRAINT IF EXISTS study_route_entry_level_check;
ALTER TABLE policy.study_route ADD CONSTRAINT study_route_entry_level_check CHECK (entry_level IN (0, 100, 200, 300));
COMMENT ON COLUMN policy.study_route.entry_level IS 'V446: the level the route''s students enter at; 0 for a programme before the first year (Preliminary Science).';

-- ── 3 · the applicant without a JAMB record ──────────────────────────────────────────────────────────────────────
-- the candidate of a route JAMB does not list carries no JAMB number; every other route keeps one
ALTER TABLE admissions.candidate ALTER COLUMN jamb_reg_no DROP NOT NULL;
ALTER TABLE admissions.candidate ADD CONSTRAINT ck_candidate_jamb_number CHECK (jamb_reg_no IS NOT NULL OR entry_mode = 'PRELIMINARY');
-- the sex the applicant gives, where no JAMB or list record carries it (Preliminary Science)
ALTER TABLE admissions.candidate ADD COLUMN IF NOT EXISTS sex text NULL CHECK (sex IS NULL OR sex IN ('M', 'F'));
COMMENT ON COLUMN admissions.candidate.sex IS 'V446: the sex the applicant gave, on a route with no JAMB or list record to carry it (Preliminary Science). Empty for every other route.';
ALTER TABLE admissions.candidate DROP CONSTRAINT ck_candidate_level;
ALTER TABLE admissions.candidate ADD CONSTRAINT ck_candidate_level CHECK (
    (entry_mode = 'UTME' AND entry_level = 100) OR (entry_mode IN ('DIRECT_ENTRY', 'TRANSFER') AND entry_level IN (200, 300))
    OR (entry_mode = 'CCE' AND entry_level IN (100, 200, 300)) OR (entry_mode = 'PRELIMINARY' AND entry_level = 0));
-- an admission off the CAPS list, the CCE list, or (V446) the Preliminary Science review
ALTER TABLE admissions.candidate DROP CONSTRAINT ck_candidate_needs_caps;
ALTER TABLE admissions.candidate ADD CONSTRAINT ck_candidate_needs_caps CHECK (
    offer_state = 'PROPOSED' OR admitted_from IS NOT NULL OR cce_candidate_id IS NOT NULL OR entry_mode = 'PRELIMINARY');

-- the account of such an applicant has no JAMB key either: it signs in with its email or its application number
ALTER TABLE admissions.applicant_account ALTER COLUMN jamb_key DROP NOT NULL;
CREATE OR REPLACE FUNCTION admissions.applicant_account_key_guard() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF NEW.jamb_key IS NULL AND NOT EXISTS (SELECT 1 FROM admissions.candidate c WHERE c.id = NEW.candidate_id AND c.entry_mode = 'PRELIMINARY') THEN
        RAISE EXCEPTION 'APPLICANT_JAMB_KEY: an applicant account carries the JAMB number, except on a route JAMB does not list' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_applicant_account_key BEFORE INSERT OR UPDATE OF jamb_key, candidate_id ON admissions.applicant_account
    FOR EACH ROW EXECUTE FUNCTION admissions.applicant_account_key_guard();

-- the examination taken in a sitting: the school certificate (May/June) or the GCE (Nov/Dec)
ALTER TABLE admissions.screening_olevel ADD COLUMN IF NOT EXISTS exam_type text NULL CHECK (exam_type IS NULL OR exam_type IN ('SSCE', 'GCE', 'OTHER'));
COMMENT ON COLUMN admissions.screening_olevel.exam_type IS 'V446: the examination of the sitting — SSCE (May/June), GCE (Nov/Dec) or another; given on the Preliminary Science form.';

-- a second passport photograph, where a route asks for two
ALTER TABLE admissions.application_document DROP CONSTRAINT ck_doc_kind;
ALTER TABLE admissions.application_document ADD CONSTRAINT ck_doc_kind CHECK (kind IN (
    'OLEVEL_STATEMENT', 'OLEVEL_STATEMENT_2', 'BIRTH_CERT', 'LGA_ID', 'JAMB_SLIP', 'PASSPORT', 'JAMB_ADMISSION_LETTER', 'STATE_OF_ORIGIN',
    'MARRIAGE_CERT', 'CHANGE_OF_NAME', 'PREVIOUS_QUALIFICATION', 'OTHER', 'PASSPORT_2'));

-- a route's fees: an acceptance fee the University has not given stays unstated, never a made-up zero
ALTER TABLE admissions.route_fee ALTER COLUMN acceptance_fee DROP NOT NULL;
COMMENT ON COLUMN admissions.route_fee.acceptance_fee IS 'The acceptance fee of the route for the session. V446: empty while the University has not given one (Preliminary Science) — owed fees are never invented.';

-- ── 4 · the programme, its rule and its targets ──────────────────────────────────────────────────────────────────
CREATE TABLE admissions.prelim_programme (
    route              text PRIMARY KEY REFERENCES policy.study_route (code),
    name               text NOT NULL CHECK (btrim(name) <> ''),
    programme_type     text NOT NULL DEFAULT 'PRELIMINARY' REFERENCES finance.programme_type (code),
    description        text NOT NULL CHECK (btrim(description) <> ''),
    completion_note    text NOT NULL,
    procedure          text[] NOT NULL DEFAULT '{}',
    office_note        text NULL,
    -- the admission rule (§5–§8): credits, sittings, core credits; an awaiting result is never a credit
    min_credits        integer NOT NULL DEFAULT 4 CHECK (min_credits BETWEEN 1 AND 9),
    max_sittings       integer NOT NULL DEFAULT 2 CHECK (max_sittings BETWEEN 1 AND 2),
    min_core_credits   integer NOT NULL DEFAULT 3 CHECK (min_core_credits >= 0),
    core_subjects      text[] NOT NULL CHECK (cardinality(core_subjects) BETWEEN 1 AND 9),
    credit_grade       text NOT NULL DEFAULT 'C6' CHECK (credit_grade IN ('A1', 'B2', 'B3', 'C4', 'C5', 'C6')),
    -- the completion rule (§9): what the candidate makes up before completing the programme
    completion_credits integer NOT NULL DEFAULT 5 CHECK (completion_credits BETWEEN 1 AND 9),
    completion_subjects text[] NOT NULL CHECK (cardinality(completion_subjects) BETWEEN 0 AND 9),
    -- what the University has not said about remediation (§11) stays its to state: examinations, attempts, fees, pass marks
    remediation_terms  text NULL,
    rules_version      integer NOT NULL DEFAULT 1,
    updated_by         uuid NULL,
    updated_office     text NULL REFERENCES ref.office (code),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_prelim_core_within CHECK (min_core_credits <= cardinality(core_subjects) AND min_core_credits <= min_credits),
    CONSTRAINT ck_prelim_completion CHECK (completion_credits >= min_credits)
);
SELECT audit.attach('admissions.prelim_programme');
COMMENT ON TABLE admissions.prelim_programme IS
  'V446: a preliminary programme run as an admission route (Preliminary Science): its description, the admission rule its eligibility is read under, the completion (remediation) rule, and what the University has said of remediation. Changed by the Academic Office with a reason; every change bumps rules_version and re-reads the open applications.';

CREATE TABLE admissions.prelim_target (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    route           text NOT NULL REFERENCES admissions.prelim_programme (route),
    group_name      text NOT NULL CHECK (btrim(group_name) <> ''),
    ord             integer NOT NULL DEFAULT 100,
    requested_name  text NOT NULL CHECK (btrim(requested_name) <> ''),
    programme_code  text NULL REFERENCES ref.programme (code),
    state           text NOT NULL DEFAULT 'MAPPED' CHECK (state IN ('MAPPED', 'MISSING', 'WITHDRAWN')),
    note            text NULL,
    added_by        uuid NULL,
    added_office    text NULL REFERENCES ref.office (code),
    added_at        timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_prelim_target_mapped CHECK ((state = 'MISSING') = (programme_code IS NULL))
);
CREATE UNIQUE INDEX ux_prelim_target_programme ON admissions.prelim_target (route, programme_code) WHERE programme_code IS NOT NULL;
CREATE UNIQUE INDEX ux_prelim_target_requested ON admissions.prelim_target (route, lower(btrim(requested_name))) WHERE state = 'MISSING';
SELECT audit.attach('admissions.prelim_target');
COMMENT ON TABLE admissions.prelim_target IS
  'V446: the target (progression) programmes of a preliminary programme — each an existing undergraduate ref.programme, never a copy. A programme named in the University''s notice that is not on the register stays MISSING until the Academic Office names the existing programme it is; a withdrawn target stays, WITHDRAWN, for the applications that chose it.';

/* a target is an existing, current undergraduate programme with its department and faculty */
CREATE OR REPLACE FUNCTION admissions.prelim_target_guard() RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE p ref.programme;
BEGIN
    IF NEW.programme_code IS NULL THEN RETURN NEW; END IF;
    SELECT * INTO p FROM ref.programme WHERE code = NEW.programme_code;
    IF p.code IS NULL THEN RAISE EXCEPTION 'PRELIM_TARGET_UNKNOWN: no programme % on the register', NEW.programme_code USING ERRCODE = '23514'; END IF;
    IF TG_OP = 'INSERT' OR NEW.programme_code IS DISTINCT FROM OLD.programme_code THEN
        IF p.archived THEN RAISE EXCEPTION 'PRELIM_TARGET_ARCHIVED: % is archived', p.name USING ERRCODE = '23514'; END IF;
        IF p.category <> 'UNDER GRADUATE' THEN RAISE EXCEPTION 'PRELIM_TARGET_NOT_UNDERGRADUATE: % is not an undergraduate programme', p.name USING ERRCODE = '23514'; END IF;
        IF NOT EXISTS (SELECT 1 FROM ref.department d WHERE d.code = p.dept_code AND d.ended_on IS NULL) THEN
            RAISE EXCEPTION 'PRELIM_TARGET_DEPARTMENT: % belongs to no current department', p.name USING ERRCODE = '23514';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM ref.faculty f WHERE f.code = p.faculty_code) THEN
            RAISE EXCEPTION 'PRELIM_TARGET_FACULTY: % belongs to no faculty on the register', p.name USING ERRCODE = '23514';
        END IF;
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_prelim_target_guard BEFORE INSERT OR UPDATE ON admissions.prelim_target FOR EACH ROW EXECUTE FUNCTION admissions.prelim_target_guard();

CREATE TABLE admissions.prelim_document (
    route              text NOT NULL REFERENCES admissions.prelim_programme (route),
    kind               text NOT NULL,
    label              text NOT NULL CHECK (btrim(label) <> ''),
    hint               text NULL,
    required           boolean NOT NULL DEFAULT true,
    second_sitting_only boolean NOT NULL DEFAULT false,
    ord                integer NOT NULL DEFAULT 100,
    PRIMARY KEY (route, kind),
    CONSTRAINT ck_prelim_document_kind CHECK (kind IN ('OLEVEL_STATEMENT', 'OLEVEL_STATEMENT_2', 'BIRTH_CERT', 'LGA_ID', 'PASSPORT', 'PASSPORT_2',
                                                        'STATE_OF_ORIGIN', 'CHANGE_OF_NAME', 'MARRIAGE_CERT', 'OTHER'))
);
SELECT audit.attach('admissions.prelim_document');
COMMENT ON TABLE admissions.prelim_document IS
  'V446: the documents a preliminary programme''s application carries (application_document kinds), with the label the applicant reads and whether each is required. The payment receipt is the University''s own, issued on the verified payment, never an upload.';

-- ── 5 · the review ───────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE admissions.prelim_review (
    application_id        uuid PRIMARY KEY REFERENCES admissions.application (id) ON DELETE CASCADE,
    route                 text NOT NULL REFERENCES admissions.prelim_programme (route),
    state                 text NOT NULL DEFAULT 'DRAFT' CHECK (state IN ('DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'CORRECTION_REQUIRED', 'RECOMMENDED',
                                                                         'APPROVED', 'ADMITTED', 'NOT_ADMITTED', 'REJECTED', 'WITHDRAWN')),
    target_programme      text NULL REFERENCES ref.programme (code),
    target_set_at         timestamptz NULL,
    submitted_at          timestamptz NULL,
    declaration_ip        text NULL,
    -- the O'Level, as the officer verified it against the documents
    olevel_verification   text NOT NULL DEFAULT 'PENDING' CHECK (olevel_verification IN ('PENDING', 'VERIFIED', 'INVALID')),
    olevel_verified_by    uuid NULL,
    olevel_verified_at    timestamptz NULL,
    olevel_note           text NULL,
    -- the eligibility, worked out by the backend on every change (prelim_evaluate); the frontend only shows it
    eligibility_status    text NOT NULL DEFAULT 'PENDING_REVIEW' CHECK (eligibility_status IN ('PENDING_REVIEW', 'ELIGIBLE', 'NOT_ELIGIBLE', 'REMEDIATION_REQUIRED',
                                                                                              'ELIGIBLE_WITH_REMEDIATION', 'REQUIRES_VERIFICATION', 'RESULT_REQUIRED', 'INVALID_RESULT')),
    total_credits         integer NULL,
    core_credits          integer NULL,
    sittings              integer NULL,
    credited_core         text[] NULL,
    eligibility_checks    jsonb NOT NULL DEFAULT '[]'::jsonb,
    eligibility_reasons   text[] NOT NULL DEFAULT '{}',
    evaluated_at          timestamptz NULL,
    rules_version         integer NULL,
    -- the completion rule: what is to be made up before the programme is completed
    remediation_status    text NULL CHECK (remediation_status IS NULL OR remediation_status IN ('NOT_REQUIRED', 'REQUIRED', 'IN_PROGRESS', 'COMPLETED', 'NOT_COMPLETED', 'REQUIRES_REVIEW')),
    remediation_subjects  text[] NOT NULL DEFAULT '{}',
    remediation_credits_short integer NOT NULL DEFAULT 0,
    remediation_note      text NULL,
    remediation_set_by    uuid NULL,
    remediation_set_at    timestamptz NULL,
    -- the steps
    request_note          text NULL,
    requested_at          timestamptz NULL,
    requested_by          uuid NULL,
    review_started_at     timestamptz NULL,
    review_started_by     uuid NULL,
    recommended_at        timestamptz NULL,
    recommended_by        uuid NULL,
    recommendation_note   text NULL,
    decided_at            timestamptz NULL,
    decided_by            uuid NULL,
    decided_office        text NULL,
    decision_note         text NULL,
    published_at          timestamptz NULL,
    published_by          uuid NULL,
    withdrawn_at          timestamptz NULL,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_prelim_review_state ON admissions.prelim_review (route, state);
CREATE INDEX ix_prelim_review_target ON admissions.prelim_review (target_programme);
CREATE INDEX ix_prelim_review_eligibility ON admissions.prelim_review (route, eligibility_status);
SELECT audit.attach('admissions.prelim_review');
COMMENT ON TABLE admissions.prelim_review IS
  'V446: a Preliminary Science application''s own record beside the ordinary application: the target programme chosen (an intended progression, never an admission into it), the O''Level verification, the eligibility the backend works out, the remediation the completion rule asks for, and the review — submitted, under review, back with the applicant for a correction, recommended by the Preliminary Science Office, approved by someone else, published by the Academic Office.';

CREATE TABLE admissions.prelim_review_event (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id  uuid NOT NULL REFERENCES admissions.application (id) ON DELETE CASCADE,
    at              timestamptz NOT NULL DEFAULT now(),
    actor           uuid NULL,
    office          text NULL,
    action          text NOT NULL,
    from_state      text NULL,
    to_state        text NULL,
    note            text NULL,
    detail          jsonb NULL
);
CREATE INDEX ix_prelim_review_event ON admissions.prelim_review_event (application_id, at);
CREATE OR REPLACE FUNCTION admissions.prelim_event_once() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    -- the application itself removed (the go-live data reset): its history goes with it, as CCE's does
    IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM admissions.application a WHERE a.id = OLD.application_id) THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'a Preliminary Science application''s history is written once and never changed' USING ERRCODE = '23514';
END $fn$;
CREATE TRIGGER trg_prelim_event_once BEFORE UPDATE OR DELETE ON admissions.prelim_review_event FOR EACH ROW EXECUTE FUNCTION admissions.prelim_event_once();
COMMENT ON TABLE admissions.prelim_review_event IS 'V446: every step of a Preliminary Science application — who, when, from what to what, and why. Written once.';
SELECT audit.attach('admissions.prelim_review_event');

-- ── 6 · the application window, the Director of ICT's like every other ──────────────────────────────────────────
ALTER TABLE policy.portal_window DROP CONSTRAINT IF EXISTS portal_window_window_type_check;
ALTER TABLE policy.portal_window ADD CONSTRAINT portal_window_window_type_check CHECK (window_type IN (
    'SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION',
    'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION', 'CCE_SCHOOL_FEES_PAYMENT',
    'CCE_COURSE_REGISTRATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING', 'PG_SCHOOL_FEES_PAYMENT', 'PG_COURSE_REGISTRATION',
    'PRELIMINARY_SCIENCE_APPLICATION'));
ALTER TABLE policy.portal_window DROP CONSTRAINT IF EXISTS ck_window_application_session;
ALTER TABLE policy.portal_window ADD CONSTRAINT ck_window_application_session CHECK (
    window_type NOT IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING',
                        'PRELIMINARY_SCIENCE_APPLICATION')
    OR (semester IS NULL AND late_until IS NULL AND NOT late_fee_enabled));

-- the message the public reads while an application window is closed, the Director's to write (V312)
ALTER TABLE policy.portal_window_message DROP CONSTRAINT IF EXISTS portal_window_message_window_type_check;
ALTER TABLE policy.portal_window_message ADD CONSTRAINT portal_window_message_window_type_check CHECK (window_type IN (
    'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING',
    'PRELIMINARY_SCIENCE_APPLICATION'));
CREATE OR REPLACE FUNCTION policy.window_message_set(p_type text, p_message text, p_actor uuid, p_office text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v_old text; v_new text;
BEGIN
    IF p_type NOT IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION', 'PRELIMINARY_SCIENCE_APPLICATION') THEN RAISE EXCEPTION 'no closure message for %', p_type USING ERRCODE = '23514'; END IF;
    v_new := btrim(regexp_replace(regexp_replace(coalesce(p_message, ''), '<[^>]*>', '', 'g'), '[\u0001-\u0008\u000B-\u001F\u007F]', '', 'g'));
    IF length(v_new) = 0 THEN RAISE EXCEPTION 'the closure message cannot be blank' USING ERRCODE = '23514'; END IF;
    IF length(v_new) > 2000 THEN RAISE EXCEPTION 'the closure message is at most 2000 characters' USING ERRCODE = '23514'; END IF;
    SELECT message INTO v_old FROM policy.portal_window_message WHERE window_type = p_type;
    INSERT INTO policy.portal_window_message (window_type, message, updated_by, updated_office, updated_at)
    VALUES (p_type, v_new, p_actor, p_office, now())
    ON CONFLICT (window_type) DO UPDATE SET message = EXCLUDED.message, updated_by = EXCLUDED.updated_by, updated_office = EXCLUDED.updated_office, updated_at = now();
    INSERT INTO policy.portal_window_event (window_type, session, action, previous_state, new_state, reason, actor, office)
    SELECT p_type, coalesce((SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1), (SELECT max(name) FROM policy.academic_session)),
           'MESSAGE', left(v_old, 120), left(v_new, 120), 'closure message updated', p_actor, p_office
     WHERE EXISTS (SELECT 1 FROM policy.academic_session);
END $function$;

-- a window the Director has not yet set is closed, for the routes whose window was closed from the start (V339, V379, V446)
CREATE OR REPLACE FUNCTION policy.window_state(p_type text, p_session text, p_semester integer)
 RETURNS TABLE(configured boolean, state text, phase text, opens_at timestamp with time zone, closes_at timestamp with time zone, late_until timestamp with time zone, late_fee_enabled boolean, forced text, reason text, window_id uuid, semester integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH w AS (
        SELECT * FROM policy.portal_window
         WHERE window_type = p_type AND session = p_session AND superseded_at IS NULL
           AND (semester = p_semester OR semester IS NULL)
         ORDER BY (semester IS NOT NULL) DESC LIMIT 1)
    SELECT w.id IS NOT NULL,
           CASE WHEN w.id IS NULL THEN CASE WHEN p_type IN ('ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING', 'PRELIMINARY_SCIENCE_APPLICATION') THEN 'CLOSED' ELSE 'OPEN' END
                WHEN w.forced = 'CLOSED' THEN 'CLOSED'
                WHEN w.forced = 'OPEN' THEN 'OPEN'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'SCHEDULED'
                WHEN w.closes_at IS NULL OR now() <= w.closes_at THEN 'OPEN'
                WHEN w.late_until IS NOT NULL AND now() <= w.late_until THEN 'OPEN'
                ELSE 'EXPIRED' END,
           CASE WHEN w.id IS NULL THEN CASE WHEN p_type IN ('ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING', 'PRELIMINARY_SCIENCE_APPLICATION') THEN 'NONE' ELSE 'NORMAL' END
                WHEN w.forced = 'OPEN' THEN CASE WHEN w.late_fee_enabled THEN 'LATE' ELSE 'NORMAL' END
                WHEN w.forced = 'CLOSED' THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at AND w.late_until IS NOT NULL AND now() <= w.late_until THEN 'LATE'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at THEN 'NONE'
                ELSE 'NORMAL' END,
           w.opens_at, w.closes_at, w.late_until, coalesce(w.late_fee_enabled, false), w.forced, w.reason, w.id, w.semester
      FROM (SELECT 1) one LEFT JOIN w ON true
$function$;

CREATE OR REPLACE FUNCTION policy.window_word(p_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE p_type
        WHEN 'SCHOOL_FEES_PAYMENT' THEN 'School fees payment'
        WHEN 'COURSE_REGISTRATION' THEN 'Course registration'
        WHEN 'ADMISSION_STATUS_CHECKING' THEN 'Admission status checking'
        WHEN 'POST_UTME_REGISTRATION' THEN 'Post-UTME registration'
        WHEN 'POSTGRADUATE_APPLICATION' THEN 'Postgraduate application'
        WHEN 'POSTGRADUATE_ADMISSION_STATUS_CHECKING' THEN 'Postgraduate admission status checking'
        WHEN 'JUPEB_APPLICATION' THEN 'JUPEB application'
        WHEN 'JUPEB_ADMISSION_STATUS_CHECKING' THEN 'JUPEB admission status checking'
        WHEN 'CCE_APPLICATION' THEN 'CCE application'
        WHEN 'CCE_SCHOOL_FEES_PAYMENT' THEN 'CCE school fees payment'
        WHEN 'CCE_COURSE_REGISTRATION' THEN 'CCE course registration'
        WHEN 'POST_UTME_CBT' THEN 'Post-UTME CBT'
        WHEN 'POST_UTME_RESULT_CHECKING' THEN 'Post-UTME result checking'
        WHEN 'PG_SCHOOL_FEES_PAYMENT' THEN 'Postgraduate school fees payment'
        WHEN 'PG_COURSE_REGISTRATION' THEN 'Postgraduate course registration'
        WHEN 'PRELIMINARY_SCIENCE_APPLICATION' THEN 'Preliminary Science application'
        ELSE initcap(replace(lower(p_type), '_', ' ')) END
$function$;

CREATE OR REPLACE FUNCTION policy.window_act(p_type text, p_session text, p_semester integer, p_action text, p_opens timestamp with time zone, p_closes timestamp with time zone, p_late_until timestamp with time zone, p_late_fee boolean, p_reason text, p_actor uuid, p_office text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE cur policy.portal_window; prev record; v_forced text; v_opens timestamptz; v_closes timestamptz; v_late timestamptz; v_fee boolean; v_id uuid; nxt record;
BEGIN
    IF p_type NOT IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION',
                      'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION',
                      'CCE_SCHOOL_FEES_PAYMENT', 'CCE_COURSE_REGISTRATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING',
                      'PG_SCHOOL_FEES_PAYMENT', 'PG_COURSE_REGISTRATION', 'PRELIMINARY_SCIENCE_APPLICATION') THEN
        RAISE EXCEPTION 'no such portal window %', p_type USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('ADMISSION_STATUS_CHECKING', 'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_ADMISSION_STATUS_CHECKING', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING')
       AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_CHECKING_SESSION: this window opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION', 'PRELIMINARY_SCIENCE_APPLICATION')
       AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
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
END $function$;

CREATE OR REPLACE FUNCTION policy.application_session(p_type text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE WHEN p_type = 'POSTGRADUATE_APPLICATION' THEN admissions.pg_current_session()
                WHEN p_type = 'CCE_APPLICATION' THEN policy.route_session('CCE')
                WHEN p_type = 'PRELIMINARY_SCIENCE_APPLICATION' THEN policy.route_session('PRELIMINARY_SCIENCE')
                WHEN p_type LIKE 'JUPEB%'
                    THEN coalesce((SELECT current_session FROM jupeb.setting WHERE session = '*'), policy.university_current_session())
                ELSE policy.intake_session() END
$function$;

CREATE OR REPLACE FUNCTION policy.application_windows_public()
 RETURNS TABLE(window_type text, session text, state text, opens_at timestamp with time zone, closes_at timestamp with time zone, message text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT t.window_type, s.session, w.state, w.opens_at, w.closes_at, m.message
      FROM (VALUES ('POST_UTME_REGISTRATION'), ('POSTGRADUATE_APPLICATION'), ('JUPEB_APPLICATION'), ('PRELIMINARY_SCIENCE_APPLICATION')) t(window_type)
      CROSS JOIN LATERAL (SELECT policy.application_session(t.window_type) AS session) s
      CROSS JOIN LATERAL policy.window_state(t.window_type, s.session, NULL) w
      LEFT JOIN policy.portal_window_message m ON m.window_type = t.window_type
$function$;

-- a new applicant account is held at its own route's window: Post-UTME registration for a JAMB applicant, the CCE window for a
-- CCE applicant (V379 left them all at Post-UTME's), the Preliminary Science window for a Preliminary Science applicant
CREATE OR REPLACE FUNCTION policy.application_window_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_type text := TG_ARGV[0]; v_state text; v_mode text;
BEGIN
    -- only the applicant registering themselves is held at the door; an office importing or correcting records is not
    IF coalesce(current_setting('moaum.actor_office', true), '') <> 'applicant' THEN RETURN NEW; END IF;
    IF TG_TABLE_SCHEMA = 'admissions' AND TG_TABLE_NAME = 'applicant_account' THEN
        SELECT c.entry_mode INTO v_mode FROM admissions.candidate c WHERE c.id = NEW.candidate_id;
        v_type := CASE v_mode WHEN 'CCE' THEN 'CCE_APPLICATION' WHEN 'PRELIMINARY' THEN 'PRELIMINARY_SCIENCE_APPLICATION' ELSE v_type END;
    END IF;
    SELECT state INTO v_state FROM policy.window_state(v_type, NEW.session, NULL);
    IF v_state <> 'OPEN' THEN
        RAISE EXCEPTION 'APPLICATION_CLOSED: % for % is % — no new application can be started until the Director of ICT opens it',
            CASE v_type WHEN 'POST_UTME_REGISTRATION' THEN 'Post-UTME registration' WHEN 'JUPEB_APPLICATION' THEN 'JUPEB application'
                        WHEN 'CCE_APPLICATION' THEN 'CCE application' WHEN 'PRELIMINARY_SCIENCE_APPLICATION' THEN 'Preliminary Science application'
                        ELSE 'postgraduate application' END,
            NEW.session, lower(v_state)
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $function$;

-- the reminders before an application window closes (V444): the Preliminary Science applicants are their own window's
CREATE OR REPLACE FUNCTION platform.applicant_window_type(p_type text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT p_type IN ('POST_UTME_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_CBT',
                      'JUPEB_APPLICATION', 'POSTGRADUATE_APPLICATION', 'CCE_APPLICATION', 'PRELIMINARY_SCIENCE_APPLICATION')
$$;

CREATE OR REPLACE FUNCTION platform.applicant_window_audience(p_type text, p_session text, p_after uuid, p_limit int)
RETURNS SETOF uuid LANGUAGE sql STABLE AS $$
    SELECT x.id FROM (
        SELECT a.id
          FROM admissions.application a
          JOIN admissions.applicant_account acc ON acc.id = a.account_id
          JOIN admissions.candidate c ON c.id = a.candidate_id
         WHERE p_type IN ('POST_UTME_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_CBT')
           AND a.session = p_session AND coalesce(c.entry_mode, '') NOT IN ('CCE', 'PRELIMINARY')
        UNION ALL
        SELECT a.id
          FROM admissions.application a
          JOIN admissions.applicant_account acc ON acc.id = a.account_id
          JOIN admissions.candidate c ON c.id = a.candidate_id
         WHERE p_type = 'CCE_APPLICATION' AND a.session = p_session AND c.entry_mode = 'CCE'
        UNION ALL
        SELECT a.id
          FROM admissions.application a
          JOIN admissions.applicant_account acc ON acc.id = a.account_id
          JOIN admissions.candidate c ON c.id = a.candidate_id
         WHERE p_type = 'PRELIMINARY_SCIENCE_APPLICATION' AND a.session = p_session AND c.entry_mode = 'PRELIMINARY'
        UNION ALL
        SELECT j.id FROM jupeb.application j
         WHERE p_type = 'JUPEB_APPLICATION' AND j.session = p_session AND j.withdrawn_at IS NULL
        UNION ALL
        SELECT g.id FROM admissions.pg_application g
         WHERE p_type = 'POSTGRADUATE_APPLICATION' AND g.session = p_session) x
     WHERE p_after IS NULL OR x.id > p_after
     ORDER BY x.id
     LIMIT greatest(1, p_limit)
$$;

CREATE OR REPLACE FUNCTION policy.applicant_window_done(p_type text, p_session text, p_application uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN p_type IN ('POST_UTME_REGISTRATION', 'CCE_APPLICATION') THEN
            coalesce((SELECT a.submitted_at IS NOT NULL FROM admissions.application a WHERE a.id = p_application), true)
        WHEN p_type = 'PRELIMINARY_SCIENCE_APPLICATION' THEN
            coalesce((SELECT r.state NOT IN ('DRAFT', 'CORRECTION_REQUIRED') FROM admissions.prelim_review r WHERE r.application_id = p_application), true)
        WHEN p_type = 'ADMISSION_STATUS_CHECKING' THEN
            coalesce((SELECT a.submitted_at IS NULL FROM admissions.application a WHERE a.id = p_application), true)
            OR EXISTS (SELECT 1 FROM admissions.status_check c WHERE c.application_id = p_application)
        WHEN p_type = 'POST_UTME_CBT' THEN
            coalesce((SELECT a.submitted_at IS NULL FROM admissions.application a WHERE a.id = p_application), true)
            OR EXISTS (SELECT 1 FROM assessment.cbt_attempt t WHERE t.application_id = p_application)
        WHEN p_type = 'JUPEB_APPLICATION' THEN
            coalesce((SELECT j.state NOT IN ('DRAFT', 'RETURNED') OR j.withdrawn_at IS NOT NULL FROM jupeb.application j WHERE j.id = p_application), true)
        WHEN p_type = 'POSTGRADUATE_APPLICATION' THEN
            coalesce((SELECT g.state <> 'DRAFT' FROM admissions.pg_application g WHERE g.id = p_application), true)
        ELSE true END
$$;

-- ── 7 · the fees: the route's own, through the ordinary references and receipts ──────────────────────────────────
/* the route an applicant's fees are read under: the CCE route, a preliminary programme's route, or none (the Post-UTME figures) */
CREATE OR REPLACE FUNCTION admissions.applicant_route(p_app uuid)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE c.entry_mode WHEN 'CCE' THEN 'CCE'
                             WHEN 'PRELIMINARY' THEN (SELECT r.route FROM admissions.prelim_review r WHERE r.application_id = a.id)
                             END
      FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id WHERE a.id = p_app
$fn$;

CREATE OR REPLACE FUNCTION admissions.new_fee_reference(p_app uuid, p_kind text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application; fee record; v_ref text; v_amount numeric; c record; v_cce boolean; v_try int; v_route text; v_prelim boolean;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    v_cce := EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE');
    v_route := admissions.applicant_route(p_app);
    v_prelim := v_route IS NOT NULL AND NOT v_cce;
    IF p_kind = 'APPLICATION' AND a.fee_confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'the application fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed for the application.';
    END IF;
    -- V446: a Preliminary Science applicant pays the application fee; the University has stated no checking or acceptance fee for it
    IF v_prelim AND p_kind <> 'APPLICATION' THEN
        SELECT r.checking_fee, r.acceptance_fee INTO fee FROM admissions.route_fee_rule(a.session, v_route) r;
        IF (p_kind = 'CHECKING' AND fee.checking_fee IS NULL) OR (p_kind = 'ACCEPTANCE' AND fee.acceptance_fee IS NULL) THEN
            RAISE EXCEPTION 'PRELIM_FEE_NOT_CONFIGURED: the University has not stated a Preliminary Science % fee for %', lower(p_kind), a.session USING ERRCODE = '23514';
        END IF;
    END IF;
    IF p_kind = 'CHECKING' AND NOT v_prelim THEN
        -- V295: the checking fee is open to every applicant with a valid Post-UTME application while the Director of ICT has
        -- admission status checking open — admitted, not admitted or not yet decided alike; the decision is what the check reveals
        SELECT * INTO c FROM admissions.status_checking(p_app);
        IF c.paid THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_PAID: the admission checking fee is already paid; nothing more is owed' USING ERRCODE = '23514';
        END IF;
        IF NOT c.application_valid THEN
            RAISE EXCEPTION '%', CASE WHEN v_cce THEN 'ADMISSION_CHECKING_NOT_ELIGIBLE: admission status checking follows a CCE application paid for and submitted'
                ELSE 'ADMISSION_CHECKING_NOT_ELIGIBLE: admission status checking is for applicants whose Post-UTME application is paid for and submitted' END USING ERRCODE = '23514';
        END IF;
        IF NOT c.window_open THEN
            -- V404: for CCE, checking opens when the Centre publishes the outcome of the application
            RAISE EXCEPTION '%', CASE WHEN v_cce THEN 'ADMISSION_CHECKING_CLOSED: the Centre for Continuing Education has not yet published the outcome of your application'
                ELSE 'ADMISSION_CHECKING_CLOSED: admission status checking is closed' END USING ERRCODE = '23514';
        END IF;
        -- a reference still open is the one to pay: the same service is never charged twice
        IF c.open_reference IS NOT NULL THEN RETURN c.open_reference; END IF;
    END IF;
    IF p_kind = 'ACCEPTANCE' AND NOT v_prelim THEN
        -- V295: the acceptance fee follows an offer the applicant has read through Admission Status Checking; before that the
        -- answer is the same whatever the decision, so no path here says whether there is an offer
        IF NOT (SELECT k.past FROM admissions.status_checking(p_app) k) THEN
            RAISE EXCEPTION 'ADMISSION_STATUS_NOT_CHECKED: check your admission status before paying for, accepting or declining the offer' USING ERRCODE = '23514';
        END IF;
        IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
            RAISE EXCEPTION 'there is no offer to accept' USING ERRCODE = '23514', HINT = 'The acceptance fee follows an offer of admission.';
        END IF;
        IF a.acceptance_confirmed_at IS NOT NULL THEN
            RAISE EXCEPTION 'the acceptance fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed to accept.';
        END IF;
    END IF;
    IF v_cce OR v_prelim THEN
        -- V379: the route's fees, as the Bursary stated them for the session (or last stated); never the Post-UTME figures.
        -- V404: the CCE admission checking fee among them; V446: a preliminary programme's fees, read the same way
        SELECT r.application_fee, r.portal_charge, r.acceptance_fee, r.checking_fee INTO fee FROM admissions.route_fee_rule(a.session, v_route) r;
        v_amount := CASE p_kind WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge WHEN 'CHECKING' THEN fee.checking_fee ELSE fee.acceptance_fee END;
        IF v_amount IS NULL THEN
            RAISE EXCEPTION '%', CASE WHEN v_cce THEN format('CCE_FEE_NOT_STATED: the Bursary has not stated the CCE %s fee for %s', lower(p_kind), a.session)
                                      ELSE format('PRELIM_FEE_NOT_CONFIGURED: the Bursary has not stated the Preliminary Science %s fee for %s', lower(p_kind), a.session) END
                USING ERRCODE = '23514';
        END IF;
    ELSE
    SELECT * INTO fee FROM admissions.applicant_fee_rule(a.session);
    -- V401: where the Bursary refuses to carry a session's applicant fees forward, nothing is paid until they are stated
    IF NOT fee.stated AND admissions.applicant_fee_policy() = 'REFUSE' THEN
        RAISE EXCEPTION 'APPLICANT_FEE_NOT_STATED: the % fee for % is not stated yet', lower(p_kind), a.session USING ERRCODE = '23514',
            HINT = 'The Bursary states the applicant fees for the session on Fee Setup.';
    END IF;
    -- each fee on its own reference (V271): the checking fee is never folded into the acceptance fee
    v_amount := CASE p_kind
                    WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge
                    WHEN 'CHECKING' THEN coalesce(fee.checking_fee, 0)
                    ELSE fee.acceptance_fee END;
    END IF;
    IF v_amount <= 0 THEN RAISE EXCEPTION 'no % fee is stated for %', lower(p_kind), a.session USING ERRCODE = '23514', HINT = 'The Bursary states the applicant fees on Fee Setup.'; END IF;
    -- a reference still open for the application fee is the one to pay (V446: never two at once for the same fee)
    IF v_prelim AND p_kind = 'APPLICATION' THEN
        SELECT r.reference INTO v_ref FROM admissions.fee_reference r
         WHERE r.application_id = p_app AND r.kind = 'APPLICATION' AND r.confirmed_at IS NULL AND r.expires_at > now() AND r.amount = v_amount
         ORDER BY r.generated_at DESC LIMIT 1;
        IF v_ref IS NOT NULL THEN RETURN v_ref; END IF;
    END IF;
    -- V390: the four random digits may repeat a reference another application drew (the last six digits of an application
    -- number are the session's running number, shared across sessions); a taken reference is drawn again, never answered as a clash
    FOR v_try IN 1..50 LOOP
        v_ref := 'MOAUM-' || CASE p_kind WHEN 'APPLICATION' THEN 'APP' WHEN 'CHECKING' THEN 'CHK' ELSE 'ACC' END || '-' || right(a.application_no, 6) || '-'
                 || lpad((floor(random() * 10000))::int::text, 4, '0');
        INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at)
        VALUES (gen_random_uuid(), p_app, p_kind, v_ref, v_amount, now() + interval '24 hours')
        ON CONFLICT (reference) DO NOTHING;
        IF FOUND THEN RETURN v_ref; END IF;
    END LOOP;
    RAISE EXCEPTION 'FEE_REFERENCE_EXHAUSTED: no free % reference was found for % in fifty draws', lower(p_kind), a.application_no USING ERRCODE = '23514',
        HINT = 'Try again; if it persists, the Directorate of ICT widens the reference.';
END $function$;

CREATE OR REPLACE FUNCTION admissions.confirm_fee(p_reference text, p_channel text, p_note text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE r admissions.fee_reference; a admissions.application; v_no text; v_purpose text; v_action text; v_sms_action text; v_prelim boolean;
BEGIN
    SELECT * INTO r FROM admissions.fee_reference WHERE reference = upper(btrim(p_reference));
    IF NOT FOUND THEN RAISE EXCEPTION 'no reference % was generated by this portal', p_reference USING ERRCODE = '23503',
        HINT = 'Only a reference this portal generated is confirmed; money sent anywhere else did not reach the University.'; END IF;
    IF r.confirmed_at IS NOT NULL THEN RETURN 'already confirmed'; END IF;
    IF admissions.acting_person() IS NULL THEN
        RAISE EXCEPTION 'a payment is confirmed by a person' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO a FROM admissions.application WHERE id = r.application_id;
    v_prelim := EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'PRELIMINARY');

    v_no := 'RCT-' || left(a.session, 4) || '-' || lpad(platform.next_number('RECEIPT', 'UNIVERSITY', a.session)::text, 5, '0');
    UPDATE admissions.fee_reference SET confirmed_at = now(), confirmed_by = admissions.acting_person(),
           channel = p_channel, note = p_note, receipt_no = v_no WHERE id = r.id;

    IF r.kind = 'APPLICATION' THEN
        UPDATE admissions.application SET fee_confirmed_at = coalesce(fee_confirmed_at, now()) WHERE id = a.id;
        v_purpose := CASE WHEN EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE') THEN 'CCE application'
                          WHEN v_prelim THEN 'Preliminary Science application' ELSE 'Application & Post-UTME' END;
        v_action := 'Your application form is now open: sign in and complete it.';
        v_sms_action := 'Your application form is open.';
    ELSIF r.kind = 'CHECKING' THEN
        -- V295: the fee grants the checking service; the status is read, and recorded, when the applicant checks it
        UPDATE admissions.application SET checking_confirmed_at = coalesce(checking_confirmed_at, now()) WHERE id = a.id;
        -- V412: a CCE applicant's checking fee is the CCE admission checking fee, paid to read the published outcome
        IF EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE') THEN
            v_purpose := 'CCE admission checking';
            v_action := 'Your CCE admission checking fee payment has been verified. Sign in and open Admission Status to read the outcome of your application.';
            v_sms_action := 'CCE admission checking fee verified. Sign in to read the outcome of your application.';
        ELSE
            v_purpose := 'Admission checking';
            v_action := 'Your Admission Checking Fee payment has been verified. You can now check your admission status: sign in and open Admission Status.';
            v_sms_action := 'Admission checking fee verified. You can now check your admission status.';
        END IF;
    ELSE
        UPDATE admissions.application SET acceptance_confirmed_at = coalesce(acceptance_confirmed_at, now()) WHERE id = a.id;
        v_purpose := CASE WHEN EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE') THEN 'CCE acceptance' ELSE 'Acceptance' END;
        v_action := 'Your acceptance of the offer is settled. Sign in to continue to clearance.';
        v_sms_action := 'Acceptance settled.';
        PERFORM admissions.settle_acceptance(a.id);
    END IF;

    IF v_prelim THEN
        -- V446: a Preliminary Science payment is told through the central templates (email, SMS and the portal), with its receipt
        PERFORM platform.tell_applicant(a.id, 'PRELIMINARY_SCIENCE', 'PAYMENT_SUCCESSFUL',
            jsonb_build_object('RECEIPT_NUMBER', v_no, 'REFERENCE', r.reference, 'PURPOSE', v_purpose || ' fee',
                               'AMOUNT', 'NGN ' || to_char(r.amount, 'FM999,999,990.00'), 'PAID_ON', to_char(now() AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY'),
                               'CHANNEL', coalesce(p_channel, 'Bank')),
            'PRELIMINARY_SCIENCE_PAYMENT_SUCCESSFUL:' || r.reference);
        RETURN 'confirmed';
    END IF;

    PERFORM admissions.notify_applicant(a.id, 'Your payment receipt · ' || v_no,
        'This is your official receipt from Rev. Fr. Moses Orshio Adasu University, Makurdi.' || chr(10) || chr(10)
        || 'Receipt no:  ' || v_no || chr(10)
        || 'Reference:   ' || r.reference || chr(10)
        || 'Purpose:     ' || v_purpose || ' fee' || chr(10)
        || 'Session:     ' || a.session || chr(10)
        || 'Amount:      NGN ' || to_char(r.amount, 'FM999,999,990.00') || chr(10)
        || 'Confirmed:   ' || to_char(now(), 'FMDD FMMonth YYYY') || chr(10)
        || 'Channel:     ' || coalesce(p_channel, 'Bank') || chr(10) || chr(10)
        || v_action || chr(10) || chr(10)
        || 'Keep this receipt. It is verified against the University''s record by its receipt number, not by its appearance.',
        'MOAUM receipt ' || v_no || ': NGN ' || to_char(r.amount, 'FM999,999,990.00') || ' for ' || v_purpose || ' confirmed. ' || v_sms_action);

    RETURN 'confirmed';
END $function$;

/* the Bursary states a route's applicant fees: every CCE fee (V379, V404); for a preliminary programme the application fee, and
   any other fee only when the University has given one (V446) */
CREATE OR REPLACE FUNCTION admissions.set_route_fee(p_session text, p_route text, p_application numeric, p_portal numeric, p_acceptance numeric, p_checking numeric)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v_route text := upper(btrim(p_route)); v_prelim boolean;
BEGIN
    v_prelim := EXISTS (SELECT 1 FROM admissions.prelim_programme p WHERE p.route = v_route);
    PERFORM admissions.cce_require_office(ARRAY['bursar', 'super'], CASE WHEN v_prelim THEN 'stating the Preliminary Science applicant fees' ELSE 'stating the CCE applicant fees' END);
    IF v_prelim THEN
        IF p_application IS NULL OR p_application < 0 OR coalesce(p_acceptance, 0) < 0 OR coalesce(p_checking, 0) < 0 OR coalesce(p_portal, 0) < 0 THEN
            RAISE EXCEPTION 'PRELIM_FEE_AMOUNT: the application fee is stated; an acceptance or checking fee only when the University has given one, and none is negative' USING ERRCODE = '23514';
        END IF;
    ELSIF p_application IS NULL OR p_acceptance IS NULL OR p_checking IS NULL
       OR p_application < 0 OR p_acceptance < 0 OR p_checking < 0 OR coalesce(p_portal, 0) < 0 THEN
        RAISE EXCEPTION 'CCE_FEE_AMOUNT: the application, admission checking and acceptance fees are stated, and none is negative' USING ERRCODE = '23514';
    END IF;
    INSERT INTO admissions.route_fee (session, route, application_fee, portal_charge, acceptance_fee, checking_fee, stated_by, stated_office)
    VALUES (p_session, v_route, p_application, coalesce(p_portal, 0), p_acceptance, p_checking,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, current_setting('moaum.actor_office', true))
    ON CONFLICT (session, route) DO UPDATE SET application_fee = EXCLUDED.application_fee, portal_charge = EXCLUDED.portal_charge,
        acceptance_fee = EXCLUDED.acceptance_fee, checking_fee = EXCLUDED.checking_fee, stated_by = EXCLUDED.stated_by,
        stated_office = EXCLUDED.stated_office, stated_at = now();
END $function$;

-- ── 8 · kept apart from Post-UTME ────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.screening_required(p_app uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT coalesce((SELECT sp.enabled AND (a.accepted_at IS NULL OR a.accepted_at >= sp.enabled_from)
                       FROM admissions.application a JOIN admissions.screening_policy sp ON sp.session = a.session
                       JOIN admissions.candidate c ON c.id = a.candidate_id AND c.entry_mode NOT IN ('CCE', 'PRELIMINARY') WHERE a.id = p_app), false);
$function$;

CREATE OR REPLACE FUNCTION admissions.status_checking_rows(p_session text, p_cce boolean)
 RETURNS TABLE(application_id uuid, application_no text, jamb_reg_no text, name text, sex text, programme text, programme_code text, faculty_code text, faculty text, dept_code text, department text, valid boolean, paid boolean, paid_at timestamp with time zone, reference text, amount numeric, checked boolean, checks bigint, first_checked_at timestamp with time zone, last_checked_at timestamp with time zone, last_result text, result text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT a.id, a.application_no, c.jamb_reg_no, c.surname || ', ' || c.other_names, r.sex, c.programme, p.code,
           p.faculty_code, fa.name, p.dept_code, d.name,
           (a.fee_confirmed_at IS NOT NULL AND a.submitted_at IS NOT NULL),
           (a.checking_confirmed_at IS NOT NULL OR ck.confirmed_at IS NOT NULL OR a.acceptance_confirmed_at IS NOT NULL),
           coalesce(a.checking_confirmed_at, ck.confirmed_at), ck.reference, ck.amount,
           (k.n > 0 OR a.status_checked_at IS NOT NULL), k.n, coalesce(k.first_at, a.status_checked_at), coalesce(k.last_at, a.status_checked_at), k.last_result,
           CASE WHEN a.decision_released_at IS NULL OR a.decision IS NULL THEN 'PENDING'
                WHEN a.decision = 'OFFERED' THEN 'ADMITTED' WHEN a.decision = 'WAITING' THEN 'WAITING_LIST' ELSE 'NOT_ADMITTED' END
      FROM admissions.application a
      JOIN admissions.candidate c ON c.id = a.candidate_id
      LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
      LEFT JOIN ref.programme p ON p.code = admissions.programme_code_of(c.programme)
      LEFT JOIN ref.faculty fa ON fa.code = p.faculty_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN LATERAL (SELECT x.reference, x.amount, x.confirmed_at FROM admissions.fee_reference x
                          WHERE x.application_id = a.id AND x.kind = 'CHECKING' AND x.confirmed_at IS NOT NULL ORDER BY x.confirmed_at LIMIT 1) ck ON true
      LEFT JOIN LATERAL (SELECT count(*) AS n, min(s.checked_at) AS first_at, max(s.checked_at) AS last_at,
                                (array_agg(s.result ORDER BY s.checked_at DESC))[1] AS last_result
                           FROM admissions.status_check s WHERE s.application_id = a.id) k ON true
     WHERE a.session = p_session
       -- V412: the CCE applicants apart from the rest (their checking is not the ICT window's); V446: Preliminary Science has none
       AND (coalesce(c.entry_mode, '') = 'CCE') = coalesce(p_cce, false)
       AND coalesce(c.entry_mode, '') <> 'PRELIMINARY'
$function$;

-- ── 9 · the Preliminary Science application ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.prelim_require_office(p_offices text[], p_what text)
RETURNS void LANGUAGE plpgsql STABLE AS $fn$
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION '% is done by a person', p_what USING ERRCODE = '23514';
    END IF;
    IF coalesce(nullif(current_setting('moaum.actor_office', true), ''), '') <> ALL (p_offices) THEN
        RAISE EXCEPTION 'PRELIM_OFFICE: % is for %', p_what, array_to_string(p_offices, ', ') USING ERRCODE = '23514';
    END IF;
END $fn$;

CREATE OR REPLACE FUNCTION admissions.prelim_log(p_app uuid, p_action text, p_from text, p_to text, p_note text, p_detail jsonb DEFAULT NULL)
RETURNS void LANGUAGE sql AS $fn$
    INSERT INTO admissions.prelim_review_event (application_id, actor, office, action, from_state, to_state, note, detail)
    VALUES (p_app, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''),
            p_action, p_from, p_to, nullif(btrim(coalesce(p_note, '')), ''), p_detail)
$fn$;

/* the review of a Preliminary Science application; anything else is refused */
CREATE OR REPLACE FUNCTION admissions.prelim_application(p_app uuid)
RETURNS admissions.prelim_review LANGUAGE plpgsql STABLE AS $fn$
DECLARE r admissions.prelim_review;
BEGIN
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app;
    IF r.application_id IS NULL THEN RAISE EXCEPTION 'PRELIM_NOT_APPLICATION: that is not a Preliminary Science application' USING ERRCODE = '23514'; END IF;
    RETURN r;
END $fn$;

/* the admission settings under which a session's O'Level subjects are matched (the Committee's stated equivalences) */
CREATE OR REPLACE FUNCTION admissions.prelim_policy(p_session text)
RETURNS uuid LANGUAGE sql STABLE AS $fn$
    SELECT id FROM admissions.session_policy WHERE session = p_session ORDER BY (state = 'IN_FORCE') DESC, rules_version DESC LIMIT 1
$fn$;

/* the biodata a Preliminary Science applicant gives, and which of it is required */
CREATE OR REPLACE FUNCTION admissions.prelim_form_fields()
RETURNS TABLE (field text, required boolean)
LANGUAGE sql IMMUTABLE AS $fn$
    VALUES ('date_of_birth', true), ('place_of_birth', false), ('marital_status', false), ('religion', false), ('home_address', true),
           ('postal_address', false), ('state_of_origin', true), ('lga', true), ('nationality', true), ('mobile', true), ('alt_mobile', false),
           ('personal_email', false), ('disability', false), ('kin_name', true), ('kin_relationship', true), ('kin_mobile', true), ('kin_address', false)
$fn$;

/* whether the application fee stands settled: confirmed, or nothing to pay */
CREATE OR REPLACE FUNCTION admissions.prelim_fee_settled(p_app uuid)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT a.fee_confirmed_at IS NOT NULL
           OR coalesce((SELECT f.application_fee + f.portal_charge = 0 FROM admissions.route_fee_rule(a.session, r.route) f), false)
      FROM admissions.application a JOIN admissions.prelim_review r ON r.application_id = a.id WHERE a.id = p_app
$fn$;

/* the applicant changes the form while it is theirs — a draft, or back with them for a correction — and once the fee is paid */
CREATE OR REPLACE FUNCTION admissions.prelim_require_editable(p_app uuid)
RETURNS admissions.prelim_review LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review;
BEGIN
    PERFORM admissions.prelim_application(p_app);
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    IF r.state NOT IN ('DRAFT', 'CORRECTION_REQUIRED') THEN
        RAISE EXCEPTION 'PRELIM_NOT_EDITABLE: the application is % and is with the Preliminary Science Office; it is changed only when the Office asks',
            lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF NOT admissions.prelim_fee_settled(p_app) THEN
        RAISE EXCEPTION 'PRELIM_FEE_FIRST: pay the application fee first; the application form opens once the payment is verified' USING ERRCODE = '23514';
    END IF;
    RETURN r;
END $fn$;

/* the eligibility, worked out on the O'Level the applicant gave, under the programme's rule. A credit is a grade no worse than
   the credit grade; a subject sat twice counts once, at its better grade; the core subjects are matched as the eligibility engine
   matches them (admissions.subject_same, the session's stated equivalences included). An awaiting result is never a credit: the
   form takes none (prelim_save_olevel), and no result at all is RESULT_REQUIRED. An eligible candidate short of the completion
   rule is ELIGIBLE_WITH_REMEDIATION, with what is to be made up; an officer's finding that the result is invalid stands over all. */
CREATE OR REPLACE FUNCTION admissions.prelim_evaluate(p_app uuid)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; a admissions.application; p admissions.prelim_programme; v_policy uuid; v_credit int; v_sittings int;
        v_total int := NULL; v_core text[] := NULL; v_missing text[] := '{}'; v_short int := 0; v_status text; v_checks jsonb := '[]'::jsonb;
        v_reasons text[] := '{}'; v_rem text; v_ok_credits boolean; v_ok_sittings boolean; v_ok_core boolean;
BEGIN
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    IF r.application_id IS NULL THEN RETURN NULL; END IF;
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = r.route;
    v_policy := admissions.prelim_policy(a.session);
    v_credit := admissions.grade_rank(p.credit_grade);
    SELECT count(DISTINCT o.sitting) INTO v_sittings FROM admissions.screening_olevel o WHERE o.application_id = p_app AND o.active;
    IF v_sittings = 0 THEN
        v_status := 'RESULT_REQUIRED';
        v_reasons := ARRAY['No released O''Level result has been given. Admission is on results already released; an awaiting result is not accepted.'];
        v_checks := jsonb_build_array(jsonb_build_object('key', 'RESULT_RELEASED', 'label', 'O''Level results released (no awaiting result)', 'ok', false));
    ELSE
        WITH best AS (SELECT min(btrim(o.subject)) AS subject, min(admissions.grade_rank(o.grade)) AS rank
                        FROM admissions.screening_olevel o WHERE o.application_id = p_app AND o.active
                       GROUP BY lower(btrim(o.subject)))
        SELECT count(*) FILTER (WHERE best.rank <= v_credit),
               (SELECT array_agg(cs ORDER BY ord) FROM unnest(p.core_subjects) WITH ORDINALITY u(cs, ord)
                 WHERE EXISTS (SELECT 1 FROM best b WHERE b.rank <= v_credit AND admissions.subject_same(b.subject, cs, v_policy, 'OLEVEL'))),
               (SELECT coalesce(array_agg(cs ORDER BY ord), '{}') FROM unnest(p.completion_subjects) WITH ORDINALITY u(cs, ord)
                 WHERE NOT EXISTS (SELECT 1 FROM best b WHERE b.rank <= v_credit AND admissions.subject_same(b.subject, cs, v_policy, 'OLEVEL')))
          INTO v_total, v_core, v_missing
          FROM best;
        v_core := coalesce(v_core, '{}');
        v_ok_credits := v_total >= p.min_credits;
        v_ok_sittings := v_sittings <= p.max_sittings;
        v_ok_core := cardinality(v_core) >= p.min_core_credits;
        v_checks := jsonb_build_array(
            jsonb_build_object('key', 'MIN_CREDITS', 'label', 'Credit passes (' || p.credit_grade || ' or better)', 'required', p.min_credits, 'held', v_total, 'ok', v_ok_credits),
            jsonb_build_object('key', 'MAX_SITTINGS', 'label', 'Sittings', 'required', p.max_sittings, 'held', v_sittings, 'ok', v_ok_sittings, 'atMost', true),
            jsonb_build_object('key', 'MIN_CORE_CREDITS', 'label', 'Credits in ' || array_to_string(p.core_subjects, ', '), 'required', p.min_core_credits,
                               'held', cardinality(v_core), 'ok', v_ok_core, 'subjects', to_jsonb(v_core)),
            jsonb_build_object('key', 'RESULT_RELEASED', 'label', 'O''Level results released (no awaiting result)', 'ok', true));
        IF NOT v_ok_credits THEN
            v_reasons := v_reasons || format('%s credit pass%s held; at least %s are required.', v_total, CASE WHEN v_total = 1 THEN '' ELSE 'es' END, p.min_credits);
        END IF;
        IF NOT v_ok_sittings THEN
            v_reasons := v_reasons || format('%s sittings given; at most %s %s allowed.', v_sittings, p.max_sittings, CASE WHEN p.max_sittings = 1 THEN 'is' ELSE 'are' END);
        END IF;
        IF NOT v_ok_core THEN
            v_reasons := v_reasons || format('%s credit%s among %s; at least %s are required.', cardinality(v_core), CASE WHEN cardinality(v_core) = 1 THEN '' ELSE 's' END,
                                             array_to_string(p.core_subjects, ', '), p.min_core_credits);
        END IF;
        IF v_ok_credits AND v_ok_sittings AND v_ok_core THEN
            -- the completion rule: the named subjects credited, and the total reached; credits besides the named subjects are counted apart
            v_short := greatest(0, p.completion_credits - v_total - cardinality(v_missing));
            v_status := CASE WHEN cardinality(v_missing) > 0 OR v_short > 0 THEN 'ELIGIBLE_WITH_REMEDIATION' ELSE 'ELIGIBLE' END;
        ELSE
            v_status := 'NOT_ELIGIBLE';
            v_missing := '{}';
        END IF;
    END IF;
    IF r.olevel_verification = 'INVALID' THEN
        v_status := 'INVALID_RESULT';
        v_reasons := ARRAY['The O''Level result was found invalid on verification' || coalesce(': ' || r.olevel_note, '.')] || v_reasons;
    END IF;
    -- the remediation the completion rule asks for; an officer's own setting (in progress, completed, not completed, review) stands
    v_rem := r.remediation_status;
    IF v_status IN ('ELIGIBLE', 'ELIGIBLE_WITH_REMEDIATION') THEN
        IF r.remediation_status IS NULL OR r.remediation_status IN ('NOT_REQUIRED', 'REQUIRED') THEN
            v_rem := CASE WHEN v_status = 'ELIGIBLE_WITH_REMEDIATION' THEN 'REQUIRED' ELSE 'NOT_REQUIRED' END;
        END IF;
    ELSIF r.remediation_status IN ('NOT_REQUIRED', 'REQUIRED') THEN
        v_rem := NULL;
    END IF;
    UPDATE admissions.prelim_review
       SET eligibility_status = v_status, total_credits = v_total, core_credits = CASE WHEN v_core IS NULL THEN NULL ELSE cardinality(v_core) END,
           sittings = v_sittings, credited_core = v_core, eligibility_checks = v_checks, eligibility_reasons = v_reasons, evaluated_at = now(),
           rules_version = p.rules_version, remediation_status = v_rem,
           remediation_subjects = CASE WHEN v_status = 'ELIGIBLE_WITH_REMEDIATION' THEN v_missing ELSE '{}' END,
           remediation_credits_short = CASE WHEN v_status = 'ELIGIBLE_WITH_REMEDIATION' THEN v_short ELSE 0 END,
           updated_at = now()
     WHERE application_id = p_app;
    RETURN v_status;
END $fn$;

/* what still stands between the applicant and submitting, step by step */
CREATE OR REPLACE FUNCTION admissions.prelim_problems(p_app uuid)
RETURNS TABLE (step text, field text, message text)
LANGUAGE sql STABLE AS $fn$
    WITH a AS (SELECT ap.*, c.sex FROM admissions.application ap JOIN admissions.candidate c ON c.id = ap.candidate_id WHERE ap.id = p_app),
         r AS (SELECT x.* FROM admissions.prelim_review x WHERE x.application_id = p_app),
         fee AS (SELECT f.* FROM a CROSS JOIN r CROSS JOIN LATERAL admissions.route_fee_rule(a.session, r.route) f),
         ans AS (SELECT x.field, x.value FROM admissions.screening_answer x WHERE x.application_id = p_app),
         ol AS (SELECT x.* FROM admissions.screening_olevel x WHERE x.application_id = p_app AND x.active),
         sittings AS (SELECT count(DISTINCT sitting) AS n FROM ol),
         docs AS (SELECT d.* FROM admissions.application_document d WHERE d.application_id = p_app AND d.superseded_at IS NULL),
         req AS (SELECT d.* FROM admissions.prelim_document d JOIN r ON r.route = d.route WHERE d.required AND (NOT d.second_sitting_only OR (SELECT n FROM sittings) >= 2))
    SELECT 'PAYMENT', 'application_fee',
           CASE WHEN NOT EXISTS (SELECT 1 FROM fee) THEN 'The Bursary has not yet stated the Preliminary Science application fee for ' || (SELECT session FROM a) || '; the form opens once it is paid'
                ELSE 'Pay the Preliminary Science application fee' END
     WHERE NOT admissions.prelim_fee_settled(p_app)
    UNION ALL
    SELECT 'PERSONAL', 'sex', 'Give your sex' WHERE (SELECT sex FROM a) IS NULL
    UNION ALL
    SELECT 'PERSONAL', f.field, 'Give your ' || replace(replace(replace(f.field, 'kin_', 'next of kin''s '), '_', ' '), 'lga', 'local government area')
      FROM admissions.prelim_form_fields() f WHERE f.required AND NOT EXISTS (SELECT 1 FROM ans WHERE ans.field = f.field)
    UNION ALL
    SELECT 'OLEVEL', 'sittings', 'Give your O''Level results (one sitting or two). An awaiting result is not accepted.' WHERE (SELECT n FROM sittings) = 0
    UNION ALL
    SELECT 'PROGRAMME', 'target', 'Choose the programme you intend to progress to' WHERE (SELECT target_programme FROM r) IS NULL
    UNION ALL
    SELECT 'PROGRAMME', 'target', 'The programme you chose is no longer offered under Preliminary Science; choose another'
     WHERE (SELECT target_programme FROM r) IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM admissions.prelim_target t JOIN r ON r.route = t.route AND t.programme_code = r.target_programme WHERE t.state = 'MAPPED')
    UNION ALL
    SELECT 'DOCUMENTS', q.kind, 'Upload your ' || lower(left(q.label, 1)) || substr(q.label, 2)
      FROM req q WHERE NOT EXISTS (SELECT 1 FROM docs WHERE docs.kind = q.kind)
    UNION ALL
    SELECT 'DOCUMENTS', d.kind, 'Replace your ' || lower(coalesce((SELECT q.label FROM admissions.prelim_document q JOIN r ON r.route = q.route WHERE q.kind = d.kind), replace(d.kind, '_', ' ')))
                                 || ', which the Office could not accept: ' || rtrim(coalesce(d.review_note, ''), '. ')
      FROM docs d WHERE d.status = 'REJECTED'
$fn$;

/* the applicant's account and application: while the window of the programme's session is open; one per address, and one per
   person (name and date of birth) in a session. The candidate is an ordinary admissions candidate with no JAMB number. */
CREATE OR REPLACE FUNCTION admissions.prelim_register(p_route text, p_surname text, p_first text, p_middle text, p_sex text, p_dob date,
                                                      p_email text, p_phone text, p_hash text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE p admissions.prelim_programme; v_session text; v_state text; v_candidate uuid := gen_random_uuid(); v_account uuid := gen_random_uuid();
        v_app uuid := gen_random_uuid(); v_no text; fee record; v_surname text := upper(btrim(coalesce(p_surname, '')));
        v_first text := initcap(btrim(coalesce(p_first, ''))); v_middle text := nullif(initcap(btrim(coalesce(p_middle, ''))), '');
        v_phone text := admissions.cce_phone(p_phone);
BEGIN
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = upper(btrim(p_route));
    IF p.route IS NULL THEN RAISE EXCEPTION 'PRELIM_NO_PROGRAMME: no preliminary programme %', p_route USING ERRCODE = '23514'; END IF;
    v_session := policy.route_session(p.route);
    SELECT w.state INTO v_state FROM policy.window_state('PRELIMINARY_SCIENCE_APPLICATION', v_session, NULL) w;
    IF coalesce(v_state, 'CLOSED') <> 'OPEN' THEN
        RAISE EXCEPTION 'APPLICATION_CLOSED: the % application for % is %', p.name, v_session, lower(coalesce(v_state, 'closed')) USING ERRCODE = '23514';
    END IF;
    IF v_surname = '' OR v_first = '' OR length(v_surname) > 60 OR length(v_first) > 60 OR length(coalesce(v_middle, '')) > 60 THEN
        RAISE EXCEPTION 'PRELIM_NAME: the surname and first name are given, as on your O''Level certificate' USING ERRCODE = '23514';
    END IF;
    IF upper(coalesce(p_sex, '')) NOT IN ('M', 'F') THEN RAISE EXCEPTION 'PRELIM_SEX: give your sex' USING ERRCODE = '23514'; END IF;
    IF p_dob IS NULL OR p_dob > current_date OR p_dob < DATE '1950-01-01' THEN
        RAISE EXCEPTION 'PRELIM_DATE_OF_BIRTH: give your date of birth' USING ERRCODE = '23514';
    END IF;
    IF v_phone IS NULL THEN RAISE EXCEPTION 'PRELIM_PHONE: give a Nigerian mobile number (eleven digits beginning with 0)' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE lower(a.email) = lower(btrim(p_email))) THEN
        RAISE EXCEPTION 'the address % already belongs to an application account', btrim(p_email) USING ERRCODE = '23505', HINT = 'Sign in with it, or use another address.';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.candidate c JOIN admissions.application ap ON ap.candidate_id = c.id
                 JOIN admissions.screening_answer s ON s.application_id = ap.id AND s.field = 'date_of_birth'
                WHERE c.session = v_session AND c.entry_mode = 'PRELIMINARY' AND upper(c.surname) = v_surname
                  AND lower(split_part(c.other_names, ' ', 1)) = lower(v_first) AND s.value = p_dob::text) THEN
        RAISE EXCEPTION 'PRELIM_DUPLICATE: an application for % % born % already exists for %', v_first, v_surname, to_char(p_dob, 'DD Mon YYYY'), v_session USING ERRCODE = '23514',
            HINT = 'Sign in to the application you started; a forgotten password is reset from the sign-in page. If it is not yours, write to the Preliminary Science Office.';
    END IF;
    INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, sex)
    VALUES (v_candidate, v_session, NULL, v_surname, btrim(v_first || coalesce(' ' || v_middle, '')), p.name, 'PRELIMINARY', 0, 'PROPOSED', upper(p_sex));
    INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
    VALUES (v_account, v_session, v_candidate, NULL, btrim(p_email), v_phone, p_hash);
    v_no := 'APP/' || substr(v_session, 3, 2) || '/' || lpad(platform.next_number('APPLICATION', 'UNIVERSITY', v_session)::text, 6, '0');
    INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no) VALUES (v_app, v_account, v_candidate, v_session, v_no);
    INSERT INTO admissions.prelim_review (application_id, route, state) VALUES (v_app, p.route, 'DRAFT');
    INSERT INTO admissions.screening_answer (application_id, field, value)
    VALUES (v_app, 'date_of_birth', p_dob::text), (v_app, 'mobile', v_phone), (v_app, 'personal_email', btrim(p_email));
    -- an application fee stated as nothing is nothing to pay
    SELECT * INTO fee FROM admissions.route_fee_rule(v_session, p.route);
    IF fee.stated IS NOT NULL AND coalesce(fee.application_fee, -1) + coalesce(fee.portal_charge, 0) = 0 THEN
        UPDATE admissions.application SET fee_confirmed_at = now() WHERE id = v_app;
    END IF;
    PERFORM admissions.prelim_evaluate(v_app);
    PERFORM admissions.prelim_log(v_app, 'REGISTERED', NULL, 'DRAFT', 'The application was started online');
    PERFORM platform.tell_applicant(v_app, 'PRELIMINARY_SCIENCE', 'APPLICATION_CREATED', '{}'::jsonb, 'PRELIMINARY_SCIENCE_APPLICATION_CREATED:' || v_app);
    RETURN v_account;
END $fn$;

CREATE OR REPLACE FUNCTION admissions.prelim_save_biodata(p_app uuid, p_fields jsonb, p_sex text)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; k text; v text; n int := 0; d date;
BEGIN
    r := admissions.prelim_require_editable(p_app);
    IF p_fields IS NULL OR jsonb_typeof(p_fields) <> 'object' THEN RAISE EXCEPTION 'the form is a set of fields' USING ERRCODE = '23514'; END IF;
    IF p_sex IS NOT NULL THEN
        IF upper(btrim(p_sex)) NOT IN ('M', 'F') THEN RAISE EXCEPTION 'PRELIM_SEX: the sex is male or female' USING ERRCODE = '23514'; END IF;
        UPDATE admissions.candidate c SET sex = upper(btrim(p_sex)) FROM admissions.application a WHERE a.id = p_app AND c.id = a.candidate_id;
    END IF;
    FOR k IN SELECT jsonb_object_keys(p_fields) LOOP
        IF NOT EXISTS (SELECT 1 FROM admissions.prelim_form_fields() f WHERE f.field = k) THEN
            RAISE EXCEPTION 'PRELIM_FIELD: % is not a field of the Preliminary Science form', k USING ERRCODE = '23514';
        END IF;
        v := nullif(btrim(coalesce(p_fields->>k, '')), '');
        IF v IS NOT NULL AND length(v) > 400 THEN RAISE EXCEPTION 'PRELIM_FIELD: % is too long', k USING ERRCODE = '23514'; END IF;
        IF k = 'date_of_birth' AND v IS NOT NULL THEN
            d := admissions.cce_date(v);
            IF d IS NULL OR d > current_date OR d < DATE '1950-01-01' THEN RAISE EXCEPTION 'PRELIM_FIELD: the date of birth cannot be read' USING ERRCODE = '23514'; END IF;
            v := d::text;
        END IF;
        IF k IN ('mobile', 'alt_mobile', 'kin_mobile') AND v IS NOT NULL THEN
            IF admissions.cce_phone(v) IS NULL THEN RAISE EXCEPTION 'PRELIM_FIELD: % is not a Nigerian mobile number (eleven digits beginning with 0)', replace(k, '_', ' ') USING ERRCODE = '23514'; END IF;
            v := admissions.cce_phone(v);
        END IF;
        IF k = 'personal_email' AND v IS NOT NULL AND v !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN RAISE EXCEPTION 'PRELIM_FIELD: that is not a complete email address' USING ERRCODE = '23514'; END IF;
        IF v IS NULL THEN
            DELETE FROM admissions.screening_answer WHERE application_id = p_app AND field = k;
        ELSE
            INSERT INTO admissions.screening_answer (application_id, field, value) VALUES (p_app, k, v)
            ON CONFLICT (application_id, field) DO UPDATE SET value = EXCLUDED.value;
        END IF;
        n := n + 1;
    END LOOP;
    UPDATE admissions.application a
       SET next_of_kin = nullif(btrim(concat_ws(', ', (SELECT value FROM admissions.screening_answer WHERE application_id = p_app AND field = 'kin_name')
                                                    || coalesce(' (' || (SELECT value FROM admissions.screening_answer WHERE application_id = p_app AND field = 'kin_relationship') || ')', ''),
                                                (SELECT value FROM admissions.screening_answer WHERE application_id = p_app AND field = 'kin_mobile'))), '')
     WHERE a.id = p_app;
    RETURN n;
END $fn$;

/* the O'Level: one sitting or two (as the programme allows), each complete and RELEASED — the examination body, type, number and
   year, and its subjects and grades. An awaiting result is refused outright: admission is strictly on results already released. */
CREATE OR REPLACE FUNCTION admissions.prelim_save_olevel(p_app uuid, p_sittings jsonb)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; p admissions.prelim_programme; s jsonb; g jsonb; v_sit int; v_body text; v_type text; v_no text; v_year int; n int := 0; ord int := 0;
        v_subj text; v_grade text; seen text[];
BEGIN
    r := admissions.prelim_require_editable(p_app);
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = r.route;
    IF p_sittings IS NULL OR jsonb_typeof(p_sittings) <> 'array' OR jsonb_array_length(p_sittings) < 1 THEN
        RAISE EXCEPTION 'PRELIM_OLEVEL_SITTINGS: give one sitting or two' USING ERRCODE = '23514';
    END IF;
    IF jsonb_array_length(p_sittings) > 2 OR jsonb_array_length(p_sittings) > p.max_sittings THEN
        RAISE EXCEPTION 'PRELIM_OLEVEL_SITTINGS: at most % sitting% are accepted for %', p.max_sittings, CASE WHEN p.max_sittings = 1 THEN '' ELSE 's' END, p.name USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.screening_olevel SET active = false WHERE application_id = p_app AND active;
    SELECT coalesce(max(o.ord), 0) INTO ord FROM admissions.screening_olevel o WHERE o.application_id = p_app;
    FOR s IN SELECT x FROM jsonb_array_elements(p_sittings) x LOOP
        v_sit := coalesce((s->>'sitting')::int, 0);
        IF v_sit NOT IN (1, 2) THEN RAISE EXCEPTION 'PRELIM_OLEVEL_SITTINGS: a sitting is the first or the second' USING ERRCODE = '23514'; END IF;
        IF coalesce((s->>'awaiting')::boolean, false) THEN
            RAISE EXCEPTION 'PRELIM_AWAITING_RESULT: sitting %: an awaiting result is not accepted — Preliminary Science admission is strictly on results already released', v_sit USING ERRCODE = '23514';
        END IF;
        v_body := upper(btrim(coalesce(s->>'exam_body', '')));
        IF v_body NOT IN ('WAEC', 'NECO', 'NABTEB', 'OTHER') THEN
            RAISE EXCEPTION 'PRELIM_OLEVEL_BODY: sitting %: the examination body is WAEC, NECO, NABTEB or another', v_sit USING ERRCODE = '23514';
        END IF;
        v_type := nullif(upper(btrim(coalesce(s->>'exam_type', ''))), '');
        IF v_type IS NOT NULL AND v_type NOT IN ('SSCE', 'GCE', 'OTHER') THEN
            RAISE EXCEPTION 'PRELIM_OLEVEL_TYPE: sitting %: the examination is the school certificate (SSCE), the GCE or another', v_sit USING ERRCODE = '23514';
        END IF;
        v_no := nullif(btrim(coalesce(s->>'exam_number', '')), '');
        IF v_no IS NULL OR length(v_no) > 30 THEN RAISE EXCEPTION 'PRELIM_OLEVEL_NUMBER: sitting %: the examination number is given', v_sit USING ERRCODE = '23514'; END IF;
        v_year := CASE WHEN coalesce(s->>'exam_year', '') ~ '^[0-9]{4}$' THEN (s->>'exam_year')::int END;
        IF v_year IS NULL OR v_year < 1970 OR v_year > extract(year FROM current_date)::int THEN
            RAISE EXCEPTION 'PRELIM_OLEVEL_YEAR: sitting %: the year of the examination is given', v_sit USING ERRCODE = '23514';
        END IF;
        IF jsonb_typeof(s->'subjects') <> 'array' OR jsonb_array_length(s->'subjects') = 0 THEN
            RAISE EXCEPTION 'PRELIM_OLEVEL_INCOMPLETE: sitting % has no subjects; a second sitting is complete or not given', v_sit USING ERRCODE = '23514';
        END IF;
        IF jsonb_array_length(s->'subjects') > 9 THEN RAISE EXCEPTION 'PRELIM_OLEVEL_SUBJECTS: sitting %: nine subjects at most', v_sit USING ERRCODE = '23514'; END IF;
        seen := '{}';
        FOR g IN SELECT x FROM jsonb_array_elements(s->'subjects') x LOOP
            v_subj := nullif(btrim(coalesce(g->>'subject', '')), '');
            v_grade := upper(btrim(coalesce(g->>'grade', '')));
            IF v_subj IS NULL OR length(v_subj) > 60 THEN RAISE EXCEPTION 'PRELIM_OLEVEL_INCOMPLETE: sitting %: a subject is named', v_sit USING ERRCODE = '23514'; END IF;
            IF v_grade IN ('AR', 'AWAITING', 'AWAITING RESULT', 'PENDING', 'NR', '*') THEN
                RAISE EXCEPTION 'PRELIM_AWAITING_RESULT: sitting %, %: an awaiting result is not accepted — Preliminary Science admission is strictly on results already released', v_sit, v_subj USING ERRCODE = '23514';
            END IF;
            IF v_grade NOT IN ('A1', 'B2', 'B3', 'C4', 'C5', 'C6', 'D7', 'E8', 'F9') THEN
                RAISE EXCEPTION 'PRELIM_OLEVEL_GRADE: sitting %, %: the grade is one of A1, B2, B3, C4, C5, C6, D7, E8, F9', v_sit, v_subj USING ERRCODE = '23514';
            END IF;
            IF upper(v_subj) = ANY (seen) THEN RAISE EXCEPTION 'PRELIM_OLEVEL_SUBJECTS: sitting %: % is given twice', v_sit, v_subj USING ERRCODE = '23514'; END IF;
            seen := array_append(seen, upper(v_subj));
            ord := ord + 1;
            INSERT INTO admissions.screening_olevel (application_id, ord, exam_body, exam_type, exam_number, exam_year, subject, grade, active, sitting)
            VALUES (p_app, ord, v_body, v_type, v_no, v_year, v_subj, v_grade, true, v_sit);
            n := n + 1;
        END LOOP;
    END LOOP;
    IF (SELECT count(DISTINCT sitting) FROM admissions.screening_olevel WHERE application_id = p_app AND active) <> jsonb_array_length(p_sittings) THEN
        RAISE EXCEPTION 'PRELIM_OLEVEL_SITTINGS: the same sitting is given twice' USING ERRCODE = '23514';
    END IF;
    -- a corrected result is verified afresh
    UPDATE admissions.prelim_review SET olevel_verification = 'PENDING', olevel_verified_by = NULL, olevel_verified_at = NULL, updated_at = now()
     WHERE application_id = p_app AND olevel_verification <> 'PENDING';
    PERFORM admissions.prelim_evaluate(p_app);
    RETURN n;
END $fn$;

/* the target programme: the applicant chooses among the programme's targets while the form is theirs; an officer changes it with
   a reason until the outcome is published. It is the intended progression, never an admission into the degree. */
CREATE OR REPLACE FUNCTION admissions.prelim_set_target(p_app uuid, p_programme text, p_note text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; v_office text := coalesce(nullif(current_setting('moaum.actor_office', true), ''), ''); v_name text;
BEGIN
    r := admissions.prelim_application(p_app);
    IF v_office = 'applicant' THEN
        r := admissions.prelim_require_editable(p_app);
    ELSE
        PERFORM admissions.prelim_require_office(ARRAY['prelim', 'academic', 'super'], 'changing a Preliminary Science target programme');
        SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
        IF r.published_at IS NOT NULL OR r.state IN ('WITHDRAWN', 'ADMITTED') THEN
            RAISE EXCEPTION 'PRELIM_TARGET_FIXED: the outcome is published; the target programme stands' USING ERRCODE = '23514';
        END IF;
        IF nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN RAISE EXCEPTION 'PRELIM_TARGET_REASON: a change of the target programme is recorded with its reason' USING ERRCODE = '23514'; END IF;
    END IF;
    SELECT p.name INTO v_name FROM admissions.prelim_target t JOIN ref.programme p ON p.code = t.programme_code
     WHERE t.route = r.route AND t.programme_code = p_programme AND t.state = 'MAPPED';
    IF v_name IS NULL THEN
        RAISE EXCEPTION 'PRELIM_TARGET_NOT_OFFERED: that programme is not a target programme of Preliminary Science' USING ERRCODE = '23514';
    END IF;
    IF r.target_programme IS NOT DISTINCT FROM p_programme THEN RETURN v_name; END IF;
    UPDATE admissions.prelim_review SET target_programme = p_programme, target_set_at = now(), updated_at = now() WHERE application_id = p_app;
    PERFORM admissions.prelim_log(p_app, CASE WHEN r.target_programme IS NULL THEN 'TARGET_SET' ELSE 'TARGET_CHANGED' END, r.state, r.state, p_note,
                                  jsonb_build_object('from', r.target_programme, 'to', p_programme));
    RETURN v_name;
END $fn$;

/* the applicant submits — or sends back what the Office asked for. A first submission is made while the window is open. */
CREATE OR REPLACE FUNCTION admissions.prelim_submit(p_app uuid, p_ip text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; a admissions.application; v_missing text; v_state text; v_elig text;
BEGIN
    PERFORM admissions.prelim_application(p_app);
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    SELECT * INTO a FROM admissions.application WHERE id = p_app FOR UPDATE;
    IF r.state NOT IN ('DRAFT', 'CORRECTION_REQUIRED') THEN RETURN 'already submitted'; END IF;
    IF r.state = 'DRAFT' THEN
        SELECT w.state INTO v_state FROM policy.window_state('PRELIMINARY_SCIENCE_APPLICATION', a.session, NULL) w;
        IF coalesce(v_state, 'CLOSED') <> 'OPEN' THEN
            RAISE EXCEPTION 'APPLICATION_CLOSED: the Preliminary Science application for % is %; an application is submitted while the window is open', a.session, lower(coalesce(v_state, 'closed')) USING ERRCODE = '23514';
        END IF;
    END IF;
    SELECT string_agg(x.message, '; ') INTO v_missing FROM (SELECT p.message FROM admissions.prelim_problems(p_app) p LIMIT 6) x;
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'PRELIM_INCOMPLETE: the application is not complete: %', v_missing USING ERRCODE = '23514';
    END IF;
    v_elig := admissions.prelim_evaluate(p_app);
    IF r.state = 'DRAFT' THEN
        UPDATE admissions.prelim_review SET state = 'SUBMITTED', submitted_at = now(), declaration_ip = p_ip, updated_at = now() WHERE application_id = p_app;
        PERFORM admissions.prelim_log(p_app, 'SUBMITTED', 'DRAFT', 'SUBMITTED', NULL, jsonb_build_object('eligibility', v_elig));
        PERFORM platform.tell_applicant(p_app, 'PRELIMINARY_SCIENCE', 'APPLICATION_SUBMITTED', '{}'::jsonb, 'PRELIMINARY_SCIENCE_APPLICATION_SUBMITTED:' || p_app);
        RETURN 'submitted';
    END IF;
    UPDATE admissions.prelim_review SET state = 'UNDER_REVIEW', updated_at = now() WHERE application_id = p_app;
    PERFORM admissions.prelim_log(p_app, 'CORRECTED', r.state, 'UNDER_REVIEW', 'The applicant sent the application back with the correction asked for', jsonb_build_object('eligibility', v_elig));
    RETURN 'returned to the Office';
END $fn$;

/* the applicant withdraws an application not yet decided */
CREATE OR REPLACE FUNCTION admissions.prelim_withdraw(p_app uuid, p_note text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review;
BEGIN
    PERFORM admissions.prelim_application(p_app);
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    IF r.state NOT IN ('DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'CORRECTION_REQUIRED', 'RECOMMENDED') OR r.published_at IS NOT NULL THEN
        RAISE EXCEPTION 'PRELIM_NOT_WITHDRAWN: a % application is not withdrawn', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.prelim_review SET state = 'WITHDRAWN', withdrawn_at = now(), updated_at = now() WHERE application_id = p_app;
    PERFORM admissions.prelim_log(p_app, 'WITHDRAWN', r.state, 'WITHDRAWN', coalesce(nullif(btrim(coalesce(p_note, '')), ''), 'Withdrawn by the applicant'));
    RETURN 'WITHDRAWN';
END $fn$;

-- ── 10 · the Office reviews, the Academic Office approves and publishes ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.prelim_review_document(p_document uuid, p_status text, p_note text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE d admissions.application_document; r admissions.prelim_review; v_label text;
BEGIN
    PERFORM admissions.prelim_require_office(ARRAY['prelim', 'academic', 'super'], 'verifying a Preliminary Science applicant''s documents');
    SELECT * INTO d FROM admissions.application_document WHERE id = p_document FOR UPDATE;
    IF d.id IS NULL THEN RAISE EXCEPTION 'no such document' USING ERRCODE = '23503'; END IF;
    r := admissions.prelim_application(d.application_id);
    IF r.state NOT IN ('SUBMITTED', 'UNDER_REVIEW', 'CORRECTION_REQUIRED', 'RECOMMENDED') THEN
        RAISE EXCEPTION 'PRELIM_REVIEW_STATE: the documents of a % application are not reviewed', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF p_status NOT IN ('ACCEPTED', 'REJECTED') THEN RAISE EXCEPTION 'a document is ACCEPTED or REJECTED' USING ERRCODE = '23514'; END IF;
    IF p_status = 'REJECTED' AND nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN
        RAISE EXCEPTION 'PRELIM_DOCUMENT_REASON: a document is rejected with the reason the applicant reads' USING ERRCODE = '23514';
    END IF;
    IF d.superseded_at IS NOT NULL THEN RAISE EXCEPTION 'PRELIM_DOCUMENT_REPLACED: the applicant has replaced this document' USING ERRCODE = '23514'; END IF;
    UPDATE admissions.application_document SET status = p_status, reviewed_at = now(), reviewed_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
           review_note = nullif(btrim(coalesce(p_note, '')), '')
     WHERE id = p_document;
    SELECT q.label INTO v_label FROM admissions.prelim_document q WHERE q.route = r.route AND q.kind = d.kind;
    PERFORM admissions.prelim_log(d.application_id, 'DOCUMENT_' || p_status, r.state, r.state, coalesce(v_label, d.kind) || coalesce(': ' || nullif(btrim(coalesce(p_note, '')), ''), ''));
    RETURN p_status;
END $fn$;

/* the O'Level verified against the documents: VERIFIED, or INVALID with what was found; a recommendation on an invalid result falls */
CREATE OR REPLACE FUNCTION admissions.prelim_verify_olevel(p_app uuid, p_outcome text, p_note text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_elig text; v_to text;
BEGIN
    PERFORM admissions.prelim_require_office(ARRAY['prelim', 'academic', 'super'], 'verifying a Preliminary Science applicant''s O''Level');
    PERFORM admissions.prelim_application(p_app);
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    IF r.state NOT IN ('SUBMITTED', 'UNDER_REVIEW', 'RECOMMENDED') THEN
        RAISE EXCEPTION 'PRELIM_REVIEW_STATE: the O''Level of a % application is not verified', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF upper(coalesce(p_outcome, '')) NOT IN ('VERIFIED', 'INVALID') THEN RAISE EXCEPTION 'an O''Level is VERIFIED or INVALID' USING ERRCODE = '23514'; END IF;
    IF upper(p_outcome) = 'INVALID' AND v_note IS NULL THEN
        RAISE EXCEPTION 'PRELIM_OLEVEL_REASON: an invalid result is recorded with what was found' USING ERRCODE = '23514';
    END IF;
    v_to := CASE WHEN r.state = 'RECOMMENDED' AND upper(p_outcome) = 'INVALID' THEN 'UNDER_REVIEW' ELSE r.state END;
    UPDATE admissions.prelim_review
       SET olevel_verification = upper(p_outcome), olevel_verified_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, olevel_verified_at = now(),
           olevel_note = v_note, state = v_to,
           recommended_at = CASE WHEN v_to <> r.state THEN NULL ELSE recommended_at END,
           recommended_by = CASE WHEN v_to <> r.state THEN NULL ELSE recommended_by END,
           recommendation_note = CASE WHEN v_to <> r.state THEN NULL ELSE recommendation_note END,
           updated_at = now()
     WHERE application_id = p_app;
    v_elig := admissions.prelim_evaluate(p_app);
    PERFORM admissions.prelim_log(p_app, 'OLEVEL_' || upper(p_outcome), r.state, v_to, v_note, jsonb_build_object('eligibility', v_elig));
    RETURN v_elig;
END $fn$;

/* one step of the review. START (submitted → under review), REQUEST_CORRECTION (back to the applicant with what is needed),
   RESUME, RECOMMEND (documents accepted, O'Level verified, eligible, a target chosen), APPROVE (the Academic Office, never the
   officer who recommended), NOT_ADMIT and REJECT (with the reason), REOPEN (an unpublished decision back under review). */
CREATE OR REPLACE FUNCTION admissions.prelim_act(p_app uuid, p_action text, p_note text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; a admissions.application; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_note text := nullif(btrim(coalesce(p_note, '')), '');
        v_to text; v_pending int; v_elig text;
BEGIN
    PERFORM admissions.prelim_application(p_app);
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a Preliminary Science application is reviewed by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF r.published_at IS NOT NULL THEN
        RAISE EXCEPTION 'PRELIM_PUBLISHED: the outcome was published on % and stands', to_char(r.published_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY') USING ERRCODE = '23514';
    END IF;
    CASE upper(p_action)
    WHEN 'START' THEN
        PERFORM admissions.prelim_require_office(ARRAY['prelim', 'academic', 'super'], 'reviewing Preliminary Science applications');
        IF r.state <> 'SUBMITTED' THEN RAISE EXCEPTION 'PRELIM_REVIEW_STATE: only a submitted application is taken up; this one is %', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
        v_to := 'UNDER_REVIEW';
        UPDATE admissions.prelim_review SET state = v_to, review_started_at = now(), review_started_by = v_actor, updated_at = now() WHERE application_id = p_app;
    WHEN 'REQUEST_CORRECTION' THEN
        PERFORM admissions.prelim_require_office(ARRAY['prelim', 'academic', 'super'], 'asking a Preliminary Science applicant for a correction');
        IF r.state NOT IN ('SUBMITTED', 'UNDER_REVIEW', 'RECOMMENDED') THEN
            RAISE EXCEPTION 'PRELIM_REVIEW_STATE: a % application is not sent back to the applicant', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        IF v_note IS NULL THEN RAISE EXCEPTION 'PRELIM_REQUEST_NOTE: say what the applicant is to correct or provide' USING ERRCODE = '23514'; END IF;
        v_to := 'CORRECTION_REQUIRED';
        UPDATE admissions.prelim_review SET state = v_to, request_note = v_note, requested_at = now(), requested_by = v_actor,
               recommended_at = NULL, recommended_by = NULL, recommendation_note = NULL, updated_at = now()
         WHERE application_id = p_app;
        PERFORM platform.tell_applicant(p_app, 'PRELIMINARY_SCIENCE', 'CORRECTION_REQUIRED', jsonb_build_object('NOTE', v_note),
                                        'PRELIMINARY_SCIENCE_CORRECTION_REQUIRED:' || p_app || ':' || to_char(now(), 'YYYYMMDDHH24MISS'));
    WHEN 'RESUME' THEN
        PERFORM admissions.prelim_require_office(ARRAY['prelim', 'academic', 'super'], 'reviewing Preliminary Science applications');
        IF r.state <> 'CORRECTION_REQUIRED' THEN
            RAISE EXCEPTION 'PRELIM_REVIEW_STATE: only an application waiting on the applicant is taken back; this one is %', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        v_to := 'UNDER_REVIEW';
        UPDATE admissions.prelim_review SET state = v_to, updated_at = now() WHERE application_id = p_app;
    WHEN 'RECOMMEND' THEN
        PERFORM admissions.prelim_require_office(ARRAY['prelim', 'super'], 'recommending a Preliminary Science admission');
        IF r.state <> 'UNDER_REVIEW' THEN
            RAISE EXCEPTION 'PRELIM_REVIEW_STATE: an application is recommended from review; this one is %', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        SELECT count(*) INTO v_pending FROM admissions.application_document d WHERE d.application_id = p_app AND d.superseded_at IS NULL AND d.status <> 'ACCEPTED';
        IF v_pending > 0 THEN
            RAISE EXCEPTION 'PRELIM_DOCUMENTS_UNVERIFIED: % document(s) not yet accepted; verify every document before recommending', v_pending USING ERRCODE = '23514';
        END IF;
        IF r.olevel_verification <> 'VERIFIED' THEN
            RAISE EXCEPTION 'PRELIM_OLEVEL_UNVERIFIED: verify the O''Level against the result documents before recommending' USING ERRCODE = '23514';
        END IF;
        v_elig := admissions.prelim_evaluate(p_app);
        IF v_elig NOT IN ('ELIGIBLE', 'ELIGIBLE_WITH_REMEDIATION') THEN
            RAISE EXCEPTION 'PRELIM_NOT_ELIGIBLE: the applicant does not meet the entry requirement (%); an ineligible application is not recommended', lower(replace(v_elig, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        IF r.target_programme IS NULL THEN RAISE EXCEPTION 'PRELIM_NO_TARGET: no target programme is chosen' USING ERRCODE = '23514'; END IF;
        v_to := 'RECOMMENDED';
        UPDATE admissions.prelim_review SET state = v_to, recommended_at = now(), recommended_by = v_actor, recommendation_note = v_note, updated_at = now() WHERE application_id = p_app;
    WHEN 'APPROVE' THEN
        PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'approving a Preliminary Science admission');
        IF r.state <> 'RECOMMENDED' THEN
            RAISE EXCEPTION 'PRELIM_REVIEW_STATE: an admission is approved once recommended; this one is %', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        IF r.recommended_by = v_actor THEN
            RAISE EXCEPTION 'PRELIM_APPROVE_OWN: the officer who recommended an admission does not also approve it' USING ERRCODE = '23514';
        END IF;
        v_to := 'APPROVED';
        UPDATE admissions.prelim_review SET state = v_to, decided_at = now(), decided_by = v_actor, decided_office = v_office, decision_note = v_note, updated_at = now() WHERE application_id = p_app;
    WHEN 'NOT_ADMIT', 'REJECT' THEN
        PERFORM admissions.prelim_require_office(ARRAY['prelim', 'academic', 'super'], 'deciding a Preliminary Science application');
        IF r.state NOT IN ('SUBMITTED', 'UNDER_REVIEW', 'CORRECTION_REQUIRED', 'RECOMMENDED', 'APPROVED') THEN
            RAISE EXCEPTION 'PRELIM_REVIEW_STATE: a % application is not decided', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        IF v_note IS NULL THEN RAISE EXCEPTION 'PRELIM_DECISION_NOTE: the reason is recorded and is what the applicant reads' USING ERRCODE = '23514'; END IF;
        v_to := CASE upper(p_action) WHEN 'NOT_ADMIT' THEN 'NOT_ADMITTED' ELSE 'REJECTED' END;
        UPDATE admissions.prelim_review SET state = v_to, decided_at = now(), decided_by = v_actor, decided_office = v_office, decision_note = v_note, updated_at = now() WHERE application_id = p_app;
    WHEN 'REOPEN' THEN
        PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'reopening a Preliminary Science application');
        IF r.state NOT IN ('APPROVED', 'NOT_ADMITTED', 'REJECTED') THEN
            RAISE EXCEPTION 'PRELIM_REVIEW_STATE: only a decided, unpublished application is reopened; this one is %', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        IF v_note IS NULL THEN RAISE EXCEPTION 'PRELIM_REOPEN_NOTE: say why the decision is reopened' USING ERRCODE = '23514'; END IF;
        v_to := 'UNDER_REVIEW';
        UPDATE admissions.prelim_review SET state = v_to, decided_at = NULL, decided_by = NULL, decided_office = NULL, decision_note = NULL,
               recommended_at = NULL, recommended_by = NULL, recommendation_note = NULL, updated_at = now()
         WHERE application_id = p_app;
    ELSE
        RAISE EXCEPTION 'unknown review step %', p_action USING ERRCODE = '23514';
    END CASE;
    PERFORM admissions.prelim_log(p_app, upper(p_action), r.state, v_to, v_note);
    RETURN v_to;
END $fn$;

/* the Academic Office publishes the outcome: an approved admission becomes the ordinary offer (OFFERED, released, the candidate
   ADMITTED — into Preliminary Science, never the target programme); a declined one the ordinary NOT_OFFERED with its reason */
CREATE OR REPLACE FUNCTION admissions.prelim_publish(p_route text, p_session text, p_apps uuid[])
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE x record; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; n_adm int := 0; n_not int := 0; n_rej int := 0; v_rem text;
BEGIN
    PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'publishing the Preliminary Science admission list');
    FOR x IN SELECT r.*, a.application_no, a.candidate_id, p.name AS target_name
               FROM admissions.prelim_review r JOIN admissions.application a ON a.id = r.application_id
               LEFT JOIN ref.programme p ON p.code = r.target_programme
              WHERE r.route = upper(btrim(p_route)) AND a.session = p_session AND r.published_at IS NULL AND r.state IN ('APPROVED', 'NOT_ADMITTED', 'REJECTED')
                AND (p_apps IS NULL OR r.application_id = ANY (p_apps))
              ORDER BY a.application_no FOR UPDATE OF r LOOP
        IF x.state = 'APPROVED' THEN
            UPDATE admissions.application SET decision = 'OFFERED', decision_basis = 'OTHER', decision_note = x.decision_note, decided_at = x.decided_at,
                   decision_released_at = now() WHERE id = x.application_id;
            UPDATE admissions.candidate SET offer_state = 'ADMITTED' WHERE id = x.candidate_id AND offer_state = 'PROPOSED';
            UPDATE admissions.prelim_review SET state = 'ADMITTED', published_at = now(), published_by = v_actor, updated_at = now() WHERE application_id = x.application_id;
            PERFORM admissions.prelim_log(x.application_id, 'PUBLISHED', 'APPROVED', 'ADMITTED', NULL);
            v_rem := CASE WHEN x.remediation_status = 'REQUIRED'
                          THEN array_to_string(x.remediation_subjects
                                   || CASE WHEN x.remediation_credits_short > 0 THEN ARRAY[x.remediation_credits_short || ' more O''Level credit pass' || CASE WHEN x.remediation_credits_short = 1 THEN '' ELSE 'es' END] ELSE '{}' END, ', ') END;
            PERFORM platform.tell_applicant(x.application_id, 'PRELIMINARY_SCIENCE', 'ADMISSION_OFFERED',
                jsonb_strip_nulls(jsonb_build_object('TARGET_PROGRAMME', x.target_name,
                    'REMEDIATION_NOTE', CASE WHEN v_rem IS NOT NULL THEN 'Before completing the programme you are to make up: ' || v_rem || '.' ELSE '' END)),
                'PRELIMINARY_SCIENCE_ADMISSION_OFFERED:' || x.application_id);
            IF v_rem IS NOT NULL THEN
                PERFORM platform.tell_applicant(x.application_id, 'PRELIMINARY_SCIENCE', 'REMEDIATION_REQUIRED', jsonb_build_object('REMEDIATION', v_rem),
                                                'PRELIMINARY_SCIENCE_REMEDIATION_REQUIRED:' || x.application_id);
            END IF;
            n_adm := n_adm + 1;
        ELSE
            UPDATE admissions.application SET decision = 'NOT_OFFERED', decision_basis = NULL, decision_note = x.decision_note, decided_at = x.decided_at,
                   decision_released_at = now() WHERE id = x.application_id;
            UPDATE admissions.prelim_review SET published_at = now(), published_by = v_actor, updated_at = now() WHERE application_id = x.application_id;
            PERFORM admissions.prelim_log(x.application_id, 'PUBLISHED', x.state, x.state, NULL);
            PERFORM platform.tell_applicant(x.application_id, 'PRELIMINARY_SCIENCE', 'ADMISSION_NOT_OFFERED', jsonb_build_object('NOTE', coalesce(x.decision_note, '')),
                                            'PRELIMINARY_SCIENCE_ADMISSION_NOT_OFFERED:' || x.application_id);
            IF x.state = 'NOT_ADMITTED' THEN n_not := n_not + 1; ELSE n_rej := n_rej + 1; END IF;
        END IF;
    END LOOP;
    RETURN jsonb_build_object('admitted', n_adm, 'not_admitted', n_not, 'rejected', n_rej);
END $fn$;

/* the remediation an admitted candidate is to complete, as the Office records its progress; never decided by the portal itself */
CREATE OR REPLACE FUNCTION admissions.prelim_set_remediation(p_app uuid, p_status text, p_note text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
    PERFORM admissions.prelim_require_office(ARRAY['prelim', 'academic', 'super'], 'recording a Preliminary Science remediation');
    PERFORM admissions.prelim_application(p_app);
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    IF upper(coalesce(p_status, '')) NOT IN ('NOT_REQUIRED', 'REQUIRED', 'IN_PROGRESS', 'COMPLETED', 'NOT_COMPLETED', 'REQUIRES_REVIEW') THEN
        RAISE EXCEPTION 'PRELIM_REMEDIATION_STATUS: the remediation is not required, required, in progress, completed, not completed or under review' USING ERRCODE = '23514';
    END IF;
    IF v_note IS NULL THEN RAISE EXCEPTION 'PRELIM_REMEDIATION_NOTE: the remediation is recorded with its reason or evidence' USING ERRCODE = '23514'; END IF;
    IF r.eligibility_status NOT IN ('ELIGIBLE', 'ELIGIBLE_WITH_REMEDIATION') THEN
        RAISE EXCEPTION 'PRELIM_REMEDIATION_NOT_ELIGIBLE: a remediation is recorded for an eligible applicant' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.prelim_review SET remediation_status = upper(p_status), remediation_note = v_note, remediation_set_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
           remediation_set_at = now(), updated_at = now()
     WHERE application_id = p_app;
    PERFORM admissions.prelim_log(p_app, 'REMEDIATION_' || upper(p_status), r.state, r.state, v_note,
                                  jsonb_build_object('from', r.remediation_status, 'to', upper(p_status), 'subjects', to_jsonb(r.remediation_subjects)));
    RETURN upper(p_status);
END $fn$;

-- ── 11 · the configuration, the Academic Office's ───────────────────────────────────────────────────────────────
/* the programme's description and rule, changed with a reason; every open application is read again under the new rule */
CREATE OR REPLACE FUNCTION admissions.prelim_set_rules(p_route text, p_settings jsonb, p_reason text)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE p admissions.prelim_programme; k text; x record; n int := 0;
BEGIN
    PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'changing the Preliminary Science programme and its requirements');
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'PRELIM_RULES_REASON: a change to the programme is recorded with its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = upper(btrim(p_route)) FOR UPDATE;
    IF p.route IS NULL THEN RAISE EXCEPTION 'PRELIM_NO_PROGRAMME: no preliminary programme %', p_route USING ERRCODE = '23514'; END IF;
    IF p_settings IS NULL OR jsonb_typeof(p_settings) <> 'object' THEN RAISE EXCEPTION 'the settings are a set of fields' USING ERRCODE = '23514'; END IF;
    FOR k IN SELECT jsonb_object_keys(p_settings) LOOP
        IF k NOT IN ('name', 'description', 'completion_note', 'procedure', 'office_note', 'min_credits', 'max_sittings', 'min_core_credits', 'core_subjects',
                     'credit_grade', 'completion_credits', 'completion_subjects', 'remediation_terms') THEN
            RAISE EXCEPTION 'PRELIM_RULES_FIELD: % is not a setting of the programme', k USING ERRCODE = '23514';
        END IF;
    END LOOP;
    PERFORM set_config('moaum.reason', p_reason, true);
    UPDATE admissions.prelim_programme SET
        name = coalesce(nullif(btrim(p_settings->>'name'), ''), name),
        description = coalesce(nullif(btrim(p_settings->>'description'), ''), description),
        completion_note = coalesce(p_settings->>'completion_note', completion_note),
        procedure = CASE WHEN p_settings ? 'procedure' THEN ARRAY(SELECT btrim(v) FROM jsonb_array_elements_text(p_settings->'procedure') v WHERE btrim(v) <> '') ELSE procedure END,
        office_note = CASE WHEN p_settings ? 'office_note' THEN nullif(btrim(p_settings->>'office_note'), '') ELSE office_note END,
        min_credits = coalesce((p_settings->>'min_credits')::int, min_credits),
        max_sittings = coalesce((p_settings->>'max_sittings')::int, max_sittings),
        min_core_credits = coalesce((p_settings->>'min_core_credits')::int, min_core_credits),
        core_subjects = CASE WHEN p_settings ? 'core_subjects' THEN ARRAY(SELECT btrim(v) FROM jsonb_array_elements_text(p_settings->'core_subjects') v WHERE btrim(v) <> '') ELSE core_subjects END,
        credit_grade = coalesce(upper(nullif(btrim(p_settings->>'credit_grade'), '')), credit_grade),
        completion_credits = coalesce((p_settings->>'completion_credits')::int, completion_credits),
        completion_subjects = CASE WHEN p_settings ? 'completion_subjects' THEN ARRAY(SELECT btrim(v) FROM jsonb_array_elements_text(p_settings->'completion_subjects') v WHERE btrim(v) <> '') ELSE completion_subjects END,
        remediation_terms = CASE WHEN p_settings ? 'remediation_terms' THEN nullif(btrim(p_settings->>'remediation_terms'), '') ELSE remediation_terms END,
        rules_version = rules_version + 1,
        updated_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, updated_office = nullif(current_setting('moaum.actor_office', true), ''), updated_at = now()
     WHERE route = p.route;
    -- the applications not yet published are read again under the new rule
    FOR x IN SELECT r.application_id FROM admissions.prelim_review r WHERE r.route = p.route AND r.published_at IS NULL AND r.state <> 'WITHDRAWN' LOOP
        PERFORM admissions.prelim_evaluate(x.application_id);
        n := n + 1;
    END LOOP;
    RETURN n;
END $fn$;

/* a target programme added: an existing, current undergraduate programme, once; a withdrawn one is reinstated */
CREATE OR REPLACE FUNCTION admissions.prelim_add_target(p_route text, p_programme text, p_group text, p_ord integer, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE t admissions.prelim_target; v_id uuid; v_name text; v_route text := upper(btrim(p_route));
BEGIN
    PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'adding a Preliminary Science target programme');
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'PRELIM_TARGET_REASON: a target programme is added with its reason' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM admissions.prelim_programme WHERE route = v_route) THEN RAISE EXCEPTION 'PRELIM_NO_PROGRAMME: no preliminary programme %', p_route USING ERRCODE = '23514'; END IF;
    IF policy.route_session(v_route) IS NULL OR NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = policy.route_session(v_route)) THEN
        RAISE EXCEPTION 'PRELIM_SESSION: the programme''s session is not on the calendar' USING ERRCODE = '23514';
    END IF;
    SELECT name INTO v_name FROM ref.programme WHERE code = p_programme;
    IF v_name IS NULL THEN RAISE EXCEPTION 'PRELIM_TARGET_UNKNOWN: no programme % on the register', p_programme USING ERRCODE = '23514'; END IF;
    PERFORM set_config('moaum.reason', p_reason, true);
    SELECT * INTO t FROM admissions.prelim_target WHERE route = v_route AND programme_code = p_programme FOR UPDATE;
    IF t.id IS NOT NULL AND t.state = 'MAPPED' THEN
        RAISE EXCEPTION 'PRELIM_TARGET_DUPLICATE: % is already a target programme', v_name USING ERRCODE = '23514';
    ELSIF t.id IS NOT NULL THEN
        UPDATE admissions.prelim_target SET state = 'MAPPED', group_name = coalesce(nullif(btrim(p_group), ''), group_name), ord = coalesce(p_ord, ord), note = p_reason
         WHERE id = t.id;
        RETURN t.id;
    END IF;
    INSERT INTO admissions.prelim_target (route, group_name, ord, requested_name, programme_code, state, note, added_by, added_office)
    VALUES (v_route, coalesce(nullif(btrim(p_group), ''), 'Other'), coalesce(p_ord, 500), v_name, p_programme, 'MAPPED', p_reason,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    RETURNING id INTO v_id;
    RETURN v_id;
END $fn$;

/* a target withdrawn (kept, WITHDRAWN, for the applications that chose it), or a programme named in the notice but missing from
   the register resolved to the existing programme it is */
CREATE OR REPLACE FUNCTION admissions.prelim_change_target(p_target uuid, p_action text, p_programme text, p_reason text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE t admissions.prelim_target;
BEGIN
    PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'changing a Preliminary Science target programme');
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'PRELIM_TARGET_REASON: a change of a target programme is recorded with its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM admissions.prelim_target WHERE id = p_target FOR UPDATE;
    IF t.id IS NULL THEN RAISE EXCEPTION 'no such target programme' USING ERRCODE = '23503'; END IF;
    PERFORM set_config('moaum.reason', p_reason, true);
    CASE upper(p_action)
    WHEN 'WITHDRAW' THEN
        IF t.state <> 'MAPPED' THEN RAISE EXCEPTION 'PRELIM_TARGET_STATE: only an offered target programme is withdrawn' USING ERRCODE = '23514'; END IF;
        UPDATE admissions.prelim_target SET state = 'WITHDRAWN', note = p_reason WHERE id = t.id;
        RETURN 'WITHDRAWN';
    WHEN 'RESOLVE' THEN
        IF t.state <> 'MISSING' THEN RAISE EXCEPTION 'PRELIM_TARGET_STATE: only a missing target programme is resolved' USING ERRCODE = '23514'; END IF;
        IF EXISTS (SELECT 1 FROM admissions.prelim_target x WHERE x.route = t.route AND x.programme_code = p_programme) THEN
            RAISE EXCEPTION 'PRELIM_TARGET_DUPLICATE: that programme is already a target programme' USING ERRCODE = '23514';
        END IF;
        UPDATE admissions.prelim_target SET state = 'MAPPED', programme_code = p_programme, note = p_reason WHERE id = t.id;
        RETURN 'MAPPED';
    ELSE
        RAISE EXCEPTION 'unknown change %', p_action USING ERRCODE = '23514';
    END CASE;
END $fn$;

/* a document of the application: its label, and whether it is required */
CREATE OR REPLACE FUNCTION admissions.prelim_set_document(p_route text, p_kind text, p_label text, p_hint text, p_required boolean, p_second_only boolean, p_ord integer, p_reason text)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'changing the Preliminary Science documents');
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'PRELIM_DOCUMENT_REASON: a change to the documents is recorded with its reason' USING ERRCODE = '23514'; END IF;
    PERFORM set_config('moaum.reason', p_reason, true);
    INSERT INTO admissions.prelim_document (route, kind, label, hint, required, second_sitting_only, ord)
    VALUES (upper(btrim(p_route)), upper(btrim(p_kind)), btrim(p_label), nullif(btrim(coalesce(p_hint, '')), ''), coalesce(p_required, true), coalesce(p_second_only, false), coalesce(p_ord, 100))
    ON CONFLICT (route, kind) DO UPDATE SET label = EXCLUDED.label, hint = EXCLUDED.hint, required = EXCLUDED.required,
        second_sitting_only = EXCLUDED.second_sitting_only, ord = EXCLUDED.ord;
END $fn$;

-- ── 12 · what the public, the applicant and the dashboard read ──────────────────────────────────────────────────
/* the public page: the programme, its session and window, the fee as the Bursary stated it, the requirements, the targets, the documents */
CREATE OR REPLACE FUNCTION admissions.prelim_public(p_route text)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
    WITH p AS (SELECT * FROM admissions.prelim_programme WHERE route = upper(btrim(p_route))),
         s AS (SELECT policy.route_session(p.route) AS session FROM p),
         w AS (SELECT ws.* FROM s CROSS JOIN LATERAL policy.window_state('PRELIMINARY_SCIENCE_APPLICATION', s.session, NULL) ws),
         f AS (SELECT rf.* FROM p CROSS JOIN s CROSS JOIN LATERAL admissions.route_fee_rule(s.session, p.route) rf)
    SELECT jsonb_build_object(
        'route', p.route, 'name', p.name, 'programmeType', pt.label, 'description', p.description, 'completionNote', p.completion_note,
        'procedure', to_jsonb(p.procedure), 'officeNote', p.office_note, 'session', s.session,
        'studyMode', r.study_mode,
        'window', jsonb_build_object('state', w.state, 'opensAt', w.opens_at, 'closesAt', w.closes_at,
                                     'message', (SELECT m.message FROM policy.portal_window_message m WHERE m.window_type = 'PRELIMINARY_SCIENCE_APPLICATION')),
        'fee', jsonb_build_object('stated', coalesce((SELECT f.stated FROM f), false), 'applicationFee', (SELECT f.application_fee + f.portal_charge FROM f),
                                  'session', coalesce((SELECT f.carried_from FROM f), s.session)),
        'rules', jsonb_build_object('minCredits', p.min_credits, 'maxSittings', p.max_sittings, 'minCoreCredits', p.min_core_credits,
                                    'coreSubjects', to_jsonb(p.core_subjects), 'creditGrade', p.credit_grade, 'completionCredits', p.completion_credits,
                                    'completionSubjects', to_jsonb(p.completion_subjects), 'awaitingAccepted', false, 'remediationTerms', p.remediation_terms),
        'targets', coalesce((SELECT jsonb_agg(jsonb_build_object('group', t.group_name, 'name', t.requested_name, 'programmeCode', t.programme_code,
                                                                 'registerName', pr.name) ORDER BY t.ord, t.requested_name)
                               FROM admissions.prelim_target t JOIN ref.programme pr ON pr.code = t.programme_code
                              WHERE t.route = p.route AND t.state = 'MAPPED'), '[]'::jsonb),
        'documents', coalesce((SELECT jsonb_agg(jsonb_build_object('kind', d.kind, 'label', d.label, 'hint', d.hint, 'required', d.required,
                                                                   'secondSittingOnly', d.second_sitting_only) ORDER BY d.ord)
                                 FROM admissions.prelim_document d WHERE d.route = p.route), '[]'::jsonb))
      FROM p CROSS JOIN s CROSS JOIN w JOIN policy.study_route r ON r.code = p.route LEFT JOIN finance.programme_type pt ON pt.code = p.programme_type
$fn$;

/* the dashboard's figures for a session, each the filter of the list behind it; a Head of Department or a Dean reads those whose
   target programme is in their department or faculty */
CREATE OR REPLACE FUNCTION admissions.prelim_stats(p_route text, p_session text, p_dept text DEFAULT NULL, p_faculty text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
    WITH x AS (SELECT r.*, a.fee_confirmed_at FROM admissions.prelim_review r JOIN admissions.application a ON a.id = r.application_id
                 LEFT JOIN ref.programme tp ON tp.code = r.target_programme
                WHERE r.route = upper(btrim(p_route)) AND a.session = p_session
                  AND (p_dept IS NULL OR tp.dept_code = p_dept) AND (p_faculty IS NULL OR tp.faculty_code = p_faculty))
    SELECT jsonb_build_object(
        'total', (SELECT count(*) FROM x),
        'paid', (SELECT count(*) FROM x WHERE fee_confirmed_at IS NOT NULL),
        'submitted', (SELECT count(*) FROM x WHERE submitted_at IS NOT NULL AND state <> 'WITHDRAWN'),
        'incomplete', (SELECT count(*) FROM x WHERE state = 'DRAFT'),
        'pendingReview', (SELECT count(*) FROM x WHERE state = 'SUBMITTED'),
        'underReview', (SELECT count(*) FROM x WHERE state IN ('UNDER_REVIEW', 'CORRECTION_REQUIRED', 'RECOMMENDED', 'APPROVED')
                                              OR (state IN ('NOT_ADMITTED', 'REJECTED') AND published_at IS NULL)),
        'correction', (SELECT count(*) FROM x WHERE state = 'CORRECTION_REQUIRED'),
        'eligible', (SELECT count(*) FROM x WHERE submitted_at IS NOT NULL AND state <> 'WITHDRAWN' AND eligibility_status IN ('ELIGIBLE', 'ELIGIBLE_WITH_REMEDIATION')),
        'notEligible', (SELECT count(*) FROM x WHERE submitted_at IS NOT NULL AND state <> 'WITHDRAWN' AND eligibility_status IN ('NOT_ELIGIBLE', 'RESULT_REQUIRED', 'INVALID_RESULT')),
        'remediationRequired', (SELECT count(*) FROM x WHERE submitted_at IS NOT NULL AND state <> 'WITHDRAWN' AND remediation_status IN ('REQUIRED', 'IN_PROGRESS', 'NOT_COMPLETED', 'REQUIRES_REVIEW')),
        'admitted', (SELECT count(*) FROM x WHERE state = 'ADMITTED'),
        'notAdmitted', (SELECT count(*) FROM x WHERE state IN ('NOT_ADMITTED', 'REJECTED') AND published_at IS NOT NULL),
        'withdrawn', (SELECT count(*) FROM x WHERE state = 'WITHDRAWN'),
        'byTarget', coalesce((SELECT jsonb_agg(jsonb_build_object('programmeCode', t.code, 'name', t.name, 'n', t.n) ORDER BY t.n DESC, t.name)
                                FROM (SELECT p.code, p.name, count(*) AS n FROM x JOIN ref.programme p ON p.code = x.target_programme
                                       WHERE x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN' GROUP BY p.code, p.name) t), '[]'::jsonb),
        'bySittings', coalesce((SELECT jsonb_agg(jsonb_build_object('sittings', s.sittings, 'n', s.n) ORDER BY s.sittings)
                                  FROM (SELECT coalesce(sittings, 0) AS sittings, count(*) AS n FROM x WHERE submitted_at IS NOT NULL AND state <> 'WITHDRAWN' GROUP BY 1) s), '[]'::jsonb))
$fn$;

/* the applicant's status, in the programme's own terms; an unpublished decision is never shown */
CREATE OR REPLACE FUNCTION admissions.prelim_status(p_app uuid)
RETURNS TABLE(status text, label text, next_action text, next_href text, detail text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE r admissions.prelim_review; a admissions.application; v_target text;
BEGIN
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app;
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT p.name INTO v_target FROM ref.programme p WHERE p.code = r.target_programme;
    IF r.state = 'WITHDRAWN' THEN RETURN QUERY SELECT 'WITHDRAWN', 'Application withdrawn', NULL::text, '/applicant/preliminary', 'This application was withdrawn.'; RETURN; END IF;
    IF r.state = 'DRAFT' THEN
        RETURN QUERY SELECT 'APPLICATION_INCOMPLETE', 'Application not complete',
            CASE WHEN admissions.prelim_fee_settled(p_app) THEN 'Complete and submit your application' ELSE 'Pay the application fee' END, '/applicant/preliminary',
            'The Preliminary Science Office reviews your application once it is complete and submitted.'; RETURN;
    END IF;
    IF r.state = 'CORRECTION_REQUIRED' THEN
        RETURN QUERY SELECT 'CORRECTION_REQUIRED', 'Correction required', 'Provide what the Office asked for', '/applicant/preliminary', r.request_note; RETURN;
    END IF;
    IF r.published_at IS NULL THEN
        RETURN QUERY SELECT 'PENDING', 'Admission pending', NULL::text, '/applicant/preliminary',
            'Your application is with the Preliminary Science Office. You are told by email and SMS when the outcome is published.'; RETURN;
    END IF;
    IF r.state = 'ADMITTED' THEN
        RETURN QUERY SELECT 'ADMITTED', 'Admitted into the Preliminary Science Programme', 'Print your admission letter', '/applicant/preliminary',
            'You are admitted into the Preliminary Science Programme for ' || a.session || '.' || coalesce(' Your intended progression is ' || v_target || ';', '')
            || ' selection of a target programme is not admission into the undergraduate programme; subsequent admission remains subject to University requirements and admission processes.'
            || CASE WHEN r.remediation_status = 'REQUIRED' THEN ' Before completing the programme you are to make up: '
                    || array_to_string(r.remediation_subjects || CASE WHEN r.remediation_credits_short > 0 THEN ARRAY[r.remediation_credits_short || ' more O''Level credit pass(es)'] ELSE '{}' END, ', ') || '.' ELSE '' END;
        RETURN;
    END IF;
    RETURN QUERY SELECT 'NOT_ADMITTED', 'Not admitted', NULL::text, '/applicant/preliminary',
        coalesce(a.decision_note, 'Your application for the Preliminary Science Programme for ' || a.session || ' was not successful.');
END $fn$;

-- ── 13 · admission status, read in the route's own terms ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.status_checking(p_app uuid)
 RETURNS TABLE(application_id uuid, session text, application_valid boolean, window_state text, window_open boolean, opens_at timestamp with time zone, closes_at timestamp with time zone, fee numeric, fee_required boolean, paid boolean, paid_at timestamp with time zone, paid_reference text, open_reference text, open_reference_expires timestamp with time zone, past boolean, may_pay boolean, may_check boolean, decision_visible boolean, reason text, checks bigint, last_checked_at timestamp with time zone, last_result text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH a AS (SELECT * FROM admissions.application WHERE id = p_app),
    -- V404: a CCE applicant has no checking window of the Director of ICT's: checking opens to them when the Centre's outcome of
    -- their application is published (admissions.cce_publish releases it and tells them), and costs the CCE admission checking
    -- fee the Bursary stated for the route (NULL while it is not stated: owed, and not yet payable)
    cce AS (SELECT EXISTS (SELECT 1 FROM a JOIN admissions.candidate c ON c.id = a.candidate_id WHERE c.entry_mode = 'CCE') AS yes),
    -- V446: a Preliminary Science applicant likewise reads the published outcome, with no window of ICT's and no fee the University has not stated
    pre AS (SELECT EXISTS (SELECT 1 FROM a JOIN admissions.candidate c ON c.id = a.candidate_id WHERE c.entry_mode = 'PRELIMINARY') AS yes,
                   (SELECT r.route FROM admissions.prelim_review r WHERE r.application_id = p_app) AS route,
                   (SELECT r.submitted_at FROM admissions.prelim_review r WHERE r.application_id = p_app) AS submitted_at),
    w AS (SELECT CASE WHEN cce.yes OR pre.yes THEN CASE WHEN a.decision_released_at IS NOT NULL THEN 'OPEN' ELSE 'CLOSED' END ELSE ws.state END AS state,
                 CASE WHEN cce.yes OR pre.yes THEN NULL ELSE ws.opens_at END AS opens_at,
                 CASE WHEN cce.yes OR pre.yes THEN NULL ELSE ws.closes_at END AS closes_at
            FROM a CROSS JOIN cce CROSS JOIN pre CROSS JOIN LATERAL policy.window_state('ADMISSION_STATUS_CHECKING', a.session, NULL) ws),
    f AS (SELECT CASE WHEN (SELECT yes FROM cce) THEN (SELECT r.checking_fee FROM a CROSS JOIN LATERAL admissions.route_fee_rule(a.session, 'CCE') r)
                      WHEN (SELECT yes FROM pre) THEN (SELECT r.checking_fee FROM a CROSS JOIN pre CROSS JOIN LATERAL admissions.route_fee_rule(a.session, pre.route) r)
                      ELSE coalesce((SELECT r.checking_fee FROM a CROSS JOIN LATERAL admissions.applicant_fee_rule(a.session) r), 0) END::numeric AS fee),
    pay AS (SELECT min(r.confirmed_at) FILTER (WHERE r.kind = 'CHECKING') AS ck_at,
                   (array_agg(r.reference ORDER BY r.confirmed_at) FILTER (WHERE r.kind = 'CHECKING'))[1] AS ck_ref,
                   coalesce(bool_or(r.kind = 'ACCEPTANCE'), false) AS acc
              FROM admissions.fee_reference r WHERE r.application_id = p_app AND r.confirmed_at IS NOT NULL),
    o AS (SELECT r.reference, r.expires_at FROM admissions.fee_reference r
           WHERE r.application_id = p_app AND r.kind = 'CHECKING' AND r.confirmed_at IS NULL AND r.expires_at > now()
           ORDER BY r.generated_at DESC LIMIT 1),
    k AS (SELECT count(*) AS n, max(c.checked_at) AS last_at, (array_agg(c.result ORDER BY c.checked_at DESC))[1] AS last_result
            FROM admissions.status_check c WHERE c.application_id = p_app),
    x AS (
        SELECT a.id, a.session,
               (a.fee_confirmed_at IS NOT NULL AND coalesce(a.submitted_at, (SELECT pre.submitted_at FROM pre)) IS NOT NULL) AS valid,
               w.state AS wstate, w.state = 'OPEN' AS wopen, w.opens_at, w.closes_at,
               f.fee, coalesce(f.fee > 0, (SELECT yes FROM cce)) AS required,
               -- an acceptance confirmed under the old rule (V148) included the checking fee: it counts as paid
               (a.checking_confirmed_at IS NOT NULL OR pay.ck_at IS NOT NULL OR a.acceptance_confirmed_at IS NOT NULL OR pay.acc) AS paid,
               coalesce(a.checking_confirmed_at, pay.ck_at) AS paid_at, pay.ck_ref,
               -- the offer has been read and the admission is under way: the workflow continues whatever the window
               (a.decision_released_at IS NOT NULL AND a.decision = 'OFFERED'
                AND (a.status_checked_at IS NOT NULL OR a.undertaking_at IS NOT NULL OR a.acceptance_confirmed_at IS NOT NULL
                     OR a.accepted_at IS NOT NULL OR a.declined_at IS NOT NULL OR pay.acc)) AS past
          FROM a, w, f, pay)
    SELECT x.id, x.session, x.valid, x.wstate, x.wopen, x.opens_at, x.closes_at, x.fee, x.required,
           x.paid, x.paid_at, x.ck_ref, (SELECT o.reference FROM o), (SELECT o.expires_at FROM o),
           x.past,
           x.valid AND x.wopen AND x.required AND NOT x.paid,
           x.valid AND x.wopen AND (x.paid OR NOT x.required),
           x.past OR (x.valid AND x.wopen AND (x.paid OR NOT x.required)),
           CASE WHEN x.past THEN NULL WHEN NOT x.valid THEN 'APPLICATION_INCOMPLETE' WHEN NOT x.wopen THEN 'CHECKING_CLOSED'
                WHEN x.required AND NOT x.paid THEN 'CHECKING_FEE_UNPAID' END,
           k.n, k.last_at, k.last_result
      FROM x, k
$function$;

CREATE OR REPLACE FUNCTION admissions.admission_status(p_app uuid)
 RETURNS TABLE(status text, label text, next_action text, next_href text, detail text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE a admissions.application; f admissions.screening_form; s people.student; q admissions.programme_change_request; req boolean; ent record; reg boolean; paid boolean; c record; v_cce boolean;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN QUERY SELECT 'NOT_FOUND', 'Not found', NULL, NULL, NULL; RETURN; END IF;
    v_cce := EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE');
    -- V446: a Preliminary Science applicant is told in the programme's own terms (admissions.prelim_status)
    IF EXISTS (SELECT 1 FROM admissions.prelim_review x WHERE x.application_id = p_app) THEN
        RETURN QUERY SELECT * FROM admissions.prelim_status(p_app); RETURN;
    END IF;
    -- V295: the status is read through Admission Status Checking — a valid Post-UTME application (paid for and submitted), checking
    -- open (the Director of ICT's window) and the checking fee paid; never through the decision, which is what the check reveals.
    -- An applicant who has read an offer and whose admission is under way continues whatever the window.
    SELECT * INTO c FROM admissions.status_checking(p_app);
    IF NOT c.decision_visible THEN
        IF NOT c.application_valid THEN
            RETURN QUERY SELECT 'APPLICATION_INCOMPLETE', 'Application not complete',
                CASE WHEN a.fee_confirmed_at IS NULL THEN 'Pay the application fee' ELSE 'Complete and submit your application' END,
                CASE WHEN EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE') THEN '/applicant/cce'
                     WHEN a.fee_confirmed_at IS NULL THEN '/applicant/fee' ELSE '/applicant/apply' END,
                CASE WHEN EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE')
                     THEN 'The Centre for Continuing Education reviews your application once it is complete and submitted.'
                     ELSE 'Admission status checking is open to every applicant whose Post-UTME application is paid for and submitted.' END; RETURN;
        END IF;
        IF NOT c.window_open THEN
            RETURN QUERY SELECT 'CHECKING_CLOSED', 'Admission status checking closed', NULL::text, '/applicant/admission',
                -- V404: a CCE applicant's checking opens when the Centre publishes the outcome of the application
                CASE WHEN v_cce THEN 'The Centre for Continuing Education has not yet published the outcome of your application. You are told by email and SMS when it does; then pay the admission checking fee and read it here.'
                     WHEN c.window_state = 'SCHEDULED' AND c.opens_at IS NOT NULL
                     THEN 'Admission status checking opens on ' || to_char(c.opens_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY "at" HH24:MI') || '.'
                     ELSE 'Admission status checking is currently unavailable. Please check back when the University opens the admission checking portal.' END; RETURN;
        END IF;
        RETURN QUERY SELECT 'CHECKING_FEE_PENDING', 'Admission checking fee not paid', 'Pay the admission checking fee', '/applicant/admission',
            CASE WHEN v_cce AND c.fee IS NULL
                 THEN 'The Centre for Continuing Education has published the outcome of your application. The Bursary has not yet stated the CCE admission checking fee for ' || a.session || '; pay it and read the outcome here once it does.'
                 WHEN v_cce
                 THEN 'The Centre for Continuing Education has published the outcome of your application. Pay the admission checking fee of ₦' || to_char(c.fee, 'FM999,999,990') || ' once, then read it here as often as you need.'
                 ELSE 'Admission status checking is open. Pay the admission checking fee of ₦' || to_char(c.fee, 'FM999,999,990') || ' once, then check your admission status as often as you need while checking is open.' END; RETURN;
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

CREATE OR REPLACE FUNCTION admissions.issue_admission_letter(p_app uuid)
 RETURNS credentials.issued
 LANGUAGE plpgsql
AS $function$
DECLARE pr admissions.prelim_review; pp admissions.prelim_programme; tg record; a admissions.application; c admissions.candidate; cur credentials.issued; v_stmt jsonb; v_hash text; v_number text; v_version int := 1; v_id uuid := gen_random_uuid();
        v_actor uuid; v_office text; ent record; v_prog record; v_changed record; v_student people.student;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN RAISE EXCEPTION 'there is no offer to issue a letter for' USING ERRCODE = '23514'; END IF;
    SELECT * INTO pr FROM admissions.prelim_review WHERE application_id = p_app;
    -- V446: a Preliminary Science offer has no acceptance fee the University has stated; its letter follows the published offer
    IF a.accepted_at IS NULL AND pr.application_id IS NULL THEN RAISE EXCEPTION 'the admission letter is issued once the offer is accepted and the acceptance fee confirmed' USING ERRCODE = '23514', HINT = 'Sign the undertaking and pay the acceptance fee, then print the letter.'; END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    SELECT p.code, p.name, p.category, f.name AS faculty, d.name AS department INTO v_prog
      FROM ref.programme p LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code WHERE p.code = admissions.programme_code_of(c.programme);
    SELECT * INTO cur FROM credentials.issued i WHERE i.application_id = p_app AND i.kind = 'ADMISSION_LETTER' AND NOT EXISTS (SELECT 1 FROM credentials.issued x WHERE x.supersedes = i.id) ORDER BY i.version DESC LIMIT 1;
    -- the letter stands while it names the programme the admission is for
    IF cur.id IS NOT NULL AND cur.statement->>'programme' = c.programme THEN RETURN cur; END IF;
    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);
    SELECT * INTO v_student FROM people.student WHERE candidate_id = c.id LIMIT 1;
    SELECT q.from_programme, q.to_programme, q.decided_at INTO v_changed FROM admissions.programme_change_request q WHERE q.application_id = p_app AND q.state = 'APPROVED' ORDER BY q.decided_at DESC LIMIT 1;
    v_actor := coalesce(nullif(current_setting('moaum.actor_id', true), '')::uuid, '00000000-0000-0000-0000-000000000000'::uuid);
    v_office := nullif(current_setting('moaum.actor_office', true), '');
    IF v_office IS NULL OR NOT EXISTS (SELECT 1 FROM ref.office WHERE code = v_office) THEN v_office := 'registrar'; END IF;
    IF cur.id IS NOT NULL THEN v_version := cur.version + 1; v_number := cur.number; ELSE v_number := credentials.next_document_number('ADMISSION_LETTER'); END IF;
    v_stmt := jsonb_build_object(
        'kind', 'ADMISSION_LETTER', 'number', v_number, 'version', v_version,
        'holder', c.surname || ', ' || c.other_names, 'surname', c.surname, 'otherNames', c.other_names, 'jambRegNo', c.jamb_reg_no, 'applicationNo', a.application_no,
        'session', a.session, 'programme', c.programme, 'programmeCode', v_prog.code, 'degreeType', v_prog.category, 'faculty', v_prog.faculty, 'department', v_prog.department,
        'admissionType', c.entry_mode || ' · ' || c.entry_level || ' Level', 'entryMode', c.entry_mode, 'entryLevel', c.entry_level, 'basis', a.decision_basis,
        'decisionReleasedOn', a.decision_released_at::date, 'acceptedOn', a.accepted_at::date, 'acceptanceReference', ent.reference, 'acceptanceConfirmedOn', ent.confirmed_at::date,
        'admissionNo', v_student.admission_no,
        'changedFrom', v_changed.from_programme, 'changedTo', v_changed.to_programme, 'changedOn', v_changed.decided_at::date,
        'issuedOn', current_date, 'issuingAuthority', 'The Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi');
    -- V379: a CCE admission names the route, the study mode, the Centre and the programme's duration on the route
    IF c.entry_mode = 'CCE' THEN
        v_stmt := v_stmt || jsonb_build_object('admissionRoute', 'CCE', 'studyMode', 'PART-TIME', 'centre', 'Centre for Continuing Education',
                    'admissionType', 'CCE · Part-time · ' || c.entry_level || ' Level',
                    'durationYears', (SELECT t.duration_years FROM ref.programme_route_terms(v_prog.code, 'CCE') t),
                    'issuingAuthority', 'The Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi, for the Centre for Continuing Education');
    END IF;
    -- V446: the Preliminary Science letter names the programme, its type and the target programme as an intended progression only
    IF pr.application_id IS NOT NULL THEN
        SELECT * INTO pp FROM admissions.prelim_programme WHERE route = pr.route;
        SELECT p.code, p.name, f.name AS faculty, d.name AS department INTO tg
          FROM ref.programme p LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code WHERE p.code = pr.target_programme;
        v_stmt := v_stmt || jsonb_build_object('admissionRoute', pr.route, 'programme', c.programme, 'programmeCode', NULL, 'degreeType', 'PRELIMINARY / REMEDIAL',
                    'faculty', NULL, 'department', NULL, 'studyMode', 'FULL-TIME', 'admissionType', 'Preliminary Science · Full-time', 'entryLevel', NULL,
                    'targetProgramme', tg.name, 'targetProgrammeCode', tg.code, 'targetFaculty', tg.faculty, 'targetDepartment', tg.department,
                    'targetNote', 'Selection of a target programme under Preliminary Science does not constitute admission into the undergraduate programme. Subsequent admission remains subject to University requirements and applicable admission processes.',
                    'remediationRequired', pr.remediation_status = 'REQUIRED',
                    'remediationSubjects', to_jsonb(pr.remediation_subjects), 'remediationCreditsShort', pr.remediation_credits_short,
                    'completionNote', pp.completion_note,
                    'issuingAuthority', 'The Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi, for the Preliminary Science Programme');
    END IF;
    v_hash := encode(sha256(convert_to(v_stmt::text, 'UTF8')), 'hex');
    INSERT INTO credentials.issued (id, kind, student_id, application_id, verification_code, statement, signature, signed_with, issuing_name, issued_on, issued_by, issued_office, supersedes, number, version, template_version, content_hash, note)
    VALUES (v_id, 'ADMISSION_LETTER', v_student.id, p_app, credentials.new_code(), v_stmt, decode(v_hash, 'hex'), NULL, 'Rev. Fr. Moses Orshio Adasu University, Makurdi', current_date, v_actor, v_office, cur.id,
            v_number, v_version, NULL, v_hash, CASE WHEN cur.id IS NULL THEN 'Letter of provisional admission' ELSE 'Reissued: the programme changed to ' || c.programme END);
    PERFORM credentials.log(NULL, v_id, v_student.id, 'ISSUED', NULL, 'ACTIVE', 'ADMISSION_LETTER ' || v_number || ' v' || v_version || ' · ' || c.programme);
    SELECT * INTO cur FROM credentials.issued WHERE id = v_id;
    RETURN cur;
END $function$;
-- ── 14 · the Preliminary Science Programme for 2026/2027 ─────────────────────────────────────────────────────────
-- the route; its session is the one the University's notice names (2026/2027), set by the Academic Office like CCE's override.
-- Its duration is not in the notice: one year is the route register's placeholder, never printed (docs/preliminary-science.md).
INSERT INTO policy.study_route (code, name, study_mode, centre_unit, entry_level, default_duration_years, session_offset, session_override, override_reason, configured_office)
SELECT 'PRELIMINARY_SCIENCE', 'Preliminary Science Programme', 'FULL_TIME', NULL, 0, 1, 0,
       CASE WHEN EXISTS (SELECT 1 FROM policy.academic_session WHERE name = '2026/2027') THEN '2026/2027' END,
       CASE WHEN EXISTS (SELECT 1 FROM policy.academic_session WHERE name = '2026/2027') THEN 'The University''s Preliminary Science notice is for the 2026/2027 academic session' END,
       'academic'
ON CONFLICT (code) DO NOTHING;
INSERT INTO policy.study_route_event (route, actor, office, what, after, reason)
VALUES ('PRELIMINARY_SCIENCE', '00000000-0000-0000-0000-000000000000', 'academic', 'CREATED',
        jsonb_build_object('study_mode', 'FULL_TIME', 'entry_level', 0, 'session', policy.route_session('PRELIMINARY_SCIENCE')),
        'V446: the Preliminary Science Programme, as the University''s notice gives it');

INSERT INTO admissions.prelim_programme (route, name, programme_type, description, completion_note, procedure, office_note,
                                         min_credits, max_sittings, min_core_credits, core_subjects, credit_grade, completion_credits, completion_subjects, remediation_terms)
VALUES ('PRELIMINARY_SCIENCE', 'Preliminary Science', 'PRELIMINARY',
        'The Preliminary Science Programme is a preparatory programme for candidates seeking subsequent admission into approved science-based programmes of the University. It prepares candidates academically and allows them to remedy relevant O''Level deficiencies where University policy permits. It is not an undergraduate degree programme.',
        'Candidates admitted with fewer than five O''Level credit passes will have to make up five O''Level credit passes, including Mathematics, Physics, Chemistry and Biology, before completing the programme.',
        ARRAY['Open the University''s application portal and choose Preliminary Science.',
              'Start the application: give your name, sex, date of birth, email and phone number. Your application number is issued at once.',
              'Pay the application fee online with the reference the portal gives you.',
              'Once the payment is verified, continue the application.',
              'Complete the form: your personal details, your O''Level results (one sitting or two; an awaiting result is not accepted) and the programme you intend to progress to.',
              'Upload the documents listed on this page.',
              'Submit the application.',
              'Print the application form.',
              'Submit the printed form and the required photocopies to the Preliminary Science Office where the University asks for physical submission.'],
        'Applications are reviewed by the Preliminary Science Office; the admission decision is approved and published by the Academic Office.',
        4, 2, 3, ARRAY['Mathematics', 'Chemistry', 'Physics', 'Biology'], 'C6', 5, ARRAY['Mathematics', 'Physics', 'Chemistry', 'Biology'], NULL)
ON CONFLICT (route) DO NOTHING;

INSERT INTO admissions.prelim_document (route, kind, label, hint, required, second_sitting_only, ord) VALUES
    ('PRELIMINARY_SCIENCE', 'PASSPORT', 'Recent passport photograph', 'A clear, recent JPEG photograph on a plain background.', true, false, 10),
    ('PRELIMINARY_SCIENCE', 'PASSPORT_2', 'Second recent passport photograph', 'The notice asks for two recent passport photographs (JPEG).', true, false, 20),
    ('PRELIMINARY_SCIENCE', 'OLEVEL_STATEMENT', 'O''Level result (first sitting)', 'The result or statement of result of your first sitting.', true, false, 30),
    ('PRELIMINARY_SCIENCE', 'OLEVEL_STATEMENT_2', 'O''Level result (second sitting)', 'Only when you give two sittings: the result of the second, kept apart from the first.', true, true, 40),
    ('PRELIMINARY_SCIENCE', 'LGA_ID', 'Indigene certificate', 'The certificate of indigeneship (local government identification) of your local government area.', true, false, 50),
    ('PRELIMINARY_SCIENCE', 'BIRTH_CERT', 'Birth certificate or declaration of age', NULL, true, false, 60)
ON CONFLICT (route, kind) DO NOTHING;

-- the target programmes the notice names, each the existing programme of the register whose official name it is; a name the
-- register does not hold stays MISSING for the Academic Office to resolve — never a new programme, never a guess
WITH want(group_name, ord, requested_name, official) AS (VALUES
    ('Health / Medical', 10, 'Medicine and Surgery (M.B.B.S)', ARRAY['MBBS', 'MEDICINE AND SURGERY', 'BACHELOR OF MEDICINE AND BACHELOR OF SURGERY (MBBS)']),
    ('Health / Medical', 20, 'Bachelor of Medical Laboratory Science (BMLS)', ARRAY['BACHELOR OF MEDICAL LABORATORY SCIENCE (BMLS)', 'BACHELOR OF MEDICAL LABORATORY SCIENCE', 'BMLS']),
    ('Health / Medical', 30, 'B. Nursing Science', ARRAY['BACHELOR OF NURSING SCIENCES', 'BACHELOR OF NURSING SCIENCE', 'B. NURSING SCIENCE', 'B.N.SC NURSING SCIENCE']),
    ('Health / Medical', 40, 'B.Sc Anatomy', ARRAY['B.Sc. HUMAN ANATOMY', 'B.Sc. ANATOMY']),
    ('Health / Medical', 50, 'B.Sc Radiography & Radiation Science', ARRAY['B.Sc. RADIOGRAPHY AND RADIATION SCIENCE']),
    ('Health / Medical', 60, 'B.Sc Doctor of Pharmacy (Pharm.D)', ARRAY['DOCTOR OF PHARMACY', 'PHARM.D', 'DOCTOR OF PHARMACY (PHARM.D)']),
    ('Health / Medical', 70, 'B.Sc Physiology', ARRAY['B.Sc. HUMAN PHYSIOLOGY', 'B.Sc. PHYSIOLOGY']),
    ('Science / Technology', 110, 'B.Sc Environmental Management & Toxicology', ARRAY['B.Sc. ENVIRONMENTAL MANAGEMENT AND TOXICOLOGY']),
    ('Science / Technology', 120, 'B.Sc Computer Science', ARRAY['B.Sc. COMPUTER SCIENCE']),
    ('Science / Technology', 130, 'B.Sc Statistics', ARRAY['B.Sc. STATISTICS']),
    ('Science / Technology', 140, 'B.Sc Mathematics', ARRAY['B.Sc. MATHEMATICS']),
    ('Science / Technology', 150, 'B.Sc Physics', ARRAY['B.Sc. PHYSICS']),
    ('Science / Technology', 160, 'B.Sc Chemistry', ARRAY['B.Sc. CHEMISTRY']),
    ('Science / Technology', 170, 'B.Sc Industrial Chemistry', ARRAY['B.Sc INDUSTRIAL CHEMISTRY', 'B.INDCHM', 'B. INDUSTRIAL CHEMISTRY']),
    ('Science / Technology', 180, 'B.Sc Biology', ARRAY['B.Sc. BIOLOGY']),
    ('Science / Technology', 190, 'B.Sc Plant Science and Biotechnology', ARRAY['B.Sc. PLANT SCIENCE AND BIOTECHNOLOGY']),
    ('Science / Technology', 200, 'B.Sc Microbiology', ARRAY['B.Sc. MICROBIOLOGY']),
    ('Science / Technology', 210, 'B.Sc Zoology', ARRAY['B.Sc. ZOOLOGY']),
    ('Science / Technology', 220, 'B.Sc Technology and Industrial Studies', ARRAY['B.Sc. TECHNOLOGY AND INDUSTRIAL STUDIES']),
    ('Built Environment / Design', 310, 'B.Sc Architecture', ARRAY['B. Sc. ARCHITECTURE']),
    ('Built Environment / Design', 320, 'B.Sc Landscape Architecture', ARRAY['B. Sc. LANDSCAPE ARCHITECTURE']),
    ('Built Environment / Design', 330, 'B.Sc Interior Design', ARRAY['B. Sc. INTERIOR DESIGN']),
    ('Science Education', 410, 'B.Sc Ed. Computer Science', ARRAY['B.Sc. (ED) COMPUTER SCIENCE']),
    ('Science Education', 420, 'B.Sc Ed. Integrated Science', ARRAY['B.Sc. (ED) INTEGRATED SCIENCE']),
    ('Science Education', 430, 'B.Sc Ed. Chemistry', ARRAY['B.Sc. (ED) CHEMISTRY']),
    ('Science Education', 440, 'B.Sc Ed. Mathematics', ARRAY['B.Sc. (ED) MATHEMATICS']),
    ('Science Education', 450, 'B.Sc Ed. Biology', ARRAY['B.Sc. (ED) BIOLOGY']),
    ('Science Education', 460, 'B.Sc Ed. Physics', ARRAY['B.Sc. (ED) PHYSICS'])),
found AS (
    SELECT w.*, (SELECT array_agg(p.code ORDER BY p.code) FROM ref.programme p
                  WHERE NOT p.archived AND p.category = 'UNDER GRADUATE'
                    AND regexp_replace(upper(p.name), '[^A-Z0-9]', '', 'g') IN (SELECT regexp_replace(upper(o), '[^A-Z0-9]', '', 'g') FROM unnest(w.official) o)
                    AND EXISTS (SELECT 1 FROM ref.department d WHERE d.code = p.dept_code AND d.ended_on IS NULL)) AS codes
      FROM want w)
INSERT INTO admissions.prelim_target (route, group_name, ord, requested_name, programme_code, state, note, added_office)
SELECT 'PRELIMINARY_SCIENCE', f.group_name, f.ord, f.requested_name,
       CASE WHEN cardinality(f.codes) = 1 THEN f.codes[1] END,
       CASE WHEN cardinality(f.codes) = 1 THEN 'MAPPED' ELSE 'MISSING' END,
       CASE WHEN cardinality(f.codes) = 1 THEN 'Named in the University''s Preliminary Science notice (2026/2027)'
            WHEN f.codes IS NULL THEN 'MISSING TARGET PROGRAMME: no programme of that name is on the register; the Academic Office names the existing programme it is'
            ELSE 'MISSING TARGET PROGRAMME: more than one programme answers to that name (' || array_to_string(f.codes, ', ') || '); the Academic Office names the one it is' END,
       'academic'
  FROM found f;

-- the application fee of the notice, through the Bursary's route fees for the session (no other fee is stated: none is invented)
INSERT INTO admissions.route_fee (session, route, application_fee, portal_charge, acceptance_fee, checking_fee, stated_by, stated_office)
SELECT '2026/2027', 'PRELIMINARY_SCIENCE', 5000, 0, NULL, NULL, '00000000-0000-0000-0000-000000000000', 'bursar'
 WHERE EXISTS (SELECT 1 FROM policy.academic_session WHERE name = '2026/2027')
ON CONFLICT (session, route) DO NOTHING;

-- the window: applications open on Monday, 20 July 2026; the closing date is the Director of ICT's to set
SELECT policy.window_act('PRELIMINARY_SCIENCE_APPLICATION', '2026/2027', NULL, 'SCHEDULE', TIMESTAMPTZ '2026-07-20 00:00:00+01', NULL, NULL, false,
                         'The University''s Preliminary Science notice: applications for 2026/2027 open on Monday, 20 July 2026', '00000000-0000-0000-0000-000000000000', 'ict')
 WHERE EXISTS (SELECT 1 FROM policy.academic_session WHERE name = '2026/2027')
   AND NOT EXISTS (SELECT 1 FROM policy.portal_window WHERE window_type = 'PRELIMINARY_SCIENCE_APPLICATION' AND session = '2026/2027');
INSERT INTO policy.portal_window_message (window_type, message, updated_by, updated_office)
VALUES ('PRELIMINARY_SCIENCE_APPLICATION', 'Preliminary Science applications are not open at present. The University announces the opening on this page.',
        '00000000-0000-0000-0000-000000000000', 'ict')
ON CONFLICT (window_type) DO NOTHING;

-- the programme type its payments are classified under (V409): the Preliminary entry mode, owned by the Preliminary Science Office
UPDATE finance.programme_type SET entry_modes = ARRAY['PRELIMINARY'],
       description = 'The Preliminary Science Programme (V446) and any other preliminary programme run as an admission route'
 WHERE code = 'PRELIMINARY';
UPDATE finance.payment_classification SET source_module = 'PRELIMINARY_SCIENCE', responsible_office = 'prelim',
       note = 'The Preliminary Science Programme''s applications and fees (V446)'
 WHERE purpose IS NULL AND programme_type = 'PRELIMINARY';

-- ── 15 · the notices, in the central templates ──────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('PRELIMINARY_SCIENCE', 'Preliminary Science', 'A message to a Preliminary Science applicant; each event has its own wording under PRELIMINARY_SCIENCE:<event>.',
 'Your Preliminary Science application [APPLICATION_NUMBER]',
 E'Dear [FIRST_NAME],\n\nThere is news on your Preliminary Science application ([APPLICATION_NUMBER], [SESSION]). Sign in to read it: [PORTAL_URL]\n\nPreliminary Science Office, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: news on your Preliminary Science application [APPLICATION_NUMBER]. Sign in to read it.',
 'Preliminary Science application', 'There is news on your Preliminary Science application [APPLICATION_NUMBER].',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','SESSION','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'NORMAL'),
('PRELIMINARY_SCIENCE:APPLICATION_CREATED', 'Preliminary Science application started', 'Sent when a Preliminary Science application is started online: the application number and the next step.',
 'Your Preliminary Science application number: [APPLICATION_NUMBER]',
 E'Dear [FIRST_NAME],\n\nYour Preliminary Science application for the [SESSION] session is started. Your application number is [APPLICATION_NUMBER]; sign in with it or with this email address.\n\nNext, pay the application fee with the reference the portal gives you. Once the payment is verified, continue and complete the application: [PORTAL_URL]\n\nPreliminary Science Office, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: your Preliminary Science application number is [APPLICATION_NUMBER]. Pay the application fee, then complete the form.',
 'Application started', 'Your application number is [APPLICATION_NUMBER]. Pay the application fee, then complete the form.',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','SESSION','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('PRELIMINARY_SCIENCE:PAYMENT_SUCCESSFUL', 'Preliminary Science payment verified', 'Sent when a Preliminary Science payment is verified by the payment service: the receipt and the next step.',
 'Your payment receipt [RECEIPT_NUMBER]',
 E'Dear [FIRST_NAME],\n\nThis is your official receipt from [UNIVERSITY_NAME].\n\nReceipt no:  [RECEIPT_NUMBER]\nReference:   [REFERENCE]\nPurpose:     [PURPOSE]\nApplication: [APPLICATION_NUMBER]\nSession:     [SESSION]\nAmount:      [AMOUNT]\nVerified:    [PAID_ON]\nChannel:     [CHANNEL]\n\nYour application form is now open: sign in and continue the application. [PORTAL_URL]\n\nKeep this receipt. It is verified against the University''s record by its receipt number, not by its appearance.',
 '[UNIVERSITY_SHORT] receipt [RECEIPT_NUMBER]: [AMOUNT] for [PURPOSE] verified. Continue your application.',
 'Payment verified', 'Receipt [RECEIPT_NUMBER]: [AMOUNT] for [PURPOSE]. Continue your application.',
 ARRAY['FIRST_NAME','RECEIPT_NUMBER','REFERENCE','PURPOSE','APPLICATION_NUMBER','SESSION','AMOUNT','PAID_ON','CHANNEL','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('PRELIMINARY_SCIENCE:APPLICATION_SUBMITTED', 'Preliminary Science application submitted', 'Sent when the applicant submits the application.',
 'Your Preliminary Science application is submitted',
 E'Dear [FIRST_NAME],\n\nYour Preliminary Science application ([APPLICATION_NUMBER], [SESSION] session) is submitted. The Preliminary Science Office reviews it; you will be told here and by email if anything more is needed, and when the outcome is published.\n\nPrint your application form from the portal: [PORTAL_URL]\n\nPreliminary Science Office, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: your Preliminary Science application [APPLICATION_NUMBER] is submitted. Print your application form from the portal.',
 'Application submitted', 'Your application [APPLICATION_NUMBER] is submitted and is with the Preliminary Science Office.',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','SESSION','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'NORMAL'),
('PRELIMINARY_SCIENCE:CORRECTION_REQUIRED', 'Preliminary Science correction required', 'Sent when the Preliminary Science Office returns an application to the applicant for a correction.',
 'The Preliminary Science Office needs a correction',
 E'Dear [FIRST_NAME],\n\nThe Preliminary Science Office has reviewed your application ([APPLICATION_NUMBER]) and needs the following before it can continue:\n\n[NOTE]\n\nSign in, make the correction and send the application back: [PORTAL_URL]\n\nPreliminary Science Office, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: the Preliminary Science Office needs a correction on your application [APPLICATION_NUMBER]. Sign in to see what.',
 'Correction required', '[NOTE]',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','NOTE','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('PRELIMINARY_SCIENCE:ADMISSION_OFFERED', 'Preliminary Science admission offered', 'Sent when the Academic Office publishes an admission into the Preliminary Science Programme.',
 'Admission into the Preliminary Science Programme',
 E'Dear [FIRST_NAME],\n\nCongratulations: you have been offered admission into the Preliminary Science Programme of [UNIVERSITY_NAME] for the [SESSION] session (application [APPLICATION_NUMBER]).\n\nYour intended progression is [TARGET_PROGRAMME]. Selection of a target programme under Preliminary Science does not constitute admission into the undergraduate programme; subsequent admission remains subject to University requirements and applicable admission processes. [REMEDIATION_NOTE]\n\nSign in to read the offer and print your admission letter: [PORTAL_URL]\n\nPreliminary Science Office, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: congratulations, you are offered admission into the Preliminary Science Programme ([APPLICATION_NUMBER]). Sign in for your letter.',
 'Admission offered', 'You are offered admission into the Preliminary Science Programme for [SESSION]. [REMEDIATION_NOTE]',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','SESSION','TARGET_PROGRAMME','REMEDIATION_NOTE','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('PRELIMINARY_SCIENCE:ADMISSION_NOT_OFFERED', 'Preliminary Science admission not offered', 'Sent when the Academic Office publishes that an application was not successful, with the reason recorded.',
 'The outcome of your Preliminary Science application',
 E'Dear [FIRST_NAME],\n\nThe outcome of applications to the Preliminary Science Programme for [SESSION] is published. Your application ([APPLICATION_NUMBER]) was not successful.\n\n[NOTE]\n\nYou may sign in to read it: [PORTAL_URL]\n\nPreliminary Science Office, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: the outcome of your Preliminary Science application [APPLICATION_NUMBER] is published. Sign in to read it.',
 'Outcome published', 'Your application was not successful. [NOTE]',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','SESSION','NOTE','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('PRELIMINARY_SCIENCE:REMEDIATION_REQUIRED', 'Preliminary Science remediation required', 'Sent with an admission whose completion rule asks the candidate to make up O''Level credits.',
 'What you are to make up before completing Preliminary Science',
 E'Dear [FIRST_NAME],\n\nOn the O''Level results you gave, you are to make up the following before completing the Preliminary Science Programme: [REMEDIATION].\n\nThe Preliminary Science Office will tell you how and when; nothing more is required of you today.\n\nPreliminary Science Office, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: before completing Preliminary Science you are to make up: [REMEDIATION].',
 'Remediation required', 'Before completing the programme you are to make up: [REMEDIATION].',
 ARRAY['FIRST_NAME','REMEDIATION','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'NORMAL'),
('WINDOW_CLOSING:PRELIMINARY_SCIENCE_APPLICATION', 'Preliminary Science application closing',
 'The reminder before the Preliminary Science application window closes, to the applicants of the session whose application is a draft or was returned for correction',
 'Preliminary Science applications for [SESSION] close [DAYS_WORD]',
 E'Dear [FIRST_NAME],\n\n[WINDOW] for [SESSION] closes [DAYS_WORD], on [DEADLINE]. Our record shows your application ([APPLICATION_NUMBER]) has not been submitted, or was returned to you for correction. [LATE_NOTE]\n\nComplete and submit it before then: [PORTAL_URL]\n\nPreliminary Science Office, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: Preliminary Science applications for [SESSION] close [DAYS_WORD] ([DEADLINE]) and yours is not yet submitted. Submit it before then.',
 'Preliminary Science application closes [DAYS_WORD]',
 '[WINDOW] for [SESSION] closes [DAYS_WORD], on [DEADLINE]; your application has not been submitted. [LATE_NOTE]',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','WINDOW','SESSION','DAYS_WORD','DEADLINE','LATE_NOTE','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH')
ON CONFLICT (key) DO NOTHING;

COMMIT;
