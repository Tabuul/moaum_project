-- ═══════════════════════════════════════════════════════════════════════════
-- V237 — the kind of course the University calls "Compulsory" is "Core"
--
--   The catalogue has named a course's kind Compulsory, Required, Elective
--   or GST since V013; the per-programme offer basis (V116) already says
--   Core. The Registry's word is Core Courses, and one word is right: the
--   kind becomes Core on every course, in the default, in the check, and in
--   every function that still wrote the old word (the department's
--   create_course, the structure import). The functions are re-created from
--   their own current definitions with the word replaced, so nothing else
--   about them changes.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'registrar', true);
SELECT set_config('moaum.reason', 'The kind of course called Compulsory is Core (V237)', true);

ALTER TABLE catalogue.course DROP CONSTRAINT ck_course_kind;
UPDATE catalogue.course SET kind = 'Core' WHERE kind = 'Compulsory';
ALTER TABLE catalogue.course ALTER COLUMN kind SET DEFAULT 'Core';
ALTER TABLE catalogue.course ADD CONSTRAINT ck_course_kind CHECK (kind IN ('Core','Required','Elective','GST'));

DO $$
DECLARE r record; n int := 0;
BEGIN
    FOR r IN
        SELECT p.oid, n.nspname, p.proname, pg_get_functiondef(p.oid) AS def
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
           AND p.prokind = 'f'
           AND pg_get_functiondef(p.oid) LIKE '%''Compulsory''%'
    LOOP
        EXECUTE replace(r.def, '''Compulsory''', '''Core''');
        n := n + 1;
        RAISE NOTICE 'V237: %.% now says Core', r.nspname, r.proname;
    END LOOP;
    RAISE NOTICE 'V237: % function(s) re-created', n;
END $$;

COMMIT;
