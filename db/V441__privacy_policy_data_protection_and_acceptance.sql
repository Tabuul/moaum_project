-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V441 — the Privacy Policy, data protection and acceptance
--
--   The portal holds personal data of applicants, students, staff, alumni and the offices; this is the one policy that
--   tells them how, written from an inventory of what the portal actually holds (docs/privacy-data-inventory.md), and
--   the engine that keeps it: versions, publication, acceptance, requests. Nothing here is a second anything — the
--   governance register and request log (V075), the audit spine, the notification engine, the document engine and the
--   sign-in doors are reused.
--
--   1. platform.legal_document — a legal document of a kind (PRIVACY_POLICY now; TERMS_OF_USE, COOKIE_NOTICE when the
--      University writes them) in numbered versions: one DRAFT at a time, one PUBLISHED at a time, every earlier version
--      kept as ARCHIVED. Sections are ordered plain text with headings; tokens in {{double braces}} (the University's
--      name and contacts, the privacy contact, the providers in use, the version and dates) are resolved when the document
--      is read, so none of those is hard-coded in the text. Review points are the items the Data Protection Officer or
--      legal adviser must confirm before a draft can be published; publication refuses while any is unconfirmed.
--   2. platform.privacy_contact — the Data Protection Officer / privacy contact and the period within which requests are
--      answered (30 days by default), set by the Directorate of ICT, the Registrar or an administrator.
--   3. platform.policy_acceptance — who accepted which version when, from where; version-aware, once per version, by the
--      person's own act; a new version that requires acceptance is asked for again, an unchanged one never is.
--   4. governance.dsr — the existing data-subject request log takes the policy's requests: COMPLAINT and INQUIRY join
--      the kinds, and a request filed by the person through the portal carries who filed it, how to reach them and what
--      they ask; the reference series and the due-date rule are the log's own.
--   5. The governance register's CBT row restated to what the engine does: the camera by consent, presence signals in
--      the browser, no video, image or biometric template kept.
--   6. The Privacy Policy version 1 seeded as a DRAFT — 36 sections, eight review points — for the University to
--      confirm, complete (the contact) and publish from ICT → Portal Management → Privacy & Data Protection.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    PERFORM set_config('moaum.reason', 'V441: the Privacy Policy, data protection and acceptance', true);
END $seed$;

-- ── 1 · legal documents in versions ─────────────────────────────────────────────────────────────────────────────────
CREATE TABLE platform.legal_document (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kind                text NOT NULL,
    version             int NOT NULL,
    status              text NOT NULL DEFAULT 'DRAFT',
    title               text NOT NULL,
    summary             text NULL,
    sections            jsonb NOT NULL DEFAULT '[]'::jsonb,
    review_points       jsonb NOT NULL DEFAULT '[]'::jsonb,
    requires_acceptance boolean NOT NULL DEFAULT true,
    effective_on        date NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),
    created_by          uuid NULL,
    updated_at          timestamptz NOT NULL DEFAULT now(),
    updated_by          uuid NULL,
    published_at        timestamptz NULL,
    published_by        uuid NULL,
    archived_at         timestamptz NULL,
    archive_note        text NULL,
    CONSTRAINT ck_legal_kind CHECK (kind IN ('PRIVACY_POLICY', 'TERMS_OF_USE', 'COOKIE_NOTICE')),
    CONSTRAINT ck_legal_status CHECK (status IN ('DRAFT', 'PUBLISHED', 'ARCHIVED')),
    CONSTRAINT ck_legal_version CHECK (version >= 1),
    CONSTRAINT ck_legal_title CHECK (btrim(title) <> ''),
    CONSTRAINT ck_legal_sections CHECK (jsonb_typeof(sections) = 'array'),
    CONSTRAINT ck_legal_review CHECK (jsonb_typeof(review_points) = 'array'),
    CONSTRAINT ck_legal_published CHECK (status <> 'PUBLISHED' OR (published_at IS NOT NULL AND effective_on IS NOT NULL)),
    CONSTRAINT uq_legal_version UNIQUE (kind, version)
);
CREATE UNIQUE INDEX ux_legal_document_published ON platform.legal_document (kind) WHERE status = 'PUBLISHED';
CREATE UNIQUE INDEX ux_legal_document_draft ON platform.legal_document (kind) WHERE status = 'DRAFT';
SELECT audit.attach('platform.legal_document');
COMMENT ON TABLE platform.legal_document IS
  'V441: the University''s legal documents (Privacy Policy, Terms of Use, Cookie Notice) in numbered versions — one DRAFT and one PUBLISHED per kind, earlier versions ARCHIVED and kept; sections [{key, heading, body}] with {{tokens}} resolved on reading; review_points [{key, text, confirmed_at, confirmed_by}] confirmed before publication.';

-- ── 2 · the privacy contact ─────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE platform.privacy_contact (
    id             boolean PRIMARY KEY DEFAULT true,
    dpo_name       text NULL,
    dpo_title      text NULL,
    dpo_office     text NULL,
    dpo_email      text NULL,
    dpo_phone      text NULL,
    dpo_address    text NULL,
    request_days   int NOT NULL DEFAULT 30,
    note           text NULL,
    updated_at     timestamptz NULL,
    updated_by     uuid NULL,
    updated_office text NULL,
    CONSTRAINT ck_privacy_contact_singleton CHECK (id = true),
    CONSTRAINT ck_privacy_contact_days CHECK (request_days BETWEEN 1 AND 90)
);
INSERT INTO platform.privacy_contact (id) VALUES (true);
SELECT audit.attach('platform.privacy_contact');
COMMENT ON TABLE platform.privacy_contact IS 'V441: the Data Protection Officer / privacy contact the policy names, and the period (days) within which requests are answered.';

CREATE OR REPLACE FUNCTION platform.privacy_contact_set(p_name text, p_title text, p_office text, p_email text, p_phone text, p_address text,
                                                        p_days int, p_note text, p_actor uuid, p_acting text)
