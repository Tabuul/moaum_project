-- ═══════════════════════════════════════════════════════════
-- V737 — preliminary applicants migrated from the old portal, their fees held for the Bursary, and the programme corrected by ICT
--
--   The University's master prompt of 12 November 2026: the old portal's applicants of Preliminary Technology & Industrial Studies
--   and of Preliminary Science are uploaded programme by programme (a template, a check of the file, a preview, an explicit
--   confirmation, an import history); an application fee paid on the old portal is kept but counted paid only once the Bursary has
--   verified it; and ICT corrects an applicant's programme between the two (one applicant, the same number, the fee kept, the history
--   kept). And its decisions the same day: every migrated applicant gets this portal's own application number, the old number kept
--   beside it (unique, searchable, a sign-in, a first password); an applicant admitted on the old portal comes in admitted, the old
--   portal's decision published here with no second review (an acceptance accepted, a refusal not admitted, the same way); a decided
--   but unpublished application is reopened by the Academic Office before its programme is corrected, and a published outcome stands;
--   the Director of ICT, the ICT Support agents the Director authorises, the Academic Office, a Database Operator with a University-wide
--   grant and super upload; only the Bursary verifies an old-portal fee, and never the officer who uploaded it.
--
--   What stood: the preliminary stack of V446/V701 — a preliminary application is an admissions.application with a prelim_review
--   (its route, PRELIMINARY_SCIENCE or PRELIMINARY_TECHNOLOGY, is held there alone) — opened only by the applicant through
--   prelim_register while the route's window is open; the PG old-portal pipeline of V675 (a batch, its rows, a dry run, an import, a
--   held fee); no way to move an application between the two routes; no held state for a payment.
--
--   1 · The batch (PRELIM-MIG/YYYY/NNNNNN) and its rows, as V675's: the file as read, its check (READY, WARNING, DUPLICATE_IN_FILE,
--       CONFLICT, REQUIRES_REVIEW, ERROR — what each row would do and why not), the import (CREATED, UPDATED, RECONCILED, UNCHANGED,
--       SKIPPED, FAILED), never deleted. The target programme is the batch's route, never the file's "Programme" cell: a row naming
--       the other preliminary programme is a CONFLICT. Nothing is written until the officer confirms the import; each row is imported
--       alone (a failed row is undone and reported FAILED); a second run takes only the rows not yet done; the same file again changes
--       nothing; an old number already migrated is never created twice; a name and a phone, or a name and a birth date, never merge.
--   2 · The old number beside the application (admissions.prelim_legacy_application), and the old portal's words for an application,
--       an admission and a payment read onto this portal's (admissions.prelim_legacy_status). An old number shaped like this portal's APP
--       number, or one an account here already signs in with, is held back (LEGACY_NO_IS_PORTAL_NUMBER).
--   3 · A fee paid on the old portal (admissions.prelim_legacy_fee) comes in held (REQUIRES_REVIEW) — an Excel "Paid" is never proof —
--       and blocks a new application-fee reference meanwhile (PRELIM_FEE_UNDER_REVIEW: the applicant is not asked to pay again). The
--       Bursary verifies it, posting the OLD reference as a confirmed fee (channel "Old portal"), or rejects it with a note. A rejected
--       claim is not held again by a later file (only another, non-blank reference is); a posting the Bursary reverses (V420) rejects it.
--   4 · The programme corrected (admissions.prelim_change_route): Preliminary Technology & Industrial Studies ↔ Preliminary Science,
--       by the Director of ICT, the head of the support desk, super, or an agent the Director authorised — the same application, the
--       same number, the fee and its receipts untouched, the target cleared, what the applicant must now complete asked of them, the
--       history written once (admissions.prelim_route_change). A published outcome stands; a decided one is reopened first.
--   5 · Restated: helpdesk.support_capabilities (MIGRATE_PRELIM_APPLICANTS, CHANGE_PRELIM_PROGRAMME — never in the baseline);
--       admissions.prelim_stats (new, accepted, outstanding requirements, fee held, from the old portal); admissions.prelim_problems
--       (a held fee is being verified, not to be paid); people.intake_tranche and
--       admissions.pipeline_stats (the preliminary programmes never go onto the register through the UTME intake and are not counted
--       among its offers: their own panel shows them).
--   6 · The notices: each route's MIGRATED, PROGRAMME_CHANGED and OLD_FEE_NOT_VERIFIED, in the central templates.
-- ═══════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V737: preliminary applicants migrated from the old portal, their fees held for the Bursary, and the programme corrected by ICT', true);

-- ── 1 · the batch and its rows ──────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE admissions.prelim_migration_batch (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference         text NOT NULL UNIQUE CHECK (reference ~ '^PRELIM-MIG/[0-9]{4}/[0-9]{6}$'),
    route             text NOT NULL REFERENCES admissions.prelim_programme (route) CHECK (route IN ('PRELIMINARY_TECHNOLOGY', 'PRELIMINARY_SCIENCE')),
    session           text NOT NULL,
    file_name         text NOT NULL CHECK (length(btrim(file_name)) BETWEEN 1 AND 255 AND file_name ~* '\.xlsx$'),
    file_sha256       text NOT NULL CHECK (file_sha256 ~ '^[0-9a-f]{64}$'),
    rows_expected     int  NOT NULL CHECK (rows_expected BETWEEN 1 AND 20000),
    rows_staged       int  NOT NULL DEFAULT 0,
    state             text NOT NULL DEFAULT 'STAGING' CHECK (state IN ('STAGING', 'CHECKED', 'IMPORTING', 'COMPLETED', 'ABANDONED')),
    allow_update      boolean NOT NULL DEFAULT false,
    notify            boolean NOT NULL DEFAULT true,
    started_by        uuid NOT NULL REFERENCES iam.person (id),
    started_office    text NOT NULL,
    started_at        timestamptz NOT NULL DEFAULT now(),
    checked_at        timestamptz NULL,
    import_started_at timestamptz NULL,
    completed_at      timestamptz NULL,
    completed_by      uuid NULL REFERENCES iam.person (id),
    abandoned_at      timestamptz NULL,
    abandoned_by      uuid NULL REFERENCES iam.person (id),
    abandoned_reason  text NULL,
    CONSTRAINT ck_prelimmig_abandoned CHECK (state <> 'ABANDONED' OR (abandoned_at IS NOT NULL AND length(btrim(coalesce(abandoned_reason, ''))) >= 5))
);
CREATE INDEX ix_prelimmig_batch_sha ON admissions.prelim_migration_batch (file_sha256);
CREATE INDEX ix_prelimmig_batch_route ON admissions.prelim_migration_batch (route, started_at DESC);
SELECT audit.attach('admissions.prelim_migration_batch');
COMMENT ON TABLE admissions.prelim_migration_batch IS
  'V737: one upload of old-portal applicants of one preliminary programme (the route is the upload section''s, never the file''s): PRELIM-MIG/YYYY/NNNNNN, the route''s session, the file''s name and SHA-256, whether applicants already here have their empty details filled in (allow_update), whether they are told, who uploaded it, and where it stands (STAGING → CHECKED → IMPORTING → COMPLETED, or ABANDONED with a reason). Never deleted.';

CREATE TABLE admissions.prelim_migration_row (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id           uuid NOT NULL REFERENCES admissions.prelim_migration_batch (id),
    row_no             int  NOT NULL CHECK (row_no >= 1),
    data               jsonb NOT NULL,
    legacy_no          text NULL,
    applicant          text NULL,
    email              text NULL,
    fee_ref            text NULL,
    olevel_keys        text[] NOT NULL DEFAULT '{}',
    -- the check (the dry run): what the row would do, and why not
    checked_at         timestamptz NULL,
    verdict            text NULL CHECK (verdict IN ('READY', 'WARNING', 'DUPLICATE_IN_FILE', 'CONFLICT', 'REQUIRES_REVIEW', 'ERROR')),
    match              text NULL CHECK (match IN ('NEW_APPLICANT', 'EXISTING_APPLICANT')),
    action             text NULL CHECK (action IN ('CREATE', 'UPDATE', 'RECONCILE', 'NONE')),
    application_id     uuid NULL REFERENCES admissions.application (id) ON DELETE SET NULL,
    problems           jsonb NOT NULL DEFAULT '[]',
    -- the officer's word on a possible same applicant: a new applicant all the same
    decided_new        boolean NOT NULL DEFAULT false,
    decided_new_by     uuid NULL REFERENCES iam.person (id),
    decided_new_reason text NULL,
    -- the import
    imported_at        timestamptz NULL,
    result             text NULL CHECK (result IN ('CREATED', 'UPDATED', 'RECONCILED', 'UNCHANGED', 'SKIPPED', 'FAILED')),
    result_note        text NULL,
    CONSTRAINT uq_prelimmig_row UNIQUE (batch_id, row_no)
);
CREATE INDEX ix_prelimmig_row_legacy ON admissions.prelim_migration_row (batch_id, legacy_no);
CREATE INDEX ix_prelimmig_row_email ON admissions.prelim_migration_row (batch_id, email) WHERE email IS NOT NULL;
CREATE INDEX ix_prelimmig_row_fee ON admissions.prelim_migration_row (batch_id, fee_ref) WHERE fee_ref IS NOT NULL;
CREATE INDEX ix_prelimmig_row_olevel ON admissions.prelim_migration_row USING gin (olevel_keys);
CREATE INDEX ix_prelimmig_row_verdict ON admissions.prelim_migration_row (batch_id, verdict);
CREATE INDEX ix_prelimmig_row_legacy_all ON admissions.prelim_migration_row (legacy_no) WHERE legacy_no IS NOT NULL;
CREATE INDEX ix_prelimmig_row_app ON admissions.prelim_migration_row (application_id) WHERE application_id IS NOT NULL;
SELECT audit.exempt('admissions.prelim_migration_row',
    'V737: the rows of a preliminary migration file as read, their check and their outcome, written only by the batch''s own functions and never deleted (a trigger refuses it); the batch itself, and every record the import writes, are on the spine.');
COMMENT ON TABLE admissions.prelim_migration_row IS
  'V737: each row of a preliminary migration file: the values read (only the template''s columns kept), the check — verdict READY, WARNING, DUPLICATE_IN_FILE, CONFLICT, REQUIRES_REVIEW or ERROR, the match, the proposed action and every problem with what to correct — and the import''s result. Never deleted; the values are written once.';

-- written once, never deleted: the file as read is what the import did
CREATE OR REPLACE FUNCTION admissions.prelim_migration_kept() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF coalesce(current_setting('moaum.maintenance', true), '') = 'on' THEN RETURN OLD; END IF;
        RAISE EXCEPTION 'PRELIMMIG_KEPT: a migration''s history is never deleted' USING ERRCODE = '23514';
    END IF;
    IF TG_TABLE_NAME = 'prelim_migration_row' AND NEW.data IS DISTINCT FROM OLD.data
       AND (SELECT b.state FROM admissions.prelim_migration_batch b WHERE b.id = NEW.batch_id) <> 'STAGING' THEN
        RAISE EXCEPTION 'PRELIMMIG_KEPT: a row''s values are written once; upload the corrected file as a new batch' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_prelimmig_batch_kept BEFORE DELETE ON admissions.prelim_migration_batch FOR EACH ROW EXECUTE FUNCTION admissions.prelim_migration_kept();
CREATE TRIGGER trg_prelimmig_row_kept BEFORE DELETE OR UPDATE ON admissions.prelim_migration_row FOR EACH ROW EXECUTE FUNCTION admissions.prelim_migration_kept();

-- ── 2 · the old application number, beside the application ──────────────────────────────────────────────────────────────────
CREATE TABLE admissions.prelim_legacy_application (
    application_id        uuid PRIMARY KEY REFERENCES admissions.application (id) ON DELETE CASCADE,
    legacy_application_no text NOT NULL CHECK (length(btrim(legacy_application_no)) BETWEEN 1 AND 40),
    legacy_jamb_reg_no    text NULL,
    legacy_exam_number    text NULL,
    legacy_programme      text NULL,
    legacy_target         text NULL,
    legacy_status         text NULL,
    legacy_admission      text NULL,
    applied_on            date NULL,
    legacy_source         text NOT NULL DEFAULT 'OLD_PORTAL' CHECK (legacy_source IN ('OLD_PORTAL')),
    route_at_import       text NOT NULL,
    batch_id              uuid NOT NULL REFERENCES admissions.prelim_migration_batch (id),
    row_id                uuid NULL REFERENCES admissions.prelim_migration_row (id),
    migrated_by           uuid NULL REFERENCES iam.person (id),
    migrated_office       text NULL,
    migrated_at           timestamptz NOT NULL DEFAULT now(),
    told_at               timestamptz NULL
);
CREATE UNIQUE INDEX uq_prelim_legacy_application_no ON admissions.prelim_legacy_application (upper(btrim(legacy_application_no)));
CREATE INDEX ix_prelim_legacy_application_batch ON admissions.prelim_legacy_application (batch_id);
-- an old number one of this portal's accounts already signs in with is held back (LEGACY_NO_IS_PORTAL_NUMBER), row by row: the
-- account's JAMB key looked up alone (uq_applicant_per_session leads with the session, and PostgreSQL 17 has no skip scan)
CREATE INDEX IF NOT EXISTS ix_applicant_account_jamb_key ON admissions.applicant_account (jamb_key) WHERE jamb_key IS NOT NULL;
SELECT audit.attach('admissions.prelim_legacy_application');
COMMENT ON TABLE admissions.prelim_legacy_application IS
  'V737: the old portal''s application number of a migrated preliminary application (unique, searchable, a sign-in beside this portal''s own APP number), what the old portal said of it (JAMB and examination numbers, programme, target, application and admission status, as written), the route it came in on, the batch and row that brought it, and when the applicant was told. The application''s own state stays authoritative.';

