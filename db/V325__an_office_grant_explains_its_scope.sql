-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V325 — an office grant explains its scope; a bounded office is never granted without its bound
--
--   A Head of Department whose desk read "not tied to a department yet" had no way of learning why, and the
--   Registry no way of seeing which grant was at fault. Three things could be wrong with the grant itself — bounded
--   to the University instead of a department, bounded to a department with none chosen, bounded to a department
--   the register has since ended — and one with the person: no live grant at all (a grant ended, or dated later
--   than the sign-in whose token still carries the office). Every one of them produced the same two lines on the
--   screen. Worse, the desk resolved the department by taking the FIRST scope it found and matching that alone:
--   a grant whose scope no longer matched anything hid the lecturer grant and the staff record that would have
--   answered.
--
--   Now:
--     · iam.live_scope_code resolves a scope (V316's rule, by code or by name) to a LIVE entry on the register —
--       a department not ended, a programme not archived — or to nothing;
--     · iam.acting_department tries each source in turn — the office's own department, the programme the office
--       is held over, the lecturer grant, the staff record — and takes the first that resolves, so a stale scope on
--       one grant no longer silences the rest; iam.acting_faculty does the same for the faculty offices;
--     · iam.office_scope_state says, for one person acting in one office, what the newest live grant holds, what
--       the desk resolved to and through which source, and when the grant itself did not answer, the one reason:
--       NO_LIVE_GRANT, GRANT_NOT_BOUNDED, SCOPE_BLANK, SCOPE_NOT_ON_REGISTER or SCOPE_ENDED — the words the
--       dashboard and Users & Roles show;
--     · the grant trigger refuses a department office (Head of Department, SIWES Coordinator) bounded to anything
--       but a department, an Examinations Officer bounded to anything but a department or a programme, a faculty
--       office (Dean, Faculty Officer, Faculty Examinations Officer) bounded to anything but a faculty — and any
--       of them bounded to nothing: OFFICE_SCOPE_REQUIRED, with the remedy in the hint.
--   Grants already on record are not touched: the state function describes them, and Users & Roles marks them.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V325: an office grant explains its scope; a bounded office is never granted without its bound', true);

/* the LIVE register entry a scope resolves to — V316's resolution by code or name, kept only when that entry is
   still live: a department not ended, a programme not archived; a faculty or college as the register has it */
CREATE OR REPLACE FUNCTION iam.live_scope_code(p_kind text, p_id text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT c FROM (SELECT iam.scope_code(p_kind, p_id) AS c) x
     WHERE c IS NOT NULL
       AND CASE p_kind
             WHEN 'department' THEN EXISTS (SELECT 1 FROM ref.department d WHERE d.code = c AND d.ended_on IS NULL)
             WHEN 'programme'  THEN EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = c AND NOT p.archived)
             WHEN 'faculty'    THEN EXISTS (SELECT 1 FROM ref.faculty f WHERE f.code = c)
             WHEN 'college'    THEN EXISTS (SELECT 1 FROM ref.college g WHERE g.code = c)
             ELSE false END
$$;
COMMENT ON FUNCTION iam.live_scope_code(text, text) IS
  'V325: the LIVE register entry a grant''s scope resolves to (by code or by name, as V316 resolves it) — a department not ended, a programme not archived; NULL when nothing live answers.';

/* the department a person works in when acting in a department office: the first of these that resolves to a
   live department — the office's own department grant (newest first), the programme the office is held over,
   the lecturer grant, the staff record's home department */
CREATE OR REPLACE FUNCTION iam.acting_department(p_person uuid, p_office text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT code FROM (
        SELECT 1 AS rank, a.valid_from, iam.live_scope_code('department', a.scope_id) AS code
          FROM iam.office_assignment a
         WHERE a.person_id = p_person AND a.office_code = p_office AND a.scope_kind = 'department'
           AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
        UNION ALL
        SELECT 2, a.valid_from,
               (SELECT p.dept_code FROM ref.programme p
                 WHERE p.code = iam.live_scope_code('programme', a.scope_id)
                   AND EXISTS (SELECT 1 FROM ref.department d WHERE d.code = p.dept_code AND d.ended_on IS NULL))
          FROM iam.office_assignment a
         WHERE a.person_id = p_person AND a.office_code = p_office AND a.scope_kind = 'programme'
           AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
        UNION ALL
        SELECT 3, a.valid_from, iam.live_scope_code('department', a.scope_id)
          FROM iam.office_assignment a
         WHERE a.person_id = p_person AND a.office_code = 'lecturer' AND a.scope_kind = 'department'
           AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
        UNION ALL
        SELECT 4, NULL::date, iam.live_scope_code('department', sr.home_department)
          FROM hrm.staff_record sr
         WHERE sr.person_id = p_person
    ) s
    WHERE code IS NOT NULL
    ORDER BY rank, valid_from DESC NULLS LAST
    LIMIT 1
$$;
COMMENT ON FUNCTION iam.acting_department(uuid, text) IS
  'V325: the department a person acts in for a department office — the office''s own grant, else the programme it is held over, else the lecturer grant, else the staff record; the first that resolves to a live department.';

/* the faculty a person works in when acting in a faculty office: the faculty grant, else the faculty of the
   staff record's home department */
CREATE OR REPLACE FUNCTION iam.acting_faculty(p_person uuid, p_office text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT code FROM (
        SELECT 1 AS rank, a.valid_from, iam.live_scope_code('faculty', a.scope_id) AS code
          FROM iam.office_assignment a
         WHERE a.person_id = p_person AND a.office_code IN ('dean', 'facultyofficer', 'facultyexams') AND a.scope_kind = 'faculty'
           AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
        UNION ALL
        SELECT 2, NULL::date, d.faculty_code
          FROM hrm.staff_record sr
          JOIN ref.department d ON d.code = iam.live_scope_code('department', sr.home_department)
         WHERE sr.person_id = p_person
    ) s
    WHERE code IS NOT NULL
    ORDER BY rank, valid_from DESC NULLS LAST
    LIMIT 1
$$;
COMMENT ON FUNCTION iam.acting_faculty(uuid, text) IS
  'V325: the faculty a person acts in for a faculty office — the faculty grant (Dean, Faculty Officer, Faculty Examinations Officer), else the faculty of the staff record''s home department.';

/* one person acting in one office: what the newest live grant holds, what the desk resolved to and from which
   source, and — when the grant itself did not answer — the one reason why. bound_kind is NULL for an office that
   is not bounded this way (nothing to explain). */
CREATE OR REPLACE FUNCTION iam.office_scope_state(p_person uuid, p_office text)
RETURNS TABLE (
    bound_kind     text,
    grant_id       uuid,
    scope_kind     text,
    scope_id       text,
    valid_from     date,
    valid_to       date,
    instrument     text,
    resolved_code  text,
    resolved_name  text,
    source         text,
    reason         text,
    programme_code text,
    programme_name text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    g record;
BEGIN
    bound_kind := CASE WHEN p_office IN ('hod', 'siwes', 'exams', 'lecturer') THEN 'department'
                       WHEN p_office IN ('dean', 'facultyofficer', 'facultyexams') THEN 'faculty' END;
    IF bound_kind IS NULL THEN
        RETURN NEXT;
        RETURN;
    END IF;

    SELECT a.id, a.scope_kind, a.scope_id, a.valid_from, a.valid_to, a.instrument INTO g
      FROM iam.office_assignment a
     WHERE a.person_id = p_person AND a.office_code = p_office
       AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
     ORDER BY a.valid_from DESC, a.id
     LIMIT 1;

    IF g.id IS NULL THEN
        reason := 'NO_LIVE_GRANT';
    ELSE
        grant_id := g.id; scope_kind := g.scope_kind; scope_id := g.scope_id;
        valid_from := g.valid_from; valid_to := g.valid_to; instrument := g.instrument;
        IF g.scope_kind <> bound_kind AND NOT (p_office = 'exams' AND g.scope_kind = 'programme') THEN
            reason := 'GRANT_NOT_BOUNDED';
        ELSIF nullif(btrim(coalesce(g.scope_id, '')), '') IS NULL THEN
            reason := 'SCOPE_BLANK';
        ELSIF iam.live_scope_code(g.scope_kind, g.scope_id) IS NULL THEN
            reason := CASE WHEN iam.scope_code(g.scope_kind, g.scope_id) IS NOT NULL THEN 'SCOPE_ENDED' ELSE 'SCOPE_NOT_ON_REGISTER' END;
        END IF;
        IF p_office = 'exams' AND g.scope_kind = 'programme' THEN
            programme_code := iam.live_scope_code('programme', g.scope_id);
            SELECT p.name INTO programme_name FROM ref.programme p WHERE p.code = programme_code;
        END IF;
    END IF;

    IF bound_kind = 'department' THEN
        resolved_code := iam.acting_department(p_person, p_office);
        IF resolved_code IS NOT NULL THEN
            SELECT d.name INTO resolved_name FROM ref.department d WHERE d.code = resolved_code;
            source := CASE
                WHEN EXISTS (SELECT 1 FROM iam.office_assignment a
                              WHERE a.person_id = p_person AND a.office_code = p_office AND a.scope_kind = 'department'
                                AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                                AND iam.live_scope_code('department', a.scope_id) = resolved_code) THEN 'OFFICE_GRANT'
                WHEN EXISTS (SELECT 1 FROM iam.office_assignment a JOIN ref.programme p ON p.code = iam.live_scope_code('programme', a.scope_id)
                              WHERE a.person_id = p_person AND a.office_code = p_office AND a.scope_kind = 'programme'
                                AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                                AND p.dept_code = resolved_code) THEN 'PROGRAMME_GRANT'
                WHEN EXISTS (SELECT 1 FROM iam.office_assignment a
                              WHERE a.person_id = p_person AND a.office_code = 'lecturer' AND a.scope_kind = 'department'
                                AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                                AND iam.live_scope_code('department', a.scope_id) = resolved_code) THEN 'LECTURER_GRANT'
                ELSE 'STAFF_RECORD' END;
        END IF;
    ELSE
        resolved_code := iam.acting_faculty(p_person, p_office);
        IF resolved_code IS NOT NULL THEN
            SELECT f.name INTO resolved_name FROM ref.faculty f WHERE f.code = resolved_code;
            source := CASE
                WHEN EXISTS (SELECT 1 FROM iam.office_assignment a
                              WHERE a.person_id = p_person AND a.office_code IN ('dean', 'facultyofficer', 'facultyexams') AND a.scope_kind = 'faculty'
                                AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                                AND iam.live_scope_code('faculty', a.scope_id) = resolved_code) THEN 'OFFICE_GRANT'
                ELSE 'STAFF_RECORD' END;
        END IF;
    END IF;
    RETURN NEXT;
END $$;
COMMENT ON FUNCTION iam.office_scope_state(uuid, text) IS
  'V325: one person acting in one office — what the newest live grant holds, what the desk resolved to and through which source (OFFICE_GRANT, PROGRAMME_GRANT, LECTURER_GRANT, STAFF_RECORD), and when the grant itself did not answer, why: NO_LIVE_GRANT, GRANT_NOT_BOUNDED, SCOPE_BLANK, SCOPE_NOT_ON_REGISTER, SCOPE_ENDED.';

/* the grant trigger (V316) now also refuses a bounded office granted without its bound */
CREATE OR REPLACE FUNCTION iam.office_assignment_scope()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_code  text;
    v_label text;
    v_need  text;
BEGIN
    v_need := CASE WHEN NEW.office_code IN ('hod', 'siwes') THEN 'department'
                   WHEN NEW.office_code = 'exams' THEN 'department or programme'
                   WHEN NEW.office_code IN ('dean', 'facultyofficer', 'facultyexams') THEN 'faculty' END;
    IF v_need IS NOT NULL THEN
        SELECT o.label INTO v_label FROM ref.office o WHERE o.code = NEW.office_code;
        IF NOT ((v_need = 'department' AND NEW.scope_kind = 'department')
             OR (v_need = 'department or programme' AND NEW.scope_kind IN ('department', 'programme'))
             OR (v_need = 'faculty' AND NEW.scope_kind = 'faculty')) THEN
            RAISE EXCEPTION 'OFFICE_SCOPE_REQUIRED: the % office is held over a %; this grant is bounded to "%"',
                coalesce(v_label, NEW.office_code), v_need, NEW.scope_kind
                USING ERRCODE = '23514',
                      HINT = 'On Users & Roles bound the grant to a ' || v_need || ' and choose it from the register; the desk is scoped to it.';
        END IF;
        IF nullif(btrim(coalesce(NEW.scope_id, '')), '') IS NULL THEN
            RAISE EXCEPTION 'OFFICE_SCOPE_REQUIRED: the % office is held over one %; none was chosen',
                coalesce(v_label, NEW.office_code), v_need
                USING ERRCODE = '23514',
                      HINT = 'On Users & Roles choose the ' || v_need || ' from the register; the desk is scoped to it.';
        END IF;
    END IF;
    /* V316/V317, unchanged: a register scope is stored as its code and an unknown name refused; a course scope takes
       the catalogue's code where it is known and is otherwise kept as typed */
    IF nullif(btrim(coalesce(NEW.scope_id, '')), '') IS NOT NULL THEN
        IF NEW.scope_kind IN ('department', 'faculty', 'college', 'programme') THEN
            v_code := iam.scope_code(NEW.scope_kind, NEW.scope_id);
            IF v_code IS NULL THEN
                RAISE EXCEPTION 'OFFICE_SCOPE_UNKNOWN: no % on the register is called "%"', NEW.scope_kind, btrim(NEW.scope_id)
                    USING ERRCODE = '23514', HINT = 'Choose the ' || NEW.scope_kind || ' from the register on Users & Roles; its code is what the grant carries.';
            END IF;
            NEW.scope_id := v_code;
        ELSIF NEW.scope_kind = 'course' THEN
            NEW.scope_id := coalesce(iam.scope_code('course', NEW.scope_id), btrim(NEW.scope_id));
        END IF;
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_office_assignment_scope ON iam.office_assignment;
CREATE TRIGGER trg_office_assignment_scope BEFORE INSERT OR UPDATE OF office_code, scope_kind, scope_id ON iam.office_assignment
    FOR EACH ROW EXECUTE FUNCTION iam.office_assignment_scope();
COMMENT ON FUNCTION iam.office_assignment_scope() IS
  'V316/V317/V325: a bounded office is granted over its bound — a department office over a department (the Examinations Officer also over a programme), a faculty office over a faculty — chosen from the register, whose code the grant then carries; anything else is refused with the remedy in the hint.';

COMMIT;
