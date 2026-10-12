-- ═══════════════════════════════════════
-- V409 — every payment classified by programme type, purpose, source module and responsible office, on one ledger
--
--   The University has one payment engine already: every reference — a student's, an applicant's (UTME, Direct Entry,
--   CCE), the School's postgraduate applicants', JUPEB's — is paid through the one gateway service (WebPAY, PAYDirect) and
--   settled by the one PaymentsService, and the Bursary reads them on one ledger (reporting.payments, V279). What it lacked
--   was the classification a Bursary report needs — "₦X collected from Sandwich school fees", "₦X from JUPEB applications" —
--   kept as separate dimensions rather than run together in one name. Nothing here is a second payment system:
--
--     · finance.programme_type — the programme types (Undergraduate, Postgraduate, CCE, JUPEB, Sandwich, Preliminary,
--       Remedial, Foundation, Other), each read from the entry modes and programme categories the Bursary maps to it; a type
--       the University does not run yet (Preliminary, Remedial, Foundation) waits, mapped to nothing, for its first programme;
--     · finance.payment_purpose — what was paid for (Application, Admission status checking, Acceptance fee, School fees,
--       GST fee, Hostel fee…), with the income account it posts to and what it entitles; every payment category (V279) now
--       names its purpose, so a category may be as fine as the Bursary likes while reports group by purpose;
--     · finance.payment_classification — which source module generated a payment and which office owns it, by purpose and
--       programme type, the most particular rule winning (GST fee → GST office whatever the programme; CCE → the Centre;
--       Undergraduate school fees → Student Finance and the Bursary);
--     · reporting.payments — the one ledger — gains JUPEB's references (so far kept apart) and, on every row, the programme
--       type, admission route, study mode, purpose, source module, responsible office, semester, the application, JAMB and
--       JUPEB examination numbers and the ledger status; its earlier columns stand as they were;
--     · finance.gl_sync posts every confirmed payment of the ledger to the general ledger, not only a student's.
--
--   The classification is read from the record on the server, never from a request. No fee, amount, reference, payment or
--   entitlement is created or changed here.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V409: payments classified by programme type, purpose, source module and responsible office', true);

-- ── 1 · the programme types ───────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.programme_type (
    code                 text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z_]{1,30}$'),
    label                text NOT NULL CHECK (btrim(label) <> ''),
    ord                  int  NOT NULL DEFAULT 100,
    active               boolean NOT NULL DEFAULT true,
    entry_modes          text[] NOT NULL DEFAULT '{}',   -- a student's or applicant's entry mode that is of this type
    programme_categories text[] NOT NULL DEFAULT '{}',   -- a programme's category (ref.programme.category) that is of this type
    study_mode           text NULL CHECK (study_mode IS NULL OR study_mode IN ('FULL_TIME', 'PART_TIME', 'SANDWICH')),
    description          text NULL,
    updated_by           uuid NULL,
    updated_at           timestamptz NOT NULL DEFAULT now()
);
SELECT audit.attach('finance.programme_type');
COMMENT ON TABLE finance.programme_type IS
  'V409: the programme types a payment is classified by. A payer''s type is read from their entry mode first, then their programme''s category; the Bursary maps both. A type with nothing mapped (Preliminary, Remedial, Foundation until the University runs one) classifies nobody and waits.';
INSERT INTO finance.programme_type (code, label, ord, entry_modes, programme_categories, study_mode, description) VALUES
    ('UNDERGRADUATE', 'Undergraduate', 10, '{UTME,DIRECT_ENTRY,TRANSFER}', '{UNDER GRADUATE}', 'FULL_TIME', 'Full-time first degrees: UTME, Direct Entry and transfer'),
    ('POSTGRADUATE',  'Postgraduate',  20, '{POSTGRADUATE}', '{POST GRADUATE}', NULL, 'The School of Postgraduate Studies: PGD, Masters and Doctorate programmes'),
    ('CCE',           'Continuing Education (CCE)', 30, '{CCE}', '{}', 'PART_TIME', 'The Centre for Continuing Education''s part-time route'),
    ('JUPEB',         'JUPEB', 40, '{JUPEB}', '{}', 'FULL_TIME', 'The Joint Universities Preliminary Examinations Board programme'),
    ('SANDWICH',      'Sandwich', 50, '{SANDWICH}', '{}', 'SANDWICH', 'The Sandwich programme'),
    ('PRELIMINARY',   'Preliminary', 60, '{}', '{}', NULL, 'A preliminary programme — mapped when the University runs one'),
    ('REMEDIAL',      'Remedial', 70, '{}', '{}', NULL, 'A remedial programme — mapped when the University runs one'),
    ('FOUNDATION',    'Foundation', 80, '{}', '{}', NULL, 'A foundation programme — mapped when the University runs one'),
    ('OTHER',         'Other', 999, '{}', '{}', NULL, 'A payer no other type claims');

