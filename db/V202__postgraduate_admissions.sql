-- ═══════════════════════════════════════════════════════════════════════════
-- V202 — Postgraduate admissions (Phase 1): application → decision → admit
--
--   A postgraduate applicant does not come through JAMB/CAPS: there is no CAPS
--   row, no UTME aggregate, no JAMB attachment. The undergraduate applicant
--   journey (V021) is bolted to admissions.candidate, which cannot be admitted
--   without a CAPS row (ck_candidate_needs_caps), so postgraduate admissions is
--   a SEPARATE, self-contained path built here and it never touches the
--   undergraduate candidate/merit machinery.
--
--   The shape mirrors the undergraduate journey where it can — an account, an
--   application with a computed-then-stored state, a fee reference, an office
--   decision, an acceptance — but everything is typed by the applicant (name,
--   sex, date of birth, contact, the first degree the admission rests on, and a
--   research proposal for a research degree) rather than read from JAMB. On
--   acceptance the student is created directly on the register with
--   entry_mode = 'POSTGRADUATE', the postgraduate level from the award, and the
--   postgraduate school id, then matriculated by the ordinary path (V064).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1 · the applicant account and the typed biodata (self-contained) ────────
-- Holds a password hash and the applicant's own biodata; excluded from the audit
-- spine exactly as admissions.applicant_account (V021) is.
CREATE TABLE admissions.pg_applicant (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session           text NOT NULL,
    surname           text NOT NULL,
    other_names       text NOT NULL,
    sex               text NULL,
    date_of_birth     date NULL,
    state_of_origin   text NULL,
    lga               text NULL,
    email             text NOT NULL,
    phone             text NULL,
    password_hash     text NOT NULL,
    failed_attempts   int  NOT NULL DEFAULT 0,
    locked_until      timestamptz NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    last_signed_in_at timestamptz NULL,
    CONSTRAINT ck_pgapplicant_sex   CHECK (sex IS NULL OR sex IN ('F','M')),
    CONSTRAINT ck_pgapplicant_pw    CHECK (password_hash LIKE '$2%$12$%'),
    CONSTRAINT ck_pgapplicant_email CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
    CONSTRAINT ck_pgapplicant_phone CHECK (phone IS NULL OR phone ~ '^0[0-9]{10}$')
);
CREATE UNIQUE INDEX uq_pg_applicant_email ON admissions.pg_applicant (lower(email));
SELECT audit.exempt('admissions.pg_applicant',
    'Holds a password hash and applicant biodata; excluded from the spine like admissions.applicant_account (V021).');

-- ── 2 · the application, its first degree, proposal and state machine ────────
CREATE TABLE admissions.pg_application (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    applicant_id    uuid NOT NULL REFERENCES admissions.pg_applicant(id),
    session         text NOT NULL,
    application_no  text NOT NULL UNIQUE,
    programme_code  text NOT NULL REFERENCES ref.programme(code),
    entry_level     int  NOT NULL,                 -- 700 PGD · 800 Master's · 900 MPhil/PhD
    -- the first degree the postgraduate admission rests on
    prior_institution text NULL,
    prior_award       text NULL,
    prior_class       text NULL,                   -- e.g. 'First Class', 'Second Class (Upper)'
    prior_cgpa        numeric(3,2) NULL,
    prior_year        int NULL,
    -- the research proposal (required for a research programme, ref.programme.pg_research)
    proposal_title  text NULL,
    proposal_text   text NULL,
    -- the state machine, and the acts that move it
    state           text NOT NULL DEFAULT 'DRAFT',
    fee_confirmed_at timestamptz NULL,
    submitted_at    timestamptz NULL,
    dept_decided_at timestamptz NULL, dept_decided_by uuid NULL REFERENCES iam.person(id), dept_note text NULL,
    spgs_decided_at timestamptz NULL, spgs_decided_by uuid NULL REFERENCES iam.person(id), spgs_note text NULL,
    accepted_at     timestamptz NULL,
    admitted_at     timestamptz NULL,
    student_id      uuid NULL REFERENCES people.student(id),
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_pg_application_per_applicant UNIQUE (applicant_id),
    CONSTRAINT ck_pg_app_state CHECK (state IN
        ('DRAFT','SUBMITTED','DEPT_RECOMMENDED','DEPT_DECLINED','OFFERED','NOT_OFFERED','ACCEPTED','ADMITTED')),
    CONSTRAINT ck_pg_app_no    CHECK (application_no ~ '^PG/[0-9]{2}/[0-9]{6}$'),
    CONSTRAINT ck_pg_app_level CHECK (entry_level IN (700,800,900)),
    CONSTRAINT ck_pg_app_cgpa  CHECK (prior_cgpa IS NULL OR prior_cgpa BETWEEN 0 AND 5)
);
CREATE INDEX ix_pg_app_session   ON admissions.pg_application (session, state);
CREATE INDEX ix_pg_app_programme ON admissions.pg_application (programme_code, session);
SELECT audit.attach('admissions.pg_application');