-- the old portal's words for an application, an admission and a payment, read onto this portal's
CREATE TABLE admissions.prelim_legacy_status (
    kind  text NOT NULL CHECK (kind IN ('APPLICATION', 'ADMISSION', 'PAYMENT')),
    word  text NOT NULL CHECK (word = lower(btrim(regexp_replace(word, '\s+', ' ', 'g')))),
    value text NOT NULL,
    PRIMARY KEY (kind, word),
    CONSTRAINT ck_prelim_legacy_status_value CHECK (
        (kind = 'APPLICATION' AND value IN ('DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'WITHDRAWN'))
     OR (kind = 'ADMISSION' AND value IN ('ADMITTED', 'ACCEPTED', 'NOT_ADMITTED', 'PENDING'))
     OR (kind = 'PAYMENT' AND value IN ('PAID', 'UNPAID')))
);
SELECT audit.attach('admissions.prelim_legacy_status');
COMMENT ON TABLE admissions.prelim_legacy_status IS
  'V737: the old portal''s words (lower case, single spaces) for an application''s state, an admission and a payment, read onto this portal''s values. A word not here is STATUS_UNKNOWN on the row, never a guess. There is no screen to add a word: a new word is added by a migration.';
INSERT INTO admissions.prelim_legacy_status (kind, word, value) VALUES
    ('APPLICATION', 'not submitted', 'DRAFT'), ('APPLICATION', 'draft', 'DRAFT'), ('APPLICATION', 'incomplete', 'DRAFT'), ('APPLICATION', 'started', 'DRAFT'),
    ('APPLICATION', 'submitted', 'SUBMITTED'), ('APPLICATION', 'completed', 'SUBMITTED'), ('APPLICATION', 'complete', 'SUBMITTED'), ('APPLICATION', 'pending', 'SUBMITTED'),
    ('APPLICATION', 'under review', 'UNDER_REVIEW'), ('APPLICATION', 'screening', 'UNDER_REVIEW'), ('APPLICATION', 'being screened', 'UNDER_REVIEW'),
    ('APPLICATION', 'in review', 'UNDER_REVIEW'), ('APPLICATION', 'withdrawn', 'WITHDRAWN'),
    ('ADMISSION', 'admitted', 'ADMITTED'), ('ADMISSION', 'offered', 'ADMITTED'), ('ADMISSION', 'admission offered', 'ADMITTED'),
    ('ADMISSION', 'accepted', 'ACCEPTED'), ('ADMISSION', 'admission accepted', 'ACCEPTED'),
    ('ADMISSION', 'not admitted', 'NOT_ADMITTED'), ('ADMISSION', 'rejected', 'NOT_ADMITTED'), ('ADMISSION', 'not offered', 'NOT_ADMITTED'), ('ADMISSION', 'declined', 'NOT_ADMITTED'),
    ('ADMISSION', 'pending', 'PENDING'), ('ADMISSION', 'not yet', 'PENDING'), ('ADMISSION', 'awaiting', 'PENDING'), ('ADMISSION', 'none', 'PENDING'), ('ADMISSION', '', 'PENDING'),
    ('PAYMENT', 'paid', 'PAID'), ('PAYMENT', 'verified', 'PAID'), ('PAYMENT', 'successful', 'PAID'), ('PAYMENT', 'confirmed', 'PAID'), ('PAYMENT', 'completed', 'PAID'),
    ('PAYMENT', 'not paid', 'UNPAID'), ('PAYMENT', 'unpaid', 'UNPAID'), ('PAYMENT', 'pending', 'UNPAID'), ('PAYMENT', 'failed', 'UNPAID'), ('PAYMENT', 'none', 'UNPAID'),
    ('PAYMENT', 'cancelled', 'UNPAID');

-- ── 3 · fees paid on the old portal: held until the Bursary verifies them ─────────────────────────────────────────────────────
CREATE TABLE admissions.prelim_legacy_fee (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id    uuid NOT NULL REFERENCES admissions.application (id) ON DELETE CASCADE,
    batch_id          uuid NOT NULL REFERENCES admissions.prelim_migration_batch (id),
    row_id            uuid NULL REFERENCES admissions.prelim_migration_row (id),
    legacy_reference  text NULL CHECK (legacy_reference IS NULL OR length(btrim(legacy_reference)) BETWEEN 1 AND 80),
    gateway_reference text NULL CHECK (gateway_reference IS NULL OR length(btrim(gateway_reference)) BETWEEN 1 AND 120),
    amount            numeric(12,2) NOT NULL CHECK (amount > 0),
    paid_on           date NULL,
    stated_status     text NULL,
    state             text NOT NULL DEFAULT 'REQUIRES_REVIEW' CHECK (state IN ('REQUIRES_REVIEW', 'VERIFIED', 'REJECTED')),
    fee_reference_id  uuid NULL REFERENCES admissions.fee_reference (id) ON DELETE CASCADE,
    decided_by        uuid NULL REFERENCES iam.person (id),
    decided_office    text NULL,
    decided_at        timestamptz NULL,
    decision_note     text NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_prelim_legacy_fee_verified CHECK ((state = 'VERIFIED') = (fee_reference_id IS NOT NULL)),
    CONSTRAINT ck_prelim_legacy_fee_rejected CHECK (state <> 'REJECTED' OR length(btrim(coalesce(decision_note, ''))) >= 5)
);
CREATE UNIQUE INDEX uq_prelim_legacy_fee_ref ON admissions.prelim_legacy_fee (upper(btrim(legacy_reference))) WHERE state <> 'REJECTED' AND legacy_reference IS NOT NULL;
CREATE UNIQUE INDEX uq_prelim_legacy_fee_held ON admissions.prelim_legacy_fee (application_id) WHERE state = 'REQUIRES_REVIEW';
CREATE INDEX ix_prelim_legacy_fee_app ON admissions.prelim_legacy_fee (application_id);
CREATE INDEX ix_prelim_legacy_fee_batch ON admissions.prelim_legacy_fee (batch_id);
CREATE INDEX ix_prelim_legacy_fee_gateway ON admissions.prelim_legacy_fee (upper(btrim(gateway_reference))) WHERE gateway_reference IS NOT NULL;
CREATE INDEX ix_prelim_legacy_fee_state ON admissions.prelim_legacy_fee (state);
SELECT audit.attach('admissions.prelim_legacy_fee');
COMMENT ON TABLE admissions.prelim_legacy_fee IS
  'V737: an application fee a migrated preliminary applicant paid on the old portal, as the file stated it: always REQUIRES_REVIEW at the import (an Excel "Paid" is never proof) — the applicant is not asked to pay again meanwhile — until the Bursary (never the officer who uploaded it) VERIFIES it (the old reference posted as a confirmed admissions.fee_reference, channel Old portal) or REJECTS it with a note. One old reference, one fee; at most one held at a time for an application.';

-- the programme corrected, written once
CREATE TABLE admissions.prelim_route_change (
    id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference                text NOT NULL UNIQUE CHECK (reference ~ '^PRELIM-CHG/[0-9]{4}/[0-9]{6}$'),
    application_id           uuid NOT NULL REFERENCES admissions.application (id) ON DELETE CASCADE,
    application_no           text NOT NULL,
    legacy_application_no    text NULL,
    from_route               text NULL,
    to_route                 text NULL,
    from_target_id           uuid NULL,
    from_target_name         text NULL,
    from_specialisation_name text NULL,
    from_state               text NULL,
    to_state                 text NULL,
    reason                   text NOT NULL,
    fee_status               text NULL CHECK (fee_status IS NULL OR fee_status IN ('PAID', 'HELD', 'UNPAID', 'NOT_REQUIRED')),
    fee_amount               numeric(12,2) NULL,
    fee_references           text[] NOT NULL DEFAULT '{}',
    missing                  jsonb NOT NULL DEFAULT '[]',
    result                   text NOT NULL CHECK (result IN ('APPLIED', 'REFUSED')),
    refusal_code             text NULL,
    refusal_message          text NULL,
    actor                    uuid NULL,
    actor_office             text NULL,
    at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_prelim_route_change_refused CHECK ((result = 'REFUSED') = (refusal_code IS NOT NULL))
);
CREATE INDEX ix_prelim_route_change_app ON admissions.prelim_route_change (application_id, at DESC);
CREATE INDEX ix_prelim_route_change_at ON admissions.prelim_route_change (at DESC);
SELECT audit.attach('admissions.prelim_route_change');
COMMENT ON TABLE admissions.prelim_route_change IS
  'V737: a preliminary application''s programme corrected between Preliminary Technology & Industrial Studies and Preliminary Science (APPLIED), or the correction refused (REFUSED, with its code): PRELIM-CHG/YYYY/NNNNNN, the application and both numbers, the route, target and state before and after, the reason, the fee as it stood (kept), what the applicant must complete, who and when. Written once; removed only with the application itself.';

CREATE OR REPLACE FUNCTION admissions.prelim_route_change_once() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    -- the application itself removed (the go-live data reset): its history goes with it, as prelim_review_event's does
    IF TG_OP = 'DELETE' AND (NOT EXISTS (SELECT 1 FROM admissions.application a WHERE a.id = OLD.application_id)
                             OR coalesce(current_setting('moaum.maintenance', true), '') = 'on') THEN
        RETURN OLD;
    END IF;
    RAISE EXCEPTION 'PRELIM_CHANGE_KEPT: a programme correction is written once and never changed' USING ERRCODE = '23514';
END $fn$;
CREATE TRIGGER trg_prelim_route_change_once BEFORE UPDATE OR DELETE ON admissions.prelim_route_change FOR EACH ROW EXECUTE FUNCTION admissions.prelim_route_change_once();

-- the lookups a file's check makes for every row, each on an index
CREATE INDEX IF NOT EXISTS ix_screening_olevel_sitting_key ON admissions.screening_olevel (exam_year, upper(regexp_replace(exam_number, '\s', '', 'g'))) WHERE active;
CREATE INDEX IF NOT EXISTS ix_candidate_prelim_surname ON admissions.candidate (upper(surname)) WHERE entry_mode IN ('PRELIMINARY', 'PROFICIENCY');
CREATE INDEX IF NOT EXISTS ix_applicant_account_phone ON admissions.applicant_account (phone);

-- ── 4 · reading a file's values (V675's readers reused: pg_mig_t, pg_mig_date, pg_mig_amount, pg_mig_problem, pg_mig_at) ──────
-- a status word as the old portal wrote it: lower case, single spaces, no stray punctuation at the ends
CREATE OR REPLACE FUNCTION admissions.prelim_mig_word(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT lower(btrim(regexp_replace(regexp_replace(replace(coalesce(p, ''), '_', ' '), '\s+', ' ', 'g'), '^[[:punct:][:space:]]+|[[:punct:][:space:]]+$', '', 'g')))
$$;

-- the value a word stands for (DRAFT, ADMITTED, PAID …), or NULL when the word is not one the University has read
CREATE OR REPLACE FUNCTION admissions.prelim_mig_status(p_kind text, p_word text) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT s.value FROM admissions.prelim_legacy_status s WHERE s.kind = p_kind AND s.word = admissions.prelim_mig_word(p_word)
$$;

CREATE OR REPLACE FUNCTION admissions.prelim_mig_gender(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE upper(btrim(coalesce(p, ''))) WHEN 'M' THEN 'M' WHEN 'MALE' THEN 'M' WHEN 'F' THEN 'F' WHEN 'FEMALE' THEN 'F' END
$$;

-- the examination body as the O'Level form holds it: WAEC, NECO, NABTEB or OTHER; NULL for a word not read
CREATE OR REPLACE FUNCTION admissions.prelim_mig_body(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN k IN ('WAEC', 'WASSCE', 'WASC', 'WEST AFRICAN EXAMINATIONS COUNCIL', 'WEST AFRICAN EXAMINATION COUNCIL') THEN 'WAEC'
                WHEN k IN ('NECO', 'NATIONAL EXAMINATIONS COUNCIL', 'NATIONAL EXAMINATION COUNCIL') THEN 'NECO'
                WHEN k IN ('NABTEB', 'NATIONAL BUSINESS AND TECHNICAL EXAMINATIONS BOARD') THEN 'NABTEB'
                WHEN k IN ('OTHER', 'OTHERS', 'ANOTHER') THEN 'OTHER' END
      FROM (SELECT upper(btrim(regexp_replace(coalesce(p, ''), '[^A-Za-z ]+', ' ', 'g'))) AS k0) y,
           LATERAL (SELECT btrim(regexp_replace(y.k0, '\s+', ' ', 'g')) AS k) z
$$;

-- one sitting, as one key: body|year|number (spaces out of the number); NULL when any part is not read
CREATE OR REPLACE FUNCTION admissions.prelim_mig_olevel_key(p_body text, p_year text, p_number text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN admissions.prelim_mig_body(p_body) IS NOT NULL AND btrim(coalesce(p_year, '')) ~ '^[0-9]{4}$'
                     AND nullif(regexp_replace(coalesce(p_number, ''), '\s', '', 'g'), '') IS NOT NULL
                THEN admissions.prelim_mig_body(p_body) || '|' || btrim(p_year) || '|' || upper(regexp_replace(p_number, '\s', '', 'g')) END
$$;

/* the O'Level subjects the application form offers (frontend lib/preliminary.ts SUBJECTS, the form's list), with every subject a
   preliminary rule names (a route's core, required and completion subjects; a target's core subjects), one name a subject — matched
   as the eligibility engine matches them (admissions.subject_key: "Maths", "Eng. Language", "CRK", "Agric" read) */
CREATE OR REPLACE FUNCTION admissions.prelim_olevel_subjects()
RETURNS TABLE (name text) LANGUAGE sql STABLE AS $$
    WITH form AS (
        SELECT u.n AS name, u.o AS ord
          FROM unnest(ARRAY['English Language', 'Mathematics', 'Biology', 'Chemistry', 'Physics', 'Agricultural Science', 'Further Mathematics', 'Economics', 'Geography',
                            'Technical Drawing', 'Computer Studies', 'Data Processing', 'Government', 'Literature in English', 'Christian Religious Studies', 'Islamic Religious Studies',
                            'Civic Education', 'Commerce', 'Financial Accounting', 'Health Education', 'Physical Education', 'Food and Nutrition', 'Fine Art', 'History', 'French', 'Tiv',
                            'Hausa', 'Yoruba', 'Igbo', 'Clothing and Textiles', 'Home Management', 'Marketing', 'Office Practice', 'Book Keeping', 'Store Management', 'Insurance', 'ICT',
                            'Basic Electricity', 'Basic Electronics', 'Auto Mechanics', 'Building Construction', 'Metalwork', 'Woodwork',
                            'Electrical Installation and Maintenance Work']) WITH ORDINALITY u(n, o)),
    rules AS (
        SELECT btrim(s) AS name, 1000 AS ord FROM admissions.prelim_programme p, unnest(p.core_subjects || p.required_subjects || p.completion_subjects) s
        UNION ALL
        SELECT btrim(s), 2000 FROM admissions.prelim_target t, unnest(coalesce(t.core_subjects, '{}'::text[])) s),
    alls AS (SELECT * FROM form UNION ALL SELECT * FROM rules),
    one AS (SELECT DISTINCT ON (admissions.subject_key(a.name)) a.name, a.ord FROM alls a WHERE admissions.subject_key(a.name) IS NOT NULL
             ORDER BY admissions.subject_key(a.name), a.ord, a.name)
    SELECT one.name FROM one ORDER BY one.ord, one.name
$$;
COMMENT ON FUNCTION admissions.prelim_olevel_subjects() IS
  'V737: the O''Level subjects a preliminary migration file may name — the application form''s own list (frontend lib/preliminary.ts SUBJECTS) and every subject a preliminary rule names — one name a subject (admissions.subject_key). The template''s Subjects sheet and the check read it; a subject not on it is OLEVEL_SUBJECT_UNKNOWN.';

/* "Mathematics:B3; English Language:C4" read into its subjects and grades, each with what is wrong with it (NULL when nothing):
   SUBJECT_UNKNOWN, NO_GRADE, GRADE_INVALID, AWAITING, SUBJECT_TWICE. The subject is given back in the form's own name. */
CREATE OR REPLACE FUNCTION admissions.prelim_mig_results(p text)
RETURNS TABLE (ord int, given text, subject text, grade text, problem text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_part text; i int := 0; m text[]; v_s text; v_g text; v_canon text; v_seen text[] := '{}';
BEGIN
    FOR v_part IN SELECT btrim(x) FROM regexp_split_to_table(coalesce(p, ''), '[;,|\n\r]+') x WHERE btrim(x) <> '' LOOP
        i := i + 1;
        m := regexp_match(v_part, '^(.*?)\s*[:=]\s*([^:=]*)$');
        IF m IS NULL THEN
            m := regexp_match(v_part, '^(.*?)[[:space:]-]+([A-Fa-f][[:space:]]?[1-9]|[Aa][Rr])$');
        END IF;
        v_s := btrim(coalesce(m[1], v_part));
        v_g := upper(regexp_replace(btrim(coalesce(m[2], '')), '\s', '', 'g'));
        v_canon := (SELECT s.name FROM admissions.prelim_olevel_subjects() s WHERE admissions.subject_key(s.name) = admissions.subject_key(v_s) LIMIT 1);
        ord := i; given := left(v_s, 60); subject := v_canon; grade := nullif(v_g, '');
        problem := CASE WHEN v_s = '' OR length(v_s) > 60 OR v_canon IS NULL THEN 'SUBJECT_UNKNOWN'
                        WHEN v_g = '' THEN 'NO_GRADE'
                        WHEN v_g IN ('AR', 'AWAITING', 'AWAITINGRESULT', 'PENDING', 'NR', '*', 'ABS') THEN 'AWAITING'
                        WHEN v_g NOT IN ('A1', 'B2', 'B3', 'C4', 'C5', 'C6', 'D7', 'E8', 'F9') THEN 'GRADE_INVALID'
                        WHEN admissions.subject_key(v_canon) = ANY (v_seen) THEN 'SUBJECT_TWICE' END;
        IF v_canon IS NOT NULL THEN v_seen := v_seen || admissions.subject_key(v_canon); END IF;
        RETURN NEXT;
    END LOOP;
END $fn$;

/* the preliminary route a "Programme" cell names: its name or code, a target or area of exactly one route, or a common short form
   ("pre-science", "preliminary science", "pre-tech", "PTIS" …); NULL when it names neither (or both) */
CREATE OR REPLACE FUNCTION admissions.prelim_mig_route_of(p_cell text) RETURNS text LANGUAGE sql STABLE AS $$
    WITH k AS (SELECT admissions.pg_legacy_key(p_cell) AS k),
    named AS (
        SELECT p.route FROM admissions.prelim_programme p, k
         WHERE p.route IN ('PRELIMINARY_SCIENCE', 'PRELIMINARY_TECHNOLOGY')
           AND k.k IN (admissions.pg_legacy_key(p.name), admissions.pg_legacy_key(replace(p.route, '_', ' ')), admissions.pg_legacy_key(p.route))),
    target AS (
        SELECT DISTINCT t.route FROM admissions.prelim_target t LEFT JOIN ref.programme g ON g.code = t.programme_code, k
         WHERE t.route IN ('PRELIMINARY_SCIENCE', 'PRELIMINARY_TECHNOLOGY') AND t.state = 'MAPPED'
           AND k.k IN (admissions.pg_legacy_key(t.programme_code), admissions.pg_legacy_key(g.name), admissions.pg_legacy_key(t.requested_name),
                       admissions.pg_legacy_key(t.group_name))),
    words AS (
        SELECT k.k ~ '\m(SCIENCES?|SCI|PRESCI|PRESCIENCES?)\M' AS sci,
               k.k ~ '\m(TECH|TECHNOLOGY|TECHNICAL|INDUSTRIAL|PTIS|PRETECH|VOCATIONAL)\M' AS tech
          FROM k)
    SELECT CASE WHEN (SELECT count(*) FROM named) = 1 THEN (SELECT route FROM named)
                WHEN (SELECT count(*) FROM target) = 1 THEN (SELECT route FROM target)
                WHEN (SELECT sci AND NOT tech FROM words) THEN 'PRELIMINARY_SCIENCE'
                WHEN (SELECT tech AND NOT sci FROM words) THEN 'PRELIMINARY_TECHNOLOGY' END
$$;

/* the target a row names among the route's MAPPED targets (by programme code, the register's name, the name as requested, or the
   area), and its specialisation (by code or name); a specialisation alone finds its target when only one target offers it */
CREATE OR REPLACE FUNCTION admissions.prelim_mig_target_of(p_route text, p_target text, p_spec text)
RETURNS TABLE (target_id uuid, specialisation_id uuid, problem text, detail text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_key text := admissions.pg_legacy_key(p_target); v_skey text := admissions.pg_legacy_key(p_spec); v_n int; v_t uuid; v_s uuid; p admissions.prelim_programme;
BEGIN
    SELECT * INTO p FROM admissions.prelim_programme x WHERE x.route = p_route;
    IF v_key IS NOT NULL THEN
        SELECT count(*), (array_agg(t.id))[1] INTO v_n, v_t
          FROM admissions.prelim_target t LEFT JOIN ref.programme g ON g.code = t.programme_code
         WHERE t.route = p_route AND t.state = 'MAPPED'
           AND v_key IN (admissions.pg_legacy_key(t.programme_code), admissions.pg_legacy_key(g.name), admissions.pg_legacy_key(t.requested_name),
                         admissions.pg_legacy_key(t.group_name));
        IF v_n = 0 THEN
            RETURN QUERY SELECT NULL::uuid, NULL::uuid, 'TARGET_NOT_FOUND'::text, format('"%s" is not a %s of %s', left(p_target, 80), p.target_word, p.name); RETURN;
        ELSIF v_n > 1 THEN
            RETURN QUERY SELECT NULL::uuid, NULL::uuid, 'TARGET_NOT_FOUND'::text, format('"%s" names %s %ss of %s, not one', left(p_target, 80), v_n, p.target_word, p.name); RETURN;
        END IF;
    END IF;
    IF v_skey IS NOT NULL THEN
        SELECT count(*), (array_agg(s.id))[1], (array_agg(s.target_id))[1] INTO v_n, v_s, v_key
          FROM admissions.prelim_specialisation s JOIN admissions.prelim_target t ON t.id = s.target_id
         WHERE t.route = p_route AND t.state = 'MAPPED' AND s.active AND (v_t IS NULL OR s.target_id = v_t)
           AND v_skey IN (admissions.pg_legacy_key(s.code), admissions.pg_legacy_key(s.name));
        IF v_n = 1 THEN
            RETURN QUERY SELECT coalesce(v_t, v_key::uuid), v_s, NULL::text, NULL::text; RETURN;
        END IF;
        RETURN QUERY SELECT v_t, NULL::uuid, 'SPECIALISATION_NOT_FOUND'::text,
            format('"%s" is not a specialisation %s', left(p_spec, 80),
                   CASE WHEN v_t IS NOT NULL THEN 'of ' || coalesce((SELECT coalesce(g.name, t.requested_name) FROM admissions.prelim_target t LEFT JOIN ref.programme g ON g.code = t.programme_code WHERE t.id = v_t), 'the target')
                        ELSE 'of any ' || p.target_word || ' of ' || p.name END);
        RETURN;
    END IF;
    RETURN QUERY SELECT v_t, NULL::uuid, NULL::text, NULL::text;
END $fn$;

-- a payment reference used elsewhere: on another application's fee, another migrated fee, or an old-portal postgraduate fee — named
CREATE OR REPLACE FUNCTION admissions.prelim_mig_fee_clash(p_ref text, p_app uuid) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT 'the fee reference of application ' || ap.application_no
           FROM admissions.fee_reference fr JOIN admissions.application ap ON ap.id = fr.application_id
          WHERE fr.reference IN (btrim(p_ref), upper(btrim(p_ref))) AND fr.application_id IS DISTINCT FROM p_app LIMIT 1),
        (SELECT 'an old-portal application fee already recorded for ' || ap.application_no
           FROM admissions.prelim_legacy_fee x JOIN admissions.application ap ON ap.id = x.application_id
          WHERE (upper(btrim(x.legacy_reference)) = upper(btrim(p_ref)) OR upper(btrim(x.gateway_reference)) = upper(btrim(p_ref)))
            AND x.state <> 'REJECTED' AND x.application_id IS DISTINCT FROM p_app LIMIT 1),
        (SELECT 'an old-portal postgraduate ' || lower(replace(x.kind, '_', ' ')) || ' fee'
           FROM admissions.pg_legacy_fee x WHERE upper(btrim(x.legacy_reference)) = upper(btrim(p_ref)) AND x.state <> 'REJECTED' LIMIT 1))
    WHERE nullif(btrim(coalesce(p_ref, '')), '') IS NOT NULL
$$;

-- an application's fee as the desk reads it: PAID (confirmed), HELD (an old-portal fee waiting for the Bursary), or UNPAID
CREATE OR REPLACE FUNCTION admissions.prelim_fee_status(p_app uuid) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN a.fee_confirmed_at IS NOT NULL THEN 'PAID'
                WHEN EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee f WHERE f.application_id = a.id AND f.state = 'REQUIRES_REVIEW') THEN 'HELD'
                ELSE 'UNPAID' END
      FROM admissions.application a WHERE a.id = p_app
$$;

-- V701's list of what an application still needs, restated: while an old-portal fee is held, its PAYMENT line says it is being
-- verified by the Bursary, not "Pay the ... application fee" (the applicant is not asked to pay it again)
CREATE OR REPLACE FUNCTION admissions.prelim_problems(p_app uuid)
RETURNS TABLE (step text, field text, message text)
LANGUAGE sql STABLE AS $fn$
    WITH a AS (SELECT ap.*, c.sex FROM admissions.application ap JOIN admissions.candidate c ON c.id = ap.candidate_id WHERE ap.id = p_app),
         r AS (SELECT x.* FROM admissions.prelim_review x WHERE x.application_id = p_app),
         p AS (SELECT pp.* FROM admissions.prelim_programme pp JOIN r ON r.route = pp.route),
         t AS (SELECT tt.* FROM admissions.prelim_target tt JOIN r ON tt.id = r.target_id),
         fee AS (SELECT f.* FROM a CROSS JOIN r CROSS JOIN LATERAL admissions.route_fee_rule(a.session, r.route) f),
         ans AS (SELECT x.field, x.value FROM admissions.screening_answer x WHERE x.application_id = p_app),
         ol AS (SELECT x.* FROM admissions.screening_olevel x WHERE x.application_id = p_app AND x.active),
         sittings AS (SELECT count(DISTINCT sitting) AS n FROM ol),
         docs AS (SELECT d.* FROM admissions.application_document d WHERE d.application_id = p_app AND d.superseded_at IS NULL),
         req AS (SELECT d.* FROM admissions.prelim_document d JOIN r ON r.route = d.route WHERE d.required AND (NOT d.second_sitting_only OR (SELECT n FROM sittings) >= 2))
    SELECT 'PAYMENT', 'application_fee',
           CASE WHEN EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee lf WHERE lf.application_id = p_app AND lf.state = 'REQUIRES_REVIEW')
                THEN 'The application fee paid on the old portal is being verified by the Bursary'
                WHEN NOT EXISTS (SELECT 1 FROM fee) THEN 'The Bursary has not yet stated the ' || (SELECT name FROM p) || ' application fee for ' || (SELECT session FROM a) || '; the form opens once it is paid'
                ELSE 'Pay the ' || (SELECT name FROM p) || ' application fee' END
     WHERE NOT admissions.prelim_fee_settled(p_app)
    UNION ALL
    SELECT 'PERSONAL', 'sex', 'Give your sex' WHERE (SELECT sex FROM a) IS NULL
    UNION ALL
    SELECT 'PERSONAL', f.field, 'Give your ' || replace(replace(replace(f.field, 'kin_', 'next of kin''s '), '_', ' '), 'lga', 'local government area')
      FROM admissions.prelim_form_fields() f WHERE f.required AND NOT EXISTS (SELECT 1 FROM ans WHERE ans.field = f.field)
    UNION ALL
    SELECT 'OLEVEL', 'sittings',
           CASE WHEN (SELECT rule_kind FROM p) = 'ATTEMPTED_CERTIFICATE' THEN 'Give the results of the secondary school certificate examination you sat (one sitting or two).'
                ELSE 'Give your O''Level results (one sitting or two). An awaiting result is not accepted.' END
     WHERE (SELECT n FROM sittings) = 0
    UNION ALL
    SELECT 'PROGRAMME', 'target', 'Choose the ' || (SELECT target_word FROM p) WHERE (SELECT target_id FROM r) IS NULL
    UNION ALL
    SELECT 'PROGRAMME', 'target', 'The ' || (SELECT target_word FROM p) || ' you chose is no longer offered; choose another'
     WHERE (SELECT target_id FROM r) IS NOT NULL AND NOT EXISTS (SELECT 1 FROM t WHERE t.state = 'MAPPED')
    UNION ALL
    SELECT 'PROGRAMME', 'specialisation', 'Choose your specialisation within ' || coalesce((SELECT pr.name FROM ref.programme pr JOIN t ON pr.code = t.programme_code), (SELECT requested_name FROM t))
     WHERE (SELECT specialisation_id FROM r) IS NULL
       AND EXISTS (SELECT 1 FROM admissions.prelim_specialisation s JOIN t ON s.target_id = t.id WHERE s.active)
    UNION ALL
    SELECT 'PROGRAMME', 'specialisation', 'The specialisation you chose is no longer offered; choose another'
     WHERE (SELECT specialisation_id FROM r) IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM admissions.prelim_specialisation s JOIN r ON s.id = r.specialisation_id JOIN t ON s.target_id = t.id WHERE s.active)
    UNION ALL
    SELECT 'DOCUMENTS', q.kind, 'Upload your ' || lower(left(q.label, 1)) || substr(q.label, 2)
      FROM req q WHERE NOT EXISTS (SELECT 1 FROM docs WHERE docs.kind = q.kind)
    UNION ALL
    SELECT 'DOCUMENTS', d.kind, 'Replace your ' || lower(coalesce((SELECT q.label FROM admissions.prelim_document q JOIN r ON r.route = q.route WHERE q.kind = d.kind), replace(d.kind, '_', ' ')))
                                 || ', which the Office could not accept: ' || rtrim(coalesce(d.review_note, ''), '. ')
      FROM docs d WHERE d.status = 'REJECTED'
$fn$;

-- ── 5 · the template's columns: the single source of the template and of what an upload keeps ──────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.prelim_migration_columns(p_route text)
RETURNS TABLE (key text, header text, section text, required boolean, note text, choices text[])
LANGUAGE sql STABLE AS $$
    WITH p AS (SELECT x.* FROM admissions.prelim_programme x WHERE x.route = upper(btrim(coalesce(p_route, ''))) AND x.route IN ('PRELIMINARY_TECHNOLOGY', 'PRELIMINARY_SCIENCE')),
    w AS (SELECT kind, array_agg(initcap(word) ORDER BY value, (word <> lower(replace(value, '_', ' '))), word) FILTER (WHERE word <> '') AS list FROM admissions.prelim_legacy_status GROUP BY kind),
    tgt AS (SELECT CASE WHEN (SELECT route FROM p) = 'PRELIMINARY_TECHNOLOGY'
                        THEN (SELECT array_agg(DISTINCT t.group_name ORDER BY t.group_name) FROM admissions.prelim_target t WHERE t.route = (SELECT route FROM p) AND t.state = 'MAPPED')
                        ELSE (SELECT array_agg(t.requested_name ORDER BY t.ord, t.requested_name) FROM admissions.prelim_target t WHERE t.route = (SELECT route FROM p) AND t.state = 'MAPPED') END AS list),
    spc AS (SELECT array_agg(s.name ORDER BY t.ord, s.ord, s.name) AS list FROM admissions.prelim_specialisation s JOIN admissions.prelim_target t ON t.id = s.target_id
             WHERE t.route = (SELECT route FROM p) AND t.state = 'MAPPED' AND s.active),
    qual AS (SELECT array_agg(q.code ORDER BY q.ord) AS list, string_agg(q.code || ' (' || q.label || ')', ', ' ORDER BY q.ord) AS words
               FROM admissions.qualification_type q WHERE q.active AND q.code = ANY ((SELECT qualification_types FROM p)::text[])),
    sit AS (SELECT n FROM generate_series(1, (SELECT least(greatest(coalesce(max_sittings, 1), 1), 2) FROM p)) n),
    cols AS (
        SELECT c.* FROM (VALUES
          ( 1, 'legacyApplicationNo', 'Application Number', 'Applicant', true, 'The application number the old portal issued: kept as the old number beside the one this portal gives. Letters, digits and / - . only.', NULL::text[]),
          ( 2, 'jambRegNo', 'JAMB Registration Number', 'Applicant', false, 'If the applicant has one: kept on the record, never used to match.', NULL::text[]),
          ( 3, 'surname', 'Surname', 'Applicant', true, 'As on the O''Level certificate.', NULL::text[]),
          ( 4, 'firstName', 'First Name', 'Applicant', true, NULL, NULL::text[]),
          ( 5, 'otherNames', 'Other Names', 'Applicant', false, NULL, NULL::text[]),
          ( 6, 'gender', 'Gender', 'Applicant', true, 'Male or Female.', ARRAY['Male', 'Female']),
          ( 7, 'dateOfBirth', 'Date of Birth', 'Applicant', true, 'DD/MM/YYYY, YYYY-MM-DD, or an Excel date.', NULL::text[]),
          ( 8, 'email', 'Email Address', 'Contact', false, 'The applicant can sign in with it and is told by it. Leave it blank if there is none.', NULL::text[]),
          ( 9, 'phone', 'Phone Number', 'Contact', true, 'A Nigerian mobile number: 080…, or +234….', NULL::text[]),
          (10, 'stateOfOrigin', 'State of Origin', 'Contact', false, NULL, NULL::text[]),
          (11, 'lga', 'LGA', 'Contact', false, 'Local government area.', NULL::text[]),
          (12, 'nationality', 'Nationality', 'Contact', false, NULL, NULL::text[]),
          (13, 'address', 'Residential Address', 'Contact', false, NULL, NULL::text[]),
          (14, 'nextOfKinName', 'Next of Kin Name', 'Contact', false, NULL, NULL::text[]),
          (15, 'nextOfKinRelationship', 'Next of Kin Relationship', 'Contact', false, NULL, NULL::text[]),
          (16, 'nextOfKinPhone', 'Next of Kin Phone', 'Contact', false, 'A Nigerian mobile number.', NULL::text[]),
          (17, 'programme', 'Programme', 'Programme', false, 'As the old portal named it. Checked, never used: the programme is the one this upload is for; a row naming the other preliminary programme is held back.', NULL::text[]),
          (18, 'target', 'Intended Programme', 'Programme', false,
               CASE WHEN (SELECT route FROM p) = 'PRELIMINARY_TECHNOLOGY' THEN 'The area, as on the Targets sheet.' ELSE 'The programme the applicant intends to progress to, as on the Targets sheet.' END,
               (SELECT list FROM tgt)),
          (19, 'specialisation', 'Specialisation', 'Programme', false, 'Within the area, as on the Specialisations sheet, where the area has them.', (SELECT list FROM spc)),
          (20, 'examinationNumber', 'Examination Number', 'Programme', false, 'The old portal''s examination number, if any (kept as written).', NULL::text[]),
          (90, 'applicationDate', 'Application Date', 'Payment', false, 'The day the application was made on the old portal: DD/MM/YYYY.', NULL::text[]),
          (91, 'paymentReference', 'Application Payment Reference', 'Payment', false, 'The old portal''s reference for the application fee.', NULL::text[]),
          (92, 'gatewayReference', 'Payment Gateway Transaction Reference', 'Payment', false, 'The payment service''s own reference, if the old portal showed it.', NULL::text[]),
          (93, 'amountPaid', 'Application Fee Paid', 'Payment', false, 'Naira.', NULL::text[]),
          (94, 'paymentDate', 'Payment Date', 'Payment', false, 'DD/MM/YYYY.', NULL::text[]),
          (95, 'paymentStatus', 'Payment Status', 'Payment', false, '"Paid" is never taken as proof: the fee is held until the Bursary verifies it, and the applicant is not asked to pay again meanwhile.',
               (SELECT list FROM w WHERE kind = 'PAYMENT')),
          (96, 'applicationStatus', 'Application Status', 'Status', true, 'As the old portal showed it.', (SELECT list FROM w WHERE kind = 'APPLICATION')),
          (97, 'admissionStatus', 'Admission Status', 'Status', false, 'Blank reads Pending. An admission on the old portal comes in admitted, published here with no second review.',
               (SELECT list FROM w WHERE kind = 'ADMISSION'))
        ) c(n, key, header, section, required, note, choices)
        WHERE c.key <> 'specialisation' OR (SELECT route FROM p) = 'PRELIMINARY_TECHNOLOGY'
        UNION ALL
        SELECT 30 + s.n * 10 + k.o, 'olevel' || s.n || k.suffix, 'O''Level ' || s.n || ' ' || k.words, 'O''Level sitting ' || s.n, false, k.note, k.choices
          FROM sit s CROSS JOIN (VALUES
              (1, 'Body', 'Examination Type', 'WAEC, NECO, NABTEB or OTHER.', ARRAY['WAEC', 'NECO', 'NABTEB', 'OTHER']),
              (2, 'Qualification', 'Qualification', 'Blank reads SSCE. Accepted: ' || (SELECT words FROM qual) || '.', (SELECT list FROM qual)),
              (3, 'Year', 'Examination Year', 'YYYY.', NULL::text[]),
              (4, 'Number', 'Examination Number', NULL, NULL::text[]),
              (5, 'Results', 'Subjects and Grades', 'Subject:Grade; Subject:Grade — e.g. English Language:C4; Mathematics:B3. Grades A1 to F9; an awaiting result is not accepted.', NULL::text[])
          ) k(o, suffix, words, note, choices))
    SELECT c.key, c.header, c.section, c.required, c.note, c.choices FROM cols c WHERE EXISTS (SELECT 1 FROM p) ORDER BY c.n
$$;
COMMENT ON FUNCTION admissions.prelim_migration_columns(text) IS
  'V737: the preliminary migration template''s columns for one route, in order — the applicant, contact, programme, O''Level sitting (as many as the route allows), payment and status fields this portal holds, nothing else; Specialisation for Preliminary Technology alone. The template is built from it, its drop-downs from choices, and an upload keeps only these keys.';

-- ── 6 · who migrates, who corrects a programme ──────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.support_capabilities()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT ARRAY['VIEW_STUDENT', 'EDIT_CONTACT', 'EDIT_PERSONAL', 'EDIT_FAMILY', 'EDIT_PHOTO', 'REQUEST_CHANGE',
                 'VIEW_PAYMENTS', 'VIEW_DOCUMENTS', 'MANAGE_REGISTRATION', 'EXPORT_STUDENTS',
                 'OVERRIDE_REGISTRATION', 'RESET_PASSWORD', 'INVESTIGATE_PAYMENT', 'VERIFY_PAYMENT', 'SYNC_ENTITLEMENT',
                 'REGENERATE_RECEIPT', 'CREATE_TICKET', 'VIEW_SUPPORT_AUDIT',
                 'VIEW_ALLOCATIONS', 'ALLOCATE_COURSES', 'REMOVE_ALLOCATIONS', 'BULK_ALLOCATE',
                 'VIEW_PROGRAMME_STRUCTURE', 'EDIT_COURSES', 'BIND_COURSES', 'MANAGE_PREREQUISITES',
                 'PROGRESS_LEVEL', 'CORRECT_LEVEL', 'VIEW_LEVEL_HISTORY', 'VIEW_RESET_HISTORY',
                 'VIEW_STUDENT_PORTAL',
                 -- V559: many students reset to the default credential in one operation, within the posting's scope
                 'BULK_RESET_PASSWORD',
                 -- V582: the students of the login and password tickets the agent ticks, reset from the desk's queue
                 'BULK_RESET_FROM_TICKETS',
                 -- V713: a course's code, a course's title — corrected with a reason (EDIT_COURSES carries both)
                 'EDIT_COURSE_CODE', 'EDIT_COURSE_TITLE',
                 -- V716: a programme's code corrected with a reason, within the posting's faculties and departments
                 'EDIT_PROGRAMME_CODE',
                 -- V737: old-portal preliminary applicants uploaded, and a preliminary applicant's programme changed — each on a
                 -- University-wide (GLOBAL) posting the Director grants, never in the baseline
                 'MIGRATE_PRELIM_APPLICANTS', 'CHANGE_PRELIM_PROGRAMME']
$function$;

/* who uploads old-portal preliminary applicants: the Director of ICT, the Academic Office, a Database Operator (the API holds them to a
   University-wide grant, as for the PG migration), the head of the support desk, super — or an ICT Support agent the Director
   authorised on a University-wide posting carrying MIGRATE_PRELIM_APPLICANTS; a person, never a job */
CREATE OR REPLACE FUNCTION admissions.prelim_mig_writer() RETURNS void LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := coalesce(current_setting('moaum.actor_office', true), '');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PRELIMMIG_ACTOR: a migration is made by a person' USING ERRCODE = '23514'; END IF;
    IF v_office IN ('ict', 'academic', 'dbops', 'super', 'helpdeskhead') THEN RETURN; END IF;
    IF v_office = 'ictagent' AND coalesce((SELECT s.global FROM helpdesk.agent_scope_for(v_actor, 'MIGRATE_PRELIM_APPLICANTS') s), false) THEN RETURN; END IF;
    RAISE EXCEPTION 'PRELIMMIG_OFFICE: the Director of ICT, the Academic Office, a Database Operator or an ICT Support agent the Director has authorised uploads old-portal preliminary applicants, not %',
        coalesce(nullif(v_office, ''), 'this office') USING ERRCODE = '42501';
END $fn$;

/* who corrects a preliminary applicant's programme: the Director of ICT, the head of the support desk, super, or an agent the Director
   authorised on a University-wide posting carrying CHANGE_PRELIM_PROGRAMME */
CREATE OR REPLACE FUNCTION admissions.prelim_route_officer() RETURNS void LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := coalesce(current_setting('moaum.actor_office', true), '');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PRELIM_CHANGE_ACTOR: a programme is corrected by a person' USING ERRCODE = '23514'; END IF;
    IF v_office IN ('ict', 'super', 'helpdeskhead') THEN RETURN; END IF;
    IF v_office = 'ictagent' AND coalesce((SELECT s.global FROM helpdesk.agent_scope_for(v_actor, 'CHANGE_PRELIM_PROGRAMME') s), false) THEN RETURN; END IF;
    RAISE EXCEPTION 'PRELIM_CHANGE_OFFICE: the Director of ICT or an ICT Support agent the Director has authorised changes a preliminary applicant''s programme, not %',
        coalesce(nullif(v_office, ''), 'this office') USING ERRCODE = '42501';
END $fn$;

-- ── 7 · the check of one row: what it would do, and why not ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.prelim_migration_assess(p_row uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE
    r admissions.prelim_migration_row; b admissions.prelim_migration_batch; p admissions.prelim_programme; o admissions.prelim_programme;
    d jsonb; probs jsonb := '[]'; c record; res record; v_x text; v_n int; v_dup int; v_nos text; v_i int;
    v_legacy text; v_surname text; v_first text; v_others text; v_full text; v_sex text; v_dob date; v_email text; v_email_raw text; v_phone text;
    v_kin_phone text; v_jamb text; v_state text; v_admission text; v_pay text; v_word text;
    v_ref text; v_gw text; v_amt_raw text; v_amt numeric; v_paid_on date; v_applied date; v_fee numeric; v_route_named text;
    v_target uuid; v_spec uuid; v_tproblem text; v_tdetail text;
    v_sittings jsonb := '[]'; v_body text; v_type text; v_type_raw text; v_year int; v_no text; v_subjects jsonb; v_keys text[] := '{}'; v_key text; v_sp text;
    v_max int; v_bad boolean;
    v_app_legacy uuid; v_app_email uuid; v_acc_email uuid; v_acc_route text; v_acc_app_no text; v_app uuid;
    a admissions.application; ac admissions.candidate; ar admissions.prelim_review; lg admissions.prelim_legacy_application;
    v_match text; v_action text; v_verdict text; v_clash text; v_target_state text; v_answers jsonb;
BEGIN
    SELECT * INTO r FROM admissions.prelim_migration_row WHERE id = p_row;
    IF r.id IS NULL THEN RAISE EXCEPTION 'no such migration row' USING ERRCODE = '23503'; END IF;
    SELECT * INTO b FROM admissions.prelim_migration_batch WHERE id = r.batch_id;
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = b.route;
    SELECT * INTO o FROM admissions.prelim_programme WHERE route = CASE b.route WHEN 'PRELIMINARY_SCIENCE' THEN 'PRELIMINARY_TECHNOLOGY' ELSE 'PRELIMINARY_SCIENCE' END;
    d := r.data;

    -- the old number: its shape, and once in the file
    v_legacy := upper(admissions.pg_mig_t(d, 'legacyApplicationNo'));
    IF v_legacy IS NOT NULL AND (length(v_legacy) > 40 OR v_legacy !~ '^[A-Z0-9][A-Z0-9/.-]*$') THEN
        probs := probs || admissions.pg_mig_problem('LEGACY_NO_INVALID', 'error', format('"%s" is not an application number.', left(v_legacy, 40)),
                 'Letters, digits and / - . only, no spaces, at most 40 characters, as the old portal shows it.');
    ELSIF v_legacy IS NOT NULL THEN
        SELECT min(x.row_no) INTO v_dup FROM admissions.prelim_migration_row x WHERE x.batch_id = r.batch_id AND x.legacy_no = v_legacy AND x.row_no < r.row_no;
        IF v_dup IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('DUPLICATE_IN_FILE', 'duplicate', format('Row %s has the same application number.', v_dup),
                     'Keep one row for the applicant; this repeat is not imported.');
        END IF;
    END IF;
    -- the old number is a sign-in beside this portal's own: never shaped like this portal's APP number, never a number an account here
    -- already signs in with (an application number or a JAMB number); a JAMB-shaped number no account holds stays the old number
    IF v_legacy ~ '^APP/[0-9]{2}/[0-9]{6}$' THEN
        probs := probs || admissions.pg_mig_problem('LEGACY_NO_IS_PORTAL_NUMBER', 'error', format('"%s" is shaped like this portal''s own application numbers, not the old portal''s.', v_legacy),
                 'Give the application number the old portal issued; this portal gives its own APP number at the import.');
    ELSIF v_legacy IS NOT NULL AND (EXISTS (SELECT 1 FROM admissions.application x WHERE x.application_no = v_legacy)
                                    OR EXISTS (SELECT 1 FROM admissions.applicant_account x WHERE x.jamb_key = v_legacy)) THEN
        probs := probs || admissions.pg_mig_problem('LEGACY_NO_IS_PORTAL_NUMBER', 'conflict',
                 format('"%s" is already an applicant''s %s on this portal, and signs that applicant in.', v_legacy,
                        CASE WHEN EXISTS (SELECT 1 FROM admissions.application x WHERE x.application_no = v_legacy) THEN 'application number' ELSE 'JAMB number' END),
                 'One number signs in one applicant: check the number against the old portal; ICT settles a number this portal already uses.');
    END IF;

    -- the name (a "Full Name" column read when the template's are blank)
    v_surname := admissions.pg_mig_t(d, 'surname');
    v_first := admissions.pg_mig_t(d, 'firstName');
    v_others := admissions.pg_mig_t(d, 'otherNames');
    v_full := admissions.pg_mig_t(d, 'fullName');
    IF v_surname IS NULL AND v_first IS NULL AND v_full IS NOT NULL THEN
        IF position(',' IN v_full) > 0 THEN
            v_surname := btrim(split_part(v_full, ',', 1)); v_x := btrim(substr(v_full, position(',' IN v_full) + 1));
        ELSE
            v_surname := split_part(v_full, ' ', 1); v_x := btrim(substr(v_full, length(split_part(v_full, ' ', 1)) + 1));
        END IF;
        v_first := nullif(split_part(v_x, ' ', 1), ''); v_others := nullif(btrim(substr(v_x, length(split_part(v_x, ' ', 1)) + 1)), '');
    END IF;

    -- every required column given
    FOR c IN SELECT x.key, x.header, x.note FROM admissions.prelim_migration_columns(b.route) x WHERE x.required LOOP
        v_x := CASE c.key WHEN 'surname' THEN v_surname WHEN 'firstName' THEN v_first ELSE admissions.pg_mig_t(d, c.key) END;
        IF v_x IS NULL THEN
            probs := probs || admissions.pg_mig_problem('MISSING_' || upper(regexp_replace(c.key, '([a-z0-9])([A-Z])', '\1_\2', 'g')), 'error',
                     format('%s is missing.', c.header), coalesce(c.note, 'Give it as the old portal shows it.'));
        END IF;
    END LOOP;
    IF (v_surname IS NOT NULL OR v_first IS NOT NULL)
       AND (coalesce(v_surname, '') || ' ' || coalesce(v_first, '') || ' ' || coalesce(v_others, '')) ~ '[0-9=@<>{}\\;|_]'
        OR length(coalesce(v_surname, '')) > 60 OR length(coalesce(v_first, '')) > 60 OR length(coalesce(v_others, '')) > 60
        OR (v_surname IS NOT NULL AND v_surname !~ '[[:alpha:]]') OR (v_first IS NOT NULL AND v_first !~ '[[:alpha:]]') THEN
        probs := probs || admissions.pg_mig_problem('NAME_INVALID', 'error', format('"%s, %s" is not a name.', left(coalesce(v_surname, ''), 40), left(concat_ws(' ', v_first, v_others), 40)),
                 'Letters, spaces, hyphens and apostrophes only; at most 60 characters each.');
    END IF;

    -- the person: gender, birth date, contacts
    v_x := admissions.pg_mig_t(d, 'gender'); v_sex := admissions.prelim_mig_gender(v_x);
    IF v_x IS NOT NULL AND v_sex IS NULL THEN
        probs := probs || admissions.pg_mig_problem('GENDER_INVALID', 'error', format('Gender "%s" is not read.', left(v_x, 20)), 'Male or Female.');
    END IF;
    v_x := admissions.pg_mig_t(d, 'dateOfBirth'); v_dob := admissions.pg_mig_date(v_x);
    IF v_x IS NOT NULL AND v_dob IS NULL THEN
        probs := probs || admissions.pg_mig_problem('DATE_INVALID', 'error', format('Date of birth "%s" is not a date, or is in the future.', left(v_x, 20)),
                 'DD/MM/YYYY, YYYY-MM-DD or an Excel date.');
    ELSIF v_dob IS NOT NULL AND (v_dob > current_date - interval '10 years' OR v_dob < DATE '1950-01-01') THEN
        probs := probs || admissions.pg_mig_problem('DOB_UNLIKELY', 'warning', format('Date of birth %s is unlikely for an applicant.', to_char(v_dob, 'DD Mon YYYY')),
                 'Check it against the old portal; it is imported as written.');
    END IF;
    v_email_raw := admissions.pg_mig_t(d, 'email');
    v_email := admissions.first_email(v_email_raw);
    IF v_email_raw IS NOT NULL AND (v_email IS NULL OR length(v_email) > 254) THEN
        probs := probs || admissions.pg_mig_problem('EMAIL_INVALID', 'error', format('"%s" is not an email address.', left(v_email_raw, 80)), 'Correct it, or leave it blank.');
        v_email := NULL;
    ELSIF v_email IS NOT NULL THEN
        SELECT min(x.row_no) INTO v_dup FROM admissions.prelim_migration_row x
         WHERE x.batch_id = r.batch_id AND x.email = v_email AND x.row_no < r.row_no AND x.legacy_no IS DISTINCT FROM v_legacy;
        IF v_dup IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('DUPLICATE_EMAIL_IN_FILE', 'duplicate', format('Row %s has the same email for another application number.', v_dup),
                     'One email is one applicant''s sign-in: correct one of the two rows.');
        END IF;
    END IF;
    v_x := admissions.pg_mig_t(d, 'phone'); v_phone := admissions.cce_phone(coalesce(admissions.first_mobile(v_x), v_x));
    IF v_x IS NOT NULL AND v_phone IS NULL THEN
        probs := probs || admissions.pg_mig_problem('PHONE_INVALID', 'error', format('Phone "%s" is not a Nigerian mobile number.', left(v_x, 30)), 'Eleven digits, 080…, or +234….');
    END IF;
    v_x := admissions.pg_mig_t(d, 'nextOfKinPhone'); v_kin_phone := admissions.cce_phone(coalesce(admissions.first_mobile(v_x), v_x));
    IF v_x IS NOT NULL AND v_kin_phone IS NULL THEN
        probs := probs || admissions.pg_mig_problem('PHONE_INVALID', 'warning', format('Next of kin phone "%s" is not read; left blank.', left(v_x, 30)), 'Eleven digits, 080…, or +234….');
    END IF;
    v_jamb := upper(regexp_replace(coalesce(admissions.pg_mig_t(d, 'jambRegNo'), ''), '\s', '', 'g'));
    v_jamb := nullif(v_jamb, '');
    IF v_jamb IS NOT NULL AND v_jamb !~ '^[0-9]{6,}[A-Z]{0,3}$' THEN
        probs := probs || admissions.pg_mig_problem('JAMB_INVALID', 'warning', format('"%s" is not a JAMB registration number; kept as written.', left(v_jamb, 30)), NULL);
    END IF;
    FOREACH v_x IN ARRAY ARRAY['applicationDate', 'paymentDate'] LOOP
        IF admissions.pg_mig_t(d, v_x) IS NOT NULL AND admissions.pg_mig_date(admissions.pg_mig_t(d, v_x)) IS NULL THEN
            probs := probs || admissions.pg_mig_problem('DATE_INVALID', 'error',
                     format('%s "%s" is not a date, or is in the future.', CASE v_x WHEN 'applicationDate' THEN 'Application date' ELSE 'Payment date' END, left(admissions.pg_mig_t(d, v_x), 20)),
                     'DD/MM/YYYY, YYYY-MM-DD or an Excel date.');
        END IF;
    END LOOP;
    v_applied := admissions.pg_mig_date(admissions.pg_mig_t(d, 'applicationDate'));

    -- the old portal's words for the application, the admission and the payment
    v_word := admissions.pg_mig_t(d, 'applicationStatus');
    v_state := admissions.prelim_mig_status('APPLICATION', v_word);
    IF v_word IS NOT NULL AND v_state IS NULL THEN
        probs := probs || admissions.pg_mig_problem('STATUS_UNKNOWN', 'error', format('Application status "%s" is not one this portal reads.', left(v_word, 40)),
                 'One of the statuses in the template''s drop-down.');
    END IF;
    v_word := admissions.pg_mig_t(d, 'admissionStatus');
    v_admission := coalesce(admissions.prelim_mig_status('ADMISSION', v_word), CASE WHEN v_word IS NULL THEN 'PENDING' END);
    IF v_admission IS NULL THEN
        probs := probs || admissions.pg_mig_problem('STATUS_UNKNOWN', 'error', format('Admission status "%s" is not one this portal reads.', left(v_word, 40)),
                 'One of the statuses in the template''s drop-down, or blank for pending.');
    END IF;
    v_word := admissions.pg_mig_t(d, 'paymentStatus');
    v_pay := admissions.prelim_mig_status('PAYMENT', v_word);
    IF v_word IS NOT NULL AND v_pay IS NULL THEN
        probs := probs || admissions.pg_mig_problem('STATUS_UNKNOWN', 'error', format('Payment status "%s" is not one this portal reads.', left(v_word, 40)),
                 'Paid or Not paid (the template''s drop-down).');
    END IF;
    IF v_admission IN ('ADMITTED', 'ACCEPTED', 'NOT_ADMITTED') AND v_state IN ('DRAFT', 'WITHDRAWN') THEN
        probs := probs || admissions.pg_mig_problem('STATUS_INCONSISTENT', 'error',
                 format('Decided on the old portal (%s) but the application is %s there.', lower(replace(v_admission, '_', ' ')), lower(v_state)),
                 'An application decided on the old portal was submitted: correct the application status or the admission status.');
    END IF;
    v_target_state := CASE WHEN v_admission IN ('ADMITTED', 'ACCEPTED') THEN 'ADMITTED' WHEN v_admission = 'NOT_ADMITTED' THEN 'NOT_ADMITTED' ELSE v_state END;

    -- the programme: the upload's route; a row naming the other preliminary programme is held back
    v_x := admissions.pg_mig_t(d, 'programme');
    IF v_x IS NOT NULL THEN
        v_route_named := admissions.prelim_mig_route_of(v_x);
        IF v_route_named = o.route THEN
            probs := probs || admissions.pg_mig_problem('PROGRAMME_MISMATCH', 'conflict',
                     format('The row names %s ("%s"); this upload is for %s.', o.name, left(v_x, 80), p.name),
                     'Upload the row with the ' || o.name || ' file, or correct its programme on the portal after it is imported.');
        ELSIF v_route_named IS NULL THEN
            probs := probs || admissions.pg_mig_problem('PROGRAMME_WORD_UNKNOWN', 'warning',
                     format('Programme "%s" is not read; the applicant comes in under %s, the programme of this upload.', left(v_x, 80), p.name), NULL);
        END IF;
    END IF;

    -- the target (and its specialisation) among the route's own
    SELECT x.target_id, x.specialisation_id, x.problem, x.detail INTO v_target, v_spec, v_tproblem, v_tdetail
      FROM admissions.prelim_mig_target_of(b.route, admissions.pg_mig_t(d, 'target'),
                                           CASE WHEN b.route = 'PRELIMINARY_TECHNOLOGY' THEN admissions.pg_mig_t(d, 'specialisation') END) x;
    IF v_tproblem IS NOT NULL THEN
        probs := probs || admissions.pg_mig_problem(v_tproblem, 'warning', v_tdetail || '; imported without it.',
                 'The applicant, or the Office, chooses it on the portal; or correct it from the template''s list.');
    END IF;

    -- the O'Level: each sitting complete and released, of a body and a qualification the route accepts
    v_max := least(greatest(coalesce(p.max_sittings, 1), 1), 2);
    FOR v_i IN 1 .. 2 LOOP
        v_body := admissions.pg_mig_t(d, 'olevel' || v_i || 'Body');
        v_type_raw := admissions.pg_mig_t(d, 'olevel' || v_i || 'Qualification');
        v_x := admissions.pg_mig_t(d, 'olevel' || v_i || 'Year');
        v_no := admissions.pg_mig_t(d, 'olevel' || v_i || 'Number');
        v_sp := admissions.pg_mig_t(d, 'olevel' || v_i || 'Results');
        CONTINUE WHEN coalesce(v_body, v_type_raw, v_x, v_no, v_sp) IS NULL;
        IF v_i > v_max THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_SITTINGS', 'error', format('%s accepts at most %s sitting%s; the row gives sitting %s.', p.name, v_max, CASE WHEN v_max = 1 THEN '' ELSE 's' END, v_i),
                     'Give the sittings the applicant used, up to the number allowed.');
            CONTINUE;
        END IF;
        v_bad := false;
        IF v_body IS NULL THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_BODY_MISSING', 'error', format('O''Level sitting %s: the examination type is missing.', v_i), 'WAEC, NECO, NABTEB or OTHER.'); v_bad := true;
        ELSIF admissions.prelim_mig_body(v_body) IS NULL THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_BODY_INVALID', 'error', format('O''Level sitting %s: "%s" is not an examination body.', v_i, left(v_body, 30)), 'WAEC, NECO, NABTEB or OTHER.'); v_bad := true;
        END IF;
        v_body := admissions.prelim_mig_body(v_body);
        IF v_type_raw IS NULL THEN
            v_type := 'SSCE';
        ELSE
            SELECT q.code INTO v_type FROM admissions.qualification_type q
             WHERE q.active AND admissions.pg_legacy_key(v_type_raw) IN (admissions.pg_legacy_key(q.code), admissions.pg_legacy_key(q.label)) LIMIT 1;
        END IF;
        IF v_type IS NULL OR v_type <> ALL (p.qualification_types) THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_QUALIFICATION_INVALID', 'error',
                     format('O''Level sitting %s: "%s" is not a qualification %s accepts.', v_i, left(coalesce(v_type_raw, v_type, ''), 40), p.name),
                     'One of: ' || (SELECT string_agg(q.code, ', ' ORDER BY q.ord) FROM admissions.qualification_type q WHERE q.active AND q.code = ANY (p.qualification_types)) || '.');
            v_bad := true;
        END IF;
        v_year := CASE WHEN coalesce(v_x, '') ~ '^[0-9]{4}$' THEN v_x::int END;
        IF v_x IS NULL THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_YEAR_MISSING', 'error', format('O''Level sitting %s: the examination year is missing.', v_i), 'YYYY.'); v_bad := true;
        ELSIF v_year IS NULL OR v_year < 1970 OR v_year > extract(year FROM current_date)::int THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_YEAR_INVALID', 'error', format('O''Level sitting %s: "%s" is not an examination year.', v_i, left(v_x, 10)), 'YYYY, from 1970 to this year.'); v_bad := true;
        END IF;
        IF v_no IS NULL THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_NUMBER_MISSING', 'error', format('O''Level sitting %s: the examination number is missing.', v_i), NULL); v_bad := true;
        ELSIF length(v_no) > 30 THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_NUMBER_INVALID', 'error', format('O''Level sitting %s: the examination number is longer than 30 characters.', v_i), NULL); v_bad := true;
        END IF;
        v_subjects := '[]';
        IF v_sp IS NULL THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_RESULTS_MISSING', 'error', format('O''Level sitting %s: the subjects and grades are missing.', v_i),
                     'Subject:Grade; Subject:Grade — e.g. English Language:C4; Mathematics:B3.'); v_bad := true;
        ELSE
            v_n := 0;
            FOR res IN SELECT * FROM admissions.prelim_mig_results(v_sp) LOOP
                v_n := v_n + 1;
                IF res.problem IS NULL THEN
                    v_subjects := v_subjects || jsonb_build_array(jsonb_build_object('subject', res.subject, 'grade', res.grade));
                ELSE
                    v_bad := true;
                    probs := probs || CASE res.problem
                        WHEN 'SUBJECT_UNKNOWN' THEN admissions.pg_mig_problem('OLEVEL_SUBJECT_UNKNOWN', 'error', format('O''Level sitting %s: "%s" is not a subject the application form knows.', v_i, left(res.given, 60)),
                                                    'Write the subject as the template''s Subjects sheet names it.')
                        WHEN 'NO_GRADE' THEN admissions.pg_mig_problem('OLEVEL_GRADE_INVALID', 'error', format('O''Level sitting %s: %s has no grade.', v_i, left(res.given, 60)),
                                                    'Subject:Grade, the grade A1 to F9.')
                        WHEN 'AWAITING' THEN admissions.pg_mig_problem('OLEVEL_AWAITING', 'error', format('O''Level sitting %s: %s is an awaiting result; %s admits on results already released.', v_i, left(res.given, 60), p.name),
                                                    'Give the released grade, or leave the sitting out.')
                        WHEN 'GRADE_INVALID' THEN admissions.pg_mig_problem('OLEVEL_GRADE_INVALID', 'error', format('O''Level sitting %s: "%s" is not a grade (%s).', v_i, left(coalesce(res.grade, ''), 10), left(res.given, 60)),
                                                    'A1, B2, B3, C4, C5, C6, D7, E8 or F9.')
                        ELSE admissions.pg_mig_problem('OLEVEL_SUBJECT_TWICE', 'error', format('O''Level sitting %s: %s is given twice.', v_i, left(res.given, 60)), 'Give each subject once.') END;
                END IF;
            END LOOP;
            IF v_n = 0 THEN
                probs := probs || admissions.pg_mig_problem('OLEVEL_RESULTS_MISSING', 'error', format('O''Level sitting %s: no subject and grade is read.', v_i),
                         'Subject:Grade; Subject:Grade — e.g. English Language:C4; Mathematics:B3.'); v_bad := true;
            ELSIF v_n > 9 THEN
                probs := probs || admissions.pg_mig_problem('OLEVEL_RESULTS_TOO_MANY', 'error', format('O''Level sitting %s: %s subjects; nine at most.', v_i, v_n), NULL); v_bad := true;
            END IF;
        END IF;
        CONTINUE WHEN v_bad;
        v_key := admissions.prelim_mig_olevel_key(v_body, v_year::text, v_no);
        IF v_key = ANY (v_keys) THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_SITTING_TWICE', 'error', format('O''Level sitting %s is the same examination as sitting 1.', v_i), 'Give two different sittings, or one.');
            CONTINUE;
        END IF;
        v_keys := v_keys || v_key;
        v_sittings := v_sittings || jsonb_build_array(jsonb_build_object('sitting', v_i, 'body', v_body, 'type', v_type, 'year', v_year, 'number', v_no, 'subjects', v_subjects));
        -- the same sitting on another row of the file (through the keys' own index)
        SELECT min(x.row_no) INTO v_dup
          FROM (SELECT x2.row_no, x2.batch_id, x2.legacy_no FROM admissions.prelim_migration_row x2 WHERE x2.olevel_keys @> ARRAY[v_key] OFFSET 0) x
         WHERE x.batch_id = r.batch_id AND x.row_no < r.row_no AND x.legacy_no IS DISTINCT FROM v_legacy;
        IF v_dup IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_IN_FILE', 'duplicate', format('O''Level sitting %s (%s %s, %s) is also on row %s, another applicant.', v_i, v_body, v_year, left(v_no, 30), v_dup),
                     'One examination sitting is one person''s: correct the number on one of the rows.');
        END IF;
    END LOOP;

    -- who this is: the application the old number brought before, the account of the email, or nobody yet
    IF v_legacy IS NOT NULL THEN
        SELECT l.application_id INTO v_app_legacy FROM admissions.prelim_legacy_application l WHERE upper(btrim(l.legacy_application_no)) = v_legacy;
    END IF;
    IF v_email IS NOT NULL THEN
        SELECT acc.id, ap.id, pr.route, ap.application_no INTO v_acc_email, v_app_email, v_acc_route, v_acc_app_no
          FROM admissions.applicant_account acc LEFT JOIN admissions.application ap ON ap.account_id = acc.id
          LEFT JOIN admissions.prelim_review pr ON pr.application_id = ap.id
         WHERE lower(acc.email) = v_email LIMIT 1;
        IF v_acc_email IS NOT NULL AND coalesce(v_acc_route, '') NOT IN ('PRELIMINARY_SCIENCE', 'PRELIMINARY_TECHNOLOGY') THEN
            probs := probs || admissions.pg_mig_problem('EMAIL_ELSEWHERE', 'conflict',
                     format('%s is the sign-in of another application on this portal (%s), not a preliminary one.', v_email, coalesce(v_acc_app_no, 'an applicant account')),
                     'Give the email the applicant used on the old portal for this application, or leave it blank.');
            v_app_email := NULL;
        END IF;
    END IF;
    IF v_app_legacy IS NOT NULL AND v_app_email IS NOT NULL AND v_app_legacy <> v_app_email THEN
        probs := probs || admissions.pg_mig_problem('IDENTITY_SPLIT', 'conflict',
                 format('The application number and the email point to different applications here (%s, %s).',
                        (SELECT x.application_no FROM admissions.application x WHERE x.id = v_app_legacy), v_acc_app_no),
                 'Settle which application is this applicant''s before importing the row.');
    END IF;
    v_app := coalesce(v_app_legacy, v_app_email);

    IF v_app IS NOT NULL THEN
        SELECT * INTO a FROM admissions.application WHERE id = v_app;
        SELECT * INTO ac FROM admissions.candidate WHERE id = a.candidate_id;
        SELECT * INTO ar FROM admissions.prelim_review WHERE application_id = v_app;
        SELECT * INTO lg FROM admissions.prelim_legacy_application WHERE application_id = v_app;
        v_match := 'EXISTING_APPLICANT';
        v_action := CASE WHEN v_app_legacy IS NOT NULL THEN CASE WHEN b.allow_update THEN 'UPDATE' ELSE 'NONE' END ELSE 'RECONCILE' END;
        IF ar.route IS DISTINCT FROM b.route THEN
            probs := probs || admissions.pg_mig_problem('PROGRAMME_CONFLICT', 'conflict',
                     format('Already on the portal under %s as %s.', coalesce((SELECT x.name FROM admissions.prelim_programme x WHERE x.route = ar.route), ar.route), a.application_no),
                     'Correct its programme on the portal instead (Programme corrections), or upload the row with that programme''s file.');
        END IF;
        IF v_app_legacy IS NULL AND lg.application_id IS NOT NULL AND v_legacy IS NOT NULL AND upper(btrim(lg.legacy_application_no)) <> v_legacy THEN
            probs := probs || admissions.pg_mig_problem('LEGACY_NUMBER_DIFFERS', 'conflict',
                     format('Application %s already carries old application number %s.', a.application_no, lg.legacy_application_no),
                     'One application, one old number: check which is right.');
        END IF;
        IF v_surname IS NOT NULL AND admissions.pg_legacy_key(ac.surname) IS DISTINCT FROM admissions.pg_legacy_key(v_surname) THEN
            probs := probs || admissions.pg_mig_problem('NAME_DIFFERS', 'conflict', format('Application %s is in the name of %s, %s.', a.application_no, ac.surname, ac.other_names),
                     'Check that this is the same person; a name is corrected on the application, not by a migration.');
        END IF;
        v_x := (SELECT sa.value FROM admissions.screening_answer sa WHERE sa.application_id = v_app AND sa.field = 'date_of_birth');
        IF v_dob IS NOT NULL AND v_x IS NOT NULL AND v_x <> v_dob::text THEN
            probs := probs || admissions.pg_mig_problem('DOB_DIFFERS', 'conflict', format('Application %s gives the date of birth %s.', a.application_no, v_x),
                     'Check that this is the same person.');
        END IF;
        IF a.session IS DISTINCT FROM b.session THEN
            probs := probs || admissions.pg_mig_problem('SESSION_DIFFERS', 'conflict', format('Application %s is of %s; this upload is for %s.', a.application_no, a.session, b.session),
                     'A preliminary application is migrated into the session its programme admits for.');
        END IF;
        -- the outcome: one decided here stands, and a contrary one on the old portal is held back
        IF ar.published_at IS NOT NULL AND ((ar.state = 'ADMITTED' AND v_admission = 'NOT_ADMITTED')
                                            OR (ar.state IN ('NOT_ADMITTED', 'REJECTED') AND v_admission IN ('ADMITTED', 'ACCEPTED'))) THEN
            probs := probs || admissions.pg_mig_problem('DECISION_DIFFERS', 'conflict',
                     format('Application %s is %s here; the old portal says %s.', a.application_no, lower(replace(ar.state, '_', ' ')), lower(replace(v_admission, '_', ' '))),
                     'The outcome published here stands; the Academic Office settles a difference.');
        ELSIF v_admission IN ('ADMITTED', 'ACCEPTED', 'NOT_ADMITTED') AND (ar.published_at IS NOT NULL OR ar.state IN ('APPROVED', 'NOT_ADMITTED', 'REJECTED', 'WITHDRAWN'))
              AND NOT (ar.state = 'ADMITTED' AND v_admission IN ('ADMITTED', 'ACCEPTED')) THEN
            probs := probs || admissions.pg_mig_problem('PORTAL_FURTHER', 'warning',
                     format('Application %s is %s here: kept; the old portal''s decision is not applied.', a.application_no, lower(replace(ar.state, '_', ' '))), NULL);
        END IF;
        IF v_state = 'WITHDRAWN' AND ar.state <> 'WITHDRAWN' THEN
            probs := probs || admissions.pg_mig_problem('WITHDRAWN_ON_OLD_PORTAL', 'warning',
                     format('Withdrawn on the old portal; application %s stays as it is here.', a.application_no), NULL);
        END IF;
    ELSE
        v_match := 'NEW_APPLICANT'; v_action := 'CREATE';
        IF v_email IS NULL AND v_email_raw IS NULL THEN
            probs := probs || admissions.pg_mig_problem('NO_EMAIL', 'warning',
                     'No email: the applicant signs in with the application number, and is told by SMS.', NULL);
        END IF;
        -- the same person, perhaps, on a preliminary application of either route: never merged unseen
        IF v_surname IS NOT NULL THEN
            SELECT string_agg(x.application_no, ', ') INTO v_nos FROM (
                SELECT ap.application_no FROM admissions.candidate cc
                  JOIN admissions.application ap ON ap.candidate_id = cc.id
                  JOIN admissions.prelim_review pr ON pr.application_id = ap.id AND pr.route IN ('PRELIMINARY_SCIENCE', 'PRELIMINARY_TECHNOLOGY')
                  JOIN admissions.applicant_account acc ON acc.id = ap.account_id
                  LEFT JOIN admissions.screening_answer sa ON sa.application_id = ap.id AND sa.field = 'date_of_birth'
                 WHERE cc.entry_mode IN ('PRELIMINARY', 'PROFICIENCY') AND upper(cc.surname) = upper(v_surname)
                   AND ((v_dob IS NOT NULL AND v_first IS NOT NULL AND lower(split_part(cc.other_names, ' ', 1)) = lower(v_first) AND sa.value = v_dob::text)
                        OR (v_phone IS NOT NULL AND acc.phone = v_phone))
                 ORDER BY ap.application_no LIMIT 3) x;
            IF v_nos IS NOT NULL THEN
                probs := probs || admissions.pg_mig_problem('POSSIBLE_SAME_APPLICANT', CASE WHEN r.decided_new THEN 'warning' ELSE 'review' END,
                         format('A preliminary applicant of the same surname and %s is on the portal (%s).', CASE WHEN v_phone IS NOT NULL THEN 'first name and birth date, or phone' ELSE 'first name and birth date' END, v_nos)
                         || CASE WHEN r.decided_new THEN ' Confirmed a new applicant: ' || coalesce(r.decided_new_reason, '') ELSE '' END,
                         'If it is the same person, give that application''s email so the row finds it; else confirm a new applicant on the row, with the reason.');
            END IF;
        END IF;
    END IF;
    IF v_jamb IS NOT NULL THEN
        SELECT string_agg(x.session || ' ' || x.surname, ', ') INTO v_nos FROM (
            SELECT cc.session, cc.surname FROM admissions.candidate cc WHERE cc.jamb_key = v_jamb AND (v_app IS NULL OR cc.id <> a.candidate_id) LIMIT 3) x;
        IF v_nos IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('JAMB_ON_PORTAL', 'warning', format('JAMB number %s is already on the portal (%s); kept on the old portal''s record only, never merged.', v_jamb, v_nos), NULL);
        END IF;
    END IF;
    -- a sitting on another live application of the route and session
    IF cardinality(v_keys) > 0 THEN
        SELECT string_agg(DISTINCT ap.application_no, ', ') INTO v_nos
          FROM admissions.screening_olevel so
          JOIN admissions.prelim_review pr ON pr.application_id = so.application_id AND pr.route = b.route AND pr.state <> 'WITHDRAWN'
          JOIN admissions.application ap ON ap.id = so.application_id
         WHERE so.active AND ap.session = b.session AND so.application_id IS DISTINCT FROM v_app
           AND (so.exam_year, upper(regexp_replace(so.exam_number, '\s', '', 'g'))) IN
               (SELECT split_part(k, '|', 2)::int, split_part(k, '|', 3) FROM unnest(v_keys) k)
           AND (upper(so.exam_body) || '|' || so.exam_year || '|' || upper(regexp_replace(so.exam_number, '\s', '', 'g'))) = ANY (v_keys);
        IF v_nos IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_ELSEWHERE', 'conflict', format('An O''Level sitting of the row is already on another %s application for %s (%s).', p.name, b.session, v_nos),
                     'One examination sitting is one person''s: check which applicant it belongs to.');
        END IF;
    END IF;

    -- the payment: a "Paid" is held for the Bursary; nothing is invented
    v_ref := admissions.pg_mig_t(d, 'paymentReference');
    v_gw := admissions.pg_mig_t(d, 'gatewayReference');
    v_amt_raw := admissions.pg_mig_t(d, 'amountPaid');
    v_amt := admissions.pg_mig_amount(v_amt_raw);
    v_paid_on := admissions.pg_mig_date(admissions.pg_mig_t(d, 'paymentDate'));
    SELECT f.application_fee + f.portal_charge INTO v_fee FROM admissions.route_fee_rule(b.session, b.route) f;
    IF v_pay = 'PAID' THEN
        IF v_amt IS NULL THEN
            probs := probs || admissions.pg_mig_problem('AMOUNT_MISSING', 'error',
                     CASE WHEN v_amt_raw IS NULL THEN 'Paid, with no amount.' ELSE format('Paid, but the amount "%s" is not read.', left(v_amt_raw, 20)) END,
                     'Give the amount paid in naira.');
        ELSIF v_fee IS NOT NULL AND v_amt <> v_fee THEN
            probs := probs || admissions.pg_mig_problem('AMOUNT_DIFFERS', 'warning',
                     format('The amount paid (₦%s) is not the %s application fee (₦%s); held for the Bursary to settle.', to_char(v_amt, 'FM999,999,990.##'), p.name, to_char(v_fee, 'FM999,999,990.##')), NULL);
        END IF;
        IF v_ref IS NULL THEN
            probs := probs || admissions.pg_mig_problem('NO_PAYMENT_REFERENCE', 'warning',
                     'Paid, with no payment reference: held, and flagged for the Bursary to find the reference.' || CASE WHEN v_gw IS NOT NULL THEN ' The gateway''s reference is kept.' ELSE '' END, NULL);
        ELSE
            SELECT min(x.row_no) INTO v_dup FROM admissions.prelim_migration_row x
             WHERE x.batch_id = r.batch_id AND x.fee_ref = upper(btrim(v_ref)) AND x.row_no < r.row_no AND x.legacy_no IS DISTINCT FROM v_legacy;
            IF v_dup IS NOT NULL THEN
                probs := probs || admissions.pg_mig_problem('FEE_REFERENCE_IN_FILE', 'duplicate', format('Payment reference %s is also on row %s, another applicant.', left(v_ref, 40), v_dup),
                         'One payment belongs to one applicant: correct the reference.');
            ELSE
                v_clash := admissions.prelim_mig_fee_clash(v_ref, v_app);
                IF v_clash IS NOT NULL THEN
                    probs := probs || admissions.pg_mig_problem('FEE_REFERENCE_ELSEWHERE', 'conflict', format('Payment reference %s is %s.', left(v_ref, 40), v_clash),
                             'A payment is recorded once: the Bursary settles a payment claimed twice.');
                END IF;
            END IF;
        END IF;
        IF v_gw IS NOT NULL AND v_clash IS NULL THEN
            v_clash := admissions.prelim_mig_fee_clash(v_gw, v_app);
            IF v_clash IS NOT NULL THEN
                probs := probs || admissions.pg_mig_problem('FEE_REFERENCE_ELSEWHERE', 'conflict', format('Gateway reference %s is %s.', left(v_gw, 40), v_clash),
                         'A payment is recorded once: the Bursary settles a payment claimed twice.');
            END IF;
        END IF;
        IF v_app IS NOT NULL AND a.fee_confirmed_at IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee x WHERE x.application_id = v_app AND x.state <> 'REJECTED') THEN
            probs := probs || admissions.pg_mig_problem('FEE_ALREADY_PAID_HERE', 'warning',
                     format('Application %s''s fee is already paid on this portal: the old payment is not held.', a.application_no), NULL);
        END IF;
    ELSIF v_ref IS NOT NULL OR v_amt_raw IS NOT NULL OR v_gw IS NOT NULL THEN
        probs := probs || admissions.pg_mig_problem('PAYMENT_INCONSISTENT', 'error',
                 format('A payment reference or amount is given, but the payment status is %s.', CASE WHEN v_pay IS NULL THEN 'blank' ELSE '"' || left(admissions.pg_mig_t(d, 'paymentStatus'), 30) || '"' END),
                 'Mark the payment Paid (it is held for the Bursary to verify), or clear the reference and amount.');
    END IF;
    IF v_admission IN ('ADMITTED', 'ACCEPTED') AND v_pay IS DISTINCT FROM 'PAID' THEN
        probs := probs || admissions.pg_mig_problem('ADMITTED_WITHOUT_FEE', 'warning', 'Admitted on the old portal with no application fee paid.', 'The Bursary looks into it; the admission comes in as it stood.');
    END IF;
    IF jsonb_array_length(v_sittings) = 0 AND v_state IN ('SUBMITTED', 'UNDER_REVIEW') AND NOT probs @> '[{"level":"error"}]' THEN
        probs := probs || admissions.pg_mig_problem('OLEVEL_NONE', 'warning', 'No O''Level result is given: the eligibility reads "result required" until the Office records it.', NULL);
    END IF;

    v_verdict := CASE WHEN probs @> '[{"level":"duplicate"}]' THEN 'DUPLICATE_IN_FILE'
                      WHEN probs @> '[{"level":"error"}]' THEN 'ERROR'
                      WHEN probs @> '[{"level":"conflict"}]' THEN 'CONFLICT'
                      WHEN probs @> '[{"level":"review"}]' THEN 'REQUIRES_REVIEW'
                      WHEN probs @> '[{"level":"warning"}]' THEN 'WARNING'
                      ELSE 'READY' END;
    v_answers := jsonb_strip_nulls(jsonb_build_object(
        'date_of_birth', v_dob::text, 'mobile', v_phone, 'personal_email', v_email,
        'state_of_origin', left(admissions.pg_mig_t(d, 'stateOfOrigin'), 400), 'lga', left(admissions.pg_mig_t(d, 'lga'), 400),
        'nationality', left(admissions.pg_mig_t(d, 'nationality'), 400), 'home_address', left(admissions.pg_mig_t(d, 'address'), 400),
        'kin_name', left(admissions.pg_mig_t(d, 'nextOfKinName'), 400), 'kin_relationship', left(admissions.pg_mig_t(d, 'nextOfKinRelationship'), 400),
        'kin_mobile', v_kin_phone));
    RETURN jsonb_build_object('verdict', v_verdict, 'match', v_match, 'action', v_action, 'applicationId', v_app, 'problems', probs,
                              'legacy', v_legacy, 'surname', upper(v_surname), 'firstName', initcap(v_first), 'otherNames', initcap(v_others), 'sex', v_sex, 'dob', v_dob,
                              'email', v_email, 'phone', v_phone, 'jamb', v_jamb, 'state', v_state, 'admission', v_admission, 'targetState', v_target_state,
                              'payment', v_pay, 'reference', v_ref, 'gatewayReference', v_gw, 'amount', v_amt, 'paidOn', v_paid_on, 'appliedOn', v_applied,
                              'targetId', v_target, 'specialisationId', v_spec, 'sittings', v_sittings, 'answers', v_answers);
