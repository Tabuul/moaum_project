-- ═══════════════════════════════════════
-- V675 — old-portal postgraduate applicants migrated: the old application number kept beside the new one, the admitted kept
--        admitted
--
-- The University's master prompt of 27 October 2026 ("PG old portal applicant migration + admitted applicant migration to new
-- portal"): old applicants are migrated, never made to apply again; the old application number is kept as a legacy identifier
-- and this portal gives its own; an applicant admitted on the old portal comes in admitted; no applicant, admission, student or
-- payment twice; the old portal's history traceable for good.
--
-- Nothing rebuilt. A migrated applicant is an admissions.pg_applicant and one admissions.pg_application, numbered by this
-- portal's own series (PG/YY/NNNNNN, platform.next_number('PG_APPLICATION', …)); their state is the application's own
-- (SUBMITTED … OFFERED, ACCEPTED, ADMITTED); a fee is an admissions.pg_fee_reference; admission to the register is
-- admissions.pg_admit; a student already on the register (loaded by the old-portal PG students upload, V203) is linked, never
-- made again. What V675 adds is the migration and its memory:
--
--   · admissions.pg_migration_batch (PG-MIG/YYYY/NNNNNN) and admissions.pg_migration_row: the file as read, row by row, its
--     check (the dry run: what each row would do, and why not) and what the import did. Two kinds: APPLICANTS (not admitted on
--     the old portal) and ADMITTED (admitted there: the admission, the acceptance, the screening, the school fees). Never deleted.
--   · admissions.pg_legacy_application: the old application number (unique, searchable), its source and session, the batch, and
--     what the old portal decided (admission reference and date, acceptance, screening) — beside the application, never in it.
--     A student already on the register keeps it where V203 put it (people.biodata legacy_appno).
--   · admissions.pg_legacy_programme: an old-portal programme mapped by the School to one of this portal's PG programmes, with
--     the reason, reused by every later import; nothing is ever created. admissions.pg_legacy_status: the old portal's words for
--     an application's state, read onto this portal's states (a word not on it is for review, never a guess).
--   · admissions.pg_legacy_fee: a fee paid on the old portal. Verified, an application or acceptance fee is posted as a confirmed
--     admissions.pg_fee_reference under its old reference (channel "Old portal"); not verified, it waits for review — the
--     applicant is not asked to pay it again meanwhile (PG_FEE_UNDER_REVIEW) — and the Bursary or the PG Secretary, not the
--     officer who uploaded it, verifies or rejects it. School fees are never posted here: they are listed for the Bursary's
--     old-portal payments upload, and read as on record once the payment is.
--   · admissions.pg_legacy_document: the old portal's document references; MIGRATION_DOCUMENT_MISSING until the file is attached
--     through the PG documents (admissions.pg_document).
--   · admissions.pg_screening.source: OLD_PORTAL for a screening decided there (historical, completed) beside the portal's own.
--   · Restated: admissions.pg_tell_applicant (silent inside a migration: the migration tells the applicant once, in its own
--     words), admissions.pg_status_checking (an admission decided on the old portal is not paid for again), and
--     admissions.pg_new_fee_reference (no reference while the same fee paid on the old portal is under review).
-- ═══════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V675: old-portal postgraduate applicants migrated, the old application number kept and the admitted kept admitted', true);

-- ── 1 · the batch and its rows ──────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE admissions.pg_migration_batch (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference         text NOT NULL UNIQUE CHECK (reference ~ '^PG-MIG/[0-9]{4}/[0-9]{6}$'),
    kind              text NOT NULL CHECK (kind IN ('APPLICANTS', 'ADMITTED')),
    file_name         text NOT NULL CHECK (length(btrim(file_name)) BETWEEN 1 AND 255),
    file_sha256       text NULL CHECK (file_sha256 IS NULL OR file_sha256 ~ '^[0-9a-f]{64}$'),
    rows_expected     int  NOT NULL CHECK (rows_expected BETWEEN 1 AND 20000),
    rows_staged       int  NOT NULL DEFAULT 0,
    state             text NOT NULL DEFAULT 'STAGING' CHECK (state IN ('STAGING', 'CHECKED', 'IMPORTING', 'COMPLETED', 'ABANDONED')),
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
    CONSTRAINT ck_pgmig_abandoned CHECK (state <> 'ABANDONED' OR (abandoned_at IS NOT NULL AND length(btrim(coalesce(abandoned_reason, ''))) >= 5))
);
CREATE INDEX ix_pgmig_batch_started ON admissions.pg_migration_batch (started_at DESC);
CREATE INDEX ix_pgmig_batch_sha ON admissions.pg_migration_batch (file_sha256) WHERE file_sha256 IS NOT NULL;
SELECT audit.attach('admissions.pg_migration_batch');
COMMENT ON TABLE admissions.pg_migration_batch IS
  'V675: one upload of old-portal postgraduate applicants (APPLICANTS) or admitted applicants (ADMITTED): PG-MIG/YYYY/NNNNNN, the file''s name and SHA-256, who uploaded it, and where it stands (STAGING → CHECKED → IMPORTING → COMPLETED, or ABANDONED with a reason). Never deleted.';

CREATE TABLE admissions.pg_migration_row (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id        uuid NOT NULL REFERENCES admissions.pg_migration_batch (id),
    row_no          int  NOT NULL CHECK (row_no >= 1),
    data            jsonb NOT NULL,
    legacy_no       text NULL,
    applicant       text NULL,
    email           text NULL,
    fee_refs        text[] NOT NULL DEFAULT '{}',
    -- the check (the dry run): what the row would do, and why not
    checked_at      timestamptz NULL,
    verdict         text NULL CHECK (verdict IN ('READY', 'WARNING', 'DUPLICATE_IN_FILE', 'CONFLICT', 'REQUIRES_REVIEW', 'ERROR')),
    match           text NULL CHECK (match IN ('NEW_APPLICANT', 'EXISTING_APPLICANT', 'EXISTING_STUDENT')),
    action          text NULL CHECK (action IN ('CREATE', 'UPDATE', 'RECONCILE', 'LINK_STUDENT')),
    application_id  uuid NULL REFERENCES admissions.pg_application (id) ON DELETE SET NULL,
    student_id      uuid NULL REFERENCES people.student (id) ON DELETE SET NULL,
    programme_code  text NULL,
    session         text NULL,
    target_state    text NULL,
    problems        jsonb NOT NULL DEFAULT '[]',
    -- the School's word on a possible match: a new applicant all the same
    decided_new        boolean NOT NULL DEFAULT false,
    decided_new_by     uuid NULL REFERENCES iam.person (id),
    decided_new_reason text NULL,
    -- the import
    imported_at     timestamptz NULL,
    result          text NULL CHECK (result IN ('CREATED', 'UPDATED', 'RECONCILED', 'LINKED', 'UNCHANGED', 'SKIPPED', 'FAILED')),
    result_note     text NULL,
    CONSTRAINT uq_pgmig_row UNIQUE (batch_id, row_no)
);
CREATE INDEX ix_pgmig_row_legacy ON admissions.pg_migration_row (batch_id, legacy_no);
CREATE INDEX ix_pgmig_row_email ON admissions.pg_migration_row (batch_id, email) WHERE email IS NOT NULL;
CREATE INDEX ix_pgmig_row_refs ON admissions.pg_migration_row USING gin (fee_refs);
CREATE INDEX ix_pgmig_row_verdict ON admissions.pg_migration_row (batch_id, verdict);
CREATE INDEX ix_pgmig_row_legacy_all ON admissions.pg_migration_row (legacy_no) WHERE legacy_no IS NOT NULL;
SELECT audit.exempt('admissions.pg_migration_row',
    'V675: the rows of a migration file as read, their check and their outcome, written only by the batch''s own functions and never deleted (a trigger refuses it); the batch itself, and every record the import writes, are on the spine.');
COMMENT ON TABLE admissions.pg_migration_row IS
  'V675: each row of a migration file: the values read (only the template''s columns kept), the check — verdict READY, WARNING, DUPLICATE_IN_FILE, CONFLICT, REQUIRES_REVIEW or ERROR, the match, the proposed action and every problem with what to correct — and the import''s result. Never deleted; the values are written once.';

-- written once, never deleted: the file as read is what the import did
CREATE OR REPLACE FUNCTION admissions.pg_migration_kept() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF coalesce(current_setting('moaum.maintenance', true), '') = 'on' THEN RETURN OLD; END IF;
        RAISE EXCEPTION 'PGMIG_KEPT: a migration''s history is never deleted' USING ERRCODE = '23514';
    END IF;
    IF TG_TABLE_NAME = 'pg_migration_row' AND NEW.data IS DISTINCT FROM OLD.data
       AND (SELECT b.state FROM admissions.pg_migration_batch b WHERE b.id = NEW.batch_id) <> 'STAGING' THEN
        RAISE EXCEPTION 'PGMIG_KEPT: a row''s values are written once; upload the corrected file as a new batch' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_pgmig_batch_kept BEFORE DELETE ON admissions.pg_migration_batch FOR EACH ROW EXECUTE FUNCTION admissions.pg_migration_kept();
CREATE TRIGGER trg_pgmig_row_kept BEFORE DELETE OR UPDATE ON admissions.pg_migration_row FOR EACH ROW EXECUTE FUNCTION admissions.pg_migration_kept();

-- ── 2 · the old application number, beside the application ──────────────────────────────────────────────────────────────────
CREATE TABLE admissions.pg_legacy_application (
    application_id          uuid PRIMARY KEY REFERENCES admissions.pg_application (id) ON DELETE CASCADE,
    legacy_application_no   text NOT NULL CHECK (length(btrim(legacy_application_no)) BETWEEN 1 AND 60),
    legacy_source           text NOT NULL DEFAULT 'OLD_PORTAL' CHECK (legacy_source IN ('OLD_PORTAL')),
    legacy_session          text NULL,
    batch_id                uuid NOT NULL REFERENCES admissions.pg_migration_batch (id),
    row_id                  uuid NULL REFERENCES admissions.pg_migration_row (id),
    migrated_at             timestamptz NOT NULL DEFAULT now(),
    migrated_by             uuid NULL REFERENCES iam.person (id),
    -- what the old portal decided, as it said it
    admission_session       text NULL,
    admission_reference     text NULL,
    admitted_on             date NULL,
    admission_type          text NULL,
    admission_decision      text NULL,
    decided_on_old_portal   boolean NOT NULL DEFAULT false,
    accepted_on             date NULL,
    screening_decision      text NULL CHECK (screening_decision IN ('CLEARED', 'NOT_CLEARED', 'CORRECTION_REQUIRED', 'PENDING')),
    screened_on             date NULL,
    screening_reference     text NULL,
    screening_remarks       text NULL,
    told_at                 timestamptz NULL
);
CREATE UNIQUE INDEX uq_pg_legacy_application_no ON admissions.pg_legacy_application (upper(btrim(legacy_application_no)));
CREATE INDEX ix_pg_legacy_application_batch ON admissions.pg_legacy_application (batch_id);
SELECT audit.attach('admissions.pg_legacy_application');
COMMENT ON TABLE admissions.pg_legacy_application IS
  'V675: the old portal''s application number of a migrated postgraduate application (unique, searchable beside this portal''s own), its source and session, the batch that brought it, and what the old portal decided (admission, acceptance, screening). The application''s own state stays authoritative.';

-- a student already on the register keeps the old number where the PG students upload (V203) put it: found by it
CREATE INDEX IF NOT EXISTS ix_biodata_legacy_appno ON people.biodata (upper(btrim(value))) WHERE field = 'legacy_appno';
-- a possible same applicant, by phone or by name and date of birth
CREATE INDEX IF NOT EXISTS ix_pg_applicant_phone ON admissions.pg_applicant (phone) WHERE phone IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_pg_applicant_surname_dob ON admissions.pg_applicant (upper(surname), date_of_birth);

-- ── 3 · the old portal's programmes and words, mapped ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_legacy_key(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    -- "M.Sc. Economics", "MSC  ECONOMICS" and "M.Sc (Economics)" are one key
    SELECT nullif(upper(btrim(regexp_replace(regexp_replace(regexp_replace(coalesce(p, ''), '[.''"’]', '', 'g'), '[],([)/&-]', ' ', 'g'), '\s+', ' ', 'g'))), '')
$$;

CREATE TABLE admissions.pg_legacy_programme (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    legacy_key        text NOT NULL,
    legacy_code       text NULL,
    legacy_name       text NOT NULL CHECK (length(btrim(legacy_name)) BETWEEN 1 AND 200),
    programme_code    text NOT NULL REFERENCES ref.programme (code),
    specialisation_id uuid NULL REFERENCES catalogue.programme_specialisation (id),
    state             text NOT NULL DEFAULT 'APPROVED' CHECK (state IN ('APPROVED', 'WITHDRAWN')),
    reason            text NOT NULL CHECK (length(btrim(reason)) >= 5),
    mapped_by         uuid NOT NULL REFERENCES iam.person (id),
    mapped_office     text NOT NULL,
    mapped_at         timestamptz NOT NULL DEFAULT now(),
    withdrawn_by      uuid NULL REFERENCES iam.person (id),
    withdrawn_at      timestamptz NULL,
    withdrawn_reason  text NULL,
    CONSTRAINT ck_pg_legacy_programme_withdrawn CHECK (state <> 'WITHDRAWN' OR (withdrawn_at IS NOT NULL AND length(btrim(coalesce(withdrawn_reason, ''))) >= 5))
);
CREATE UNIQUE INDEX uq_pg_legacy_programme ON admissions.pg_legacy_programme (legacy_key) WHERE state = 'APPROVED';
SELECT audit.attach('admissions.pg_legacy_programme');
COMMENT ON TABLE admissions.pg_legacy_programme IS
  'V675: an old-portal programme (its code or name) mapped by the School of Postgraduate Studies or the Academic Office to one of this portal''s postgraduate programmes, with the reason; every later import reads it. Withdrawn with a reason, never deleted.';
-- a programme merge (V574) carries the mapping to the programme kept
INSERT INTO ref.programme_reference (tab, col, policy, note) VALUES
    ('admissions.pg_legacy_programme', 'programme_code', 'MOVE', 'V675: an old-portal programme mapped to this one follows it to the programme kept')
ON CONFLICT (tab, col) DO NOTHING;

CREATE TABLE admissions.pg_legacy_status (
    word  text PRIMARY KEY CHECK (word = upper(btrim(word)) AND word <> ''),
    state text NOT NULL CHECK (state IN ('SUBMITTED', 'DEPT_RECOMMENDED', 'DEPT_DECLINED', 'FAC_RECOMMENDED', 'FAC_DECLINED', 'OFFERED', 'NOT_OFFERED', 'ACCEPTED')),
    note  text NULL
);
SELECT audit.attach('admissions.pg_legacy_status');
COMMENT ON TABLE admissions.pg_legacy_status IS
  'V675: the old portal''s words for an application''s state, read onto this portal''s states. A word not here is for review, never a guess; WITHDRAWN and CANCELLED have no state on this portal and are not here on purpose.';
INSERT INTO admissions.pg_legacy_status (word, state, note) VALUES
    ('SUBMITTED', 'SUBMITTED', NULL), ('PENDING', 'SUBMITTED', NULL), ('APPLIED', 'SUBMITTED', NULL), ('UNDER REVIEW', 'SUBMITTED', NULL),
    ('IN REVIEW', 'SUBMITTED', NULL), ('PROCESSING', 'SUBMITTED', NULL), ('AWAITING DECISION', 'SUBMITTED', NULL), ('COMPLETED', 'SUBMITTED', 'a completed application form'),
    ('COMPLETE', 'SUBMITTED', 'a completed application form'),
    ('RECOMMENDED', 'DEPT_RECOMMENDED', NULL), ('DEPARTMENT RECOMMENDED', 'DEPT_RECOMMENDED', NULL), ('DEPT RECOMMENDED', 'DEPT_RECOMMENDED', NULL),
    ('NOT RECOMMENDED', 'DEPT_DECLINED', NULL), ('DEPARTMENT NOT RECOMMENDED', 'DEPT_DECLINED', NULL),
    ('FACULTY RECOMMENDED', 'FAC_RECOMMENDED', NULL), ('FACULTY NOT RECOMMENDED', 'FAC_DECLINED', NULL),
    ('ADMITTED', 'OFFERED', 'admitted on the old portal: an offer of admission here'), ('OFFERED', 'OFFERED', NULL), ('OFFER', 'OFFERED', NULL),
    ('OFFER OF ADMISSION', 'OFFERED', NULL), ('ADMISSION OFFERED', 'OFFERED', NULL), ('PROVISIONALLY ADMITTED', 'OFFERED', NULL),
    ('SUCCESSFUL', 'OFFERED', NULL), ('APPROVED', 'OFFERED', NULL),
    ('ACCEPTED', 'ACCEPTED', 'the offer accepted; the acceptance fee is read from its own columns'), ('OFFER ACCEPTED', 'ACCEPTED', NULL),
    ('NOT ADMITTED', 'NOT_OFFERED', NULL), ('NOT OFFERED', 'NOT_OFFERED', NULL), ('REJECTED', 'NOT_OFFERED', NULL), ('DECLINED', 'NOT_OFFERED', NULL),
    ('UNSUCCESSFUL', 'NOT_OFFERED', NULL), ('NOT SUCCESSFUL', 'NOT_OFFERED', NULL), ('DENIED', 'NOT_OFFERED', NULL);

CREATE OR REPLACE FUNCTION admissions.pg_legacy_state(p_word text) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT s.state FROM admissions.pg_legacy_status s WHERE s.word = upper(btrim(regexp_replace(replace(coalesce(p_word, ''), '_', ' '), '\s+', ' ', 'g')))
$$;

-- an application's states in order: a migration moves an application forward, never back
CREATE OR REPLACE FUNCTION admissions.pg_state_rank(p_state text) RETURNS int LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_state WHEN 'DRAFT' THEN 0 WHEN 'SUBMITTED' THEN 1 WHEN 'RETURNED' THEN 1
                        WHEN 'DEPT_RECOMMENDED' THEN 2 WHEN 'DEPT_DECLINED' THEN 2 WHEN 'FAC_RECOMMENDED' THEN 3 WHEN 'FAC_DECLINED' THEN 3
                        WHEN 'OFFERED' THEN 4 WHEN 'NOT_OFFERED' THEN 4 WHEN 'ACCEPTED' THEN 5 WHEN 'ADMITTED' THEN 6 END
$$;

-- ── 4 · fees paid on the old portal, and its documents ──────────────────────────────────────────────────────────────────────
CREATE TABLE admissions.pg_legacy_fee (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id          uuid NOT NULL REFERENCES admissions.pg_migration_batch (id),
    row_id            uuid NULL REFERENCES admissions.pg_migration_row (id),
    application_id    uuid NULL REFERENCES admissions.pg_application (id) ON DELETE CASCADE,
    student_id        uuid NULL REFERENCES people.student (id) ON DELETE CASCADE,
    kind              text NOT NULL CHECK (kind IN ('APPLICATION', 'ACCEPTANCE', 'SCHOOL_FEES')),
    legacy_reference  text NOT NULL CHECK (length(btrim(legacy_reference)) BETWEEN 1 AND 80),
    amount            numeric(12,2) NOT NULL CHECK (amount > 0),
    paid_on           date NULL,
    session           text NULL,
    semester          int NULL CHECK (semester IS NULL OR semester BETWEEN 1 AND 3),
    level             int NULL,
    purpose           text NOT NULL,
    source            text NOT NULL DEFAULT 'OLD_PORTAL' CHECK (source IN ('OLD_PORTAL')),
    stated_status     text NULL,
    state             text NOT NULL CHECK (state IN ('POSTED', 'REQUIRES_REVIEW', 'REJECTED', 'FOR_BURSARY')),
    fee_reference_id  uuid NULL REFERENCES admissions.pg_fee_reference (id) ON DELETE CASCADE,
    decided_by        uuid NULL REFERENCES iam.person (id),
    decided_office    text NULL,
    decided_at        timestamptz NULL,
    decision_note     text NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_pg_legacy_fee_owner CHECK (application_id IS NOT NULL OR student_id IS NOT NULL),
    CONSTRAINT ck_pg_legacy_fee_posted CHECK ((state = 'POSTED') = (fee_reference_id IS NOT NULL)),
    CONSTRAINT ck_pg_legacy_fee_school CHECK ((kind = 'SCHOOL_FEES') = (state = 'FOR_BURSARY')),
    CONSTRAINT ck_pg_legacy_fee_rejected CHECK (state <> 'REJECTED' OR length(btrim(coalesce(decision_note, ''))) >= 5)
);
CREATE UNIQUE INDEX uq_pg_legacy_fee ON admissions.pg_legacy_fee (kind, upper(btrim(legacy_reference))) WHERE state <> 'REJECTED';
CREATE INDEX ix_pg_legacy_fee_app ON admissions.pg_legacy_fee (application_id) WHERE application_id IS NOT NULL;
CREATE INDEX ix_pg_legacy_fee_student ON admissions.pg_legacy_fee (student_id) WHERE student_id IS NOT NULL;
CREATE INDEX ix_pg_legacy_fee_ref ON admissions.pg_legacy_fee (upper(btrim(legacy_reference)));
CREATE INDEX ix_pg_legacy_fee_state ON admissions.pg_legacy_fee (state);
SELECT audit.attach('admissions.pg_legacy_fee');
COMMENT ON TABLE admissions.pg_legacy_fee IS
  'V675: a fee paid on the old portal, as the migration file stated it. An application or acceptance fee verified there is POSTED as a confirmed admissions.pg_fee_reference under its old reference (channel Old portal); one not verified is REQUIRES_REVIEW until the Bursary or the PG Secretary (not the officer who uploaded it) verifies (POSTED) or rejects it with a reason. School fees are FOR_BURSARY: never posted here, loaded through the Bursary''s old-portal payments upload. One old reference, one fee.';

