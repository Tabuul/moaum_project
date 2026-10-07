-- ═══════════════════════════════════════════════════════════════════════════
-- V348 — Stored files are held by every table that points at them; the JUPEB documents lost to the orphan sweep are recorded
--        and asked for again
--
--   The file migration job (V310) removed an object from the store when none of the tables in a list written by hand pointed
--   at it. jupeb.document (V339) was never on that list and, unlike the tables V310 altered, had no foreign key to
--   platform.file_object that would have refused the removal — so every JUPEB document and passport photograph was swept
--   away an hour after it was uploaded, on the deployment that keeps files in S3. The job now asks the database which tables
--   hold object ids. Here:
--
--   · every column that keeps an object id references platform.file_object, so an object still held is never removed
--     (jupeb.document, and people.student_photo of V334, which had no rows yet);
--   · each JUPEB document whose object is gone is recorded in jupeb.document_lost — with the object's id, from which its key
--     in the store is rebuilt (jupeb/document/<application>/<object><ext>), should the bucket keep earlier versions — and
--     marked REPLACEMENT_REQUIRED with a note the candidate and the office read; the candidate uploads it again and the office
--     reviews it again. Nothing is deleted.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V348: stored files held by every table; JUPEB documents lost to the orphan sweep asked for again', true);

CREATE TABLE jupeb.document_lost (
    document_id    uuid PRIMARY KEY REFERENCES jupeb.document(id),
    application_id uuid NOT NULL REFERENCES jupeb.application(id),
    kind           text NOT NULL,
    sitting        int NULL,
    filename       text NOT NULL,
    content_type   text NOT NULL,
    lost_object_id uuid NOT NULL,
    status_before  text NOT NULL,
    uploaded_at    timestamptz NOT NULL,
    noticed_at     timestamptz NOT NULL DEFAULT now()
);
SELECT audit.attach('jupeb.document_lost');
COMMENT ON TABLE jupeb.document_lost IS 'V348: a JUPEB document whose stored object the V310 orphan sweep removed — what it was and the lost object''s id (its key in the store: jupeb/document/<application_id>/<lost_object_id><ext>; not a live pointer, so not named object_id), kept so it can be restored from a versioned bucket; the document itself was marked REPLACEMENT_REQUIRED.';
GRANT SELECT ON jupeb.document_lost TO app_auditor;
GRANT SELECT, INSERT, UPDATE ON jupeb.document_lost TO app_admissions;

WITH lost AS (
    INSERT INTO jupeb.document_lost (document_id, application_id, kind, sitting, filename, content_type, lost_object_id, status_before, uploaded_at)
    SELECT d.id, d.application_id, d.kind, d.sitting, d.filename, d.content_type, d.object_id, d.status, d.uploaded_at
      FROM jupeb.document d
     WHERE d.object_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM platform.file_object f WHERE f.id = d.object_id)
       AND NOT EXISTS (SELECT 1 FROM jupeb.document_blob b WHERE b.document_id = d.id)
    RETURNING document_id, application_id, kind, sitting
), marked AS (
    UPDATE jupeb.document d
       SET object_id = NULL, status = 'REPLACEMENT_REQUIRED',
           review_note = 'The file was lost from the University''s file storage. Please upload it again; the JUPEB Office will review it afresh.',
           reviewed_by = NULL, reviewed_at = now()
      FROM lost
     WHERE d.id = lost.document_id
    RETURNING d.application_id, d.kind, d.sitting
)
SELECT jupeb.app_event(m.application_id, 'DOCUMENT_REPLACEMENT_REQUIRED',
                       m.kind || coalesce(' (sitting ' || m.sitting || ')', '') || ' to be uploaded again: the stored file was lost')
  FROM marked m;

-- every table that keeps an object id holds it: platform.file_object refuses to forget an object still pointed at
ALTER TABLE jupeb.document ADD CONSTRAINT fk_jupeb_document_object FOREIGN KEY (object_id) REFERENCES platform.file_object(id);
ALTER TABLE people.student_photo ADD CONSTRAINT fk_student_photo_object FOREIGN KEY (object_id) REFERENCES platform.file_object(id);

COMMIT;