END $fn$;
COMMENT ON FUNCTION admissions.prelim_migration_assess(uuid) IS
  'V737: the check of one preliminary migration row, writing nothing: the verdict (READY, WARNING, DUPLICATE_IN_FILE, ERROR, CONFLICT, REQUIRES_REVIEW — the most serious problem decides), the match (a new applicant, or one on this portal), the action (CREATE, UPDATE, RECONCILE, NONE), every problem {code, level, message, fix}, and the values the import would write.';

-- ── 8 · the import's steps ──────────────────────────────────────────────────────────────────────────────────────────────────
-- the O'Level sittings a row gives, onto the application (active, the route's qualification, the form's subject names)
CREATE OR REPLACE FUNCTION admissions.prelim_mig_olevel(p_app uuid, p_sittings jsonb) RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE s jsonb; g jsonb; v_ord int; n int := 0;
BEGIN
    SELECT coalesce(max(o.ord), 0) INTO v_ord FROM admissions.screening_olevel o WHERE o.application_id = p_app;
    FOR s IN SELECT e FROM jsonb_array_elements(coalesce(p_sittings, '[]'::jsonb)) e LOOP
        FOR g IN SELECT e FROM jsonb_array_elements(s->'subjects') e LOOP
            v_ord := v_ord + 1;
            INSERT INTO admissions.screening_olevel (application_id, ord, exam_body, exam_type, exam_number, exam_year, subject, grade, active, sitting)
            VALUES (p_app, v_ord, s->>'body', s->>'type', s->>'number', (s->>'year')::int, g->>'subject', g->>'grade', true, (s->>'sitting')::smallint);
            n := n + 1;
        END LOOP;
    END LOOP;
    RETURN n;
