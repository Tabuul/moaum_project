-- ═══════════════════════════════════════════════════════════════════════════
-- V339 — JUPEB: the University's Joint Universities Preliminary Examinations Board programme, application to result
--
--   A one-year programme the University runs and JUPEB examines. It shares the portal's infrastructure and keeps its own
--   academic record:
--     · REUSED: the one sign-in door (an applicant token), the payment gateway and its verification, the portal windows
--       (a JUPEB_APPLICATION window, closed until the Director of ICT opens it), private file storage, the email/SMS
--       outbox, the audit spine, the support desk (a JUPEB requester and queue), faculties/departments/programmes for the
--       programme of interest, and the branded PDF writer for letters, receipts and slips.
--     · KEPT APART, deliberately: a JUPEB candidate is not put on people.student — the undergraduate register is
--       matriculation-bound and would carry the candidate into fees by level, GPA, matriculation, graduation and the
--       statistics; JUPEB subjects are not catalogue courses — those make score sheets and course registrations, and JUPEB
--       subjects are examined by the Board; the undergraduate O'Level store is keyed on JAMB records, and JUPEB needs no
--       JAMB. So one JUPEB candidate record (jupeb.application) carries the person from applicant to student to result.
--   The JUPEB Office (a new office) runs admission and academic operations; the Bursary alone sets the fees (application
--   fee, the four school fees, the instalment split, the activation threshold, the indigene state, which faculties count
--   as Science); the JUPEB Office reads them. Defaults seeded: application ₦15,000; school fees ₦180,000 / ₦195,000 /
--   ₦200,000 / ₦215,000; 70% first semester, 30% second; Benue the indigene state. No combination is seeded: the
--   University's 43 are imported or entered by the JUPEB Office.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V339: the JUPEB programme module', true);

CREATE SCHEMA IF NOT EXISTS jupeb;
COMMENT ON SCHEMA jupeb IS 'V339: the University''s JUPEB programme — application, admission, fees (set by the Bursary), subjects, registration, examination numbers and results.';
GRANT USAGE ON SCHEMA jupeb TO app_admissions, app_finance, app_auditor, app_registration, app_results;

-- ── 1 · the JUPEB Office ────────────────────────────────────────────────────────────────────────────
INSERT INTO ref.office (code, label, scope_kind) VALUES ('jupeb', 'JUPEB Office', 'platform') ON CONFLICT (code) DO NOTHING;

-- ── 2 · subjects and the approved combinations of three ─────────────────────────────────────────────
CREATE TABLE jupeb.subject (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code        text NOT NULL UNIQUE,
    title       text NOT NULL,
    description text NULL,
    active      boolean NOT NULL DEFAULT true,
    created_by  uuid NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_by  uuid NULL,
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_jupeb_subject_code CHECK (code ~ '^[A-Z0-9][A-Z0-9 /&-]{1,39}$'),
    CONSTRAINT ck_jupeb_subject_title CHECK (length(btrim(title)) BETWEEN 2 AND 160)
);
SELECT audit.attach('jupeb.subject');

CREATE TABLE jupeb.combination (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code              text NOT NULL UNIQUE,
    name              text NOT NULL,
    subject1          uuid NOT NULL REFERENCES jupeb.subject(id),
    subject2          uuid NOT NULL REFERENCES jupeb.subject(id),
    subject3          uuid NOT NULL REFERENCES jupeb.subject(id),
    area              text NULL,
    description       text NULL,
    eligibility_notes text NULL,
    from_session      text NULL,
    active            boolean NOT NULL DEFAULT true,
    created_by        uuid NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_by        uuid NULL,
    updated_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_jupeb_comb_code CHECK (code ~ '^[A-Z0-9][A-Z0-9 /&-]{0,19}$'),
    CONSTRAINT ck_jupeb_comb_three CHECK (subject1 <> subject2 AND subject1 <> subject3 AND subject2 <> subject3),
    CONSTRAINT ck_jupeb_comb_area CHECK (area IS NULL OR area IN ('Arts', 'Law', 'Engineering', 'Science', 'Social Sciences', 'Management Sciences', 'Other'))
);
SELECT audit.attach('jupeb.combination');
COMMENT ON TABLE jupeb.combination IS 'V339: an approved JUPEB subject combination — exactly three subjects; the University''s own combinations, entered or imported by the JUPEB Office.';

/* where a combination leads: a faculty, or a programme, of the University's register */
CREATE TABLE jupeb.combination_relevance (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    combination_id uuid NOT NULL REFERENCES jupeb.combination(id) ON DELETE CASCADE,
    faculty_code   text NULL REFERENCES ref.faculty(code),
    programme_code text NULL REFERENCES ref.programme(code),
    CONSTRAINT ck_jupeb_rel_one CHECK ((faculty_code IS NULL) <> (programme_code IS NULL))
);
CREATE UNIQUE INDEX ux_jupeb_rel ON jupeb.combination_relevance (combination_id, coalesce(faculty_code, ''), coalesce(programme_code, ''));
SELECT audit.attach('jupeb.combination_relevance');

-- ── 3 · the Bursary's fees, and which faculties count as Science ─────────────────────────────────────
CREATE TABLE jupeb.fee_setting (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session         text NOT NULL UNIQUE,
    application_fee numeric(12,2) NOT NULL CHECK (application_fee >= 0),
    first_percent   numeric(5,2) NOT NULL DEFAULT 70 CHECK (first_percent > 0 AND first_percent <= 100),
    allow_full      boolean NOT NULL DEFAULT true,
    activation      text NOT NULL DEFAULT 'FIRST_INSTALMENT' CHECK (activation IN ('FIRST_INSTALMENT', 'FULL')),
    indigene_state  text NOT NULL DEFAULT 'Benue',
    updated_by      uuid NULL,
    updated_office  text NULL,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_jupeb_fee_session CHECK (session = '*' OR session ~ '^[0-9]{4}/[0-9]{4}$')
);
SELECT audit.attach('jupeb.fee_setting');
COMMENT ON TABLE jupeb.fee_setting IS 'V339: the Bursary''s JUPEB fee rule for a session (''*'' is the default for every session without its own): the application fee, the first-semester share of the school fee, whether full payment is allowed, what activates a student, and the state whose indigenes pay the indigene fee.';

CREATE TABLE jupeb.school_fee (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session        text NOT NULL,
    category       text NOT NULL CHECK (category IN ('SCIENCE', 'OTHER')),
    indigene       boolean NOT NULL,
    amount         numeric(12,2) NOT NULL CHECK (amount > 0),
    updated_by     uuid NULL,
    updated_office text NULL,
    updated_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_jupeb_school_fee UNIQUE (session, category, indigene),
    CONSTRAINT ck_jupeb_school_fee_session CHECK (session = '*' OR session ~ '^[0-9]{4}/[0-9]{4}$')
);
SELECT audit.attach('jupeb.school_fee');

CREATE TABLE jupeb.fee_category (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    faculty_code text NOT NULL UNIQUE REFERENCES ref.faculty(code),
    category     text NOT NULL CHECK (category IN ('SCIENCE', 'OTHER')),
    updated_by   uuid NULL,
    updated_at   timestamptz NOT NULL DEFAULT now()
);
SELECT audit.attach('jupeb.fee_category');
COMMENT ON TABLE jupeb.fee_category IS 'V339: the Bursary''s word on which faculties count as Science for the JUPEB school fee; a faculty not named is OTHER.';

INSERT INTO jupeb.fee_setting (session, application_fee, first_percent, allow_full, activation, indigene_state) VALUES ('*', 15000, 70, true, 'FIRST_INSTALMENT', 'Benue');
INSERT INTO jupeb.school_fee (session, category, indigene, amount) VALUES
    ('*', 'OTHER', true, 180000), ('*', 'SCIENCE', true, 195000), ('*', 'OTHER', false, 200000), ('*', 'SCIENCE', false, 215000);

-- ── 4 · the JUPEB Office's settings per session: numbering, screening, result publication ─────────
CREATE TABLE jupeb.setting (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session                text NOT NULL UNIQUE,
    application_prefix     text NOT NULL DEFAULT 'JUPEB/APP',
    screening_required     boolean NOT NULL DEFAULT false,
    screening_venue        text NULL,
    screening_starts_on    date NULL,
    screening_ends_on      date NULL,
    screening_instructions text NULL,
    results_published_at   timestamptz NULL,
    results_published_by   uuid NULL,
    updated_by             uuid NULL,
    updated_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_jupeb_setting_session CHECK (session = '*' OR session ~ '^[0-9]{4}/[0-9]{4}$'),
    CONSTRAINT ck_jupeb_setting_prefix CHECK (application_prefix ~ '^[A-Z][A-Z0-9/-]{1,20}$')
);
SELECT audit.attach('jupeb.setting');
INSERT INTO jupeb.setting (session) VALUES ('*');

CREATE TABLE jupeb.document_kind (
    id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code     text NOT NULL UNIQUE CHECK (code ~ '^[A-Z][A-Z0-9_]{1,30}$'),
    label    text NOT NULL,
    required boolean NOT NULL DEFAULT true,
    image    boolean NOT NULL DEFAULT false,
    active   boolean NOT NULL DEFAULT true,
    ord      int NOT NULL DEFAULT 100
);
SELECT audit.attach('jupeb.document_kind');
INSERT INTO jupeb.document_kind (code, label, required, image, ord) VALUES
    ('OLEVEL_RESULT', 'O''Level result', true, false, 10),
    ('NIN', 'National Identification Number (NIN) slip', true, false, 20),
    ('BIRTH_CERTIFICATE', 'Birth certificate / declaration of age', true, false, 30),
    ('PASSPORT', 'Passport photograph', true, true, 40),
    ('STATE_OF_ORIGIN', 'Certificate of state of origin', true, false, 50);

-- ── 5 · the account and the candidate ──────────────────────────────────────────────────────────────
CREATE TABLE jupeb.account (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email             text NOT NULL,
    password_hash     text NOT NULL,
    failed_attempts   int NOT NULL DEFAULT 0,
    locked_until      timestamptz NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    last_signed_in_at timestamptz NULL,
    CONSTRAINT ck_jupeb_account_pw CHECK (password_hash LIKE '$2%$12$%'),
    CONSTRAINT ck_jupeb_account_email CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
);
CREATE UNIQUE INDEX ux_jupeb_account_email ON jupeb.account (lower(email));
SELECT audit.exempt('jupeb.account', 'Holds a password hash; excluded from the spine like the other applicant accounts (V021, V202).');