/* a payer's programme type: by entry mode, then by the programme's category, else Other */
CREATE OR REPLACE FUNCTION finance.programme_type_for(p_entry_mode text, p_programme_category text)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT t.code FROM finance.programme_type t WHERE t.active AND p_entry_mode IS NOT NULL AND upper(p_entry_mode) = ANY (t.entry_modes) ORDER BY t.ord, t.code LIMIT 1),
        (SELECT t.code FROM finance.programme_type t WHERE t.active AND p_programme_category IS NOT NULL AND upper(p_programme_category) = ANY (t.programme_categories) ORDER BY t.ord, t.code LIMIT 1),
        'OTHER')
$$;

/* the admission route an entry mode stands for: Post-UTME, Direct Entry, transfer, CCE, Sandwich, Postgraduate, JUPEB */
CREATE OR REPLACE FUNCTION finance.admission_route_of(p_entry_mode text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE upper(coalesce(p_entry_mode, ''))
        WHEN 'UTME' THEN 'POST_UTME' WHEN 'DIRECT_ENTRY' THEN 'DIRECT_ENTRY' WHEN 'TRANSFER' THEN 'TRANSFER' WHEN 'CCE' THEN 'CCE'
        WHEN 'SANDWICH' THEN 'SANDWICH' WHEN 'POSTGRADUATE' THEN 'POSTGRADUATE' WHEN 'JUPEB' THEN 'JUPEB' WHEN '' THEN NULL ELSE upper(p_entry_mode) END
$$;

-- ── 2 · the purposes ──────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.payment_purpose (
    code        text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z_]{1,39}$'),
    label       text NOT NULL CHECK (btrim(label) <> ''),
    ord         int  NOT NULL DEFAULT 100,
    active      boolean NOT NULL DEFAULT true,
    gl_account  text NOT NULL DEFAULT '4090' REFERENCES finance.gl_account(code),
    entitlement text NULL,
    updated_by  uuid NULL,
    updated_at  timestamptz NOT NULL DEFAULT now()
);
SELECT audit.attach('finance.payment_purpose');
COMMENT ON TABLE finance.payment_purpose IS
  'V409: what a payment is for, whatever the programme — the dimension a report groups by beside the programme type. Each purpose posts to its income account and says what a confirmed payment of it entitles.';
INSERT INTO finance.payment_purpose (code, label, ord, gl_account, entitlement) VALUES
    ('APPLICATION',            'Application fee',               10, '4030', 'The application may be completed and submitted'),
    ('ADMISSION_STATUS_CHECK', 'Admission status checking fee', 20, '4030', 'The admission status may be checked'),
    ('ACCEPTANCE_FEE',         'Acceptance fee',                30, '4020', 'The offer of admission is accepted'),
    ('SCREENING_FEE',          'Screening fee',                 40, '4090', 'Screening may proceed'),
    ('SCHOOL_FEES',            'School fees',                   50, '4010', 'Financial clearance for the session: registration, examinations and results'),
    ('LATE_SCHOOL_FEES',       'Late school fees',              55, '4010', 'Financial clearance for the session, paid late'),
    ('COURSE_REGISTRATION',    'Course registration fee',       60, '4090', 'Course registration may proceed'),
    ('LATE_REGISTRATION',      'Late registration fee',         65, '4090', 'Course registration may proceed in the late period'),
    ('EXAMINATION',            'Examination fee',               70, '4090', 'The examination may be sat'),
    ('HOSTEL_APPLICATION',     'Hostel application fee',        80, '4040', 'The hostel application may proceed'),
    ('HOSTEL_FEE',             'Hostel fee',                    85, '4040', 'The bed space is confirmed'),
    ('HOSTEL_DAMAGE',          'Hostel damage charge',          88, '4040', 'The damage charge is settled'),
    ('GST_FEE',                'GST fee',                       90, '4090', 'The GST entitlement for the session (and EPS, where the GST fee covers it)'),
    ('EPS_FEE',                'EPS fee',                       95, '4090', 'The EPS entitlement for the session'),
    ('TRANSCRIPT_FEE',         'Transcript fee',               100, '4050', 'The transcript request is processed'),
    ('CERTIFICATE_FEE',        'Certificate fee',              105, '4090', 'The certificate request is processed'),
    ('CONVOCATION_FEE',        'Convocation fee',              110, '4090', 'Convocation attendance is confirmed'),
    ('DEFERMENT_FEE',          'Deferment fee',                115, '4090', 'The deferment request may proceed'),
    ('TRANSFER_FEE',           'Inter-departmental transfer fee', 120, '4080', 'The transfer may take effect'),
    ('CHANGE_OF_PROGRAMME',    'Change of programme fee',      125, '4090', 'The change of programme may proceed'),
    ('ID_CARD',                'Identity card fee',            130, '4070', 'The identity card is issued'),
    ('LIBRARY_FINE',           'Library fine',                 140, '4090', 'The library account is cleared'),
    ('WALLET_TOP_UP',          'Wallet top-up',                150, '4090', 'The wallet is credited'),
    ('GATEWAY_TEST',           'Gateway test',                 990, '4090', NULL),
    ('OTHER',                  'Other',                        999, '4090', NULL);