END $fn$;

-- what the portal lacks is filled in from the row; what it holds is kept (sex, the form's answers, a placeholder contact, the
-- O'Level where none is given here, the target where none is chosen)
CREATE OR REPLACE FUNCTION admissions.prelim_mig_fill(p_app uuid, x jsonb) RETURNS boolean LANGUAGE plpgsql AS $fn$
DECLARE a admissions.application; v_n int; v_changed boolean := false;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    UPDATE admissions.candidate SET sex = x->>'sex' WHERE id = a.candidate_id AND sex IS NULL AND x->>'sex' IS NOT NULL;
    GET DIAGNOSTICS v_n = ROW_COUNT; v_changed := v_changed OR v_n > 0;
    INSERT INTO admissions.screening_answer (application_id, field, value)
    SELECT p_app, e.key, e.value FROM jsonb_each_text(coalesce(x->'answers', '{}'::jsonb)) e
    ON CONFLICT (application_id, field) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT; v_changed := v_changed OR v_n > 0;
    IF v_n > 0 THEN
        UPDATE admissions.application ap
           SET next_of_kin = coalesce(ap.next_of_kin, nullif(btrim(concat_ws(', ', (SELECT value FROM admissions.screening_answer WHERE application_id = p_app AND field = 'kin_name')
                                                  || coalesce(' (' || (SELECT value FROM admissions.screening_answer WHERE application_id = p_app AND field = 'kin_relationship') || ')', ''),
                                              (SELECT value FROM admissions.screening_answer WHERE application_id = p_app AND field = 'kin_mobile'))), ''))
         WHERE ap.id = p_app AND ap.next_of_kin IS NULL;
    END IF;
    -- a placeholder contact gives way to the one the old portal held, when nobody else signs in with it
    UPDATE admissions.applicant_account acc SET email = x->>'email'
     WHERE acc.id = a.account_id AND acc.email ILIKE '%@migrate.moau.local' AND x->>'email' IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM admissions.applicant_account z WHERE lower(z.email) = lower(x->>'email'));
    GET DIAGNOSTICS v_n = ROW_COUNT; v_changed := v_changed OR v_n > 0;
    UPDATE admissions.applicant_account acc SET phone = x->>'phone'
     WHERE acc.id = a.account_id AND acc.phone = '00000000000' AND x->>'phone' IS NOT NULL;
    GET DIAGNOSTICS v_n = ROW_COUNT; v_changed := v_changed OR v_n > 0;
    IF NOT EXISTS (SELECT 1 FROM admissions.screening_olevel o WHERE o.application_id = p_app AND o.active) AND jsonb_array_length(coalesce(x->'sittings', '[]'::jsonb)) > 0 THEN
        v_changed := admissions.prelim_mig_olevel(p_app, x->'sittings') > 0 OR v_changed;
    END IF;
    IF (x->>'targetId') IS NOT NULL THEN
        UPDATE admissions.prelim_review r
           SET target_id = (x->>'targetId')::uuid, target_programme = (SELECT t.programme_code FROM admissions.prelim_target t WHERE t.id = (x->>'targetId')::uuid),
               specialisation_id = (x->>'specialisationId')::uuid, target_set_at = now(), updated_at = now()
         WHERE r.application_id = p_app AND r.target_id IS NULL AND r.published_at IS NULL
           AND EXISTS (SELECT 1 FROM admissions.prelim_target t WHERE t.id = (x->>'targetId')::uuid AND t.route = r.route);
        GET DIAGNOSTICS v_n = ROW_COUNT; v_changed := v_changed OR v_n > 0;
    END IF;
    RETURN v_changed;
END $fn$;

/* the old portal's outcome, as prelim_publish writes it: an admission the ordinary offer (decision OFFERED, basis OTHER), an acceptance
   accepted, a refusal NOT_OFFERED — decided and published here at the migration, noted as the old portal's, with no second review.
   An outcome decided here stands: only the acceptance of an admission goes forward. */
CREATE OR REPLACE FUNCTION admissions.prelim_mig_publish(p_app uuid, p_admission text, p_note text) RETURNS boolean LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_n int;
BEGIN
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    IF r.application_id IS NULL OR coalesce(p_admission, '') NOT IN ('ADMITTED', 'ACCEPTED', 'NOT_ADMITTED') THEN RETURN false; END IF;
    IF r.published_at IS NOT NULL OR r.state IN ('APPROVED', 'ADMITTED', 'NOT_ADMITTED', 'REJECTED', 'WITHDRAWN') THEN
        IF r.state = 'ADMITTED' AND p_admission = 'ACCEPTED' THEN
            UPDATE admissions.candidate c SET offer_state = 'ACCEPTED' FROM admissions.application a
             WHERE a.id = p_app AND c.id = a.candidate_id AND c.offer_state = 'ADMITTED';
            GET DIAGNOSTICS v_n = ROW_COUNT;
            IF v_n > 0 THEN
                UPDATE admissions.application SET accepted_at = coalesce(accepted_at, now()) WHERE id = p_app;
                PERFORM admissions.prelim_log(p_app, 'OLD_PORTAL_ACCEPTED', r.state, r.state, 'The offer was accepted on the old portal', jsonb_build_object('source', 'OLD_PORTAL'));
                RETURN true;
            END IF;
        END IF;
        RETURN false;
    END IF;
    IF p_admission IN ('ADMITTED', 'ACCEPTED') THEN
        UPDATE admissions.application
           SET decision = 'OFFERED', decision_basis = 'OTHER', decision_note = p_note, decided_at = now(), decision_released_at = now(),
               accepted_at = CASE WHEN p_admission = 'ACCEPTED' THEN coalesce(accepted_at, now()) ELSE accepted_at END
         WHERE id = p_app;
        UPDATE admissions.candidate c SET offer_state = CASE WHEN p_admission = 'ACCEPTED' THEN 'ACCEPTED' ELSE 'ADMITTED' END
          FROM admissions.application a WHERE a.id = p_app AND c.id = a.candidate_id AND c.offer_state = 'PROPOSED';
        UPDATE admissions.prelim_review
           SET state = 'ADMITTED', submitted_at = coalesce(submitted_at, now()), decided_at = now(), decided_by = NULL, decided_office = NULL, decision_note = p_note,
               published_at = now(), published_by = v_actor, updated_at = now()
         WHERE application_id = p_app;
        PERFORM admissions.prelim_log(p_app, 'PUBLISHED', r.state, 'ADMITTED', p_note, jsonb_build_object('source', 'OLD_PORTAL', 'admission', p_admission));
    ELSE
        UPDATE admissions.application
           SET decision = 'NOT_OFFERED', decision_basis = NULL, decision_note = p_note, decided_at = now(), decision_released_at = now()
         WHERE id = p_app;
        UPDATE admissions.prelim_review
           SET state = 'NOT_ADMITTED', submitted_at = coalesce(submitted_at, now()), decided_at = now(), decided_by = NULL, decided_office = NULL, decision_note = p_note,
               published_at = now(), published_by = v_actor, updated_at = now()
         WHERE application_id = p_app;
        PERFORM admissions.prelim_log(p_app, 'PUBLISHED', r.state, 'NOT_ADMITTED', p_note, jsonb_build_object('source', 'OLD_PORTAL', 'admission', p_admission));
    END IF;
    RETURN true;
END $fn$;

-- an application moved forward to the state the old portal reached (never back, never decided, never withdrawn by a file)
CREATE OR REPLACE FUNCTION admissions.prelim_mig_advance(p_app uuid, p_state text, p_at timestamptz) RETURNS boolean LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review;
BEGIN
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    IF r.application_id IS NULL OR r.published_at IS NOT NULL OR coalesce(p_state, '') NOT IN ('SUBMITTED', 'UNDER_REVIEW') THEN RETURN false; END IF;
    IF r.state = 'DRAFT' OR (r.state = 'SUBMITTED' AND p_state = 'UNDER_REVIEW') THEN
        UPDATE admissions.prelim_review
           SET state = p_state, submitted_at = coalesce(submitted_at, p_at),
               review_started_at = CASE WHEN p_state = 'UNDER_REVIEW' THEN coalesce(review_started_at, p_at) ELSE review_started_at END, updated_at = now()
         WHERE application_id = p_app;
        PERFORM admissions.prelim_log(p_app, 'OLD_PORTAL_STATE', r.state, p_state, 'Moved forward to where the old portal had it', jsonb_build_object('source', 'OLD_PORTAL'));
        RETURN true;
    END IF;
    RETURN false;
END $fn$;