CREATE TABLE admissions.pg_legacy_document (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id         uuid NOT NULL REFERENCES admissions.pg_migration_batch (id),
    row_id           uuid NULL REFERENCES admissions.pg_migration_row (id),
    application_id   uuid NULL REFERENCES admissions.pg_application (id) ON DELETE CASCADE,
    student_id       uuid NULL REFERENCES people.student (id) ON DELETE CASCADE,
    kind             text NOT NULL,
    label            text NOT NULL,
    legacy_ref       text NOT NULL CHECK (length(btrim(legacy_ref)) BETWEEN 1 AND 255),
    document_id      uuid NULL REFERENCES admissions.pg_document (id) ON DELETE SET NULL,
    attached_at      timestamptz NULL,
    attached_by      uuid NULL REFERENCES iam.person (id),
    created_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_pg_legacy_document_owner CHECK (application_id IS NOT NULL OR student_id IS NOT NULL)
);
CREATE UNIQUE INDEX uq_pg_legacy_document ON admissions.pg_legacy_document (coalesce(application_id, student_id), label, upper(btrim(legacy_ref)));
CREATE INDEX ix_pg_legacy_document_app ON admissions.pg_legacy_document (application_id) WHERE application_id IS NOT NULL;
SELECT audit.attach('admissions.pg_legacy_document');
COMMENT ON TABLE admissions.pg_legacy_document IS
  'V675: a document the old portal held for a migrated applicant — its kind, the old document id or file name — MIGRATION_DOCUMENT_MISSING until the file itself is attached to the application (admissions.pg_document, document_id); never shown publicly.';

-- a screening decided on the old portal, apart from the portal's own
ALTER TABLE admissions.pg_screening ADD COLUMN source text NOT NULL DEFAULT 'PORTAL';
ALTER TABLE admissions.pg_screening ADD CONSTRAINT ck_pg_screening_source CHECK (source IN ('PORTAL', 'OLD_PORTAL'));
COMMENT ON COLUMN admissions.pg_screening.source IS
  'V675: OLD_PORTAL for a screening decided on the old portal and migrated (historical, completed); PORTAL for this portal''s own';