-- every category (V279) names its purpose; the categories a payment of JUPEB, EPS and the other purposes falls in are added
ALTER TABLE finance.payment_category ADD COLUMN purpose text NULL REFERENCES finance.payment_purpose(code);
UPDATE finance.payment_category SET purpose = CASE code
        WHEN 'SCHOOL_FEES' THEN 'SCHOOL_FEES' WHEN 'APPLICATION' THEN 'APPLICATION' WHEN 'CHECKING' THEN 'ADMISSION_STATUS_CHECK'
        WHEN 'ACCEPTANCE' THEN 'ACCEPTANCE_FEE' WHEN 'PG_APPLICATION' THEN 'APPLICATION' WHEN 'PG_CHECKING' THEN 'ADMISSION_STATUS_CHECK'
        WHEN 'PG_ACCEPTANCE' THEN 'ACCEPTANCE_FEE' WHEN 'HOSTEL' THEN 'HOSTEL_FEE' WHEN 'HOSTEL_DAMAGE' THEN 'HOSTEL_DAMAGE'
        WHEN 'TRANSCRIPT' THEN 'TRANSCRIPT_FEE' WHEN 'GST' THEN 'GST_FEE' WHEN 'DEFERMENT' THEN 'DEFERMENT_FEE' WHEN 'TRANSFER' THEN 'TRANSFER_FEE'
        WHEN 'LIBRARY_FINE' THEN 'LIBRARY_FINE' WHEN 'WALLET' THEN 'WALLET_TOP_UP' WHEN 'GATEWAY_TEST' THEN 'GATEWAY_TEST' ELSE 'OTHER' END;
INSERT INTO finance.payment_category (code, label, kinds, pattern, ord, revenue, active, purpose) VALUES
    ('JUPEB_APPLICATION', 'JUPEB application fee', '{JUPEB_APPLICATION}', NULL, 100, true, true, 'APPLICATION'),
    ('JUPEB_CHECKING', 'JUPEB admission status checking fee', '{JUPEB_STATUS_CHECKING}', NULL, 101, true, true, 'ADMISSION_STATUS_CHECK'),
    ('JUPEB_ACCEPTANCE', 'JUPEB acceptance fee', '{JUPEB_ACCEPTANCE}', NULL, 102, true, true, 'ACCEPTANCE_FEE'),
    ('JUPEB_SCHOOL_FEES', 'JUPEB school fees', '{JUPEB_SCHOOL_FIRST,JUPEB_SCHOOL_SECOND,JUPEB_SCHOOL_FULL}', NULL, 103, true, true, 'SCHOOL_FEES'),
    ('EPS', 'Entrepreneurship studies (EPS) fee', '{}', '^eps', 104, true, true, 'EPS_FEE'),
    ('LATE_REGISTRATION', 'Late registration fee', '{}', '^late registration', 105, true, true, 'LATE_REGISTRATION'),
    ('CERTIFICATE', 'Certificate fee', '{}', '^certificate', 106, true, true, 'CERTIFICATE_FEE'),
    ('CONVOCATION', 'Convocation fee', '{}', '^convocation', 107, true, true, 'CONVOCATION_FEE'),
    ('ID_CARD', 'Identity card fee', '{}', '^(id card|identity card)', 108, true, true, 'ID_CARD')