-- a fee the old portal says was paid, held for the Bursary (once; never where the fee is already paid here or one is held or decided)
CREATE OR REPLACE FUNCTION admissions.prelim_mig_hold(p_app uuid, p_batch uuid, p_row uuid, x jsonb, p_stated text) RETURNS boolean LANGUAGE plpgsql AS $fn$
DECLARE v_state text;
BEGIN
    IF x->>'payment' IS DISTINCT FROM 'PAID' OR (x->>'amount') IS NULL THEN RETURN false; END IF;
    IF (SELECT a.fee_confirmed_at FROM admissions.application a WHERE a.id = p_app) IS NOT NULL THEN RETURN false; END IF;
    -- a fee the Bursary rejected is not held again by the same claim: only a row bringing another, non-blank reference is held anew
    IF EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee f
                WHERE f.application_id = p_app
                  AND (f.state <> 'REJECTED' OR nullif(btrim(x->>'reference'), '') IS NULL
                       OR upper(btrim(f.legacy_reference)) IS NOT DISTINCT FROM upper(btrim(x->>'reference')))) THEN
        RETURN false;
    END IF;
    INSERT INTO admissions.prelim_legacy_fee (application_id, batch_id, row_id, legacy_reference, gateway_reference, amount, paid_on, stated_status, state)
    VALUES (p_app, p_batch, p_row, left(btrim(x->>'reference'), 80), left(btrim(x->>'gatewayReference'), 120), (x->>'amount')::numeric,
            (x->>'paidOn')::date, left(p_stated, 60), 'REQUIRES_REVIEW');
    -- a reference this portal drew and not yet paid is closed: the applicant is not asked to pay while the old payment is checked
    UPDATE admissions.fee_reference SET expires_at = least(expires_at, now())
     WHERE application_id = p_app AND kind = 'APPLICATION' AND confirmed_at IS NULL AND expires_at > now();
    SELECT r.state INTO v_state FROM admissions.prelim_review r WHERE r.application_id = p_app;
    PERFORM admissions.prelim_log(p_app, 'OLD_FEE_HELD', v_state, v_state, 'The application fee paid on the old portal is held for the Bursary to verify',
                                  jsonb_strip_nulls(jsonb_build_object('reference', x->>'reference', 'gatewayReference', x->>'gatewayReference', 'amount', (x->>'amount')::numeric, 'paidOn', x->>'paidOn')));
    RETURN true;
END $fn$;

-- the migrated applicant told once, in the route's MIGRATED notice, on the channels that are really theirs (never a placeholder)
CREATE OR REPLACE FUNCTION admissions.prelim_mig_tell(p_app uuid) RETURNS boolean LANGUAGE plpgsql AS $fn$
DECLARE a admissions.application; acc admissions.applicant_account; l admissions.prelim_legacy_application; v_route text; v_channels text[] := ARRAY['PORTAL'];
        v_held boolean;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO acc FROM admissions.applicant_account WHERE id = a.account_id;
    SELECT * INTO l FROM admissions.prelim_legacy_application WHERE application_id = p_app;
    v_route := admissions.applicant_route(p_app);
    IF a.id IS NULL OR l.application_id IS NULL OR v_route IS NULL THEN RETURN false; END IF;
    IF acc.email !~* '@migrate\.moau\.local$' THEN v_channels := array_append(v_channels, 'EMAIL'); END IF;
    IF acc.phone ~ '^0[0-9]{10}$' AND acc.phone <> '00000000000' THEN v_channels := array_append(v_channels, 'SMS'); END IF;
    IF NOT ('EMAIL' = ANY (v_channels) OR 'SMS' = ANY (v_channels)) THEN RETURN false; END IF;
    v_held := EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee f WHERE f.application_id = p_app AND f.state = 'REQUIRES_REVIEW');
    PERFORM platform.tell_applicant(p_app, v_route, 'MIGRATED',
        jsonb_build_object('APPLICATION_NO', a.application_no, 'LEGACY_NO', l.legacy_application_no,
                           'FEE_NOTE', CASE WHEN v_held THEN 'The application fee you paid on the old portal is being verified by the Bursary; you are not asked to pay it again.' ELSE '' END,
                           -- on a number until a password is chosen (as V709 for PG); an account already here keeps its own password
                           'SIGN_IN', CASE WHEN acc.password_hash = 'SET_ON_FIRST_LOGIN'
                                           THEN 'The first time, your password is your application number; you then choose your own.'
                                           ELSE 'Use the password you chose; if you have forgotten it, choose Forgot password on the sign-in page.' END),
        'prelim-migrated:' || p_app, v_channels);
    RETURN true;
END $fn$;

-- one row imported: created, updated or reconciled — from a fresh check, so nothing changed since is missed
CREATE OR REPLACE FUNCTION admissions.prelim_migration_apply(p_row uuid) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE
    r admissions.prelim_migration_row; b admissions.prelim_migration_batch; p admissions.prelim_programme; d jsonb; x jsonb; fee record;
    v_app uuid; v_cand uuid; v_acc uuid; v_no text; v_email text; v_result text; v_changed boolean := false; v_n int; v_at timestamptz;
    v_state text; v_adm text; v_lg_new boolean := false; v_note text; v_held boolean := false;
    v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    SELECT * INTO r FROM admissions.prelim_migration_row WHERE id = p_row;
    SELECT * INTO b FROM admissions.prelim_migration_batch WHERE id = r.batch_id;
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = b.route;
    d := r.data;
    x := admissions.prelim_migration_assess(p_row);
    IF x->>'verdict' NOT IN ('READY', 'WARNING') THEN
        RETURN jsonb_build_object('result', 'SKIPPED', 'assessment', x,
               'note', replace(lower(x->>'verdict'), '_', ' ') || ': ' || coalesce((SELECT e->>'message' FROM jsonb_array_elements(x->'problems') e WHERE e->>'level' <> 'warning' LIMIT 1), ''));
    END IF;
    IF x->>'action' = 'NONE' THEN
        RETURN jsonb_build_object('result', 'UNCHANGED', 'assessment', x, 'applicationId', x->>'applicationId',
               'note', (SELECT 'application ' || ap.application_no || ' is already here; this upload does not fill in details' FROM admissions.application ap WHERE ap.id = (x->>'applicationId')::uuid));
    END IF;
    v_at := admissions.pg_mig_at((x->>'appliedOn')::date);
    v_state := x->>'state'; v_adm := x->>'admission';
    v_note := format('Decided on the old portal (old application number %s); published here when it was brought across, %s.', x->>'legacy', b.reference);

    IF x->>'action' = 'CREATE' THEN
        v_cand := gen_random_uuid(); v_acc := gen_random_uuid(); v_app := gen_random_uuid();
        INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, sex)
        VALUES (v_cand, b.session, NULL, left(x->>'surname', 60), left(btrim((x->>'firstName') || coalesce(' ' || (x->>'otherNames'), '')), 121), p.name,
                CASE p.programme_type WHEN 'PROFICIENCY_CERTIFICATE' THEN 'PROFICIENCY' ELSE 'PRELIMINARY' END, 0, 'PROPOSED', x->>'sex');
        -- the sign-in: the old email, or a placeholder the applicant never sees (the application number signs in)
        v_email := x->>'email';
        IF v_email IS NULL THEN
            v_email := 'prelim-' || btrim(lower(regexp_replace(x->>'legacy', '[^A-Za-z0-9]+', '-', 'g')), '-') || '@migrate.moau.local';
            IF EXISTS (SELECT 1 FROM admissions.applicant_account z WHERE lower(z.email) = v_email) THEN
                v_email := replace(v_email, '@', '-' || left(md5(v_app::text), 6) || '@');
            END IF;
        END IF;
        -- on a number at the first sign-in (this portal's or the old portal's), then a password of their own, before anything else (as V709)
        INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash, must_change_password)
        VALUES (v_acc, b.session, v_cand, NULL, v_email, x->>'phone', 'SET_ON_FIRST_LOGIN', true);
        -- this portal's own number, from its own series: never the old one
        v_no := 'APP/' || substr(b.session, 3, 2) || '/' || lpad(platform.next_number('APPLICATION', 'UNIVERSITY', b.session)::text, 6, '0');
        INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, created_at) VALUES (v_app, v_acc, v_cand, b.session, v_no, v_at);
        INSERT INTO admissions.prelim_review (application_id, route, state, submitted_at, review_started_at, withdrawn_at,
                                              target_id, target_programme, specialisation_id, target_set_at, created_at)
        VALUES (v_app, b.route, coalesce(v_state, 'DRAFT'),
                CASE WHEN v_state IN ('SUBMITTED', 'UNDER_REVIEW') THEN v_at END, CASE WHEN v_state = 'UNDER_REVIEW' THEN v_at END,
                CASE WHEN v_state = 'WITHDRAWN' THEN v_at END,
                (x->>'targetId')::uuid, (SELECT t.programme_code FROM admissions.prelim_target t WHERE t.id = (x->>'targetId')::uuid),
                (x->>'specialisationId')::uuid, CASE WHEN (x->>'targetId') IS NOT NULL THEN v_at END, v_at);
        INSERT INTO admissions.screening_answer (application_id, field, value)
        SELECT v_app, e.key, e.value FROM jsonb_each_text(coalesce(x->'answers', '{}'::jsonb)) e;
        UPDATE admissions.application ap
           SET next_of_kin = nullif(btrim(concat_ws(', ', (x->'answers'->>'kin_name') || coalesce(' (' || (x->'answers'->>'kin_relationship') || ')', ''),
                                                    x->'answers'->>'kin_mobile')), '')
         WHERE ap.id = v_app;
        PERFORM admissions.prelim_mig_olevel(v_app, x->'sittings');
        -- an application fee stated as nothing is nothing to pay (as prelim_register)
        SELECT * INTO fee FROM admissions.route_fee_rule(b.session, b.route);
        IF fee.stated IS NOT NULL AND coalesce(fee.application_fee, -1) + coalesce(fee.portal_charge, 0) = 0 THEN
            UPDATE admissions.application SET fee_confirmed_at = now() WHERE id = v_app;
        END IF;
        v_result := 'CREATED'; v_changed := true;
    ELSE
        v_app := (x->>'applicationId')::uuid;
        PERFORM 1 FROM admissions.application WHERE id = v_app FOR UPDATE;
        IF x->>'action' = 'UPDATE' OR b.allow_update THEN
            v_changed := admissions.prelim_mig_fill(v_app, x) OR v_changed;
        END IF;
        v_result := CASE x->>'action' WHEN 'RECONCILE' THEN 'RECONCILED' ELSE 'UPDATED' END;
    END IF;

    -- the old number and what the old portal said, beside the application (its empty fields filled once)
    INSERT INTO admissions.prelim_legacy_application (application_id, legacy_application_no, legacy_jamb_reg_no, legacy_exam_number, legacy_programme, legacy_target,
                                                      legacy_status, legacy_admission, applied_on, route_at_import, batch_id, row_id, migrated_by, migrated_office)
    VALUES (v_app, x->>'legacy', left(x->>'jamb', 40), left(admissions.pg_mig_t(d, 'examinationNumber'), 60), left(admissions.pg_mig_t(d, 'programme'), 200),
            left(nullif(concat_ws(' / ', admissions.pg_mig_t(d, 'target'), admissions.pg_mig_t(d, 'specialisation')), ''), 200),
            left(admissions.pg_mig_t(d, 'applicationStatus'), 60), left(admissions.pg_mig_t(d, 'admissionStatus'), 60), (x->>'appliedOn')::date,
            b.route, b.id, r.id, v_actor, v_office)
    ON CONFLICT (application_id) DO UPDATE SET
        legacy_jamb_reg_no = coalesce(admissions.prelim_legacy_application.legacy_jamb_reg_no, EXCLUDED.legacy_jamb_reg_no),
        legacy_exam_number = coalesce(admissions.prelim_legacy_application.legacy_exam_number, EXCLUDED.legacy_exam_number),
        legacy_programme = coalesce(admissions.prelim_legacy_application.legacy_programme, EXCLUDED.legacy_programme),
        legacy_target = coalesce(admissions.prelim_legacy_application.legacy_target, EXCLUDED.legacy_target),
        legacy_status = coalesce(admissions.prelim_legacy_application.legacy_status, EXCLUDED.legacy_status),
        legacy_admission = coalesce(admissions.prelim_legacy_application.legacy_admission, EXCLUDED.legacy_admission),
        applied_on = coalesce(admissions.prelim_legacy_application.applied_on, EXCLUDED.applied_on)
    WHERE b.allow_update
      AND (admissions.prelim_legacy_application.legacy_jamb_reg_no, admissions.prelim_legacy_application.legacy_exam_number, admissions.prelim_legacy_application.legacy_programme,
           admissions.prelim_legacy_application.legacy_target, admissions.prelim_legacy_application.legacy_status, admissions.prelim_legacy_application.legacy_admission,
           admissions.prelim_legacy_application.applied_on)
          IS DISTINCT FROM
          (coalesce(admissions.prelim_legacy_application.legacy_jamb_reg_no, EXCLUDED.legacy_jamb_reg_no), coalesce(admissions.prelim_legacy_application.legacy_exam_number, EXCLUDED.legacy_exam_number),
           coalesce(admissions.prelim_legacy_application.legacy_programme, EXCLUDED.legacy_programme), coalesce(admissions.prelim_legacy_application.legacy_target, EXCLUDED.legacy_target),
           coalesce(admissions.prelim_legacy_application.legacy_status, EXCLUDED.legacy_status), coalesce(admissions.prelim_legacy_application.legacy_admission, EXCLUDED.legacy_admission),
           coalesce(admissions.prelim_legacy_application.applied_on, EXCLUDED.applied_on))
    RETURNING (xmax = 0) INTO v_lg_new;
    IF FOUND THEN v_changed := true; END IF;

    -- the outcome the old portal published, here only where nothing is decided here; else the state it reached, forward only
    IF v_adm IN ('ADMITTED', 'ACCEPTED', 'NOT_ADMITTED') THEN
        v_changed := admissions.prelim_mig_publish(v_app, v_adm,
                         CASE WHEN v_adm = 'NOT_ADMITTED' THEN replace(v_note, 'Decided on the old portal', 'Not admitted on the old portal') ELSE v_note END) OR v_changed;
    ELSIF x->>'action' <> 'CREATE' THEN
        v_changed := admissions.prelim_mig_advance(v_app, v_state, v_at) OR v_changed;
    END IF;

    -- the fee the old portal says was paid: held for the Bursary, never posted here
    v_held := admissions.prelim_mig_hold(v_app, b.id, r.id, x, admissions.pg_mig_t(d, 'paymentStatus'));
    v_changed := v_changed OR v_held;
    IF v_changed THEN PERFORM admissions.prelim_evaluate(v_app); END IF;

    IF x->>'action' = 'CREATE' OR coalesce(v_lg_new, false) THEN
        PERFORM admissions.prelim_log(v_app, 'MIGRATED', NULL, (SELECT z.state FROM admissions.prelim_review z WHERE z.application_id = v_app),
                                      format('From the old portal: %s, batch %s', x->>'legacy', b.reference),
                                      jsonb_strip_nulls(jsonb_build_object('legacy', x->>'legacy', 'batch', b.reference, 'row', r.row_no, 'route', b.route,
                                                                           'action', x->>'action', 'admission', v_adm, 'payment', x->>'payment', 'feeHeld', v_held)));
    ELSIF v_changed THEN
        PERFORM admissions.prelim_log(v_app, 'MIGRATION_UPDATED', (SELECT z.state FROM admissions.prelim_review z WHERE z.application_id = v_app),
                                      (SELECT z.state FROM admissions.prelim_review z WHERE z.application_id = v_app),
                                      format('Details filled in from the old portal: %s, batch %s', x->>'legacy', b.reference), NULL);
    END IF;

    -- told once, if the batch tells
    IF b.notify AND (SELECT l.told_at FROM admissions.prelim_legacy_application l WHERE l.application_id = v_app) IS NULL THEN
        IF admissions.prelim_mig_tell(v_app) THEN
            UPDATE admissions.prelim_legacy_application SET told_at = now() WHERE application_id = v_app;
        END IF;
    END IF;

    IF v_result IN ('UPDATED', 'RECONCILED') AND NOT v_changed THEN v_result := 'UNCHANGED'; END IF;
    RETURN jsonb_build_object('result', v_result, 'assessment', x, 'applicationId', v_app,
                              'note', (SELECT 'application ' || ap.application_no || ', ' || lower(replace(z.state, '_', ' ')) || CASE WHEN v_held THEN ', fee held for the Bursary' ELSE '' END
                                         FROM admissions.application ap JOIN admissions.prelim_review z ON z.application_id = ap.id WHERE ap.id = v_app));
END $fn$;
COMMENT ON FUNCTION admissions.prelim_migration_apply(uuid) IS
  'V737: one preliminary migration row imported from a fresh check: a new applicant (candidate, account, APP number, prelim_review, answers, O''Level, as prelim_register writes them, without its window and its notice), an applicant already here reconciled or filled in (only what is empty; the state forward only), the old number beside it, the old portal''s published outcome (admitted, accepted, not admitted) where nothing is decided here, a fee paid there held for the Bursary, the eligibility read again, the history, and the applicant told once.';

-- ── 9 · the batch: opened, staged, checked, imported, finished ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.prelim_migration_summary(p_batch uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'id', b.id, 'reference', b.reference, 'route', b.route, 'routeName', (SELECT p.name FROM admissions.prelim_programme p WHERE p.route = b.route),
        'session', b.session, 'fileName', b.file_name, 'fileSha256', b.file_sha256, 'state', b.state, 'allowUpdate', b.allow_update, 'notify', b.notify,
        'rowsExpected', b.rows_expected, 'rowsStaged', b.rows_staged, 'startedById', b.started_by,
        'startedBy', (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = b.started_by), 'startedOffice', b.started_office, 'startedAt', b.started_at,
        'checkedAt', b.checked_at, 'importStartedAt', b.import_started_at, 'completedAt', b.completed_at,
        'completedBy', (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = b.completed_by),
        'abandonedAt', b.abandoned_at, 'abandonedBy', (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = b.abandoned_by), 'abandonedReason', b.abandoned_reason)
        || jsonb_build_object(
        'rows', count(r.id), 'staged', b.rows_staged, 'checked', count(r.id) FILTER (WHERE r.checked_at IS NOT NULL),
        'ready', count(r.id) FILTER (WHERE r.verdict = 'READY'), 'warning', count(r.id) FILTER (WHERE r.verdict = 'WARNING'),
        'duplicateInFile', count(r.id) FILTER (WHERE r.verdict = 'DUPLICATE_IN_FILE'), 'conflict', count(r.id) FILTER (WHERE r.verdict = 'CONFLICT'),
        'requiresReview', count(r.id) FILTER (WHERE r.verdict = 'REQUIRES_REVIEW'), 'error', count(r.id) FILTER (WHERE r.verdict = 'ERROR'),
        'verdicts', jsonb_build_object('READY', count(r.id) FILTER (WHERE r.verdict = 'READY'), 'WARNING', count(r.id) FILTER (WHERE r.verdict = 'WARNING'),
                                       'DUPLICATE_IN_FILE', count(r.id) FILTER (WHERE r.verdict = 'DUPLICATE_IN_FILE'), 'CONFLICT', count(r.id) FILTER (WHERE r.verdict = 'CONFLICT'),
                                       'REQUIRES_REVIEW', count(r.id) FILTER (WHERE r.verdict = 'REQUIRES_REVIEW'), 'ERROR', count(r.id) FILTER (WHERE r.verdict = 'ERROR')),
        'newApplicants', count(r.id) FILTER (WHERE r.action = 'CREATE' AND r.verdict IN ('READY', 'WARNING')),
        'existing', count(r.id) FILTER (WHERE r.match = 'EXISTING_APPLICANT'),
        'toUpdate', count(r.id) FILTER (WHERE r.action IN ('UPDATE', 'RECONCILE') AND r.verdict IN ('READY', 'WARNING')),
        'skipped', count(r.id) FILTER (WHERE r.verdict IS NOT NULL AND r.verdict NOT IN ('READY', 'WARNING')),
        'invalid', count(r.id) FILTER (WHERE r.verdict = 'ERROR'),
        -- a possible same applicant the officer confirmed as new reads "warning" (prelim_migration_row_new): no longer a duplicate
        'duplicates', count(r.id) FILTER (WHERE r.verdict = 'DUPLICATE_IN_FILE' OR r.problems @> '[{"code":"POSSIBLE_SAME_APPLICANT","level":"review"}]'),
        -- the fees the import holds for the Bursary (prelim_mig_hold's own test): a row imported, its fee not already paid here, and its
        -- application holding no fee of another batch that is held or verified, nor one the Bursary rejected for the same claim
        'paymentsToVerify', count(r.id) FILTER (WHERE admissions.prelim_mig_status('PAYMENT', r.data ->> 'paymentStatus') = 'PAID'
                                                   AND r.verdict IN ('READY', 'WARNING') AND r.action <> 'NONE'
                                                   AND NOT r.problems @> '[{"code":"FEE_ALREADY_PAID_HERE"}]'
                                                   AND NOT EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee f
                                                                    WHERE f.application_id = r.application_id AND f.batch_id <> r.batch_id
                                                                      AND (f.state <> 'REJECTED' OR r.fee_ref IS NULL
                                                                           OR upper(btrim(f.legacy_reference)) IS NOT DISTINCT FROM r.fee_ref))),
        'programmeConflicts', count(r.id) FILTER (WHERE r.problems @> '[{"code":"PROGRAMME_MISMATCH"}]' OR r.problems @> '[{"code":"PROGRAMME_CONFLICT"}]'),
        'readyToImport', count(r.id) FILTER (WHERE r.verdict IN ('READY', 'WARNING') AND r.result IS NULL))
        || jsonb_build_object(
        'imported', count(r.id) FILTER (WHERE r.result IS NOT NULL),
        'created', count(r.id) FILTER (WHERE r.result = 'CREATED'), 'updated', count(r.id) FILTER (WHERE r.result = 'UPDATED'),
        'reconciled', count(r.id) FILTER (WHERE r.result = 'RECONCILED'), 'unchanged', count(r.id) FILTER (WHERE r.result = 'UNCHANGED'),
        'importSkipped', count(r.id) FILTER (WHERE r.result = 'SKIPPED'), 'failed', count(r.id) FILTER (WHERE r.result = 'FAILED'),
        'results', jsonb_build_object('CREATED', count(r.id) FILTER (WHERE r.result = 'CREATED'), 'UPDATED', count(r.id) FILTER (WHERE r.result = 'UPDATED'),
                                      'RECONCILED', count(r.id) FILTER (WHERE r.result = 'RECONCILED'), 'UNCHANGED', count(r.id) FILTER (WHERE r.result = 'UNCHANGED'),
                                      'SKIPPED', count(r.id) FILTER (WHERE r.result = 'SKIPPED'), 'FAILED', count(r.id) FILTER (WHERE r.result = 'FAILED')),
        'feesHeld', (SELECT count(*) FROM admissions.prelim_legacy_fee x WHERE x.batch_id = b.id AND x.state = 'REQUIRES_REVIEW'),
        'feesVerified', (SELECT count(*) FROM admissions.prelim_legacy_fee x WHERE x.batch_id = b.id AND x.state = 'VERIFIED'),
        'feesRejected', (SELECT count(*) FROM admissions.prelim_legacy_fee x WHERE x.batch_id = b.id AND x.state = 'REJECTED'))
      FROM admissions.prelim_migration_batch b LEFT JOIN admissions.prelim_migration_row r ON r.batch_id = b.id
     WHERE b.id = p_batch
     GROUP BY b.id
$$;

CREATE OR REPLACE FUNCTION admissions.prelim_migration_open(p_route text, p_file text, p_sha text, p_rows int, p_update boolean, p_notify boolean)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_route text := upper(btrim(coalesce(p_route, ''))); v_file text; v_year text; v_id uuid; v_seen text; v_session text;
BEGIN
    PERFORM admissions.prelim_mig_writer();
    IF v_route NOT IN ('PRELIMINARY_TECHNOLOGY', 'PRELIMINARY_SCIENCE') OR NOT EXISTS (SELECT 1 FROM admissions.prelim_programme p WHERE p.route = v_route) THEN
        RAISE EXCEPTION 'PRELIMMIG_ROUTE: an upload is of Preliminary Technology & Industrial Studies applicants or of Preliminary Science applicants' USING ERRCODE = '23514';
    END IF;
    v_file := btrim(regexp_replace(coalesce(p_file, ''), '^.*[\\/]', ''));
    IF v_file !~* '\.xlsx$' OR length(v_file) > 255 THEN
        RAISE EXCEPTION 'PRELIMMIG_FILE_TYPE: a migration file is an Excel workbook (.xlsx) made from the template' USING ERRCODE = '23514';
    END IF;
    IF lower(coalesce(p_sha, '')) !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'PRELIMMIG_CHECKSUM: the file''s checksum did not arrive intact' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR p_rows < 1 OR p_rows > 20000 THEN
        RAISE EXCEPTION 'PRELIMMIG_ROWS: a migration file holds 1 to 20,000 rows (this one %); split a larger one', coalesce(p_rows, 0) USING ERRCODE = '23514';
    END IF;
    v_session := policy.route_session(v_route);
    IF v_session IS NULL THEN
        RAISE EXCEPTION 'PRELIMMIG_SESSION: no session is set for %; the Academic Office sets it first', (SELECT p.name FROM admissions.prelim_programme p WHERE p.route = v_route) USING ERRCODE = '23514';
    END IF;
    v_year := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY');
    INSERT INTO admissions.prelim_migration_batch (reference, route, session, file_name, file_sha256, rows_expected, allow_update, notify, started_by, started_office)
    VALUES ('PRELIM-MIG/' || v_year || '/' || lpad(platform.next_number('PRELIM_MIGRATION', 'UNIVERSITY', v_year)::text, 6, '0'),
            v_route, v_session, v_file, lower(p_sha), p_rows, coalesce(p_update, false), coalesce(p_notify, true),
            nullif(current_setting('moaum.actor_id', true), '')::uuid, current_setting('moaum.actor_office', true))
    RETURNING id INTO v_id;
    -- the same file of the same programme imported before: importing it again changes nothing already on record, and says so
    SELECT string_agg(x.reference, ', ' ORDER BY x.started_at) INTO v_seen FROM admissions.prelim_migration_batch x
     WHERE x.file_sha256 = lower(p_sha) AND x.route = v_route AND x.id <> v_id AND x.state = 'COMPLETED';
    RETURN admissions.prelim_migration_summary(v_id) || jsonb_build_object('importedBefore', v_seen);
END $fn$;