/* a forgotten password: a one-hour, single-use link; only the token's hash is kept */
CREATE TABLE jupeb.password_reset (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id  uuid NOT NULL REFERENCES jupeb.account(id),
    token_hash  text NOT NULL UNIQUE,
    expires_at  timestamptz NOT NULL,
    used_at     timestamptz NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
SELECT audit.exempt('jupeb.password_reset', 'Password reset tokens (hashes) for JUPEB accounts; excluded like the applicant resets.');

CREATE TABLE jupeb.class (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session        text NOT NULL,
    name           text NOT NULL,
    combination_id uuid NULL REFERENCES jupeb.combination(id),
    capacity       int NULL CHECK (capacity IS NULL OR capacity > 0),
    created_by     uuid NULL,
    created_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_jupeb_class UNIQUE (session, name)
);
SELECT audit.attach('jupeb.class');

CREATE TABLE jupeb.application (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id              uuid NOT NULL REFERENCES jupeb.account(id),
    session                 text NOT NULL,
    application_no          text NOT NULL UNIQUE,
    surname                 text NOT NULL,
    first_name              text NOT NULL,
    middle_name             text NULL,
    sex                     text NULL CHECK (sex IS NULL OR sex IN ('F', 'M')),
    date_of_birth           date NULL,
    nin                     text NULL CHECK (nin IS NULL OR nin ~ '^[0-9]{11}$'),
    email                   text NOT NULL,
    phone                   text NULL CHECK (phone IS NULL OR phone ~ '^0[0-9]{10}$'),
    nationality             text NULL,
    state_of_origin         text NULL,
    lga                     text NULL,
    contact_address         text NULL CHECK (contact_address IS NULL OR length(contact_address) <= 300),
    permanent_address       text NULL CHECK (permanent_address IS NULL OR length(permanent_address) <= 300),
    home_town               text NULL,
    guardian_name           text NULL,
    guardian_phone          text NULL,
    guardian_address        text NULL,
    next_of_kin_name        text NULL,
    next_of_kin_phone       text NULL,
    next_of_kin_relationship text NULL,
    programme_code          text NULL REFERENCES ref.programme(code),
    combination_id          uuid NULL REFERENCES jupeb.combination(id),
    state                   text NOT NULL DEFAULT 'DRAFT',
    fee_confirmed_at        timestamptz NULL,
    submitted_at            timestamptz NULL,
    return_note             text NULL,
    returned_at             timestamptz NULL,
    returned_by             uuid NULL,
    eligibility_note        text NULL,
    eligibility_decided_at  timestamptz NULL,
    eligibility_decided_by  uuid NULL,
    admission_ref           text NULL UNIQUE,
    admission_note          text NULL,
    admission_decided_at    timestamptz NULL,
    admission_decided_by    uuid NULL,
    fee_category            text NULL,
    indigene                boolean NULL,
    school_fee_total        numeric(12,2) NULL,
    first_percent           numeric(5,2) NULL,
    activated_at            timestamptz NULL,
    class_id                uuid NULL REFERENCES jupeb.class(id),
    subjects_registered_at  timestamptz NULL,
    exam_no                 text NULL,
    exam_no_assigned_at     timestamptz NULL,
    screening_state         text NULL,
    screening_venue         text NULL,
    screening_at            timestamptz NULL,
    screening_reason        text NULL,
    screening_decided_at    timestamptz NULL,
    screening_decided_by    uuid NULL,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_jupeb_application_session UNIQUE (account_id, session),
    CONSTRAINT ck_jupeb_app_state CHECK (state IN ('DRAFT', 'SUBMITTED', 'RETURNED', 'ELIGIBLE', 'INELIGIBLE', 'ADMITTED', 'NOT_ADMITTED', 'PENDING',
                                                   'STUDENT', 'COMPLETED', 'WITHDRAWN')),
    CONSTRAINT ck_jupeb_app_session CHECK (session ~ '^[0-9]{4}/[0-9]{4}$'),
    CONSTRAINT ck_jupeb_app_screening CHECK (screening_state IS NULL OR screening_state IN ('PENDING', 'SCHEDULED', 'IN_PROGRESS', 'CLEARED', 'NOT_CLEARED', 'CORRECTION_REQUIRED')),
    CONSTRAINT ck_jupeb_app_fee_category CHECK (fee_category IS NULL OR fee_category IN ('SCIENCE', 'OTHER'))
);
CREATE UNIQUE INDEX ux_jupeb_exam_no ON jupeb.application (upper(exam_no)) WHERE exam_no IS NOT NULL;
CREATE INDEX ix_jupeb_app_session_state ON jupeb.application (session, state);
CREATE INDEX ix_jupeb_app_combination ON jupeb.application (combination_id);
CREATE INDEX ix_jupeb_app_programme ON jupeb.application (programme_code);
CREATE INDEX ix_jupeb_app_nin ON jupeb.application (nin) WHERE nin IS NOT NULL;
CREATE INDEX ix_jupeb_app_created ON jupeb.application (created_at DESC);
SELECT audit.attach('jupeb.application');
COMMENT ON TABLE jupeb.application IS
  'V339: one JUPEB candidate for one session — the application (its number for life), the biodata, the programme of interest and the combination, '
  'the eligibility and admission decisions, the school fee frozen when first charged, the activation as a JUPEB student, the subject registration, '
  'the official JUPEB examination number (separate from the application number, never overwriting it) and the screening.';
COMMENT ON COLUMN jupeb.application.exam_no IS 'V339: the official JUPEB examination number, issued by the Board and imported or entered by the JUPEB Office; unique; NULL until assigned';

CREATE TABLE jupeb.olevel (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES jupeb.application(id) ON DELETE CASCADE,
    sitting        int NOT NULL CHECK (sitting IN (1, 2)),
    exam_type      text NOT NULL CHECK (exam_type IN ('WAEC', 'NECO', 'NABTEB', 'GCE', 'OTHER')),
    exam_number    text NULL,
    exam_year      int NULL CHECK (exam_year IS NULL OR exam_year BETWEEN 1970 AND 2100),
    subject        text NOT NULL,
    grade          text NOT NULL CHECK (grade IN ('A1', 'B2', 'B3', 'C4', 'C5', 'C6', 'D7', 'E8', 'F9', 'AR')),
    CONSTRAINT uq_jupeb_olevel UNIQUE (application_id, sitting, subject)
);
SELECT audit.attach('jupeb.olevel');

CREATE TABLE jupeb.document (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES jupeb.application(id) ON DELETE CASCADE,
    kind           text NOT NULL REFERENCES jupeb.document_kind(code),
    filename       text NOT NULL,
    content_type   text NOT NULL,
    size_bytes     int NOT NULL CHECK (size_bytes > 0),
    object_id      uuid NULL,
    status         text NOT NULL DEFAULT 'UPLOADED' CHECK (status IN ('UPLOADED', 'UNDER_REVIEW', 'VERIFIED', 'REJECTED', 'REPLACEMENT_REQUIRED')),
    review_note    text NULL,
    reviewed_by    uuid NULL,
    reviewed_at    timestamptz NULL,
    uploaded_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_jupeb_document UNIQUE (application_id, kind)
);
SELECT audit.attach('jupeb.document');
CREATE TABLE jupeb.document_blob (
    document_id uuid PRIMARY KEY REFERENCES jupeb.document(id) ON DELETE CASCADE,
    bytes       bytea NOT NULL
);
SELECT audit.exempt('jupeb.document_blob', 'The bytes of a JUPEB document kept in the database when no object store is configured; the document row on the spine records who uploaded and verified it.');

CREATE TABLE jupeb.fee_reference (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES jupeb.application(id),
    kind           text NOT NULL CHECK (kind IN ('APPLICATION', 'SCHOOL_FIRST', 'SCHOOL_SECOND', 'SCHOOL_FULL')),
    reference      text NOT NULL UNIQUE,
    amount         numeric(12,2) NOT NULL CHECK (amount > 0),
    session        text NOT NULL,
    semester       int NULL CHECK (semester IS NULL OR semester IN (1, 2)),
    expires_at     timestamptz NOT NULL,
    confirmed_at   timestamptz NULL,
    channel        text NULL,
    created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_jupeb_fee_reference_app ON jupeb.fee_reference (application_id, kind);
SELECT audit.attach('jupeb.fee_reference');
COMMENT ON TABLE jupeb.fee_reference IS 'V339: a JUPEB payment, at the amount the Bursary''s rule gave when it was generated (a later fee change never rewrites it), confirmed by the gateway or the Bursary.';

CREATE TABLE jupeb.subject_registration (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES jupeb.application(id),
    subject_id     uuid NOT NULL REFERENCES jupeb.subject(id),
    session        text NOT NULL,
    registered_at  timestamptz NOT NULL DEFAULT now(),
    registered_by  uuid NULL,
    CONSTRAINT uq_jupeb_subject_registration UNIQUE (application_id, subject_id)
);
SELECT audit.attach('jupeb.subject_registration');

CREATE TABLE jupeb.exam_no_change (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES jupeb.application(id),
    old_no         text NULL,
    new_no         text NULL,
    reason         text NULL,
    source         text NOT NULL CHECK (source IN ('DESK', 'IMPORT')),
    batch_ref      text NULL,
    changed_by     uuid NULL,
    changed_office text NULL,
    changed_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_jupeb_exam_no_change ON jupeb.exam_no_change (application_id, changed_at DESC);
SELECT audit.attach('jupeb.exam_no_change');

CREATE TABLE jupeb.result (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES jupeb.application(id),
    subject_id     uuid NOT NULL REFERENCES jupeb.subject(id),
    grade          text NOT NULL CHECK (grade IN ('A', 'B', 'C', 'D', 'E', 'F')),
    points         numeric(5,2) NOT NULL,
    batch_ref      text NULL,
    recorded_by    uuid NULL,
    recorded_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_jupeb_result UNIQUE (application_id, subject_id)
);
SELECT audit.attach('jupeb.result');
CREATE TABLE jupeb.result_change (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES jupeb.application(id),
    subject_id     uuid NOT NULL REFERENCES jupeb.subject(id),
    old_grade      text NULL,
    new_grade      text NOT NULL,
    reason         text NOT NULL,
    batch_ref      text NULL,
    changed_by     uuid NULL,
    changed_at     timestamptz NOT NULL DEFAULT now()
);
SELECT audit.attach('jupeb.result_change');

CREATE TABLE jupeb.import_batch (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref             text NOT NULL UNIQUE,
    kind            text NOT NULL CHECK (kind IN ('EXAM_NUMBERS', 'RESULTS', 'COMBINATIONS')),
    file_name       text NULL,
    rows            int NOT NULL DEFAULT 0,
    applied         int NOT NULL DEFAULT 0,
    result          jsonb NULL,
    imported_by     uuid NOT NULL,
    imported_office text NULL,
    imported_at     timestamptz NOT NULL DEFAULT now()
);
SELECT audit.attach('jupeb.import_batch');

CREATE TABLE jupeb.application_event (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES jupeb.application(id) ON DELETE CASCADE,
    kind           text NOT NULL,
    note           text NULL,
    actor_id       uuid NULL,
    actor_office   text NULL,
    at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_jupeb_event ON jupeb.application_event (application_id, at);
SELECT audit.attach('jupeb.application_event');

-- ── 6 · the rules: the session, the fee in force, the fee a candidate pays ─────────────────────────

CREATE OR REPLACE FUNCTION jupeb.current_session()
RETURNS text LANGUAGE sql STABLE AS $$ SELECT policy.application_session('JUPEB_APPLICATION') $$;

CREATE OR REPLACE FUNCTION jupeb.fee_setting_of(p_session text)
RETURNS jupeb.fee_setting LANGUAGE sql STABLE AS $$
    SELECT * FROM jupeb.fee_setting WHERE session IN (p_session, '*') ORDER BY (session = '*') LIMIT 1
$$;

CREATE OR REPLACE FUNCTION jupeb.setting_of(p_session text)
RETURNS jupeb.setting LANGUAGE sql STABLE AS $$
    SELECT * FROM jupeb.setting WHERE session IN (p_session, '*') ORDER BY (session = '*') LIMIT 1
$$;

CREATE OR REPLACE FUNCTION jupeb.school_fee_amount(p_session text, p_category text, p_indigene boolean)
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT amount FROM jupeb.school_fee WHERE session IN (p_session, '*') AND category = p_category AND indigene = p_indigene
     ORDER BY (session = '*') LIMIT 1
$$;

/* Science or other, by the faculty of the programme of interest, as the Bursary maps it */
CREATE OR REPLACE FUNCTION jupeb.category_of(p_programme text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT fc.category FROM ref.programme p JOIN jupeb.fee_category fc ON fc.faculty_code = p.faculty_code WHERE p.code = p_programme), 'OTHER')
$$;

/* the school fee of a candidate: the category and indigene status, the total (frozen once first charged), the two shares, what is paid */
CREATE OR REPLACE FUNCTION jupeb.school_fees(p_app uuid)
RETURNS TABLE (category text, indigene boolean, total numeric, first_percent numeric, first_amount numeric, second_amount numeric,
               allow_full boolean, first_paid boolean, second_paid boolean, full_paid boolean, paid numeric, outstanding numeric, status text, frozen boolean)
LANGUAGE sql STABLE AS $$
    WITH a AS (SELECT * FROM jupeb.application WHERE id = p_app),
    fs AS (SELECT f.* FROM a CROSS JOIN LATERAL jupeb.fee_setting_of(a.session) f),
    c AS (SELECT coalesce(a.fee_category, jupeb.category_of(a.programme_code)) AS category,
                 coalesce(a.indigene, upper(btrim(coalesce(a.state_of_origin, ''))) = upper(btrim(fs.indigene_state))) AS indigene,
                 a.school_fee_total IS NOT NULL AS frozen, coalesce(a.first_percent, fs.first_percent) AS pct, fs.allow_full,
                 a.session, a.school_fee_total
            FROM a, fs),
    t AS (SELECT c.*, coalesce(c.school_fee_total, jupeb.school_fee_amount(c.session, c.category, c.indigene)) AS total FROM c),
    p AS (SELECT coalesce(bool_or(kind = 'SCHOOL_FIRST' AND confirmed_at IS NOT NULL), false) AS f1,
                 coalesce(bool_or(kind = 'SCHOOL_SECOND' AND confirmed_at IS NOT NULL), false) AS f2,
                 coalesce(bool_or(kind = 'SCHOOL_FULL' AND confirmed_at IS NOT NULL), false) AS ff,
                 coalesce(sum(amount) FILTER (WHERE kind LIKE 'SCHOOL_%' AND confirmed_at IS NOT NULL), 0) AS paid
            FROM jupeb.fee_reference WHERE application_id = p_app)
    SELECT t.category, t.indigene, t.total, t.pct,
           round(t.total * t.pct / 100, 2), t.total - round(t.total * t.pct / 100, 2), t.allow_full,
           p.f1 OR p.ff, p.f2 OR p.ff, p.ff, p.paid, greatest(coalesce(t.total, 0) - p.paid, 0),
           CASE WHEN t.total IS NULL THEN 'NOT_SET' WHEN p.paid >= t.total THEN 'PAID' WHEN p.paid > 0 THEN 'PARTIALLY_PAID' ELSE 'NOT_PAID' END,
           t.frozen
      FROM t, p
$$;
COMMENT ON FUNCTION jupeb.school_fees(uuid) IS
  'V339: the JUPEB school fee of a candidate, computed on the server: the category (the Bursary''s Science faculties, else OTHER) and indigene status '
  '(state of origin against the Bursary''s indigene state), the total for the session (frozen on the candidate when first charged), the first and second '
  'semester shares by the Bursary''s percentage, and what the confirmed payments cover.';

/* five credits including English and Mathematics, in no more than two sittings */
CREATE OR REPLACE FUNCTION jupeb.olevel_check(p_app uuid)
RETURNS TABLE (credits int, english boolean, mathematics boolean, sittings int, ok boolean, reasons text[])
LANGUAGE sql STABLE AS $$
    WITH best AS (
        SELECT upper(btrim(subject)) AS subject, bool_or(grade IN ('A1', 'B2', 'B3', 'C4', 'C5', 'C6')) AS credit
          FROM jupeb.olevel WHERE application_id = p_app GROUP BY upper(btrim(subject))
    ), s AS (SELECT count(DISTINCT sitting)::int AS n FROM jupeb.olevel WHERE application_id = p_app),
    x AS (SELECT count(*) FILTER (WHERE credit)::int AS credits,
                 coalesce(bool_or(credit) FILTER (WHERE subject ~ '^ENGLISH'), false) AS eng,
                 coalesce(bool_or(credit) FILTER (WHERE subject ~ '^(MATHEMATICS|MATHS|GENERAL MATHEMATICS)'), false) AS maths
            FROM best)
    SELECT x.credits, x.eng, x.maths, s.n, x.credits >= 5 AND x.eng AND x.maths AND s.n BETWEEN 1 AND 2,
           array_remove(ARRAY[
               CASE WHEN s.n = 0 THEN 'no O''Level result entered' END,
               CASE WHEN s.n > 0 AND x.credits < 5 THEN 'fewer than five credits (' || x.credits || ')' END,
               CASE WHEN s.n > 0 AND NOT x.eng THEN 'no credit in English Language' END,
               CASE WHEN s.n > 0 AND NOT x.maths THEN 'no credit in Mathematics' END], NULL)
      FROM x, s
$$;

/* what still stands between an application and its submission */
CREATE OR REPLACE FUNCTION jupeb.missing(p_app uuid)
RETURNS text[] LANGUAGE sql STABLE AS $$
    SELECT array_remove(ARRAY[
        CASE WHEN a.fee_confirmed_at IS NULL THEN 'The application fee is not yet paid' END,
        CASE WHEN a.sex IS NULL OR a.date_of_birth IS NULL THEN 'Sex and date of birth' END,
        CASE WHEN a.nin IS NULL THEN 'NIN' END,
        CASE WHEN a.phone IS NULL THEN 'Phone number' END,
        CASE WHEN a.state_of_origin IS NULL OR a.lga IS NULL THEN 'State of origin and LGA' END,
        CASE WHEN a.contact_address IS NULL THEN 'Contact address' END,
        CASE WHEN a.next_of_kin_name IS NULL OR a.next_of_kin_phone IS NULL THEN 'Next of kin and their phone' END,
        CASE WHEN a.programme_code IS NULL THEN 'Programme of interest' END,
        CASE WHEN a.combination_id IS NULL THEN 'Subject combination' END,
        (SELECT 'O''Level: ' || array_to_string(k.reasons, '; ') FROM jupeb.olevel_check(a.id) k WHERE NOT k.ok),
        (SELECT 'Documents: ' || string_agg(dk.label, ', ' ORDER BY dk.ord) FROM jupeb.document_kind dk
          WHERE dk.active AND dk.required
            AND NOT EXISTS (SELECT 1 FROM jupeb.document d WHERE d.application_id = a.id AND d.kind = dk.code AND d.status NOT IN ('REJECTED', 'REPLACEMENT_REQUIRED')))
    ], NULL)
      FROM jupeb.application a WHERE a.id = p_app
$$;

-- ── 7 · the trail and the notices ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION jupeb.app_event(p_app uuid, p_kind text, p_note text)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO jupeb.application_event (application_id, kind, note, actor_id, actor_office)
    VALUES (p_app, p_kind, p_note, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
$$;

/* the candidate told by email (and SMS where a phone is held), from the one outbox */
CREATE OR REPLACE FUNCTION jupeb.tell(p_app uuid, p_subject text, p_body text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE a jupeb.application;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN; END IF;
    PERFORM platform.queue_notice('EMAIL', a.email, p_subject,
        'Dear ' || a.first_name || ',' || E'\n\n' || p_body || E'\n\n' || 'Application number: ' || a.application_no || E'\n'
        || 'JUPEB Office, Rev. Fr. Moses Orshio Adasu University, Makurdi', 'jupeb_application', p_app);
    IF a.phone IS NOT NULL THEN
        PERFORM platform.queue_notice('SMS', a.phone, p_subject, 'MOAUM JUPEB ' || a.application_no || ': ' || p_subject || '. Sign in to the JUPEB portal for details.', 'jupeb_application', p_app);
    END IF;
END $$;

CREATE OR REPLACE FUNCTION jupeb.application_trail()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_fee numeric;
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM jupeb.app_event(NEW.id, 'CREATED', 'Application started for ' || NEW.session);
        v_fee := (jupeb.fee_setting_of(NEW.session)).application_fee;
        PERFORM jupeb.tell(NEW.id, 'Your JUPEB application is started',
            'Your JUPEB application for the ' || NEW.session || ' session is started and numbered. Sign in to the JUPEB portal with your email or application number, '
            || 'pay the application fee of ₦' || coalesce(to_char(v_fee, 'FM999,999,990'), '') || ', complete your biodata, enter your O''Level results, upload your documents and submit.');
        RETURN NEW;
    END IF;
    IF NEW.state IS DISTINCT FROM OLD.state THEN
        PERFORM jupeb.app_event(NEW.id, NEW.state, CASE NEW.state
            WHEN 'SUBMITTED'    THEN CASE WHEN OLD.state = 'RETURNED' THEN 'Corrected and resubmitted' ELSE 'Application submitted' END
            WHEN 'RETURNED'     THEN 'Returned for correction — ' || coalesce(NEW.return_note, '')
            WHEN 'ELIGIBLE'     THEN 'Found eligible' || coalesce(' — ' || NEW.eligibility_note, '')
            WHEN 'INELIGIBLE'   THEN 'Found not eligible — ' || coalesce(NEW.eligibility_note, '')
            WHEN 'ADMITTED'     THEN 'Admitted · ' || coalesce(NEW.admission_ref, '') || coalesce(' — ' || NEW.admission_note, '')
            WHEN 'NOT_ADMITTED' THEN 'Not admitted' || coalesce(' — ' || NEW.admission_note, '')
            WHEN 'PENDING'      THEN 'Admission decision pending' || coalesce(' — ' || NEW.admission_note, '')
            WHEN 'STUDENT'      THEN 'Activated as a JUPEB student'
            WHEN 'COMPLETED'    THEN 'Results published'
            ELSE NEW.state END);
        IF NEW.state = 'SUBMITTED' THEN
            PERFORM jupeb.tell(NEW.id, 'Your JUPEB application is submitted', 'Your application is submitted to the JUPEB Office for review. Follow it on the JUPEB portal.');
        ELSIF NEW.state = 'RETURNED' THEN
            PERFORM jupeb.tell(NEW.id, 'Your JUPEB application needs a correction', 'The JUPEB Office returned your application for correction: '
                || coalesce(NEW.return_note, '') || ' Sign in, make the correction and submit it again.');
        ELSIF NEW.state IN ('ADMITTED', 'NOT_ADMITTED') THEN
            PERFORM jupeb.tell(NEW.id, 'Your JUPEB admission decision is available', 'The JUPEB Office has decided on your application. Sign in to the JUPEB portal to read the decision.'
                || CASE WHEN NEW.state = 'ADMITTED' THEN ' Your admission letter and your school fees are there.' ELSE '' END);
        ELSIF NEW.state = 'STUDENT' THEN
            PERFORM jupeb.tell(NEW.id, 'You are a JUPEB student', 'Your school fee payment is confirmed and your JUPEB studentship is active. Sign in to register your three subjects.');
        ELSIF NEW.state = 'COMPLETED' THEN
            PERFORM jupeb.tell(NEW.id, 'Your JUPEB results are published', 'Your JUPEB results are published on the JUPEB portal.');
        END IF;
    END IF;
    IF NEW.fee_confirmed_at IS NOT NULL AND OLD.fee_confirmed_at IS NULL THEN
        PERFORM jupeb.app_event(NEW.id, 'APPLICATION_FEE_CONFIRMED', 'Application fee confirmed');
        PERFORM jupeb.tell(NEW.id, 'Your JUPEB application fee is confirmed', 'Your application fee is confirmed. Complete your biodata, O''Level results and documents, then submit.');
    END IF;
    IF NEW.subjects_registered_at IS NOT NULL AND OLD.subjects_registered_at IS NULL THEN
        PERFORM jupeb.app_event(NEW.id, 'SUBJECTS_REGISTERED', 'The three subjects of the combination registered');
    END IF;
    IF NEW.exam_no IS DISTINCT FROM OLD.exam_no AND NEW.exam_no IS NOT NULL THEN
        PERFORM jupeb.app_event(NEW.id, 'EXAM_NO_ASSIGNED', 'JUPEB examination number ' || NEW.exam_no || CASE WHEN OLD.exam_no IS NOT NULL THEN ' (was ' || OLD.exam_no || ')' ELSE '' END);
        PERFORM jupeb.tell(NEW.id, 'Your JUPEB examination number is assigned', 'Your official JUPEB examination number is ' || NEW.exam_no || '. It is on your JUPEB portal.');
    END IF;
    IF NEW.screening_state IS DISTINCT FROM OLD.screening_state AND NEW.screening_state IS NOT NULL THEN
        PERFORM jupeb.app_event(NEW.id, 'SCREENING_' || NEW.screening_state, coalesce(NEW.screening_reason, 'Screening ' || lower(replace(NEW.screening_state, '_', ' '))));
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END $$;
CREATE TRIGGER trg_jupeb_application_trail_ins AFTER INSERT ON jupeb.application FOR EACH ROW EXECUTE FUNCTION jupeb.application_trail();
CREATE TRIGGER trg_jupeb_application_trail_upd BEFORE UPDATE ON jupeb.application FOR EACH ROW EXECUTE FUNCTION jupeb.application_trail();

-- ── 8 · applying, paying, submitting ──────────────────────────────────────────────────────────────

/* the fee reference of a kind, at the amount the Bursary's rule gives now; a live unpaid one of the same amount is reused */
CREATE OR REPLACE FUNCTION jupeb.new_fee_reference(p_app uuid, p_kind text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; fs jupeb.fee_setting; st jupeb.setting; sf record; v_amt numeric; v_ref text; v_sem int;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such JUPEB application' USING ERRCODE = '23503'; END IF;
    fs := jupeb.fee_setting_of(a.session);
    IF p_kind = 'APPLICATION' THEN
        IF a.fee_confirmed_at IS NOT NULL THEN RAISE EXCEPTION 'JUPEB_FEE_PAID: the application fee is already paid' USING ERRCODE = '23514'; END IF;
        v_amt := fs.application_fee;
    ELSIF p_kind IN ('SCHOOL_FIRST', 'SCHOOL_SECOND', 'SCHOOL_FULL') THEN
        IF a.state NOT IN ('ADMITTED', 'STUDENT', 'COMPLETED') THEN
            RAISE EXCEPTION 'JUPEB_FEES_NOT_YET: school fees are paid once you are admitted' USING ERRCODE = '23514';
        END IF;
        st := jupeb.setting_of(a.session);
        IF st.screening_required AND coalesce(a.screening_state, '') <> 'CLEARED' AND a.state = 'ADMITTED' THEN
            RAISE EXCEPTION 'JUPEB_SCREENING_FIRST: school fees open once you are cleared at screening' USING ERRCODE = '23514',
                HINT = 'Attend the screening shown on your JUPEB portal.';
        END IF;
        -- the fee is frozen on the candidate the first time it is charged: a later change by the Bursary does not rewrite it
        IF a.school_fee_total IS NULL THEN
            SELECT * INTO sf FROM jupeb.school_fees(p_app);
            IF sf.total IS NULL THEN
                RAISE EXCEPTION 'JUPEB_FEE_NOT_SET: the Bursary has not stated the JUPEB school fee for %', a.session USING ERRCODE = '23514';
            END IF;
            UPDATE jupeb.application SET school_fee_total = sf.total, fee_category = sf.category, indigene = sf.indigene, first_percent = sf.first_percent
             WHERE id = p_app;
        END IF;
        SELECT * INTO sf FROM jupeb.school_fees(p_app);
        IF p_kind = 'SCHOOL_FIRST' THEN
            IF sf.first_paid THEN RAISE EXCEPTION 'JUPEB_FEE_PAID: the first semester''s share is already paid' USING ERRCODE = '23514'; END IF;
            v_amt := sf.first_amount; v_sem := 1;
        ELSIF p_kind = 'SCHOOL_SECOND' THEN
            IF NOT sf.first_paid THEN RAISE EXCEPTION 'JUPEB_FEE_ORDER: the first semester''s share is paid first' USING ERRCODE = '23514'; END IF;
            IF sf.second_paid THEN RAISE EXCEPTION 'JUPEB_FEE_PAID: the second semester''s share is already paid' USING ERRCODE = '23514'; END IF;
            v_amt := sf.second_amount; v_sem := 2;
        ELSE
            IF NOT sf.allow_full THEN RAISE EXCEPTION 'JUPEB_FULL_NOT_ALLOWED: the Bursary takes the school fee in two instalments' USING ERRCODE = '23514'; END IF;
            IF sf.paid > 0 THEN RAISE EXCEPTION 'JUPEB_FEE_ORDER: part of the fee is paid; pay the remaining instalment' USING ERRCODE = '23514'; END IF;
            v_amt := sf.total;
        END IF;
    ELSE
        RAISE EXCEPTION 'JUPEB_FEE_KIND: unknown JUPEB fee %', p_kind USING ERRCODE = '23514';
    END IF;
    IF v_amt IS NULL OR v_amt <= 0 THEN RAISE EXCEPTION 'JUPEB_FEE_NOT_SET: the Bursary has not stated this fee' USING ERRCODE = '23514'; END IF;
    SELECT fr.reference INTO v_ref FROM jupeb.fee_reference fr
     WHERE fr.application_id = p_app AND fr.kind = p_kind AND fr.confirmed_at IS NULL AND fr.expires_at > now() AND fr.amount = v_amt
     ORDER BY fr.created_at DESC LIMIT 1;
    IF v_ref IS NOT NULL THEN RETURN v_ref; END IF;
    v_ref := 'MOAUM-JUPEB' || CASE p_kind WHEN 'APPLICATION' THEN 'APP' WHEN 'SCHOOL_FIRST' THEN 'SF1' WHEN 'SCHOOL_SECOND' THEN 'SF2' ELSE 'SFF' END
             || '-' || lpad(platform.next_number('JUPEB_FEEREF', 'UNIVERSITY', a.session)::text, 6, '0');
    INSERT INTO jupeb.fee_reference (application_id, kind, reference, amount, session, semester, expires_at)
    VALUES (p_app, p_kind, v_ref, v_amt, a.session, v_sem, now() + interval '24 hours');
    RETURN v_ref;
END $$;

/* a JUPEB student is activated when the Bursary's threshold is met: the first instalment, or the whole fee */
CREATE OR REPLACE FUNCTION jupeb.activate_if_due(p_app uuid)
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; fs jupeb.fee_setting; sf record;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.state <> 'ADMITTED' THEN RETURN false; END IF;
    fs := jupeb.fee_setting_of(a.session);
    SELECT * INTO sf FROM jupeb.school_fees(p_app);
    IF (fs.activation = 'FIRST_INSTALMENT' AND sf.first_paid) OR (fs.activation = 'FULL' AND sf.total IS NOT NULL AND sf.paid >= sf.total) THEN
        UPDATE jupeb.application SET state = 'STUDENT', activated_at = now() WHERE id = p_app;
        RETURN true;
    END IF;
    RETURN false;
END $$;

/* the one act a gateway or the Bursary performs: a JUPEB payment confirmed (idempotent) */
CREATE OR REPLACE FUNCTION jupeb.confirm_fee(p_reference text, p_channel text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE fr jupeb.fee_reference;
BEGIN
    UPDATE jupeb.fee_reference SET confirmed_at = now(), channel = coalesce(nullif(btrim(coalesce(p_channel, '')), ''), 'bank')
     WHERE upper(reference) = upper(btrim(coalesce(p_reference, ''))) AND confirmed_at IS NULL
    RETURNING * INTO fr;
    IF fr.id IS NULL THEN RETURN 'already confirmed'; END IF;
    IF fr.kind = 'APPLICATION' THEN
        UPDATE jupeb.application SET fee_confirmed_at = coalesce(fee_confirmed_at, now()) WHERE id = fr.application_id;
    ELSE
        PERFORM jupeb.app_event(fr.application_id, 'SCHOOL_FEE_CONFIRMED', CASE fr.kind WHEN 'SCHOOL_FIRST' THEN 'First semester school fee' WHEN 'SCHOOL_SECOND' THEN 'Second semester school fee' ELSE 'Full school fee' END
            || ' confirmed · ₦' || to_char(fr.amount, 'FM999,999,990.00') || ' · ' || fr.reference);
        PERFORM jupeb.tell(fr.application_id, 'Your JUPEB school fee payment is confirmed', 'We confirm your payment of ₦' || to_char(fr.amount, 'FM999,999,990.00') || ' (' || fr.reference || '). Your receipt is on the JUPEB portal.');
        PERFORM jupeb.activate_if_due(fr.application_id);
    END IF;
    RETURN 'confirmed';
END $$;

/* the public application: the account, the application numbered for life, and the application fee reference */
CREATE OR REPLACE FUNCTION jupeb.apply(p jsonb)
RETURNS TABLE (application_id uuid, application_no text, reference text, amount numeric)
LANGUAGE plpgsql AS $$
DECLARE v_session text := jupeb.current_session(); v_acc uuid; v_app uuid; v_no text; v_ref text; st jupeb.setting; v_prog text; v_comb uuid;
BEGIN
    IF v_session IS NULL THEN RAISE EXCEPTION 'JUPEB_NO_SESSION: no academic session is on the calendar' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM jupeb.account x WHERE lower(x.email) = lower(btrim(p->>'email'))) THEN
        RAISE EXCEPTION 'JUPEB_APP_EXISTS: a JUPEB application already exists for this email' USING ERRCODE = '23514',
            HINT = 'Sign in with this email to continue it; forgotten your password? Reset it from the sign-in page.';
    END IF;
    SELECT g.code INTO v_prog FROM ref.programme g
     WHERE upper(g.code) = upper(btrim(coalesce(p->>'programme', ''))) AND NOT coalesce(g.archived, false) AND g.category = 'UNDER GRADUATE';
    IF v_prog IS NULL THEN RAISE EXCEPTION 'JUPEB_PROGRAMME: choose the undergraduate programme you intend to study' USING ERRCODE = '23514'; END IF;
    SELECT c.id INTO v_comb FROM jupeb.combination c WHERE (c.id::text = p->>'combination' OR upper(c.code) = upper(btrim(coalesce(p->>'combination', '')))) AND c.active;
    IF v_comb IS NULL THEN RAISE EXCEPTION 'JUPEB_COMBINATION: choose one of the approved subject combinations' USING ERRCODE = '23514'; END IF;
    INSERT INTO jupeb.account (email, password_hash) VALUES (lower(btrim(p->>'email')), p->>'passwordHash') RETURNING id INTO v_acc;
    st := jupeb.setting_of(v_session);
    v_no := st.application_prefix || '/' || substr(v_session, 1, 4) || '/' || lpad(platform.next_number('JUPEB_APPLICATION', 'UNIVERSITY', v_session)::text, 6, '0');
    INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, middle_name, sex, date_of_birth, nin, email, phone, programme_code, combination_id)
    VALUES (v_acc, v_session, v_no, upper(btrim(p->>'surname')), btrim(p->>'firstName'), nullif(btrim(coalesce(p->>'middleName', '')), ''),
            nullif(upper(left(btrim(coalesce(p->>'sex', '')), 1)), ''),
            CASE WHEN coalesce(p->>'dob', '') ~ '^\d{4}-\d{2}-\d{2}$' THEN (p->>'dob')::date END,
            nullif(btrim(coalesce(p->>'nin', '')), ''), lower(btrim(p->>'email')), nullif(btrim(coalesce(p->>'phone', '')), ''), v_prog, v_comb)
    RETURNING id INTO v_app;
    v_ref := jupeb.new_fee_reference(v_app, 'APPLICATION');
    RETURN QUERY SELECT v_app, v_no, v_ref, (SELECT fr.amount FROM jupeb.fee_reference fr WHERE fr.reference = v_ref);
END $$;

CREATE OR REPLACE FUNCTION jupeb.submit(p_app uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; v_missing text[];
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.state NOT IN ('DRAFT', 'RETURNED') THEN RAISE EXCEPTION 'JUPEB_NOT_EDITABLE: the application is already with the JUPEB Office' USING ERRCODE = '23514'; END IF;
    v_missing := jupeb.missing(p_app);
    IF cardinality(v_missing) > 0 THEN
        RAISE EXCEPTION 'JUPEB_INCOMPLETE: %', array_to_string(v_missing, '; ') USING ERRCODE = '23514', HINT = 'Complete each item on the JUPEB portal, then submit.';
    END IF;
    UPDATE jupeb.application SET state = 'SUBMITTED', submitted_at = coalesce(submitted_at, now()), return_note = CASE WHEN a.state = 'RETURNED' THEN return_note END WHERE id = p_app;
END $$;

-- ── 9 · the JUPEB Office's decisions ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION jupeb.decide_eligibility(p_app uuid, p_eligible boolean, p_note text, p_actor uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE a jupeb.application;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such JUPEB application' USING ERRCODE = '23503'; END IF;
    IF a.state NOT IN ('SUBMITTED', 'ELIGIBLE', 'INELIGIBLE') THEN
        RAISE EXCEPTION 'JUPEB_STATE: eligibility is decided on a submitted application before admission; this one is %', lower(a.state) USING ERRCODE = '23514';
    END IF;
    IF NOT p_eligible AND nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN
        RAISE EXCEPTION 'JUPEB_REASON: say why the application is not eligible' USING ERRCODE = '23514';
    END IF;
    UPDATE jupeb.application SET state = CASE WHEN p_eligible THEN 'ELIGIBLE' ELSE 'INELIGIBLE' END,
           eligibility_note = nullif(btrim(coalesce(p_note, '')), ''), eligibility_decided_at = now(), eligibility_decided_by = p_actor
     WHERE id = p_app;
END $$;

CREATE OR REPLACE FUNCTION jupeb.return_application(p_app uuid, p_note text, p_actor uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE a jupeb.application;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.state NOT IN ('SUBMITTED', 'ELIGIBLE', 'INELIGIBLE') THEN
        RAISE EXCEPTION 'JUPEB_STATE: an application is returned for correction before admission; this one is %', lower(coalesce(a.state, 'unknown')) USING ERRCODE = '23514';
    END IF;
    IF nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN RAISE EXCEPTION 'JUPEB_REASON: say what the applicant must correct' USING ERRCODE = '23514'; END IF;
    UPDATE jupeb.application SET state = 'RETURNED', return_note = btrim(p_note), returned_at = now(), returned_by = p_actor WHERE id = p_app;
END $$;

CREATE OR REPLACE FUNCTION jupeb.decide_admission(p_app uuid, p_decision text, p_note text, p_actor uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; v text := upper(btrim(coalesce(p_decision, ''))); sf record; st jupeb.setting;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such JUPEB application' USING ERRCODE = '23503'; END IF;
    IF v NOT IN ('ADMITTED', 'NOT_ADMITTED', 'PENDING') THEN RAISE EXCEPTION 'JUPEB_DECISION: admitted, not admitted or pending' USING ERRCODE = '23514'; END IF;
    IF a.state NOT IN ('ELIGIBLE', 'PENDING', 'NOT_ADMITTED', 'ADMITTED') THEN
        RAISE EXCEPTION 'JUPEB_STATE: admission is decided on an eligible application; this one is %', lower(a.state) USING ERRCODE = '23514',
            HINT = 'Mark the application eligible first.';
    END IF;
    IF a.state = 'ADMITTED' AND v <> 'ADMITTED' THEN
        SELECT * INTO sf FROM jupeb.school_fees(p_app);
        IF sf.paid > 0 THEN RAISE EXCEPTION 'JUPEB_ADMISSION_PAID: a school fee is paid against this admission; it is not withdrawn here' USING ERRCODE = '23514'; END IF;
    END IF;
    IF v = a.state THEN RETURN v; END IF;
    st := jupeb.setting_of(a.session);
    UPDATE jupeb.application
       SET state = v, admission_note = nullif(btrim(coalesce(p_note, '')), ''), admission_decided_at = now(), admission_decided_by = p_actor,
           admission_ref = CASE WHEN v = 'ADMITTED' AND admission_ref IS NULL
                                THEN 'JUPEB/ADM/' || substr(a.session, 1, 4) || '/' || lpad(platform.next_number('JUPEB_ADMISSION', 'UNIVERSITY', a.session)::text, 5, '0')
                                ELSE admission_ref END,
           screening_state = CASE WHEN v = 'ADMITTED' AND st.screening_required AND screening_state IS NULL THEN 'PENDING' ELSE screening_state END,
           screening_venue = CASE WHEN v = 'ADMITTED' AND st.screening_required AND screening_venue IS NULL THEN st.screening_venue ELSE screening_venue END
     WHERE id = p_app;
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION jupeb.decide_screening(p_app uuid, p_decision text, p_reason text, p_venue text, p_at timestamptz, p_actor uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; v text := upper(btrim(coalesce(p_decision, '')));
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.state NOT IN ('ADMITTED', 'STUDENT') THEN RAISE EXCEPTION 'JUPEB_STATE: screening follows admission' USING ERRCODE = '23514'; END IF;
    IF v NOT IN ('SCHEDULED', 'IN_PROGRESS', 'CLEARED', 'NOT_CLEARED', 'CORRECTION_REQUIRED') THEN RAISE EXCEPTION 'JUPEB_DECISION: unknown screening decision' USING ERRCODE = '23514'; END IF;
    IF v IN ('NOT_CLEARED', 'CORRECTION_REQUIRED') AND nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'JUPEB_REASON: say why, and what the candidate must do' USING ERRCODE = '23514';
    END IF;
    UPDATE jupeb.application SET screening_state = v, screening_reason = nullif(btrim(coalesce(p_reason, '')), ''),
           screening_venue = coalesce(nullif(btrim(coalesce(p_venue, '')), ''), screening_venue), screening_at = coalesce(p_at, screening_at),
           screening_decided_at = now(), screening_decided_by = p_actor
     WHERE id = p_app;
    RETURN v;
END $$;

-- ── 10 · the student's subjects, the examination number, the results ──────────────────────────────

CREATE OR REPLACE FUNCTION jupeb.register_subjects(p_app uuid, p_actor uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; c jupeb.combination; n int;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.state NOT IN ('STUDENT') THEN RAISE EXCEPTION 'JUPEB_NOT_STUDENT: subjects are registered by an active JUPEB student' USING ERRCODE = '23514',
        HINT = 'Pay the school fee the Bursary requires for activation first.'; END IF;
    IF a.subjects_registered_at IS NOT NULL THEN RETURN 0; END IF;
    SELECT * INTO c FROM jupeb.combination WHERE id = a.combination_id;
    IF c.id IS NULL THEN RAISE EXCEPTION 'JUPEB_COMBINATION: no combination is on the record' USING ERRCODE = '23514'; END IF;
    INSERT INTO jupeb.subject_registration (application_id, subject_id, session, registered_by)
    SELECT p_app, s, a.session, p_actor FROM unnest(ARRAY[c.subject1, c.subject2, c.subject3]) s
    ON CONFLICT (application_id, subject_id) DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    UPDATE jupeb.application SET subjects_registered_at = now() WHERE id = p_app;
    RETURN n;
END $$;

/* the official examination number: unique, never silently overwritten — a correction states its reason */
CREATE OR REPLACE FUNCTION jupeb.set_exam_no(p_app uuid, p_no text, p_reason text, p_source text, p_batch text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; v text := upper(regexp_replace(btrim(coalesce(p_no, '')), '\s+', '', 'g'));
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such JUPEB candidate' USING ERRCODE = '23503'; END IF;
    IF v !~ '^[A-Z0-9][A-Z0-9/-]{3,29}$' THEN RAISE EXCEPTION 'JUPEB_EXAM_NO_FORMAT: % is not an examination number', p_no USING ERRCODE = '23514'; END IF;
    IF a.state NOT IN ('STUDENT', 'COMPLETED') OR a.subjects_registered_at IS NULL THEN
        RAISE EXCEPTION 'JUPEB_NOT_CANDIDATE: an examination number goes to an active student whose subjects are registered' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM jupeb.application x WHERE upper(x.exam_no) = v AND x.id <> p_app) THEN
        RAISE EXCEPTION 'JUPEB_EXAM_NO_TAKEN: % is already another candidate''s examination number', v USING ERRCODE = '23514';
    END IF;
    IF a.exam_no IS NOT NULL AND upper(a.exam_no) = v THEN RETURN 'UNCHANGED'; END IF;
    IF a.exam_no IS NOT NULL AND nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'JUPEB_EXAM_NO_REASON: % already holds %; a correction states its reason', a.application_no, a.exam_no USING ERRCODE = '23514';
    END IF;
    INSERT INTO jupeb.exam_no_change (application_id, old_no, new_no, reason, source, batch_ref, changed_by, changed_office)
    VALUES (p_app, a.exam_no, v, nullif(btrim(coalesce(p_reason, '')), ''), p_source, p_batch,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
    UPDATE jupeb.application SET exam_no = v, exam_no_assigned_at = now() WHERE id = p_app;
    RETURN CASE WHEN a.exam_no IS NULL THEN 'ASSIGNED' ELSE 'CORRECTED' END;
END $$;

CREATE OR REPLACE FUNCTION jupeb.grade_points(p_grade text)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE upper(btrim(p_grade)) WHEN 'A' THEN 5 WHEN 'B' THEN 4 WHEN 'C' THEN 3 WHEN 'D' THEN 2 WHEN 'E' THEN 1 WHEN 'F' THEN 0 END::numeric
$$;

/* the results: each of the three registered subjects graded by the Board, imported in one batch; nothing is shown before publication */
CREATE OR REPLACE FUNCTION jupeb.results_published(p_session text)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM jupeb.setting WHERE session = p_session AND results_published_at IS NOT NULL)
$$;

-- ── 11 · the imports: judged whole before anything is written ──────────────────────────────────────

CREATE OR REPLACE FUNCTION jupeb.batch_ref(p_kind text)
RETURNS text LANGUAGE sql AS $$
    SELECT 'JUPEB-' || CASE p_kind WHEN 'EXAM_NUMBERS' THEN 'EXAMNO' WHEN 'RESULTS' THEN 'RESULT' ELSE 'COMB' END || '-'
           || to_char(now(), 'YYYY') || '-' || lpad(platform.next_number('JUPEB_' || p_kind, 'UNIVERSITY', to_char(now(), 'YYYY'))::text, 5, '0')
$$;

/* the official examination numbers JUPEB issued, matched to candidates by APPLICATION NUMBER — never by name alone.
   A row whose surname disagrees, or that would change a number already held without a stated reason, needs review and is
   not applied; an invalid row (unknown application, a number another candidate holds, a number twice in the file) stops
   the whole commit. Returns the judgement of every row, and, on commit, the batch reference. */
CREATE OR REPLACE FUNCTION jupeb.import_exam_numbers(p_rows jsonb, p_commit boolean, p_file text, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_out jsonb := '[]'::jsonb; a jupeb.application; v_no text; v_app text; v_status text; v_msg text;
        n_invalid int := 0; n_review int := 0; n_new int := 0; n_fix int := 0; n_same int := 0; v_ref text; seen_no text[] := '{}'; seen_app text[] := '{}'; applied int := 0;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('jupeb.exam_numbers'));
    FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) LOOP
        v_app := upper(btrim(coalesce(r->>'applicationNo', '')));
        v_no := upper(regexp_replace(btrim(coalesce(r->>'examNo', '')), '\s+', '', 'g'));
        v_status := NULL; v_msg := NULL;
        SELECT * INTO a FROM jupeb.application x WHERE upper(x.application_no) = v_app;
        IF v_app = '' THEN v_status := 'INVALID'; v_msg := 'No application number';
        ELSIF v_no = '' THEN v_status := 'INVALID'; v_msg := 'No examination number';
        ELSIF v_no !~ '^[A-Z0-9][A-Z0-9/-]{3,29}$' THEN v_status := 'INVALID'; v_msg := v_no || ' is not an examination number';
        ELSIF a.id IS NULL THEN v_status := 'INVALID'; v_msg := 'No JUPEB application ' || v_app;
        ELSIF v_app = ANY(seen_app) THEN v_status := 'INVALID'; v_msg := 'The application appears twice in the file';
        ELSIF v_no = ANY(seen_no) THEN v_status := 'INVALID'; v_msg := v_no || ' appears twice in the file';
        ELSIF a.state NOT IN ('STUDENT', 'COMPLETED') OR a.subjects_registered_at IS NULL THEN
            v_status := 'INVALID'; v_msg := 'Not an active JUPEB student with registered subjects (' || lower(a.state) || ')';
        ELSIF EXISTS (SELECT 1 FROM jupeb.application x WHERE upper(x.exam_no) = v_no AND x.id <> a.id) THEN
            v_status := 'INVALID'; v_msg := v_no || ' is already another candidate''s examination number';
        ELSIF nullif(btrim(coalesce(r->>'surname', '')), '') IS NOT NULL AND upper(btrim(r->>'surname')) <> upper(a.surname) THEN
            v_status := 'REQUIRES_REVIEW'; v_msg := 'The surname in the file (' || btrim(r->>'surname') || ') is not the applicant''s (' || a.surname || ')';
        ELSIF a.exam_no IS NOT NULL AND upper(a.exam_no) = v_no THEN v_status := 'UNCHANGED'; v_msg := 'Already holds this number';
        ELSIF a.exam_no IS NOT NULL AND nullif(btrim(coalesce(r->>'reason', '')), '') IS NULL THEN
            v_status := 'REQUIRES_REVIEW'; v_msg := 'Already holds ' || a.exam_no || '; a correction states its reason';
        ELSIF a.exam_no IS NOT NULL THEN v_status := 'CORRECTION'; v_msg := a.exam_no || ' → ' || v_no;
        ELSE v_status := 'NEW'; v_msg := 'Assign ' || v_no;
        END IF;
        IF v_app <> '' THEN seen_app := seen_app || v_app; END IF;
        IF v_no <> '' THEN seen_no := seen_no || v_no; END IF;
        CASE v_status WHEN 'INVALID' THEN n_invalid := n_invalid + 1; WHEN 'REQUIRES_REVIEW' THEN n_review := n_review + 1;
                      WHEN 'NEW' THEN n_new := n_new + 1; WHEN 'CORRECTION' THEN n_fix := n_fix + 1; ELSE n_same := n_same + 1; END CASE;
        v_out := v_out || jsonb_build_object('row', r->'row', 'applicationNo', v_app, 'examNo', v_no, 'status', v_status, 'message', v_msg,
                                         'applicationId', a.id, 'name', CASE WHEN a.id IS NOT NULL THEN a.surname || ', ' || a.first_name END,
                                         'currentNo', a.exam_no, 'reason', nullif(btrim(coalesce(r->>'reason', '')), ''));
    END LOOP;
    IF p_commit THEN
        IF jsonb_array_length(v_out) = 0 THEN RAISE EXCEPTION 'JUPEB_IMPORT_EMPTY: the file has no rows' USING ERRCODE = '23514'; END IF;
        IF n_invalid > 0 THEN
            RAISE EXCEPTION 'JUPEB_IMPORT_INVALID: % row(s) are invalid; nothing was written', n_invalid USING ERRCODE = '23514', HINT = 'Correct the rows the preview lists and upload again.';
        END IF;
        v_ref := jupeb.batch_ref('EXAM_NUMBERS');
        FOR r IN SELECT * FROM jsonb_array_elements(v_out) LOOP
            IF r->>'status' IN ('NEW', 'CORRECTION') THEN
                PERFORM jupeb.set_exam_no((r->>'applicationId')::uuid, r->>'examNo', coalesce(r->>'reason', 'Imported'), 'IMPORT', v_ref);
                applied := applied + 1;
            END IF;
        END LOOP;
        INSERT INTO jupeb.import_batch (ref, kind, file_name, rows, applied, result, imported_by, imported_office)
        VALUES (v_ref, 'EXAM_NUMBERS', p_file, jsonb_array_length(v_out), applied,
                jsonb_build_object('new', n_new, 'corrections', n_fix, 'unchanged', n_same, 'review', n_review,
                                   'reviewRows', (SELECT coalesce(jsonb_agg(x), '[]'::jsonb) FROM jsonb_array_elements(v_out) x WHERE x->>'status' = 'REQUIRES_REVIEW')),
                p_actor, nullif(current_setting('moaum.actor_office', true), ''));
    END IF;
    RETURN jsonb_build_object('rows', v_out, 'invalid', n_invalid, 'review', n_review, 'new', n_new, 'corrections', n_fix, 'unchanged', n_same,
                              'committed', p_commit, 'ref', v_ref, 'applied', applied);
END $$;

/* the Board's grades: by examination number (or application number), one row per subject the candidate registered */
CREATE OR REPLACE FUNCTION jupeb.import_results(p_rows jsonb, p_commit boolean, p_file text, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_out jsonb := '[]'::jsonb; a jupeb.application; s jupeb.subject; v_key text; v_grade text; v_old text; v_status text; v_msg text; v_pair text;
        n_invalid int := 0; n_new int := 0; n_fix int := 0; n_same int := 0; v_ref text; seen text[] := '{}'; applied int := 0;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('jupeb.results'));
    FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) LOOP
        v_key := upper(regexp_replace(btrim(coalesce(nullif(r->>'examNo', ''), r->>'applicationNo', '')), '\s+', '', 'g'));
        v_grade := upper(btrim(coalesce(r->>'grade', '')));
        v_status := NULL; v_msg := NULL; v_old := NULL;
        SELECT * INTO a FROM jupeb.application x WHERE upper(x.exam_no) = v_key OR upper(x.application_no) = v_key ORDER BY (upper(x.exam_no) = v_key) DESC NULLS LAST LIMIT 1;
        SELECT * INTO s FROM jupeb.subject x WHERE upper(x.code) = upper(btrim(coalesce(r->>'subject', ''))) OR upper(x.title) = upper(btrim(coalesce(r->>'subject', ''))) LIMIT 1;
        v_pair := coalesce(a.id::text, v_key) || '|' || coalesce(s.id::text, upper(btrim(coalesce(r->>'subject', ''))));
        IF v_key = '' THEN v_status := 'INVALID'; v_msg := 'No examination or application number';
        ELSIF a.id IS NULL THEN v_status := 'INVALID'; v_msg := 'No JUPEB candidate ' || v_key;
        ELSIF s.id IS NULL THEN v_status := 'INVALID'; v_msg := 'No JUPEB subject ' || coalesce(r->>'subject', '');
        ELSIF NOT EXISTS (SELECT 1 FROM jupeb.subject_registration sr WHERE sr.application_id = a.id AND sr.subject_id = s.id) THEN
            v_status := 'INVALID'; v_msg := s.title || ' is not one of the candidate''s registered subjects';
        ELSIF v_grade NOT IN ('A', 'B', 'C', 'D', 'E', 'F') THEN v_status := 'INVALID'; v_msg := 'The grade is A to F, not ' || coalesce(nullif(v_grade, ''), 'blank');
        ELSIF v_pair = ANY(seen) THEN v_status := 'INVALID'; v_msg := 'The candidate''s ' || s.title || ' appears twice in the file';
        ELSE
            SELECT grade INTO v_old FROM jupeb.result WHERE application_id = a.id AND subject_id = s.id;
            IF v_old IS NULL THEN v_status := 'NEW'; v_msg := s.title || ': ' || v_grade;
            ELSIF v_old = v_grade THEN v_status := 'UNCHANGED'; v_msg := s.title || ' already ' || v_grade;
            ELSIF nullif(btrim(coalesce(r->>'reason', '')), '') IS NULL THEN v_status := 'INVALID'; v_msg := s.title || ' is already ' || v_old || '; a correction states its reason';
            ELSE v_status := 'CORRECTION'; v_msg := s.title || ': ' || v_old || ' → ' || v_grade;
            END IF;
        END IF;
        seen := seen || v_pair;
        CASE v_status WHEN 'INVALID' THEN n_invalid := n_invalid + 1; WHEN 'NEW' THEN n_new := n_new + 1; WHEN 'CORRECTION' THEN n_fix := n_fix + 1; ELSE n_same := n_same + 1; END CASE;
        v_out := v_out || jsonb_build_object('row', r->'row', 'key', v_key, 'subject', coalesce(s.code, r->>'subject'), 'grade', v_grade, 'status', v_status, 'message', v_msg,
                                         'applicationId', a.id, 'subjectId', s.id, 'applicationNo', a.application_no, 'examNo', a.exam_no,
                                         'name', CASE WHEN a.id IS NOT NULL THEN a.surname || ', ' || a.first_name END, 'reason', nullif(btrim(coalesce(r->>'reason', '')), ''));
    END LOOP;
    IF p_commit THEN
        IF jsonb_array_length(v_out) = 0 THEN RAISE EXCEPTION 'JUPEB_IMPORT_EMPTY: the file has no rows' USING ERRCODE = '23514'; END IF;
        IF n_invalid > 0 THEN
            RAISE EXCEPTION 'JUPEB_IMPORT_INVALID: % row(s) are invalid; nothing was written', n_invalid USING ERRCODE = '23514', HINT = 'Correct the rows the preview lists and upload again.';
        END IF;
        v_ref := jupeb.batch_ref('RESULTS');
        FOR r IN SELECT * FROM jsonb_array_elements(v_out) LOOP
            IF r->>'status' = 'NEW' THEN
                INSERT INTO jupeb.result (application_id, subject_id, grade, points, batch_ref, recorded_by)
                VALUES ((r->>'applicationId')::uuid, (r->>'subjectId')::uuid, r->>'grade', jupeb.grade_points(r->>'grade'), v_ref, p_actor);
                applied := applied + 1;
            ELSIF r->>'status' = 'CORRECTION' THEN
                INSERT INTO jupeb.result_change (application_id, subject_id, old_grade, new_grade, reason, batch_ref, changed_by)
                SELECT application_id, subject_id, grade, r->>'grade', r->>'reason', v_ref, p_actor FROM jupeb.result
                 WHERE application_id = (r->>'applicationId')::uuid AND subject_id = (r->>'subjectId')::uuid;
                UPDATE jupeb.result SET grade = r->>'grade', points = jupeb.grade_points(r->>'grade'), batch_ref = v_ref, recorded_by = p_actor, recorded_at = now()
                 WHERE application_id = (r->>'applicationId')::uuid AND subject_id = (r->>'subjectId')::uuid;
                PERFORM jupeb.app_event((r->>'applicationId')::uuid, 'RESULT_CORRECTED', (r->>'message') || ' — ' || (r->>'reason'));
                applied := applied + 1;
            END IF;
        END LOOP;
        INSERT INTO jupeb.import_batch (ref, kind, file_name, rows, applied, result, imported_by, imported_office)
        VALUES (v_ref, 'RESULTS', p_file, jsonb_array_length(v_out), applied, jsonb_build_object('new', n_new, 'corrections', n_fix, 'unchanged', n_same),
                p_actor, nullif(current_setting('moaum.actor_office', true), ''));
    END IF;
    RETURN jsonb_build_object('rows', v_out, 'invalid', n_invalid, 'new', n_new, 'corrections', n_fix, 'unchanged', n_same, 'committed', p_commit, 'ref', v_ref, 'applied', applied);
END $$;

/* the session's results released: every active student with a result is COMPLETED and told */
CREATE OR REPLACE FUNCTION jupeb.publish_results(p_session text, p_actor uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM jupeb.result r JOIN jupeb.application a ON a.id = r.application_id WHERE a.session = p_session) THEN
        RAISE EXCEPTION 'JUPEB_NO_RESULTS: no result is recorded for %', p_session USING ERRCODE = '23514', HINT = 'Import the Board''s results first.';
    END IF;
    INSERT INTO jupeb.setting (session, application_prefix, screening_required, screening_venue, screening_starts_on, screening_ends_on, screening_instructions)
    SELECT p_session, application_prefix, screening_required, screening_venue, screening_starts_on, screening_ends_on, screening_instructions FROM jupeb.setting WHERE session = '*'
    ON CONFLICT (session) DO NOTHING;
    UPDATE jupeb.setting SET results_published_at = coalesce(results_published_at, now()), results_published_by = coalesce(results_published_by, p_actor), updated_by = p_actor, updated_at = now()
     WHERE session = p_session;
    UPDATE jupeb.application a SET state = 'COMPLETED'
     WHERE a.session = p_session AND a.state = 'STUDENT' AND EXISTS (SELECT 1 FROM jupeb.result r WHERE r.application_id = a.id);
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

/* the approved combinations, imported: subjects matched by code or title (a new subject is named in the preview and made on
   commit), the faculties and programmes it leads to matched on the register; a combination someone has chosen keeps its subjects */
CREATE OR REPLACE FUNCTION jupeb.import_combinations(p_rows jsonb, p_commit boolean, p_file text, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_out jsonb := '[]'::jsonb; v_code text; v_status text; v_msg text; v_subj text[]; v_ids uuid[]; v_new text[]; t text; v_sid uuid; v_scode text;
        v_area text; v_fac text[]; v_prog text[]; x text; cur jupeb.combination; n_invalid int := 0; n_new int := 0; n_upd int := 0; v_ref text; seen text[] := '{}';
        new_subjects jsonb := '{}'::jsonb; v_newj jsonb; applied int := 0; v_cid uuid;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('jupeb.combinations'));
    FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) LOOP
        v_code := upper(btrim(coalesce(r->>'code', '')));
        v_subj := ARRAY[btrim(coalesce(r->>'subject1', '')), btrim(coalesce(r->>'subject2', '')), btrim(coalesce(r->>'subject3', ''))];
        v_status := NULL; v_msg := NULL; v_ids := '{}'; v_new := '{}'; v_newj := '{}'::jsonb; v_fac := '{}'; v_prog := '{}'; cur := NULL;
        v_area := (SELECT a FROM unnest(ARRAY['Arts', 'Law', 'Engineering', 'Science', 'Social Sciences', 'Management Sciences', 'Other']) a
                    WHERE lower(a) = lower(btrim(coalesce(r->>'area', ''))));
        SELECT * INTO cur FROM jupeb.combination WHERE code = v_code;
        IF v_code = '' THEN v_status := 'INVALID'; v_msg := 'No combination code';
        ELSIF v_code !~ '^[A-Z0-9][A-Z0-9 /&-]{0,19}$' THEN v_status := 'INVALID'; v_msg := v_code || ' is not a combination code (letters, digits, / & - and spaces; at most 20)';
        ELSIF v_code = ANY(seen) THEN v_status := 'INVALID'; v_msg := v_code || ' appears twice in the file';
        ELSIF nullif(btrim(coalesce(r->>'name', '')), '') IS NULL THEN v_status := 'INVALID'; v_msg := 'No combination name';
        ELSIF '' = ANY(v_subj) THEN v_status := 'INVALID'; v_msg := 'A combination has exactly three subjects';
        ELSIF nullif(btrim(coalesce(r->>'area', '')), '') IS NOT NULL AND v_area IS NULL THEN
            v_status := 'INVALID'; v_msg := 'The area is Arts, Law, Engineering, Science, Social Sciences, Management Sciences or Other';
        END IF;
        IF v_status IS NULL THEN
            FOREACH t IN ARRAY v_subj LOOP
                SELECT id INTO v_sid FROM jupeb.subject WHERE upper(code) = upper(t) OR upper(title) = upper(t) LIMIT 1;
                IF v_sid IS NULL THEN
                    v_scode := btrim(left(upper(regexp_replace(t, '[^A-Za-z0-9 /&-]', '', 'g')), 40));
                    IF v_scode !~ '^[A-Z0-9][A-Z0-9 /&-]{1,39}$' THEN v_status := 'INVALID'; v_msg := '"' || t || '" cannot be made a subject'; EXIT; END IF;
                    IF EXISTS (SELECT 1 FROM jupeb.subject WHERE code = v_scode) THEN
                        v_status := 'INVALID'; v_msg := '"' || t || '" is not a subject, and its code ' || v_scode || ' is another subject''s'; EXIT;
                    END IF;
                    v_new := v_new || t;
                    v_newj := v_newj || jsonb_build_object(v_scode, t);
                    v_ids := v_ids || NULL::uuid;
                ELSE
                    v_ids := v_ids || v_sid;
                END IF;
            END LOOP;
        END IF;
        IF v_status IS NULL AND (SELECT count(DISTINCT upper(z)) FROM unnest(v_subj) z) < 3 THEN v_status := 'INVALID'; v_msg := 'The three subjects must differ'; END IF;
        IF v_status IS NULL AND (SELECT count(DISTINCT z) FROM unnest(v_ids) z WHERE z IS NOT NULL) < (SELECT count(*) FROM unnest(v_ids) z WHERE z IS NOT NULL) THEN
            v_status := 'INVALID'; v_msg := 'Two of the subjects are the same subject';
        END IF;
        IF v_status IS NULL THEN
            FOREACH x IN ARRAY coalesce(string_to_array(regexp_replace(coalesce(r->>'faculties', ''), '\s*[;,]\s*', ',', 'g'), ','), '{}') LOOP
                CONTINUE WHEN btrim(x) = '';
                SELECT code INTO t FROM ref.faculty WHERE upper(code) = upper(btrim(x)) OR upper(name) = upper(btrim(x)) LIMIT 1;
                IF t IS NULL THEN v_status := 'INVALID'; v_msg := 'No faculty ' || btrim(x); EXIT; END IF;
                v_fac := v_fac || t; t := NULL;
            END LOOP;
        END IF;
        IF v_status IS NULL THEN
            FOREACH x IN ARRAY coalesce(string_to_array(regexp_replace(coalesce(r->>'programmes', ''), '\s*[;,]\s*', ',', 'g'), ','), '{}') LOOP
                CONTINUE WHEN btrim(x) = '';
                SELECT code INTO t FROM ref.programme WHERE (upper(code) = upper(btrim(x)) OR upper(name) = upper(btrim(x))) AND NOT coalesce(archived, false) LIMIT 1;
                IF t IS NULL THEN v_status := 'INVALID'; v_msg := 'No programme ' || btrim(x); EXIT; END IF;
                v_prog := v_prog || t; t := NULL;
            END LOOP;
        END IF;
        IF v_status IS NULL AND cur.id IS NOT NULL
           AND ARRAY[cur.subject1, cur.subject2, cur.subject3]::uuid[] IS DISTINCT FROM v_ids
           AND NOT (ARRAY[cur.subject1, cur.subject2, cur.subject3]::uuid[] @> v_ids AND v_ids @> ARRAY[cur.subject1, cur.subject2, cur.subject3]::uuid[])
           AND EXISTS (SELECT 1 FROM jupeb.application WHERE combination_id = cur.id) THEN
            v_status := 'INVALID'; v_msg := v_code || ' is held by applicants; its subjects are not changed — add a new combination instead';
        END IF;
        IF v_status IS NULL THEN v_status := CASE WHEN cur.id IS NULL THEN 'NEW' ELSE 'UPDATE' END;
            new_subjects := new_subjects || v_newj;
            v_msg := array_to_string(v_subj, ' / ') || CASE WHEN cardinality(v_new) > 0 THEN ' · new subject(s): ' || array_to_string(v_new, ', ') ELSE '' END;
        END IF;
        seen := seen || v_code;
        CASE v_status WHEN 'INVALID' THEN n_invalid := n_invalid + 1; WHEN 'NEW' THEN n_new := n_new + 1; ELSE n_upd := n_upd + 1; END CASE;
        v_out := v_out || jsonb_build_object('row', r->'row', 'code', v_code, 'name', btrim(coalesce(r->>'name', '')), 'subjects', to_jsonb(v_subj), 'area', v_area,
                                         'faculties', to_jsonb(v_fac), 'programmes', to_jsonb(v_prog), 'description', nullif(btrim(coalesce(r->>'description', '')), ''),
                                         'eligibility', nullif(btrim(coalesce(r->>'eligibility', '')), ''),
                                         'active', coalesce(upper(btrim(coalesce(r->>'active', ''))) NOT IN ('NO', 'N', 'FALSE', 'INACTIVE', '0'), true),
                                         'status', v_status, 'message', v_msg);
    END LOOP;
    IF p_commit THEN
        IF jsonb_array_length(v_out) = 0 THEN RAISE EXCEPTION 'JUPEB_IMPORT_EMPTY: the file has no rows' USING ERRCODE = '23514'; END IF;
        IF n_invalid > 0 THEN
            RAISE EXCEPTION 'JUPEB_IMPORT_INVALID: % row(s) are invalid; nothing was written', n_invalid USING ERRCODE = '23514', HINT = 'Correct the rows the preview lists and upload again.';
        END IF;
        v_ref := jupeb.batch_ref('COMBINATIONS');
        INSERT INTO jupeb.subject (code, title, created_by, updated_by)
        SELECT k, v, p_actor, p_actor FROM jsonb_each_text(new_subjects) e(k, v) ON CONFLICT (code) DO NOTHING;
        FOR r IN SELECT * FROM jsonb_array_elements(v_out) LOOP
            SELECT array_agg((SELECT s.id FROM jupeb.subject s WHERE upper(s.code) = upper(z) OR upper(s.title) = upper(z)
                                      OR s.code = btrim(left(upper(regexp_replace(z, '[^A-Za-z0-9 /&-]', '', 'g')), 40)) ORDER BY (upper(s.code) = upper(z) OR upper(s.title) = upper(z)) DESC LIMIT 1) ORDER BY o)
              INTO v_ids FROM jsonb_array_elements_text(r->'subjects') WITH ORDINALITY AS q(z, o);
            INSERT INTO jupeb.combination (code, name, subject1, subject2, subject3, area, description, eligibility_notes, active, created_by, updated_by)
            VALUES (r->>'code', r->>'name', v_ids[1], v_ids[2], v_ids[3], r->>'area', r->>'description', r->>'eligibility', (r->>'active')::boolean, p_actor, p_actor)
            ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, subject1 = EXCLUDED.subject1, subject2 = EXCLUDED.subject2, subject3 = EXCLUDED.subject3,
                   area = EXCLUDED.area, description = coalesce(EXCLUDED.description, jupeb.combination.description),
                   eligibility_notes = coalesce(EXCLUDED.eligibility_notes, jupeb.combination.eligibility_notes), active = EXCLUDED.active,
                   updated_by = p_actor, updated_at = now()
            RETURNING id INTO v_cid;
            IF jsonb_array_length(r->'faculties') + jsonb_array_length(r->'programmes') > 0 THEN
                DELETE FROM jupeb.combination_relevance WHERE combination_id = v_cid;
                INSERT INTO jupeb.combination_relevance (combination_id, faculty_code) SELECT v_cid, f FROM jsonb_array_elements_text(r->'faculties') f ON CONFLICT DO NOTHING;
                INSERT INTO jupeb.combination_relevance (combination_id, programme_code) SELECT v_cid, p FROM jsonb_array_elements_text(r->'programmes') p ON CONFLICT DO NOTHING;
            END IF;
            applied := applied + 1;
        END LOOP;
        INSERT INTO jupeb.import_batch (ref, kind, file_name, rows, applied, result, imported_by, imported_office)
        VALUES (v_ref, 'COMBINATIONS', p_file, jsonb_array_length(v_out), applied, jsonb_build_object('new', n_new, 'updated', n_upd, 'newSubjects', new_subjects),
                p_actor, nullif(current_setting('moaum.actor_office', true), ''));
    END IF;
    RETURN jsonb_build_object('rows', v_out, 'invalid', n_invalid, 'new', n_new, 'updated', n_upd, 'newSubjects', new_subjects, 'committed', p_commit, 'ref', v_ref, 'applied', applied);
END $$;

/* admission for many at once: the preview says what each would become; the commit decides the ones that can be decided and lists the rest */
CREATE OR REPLACE FUNCTION jupeb.bulk_admission(p_ids uuid[], p_decision text, p_note text, p_actor uuid, p_commit boolean)
RETURNS TABLE (application_id uuid, application_no text, name text, state text, ok boolean, reason text)
LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; v text := upper(btrim(coalesce(p_decision, ''))); v_ok boolean; v_reason text;
BEGIN
    IF v NOT IN ('ADMITTED', 'NOT_ADMITTED', 'PENDING') THEN RAISE EXCEPTION 'JUPEB_DECISION: admitted, not admitted or pending' USING ERRCODE = '23514'; END IF;
    IF cardinality(coalesce(p_ids, '{}')) > 2000 THEN RAISE EXCEPTION 'JUPEB_BULK_LIMIT: at most 2,000 applications at once' USING ERRCODE = '23514'; END IF;
    FOR a IN SELECT * FROM jupeb.application x WHERE x.id = ANY(p_ids) ORDER BY x.application_no LOOP
        v_ok := a.state IN ('ELIGIBLE', 'PENDING', 'NOT_ADMITTED', 'ADMITTED') AND a.state <> v;
        v_reason := CASE WHEN a.state = v THEN 'Already ' || lower(replace(v, '_', ' '))
                         WHEN NOT v_ok THEN 'Not eligible for an admission decision (' || lower(a.state) || ')' END;
        IF v_ok AND a.state = 'ADMITTED' AND (SELECT sf.paid FROM jupeb.school_fees(a.id) sf) > 0 THEN v_ok := false; v_reason := 'A school fee is paid against the admission'; END IF;
        IF v_ok AND p_commit THEN PERFORM jupeb.decide_admission(a.id, v, p_note, p_actor); END IF;
        application_id := a.id; application_no := a.application_no; name := a.surname || ', ' || a.first_name || coalesce(' ' || a.middle_name, '');
        state := a.state; ok := v_ok; reason := v_reason;
        RETURN NEXT;
    END LOOP;
END $$;

-- ── 12 · the JUPEB application window, among the Director of ICT's portal windows ──────────────────

ALTER TABLE policy.portal_window DROP CONSTRAINT IF EXISTS portal_window_window_type_check;
ALTER TABLE policy.portal_window ADD CONSTRAINT portal_window_window_type_check
    CHECK (window_type IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION',
                           'POSTGRADUATE_APPLICATION', 'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION'));
ALTER TABLE policy.portal_window DROP CONSTRAINT IF EXISTS ck_window_application_session;
ALTER TABLE policy.portal_window ADD CONSTRAINT ck_window_application_session
    CHECK (window_type NOT IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION') OR (semester IS NULL AND late_until IS NULL AND NOT late_fee_enabled));
ALTER TABLE policy.portal_window_message DROP CONSTRAINT IF EXISTS portal_window_message_window_type_check;
ALTER TABLE policy.portal_window_message ADD CONSTRAINT portal_window_message_window_type_check
    CHECK (window_type IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION'));
INSERT INTO policy.portal_window_message (window_type, message) VALUES
  ('JUPEB_APPLICATION',
   E'JUPEB APPLICATION IS CURRENTLY CLOSED\n\nThank you for your interest in the University''s JUPEB programme.\n\nApplications are not open at the moment. Please check the University''s official website and this portal for the next application window.')
ON CONFLICT (window_type) DO NOTHING;

/* the JUPEB window, unlike the older application windows, is CLOSED until the Director of ICT first opens it */
CREATE OR REPLACE FUNCTION policy.window_state(p_type text, p_session text, p_semester integer)
RETURNS TABLE(configured boolean, state text, phase text, opens_at timestamptz, closes_at timestamptz, late_until timestamptz,
              late_fee_enabled boolean, forced text, reason text, window_id uuid, semester integer)
LANGUAGE sql STABLE AS $fn$
    WITH w AS (
        SELECT * FROM policy.portal_window
         WHERE window_type = p_type AND session = p_session AND superseded_at IS NULL
           AND (semester = p_semester OR semester IS NULL)
         ORDER BY (semester IS NOT NULL) DESC LIMIT 1)
    SELECT w.id IS NOT NULL,
           CASE WHEN w.id IS NULL THEN CASE WHEN p_type IN ('ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION') THEN 'CLOSED' ELSE 'OPEN' END
                WHEN w.forced = 'CLOSED' THEN 'CLOSED'
                WHEN w.forced = 'OPEN' THEN 'OPEN'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'SCHEDULED'
                WHEN w.closes_at IS NULL OR now() <= w.closes_at THEN 'OPEN'
                WHEN w.late_until IS NOT NULL AND now() <= w.late_until THEN 'OPEN'
                ELSE 'EXPIRED' END,
           CASE WHEN w.id IS NULL THEN CASE WHEN p_type IN ('ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION') THEN 'NONE' ELSE 'NORMAL' END
                WHEN w.forced = 'OPEN' THEN CASE WHEN w.late_fee_enabled THEN 'LATE' ELSE 'NORMAL' END
                WHEN w.forced = 'CLOSED' THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at AND w.late_until IS NOT NULL AND now() <= w.late_until THEN 'LATE'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at THEN 'NONE'
                ELSE 'NORMAL' END,
           w.opens_at, w.closes_at, w.late_until, coalesce(w.late_fee_enabled, false), w.forced, w.reason, w.id, w.semester
      FROM (SELECT 1) one LEFT JOIN w ON true
$fn$;

CREATE OR REPLACE FUNCTION policy.window_act(p_type text, p_session text, p_semester integer, p_action text,
                                             p_opens timestamptz, p_closes timestamptz, p_late_until timestamptz, p_late_fee boolean,
                                             p_reason text, p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE cur policy.portal_window; prev record; v_forced text; v_opens timestamptz; v_closes timestamptz; v_late timestamptz; v_fee boolean; v_id uuid; nxt record;
BEGIN
    IF p_type NOT IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION',
                      'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION') THEN
        RAISE EXCEPTION 'no such portal window %', p_type USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('ADMISSION_STATUS_CHECKING', 'POSTGRADUATE_ADMISSION_STATUS_CHECKING') AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_CHECKING_SESSION: admission status checking opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION') AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
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

CREATE OR REPLACE FUNCTION policy.window_message_set(p_type text, p_message text, p_actor uuid, p_office text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_old text; v_new text;
BEGIN
    IF p_type NOT IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION') THEN RAISE EXCEPTION 'no closure message for %', p_type USING ERRCODE = '23514'; END IF;
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
END $fn$;

CREATE OR REPLACE FUNCTION policy.application_windows_public()
RETURNS TABLE(window_type text, session text, state text, opens_at timestamptz, closes_at timestamptz, message text)
LANGUAGE sql STABLE AS $fn$
    SELECT t.window_type, s.session, w.state, w.opens_at, w.closes_at, m.message
      FROM (VALUES ('POST_UTME_REGISTRATION'), ('POSTGRADUATE_APPLICATION'), ('JUPEB_APPLICATION')) t(window_type)
      CROSS JOIN LATERAL (SELECT policy.application_session(t.window_type) AS session) s
      CROSS JOIN LATERAL policy.window_state(t.window_type, s.session, NULL) w
      LEFT JOIN policy.portal_window_message m ON m.window_type = t.window_type
$fn$;

CREATE OR REPLACE FUNCTION policy.application_window_guard()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_type text := TG_ARGV[0]; v_state text;
BEGIN
    -- only the applicant registering themselves is held at the door; an office importing or correcting records is not
    IF coalesce(current_setting('moaum.actor_office', true), '') <> 'applicant' THEN RETURN NEW; END IF;
    SELECT state INTO v_state FROM policy.window_state(v_type, NEW.session, NULL);
    IF v_state <> 'OPEN' THEN
        RAISE EXCEPTION 'APPLICATION_CLOSED: % for % is % — no new application can be started until the Director of ICT opens it',
            CASE v_type WHEN 'POST_UTME_REGISTRATION' THEN 'Post-UTME registration' WHEN 'JUPEB_APPLICATION' THEN 'JUPEB application' ELSE 'postgraduate application' END,
            NEW.session, lower(v_state)
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_application_window_jupeb BEFORE INSERT ON jupeb.application
    FOR EACH ROW EXECUTE FUNCTION policy.application_window_guard('JUPEB_APPLICATION');

-- ── 13 · support: a JUPEB requester, the JUPEB queue, the JUPEB category ──────────────────────────

ALTER TABLE helpdesk.ticket DROP CONSTRAINT IF EXISTS ck_hd_ticket_requester;
ALTER TABLE helpdesk.ticket ADD CONSTRAINT ck_hd_ticket_requester CHECK (requester_kind IN ('STUDENT', 'STAFF', 'JUPEB'));
COMMENT ON COLUMN helpdesk.ticket.requester_kind IS 'STUDENT (people.student), STAFF (iam.person) or, from V339, JUPEB (a JUPEB applicant or student, jupeb.application).';
INSERT INTO helpdesk.queue (code, name, description, office_code, ordinal) VALUES
    ('JUPEB_SUPPORT', 'JUPEB Support', 'JUPEB applications, payments, documents, admission, subjects, examination numbers and results.', 'jupeb', 120)
ON CONFLICT (code) DO NOTHING;
INSERT INTO helpdesk.category (code, name, description, ordinal, suggested_priority, attachment_hint, fields) VALUES
('JUPEB', 'JUPEB Programme', 'A JUPEB application, payment, document, admission, subject registration, examination number or result.', 90, 'NORMAL',
 'The receipt, the document, or a screenshot', '[
  {"key":"jupeb_issue","label":"What is wrong","type":"select","required":true,"options":["Application","Application fee","School fees","Documents","Admission","Subject registration","Examination number","Results","Other"]},
  {"key":"payment_reference","label":"Payment reference, if a payment","type":"text","required":false}
]')
ON CONFLICT (code) DO NOTHING;
INSERT INTO helpdesk.routing_rule (category_code, queue_code, strategy)
SELECT 'JUPEB', 'JUPEB_SUPPORT', 'LEAST_LOADED'
 WHERE NOT EXISTS (SELECT 1 FROM helpdesk.routing_rule r WHERE r.category_code = 'JUPEB' AND r.faculty_code IS NULL AND r.department_code IS NULL);

-- ── 14 · the Bursary's books see JUPEB money: the reference state the reconciler reads, and the day book ─────
CREATE OR REPLACE FUNCTION finance.reference_state(p_reference text)
RETURNS TABLE (kind text, amount numeric, confirmed_at timestamptz, expires_at timestamptz, channel text, receipt_no text)
LANGUAGE sql STABLE AS $$
    SELECT 'STUDENT', r.amount, r.confirmed_at, r.expires_at, r.channel, r.receipt_no FROM finance.payment_reference r WHERE r.reference = upper(btrim(p_reference))
    UNION ALL
    SELECT f.kind, f.amount, f.confirmed_at, f.expires_at, f.channel, NULL FROM admissions.fee_reference f WHERE f.reference = upper(btrim(p_reference))
    UNION ALL
    SELECT 'JUPEB_' || j.kind, j.amount, j.confirmed_at, j.expires_at, j.channel, NULL FROM jupeb.fee_reference j WHERE j.reference = upper(btrim(p_reference))
    LIMIT 1
$$;

CREATE OR REPLACE FUNCTION finance.day_book(p_from date, p_to date)
RETURNS TABLE (reference text, confirmed_at timestamptz, payer text, number text, purpose text, amount numeric, channel text, receipt_no text, note text, session text)
LANGUAGE sql STABLE AS $$
    SELECT r.reference, r.confirmed_at, s.surname || ', ' || s.other_names, coalesce(s.matric_no, s.admission_no), r.purpose, r.amount, r.channel, r.receipt_no, r.note, r.session
      FROM finance.payment_reference r JOIN people.student s ON s.id = r.student_id
     WHERE r.confirmed_at IS NOT NULL AND r.confirmed_at::date BETWEEN p_from AND p_to
    UNION ALL
    SELECT f.reference, f.confirmed_at, c.surname || ', ' || c.other_names, a.application_no,
           CASE f.kind WHEN 'APPLICATION' THEN 'Application fee' ELSE 'Acceptance fee' END, f.amount, f.channel, NULL, f.note, a.session
      FROM admissions.fee_reference f JOIN admissions.application a ON a.id = f.application_id JOIN admissions.candidate c ON c.id = a.candidate_id
     WHERE f.confirmed_at IS NOT NULL AND f.confirmed_at::date BETWEEN p_from AND p_to
    UNION ALL
    SELECT j.reference, j.confirmed_at, a.surname || ', ' || a.first_name || coalesce(' ' || a.middle_name, ''), a.application_no,
           CASE j.kind WHEN 'APPLICATION' THEN 'JUPEB application fee' WHEN 'SCHOOL_FIRST' THEN 'JUPEB school fee (first semester)'
                       WHEN 'SCHOOL_SECOND' THEN 'JUPEB school fee (second semester)' ELSE 'JUPEB school fee (full)' END,
           j.amount, j.channel, NULL, NULL, j.session
      FROM jupeb.fee_reference j JOIN jupeb.application a ON a.id = j.application_id
     WHERE j.confirmed_at IS NOT NULL AND j.confirmed_at::date BETWEEN p_from AND p_to
    ORDER BY 2 DESC
$$;

-- ── 15 · grants (the API runs as the owner; the roles read for reports and audit) ──────────────────
GRANT SELECT ON ALL TABLES IN SCHEMA jupeb TO app_auditor;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA jupeb TO app_admissions;
GRANT SELECT ON jupeb.fee_reference, jupeb.fee_setting, jupeb.school_fee, jupeb.fee_category, jupeb.application TO app_finance;
GRANT UPDATE ON jupeb.fee_reference TO app_finance;

COMMIT;