ON CONFLICT (code) DO NOTHING;
UPDATE finance.payment_category SET purpose = 'OTHER' WHERE purpose IS NULL;
ALTER TABLE finance.payment_category ALTER COLUMN purpose SET DEFAULT 'OTHER';
ALTER TABLE finance.payment_category ALTER COLUMN purpose SET NOT NULL;
COMMENT ON COLUMN finance.payment_category.purpose IS 'V409: the purpose a payment of this category is for — a category may be as particular as the Bursary likes; the reports group by purpose and programme type.';

-- ── 3 · which module generated a payment and which office owns it ──────────────────────────────────────────────────
CREATE TABLE finance.payment_classification (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    purpose            text NULL REFERENCES finance.payment_purpose(code),   -- NULL: any purpose
    programme_type     text NULL REFERENCES finance.programme_type(code),    -- NULL: any programme type
    source_module      text NOT NULL CHECK (source_module ~ '^[A-Z][A-Z_]{1,30}$'),
    responsible_office text NOT NULL REFERENCES ref.office(code),
    note               text NULL,
    updated_by         uuid NULL,
    updated_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_payment_classification UNIQUE NULLS NOT DISTINCT (purpose, programme_type)
);
SELECT audit.attach('finance.payment_classification');
COMMENT ON TABLE finance.payment_classification IS
  'V409: the source module that generates a payment and the office that owns it, by purpose and programme type. The most particular rule wins: purpose and type, then purpose alone, then type alone, then the rule for everything. Source module and responsible office are kept apart: the Student Finance module may generate a payment the Bursary owns.';
INSERT INTO finance.payment_classification (purpose, programme_type, source_module, responsible_office, note) VALUES
    (NULL, NULL, 'STUDENT_FINANCE', 'bursar', 'Every payment no other rule claims'),
    ('SCHOOL_FEES', 'UNDERGRADUATE', 'STUDENT_FINANCE', 'bursar', NULL),
    ('APPLICATION', 'UNDERGRADUATE', 'ADMISSIONS', 'academic', 'Post-UTME, Direct Entry and transfer applications'),
    ('ADMISSION_STATUS_CHECK', 'UNDERGRADUATE', 'ADMISSIONS', 'academic', NULL),
    ('ACCEPTANCE_FEE', 'UNDERGRADUATE', 'ADMISSIONS', 'academic', NULL),
    ('SCREENING_FEE', 'UNDERGRADUATE', 'ADMISSIONS', 'academic', NULL),
    (NULL, 'POSTGRADUATE', 'PG', 'pgschool', 'The School''s applications, acceptance and fees'),
    (NULL, 'CCE', 'CCE', 'cce', 'The Centre''s applications, acceptance and fees'),
    (NULL, 'JUPEB', 'JUPEB', 'jupeb', 'The JUPEB Office''s applications, acceptance and fees'),
    (NULL, 'SANDWICH', 'SANDWICH', 'bursar', 'Until the University names the office that runs the Sandwich programme'),
    (NULL, 'PRELIMINARY', 'PRELIMINARY', 'bursar', 'Until the University names the office that runs it'),
    (NULL, 'REMEDIAL', 'REMEDIAL', 'bursar', 'Until the University names the office that runs it'),
    (NULL, 'FOUNDATION', 'FOUNDATION', 'bursar', 'Until the University names the office that runs it'),
    ('GST_FEE', NULL, 'GST', 'gst', 'Whatever the payer''s programme type'),
    ('EPS_FEE', NULL, 'EPS', 'eps', 'Whatever the payer''s programme type'),
    ('HOSTEL_APPLICATION', NULL, 'HOSTEL', 'housing', NULL),
    ('HOSTEL_FEE', NULL, 'HOSTEL', 'housing', NULL),
    ('HOSTEL_DAMAGE', NULL, 'HOSTEL', 'housing', NULL),
    ('TRANSCRIPT_FEE', NULL, 'REGISTRY', 'records', NULL),
    ('CERTIFICATE_FEE', NULL, 'REGISTRY', 'records', NULL),
    ('CONVOCATION_FEE', NULL, 'REGISTRY', 'registrar', NULL),
    ('DEFERMENT_FEE', NULL, 'REGISTRY', 'registrar', NULL),
    ('TRANSFER_FEE', NULL, 'REGISTRY', 'registrar', NULL),
    ('CHANGE_OF_PROGRAMME', NULL, 'ADMISSIONS', 'academic', NULL),
    ('LIBRARY_FINE', NULL, 'LIBRARY', 'library', NULL),
    ('GATEWAY_TEST', NULL, 'STUDENT_FINANCE', 'bursar', NULL);

