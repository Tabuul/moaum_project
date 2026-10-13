-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V443 — a course is never tied to a session, and belongs to the department whose code it carries
--
--   Two rules the University stated (13 Oct 2026), both already true of the pool and both broken by a gate and an upload:
--
--   1 · THE POOL IS ONE. A course lives in the catalogue once; only a class — the course taught in one session and semester,
--       to which allocation, timetable and registration attach — is per session. The allocation desk nevertheless listed a
--       department's CLASSES, and a class was opened only when the calendar opened a semester's registration (or, V405, when a
--       course joined the structure after that): a session whose semesters the portal never opened — a migrated 2021/2022 —
--       showed "30 courses have no class" and nothing to allocate. From V443 the desk lists the department's COURSES for the
--       semester, each with its class for the session if one exists, and allocating a course that has none opens the class
--       as part of the allocation: catalogue.open_class(course, session, semester) — the one way a class comes to be outside
--       the calendar's opening, used by the Head of Department's desk, the ICT/CPO desk and the bulk upload. No "opened
--       semester" gate: any session on the register that was not cancelled or merged.
--
--   2 · THE CODE NAMES THE OWNER. A course's code begins with its department's code — ENG 101 is the Department of English's
--       — but the structure upload gave a NEW course to the department of the programme uploading it, so a B.Ed English
--       structure uploaded first made Arts and Social Science Education the owner of 88 ENG courses, and 471 live courses in all
--       sat with a department whose code they do not carry; their Heads of Department could not allocate them, and the
--       claiming department's desk showed them. From V443 a course inserted with a code whose prefix is a department's own
--       code belongs to that department (a BEFORE INSERT rule), the courses already astray are moved to it here — every move
--       on the owner trail (V338) with the source CODE — and prefixes that are no department's code (MTH, STA, LIN, HIS…)
--       are named to their department by the Academic Office in ref.course_prefix, applied to the pool when it says so.
--       Change owner (V338) stays the deliberate exception and is never overridden: the rule runs at insert, not at update.
--       GST/EPS courses are the general office's and are left alone.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM set_config('moaum.reason', 'V443: a course is never tied to a session; a course belongs to the department whose code it carries', true);
END $seed$;

-- ── 1 · a class opened for a course in a session, on allocation ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.open_class(p_course text, p_session text, p_semester int, p_stream text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE c catalogue.course; s policy.academic_session; v_stream text; v_id uuid;
BEGIN
    SELECT * INTO c FROM catalogue.course WHERE code = regexp_replace(upper(btrim(coalesce(p_course, ''))), '\s+', ' ', 'g');
    IF c.code IS NULL THEN
        RAISE EXCEPTION 'CLASS_COURSE: no course is coded %', p_course USING ERRCODE = '23503';
    END IF;
    IF c.state = 'ENDED' THEN
        RAISE EXCEPTION 'ALLOC_ENDED: % has ended, so it is not taught; restore it on the Department courses page first', c.code USING ERRCODE = '23514';
    END IF;
    IF c.code LIKE 'DMO %' THEN
        RAISE EXCEPTION 'CLASS_DEMO: % is a demonstration course', c.code USING ERRCODE = '23514';
    END IF;
    IF p_semester IS NULL OR p_semester NOT IN (1, 2, 3) THEN
        RAISE EXCEPTION 'CLASS_SEMESTER: a semester is 1, 2 or 3' USING ERRCODE = '23514';
    END IF;
    IF NOT catalogue.runs_in(c.semester, c.both_semesters, p_semester) THEN
        RAISE EXCEPTION 'CLASS_NOT_IN_SEMESTER: % is taught in semester %, not semester %', c.code,
            CASE WHEN c.both_semesters THEN '1 and 2' ELSE c.semester::text END, p_semester USING ERRCODE = '23514';
    END IF;
    SELECT * INTO s FROM policy.academic_session WHERE name = btrim(coalesce(p_session, ''));
    IF s.id IS NULL THEN
        RAISE EXCEPTION 'CLASS_SESSION: no session is named %', p_session USING ERRCODE = '23503';
    END IF;
    IF s.state = 'CANCELLED' OR s.merged_into IS NOT NULL THEN
        RAISE EXCEPTION 'CLASS_SESSION_GONE: the session % was % and holds no classes', s.name,
            CASE WHEN s.merged_into IS NOT NULL THEN 'merged into ' || s.merged_into ELSE 'cancelled' END USING ERRCODE = '23514';
    END IF;
    -- the stream: as asked, else the full-time class unless every programme offering the course is a postgraduate one
    v_stream := upper(nullif(btrim(coalesce(p_stream, '')), ''));
    IF v_stream IS NULL THEN
        v_stream := CASE WHEN EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code)
                          AND NOT EXISTS (SELECT 1 FROM catalogue.course_offer co JOIN ref.programme p ON p.code = co.programme_code
                                           WHERE co.course_code = c.code AND coalesce(p.category, '') <> 'POST GRADUATE')
                         THEN 'PG' ELSE 'REGULAR' END;
    END IF;
    IF v_stream NOT IN ('REGULAR', 'PG', 'CCE') THEN
        RAISE EXCEPTION 'CLASS_STREAM: a class is REGULAR, PG or CCE' USING ERRCODE = '23514';
    END IF;
    SELECT id INTO v_id FROM catalogue.offering WHERE course_code = c.code AND session = s.name AND semester = p_semester AND stream = v_stream;
    IF v_id IS NOT NULL THEN
        RETURN v_id;
    END IF;
    INSERT INTO catalogue.offering (id, course_code, session, semester, stream)
    VALUES (gen_random_uuid(), c.code, s.name, p_semester, v_stream)
    ON CONFLICT (course_code, session, semester, stream) DO UPDATE SET course_code = EXCLUDED.course_code
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;
COMMENT ON FUNCTION catalogue.open_class(text, text, int, text) IS
  'V443: the class of a course in a session and semester — the one there is, or one opened now (any session on the register not cancelled or merged; the course live and taught in that semester); the stream as asked, else REGULAR unless only postgraduate programmes offer the course. Used by the allocation desks and the bulk upload when a course is allocated before the calendar opened its class.';

