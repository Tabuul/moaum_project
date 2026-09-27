-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V283 — the letter of admission follows the Registry's own format
--
--   The letter's wording, signatory and notes are a document template (V262:
--   credentials.document_template, a new version from Credentials → Document
--   settings), not code: the title CONFIRMATION OF OFFER OF ADMISSION for the
--   session, the Deputy Registrar who signs it for the Registrar, and the six
--   notes in `remarks` (one per line; {session}, {from} and {date} are filled
--   from the record — the session, " from 5th January, 2026" when the semester's
--   registration date is stated, and that date alone).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V283: the letter of admission follows the Registry''s format', true);

INSERT INTO credentials.document_template (kind, version, title, subtitle, signatory_name, signatory_title, second_name, second_title, footer, remarks)
SELECT 'ADMISSION_LETTER', 1, 'CONFIRMATION OF OFFER OF ADMISSION', '{session} ACADEMIC SESSION',
       'Andrew Aondoakaa Anjah, MAUA, MIMC', 'Deputy Registrar, Admissions, Examinations and Records', NULL, 'For: Registrar', NULL,
       E'The University shall commence registration of Fresh Students for the First Semester of {session} Academic Session{from}.\n'
       || E'This admission is only provisional as only candidates who are successful at the screening exercise would be registered.\n'
       || E'Successfully screened candidates are to proceed and pay appropriate user charges immediately in order to validate their admission.\n'
       || E'There shall be physical screening of certificates at the faculties.\n'
       || E'Please, note that should any problem be discovered with your credentials in the course of your study, you will be required to withdraw from the University.\n'
       || 'Congratulations on your admission.'
 WHERE NOT EXISTS (SELECT 1 FROM credentials.document_template WHERE kind = 'ADMISSION_LETTER');

COMMIT;
