-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V320 — one official identity for every document the portal prints, and a record of what it issues
--
--   Until now the University's name was typed into fifty-four screens and thirteen services, and the
--   crest was a file in the frontend's public folder: a change of name, motto, address or logo was a
--   change of code. platform.institution_profile is the one row every document reads — the name, the
--   short name, the motto, the address and the contact lines, the logo as objects in the file store
--   (the upload as given, and a JPEG the PDF engine can embed), and the document defaults (whether to
--   print who generated a report, page numbers, the date style, a footer note). It is seeded with what
--   the code carried, so nothing changes until an administrator changes it, and it is audited.
--
--   platform.document_issue records a document the portal issued — a receipt downloaded, a result
--   statement printed, a broadsheet exported — in the actor's name, through the same audit spine as
--   every other write, so the issuing of an official document is on the record without a second
--   audit system.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V320: the institution profile and the record of issued documents', true);

/* ── 1 · the institution profile: one row ──────────────────────────────────────────────────────── */
CREATE TABLE platform.institution_profile (
    id                  boolean     PRIMARY KEY DEFAULT true,
    name                text        NOT NULL,
    short_name          text        NOT NULL,
    motto               text        NULL,
    address             text        NULL,
    city                text        NULL,
    state               text        NULL,
    country             text        NULL,
    phone               text        NULL,
    email               text        NULL,
    website             text        NULL,
    logo_object_id      uuid        NULL REFERENCES platform.file_object(id) ON DELETE SET NULL,
    logo_jpeg_object_id uuid        NULL REFERENCES platform.file_object(id) ON DELETE SET NULL,
    logo_version        int         NOT NULL DEFAULT 0,
    footer_note         text        NULL,
    show_generated_by   boolean     NOT NULL DEFAULT true,
    show_page_numbers   boolean     NOT NULL DEFAULT true,
    date_format         text        NOT NULL DEFAULT 'LONG',
    updated_at          timestamptz NOT NULL DEFAULT now(),
    updated_by          uuid        NULL,
    CONSTRAINT ck_institution_one         CHECK (id),
    CONSTRAINT ck_institution_name        CHECK (btrim(name) <> '' AND btrim(short_name) <> ''),
    CONSTRAINT ck_institution_date_format CHECK (date_format IN ('LONG', 'SHORT'))
);
COMMENT ON TABLE platform.institution_profile IS
  'V320: the University''s official identity, read by every document the portal prints or exports — name, short name, motto, address, contacts, the logo (an object in the file store, with a JPEG derivative for the PDF engine) and the document defaults. One row; audited.';

INSERT INTO platform.institution_profile (id, name, short_name, city, state, country)
VALUES (true, 'Rev. Fr. Moses Orshio Adasu University, Makurdi', 'MOAUM', 'Makurdi', 'Benue State', 'Nigeria');

SELECT audit.attach('platform.institution_profile');

CREATE OR REPLACE FUNCTION platform.institution()
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'name', name, 'shortName', short_name, 'motto', motto, 'address', address, 'city', city, 'state', state, 'country', country,
        'phone', phone, 'email', email, 'website', website,
        'hasLogo', logo_object_id IS NOT NULL, 'hasLogoJpeg', logo_jpeg_object_id IS NOT NULL, 'logoVersion', logo_version,
        'footerNote', footer_note, 'showGeneratedBy', show_generated_by, 'showPageNumbers', show_page_numbers, 'dateFormat', date_format,
        'updatedAt', updated_at, 'updatedBy', updated_by)
      FROM platform.institution_profile WHERE id
$$;
COMMENT ON FUNCTION platform.institution() IS 'V320: the institution profile as the documents read it.';