-- ── 3 · the referees ────────────────────────────────────────────────────────
CREATE TABLE admissions.pg_referee (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES admissions.pg_application(id) ON DELETE CASCADE,
    name           text NOT NULL,
    email          text NULL,
    institution    text NULL,
    position       text NULL,
    reference_text text NULL,
    submitted_at   timestamptz NULL,
    CONSTRAINT ck_pg_ref_email CHECK (email IS NULL OR email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
);
CREATE INDEX ix_pg_referee_app ON admissions.pg_referee (application_id);
SELECT audit.attach('admissions.pg_referee');

-- ── 4 · the uploaded documents (transcript, certificate, CV, proposal) ──────
-- Holds file bytes; excluded from the spine like admissions.attachment (V007).
CREATE TABLE admissions.pg_document (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES admissions.pg_application(id) ON DELETE CASCADE,
    kind           text NOT NULL,
    filename       text NOT NULL,
    content_type   text NOT NULL,
    bytes          bytea NOT NULL,
    uploaded_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_pg_doc_kind CHECK (kind IN ('TRANSCRIPT','DEGREE_CERTIFICATE','CV','PROPOSAL','NYSC','OTHER'))
);
CREATE INDEX ix_pg_document_app ON admissions.pg_document (application_id);
SELECT audit.exempt('admissions.pg_document',
    'Holds uploaded file bytes; excluded from the spine like admissions.attachment (V007).');

-- ── 5 · the postgraduate application fee, per session ───────────────────────
CREATE TABLE admissions.pg_fee (
    session         text PRIMARY KEY,
    application_fee numeric(12,2) NOT NULL,
    acceptance_fee  numeric(12,2) NOT NULL,
    CONSTRAINT ck_pg_fee_amt CHECK (application_fee >= 0 AND acceptance_fee >= 0)
);
SELECT audit.attach('admissions.pg_fee');

CREATE OR REPLACE FUNCTION admissions.pg_fee_rule(p_session text)
RETURNS TABLE (application_fee numeric, acceptance_fee numeric)
LANGUAGE sql STABLE AS $$
    SELECT f.application_fee, f.acceptance_fee FROM admissions.pg_fee f WHERE f.session = p_session
    UNION ALL
    SELECT 20000, 50000 WHERE NOT EXISTS (SELECT 1 FROM admissions.pg_fee f WHERE f.session = p_session)
$$;

CREATE TABLE admissions.pg_fee_reference (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES admissions.pg_application(id),
    kind           text NOT NULL,
    reference      text NOT NULL UNIQUE,
    amount         numeric(12,2) NOT NULL,
    generated_at   timestamptz NOT NULL DEFAULT now(),
    expires_at     timestamptz NOT NULL,
    confirmed_at   timestamptz NULL,
    channel        text NULL,
    CONSTRAINT ck_pg_feeref_kind CHECK (kind IN ('APPLICATION','ACCEPTANCE'))
);
CREATE INDEX ix_pg_feeref_app ON admissions.pg_fee_reference (application_id);
SELECT audit.attach('admissions.pg_fee_reference');

-- ── 6 · the award → postgraduate level map ──────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_award_level(p_award text)
RETURNS int
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE upper(coalesce(p_award, ''))
             WHEN 'PGD'   THEN 700
             WHEN 'PHD'   THEN 900
             WHEN 'MPHIL' THEN 900
             ELSE 800                              -- MSc/MA/MBA/MPA/MEd/LLM and the default
           END
$$;

-- ── 7 · register an applicant and open a draft application ───────────────────
-- The password is hashed by the caller (bcrypt cost-12), as the undergraduate
-- register does. The programme must be one the University runs at postgraduate
-- level. Returns the new application id.
CREATE OR REPLACE FUNCTION admissions.pg_register(
        p_session text, p_surname text, p_other_names text, p_email text, p_phone text,
        p_password_hash text, p_programme text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_cat text; v_award text; v_applicant uuid; v_app uuid; v_yy text := substr(p_session, 3, 2);
BEGIN
    SELECT category, pg_award INTO v_cat, v_award FROM ref.programme WHERE code = p_programme AND NOT archived;
    IF v_cat IS NULL THEN
        RAISE EXCEPTION 'programme % is not one the University runs', p_programme USING ERRCODE = '23503';
    END IF;
    IF v_cat <> 'POST GRADUATE' THEN
        RAISE EXCEPTION 'programme % is not a postgraduate programme', p_programme USING ERRCODE = '23514';
    END IF;

    INSERT INTO admissions.pg_applicant (session, surname, other_names, email, phone, password_hash)
    VALUES (p_session, btrim(p_surname), btrim(p_other_names), lower(btrim(p_email)),
            nullif(btrim(p_phone), ''), p_password_hash)
    RETURNING id INTO v_applicant;

    INSERT INTO admissions.pg_application (applicant_id, session, application_no, programme_code, entry_level)
    VALUES (v_applicant, p_session,
            'PG/' || v_yy || '/' || lpad(platform.next_number('PG_APPLICATION', 'UNIVERSITY', p_session)::text, 6, '0'),
            p_programme, admissions.pg_award_level(v_award))
    RETURNING id INTO v_app;

    RETURN v_app;
END;
$$;

-- ── 8 · a fee reference, and its confirmation ───────────────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_new_fee_reference(p_application uuid, p_kind text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v_session text; v_amt numeric; v_ref text; v_rule record;
BEGIN
    SELECT session INTO v_session FROM admissions.pg_application WHERE id = p_application;
    IF v_session IS NULL THEN
        RAISE EXCEPTION 'no such postgraduate application';
    END IF;
    SELECT * INTO v_rule FROM admissions.pg_fee_rule(v_session);
    v_amt := CASE WHEN p_kind = 'ACCEPTANCE' THEN v_rule.acceptance_fee ELSE v_rule.application_fee END;
    v_ref := 'MOAUM-PG' || CASE WHEN p_kind = 'ACCEPTANCE' THEN 'ACC' ELSE 'APP' END || '-'
             || lpad(platform.next_number('PG_FEEREF', 'UNIVERSITY', v_session)::text, 6, '0');
    INSERT INTO admissions.pg_fee_reference (application_id, kind, reference, amount, expires_at)
    VALUES (p_application, p_kind, v_ref, v_amt, now() + interval '24 hours');
    RETURN v_ref;
END;
$$;

CREATE OR REPLACE FUNCTION admissions.pg_confirm_fee(p_reference text, p_channel text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_app uuid; v_kind text;
BEGIN
    UPDATE admissions.pg_fee_reference
       SET confirmed_at = now(), channel = p_channel
     WHERE reference = p_reference AND confirmed_at IS NULL
     RETURNING application_id, kind INTO v_app, v_kind;
    IF v_app IS NULL THEN
        RETURN;                                   -- unknown or already confirmed: nothing to do
    END IF;
    IF v_kind = 'APPLICATION' THEN
        UPDATE admissions.pg_application SET fee_confirmed_at = coalesce(fee_confirmed_at, now())
         WHERE id = v_app;
    END IF;
END;
$$;

-- ── 9 · submit, decide (department, then School), accept ─────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_submit(p_application uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE a admissions.pg_application; v_research boolean;
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_application;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such postgraduate application'; END IF;
    IF a.state <> 'DRAFT' THEN RAISE EXCEPTION 'the application has already been submitted'; END IF;
    IF a.fee_confirmed_at IS NULL THEN RAISE EXCEPTION 'the application fee is not yet confirmed'; END IF;
    IF coalesce(btrim(a.prior_institution), '') = '' OR coalesce(btrim(a.prior_award), '') = '' THEN
        RAISE EXCEPTION 'the first degree (institution and award) must be stated';
    END IF;
    SELECT pg_research INTO v_research FROM ref.programme WHERE code = a.programme_code;
    IF v_research AND coalesce(btrim(a.proposal_text), '') = '' THEN
        RAISE EXCEPTION 'this is a research programme; a research proposal is required';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM admissions.pg_referee r WHERE r.application_id = p_application) THEN
        RAISE EXCEPTION 'at least one referee must be named';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM admissions.pg_document d WHERE d.application_id = p_application AND d.kind = 'TRANSCRIPT') THEN
        RAISE EXCEPTION 'the first-degree transcript must be uploaded';
    END IF;
    UPDATE admissions.pg_application SET state = 'SUBMITTED', submitted_at = now() WHERE id = p_application;
END;
$$;

CREATE OR REPLACE FUNCTION admissions.pg_dept_decide(p_application uuid, p_recommend boolean, p_note text, p_actor uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_state text;
BEGIN
    SELECT state INTO v_state FROM admissions.pg_application WHERE id = p_application;
    IF v_state IS NULL THEN RAISE EXCEPTION 'no such postgraduate application'; END IF;
    IF v_state <> 'SUBMITTED' THEN RAISE EXCEPTION 'the department decides a submitted application, not one at %', v_state; END IF;
    UPDATE admissions.pg_application
       SET state = CASE WHEN p_recommend THEN 'DEPT_RECOMMENDED' ELSE 'DEPT_DECLINED' END,
           dept_decided_at = now(), dept_decided_by = p_actor, dept_note = nullif(btrim(p_note), '')
     WHERE id = p_application;
END;
$$;

CREATE OR REPLACE FUNCTION admissions.pg_spgs_decide(p_application uuid, p_offer boolean, p_note text, p_actor uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_state text;
BEGIN
    SELECT state INTO v_state FROM admissions.pg_application WHERE id = p_application;
    IF v_state IS NULL THEN RAISE EXCEPTION 'no such postgraduate application'; END IF;
    IF v_state NOT IN ('DEPT_RECOMMENDED','SUBMITTED') THEN
        RAISE EXCEPTION 'the School decides after the department, not on an application at %', v_state;
    END IF;
    UPDATE admissions.pg_application
       SET state = CASE WHEN p_offer THEN 'OFFERED' ELSE 'NOT_OFFERED' END,
           spgs_decided_at = now(), spgs_decided_by = p_actor, spgs_note = nullif(btrim(p_note), '')
     WHERE id = p_application;
END;
$$;

CREATE OR REPLACE FUNCTION admissions.pg_accept(p_application uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_state text;
BEGIN
    SELECT state INTO v_state FROM admissions.pg_application WHERE id = p_application;
    IF v_state IS NULL THEN RAISE EXCEPTION 'no such postgraduate application'; END IF;
    IF v_state <> 'OFFERED' THEN RAISE EXCEPTION 'only an offer can be accepted (state is %)', v_state; END IF;
    UPDATE admissions.pg_application SET state = 'ACCEPTED', accepted_at = now() WHERE id = p_application;
END;
$$;

-- ── 10 · admit: create the student on the register (no CAPS row) ─────────────
-- Mirrors people.intake for a postgraduate: inserts people.student directly from
-- the application, with entry_mode POSTGRADUATE, the award's level, and the
-- postgraduate school id (which sets the curriculum via the V117 trigger). The
-- student is then matriculated by the ordinary fees+registration path (V064).
CREATE OR REPLACE FUNCTION admissions.pg_admit(p_application uuid)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE a admissions.pg_application; p admissions.pg_applicant; v_student uuid; v_yy text;
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_application;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such postgraduate application'; END IF;
    IF a.state <> 'ACCEPTED' THEN RAISE EXCEPTION 'only an accepted offer is admitted (state is %)', a.state; END IF;
    IF a.student_id IS NOT NULL THEN RETURN a.student_id; END IF;   -- idempotent
    SELECT * INTO p FROM admissions.pg_applicant WHERE id = a.applicant_id;
    v_yy := substr(a.session, 3, 2);

    INSERT INTO people.student (id, candidate_id, admission_no, surname, other_names, sex, date_of_birth,
                               programme_code, entry_mode, entry_session, entry_level, current_level, status, school_id)
    VALUES (gen_random_uuid(), NULL,
            'MOAUM/ADM/' || v_yy || '/' || lpad(platform.next_number('ADMISSION', 'UNIVERSITY', a.session)::text, 6, '0'),
            p.surname, p.other_names, p.sex, p.date_of_birth,
            a.programme_code, 'POSTGRADUATE', a.session, a.entry_level, a.entry_level, 'ADMITTED', 'S002')
    RETURNING id INTO v_student;

    UPDATE admissions.pg_application
       SET state = 'ADMITTED', admitted_at = now(), student_id = v_student
     WHERE id = p_application;
    RETURN v_student;
END;
$$;

COMMIT;
