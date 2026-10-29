-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V703 — Preliminary Technology & Industrial Studies asks for one passport photograph, not three
--
--   The University's word of 29 October 2026, on the documents Preliminary Technology's public page and form list: "remove
--   Passport photograph (2 of 3), Passport photograph (3 of 3) from the upload of Required documents". V701 had taken the three
--   from the programme's procedure. Its documents now hold one passport photograph (PASSPORT, "Passport photograph"), as
--   Preliminary Science's first one reads; PASSPORT_2 and PASSPORT_3 are no longer among them, so the public page and the form
--   stop asking for them, the submission no longer waits on them, and an upload of either is refused as not a document of the
--   application (the API reads the route's documents). A photograph an applicant already uploaded under either stays where it
--   is, on the desk with the application's other files: nothing uploaded is removed. The kinds stay allowed (ck_prelim_document_kind)
--   should the Academic Office ask for them again. Preliminary Science and the proficiency courses are not touched.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V703: Preliminary Technology asks for one passport photograph (the University''s word of 29 October 2026)', true);

DELETE FROM admissions.prelim_document WHERE route = 'PRELIMINARY_TECHNOLOGY' AND kind IN ('PASSPORT_2', 'PASSPORT_3');

UPDATE admissions.prelim_document
   SET label = 'Passport photograph', hint = 'A clear, recent JPEG photograph on a plain background.'
 WHERE route = 'PRELIMINARY_TECHNOLOGY' AND kind = 'PASSPORT' AND label = 'Passport photograph (1 of 3)';

COMMIT;