/* the source module and responsible office of a purpose and programme type: the most particular rule */
CREATE OR REPLACE FUNCTION finance.payment_owner(p_purpose text, p_programme_type text)
RETURNS TABLE (source_module text, responsible_office text)
LANGUAGE sql STABLE AS $$
    SELECT c.source_module, c.responsible_office FROM finance.payment_classification c
     WHERE (c.purpose IS NULL OR c.purpose = p_purpose) AND (c.programme_type IS NULL OR c.programme_type = p_programme_type)
     ORDER BY (c.purpose IS NOT NULL) DESC, (c.programme_type IS NOT NULL) DESC
     LIMIT 1
$$;

-- ── 4 · the Bursary states the catalogue ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.set_programme_type(p_code text, p_label text, p_entry_modes text[], p_programme_categories text[],
                                                      p_study_mode text, p_ord int, p_active boolean, p_description text)
RETURNS finance.programme_type
LANGUAGE plpgsql AS $$
DECLARE r finance.programme_type; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a programme type is stated by a person' USING ERRCODE = '23514'; END IF;
    IF upper(btrim(p_code)) = 'OTHER' AND coalesce(p_active, true) = false THEN
        RAISE EXCEPTION 'PAY_TYPE_OTHER: the type Other stays, so every payer has one' USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.programme_type (code, label, entry_modes, programme_categories, study_mode, ord, active, description, updated_by, updated_at)
    VALUES (upper(btrim(p_code)), btrim(p_label),
            coalesce((SELECT array_agg(DISTINCT upper(btrim(x))) FROM unnest(p_entry_modes) x WHERE btrim(x) <> ''), '{}'),
            coalesce((SELECT array_agg(DISTINCT upper(btrim(x))) FROM unnest(p_programme_categories) x WHERE btrim(x) <> ''), '{}'),
            nullif(upper(btrim(coalesce(p_study_mode, ''))), ''), coalesce(p_ord, 100), coalesce(p_active, true), nullif(btrim(coalesce(p_description, '')), ''), v_actor, now())
    ON CONFLICT (code) DO UPDATE SET label = EXCLUDED.label, entry_modes = EXCLUDED.entry_modes, programme_categories = EXCLUDED.programme_categories,
        study_mode = EXCLUDED.study_mode, ord = EXCLUDED.ord, active = EXCLUDED.active, description = EXCLUDED.description, updated_by = v_actor, updated_at = now()
    RETURNING * INTO r;
    RETURN r;
END $$;

CREATE OR REPLACE FUNCTION finance.set_payment_classification(p_purpose text, p_programme_type text, p_source_module text, p_responsible_office text, p_note text)
RETURNS finance.payment_classification
LANGUAGE plpgsql AS $$
DECLARE r finance.payment_classification; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_purpose text := nullif(upper(btrim(coalesce(p_purpose, ''))), ''); v_type text := nullif(upper(btrim(coalesce(p_programme_type, ''))), '');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a classification is stated by a person' USING ERRCODE = '23514'; END IF;
    INSERT INTO finance.payment_classification (purpose, programme_type, source_module, responsible_office, note, updated_by, updated_at)
    VALUES (v_purpose, v_type, upper(btrim(p_source_module)), lower(btrim(p_responsible_office)), nullif(btrim(coalesce(p_note, '')), ''), v_actor, now())
    ON CONFLICT ON CONSTRAINT uq_payment_classification DO UPDATE SET source_module = EXCLUDED.source_module, responsible_office = EXCLUDED.responsible_office,
        note = EXCLUDED.note, updated_by = v_actor, updated_at = now()
    RETURNING * INTO r;
    RETURN r;
END $$;

