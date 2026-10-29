-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V704 — Preliminary Science asks for one passport photograph, not two
--
--   The University's word of 29 October 2026, after V703 took Preliminary Technology's second and third photographs off: "remove
--   the second passport photograph from preliminary science too". V446 had taken two from the notice ("Second recent passport
--   photograph", PASSPORT_2). Preliminary Science's documents now hold one ("Recent passport photograph", PASSPORT): the public page
--   and the form stop asking for the second, the submission no longer waits on it, and an upload of it is refused as not a document
--   of the application (the API reads the route's documents). A second photograph an applicant already uploaded stays where it is,
--   on the desk under its code with the application's other files, to be accepted with them as before: nothing uploaded is
--   removed. The kind stays allowed (ck_prelim_document_kind) should the Academic Office ask for it again. Every preliminary and
--   proficiency programme now asks for one passport photograph.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V704: Preliminary Science asks for one passport photograph (the University''s word of 29 October 2026)', true);

DELETE FROM admissions.prelim_document WHERE route = 'PRELIMINARY_SCIENCE' AND kind = 'PASSPORT_2';

COMMIT;
