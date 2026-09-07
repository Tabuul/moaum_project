-- ═══════════════════════════════════════════════════════════════════════════
-- V001 — schemas, module roles and grants
--
-- ADR-006: each module owns a PostgreSQL schema and connects with a role
-- granted only on that schema. Boundaries enforced in Java alone are one
-- JDBC template away from being bypassed.
--
-- Two rules this file exists to make true, and both are refusals:
--   · a query against another module's schema fails with a permission error
--     in development, long before it can fail in production;
--   · no application role anywhere holds DELETE. Nothing is deleted (D11);
--     a record is ended with an effective date and a reason.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── the module schemas ────────────────────────────────────────────────────
-- Schema names are NOT package names, and they are not derived from them.
-- The mapping is published in ARC (see the reconciliation paper); it is a
-- lookup, not a convention, because four modules own a schema whose name
-- differs from the package (`student`/people, `results`/assessment,
-- `credentials`/clearance, `registration`/catalogue).

CREATE SCHEMA iam;            -- IAM   · identity, offices, grants
CREATE SCHEMA people;         -- SIM   · the person and the student
CREATE SCHEMA admissions;     -- ADM
CREATE SCHEMA catalogue;      -- CRG   · programmes, courses, eligible sets
CREATE SCHEMA registration;   -- CRG   · registrations against offerings
CREATE SCHEMA assessment;     -- RES   · score sheets, marks, approval acts
CREATE SCHEMA records;        -- ACR
CREATE SCHEMA credentials;    -- CTP   · transcripts, certificates, cards
CREATE SCHEMA clearance;      -- CTP   · clearance items and their holders
CREATE SCHEMA finance;        -- FIN
CREATE SCHEMA payments;       -- EPS
CREATE SCHEMA expenditure;    -- EXA   · vouchers and the pre-payment gate
CREATE SCHEMA notify;         -- NTF
CREATE SCHEMA governance;     -- DGV
CREATE SCHEMA reporting;      -- RBI   · read models, refreshed from events
CREATE SCHEMA apimgmt;        -- API   · consumers, keys, rate limits

-- ── the two schemas every module may read ─────────────────────────────────
CREATE SCHEMA ref;            -- currencies, states, LGAs, ISO codes
CREATE SCHEMA policy;         -- effective-dated institutional policy

-- ── platform, and audit ───────────────────────────────────────────────────
-- These are separated deliberately. `platform` holds machinery the
-- application reads and writes (sessions, idempotency keys, number series).
-- `audit` holds the spine, and NO application role may write to it at all
-- (V002). One schema carrying both grant profiles is how an audit table
-- acquires an application write path by accident.
CREATE SCHEMA platform;
CREATE SCHEMA audit;

COMMENT ON SCHEMA audit IS
  'The audit spine. No application role holds INSERT, UPDATE or DELETE here. '
  'Rows are appended by SECURITY DEFINER triggers on the business tables.';

-- ── reference data every module reads ─────────────────────────────────────
CREATE TABLE ref.office (
    code        text PRIMARY KEY,
    label       text NOT NULL,
    scope_kind  text NOT NULL,
    CONSTRAINT ck_office_scope CHECK (scope_kind IN
        ('institution','college','faculty','department','programme',
         'course','unit','platform'))
);

COMMENT ON TABLE ref.office IS
  'The twenty-five offices that sign in (ROL-MOAUMPP-001 v0.7 §1.1). '
  'An office is added to a person, never substituted: a Head of Department '
  'is still a lecturer, and keeps the lecturer grant alongside.';