-- ── 5 · the one ledger, with JUPEB's references and every dimension ────────────────────────────────────────────────
CREATE OR REPLACE VIEW reporting.payments AS
    -- a student's payments: school fees and every other purpose the portal charges a student for
    SELECT 'STUDENT'::text AS source, r.id AS payment_id, r.reference, r.receipt_no, r.purpose, NULL::text AS kind,
           k.code AS category_code,
           r.amount, r.generated_at, r.confirmed_at, r.expires_at, r.channel, r.session,
           st.id AS student_id, NULL::uuid AS application_id, NULL::uuid AS pg_application_id, st.id::text AS payer_key,
           st.surname, st.other_names, coalesce(st.matric_no, st.admission_no) AS number, st.sex, st.entry_mode, st.entry_session, st.status,
           f.code AS faculty_code, f.name AS faculty, d.code AS dept_code, d.name AS department, p.code AS programme_code, p.name AS programme,
           reporting.level_in_session(st.entry_level, st.entry_session, st.current_level, st.entry_mode, r.session) AS level,
           st.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE' AS is_pg,
           coalesce(f.college_code, '') = 'CHS' AS is_chs,
           -- V409
           pt.code AS programme_type, finance.admission_route_of(st.entry_mode) AS admission_route, st.study_mode,
           coalesce(cat.purpose, 'OTHER') AS purpose_code, own.source_module, own.responsible_office,
           CASE WHEN r.purpose ~* '(first|1st) semester' THEN 1 WHEN r.purpose ~* '(second|2nd) semester' THEN 2 END AS semester,
           st.jamb_reg_no, NULL::text AS application_no, NULL::text AS exam_no, NULL::uuid AS jupeb_application_id,
           CASE WHEN r.confirmed_at IS NOT NULL THEN 'PAID' WHEN r.expires_at <= now() THEN 'EXPIRED' ELSE 'PENDING' END AS ledger_status
      FROM finance.payment_reference r
      JOIN people.student st ON st.id = r.student_id
      JOIN ref.programme p ON p.code = st.programme_code
      JOIN ref.faculty f ON f.code = p.faculty_code
      JOIN ref.department d ON d.code = p.dept_code
      CROSS JOIN LATERAL (SELECT finance.categorise(NULL, r.purpose) AS code) k
      LEFT JOIN finance.payment_category cat ON cat.code = k.code
      CROSS JOIN LATERAL (SELECT finance.programme_type_for(st.entry_mode, p.category) AS code) pt
      LEFT JOIN LATERAL finance.payment_owner(coalesce(cat.purpose, 'OTHER'), pt.code) own ON true
    UNION ALL
    -- an applicant's: the application, admission checking and acceptance fees (UTME, Direct Entry, transfer and CCE)
    SELECT 'APPLICANT'::text, fr.id, fr.reference, fr.receipt_no, NULL::text, fr.kind,
           k.code,
           fr.amount, fr.generated_at, fr.confirmed_at, fr.expires_at, fr.channel, a.session,
           s.id, a.id, NULL::uuid, coalesce(s.id::text, a.id::text),
           c.surname, c.other_names, coalesce(s.matric_no, s.admission_no, a.application_no), coalesce(s.sex, cr.sex), c.entry_mode, a.session,
           coalesce(s.status, 'APPLICANT'),
           f.code, f.name, d.code, d.name, p.code, p.name,
           c.entry_level, false, coalesce(f.college_code, '') = 'CHS',
           pt.code, finance.admission_route_of(c.entry_mode), CASE WHEN c.entry_mode = 'CCE' THEN 'PART_TIME' ELSE 'FULL_TIME' END,
           coalesce(cat.purpose, 'OTHER'), own.source_module, own.responsible_office,
           NULL::int, c.jamb_reg_no, a.application_no, NULL::text, NULL::uuid,
           CASE WHEN fr.confirmed_at IS NOT NULL THEN 'PAID' WHEN fr.expires_at <= now() THEN 'EXPIRED' ELSE 'PENDING' END
      FROM admissions.fee_reference fr
      JOIN admissions.application a ON a.id = fr.application_id
      JOIN admissions.candidate c ON c.id = a.candidate_id
      LEFT JOIN admissions.caps_row cr ON cr.id = c.admitted_from
      LEFT JOIN people.student s ON s.candidate_id = c.id
      LEFT JOIN ref.programme p ON p.code = admissions.programme_code_of(c.programme)
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      CROSS JOIN LATERAL (SELECT finance.categorise(fr.kind, NULL) AS code) k
      LEFT JOIN finance.payment_category cat ON cat.code = k.code
      CROSS JOIN LATERAL (SELECT finance.programme_type_for(c.entry_mode, p.category) AS code) pt
      LEFT JOIN LATERAL finance.payment_owner(coalesce(cat.purpose, 'OTHER'), pt.code) own ON true
    UNION ALL
    -- the School of Postgraduate Studies' applicants: the application, checking and acceptance fees
    SELECT 'PG'::text, fr.id, fr.reference, NULL::text, NULL::text, 'PG_' || fr.kind,
           k.code,
           fr.amount, fr.generated_at, fr.confirmed_at, fr.expires_at, fr.channel, pa.session,
           pa.student_id, NULL::uuid, pa.id, coalesce(pa.student_id::text, pa.id::text),
           ap.surname, ap.other_names, coalesce(s.matric_no, s.admission_no, pa.application_no), coalesce(s.sex, ap.sex), 'POSTGRADUATE', pa.session,
           coalesce(s.status, pa.state),
           f.code, f.name, d.code, d.name, p.code, p.name,
           coalesce(s.current_level, pa.entry_level), true, coalesce(f.college_code, '') = 'CHS',
           pt.code, 'POSTGRADUATE', s.study_mode,
           coalesce(cat.purpose, 'OTHER'), own.source_module, own.responsible_office,
           NULL::int, NULL::text, pa.application_no, NULL::text, NULL::uuid,
           CASE WHEN fr.confirmed_at IS NOT NULL THEN 'PAID' WHEN fr.expires_at <= now() THEN 'EXPIRED' ELSE 'PENDING' END
      FROM admissions.pg_fee_reference fr
      JOIN admissions.pg_application pa ON pa.id = fr.application_id
      JOIN admissions.pg_applicant ap ON ap.id = pa.applicant_id
      LEFT JOIN people.student s ON s.id = pa.student_id
      LEFT JOIN ref.programme p ON p.code = pa.programme_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      CROSS JOIN LATERAL (SELECT finance.categorise('PG_' || fr.kind, NULL) AS code) k
      LEFT JOIN finance.payment_category cat ON cat.code = k.code
      CROSS JOIN LATERAL (SELECT finance.programme_type_for('POSTGRADUATE', 'POST GRADUATE') AS code) pt
      LEFT JOIN LATERAL finance.payment_owner(coalesce(cat.purpose, 'OTHER'), pt.code) own ON true
    UNION ALL
    -- V409: JUPEB's references — application, admission status checking, acceptance and school fees — on the same ledger
    SELECT 'JUPEB'::text, jf.id, jf.reference, NULL::text, NULL::text, 'JUPEB_' || jf.kind,
           k.code,
           jf.amount, jf.created_at, jf.confirmed_at, jf.expires_at, jf.channel, jf.session,
           NULL::uuid, NULL::uuid, NULL::uuid, ja.id::text,
           ja.surname, concat_ws(' ', nullif(btrim(ja.first_name), ''), nullif(btrim(ja.middle_name), '')), ja.application_no, ja.sex, 'JUPEB', ja.session,
           ja.state,
           f.code, f.name, d.code, d.name, p.code, p.name,
           NULL::int, false, coalesce(f.college_code, '') = 'CHS',
           pt.code, 'JUPEB', 'FULL_TIME',
           coalesce(cat.purpose, 'OTHER'), own.source_module, own.responsible_office,
           jf.semester, NULL::text, ja.application_no, ja.exam_no, ja.id,
           CASE WHEN jf.confirmed_at IS NOT NULL THEN 'PAID' WHEN jf.expires_at <= now() THEN 'EXPIRED' ELSE 'PENDING' END
      FROM jupeb.fee_reference jf
      JOIN jupeb.application ja ON ja.id = jf.application_id
      LEFT JOIN ref.programme p ON p.code = ja.programme_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      CROSS JOIN LATERAL (SELECT finance.categorise('JUPEB_' || jf.kind, NULL) AS code) k
      LEFT JOIN finance.payment_category cat ON cat.code = k.code
      CROSS JOIN LATERAL (SELECT finance.programme_type_for('JUPEB', NULL) AS code) pt
      LEFT JOIN LATERAL finance.payment_owner(coalesce(cat.purpose, 'OTHER'), pt.code) own ON true;