-- ── 5 · reading a migration file's values ───────────────────────────────────────────────────────────────────────────────────
-- a value, trimmed and with its spaces single (non-breaking spaces too); NULL when blank
CREATE OR REPLACE FUNCTION admissions.pg_mig_t(p jsonb, k text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT nullif(btrim(regexp_replace(coalesce(p ->> k, ''), '[[:space:] ]+', ' ', 'g')), '')
$$;

-- an academic session, however the old portal wrote it (2025/2026, 2025-2026, 2025/26): YYYY/YYYY, or NULL
CREATE OR REPLACE FUNCTION admissions.pg_legacy_session(p text) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE m text[]; a int; b int;
BEGIN
    m := regexp_match(coalesce(p, ''), '^\s*([0-9]{4})\s*[-/_–— ]\s*([0-9]{2}|[0-9]{4})\s*$');
    IF m IS NULL THEN RETURN NULL; END IF;
    a := m[1]::int;
    b := CASE WHEN length(m[2]) = 2 THEN (a / 100) * 100 + m[2]::int ELSE m[2]::int END;
    IF b <> a + 1 THEN RETURN NULL; END IF;
    RETURN a || '/' || b;
END $$;

-- a session this portal holds: the School's calendar or the University's
CREATE OR REPLACE FUNCTION admissions.pg_session_known(p text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM admissions.pg_academic_session s WHERE s.name = p)
        OR EXISTS (SELECT 1 FROM policy.academic_session s WHERE s.name = p)
$$;

-- a date as a spreadsheet gives it: ISO, day first (as Nigeria writes it), YYYY/MM/DD, "05 Jan 2024", or an Excel serial
CREATE OR REPLACE FUNCTION admissions.pg_mig_date(p text) RETURNS date LANGUAGE plpgsql STABLE AS $$
DECLARE t text := btrim(coalesce(p, '')); m text[]; v date;
BEGIN
    IF t = '' THEN RETURN NULL; END IF;
    BEGIN
        m := regexp_match(t, '^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})([T ].*)?$');
        IF m IS NOT NULL THEN v := make_date(m[1]::int, m[2]::int, m[3]::int);
        ELSE
            m := regexp_match(t, '^([0-9]{1,2})[/.-]([0-9]{1,2})[/.-]([0-9]{4})$');
            IF m IS NOT NULL THEN v := make_date(m[3]::int, m[2]::int, m[1]::int);
            ELSE
                m := regexp_match(t, '^([0-9]{4})/([0-9]{1,2})/([0-9]{1,2})$');
                IF m IS NOT NULL THEN v := make_date(m[1]::int, m[2]::int, m[3]::int);
                ELSIF t ~ '^[0-9]{5}(\.[0-9]+)?$' THEN v := date '1899-12-30' + floor(t::numeric)::int;
                ELSE
                    m := regexp_match(t, '^([0-9]{1,2})[ -]([A-Za-z]{3})[A-Za-z]*[ ,-]+([0-9]{4})$');
                    IF m IS NOT NULL THEN v := to_date(m[1] || ' ' || m[2] || ' ' || m[3], 'DD Mon YYYY'); END IF;
                END IF;
            END IF;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RETURN NULL;
    END;
    IF v IS NULL OR v < date '1940-01-01' OR v > current_date + 1 THEN RETURN NULL; END IF;
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION admissions.pg_mig_amount(p text) RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN t ~ '^[0-9]+(\.[0-9]{1,2})?$' AND t::numeric > 0 AND t::numeric < 100000000 THEN t::numeric END
      FROM (SELECT regexp_replace(regexp_replace(coalesce(p, ''), 'NGN|N(?=[0-9])', '', 'gi'), '[₦,[:space:]]', '', 'g') AS t) x
$$;

CREATE OR REPLACE FUNCTION admissions.pg_mig_phone(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN v ~ '^0[0-9]{10}$' THEN v END
      FROM (SELECT CASE WHEN length(d) = 10 AND left(d, 1) <> '0' THEN '0' || d
                        WHEN length(d) = 13 AND left(d, 3) = '234' THEN '0' || right(d, 10)
                        ELSE d END AS v
              FROM (SELECT regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') AS d) y) x
$$;

-- a fee's standing as the old portal gave it: VERIFIED (posted), CLAIMED (held for review), NONE, or UNKNOWN (a word not read)
CREATE OR REPLACE FUNCTION admissions.pg_mig_paid(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN w IN ('', 'UNPAID', 'NOT PAID', 'NO', 'NONE', 'NIL', 'N/A', 'NA') THEN 'NONE'
        WHEN w IN ('VERIFIED', 'CONFIRMED', 'PAID VERIFIED', 'PAID AND VERIFIED', 'VERIFIED PAID', 'PAID (VERIFIED)', 'PAID - VERIFIED', 'YES VERIFIED') THEN 'VERIFIED'
        WHEN w IN ('PAID', 'SUCCESSFUL', 'SUCCESS', 'COMPLETED', 'YES', 'UNVERIFIED', 'NOT VERIFIED', 'PENDING VERIFICATION',
                   'AWAITING VERIFICATION', 'CLAIMED', 'REQUIRES REVIEW', 'REQUIRES_REVIEW') THEN 'CLAIMED'
        ELSE 'UNKNOWN' END
      FROM (SELECT upper(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g'))) AS w) x
$$;

-- a problem of a row: its code, its weight (duplicate, error, conflict, review, warning), what is wrong and what to do
CREATE OR REPLACE FUNCTION admissions.pg_mig_problem(p_code text, p_level text, p_message text, p_fix text) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
    SELECT jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('code', p_code, 'level', p_level, 'message', p_message, 'fix', p_fix)))
$$;

-- ── 6 · the template's columns: the real postgraduate application, admission, fee and document fields ───────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_migration_columns(p_kind text)
RETURNS TABLE (key text, header text, section text, required boolean, note text)
LANGUAGE sql IMMUTABLE AS $$
    SELECT c.key, c.header, c.section, c.required, c.note FROM (VALUES
      ( 1, 'legacyApplicationNo', 'Old Application Number', 'Identification', true, 'B', 'As the old portal issued it. Kept as the legacy number; this portal gives its own.'),
      ( 2, 'applicationNo', 'New Application Number', 'Identification', false, 'B', 'Only when the applicant already has an application on this portal (PG/YY/NNNNNN).'),
      ( 3, 'matricNo', 'Matriculation Number', 'Identification', false, 'B', 'Only when the old portal issued one: the student on the register is linked, never made again.'),
      ( 4, 'jambNo', 'JAMB Number', 'Identification', false, 'B', 'If any.'),
      ( 5, 'lastName', 'Last Name', 'Identification', true, 'B', 'The surname.'),
      ( 6, 'firstName', 'First Name', 'Identification', true, 'B', NULL),
      ( 7, 'middleName', 'Middle Name', 'Identification', false, 'B', NULL),
      ( 8, 'otherNames', 'Other Names', 'Identification', false, 'B', NULL),
      ( 9, 'gender', 'Gender', 'Identification', false, 'B', 'Male or Female.'),
      (10, 'dateOfBirth', 'Date of Birth', 'Identification', false, 'B', 'DD/MM/YYYY.'),
      (11, 'phone', 'Phone', 'Identification', false, 'B', '11 digits, 080… or +234…'),
      (12, 'email', 'Email', 'Identification', true, 'B', 'The applicant''s sign-in on this portal; needed for a new applicant.'),
      (13, 'nationality', 'Nationality', 'Identification', false, 'B', NULL),
      (14, 'stateOfOrigin', 'State of Origin', 'Identification', false, 'B', NULL),
      (15, 'lga', 'LGA', 'Identification', false, 'B', NULL),
      (16, 'address', 'Contact Address', 'Identification', false, 'B', NULL),
      (20, 'session', 'Application Session', 'PG Application', true, 'B', 'YYYY/YYYY, a session on this portal''s calendar (see Sessions).'),
      (21, 'faculty', 'Faculty', 'PG Application', false, 'B', 'As on the Faculties sheet; checked against the programme.'),
      (22, 'department', 'Department', 'PG Application', false, 'B', 'As on the Departments sheet; checked against the programme.'),
      (23, 'programmeCode', 'Programme Code', 'PG Application', false, 'B', 'This portal''s code (Programmes sheet), or the old portal''s code if it has been mapped.'),
      (24, 'programme', 'Programme', 'PG Application', true, 'B', 'The programme the applicant is placed in now on the old portal (after any approved change), by name.'),
      (25, 'specialisation', 'Specialisation', 'PG Application', false, 'B', 'As on the Specialisations sheet, if the programme has them.'),
      (26, 'applicationStatus', 'Application Status', 'PG Application', false, 'P', 'Submitted, Recommended, Not recommended, Not admitted… (Statuses sheet). Blank reads Submitted.'),
      (27, 'applicationDate', 'Application Date', 'PG Application', false, 'B', 'DD/MM/YYYY.'),
      (28, 'applicationFeeStatus', 'Application Fee Status', 'PG Application', false, 'B', 'Verified (posted as paid), Paid (held for the Bursary to verify) or Unpaid.'),
      (29, 'applicationFeeReference', 'Application Fee Reference', 'PG Application', false, 'B', 'The old payment reference.'),
      (30, 'applicationFeeAmount', 'Application Fee Amount', 'PG Application', false, 'B', 'Naira.'),
      (31, 'applicationFeeDate', 'Application Fee Date', 'PG Application', false, 'B', 'DD/MM/YYYY.'),
      (40, 'firstDegreeInstitution', 'First Degree Institution', 'Academic Qualifications', false, 'B', NULL),
      (41, 'firstDegreeQualification', 'First Degree Qualification', 'Academic Qualifications', false, 'B', 'e.g. B.Sc.'),
      (42, 'firstDegreeProgramme', 'First Degree Programme', 'Academic Qualifications', false, 'B', 'The course studied.'),
      (43, 'firstDegreeClass', 'First Degree Class', 'Academic Qualifications', false, 'B', 'e.g. Second Class (Upper).'),
      (44, 'firstDegreeCgpa', 'First Degree CGPA', 'Academic Qualifications', false, 'B', 'On a 5-point scale.'),
      (45, 'firstDegreeYear', 'Graduation Year', 'Academic Qualifications', false, 'B', 'YYYY.'),
      (46, 'pgQualification', 'PG Qualification', 'Academic Qualifications', false, 'B', 'A postgraduate qualification held, e.g. PGD, M.Sc.'),
      (47, 'pgInstitution', 'PG Institution', 'Academic Qualifications', false, 'B', NULL),
      (48, 'pgYear', 'PG Graduation Year', 'Academic Qualifications', false, 'B', 'YYYY.'),
      (49, 'otherQualifications', 'Other Qualifications', 'Academic Qualifications', false, 'B', NULL),
      (50, 'proposalTitle', 'Research Proposal Title', 'Academic Qualifications', false, 'B', 'For a research programme.'),
      (60, 'docPassport', 'Passport Photograph', 'Documents', false, 'B', 'The old document id or file name; the file itself is attached afterwards.'),
      (61, 'docOlevel', 'O''Level Result', 'Documents', false, 'B', NULL),
      (62, 'docDegreeCertificate', 'Degree Certificate', 'Documents', false, 'B', NULL),
      (63, 'docTranscript', 'Transcript', 'Documents', false, 'B', NULL),
      (64, 'docNysc', 'NYSC Certificate', 'Documents', false, 'B', NULL),
      (65, 'docBirthCertificate', 'Birth Certificate', 'Documents', false, 'B', NULL),
      (66, 'docIndigene', 'Certificate of Origin', 'Documents', false, 'B', 'State/LGA (indigene) certificate.'),
      (67, 'docCv', 'Curriculum Vitae', 'Documents', false, 'B', NULL),
      (68, 'docProposal', 'Research Proposal', 'Documents', false, 'B', NULL),
      (69, 'docAdmissionLetter', 'Admission Letter', 'Documents', false, 'A', NULL),
      (70, 'docOther', 'Other Document', 'Documents', false, 'B', NULL),
      (80, 'admissionSession', 'Admission Session', 'Admission', false, 'A', 'YYYY/YYYY; blank reads the application session.'),
      (81, 'admissionStatus', 'Admission Status', 'Admission', true, 'A', 'Admitted, Offered or Accepted (Statuses sheet).'),
      (82, 'admissionDate', 'Admission Date', 'Admission', false, 'A', 'DD/MM/YYYY.'),
      (83, 'admissionReference', 'Admission Reference', 'Admission', false, 'A', 'The old portal''s admission list or letter reference.'),
      (84, 'admissionType', 'Admission Type', 'Admission', false, 'A', 'As the old portal said it (kept as written).'),
      (85, 'admissionDecision', 'Admission Decision', 'Admission', false, 'A', 'The decision''s words (kept as written).'),
      (90, 'acceptanceStatus', 'Acceptance Status', 'Acceptance', false, 'A', 'Accepted, or blank.'),
      (91, 'acceptanceFeeReference', 'Acceptance Payment Reference', 'Acceptance', false, 'A', NULL),
      (92, 'acceptanceFeeAmount', 'Acceptance Payment Amount', 'Acceptance', false, 'A', 'Naira.'),
      (93, 'acceptanceFeeDate', 'Acceptance Payment Date', 'Acceptance', false, 'A', 'DD/MM/YYYY.'),
      (94, 'acceptanceVerification', 'Acceptance Verification Status', 'Acceptance', false, 'A', 'Verified (posted), or Paid (held for the Bursary to verify).'),
      (100, 'screeningDecision', 'Screening Decision', 'Screening', false, 'A', 'Cleared, Not cleared, Correction required or Pending.'),
      (101, 'screeningDate', 'Screening Date', 'Screening', false, 'A', 'DD/MM/YYYY.'),
      (102, 'screeningReference', 'Screening Reference', 'Screening', false, 'A', NULL),
      (103, 'screeningRemarks', 'Screening Remarks', 'Screening', false, 'A', NULL),
      (110, 'schoolFeesReference', 'School Fees Payment Reference', 'School Fees', false, 'A', 'Listed for the Bursary''s old-portal payments upload; never posted here.'),
      (111, 'schoolFeesAmount', 'School Fees Amount', 'School Fees', false, 'A', 'Naira.'),
      (112, 'schoolFeesDate', 'School Fees Payment Date', 'School Fees', false, 'A', 'DD/MM/YYYY.'),
      (113, 'schoolFeesSession', 'School Fees Session', 'School Fees', false, 'A', 'YYYY/YYYY.'),
      (114, 'schoolFeesSemester', 'School Fees Semester', 'School Fees', false, 'A', 'First, Second, or blank for the session.'),
      (115, 'schoolFeesVerification', 'School Fees Verification Status', 'School Fees', false, 'A', 'As the old portal said it.')
    ) c(n, key, header, section, required, applies, note)
    WHERE c.applies = 'B' OR (c.applies = 'P' AND upper(p_kind) = 'APPLICANTS') OR (c.applies = 'A' AND upper(p_kind) = 'ADMITTED')
    ORDER BY c.n
$$;
COMMENT ON FUNCTION admissions.pg_migration_columns(text) IS
  'V675: the migration template''s columns for APPLICANTS or ADMITTED — the postgraduate applicant, application, qualification, document, admission, acceptance, screening and school-fee fields this portal holds, nothing else. The template is built from it and the upload keeps only these keys.';

-- ── 7 · an old-portal programme to this portal's programme ───────────────────────────────────────────────────────────────────
-- The School's mapping first; else this portal's code; else the name among the running postgraduate programmes. Never an
-- application number, a matriculation number or anything else the programme is not; never created.
CREATE OR REPLACE FUNCTION admissions.pg_legacy_programme_of(p_code text, p_name text, p_dept text, p_faculty text)
RETURNS TABLE (programme_code text, specialisation_id uuid, how text, problem text, detail text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE m admissions.pg_legacy_programme; g ref.programme; n int; v_code text; d ref.department; f ref.faculty;
BEGIN
    -- 1 · mapped by the School
    SELECT * INTO m FROM admissions.pg_legacy_programme x
     WHERE x.state = 'APPROVED' AND x.legacy_key IN (admissions.pg_legacy_key(p_code), admissions.pg_legacy_key(p_name))
     ORDER BY (x.legacy_key = admissions.pg_legacy_key(p_code)) DESC NULLS LAST LIMIT 1;
    IF m.id IS NOT NULL THEN
        RETURN QUERY SELECT m.programme_code, m.specialisation_id, 'MAPPED'::text, NULL::text, NULL::text; RETURN;
    END IF;
    -- 2 · this portal's code
    SELECT * INTO g FROM ref.programme x WHERE upper(x.code) = upper(btrim(coalesce(p_code, ''))) OR (p_code IS NULL AND upper(x.code) = upper(btrim(coalesce(p_name, ''))))
     ORDER BY x.archived, x.code LIMIT 1;
    IF g.code IS NOT NULL THEN
        IF g.category IS DISTINCT FROM 'POST GRADUATE' THEN
            RETURN QUERY SELECT NULL::text, NULL::uuid, 'CODE'::text, 'PROGRAMME_NOT_PG'::text, format('%s (%s) is not a postgraduate programme', g.code, g.name); RETURN;
        ELSIF g.archived THEN
            RETURN QUERY SELECT NULL::text, NULL::uuid, 'CODE'::text, 'PROGRAMME_NOT_RUNNING'::text, format('%s (%s) is no longer run', g.code, g.name); RETURN;
        END IF;
        v_code := g.code;
    ELSE
        -- 3 · the name among the running postgraduate programmes
        SELECT count(*), (array_agg(x.code ORDER BY x.code))[1] INTO n, v_code FROM ref.programme x
         WHERE x.category = 'POST GRADUATE' AND NOT x.archived AND admissions.pg_legacy_key(x.name) = admissions.pg_legacy_key(p_name);
        IF n > 1 THEN
            RETURN QUERY SELECT NULL::text, NULL::uuid, 'NAME'::text, 'PROGRAMME_AMBIGUOUS'::text, format('%s postgraduate programmes are named "%s"', n, p_name); RETURN;
        ELSIF n = 0 OR v_code IS NULL THEN
            RETURN QUERY SELECT NULL::text, NULL::uuid, NULL::text, 'PROGRAMME_NOT_MAPPED'::text, format('"%s" is not a postgraduate programme of this portal', coalesce(p_name, p_code)); RETURN;
        END IF;
        SELECT * INTO g FROM ref.programme x WHERE x.code = v_code;
    END IF;
    -- the department and faculty the file names agree with the programme's
    IF p_dept IS NOT NULL THEN
        SELECT * INTO d FROM ref.department x WHERE x.code = g.dept_code;
        IF admissions.pg_legacy_key(p_dept) NOT IN (coalesce(admissions.pg_legacy_key(d.code), '-'), coalesce(admissions.pg_legacy_key(d.name), '-'))
           AND admissions.pg_legacy_key('DEPARTMENT OF ' || d.name) IS DISTINCT FROM admissions.pg_legacy_key(p_dept) THEN
            RETURN QUERY SELECT v_code, NULL::uuid, 'CODE'::text, 'PLACEMENT_DIFFERS'::text,
                format('%s is in the department of %s; the file says "%s"', g.name, d.name, p_dept); RETURN;
        END IF;
    END IF;
    IF p_faculty IS NOT NULL THEN
        SELECT * INTO f FROM ref.faculty x WHERE x.code = g.faculty_code;
        IF admissions.pg_legacy_key(p_faculty) NOT IN (coalesce(admissions.pg_legacy_key(f.code), '-'), coalesce(admissions.pg_legacy_key(f.name), '-'))
           AND admissions.pg_legacy_key('FACULTY OF ' || f.name) IS DISTINCT FROM admissions.pg_legacy_key(p_faculty) THEN
            RETURN QUERY SELECT v_code, NULL::uuid, 'CODE'::text, 'PLACEMENT_DIFFERS'::text,
                format('%s is in the %s; the file says "%s"', g.name, f.name, p_faculty); RETURN;
        END IF;
    END IF;
    RETURN QUERY SELECT v_code, NULL::uuid, CASE WHEN upper(g.code) = upper(btrim(coalesce(p_code, p_name, ''))) THEN 'CODE' ELSE 'NAME' END, NULL::text, NULL::text;
END $fn$;

-- a fee reference used elsewhere: on another application, another student, or another fee — named, else NULL
CREATE OR REPLACE FUNCTION admissions.pg_mig_fee_clash(p_kind text, p_ref text, p_app uuid, p_student uuid)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT 'the postgraduate fee reference of application ' || a.application_no
           FROM admissions.pg_fee_reference fr JOIN admissions.pg_application a ON a.id = fr.application_id
          WHERE fr.reference IN (btrim(p_ref), upper(btrim(p_ref))) AND (fr.application_id IS DISTINCT FROM p_app OR fr.kind <> p_kind) LIMIT 1),
        (SELECT 'an old-portal ' || lower(replace(x.kind, '_', ' ')) || ' already recorded for '
                || coalesce((SELECT a.application_no FROM admissions.pg_application a WHERE a.id = x.application_id),
                            (SELECT coalesce(s.matric_no, s.admission_no) FROM people.student s WHERE s.id = x.student_id), 'another applicant')
           FROM admissions.pg_legacy_fee x
          WHERE upper(btrim(x.legacy_reference)) = upper(btrim(p_ref)) AND x.state <> 'REJECTED'
            AND (x.kind <> p_kind OR (x.application_id IS DISTINCT FROM p_app AND x.student_id IS DISTINCT FROM p_student)
                 OR (p_app IS NULL AND p_student IS NULL)) LIMIT 1),
        (SELECT 'a school-fees payment of ' || coalesce(s.matric_no, s.admission_no, 'another student')
           FROM finance.payment_reference pr JOIN people.student s ON s.id = pr.student_id
          WHERE p_kind = 'SCHOOL_FEES' AND (pr.reference IN (btrim(p_ref), upper(btrim(p_ref))) OR pr.receipt_no IN (btrim(p_ref), upper(btrim(p_ref))))
            AND pr.confirmed_at IS NOT NULL AND pr.archived_at IS NULL AND pr.student_id IS DISTINCT FROM p_student LIMIT 1))
$$;

-- ── 8 · the check of one row: what it would do, and why not ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_migration_assess(p_row uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE
    r admissions.pg_migration_row; b admissions.pg_migration_batch; d jsonb; probs jsonb := '[]';
    v_legacy text; v_newno text; v_matric text; v_email text; v_email_raw text; v_surname text; v_given text; v_full text;
    v_session text; v_raw text; v_prog text; v_spec uuid; v_how text; v_problem text; v_detail text; v_x text; v_n int;
    v_target text; v_word text; v_accepted boolean := false; v_acc_ok boolean := false; v_screen text; v_dob date; v_phone text;
    v_app uuid; v_app2 uuid; v_app3 uuid; v_student uuid; v_student2 uuid; v_student3 uuid; v_nos text;
    a admissions.pg_application; ap admissions.pg_applicant; st people.student; lg admissions.pg_legacy_application;
    v_match text; v_action text; v_verdict text; v_dup int; v_clash text;
    f record; v_status text; v_ref text; v_amt numeric; v_refs text[] := '{}';
BEGIN
    SELECT * INTO r FROM admissions.pg_migration_row WHERE id = p_row;
    IF r.id IS NULL THEN RAISE EXCEPTION 'no such migration row' USING ERRCODE = '23503'; END IF;
    SELECT * INTO b FROM admissions.pg_migration_batch WHERE id = r.batch_id;
    d := r.data;

    -- the old number: required, and once in the file
    v_legacy := upper(admissions.pg_mig_t(d, 'legacyApplicationNo'));
    IF v_legacy IS NULL THEN
        probs := probs || admissions.pg_mig_problem('LEGACY_NUMBER_MISSING', 'error', 'The old application number is missing.',
                 'Copy it from the old portal: it is how this applicant is found again.');
    ELSIF length(v_legacy) > 60 OR v_legacy !~ '^[A-Z0-9][A-Z0-9/._ -]*$' THEN
        probs := probs || admissions.pg_mig_problem('LEGACY_NUMBER_FORM', 'error', format('"%s" is not an application number.', left(v_legacy, 60)),
                 'Letters, digits and / . _ - only, as the old portal shows it.');
    ELSE
        SELECT min(x.row_no) INTO v_dup FROM admissions.pg_migration_row x
         WHERE x.batch_id = r.batch_id AND x.legacy_no = v_legacy AND x.row_no < r.row_no;
        IF v_dup IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('DUPLICATE_IN_FILE', 'duplicate', format('Row %s has the same old application number.', v_dup),
                     'Keep one row for the applicant; this repeat is not imported.');
        END IF;
    END IF;

    -- the name
    v_surname := admissions.pg_mig_t(d, 'lastName');
    v_given := nullif(btrim(concat_ws(' ', admissions.pg_mig_t(d, 'firstName'), admissions.pg_mig_t(d, 'middleName'), admissions.pg_mig_t(d, 'otherNames'))), '');
    v_full := admissions.pg_mig_t(d, 'fullName');
    IF v_surname IS NULL AND v_given IS NULL AND v_full IS NOT NULL THEN
        IF position(',' IN v_full) > 0 THEN
            v_surname := btrim(split_part(v_full, ',', 1)); v_given := nullif(btrim(substr(v_full, position(',' IN v_full) + 1)), '');
        ELSE
            v_surname := split_part(v_full, ' ', 1); v_given := nullif(btrim(substr(v_full, length(split_part(v_full, ' ', 1)) + 1)), '');
        END IF;
    END IF;
    IF v_surname IS NULL OR v_given IS NULL THEN
        probs := probs || admissions.pg_mig_problem('NAME_MISSING', 'error', 'The last name or the first name is missing.', 'Give both, as on the old portal.');
    ELSIF (v_surname || ' ' || v_given) ~ '[0-9=@<>{}\\;|]' OR v_surname !~ '[[:alpha:]]' OR length(v_surname) > 80 OR length(v_given) > 120 THEN
        probs := probs || admissions.pg_mig_problem('NAME_FORM', 'error', format('"%s, %s" is not a name.', left(v_surname, 40), left(v_given, 40)),
                 'Letters, spaces, hyphens and apostrophes only.');
    END IF;

    -- the email (the sign-in), once in the file
    v_email_raw := lower(admissions.pg_mig_t(d, 'email'));
    IF v_email_raw IS NOT NULL AND (v_email_raw !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' OR length(v_email_raw) > 254) THEN
        probs := probs || admissions.pg_mig_problem('EMAIL_FORM', 'error', format('"%s" is not an email address.', left(v_email_raw, 80)), 'Correct it, or leave it blank for an applicant already on this portal.');
    ELSE
        v_email := v_email_raw;
    END IF;
    IF v_email IS NOT NULL THEN
        SELECT min(x.row_no) INTO v_dup FROM admissions.pg_migration_row x
         WHERE x.batch_id = r.batch_id AND x.email = v_email AND x.row_no < r.row_no AND x.legacy_no IS DISTINCT FROM v_legacy;
        IF v_dup IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('DUPLICATE_EMAIL_IN_FILE', 'duplicate',
                     format('Row %s has the same email for another old application.', v_dup),
                     'One person holds one postgraduate application here: keep the application they are placed in now.');
        END IF;
    END IF;

    -- the rest of the person: read, or left out and said so
    v_x := admissions.pg_mig_t(d, 'gender');
    IF v_x IS NOT NULL AND upper(left(v_x, 1)) NOT IN ('M', 'F') THEN
        probs := probs || admissions.pg_mig_problem('GENDER_UNKNOWN', 'warning', format('Gender "%s" is not read; left blank.', left(v_x, 20)), 'Male or Female.');
    END IF;
    v_x := admissions.pg_mig_t(d, 'dateOfBirth'); v_dob := admissions.pg_mig_date(v_x);
    IF v_x IS NOT NULL AND v_dob IS NULL THEN
        probs := probs || admissions.pg_mig_problem('DATE_OF_BIRTH_FORM', 'warning', format('Date of birth "%s" is not read; left blank.', left(v_x, 20)), 'DD/MM/YYYY.');
    END IF;
    v_x := admissions.pg_mig_t(d, 'phone'); v_phone := admissions.pg_mig_phone(v_x);
    IF v_x IS NOT NULL AND v_phone IS NULL THEN
        probs := probs || admissions.pg_mig_problem('PHONE_FORM', 'warning', format('Phone "%s" is not read; left blank.', left(v_x, 20)), 'Eleven digits, 080…, or +234….');
    END IF;
    FOREACH v_x IN ARRAY ARRAY['applicationDate', 'applicationFeeDate', 'admissionDate', 'acceptanceFeeDate', 'screeningDate', 'schoolFeesDate'] LOOP
        IF admissions.pg_mig_t(d, v_x) IS NOT NULL AND admissions.pg_mig_date(admissions.pg_mig_t(d, v_x)) IS NULL THEN
            probs := probs || admissions.pg_mig_problem('DATE_FORM', 'warning',
                     format('%s "%s" is not read; today stands in for it.', (SELECT c.header FROM admissions.pg_migration_columns(b.kind) c WHERE c.key = v_x), left(admissions.pg_mig_t(d, v_x), 20)),
                     'DD/MM/YYYY.');
        END IF;
    END LOOP;

    -- the session, as this portal holds it
    v_raw := admissions.pg_mig_t(d, 'session');
    v_session := admissions.pg_legacy_session(v_raw);
    IF v_raw IS NULL THEN
        probs := probs || admissions.pg_mig_problem('SESSION_MISSING', 'error', 'The application session is missing.', 'YYYY/YYYY, as on the Sessions sheet.');
    ELSIF v_session IS NULL THEN
        probs := probs || admissions.pg_mig_problem('SESSION_FORM', 'error', format('"%s" is not a session.', left(v_raw, 20)), 'YYYY/YYYY, e.g. 2025/2026.');
    ELSIF NOT admissions.pg_session_known(v_session) THEN
        probs := probs || admissions.pg_mig_problem('SESSION_UNKNOWN', 'error', format('%s is not a session on this portal''s calendar.', v_session),
                 'Use a session on the Sessions sheet; the Academic Office adds a session to the calendar.');
    END IF;
    IF b.kind = 'ADMITTED' AND admissions.pg_mig_t(d, 'admissionSession') IS NOT NULL THEN
        v_x := admissions.pg_legacy_session(admissions.pg_mig_t(d, 'admissionSession'));
        IF v_x IS NULL OR NOT admissions.pg_session_known(v_x) THEN
            probs := probs || admissions.pg_mig_problem('ADMISSION_SESSION_UNKNOWN', 'error',
                     format('Admission session "%s" is not a session on this portal''s calendar.', left(admissions.pg_mig_t(d, 'admissionSession'), 20)),
                     'YYYY/YYYY, as on the Sessions sheet, or blank for the application session.');
        END IF;
    END IF;

    -- the programme the applicant is placed in now: mapped, never guessed, never created
    IF admissions.pg_mig_t(d, 'programme') IS NULL AND admissions.pg_mig_t(d, 'programmeCode') IS NULL THEN
        probs := probs || admissions.pg_mig_problem('PROGRAMME_MISSING', 'error', 'The programme is missing.', 'The programme the applicant is placed in now on the old portal.');
    ELSE
        SELECT x.programme_code, x.specialisation_id, x.how, x.problem, x.detail INTO v_prog, v_spec, v_how, v_problem, v_detail
          FROM admissions.pg_legacy_programme_of(admissions.pg_mig_t(d, 'programmeCode'), admissions.pg_mig_t(d, 'programme'),
                                                 admissions.pg_mig_t(d, 'department'), admissions.pg_mig_t(d, 'faculty')) x;
        IF v_problem IN ('PROGRAMME_NOT_MAPPED', 'PROGRAMME_AMBIGUOUS') THEN
            probs := probs || admissions.pg_mig_problem(v_problem, 'review', 'Programme not found: ' || v_detail || '.',
                     'Map the old programme to this portal''s programme on Programme mapping, then check the file again.');
            v_prog := NULL;
        ELSIF v_problem = 'PLACEMENT_DIFFERS' THEN
            probs := probs || admissions.pg_mig_problem(v_problem, 'conflict', v_detail || '.', 'Correct the faculty or department, or the programme, to the old portal''s current placement.');
        ELSIF v_problem IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem(v_problem, 'error', v_detail || '.', 'Give a postgraduate programme this portal runs, or map the old one.');
            v_prog := NULL;
        END IF;
        v_x := admissions.pg_mig_t(d, 'specialisation');
        IF v_x IS NOT NULL AND v_prog IS NOT NULL THEN
            SELECT ps.id INTO v_spec FROM catalogue.programme_specialisation ps
             WHERE ps.programme_code = v_prog AND ps.active AND (lower(btrim(ps.name)) = lower(v_x) OR upper(ps.code) = upper(v_x)) LIMIT 1;
            IF v_spec IS NULL THEN
                probs := probs || admissions.pg_mig_problem('SPECIALISATION_UNKNOWN', 'warning',
                         format('"%s" is not a specialisation of the programme; left unset.', left(v_x, 60)), 'As on the Specialisations sheet; the School can set it on the application.');
            END IF;
        END IF;
    END IF;

    -- the state the old portal reached, read onto this portal's states
    IF b.kind = 'APPLICANTS' THEN
        v_word := coalesce(admissions.pg_mig_t(d, 'applicationStatus'), 'SUBMITTED');
        v_target := admissions.pg_legacy_state(v_word);
        IF v_target IS NULL THEN
            probs := probs || admissions.pg_mig_problem('STATUS_UNMAPPED', 'review', format('Application status "%s" is not a state this portal knows.', left(v_word, 40)),
                     'Use a status on the Statuses sheet; an application withdrawn or cancelled on the old portal is not migrated as one.');
        ELSIF v_target IN ('OFFERED', 'ACCEPTED') THEN
            probs := probs || admissions.pg_mig_problem('ADMITTED_IN_APPLICANT_FILE', 'error', format('"%s": admitted on the old portal.', left(v_word, 40)),
                     'Upload this applicant with the admitted PG applicants template, which carries the admission.');
        END IF;
    ELSE
        v_word := admissions.pg_mig_t(d, 'admissionStatus');
        v_target := admissions.pg_legacy_state(v_word);
        IF v_word IS NULL THEN
            probs := probs || admissions.pg_mig_problem('ADMISSION_STATUS_MISSING', 'error', 'The admission status is missing.', 'Admitted, Offered or Accepted.');
        ELSIF v_target IS NULL THEN
            probs := probs || admissions.pg_mig_problem('STATUS_UNMAPPED', 'review', format('Admission status "%s" is not a state this portal knows.', left(v_word, 40)),
                     'Use a status on the Statuses sheet.');
        ELSIF v_target NOT IN ('OFFERED', 'ACCEPTED') THEN
            probs := probs || admissions.pg_mig_problem('NOT_ADMITTED_IN_ADMITTED_FILE', 'error', format('"%s": not admitted on the old portal.', left(v_word, 40)),
                     'Upload this applicant with the PG applicant template.');
            v_target := NULL;
        END IF;
        IF v_target IS NOT NULL THEN
            -- the acceptance: taken as paid only on a verified payment with its reference
            v_word := upper(coalesce(admissions.pg_mig_t(d, 'acceptanceStatus'), ''));
            v_accepted := v_target = 'ACCEPTED' OR v_word IN ('ACCEPTED', 'YES', 'DONE', 'COMPLETED', 'PAID', 'OFFER ACCEPTED', 'ACCEPTANCE PAID');
            IF v_word <> '' AND NOT v_accepted AND v_word NOT IN ('NO', 'NOT ACCEPTED', 'PENDING', 'NONE') THEN
                probs := probs || admissions.pg_mig_problem('ACCEPTANCE_WORD', 'warning', format('Acceptance status "%s" is not read.', left(v_word, 30)), 'Accepted, or blank.');
            END IF;
            IF v_accepted THEN
                IF admissions.pg_mig_t(d, 'acceptanceFeeReference') IS NOT NULL AND admissions.pg_mig_amount(admissions.pg_mig_t(d, 'acceptanceFeeAmount')) IS NOT NULL THEN
                    v_acc_ok := admissions.pg_mig_paid(admissions.pg_mig_t(d, 'acceptanceVerification')) = 'VERIFIED';
                    IF NOT v_acc_ok THEN
                        probs := probs || admissions.pg_mig_problem('ACCEPTANCE_UNDER_REVIEW', 'warning',
                                 'The acceptance fee is not verified: it is held for the Bursary or the PG Secretary to verify, and the offer stands until then.',
                                 'Nothing to correct; the applicant is not asked to pay it again meanwhile.');
                    END IF;
                ELSE
                    probs := probs || admissions.pg_mig_problem('ACCEPTANCE_NO_PAYMENT', 'warning',
                             'Accepted on the old portal with no payment reference and amount: the acceptance fee is not taken as paid; the offer stands.',
                             'Give the acceptance payment''s reference and amount, or the School records the acceptance on the application once it has checked.');
                END IF;
            END IF;
            v_target := CASE WHEN v_acc_ok THEN 'ACCEPTED' ELSE 'OFFERED' END;
            -- the screening the old portal recorded: historical, completed
            v_word := upper(regexp_replace(coalesce(admissions.pg_mig_t(d, 'screeningDecision'), ''), '[ -]+', '_', 'g'));
            v_screen := CASE WHEN v_word IN ('CLEARED', 'PASSED', 'SCREENED', 'SUCCESSFUL', 'VERIFIED', 'COMPLETED') THEN 'CLEARED'
                             WHEN v_word IN ('NOT_CLEARED', 'FAILED', 'REJECTED', 'UNSUCCESSFUL') THEN 'NOT_CLEARED'
                             WHEN v_word IN ('CORRECTION_REQUIRED', 'CORRECTION', 'INCOMPLETE') THEN 'CORRECTION_REQUIRED'
                             WHEN v_word IN ('PENDING', 'NOT_SCREENED', 'AWAITING', 'SCHEDULED') THEN 'PENDING' END;
            IF v_word <> '' AND v_screen IS NULL THEN
                probs := probs || admissions.pg_mig_problem('SCREENING_WORD', 'warning', format('Screening decision "%s" is not read.', left(v_word, 30)), 'Cleared, Not cleared, Correction required or Pending.');
            ELSIF v_screen = 'CLEARED' AND v_target = 'ACCEPTED' THEN
                v_target := 'ADMITTED';
            ELSIF v_screen = 'CLEARED' THEN
                probs := probs || admissions.pg_mig_problem('SCREENING_WAITS', 'warning',
                         'Cleared at screening on the old portal: kept, and applied once the acceptance is settled.', NULL);
            END IF;
        END IF;
    END IF;

    -- who this is: the student on the register, the application on this portal, or nobody yet
    v_newno := upper(admissions.pg_mig_t(d, 'applicationNo'));
    IF v_newno IS NOT NULL THEN
        SELECT x.id INTO v_app FROM admissions.pg_application x WHERE x.application_no = v_newno;
        IF v_app IS NULL THEN
            probs := probs || admissions.pg_mig_problem('NEW_NUMBER_UNKNOWN', 'error', format('%s is not an application on this portal.', left(v_newno, 30)),
                     'Leave the new application number blank unless the applicant already has one here.');
        END IF;
    END IF;
    IF v_legacy IS NOT NULL THEN
        SELECT x.application_id INTO v_app2 FROM admissions.pg_legacy_application x WHERE upper(btrim(x.legacy_application_no)) = v_legacy;
    END IF;
    IF v_email IS NOT NULL THEN
        SELECT x.id INTO v_app3 FROM admissions.pg_application x JOIN admissions.pg_applicant p ON p.id = x.applicant_id WHERE lower(p.email) = v_email;
    END IF;
    SELECT count(DISTINCT x.id), string_agg(DISTINCT x.application_no, ', ')
      INTO v_n, v_nos FROM admissions.pg_application x WHERE x.id = ANY (ARRAY[v_app, v_app2, v_app3]);
    IF v_n > 1 THEN
        probs := probs || admissions.pg_mig_problem('IDENTITY_SPLIT', 'conflict',
                 format('The old number, the email and the new number point to different applications here (%s).', v_nos),
                 'Settle which application is this applicant''s before importing the row.');
    END IF;
    v_app := coalesce(v_app, v_app2, v_app3);

    v_matric := upper(admissions.pg_mig_t(d, 'matricNo'));
    IF v_matric IS NOT NULL THEN
        SELECT s.id INTO v_student FROM people.student s WHERE upper(s.matric_no) = v_matric;
        IF v_student IS NULL THEN
            probs := probs || admissions.pg_mig_problem('MATRIC_NOT_ON_RECORD', 'review', format('No student holds matriculation number %s here.', left(v_matric, 40)),
                     'Load the student through Records → Migration → PG students first, then check the file again; a matriculation number is never issued twice.');
        END IF;
    END IF;
    IF v_legacy IS NOT NULL THEN
        SELECT count(*), (array_agg(b2.student_id))[1] INTO v_n, v_student2 FROM people.biodata b2
         WHERE b2.field = 'legacy_appno' AND upper(btrim(b2.value)) = v_legacy;
        IF v_n > 1 THEN
            probs := probs || admissions.pg_mig_problem('LEGACY_ON_SEVERAL_STUDENTS', 'review', format('%s students on the register carry old application number %s.', v_n, v_legacy),
                     'Give the matriculation number of the one this row is.');
            v_student2 := NULL;
        END IF;
    END IF;
    IF v_app IS NOT NULL THEN
        SELECT * INTO a FROM admissions.pg_application WHERE id = v_app;
        v_student3 := a.student_id;
    END IF;
    SELECT count(DISTINCT u) INTO v_n FROM unnest(ARRAY[v_student, v_student2, v_student3]) u WHERE u IS NOT NULL;
    IF v_n > 1 THEN
        probs := probs || admissions.pg_mig_problem('STUDENT_SPLIT', 'conflict',
                 'The matriculation number, the old application number and the application point to different students on the register.',
                 'Settle which student this is before importing the row.');
    END IF;
    v_student := coalesce(v_student, v_student3, v_student2);

    IF v_app IS NOT NULL THEN
        SELECT * INTO ap FROM admissions.pg_applicant WHERE id = a.applicant_id;
        SELECT * INTO lg FROM admissions.pg_legacy_application WHERE application_id = v_app;
        v_match := CASE WHEN a.student_id IS NOT NULL THEN 'EXISTING_STUDENT' ELSE 'EXISTING_APPLICANT' END;
        v_action := 'UPDATE';
        IF lg.application_id IS NOT NULL AND v_legacy IS NOT NULL AND upper(btrim(lg.legacy_application_no)) <> v_legacy THEN
            probs := probs || admissions.pg_mig_problem('LEGACY_NUMBER_DIFFERS', 'conflict',
                     format('Application %s already carries old application number %s.', a.application_no, lg.legacy_application_no),
                     'One application, one old number: check which is right.');
        END IF;
        IF v_surname IS NOT NULL AND admissions.pg_legacy_key(ap.surname) IS DISTINCT FROM admissions.pg_legacy_key(v_surname) THEN
            probs := probs || admissions.pg_mig_problem('NAME_DIFFERS', 'conflict',
                     format('Application %s is in the name of %s, %s.', a.application_no, ap.surname, ap.other_names),
                     'Check that this is the same person; a name is corrected on the application, not by a migration.');
        END IF;
        IF v_prog IS NOT NULL AND a.programme_code <> v_prog THEN
            probs := probs || admissions.pg_mig_problem('PROGRAMME_DIFFERS', 'conflict',
                     format('Application %s is for %s here; the file says %s.', a.application_no, a.programme_code, v_prog),
                     'The application''s programme stands: correct the file, or the application, to the approved current programme.');
        END IF;
        IF v_target IS NOT NULL THEN
            IF (a.state = 'NOT_OFFERED' AND v_target IN ('OFFERED', 'ACCEPTED', 'ADMITTED'))
               OR (a.state IN ('OFFERED', 'ACCEPTED', 'ADMITTED') AND v_target = 'NOT_OFFERED') THEN
                probs := probs || admissions.pg_mig_problem('DECISION_DIFFERS', 'conflict',
                         format('Application %s is %s here; the old portal says %s.', a.application_no, lower(replace(a.state, '_', ' ')), lower(replace(v_target, '_', ' '))),
                         'The two decisions differ: the School settles which stands.');
            ELSIF admissions.pg_state_rank(v_target) > admissions.pg_state_rank(a.state) THEN
                v_action := 'RECONCILE';
            ELSIF admissions.pg_state_rank(v_target) < admissions.pg_state_rank(a.state) THEN
                probs := probs || admissions.pg_mig_problem('PORTAL_FURTHER', 'warning',
                         format('Application %s is further along here (%s): kept, never moved back.', a.application_no, lower(replace(a.state, '_', ' '))), NULL);
            END IF;
        END IF;
        IF a.student_id IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('ALREADY_STUDENT', 'warning',
                     format('Already on the register (%s): linked, not admitted again.', (SELECT coalesce(s.matric_no, s.admission_no) FROM people.student s WHERE s.id = a.student_id)), NULL);
        END IF;
    ELSIF v_student IS NOT NULL THEN
        SELECT * INTO st FROM people.student WHERE id = v_student;
        v_match := 'EXISTING_STUDENT'; v_action := 'LINK_STUDENT';
        IF st.entry_mode IS DISTINCT FROM 'POSTGRADUATE' THEN
            probs := probs || admissions.pg_mig_problem('NOT_PG_STUDENT', 'conflict',
                     format('%s is not a postgraduate student here.', coalesce(st.matric_no, st.admission_no)), 'Check the matriculation number.');
        END IF;
        IF v_prog IS NOT NULL AND st.programme_code <> v_prog THEN
            probs := probs || admissions.pg_mig_problem('PROGRAMME_DIFFERS', 'conflict',
                     format('%s is in %s on the register; the file says %s.', coalesce(st.matric_no, st.admission_no), st.programme_code, v_prog),
                     'The register''s placement stands: if it is wrong, correct it through the programme swap, then check the file again.');
        END IF;
        IF v_surname IS NOT NULL AND admissions.pg_legacy_key(st.surname) IS DISTINCT FROM admissions.pg_legacy_key(v_surname) THEN
            probs := probs || admissions.pg_mig_problem('NAME_DIFFERS', 'conflict',
                     format('%s is in the name of %s, %s.', coalesce(st.matric_no, st.admission_no), st.surname, st.other_names),
                     'Check that this is the same person.');
        END IF;
        SELECT b2.value INTO v_x FROM people.biodata b2 WHERE b2.student_id = st.id AND b2.field = 'legacy_appno';
        IF v_x IS NOT NULL AND v_legacy IS NOT NULL AND upper(btrim(v_x)) <> v_legacy THEN
            probs := probs || admissions.pg_mig_problem('LEGACY_NUMBER_DIFFERS', 'conflict',
                     format('%s already carries old application number %s.', coalesce(st.matric_no, st.admission_no), v_x), 'One student, one old number: check which is right.');
        END IF;
        probs := probs || admissions.pg_mig_problem('ALREADY_STUDENT', 'warning',
                 format('Already on the register (%s): linked, not admitted again.', coalesce(st.matric_no, st.admission_no)), NULL);
    ELSE
        v_match := 'NEW_APPLICANT'; v_action := 'CREATE';
        IF v_email IS NULL AND v_email_raw IS NULL THEN
            probs := probs || admissions.pg_mig_problem('EMAIL_MISSING', 'error', 'A new applicant needs an email: it is their sign-in on this portal.',
                     'Give the email the applicant used on the old portal.');
        END IF;
        -- the same person, perhaps, under another email: never created twice unseen
        IF v_surname IS NOT NULL THEN
            SELECT string_agg(x.application_no, ', ') INTO v_nos FROM (
                SELECT a2.application_no FROM admissions.pg_applicant p JOIN admissions.pg_application a2 ON a2.applicant_id = p.id
                 WHERE (v_phone IS NOT NULL AND p.phone = v_phone AND admissions.pg_legacy_key(p.surname) = admissions.pg_legacy_key(v_surname))
                    OR (v_dob IS NOT NULL AND upper(p.surname) = upper(v_surname) AND p.date_of_birth = v_dob)
                 LIMIT 3) x;
            IF v_nos IS NOT NULL THEN
                probs := probs || admissions.pg_mig_problem('POSSIBLE_SAME_APPLICANT', CASE WHEN r.decided_new THEN 'warning' ELSE 'review' END,
                         format('An applicant of the same surname and %s is on this portal (%s).', CASE WHEN v_phone IS NOT NULL THEN 'phone or birth date' ELSE 'birth date' END, v_nos)
                         || CASE WHEN r.decided_new THEN ' The School confirmed a new applicant: ' || coalesce(r.decided_new_reason, '') ELSE '' END,
                         'Give that application''s number as the new application number if it is the same person; else confirm a new applicant on the row.');
            END IF;
            SELECT string_agg(coalesce(s.matric_no, s.admission_no), ', ') INTO v_nos FROM (
                SELECT s.matric_no, s.admission_no FROM people.student s
                 WHERE s.entry_mode = 'POSTGRADUATE' AND upper(s.surname) = upper(v_surname)
                   AND ((v_dob IS NOT NULL AND s.date_of_birth = v_dob) OR (v_prog IS NOT NULL AND s.programme_code = v_prog
                        AND admissions.pg_legacy_key(s.other_names) = admissions.pg_legacy_key(v_given)))
                 LIMIT 3) s;
            IF v_nos IS NOT NULL THEN
                probs := probs || admissions.pg_mig_problem('POSSIBLE_STUDENT', CASE WHEN r.decided_new THEN 'warning' ELSE 'review' END,
                         format('A postgraduate student of the same name is on the register (%s).', v_nos)
                         || CASE WHEN r.decided_new THEN ' The School confirmed a new applicant: ' || coalesce(r.decided_new_reason, '') ELSE '' END,
                         'Give the matriculation number if it is the same person; else confirm a new applicant on the row.');
            END IF;
        END IF;
    END IF;

    -- the fees: one old reference, one fee
    FOR f IN SELECT * FROM (VALUES
                ('APPLICATION', 'applicationFeeStatus', 'applicationFeeReference', 'applicationFeeAmount', 'Application fee'),
                ('ACCEPTANCE', 'acceptanceVerification', 'acceptanceFeeReference', 'acceptanceFeeAmount', 'Acceptance fee'),
                ('SCHOOL_FEES', 'schoolFeesVerification', 'schoolFeesReference', 'schoolFeesAmount', 'School fees')) x(kind, status_key, ref_key, amount_key, label)
              WHERE x.kind = 'APPLICATION' OR b.kind = 'ADMITTED' LOOP
        v_ref := admissions.pg_mig_t(d, f.ref_key);
        v_amt := admissions.pg_mig_amount(admissions.pg_mig_t(d, f.amount_key));
        v_status := CASE f.kind WHEN 'APPLICATION' THEN admissions.pg_mig_paid(admissions.pg_mig_t(d, f.status_key))
                                WHEN 'ACCEPTANCE' THEN CASE WHEN v_accepted THEN 'ANY' ELSE 'NONE' END
                                ELSE CASE WHEN v_ref IS NOT NULL THEN 'ANY' ELSE 'NONE' END END;
        IF f.kind = 'APPLICATION' AND v_status = 'UNKNOWN' THEN
            probs := probs || admissions.pg_mig_problem('FEE_STATUS_UNKNOWN', 'warning',
                     format('Application fee status "%s" is not read: the fee is not recorded.', left(admissions.pg_mig_t(d, f.status_key), 30)), 'Verified, Paid or Unpaid.');
            CONTINUE;
        END IF;
        CONTINUE WHEN v_status = 'NONE';
        IF v_action = 'LINK_STUDENT' AND f.kind <> 'SCHOOL_FEES' THEN
            probs := probs || admissions.pg_mig_problem('FEE_NOT_FOR_STUDENT', 'warning',
                     f.label || ': a student on the register has no application here to post it to; not recorded.', NULL);
            CONTINUE;
        END IF;
        IF v_ref IS NULL OR v_amt IS NULL THEN
            IF f.kind = 'APPLICATION' AND v_status = 'VERIFIED' THEN
                probs := probs || admissions.pg_mig_problem('FEE_INCOMPLETE', 'error', 'A verified application fee needs its old reference and amount.',
                         'Give both, as the old portal shows them, or mark the fee Paid to hold it for review.');
            ELSIF f.kind <> 'ACCEPTANCE' THEN
                probs := probs || admissions.pg_mig_problem('FEE_INCOMPLETE', 'warning', f.label || ': no reference or amount, so nothing is recorded.', 'Give both to record it.');
            END IF;
            CONTINUE;
        END IF;
        IF upper(btrim(v_ref)) = ANY (v_refs) THEN
            probs := probs || admissions.pg_mig_problem('FEE_REFERENCE_TWICE', 'error', format('%s: reference %s is given for another fee in the same row.', f.label, left(v_ref, 40)),
                     'Each payment has its own reference.');
            CONTINUE;
        END IF;
        v_refs := v_refs || upper(btrim(v_ref));
        -- through the reference's own index (the fence keeps the planner from walking every earlier row of the batch)
        SELECT min(x.row_no) INTO v_dup
          FROM (SELECT x2.row_no, x2.batch_id, x2.legacy_no FROM admissions.pg_migration_row x2 WHERE x2.fee_refs @> ARRAY[upper(btrim(v_ref))] OFFSET 0) x
         WHERE x.batch_id = r.batch_id AND x.row_no < r.row_no AND x.legacy_no IS DISTINCT FROM v_legacy;
        IF v_dup IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('FEE_REFERENCE_IN_FILE', 'conflict', format('%s: reference %s is also on row %s, another applicant.', f.label, left(v_ref, 40), v_dup),
                     'One payment belongs to one applicant: correct the reference.');
            CONTINUE;
        END IF;
        v_clash := admissions.pg_mig_fee_clash(f.kind, v_ref, v_app, v_student);
        IF v_clash IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('FEE_REFERENCE_ELSEWHERE', 'conflict', format('%s: reference %s is %s.', f.label, left(v_ref, 40), v_clash),
                     'A payment is recorded once: the Bursary settles a payment claimed twice through its own reconciliation.');
        ELSIF f.kind = 'APPLICATION' AND v_app IS NOT NULL AND a.fee_confirmed_at IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM admissions.pg_legacy_fee x WHERE x.application_id = v_app AND x.kind = 'APPLICATION' AND upper(btrim(x.legacy_reference)) = upper(btrim(v_ref))) THEN
            probs := probs || admissions.pg_mig_problem('FEE_ALREADY_PAID_HERE', 'warning',
                     'An application fee is already confirmed on this portal: the old payment is held for the Bursary to review, not posted.', NULL);
        ELSIF f.kind = 'APPLICATION' AND v_status = 'CLAIMED' THEN
            probs := probs || admissions.pg_mig_problem('FEE_UNDER_REVIEW', 'warning',
                     'The application fee is not verified: held for the Bursary or the PG Secretary to verify; the applicant is not asked to pay it again meanwhile.', NULL);
        END IF;
    END LOOP;

    v_verdict := CASE WHEN probs @> '[{"level":"duplicate"}]' THEN 'DUPLICATE_IN_FILE'
                      WHEN probs @> '[{"level":"error"}]' THEN 'ERROR'
                      WHEN probs @> '[{"level":"conflict"}]' THEN 'CONFLICT'
                      WHEN probs @> '[{"level":"review"}]' THEN 'REQUIRES_REVIEW'
                      WHEN probs @> '[{"level":"warning"}]' THEN 'WARNING'
                      ELSE 'READY' END;
    RETURN jsonb_build_object('verdict', v_verdict, 'match', v_match, 'action', v_action, 'applicationId', v_app, 'studentId', v_student,
                              'programme', v_prog, 'specialisationId', v_spec, 'session', v_session, 'target', v_target, 'screening', v_screen,
                              'accepted', v_accepted, 'acceptanceVerified', v_acc_ok, 'surname', v_surname, 'givenNames', v_given,
                              'email', v_email, 'phone', v_phone, 'dob', v_dob, 'legacy', v_legacy, 'problems', probs);
END $fn$;
COMMENT ON FUNCTION admissions.pg_migration_assess(uuid) IS
  'V675: the check of one migration row, writing nothing: the verdict (READY, WARNING, DUPLICATE_IN_FILE, ERROR, CONFLICT, REQUIRES_REVIEW), the match (a new applicant, an application on this portal, a student on the register), the action (CREATE, UPDATE, RECONCILE, LINK_STUDENT), the programme and the state this portal would hold, and every problem with what to correct.';

-- ── 9 · the import's steps ──────────────────────────────────────────────────────────────────────────────────────────────────
-- noon in Lagos on a date the old portal gave, else now
CREATE OR REPLACE FUNCTION admissions.pg_mig_at(p date) RETURNS timestamptz LANGUAGE sql STABLE AS $$
    SELECT coalesce((p + time '12:00') AT TIME ZONE 'Africa/Lagos', now())
$$;

-- a fee paid on the old portal posted as paid: a confirmed postgraduate fee reference under its old reference, as the
-- gateway's confirmation does it (an acceptance fee accepts the offer)
CREATE OR REPLACE FUNCTION admissions.pg_mig_post_fee(p_fee uuid) RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE f admissions.pg_legacy_fee; fr admissions.pg_fee_reference; v_ts timestamptz; v_ref uuid;
BEGIN
    SELECT * INTO f FROM admissions.pg_legacy_fee WHERE id = p_fee FOR UPDATE;
    IF f.id IS NULL THEN RAISE EXCEPTION 'no such old-portal fee' USING ERRCODE = '23503'; END IF;
    IF f.state = 'POSTED' THEN RETURN f.fee_reference_id; END IF;
    IF f.kind = 'SCHOOL_FEES' THEN
        RAISE EXCEPTION 'PGMIG_FEE_BURSARY_UPLOAD: school fees paid on the old portal are loaded through the Bursary''s old-portal payments upload' USING ERRCODE = '23514';
    END IF;
    IF f.application_id IS NULL THEN
        RAISE EXCEPTION 'PGMIG_FEE_NO_APPLICATION: an application or acceptance fee is posted to an application' USING ERRCODE = '23514';
    END IF;
    v_ts := admissions.pg_mig_at(f.paid_on);
    SELECT * INTO fr FROM admissions.pg_fee_reference x WHERE x.reference IN (btrim(f.legacy_reference), upper(btrim(f.legacy_reference)));
    IF fr.id IS NOT NULL THEN
        IF fr.application_id <> f.application_id OR fr.kind <> f.kind THEN
            RAISE EXCEPTION 'PGMIG_FEE_ELSEWHERE: reference % is another postgraduate fee''s', f.legacy_reference USING ERRCODE = '23514';
        END IF;
        UPDATE admissions.pg_fee_reference SET confirmed_at = coalesce(confirmed_at, v_ts), channel = coalesce(channel, 'Old portal') WHERE id = fr.id;
        v_ref := fr.id;
    ELSE
        INSERT INTO admissions.pg_fee_reference (application_id, kind, reference, amount, generated_at, expires_at, confirmed_at, channel)
        VALUES (f.application_id, f.kind, btrim(f.legacy_reference), f.amount, v_ts, v_ts, v_ts, 'Old portal')
        RETURNING id INTO v_ref;
    END IF;
    UPDATE admissions.pg_legacy_fee SET state = 'POSTED', fee_reference_id = v_ref WHERE id = p_fee;
    IF f.kind = 'APPLICATION' THEN
        UPDATE admissions.pg_application SET fee_confirmed_at = coalesce(fee_confirmed_at, v_ts) WHERE id = f.application_id;
    ELSE
        UPDATE admissions.pg_application SET acceptance_confirmed_at = coalesce(acceptance_confirmed_at, v_ts) WHERE id = f.application_id;
        UPDATE admissions.pg_application a
           SET state = 'ACCEPTED',
               accepted_at = coalesce(a.accepted_at, (SELECT admissions.pg_mig_at(l.accepted_on) FROM admissions.pg_legacy_application l
                                                       WHERE l.application_id = a.id AND l.accepted_on IS NOT NULL), v_ts)
         WHERE a.id = f.application_id AND a.state = 'OFFERED';
    END IF;
    RETURN v_ref;
END $fn$;

-- an application moved forward to the state the old portal reached (never back): the acceptance comes by its fee and the
-- register by the screening, as on this portal
CREATE OR REPLACE FUNCTION admissions.pg_mig_advance(p_app uuid, p_target text, p_on date, p_note text) RETURNS boolean LANGUAGE plpgsql AS $fn$
DECLARE a admissions.pg_application; v_t text := CASE WHEN p_target IN ('ACCEPTED', 'ADMITTED') THEN 'OFFERED' ELSE p_target END; v_ts timestamptz;
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_app FOR UPDATE;
    IF v_t IS NULL OR admissions.pg_state_rank(v_t) <= admissions.pg_state_rank(a.state) THEN RETURN false; END IF;
    v_ts := admissions.pg_mig_at(p_on);
    IF v_t IN ('DEPT_RECOMMENDED', 'DEPT_DECLINED') THEN
        UPDATE admissions.pg_application SET state = v_t, dept_decided_at = v_ts, dept_note = p_note WHERE id = p_app;
    ELSIF v_t IN ('FAC_RECOMMENDED', 'FAC_DECLINED') THEN
        UPDATE admissions.pg_application SET state = v_t, fac_decided_at = v_ts, fac_note = p_note WHERE id = p_app;
    ELSIF v_t IN ('OFFERED', 'NOT_OFFERED') THEN
        UPDATE admissions.pg_application SET state = v_t, spgs_decided_at = v_ts, spgs_note = p_note WHERE id = p_app;
    ELSIF v_t = 'SUBMITTED' THEN
        UPDATE admissions.pg_application SET state = 'SUBMITTED', submitted_at = coalesce(submitted_at, v_ts) WHERE id = p_app;
    ELSE
        RETURN false;
    END IF;
    RETURN true;
END $fn$;

-- the screening the old portal decided, on an accepted offer: historical and completed; cleared, the applicant is admitted to
-- the register as this portal's screening admits them
CREATE OR REPLACE FUNCTION admissions.pg_mig_screening(p_app uuid) RETURNS boolean LANGUAGE plpgsql AS $fn$
DECLARE a admissions.pg_application; lg admissions.pg_legacy_application;
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_app FOR UPDATE;
    SELECT * INTO lg FROM admissions.pg_legacy_application WHERE application_id = p_app;
    IF a.state <> 'ACCEPTED' OR lg.screening_decision IS NULL OR lg.screening_decision = 'PENDING' THEN RETURN false; END IF;
    IF EXISTS (SELECT 1 FROM admissions.pg_screening sc WHERE sc.application_id = p_app AND sc.state = 'CLEARED') THEN RETURN false; END IF;
    INSERT INTO admissions.pg_screening (application_id, state, remarks, reason, decided_at, source)
    VALUES (p_app, lg.screening_decision,
            concat_ws(' · ', 'Screened on the old portal', 'reference ' || lg.screening_reference, lg.screening_remarks),
            CASE WHEN lg.screening_decision IN ('NOT_CLEARED', 'CORRECTION_REQUIRED') THEN coalesce(lg.screening_remarks, 'Recorded on the old portal') END,
            admissions.pg_mig_at(lg.screened_on), 'OLD_PORTAL')
    ON CONFLICT (application_id) DO UPDATE
       SET state = EXCLUDED.state, remarks = EXCLUDED.remarks, reason = EXCLUDED.reason, decided_at = EXCLUDED.decided_at,
           source = 'OLD_PORTAL', updated_at = now()
     WHERE admissions.pg_screening.state <> 'CLEARED';
    PERFORM admissions.pg_app_event(p_app, 'SCREENING_' || lg.screening_decision,
            CASE lg.screening_decision WHEN 'CLEARED' THEN 'Cleared at physical screening on the old portal'
                                       WHEN 'NOT_CLEARED' THEN 'Not cleared at physical screening on the old portal'
                                       ELSE 'Correction required at physical screening on the old portal' END
            || coalesce(' — ' || lg.screening_remarks, ''));
    IF lg.screening_decision = 'CLEARED' THEN
        PERFORM admissions.pg_admit(p_app);   -- the register, as this portal's screening does it; one student, made once
    END IF;
    RETURN true;
END $fn$;

-- the applicant told once, in the words of where the migration left them; no password, no fee figure
CREATE OR REPLACE FUNCTION admissions.pg_mig_tell(p_app uuid) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE a admissions.pg_application; p admissions.pg_applicant; lg admissions.pg_legacy_application; st people.student;
        v_url text; v_sub text; v_where text; v_body text; v_review boolean;
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_app;
    SELECT * INTO p FROM admissions.pg_applicant WHERE id = a.applicant_id;
    SELECT * INTO lg FROM admissions.pg_legacy_application WHERE application_id = p_app;
    IF a.id IS NULL OR lg.application_id IS NULL THEN RETURN; END IF;
    v_url := coalesce(nullif(platform.portal_url(), ''), 'the University portal');
    v_review := EXISTS (SELECT 1 FROM admissions.pg_legacy_fee x WHERE x.application_id = p_app AND x.state = 'REQUIRES_REVIEW');
    IF a.state = 'ADMITTED' THEN
        SELECT * INTO st FROM people.student WHERE id = a.student_id;
        v_sub := 'Your postgraduate admission is on the new University portal';
        v_where := 'Your admission has been brought to the new portal as it stood: you are on the University register, admission number '
                   || coalesce(st.admission_no, '') || coalesce(', matriculation number ' || st.matric_no, '') || '. Sign in to the student portal at '
                   || v_url || ' with your admission number; if you have not set a password on the new portal, choose "Forgot password" to set one. '
                   || 'Your school fees and course registration are there.';
    ELSIF a.state IN ('OFFERED', 'ACCEPTED') THEN
        v_sub := 'Your postgraduate admission record is on the new University portal';
        v_where := 'Your admission has been brought to the new portal as it stood: '
                   || CASE WHEN a.state = 'ACCEPTED' THEN 'your offer of admission is accepted'
                           WHEN v_review THEN 'your offer of admission stands, and the acceptance fee you paid on the old portal is being verified by the Bursary — you are not asked to pay it again meanwhile'
                           ELSE 'your offer of admission stands; accept it on the applicant portal' END
                   || '. You do not apply or get admitted again.';
    ELSE
        v_sub := 'Your postgraduate application is on the new University portal';
        v_where := 'Your application has been brought to the new portal as it stood; you do not apply again'
                   || CASE WHEN v_review THEN ', and the fee you paid on the old portal is being verified by the Bursary — you are not asked to pay it again meanwhile' ELSE '' END || '.';
    END IF;
    v_body := 'Dear ' || p.other_names || ',' || E'\n\n'
              || 'Your postgraduate application on the University''s old portal (application number ' || lg.legacy_application_no || ') is now on the new portal. '
              || v_where || E'\n\n'
              || 'Your new application number is ' || a.application_no || '; your old number stays on your record and finds it too. '
              || 'Sign in to the applicant portal at ' || v_url || '/pg/portal with your email, ' || p.email
              || '; if you have not set a password on the new portal, choose "Forgot password" to set one.' || E'\n\n'
              || 'School of Postgraduate Studies, Rev. Fr. Moses Orshio Adasu University, Makurdi';
    PERFORM platform.queue_notice('EMAIL', p.email, v_sub, v_body, 'pg_application', p_app, 'pg-migrated:' || p_app, NULL, 'NORMAL');
    PERFORM platform.queue_notice('SMS', p.phone, v_sub,
            'MOAUM PG: your application ' || lg.legacy_application_no || ' is now ' || a.application_no || ' on the new portal. Sign in with your email; use Forgot password to set a password.',
            'pg_application', p_app, 'pg-migrated:' || p_app, NULL, 'NORMAL');
END $fn$;

-- the qualifications a row gives, onto the application (only where it holds none)
CREATE OR REPLACE FUNCTION admissions.pg_mig_qualifications(p_app uuid, d jsonb) RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE n int := 0; v_q text; v_cgpa numeric; v_year int;
BEGIN
    IF EXISTS (SELECT 1 FROM admissions.pg_prior_degree x WHERE x.application_id = p_app) THEN RETURN 0; END IF;
    v_cgpa := CASE WHEN admissions.pg_mig_t(d, 'firstDegreeCgpa') ~ '^[0-5](\.[0-9]{1,2})?$' THEN admissions.pg_mig_t(d, 'firstDegreeCgpa')::numeric END;
    v_year := CASE WHEN admissions.pg_mig_t(d, 'firstDegreeYear') ~ '^(19|20)[0-9]{2}$' THEN admissions.pg_mig_t(d, 'firstDegreeYear')::int END;
    IF coalesce(admissions.pg_mig_t(d, 'firstDegreeInstitution'), admissions.pg_mig_t(d, 'firstDegreeQualification'), admissions.pg_mig_t(d, 'firstDegreeProgramme')) IS NOT NULL THEN
        INSERT INTO admissions.pg_prior_degree (application_id, kind, institution, award, field, class_of_degree, cgpa, year)
        VALUES (p_app, 'FIRST', left(admissions.pg_mig_t(d, 'firstDegreeInstitution'), 200), left(admissions.pg_mig_t(d, 'firstDegreeQualification'), 80),
                left(admissions.pg_mig_t(d, 'firstDegreeProgramme'), 200), left(admissions.pg_mig_t(d, 'firstDegreeClass'), 80), v_cgpa, v_year);
        n := n + 1;
    END IF;
    v_q := admissions.pg_mig_t(d, 'pgQualification');
    IF coalesce(v_q, admissions.pg_mig_t(d, 'pgInstitution')) IS NOT NULL THEN
        INSERT INTO admissions.pg_prior_degree (application_id, kind, institution, award, year)
        VALUES (p_app, CASE WHEN upper(coalesce(v_q, '')) ~ '^(PGD|P\.?G\.?D|POST ?GRAD)' THEN 'PGD'
                            WHEN upper(coalesce(v_q, '')) ~ '^(PHD|PH\.D|DOCTOR)' THEN 'PHD'
                            WHEN upper(coalesce(v_q, '')) ~ '^M' THEN 'MASTERS' ELSE 'OTHER' END,
                left(admissions.pg_mig_t(d, 'pgInstitution'), 200), left(v_q, 80),
                CASE WHEN admissions.pg_mig_t(d, 'pgYear') ~ '^(19|20)[0-9]{2}$' THEN admissions.pg_mig_t(d, 'pgYear')::int END);
        n := n + 1;
    END IF;
    IF admissions.pg_mig_t(d, 'otherQualifications') IS NOT NULL THEN
        INSERT INTO admissions.pg_prior_degree (application_id, kind, award) VALUES (p_app, 'OTHER', left(admissions.pg_mig_t(d, 'otherQualifications'), 200));
        n := n + 1;
    END IF;
    RETURN n;
END $fn$;

-- one row imported: created, updated, reconciled or linked — from a fresh check, so nothing changed since is missed
CREATE OR REPLACE FUNCTION admissions.pg_migration_apply(p_row uuid, p_sealed text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE
    r admissions.pg_migration_row; b admissions.pg_migration_batch; d jsonb; x jsonb; a admissions.pg_application;
    v_app uuid; v_student uuid; v_applicant uuid; v_result text; v_changed boolean := false; v_session text; v_n int;
    v_sex text; v_dob date; v_lg_new boolean; v_note text; v_fee uuid; f record; dk record; v_status text; v_ref text; v_amt numeric;
    v_paid_here boolean; v_target text; v_x text;
BEGIN
    SELECT * INTO r FROM admissions.pg_migration_row WHERE id = p_row;
    SELECT * INTO b FROM admissions.pg_migration_batch WHERE id = r.batch_id;
    d := r.data;
    x := admissions.pg_migration_assess(p_row);
    IF x->>'verdict' NOT IN ('READY', 'WARNING') THEN
        RETURN jsonb_build_object('result', 'SKIPPED', 'assessment', x,
               'note', replace(lower(x->>'verdict'), '_', ' ') || ': ' || coalesce((SELECT e->>'message' FROM jsonb_array_elements(x->'problems') e
                                                                               WHERE e->>'level' <> 'warning' LIMIT 1), ''));
    END IF;
    v_app := (x->>'applicationId')::uuid; v_student := (x->>'studentId')::uuid; v_session := x->>'session'; v_target := x->>'target';
    v_sex := CASE upper(left(coalesce(admissions.pg_mig_t(d, 'gender'), ''), 1)) WHEN 'M' THEN 'M' WHEN 'F' THEN 'F' END;
    v_dob := (x->>'dob')::date;

    IF x->>'action' = 'CREATE' THEN
        IF p_sealed IS NULL OR p_sealed NOT LIKE '$2%$12$%' THEN
            RAISE EXCEPTION 'a new applicant''s sign-in is opened sealed' USING ERRCODE = '23514';
        END IF;
        INSERT INTO admissions.pg_applicant (session, surname, other_names, sex, date_of_birth, state_of_origin, lga, nationality, contact_address,
                                             email, phone, password_hash)
        VALUES (v_session, left(x->>'surname', 80), left(x->>'givenNames', 120), v_sex, v_dob, left(admissions.pg_mig_t(d, 'stateOfOrigin'), 80),
                left(admissions.pg_mig_t(d, 'lga'), 80), left(admissions.pg_mig_t(d, 'nationality'), 80), left(admissions.pg_mig_t(d, 'address'), 300),
                x->>'email', x->>'phone', p_sealed)
        RETURNING id INTO v_applicant;
        -- this portal's own number, from its own series: never the old one, never a counter of rows
        INSERT INTO admissions.pg_application (applicant_id, session, application_no, programme_code, entry_level,
                                               prior_institution, prior_award, prior_class, prior_cgpa, prior_year, proposal_title,
                                               state, submitted_at, specialisation_id)
        VALUES (v_applicant, v_session,
                'PG/' || substr(v_session, 3, 2) || '/' || lpad(platform.next_number('PG_APPLICATION', 'UNIVERSITY', v_session)::text, 6, '0'),
                x->>'programme', admissions.pg_award_level((SELECT g.pg_award FROM ref.programme g WHERE g.code = x->>'programme')),
                left(admissions.pg_mig_t(d, 'firstDegreeInstitution'), 200), left(admissions.pg_mig_t(d, 'firstDegreeQualification'), 80),
                left(admissions.pg_mig_t(d, 'firstDegreeClass'), 80),
                CASE WHEN admissions.pg_mig_t(d, 'firstDegreeCgpa') ~ '^[0-5](\.[0-9]{1,2})?$' THEN admissions.pg_mig_t(d, 'firstDegreeCgpa')::numeric END,
                CASE WHEN admissions.pg_mig_t(d, 'firstDegreeYear') ~ '^(19|20)[0-9]{2}$' THEN admissions.pg_mig_t(d, 'firstDegreeYear')::int END,
                left(admissions.pg_mig_t(d, 'proposalTitle'), 300), 'SUBMITTED',
                admissions.pg_mig_at(admissions.pg_mig_date(admissions.pg_mig_t(d, 'applicationDate'))), (x->>'specialisationId')::uuid)
        RETURNING id INTO v_app;
        PERFORM admissions.pg_mig_qualifications(v_app, d);
        v_result := 'CREATED'; v_changed := true;
    ELSIF x->>'action' IN ('UPDATE', 'RECONCILE') THEN
        SELECT * INTO a FROM admissions.pg_application WHERE id = v_app FOR UPDATE;
        -- what this portal lacks is filled in; what it holds is kept
        UPDATE admissions.pg_applicant p
           SET sex = coalesce(p.sex, v_sex), date_of_birth = coalesce(p.date_of_birth, v_dob),
               state_of_origin = coalesce(p.state_of_origin, left(admissions.pg_mig_t(d, 'stateOfOrigin'), 80)),
               lga = coalesce(p.lga, left(admissions.pg_mig_t(d, 'lga'), 80)), nationality = coalesce(p.nationality, left(admissions.pg_mig_t(d, 'nationality'), 80)),
               contact_address = coalesce(p.contact_address, left(admissions.pg_mig_t(d, 'address'), 300)), phone = coalesce(p.phone, x->>'phone')
         WHERE p.id = a.applicant_id
           AND (p.sex, p.date_of_birth, p.state_of_origin, p.lga, p.nationality, p.contact_address, p.phone)
               IS DISTINCT FROM (coalesce(p.sex, v_sex), coalesce(p.date_of_birth, v_dob), coalesce(p.state_of_origin, left(admissions.pg_mig_t(d, 'stateOfOrigin'), 80)),
                                 coalesce(p.lga, left(admissions.pg_mig_t(d, 'lga'), 80)), coalesce(p.nationality, left(admissions.pg_mig_t(d, 'nationality'), 80)),
                                 coalesce(p.contact_address, left(admissions.pg_mig_t(d, 'address'), 300)), coalesce(p.phone, x->>'phone'));
        GET DIAGNOSTICS v_n = ROW_COUNT; v_changed := v_changed OR v_n > 0;
        UPDATE admissions.pg_application g
           SET prior_institution = coalesce(g.prior_institution, left(admissions.pg_mig_t(d, 'firstDegreeInstitution'), 200)),
               prior_award = coalesce(g.prior_award, left(admissions.pg_mig_t(d, 'firstDegreeQualification'), 80)),
               prior_class = coalesce(g.prior_class, left(admissions.pg_mig_t(d, 'firstDegreeClass'), 80)),
               proposal_title = coalesce(g.proposal_title, left(admissions.pg_mig_t(d, 'proposalTitle'), 300)),
               specialisation_id = coalesce(g.specialisation_id, CASE WHEN g.student_id IS NULL THEN (x->>'specialisationId')::uuid END)
         WHERE g.id = v_app
           AND (g.prior_institution, g.prior_award, g.prior_class, g.proposal_title, g.specialisation_id)
               IS DISTINCT FROM (coalesce(g.prior_institution, left(admissions.pg_mig_t(d, 'firstDegreeInstitution'), 200)),
                                 coalesce(g.prior_award, left(admissions.pg_mig_t(d, 'firstDegreeQualification'), 80)),
                                 coalesce(g.prior_class, left(admissions.pg_mig_t(d, 'firstDegreeClass'), 80)),
                                 coalesce(g.proposal_title, left(admissions.pg_mig_t(d, 'proposalTitle'), 300)),
                                 coalesce(g.specialisation_id, CASE WHEN g.student_id IS NULL THEN (x->>'specialisationId')::uuid END));
        GET DIAGNOSTICS v_n = ROW_COUNT; v_changed := v_changed OR v_n > 0;
        v_changed := admissions.pg_mig_qualifications(v_app, d) > 0 OR v_changed;
        v_result := CASE x->>'action' WHEN 'RECONCILE' THEN 'RECONCILED' ELSE 'UPDATED' END;
    ELSE   -- LINK_STUDENT: the student on the register keeps the old number where the PG students upload keeps it
        INSERT INTO people.biodata (student_id, field, value) VALUES (v_student, 'legacy_appno', x->>'legacy')
        ON CONFLICT (student_id, field) DO NOTHING;
        GET DIAGNOSTICS v_n = ROW_COUNT; v_changed := v_n > 0;
        v_result := 'LINKED';
    END IF;

    -- the old number and what the old portal decided, beside the application
    IF v_app IS NOT NULL THEN
        INSERT INTO admissions.pg_legacy_application (application_id, legacy_application_no, legacy_session, batch_id, row_id, migrated_by,
                admission_session, admission_reference, admitted_on, admission_type, admission_decision, decided_on_old_portal, accepted_on,
                screening_decision, screened_on, screening_reference, screening_remarks)
        VALUES (v_app, x->>'legacy', left(admissions.pg_mig_t(d, 'session'), 30), b.id, r.id, nullif(current_setting('moaum.actor_id', true), '')::uuid,
                CASE WHEN b.kind = 'ADMITTED' THEN coalesce(admissions.pg_legacy_session(admissions.pg_mig_t(d, 'admissionSession')), v_session) END,
                left(admissions.pg_mig_t(d, 'admissionReference'), 120), admissions.pg_mig_date(admissions.pg_mig_t(d, 'admissionDate')),
                left(admissions.pg_mig_t(d, 'admissionType'), 120), left(admissions.pg_mig_t(d, 'admissionDecision'), 300),
                coalesce(v_target IN ('OFFERED', 'NOT_OFFERED', 'ACCEPTED', 'ADMITTED'), false),
                CASE WHEN (x->>'accepted')::boolean THEN admissions.pg_mig_date(admissions.pg_mig_t(d, 'acceptanceFeeDate')) END,
                x->>'screening', admissions.pg_mig_date(admissions.pg_mig_t(d, 'screeningDate')),
                left(admissions.pg_mig_t(d, 'screeningReference'), 120), left(admissions.pg_mig_t(d, 'screeningRemarks'), 500))
        ON CONFLICT (application_id) DO UPDATE SET
            admission_session = coalesce(admissions.pg_legacy_application.admission_session, EXCLUDED.admission_session),
            admission_reference = coalesce(admissions.pg_legacy_application.admission_reference, EXCLUDED.admission_reference),
            admitted_on = coalesce(admissions.pg_legacy_application.admitted_on, EXCLUDED.admitted_on),
            admission_type = coalesce(admissions.pg_legacy_application.admission_type, EXCLUDED.admission_type),
            admission_decision = coalesce(admissions.pg_legacy_application.admission_decision, EXCLUDED.admission_decision),
            decided_on_old_portal = admissions.pg_legacy_application.decided_on_old_portal OR EXCLUDED.decided_on_old_portal,
            accepted_on = coalesce(admissions.pg_legacy_application.accepted_on, EXCLUDED.accepted_on),
            screening_decision = coalesce(admissions.pg_legacy_application.screening_decision, EXCLUDED.screening_decision),
            screened_on = coalesce(admissions.pg_legacy_application.screened_on, EXCLUDED.screened_on),
            screening_reference = coalesce(admissions.pg_legacy_application.screening_reference, EXCLUDED.screening_reference),
            screening_remarks = coalesce(admissions.pg_legacy_application.screening_remarks, EXCLUDED.screening_remarks)
        WHERE (admissions.pg_legacy_application.admission_session, admissions.pg_legacy_application.admission_reference, admissions.pg_legacy_application.admitted_on,
               admissions.pg_legacy_application.admission_type, admissions.pg_legacy_application.admission_decision, admissions.pg_legacy_application.decided_on_old_portal,
               admissions.pg_legacy_application.accepted_on, admissions.pg_legacy_application.screening_decision, admissions.pg_legacy_application.screened_on,
               admissions.pg_legacy_application.screening_reference, admissions.pg_legacy_application.screening_remarks)
              IS DISTINCT FROM
              (coalesce(admissions.pg_legacy_application.admission_session, EXCLUDED.admission_session),
               coalesce(admissions.pg_legacy_application.admission_reference, EXCLUDED.admission_reference),
               coalesce(admissions.pg_legacy_application.admitted_on, EXCLUDED.admitted_on), coalesce(admissions.pg_legacy_application.admission_type, EXCLUDED.admission_type),
               coalesce(admissions.pg_legacy_application.admission_decision, EXCLUDED.admission_decision),
               admissions.pg_legacy_application.decided_on_old_portal OR EXCLUDED.decided_on_old_portal,
               coalesce(admissions.pg_legacy_application.accepted_on, EXCLUDED.accepted_on), coalesce(admissions.pg_legacy_application.screening_decision, EXCLUDED.screening_decision),
               coalesce(admissions.pg_legacy_application.screened_on, EXCLUDED.screened_on), coalesce(admissions.pg_legacy_application.screening_reference, EXCLUDED.screening_reference),
               coalesce(admissions.pg_legacy_application.screening_remarks, EXCLUDED.screening_remarks))
        RETURNING (xmax = 0) INTO v_lg_new;
        IF FOUND THEN v_changed := true; END IF;
        IF coalesce(v_lg_new, false) THEN
            PERFORM admissions.pg_app_event(v_app, 'MIGRATED', format('Brought from the old portal: old application number %s, %s', x->>'legacy', b.reference));
        END IF;
        -- the state the old portal reached: forward only
        IF v_target IS NOT NULL AND x->>'action' IN ('CREATE', 'RECONCILE') THEN
            v_note := concat_ws(' · ', 'On the old portal', 'reference ' || left(admissions.pg_mig_t(d, 'admissionReference'), 120),
                                left(admissions.pg_mig_t(d, 'admissionDecision'), 300));
            IF admissions.pg_mig_advance(v_app, v_target, admissions.pg_mig_date(admissions.pg_mig_t(d, 'admissionDate')), v_note) THEN v_changed := true; END IF;
        END IF;
    END IF;

    -- the application and acceptance fees: posted when verified, else held for review — once each
    IF v_app IS NOT NULL THEN
        FOR f IN SELECT * FROM (VALUES
                    ('APPLICATION', 'applicationFeeStatus', 'applicationFeeReference', 'applicationFeeAmount', 'applicationFeeDate', 'Application fee'),
                    ('ACCEPTANCE', 'acceptanceVerification', 'acceptanceFeeReference', 'acceptanceFeeAmount', 'acceptanceFeeDate', 'Acceptance fee')) y(kind, status_key, ref_key, amount_key, date_key, label)
                  WHERE y.kind = 'APPLICATION' OR b.kind = 'ADMITTED' LOOP
            v_ref := admissions.pg_mig_t(d, f.ref_key); v_amt := admissions.pg_mig_amount(admissions.pg_mig_t(d, f.amount_key));
            CONTINUE WHEN v_ref IS NULL OR v_amt IS NULL;
            IF f.kind = 'APPLICATION' THEN
                v_status := admissions.pg_mig_paid(admissions.pg_mig_t(d, f.status_key));
                CONTINUE WHEN v_status NOT IN ('VERIFIED', 'CLAIMED');
            ELSE
                CONTINUE WHEN NOT (x->>'accepted')::boolean;
                v_status := CASE WHEN admissions.pg_mig_paid(admissions.pg_mig_t(d, f.status_key)) = 'VERIFIED' THEN 'VERIFIED' ELSE 'CLAIMED' END;
            END IF;
            CONTINUE WHEN EXISTS (SELECT 1 FROM admissions.pg_legacy_fee z WHERE z.kind = f.kind AND upper(btrim(z.legacy_reference)) = upper(btrim(v_ref))
                                     AND (z.application_id = v_app OR z.state <> 'REJECTED'));
            SELECT CASE f.kind WHEN 'APPLICATION' THEN g.fee_confirmed_at IS NOT NULL ELSE g.acceptance_confirmed_at IS NOT NULL END INTO v_paid_here
              FROM admissions.pg_application g WHERE g.id = v_app;
            INSERT INTO admissions.pg_legacy_fee (batch_id, row_id, application_id, kind, legacy_reference, amount, paid_on, session, purpose, stated_status, state)
            VALUES (b.id, r.id, v_app, f.kind, btrim(v_ref), v_amt, admissions.pg_mig_date(admissions.pg_mig_t(d, f.date_key)), v_session,
                    f.label || ' paid on the old portal', left(admissions.pg_mig_t(d, f.status_key), 60), 'REQUIRES_REVIEW')
            RETURNING id INTO v_fee;
            v_changed := true;
            -- verified and not already paid here: posted as paid. Already paid here: held, for the Bursary to settle the second payment
            IF v_status = 'VERIFIED' AND NOT coalesce(v_paid_here, false) THEN
                PERFORM admissions.pg_mig_post_fee(v_fee);
            END IF;
        END LOOP;
        -- the screening the old portal decided, once the offer is accepted here
        IF admissions.pg_mig_screening(v_app) THEN v_changed := true; END IF;
        SELECT g.student_id INTO v_x FROM admissions.pg_application g WHERE g.id = v_app;
        v_student := coalesce(v_student, v_x::uuid);
    END IF;

    -- school fees: never posted here; listed for the Bursary's old-portal payments upload
    IF b.kind = 'ADMITTED' THEN
        v_ref := admissions.pg_mig_t(d, 'schoolFeesReference'); v_amt := admissions.pg_mig_amount(admissions.pg_mig_t(d, 'schoolFeesAmount'));
        IF v_ref IS NOT NULL AND v_amt IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM admissions.pg_legacy_fee z WHERE z.kind = 'SCHOOL_FEES' AND upper(btrim(z.legacy_reference)) = upper(btrim(v_ref))) THEN
            INSERT INTO admissions.pg_legacy_fee (batch_id, row_id, application_id, student_id, kind, legacy_reference, amount, paid_on, session, semester,
                                                  purpose, stated_status, state)
            VALUES (b.id, r.id, v_app, v_student, 'SCHOOL_FEES', btrim(v_ref), v_amt, admissions.pg_mig_date(admissions.pg_mig_t(d, 'schoolFeesDate')),
                    coalesce(admissions.pg_legacy_session(admissions.pg_mig_t(d, 'schoolFeesSession')), v_session),
                    CASE WHEN upper(coalesce(admissions.pg_mig_t(d, 'schoolFeesSemester'), '')) ~ '^(1|FIRST|1ST)' THEN 1
                         WHEN upper(coalesce(admissions.pg_mig_t(d, 'schoolFeesSemester'), '')) ~ '^(2|SECOND|2ND)' THEN 2 END,
                    'School fees paid on the old portal', left(admissions.pg_mig_t(d, 'schoolFeesVerification'), 60), 'FOR_BURSARY');
            v_changed := true;
        END IF;
    END IF;

    -- the old portal's documents: references until the files are attached
    FOR dk IN SELECT * FROM (VALUES ('docPassport', 'PASSPORT', 'Passport photograph'), ('docOlevel', 'OLEVEL', 'O''Level result'),
                                    ('docDegreeCertificate', 'DEGREE_CERTIFICATE', 'Degree certificate'), ('docTranscript', 'TRANSCRIPT', 'Transcript'),
                                    ('docNysc', 'NYSC', 'NYSC certificate'), ('docBirthCertificate', 'BIRTH_CERTIFICATE', 'Birth certificate'),
                                    ('docIndigene', 'LGA_CERTIFICATE', 'Certificate of origin'), ('docCv', 'CV', 'Curriculum vitae'),
                                    ('docProposal', 'PROPOSAL', 'Research proposal'), ('docAdmissionLetter', 'OTHER', 'Admission letter'),
                                    ('docOther', 'OTHER', 'Other document')) z(key, kind, label) LOOP
        v_x := admissions.pg_mig_t(d, dk.key);
        CONTINUE WHEN v_x IS NULL;
        INSERT INTO admissions.pg_legacy_document (batch_id, row_id, application_id, student_id, kind, label, legacy_ref)
        VALUES (b.id, r.id, v_app, CASE WHEN v_app IS NULL THEN v_student END, dk.kind, dk.label, left(v_x, 255))
        ON CONFLICT DO NOTHING;
        GET DIAGNOSTICS v_n = ROW_COUNT; v_changed := v_changed OR v_n > 0;
    END LOOP;

    -- told once, if the batch tells
    IF b.notify AND v_app IS NOT NULL AND (SELECT l.told_at FROM admissions.pg_legacy_application l WHERE l.application_id = v_app) IS NULL THEN
        PERFORM admissions.pg_mig_tell(v_app);
        UPDATE admissions.pg_legacy_application SET told_at = now() WHERE application_id = v_app;
    END IF;

    IF v_result IN ('UPDATED', 'RECONCILED', 'LINKED') AND NOT v_changed THEN v_result := 'UNCHANGED'; END IF;
    RETURN jsonb_build_object('result', v_result, 'assessment', x, 'applicationId', v_app,
                              'studentId', coalesce(v_student, (SELECT g.student_id FROM admissions.pg_application g WHERE g.id = v_app)),
                              'note', concat_ws(' · ',
                                  (SELECT 'application ' || g.application_no || ', ' || lower(replace(g.state, '_', ' ')) FROM admissions.pg_application g WHERE g.id = v_app),
                                  (SELECT 'student ' || coalesce(s.matric_no, s.admission_no) FROM people.student s
                                    WHERE s.id = coalesce(v_student, (SELECT g.student_id FROM admissions.pg_application g WHERE g.id = v_app)))));
END $fn$;
COMMENT ON FUNCTION admissions.pg_migration_apply(uuid, text) IS
  'V675: one migration row imported from a fresh check: a new applicant and application (this portal''s number), an application updated or moved forward to the state the old portal reached (never back), or a student on the register linked; the old number beside it; fees posted when verified, else held for review; the old portal''s screening applied (cleared: admitted through admissions.pg_admit); school fees listed for the Bursary; document references; the applicant told once.';

-- ── 10 · the batch: opened, the file staged, checked, imported, finished ─────────────────────────────────────────────────────
-- who migrates: the School of Postgraduate Studies, its Secretary, the Academic Office (and super); a person, never a job
CREATE OR REPLACE FUNCTION admissions.pg_mig_writer() RETURNS uuid LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := coalesce(current_setting('moaum.actor_office', true), '');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PGMIG_ACTOR: a migration is made by a person' USING ERRCODE = '23514'; END IF;
    IF v_office NOT IN ('pgschool', 'pgsecretary', 'academic', 'super') THEN
        RAISE EXCEPTION 'PGMIG_OFFICE: the School of Postgraduate Studies, its Secretary or the Academic Office migrates old-portal applicants, not %', v_office USING ERRCODE = '42501';
    END IF;
    RETURN v_actor;
END $fn$;

CREATE OR REPLACE FUNCTION admissions.pg_migration_summary(p_batch uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'id', b.id, 'reference', b.reference, 'kind', b.kind, 'state', b.state, 'fileName', b.file_name, 'fileSha256', b.file_sha256,
        'rowsExpected', b.rows_expected, 'rowsStaged', b.rows_staged, 'notify', b.notify,
        'startedAt', b.started_at, 'startedOffice', b.started_office,
        'startedBy', (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = b.started_by),
        'checkedAt', b.checked_at, 'importStartedAt', b.import_started_at, 'completedAt', b.completed_at, 'abandonedAt', b.abandoned_at, 'abandonedReason', b.abandoned_reason,
        'checked', count(r.id) FILTER (WHERE r.checked_at IS NOT NULL),
        'ready', count(r.id) FILTER (WHERE r.verdict = 'READY'), 'warnings', count(r.id) FILTER (WHERE r.verdict = 'WARNING'),
        'duplicates', count(r.id) FILTER (WHERE r.verdict = 'DUPLICATE_IN_FILE'), 'conflicts', count(r.id) FILTER (WHERE r.verdict = 'CONFLICT'),
        'review', count(r.id) FILTER (WHERE r.verdict = 'REQUIRES_REVIEW'), 'errors', count(r.id) FILTER (WHERE r.verdict = 'ERROR'),
        'newApplicants', count(r.id) FILTER (WHERE r.match = 'NEW_APPLICANT'),
        'existingApplicants', count(r.id) FILTER (WHERE r.match = 'EXISTING_APPLICANT'),
        'alreadyStudents', count(r.id) FILTER (WHERE r.match = 'EXISTING_STUDENT'),
        'admitted', count(r.id) FILTER (WHERE r.target_state IN ('OFFERED', 'ACCEPTED', 'ADMITTED')),
        'creates', count(r.id) FILTER (WHERE r.action = 'CREATE' AND r.verdict IN ('READY', 'WARNING')),
        'updates', count(r.id) FILTER (WHERE r.action = 'UPDATE' AND r.verdict IN ('READY', 'WARNING')),
        'reconciles', count(r.id) FILTER (WHERE r.action = 'RECONCILE' AND r.verdict IN ('READY', 'WARNING')),
        'links', count(r.id) FILTER (WHERE r.action = 'LINK_STUDENT' AND r.verdict IN ('READY', 'WARNING')),
        'programmesNotMapped', count(r.id) FILTER (WHERE r.problems @> '[{"code":"PROGRAMME_NOT_MAPPED"}]' OR r.problems @> '[{"code":"PROGRAMME_AMBIGUOUS"}]'),
        'missingData', count(r.id) FILTER (WHERE EXISTS (SELECT 1 FROM jsonb_array_elements(r.problems) e WHERE e->>'code' LIKE '%\_MISSING' ESCAPE '\')),
        'proposedFees', coalesce(sum(((r.data ? 'applicationFeeReference')::int + (r.data ? 'acceptanceFeeReference')::int + (r.data ? 'schoolFeesReference')::int))
                                      FILTER (WHERE r.verdict IN ('READY', 'WARNING')), 0),
        'proposedDocuments', coalesce(sum((SELECT count(*) FROM jsonb_object_keys(r.data) k WHERE k LIKE 'doc%')) FILTER (WHERE r.verdict IN ('READY', 'WARNING')), 0),
        'readyToImport', count(r.id) FILTER (WHERE r.verdict IN ('READY', 'WARNING') AND r.result IS NULL),
        'imported', count(r.id) FILTER (WHERE r.result IS NOT NULL),
        'created', count(r.id) FILTER (WHERE r.result = 'CREATED'), 'updated', count(r.id) FILTER (WHERE r.result = 'UPDATED'),
        'reconciled', count(r.id) FILTER (WHERE r.result = 'RECONCILED'), 'linked', count(r.id) FILTER (WHERE r.result = 'LINKED'),
        'unchanged', count(r.id) FILTER (WHERE r.result = 'UNCHANGED'), 'skipped', count(r.id) FILTER (WHERE r.result = 'SKIPPED'),
        'failed', count(r.id) FILTER (WHERE r.result = 'FAILED'),
        'feesPosted', (SELECT count(*) FROM admissions.pg_legacy_fee x WHERE x.batch_id = b.id AND x.state = 'POSTED'),
        'feesUnderReview', (SELECT count(*) FROM admissions.pg_legacy_fee x WHERE x.batch_id = b.id AND x.state = 'REQUIRES_REVIEW'),
        'feesForBursary', (SELECT count(*) FROM admissions.pg_legacy_fee x WHERE x.batch_id = b.id AND x.state = 'FOR_BURSARY'),
        'documents', (SELECT count(*) FROM admissions.pg_legacy_document x WHERE x.batch_id = b.id),
        'documentsMissing', (SELECT count(*) FROM admissions.pg_legacy_document x WHERE x.batch_id = b.id AND x.document_id IS NULL))
      FROM admissions.pg_migration_batch b LEFT JOIN admissions.pg_migration_row r ON r.batch_id = b.id
     WHERE b.id = p_batch
     GROUP BY b.id
$$;

CREATE OR REPLACE FUNCTION admissions.pg_migration_open(p_kind text, p_file text, p_sha text, p_rows int, p_notify boolean)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := admissions.pg_mig_writer(); v_kind text := upper(btrim(coalesce(p_kind, ''))); v_file text; v_year text; v_id uuid; v_seen text;
BEGIN
    IF v_kind NOT IN ('APPLICANTS', 'ADMITTED') THEN
        RAISE EXCEPTION 'PGMIG_KIND: a migration is of PG applicants or of admitted PG applicants' USING ERRCODE = '23514';
    END IF;
    v_file := btrim(regexp_replace(coalesce(p_file, ''), '^.*[\\/]', ''));
    IF v_file !~* '\.xlsx$' OR length(v_file) > 255 THEN
        RAISE EXCEPTION 'PGMIG_FILE_TYPE: a migration file is an Excel workbook (.xlsx) made from the template' USING ERRCODE = '23514';
    END IF;
    IF p_sha IS NOT NULL AND lower(p_sha) !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'PGMIG_CHECKSUM: the file''s checksum did not arrive intact' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR p_rows < 1 OR p_rows > 20000 THEN
        RAISE EXCEPTION 'PGMIG_ROWS: a migration file holds 1 to 20,000 rows (this one %); split a larger one', coalesce(p_rows, 0) USING ERRCODE = '23514';
    END IF;
    v_year := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY');
    INSERT INTO admissions.pg_migration_batch (reference, kind, file_name, file_sha256, rows_expected, notify, started_by, started_office)
    VALUES ('PG-MIG/' || v_year || '/' || lpad(platform.next_number('PG_MIGRATION', 'UNIVERSITY', v_year)::text, 6, '0'),
            v_kind, v_file, lower(p_sha), p_rows, coalesce(p_notify, true), v_actor, current_setting('moaum.actor_office', true))
    RETURNING id INTO v_id;
    -- the same file imported before: importing it again changes nothing already on record, and says so
    SELECT string_agg(x.reference, ', ' ORDER BY x.started_at) INTO v_seen FROM admissions.pg_migration_batch x
     WHERE x.file_sha256 = lower(p_sha) AND x.id <> v_id AND x.state = 'COMPLETED';
    RETURN admissions.pg_migration_summary(v_id) || jsonb_build_object('importedBefore', v_seen);
END $fn$;

CREATE OR REPLACE FUNCTION admissions.pg_migration_stage(p_batch uuid, p_first int, p_rows jsonb) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE b admissions.pg_migration_batch; v_keys text[]; i int; n int; o jsonb; c jsonb; v_email text;
BEGIN
    PERFORM admissions.pg_mig_writer();
    SELECT * INTO b FROM admissions.pg_migration_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such migration batch' USING ERRCODE = '23503'; END IF;
    IF b.state <> 'STAGING' THEN
        RAISE EXCEPTION 'PGMIG_STAGED: the file of % is already in; upload a corrected file as a new batch', b.reference USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 1000 THEN
        RAISE EXCEPTION 'PGMIG_CHUNK: rows arrive 1 to 1,000 at a time' USING ERRCODE = '23514';
    END IF;
    n := jsonb_array_length(p_rows);
    IF p_first IS NULL OR p_first < 1 OR p_first + n - 1 > b.rows_expected THEN
        RAISE EXCEPTION 'PGMIG_ROWS_BEYOND: rows % to % are beyond the % the file was opened with', p_first, p_first + n - 1, b.rows_expected USING ERRCODE = '23514';
    END IF;
    v_keys := ARRAY(SELECT c2.key FROM admissions.pg_migration_columns(b.kind) c2) || ARRAY['fullName', 'sheetRow'];   -- the sheet's own row number, for the report
    FOR i IN 0 .. n - 1 LOOP
        o := p_rows -> i;
        IF jsonb_typeof(o) <> 'object' THEN
            RAISE EXCEPTION 'PGMIG_ROW_SHAPE: row % is not a row of the template', p_first + i USING ERRCODE = '23514';
        END IF;
        -- only the template's columns, as text, without control characters, at most 1,000 characters each
        SELECT coalesce(jsonb_object_agg(e.k, left(btrim(regexp_replace(e.v, '[[:cntrl:]]+', ' ', 'g')), 1000)), '{}') INTO c
          FROM jsonb_each_text(o) e(k, v) WHERE e.k = ANY (v_keys) AND btrim(coalesce(e.v, '')) <> '';
        v_email := lower(admissions.pg_mig_t(c, 'email'));
        IF v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN v_email := NULL; END IF;
        INSERT INTO admissions.pg_migration_row (batch_id, row_no, data, legacy_no, applicant, email, fee_refs)
        VALUES (b.id, p_first + i, c, upper(admissions.pg_mig_t(c, 'legacyApplicationNo')),
                left(nullif(concat_ws(', ', admissions.pg_mig_t(c, 'lastName'),
                                      nullif(concat_ws(' ', admissions.pg_mig_t(c, 'firstName'), admissions.pg_mig_t(c, 'middleName'), admissions.pg_mig_t(c, 'otherNames')), '')), ''), 200),
                v_email,
                ARRAY(SELECT upper(btrim(v)) FROM unnest(ARRAY[admissions.pg_mig_t(c, 'applicationFeeReference'), admissions.pg_mig_t(c, 'acceptanceFeeReference'),
                                                              admissions.pg_mig_t(c, 'schoolFeesReference')]) v WHERE v IS NOT NULL))
        ON CONFLICT (batch_id, row_no) DO UPDATE
           SET data = EXCLUDED.data, legacy_no = EXCLUDED.legacy_no, applicant = EXCLUDED.applicant, email = EXCLUDED.email, fee_refs = EXCLUDED.fee_refs;
    END LOOP;
    UPDATE admissions.pg_migration_batch SET rows_staged = (SELECT count(*) FROM admissions.pg_migration_row r WHERE r.batch_id = b.id) WHERE id = b.id;
    RETURN jsonb_build_object('staged', (SELECT rows_staged FROM admissions.pg_migration_batch WHERE id = b.id), 'expected', b.rows_expected);
END $fn$;

-- the dry run: every check, nothing written but the rows' own verdicts
CREATE OR REPLACE FUNCTION admissions.pg_migration_check(p_batch uuid, p_from int, p_to int) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE b admissions.pg_migration_batch; r record; x jsonb;
BEGIN
    PERFORM admissions.pg_mig_writer();
    SELECT * INTO b FROM admissions.pg_migration_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such migration batch' USING ERRCODE = '23503'; END IF;
    IF b.state NOT IN ('STAGING', 'CHECKED') THEN
        RAISE EXCEPTION 'PGMIG_CHECK_CLOSED: % is %; once the import begins each row is checked again as it is imported', b.reference, lower(b.state) USING ERRCODE = '23514';
    END IF;
    IF b.rows_staged < b.rows_expected THEN
        RAISE EXCEPTION 'PGMIG_NOT_ALL_STAGED: % of % rows have arrived; send the rest before the check', b.rows_staged, b.rows_expected USING ERRCODE = '23514';
    END IF;
    IF p_to - p_from + 1 > 2000 THEN RAISE EXCEPTION 'PGMIG_CHUNK: rows are checked up to 2,000 at a time' USING ERRCODE = '23514'; END IF;
    -- a file just in: the planner learns the rows' numbers once, so each lookup of an earlier row stays on its index
    IF b.state = 'STAGING' AND p_from = 1 THEN ANALYZE admissions.pg_migration_row; END IF;
    FOR r IN SELECT x2.id FROM admissions.pg_migration_row x2 WHERE x2.batch_id = b.id AND x2.row_no BETWEEN p_from AND p_to ORDER BY x2.row_no LOOP
        x := admissions.pg_migration_assess(r.id);
        UPDATE admissions.pg_migration_row
           SET checked_at = now(), verdict = x->>'verdict', match = x->>'match', action = x->>'action',
               application_id = (x->>'applicationId')::uuid, student_id = (x->>'studentId')::uuid, programme_code = x->>'programme',
               session = x->>'session', target_state = x->>'target', problems = x->'problems'
         WHERE id = r.id;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM admissions.pg_migration_row x2 WHERE x2.batch_id = b.id AND x2.checked_at IS NULL) THEN
        UPDATE admissions.pg_migration_batch SET state = 'CHECKED', checked_at = now() WHERE id = b.id;
    END IF;
    RETURN admissions.pg_migration_summary(b.id);
END $fn$;

CREATE OR REPLACE FUNCTION admissions.pg_migration_import(p_batch uuid, p_from int, p_to int) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE b admissions.pg_migration_batch; r record; res jsonb; v_sealed text; n int := 0; v_mine boolean;
BEGIN
    PERFORM admissions.pg_mig_writer();
    SELECT * INTO b FROM admissions.pg_migration_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such migration batch' USING ERRCODE = '23503'; END IF;
    IF b.state IN ('COMPLETED', 'ABANDONED') THEN
        RAISE EXCEPTION 'PGMIG_CLOSED: % is %', b.reference, lower(b.state) USING ERRCODE = '23514';
    END IF;
    IF b.state = 'STAGING' OR EXISTS (SELECT 1 FROM admissions.pg_migration_row x WHERE x.batch_id = b.id AND x.checked_at IS NULL) THEN
        RAISE EXCEPTION 'PGMIG_NOT_CHECKED: check the whole file (the dry run) before it is imported' USING ERRCODE = '23514';
    END IF;
    IF p_to - p_from + 1 > 1000 THEN RAISE EXCEPTION 'PGMIG_CHUNK: rows are imported up to 1,000 at a time' USING ERRCODE = '23514'; END IF;
    UPDATE admissions.pg_migration_batch SET state = 'IMPORTING', import_started_at = coalesce(import_started_at, now()) WHERE id = b.id;
    -- inside a migration the pipeline's own notices are silent; the migration tells each applicant once
    PERFORM set_config('moaum.pg_migration', b.reference, true);
    v_mine := people.defer_positions();   -- the students admitted in the chunk refreshed once, together (V463)
    IF EXISTS (SELECT 1 FROM admissions.pg_migration_row x WHERE x.batch_id = b.id AND x.row_no BETWEEN p_from AND p_to AND x.result IS NULL) THEN
        -- a new applicant's sign-in is sealed: a cost-12 hash of a secret nobody holds, one for the chunk; they set their own by "Forgot password"
        v_sealed := crypt(gen_random_uuid()::text, gen_salt('bf', 12));
    END IF;
    FOR r IN SELECT x.id FROM admissions.pg_migration_row x
              WHERE x.batch_id = b.id AND x.row_no BETWEEN p_from AND p_to AND x.result IS NULL ORDER BY x.row_no LOOP
        BEGIN
            res := admissions.pg_migration_apply(r.id, v_sealed);
            UPDATE admissions.pg_migration_row
               SET imported_at = now(), result = res->>'result', result_note = left(res->>'note', 500),
                   checked_at = now(), verdict = res->'assessment'->>'verdict', match = res->'assessment'->>'match', action = res->'assessment'->>'action',
                   application_id = coalesce((res->>'applicationId')::uuid, (res->'assessment'->>'applicationId')::uuid),
                   student_id = coalesce((res->>'studentId')::uuid, (res->'assessment'->>'studentId')::uuid),
                   programme_code = res->'assessment'->>'programme', session = res->'assessment'->>'session',
                   target_state = res->'assessment'->>'target', problems = res->'assessment'->'problems'
             WHERE id = r.id;
        EXCEPTION WHEN OTHERS THEN
            -- the row's writes are undone; the rest go on, and the row says why
            UPDATE admissions.pg_migration_row SET imported_at = now(), result = 'FAILED', result_note = left(SQLERRM, 500) WHERE id = r.id;
        END;
        n := n + 1;
    END LOOP;
    IF v_mine THEN PERFORM people.refresh_deferred_positions(); END IF;
    PERFORM set_config('moaum.pg_migration', '', true);
    RETURN admissions.pg_migration_summary(b.id) || jsonb_build_object('processed', n);
END $fn$;

CREATE OR REPLACE FUNCTION admissions.pg_migration_finish(p_batch uuid) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := admissions.pg_mig_writer(); b admissions.pg_migration_batch; n int;
BEGIN
    SELECT * INTO b FROM admissions.pg_migration_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such migration batch' USING ERRCODE = '23503'; END IF;
    IF b.state NOT IN ('IMPORTING', 'CHECKED') THEN
        RAISE EXCEPTION 'PGMIG_CLOSED: % is %', b.reference, lower(b.state) USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO n FROM admissions.pg_migration_row x WHERE x.batch_id = b.id AND x.result IS NULL;
    IF n > 0 THEN RAISE EXCEPTION 'PGMIG_NOT_ALL_IMPORTED: % rows wait to be imported', n USING ERRCODE = '23514'; END IF;
    UPDATE admissions.pg_migration_batch SET state = 'COMPLETED', completed_at = now(), completed_by = v_actor WHERE id = b.id;
    RETURN admissions.pg_migration_summary(b.id);
END $fn$;

CREATE OR REPLACE FUNCTION admissions.pg_migration_abandon(p_batch uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := admissions.pg_mig_writer(); b admissions.pg_migration_batch;
BEGIN
    SELECT * INTO b FROM admissions.pg_migration_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such migration batch' USING ERRCODE = '23503'; END IF;
    IF b.state IN ('COMPLETED', 'ABANDONED') THEN RAISE EXCEPTION 'PGMIG_CLOSED: % is %', b.reference, lower(b.state) USING ERRCODE = '23514'; END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'PGMIG_REASON: say why the upload is set aside' USING ERRCODE = '23514'; END IF;
    -- set aside, never deleted: what was imported stays imported, the rest is never imported from this batch
    UPDATE admissions.pg_migration_batch SET state = 'ABANDONED', abandoned_at = now(), abandoned_by = v_actor, abandoned_reason = btrim(p_reason) WHERE id = b.id;
    RETURN admissions.pg_migration_summary(b.id);
END $fn$;

-- the School's word on a possible same person: a new applicant all the same, with its reason
CREATE OR REPLACE FUNCTION admissions.pg_migration_row_new(p_row uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := admissions.pg_mig_writer(); r admissions.pg_migration_row; b admissions.pg_migration_batch; x jsonb;
BEGIN
    SELECT * INTO r FROM admissions.pg_migration_row WHERE id = p_row FOR UPDATE;
    IF r.id IS NULL THEN RAISE EXCEPTION 'no such migration row' USING ERRCODE = '23503'; END IF;
    SELECT * INTO b FROM admissions.pg_migration_batch WHERE id = r.batch_id;
    IF b.state NOT IN ('CHECKED', 'IMPORTING') OR r.result IS NOT NULL THEN
        RAISE EXCEPTION 'PGMIG_CLOSED: row % of % is no longer open', r.row_no, b.reference USING ERRCODE = '23514';
    END IF;
    IF NOT (r.problems @> '[{"code":"POSSIBLE_SAME_APPLICANT"}]' OR r.problems @> '[{"code":"POSSIBLE_STUDENT"}]') THEN
        RAISE EXCEPTION 'PGMIG_NOTHING_TO_DECIDE: row % is not held as a possible same person', r.row_no USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'PGMIG_REASON: say how you know this is another person (at least ten characters)' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.pg_migration_row SET decided_new = true, decided_new_by = v_actor, decided_new_reason = btrim(p_reason) WHERE id = r.id;
    x := admissions.pg_migration_assess(r.id);
    UPDATE admissions.pg_migration_row
       SET checked_at = now(), verdict = x->>'verdict', match = x->>'match', action = x->>'action', application_id = (x->>'applicationId')::uuid,
           student_id = (x->>'studentId')::uuid, programme_code = x->>'programme', session = x->>'session', target_state = x->>'target', problems = x->'problems'
     WHERE id = r.id;
    RETURN x;
END $fn$;

-- ── 11 · a fee paid on the old portal, verified or rejected by the Bursary or the PG Secretary ──────────────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_legacy_fee_decide(p_fee uuid, p_verify boolean, p_note text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := coalesce(current_setting('moaum.actor_office', true), '');
        f admissions.pg_legacy_fee; b admissions.pg_migration_batch; a admissions.pg_application; p admissions.pg_applicant; v_label text;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PGMIG_ACTOR: a fee is verified by a person' USING ERRCODE = '23514'; END IF;
    IF v_office NOT IN ('pgsecretary', 'bursar', 'super') THEN
        RAISE EXCEPTION 'PGMIG_FEE_OFFICE: the Bursary or the PG Secretary verifies a fee paid on the old portal, not %', v_office USING ERRCODE = '42501';
    END IF;
    SELECT * INTO f FROM admissions.pg_legacy_fee WHERE id = p_fee FOR UPDATE;
    IF f.id IS NULL THEN RAISE EXCEPTION 'no such old-portal fee' USING ERRCODE = '23503'; END IF;
    IF f.kind = 'SCHOOL_FEES' THEN
        RAISE EXCEPTION 'PGMIG_FEE_BURSARY_UPLOAD: school fees paid on the old portal are loaded through the Bursary''s old-portal payments upload' USING ERRCODE = '23514';
    END IF;
    IF f.state <> 'REQUIRES_REVIEW' THEN
        RAISE EXCEPTION 'PGMIG_FEE_DECIDED: this fee is already %', lower(replace(f.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO b FROM admissions.pg_migration_batch WHERE id = f.batch_id;
    IF b.started_by = v_actor THEN
        RAISE EXCEPTION 'PGMIG_SAME_OFFICER: the officer who uploaded the fee (%) does not verify it', b.reference USING ERRCODE = '23514',
              HINT = 'Another officer of the Bursary or the PG Secretary verifies it.';
    END IF;
    IF length(btrim(coalesce(p_note, ''))) < 5 THEN
        RAISE EXCEPTION 'PGMIG_FEE_NOTE: say what was checked (the bank statement, the gateway''s record) or why it is rejected' USING ERRCODE = '23514';
    END IF;
    v_label := CASE f.kind WHEN 'APPLICATION' THEN 'Application fee' ELSE 'Acceptance fee' END;
    IF NOT coalesce(p_verify, false) THEN
        UPDATE admissions.pg_legacy_fee SET state = 'REJECTED', decided_by = v_actor, decided_office = v_office, decided_at = now(), decision_note = btrim(p_note) WHERE id = f.id;
        PERFORM admissions.pg_app_event(f.application_id, 'OLD_PORTAL_FEE_REJECTED',
                format('%s paid on the old portal (%s) not verified: %s', v_label, f.legacy_reference, btrim(p_note)));
    ELSE
        PERFORM set_config('moaum.pg_migration', 'fee verified', true);
        PERFORM admissions.pg_mig_post_fee(f.id);
        UPDATE admissions.pg_legacy_fee SET decided_by = v_actor, decided_office = v_office, decided_at = now(), decision_note = btrim(p_note) WHERE id = f.id;
        PERFORM admissions.pg_app_event(f.application_id, 'OLD_PORTAL_FEE_VERIFIED',
                format('%s paid on the old portal (%s, ₦%s) verified: %s', v_label, f.legacy_reference, to_char(f.amount, 'FM999,999,990'), btrim(p_note)));
        IF f.kind = 'ACCEPTANCE' THEN PERFORM admissions.pg_mig_screening(f.application_id); END IF;
        PERFORM set_config('moaum.pg_migration', '', true);
        SELECT * INTO a FROM admissions.pg_application WHERE id = f.application_id;
        SELECT * INTO p FROM admissions.pg_applicant WHERE id = a.applicant_id;
        PERFORM platform.queue_notice('EMAIL', p.email, 'Your ' || lower(v_label) || ' paid on the old portal is verified',
                'Dear ' || p.other_names || ',' || E'\n\n' || 'The ' || lower(v_label) || ' you paid on the University''s old portal (reference ' || f.legacy_reference
                || ') is verified and recorded on your application ' || a.application_no || '. You do not pay it again.'
                || CASE WHEN a.state = 'ADMITTED' THEN ' Your admission is complete: sign in to the student portal with your admission number.'
                        WHEN a.state = 'ACCEPTED' THEN ' Your offer of admission is accepted; the applicant portal shows what is next.' ELSE '' END
                || E'\n\n' || 'School of Postgraduate Studies, Rev. Fr. Moses Orshio Adasu University, Makurdi',
                'pg_application', a.id, 'pg-fee-verified:' || f.id, NULL, 'NORMAL');
    END IF;
    RETURN jsonb_build_object('id', f.id, 'state', (SELECT x.state FROM admissions.pg_legacy_fee x WHERE x.id = f.id),
                              'applicationState', (SELECT x.state FROM admissions.pg_application x WHERE x.id = f.application_id));
END $fn$;

-- ── 12 · the old programmes mapped ──────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_legacy_map_programme(p_code text, p_name text, p_programme text, p_specialisation uuid, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := admissions.pg_mig_writer(); v_key text; g ref.programme; v_id uuid;
BEGIN
    v_key := admissions.pg_legacy_key(coalesce(nullif(btrim(coalesce(p_code, '')), ''), p_name));
    IF v_key IS NULL THEN RAISE EXCEPTION 'PGMIG_MAP_NAME: name the old programme (its code or its name)' USING ERRCODE = '23514'; END IF;
    SELECT * INTO g FROM ref.programme x WHERE x.code = upper(btrim(coalesce(p_programme, '')));
    IF g.code IS NULL OR g.category IS DISTINCT FROM 'POST GRADUATE' OR g.archived THEN
        RAISE EXCEPTION 'PGMIG_MAP_PROGRAMME: an old programme is mapped to a postgraduate programme this portal runs' USING ERRCODE = '23514';
    END IF;
    IF p_specialisation IS NOT NULL AND NOT EXISTS (SELECT 1 FROM catalogue.programme_specialisation s WHERE s.id = p_specialisation AND s.programme_code = g.code AND s.active) THEN
        RAISE EXCEPTION 'PGMIG_MAP_SPECIALISATION: that specialisation is not one of %''s', g.name USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'PGMIG_REASON: say why the old programme is this one' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM admissions.pg_legacy_programme x WHERE x.legacy_key = v_key AND x.state = 'APPROVED') THEN
        RAISE EXCEPTION 'PGMIG_MAP_EXISTS: the old programme "%" is already mapped; withdraw that mapping first', coalesce(p_name, p_code) USING ERRCODE = '23514';
    END IF;
    INSERT INTO admissions.pg_legacy_programme (legacy_key, legacy_code, legacy_name, programme_code, specialisation_id, reason, mapped_by, mapped_office)
    VALUES (v_key, nullif(btrim(coalesce(p_code, '')), ''), left(btrim(coalesce(nullif(btrim(coalesce(p_name, '')), ''), p_code)), 200), g.code, p_specialisation,
            btrim(p_reason), v_actor, current_setting('moaum.actor_office', true))
    RETURNING id INTO v_id;
    RETURN v_id;
END $fn$;

CREATE OR REPLACE FUNCTION admissions.pg_legacy_unmap(p_id uuid, p_reason text) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := admissions.pg_mig_writer();
BEGIN
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'PGMIG_REASON: say why the mapping is withdrawn' USING ERRCODE = '23514'; END IF;
    UPDATE admissions.pg_legacy_programme SET state = 'WITHDRAWN', withdrawn_by = v_actor, withdrawn_at = now(), withdrawn_reason = btrim(p_reason)
     WHERE id = p_id AND state = 'APPROVED';
    IF NOT FOUND THEN RAISE EXCEPTION 'PGMIG_MAP_GONE: no such mapping in force' USING ERRCODE = '23514'; END IF;
END $fn$;

-- ── 13 · what is still to migrate, found, and counted ────────────────────────────────────────────────────────────────────────
-- the latest row of each old application number in a batch not set aside: where its migration stands
CREATE OR REPLACE VIEW admissions.pg_migration_outstanding AS
SELECT DISTINCT ON (r.legacy_no) r.id, r.batch_id, r.row_no, r.legacy_no, r.applicant, r.verdict, r.match, r.action, r.programme_code, r.target_state,
       r.problems, r.result, r.result_note, r.checked_at, r.data, b.reference AS batch_reference, b.kind AS batch_kind, b.state AS batch_state, b.started_at
  FROM admissions.pg_migration_row r JOIN admissions.pg_migration_batch b ON b.id = r.batch_id
 WHERE b.state <> 'ABANDONED' AND r.legacy_no IS NOT NULL AND r.checked_at IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM admissions.pg_legacy_application l WHERE upper(btrim(l.legacy_application_no)) = r.legacy_no)
   AND NOT EXISTS (SELECT 1 FROM people.biodata bd WHERE bd.field = 'legacy_appno' AND upper(btrim(bd.value)) = r.legacy_no)
 ORDER BY r.legacy_no, b.started_at DESC, r.row_no DESC;
COMMENT ON VIEW admissions.pg_migration_outstanding IS
  'V675: each old application number not yet on this portal, at its latest row in a batch not set aside: pending (ready, not yet imported) or held back (duplicate, conflict, review, error, failed).';

CREATE OR REPLACE FUNCTION admissions.pg_legacy_unmapped()
RETURNS TABLE (legacy_code text, legacy_name text, department text, faculty text, rows bigint, batches text)
LANGUAGE sql STABLE AS $$
    SELECT (array_agg(admissions.pg_mig_t(o.data, 'programmeCode')))[1], (array_agg(admissions.pg_mig_t(o.data, 'programme')))[1],
           (array_agg(admissions.pg_mig_t(o.data, 'department')))[1], (array_agg(admissions.pg_mig_t(o.data, 'faculty')))[1],
           count(*), string_agg(DISTINCT o.batch_reference, ', ')
      FROM admissions.pg_migration_outstanding o
     WHERE (o.result IS NULL OR o.result IN ('SKIPPED', 'FAILED'))
       AND (o.problems @> '[{"code":"PROGRAMME_NOT_MAPPED"}]' OR o.problems @> '[{"code":"PROGRAMME_AMBIGUOUS"}]')
     GROUP BY admissions.pg_legacy_key(coalesce(admissions.pg_mig_t(o.data, 'programmeCode'), admissions.pg_mig_t(o.data, 'programme')))
     ORDER BY count(*) DESC, 2
$$;

-- an applicant or student, by the new number, the old number, the matriculation or admission number, JAMB number, email,
-- phone or name: both numbers find the same person
CREATE OR REPLACE FUNCTION admissions.pg_legacy_find(p_q text)
RETURNS TABLE (kind text, application_id uuid, student_id uuid, application_no text, legacy_application_no text, name text, email text, phone text,
               programme_code text, programme_name text, session text, state text, matric_no text, admission_no text, migrated boolean)
LANGUAGE sql STABLE AS $$
    WITH q AS (SELECT btrim(coalesce(p_q, '')) AS t, upper(btrim(coalesce(p_q, ''))) AS u, admissions.pg_mig_phone(p_q) AS ph,
                      '%' || replace(replace(replace(btrim(coalesce(p_q, '')), '\', '\\'), '%', '\%'), '_', '\_') || '%' AS pat)
    (SELECT 'APPLICATION', a.id, a.student_id, a.application_no, l.legacy_application_no, p.surname || ', ' || p.other_names, p.email, p.phone,
            a.programme_code, g.name, a.session, a.state, s.matric_no, s.admission_no, l.application_id IS NOT NULL
       FROM q, admissions.pg_application a JOIN admissions.pg_applicant p ON p.id = a.applicant_id JOIN ref.programme g ON g.code = a.programme_code
       LEFT JOIN admissions.pg_legacy_application l ON l.application_id = a.id LEFT JOIN people.student s ON s.id = a.student_id
      WHERE length(q.t) >= 3
        AND (a.application_no = q.u OR upper(btrim(l.legacy_application_no)) = q.u OR lower(p.email) = lower(q.t) OR p.phone = q.ph
             OR upper(s.matric_no) = q.u OR upper(s.admission_no) = q.u OR (p.surname || ' ' || p.other_names) ILIKE q.pat
             OR (p.other_names || ' ' || p.surname) ILIKE q.pat)
      ORDER BY p.surname, p.other_names LIMIT 50)
    UNION ALL
    (SELECT 'STUDENT', NULL::uuid, s.id, NULL, bd.value, s.surname || ', ' || s.other_names, c.email, c.phone,
            s.programme_code, g.name, s.entry_session, s.status, s.matric_no, s.admission_no, bd.value IS NOT NULL
       FROM q, people.student s JOIN ref.programme g ON g.code = s.programme_code
       LEFT JOIN people.biodata bd ON bd.student_id = s.id AND bd.field = 'legacy_appno' LEFT JOIN people.student_contact c ON c.student_id = s.id
      WHERE length(q.t) >= 3 AND s.entry_mode = 'POSTGRADUATE'
        AND NOT EXISTS (SELECT 1 FROM admissions.pg_application a WHERE a.student_id = s.id)
        AND (upper(s.matric_no) = q.u OR upper(s.admission_no) = q.u OR upper(btrim(s.jamb_reg_no)) = q.u OR upper(btrim(bd.value)) = q.u
             OR lower(c.email) = lower(q.t) OR c.phone = q.ph OR (s.surname || ' ' || s.other_names) ILIKE q.pat OR (s.other_names || ' ' || s.surname) ILIKE q.pat)
      ORDER BY s.surname, s.other_names LIMIT 50)
$$;

CREATE OR REPLACE FUNCTION admissions.pg_legacy_figures() RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH la AS (SELECT l.*, a.state, a.student_id FROM admissions.pg_legacy_application l JOIN admissions.pg_application a ON a.id = l.application_id),
         ls AS (SELECT DISTINCT s.id, s.status FROM people.biodata bd JOIN people.student s ON s.id = bd.student_id
                 WHERE bd.field = 'legacy_appno' AND s.entry_mode = 'POSTGRADUATE' AND NOT EXISTS (SELECT 1 FROM la WHERE la.student_id = s.id)),
         o AS (SELECT * FROM admissions.pg_migration_outstanding)
    SELECT jsonb_build_object(
        'legacyApplicants', (SELECT count(*) FROM la) + (SELECT count(*) FROM ls) + (SELECT count(*) FROM o),
        'migrated', (SELECT count(*) FROM la),
        'pending', (SELECT count(*) FROM o WHERE o.result IS NULL AND o.verdict IN ('READY', 'WARNING') AND o.batch_state IN ('STAGING', 'CHECKED', 'IMPORTING')),
        'offered', (SELECT count(*) FROM la WHERE la.state = 'OFFERED'),
        'accepted', (SELECT count(*) FROM la WHERE la.state = 'ACCEPTED'),
        -- screened: cleared at a screening the old portal decided and that is applied here, not merely what the file said
        'screened', (SELECT count(*) FROM la WHERE EXISTS (SELECT 1 FROM admissions.pg_screening sc WHERE sc.application_id = la.application_id
                                                             AND sc.source = 'OLD_PORTAL' AND sc.state = 'CLEARED')),
        'students', (SELECT count(*) FROM la JOIN people.student s ON s.id = la.student_id WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION'))
                    + (SELECT count(*) FROM ls WHERE ls.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
        'duplicates', (SELECT count(*) FROM o WHERE o.verdict = 'DUPLICATE_IN_FILE' AND (o.result IS NULL OR o.result = 'SKIPPED')),
        'conflicts', (SELECT count(*) FROM o WHERE o.verdict = 'CONFLICT' AND (o.result IS NULL OR o.result = 'SKIPPED')),
        'review', (SELECT count(*) FROM o WHERE o.verdict = 'REQUIRES_REVIEW' AND (o.result IS NULL OR o.result = 'SKIPPED')),
        'errors', (SELECT count(*) FROM o WHERE (o.verdict = 'ERROR' AND (o.result IS NULL OR o.result = 'SKIPPED')) OR o.result = 'FAILED'),
        'documentsMissing', (SELECT count(*) FROM admissions.pg_legacy_document x WHERE x.document_id IS NULL),
        'unmappedProgrammes', (SELECT count(*) FROM admissions.pg_legacy_unmapped()),
        'feesUnderReview', (SELECT count(*) FROM admissions.pg_legacy_fee x WHERE x.state = 'REQUIRES_REVIEW'),
        'schoolFeesForBursary', (SELECT count(*) FROM admissions.pg_legacy_fee x WHERE x.state = 'FOR_BURSARY'
                                    AND NOT EXISTS (SELECT 1 FROM finance.payment_reference pr
                                                     WHERE pr.student_id = x.student_id AND pr.confirmed_at IS NOT NULL AND pr.archived_at IS NULL
                                                       AND (upper(btrim(pr.reference)) = upper(btrim(x.legacy_reference)) OR upper(btrim(pr.receipt_no)) = upper(btrim(x.legacy_reference))))),
        'batches', (SELECT count(*) FROM admissions.pg_migration_batch),
        'openBatches', (SELECT count(*) FROM admissions.pg_migration_batch b WHERE b.state IN ('STAGING', 'CHECKED', 'IMPORTING')))
$$;

-- the records behind a figure, a page at a time
CREATE OR REPLACE FUNCTION admissions.pg_legacy_list(p_view text, p_limit int, p_offset int) RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE v text := lower(coalesce(p_view, '')); lim int := least(greatest(coalesce(p_limit, 50), 1), 500); off int := greatest(coalesce(p_offset, 0), 0);
        n bigint; rows jsonb;
BEGIN
    IF v IN ('migrated', 'offered', 'accepted', 'screened', 'students') THEN
        WITH x AS (
            SELECT a.id AS application_id, a.application_no, l.legacy_application_no, p.surname || ', ' || p.other_names AS name, a.programme_code, g.name AS programme_name,
                   a.session, a.state, s.matric_no, s.admission_no, s.status AS student_status, b.reference AS batch_reference, l.migrated_at, l.screening_decision
              FROM admissions.pg_legacy_application l JOIN admissions.pg_application a ON a.id = l.application_id
              JOIN admissions.pg_applicant p ON p.id = a.applicant_id JOIN ref.programme g ON g.code = a.programme_code
              JOIN admissions.pg_migration_batch b ON b.id = l.batch_id LEFT JOIN people.student s ON s.id = a.student_id
             WHERE v = 'migrated' OR (v = 'offered' AND a.state = 'OFFERED') OR (v = 'accepted' AND a.state = 'ACCEPTED')
                OR (v = 'screened' AND EXISTS (SELECT 1 FROM admissions.pg_screening sc WHERE sc.application_id = a.id AND sc.source = 'OLD_PORTAL' AND sc.state = 'CLEARED'))
                OR (v = 'students' AND s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')))
        SELECT (SELECT count(*) FROM x), coalesce((SELECT jsonb_agg(to_jsonb(y)) FROM (SELECT * FROM x ORDER BY x.migrated_at DESC, x.name LIMIT lim OFFSET off) y), '[]')
          INTO n, rows;
    ELSIF v IN ('pending', 'duplicates', 'conflicts', 'review', 'errors') THEN
        WITH x AS (
            SELECT o.id AS row_id, o.batch_id, o.batch_reference, o.row_no, o.legacy_no, o.applicant, o.verdict, o.action, o.result, o.result_note, o.programme_code,
                   (SELECT e->>'message' FROM jsonb_array_elements(o.problems) e WHERE e->>'level' <> 'warning' LIMIT 1) AS problem, o.started_at
              FROM admissions.pg_migration_outstanding o
             WHERE (v = 'pending' AND o.result IS NULL AND o.verdict IN ('READY', 'WARNING') AND o.batch_state IN ('STAGING', 'CHECKED', 'IMPORTING'))
                OR (v = 'duplicates' AND o.verdict = 'DUPLICATE_IN_FILE' AND (o.result IS NULL OR o.result = 'SKIPPED'))
                OR (v = 'conflicts' AND o.verdict = 'CONFLICT' AND (o.result IS NULL OR o.result = 'SKIPPED'))
                OR (v = 'review' AND o.verdict = 'REQUIRES_REVIEW' AND (o.result IS NULL OR o.result = 'SKIPPED'))
                OR (v = 'errors' AND ((o.verdict = 'ERROR' AND (o.result IS NULL OR o.result = 'SKIPPED')) OR o.result = 'FAILED')))
        SELECT (SELECT count(*) FROM x), coalesce((SELECT jsonb_agg(to_jsonb(y)) FROM (SELECT * FROM x ORDER BY x.started_at DESC, x.row_no LIMIT lim OFFSET off) y), '[]')
          INTO n, rows;
    ELSIF v = 'documents' THEN
        WITH x AS (
            SELECT d.id, d.label, d.kind, d.legacy_ref, d.application_id, a.application_no, l.legacy_application_no,
                   coalesce(p.surname || ', ' || p.other_names, s.surname || ', ' || s.other_names) AS name, coalesce(s.matric_no, s.admission_no) AS student_no,
                   b.reference AS batch_reference, d.created_at
              FROM admissions.pg_legacy_document d JOIN admissions.pg_migration_batch b ON b.id = d.batch_id
              LEFT JOIN admissions.pg_application a ON a.id = d.application_id LEFT JOIN admissions.pg_applicant p ON p.id = a.applicant_id
              LEFT JOIN admissions.pg_legacy_application l ON l.application_id = d.application_id LEFT JOIN people.student s ON s.id = d.student_id
             WHERE d.document_id IS NULL)
        SELECT (SELECT count(*) FROM x), coalesce((SELECT jsonb_agg(to_jsonb(y)) FROM (SELECT * FROM x ORDER BY x.name, x.label LIMIT lim OFFSET off) y), '[]')
          INTO n, rows;
    ELSIF v = 'fees' THEN
        WITH x AS (
            SELECT f.id, f.kind, f.legacy_reference, f.amount, f.paid_on, f.session, f.semester, f.state, f.stated_status, f.application_id, a.application_no,
                   l.legacy_application_no, coalesce(p.surname || ', ' || p.other_names, s.surname || ', ' || s.other_names) AS name,
                   coalesce(s.matric_no, s.admission_no) AS student_no, b.reference AS batch_reference, b.started_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS uploaded_by_me,
                   EXISTS (SELECT 1 FROM finance.payment_reference pr
                            WHERE pr.student_id = f.student_id AND pr.confirmed_at IS NOT NULL AND pr.archived_at IS NULL
                              AND (upper(btrim(pr.reference)) = upper(btrim(f.legacy_reference)) OR upper(btrim(pr.receipt_no)) = upper(btrim(f.legacy_reference)))) AS on_record,
                   f.created_at
              FROM admissions.pg_legacy_fee f JOIN admissions.pg_migration_batch b ON b.id = f.batch_id
              LEFT JOIN admissions.pg_application a ON a.id = f.application_id LEFT JOIN admissions.pg_applicant p ON p.id = a.applicant_id
              LEFT JOIN admissions.pg_legacy_application l ON l.application_id = f.application_id
              LEFT JOIN people.student s ON s.id = coalesce(f.student_id, a.student_id)
             WHERE f.state IN ('REQUIRES_REVIEW', 'FOR_BURSARY'))
        SELECT (SELECT count(*) FROM x), coalesce((SELECT jsonb_agg(to_jsonb(y)) FROM (SELECT * FROM x ORDER BY x.state DESC, x.created_at DESC LIMIT lim OFFSET off) y), '[]')
          INTO n, rows;
    ELSE
        RAISE EXCEPTION 'PGMIG_VIEW: no such list "%"', p_view USING ERRCODE = '23514';
    END IF;
    RETURN jsonb_build_object('view', v, 'total', n, 'limit', lim, 'offset', off, 'rows', rows);
END $fn$;

-- ── 14 · the pipeline, aware of the migration ───────────────────────────────────────────────────────────────────────────────
-- silent inside a migration: the migration tells the applicant once, in its own words (admissions.pg_mig_tell)
CREATE OR REPLACE FUNCTION admissions.pg_tell_applicant(p_app uuid, p_subject text, p_body text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v_email text; v_no text; v_phone text;
BEGIN
    IF coalesce(current_setting('moaum.pg_migration', true), '') <> '' THEN RETURN; END IF;   -- V675
    SELECT p.email, a.application_no, p.phone INTO v_email, v_no, v_phone
      FROM admissions.pg_application a JOIN admissions.pg_applicant p ON p.id = a.applicant_id
     WHERE a.id = p_app;
    -- V389: the applicant is told by SMS as well, in a line, and reads the rest on the portal
    PERFORM platform.queue_notice('SMS', v_phone, p_subject, 'MOAUM PG: ' || p_subject || '. Sign in to the applicant portal.', 'pg_application', p_app);
    IF v_email IS NULL THEN RETURN; END IF;
    PERFORM platform.queue_notice('EMAIL', v_email, p_subject,
        'Dear applicant,' || E'\n\n' || p_body || E'\n\n' || 'Application number: ' || coalesce(v_no, '') || E'\n' ||
        'School of Postgraduate Studies, Rev. Fr. Moses Orshio Adasu University, Makurdi',
        'pg_application', p_app);
END $function$;

-- an admission decided on the old portal is read without the checking fee: the applicant was told there
CREATE OR REPLACE FUNCTION admissions.pg_status_checking(p_application uuid)
 RETURNS TABLE(valid boolean, window_state text, window_open boolean, paid boolean, may_pay boolean, may_check boolean, continuing boolean, status text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT v.valid, w.state, w.state = 'OPEN', v.paid,
           v.valid AND NOT v.paid AND w.state = 'OPEN',
           v.valid AND v.paid AND (w.state = 'OPEN' OR v.continuing),
           v.continuing,
           CASE WHEN a.state IN ('OFFERED', 'ACCEPTED', 'ADMITTED') THEN 'ADMITTED'
                WHEN a.state = 'NOT_OFFERED' THEN 'NOT_ADMITTED'
                ELSE 'PENDING' END
      FROM admissions.pg_application a
      LEFT JOIN admissions.pg_legacy_application lg ON lg.application_id = a.id AND lg.decided_on_old_portal   -- V675
      CROSS JOIN LATERAL (SELECT (a.fee_confirmed_at IS NOT NULL AND a.submitted_at IS NOT NULL AND a.state <> 'DRAFT') OR lg.application_id IS NOT NULL AS valid,
                                 a.checking_confirmed_at IS NOT NULL OR lg.application_id IS NOT NULL AS paid,
                                 a.acceptance_confirmed_at IS NOT NULL OR a.state IN ('ACCEPTED', 'ADMITTED') OR lg.application_id IS NOT NULL AS continuing) v
      CROSS JOIN LATERAL policy.window_state('POSTGRADUATE_ADMISSION_STATUS_CHECKING', a.session, NULL) w
     WHERE a.id = p_application;
$function$;

-- no reference for a fee paid on the old portal and under review, nor a checking fee for a decision the old portal made
CREATE OR REPLACE FUNCTION admissions.pg_new_fee_reference(p_application uuid, p_kind text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE v_session text; v_amt numeric; v_ref text; v_rule record; v_try int; v_top bigint;
BEGIN
    SELECT session INTO v_session FROM admissions.pg_application WHERE id = p_application;
    IF v_session IS NULL THEN
        RAISE EXCEPTION 'no such postgraduate application';
    END IF;
    -- V675: the same fee paid on the old portal is being verified; not paid twice meanwhile
    IF EXISTS (SELECT 1 FROM admissions.pg_legacy_fee x WHERE x.application_id = p_application AND x.kind = p_kind AND x.state = 'REQUIRES_REVIEW') THEN
        RAISE EXCEPTION 'PG_FEE_UNDER_REVIEW: the % fee you paid on the old portal is being verified by the Bursary; you do not pay it again meanwhile', lower(p_kind)
              USING ERRCODE = '23514', HINT = 'You are told by email once it is verified.';
    END IF;
    IF p_kind = 'CHECKING' AND EXISTS (SELECT 1 FROM admissions.pg_legacy_application l WHERE l.application_id = p_application AND l.decided_on_old_portal) THEN
        RAISE EXCEPTION 'PG_FEE_NOT_NEEDED: your admission was decided on the old portal and is read here without the checking fee' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO v_rule FROM admissions.pg_fee_rule(v_session);
    v_amt := CASE p_kind WHEN 'ACCEPTANCE' THEN v_rule.acceptance_fee
                         WHEN 'CHECKING'   THEN v_rule.checking_fee
                         ELSE v_rule.application_fee END;
    -- V564: the series is the session's but the reference names no session, so a new session's series draws numbers an earlier
    -- one issued: a taken reference carries the series past every postgraduate fee reference's number, and is drawn again
    FOR v_try IN 1..50 LOOP
        v_ref := 'MOAUM-PG' || CASE p_kind WHEN 'ACCEPTANCE' THEN 'ACC' WHEN 'CHECKING' THEN 'CHK' ELSE 'APP' END || '-'
                 || lpad(platform.next_number('PG_FEEREF', 'UNIVERSITY', v_session)::text, 6, '0');
        INSERT INTO admissions.pg_fee_reference (application_id, kind, reference, amount, expires_at)
        VALUES (p_application, p_kind, v_ref, v_amt, now() + interval '24 hours')
        ON CONFLICT (reference) DO NOTHING;
        IF FOUND THEN RETURN v_ref; END IF;
        SELECT max(substring(f.reference FROM '-([0-9]+)$')::bigint) INTO v_top
          FROM admissions.pg_fee_reference f WHERE f.reference ~ '^MOAUM-PG(APP|CHK|ACC)-[0-9]+$';
        UPDATE platform.number_series SET next_value = greatest(next_value, coalesce(v_top, 0) + 1)
         WHERE kind = 'PG_FEEREF' AND scope = 'UNIVERSITY' AND session = v_session;
    END LOOP;
    RAISE EXCEPTION 'PG_FEE_REFERENCE_EXHAUSTED: no free % reference was found in fifty draws', lower(p_kind) USING ERRCODE = '23514',
        HINT = 'Try again; if it persists, tell the Directorate of ICT.';
END;
$function$;

COMMIT;
