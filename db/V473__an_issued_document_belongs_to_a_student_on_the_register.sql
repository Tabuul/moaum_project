-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V473 — An issued document belongs to a student on the register
--
--   · credentials.issued.student_id had no foreign key — the one table of the documents that lacked it (certificate,
--     transcript_request, identity_card and event all reference people.student). A document could name a student not on
--     the register; nothing could then be logged against it (credentials.event's own key refuses), so its flag could not be
--     cleared nor the document reissued. On the live-shaped copy of 13 Oct 2026 none does (11 documents, each with its
--     student or applicant). The only way a student leaves the register is the operational reset, which removes the
--     documents with them; no merge of student records exists (V429 keeps one student per candidate), so no document ever
--     needs to move to another student.
--   · The key, DEFERRABLE INITIALLY DEFERRED: the reset deletes the students before the documents, in one transaction.
--     Where a database already holds documents of students no longer on the register, the key is added NOT VALID — every
--     new or changed document is held to it, nothing stops the deploy — and credentials.orphaned_documents() lists them for
--     the Registry to put right.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V473: an issued document belongs to a student on the register', true);

DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM credentials.issued i
     WHERE i.student_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM people.student s WHERE s.id = i.student_id);
    IF n = 0 THEN
        ALTER TABLE credentials.issued ADD CONSTRAINT issued_student_id_fkey
            FOREIGN KEY (student_id) REFERENCES people.student(id) DEFERRABLE INITIALLY DEFERRED;
    ELSE
        ALTER TABLE credentials.issued ADD CONSTRAINT issued_student_id_fkey
            FOREIGN KEY (student_id) REFERENCES people.student(id) DEFERRABLE INITIALLY DEFERRED NOT VALID;
        RAISE NOTICE 'V473: % issued document(s) name a student no longer on the register; the key holds every new one, and credentials.orphaned_documents() lists them', n;
    END IF;
END $$;
COMMENT ON CONSTRAINT issued_student_id_fkey ON credentials.issued IS
  'V473: an issued document names a student on the register — deferred to the end of the transaction, as the operational reset deletes students before documents.';

CREATE OR REPLACE FUNCTION credentials.orphaned_documents()
RETURNS TABLE(id uuid, kind text, number text, verification_code text, student_id uuid, issued_on date, holder text)
LANGUAGE sql STABLE AS $fn$
    SELECT i.id, i.kind, i.number, i.verification_code, i.student_id, i.issued_on, i.statement->>'holder'
      FROM credentials.issued i
     WHERE i.student_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM people.student s WHERE s.id = i.student_id)
     ORDER BY i.issued_on, i.kind
$fn$;
COMMENT ON FUNCTION credentials.orphaned_documents() IS
  'V473: the issued documents naming a student no longer on the register (none where the key was validated) — for the Registry to put right.';

COMMIT;