COMMENT ON VIEW reporting.payments IS
  'The one payment ledger (V279; V409): every reference the portal generated — a student''s, an applicant''s (UTME, Direct Entry, transfer, CCE), the School''s, JUPEB''s — with its category and, as separate dimensions, its programme type, admission route, study mode, purpose, source module and responsible office (finance.programme_type, finance.payment_purpose, finance.payment_classification), the payer''s faculty, department, programme and level, and its ledger status. Read on the server; never classified by a request.';

-- ── 6 · the general ledger: every confirmed payment of the ledger, not only a student's ──────────────────────────
CREATE OR REPLACE FUNCTION finance.gl_sync() RETURNS TABLE (payments int, refunds int, vouchers int)
LANGUAGE plpgsql AS $$
DECLARE r record; v_p int := 0; v_r int := 0; v_v int := 0;
BEGIN
    -- confirmed student payments → Dr Bank (Collections), Cr the income account
    FOR r IN
        SELECT pr.reference, pr.confirmed_at::date AS d, pr.amount, pr.session,
               finance.payment_category(pr.purpose) AS cat, pr.purpose
          FROM finance.payment_reference pr
         WHERE pr.confirmed_at IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'PAYMENT' AND j.source_ref = pr.reference)
    LOOP
        PERFORM finance.gl_post(r.d, 'Fee receipt ' || r.reference || ' — ' || r.cat, 'AUTO', 'PAYMENT', r.reference,
            jsonb_build_array(
                jsonb_build_object('account','1010','debit', r.amount, 'narration', r.purpose, 'session', r.session),
                jsonb_build_object('account', finance.gl_income_account(r.cat), 'credit', r.amount, 'narration', r.purpose, 'session', r.session)));
        v_p := v_p + 1;
    END LOOP;

    -- V409: every other confirmed payment of the one ledger — an applicant's, the School's, JUPEB's — Dr Bank (Collections),
    -- Cr the income account of its purpose, narrated by programme type and purpose
    FOR r IN
        SELECT v.reference, v.confirmed_at::date AS d, v.amount, v.session, pp.gl_account,
               concat_ws(' ', t.label, lower(pp.label)) AS narration
          FROM reporting.payments v
          LEFT JOIN finance.payment_purpose pp ON pp.code = v.purpose_code
          LEFT JOIN finance.programme_type t ON t.code = v.programme_type
         WHERE v.source <> 'STUDENT' AND v.confirmed_at IS NOT NULL AND v.amount > 0
           AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'PAYMENT' AND j.source_ref = v.reference)
    LOOP
        PERFORM finance.gl_post(r.d, 'Fee receipt ' || r.reference || ' — ' || r.narration, 'AUTO', 'PAYMENT', r.reference,
            jsonb_build_array(
                jsonb_build_object('account','1010','debit', r.amount, 'narration', r.narration, 'session', r.session),
                jsonb_build_object('account', coalesce(r.gl_account, '4090'), 'credit', r.amount, 'narration', r.narration, 'session', r.session)));
        v_p := v_p + 1;
    END LOOP;

    -- paid refunds → Dr Refunds of fees, Cr Bank (Disbursements)
    FOR r IN
        SELECT rf.reference, rf.paid_at::date AS d, rf.amount, rf.reason
          FROM finance.refund rf
         WHERE rf.state = 'PAID' AND rf.paid_at IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'REFUND' AND j.source_ref = rf.reference)
    LOOP
        PERFORM finance.gl_post(r.d, 'Refund ' || r.reference || ' — ' || r.reason, 'AUTO', 'REFUND', r.reference,
            jsonb_build_array(
                jsonb_build_object('account','4990','debit', r.amount, 'narration', r.reason),
                jsonb_build_object('account','1020','credit', r.amount, 'narration', r.reason)));
        v_r := v_r + 1;
    END LOOP;

    -- paid vouchers → Dr the expense account, Cr Bank (Disbursements)
    FOR r IN
        SELECT v.reference, v.paid_at::date AS d, v.amount, v.title, v.kind, v.payee
          FROM expenditure.voucher v
         WHERE v.stage = 'PAID' AND v.paid_at IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'VOUCHER' AND j.source_ref = v.reference)
    LOOP
        PERFORM finance.gl_post(r.d, 'Voucher ' || r.reference || ' — ' || r.title || ' (' || r.payee || ')',
            'AUTO', 'VOUCHER', r.reference,
            jsonb_build_array(
                jsonb_build_object('account', finance.gl_expense_account(r.kind), 'debit', r.amount, 'narration', r.title),
                jsonb_build_object('account','1020','credit', r.amount, 'narration', r.payee)));
        v_v := v_v + 1;
    END LOOP;

    payments := v_p; refunds := v_r; vouchers := v_v; RETURN NEXT;
END $$;
COMMENT ON FUNCTION finance.gl_sync() IS
  'Posts what the ledger has not yet posted: every confirmed payment (a student''s by its purpose words, V145; V409: an applicant''s, the School''s and JUPEB''s by the income account of its purpose), every paid refund and every paid voucher — each once, by (source type, reference).';

COMMIT;