CREATE OR REPLACE FUNCTION admissions.prelim_migration_stage(p_batch uuid, p_first int, p_rows jsonb) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE b admissions.prelim_migration_batch; v_keys text[]; i int; n int; o jsonb; c jsonb; v_s int;
BEGIN
    PERFORM admissions.prelim_mig_writer();
    SELECT * INTO b FROM admissions.prelim_migration_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such migration batch' USING ERRCODE = '23503'; END IF;
    -- every row of a file is the opener's: the uploader of every fee it holds is the officer who never verifies one
    IF b.started_by IS DISTINCT FROM nullif(current_setting('moaum.actor_id', true), '')::uuid THEN
        RAISE EXCEPTION 'PRELIMMIG_NOT_YOURS: the rows of % are sent by the officer who opened it', b.reference USING ERRCODE = '23514';
    END IF;
    IF b.state <> 'STAGING' THEN
        RAISE EXCEPTION 'PRELIMMIG_STAGED: the file of % is already in; upload a corrected file as a new batch', b.reference USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 1000 THEN
        RAISE EXCEPTION 'PRELIMMIG_CHUNK: rows arrive 1 to 1,000 at a time' USING ERRCODE = '23514';
    END IF;
    n := jsonb_array_length(p_rows);
    IF p_first IS NULL OR p_first < 1 OR p_first + n - 1 > b.rows_expected THEN
        RAISE EXCEPTION 'PRELIMMIG_ROWS_BEYOND: rows % to % are beyond the % the file was opened with', p_first, p_first + n - 1, b.rows_expected USING ERRCODE = '23514';
    END IF;
    v_keys := ARRAY(SELECT c2.key FROM admissions.prelim_migration_columns(b.route) c2) || ARRAY['fullName', 'sheetRow'];
    FOR i IN 0 .. n - 1 LOOP
        o := p_rows -> i;
        IF jsonb_typeof(o) <> 'object' THEN
            RAISE EXCEPTION 'PRELIMMIG_ROW_SHAPE: row % is not a row of the template', p_first + i USING ERRCODE = '23514';
        END IF;
        -- only the template's columns, as text, without control characters, at most 1,000 characters each
        SELECT coalesce(jsonb_object_agg(e.k, left(btrim(regexp_replace(e.v, '[[:cntrl:]]+', ' ', 'g')), 1000)), '{}') INTO c
          FROM jsonb_each_text(o) e(k, v) WHERE e.k = ANY (v_keys) AND btrim(regexp_replace(coalesce(e.v, ''), '[[:cntrl:]]+', ' ', 'g')) <> '';
        INSERT INTO admissions.prelim_migration_row (batch_id, row_no, data, legacy_no, applicant, email, fee_ref, olevel_keys)
        VALUES (b.id, p_first + i, c, upper(admissions.pg_mig_t(c, 'legacyApplicationNo')),
                left(nullif(concat_ws(', ', upper(admissions.pg_mig_t(c, 'surname')),
                                      nullif(concat_ws(' ', admissions.pg_mig_t(c, 'firstName'), admissions.pg_mig_t(c, 'otherNames')), '')), ''), 200),
                admissions.first_email(admissions.pg_mig_t(c, 'email')),
                upper(btrim(admissions.pg_mig_t(c, 'paymentReference'))),
                ARRAY(SELECT k FROM (SELECT admissions.prelim_mig_olevel_key(admissions.pg_mig_t(c, 'olevel' || s || 'Body'), admissions.pg_mig_t(c, 'olevel' || s || 'Year'),
                                                                               admissions.pg_mig_t(c, 'olevel' || s || 'Number')) AS k
                                       FROM generate_series(1, 2) s) z WHERE k IS NOT NULL))
        ON CONFLICT (batch_id, row_no) DO UPDATE
           SET data = EXCLUDED.data, legacy_no = EXCLUDED.legacy_no, applicant = EXCLUDED.applicant, email = EXCLUDED.email, fee_ref = EXCLUDED.fee_ref,
               olevel_keys = EXCLUDED.olevel_keys;
    END LOOP;
    UPDATE admissions.prelim_migration_batch SET rows_staged = (SELECT count(*) FROM admissions.prelim_migration_row r WHERE r.batch_id = b.id) WHERE id = b.id
    RETURNING rows_staged INTO v_s;
    RETURN jsonb_build_object('staged', v_s, 'expected', b.rows_expected);
END $fn$;

-- the dry run: every check, nothing written but the rows' own verdicts
CREATE OR REPLACE FUNCTION admissions.prelim_migration_check(p_batch uuid, p_from int, p_to int) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE b admissions.prelim_migration_batch; r record; x jsonb; v_from int; v_to int;
BEGIN
    PERFORM admissions.prelim_mig_writer();
    SELECT * INTO b FROM admissions.prelim_migration_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such migration batch' USING ERRCODE = '23503'; END IF;
    IF b.state NOT IN ('STAGING', 'CHECKED') THEN
        RAISE EXCEPTION 'PRELIMMIG_CHECK_CLOSED: % is %; once the import begins each row is checked again as it is imported', b.reference, lower(b.state) USING ERRCODE = '23514';
    END IF;
    IF b.rows_staged < b.rows_expected THEN
        RAISE EXCEPTION 'PRELIMMIG_NOT_ALL_STAGED: % of % rows have arrived; send the rest before the check', b.rows_staged, b.rows_expected USING ERRCODE = '23514';
    END IF;
    v_from := greatest(coalesce(p_from, 1), 1); v_to := coalesce(p_to, b.rows_expected);
    IF v_to - v_from + 1 > 2000 THEN RAISE EXCEPTION 'PRELIMMIG_CHUNK: rows are checked up to 2,000 at a time' USING ERRCODE = '23514'; END IF;
    -- a file just in: the planner learns the rows' numbers once, so each lookup of an earlier row stays on its index
    IF b.state = 'STAGING' AND v_from = 1 THEN ANALYZE admissions.prelim_migration_row; END IF;
    FOR r IN SELECT x2.id FROM admissions.prelim_migration_row x2 WHERE x2.batch_id = b.id AND x2.row_no BETWEEN v_from AND v_to ORDER BY x2.row_no LOOP
        x := admissions.prelim_migration_assess(r.id);
        UPDATE admissions.prelim_migration_row
           SET checked_at = now(), verdict = x->>'verdict', match = x->>'match', action = x->>'action',
               application_id = (x->>'applicationId')::uuid, problems = x->'problems'
         WHERE id = r.id;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM admissions.prelim_migration_row x2 WHERE x2.batch_id = b.id AND x2.checked_at IS NULL) THEN
        UPDATE admissions.prelim_migration_batch SET state = 'CHECKED', checked_at = now() WHERE id = b.id;
    END IF;
    RETURN admissions.prelim_migration_summary(b.id);
END $fn$;

CREATE OR REPLACE FUNCTION admissions.prelim_migration_import(p_batch uuid, p_from int, p_to int) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE b admissions.prelim_migration_batch; r record; res jsonb; n int := 0; v_from int; v_to int;
BEGIN
    PERFORM admissions.prelim_mig_writer();
    SELECT * INTO b FROM admissions.prelim_migration_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such migration batch' USING ERRCODE = '23503'; END IF;
    IF b.state IN ('COMPLETED', 'ABANDONED') THEN
        RAISE EXCEPTION 'PRELIMMIG_CLOSED: % is %', b.reference, lower(b.state) USING ERRCODE = '23514';
    END IF;
    IF b.state = 'STAGING' OR EXISTS (SELECT 1 FROM admissions.prelim_migration_row x WHERE x.batch_id = b.id AND x.checked_at IS NULL) THEN
        RAISE EXCEPTION 'PRELIMMIG_NOT_CHECKED: check the whole file (the dry run) before it is imported' USING ERRCODE = '23514';
    END IF;
    v_from := greatest(coalesce(p_from, 1), 1); v_to := coalesce(p_to, b.rows_expected);
    IF v_to - v_from + 1 > 1000 THEN RAISE EXCEPTION 'PRELIMMIG_CHUNK: rows are imported up to 1,000 at a time' USING ERRCODE = '23514'; END IF;
    UPDATE admissions.prelim_migration_batch SET state = 'IMPORTING', import_started_at = coalesce(import_started_at, now()) WHERE id = b.id;
    PERFORM set_config('moaum.prelim_migration', b.reference, true);
    FOR r IN SELECT x.id FROM admissions.prelim_migration_row x
              WHERE x.batch_id = b.id AND x.row_no BETWEEN v_from AND v_to AND x.result IS NULL ORDER BY x.row_no LOOP
        BEGIN
            res := admissions.prelim_migration_apply(r.id);
            UPDATE admissions.prelim_migration_row
               SET imported_at = now(), result = res->>'result', result_note = left(res->>'note', 500),
                   checked_at = now(), verdict = res->'assessment'->>'verdict', match = res->'assessment'->>'match', action = res->'assessment'->>'action',
                   application_id = coalesce((res->>'applicationId')::uuid, (res->'assessment'->>'applicationId')::uuid), problems = res->'assessment'->'problems'
             WHERE id = r.id;
        EXCEPTION WHEN OTHERS THEN
            -- the row's writes are undone; the rest go on, and the row says why
            UPDATE admissions.prelim_migration_row SET imported_at = now(), result = 'FAILED', result_note = left(SQLERRM, 500) WHERE id = r.id;
        END;
        n := n + 1;
    END LOOP;
    PERFORM set_config('moaum.prelim_migration', '', true);
    RETURN admissions.prelim_migration_summary(b.id) || jsonb_build_object('processed', n);
END $fn$;

CREATE OR REPLACE FUNCTION admissions.prelim_migration_finish(p_batch uuid) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE b admissions.prelim_migration_batch; n int;
BEGIN
    PERFORM admissions.prelim_mig_writer();
    SELECT * INTO b FROM admissions.prelim_migration_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such migration batch' USING ERRCODE = '23503'; END IF;
    IF b.state NOT IN ('IMPORTING', 'CHECKED') THEN
        RAISE EXCEPTION 'PRELIMMIG_CLOSED: % is %', b.reference, lower(b.state) USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO n FROM admissions.prelim_migration_row x WHERE x.batch_id = b.id AND x.result IS NULL;
    IF n > 0 THEN RAISE EXCEPTION 'PRELIMMIG_NOT_ALL_IMPORTED: % rows wait to be imported', n USING ERRCODE = '23514'; END IF;
    UPDATE admissions.prelim_migration_batch SET state = 'COMPLETED', completed_at = now(), completed_by = nullif(current_setting('moaum.actor_id', true), '')::uuid WHERE id = b.id;
    RETURN admissions.prelim_migration_summary(b.id);
END $fn$;

