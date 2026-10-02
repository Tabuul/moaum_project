-- ═══════════════════════════════════════════════════════════════════════════
-- V310 — a file's bytes may live in an object store; the database keeps the fact of the file
--
--   Every uploaded file — passports, applicant and postgraduate documents, course materials and
--   submissions, service-request and helpdesk attachments, deferment documents, staff photographs,
--   examiner files — has been a bytea column in PostgreSQL. On AWS the bytes move to a private S3
--   bucket; here the schema learns to hold either: each file row gains object_id, its bytes column
--   may be NULL, and platform.file_object records every object (key, type, size, SHA-256, owner).
--   With no object store configured nothing changes: the API keeps writing the bytes, and reads them.
--   The move of the existing files is done by the API's FileMigrationJob, a row at a time, verified.
--
--   Not moved: platform.notice_attachment (an email's attachments, written and sent within minutes;
--   the table is on the audit spine, and a copy in S3 would outlive the notice for nothing).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE platform.file_object (
    id           uuid PRIMARY KEY,
    bucket       text NULL,
    object_key   text NOT NULL UNIQUE,
    content_type text NOT NULL,
    size_bytes   bigint NOT NULL CHECK (size_bytes >= 0),
    sha256       bytea NOT NULL,
    owner_table  text NOT NULL,
    owner_id     text NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE platform.file_object IS
  'A file whose bytes are in the object store (V310): where (object_key), what (content_type, size_bytes, sha256) and '
  'whose (owner_table, owner_id). The owning row carries object_id; its bytes column is NULL once the object is written and verified.';
CREATE INDEX ix_file_object_owner ON platform.file_object (owner_table, owner_id);
SELECT audit.attach('platform.file_object');

-- each file row: an object id, and bytes that may now be absent
ALTER TABLE admissions.application_document_blob ADD COLUMN object_id uuid NULL REFERENCES platform.file_object(id), ALTER COLUMN content DROP NOT NULL;
ALTER TABLE admissions.pg_document                ADD COLUMN object_id uuid NULL REFERENCES platform.file_object(id), ALTER COLUMN bytes   DROP NOT NULL;
ALTER TABLE admissions.pg_research_document_blob  ADD COLUMN object_id uuid NULL REFERENCES platform.file_object(id), ALTER COLUMN bytes   DROP NOT NULL;
ALTER TABLE lms.material_blob                     ADD COLUMN object_id uuid NULL REFERENCES platform.file_object(id), ALTER COLUMN content DROP NOT NULL;
ALTER TABLE lms.submission_blob                   ADD COLUMN object_id uuid NULL REFERENCES platform.file_object(id), ALTER COLUMN content DROP NOT NULL;
ALTER TABLE platform.request_document_blob        ADD COLUMN object_id uuid NULL REFERENCES platform.file_object(id), ALTER COLUMN content DROP NOT NULL;
ALTER TABLE helpdesk.ticket_attachment_blob       ADD COLUMN object_id uuid NULL REFERENCES platform.file_object(id), ALTER COLUMN content DROP NOT NULL;
ALTER TABLE people.deferment_document_blob        ADD COLUMN object_id uuid NULL REFERENCES platform.file_object(id), ALTER COLUMN bytes   DROP NOT NULL;
ALTER TABLE hrm.staff_photo                       ADD COLUMN object_id uuid NULL REFERENCES platform.file_object(id), ALTER COLUMN content DROP NOT NULL;
ALTER TABLE extexam.examiner_file_blob            ADD COLUMN object_id uuid NULL REFERENCES platform.file_object(id), ALTER COLUMN content DROP NOT NULL;
ALTER TABLE extexam.project_document_blob         ADD COLUMN object_id uuid NULL REFERENCES platform.file_object(id), ALTER COLUMN content DROP NOT NULL;
-- the JAMB passports: a base64 data URL in the payload today; object_key (V007) was made for this day
ALTER TABLE admissions.attachment                 ADD COLUMN object_id uuid NULL REFERENCES platform.file_object(id);

-- a row has its bytes, or its object, or (an upload in progress) neither; never both
ALTER TABLE admissions.application_document_blob ADD CONSTRAINT ck_appdoc_blob_one_place CHECK (NOT (content IS NOT NULL AND object_id IS NOT NULL));
ALTER TABLE admissions.pg_document                ADD CONSTRAINT ck_pg_document_one_place CHECK (NOT (bytes IS NOT NULL AND object_id IS NOT NULL));
ALTER TABLE admissions.pg_research_document_blob  ADD CONSTRAINT ck_pg_research_blob_one_place CHECK (NOT (bytes IS NOT NULL AND object_id IS NOT NULL));
ALTER TABLE lms.material_blob                     ADD CONSTRAINT ck_material_blob_one_place CHECK (NOT (content IS NOT NULL AND object_id IS NOT NULL));
ALTER TABLE lms.submission_blob                   ADD CONSTRAINT ck_submission_blob_one_place CHECK (NOT (content IS NOT NULL AND object_id IS NOT NULL));
ALTER TABLE platform.request_document_blob        ADD CONSTRAINT ck_request_blob_one_place CHECK (NOT (content IS NOT NULL AND object_id IS NOT NULL));
ALTER TABLE helpdesk.ticket_attachment_blob       ADD CONSTRAINT ck_ticket_blob_one_place CHECK (NOT (content IS NOT NULL AND object_id IS NOT NULL));
ALTER TABLE people.deferment_document_blob        ADD CONSTRAINT ck_deferment_blob_one_place CHECK (NOT (bytes IS NOT NULL AND object_id IS NOT NULL));
ALTER TABLE hrm.staff_photo                       ADD CONSTRAINT ck_staff_photo_one_place CHECK (NOT (content IS NOT NULL AND object_id IS NOT NULL));
ALTER TABLE extexam.examiner_file_blob            ADD CONSTRAINT ck_examiner_blob_one_place CHECK (NOT (content IS NOT NULL AND object_id IS NOT NULL));
ALTER TABLE extexam.project_document_blob         ADD CONSTRAINT ck_project_blob_one_place CHECK (NOT (content IS NOT NULL AND object_id IS NOT NULL));

-- ── the three functions that take the bytes: they now take the object too ──
-- The old signatures go first: with a defaulted parameter the old arity still resolves to the new
-- function, and keeping both would make every call of the old arity ambiguous.
DROP FUNCTION IF EXISTS helpdesk.attach(uuid, uuid, text, uuid, text, text, text, bigint, bytea, boolean);
DROP FUNCTION IF EXISTS platform.attach_request_document(uuid, text, text, bigint, bytea);
DROP FUNCTION IF EXISTS hrm.set_my_staff_photo(text, bigint, bytea);

CREATE OR REPLACE FUNCTION helpdesk.attach(p_ticket uuid, p_comment uuid, p_kind text, p_by uuid, p_by_name text,
                                           p_filename text, p_type text, p_bytes bigint, p_content bytea, p_internal boolean,
                                           p_object_id uuid DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE t helpdesk.ticket; v uuid := gen_random_uuid(); n int;
BEGIN
    SELECT * INTO t FROM helpdesk.ticket WHERE id = p_ticket FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no ticket %', p_ticket USING ERRCODE = 'no_data_found'; END IF;
    IF p_kind = 'REQUESTER' AND t.status = 'CLOSED' THEN
        RAISE EXCEPTION 'a closed ticket takes no more attachments' USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO n FROM helpdesk.ticket_attachment WHERE ticket_id = p_ticket AND uploaded_kind = p_kind;
    IF n >= 10 THEN RAISE EXCEPTION 'ten attachments are on the ticket already' USING ERRCODE = '23514', HINT = 'Put further evidence in an update, or combine the files.'; END IF;
    INSERT INTO helpdesk.ticket_attachment (id, ticket_id, comment_id, uploaded_kind, uploaded_by, uploader_name, filename, content_type, bytes, internal)
    VALUES (v, p_ticket, p_comment, p_kind, p_by, p_by_name, btrim(p_filename), p_type, p_bytes, coalesce(p_internal, false) AND p_kind = 'AGENT');
    INSERT INTO helpdesk.ticket_attachment_blob (attachment_id, content, object_id)
    VALUES (v, CASE WHEN p_object_id IS NULL THEN p_content END, p_object_id);
    PERFORM helpdesk.record(p_ticket, p_kind, p_by, p_by_name, 'ATTACHMENT', NULL, NULL, btrim(p_filename), coalesce(p_internal, false) AND p_kind = 'AGENT');
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION platform.attach_request_document(p_request uuid, p_filename text, p_content_type text, p_bytes bigint, p_content bytea,
                                                            p_object_id uuid DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE v_id uuid := gen_random_uuid(); who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a document is attached by a person' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM platform.service_request WHERE id = p_request) THEN
        RAISE EXCEPTION 'no such request' USING ERRCODE = '23503';
    END IF;
    IF (SELECT count(*) FROM platform.request_document WHERE request_id = p_request) >= 6 THEN
        RAISE EXCEPTION 'a request carries at most six documents' USING ERRCODE = '23514',
            HINT = 'Remove one before adding another, or raise a separate request.';
    END IF;
    INSERT INTO platform.request_document (id, request_id, filename, content_type, bytes, uploaded_by)
    VALUES (v_id, p_request, p_filename, p_content_type, p_bytes, who);
    INSERT INTO platform.request_document_blob (document_id, content, object_id)
    VALUES (v_id, CASE WHEN p_object_id IS NULL THEN p_content END, p_object_id);
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION hrm.set_my_staff_photo(p_content_type text, p_bytes bigint, p_content bytea, p_object_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a photograph is set by the person themselves' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM iam.person WHERE id = who) THEN
        RAISE EXCEPTION 'no person % on the register', who USING ERRCODE = '23503';
    END IF;
    INSERT INTO hrm.staff_photo (person_id, content_type, bytes, content, object_id, updated_at)
    VALUES (who, p_content_type, p_bytes, CASE WHEN p_object_id IS NULL THEN p_content END, p_object_id, now())
    ON CONFLICT (person_id) DO UPDATE SET
        content_type = excluded.content_type, bytes = excluded.bytes,
        content = excluded.content, object_id = excluded.object_id, updated_at = now();
END $$;

COMMIT;