RETURNS platform.privacy_contact LANGUAGE plpgsql AS $$
DECLARE r platform.privacy_contact;
BEGIN
    IF p_acting IS NULL OR p_acting NOT IN ('ict', 'admin', 'super', 'registrar') THEN
        RAISE EXCEPTION 'PRIVACY_CONTACT_OFFICE: the privacy contact is set by the Directorate of ICT, the Registrar or an administrator' USING ERRCODE = '23514';
    END IF;
    IF p_days IS NULL OR p_days < 1 OR p_days > 90 THEN
        RAISE EXCEPTION 'PRIVACY_CONTACT_DAYS: requests are answered within 1 to 90 days' USING ERRCODE = '23514';
    END IF;
    IF p_email IS NOT NULL AND btrim(p_email) <> '' AND p_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
        RAISE EXCEPTION 'PRIVACY_CONTACT_EMAIL: the privacy e-mail address is not an address' USING ERRCODE = '23514';
    END IF;
    UPDATE platform.privacy_contact
       SET dpo_name = nullif(btrim(coalesce(p_name, '')), ''), dpo_title = nullif(btrim(coalesce(p_title, '')), ''),
           dpo_office = nullif(btrim(coalesce(p_office, '')), ''), dpo_email = nullif(lower(btrim(coalesce(p_email, ''))), ''),
           dpo_phone = nullif(btrim(coalesce(p_phone, '')), ''), dpo_address = nullif(btrim(coalesce(p_address, '')), ''),
           request_days = p_days, note = nullif(btrim(coalesce(p_note, '')), ''),
           updated_at = now(), updated_by = p_actor, updated_office = p_acting
     WHERE id = true
    RETURNING * INTO r;
    RETURN r;
END $$;

-- ── 3 · the acceptance record ───────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE platform.policy_acceptance (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id  uuid NOT NULL REFERENCES platform.legal_document (id),
    kind         text NOT NULL,
    version      int NOT NULL,
    subject_kind text NOT NULL,
    subject_id   uuid NOT NULL,
    accepted_at  timestamptz NOT NULL DEFAULT now(),
    source_ip    text NULL,
    user_agent   text NULL,
    channel      text NOT NULL DEFAULT 'PORTAL',
    withdrawn_at timestamptz NULL,
    withdrawal_note text NULL,
    CONSTRAINT ck_acceptance_subject CHECK (subject_kind IN ('STUDENT', 'STAFF', 'APPLICANT')),
    CONSTRAINT ck_acceptance_channel CHECK (channel IN ('PORTAL', 'REGISTRATION')),
    CONSTRAINT uq_acceptance_once UNIQUE (document_id, subject_kind, subject_id)
);
CREATE INDEX ix_acceptance_subject ON platform.policy_acceptance (subject_kind, subject_id);
SELECT audit.attach('platform.policy_acceptance');
COMMENT ON TABLE platform.policy_acceptance IS 'V441: who accepted which version of a legal document, when and from where — once per version, by the person''s own act; a withdrawal is recorded, never deleted.';

-- ── 4 · the engine ──────────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION platform.legal_office_check(p_acting text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_acting IS NULL OR p_acting NOT IN ('ict', 'admin', 'super') THEN
        RAISE EXCEPTION 'LEGAL_OFFICE: legal documents are drafted and published by the Directorate of ICT or an administrator' USING ERRCODE = '23514';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION platform.legal_sections_check(p_sections jsonb)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE s jsonb; n int := 0;
BEGIN
    IF p_sections IS NULL OR jsonb_typeof(p_sections) <> 'array' THEN
        RAISE EXCEPTION 'LEGAL_SECTIONS: the sections are a list' USING ERRCODE = '23514';
    END IF;
    FOR s IN SELECT value FROM jsonb_array_elements(p_sections) LOOP
        n := n + 1;
        IF jsonb_typeof(s) <> 'object' OR btrim(coalesce(s->>'heading', '')) = '' OR btrim(coalesce(s->>'body', '')) = '' THEN
            RAISE EXCEPTION 'LEGAL_SECTIONS: section % needs a heading and a body', n USING ERRCODE = '23514';
        END IF;
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION platform.legal_published(p_kind text)
RETURNS platform.legal_document LANGUAGE sql STABLE AS $$
    SELECT * FROM platform.legal_document WHERE kind = p_kind AND status = 'PUBLISHED'
$$;

-- a new draft: from the latest version of its kind (the published one, else the last archived), its review points unconfirmed again
CREATE OR REPLACE FUNCTION platform.legal_document_draft(p_kind text, p_actor uuid, p_acting text)
RETURNS platform.legal_document LANGUAGE plpgsql AS $$
DECLARE base platform.legal_document; r platform.legal_document; v int;
BEGIN
    PERFORM platform.legal_office_check(p_acting);
    IF p_kind IS NULL OR p_kind NOT IN ('PRIVACY_POLICY', 'TERMS_OF_USE', 'COOKIE_NOTICE') THEN
        RAISE EXCEPTION 'LEGAL_KIND: the kind is PRIVACY_POLICY, TERMS_OF_USE or COOKIE_NOTICE' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM platform.legal_document WHERE kind = p_kind AND status = 'DRAFT') THEN
        RAISE EXCEPTION 'LEGAL_DRAFT_EXISTS: a draft of this document is already open; edit or withdraw it' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO base FROM platform.legal_document WHERE kind = p_kind ORDER BY (status = 'PUBLISHED') DESC, version DESC LIMIT 1;
    SELECT coalesce(max(version), 0) + 1 INTO v FROM platform.legal_document WHERE kind = p_kind;
    INSERT INTO platform.legal_document (kind, version, status, title, summary, sections, review_points, requires_acceptance, created_by, updated_by)
    VALUES (p_kind, v, 'DRAFT',
            coalesce(base.title, CASE p_kind WHEN 'PRIVACY_POLICY' THEN 'Privacy Policy' WHEN 'TERMS_OF_USE' THEN 'Terms of Use' ELSE 'Cookie Notice' END),
            base.summary, coalesce(base.sections, '[]'::jsonb),
            coalesce((SELECT jsonb_agg(jsonb_build_object('key', p->>'key', 'text', p->>'text', 'confirmed_at', NULL, 'confirmed_by', NULL))
                        FROM jsonb_array_elements(coalesce(base.review_points, '[]'::jsonb)) p), '[]'::jsonb),
            coalesce(base.requires_acceptance, true), p_actor, p_actor)
    RETURNING * INTO r;
    RETURN r;
END $$;

CREATE OR REPLACE FUNCTION platform.legal_document_update(p_id uuid, p_title text, p_summary text, p_sections jsonb, p_effective date,
                                                          p_requires boolean, p_actor uuid, p_acting text)
