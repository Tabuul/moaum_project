-- ═══════════════════════════════════════════════════════════════════════════
-- V092 — edit and remove faculties and programmes
--
--   Editing reuses the upsert functions (V091): saving the same code changes the
--   record. Removing is careful, because faculties and programmes are referenced
--   across the estate:
--
--     · a programme is ARCHIVED by default (it keeps its code for ever, so a
--       graduate who holds it still resolves); it may be hard-deleted only when
--       nothing references it — a freshly created one entered in error.
--     · a faculty is deleted only when it holds no programme and none of its
--       departments carries a course; its empty departments go with it.
--
--   Every change is attributed on the audit spine.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- archive / unarchive a programme (the safe "remove": reversible, keeps the code)
CREATE OR REPLACE FUNCTION ref.set_programme_archived(p_code text, p_archived boolean)
RETURNS ref.programme
LANGUAGE plpgsql AS $$
DECLARE v_code text := upper(btrim(coalesce(p_code, ''))); r ref.programme;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a programme is archived by a person' USING ERRCODE = '23514';
    END IF;
    UPDATE ref.programme SET archived = coalesce(p_archived, true) WHERE code = v_code RETURNING * INTO r;
    IF r.code IS NULL THEN RAISE EXCEPTION 'no programme is coded %', p_code USING ERRCODE = '23503'; END IF;
    RETURN r;
END $$;

-- hard-delete a programme, only when nothing hangs on it
CREATE OR REPLACE FUNCTION ref.delete_programme(p_code text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_code text := upper(btrim(coalesce(p_code, '')));
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a programme is removed by a person' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM ref.programme WHERE code = v_code) THEN
        RAISE EXCEPTION 'no programme is coded %', p_code USING ERRCODE = '23503';
    END IF;
    IF EXISTS (SELECT 1 FROM people.student WHERE programme_code = v_code)
       OR EXISTS (SELECT 1 FROM catalogue.course_offer WHERE programme_code = v_code)
       OR EXISTS (SELECT 1 FROM finance.fee_schedule WHERE programme_code = v_code)
       OR EXISTS (SELECT 1 FROM admissions.programme_rule WHERE programme_code = v_code) THEN
        RAISE EXCEPTION 'programme % has records hanging on it (students, courses, fees or an admission rule) — archive it instead of deleting', v_code
            USING ERRCODE = '23514', HINT = 'Use Archive: it keeps the code so past records still resolve.';
    END IF;
    DELETE FROM ref.programme WHERE code = v_code;
END $$;

-- delete a faculty, only when it holds no programme and no course-bearing department
CREATE OR REPLACE FUNCTION ref.delete_faculty(p_code text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_code text := upper(btrim(coalesce(p_code, '')));
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a faculty is removed by a person' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM ref.faculty WHERE code = v_code) THEN
        RAISE EXCEPTION 'no faculty is coded %', p_code USING ERRCODE = '23503';
    END IF;
    IF EXISTS (SELECT 1 FROM ref.programme WHERE faculty_code = v_code) THEN
        RAISE EXCEPTION 'faculty % still has programmes — remove or move them first', v_code USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM catalogue.course c JOIN ref.department d ON d.code = c.dept_code WHERE d.faculty_code = v_code) THEN
        RAISE EXCEPTION 'faculty %s departments carry courses — remove them first', v_code USING ERRCODE = '23514';
    END IF;
    DELETE FROM ref.department WHERE faculty_code = v_code;
    DELETE FROM ref.faculty WHERE code = v_code;
END $$;

COMMIT;
