-- ═══════════════════════════════════════════════════════════════════════════
-- V279 — one payment ledger for the analytics, and configurable payment categories
--
--   Money reaches the University through three reference tables — a student's
--   (finance.payment_reference: school fees, hostel, transcript, deferment,
--   transfer, fines, wallet), an undergraduate applicant's
--   (admissions.fee_reference: application, checking, acceptance) and a
--   postgraduate applicant's (admissions.pg_fee_reference). Each row's purpose
--   or kind said what it was for in words; nothing named the category, and no
--   one place joined a payment to the person's faculty, department, programme,
--   level, sex, entry mode and session at the time.
--
--   reporting.payments is that one place: every reference, confirmed or not,
--   with its category and the payer's dimensions, read from the authoritative
--   tables, never copied. A payment counts as revenue when it is confirmed
--   (confirmed_at) — the same rule every receipt, position and return uses.
--   finance.payment_category is the Bursary's list of categories, each with the
--   reference kinds and the purpose pattern that place a payment in it; a new
--   category appears in every filter, chart and report without a code change.
--   The level a student was at when they paid is the level for the payment's
--   session, not today's; the session is the reference's own.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V279: the payment ledger and its categories', true);

/* ── the categories: configured, ordered, matched by kind or by purpose ── */
CREATE TABLE IF NOT EXISTS finance.payment_category (
    code        text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9_]{1,39}$'),
    label       text NOT NULL,
    kinds       text[] NOT NULL DEFAULT '{}',        -- reference kinds that fall in it (APPLICATION, CHECKING, ACCEPTANCE, PG_…)
    pattern     text NULL,                           -- a case-insensitive regular expression over the purpose
    ord         int NOT NULL DEFAULT 100,
    revenue     boolean NOT NULL DEFAULT true,       -- counted in revenue (a gateway test is not)
    active      boolean NOT NULL DEFAULT true,
    stated_by   uuid NULL,
    updated_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE finance.payment_category IS 'The Bursary''s payment categories (V279): a payment falls in the first active category, by ord, whose kinds hold its reference kind or whose pattern matches its purpose; else OTHER.';
SELECT audit.attach('finance.payment_category');

INSERT INTO finance.payment_category (code, label, kinds, pattern, ord, revenue) VALUES
    ('SCHOOL_FEES',     'School fees',                       '{}',                '^school fees',                              10, true),
    ('APPLICATION',     'Application & Post-UTME fee',       '{APPLICATION}',     NULL,                                        20, true),
    ('CHECKING',        'Admission checking fee',            '{CHECKING}',        NULL,                                        30, true),
    ('ACCEPTANCE',      'Acceptance fee',                    '{ACCEPTANCE}',      NULL,                                        40, true),
    ('PG_APPLICATION',  'Postgraduate application fee',      '{PG_APPLICATION}',  NULL,                                        50, true),
    ('PG_CHECKING',     'Postgraduate checking fee',         '{PG_CHECKING}',     NULL,                                        55, true),
    ('PG_ACCEPTANCE',   'Postgraduate acceptance fee',       '{PG_ACCEPTANCE}',   NULL,                                        60, true),
    ('HOSTEL',          'Hostel accommodation',              '{}',                '^hostel accommodation(?! damage)',          70, true),
    ('HOSTEL_DAMAGE',   'Hostel damage charge',              '{}',                '^hostel accommodation damage',              75, true),
    ('TRANSCRIPT',      'Transcript fee',                    '{}',                '^transcript',                               80, true),
    ('DEFERMENT',       'Deferment application fee',         '{}',                '^deferment',                                90, true),
    ('TRANSFER',        'Inter-departmental transfer fee',   '{}',                '^inter-departmental transfer',             100, true),
    ('LIBRARY_FINE',    'Library fine',                      '{}',                '^library fine',                            110, true),
    ('WALLET',          'Wallet top-up',                     '{}',                '^wallet top-up',                           120, true),
    ('GATEWAY_TEST',    'Gateway test (Bursary)',            '{}',                '^gateway test',                            900, false),
    ('OTHER',           'Other',                             '{}',                NULL,                                       999, true)
ON CONFLICT (code) DO NOTHING;

