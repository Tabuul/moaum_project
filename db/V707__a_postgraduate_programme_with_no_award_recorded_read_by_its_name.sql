-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V707 — a postgraduate programme with no award recorded is read by its name: a PhD applicant is filed as one
--
--   The University's word of 30 October 2026, with an applicant's portal: "PhD programme coming as Master instead of PhD
--   programme" — PG/26/000119 applied for "PhD LAW", and the portal's Programme tile read Master. The postgraduate register upload
--   (V203 to V463) makes a programme for an old-portal code it does not know, named "<AWARD> <DEPARTMENT>" — "PhD LAW", "MSC
--   CHEMISTRY", "PGD SOCIOLOGY" — and records no award (ref.programme.pg_award NULL, pg_research false): on the live copy of
--   10 October 2026, 175 of the 364 postgraduate programmes in use, 69 of them PhD. V574 leaves them so — no award recorded is how
--   its merge desk tells an older code from the catalogue's — until the School merges them into the catalogue's programmes;
--   meanwhile they are open to applicants. An application is filed at its programme's award level (admissions.pg_award_level),
--   which reads no award as a Master's: a PhD applicant on "PhD LAW" was filed at 800, shown "Master", asked a Master's
--   applicant's documents (not the higher degree, V694) and no research proposal. The students on these programmes are not
--   touched: their level is the register's (1,234 of the 1,244 on the PhD ones at 900 on that copy).
--
--   Now a programme with no award recorded is read by the award its name begins with, the recorded award always first:
--   · admissions.pg_award_of(award, name) — V574's ref.programme_degree (PHD, PGD, MSC, MA, MED, MBA, MPA, LLM, …), else the first
--     word without its stops (Ph.D., M.Phil., M.Sc., …); admissions.pg_research_of(research, award, name) — a PhD or MPhil read
--     by its name is a research degree;
--   · an application to such a programme is filed at its name's level — PhD 900, PGD 700 — whichever door writes it (the public
--     form, admissions.pg_apply; the old portal's migration, V675) and when it is moved to one (trg_pg_application_programme_level,
--     after V574's alias trigger);
--   · the applications already filed at another level and not on the register are corrected (an admitted one keeps the level
--     its student was given);
--   · the API reads the award and the research degree so: the form's programme list, the applicant's portal, the referee's page,
--     the School's desk.
--   No programme's recorded award is written: the merge desk reads them as before.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'pgschool', true),
       set_config('moaum.reason', 'V707: a postgraduate programme with no award recorded read by its name (the University''s word of 30 October 2026)', true);

-- ── 1 · the award a postgraduate programme is read at ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_award_of(p_award text, p_name text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $fn$
    SELECT coalesce(nullif(upper(btrim(coalesce(p_award, ''))), ''),
                    ref.programme_degree(p_name),
                    CASE upper(regexp_replace(split_part(btrim(coalesce(p_name, '')), ' ', 1), '[.]', '', 'g'))
                         WHEN 'PHD' THEN 'PHD' WHEN 'MPHIL' THEN 'MPHIL' WHEN 'PGD' THEN 'PGD' WHEN 'MSC' THEN 'MSC' WHEN 'MA' THEN 'MA'
                         WHEN 'MED' THEN 'MED' WHEN 'LLM' THEN 'LLM' WHEN 'MBA' THEN 'MBA' WHEN 'MPA' THEN 'MPA' END)
$fn$;
COMMENT ON FUNCTION admissions.pg_award_of(text, text) IS
  'V707: the award a postgraduate programme is read at — the one recorded, else the one its name begins with (ref.programme_degree, else the first word without its stops: Ph.D., M.Phil., M.Sc.). The register upload names a programme "<AWARD> <DEPARTMENT>" and records no award.';

CREATE OR REPLACE FUNCTION admissions.pg_research_of(p_research boolean, p_award text, p_name text)
RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $fn$
    SELECT coalesce(p_research, false)
        OR (nullif(btrim(coalesce(p_award, '')), '') IS NULL AND admissions.pg_award_of(NULL, p_name) IN ('PHD', 'MPHIL'))
$fn$;
COMMENT ON FUNCTION admissions.pg_research_of(boolean, text, text) IS
  'V707: whether a postgraduate programme is a research degree — as recorded, or, with no award recorded, a PhD or MPhil by its name.';

-- ── 2 · an application filed at its programme's level, read by the name when no award is recorded ─────────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_application_level_named()
RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE v_award text; v_name text; v_named text;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.programme_code IS NOT DISTINCT FROM OLD.programme_code THEN
        RETURN NEW;
    END IF;
    SELECT g.pg_award, g.name INTO v_award, v_name FROM ref.programme g WHERE g.code = NEW.programme_code;
    v_named := admissions.pg_award_of(NULL, v_name);
    IF nullif(btrim(coalesce(v_award, '')), '') IS NULL AND v_named IS NOT NULL THEN
        NEW.entry_level := admissions.pg_award_level(v_named);
    END IF;
    RETURN NEW;
END $fn$;
COMMENT ON FUNCTION admissions.pg_application_level_named() IS
  'V707: an application to a postgraduate programme with no award recorded is filed at the level of the award its name begins with (PhD 900, PGD 700), whichever door writes it; a programme with an award recorded is left to the door, as before.';

DROP TRIGGER IF EXISTS trg_pg_application_programme_level ON admissions.pg_application;
-- named after trg_pg_application_programme_alias, so it reads the programme an old code lands on (V574)
CREATE TRIGGER trg_pg_application_programme_level
    BEFORE INSERT OR UPDATE OF programme_code ON admissions.pg_application
    FOR EACH ROW EXECUTE FUNCTION admissions.pg_application_level_named();

-- ── 3 · the applications already filed at another level, not on the register, corrected ────────────────────────────────
DO $$
DECLARE v_fixed int; v_admitted int;
BEGIN
    WITH wrong AS (
        SELECT a.id, admissions.pg_award_level(admissions.pg_award_of(NULL, g.name)) AS lvl, a.student_id
          FROM admissions.pg_application a
          JOIN ref.programme g ON g.code = a.programme_code
         WHERE nullif(btrim(coalesce(g.pg_award, '')), '') IS NULL
           AND admissions.pg_award_of(NULL, g.name) IS NOT NULL
           AND a.entry_level IS DISTINCT FROM admissions.pg_award_level(admissions.pg_award_of(NULL, g.name))),
    fixed AS (
        UPDATE admissions.pg_application a SET entry_level = w.lvl FROM wrong w WHERE a.id = w.id AND w.student_id IS NULL RETURNING a.id)
    SELECT (SELECT count(*) FROM fixed), (SELECT count(*) FROM wrong WHERE student_id IS NOT NULL) INTO v_fixed, v_admitted;
    RAISE NOTICE 'V707: % postgraduate application(s) filed at their programme''s level by its name; % admitted left at their student''s level', v_fixed, v_admitted;
END $$;

COMMIT;