RETURNS platform.legal_document LANGUAGE plpgsql AS $$
DECLARE r platform.legal_document;
BEGIN
    PERFORM platform.legal_office_check(p_acting);
    SELECT * INTO r FROM platform.legal_document WHERE id = p_id FOR UPDATE;
    IF r.id IS NULL THEN
        RAISE EXCEPTION 'LEGAL_NOT_FOUND: no such document' USING ERRCODE = 'P0002';
    END IF;
    IF r.status <> 'DRAFT' THEN
        RAISE EXCEPTION 'LEGAL_NOT_DRAFT: only a draft is edited; a published version is replaced by a new draft' USING ERRCODE = '23514';
    END IF;
    IF p_title IS NULL OR btrim(p_title) = '' THEN
        RAISE EXCEPTION 'LEGAL_TITLE: the document needs a title' USING ERRCODE = '23514';
    END IF;
    PERFORM platform.legal_sections_check(p_sections);
    UPDATE platform.legal_document
       SET title = btrim(p_title), summary = nullif(btrim(coalesce(p_summary, '')), ''), sections = p_sections, effective_on = p_effective,
           requires_acceptance = coalesce(p_requires, requires_acceptance), updated_at = now(), updated_by = p_actor
     WHERE id = p_id
    RETURNING * INTO r;
    RETURN r;
END $$;

CREATE OR REPLACE FUNCTION platform.legal_review_confirm(p_id uuid, p_key text, p_confirmed boolean, p_actor uuid, p_acting text)
RETURNS platform.legal_document LANGUAGE plpgsql AS $$
DECLARE r platform.legal_document; pts jsonb;
BEGIN
    PERFORM platform.legal_office_check(p_acting);
    SELECT * INTO r FROM platform.legal_document WHERE id = p_id FOR UPDATE;
    IF r.id IS NULL THEN
        RAISE EXCEPTION 'LEGAL_NOT_FOUND: no such document' USING ERRCODE = 'P0002';
    END IF;
    IF r.status <> 'DRAFT' THEN
        RAISE EXCEPTION 'LEGAL_NOT_DRAFT: review points are confirmed on a draft' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r.review_points) p WHERE p->>'key' = p_key) THEN
        RAISE EXCEPTION 'LEGAL_REVIEW_POINT: no review point "%"', p_key USING ERRCODE = '23514';
    END IF;
    SELECT jsonb_agg(CASE WHEN p->>'key' = p_key
                          THEN p || jsonb_build_object('confirmed_at', CASE WHEN p_confirmed THEN to_jsonb(now()) ELSE 'null'::jsonb END,
                                                       'confirmed_by', CASE WHEN p_confirmed THEN to_jsonb(p_actor) ELSE 'null'::jsonb END)
                          ELSE p END ORDER BY ord)
      INTO pts
      FROM jsonb_array_elements(r.review_points) WITH ORDINALITY AS t(p, ord);
    UPDATE platform.legal_document SET review_points = pts, updated_at = now(), updated_by = p_actor WHERE id = p_id RETURNING * INTO r;
    RETURN r;
END $$;

-- publication: every review point confirmed, an effective date, something to publish; the current version archived, kept
CREATE OR REPLACE FUNCTION platform.legal_document_publish(p_id uuid, p_effective date, p_actor uuid, p_acting text)
RETURNS platform.legal_document LANGUAGE plpgsql AS $$
DECLARE r platform.legal_document; pending text; eff date;
BEGIN
    PERFORM platform.legal_office_check(p_acting);
    SELECT * INTO r FROM platform.legal_document WHERE id = p_id FOR UPDATE;
    IF r.id IS NULL THEN
        RAISE EXCEPTION 'LEGAL_NOT_FOUND: no such document' USING ERRCODE = 'P0002';
    END IF;
    IF r.status <> 'DRAFT' THEN
        RAISE EXCEPTION 'LEGAL_NOT_DRAFT: only a draft is published' USING ERRCODE = '23514';
    END IF;
    IF jsonb_array_length(r.sections) = 0 THEN
        RAISE EXCEPTION 'LEGAL_EMPTY: the document has no sections' USING ERRCODE = '23514';
    END IF;
    SELECT string_agg(p->>'text', ' · ' ORDER BY ord) INTO pending
      FROM jsonb_array_elements(r.review_points) WITH ORDINALITY AS t(p, ord)
     WHERE p->>'confirmed_at' IS NULL;
    IF pending IS NOT NULL THEN
        RAISE EXCEPTION 'LEGAL_REVIEW_PENDING: review points await confirmation before publication: %', pending USING ERRCODE = '23514';
    END IF;
    eff := coalesce(p_effective, r.effective_on, current_date);
    UPDATE platform.legal_document SET status = 'ARCHIVED', archived_at = now(), archive_note = 'replaced by version ' || r.version
     WHERE kind = r.kind AND status = 'PUBLISHED';
    UPDATE platform.legal_document
       SET status = 'PUBLISHED', effective_on = eff, published_at = now(), published_by = p_actor, updated_at = now(), updated_by = p_actor
     WHERE id = p_id
    RETURNING * INTO r;
    RETURN r;
END $$;

CREATE OR REPLACE FUNCTION platform.legal_document_withdraw(p_id uuid, p_actor uuid, p_acting text)
RETURNS platform.legal_document LANGUAGE plpgsql AS $$
DECLARE r platform.legal_document;
BEGIN
    PERFORM platform.legal_office_check(p_acting);
    SELECT * INTO r FROM platform.legal_document WHERE id = p_id FOR UPDATE;
    IF r.id IS NULL THEN
        RAISE EXCEPTION 'LEGAL_NOT_FOUND: no such document' USING ERRCODE = 'P0002';
    END IF;
    IF r.status <> 'DRAFT' THEN
        RAISE EXCEPTION 'LEGAL_NOT_DRAFT: only a draft is withdrawn; a published version stays until replaced' USING ERRCODE = '23514';
    END IF;
    UPDATE platform.legal_document SET status = 'ARCHIVED', archived_at = now(), archive_note = 'draft withdrawn', updated_at = now(), updated_by = p_actor
     WHERE id = p_id RETURNING * INTO r;
    RETURN r;
END $$;

