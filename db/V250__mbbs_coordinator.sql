-- ═══════════════════════════════════════════════════════════════════════════
-- V250 — the MBBS Coordinator: an office held by level
--
--   A College lecturer is given a second office for one level, 200 to 600:
--   MBBS Coordinator, 200 Level. They see and act on that level's students
--   only — the cohort, its score sheet (downloaded, filled, uploaded), its
--   results and CA, a student's year opened for a paper registration. The
--   Board's confirmation, the calendar, Senate appeals and allocation stay
--   with the Provost and the College Secretary.
--
--   'level' joins the scope kinds an office and a grant may carry; this
--   office alone uses it. The grant is refused unless the person already
--   holds a lecturer's office in a department under the College, so it can
--   only be added to a College lecturer. Nothing on the University side
--   reads the kind.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE ref.office DROP CONSTRAINT ck_office_scope;
ALTER TABLE ref.office ADD CONSTRAINT ck_office_scope CHECK (scope_kind IN
        ('institution','college','faculty','department','programme','course','unit','platform','level'));
ALTER TABLE iam.office_assignment DROP CONSTRAINT ck_grant_scope;
ALTER TABLE iam.office_assignment ADD CONSTRAINT ck_grant_scope CHECK (scope_kind IN
        ('institution','college','faculty','department','programme','course','unit','platform','level'));

-- ref.office is on the audit spine and a migration has no acting person: the one row goes in as V227's did
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'academic', true);
SELECT set_config('moaum.reason', 'MBBS Coordinator office (V250)', true);
INSERT INTO ref.office (code, label, scope_kind) VALUES ('mbbscoordinator', 'MBBS Coordinator', 'level')
ON CONFLICT (code) DO NOTHING;

-- a person's current lecturer's department, as a code, when it is under the College
CREATE OR REPLACE FUNCTION iam.college_lecturer_dept(p_person uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT d.code
      FROM iam.office_assignment a
      JOIN ref.department d ON (upper(btrim(d.code)) = upper(btrim(a.scope_id)) OR lower(btrim(d.name)) = lower(btrim(a.scope_id)))
     WHERE a.person_id = p_person AND a.office_code = 'lecturer' AND a.scope_kind = 'department'
       AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
       AND EXISTS (SELECT 1 FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code WHERE p.dept_code = d.code AND f.college_code = 'CHS')
     ORDER BY a.valid_from DESC LIMIT 1
$$;

-- the grant guard: the coordinatorship is by level, 200 to 600, and only a College lecturer holds it
CREATE OR REPLACE FUNCTION iam.guard_coordinator_grant()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.office_code <> 'mbbscoordinator' THEN RETURN NEW; END IF;
    IF NEW.scope_kind <> 'level' OR NEW.scope_id IS NULL OR btrim(NEW.scope_id) NOT IN ('200','300','400','500','600') THEN
        RAISE EXCEPTION 'the MBBS Coordinator is held by level: 200, 300, 400, 500 or 600' USING ERRCODE = '23514',
            HINT = 'Bound the grant to a level and give the level as its scope.';
    END IF;
    IF iam.college_lecturer_dept(NEW.person_id) IS NULL THEN
        RAISE EXCEPTION 'the MBBS Coordinator is a College lecturer: no current lecturer''s office in a department under the College of Health Sciences' USING ERRCODE = '23514',
            HINT = 'Grant the lecturer''s office in a College department first, then the coordinatorship.';
    END IF;
    NEW.scope_id := btrim(NEW.scope_id);
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_guard_coordinator_grant ON iam.office_assignment;
CREATE TRIGGER trg_guard_coordinator_grant BEFORE INSERT OR UPDATE ON iam.office_assignment
    FOR EACH ROW EXECUTE FUNCTION iam.guard_coordinator_grant();

-- the level a person coordinates, now; NULL when none
CREATE OR REPLACE FUNCTION iam.coordinator_level(p_person uuid)
RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT a.scope_id::int FROM iam.office_assignment a
     WHERE a.person_id = p_person AND a.office_code = 'mbbscoordinator' AND a.scope_kind = 'level'
       AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
     ORDER BY a.valid_from DESC LIMIT 1
$$;

COMMIT;
