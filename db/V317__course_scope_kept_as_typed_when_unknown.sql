-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V317 — a course-scoped grant is normalised when the catalogue knows the code, and kept as typed when it
--        does not
--
--   V316 made every bounded grant carry the register's code and refused a name the register does not
--   know. For a department, a faculty, a college or a programme that is right: the desk cannot work on
--   a scope the register has never heard of. A COURSE scope is different: it is a lecturer's "own
--   courses" bound, written before the course may be on the catalogue (a grant made ahead of the
--   department's upload, a resit or special sitting), and refusing it stopped grants that used to go
--   through. So a course scope is written as the catalogue's code when the catalogue knows it, and as
--   typed when it does not; the other four kinds keep V316's rule.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V317: a course scope kept as typed when the catalogue does not know it', true);

CREATE OR REPLACE FUNCTION iam.office_assignment_scope()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_code text;
BEGIN
    IF nullif(btrim(coalesce(NEW.scope_id, '')), '') IS NOT NULL THEN
        IF NEW.scope_kind IN ('department', 'faculty', 'college', 'programme') THEN
            v_code := iam.scope_code(NEW.scope_kind, NEW.scope_id);
            IF v_code IS NULL THEN
                RAISE EXCEPTION 'OFFICE_SCOPE_UNKNOWN: no % on the register is called "%"', NEW.scope_kind, btrim(NEW.scope_id)
                    USING ERRCODE = '23514', HINT = 'Choose the ' || NEW.scope_kind || ' from the register on Users & Roles; its code is what the grant carries.';
            END IF;
            NEW.scope_id := v_code;
        ELSIF NEW.scope_kind = 'course' THEN
            -- the catalogue's code where it is known; otherwise as typed, trimmed
            NEW.scope_id := coalesce(iam.scope_code('course', NEW.scope_id), btrim(NEW.scope_id));
        END IF;
    END IF;
    RETURN NEW;
END $$;

COMMIT;
