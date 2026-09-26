-- ═══════════════════════════════════════════════════════════════════════════
-- V274 — the screening form takes no passport photograph: it comes from JAMB
--
--   The applicant's photograph is the one JAMB sent with the admission list
--   (admissions.attachment, kind PASSPORT), shown on every screen. The online
--   screening form asked for another upload and required it; it no longer
--   does. Existing policies lose the requirement; new ones never carry it.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V274: the screening passport comes from JAMB', true);

ALTER TABLE admissions.screening_policy ALTER COLUMN required_documents SET DEFAULT ARRAY['OLEVEL_STATEMENT', 'JAMB_SLIP', 'BIRTH_CERT', 'LGA_ID'];
UPDATE admissions.screening_policy SET required_documents = array_remove(required_documents, 'PASSPORT'), updated_at = now() WHERE 'PASSPORT' = ANY (required_documents);

COMMIT;
