-- V644: a BSU- GST course is a GST course — the University's word of 23 October 2026 ("courses that start with BSU-GST 112 are still
-- gst courses allow them to print GST permit").
--   A course belongs to the GST or EPS office by the subject behind its code (catalogue.general_office_of, V368: the GST family GST,
--   GES, GNS; the EPS family ENT, EPS). catalogue.course_subject read the subject behind a MOAU- prefix but not behind BSU-, the other
--   cohort prefix (V592): BSU-GST 112 read as subject "BSU", matched no family, and kept no office. Its kind is GST, so the registration
--   gate already asked the GST fee for it (coalesce(general_office, 'GST')); but the GST/EPS engine, the GST office's desk and the
--   GST & EPS examination permit (registration.gst_eps_permit_courses, V492, V589) take a course with an office alone, and a student
--   registered on BSU-GST 112 had no permit for it.
--   Now the subject is read behind BSU- as behind MOAU-, and every GST-kind course the families now name is given its office, each
--   such change listed as a reclassification (trg_course_reclassified, V368). A course given back to its department keeps its own kind
--   and is not touched.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V644: BSU- GST courses are GST courses (the University, 23 October 2026)', true);

CREATE OR REPLACE FUNCTION catalogue.course_subject(p_code text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT substring(regexp_replace(upper(btrim(coalesce(p_code, ''))), '^(MOAU-?|BSU-)', '') FROM '^[A-Z]+')
$$;
COMMENT ON FUNCTION catalogue.course_subject(text) IS
  'V644: the subject a course code names, behind the cohort prefix — GST for GST 112, BSU-GST 112 and MOAU-GST 112 — read by catalogue.general_office_of and catalogue.set_general_family.';

-- the GST-kind courses the families now name, given their office
UPDATE catalogue.course c
   SET general_office = catalogue.general_office_of(c.code, c.title, c.kind)
 WHERE c.kind = 'GST' AND c.general_office IS NULL
   AND catalogue.general_office_of(c.code, c.title, c.kind) IS NOT NULL;

COMMIT;