-- ── 2 · ownership by code ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE ref.course_prefix (
    prefix     text PRIMARY KEY,
    dept_code  text NOT NULL REFERENCES ref.department (code),
    note       text NULL,
    set_by     uuid NULL,
    set_office text NULL,
    set_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_course_prefix_shape CHECK (prefix ~ '^[A-Z]{2,6}$')
);
SELECT audit.attach('ref.course_prefix');
COMMENT ON TABLE ref.course_prefix IS
  'V443: a course-code prefix that is no department''s own code (MTH, STA, LIN, HIS…), named to the department that owns its courses by the Academic Office; a prefix that IS a department''s code needs no row — the rule reads it.';

CREATE OR REPLACE FUNCTION catalogue.code_prefix(p_code text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT upper((regexp_match(btrim(coalesce(p_code, '')), '^(?:BSU-|MOAU-)?([A-Za-z]+)'))[1])
$$;
COMMENT ON FUNCTION catalogue.code_prefix(text) IS 'V443: the letters a course code begins with, past a BSU-/MOAU- twin prefix: ENG for "ENG 101" and "MOAU-ENG 101".';

CREATE OR REPLACE FUNCTION catalogue.course_owner_by_code(p_code text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT d.code FROM ref.department d WHERE d.code = catalogue.code_prefix(p_code) AND d.ended_on IS NULL),
        (SELECT x.dept_code FROM ref.course_prefix x JOIN ref.department d ON d.code = x.dept_code AND d.ended_on IS NULL
          WHERE x.prefix = catalogue.code_prefix(p_code)))
$$;
COMMENT ON FUNCTION catalogue.course_owner_by_code(text) IS
  'V443: the department a course code names — the live department whose code is the code''s prefix, else the one ref.course_prefix names for it, else none.';

-- a new course belongs to the department its code names, whoever inserts it; a deliberate Change owner afterwards stands
CREATE OR REPLACE FUNCTION catalogue.course_owner_by_code_on_insert()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
    IF NEW.general_office IS NULL AND coalesce(NEW.kind, '') <> 'GST' AND NEW.code NOT LIKE 'DMO %' THEN
        v := catalogue.course_owner_by_code(NEW.code);
        IF v IS NOT NULL AND v IS DISTINCT FROM NEW.dept_code THEN
            NEW.dept_code := v;
            IF NEW.owner_programme IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = NEW.owner_programme AND p.dept_code = v) THEN
                NEW.owner_programme := NULL;
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_course_owner_by_code BEFORE INSERT ON catalogue.course
FOR EACH ROW EXECUTE FUNCTION catalogue.course_owner_by_code_on_insert();

-- the courses astray from the department their code names, moved to it — every move on the owner trail with the source CODE
CREATE OR REPLACE FUNCTION catalogue.apply_code_owners(p_prefix text, p_reason text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    PERFORM set_config('moaum.reason', coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'a course belongs to the department whose code it carries'), true);
    PERFORM set_config('moaum.owner_source', 'CODE', true);
    UPDATE catalogue.course c
       SET dept_code = o.dept,
           owner_programme = CASE WHEN EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = c.owner_programme AND p.dept_code = o.dept)
                                  THEN c.owner_programme END
      FROM (SELECT c2.code, catalogue.course_owner_by_code(c2.code) AS dept FROM catalogue.course c2) o
     WHERE o.code = c.code AND o.dept IS NOT NULL AND o.dept <> c.dept_code
       AND c.general_office IS NULL AND coalesce(c.kind, '') <> 'GST' AND c.code NOT LIKE 'DMO %'
       AND (p_prefix IS NULL OR catalogue.code_prefix(c.code) = upper(btrim(p_prefix)));
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;
COMMENT ON FUNCTION catalogue.apply_code_owners(text, text) IS
  'V443: moves every course (or every course of one prefix) to the department its code names where it sits elsewhere — GST/EPS and demonstration courses left alone; the number moved, each on the owner trail as source CODE.';

