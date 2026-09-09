-- ═══════════════════════════════════════════════════════════════════════════
-- V040 — a supporting document on a Help & requests item (V036)
--
--   When a student asks an office for help, the office often needs to see the
--   evidence: a receipt, a screenshot, a letter. A request now carries up to
--   six documents. As with an applicant's documents (V021), the fact of the
--   file — its name, size, type and who attached it — sits on the audit spine;
--   the bytes themselves, up to 2 MB, sit beside it in a table exempt from the
--   spine, because a hash of a 2 MB blob on every write helps no one.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE platform.request_document (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id   uuid NOT NULL REFERENCES platform.service_request(id),
    filename     text NOT NULL,
    content_type text NOT NULL,
    bytes        bigint NOT NULL,
    uploaded_at  timestamptz NOT NULL DEFAULT now(),
    uploaded_by  uuid NULL,
    CONSTRAINT ck_rd_bytes CHECK (bytes BETWEEN 1 AND 2097152),
    CONSTRAINT ck_rd_type CHECK (content_type IN ('application/pdf','image/jpeg','image/png'))
);
CREATE INDEX ix_rd_request ON platform.request_document (request_id, uploaded_at);
SELECT audit.attach('platform.request_document');

CREATE TABLE platform.request_document_blob (
    document_id uuid PRIMARY KEY REFERENCES platform.request_document(id),
    content     bytea NOT NULL
);
SELECT audit.exempt('platform.request_document_blob',
    'The file itself, up to 2 MB; its name, size, type and who attached it are on the spine in request_document.');

-- attach a document to a request; the caller has already checked the request is
-- one the actor may touch (their own, or one their office handles)
CREATE OR REPLACE FUNCTION platform.attach_request_document(p_request uuid, p_filename text, p_content_type text, p_bytes bigint, p_content bytea)
RETURNS uuid
LANGUAGE plpgsql AS $$
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
    INSERT INTO platform.request_document_blob (document_id, content) VALUES (v_id, p_content);
    RETURN v_id;
END $$;