CREATE OR REPLACE FUNCTION platform.set_institution_profile(p_name text, p_short text, p_motto text, p_address text, p_city text, p_state text,
                                                            p_country text, p_phone text, p_email text, p_website text, p_footer text,
                                                            p_generated_by boolean, p_page_numbers boolean, p_date_format text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF p_name IS NULL OR btrim(p_name) = '' THEN
        RAISE EXCEPTION 'INSTITUTION_NAME_REQUIRED: the University''s name is what every document carries; it cannot be blank' USING ERRCODE = 'check_violation';
    END IF;
    IF p_short IS NULL OR btrim(p_short) = '' THEN
        RAISE EXCEPTION 'INSTITUTION_SHORT_NAME_REQUIRED: the short name heads every continuation page; it cannot be blank' USING ERRCODE = 'check_violation';
    END IF;
    IF nullif(btrim(coalesce(p_email, '')), '') IS NOT NULL AND btrim(p_email) !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
        RAISE EXCEPTION 'INSTITUTION_EMAIL_INVALID: % is not an e-mail address', btrim(p_email) USING ERRCODE = 'check_violation';
    END IF;
    IF nullif(btrim(coalesce(p_website, '')), '') IS NOT NULL AND btrim(p_website) !~ '^(https?://)?[A-Za-z0-9.-]+\.[A-Za-z]{2,}(/.*)?$' THEN
        RAISE EXCEPTION 'INSTITUTION_WEBSITE_INVALID: % is not a web address', btrim(p_website) USING ERRCODE = 'check_violation';
    END IF;
    IF coalesce(p_date_format, 'LONG') NOT IN ('LONG', 'SHORT') THEN
        RAISE EXCEPTION 'INSTITUTION_DATE_FORMAT: the date style is LONG (04 October 2026) or SHORT (04/10/2026)' USING ERRCODE = 'check_violation';
    END IF;
    UPDATE platform.institution_profile
       SET name = btrim(p_name), short_name = btrim(p_short), motto = nullif(btrim(coalesce(p_motto, '')), ''),
           address = nullif(btrim(coalesce(p_address, '')), ''), city = nullif(btrim(coalesce(p_city, '')), ''),
           state = nullif(btrim(coalesce(p_state, '')), ''), country = nullif(btrim(coalesce(p_country, '')), ''),
           phone = nullif(btrim(coalesce(p_phone, '')), ''), email = nullif(btrim(coalesce(p_email, '')), ''),
           website = nullif(btrim(coalesce(p_website, '')), ''), footer_note = nullif(btrim(coalesce(p_footer, '')), ''),
           show_generated_by = coalesce(p_generated_by, true), show_page_numbers = coalesce(p_page_numbers, true),
           date_format = coalesce(p_date_format, 'LONG'), updated_at = now(), updated_by = v_actor
     WHERE id;
    RETURN platform.institution();
END $$;
COMMENT ON FUNCTION platform.set_institution_profile(text, text, text, text, text, text, text, text, text, text, text, boolean, boolean, text) IS
  'V320: the administrator''s change to the institution profile — the name and short name required, the e-mail and website checked for shape, the rest trimmed; audited on the row.';

CREATE OR REPLACE FUNCTION platform.set_institution_logo(p_logo uuid, p_jpeg uuid)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    UPDATE platform.institution_profile
       SET logo_object_id = p_logo, logo_jpeg_object_id = p_jpeg, logo_version = logo_version + 1, updated_at = now(), updated_by = v_actor
     WHERE id;
    RETURN platform.institution();
END $$;
COMMENT ON FUNCTION platform.set_institution_logo(uuid, uuid) IS
  'V320: the logo as uploaded and its JPEG derivative, both objects in the file store; NULLs return the documents to the built-in crest. The version rises so caches refresh.';

/* ── 2 · what the portal issued: a document downloaded or printed, in the actor''s name ─────────── */
CREATE TABLE platform.document_issue (
    id           uuid        PRIMARY KEY,
    kind         text        NOT NULL,
    reference    text        NULL,
    subject_kind text        NULL,
    subject_id   text        NULL,
    actor_id     uuid        NULL,
    actor_office text        NULL,
    issued_at    timestamptz NOT NULL DEFAULT now(),
    detail       jsonb       NULL,
    CONSTRAINT ck_document_issue_kind CHECK (kind ~ '^[A-Z][A-Z0-9_]{2,60}$')
);
CREATE INDEX ix_document_issue_subject ON platform.document_issue (subject_kind, subject_id, issued_at DESC);
CREATE INDEX ix_document_issue_when ON platform.document_issue (issued_at DESC);
COMMENT ON TABLE platform.document_issue IS
  'V320: a document the portal issued — RECEIPT_DOWNLOADED, RESULT_STATEMENT_DOWNLOADED, RESULT_BROADSHEET_EXPORTED and the like — with its reference, what it was about, who issued it in which office, and the filters or options used. Audited through the spine like every write.';
SELECT audit.attach('platform.document_issue');

CREATE OR REPLACE FUNCTION platform.record_document_issue(p_kind text, p_reference text, p_subject_kind text, p_subject_id text, p_detail jsonb)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
    INSERT INTO platform.document_issue (id, kind, reference, subject_kind, subject_id, actor_id, actor_office, detail)
    VALUES (v_id, upper(btrim(p_kind)), nullif(btrim(coalesce(p_reference, '')), ''), nullif(btrim(coalesce(p_subject_kind, '')), ''),
            nullif(btrim(coalesce(p_subject_id, '')), ''), nullif(current_setting('moaum.actor_id', true), '')::uuid,
            nullif(current_setting('moaum.actor_office', true), ''), p_detail);
    RETURN v_id;
END $$;

COMMIT;