CREATE OR REPLACE FUNCTION catalogue.set_code_prefix(p_prefix text, p_dept text, p_note text, p_apply boolean, p_reason text, p_actor uuid, p_office text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE v_prefix text := upper(btrim(coalesce(p_prefix, ''))); v_dept text;
BEGIN
    IF p_office IS NULL OR p_office NOT IN ('academic', 'registrar', 'dregistrar', 'ict', 'super') THEN
        RAISE EXCEPTION 'CODE_OWNER_OFFICE: a code prefix is named to its department by the Academic Office, the Registry or the Directorate of ICT' USING ERRCODE = '23514';
    END IF;
    IF v_prefix !~ '^[A-Z]{2,6}$' THEN
        RAISE EXCEPTION 'CODE_PREFIX: a prefix is two to six letters, as a course code begins' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM ref.department d WHERE d.code = v_prefix AND d.ended_on IS NULL) THEN
        RAISE EXCEPTION 'CODE_PREFIX_IS_DEPARTMENT: % is a department''s own code; its courses are its by the rule, nothing to name', v_prefix USING ERRCODE = '23514';
    END IF;
    SELECT d.code INTO v_dept FROM ref.department d
     WHERE d.ended_on IS NULL AND (upper(d.code) = upper(btrim(coalesce(p_dept, ''))) OR upper(d.name) = upper(btrim(coalesce(p_dept, '')))) LIMIT 1;
    IF v_dept IS NULL THEN
        RAISE EXCEPTION 'CODE_OWNER_DEPT: no live department is coded or named %', p_dept USING ERRCODE = '23514';
    END IF;
    INSERT INTO ref.course_prefix (prefix, dept_code, note, set_by, set_office, set_at)
    VALUES (v_prefix, v_dept, nullif(btrim(coalesce(p_note, '')), ''), p_actor, p_office, now())
    ON CONFLICT (prefix) DO UPDATE SET dept_code = EXCLUDED.dept_code, note = EXCLUDED.note, set_by = EXCLUDED.set_by, set_office = EXCLUDED.set_office, set_at = now();
    IF coalesce(p_apply, false) THEN
        RETURN catalogue.apply_code_owners(v_prefix, coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'the prefix ' || v_prefix || ' named to ' || v_dept));
    END IF;
    RETURN 0;
END $$;

CREATE OR REPLACE FUNCTION catalogue.unset_code_prefix(p_prefix text, p_office text)
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    IF p_office IS NULL OR p_office NOT IN ('academic', 'registrar', 'dregistrar', 'ict', 'super') THEN
        RAISE EXCEPTION 'CODE_OWNER_OFFICE: a code prefix is named to its department by the Academic Office, the Registry or the Directorate of ICT' USING ERRCODE = '23514';
    END IF;
    DELETE FROM ref.course_prefix WHERE prefix = upper(btrim(coalesce(p_prefix, '')));
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n = 1;
END $$;

-- every prefix in the pool: who the code names, who holds the courses now, how many sit astray
CREATE OR REPLACE FUNCTION catalogue.code_owners()
RETURNS TABLE (prefix text, courses bigint, live_courses bigint, is_department boolean, mapped_dept text, owner_by_code text, owner_name text,
               owners_now text, astray bigint, note text, set_at timestamptz)
LANGUAGE sql STABLE AS $$
    WITH c AS (
        SELECT catalogue.code_prefix(code) AS prefix, code, dept_code, state, general_office, kind
          FROM catalogue.course WHERE code NOT LIKE 'DMO %'
    )
    SELECT c.prefix, count(*), count(*) FILTER (WHERE c.state <> 'ENDED'),
           EXISTS (SELECT 1 FROM ref.department d WHERE d.code = c.prefix AND d.ended_on IS NULL),
           x.dept_code,
           catalogue.course_owner_by_code(c.prefix || ' 000'),
           (SELECT d.name FROM ref.department d WHERE d.code = catalogue.course_owner_by_code(c.prefix || ' 000')),
           string_agg(DISTINCT c.dept_code, ', ' ORDER BY c.dept_code),
           count(*) FILTER (WHERE c.state <> 'ENDED' AND c.general_office IS NULL AND coalesce(c.kind, '') <> 'GST'
                              AND catalogue.course_owner_by_code(c.prefix || ' 000') IS NOT NULL
                              AND c.dept_code <> catalogue.course_owner_by_code(c.prefix || ' 000')),
           x.note, x.set_at
      FROM c LEFT JOIN ref.course_prefix x ON x.prefix = c.prefix
     WHERE c.prefix IS NOT NULL
     GROUP BY c.prefix, x.dept_code, x.note, x.set_at
     ORDER BY c.prefix
$$;
COMMENT ON FUNCTION catalogue.code_owners() IS
  'V443: the course-code prefixes of the pool — whether each is a department''s own code or named in ref.course_prefix, which department the code names, which departments hold its courses now, and how many live courses sit astray.';

-- ── 3 · the courses already astray, moved to the department their code names ─────────────────────────────────────────
DO $fix$
DECLARE n int;
BEGIN
    n := catalogue.apply_code_owners(NULL, 'V443: a course belongs to the department whose code it carries');
    RAISE NOTICE 'V443: % courses moved to the department their code names', n;
END $fix$;

COMMIT;