CREATE OR REPLACE FUNCTION admissions.prelim_migration_abandon(p_batch uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE b admissions.prelim_migration_batch;
BEGIN
    PERFORM admissions.prelim_mig_writer();
    SELECT * INTO b FROM admissions.prelim_migration_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such migration batch' USING ERRCODE = '23503'; END IF;
    IF b.state IN ('COMPLETED', 'ABANDONED') THEN RAISE EXCEPTION 'PRELIMMIG_CLOSED: % is %', b.reference, lower(b.state) USING ERRCODE = '23514'; END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'PRELIMMIG_REASON: say why the upload is set aside' USING ERRCODE = '23514'; END IF;
    -- set aside, never deleted: what was imported stays imported, the rest is never imported from this batch
    UPDATE admissions.prelim_migration_batch
       SET state = 'ABANDONED', abandoned_at = now(), abandoned_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, abandoned_reason = btrim(p_reason)
     WHERE id = b.id;
    RETURN admissions.prelim_migration_summary(b.id);
END $fn$;

-- the officer's word on a possible same applicant: a new applicant all the same, with its reason
CREATE OR REPLACE FUNCTION admissions.prelim_migration_row_new(p_row uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_migration_row; b admissions.prelim_migration_batch; x jsonb;
BEGIN
    PERFORM admissions.prelim_mig_writer();
    SELECT * INTO r FROM admissions.prelim_migration_row WHERE id = p_row FOR UPDATE;
    IF r.id IS NULL THEN RAISE EXCEPTION 'no such migration row' USING ERRCODE = '23503'; END IF;
    SELECT * INTO b FROM admissions.prelim_migration_batch WHERE id = r.batch_id;
    IF b.state NOT IN ('CHECKED', 'IMPORTING') OR r.result IS NOT NULL THEN
        RAISE EXCEPTION 'PRELIMMIG_CLOSED: row % of % is no longer open', r.row_no, b.reference USING ERRCODE = '23514';
    END IF;
    IF NOT r.problems @> '[{"code":"POSSIBLE_SAME_APPLICANT"}]' THEN
        RAISE EXCEPTION 'PRELIMMIG_NOTHING_TO_DECIDE: row % is not held as a possible same applicant', r.row_no USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'PRELIMMIG_REASON: say how you know this is another person (at least ten characters)' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.prelim_migration_row SET decided_new = true, decided_new_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, decided_new_reason = btrim(p_reason)
     WHERE id = r.id;
    x := admissions.prelim_migration_assess(r.id);
    UPDATE admissions.prelim_migration_row
       SET checked_at = now(), verdict = x->>'verdict', match = x->>'match', action = x->>'action', application_id = (x->>'applicationId')::uuid, problems = x->'problems'
     WHERE id = r.id;
    RETURN x;
END $fn$;

-- the batches of a route (both routes when NULL), newest first, a page at a time, with what each did
CREATE OR REPLACE FUNCTION admissions.prelim_migration_batches(p_route text, p_limit int, p_offset int) RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH b AS (
        SELECT b.*, count(*) OVER () AS total
          FROM admissions.prelim_migration_batch b
         WHERE p_route IS NULL OR b.route = upper(btrim(p_route))
         ORDER BY b.started_at DESC, b.reference DESC
         LIMIT least(greatest(coalesce(p_limit, 50), 1), 500) OFFSET greatest(coalesce(p_offset, 0), 0))
    SELECT jsonb_build_object('total', coalesce((SELECT max(total) FROM b), 0),
        'rows', coalesce(jsonb_agg(jsonb_build_object(
            'id', b.id, 'reference', b.reference, 'route', b.route, 'routeName', (SELECT p.name FROM admissions.prelim_programme p WHERE p.route = b.route),
            'session', b.session, 'fileName', b.file_name, 'fileSha256', b.file_sha256, 'state', b.state, 'allowUpdate', b.allow_update, 'notify', b.notify,
            'startedAt', b.started_at, 'startedById', b.started_by, 'startedBy', (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = b.started_by),
            'startedOffice', b.started_office, 'completedAt', b.completed_at, 'abandonedAt', b.abandoned_at, 'abandonedReason', b.abandoned_reason,
            'rows', b.rows_expected, 'created', c.created, 'updated', c.updated, 'reconciled', c.reconciled, 'unchanged', c.unchanged, 'skipped', c.skipped,
            'failed', c.failed, 'successful', c.created + c.updated + c.reconciled + c.unchanged,
            'feesHeld', (SELECT count(*) FROM admissions.prelim_legacy_fee x WHERE x.batch_id = b.id AND x.state = 'REQUIRES_REVIEW'))
            ORDER BY b.started_at DESC, b.reference DESC), '[]'::jsonb))
      FROM b CROSS JOIN LATERAL (
          SELECT count(*) FILTER (WHERE r.result = 'CREATED') AS created, count(*) FILTER (WHERE r.result = 'UPDATED') AS updated,
                 count(*) FILTER (WHERE r.result = 'RECONCILED') AS reconciled, count(*) FILTER (WHERE r.result = 'UNCHANGED') AS unchanged,
                 count(*) FILTER (WHERE r.result = 'SKIPPED') AS skipped, count(*) FILTER (WHERE r.result = 'FAILED') AS failed
            FROM admissions.prelim_migration_row r WHERE r.batch_id = b.id) c
$$;

/* a preliminary applicant of either route, by the APP number, the old number, the email, the phone or the name: both numbers find them;
   p_routes, the routes the office reads (NULL: both), applied before the page is cut, so a programme office never loses its own */
DROP FUNCTION IF EXISTS admissions.prelim_legacy_find(text);
CREATE OR REPLACE FUNCTION admissions.prelim_legacy_find(p_q text, p_routes text[] DEFAULT NULL)
RETURNS TABLE (application_id uuid, application_no text, legacy_application_no text, name text, email text, phone text, route text, route_name text,
               state text, fee_status text, session text, migrated boolean)
LANGUAGE sql STABLE AS $$
    WITH q AS (SELECT btrim(coalesce(p_q, '')) AS t, upper(btrim(coalesce(p_q, ''))) AS u, admissions.cce_phone(p_q) AS ph,
                      '%' || replace(replace(replace(btrim(coalesce(p_q, '')), '\', '\\'), '%', '\%'), '_', '\_') || '%' AS pat)
    SELECT a.id, a.application_no, l.legacy_application_no, c.surname || ', ' || c.other_names,
           CASE WHEN acc.email ILIKE '%@migrate.moau.local' THEN NULL ELSE acc.email END, acc.phone, r.route, pp.name, r.state,
           admissions.prelim_fee_status(a.id), a.session, l.application_id IS NOT NULL
      FROM q, admissions.prelim_review r
      JOIN admissions.application a ON a.id = r.application_id
      JOIN admissions.candidate c ON c.id = a.candidate_id
      JOIN admissions.applicant_account acc ON acc.id = a.account_id
      JOIN admissions.prelim_programme pp ON pp.route = r.route
      LEFT JOIN admissions.prelim_legacy_application l ON l.application_id = a.id
     WHERE length(q.t) >= 3 AND r.route IN ('PRELIMINARY_SCIENCE', 'PRELIMINARY_TECHNOLOGY')
       AND (p_routes IS NULL OR r.route = ANY (p_routes))
       AND (a.application_no = q.u OR upper(btrim(l.legacy_application_no)) = q.u OR lower(acc.email) = lower(q.t) OR acc.phone = q.ph
            OR (c.surname || ' ' || c.other_names) ILIKE q.pat OR (c.other_names || ' ' || c.surname) ILIKE q.pat)
     ORDER BY coalesce(a.application_no = q.u OR upper(btrim(l.legacy_application_no)) = q.u, false) DESC, c.surname, c.other_names   -- no old number is not NULL first
     LIMIT 50
$$;

-- ── 10 · the fee held, and verified or rejected by the Bursary ───────────────────────────────────────────────────────────────
-- while a fee paid on the old portal waits for the Bursary, no new application-fee reference is drawn: the applicant is not asked to
-- pay again (the Bursary's own posting of the verified fee passes)
CREATE OR REPLACE FUNCTION admissions.prelim_legacy_fee_hold() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF coalesce(current_setting('moaum.prelim_fee_posting', true), '') = 'on' THEN RETURN NEW; END IF;
    IF EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee f WHERE f.application_id = NEW.application_id AND f.state = 'REQUIRES_REVIEW') THEN
        RAISE EXCEPTION 'PRELIM_FEE_UNDER_REVIEW: your application fee paid on the old portal is being verified by the Bursary; you are not asked to pay again'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_prelim_legacy_fee_hold BEFORE INSERT ON admissions.fee_reference
    FOR EACH ROW WHEN (NEW.kind = 'APPLICATION') EXECUTE FUNCTION admissions.prelim_legacy_fee_hold();

CREATE OR REPLACE FUNCTION admissions.prelim_legacy_fee_decide(p_fee uuid, p_verify boolean, p_note text, p_reference text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := coalesce(current_setting('moaum.actor_office', true), '');
        f admissions.prelim_legacy_fee; b admissions.prelim_migration_batch; a admissions.application; acc admissions.applicant_account; v_route text; v_name text;
        v_ref text; v_ts timestamptz; v_receipt text; v_fr uuid; v_state text; v_channels text[] := ARRAY['PORTAL'];
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PRELIMMIG_ACTOR: a fee is verified by a person' USING ERRCODE = '23514'; END IF;
    IF v_office NOT IN ('bursar', 'super') THEN
        RAISE EXCEPTION 'PRELIMMIG_FEE_OFFICE: the Bursary verifies an application fee paid on the old portal, not %', coalesce(nullif(v_office, ''), 'this office') USING ERRCODE = '42501';
    END IF;
    SELECT * INTO f FROM admissions.prelim_legacy_fee WHERE id = p_fee FOR UPDATE;
    IF f.id IS NULL THEN RAISE EXCEPTION 'no such old-portal fee' USING ERRCODE = '23503'; END IF;
    IF f.state <> 'REQUIRES_REVIEW' THEN
        RAISE EXCEPTION 'PRELIMMIG_FEE_DECIDED: this fee is already %', lower(f.state) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO b FROM admissions.prelim_migration_batch WHERE id = f.batch_id;
    IF b.started_by = v_actor THEN
        RAISE EXCEPTION 'PRELIMMIG_SAME_OFFICER: the officer who uploaded the fee (%) does not verify it; another Bursary officer does', b.reference USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_note, ''))) < 5 THEN
        RAISE EXCEPTION 'PRELIMMIG_FEE_NOTE: say what was checked (the bank statement, the gateway''s record) or why it is not verified' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO a FROM admissions.application WHERE id = f.application_id FOR UPDATE;
    SELECT * INTO acc FROM admissions.applicant_account WHERE id = a.account_id;
    v_route := admissions.applicant_route(a.id);
    v_name := (SELECT pp.name FROM admissions.prelim_programme pp WHERE pp.route = v_route);
    IF acc.email !~* '@migrate\.moau\.local$' THEN v_channels := array_append(v_channels, 'EMAIL'); END IF;
    IF acc.phone ~ '^0[0-9]{10}$' AND acc.phone <> '00000000000' THEN v_channels := array_append(v_channels, 'SMS'); END IF;
    v_state := (SELECT r.state FROM admissions.prelim_review r WHERE r.application_id = a.id);

    IF NOT coalesce(p_verify, false) THEN
        UPDATE admissions.prelim_legacy_fee SET state = 'REJECTED', decided_by = v_actor, decided_office = v_office, decided_at = now(), decision_note = btrim(p_note) WHERE id = f.id;
        PERFORM admissions.prelim_log(a.id, 'OLD_FEE_REJECTED', v_state, v_state, btrim(p_note),
                                      jsonb_strip_nulls(jsonb_build_object('reference', f.legacy_reference, 'amount', f.amount,
                                                                           'alreadyPaidHere', CASE WHEN a.fee_confirmed_at IS NOT NULL THEN true END)));
        -- told to pay only while the fee is unpaid here; an application already paid here is told nothing (the old payment is not counted)
        IF a.fee_confirmed_at IS NULL THEN
            PERFORM platform.tell_applicant(a.id, v_route, 'OLD_FEE_NOT_VERIFIED',
                jsonb_build_object('APPLICATION_NO', a.application_no, 'REFERENCE', coalesce(f.legacy_reference, 'not given'), 'NOTE', btrim(p_note)),
                'prelim-old-fee-rejected:' || f.id, v_channels);
        END IF;
    ELSE
        v_ref := upper(btrim(coalesce(f.legacy_reference, nullif(btrim(coalesce(p_reference, '')), ''))));
        IF v_ref IS NULL THEN
            RAISE EXCEPTION 'PRELIMMIG_FEE_REFERENCE: this fee came with no reference; give the reference found on the evidence checked' USING ERRCODE = '23514';
        END IF;
        IF f.legacy_reference IS NOT NULL AND nullif(btrim(coalesce(p_reference, '')), '') IS NOT NULL AND upper(btrim(p_reference)) <> v_ref THEN
            RAISE EXCEPTION 'PRELIMMIG_FEE_REFERENCE: the fee carries its old reference %; it is verified under that reference', f.legacy_reference USING ERRCODE = '23514';
        END IF;
        IF length(v_ref) > 80 OR v_ref ~ '[[:cntrl:]]' THEN
            RAISE EXCEPTION 'PRELIMMIG_FEE_REFERENCE: % is not a payment reference', left(v_ref, 40) USING ERRCODE = '23514';
        END IF;
        IF EXISTS (SELECT 1 FROM admissions.fee_reference fr WHERE fr.reference IN (v_ref, btrim(coalesce(f.legacy_reference, p_reference))))
           OR EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee x WHERE x.id <> f.id AND x.state <> 'REJECTED' AND upper(btrim(x.legacy_reference)) = v_ref)
           OR EXISTS (SELECT 1 FROM admissions.pg_legacy_fee x WHERE x.state <> 'REJECTED' AND upper(btrim(x.legacy_reference)) = v_ref) THEN
            RAISE EXCEPTION 'PRELIMMIG_FEE_REFERENCE_TAKEN: reference % is already another payment''s on this portal; a payment is recorded once', v_ref USING ERRCODE = '23514';
        END IF;
        IF a.fee_confirmed_at IS NOT NULL THEN
            RAISE EXCEPTION 'PRELIMMIG_FEE_ALREADY_PAID: application % is already paid on this portal; reject the old payment instead, with a note', a.application_no USING ERRCODE = '23514';
        END IF;
        v_ts := admissions.pg_mig_at(f.paid_on);
        v_receipt := 'RCT-' || left(a.session, 4) || '-' || lpad(platform.next_number('RECEIPT', 'UNIVERSITY', a.session)::text, 5, '0');
        -- the old reference posted as a confirmed fee, as the gateway's confirmation does it (never "Old-portal migration": V175's reset deletes those)
        PERFORM set_config('moaum.prelim_fee_posting', 'on', true);
        INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, generated_at, expires_at, confirmed_at, confirmed_by, channel, note, receipt_no)
        VALUES (gen_random_uuid(), a.id, 'APPLICATION', v_ref, f.amount, v_ts, v_ts, v_ts, v_actor, 'Old portal',
                'Paid on the old portal; verified by the Bursary: ' || btrim(p_note), v_receipt)
        RETURNING id INTO v_fr;
        PERFORM set_config('moaum.prelim_fee_posting', '', true);
        UPDATE admissions.application SET fee_confirmed_at = coalesce(fee_confirmed_at, v_ts) WHERE id = a.id;
        UPDATE admissions.fee_reference SET expires_at = least(expires_at, now())
         WHERE application_id = a.id AND kind = 'APPLICATION' AND confirmed_at IS NULL AND expires_at > now();
        UPDATE admissions.prelim_legacy_fee
           SET state = 'VERIFIED', fee_reference_id = v_fr, legacy_reference = coalesce(legacy_reference, v_ref),
               decided_by = v_actor, decided_office = v_office, decided_at = now(), decision_note = btrim(p_note)
         WHERE id = f.id;
        PERFORM admissions.prelim_log(a.id, 'OLD_FEE_VERIFIED', v_state, v_state, btrim(p_note),
                                      jsonb_build_object('reference', v_ref, 'amount', f.amount, 'receipt', v_receipt));
        PERFORM platform.tell_applicant(a.id, v_route, 'PAYMENT_SUCCESSFUL',
            jsonb_build_object('RECEIPT_NUMBER', v_receipt, 'REFERENCE', v_ref, 'PURPOSE', coalesce(v_name, 'Preliminary') || ' application fee',
                               'AMOUNT', 'NGN ' || to_char(f.amount, 'FM999,999,990.00'), 'PAID_ON', to_char(v_ts AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY'),
                               'CHANNEL', 'Old portal'),
            v_route || '_PAYMENT_SUCCESSFUL:' || v_ref, v_channels);
    END IF;
    RETURN (SELECT to_jsonb(x) FROM admissions.prelim_legacy_fee x WHERE x.id = f.id)
           || jsonb_build_object('applicationNo', a.application_no, 'feeConfirmed', (SELECT ap.fee_confirmed_at IS NOT NULL FROM admissions.application ap WHERE ap.id = a.id),
                                 'feeReference', (SELECT fr.reference FROM admissions.fee_reference fr WHERE fr.id = v_fr),
                                 'receiptNo', (SELECT fr.receipt_no FROM admissions.fee_reference fr WHERE fr.id = v_fr),
                                 'applicantTold', coalesce(p_verify, false) OR a.fee_confirmed_at IS NULL,
                                 'outcome', CASE WHEN coalesce(p_verify, false) THEN 'Verified: the old reference is posted as the application fee, and the applicant is sent the receipt.'
                                                 WHEN a.fee_confirmed_at IS NOT NULL THEN 'Not verified: the application fee is already paid on this portal, so the old payment is not counted; the applicant is not told to pay.'
                                                 ELSE 'Not verified: the applicant is told to pay the application fee on the portal, or to bring proof to the Bursary.' END);
END $fn$;
COMMENT ON FUNCTION admissions.prelim_legacy_fee_decide(uuid, boolean, text, text) IS
  'V737: an application fee paid on the old portal, decided by the Bursary (never the officer who uploaded it), with a note of what was checked: verified, the old reference (or, where it came with none, the reference found on the evidence) posted as a confirmed fee — channel Old portal, a receipt, the fee confirmed — and the applicant sent the receipt; or not verified, the applicant told to pay on the portal or see the Bursary — unless the fee is already paid here, when the old payment is not counted and the applicant is told nothing (applicantTold false). A reference already on record, or a fee already paid here, is refused verification.';

-- the Bursary's reversal of a posted fee (admissions.reverse_fee_confirmation, V420) undoes the verification of the old-portal fee it
-- posted: the fee is rejected with the reversal's reason, so the application reads unpaid and the figures and the list read it rejected
CREATE OR REPLACE FUNCTION admissions.prelim_legacy_fee_reversed() RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE f admissions.prelim_legacy_fee; v_state text;
BEGIN
    UPDATE admissions.prelim_legacy_fee
       SET state = 'REJECTED', fee_reference_id = NULL, decided_by = NEW.reversed_by, decided_office = NEW.reversed_office, decided_at = now(),
           decision_note = 'Verification reversed by the Bursary: ' || NEW.reason
     WHERE fee_reference_id = NEW.fee_reference_id AND state = 'VERIFIED'
    RETURNING * INTO f;
    IF f.id IS NOT NULL THEN
        v_state := (SELECT r.state FROM admissions.prelim_review r WHERE r.application_id = f.application_id);
        PERFORM admissions.prelim_log(f.application_id, 'OLD_FEE_REVERSED', v_state, v_state, f.decision_note,
                                      jsonb_strip_nulls(jsonb_build_object('reference', NEW.reference, 'amount', f.amount, 'receipt', NEW.receipt_no)));
    END IF;
    RETURN NULL;
END $fn$;
CREATE TRIGGER trg_prelim_legacy_fee_reversed AFTER INSERT ON admissions.fee_reversal
    FOR EACH ROW EXECUTE FUNCTION admissions.prelim_legacy_fee_reversed();
COMMENT ON FUNCTION admissions.prelim_legacy_fee_reversed() IS
  'V737: an old-portal application fee the Bursary verified (posted as a confirmed fee reference) goes back to REJECTED when the Bursary reverses that posting (admissions.fee_reversal, V420), with the reversal''s reason, officer and office; the reversal itself reopens the fee to be paid.';

-- the reconciliation's figures: what was migrated, what is held, verified, rejected, and what has no payment at all
CREATE OR REPLACE FUNCTION admissions.prelim_legacy_fee_figures(p_route text DEFAULT NULL) RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH la AS (SELECT l.application_id, r.route, a.fee_confirmed_at FROM admissions.prelim_legacy_application l
                  JOIN admissions.prelim_review r ON r.application_id = l.application_id JOIN admissions.application a ON a.id = l.application_id
                 WHERE p_route IS NULL OR r.route = upper(btrim(p_route))),
         f AS (SELECT x.*, r.route FROM admissions.prelim_legacy_fee x JOIN admissions.prelim_review r ON r.application_id = x.application_id
                WHERE p_route IS NULL OR r.route = upper(btrim(p_route))),
         -- the latest checked row of each old number not yet migrated, in a batch still open, whose payment reference is claimed twice
         dup AS (SELECT DISTINCT ON (rw.legacy_no) rw.legacy_no, b.route, rw.problems
                   FROM admissions.prelim_migration_row rw JOIN admissions.prelim_migration_batch b ON b.id = rw.batch_id
                  WHERE b.state IN ('STAGING', 'CHECKED', 'IMPORTING') AND rw.legacy_no IS NOT NULL AND rw.checked_at IS NOT NULL
                    AND (p_route IS NULL OR b.route = upper(btrim(p_route)))
                    AND NOT EXISTS (SELECT 1 FROM admissions.prelim_legacy_application l WHERE upper(btrim(l.legacy_application_no)) = rw.legacy_no)
                  ORDER BY rw.legacy_no, b.started_at DESC, rw.row_no DESC),
         dupf AS (SELECT d.* FROM dup d WHERE d.problems @> '[{"code":"FEE_REFERENCE_IN_FILE"}]' OR d.problems @> '[{"code":"FEE_REFERENCE_ELSEWHERE"}]'),
         per AS (SELECT p.route, p.name,
                        (SELECT count(*) FROM la WHERE la.route = p.route) AS imported,
                        (SELECT count(*) FROM f WHERE f.route = p.route AND f.legacy_reference IS NOT NULL) AS with_reference,
                        (SELECT count(*) FROM f WHERE f.route = p.route AND f.state = 'VERIFIED') AS verified,
                        (SELECT count(*) FROM f WHERE f.route = p.route AND f.state = 'REQUIRES_REVIEW') AS unverified,
                        (SELECT count(*) FROM f WHERE f.route = p.route AND f.state = 'REJECTED') AS rejected,
                        (SELECT count(*) FROM la WHERE la.route = p.route AND la.fee_confirmed_at IS NULL
                            AND NOT EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee x WHERE x.application_id = la.application_id)) AS no_payment,
                        (SELECT count(DISTINCT legacy_no) FROM dupf WHERE dupf.route = p.route) AS duplicates,
                        (SELECT coalesce(sum(f.amount), 0) FROM f WHERE f.route = p.route AND f.state = 'REQUIRES_REVIEW') AS held,
                        (SELECT coalesce(sum(f.amount), 0) FROM f WHERE f.route = p.route AND f.state = 'VERIFIED') AS verified_amount
                   FROM admissions.prelim_programme p
                  WHERE p.route IN ('PRELIMINARY_SCIENCE', 'PRELIMINARY_TECHNOLOGY') AND (p_route IS NULL OR p.route = upper(btrim(p_route))))
    SELECT jsonb_build_object(
        'imported', coalesce(sum(imported), 0), 'withReference', coalesce(sum(with_reference), 0), 'verified', coalesce(sum(verified), 0),
        'unverified', coalesce(sum(unverified), 0), 'rejected', coalesce(sum(rejected), 0), 'noPaymentRecord', coalesce(sum(no_payment), 0),
        'duplicateReferences', coalesce(sum(duplicates), 0), 'forReview', coalesce(sum(unverified), 0) + coalesce(sum(no_payment), 0),
        'amountHeld', coalesce(sum(held), 0), 'amountVerified', coalesce(sum(verified_amount), 0),
        'byRoute', coalesce(jsonb_agg(jsonb_build_object('route', route, 'name', name, 'imported', imported, 'withReference', with_reference, 'verified', verified,
                                                         'unverified', unverified, 'rejected', rejected, 'noPaymentRecord', no_payment, 'duplicateReferences', duplicates,
                                                         'forReview', unverified + no_payment, 'amountHeld', held, 'amountVerified', verified_amount) ORDER BY name), '[]'::jsonb))
      FROM per
$$;

-- the old-portal fees, a page at a time (a route, a state, or all)
CREATE OR REPLACE FUNCTION admissions.prelim_legacy_fees(p_route text, p_state text, p_limit int, p_offset int) RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH x AS (
        SELECT f.*, r.route, pp.name AS route_name, a.application_no, l.legacy_application_no, c.surname || ', ' || c.other_names AS applicant,
               b.reference AS batch_reference, b.started_by, b.started_office,
               (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = b.started_by) AS uploaded_by,
               (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = f.decided_by) AS decided_by_name,
               fr.reference AS posted_reference, fr.receipt_no, count(*) OVER () AS total
          FROM admissions.prelim_legacy_fee f
          JOIN admissions.application a ON a.id = f.application_id
          JOIN admissions.candidate c ON c.id = a.candidate_id
          JOIN admissions.prelim_review r ON r.application_id = f.application_id
          JOIN admissions.prelim_programme pp ON pp.route = r.route
          JOIN admissions.prelim_migration_batch b ON b.id = f.batch_id
          LEFT JOIN admissions.prelim_legacy_application l ON l.application_id = f.application_id
          LEFT JOIN admissions.fee_reference fr ON fr.id = f.fee_reference_id
         WHERE (p_route IS NULL OR r.route = upper(btrim(p_route))) AND (p_state IS NULL OR f.state = upper(btrim(p_state)))
         ORDER BY (f.state = 'REQUIRES_REVIEW') DESC, f.created_at DESC, a.application_no
         LIMIT least(greatest(coalesce(p_limit, 50), 1), 500) OFFSET greatest(coalesce(p_offset, 0), 0))
    SELECT jsonb_build_object('total', coalesce((SELECT max(total) FROM x), 0),
        'rows', coalesce(jsonb_agg(jsonb_build_object(
            'id', x.id, 'applicationId', x.application_id, 'applicationNo', x.application_no, 'legacyNo', x.legacy_application_no, 'name', x.applicant,
            'route', x.route, 'routeName', x.route_name, 'reference', x.legacy_reference, 'gatewayReference', x.gateway_reference, 'amount', x.amount,
            'paidOn', x.paid_on, 'statedStatus', x.stated_status, 'state', x.state, 'batchId', x.batch_id, 'batchReference', x.batch_reference,
            'uploadedById', x.started_by, 'uploadedBy', x.uploaded_by, 'uploadedOffice', x.started_office,
            'decidedById', x.decided_by, 'decidedBy', x.decided_by_name, 'decidedOffice', x.decided_office, 'decidedAt', x.decided_at, 'decisionNote', x.decision_note,
            'postedReference', x.posted_reference, 'receiptNo', x.receipt_no, 'createdAt', x.created_at)
            ORDER BY (x.state = 'REQUIRES_REVIEW') DESC, x.created_at DESC, x.application_no), '[]'::jsonb))
      FROM x
$$;

-- ── 11 · the programme corrected: Preliminary Technology & Industrial Studies ↔ Preliminary Science ─────────────────────────
/* what the applicant must complete under the new programme: the target (always, unless the same programme is a target there too), a
   specialisation where the targets have them, O'Level sittings the new programme does not accept, the documents it requires that are
   not uploaded or were rejected, the biodata the form requires that is empty, and the fee where nothing is paid */
CREATE OR REPLACE FUNCTION admissions.prelim_route_missing(p_app uuid, p_to text, p_target uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH pt AS (SELECT x.* FROM admissions.prelim_programme x WHERE x.route = p_to),
         a AS (SELECT ap.*, c.sex FROM admissions.application ap JOIN admissions.candidate c ON c.id = ap.candidate_id WHERE ap.id = p_app),
         ol AS (SELECT DISTINCT o.sitting, o.exam_type FROM admissions.screening_olevel o WHERE o.application_id = p_app AND o.active),
         sittings AS (SELECT count(DISTINCT sitting) AS n FROM ol),
         docs AS (SELECT d.* FROM admissions.application_document d WHERE d.application_id = p_app AND d.superseded_at IS NULL),
         fee AS (SELECT f.application_fee + f.portal_charge AS total FROM a CROSS JOIN LATERAL admissions.route_fee_rule(a.session, p_to) f),
         m AS (
            SELECT 1 AS ord, 'PAYMENT' AS step, 'application_fee' AS field, 'Pay the ' || (SELECT name FROM pt) || ' application fee' AS message
             WHERE (SELECT fee_confirmed_at FROM a) IS NULL AND coalesce((SELECT total FROM fee), -1) <> 0
               AND NOT EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee f WHERE f.application_id = p_app AND f.state = 'REQUIRES_REVIEW')
            UNION ALL
            SELECT 2, 'PERSONAL', 'sex', 'Give your sex' WHERE (SELECT sex FROM a) IS NULL
            UNION ALL
            SELECT 3, 'PERSONAL', f.field, 'Give your ' || replace(replace(replace(f.field, 'kin_', 'next of kin''s '), '_', ' '), 'lga', 'local government area')
              FROM admissions.prelim_form_fields() f
             WHERE f.required AND NOT EXISTS (SELECT 1 FROM admissions.screening_answer s WHERE s.application_id = p_app AND s.field = f.field)
            UNION ALL
            SELECT 4, 'OLEVEL', 'sittings', 'Give your O''Level results (one sitting or two). An awaiting result is not accepted.' WHERE (SELECT n FROM sittings) = 0
            UNION ALL
            SELECT 5, 'OLEVEL', 'sitting ' || ol.sitting,
                   'Sitting ' || ol.sitting || ': ' || coalesce((SELECT q.label FROM admissions.qualification_type q WHERE q.code = ol.exam_type), coalesce(ol.exam_type, 'the qualification given'))
                   || ' is not accepted for ' || (SELECT name FROM pt) || '; give a result the programme accepts'
              FROM ol WHERE ol.exam_type IS NOT NULL AND ol.exam_type <> ALL ((SELECT qualification_types FROM pt)::text[])
            UNION ALL
            SELECT 6, 'OLEVEL', 'sittings', 'At most ' || (SELECT max_sittings FROM pt) || ' sitting(s) are accepted for ' || (SELECT name FROM pt)
             WHERE (SELECT n FROM sittings) > (SELECT max_sittings FROM pt)
            UNION ALL
            SELECT 7, 'PROGRAMME', 'target', 'Choose the ' || (SELECT target_word FROM pt) || ' under ' || (SELECT name FROM pt) WHERE p_target IS NULL
            UNION ALL
            SELECT 8, 'PROGRAMME', 'specialisation', 'Choose your specialisation, where the ' || (SELECT target_word FROM pt) || ' you choose has them'
             WHERE p_target IS NULL AND EXISTS (SELECT 1 FROM admissions.prelim_specialisation s JOIN admissions.prelim_target t ON t.id = s.target_id
                                                 WHERE t.route = p_to AND t.state = 'MAPPED' AND s.active)
            UNION ALL
            SELECT 8, 'PROGRAMME', 'specialisation', 'Choose your specialisation' WHERE p_target IS NOT NULL
               AND EXISTS (SELECT 1 FROM admissions.prelim_specialisation s WHERE s.target_id = p_target AND s.active)
            UNION ALL
            SELECT 9, 'DOCUMENTS', q.kind, 'Upload your ' || lower(left(q.label, 1)) || substr(q.label, 2)
              FROM admissions.prelim_document q
             WHERE q.route = p_to AND q.required AND (NOT q.second_sitting_only OR (SELECT n FROM sittings) >= 2)
               AND NOT EXISTS (SELECT 1 FROM docs WHERE docs.kind = q.kind)
            UNION ALL
            SELECT 10, 'DOCUMENTS', d.kind, 'Replace your ' || lower(coalesce((SELECT q.label FROM admissions.prelim_document q WHERE q.route = p_to AND q.kind = d.kind), replace(d.kind, '_', ' ')))
                       || ', which the Office could not accept'
              FROM docs d WHERE d.status = 'REJECTED')
    SELECT coalesce(jsonb_agg(jsonb_build_object('step', m.step, 'field', m.field, 'message', m.message) ORDER BY m.ord, m.field), '[]'::jsonb) FROM m
$$;

CREATE OR REPLACE FUNCTION admissions.prelim_change_route_check(p_app uuid, p_to_route text) RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE r admissions.prelim_review; a admissions.application; c admissions.candidate; pf admissions.prelim_programme; pt admissions.prelim_programme;
        v_to text := upper(btrim(coalesce(p_to_route, ''))); v_code text; v_msg text; v_after text; v_missing jsonb := '[]';
        v_fee_status text; v_paid numeric := 0; v_refs text[] := '{}'; h admissions.prelim_legacy_fee; v_from_fee numeric; v_to_fee numeric;
        v_covers boolean := true; v_dup text; v_remap uuid; t admissions.prelim_target; v_from_target text; v_spec text; v_legacy text; v_dob text;
BEGIN
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app;
    IF r.application_id IS NULL THEN RAISE EXCEPTION 'PRELIM_NOT_APPLICATION: that is not a preliminary programme application' USING ERRCODE = '23514'; END IF;
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    SELECT * INTO pf FROM admissions.prelim_programme WHERE route = r.route;
    SELECT * INTO pt FROM admissions.prelim_programme WHERE route = v_to;
    SELECT * INTO t FROM admissions.prelim_target WHERE id = r.target_id;
    v_from_target := coalesce((SELECT g.name FROM ref.programme g WHERE g.code = t.programme_code), t.requested_name);
    v_spec := (SELECT s.name FROM admissions.prelim_specialisation s WHERE s.id = r.specialisation_id);
    v_legacy := (SELECT l.legacy_application_no FROM admissions.prelim_legacy_application l WHERE l.application_id = p_app);
    v_dob := (SELECT sa.value FROM admissions.screening_answer sa WHERE sa.application_id = p_app AND sa.field = 'date_of_birth');

    -- the fee as it stands: paid (confirmed references), held (an old-portal fee waiting for the Bursary), nothing to pay, or unpaid
    SELECT coalesce(sum(fr.amount), 0), coalesce(array_agg(fr.reference ORDER BY fr.confirmed_at), '{}') INTO v_paid, v_refs
      FROM admissions.fee_reference fr WHERE fr.application_id = p_app AND fr.kind = 'APPLICATION' AND fr.confirmed_at IS NOT NULL;
    SELECT * INTO h FROM admissions.prelim_legacy_fee f WHERE f.application_id = p_app AND f.state = 'REQUIRES_REVIEW';
    SELECT f.application_fee + f.portal_charge INTO v_from_fee FROM admissions.route_fee_rule(a.session, r.route) f;
    IF pt.route IS NOT NULL THEN
        SELECT f.application_fee + f.portal_charge INTO v_to_fee FROM admissions.route_fee_rule(a.session, pt.route) f;
    END IF;
    IF a.fee_confirmed_at IS NOT NULL AND v_paid > 0 THEN
        v_fee_status := 'PAID';
    ELSIF a.fee_confirmed_at IS NOT NULL THEN
        v_fee_status := 'NOT_REQUIRED';
    ELSIF h.id IS NOT NULL THEN
        v_fee_status := 'HELD'; v_paid := h.amount; v_refs := CASE WHEN h.legacy_reference IS NOT NULL THEN ARRAY[h.legacy_reference] ELSE '{}' END;
    ELSIF v_from_fee = 0 THEN
        v_fee_status := 'NOT_REQUIRED';
    ELSE
        v_fee_status := 'UNPAID'; v_paid := 0;
    END IF;
    -- a fee settled (or held) carries across unless the new programme costs more than the one it settled
    v_covers := CASE v_fee_status WHEN 'PAID' THEN v_paid >= coalesce(v_to_fee, 0) OR coalesce(v_to_fee, 0) <= coalesce(v_from_fee, 0)
                                  WHEN 'HELD' THEN v_paid >= coalesce(v_to_fee, 0) OR coalesce(v_to_fee, 0) <= coalesce(v_from_fee, 0)
                                  WHEN 'NOT_REQUIRED' THEN a.fee_confirmed_at IS NULL OR coalesce(v_to_fee, 0) = 0
                                  ELSE true END;

    -- the target kept only where the same programme of the register is a target of the new programme too
    IF pt.route IS NOT NULL AND t.programme_code IS NOT NULL THEN
        SELECT t2.id INTO v_remap FROM admissions.prelim_target t2 WHERE t2.route = pt.route AND t2.programme_code = t.programme_code AND t2.state = 'MAPPED';
    END IF;
    IF pt.route IS NOT NULL THEN v_missing := admissions.prelim_route_missing(p_app, pt.route, v_remap); END IF;
    v_after := CASE WHEN r.state = 'DRAFT' THEN 'DRAFT'
                    WHEN r.state IN ('SUBMITTED', 'UNDER_REVIEW', 'RECOMMENDED', 'CORRECTION_REQUIRED')
                         THEN CASE WHEN jsonb_array_length(v_missing) > 0 THEN 'CORRECTION_REQUIRED' ELSE 'SUBMITTED' END
                    ELSE r.state END;

    -- the same person already on the new programme in the session (the name and birth date, or an O'Level sitting)
    IF pt.route IS NOT NULL THEN
        SELECT ap.application_no INTO v_dup
          FROM admissions.application ap
          JOIN admissions.prelim_review pr ON pr.application_id = ap.id AND pr.route = pt.route AND pr.state <> 'WITHDRAWN'
          JOIN admissions.candidate c2 ON c2.id = ap.candidate_id
          LEFT JOIN admissions.screening_answer sa ON sa.application_id = ap.id AND sa.field = 'date_of_birth'
         WHERE ap.session = a.session AND ap.id <> p_app
           AND ((upper(c2.surname) = upper(c.surname) AND lower(split_part(c2.other_names, ' ', 1)) = lower(split_part(c.other_names, ' ', 1)) AND sa.value = v_dob)
                OR EXISTS (SELECT 1 FROM admissions.screening_olevel o1
                             JOIN admissions.screening_olevel o2 ON o2.application_id = ap.id AND o2.active AND upper(o2.exam_body) = upper(o1.exam_body)
                                  AND o2.exam_year = o1.exam_year
                                  AND upper(regexp_replace(o2.exam_number, '\s', '', 'g')) = upper(regexp_replace(o1.exam_number, '\s', '', 'g'))
                            WHERE o1.application_id = p_app AND o1.active))
         ORDER BY ap.application_no LIMIT 1;
    END IF;

    IF v_to NOT IN ('PRELIMINARY_TECHNOLOGY', 'PRELIMINARY_SCIENCE') OR r.route NOT IN ('PRELIMINARY_TECHNOLOGY', 'PRELIMINARY_SCIENCE') OR v_to = r.route OR pt.route IS NULL THEN
        v_code := 'PRELIM_CHANGE_ROUTE';
        v_msg := 'a preliminary application moves only between Preliminary Technology & Industrial Studies and Preliminary Science, to the other one';
    ELSIF r.published_at IS NOT NULL THEN
        v_code := 'PRELIM_CHANGE_PUBLISHED';
        v_msg := format('the outcome was published on %s and stands; the programme of a published application is not changed', to_char(r.published_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY'));
    ELSIF r.state IN ('APPROVED', 'NOT_ADMITTED', 'REJECTED') THEN
        v_code := 'PRELIM_CHANGE_DECIDED';
        v_msg := format('the application is decided (%s); the Academic Office reopens it before its programme is changed', lower(replace(r.state, '_', ' ')));
    ELSIF r.state = 'WITHDRAWN' THEN
        v_code := 'PRELIM_CHANGE_WITHDRAWN';
        v_msg := 'the application was withdrawn; a withdrawn application''s programme is not changed';
    ELSIF v_dup IS NOT NULL THEN
        v_code := 'PRELIM_CHANGE_DUPLICATE';
        v_msg := format('the applicant already has a %s application for %s (%s); one person holds one application', pt.name, a.session, v_dup);
    ELSIF NOT v_covers THEN
        v_code := 'PRELIM_CHANGE_FEE_SHORT';
        v_msg := format('the application fee paid (₦%s) does not cover the %s application fee (₦%s)', to_char(v_paid, 'FM999,999,990.##'), pt.name, to_char(coalesce(v_to_fee, 0), 'FM999,999,990.##'));
    END IF;

    RETURN jsonb_build_object(
        'may', v_code IS NULL, 'refusal', CASE WHEN v_code IS NOT NULL THEN jsonb_build_object('code', v_code, 'message', v_msg) END,
        'applicationId', a.id, 'applicationNo', a.application_no, 'legacyNo', v_legacy, 'applicantName', c.surname || ', ' || c.other_names, 'session', a.session,
        'route', r.route, 'routeName', pf.name, 'toRoute', pt.route, 'toRouteName', pt.name,
        'state', r.state, 'stateAfter', v_after, 'published', r.published_at IS NOT NULL,
        'fromTarget', CASE WHEN t.id IS NOT NULL THEN jsonb_build_object('id', t.id, 'name', v_from_target, 'group', t.group_name, 'specialisation', v_spec) END,
        'targetKept', CASE WHEN v_remap IS NOT NULL THEN jsonb_build_object('id', v_remap, 'name', v_from_target) END,
        'feeStatus', v_fee_status, 'feeAmount', v_paid, 'feeReferences', to_jsonb(v_refs), 'heldReference', h.legacy_reference,
        'fromRouteFee', v_from_fee, 'toRouteFee', v_to_fee, 'feeCovers', v_covers, 'missing', v_missing);
END $fn$;
COMMENT ON FUNCTION admissions.prelim_change_route_check(uuid, text) IS
  'V737: whether a preliminary application may move to the other preliminary programme, and why not (PRELIM_CHANGE_ROUTE, _PUBLISHED, _DECIDED, _WITHDRAWN, _DUPLICATE, _FEE_SHORT), with the facts the officer reads first: both numbers, the programme now and after, the state now and after, the fee as it stands (PAID with its references, HELD with the old reference, UNPAID, NOT_REQUIRED) and the new programme''s fee, and what the applicant must complete under the new programme.';

-- the history row of a correction, applied or refused
CREATE OR REPLACE FUNCTION admissions.prelim_route_change_row(p_check jsonb, p_reason text, p_result text, p_code text, p_message text, p_to_state text)
RETURNS admissions.prelim_route_change LANGUAGE plpgsql AS $fn$
DECLARE v_year text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY'); x admissions.prelim_route_change;
BEGIN
    INSERT INTO admissions.prelim_route_change (reference, application_id, application_no, legacy_application_no, from_route, to_route, from_target_id, from_target_name,
                                                from_specialisation_name, from_state, to_state, reason, fee_status, fee_amount, fee_references, missing, result,
                                                refusal_code, refusal_message, actor, actor_office)
    VALUES ('PRELIM-CHG/' || v_year || '/' || lpad(platform.next_number('PRELIM_ROUTE_CHANGE', 'UNIVERSITY', v_year)::text, 6, '0'),
            (p_check->>'applicationId')::uuid, p_check->>'applicationNo', p_check->>'legacyNo', p_check->>'route', p_check->>'toRoute',
            (p_check->'fromTarget'->>'id')::uuid, p_check->'fromTarget'->>'name', p_check->'fromTarget'->>'specialisation', p_check->>'state', p_to_state,
            coalesce(btrim(p_reason), ''), p_check->>'feeStatus', (p_check->>'feeAmount')::numeric,
            coalesce(ARRAY(SELECT jsonb_array_elements_text(coalesce(p_check->'feeReferences', '[]'::jsonb))), '{}'),
            coalesce(p_check->'missing', '[]'::jsonb), p_result, p_code, p_message,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    RETURNING * INTO x;
    RETURN x;
END $fn$;

CREATE OR REPLACE FUNCTION admissions.prelim_change_route(p_app uuid, p_to_route text, p_from_route text, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; a admissions.application; k jsonb; v_to text := upper(btrim(coalesce(p_to_route, ''))); pt admissions.prelim_programme;
        v_after text; v_note text; v_remap uuid; x admissions.prelim_route_change; v_reason text := btrim(coalesce(p_reason, '')); v_from_name text;
        acc admissions.applicant_account; v_channels text[] := ARRAY['PORTAL']; v_next text; v_fee_note text; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    PERFORM admissions.prelim_route_officer();
    IF length(v_reason) < 15 OR array_length(regexp_split_to_array(v_reason, '\s+'), 1) < 3 THEN
        RAISE EXCEPTION 'PRELIM_CHANGE_REASON: say why the programme is changed, in a sentence (at least 15 characters and three words)' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    IF r.application_id IS NULL THEN RAISE EXCEPTION 'PRELIM_NOT_APPLICATION: that is not a preliminary programme application' USING ERRCODE = '23514'; END IF;
    SELECT * INTO a FROM admissions.application WHERE id = p_app FOR UPDATE;
    IF r.route IS DISTINCT FROM upper(btrim(coalesce(p_from_route, ''))) THEN
        RAISE EXCEPTION 'PRELIM_CHANGE_STALE: the application is now under %, not the programme the screen showed; open it again', (SELECT p.name FROM admissions.prelim_programme p WHERE p.route = r.route)
            USING ERRCODE = '23514';
    END IF;
    k := admissions.prelim_change_route_check(p_app, v_to);
    IF NOT (k->>'may')::boolean THEN
        RAISE EXCEPTION '%: %', k->'refusal'->>'code', k->'refusal'->>'message' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO pt FROM admissions.prelim_programme WHERE route = v_to;
    v_from_name := k->>'routeName';
    v_after := k->>'stateAfter';
    v_remap := (k->'targetKept'->>'id')::uuid;
    v_next := (SELECT string_agg(e->>'message', '; ') FROM jsonb_array_elements(k->'missing') e);
    v_note := 'Your application was moved by the University from ' || v_from_name || ' to ' || pt.name || '. Complete under ' || pt.name || ': ' || coalesce(v_next, 'nothing more') || '.';
    UPDATE admissions.prelim_review
       SET route = v_to,
           target_id = v_remap, target_programme = CASE WHEN v_remap IS NOT NULL THEN r.target_programme END, specialisation_id = NULL,
           target_set_at = CASE WHEN v_remap IS NOT NULL THEN r.target_set_at END,
           state = v_after,
           request_note = CASE WHEN v_after = 'CORRECTION_REQUIRED' THEN v_note ELSE request_note END,
           requested_at = CASE WHEN v_after = 'CORRECTION_REQUIRED' THEN now() ELSE requested_at END,
           requested_by = CASE WHEN v_after = 'CORRECTION_REQUIRED' THEN v_actor ELSE requested_by END,
           recommended_at = NULL, recommended_by = NULL, recommendation_note = NULL, review_started_at = NULL, review_started_by = NULL,
           -- the old programme's remediation decision does not settle the new one's: prelim_evaluate reads it afresh (the history keeps it)
           remediation_status = CASE WHEN remediation_status IN ('NOT_REQUIRED', 'REQUIRED') THEN remediation_status END,
           remediation_note = NULL, remediation_set_by = NULL, remediation_set_at = NULL,
           updated_at = now()
     WHERE application_id = p_app;
    UPDATE admissions.candidate SET programme = pt.name WHERE id = a.candidate_id;
    -- a reference drawn for the old programme's fee and not paid is closed where the new fee differs; paid fees and receipts stay
    UPDATE admissions.fee_reference SET expires_at = least(expires_at, now())
     WHERE application_id = p_app AND kind = 'APPLICATION' AND confirmed_at IS NULL AND expires_at > now()
       AND amount IS DISTINCT FROM (k->>'toRouteFee')::numeric;
    PERFORM admissions.prelim_evaluate(p_app);
    x := admissions.prelim_route_change_row(k, v_reason, 'APPLIED', NULL, NULL, v_after);
    PERFORM admissions.prelim_log(p_app, 'ROUTE_CHANGED', r.state, v_after, v_reason,
                                  jsonb_strip_nulls(jsonb_build_object('fromRoute', r.route, 'toRoute', v_to, 'fromTarget', k->'fromTarget',
                                                                       'fee', jsonb_build_object('status', k->>'feeStatus', 'amount', (k->>'feeAmount')::numeric, 'references', k->'feeReferences'),
                                                                       'reference', x.reference, 'missing', k->'missing')));
    -- the applicant told under the new programme's own notices, on the channels that are really theirs
    SELECT * INTO acc FROM admissions.applicant_account WHERE id = a.account_id;
    IF acc.email !~* '@migrate\.moau\.local$' THEN v_channels := array_append(v_channels, 'EMAIL'); END IF;
    IF acc.phone ~ '^0[0-9]{10}$' AND acc.phone <> '00000000000' THEN v_channels := array_append(v_channels, 'SMS'); END IF;
    v_fee_note := CASE k->>'feeStatus' WHEN 'PAID' THEN 'The application fee you paid is kept; you do not pay it again.'
                                       WHEN 'HELD' THEN 'The application fee you paid on the old portal is still being verified by the Bursary; you are not asked to pay it again.'
                                       WHEN 'UNPAID' THEN 'Pay the ' || pt.name || ' application fee from your dashboard.' ELSE '' END;
    PERFORM platform.tell_applicant(p_app, v_to, 'PROGRAMME_CHANGED',
        jsonb_build_object('APPLICATION_NO', a.application_no, 'FROM_PROGRAMME', v_from_name, 'FEE_NOTE', v_fee_note,
                           'NEXT_STEP', CASE WHEN v_next IS NOT NULL THEN 'Complete the following under ' || pt.name || ': ' || v_next || '.' ELSE 'Nothing more is needed from you now.' END),
        'prelim-programme-changed:' || x.id, v_channels);
    RETURN jsonb_build_object('id', x.id, 'reference', x.reference, 'applicationId', x.application_id, 'applicationNo', x.application_no, 'legacyNo', x.legacy_application_no,
                              'fromRoute', x.from_route, 'toRoute', x.to_route, 'toRouteName', pt.name, 'fromState', x.from_state, 'toState', x.to_state,
                              'feeStatus', x.fee_status, 'feeAmount', x.fee_amount, 'feeReferences', to_jsonb(x.fee_references), 'missing', x.missing,
                              'targetKept', k->'targetKept', 'result', x.result, 'at', x.at, 'check', k);
END $fn$;
COMMENT ON FUNCTION admissions.prelim_change_route(uuid, text, text, text) IS
  'V737: a preliminary application moved to the other preliminary programme by ICT (admissions.prelim_route_officer), with a reason, from the programme the screen showed: the same application and number; the target cleared (kept only where the same programme is a target there too); a submitted or reviewed application back with the applicant for what the new programme asks (CORRECTION_REQUIRED), else submitted afresh; the review''s recommendation and an officer''s remediation decision cleared; the O''Level, documents, fees and receipts untouched (an unpaid reference for a different amount closed); the eligibility read again; the history written once; the applicant told.';

CREATE OR REPLACE FUNCTION admissions.prelim_route_change_refused(p_app uuid, p_to_route text, p_reason text, p_code text, p_message text) RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE k jsonb; x admissions.prelim_route_change;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'PRELIM_CHANGE_ACTOR: a programme correction is recorded with the person who asked for it' USING ERRCODE = '23514';
    END IF;
    IF coalesce(p_code, '') !~ '^[A-Z][A-Z0-9_]{2,60}$' THEN
        RAISE EXCEPTION 'PRELIM_CHANGE_CODE: a refusal is recorded with its code' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM admissions.prelim_review r WHERE r.application_id = p_app) THEN
        RAISE EXCEPTION 'PRELIM_NOT_APPLICATION: that is not a preliminary programme application' USING ERRCODE = '23514';
    END IF;
    k := admissions.prelim_change_route_check(p_app, p_to_route);
    k := k || jsonb_build_object('toRoute', coalesce(k->>'toRoute', nullif(left(upper(btrim(coalesce(p_to_route, ''))), 40), '')));
    x := admissions.prelim_route_change_row(k, p_reason, 'REFUSED', p_code, left(coalesce(p_message, ''), 500), k->>'state');
    RETURN x.id;
END $fn$;

-- the corrections of a route (to or from it; both routes when NULL), newest first, a page at a time
CREATE OR REPLACE FUNCTION admissions.prelim_route_changes(p_route text, p_limit int, p_offset int) RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH x AS (
        SELECT ch.*, count(*) OVER () AS total
          FROM admissions.prelim_route_change ch
         WHERE p_route IS NULL OR upper(btrim(p_route)) IN (ch.from_route, ch.to_route)
         ORDER BY ch.at DESC, ch.reference DESC
         LIMIT least(greatest(coalesce(p_limit, 50), 1), 500) OFFSET greatest(coalesce(p_offset, 0), 0))
    SELECT jsonb_build_object('total', coalesce((SELECT max(total) FROM x), 0),
        'rows', coalesce(jsonb_agg(jsonb_build_object(
            'id', x.id, 'reference', x.reference, 'applicationId', x.application_id, 'applicationNo', x.application_no, 'legacyNo', x.legacy_application_no,
            'name', (SELECT c.surname || ', ' || c.other_names FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id WHERE a.id = x.application_id),
            'fromRoute', x.from_route, 'fromRouteName', (SELECT p.name FROM admissions.prelim_programme p WHERE p.route = x.from_route),
            'toRoute', x.to_route, 'toRouteName', (SELECT p.name FROM admissions.prelim_programme p WHERE p.route = x.to_route),
            'fromTargetName', x.from_target_name, 'fromSpecialisationName', x.from_specialisation_name, 'fromState', x.from_state, 'toState', x.to_state,
            'reason', x.reason, 'feeStatus', x.fee_status, 'feeAmount', x.fee_amount, 'feeReferences', to_jsonb(x.fee_references), 'missing', x.missing,
            'result', x.result, 'refusalCode', x.refusal_code, 'refusalMessage', x.refusal_message,
            'actorId', x.actor, 'actor', (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = x.actor), 'actorOffice', x.actor_office, 'at', x.at)
            ORDER BY x.at DESC, x.reference DESC), '[]'::jsonb))
      FROM x
$$;

-- ── 12 · the desk's figures (V701's prelim_stats, with the new ones) ────────────────────────────────────────────────────────
/* the dashboard's figures for a session, each the filter of the list behind it; a Head of Department or a Dean reads those whose
   target programme is in their department or faculty. V737 adds:
     new          — the application made in the last seven days, Lagos: (a.created_at AT TIME ZONE 'Africa/Lagos')::date > today (Lagos) - 7
     accepted     — candidate.offer_state = 'ACCEPTED'
     outstanding  — open (not WITHDRAWN, ADMITTED, NOT_ADMITTED, REJECTED) with any of: the fee not settled (not confirmed, and the route's
                    fee not nothing), a required document of the route not uploaded or rejected, eligibility RESULT_REQUIRED or
                    PENDING_REVIEW, no target, CORRECTION_REQUIRED
     feeHeld      — an old-portal fee waiting for the Bursary (prelim_legacy_fee REQUIRES_REVIEW)
     migrated     — brought from the old portal (prelim_legacy_application) */
CREATE OR REPLACE FUNCTION admissions.prelim_stats(p_route text, p_session text, p_dept text DEFAULT NULL, p_faculty text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
    WITH fee AS (SELECT coalesce((SELECT f.application_fee + f.portal_charge FROM admissions.route_fee_rule(p_session, upper(btrim(p_route))) f), -1) AS total),
         x AS (SELECT r.*, a.fee_confirmed_at, a.created_at AS applied_at, c.offer_state FROM admissions.prelim_review r JOIN admissions.application a ON a.id = r.application_id
                 JOIN admissions.candidate c ON c.id = a.candidate_id
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
        -- V737
        'new', (SELECT count(*) FROM x WHERE (x.applied_at AT TIME ZONE 'Africa/Lagos')::date > (now() AT TIME ZONE 'Africa/Lagos')::date - 7),
        'accepted', (SELECT count(*) FROM x WHERE x.offer_state = 'ACCEPTED'),
        'outstanding', (SELECT count(*) FROM x
                         WHERE x.state NOT IN ('WITHDRAWN', 'ADMITTED', 'NOT_ADMITTED', 'REJECTED')
                           AND ((x.fee_confirmed_at IS NULL AND (SELECT total FROM fee) <> 0)
                                OR x.eligibility_status IN ('RESULT_REQUIRED', 'PENDING_REVIEW')
                                OR x.target_id IS NULL
                                OR x.state = 'CORRECTION_REQUIRED'
                                OR EXISTS (SELECT 1 FROM admissions.prelim_document dq
                                            WHERE dq.route = x.route AND dq.required AND (NOT dq.second_sitting_only OR coalesce(x.sittings, 0) >= 2)
                                              AND NOT EXISTS (SELECT 1 FROM admissions.application_document ad
                                                               WHERE ad.application_id = x.application_id AND ad.kind = dq.kind
                                                                 AND ad.superseded_at IS NULL AND ad.status <> 'REJECTED')))),
        'feeHeld', (SELECT count(*) FROM x WHERE EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee f WHERE f.application_id = x.application_id AND f.state = 'REQUIRES_REVIEW')),
        'migrated', (SELECT count(*) FROM x WHERE EXISTS (SELECT 1 FROM admissions.prelim_legacy_application l WHERE l.application_id = x.application_id)),
        'byTarget', coalesce((SELECT jsonb_agg(jsonb_build_object('targetId', q.id, 'programmeCode', q.code, 'name', q.name, 'group', q.group_name, 'n', q.n) ORDER BY q.n DESC, q.name)
                                FROM (SELECT t.id, t.programme_code AS code, coalesce(p.name, t.requested_name) AS name, t.group_name, count(*) AS n
                                        FROM x JOIN admissions.prelim_target t ON t.id = x.target_id LEFT JOIN ref.programme p ON p.code = t.programme_code
                                       WHERE x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN' GROUP BY t.id, t.programme_code, p.name, t.requested_name, t.group_name) q), '[]'::jsonb),
        'byGroup', coalesce((SELECT jsonb_agg(jsonb_build_object('group', q.group_name, 'n', q.n) ORDER BY q.n DESC, q.group_name)
                               FROM (SELECT t.group_name, count(*) AS n FROM x JOIN admissions.prelim_target t ON t.id = x.target_id
                                      WHERE x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN' GROUP BY t.group_name) q), '[]'::jsonb),
        'bySpecialisation', coalesce((SELECT jsonb_agg(jsonb_build_object('name', q.name, 'n', q.n) ORDER BY q.n DESC, q.name)
                                        FROM (SELECT sp.name, count(*) AS n FROM x JOIN admissions.prelim_specialisation sp ON sp.id = x.specialisation_id
                                               WHERE x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN' GROUP BY sp.name) q), '[]'::jsonb),
        'bySittings', coalesce((SELECT jsonb_agg(jsonb_build_object('sittings', s.sittings, 'n', s.n) ORDER BY s.sittings)
                                  FROM (SELECT coalesce(sittings, 0) AS sittings, count(*) AS n FROM x WHERE submitted_at IS NOT NULL AND state <> 'WITHDRAWN' GROUP BY 1) s), '[]'::jsonb))
$fn$;

-- ── 13 · the UTME intake and the pipeline leave the preliminary programmes to their own panel ────────────────────────────────
-- people.intake_tranche (V722): a preliminary or proficiency candidate never goes onto the register through the UTME intake —
-- people.intake_one refuses a programme the register does not hold (the route's name), and the tranche rolled back on the first
CREATE OR REPLACE FUNCTION people.intake_tranche(p_session text, p_limit int DEFAULT NULL)
RETURNS TABLE (brought int, remaining int)
LANGUAGE plpgsql AS $$
DECLARE c record; v_n int := 0; v_began boolean;
BEGIN
    -- one run of a session at a time: a second run (another officer, another tab, a resent request) waits for the first to commit
    -- and then reads what is still off the register, instead of racing it onto ux_student_candidate (V429) for the same candidate
    PERFORM pg_advisory_xact_lock(hashtext('people.intake:' || p_session));
    -- V463's deferral: each student the triggers would refresh is noted, and the run's students are refreshed together at the end
    v_began := people.defer_positions();
    FOR c IN
        SELECT a.id FROM admissions.candidate a
         WHERE a.session = p_session AND a.offer_state IN ('ADMITTED', 'ACCEPTED')
           AND a.entry_mode NOT IN ('PRELIMINARY', 'PROFICIENCY')   -- V737: the preliminary programmes are not on the UTME intake
           AND NOT EXISTS (SELECT 1 FROM people.student s WHERE s.candidate_id = a.id)
         ORDER BY a.surname, a.other_names, a.id
         LIMIT CASE WHEN p_limit IS NULL OR p_limit < 1 THEN NULL ELSE p_limit END
    LOOP
        PERFORM people.intake_one(c.id);
        v_n := v_n + 1;
    END LOOP;
    IF v_began THEN PERFORM people.refresh_deferred_positions(); END IF;
    RETURN QUERY
        SELECT v_n,
               (SELECT count(*)::int FROM admissions.candidate a
                 WHERE a.session = p_session AND a.offer_state IN ('ADMITTED', 'ACCEPTED')
                   AND a.entry_mode NOT IN ('PRELIMINARY', 'PROFICIENCY')
                   AND NOT EXISTS (SELECT 1 FROM people.student s WHERE s.candidate_id = a.id));
END $$;
COMMENT ON FUNCTION people.intake_tranche(text, int) IS
  'V722: the session''s admitted candidates not yet on the register brought on by surname, at most p_limit of them (NULL or under one: all), each by people.intake_one; one run of a session at a time (an advisory lock per session); the academic position triggers deferred for the run and the run''s students refreshed together once (V463). Returns how many were brought on and how many remain. V737: never a preliminary or proficiency candidate (their programmes are not on the register; their own panel shows them).';

-- admissions.pipeline_stats (V537): the offered and acceptance figures leave out the preliminary and proficiency candidates
CREATE OR REPLACE FUNCTION admissions.pipeline_stats(p_session text)
 RETURNS TABLE(jamb_uploaded bigint, matched bigint, unmatched bigint, admitted bigint, acceptance_pending bigint, acceptance_paid bigint, screening_pending bigint, screening_submitted bigint, screening_successful bigint, screening_unsuccessful bigint, screening_returned bigint, change_requested bigint, change_approved bigint, fees_paid bigint, registered bigint, ready_for_matric bigint, matriculated bigint)
 LANGUAGE sql
 STABLE
AS $function$

    WITH offered AS MATERIALIZED (
        SELECT a.id, a.candidate_id, a.session, a.accepted_at, (SELECT e.paid FROM admissions.acceptance_entitlement(a.id) e) AS acc_paid, f.state AS scr,
               s.id AS student_id, s.matric_no,
               s.id IS NOT NULL AND EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = a.session AND r.status IN ('APPROVED', 'LOCKED')) AS reg
          FROM admissions.application a
          -- V737: the preliminary programmes are shown on their own panel, never among the UTME offers
          JOIN admissions.candidate cd ON cd.id = a.candidate_id AND cd.entry_mode NOT IN ('PRELIMINARY', 'PROFICIENCY')
          LEFT JOIN admissions.screening_form f ON f.application_id = a.id
          LEFT JOIN people.student s ON s.candidate_id = a.candidate_id
         WHERE a.session = p_session AND a.decision = 'OFFERED' AND a.decision_released_at IS NOT NULL),
    -- V537: the school fees paid in full read for the session at once — finance.position's test (nothing due, or short by under one
    -- naira) on the session's charges and payments — not finance.position once for every admitted student (24 s on the live-shaped copy)
    fees AS MATERIALIZED (
        SELECT c.student_id, c.total = 0 OR NOT finance.fee_short(c.total, coalesce(pay.total, 0)) AS paid_in_full
          FROM finance.session_charges(p_session) c
          LEFT JOIN finance.session_payments(p_session) pay ON pay.student_id = c.student_id),
    apps AS MATERIALIZED (
        SELECT o.*, coalesce(fe.paid_in_full, false) AS paid
          FROM offered o LEFT JOIN fees fe ON fe.student_id = o.student_id)

    SELECT (SELECT count(*) FROM admissions.jamb_admission j WHERE j.session = p_session),

           (SELECT count(*) FROM admissions.jamb_admission j WHERE j.session = p_session AND j.matched),

           (SELECT count(*) FROM admissions.jamb_admission j WHERE j.session = p_session AND NOT j.matched),

           count(*), count(*) FILTER (WHERE accepted_at IS NULL), count(*) FILTER (WHERE acc_paid),

           count(*) FILTER (WHERE accepted_at IS NOT NULL AND (scr IS NULL OR scr = 'PENDING') AND admissions.screening_required(id)),

           count(*) FILTER (WHERE scr = 'IN_REVIEW'), count(*) FILTER (WHERE scr = 'SUCCESSFUL'), count(*) FILTER (WHERE scr = 'UNSUCCESSFUL'), count(*) FILTER (WHERE scr = 'CORRECTION_REQUIRED'),

           (SELECT count(*) FROM admissions.programme_change_request q WHERE q.session = p_session AND q.state = 'REQUESTED'),

           (SELECT count(*) FROM admissions.programme_change_request q WHERE q.session = p_session AND q.state = 'APPROVED'),

           count(*) FILTER (WHERE paid), count(*) FILTER (WHERE reg),

           count(*) FILTER (WHERE paid AND reg AND matric_no IS NULL AND admissions.screening_ok(id)), count(*) FILTER (WHERE matric_no IS NOT NULL)

      FROM apps;

$function$;

-- ── 14 · the notices: each route's own, in its office's words ───────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority)
SELECT x.route || ':' || t.event, replace(t.label, '[NAME]', x.name), replace(t.purpose, '[NAME]', x.name),
       replace(t.email_subject, '[NAME]', x.name), replace(replace(t.email_body, '[NAME]', x.name), '[OFFICE]', x.office),
       replace(t.sms_body, '[NAME]', x.name), replace(t.portal_title, '[NAME]', x.name), replace(t.portal_body, '[NAME]', x.name),
       t.variables, true, t.priority
  FROM (VALUES ('PRELIMINARY_SCIENCE', 'Preliminary Science', 'Preliminary Science Office'),
               ('PRELIMINARY_TECHNOLOGY', 'Preliminary Technology & Industrial Studies', 'Preliminary Vocational and Technical Education Office')) x(route, name, office)
 CROSS JOIN (VALUES
  ('MIGRATED', '[NAME] application brought from the old portal',
   'Sent once when a [NAME] application is brought from the old portal: both numbers, how to sign in, the fee held for the Bursary where there is one.',
   'Your [NAME] application is on the new portal: [APPLICATION_NO]',
   E'Dear [FIRST_NAME],\n\nYour [NAME] application on the University''s old portal (application number [LEGACY_NO]) has been brought across to the new portal as it stood. You do not apply again.\n\nYour application number on the new portal is [APPLICATION_NO]; your old number stays on your record. Sign in at [PORTAL_URL] with either number, or with this email address. [SIGN_IN]\n\n[FEE_NOTE]\n\n[OFFICE], [UNIVERSITY_NAME]',
   '[UNIVERSITY_SHORT]: your [NAME] application [LEGACY_NO] is now [APPLICATION_NO] on the new portal. Sign in with either number. [SIGN_IN]',
   'Application brought from the old portal', 'Your old application [LEGACY_NO] is now [APPLICATION_NO] on this portal. [FEE_NOTE]',
   ARRAY['FIRST_NAME', 'APPLICATION_NO', 'LEGACY_NO', 'PROGRAMME', 'FEE_NOTE', 'SIGN_IN', 'PORTAL_URL', 'UNIVERSITY_NAME', 'UNIVERSITY_SHORT'], 'HIGH'),
  ('PROGRAMME_CHANGED', '[NAME] application moved here by the University',
   'Sent when the University moves an application to [NAME] from the other preliminary programme: the same number, the fee kept, what to complete.',
   'Your application is now for [NAME]',
   E'Dear [FIRST_NAME],\n\nThe University has moved your application [APPLICATION_NO] from [FROM_PROGRAMME] to [NAME]. Your application number stays the same.\n\n[FEE_NOTE]\n\n[NEXT_STEP]\n\nSign in to see it: [PORTAL_URL]\n\n[OFFICE], [UNIVERSITY_NAME]',
   '[UNIVERSITY_SHORT]: your application [APPLICATION_NO] is now for [NAME] (moved from [FROM_PROGRAMME]). Same number. Sign in to see what to complete.',
   'Programme changed', 'Your application [APPLICATION_NO] is now for [NAME]. [FEE_NOTE] [NEXT_STEP]',
   ARRAY['FIRST_NAME', 'APPLICATION_NO', 'FROM_PROGRAMME', 'PROGRAMME', 'FEE_NOTE', 'NEXT_STEP', 'PORTAL_URL', 'UNIVERSITY_NAME', 'UNIVERSITY_SHORT'], 'HIGH'),
  ('OLD_FEE_NOT_VERIFIED', '[NAME] old-portal fee not verified',
   'Sent when the Bursary could not verify the application fee a [NAME] applicant paid on the old portal.',
   'Your old-portal application fee could not be verified',
   E'Dear [FIRST_NAME],\n\nThe Bursary could not verify the application fee you paid on the old portal (reference [REFERENCE]) for your [NAME] application [APPLICATION_NO]:\n\n[NOTE]\n\nPay the application fee on the portal: sign in at [PORTAL_URL]. If you hold proof of the old payment, take it to the Bursary.\n\nBursary, [UNIVERSITY_NAME]',
   '[UNIVERSITY_SHORT]: your old-portal application fee ([REFERENCE]) could not be verified. Pay the fee on the portal, or take your proof to the Bursary.',
   'Old-portal fee not verified', 'The application fee you paid on the old portal ([REFERENCE]) could not be verified: [NOTE] Pay the fee on the portal, or take your proof to the Bursary.',
   ARRAY['FIRST_NAME', 'APPLICATION_NO', 'REFERENCE', 'NOTE', 'PORTAL_URL', 'UNIVERSITY_NAME', 'UNIVERSITY_SHORT'], 'HIGH')
 ) t(event, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, priority)
ON CONFLICT (key) DO NOTHING;

COMMIT;