INSERT INTO ref.office (code, label, scope_kind) VALUES
 ('lecturer',         'Lecturer',                                    'course'),
 ('hod',              'Head of Department',                          'department'),
 ('exams',            'Examinations Officer',                        'programme'),
 ('facultyexams',     'Faculty Examinations Officer',                'faculty'),
 ('facultyofficer',   'Faculty Officer',                             'faculty'),
 ('dean',             'Dean',                                        'faculty'),
 ('records',          'Exams and Records',                           'institution'),
 ('academic',         'Academic Officer',                            'institution'),
 ('dregistrar',       'Deputy Registrar (Academic Affairs)',         'institution'),
 ('registrar',        'Registrar',                                   'institution'),
 ('dvc',              'Deputy Vice-Chancellor (Academic)',           'institution'),
 ('vc',               'Vice-Chancellor',                             'institution'),
 ('bursar',           'Bursar',                                      'institution'),
 ('audit',            'Director of Internal Audit',                  'institution'),
 ('deputyaudit',      'Deputy Director of Audit',                    'unit'),
 ('hrm',              'Director of Human Resource Management',       'institution'),
 ('housing',          'Deputy Registrar (Housing, Welfare, Passages)','institution'),
 ('provost',          'Provost, College of Health Sciences',         'college'),
 ('collegesecretary', 'College Secretary',                           'college'),
 ('library',          'Librarian',                                   'unit'),
 ('security',         'Chief Security Officer',                      'unit'),
 ('services',         'Support Services',                            'unit'),
 ('ict',              'Director of ICT',                             'platform'),
 ('admin',            'System Administrator',                        'platform'),
 ('super',            'Super Administrator',                         'platform');

-- ── one login role per module ─────────────────────────────────────────────
DO $$
DECLARE
    m record;
BEGIN
    FOR m IN
        SELECT * FROM (VALUES
            ('iam',          'iam'),
            ('student',      'people'),
            ('admissions',   'admissions'),
            ('registration', 'catalogue,registration'),
            ('results',      'assessment'),
            ('acrecords',    'records'),
            ('credentials',  'credentials,clearance'),
            ('finance',      'finance'),
            ('payments',     'payments'),
            ('expenditure',  'expenditure'),
            ('notification', 'notify'),
            ('governance',   'governance'),
            ('reporting',    'reporting'),
            ('apimgmt',      'apimgmt'),
            ('platform',     'platform')
        ) AS t(module, schemas)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_' || m.module) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', 'app_' || m.module);
        END IF;

        -- its own schema or schemas: read and write, but never DELETE
        EXECUTE format('GRANT USAGE ON SCHEMA %s TO %I', m.schemas, 'app_' || m.module);
        EXECUTE format(
            'ALTER DEFAULT PRIVILEGES IN SCHEMA %s '
            'GRANT SELECT, INSERT, UPDATE ON TABLES TO %I', m.schemas, 'app_' || m.module);
        EXECUTE format(
            'ALTER DEFAULT PRIVILEGES IN SCHEMA %s '
            'GRANT USAGE, SELECT ON SEQUENCES TO %I', m.schemas, 'app_' || m.module);

        -- the two shared schemas: read only
        EXECUTE format('GRANT USAGE ON SCHEMA ref, policy TO %I', 'app_' || m.module);
        EXECUTE format(
            'ALTER DEFAULT PRIVILEGES IN SCHEMA ref, policy '
            'GRANT SELECT ON TABLES TO %I', 'app_' || m.module);
    END LOOP;
END $$;

GRANT SELECT ON ALL TABLES IN SCHEMA ref, policy TO
    app_iam, app_student, app_admissions, app_registration, app_results,
    app_acrecords, app_credentials, app_finance, app_payments, app_expenditure,
    app_notification, app_governance, app_reporting, app_apimgmt, app_platform;

-- ── the only role in the estate with DELETE ───────────────────────────────
-- FR-DGV / the retention schedule. It runs as itself, on a schedule, and it
-- is the reason no application role needs the privilege.
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_retention') THEN
        CREATE ROLE app_retention NOLOGIN;
    END IF;
END $$;

-- ── the audit reader ──────────────────────────────────────────────────────
-- Internal Audit's scope is defined by what it may READ (ROL §1.4). This
-- role holds SELECT and nothing else, anywhere.
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_auditor') THEN
        CREATE ROLE app_auditor NOLOGIN;
    END IF;
END $$;
