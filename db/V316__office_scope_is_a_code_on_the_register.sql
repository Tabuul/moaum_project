-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V316 — a bounded office grant names its department, faculty, programme or course by CODE
--
--   The grant console took "Which one" as free text, so a Head of Department was granted over
--   "MATHEMATICS AND COMPUTER SCIENCE" or "B.A. ENGLISH" rather than MTC or ENG, an Examinations
--   Officer over "B.Sc. COMPUTER SCIENCE" rather than C00023 — and every desk that scopes itself by
--   the grant (the HOD dashboard, the sheets, the structure ladder, the statistics) read a code that
--   matched nothing and showed "not tied to a department yet". Only the grants typed as codes worked.
--
--   The console now chooses from the register. This migration makes the register the rule for every
--   path: iam.scope_code resolves a scope by code, then by name (a department scope also by the name of
--   one of its programmes; a programme scope also by the name of a department with exactly one live
--   programme); a trigger stores the code and refuses a name the register does not know; and the
--   grants already on record are rewritten to their codes where they resolve. The one that does not
--   resolve is left as it is and listed by the console as it always was.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V316: office scopes stored as codes on the register', true);

CREATE OR REPLACE FUNCTION iam.scope_code(p_kind text, p_id text)
RETURNS text LANGUAGE sql STABLE AS $$
    WITH v AS (SELECT btrim(coalesce(p_id, '')) AS raw, upper(btrim(coalesce(p_id, ''))) AS up)
    SELECT CASE
        WHEN v.raw = '' THEN NULL
        WHEN p_kind = 'department' THEN coalesce(
            (SELECT code FROM ref.department WHERE upper(code) = v.up),
            (SELECT code FROM ref.department WHERE upper(name) = v.up ORDER BY ended_on IS NOT NULL, code LIMIT 1),
            (SELECT dept_code FROM ref.programme WHERE upper(name) = v.up ORDER BY archived, code LIMIT 1))
        WHEN p_kind = 'faculty' THEN coalesce(
            (SELECT code FROM ref.faculty WHERE upper(code) = v.up),
            (SELECT code FROM ref.faculty WHERE upper(name) = v.up ORDER BY code LIMIT 1))
        WHEN p_kind = 'college' THEN coalesce(
            (SELECT code FROM ref.college WHERE upper(code) = v.up),
            (SELECT code FROM ref.college WHERE upper(name) = v.up ORDER BY code LIMIT 1))
        WHEN p_kind = 'programme' THEN coalesce(
            (SELECT code FROM ref.programme WHERE upper(code) = v.up),
            (SELECT code FROM ref.programme WHERE upper(name) = v.up ORDER BY archived, code LIMIT 1),
            (SELECT min(p.code) FROM ref.programme p JOIN ref.department d ON d.code = p.dept_code
              WHERE upper(d.name) = v.up AND NOT p.archived
             HAVING count(*) = 1))
        WHEN p_kind = 'course' THEN coalesce(
            (SELECT code FROM catalogue.course WHERE upper(code) = v.up),
            (SELECT code FROM catalogue.course WHERE upper(regexp_replace(code, '\s+', '', 'g')) = regexp_replace(v.up, '\s+', '', 'g') ORDER BY code LIMIT 1))
        ELSE v.raw END
      FROM v
$$;
COMMENT ON FUNCTION iam.scope_code(text, text) IS
  'The code a bounded office grant stores for its scope (V316): the code itself, else the register''s entry of that name (a department also by one of its programmes'' names; a programme also by the name of a department with exactly one live programme); NULL when the register knows nothing of that name.';

/* the grants already on record: rewritten to their codes where the register resolves them */
UPDATE iam.office_assignment a
   SET scope_id = iam.scope_code(a.scope_kind, a.scope_id)
 WHERE a.scope_kind IN ('department', 'faculty', 'college', 'programme', 'course')
   AND nullif(btrim(coalesce(a.scope_id, '')), '') IS NOT NULL
   AND iam.scope_code(a.scope_kind, a.scope_id) IS NOT NULL
   AND iam.scope_code(a.scope_kind, a.scope_id) <> a.scope_id;

/* from now on: the code is stored, and a name the register does not know is refused, not recorded on nothing */
CREATE OR REPLACE FUNCTION iam.office_assignment_scope()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_code text;
BEGIN
    IF NEW.scope_kind IN ('department', 'faculty', 'college', 'programme', 'course') AND nullif(btrim(coalesce(NEW.scope_id, '')), '') IS NOT NULL THEN
        v_code := iam.scope_code(NEW.scope_kind, NEW.scope_id);
        IF v_code IS NULL THEN
            RAISE EXCEPTION 'OFFICE_SCOPE_UNKNOWN: no % on the register is called "%"', NEW.scope_kind, btrim(NEW.scope_id)
                USING ERRCODE = '23514', HINT = 'Choose the ' || NEW.scope_kind || ' from the register on Users & Roles; its code is what the grant carries.';
        END IF;
        NEW.scope_id := v_code;
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_office_assignment_scope ON iam.office_assignment;
CREATE TRIGGER trg_office_assignment_scope BEFORE INSERT OR UPDATE OF scope_kind, scope_id ON iam.office_assignment
    FOR EACH ROW EXECUTE FUNCTION iam.office_assignment_scope();

COMMIT;