/* the category a payment falls in: by its reference kind, else by its purpose, else OTHER */
CREATE OR REPLACE FUNCTION finance.categorise(p_kind text, p_purpose text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce((
        SELECT c.code FROM finance.payment_category c
         WHERE c.active AND c.code <> 'OTHER'
           AND ((p_kind IS NOT NULL AND p_kind = ANY (c.kinds))
                OR (p_purpose IS NOT NULL AND c.pattern IS NOT NULL AND p_purpose ~* c.pattern))
         ORDER BY c.ord, c.code LIMIT 1), 'OTHER');
$$;

/* the Bursary states or amends a category (a code is never deleted: it is deactivated) */
CREATE OR REPLACE FUNCTION finance.set_payment_category(p_code text, p_label text, p_kinds text[], p_pattern text, p_ord int, p_revenue boolean, p_active boolean)
RETURNS finance.payment_category LANGUAGE plpgsql AS $$
DECLARE r finance.payment_category; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a payment category is stated by a person' USING ERRCODE = '23514'; END IF;
    IF p_pattern IS NOT NULL THEN PERFORM 'x' ~* p_pattern; END IF;   -- a bad expression fails here, not on every report
    INSERT INTO finance.payment_category (code, label, kinds, pattern, ord, revenue, active, stated_by, updated_at)
    VALUES (upper(btrim(p_code)), btrim(p_label), coalesce(p_kinds, '{}'), nullif(btrim(coalesce(p_pattern, '')), ''), coalesce(p_ord, 100), coalesce(p_revenue, true), coalesce(p_active, true), v_actor, now())
    ON CONFLICT (code) DO UPDATE SET label = EXCLUDED.label, kinds = EXCLUDED.kinds, pattern = EXCLUDED.pattern, ord = EXCLUDED.ord,
        revenue = EXCLUDED.revenue, active = EXCLUDED.active, stated_by = EXCLUDED.stated_by, updated_at = now()
    RETURNING * INTO r;
    RETURN r;
END $$;

/* the level a student was at in a session: the entry level advanced a year per session for an undergraduate; a postgraduate's is their level */
CREATE OR REPLACE FUNCTION reporting.level_in_session(p_entry_level int, p_entry_session text, p_current_level int, p_entry_mode text, p_session text)
RETURNS int LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_entry_mode = 'POSTGRADUATE' OR p_session IS NULL OR p_entry_session IS NULL
                     OR p_session !~ '^[0-9]{4}' OR p_entry_session !~ '^[0-9]{4}' THEN p_current_level
                ELSE least(600, greatest(100, coalesce(p_entry_level, 100) + (left(p_session, 4)::int - left(p_entry_session, 4)::int) * 100)) END;
$$;

/* ── the ledger: every payment reference with its category and the payer's dimensions ── */
CREATE OR REPLACE VIEW reporting.payments AS
    -- a student's payments: school fees and every other purpose the portal charges a student for
    SELECT 'STUDENT'::text AS source, r.id AS payment_id, r.reference, r.receipt_no, r.purpose, NULL::text AS kind,
           finance.categorise(NULL, r.purpose) AS category_code,
           r.amount, r.generated_at, r.confirmed_at, r.expires_at, r.channel, r.session,
           st.id AS student_id, NULL::uuid AS application_id, NULL::uuid AS pg_application_id, st.id::text AS payer_key,
           st.surname, st.other_names, coalesce(st.matric_no, st.admission_no) AS number, st.sex, st.entry_mode, st.entry_session, st.status,
           f.code AS faculty_code, f.name AS faculty, d.code AS dept_code, d.name AS department, p.code AS programme_code, p.name AS programme,
           reporting.level_in_session(st.entry_level, st.entry_session, st.current_level, st.entry_mode, r.session) AS level,
           (st.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE') AS is_pg, (coalesce(f.college_code, '') = 'CHS') AS is_chs
      FROM finance.payment_reference r
      JOIN people.student st ON st.id = r.student_id
      JOIN ref.programme p ON p.code = st.programme_code
      JOIN ref.faculty f ON f.code = p.faculty_code
      JOIN ref.department d ON d.code = p.dept_code
    UNION ALL
    -- an undergraduate applicant's payments: application, checking, acceptance — the person as JAMB sent them
    SELECT 'APPLICANT', fr.id, fr.reference, fr.receipt_no, NULL, fr.kind,
           finance.categorise(fr.kind, NULL),
           fr.amount, fr.generated_at, fr.confirmed_at, fr.expires_at, fr.channel, a.session,
           s.id, a.id, NULL, coalesce(s.id::text, a.id::text),
           c.surname, c.other_names, coalesce(s.matric_no, s.admission_no, a.application_no), coalesce(s.sex, cr.sex), c.entry_mode, a.session,
           coalesce(s.status, 'APPLICANT'),
           f.code, f.name, d.code, d.name, p.code, p.name,
           c.entry_level,
           false, (coalesce(f.college_code, '') = 'CHS')
      FROM admissions.fee_reference fr
      JOIN admissions.application a ON a.id = fr.application_id
      JOIN admissions.candidate c ON c.id = a.candidate_id
      LEFT JOIN admissions.caps_row cr ON cr.id = c.admitted_from
      LEFT JOIN people.student s ON s.candidate_id = c.id
      LEFT JOIN ref.programme p ON p.code = admissions.programme_code_of(c.programme)
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
    UNION ALL
    -- a postgraduate applicant's payments
    SELECT 'PG', fr.id, fr.reference, NULL, NULL, 'PG_' || fr.kind,
           finance.categorise('PG_' || fr.kind, NULL),
           fr.amount, fr.generated_at, fr.confirmed_at, fr.expires_at, fr.channel, pa.session,
           pa.student_id, NULL, pa.id, coalesce(pa.student_id::text, pa.id::text),
           ap.surname, ap.other_names, coalesce(s.matric_no, s.admission_no, pa.application_no), coalesce(s.sex, ap.sex), 'POSTGRADUATE', pa.session,
           coalesce(s.status, pa.state),
           f.code, f.name, d.code, d.name, p.code, p.name,
           coalesce(s.current_level, pa.entry_level),
           true, (coalesce(f.college_code, '') = 'CHS')
      FROM admissions.pg_fee_reference fr
      JOIN admissions.pg_application pa ON pa.id = fr.application_id
      JOIN admissions.pg_applicant ap ON ap.id = pa.applicant_id
      LEFT JOIN people.student s ON s.id = pa.student_id
      LEFT JOIN ref.programme p ON p.code = pa.programme_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN ref.department d ON d.code = p.dept_code;

COMMENT ON VIEW reporting.payments IS 'Every payment reference the portal generated — a student''s, an undergraduate applicant''s, a postgraduate applicant''s — with its category and the payer''s dimensions (V279). Revenue is the rows with confirmed_at set; the session is the reference''s own; the level is the level for that session.';

/* the indexes the ledger's date questions lean on */
CREATE INDEX IF NOT EXISTS ix_payment_reference_confirmed ON finance.payment_reference (confirmed_at) WHERE confirmed_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_fee_reference_confirmed ON admissions.fee_reference (confirmed_at) WHERE confirmed_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_pg_fee_reference_confirmed ON admissions.pg_fee_reference (confirmed_at) WHERE confirmed_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_gateway_event_received ON finance.gateway_event (received_at);

/* the student positions carry the sex and the entry session too, so the student statistics count by them */
DROP FUNCTION IF EXISTS reporting.student_positions(text, int);
CREATE OR REPLACE FUNCTION reporting.student_positions(p_session text, p_semester int)
RETURNS TABLE (
    student_id uuid, surname text, other_names text, number text,
    faculty_code text, faculty text, dept_code text, department text, programme_code text, programme text,
    level int, status text, entry_mode text, is_pg boolean, is_chs boolean, college_code text, degree_type text,
    payable numeric, paid_amount numeric, outstanding numeric, pay_status text, paid boolean, last_paid_at timestamptz, last_reference text,
    registered boolean, registration_status text, registered_at timestamptz,
    sex text, entry_session text, matriculated_at timestamptz
)
LANGUAGE sql STABLE AS $$
    SELECT st.id, st.surname, st.other_names, coalesce(st.matric_no, st.admission_no),
           f.code, f.name, d.code, d.name, p.code, p.name,
           st.current_level, st.status, st.entry_mode,
           (st.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE'),
           (coalesce(f.college_code, '') = 'CHS'), f.college_code,
           CASE WHEN st.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE'
                THEN CASE WHEN upper(coalesce(p.pg_award, '')) IN ('PHD') THEN 'PHD'
                          WHEN upper(coalesce(p.pg_award, '')) IN ('MPHIL') THEN 'MPHIL'
                          WHEN upper(coalesce(p.pg_award, '')) = 'PGD' THEN 'PGD'
                          WHEN p.pg_award IS NOT NULL AND p.pg_award <> '' THEN 'MASTERS'
                          WHEN st.current_level >= 900 THEN 'PHD' WHEN st.current_level >= 800 THEN 'MASTERS' ELSE 'PGD' END
                ELSE NULL END,
           pos.payable, pos.paid, pos.outstanding, pos.status, pos.status = 'FULLY_PAID', pos.last_paid_at, pos.last_reference,
           reg.registered, reg.registration_status, reg.registered_at,
           st.sex, st.entry_session, st.matriculated_at
      FROM people.student st
      JOIN ref.programme p ON p.code = st.programme_code
      JOIN ref.faculty f ON f.code = p.faculty_code
      JOIN ref.department d ON d.code = p.dept_code
      CROSS JOIN LATERAL finance.payment_position(st.id, p_session, p_semester) pos
      CROSS JOIN LATERAL (
          SELECT r.registered, r.registration_status, r.registered_at FROM (
              SELECT (x.state IN ('SUBMITTED','ENDORSED')) AS registered, x.state AS registration_status, coalesce(x.endorsed_at, x.updated_at) AS registered_at, 1 AS pick
                FROM admissions.pg_registration x
               WHERE st.entry_mode = 'POSTGRADUATE' AND x.student_id = st.id AND x.session = p_session AND (p_semester IS NULL OR x.semester = p_semester)
               ORDER BY (x.state IN ('SUBMITTED','ENDORSED')) DESC, x.semester DESC LIMIT 1
          ) r
          UNION ALL
          SELECT r.registered, r.registration_status, r.registered_at FROM (
              SELECT (e.registered_at IS NOT NULL OR (p_semester IS NOT NULL AND EXISTS (
                          SELECT 1 FROM college.enrolment_semester es WHERE es.enrolment_id = e.id AND es.ordinal = p_semester AND es.registered_at IS NOT NULL))) AS registered,
                     CASE WHEN e.registered_at IS NOT NULL THEN 'REGISTERED' ELSE 'OPEN' END AS registration_status,
                     coalesce(e.registered_at, (SELECT max(es.registered_at) FROM college.enrolment_semester es WHERE es.enrolment_id = e.id)) AS registered_at, 2 AS pick
                FROM college.enrolment e
               WHERE st.entry_mode <> 'POSTGRADUATE' AND coalesce(f.college_code, '') = 'CHS' AND st.current_level >= 200
                 AND e.student_id = st.id AND e.session = p_session AND e.state IN ('OPEN','RESIT','CLOSED')
               ORDER BY e.registered_at DESC NULLS LAST LIMIT 1
          ) r
          UNION ALL
          SELECT r.registered, r.registration_status, r.registered_at FROM (
              SELECT (x.status IN ('SUBMITTED','APPROVED','LOCKED')) AS registered, x.status AS registration_status,
                     coalesce(x.approved_at, x.submitted_at) AS registered_at, 3 AS pick
                FROM registration.course_registration x
               WHERE st.entry_mode <> 'POSTGRADUATE' AND NOT (coalesce(f.college_code, '') = 'CHS' AND st.current_level >= 200)
                 AND x.student_id = st.id AND x.session = p_session AND (p_semester IS NULL OR x.semester = p_semester)
               ORDER BY (x.status IN ('SUBMITTED','APPROVED','LOCKED')) DESC, x.semester DESC LIMIT 1
          ) r
          UNION ALL
          SELECT false, NULL::text, NULL::timestamptz
          ORDER BY registered DESC NULLS LAST LIMIT 1
      ) reg
     WHERE st.status IN ('ACTIVE','PROBATION','ADMITTED');
$$;

COMMENT ON FUNCTION reporting.student_positions(text, int) IS
  'Every student in study (ACTIVE, PROBATION, ADMITTED) with their fee position and registration for a session '
  '(semester NULL) or one semester of it: the one set of rows the student statistics count and list (V257), '
  'with the sex, the entry session and the matriculation date since V279.';

GRANT SELECT ON reporting.payments TO app_finance, app_reporting, app_admissions, app_student;
GRANT SELECT ON finance.payment_category TO app_finance, app_reporting, app_admissions, app_student;
GRANT INSERT, UPDATE ON finance.payment_category TO app_finance;

COMMIT;