-- what a person has still to accept: every published document that asks for acceptance, not yet accepted in this version
CREATE OR REPLACE FUNCTION platform.policy_acceptance_needed(p_subject_kind text, p_subject_id uuid)
RETURNS TABLE (document_id uuid, kind text, version int, title text, effective_on date, published_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT d.id, d.kind, d.version, d.title, d.effective_on, d.published_at
      FROM platform.legal_document d
     WHERE d.status = 'PUBLISHED' AND d.requires_acceptance
       AND NOT EXISTS (SELECT 1 FROM platform.policy_acceptance a
                        WHERE a.document_id = d.id AND a.subject_kind = p_subject_kind AND a.subject_id = p_subject_id AND a.withdrawn_at IS NULL)
     ORDER BY d.kind
$$;

CREATE OR REPLACE FUNCTION platform.policy_accept(p_subject_kind text, p_subject_id uuid, p_document uuid, p_ip text, p_user_agent text, p_channel text DEFAULT 'PORTAL')
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE d platform.legal_document; n int;
BEGIN
    IF p_subject_kind IS NULL OR p_subject_kind NOT IN ('STUDENT', 'STAFF', 'APPLICANT') OR p_subject_id IS NULL THEN
        RAISE EXCEPTION 'ACCEPTANCE_SUBJECT: an acceptance is a student''s, a staff member''s or an applicant''s' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO d FROM platform.legal_document WHERE id = p_document;
    IF d.id IS NULL OR d.status <> 'PUBLISHED' THEN
        RAISE EXCEPTION 'LEGAL_NOT_PUBLISHED: only the published version of a document is accepted' USING ERRCODE = '23514';
    END IF;
    INSERT INTO platform.policy_acceptance (document_id, kind, version, subject_kind, subject_id, source_ip, user_agent, channel)
    VALUES (d.id, d.kind, d.version, p_subject_kind, p_subject_id, nullif(btrim(coalesce(p_ip, '')), ''), left(nullif(btrim(coalesce(p_user_agent, '')), ''), 300),
            coalesce(p_channel, 'PORTAL'))
    ON CONFLICT (document_id, subject_kind, subject_id) DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n = 1;
END $$;

CREATE OR REPLACE FUNCTION platform.policy_acceptance_summary(p_document uuid)
RETURNS TABLE (subject_kind text, accepted bigint, withdrawn bigint, last_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT k.subject_kind,
           count(a.id) FILTER (WHERE a.withdrawn_at IS NULL), count(a.id) FILTER (WHERE a.withdrawn_at IS NOT NULL), max(a.accepted_at)
      FROM (VALUES ('STUDENT'), ('STAFF'), ('APPLICANT')) k(subject_kind)
      LEFT JOIN platform.policy_acceptance a ON a.subject_kind = k.subject_kind AND a.document_id = p_document
     GROUP BY k.subject_kind ORDER BY k.subject_kind
$$;

-- ── 5 · the governance request log takes the policy's requests ──────────────────────────────────────────────────────
ALTER TABLE governance.dsr DROP CONSTRAINT ck_dsr_kind;
ALTER TABLE governance.dsr ADD CONSTRAINT ck_dsr_kind
    CHECK (kind IN ('ACCESS', 'RECTIFICATION', 'ERASURE', 'PORTABILITY', 'OBJECTION', 'COMPLAINT', 'INQUIRY'));
ALTER TABLE governance.dsr
    ADD COLUMN subject_kind text NULL,
    ADD COLUMN subject_id   uuid NULL,
    ADD COLUMN contact      text NULL,
    ADD COLUMN detail       text NULL,
    ADD COLUMN filed_via    text NOT NULL DEFAULT 'OFFICE',
    ADD CONSTRAINT ck_dsr_subject CHECK (subject_kind IS NULL OR subject_kind IN ('STUDENT', 'STAFF', 'APPLICANT')),
    ADD CONSTRAINT ck_dsr_filed_via CHECK (filed_via IN ('OFFICE', 'PORTAL'));
CREATE INDEX ix_dsr_subject ON governance.dsr (subject_kind, subject_id) WHERE subject_id IS NOT NULL;
COMMENT ON COLUMN governance.dsr.filed_via IS 'V441: OFFICE when an officer logged the request; PORTAL when the person filed it through the privacy-request screen.';

CREATE OR REPLACE FUNCTION governance.dsr_file(p_kind text, p_subject_kind text, p_subject_id uuid, p_contact text, p_detail text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE who text; ref text; days int; open_n int;
BEGIN
    IF p_kind IS NULL OR p_kind NOT IN ('ACCESS', 'RECTIFICATION', 'ERASURE', 'PORTABILITY', 'OBJECTION', 'COMPLAINT', 'INQUIRY') THEN
        RAISE EXCEPTION 'DSR_KIND: the request is one of access, rectification, erasure, portability, objection, complaint or inquiry' USING ERRCODE = '23514';
    END IF;
    IF p_subject_kind IS NULL OR p_subject_kind NOT IN ('STUDENT', 'STAFF', 'APPLICANT') OR p_subject_id IS NULL THEN
        RAISE EXCEPTION 'DSR_SUBJECT: a request filed through the portal is the signed-in person''s own' USING ERRCODE = '23514';
    END IF;
    IF p_detail IS NULL OR length(btrim(p_detail)) < 10 THEN
        RAISE EXCEPTION 'DSR_DETAIL: say what you ask, in at least a few words' USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO open_n FROM governance.dsr WHERE subject_kind = p_subject_kind AND subject_id = p_subject_id AND state IN ('RECEIVED', 'IN_PROGRESS');
    IF open_n >= 5 THEN
        RAISE EXCEPTION 'DSR_OPEN_LIMIT: five of your requests are still open; wait for an answer before filing another' USING ERRCODE = '23514';
    END IF;
    who := CASE p_subject_kind
             WHEN 'STUDENT' THEN (SELECT s.surname || ', ' || s.other_names || ' (' || coalesce(s.matric_no, s.admission_no, s.jamb_reg_no, '') || ')' FROM people.student s WHERE s.id = p_subject_id)
             WHEN 'STAFF' THEN (SELECT p.surname || ', ' || p.given_names || ' (' || coalesce(p.staff_number, '') || ')' FROM iam.person p WHERE p.id = p_subject_id)
             ELSE (SELECT c.surname || ', ' || c.other_names || ' (' || coalesce(c.jamb_reg_no, c.admission_no, '') || ')'
                     FROM admissions.applicant_account a JOIN admissions.candidate c ON c.id = a.candidate_id WHERE a.id = p_subject_id)
           END;
    who := coalesce(who, initcap(lower(p_subject_kind)) || ' ' || left(p_subject_id::text, 8));
    SELECT request_days INTO days FROM platform.privacy_contact WHERE id = true;
    ref := 'DSR-' || to_char(current_date, 'YYYY') || '-' || lpad(platform.next_number('DSR', 'UNIVERSITY', to_char(current_date, 'YYYY'))::text, 4, '0');
    INSERT INTO governance.dsr (reference, kind, requester, received_on, due_on, state, subject_kind, subject_id, contact, detail, filed_via)
    VALUES (ref, p_kind, left(who, 200), current_date, current_date + coalesce(days, 30), 'RECEIVED', p_subject_kind, p_subject_id,
            left(nullif(btrim(coalesce(p_contact, '')), ''), 200), left(btrim(p_detail), 4000), 'PORTAL');
    RETURN ref;
END $$;
COMMENT ON FUNCTION governance.dsr_file(text, text, uuid, text, text) IS 'V441: a privacy request filed by the signed-in person; logged on the governance request log under its own reference, due in the privacy contact''s period.';

CREATE OR REPLACE FUNCTION governance.dsr_mine(p_subject_kind text, p_subject_id uuid)
RETURNS TABLE (reference text, kind text, received_on date, due_on date, state text, detail text)
LANGUAGE sql STABLE AS $$
    SELECT reference, kind, received_on, due_on, state, detail FROM governance.dsr
     WHERE subject_kind = p_subject_kind AND subject_id = p_subject_id ORDER BY received_on DESC, reference DESC
$$;

-- ── 6 · the register's CBT row, as the engine is ────────────────────────────────────────────────────────────────────
-- V075 seeded "Biometric identity verification at CBT"; the engine (V364) uses the camera only with the candidate's consent,
-- computes presence and face signals in the browser and keeps the events — no video, image or biometric template is stored.
UPDATE governance.processing_activity
   SET activity = 'Camera presence signals at CBT (by consent; no video or image kept)',
       note = coalesce(note || ' ', '') || 'V441: restated to what the engine does — the camera only with the candidate''s consent, presence and face signals computed in the browser, only the events kept; no biometric template, video or image is stored.'
 WHERE activity = 'Biometric identity verification at CBT';

-- ── 7 · the Privacy Policy, version 1, as a draft ───────────────────────────────────────────────────────────────────
INSERT INTO platform.legal_document (kind, version, status, title, summary, sections, review_points, requires_acceptance, created_by, updated_by)
VALUES ('PRIVACY_POLICY', 1, 'DRAFT', 'Privacy Policy',
        $sum$This policy explains what personal information the {{university}} collects through its portal, why, how it is used, kept and protected, who may see it, when it is shared, and what you can ask of the University about it. It covers applicants, students, staff, lecturers, alumni and everyone else who signs in. It describes the portal as it is.$sum$,
        $json$[
 {
  "key": "introduction",
  "heading": "Introduction",
  "body": "The {{university}} (\"the University\", \"we\") operates this portal for its applicants, students, staff, lecturers, alumni and the offices that serve them. The portal holds personal, academic, financial, identification, examination, document and administrative information. This Privacy Policy explains how that information is collected, used, stored, protected, shared and retained, and the rights you have in relation to it.\n\nThe University processes personal data in accordance with applicable data protection laws and regulations, including the Nigeria Data Protection Act 2023. This policy was written from an inventory of what the portal actually holds; it describes the portal as built, not a portal in general.\n\nPlease read it together with any notice given to you on a particular screen (for example, the camera consent before a computer-based examination, or the facts you choose to share with the University clinic)."
 },
 {
  "key": "about",
  "heading": "About the University",
  "body": "{{university}} ({{short_name}}), {{address}}. Telephone {{phone}}; e-mail {{email}}; website {{website}}.\n\nThe portal is run by the University's Directorate of ICT on behalf of the University. Questions about this policy and about your personal information go to the University's privacy contact named in the section \"Contact information\"."
 },
 {
  "key": "scope",
  "heading": "Scope of this Privacy Policy",
  "body": "This policy applies to personal information processed through the portal and the services reached from it: the application and admission screens (Post-UTME, Direct Entry, part-time (CCE), postgraduate and JUPEB), the student, staff, lecturer and applicant portals, payments started from the portal, computer-based examinations, document verification pages, support tickets, and the e-mail, SMS and in-portal notices the portal sends.\n\nIt applies to everyone who uses the portal: applicants, students, staff, lecturers, external examiners, alumni, and the offices of the University acting through it. It does not cover the University's public website or other systems, except where those pass information to the portal (for example the admission lists the University receives from JAMB)."
 },
 {
  "key": "information_collected",
  "heading": "Information we collect",
  "body": "Depending on your relationship with the University, the portal may hold:\n\n- Identity information: full name, sex, date of birth, passport photograph, nationality and state of origin, local government area where an application form asks for it, JAMB registration number, application number, admission number, matriculation number, staff number, and the National Identification Number where a form lawfully requires it (at present the JUPEB application form only).\n- Contact information: e-mail address, phone number, contact or residential address, and next of kin or guardian details where a form asks for them.\n- Academic information: faculty, department, programme, level, session, semester, course registrations, attendance, results, CGPA, academic standing, examination attempts, deferments, transfers, clearance and graduation records.\n- Financial information: fee references, invoices, amounts, purposes, payment status and dates, the payment provider's transaction references, refunds and, for refunds and wallet withdrawals, the bank name and account number you give.\n- Admission information: the information on your application, the lists received from JAMB, screening and O'Level details, uploaded documents, admission decisions and letters.\n- Documents you upload or the University issues: certificates, results, birth certificates, certificates of origin, passport photographs, supporting documents, and the documents the University issues to you.\n- Health information you choose to record with the University clinic, and the clinic's own records of your visits.\n- Examination information from computer-based tests, including technical events during an attempt.\n- Support, notice and communication records: tickets you raise, messages the portal sends you and their delivery state, and your notification preferences.\n- Technical information needed to keep you signed in and the portal secure: sign-in events, session records, the network address and browser a request came from, and the audit trail of changes made in your name or to your record."
 },
 {
  "key": "how_collected",
  "heading": "How we collect information",
  "body": "Most information comes from you: the forms you complete, the documents you upload, the payments you start, the facts you record, and the requests you make.\n\nSome comes from the University's own processes: the offices that admit, register, teach, examine, clear and graduate you record decisions and results in your record; the Registry and the HR office upload records; lecturers enter scores and attendance.\n\nSome comes from third parties: the admission lists and candidate details the University receives from JAMB; payment confirmations from the University's payment providers; delivery reports from the SMS and e-mail services; and, for JUPEB, registration outcomes from the JUPEB Board.\n\nThe portal also generates information about your use of it: sign-in events, sessions, examination events and the audit trail."
 },
 {
  "key": "why_collected",
  "heading": "Why we collect personal information",
  "body": "The University collects and uses personal information to:\n\n- consider applications and admit candidates;\n- register students, allocate courses and lecturers, keep attendance and deliver teaching;\n- conduct and secure examinations, including computer-based tests, and publish results;\n- state, collect and account for fees and other charges, and pay refunds;\n- issue identity cards, admission letters, transcripts, certificates and other documents, and let their authenticity be verified;\n- allocate accommodation and run library, health and student-affairs services;\n- clear students at entry and at graduation, and keep alumni relations;\n- employ, pay and manage staff and lecturers;\n- communicate official matters by e-mail, SMS and in-portal notices;\n- resolve support requests;\n- keep the University's records accurate, complete and auditable; and\n- protect the portal and the people who use it from misuse."
 },
 {
  "key": "legal_basis",
  "heading": "Legal and institutional basis for processing",
  "body": "Different activities rest on different bases. The University's record of processing activities, kept by the Registrar and reviewed by the Data Protection Officer, states the basis for each activity. In summary:\n\n- Academic records, admission, examinations, results, clearance and graduation: the University's public task and its legal obligations as a university established by law.\n- Staff and payroll records: the contract of employment and the University's legal obligations.\n- Payment and financial records: legal obligations, including tax and audit requirements.\n- Health facts you record with the clinic, and the use of your camera during a computer-based examination: your explicit consent, which you may withhold or withdraw as described in the relevant sections.\n- Security logging of sign-ins, sessions and examination attempts: the University's legitimate interest in protecting its systems and the integrity of its examinations, and its public task.\n\nConsent is not the basis for every activity. Where the basis is consent, the University records when it was given and respects its withdrawal. Where the basis is a public task, a legal obligation or a contract, a request to delete official records cannot be granted while the University is required to keep them."
 },
 {
  "key": "categories",
  "heading": "Categories of personal data",
  "body": "The portal distinguishes:\n\n- Ordinary personal data: identity, contact, academic, admission, accommodation, library, support and communication information.\n- Sensitive data: health information held by the University clinic; financial identifiers such as bank account numbers given for refunds; the National Identification Number where a form requires it; payroll and pension details of staff.\n- Confidential University records: passwords (held only as one-way hashes that nobody can read), the audit trail, and signed check codes on documents.\n\nSensitive data is held under stricter access, described in the sections on health, financial information and data security."
 },
 {
  "key": "students_applicants",
  "heading": "Student and applicant information",
  "body": "An applicant's account holds the e-mail address, phone number and password chosen at registration, the application form (including next of kin), the uploaded documents, the screening form and score, the admission decision, the fees paid and the letters issued. The portal records when the applicant signed in, declared the application and accepted an offer, with the network address at the time, as evidence of the applicant's own act.\n\nA student's record holds identity and contact details, the passport photograph, programme and status, registrations, attendance, results, standing, fees, accommodation, library, clearance and graduation records, deferments and transfers, support tickets and the notices sent.\n\nThe portal keeps a student's record once, under a matriculation number; an applicant admitted again is linked to the same record, never made twice, and a duplicate found later is resolved by the Registry with both records kept."
 },
 {
  "key": "staff",
  "heading": "Staff and lecturer information",
  "body": "For staff and lecturers the portal holds the staff number, names, e-mail and phone, the HR record (PNO, sex, date of first appointment, rank and step, department, salary scale), payroll and pension details, the staff photograph for the identity card, course allocations and workloads, the results and attendance a lecturer enters, and the record of what each person did in the portal (the audit trail). The HR office keeps the HR record; each person sees their own; heads of unit see names, ranks and allocations.\n\nExternal examiners and referees are held with their names, e-mail and phone for the engagement only."
 },
 {
  "key": "academic",
  "heading": "Academic information",
  "body": "Course registrations, scores, grades, results, CGPA, academic standing, attendance, deferments, transfers, programme corrections, clearance and graduation are the University's academic record. Results move through a chain of offices (the lecturer, the department, the faculty, Exams and Records, the Senate stage) and are published to the student once approved; corrections to a published result go through the same chain as amendments, and the earlier state is kept.\n\nAttendance is recorded per lecture (present, absent, late, excused) for academic administration and, where a programme enables it, for examination eligibility.\n\nAcademic records are permanent. Previous registrations, results, scores, transcripts and examination history are never deleted."
 },
 {
  "key": "admission",
  "heading": "Admission information",
  "body": "For Post-UTME, Direct Entry, part-time (CCE), postgraduate and JUPEB admissions the portal processes the information on your application, the candidate lists the University receives from JAMB (registration number, scores, subjects, programme applied for, sex, state and local government area), O'Level results, screening forms and scores, uploaded documents, programme changes, admission decisions, acceptance and admission letters.\n\nAdmission decisions are made by the University's admission processes; where the portal scores or ranks candidates it does so from the published cut-off marks and requirements, and the decision is released by the responsible office."
 },
 {
  "key": "financial",
  "heading": "Financial and payment information",
  "body": "The portal processes fee references and the payments against them: school fees, application, checking and acceptance fees, GST and EPS, hostel, transcript, certificate, deferment, transfer and other University charges. It records the amount, purpose, session, status, channel, dates and the payment provider's transaction reference, and issues receipts.\n\nThe portal does not hold card details. When you pay by card or bank transfer online you enter those details on the payment provider's own page; the provider confirms the payment to the portal. Payments at the bank go through Interswitch PAYDirect against your reference. The Bursary remains the University's financial authority: a payment is recognised only on the provider's or the bank's confirmation, and refunds are paid by the Bursary to the bank account you give for that purpose.\n\nFinancial records are kept for the periods the law requires."
 },
 {
  "key": "identification",
  "heading": "Identification information",
  "body": "The portal holds the numbers that identify you (JAMB, application, admission, matriculation, staff numbers), your passport photograph, and the documents you upload to prove identity, origin or qualification. These are used to identify you across the portal, to issue identity cards and documents, and to let an issued document be verified.\n\nYour own number is never shown as a password after you have chosen one, and the portal never shows your password to anyone, including ICT Support."
 },
 {
  "key": "health",
  "heading": "Health and clinic information",
  "body": "Health information is sensitive. The portal holds the facts you choose to record with the University clinic (blood group, genotype, allergies), your appointments, the clinic's record of your visits and the outcome of each, and a fitness status where one is required.\n\nOnly the University Health Services see clinical records. The Registry and your department see the fitness status and nothing else. You see the outcome of each visit and the facts you recorded, and you may restrict those facts at any time. Students, lecturers, heads of department, deans, the Bursary, ICT Support and general administrative users do not see clinic records.\n\nEvery opening of a patient record by a clinician is logged against the clinician, and the log can be shown to you on request."
 },
 {
  "key": "examinations",
  "heading": "Examination and CBT information",
  "body": "For computer-based examinations the portal records the registration, the attempt (the paper served, the answers and the times they were given, the submission time, the score and the result), the network address and browser of the attempt, and technical events during it: tab switches, loss of window focus, leaving full screen, network disconnection and reconnection, copy, paste and right-click attempts, a second sign-in replacing the session, and the warnings and outcomes the engine issued. Invigilators and examiners see these to decide on incidents and time allowances.\n\nWhere an examination asks for camera proctoring, the camera is used only with your consent, given on the screen before the paper opens. Presence and face signals (a face not seen, more than one face, a face at the edge of the view) are computed in your browser and only those signals are kept as events; no video, image or biometric template is recorded or stored. Without your consent the examination is written without the camera, under the examination's own rules.\n\nExamination records are kept with the academic record; attempt and session logs for the period the University's register states."
 },
 {
  "key": "attendance",
  "heading": "Attendance information",
  "body": "Lecturers mark attendance per lecture: the course, the student, the date and time, and the status (present, absent, late or excused), with any change recorded. Attendance is used for academic administration, standing and, where a programme enables it, examination eligibility. You see your own attendance; your lecturer and department see the register."
 },
 {
  "key": "hostel",
  "heading": "Hostel and student affairs information",
  "body": "Where you apply for University accommodation the portal records the application, the allocation (hall, room, bed), fees, check-in and check-out, inspections and any disciplinary record. Housing, Student Affairs, the hall's wardens, Security (occupancy) and the Bursary (fees) see what their duties require. Library loans, reservations and fines, and SIWES placements, are recorded for those services."
 },
 {
  "key": "support",
  "heading": "ICT support and ticket information",
  "body": "When you raise a support ticket the portal records your name, number, e-mail and phone, the subject and description, any attachment, the actions taken, and the office a ticket was escalated to. Tickets are seen by the agents of the queue they belong to, by the escalated office and by you. Support actions are authorised and recorded on the server; ICT Support cannot read your password, mark a payment as paid or approve a refund."
 },
 {
  "key": "documents",
  "heading": "Documents and uploaded files",
  "body": "Documents you upload (O'Level certificates and results, birth certificates or declarations, certificates of origin, passport photographs, academic and medical documents where required, supporting documents) and the documents the University issues are kept as files with their type, size and a checksum, in the University's database or in object storage the Directorate of ICT configures. Files are served only to the offices whose work needs them and to you; they are never public. A document the University issues carries a signed check code so that its authenticity can be confirmed on the verification page without exposing your record."
 },
 {
  "key": "communication",
  "heading": "E-mail, SMS and portal notifications",
  "body": "The University uses e-mail, SMS and in-portal notices for official communication: admission, application, payment, course registration, school fees, results, examinations, clearance, biodata updates, portal announcements, support tickets, security notices and other University matters. Messages are generated by the portal's notification engine from your record; each message, its channel, recipient address and delivery state are kept, and a message cancelled before sending is marked, never deleted.\n\nWhere the University requires you to complete or update your biodata, it may remind you by these channels; such reminders are necessary to keep the University's records accurate. You may state channel preferences where the University allows a choice; official notices are sent regardless of marketing-style preferences, because they concern your record."
 },
 {
  "key": "cookies",
  "heading": "Cookies and similar technologies",
  "body": "The portal uses essential cookies only:\n\n- moaum_session — keeps you signed in; it holds your session token, is not readable by scripts (HttpOnly), is sent only to the portal (SameSite=Lax) and only over HTTPS in production.\n- moaum_office — the office you are acting as, so that each screen shows the right menu.\n- moaum_jupeb — a JUPEB applicant's session.\n\nCookies expire with your session. The portal sets no advertising cookies and uses no third-party analytics or tracking tools. Your browser's own storage keeps a few conveniences on your device that are not sent to the server: the idle-timeout clock shared between your tabs, a computer-based test's answers kept on the device until they are submitted, your chosen text size, and recent searches. Clearing your browser's data removes them."
 },
 {
  "key": "third_parties",
  "heading": "Third-party services",
  "body": "The University engages service providers to deliver parts of the portal. Each receives only what its service needs:\n\n{{providers}}\n\n- Hosting and object storage: the portal runs on cloud infrastructure engaged by the University; uploaded files are kept in the University's database or in S3-compatible object storage the Directorate of ICT configures.\n\nProviders act on the University's instructions under their terms of service. The University does not sell personal information."
 },
 {
  "key": "sharing",
  "heading": "Data sharing",
  "body": "Within the University, information is shared with the offices whose responsibilities require it, through role-based access bound to each office's scope: Admissions, the Academic Office, the Registry, the Bursary and Audit, the Directorate of ICT, faculties and departments (their own students and staff), Exams and Records, the Library, University Health Services, Student Affairs and Housing, Security, the School of Postgraduate Studies, the JUPEB and CCE offices, HR, the Alumni office, and the Vice-Chancellor's office. Access is not unrestricted: each office reaches the screens of its own duties, every change is attributed to the person who made it, and reading of sensitive records is logged.\n\nOutside the University, information is shared only where necessary and lawful: with JAMB for admissions, with the JUPEB Board for JUPEB registrations and results, with NELFUND for loan-funded fees, with the payment, SMS and e-mail providers named above, with the hosting and storage providers that run the portal, with regulatory and accreditation bodies that lawfully require it, and with the recipients you name when you ask the University to send a transcript or document to them."
 },
 {
  "key": "security",
  "heading": "Data security",
  "body": "The portal protects personal information with measures that are actually in place:\n\n- Sign-in with a password held only as a one-way hash (bcrypt), with lock-out after repeated failures and limits on public doors.\n- Sessions held on the server, with an idle timeout set by the Directorate of ICT and an absolute end; a session is ended on the server, not only in the browser.\n- HTTPS in production; the session cookie is HttpOnly, SameSite and Secure.\n- Access by office and scope, enforced on the server for every request, never only by hiding buttons.\n- A tamper-evident audit trail: every change records who made it, as which office, why, from where, with the state before and after, chained by hash and verified.\n- Sensitive records kept apart: clinic records visible to the clinic only, with reads logged; passwords unreadable; provider credentials encrypted at rest.\n- Uploaded files stored with a checksum and served only to those entitled.\n- Backups and recovery drills recorded by the Directorate of ICT; a security-posture screen for the responsible offices.\n\nNo system is perfectly secure. The University does not claim any particular security certification. If you believe your account has been misused, change your password and contact ICT Support at once."
 },
 {
  "key": "retention",
  "heading": "Data retention",
  "body": "The University keeps personal information for as long as its purposes and the law require:\n\n- Academic records (admission, registration, results, transcripts, examination history, graduation) are permanent.\n- Staff records are kept for the duration of service and the statutory period after it.\n- Payment and financial records are kept for the statutory (tax and audit) retention period.\n- Clinic records are kept for seven years after the last contact.\n- Computer-based examination attempt and session logs are kept for five years; automated admission scoring for seven years.\n- Support tickets, notices, sign-in and session records and the audit trail are kept for accountability and dispute resolution.\n\nThe portal runs no automatic deletion. Records are ended, archived or superseded with the reason, and earlier versions are kept. Retention periods beyond those above are set by the University's record of processing activities; where it names none, the record is kept while it stands."
 },
 {
  "key": "accuracy",
  "heading": "Data accuracy",
  "body": "You are responsible for the accuracy of the information you give. You may update your own contact details, your passport photograph (once, at first) and the biodata the University asks you to complete, through the portal. Official records — your matriculation number, admission decision, results, financial transactions and examination records — are changed only by the responsible office through its own process, with the change recorded. If you find an error in an official record, ask the responsible office or make a correction request under this policy."
 },
 {
  "key": "rights",
  "heading": "Your rights",
  "body": "Where applicable under applicable law, you have the right:\n\n- to be informed about how your personal information is processed (this policy);\n- to access the personal information the University holds about you;\n- to have inaccurate information corrected and incomplete information completed;\n- to object to processing, or to ask for it to be restricted, where the law allows;\n- to receive the information you provided in a portable form, where the law allows;\n- to withdraw consent where consent is the basis of the processing (for example the facts recorded with the clinic, or the camera at an examination), without affecting what was done before the withdrawal; and\n- to lodge a complaint with the University's privacy contact and, where applicable, with the data protection authority.\n\nNot every right applies in every circumstance: the University cannot delete or alter official academic, financial or examination records it is required to keep, and a request may be refused where the law provides."
 },
 {
  "key": "requests",
  "heading": "Access and correction requests",
  "body": "You may ask to access, correct or update your information, object to or restrict processing, or make a data-protection inquiry, through the portal's privacy-request screen when signed in, or by writing to the privacy contact below. Each request is logged with a reference and a due date, and routed to the University's privacy office, which may ask you to confirm your identity before acting. The University aims to answer within {{request_days}} days of receipt, or any period the law prescribes.\n\nOfficial academic and financial records are not deleted on request; where a record is wrong, it is corrected through the responsible office."
 },
 {
  "key": "complaints",
  "heading": "Data protection and privacy complaints",
  "body": "If you believe the University has not handled your personal information as this policy says, raise a complaint through the privacy-request screen or with the privacy contact below. Complaints are logged, investigated and answered. Where applicable, you may also complain to the data protection authority."
 },
 {
  "key": "minors",
  "heading": "Children's and minors' data",
  "body": "Some applicants, in particular JUPEB and UTME candidates, may be under eighteen. The University processes their information for admission on the same bases as other applicants; the JUPEB application form takes the details of a parent or guardian, who may act for the applicant in matters under this policy. A parent or guardian may contact the privacy office on behalf of a minor."
 },
 {
  "key": "transfers",
  "heading": "International data transfers",
  "body": "The portal's hosting and object storage are provided by cloud providers whose infrastructure may be located outside Nigeria. Where personal information is stored or processed outside Nigeria, the University relies on the provider's contractual and technical safeguards and on the conditions applicable law sets for such transfers. No personal information is transferred outside Nigeria for any other purpose."
 },
 {
  "key": "changes",
  "heading": "Changes to this Privacy Policy",
  "body": "The University may revise this policy as the portal, its services or the law change. Each version carries a number and an effective date; the current version is published on the portal and earlier versions are kept by the University. Where a revision materially changes how your information is processed, you will be asked to read and accept the new version when you next sign in."
 },
 {
  "key": "contact",
  "heading": "Contact information",
  "body": "Privacy contact / Data Protection Officer: {{dpo_name}}, {{dpo_title}}, {{dpo_office}}. E-mail {{dpo_email}}; telephone {{dpo_phone}}; {{dpo_address}}.\n\nICT Support, for account and access matters: through the portal's support desk, or the University's switchboard at {{phone}}.\n\n{{university}}, {{address}}."
 },
 {
  "key": "effective",
  "heading": "Effective date",
  "body": "This version of the Privacy Policy takes effect on {{effective_on}} and was published on {{published_on}}."
 },
 {
  "key": "version",
  "heading": "Version",
  "body": "Version {{version}}. Previous versions are kept by the University and may be requested from the privacy contact."
 }
]$json$::jsonb,
        $json$[
 {
  "key": "compliance_statement",
  "text": "The compliance statement: the policy says the University processes personal data in accordance with applicable law including the Nigeria Data Protection Act 2023, and claims no certification — confirmed by the Data Protection Officer or legal adviser.",
  "confirmed_at": null,
  "confirmed_by": null
 },
 {
  "key": "lawful_bases",
  "text": "The lawful bases stated per activity (section 7) match the University's record of processing activities.",
  "confirmed_at": null,
  "confirmed_by": null
 },
 {
  "key": "retention",
  "text": "The retention periods (section 26) match the record of processing activities and the University's records policy.",
  "confirmed_at": null,
  "confirmed_by": null
 },
 {
  "key": "providers",
  "text": "The third-party providers (section 23) are those in use; hosting and object-storage providers are named or described correctly.",
  "confirmed_at": null,
  "confirmed_by": null
 },
 {
  "key": "transfers",
  "text": "The wording on processing outside Nigeria (section 32) is confirmed; object storage defaults to the af-south-1 region when S3 is configured.",
  "confirmed_at": null,
  "confirmed_by": null
 },
 {
  "key": "minors",
  "text": "The wording on applicants under eighteen (section 31) is confirmed.",
  "confirmed_at": null,
  "confirmed_by": null
 },
 {
  "key": "request_days",
  "text": "The period for answering requests (the privacy contact's setting, 30 days by default) is confirmed against the law.",
  "confirmed_at": null,
  "confirmed_by": null
 },
 {
  "key": "contact",
  "text": "The privacy contact (Data Protection Officer: name, title, office, e-mail, telephone) has been entered on the Privacy & data protection screen.",
  "confirmed_at": null,
  "confirmed_by": null
 }
]$json$::jsonb,
        true, '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000');

COMMIT;
