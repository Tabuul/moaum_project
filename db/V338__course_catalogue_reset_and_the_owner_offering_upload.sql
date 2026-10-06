-- ═══════════════════════════════════════════════════════════════════════════
-- V338 — the course catalogue: a safe reset, and an upload that names each course's owner and the programmes that offer it
--
--   The catalogue already keeps ONE record per course (catalogue.course, owned by a department) and binds it into every
--   programme that offers it (catalogue.course_offer: programme, level, and the basis — Core, Elective, Borrowed or GST — which
--   belongs to the binding, not the course). Registration builds a student's menu from those bindings; each session's
--   instance (catalogue.offering) carries the registrations, score sheets, CBT and lecturers; registration entries carry the
--   units as registered. Nothing that records history cascades from a course or an offering: their keys refuse a delete.
--
--   What was missing, and is added here:
--
--   1. OWNERSHIP STATED, AND CHANGED ON THE RECORD. A course's owner was whoever uploaded it first — so History courses listed
--      in English's structure belong to English. The course now names its owner PROGRAMME beside its owner department (it
--      must be one of that department's), and an owner change — by the Academic Office, or by an upload that names the owner
--      — is written to catalogue.course_owner_history with who, when and why. Description and prerequisites are kept on the
--      course (prerequisites are recorded and shown; registration does not yet refuse on them).
--   2. HISTORY KEEPS ITS TITLE. Each session's offering keeps the title and units it was given (catalogue.offering.title,
--      .units). A correction of the course reaches only offerings that carry no registration or score sheet; one that does
--      keeps what it was registered and examined under, and the student's results and transcript read it from there.
--   3. THE RESET. catalogue.course_reset(scope, ref, reason, confirm) clears the active catalogue of the whole University, a
--      faculty, a department or a programme in one transaction under one reference (COURSE-RESET-YYYY-NNNNN): the scope's
--      programme bindings end (kept on course_offer_history and on the reset's own items), a session offering with nothing on
--      it is removed, a course with nothing on it is removed, and a course that anything hangs on — registrations, results,
--      CBT, questions, deferments, old-portal results, a lecturer — is ARCHIVED (ENDED, marked with the reset) and never
--      deleted. GST/EPS courses belong to their office and are left alone. catalogue.course_reset_preview shows the impact
--      first. A re-upload of an archived course brings the same record back to LIVE.
--   4. THE CATALOGUE UPLOAD WITH OWNERS AND OFFERINGS. catalogue.import_catalogue(rows, commit) reads one row per offering —
--      the course, its owner faculty, department and programme, and the faculty, department and programme that offers it as
--      CORE or ELECTIVE — validates every row against the register (nothing is created on the register: an unknown faculty,
--      department or programme is an error), resolves every row of a code to ONE course, and commits only a file with no
--      invalid row, in one transaction under one reference (COURSE-IMPORT-YYYY-NNNNN).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V338: the course catalogue reset and the owner/offering upload', true);

-- ── 1 · the owner programme, the description, the reset that archived it ─────────────────────────────

ALTER TABLE catalogue.course
    ADD COLUMN owner_programme text NULL REFERENCES ref.programme(code) ON UPDATE CASCADE,
    ADD COLUMN description     text NULL,
    ADD COLUMN reset_batch_id  uuid NULL,
    ADD CONSTRAINT ck_course_description CHECK (description IS NULL OR length(description) <= 4000);
CREATE INDEX IF NOT EXISTS ix_course_dept ON catalogue.course (dept_code);
CREATE INDEX IF NOT EXISTS ix_course_owner_programme ON catalogue.course (owner_programme) WHERE owner_programme IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_course_offer_programme ON catalogue.course_offer (programme_code, level);
COMMENT ON COLUMN catalogue.course.owner_programme IS 'V338: the programme of the owning department that owns the course';
COMMENT ON COLUMN catalogue.course.reset_batch_id IS 'V338: the course reset that archived this course (ENDED); cleared when an upload brings it back';

/* the owner programme is a programme of the owning department */
CREATE OR REPLACE FUNCTION catalogue.course_owner_valid()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.owner_programme IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = NEW.owner_programme AND p.dept_code = NEW.dept_code) THEN
        RAISE EXCEPTION 'CAT_OWNER_PROGRAMME: % is not a programme of the owning department %', NEW.owner_programme, NEW.dept_code
            USING ERRCODE = '23514', HINT = 'Name a programme of the department that owns the course, or leave the owner programme blank.';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_course_owner_valid BEFORE INSERT OR UPDATE OF dept_code, owner_programme ON catalogue.course
FOR EACH ROW EXECUTE FUNCTION catalogue.course_owner_valid();

-- ── 2 · every change of owner, kept ─────────────────────────────────────────────────────────────────

CREATE TABLE catalogue.course_owner_history (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id      uuid NOT NULL,
    course_code    text NOT NULL,
    from_dept      text NULL,
    to_dept        text NULL,
    from_programme text NULL,
    to_programme   text NULL,
    source         text NULL,
    reason         text NULL,
    changed_by     uuid NULL,
    changed_office text NULL,
    changed_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_course_owner_history ON catalogue.course_owner_history (course_id, changed_at DESC);
SELECT audit.attach('catalogue.course_owner_history');
COMMENT ON TABLE catalogue.course_owner_history IS
  'V338: each change of a course''s owner department or owner programme — from what, to what, by whom, from which desk or upload, and why. '
  'Written by trigger; kept by the course''s id, so it outlives a rename and a reset.';

CREATE OR REPLACE FUNCTION catalogue.course_owner_trail()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.dept_code IS DISTINCT FROM NEW.dept_code OR OLD.owner_programme IS DISTINCT FROM NEW.owner_programme THEN
        INSERT INTO catalogue.course_owner_history (course_id, course_code, from_dept, to_dept, from_programme, to_programme, source, reason, changed_by, changed_office)
        VALUES (NEW.id, NEW.code, OLD.dept_code, NEW.dept_code, OLD.owner_programme, NEW.owner_programme,
                coalesce(nullif(current_setting('moaum.owner_source', true), ''), 'DESK'),
                nullif(current_setting('moaum.reason', true), ''),
                nullif(current_setting('moaum.actor_id', true), '')::uuid,
                nullif(current_setting('moaum.actor_office', true), ''));
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_course_owner_trail AFTER UPDATE OF dept_code, owner_programme ON catalogue.course
FOR EACH ROW EXECUTE FUNCTION catalogue.course_owner_trail();

/* the Academic Office moves a course to its rightful owner: the same course, every binding, offering, registration and result still on it */
CREATE OR REPLACE FUNCTION catalogue.change_owner(p_code text, p_dept text, p_programme text, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; c catalogue.course; v_dept text; v_prog text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a course''s owner is changed by a person' USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'CAT_OWNER_REASON: say why the course changes owner' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM catalogue.course WHERE code = upper(btrim(coalesce(p_code, ''))) FOR UPDATE;
    IF c.code IS NULL THEN RAISE EXCEPTION 'no course is coded %', p_code USING ERRCODE = '23503'; END IF;
    IF c.general_office IS NOT NULL THEN
        RAISE EXCEPTION 'CAT_OWNER_GENERAL: % is a % course; its office keeps it', c.code, upper(c.general_office) USING ERRCODE = '23514',
            HINT = 'The GST/EPS office changes its own course''s department on its desk.';
    END IF;
    SELECT d.code INTO v_dept FROM ref.department d
     WHERE d.ended_on IS NULL AND (upper(d.code) = upper(btrim(coalesce(p_dept, ''))) OR upper(d.name) = upper(btrim(coalesce(p_dept, '')))) LIMIT 1;
    IF v_dept IS NULL THEN RAISE EXCEPTION 'CAT_OWNER_DEPT: no live department is coded or named %', p_dept USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_programme, '')), '') IS NOT NULL THEN
        SELECT p.code INTO v_prog FROM ref.programme p
         WHERE NOT coalesce(p.archived, false) AND (upper(p.code) = upper(btrim(p_programme)) OR upper(p.name) = upper(btrim(p_programme)))
         ORDER BY (p.dept_code = v_dept) DESC LIMIT 1;
        IF v_prog IS NULL THEN RAISE EXCEPTION 'CAT_OWNER_PROGRAMME: no live programme is coded or named %', p_programme USING ERRCODE = '23514'; END IF;
    END IF;
    PERFORM set_config('moaum.reason', btrim(p_reason), true);
    PERFORM set_config('moaum.owner_source', 'DESK', true);
    UPDATE catalogue.course SET dept_code = v_dept, owner_programme = v_prog WHERE code = c.code;
END $$;

-- ── 3 · prerequisites, kept on the course ─────────────────────────────────────────────────────────────

CREATE TABLE catalogue.course_prerequisite (
    course_code   text NOT NULL REFERENCES catalogue.course(code) ON UPDATE CASCADE ON DELETE CASCADE,
    requires_code text NOT NULL REFERENCES catalogue.course(code) ON UPDATE CASCADE ON DELETE CASCADE,
    added_by      uuid NULL,
    added_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (course_code, requires_code),
    CONSTRAINT ck_prereq_self CHECK (course_code <> requires_code)
);
CREATE INDEX ix_course_prerequisite_requires ON catalogue.course_prerequisite (requires_code);
SELECT audit.attach('catalogue.course_prerequisite');
COMMENT ON TABLE catalogue.course_prerequisite IS 'V338: a course a course requires first; recorded by the catalogue upload and shown on the course. Registration does not yet refuse on it.';

-- ── 4 · each session's offering keeps the title and units it was given ───────────────────────────────

ALTER TABLE catalogue.offering ADD COLUMN title text NULL, ADD COLUMN units int NULL;
UPDATE catalogue.offering o SET title = c.title, units = c.units FROM catalogue.course c WHERE c.code = o.course_code;
COMMENT ON COLUMN catalogue.offering.title IS 'V338: the course''s title as this session''s offering carries it; frozen once a registration or score sheet hangs on the offering';

CREATE OR REPLACE FUNCTION catalogue.offering_snapshot()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.title IS NULL OR NEW.units IS NULL THEN
        SELECT coalesce(NEW.title, c.title), coalesce(NEW.units, c.units) INTO NEW.title, NEW.units FROM catalogue.course c WHERE c.code = NEW.course_code;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_offering_snapshot BEFORE INSERT ON catalogue.offering FOR EACH ROW EXECUTE FUNCTION catalogue.offering_snapshot();

/* a correction of a course reaches the offerings nothing hangs on yet; an offering registered or examined keeps its own */
CREATE OR REPLACE FUNCTION catalogue.course_correction_reaches_offerings()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.title IS DISTINCT FROM NEW.title OR OLD.units IS DISTINCT FROM NEW.units THEN
        UPDATE catalogue.offering o SET title = NEW.title, units = NEW.units
         WHERE o.course_code = NEW.code
           AND NOT EXISTS (SELECT 1 FROM registration.entry e WHERE e.offering_id = o.id)
           AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh WHERE sh.offering_id = o.id);
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_course_correction_reaches_offerings AFTER UPDATE OF title, units ON catalogue.course
FOR EACH ROW EXECUTE FUNCTION catalogue.course_correction_reaches_offerings();

-- ── 5 · what hangs on an offering, and on a course ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION catalogue.offering_has_history(p_offering uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.id = p_offering AND (o.lecturer_id IS NOT NULL OR o.second_examiner_id IS NOT NULL))
        OR EXISTS (SELECT 1 FROM registration.entry x WHERE x.offering_id = p_offering)
        OR EXISTS (SELECT 1 FROM assessment.score_sheet x WHERE x.offering_id = p_offering)
        OR EXISTS (SELECT 1 FROM assessment.exam_timetable x WHERE x.offering_id = p_offering)
        OR EXISTS (SELECT 1 FROM catalogue.class_slot x WHERE x.offering_id = p_offering)
        OR EXISTS (SELECT 1 FROM registration.attendance x WHERE x.offering_id = p_offering)
        OR EXISTS (SELECT 1 FROM lms.material x WHERE x.offering_id = p_offering)
        OR EXISTS (SELECT 1 FROM lms.assignment x WHERE x.offering_id = p_offering)
        OR EXISTS (SELECT 1 FROM assessment.siwes_supervisor x WHERE x.offering_id = p_offering)
        OR EXISTS (SELECT 1 FROM people.deferred_course x WHERE x.offering_id = p_offering)
        OR EXISTS (SELECT 1 FROM assessment.cbt_exam x WHERE x.offering_id = p_offering)
        OR EXISTS (SELECT 1 FROM catalogue.offering_teacher x WHERE x.offering_id = p_offering);
$$;
COMMENT ON FUNCTION catalogue.offering_has_history(uuid) IS
  'V338: true when anything hangs on a session offering — a lecturer, a registration, a score sheet, a timetable, a class, attendance, LMS work, a SIWES supervisor, a deferment, a CBT examination — so a reset keeps it.';

CREATE OR REPLACE FUNCTION catalogue.course_has_history(p_code text)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.course_code = p_code AND catalogue.offering_has_history(o.id))
        OR EXISTS (SELECT 1 FROM assessment.cbt_exam x WHERE x.course_code = p_code)
        OR EXISTS (SELECT 1 FROM assessment.question x WHERE x.course_code = p_code)
        OR EXISTS (SELECT 1 FROM extexam.project x WHERE x.course_code = p_code)
        OR EXISTS (SELECT 1 FROM people.deferred_course x WHERE x.course_code = p_code)
        OR EXISTS (SELECT 1 FROM assessment.legacy_result_holding x WHERE x.course_code = p_code);
$$;
COMMENT ON FUNCTION catalogue.course_has_history(text) IS
  'V338: true when a course carries academic history — an offering with anything on it, a CBT examination, questions, an external examination project, a deferment, an old-portal result — so a reset archives it and never deletes it.';

-- ── 6 · the reset: its record, its items, its scope, its preview and the act ──────────────────────────

CREATE TABLE catalogue.course_reset (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref                  text NOT NULL UNIQUE,
    scope                text NOT NULL CHECK (scope IN ('ALL', 'FACULTY', 'DEPARTMENT', 'PROGRAMME')),
    scope_ref            text NULL,
    scope_label          text NOT NULL,
    reason               text NOT NULL CHECK (length(btrim(reason)) BETWEEN 5 AND 2000),
    courses_in_scope     int NOT NULL DEFAULT 0,
    bindings_removed     int NOT NULL DEFAULT 0,
    offerings_removed    int NOT NULL DEFAULT 0,
    offerings_kept       int NOT NULL DEFAULT 0,
    archived             int NOT NULL DEFAULT 0,
    deleted              int NOT NULL DEFAULT 0,
    proposals_cancelled  int NOT NULL DEFAULT 0,
    programmes_affected  int NOT NULL DEFAULT 0,
    departments_affected int NOT NULL DEFAULT 0,
    status               text NOT NULL DEFAULT 'COMPLETED' CHECK (status IN ('COMPLETED')),
    performed_by         uuid NOT NULL,
    performed_office     text NULL,
    performed_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_course_reset_scope_ref CHECK (scope = 'ALL' OR scope_ref IS NOT NULL)
);
CREATE INDEX ix_course_reset_at ON catalogue.course_reset (performed_at DESC);
SELECT audit.attach('catalogue.course_reset');
COMMENT ON TABLE catalogue.course_reset IS 'V338: each course catalogue reset, under its reference — the scope, the reason, who, when, and what it removed, archived and kept. A reset is one transaction: recorded COMPLETED, or not at all.';

ALTER TABLE catalogue.course ADD CONSTRAINT fk_course_reset_batch FOREIGN KEY (reset_batch_id) REFERENCES catalogue.course_reset(id);

CREATE TABLE catalogue.course_reset_item (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reset_id       uuid NOT NULL REFERENCES catalogue.course_reset(id),
    course_code    text NOT NULL,
    action         text NOT NULL CHECK (action IN ('BINDING_REMOVED', 'OFFERING_REMOVED', 'COURSE_ARCHIVED', 'COURSE_DELETED', 'PROPOSAL_CANCELLED')),
    programme_code text NULL,
    level          int NULL,
    detail         jsonb NULL,
    at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_course_reset_item ON catalogue.course_reset_item (reset_id, action);
CREATE INDEX ix_course_reset_item_course ON catalogue.course_reset_item (course_code);
SELECT audit.attach('catalogue.course_reset_item');
COMMENT ON TABLE catalogue.course_reset_item IS 'V338: what one reset did, course by course: each binding it ended, each empty offering it removed, each course it archived or removed (with the row as it was), each proposal it cancelled. No key to the course, so it outlives a removed one.';

/* the scope of a reset: its programmes, its departments (whose courses it clears), and its name */
CREATE OR REPLACE FUNCTION catalogue.reset_scope(p_scope text, p_ref text)
RETURNS TABLE (programmes text[], departments text[], label text, scope_ref text)
LANGUAGE plpgsql STABLE AS $$
DECLARE s text := upper(btrim(coalesce(p_scope, ''))); r text := btrim(coalesce(p_ref, '')); v_code text; v_name text;
BEGIN
    IF s = 'ALL' THEN
        RETURN QUERY SELECT ARRAY(SELECT p.code FROM ref.programme p), ARRAY(SELECT d.code FROM ref.department d), 'The whole course catalogue'::text, NULL::text;
    ELSIF s = 'FACULTY' THEN
        SELECT f.code, f.name INTO v_code, v_name FROM ref.faculty f WHERE upper(f.code) = upper(r) OR upper(f.name) = upper(r) LIMIT 1;
        IF v_code IS NULL THEN RAISE EXCEPTION 'CAT_RESET_SCOPE: no faculty is coded or named %', r USING ERRCODE = '23514'; END IF;
        RETURN QUERY SELECT ARRAY(SELECT p.code FROM ref.programme p WHERE p.faculty_code = v_code),
                            ARRAY(SELECT d.code FROM ref.department d WHERE d.faculty_code = v_code), 'Faculty: ' || v_name, v_code;
    ELSIF s = 'DEPARTMENT' THEN
        SELECT d.code, d.name INTO v_code, v_name FROM ref.department d WHERE upper(d.code) = upper(r) OR upper(d.name) = upper(r) LIMIT 1;
        IF v_code IS NULL THEN RAISE EXCEPTION 'CAT_RESET_SCOPE: no department is coded or named %', r USING ERRCODE = '23514'; END IF;
        RETURN QUERY SELECT ARRAY(SELECT p.code FROM ref.programme p WHERE p.dept_code = v_code), ARRAY[v_code], 'Department: ' || v_name, v_code;
    ELSIF s = 'PROGRAMME' THEN
        SELECT p.code, p.name INTO v_code, v_name FROM ref.programme p WHERE upper(p.code) = upper(r) OR upper(p.name) = upper(r) ORDER BY p.archived LIMIT 1;
        IF v_code IS NULL THEN RAISE EXCEPTION 'CAT_RESET_SCOPE: no programme is coded or named %', r USING ERRCODE = '23514'; END IF;
        RETURN QUERY SELECT ARRAY[v_code], ARRAY[]::text[], 'Programme: ' || v_name || ' (' || v_code || ')', v_code;
    ELSE
        RAISE EXCEPTION 'CAT_RESET_SCOPE: a reset is of the whole catalogue, a faculty, a department or a programme' USING ERRCODE = '23514';
    END IF;
END $$;

/* the courses a reset clears: every active course the scope's departments own (not GST/EPS); for a programme, the courses of its
   department bound to it alone. Bindings: every binding into the scope's programmes, and every binding of those courses. */
CREATE OR REPLACE FUNCTION catalogue.reset_courses(p_programmes text[], p_departments text[], p_scope text)
RETURNS text[] LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN upper(p_scope) = 'PROGRAMME' THEN
        ARRAY(SELECT c.code FROM catalogue.course c
               WHERE c.general_office IS NULL AND c.state <> 'ENDED'
                 AND c.dept_code = (SELECT p.dept_code FROM ref.programme p WHERE p.code = p_programmes[1])
                 AND EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code AND co.programme_code = ANY (p_programmes))
                 AND NOT EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code AND NOT (co.programme_code = ANY (p_programmes))))
    ELSE
        ARRAY(SELECT c.code FROM catalogue.course c
               WHERE c.general_office IS NULL AND c.state <> 'ENDED' AND c.dept_code = ANY (p_departments))
    END;
$$;

/* what a reset would do, before it is done */
CREATE OR REPLACE FUNCTION catalogue.course_reset_preview(p_scope text, p_ref text)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE sc record; v_courses text[]; v_out jsonb;
BEGIN
    SELECT * INTO sc FROM catalogue.reset_scope(p_scope, p_ref);
    v_courses := catalogue.reset_courses(sc.programmes, sc.departments, p_scope);
    WITH b AS (
        SELECT co.* FROM catalogue.course_offer co JOIN catalogue.course c ON c.code = co.course_code
         WHERE c.general_office IS NULL AND (co.programme_code = ANY (sc.programmes) OR co.course_code = ANY (v_courses))
    ), o AS (
        SELECT o.id, o.session, o.semester, catalogue.offering_has_history(o.id) AS kept
          FROM catalogue.offering o WHERE o.course_code = ANY (v_courses)
    ), h AS (
        SELECT x.code, catalogue.course_has_history(x.code) AS archived,
               EXISTS (SELECT 1 FROM registration.entry e JOIN catalogue.offering f ON f.id = e.offering_id WHERE f.course_code = x.code) AS registered,
               EXISTS (SELECT 1 FROM assessment.score s JOIN assessment.score_sheet sh ON sh.id = s.sheet_id JOIN catalogue.offering f ON f.id = sh.offering_id WHERE f.course_code = x.code)
               OR EXISTS (SELECT 1 FROM assessment.legacy_result_holding l WHERE l.course_code = x.code) AS resulted
          FROM unnest(v_courses) AS x(code)
    )
    SELECT jsonb_build_object(
        'scope', upper(p_scope), 'scopeRef', sc.scope_ref, 'label', sc.label,
        'courses', cardinality(v_courses),
        'bindings', (SELECT count(*) FROM b),
        'programmesAffected', (SELECT count(DISTINCT programme_code) FROM b),
        'departmentsAffected', (SELECT count(DISTINCT d) FROM (SELECT p.dept_code AS d FROM b JOIN ref.programme p ON p.code = b.programme_code
                                                              UNION SELECT c.dept_code FROM catalogue.course c WHERE c.code = ANY (v_courses)) z),
        'offerings', (SELECT count(*) FROM o),
        'offeringsRemoved', (SELECT count(*) FROM o WHERE NOT kept),
        'offeringsKept', (SELECT count(*) FROM o WHERE kept),
        'sessions', (SELECT coalesce(jsonb_agg(DISTINCT session ORDER BY session), '[]'::jsonb) FROM o),
        'referencedByRegistrations', (SELECT count(*) FROM h WHERE registered),
        'referencedByResults', (SELECT count(*) FROM h WHERE resulted),
        'toArchive', (SELECT count(*) FROM h WHERE archived),
        'toDelete', (SELECT count(*) FROM h WHERE NOT archived),
        'gstKept', (SELECT count(DISTINCT co.course_code) FROM catalogue.course_offer co JOIN catalogue.course c ON c.code = co.course_code
                     WHERE c.general_office IS NOT NULL AND co.programme_code = ANY (sc.programmes)),
        'pendingProposals', (SELECT count(*) FROM catalogue.offer_proposal pr WHERE pr.state = 'PENDING'
                              AND (pr.course_code = ANY (v_courses) OR pr.programme_code = ANY (sc.programmes))),
        'activeCourses', (SELECT count(*) FROM catalogue.course c WHERE c.state <> 'ENDED' AND c.general_office IS NULL)
    ) INTO v_out;
    RETURN v_out;
END $$;

/* the reset itself: one transaction, one reference, everything it did recorded; history archived, never deleted */
CREATE OR REPLACE FUNCTION catalogue.course_reset(p_scope text, p_ref text, p_reason text, p_confirm text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        sc record; v_courses text[]; v_off uuid[]; v_archive text[]; v_delete text[]; v_id uuid; v_ref text; v_pre jsonb;
        n_bind int := 0; n_off int := 0; n_kept int := 0; n_arch int := 0; n_del int := 0; n_prop int := 0;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a course reset is done by a person' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_confirm), '') <> 'RESET COURSES' THEN
        RAISE EXCEPTION 'CAT_RESET_CONFIRM: type RESET COURSES to confirm the reset' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN
        RAISE EXCEPTION 'CAT_RESET_REASON: say why the catalogue is reset (at least five characters)' USING ERRCODE = '23514';
    END IF;
    -- one reset or catalogue upload at a time
    PERFORM pg_advisory_xact_lock(hashtext('catalogue.course_catalogue'));
    SELECT * INTO sc FROM catalogue.reset_scope(p_scope, p_ref);
    v_pre := catalogue.course_reset_preview(p_scope, p_ref);
    v_courses := catalogue.reset_courses(sc.programmes, sc.departments, p_scope);
    v_ref := 'COURSE-RESET-' || to_char(now(), 'YYYY') || '-' || lpad(platform.next_number('COURSE_RESET', 'UNIVERSITY', to_char(now(), 'YYYY'))::text, 5, '0');
    PERFORM set_config('moaum.reason', 'Course reset ' || v_ref || ': ' || btrim(p_reason), true);
    PERFORM set_config('moaum.owner_source', 'RESET', true);
    INSERT INTO catalogue.course_reset (ref, scope, scope_ref, scope_label, reason, courses_in_scope, programmes_affected, departments_affected, performed_by, performed_office)
    VALUES (v_ref, upper(p_scope), sc.scope_ref, sc.label, btrim(p_reason), cardinality(v_courses),
            (v_pre->>'programmesAffected')::int, (v_pre->>'departmentsAffected')::int, who, office)
    RETURNING id INTO v_id;

    -- the bindings end: kept on the binding history (with what they carried) and on the reset's items
    WITH gone AS (
        DELETE FROM catalogue.course_offer co
         USING catalogue.course c
         WHERE c.code = co.course_code AND c.general_office IS NULL
           AND (co.programme_code = ANY (sc.programmes) OR co.course_code = ANY (v_courses))
        RETURNING co.*
    ), hist AS (
        INSERT INTO catalogue.course_offer_history (course_code, programme_code, level, basis, track, added_at, added_by, source, ended_by, ended_office, reason, registrations_carried)
        SELECT g.course_code, g.programme_code, g.level, g.basis, g.track, g.added_at, g.added_by, g.source, who, office, 'Course reset ' || v_ref,
               (SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                  JOIN catalogue.offering f ON f.id = e.offering_id JOIN people.student st ON st.id = r.student_id
                 WHERE f.course_code = g.course_code AND st.programme_code = g.programme_code AND r.level = g.level)
          FROM gone g
        RETURNING 1
    ), items AS (
        INSERT INTO catalogue.course_reset_item (reset_id, course_code, action, programme_code, level, detail)
        SELECT v_id, g.course_code, 'BINDING_REMOVED', g.programme_code, g.level, jsonb_build_object('basis', g.basis, 'track', g.track, 'source', g.source, 'added_at', g.added_at)
          FROM gone g
        RETURNING 1
    )
    SELECT count(*) INTO n_bind FROM items;

    -- the pending proposals of those courses, or into those programmes, are cancelled
    WITH c AS (
        UPDATE catalogue.offer_proposal pr
           SET state = 'CANCELLED', decided_by = who, decided_office = office, decided_at = now(), decision_note = 'Course reset ' || v_ref
         WHERE pr.state = 'PENDING' AND (pr.course_code = ANY (v_courses) OR pr.programme_code = ANY (sc.programmes))
        RETURNING pr.course_code, pr.programme_code, pr.level
    ), items AS (
        INSERT INTO catalogue.course_reset_item (reset_id, course_code, action, programme_code, level)
        SELECT v_id, c.course_code, 'PROPOSAL_CANCELLED', c.programme_code, c.level FROM c RETURNING 1
    )
    SELECT count(*) INTO n_prop FROM items;

    -- a session offering with nothing on it is removed; one with anything on it stays
    v_off := ARRAY(SELECT o.id FROM catalogue.offering o WHERE o.course_code = ANY (v_courses) AND NOT catalogue.offering_has_history(o.id));
    SELECT count(*) INTO n_kept FROM catalogue.offering o WHERE o.course_code = ANY (v_courses) AND NOT (o.id = ANY (v_off));
    INSERT INTO catalogue.course_reset_item (reset_id, course_code, action, detail)
    SELECT v_id, o.course_code, 'OFFERING_REMOVED', jsonb_build_object('session', o.session, 'semester', o.semester, 'title', o.title, 'units', o.units)
      FROM catalogue.offering o WHERE o.id = ANY (v_off);
    DELETE FROM catalogue.offering o WHERE o.id = ANY (v_off);
    n_off := cardinality(v_off);

    -- a course anything hangs on is archived, never deleted; the rest are removed, kept whole on the reset's items
    v_archive := ARRAY(SELECT x FROM unnest(v_courses) x WHERE catalogue.course_has_history(x));
    v_delete := ARRAY(SELECT x FROM unnest(v_courses) x WHERE NOT (x = ANY (v_archive)));
    INSERT INTO catalogue.course_reset_item (reset_id, course_code, action, detail)
    SELECT v_id, c.code, 'COURSE_ARCHIVED', jsonb_build_object('state', c.state, 'title', c.title, 'units', c.units, 'dept_code', c.dept_code, 'owner_programme', c.owner_programme)
      FROM catalogue.course c WHERE c.code = ANY (v_archive);
    UPDATE catalogue.course SET state = 'ENDED', ended_on = coalesce(ended_on, current_date), reset_batch_id = v_id WHERE code = ANY (v_archive);
    n_arch := cardinality(v_archive);
    INSERT INTO catalogue.course_reset_item (reset_id, course_code, action, detail)
    SELECT v_id, c.code, 'COURSE_DELETED', to_jsonb(c) FROM catalogue.course c WHERE c.code = ANY (v_delete);
    DELETE FROM catalogue.course WHERE code = ANY (v_delete);
    n_del := cardinality(v_delete);

    UPDATE catalogue.course_reset
       SET bindings_removed = n_bind, offerings_removed = n_off, offerings_kept = n_kept, archived = n_arch, deleted = n_del, proposals_cancelled = n_prop
     WHERE id = v_id;
    RETURN jsonb_build_object('id', v_id, 'ref', v_ref, 'scope', upper(p_scope), 'label', sc.label, 'courses', cardinality(v_courses),
                              'bindingsRemoved', n_bind, 'offeringsRemoved', n_off, 'offeringsKept', n_kept, 'archived', n_arch, 'deleted', n_del,
                              'proposalsCancelled', n_prop);
END $$;
COMMENT ON FUNCTION catalogue.course_reset(text, text, text, text) IS
  'V338: clear the active course catalogue of the whole University, a faculty, a department or a programme, in one transaction under one reference. '
  'Bindings end (kept on history), empty offerings and courses are removed, a course with any academic history is archived (ENDED) and never deleted, '
  'GST/EPS courses are left to their office. Registrations, results, transcripts, CBT, payments and the audit spine are untouched.';

-- ── 7 · the catalogue upload: one row per offering, the course's owner named, validated before anything is written ──

CREATE TABLE catalogue.course_import (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref               text NOT NULL UNIQUE,
    file_name         text NULL,
    rows              int NOT NULL DEFAULT 0,
    courses_created   int NOT NULL DEFAULT 0,
    courses_updated   int NOT NULL DEFAULT 0,
    courses_revived   int NOT NULL DEFAULT 0,
    owner_changes     int NOT NULL DEFAULT 0,
    offerings_created int NOT NULL DEFAULT 0,
    offerings_updated int NOT NULL DEFAULT 0,
    prerequisites     int NOT NULL DEFAULT 0,
    result            jsonb NULL,
    imported_by       uuid NOT NULL,
    imported_office   text NULL,
    imported_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_course_import_at ON catalogue.course_import (imported_at DESC);
SELECT audit.attach('catalogue.course_import');
COMMENT ON TABLE catalogue.course_import IS 'V338: each committed catalogue upload under its reference, with the rows as validated and what it created, updated, revived and bound.';

/* a faculty, department or programme named by its code or its name, with "Faculty of" / "Department of" allowed before the name */
CREATE OR REPLACE FUNCTION catalogue.bare_name(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT upper(btrim(regexp_replace(coalesce(p, ''), '^\s*(the\s+)?(faculty|department|school|college|institute)\s+of\s+', '', 'i')));
$$;

/* the rows, read and judged: every reference resolved against the register, every rule checked, nothing written */
CREATE OR REPLACE FUNCTION catalogue.import_catalogue_rows(p_rows jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $$
WITH raw AS (
    SELECT ord::int AS n, r AS j FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) WITH ORDINALITY AS t(r, ord)
), norm AS (
    SELECT n,
           nullif(btrim(coalesce(j->>'code', '')), '') AS code_raw,
           coalesce(catalogue.normal_code(j->>'code'), nullif(regexp_replace(upper(btrim(coalesce(j->>'code', ''))), '\s+', ' ', 'g'), '')) AS code,
           nullif(btrim(coalesce(j->>'title', '')), '') AS title,
           nullif(btrim(coalesce(j->>'units', '')), '') AS units_raw,
           nullif(btrim(coalesce(j->>'level', '')), '') AS level_raw,
           nullif(btrim(coalesce(j->>'semester', '')), '') AS sem_raw,
           nullif(btrim(coalesce(j->>'courseType', '')), '') AS type_raw,
           nullif(btrim(coalesce(j->>'ownerFaculty', '')), '') AS ofa_raw,
           nullif(btrim(coalesce(j->>'ownerDepartment', '')), '') AS od_raw,
           nullif(btrim(coalesce(j->>'ownerProgramme', '')), '') AS op_raw,
           nullif(btrim(coalesce(j->>'offeringFaculty', '')), '') AS ffa_raw,
           nullif(btrim(coalesce(j->>'offeringDepartment', '')), '') AS fd_raw,
           nullif(btrim(coalesce(j->>'offeringProgramme', '')), '') AS fp_raw,
           upper(nullif(btrim(coalesce(j->>'offeringType', '')), '')) AS otype_raw,
           upper(nullif(btrim(coalesce(j->>'status', '')), '')) AS status_raw,
           nullif(btrim(coalesce(j->>'session', '')), '') AS session_raw,
           nullif(btrim(coalesce(j->>'description', '')), '') AS description,
           nullif(btrim(coalesce(j->>'prerequisite', '')), '') AS prereq_raw,
           upper(nullif(btrim(coalesce(j->>'classification', '')), '')) AS class_raw,
           nullif(btrim(coalesce(j->>'remarks', '')), '') AS remarks
      FROM raw
     WHERE coalesce(btrim(j->>'code'), '') <> '' OR coalesce(btrim(j->>'title'), '') <> '' OR coalesce(btrim(j->>'offeringProgramme'), '') <> ''
), res AS (
    SELECT x.*,
           CASE WHEN x.units_raw ~ '^[0-9]{1,2}$' AND x.units_raw::int <= 12 THEN x.units_raw::int END AS units,
           CASE WHEN regexp_replace(coalesce(x.level_raw, ''), '[^0-9]', '', 'g') ~ '^[1-9]00$' THEN regexp_replace(x.level_raw, '[^0-9]', '', 'g')::int END AS level,
           CASE WHEN x.sem_raw ~* '^(1|1st|first)' THEN 1 WHEN x.sem_raw ~* '^(2|2nd|second)' THEN 2 WHEN x.sem_raw ~* '^(3|3rd|third)' THEN 3 END AS semester,
           CASE WHEN x.type_raw IS NULL THEN NULL WHEN upper(x.type_raw) = 'GST' THEN 'GST'
                WHEN upper(x.type_raw) IN ('CORE', 'COMPULSORY') THEN 'Core' WHEN upper(x.type_raw) = 'REQUIRED' THEN 'Required'
                WHEN upper(x.type_raw) = 'ELECTIVE' THEN 'Elective' END AS course_type,
           ofa.code AS ofa, od.code AS od, od.faculty_code AS od_fac, op.code AS op, op.dept_code AS op_dept,
           ffa.code AS ffa, fd.code AS fd, fp.code AS fp, fp.dept_code AS fp_dept, fp.faculty_code AS fp_fac, coalesce(fp.archived, false) AS fp_archived,
           ec.code AS existing, ec.state AS existing_state, ec.reset_batch_id AS existing_reset, ec.dept_code AS existing_dept,
           ec.owner_programme AS existing_prog, ec.general_office AS existing_office,
           EXISTS (SELECT 1 FROM policy.academic_session s WHERE s.name = x.session_raw) AS session_ok
      FROM norm x
      LEFT JOIN LATERAL (SELECT f.code FROM ref.faculty f
                          WHERE x.ofa_raw IS NOT NULL AND (upper(f.code) = upper(x.ofa_raw) OR upper(f.name) = catalogue.bare_name(x.ofa_raw) OR upper(f.name) = upper(x.ofa_raw)) LIMIT 1) ofa ON true
      LEFT JOIN LATERAL (SELECT d.code, d.faculty_code FROM ref.department d
                          WHERE x.od_raw IS NOT NULL AND d.ended_on IS NULL
                            AND (upper(d.code) = upper(x.od_raw) OR upper(d.name) = catalogue.bare_name(x.od_raw) OR upper(d.name) = upper(x.od_raw)) LIMIT 1) od ON true
      LEFT JOIN LATERAL (SELECT p.code, p.dept_code FROM ref.programme p
                          WHERE x.op_raw IS NOT NULL AND NOT coalesce(p.archived, false) AND (upper(p.code) = upper(x.op_raw) OR upper(p.name) = upper(x.op_raw))
                          ORDER BY (p.dept_code = od.code) DESC NULLS LAST LIMIT 1) op ON true
      LEFT JOIN LATERAL (SELECT f.code FROM ref.faculty f
                          WHERE x.ffa_raw IS NOT NULL AND (upper(f.code) = upper(x.ffa_raw) OR upper(f.name) = catalogue.bare_name(x.ffa_raw) OR upper(f.name) = upper(x.ffa_raw)) LIMIT 1) ffa ON true
      LEFT JOIN LATERAL (SELECT d.code FROM ref.department d
                          WHERE x.fd_raw IS NOT NULL AND d.ended_on IS NULL
                            AND (upper(d.code) = upper(x.fd_raw) OR upper(d.name) = catalogue.bare_name(x.fd_raw) OR upper(d.name) = upper(x.fd_raw)) LIMIT 1) fd ON true
      LEFT JOIN LATERAL (SELECT p.code, p.dept_code, p.faculty_code, p.archived FROM ref.programme p
                          WHERE x.fp_raw IS NOT NULL AND (upper(p.code) = upper(x.fp_raw) OR upper(p.name) = upper(x.fp_raw))
                          ORDER BY coalesce(p.archived, false), (p.dept_code = fd.code) DESC NULLS LAST LIMIT 1) fp ON true
      LEFT JOIN catalogue.course ec ON ec.code = x.code
), judged AS (
    SELECT r.*,
           coalesce(r.od, r.existing_dept) AS owner_dept,
           CASE WHEN r.class_raw IN ('GST', 'EPS') THEN 'GST' WHEN r.otype_raw IN ('CORE', 'C') THEN 'Core' WHEN r.otype_raw IN ('ELECTIVE', 'E') THEN 'Elective' END AS basis,
           row_number() OVER (PARTITION BY r.code, r.fp, r.level ORDER BY r.n) AS dup_rank,
           a.titles, a.unitss, a.sems, a.owners, a.owner_progs,
           ARRAY(SELECT coalesce(catalogue.normal_code(q), regexp_replace(upper(btrim(q)), '\s+', ' ', 'g'))
                   FROM unnest(regexp_split_to_array(coalesce(r.prereq_raw, ''), '\s*[,;/]\s*')) q WHERE btrim(q) <> '') AS prereqs
      FROM res r
      JOIN (SELECT code,
                   count(DISTINCT upper(title)) FILTER (WHERE title IS NOT NULL) AS titles,
                   count(DISTINCT units) FILTER (WHERE units IS NOT NULL) AS unitss,
                   count(DISTINCT semester) FILTER (WHERE semester IS NOT NULL) AS sems,
                   count(DISTINCT od) FILTER (WHERE od IS NOT NULL) AS owners,
                   count(DISTINCT op) FILTER (WHERE op IS NOT NULL) AS owner_progs
              FROM res GROUP BY code) a ON a.code IS NOT DISTINCT FROM r.code
), checked AS (
    SELECT j.*,
           array_remove(ARRAY[
             CASE WHEN j.code_raw IS NULL THEN 'CODE_MISSING: the course code is blank'
                  WHEN j.code !~ '^[A-Z][A-Z0-9 /-]{2,19}$' THEN 'CODE_INVALID: ' || j.code_raw || ' is not a course code' END,
             CASE WHEN j.title IS NULL AND j.existing IS NULL THEN 'TITLE_MISSING: a new course needs its title' END,
             CASE WHEN j.units_raw IS NOT NULL AND j.units IS NULL THEN 'UNITS_INVALID: units are a whole number from 0 to 12'
                  WHEN j.units IS NULL AND j.existing IS NULL THEN 'UNITS_INVALID: a new course needs its units' END,
             CASE WHEN j.level IS NULL THEN 'LEVEL_INVALID: the level is 100 to 900' END,
             CASE WHEN j.sem_raw IS NOT NULL AND j.semester IS NULL THEN 'SEMESTER_INVALID: the semester is 1, 2 or 3'
                  WHEN j.semester IS NULL AND j.existing IS NULL THEN 'SEMESTER_INVALID: a new course needs its semester' END,
             CASE WHEN j.type_raw IS NOT NULL AND j.course_type IS NULL THEN 'COURSE_TYPE_INVALID: the course type is Core, Required, Elective or GST' END,
             CASE WHEN j.od_raw IS NULL AND j.existing IS NULL THEN 'OWNER_DEPARTMENT_MISSING: a new course needs the department that owns it'
                  WHEN j.od_raw IS NOT NULL AND j.od IS NULL THEN 'OWNER_DEPARTMENT_UNKNOWN: no live department is coded or named ' || j.od_raw END,
             CASE WHEN j.ofa_raw IS NOT NULL AND j.ofa IS NULL THEN 'OWNER_FACULTY_UNKNOWN: no faculty is coded or named ' || j.ofa_raw
                  WHEN j.ofa IS NOT NULL AND j.od IS NOT NULL AND j.od_fac IS DISTINCT FROM j.ofa THEN 'OWNER_FACULTY_MISMATCH: the owner department is not in that faculty' END,
             CASE WHEN j.op_raw IS NOT NULL AND j.op IS NULL THEN 'OWNER_PROGRAMME_UNKNOWN: no live programme is coded or named ' || j.op_raw
                  WHEN j.op IS NOT NULL AND j.op_dept IS DISTINCT FROM coalesce(j.od, j.existing_dept) THEN 'OWNER_PROGRAMME_NOT_IN_DEPARTMENT: the owner programme is not a programme of the owner department' END,
             CASE WHEN j.fp_raw IS NULL THEN 'OFFERING_PROGRAMME_MISSING: name the programme that offers the course'
                  WHEN j.fp IS NULL THEN 'OFFERING_PROGRAMME_UNKNOWN: no programme is coded or named ' || j.fp_raw
                  WHEN j.fp_archived THEN 'OFFERING_PROGRAMME_ARCHIVED: ' || j.fp || ' is archived' END,
             CASE WHEN j.fd_raw IS NOT NULL AND j.fd IS NULL THEN 'OFFERING_DEPARTMENT_UNKNOWN: no live department is coded or named ' || j.fd_raw
                  WHEN j.fd IS NOT NULL AND j.fp IS NOT NULL AND j.fp_dept IS DISTINCT FROM j.fd THEN 'OFFERING_PROGRAMME_NOT_IN_DEPARTMENT: the offering programme is not a programme of that department' END,
             CASE WHEN j.ffa_raw IS NOT NULL AND j.ffa IS NULL THEN 'OFFERING_FACULTY_UNKNOWN: no faculty is coded or named ' || j.ffa_raw
                  WHEN j.ffa IS NOT NULL AND j.fp IS NOT NULL AND j.fp_fac IS DISTINCT FROM j.ffa THEN 'OFFERING_FACULTY_MISMATCH: the offering programme is not in that faculty' END,
             CASE WHEN j.class_raw IS NOT NULL AND j.class_raw NOT IN ('GST', 'EPS') THEN 'CLASSIFICATION_INVALID: the GST/EPS classification is GST, EPS or blank'
                  WHEN j.basis IS NULL THEN 'OFFERING_TYPE_INVALID: the offering type is CORE or ELECTIVE' END,
             CASE WHEN j.status_raw IS NOT NULL AND j.status_raw NOT IN ('ACTIVE', 'INACTIVE') THEN 'STATUS_INVALID: the status is ACTIVE or INACTIVE' END,
             CASE WHEN j.session_raw IS NOT NULL AND NOT j.session_ok THEN 'SESSION_UNKNOWN: no academic session is named ' || j.session_raw END,
             CASE WHEN j.existing IS NOT NULL AND j.existing_state = 'ENDED' AND j.existing_reset IS NULL THEN 'COURSE_ENDED: ' || j.code || ' was ended on its department''s desk; restore it there first' END,
             CASE WHEN j.dup_rank > 1 THEN 'DUPLICATE_OFFERING: ' || j.code || ' is offered to ' || j.fp || ' at ' || j.level || ' level on an earlier row' END,
             CASE WHEN j.titles > 1 OR j.unitss > 1 OR j.sems > 1 OR j.owners > 1 OR j.owner_progs > 1
                  THEN 'COURSE_CONFLICT: the rows of ' || j.code || ' disagree on its title, units, semester or owner' END,
             CASE WHEN EXISTS (SELECT 1 FROM unnest(j.prereqs) q WHERE q = j.code) THEN 'PREREQUISITE_INVALID: a course does not require itself'
                  WHEN EXISTS (SELECT 1 FROM unnest(j.prereqs) q
                                WHERE NOT EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = q)
                                  AND NOT EXISTS (SELECT 1 FROM res r2 WHERE r2.code = q))
                  THEN 'PREREQUISITE_UNKNOWN: ' || (SELECT string_agg(q, ', ') FROM unnest(j.prereqs) q
                                                     WHERE NOT EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = q) AND NOT EXISTS (SELECT 1 FROM res r2 WHERE r2.code = q)) || ' is not a course' END
           ], NULL) AS errors
      FROM judged j
)
SELECT coalesce(jsonb_agg(jsonb_build_object(
           'n', c.n, 'code', c.code, 'title', c.title, 'units', c.units, 'level', c.level, 'semester', c.semester,
           'ownerDepartment', c.owner_dept, 'ownerProgramme', coalesce(c.op, CASE WHEN c.od IS NULL OR c.od = c.existing_dept THEN c.existing_prog END),
           'offeringProgramme', c.fp, 'offeringDepartment', c.fp_dept, 'basis', c.basis, 'courseType', c.course_type, 'description', c.description,
           'prerequisites', to_jsonb(c.prereqs), 'remarks', c.remarks, 'session', c.session_raw,
           'state', CASE WHEN cardinality(c.errors) > 0 THEN 'INVALID' WHEN c.status_raw = 'INACTIVE' THEN 'SKIPPED' ELSE 'VALID' END,
           'errors', to_jsonb(c.errors),
           'existing', c.existing IS NOT NULL, 'general', c.existing_office IS NOT NULL,
           'revived', c.existing IS NOT NULL AND c.existing_state = 'ENDED' AND c.existing_reset IS NOT NULL,
           'ownerChange', c.existing IS NOT NULL AND c.existing_office IS NULL AND c.od IS NOT NULL AND c.od <> c.existing_dept,
           'existingOffering', EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code AND co.programme_code = c.fp AND co.level = c.level)
       ) ORDER BY c.n), '[]'::jsonb)
  FROM checked c;
$$;

/* the upload: judged in full, then — only when asked and only when no row is invalid — written in one transaction */
CREATE OR REPLACE FUNCTION catalogue.import_catalogue(p_rows jsonb, p_commit boolean, p_file text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_rows jsonb; v_sum jsonb; v_id uuid; v_ref text; v_valid jsonb;
        n_new int := 0; n_upd int := 0; n_rev int := 0; n_own int := 0; n_bnew int := 0; n_bupd int := 0; n_pre int := 0;
BEGIN
    v_rows := catalogue.import_catalogue_rows(p_rows);
    SELECT jsonb_build_object(
        'total', count(*),
        'valid', count(*) FILTER (WHERE x->>'state' = 'VALID'),
        'invalid', count(*) FILTER (WHERE x->>'state' = 'INVALID'),
        'skipped', count(*) FILTER (WHERE x->>'state' = 'SKIPPED'),
        'newCourses', count(DISTINCT x->>'code') FILTER (WHERE x->>'state' = 'VALID' AND NOT (x->>'existing')::boolean),
        'existingCourses', count(DISTINCT x->>'code') FILTER (WHERE x->>'state' = 'VALID' AND (x->>'existing')::boolean),
        'revivedCourses', count(DISTINCT x->>'code') FILTER (WHERE x->>'state' = 'VALID' AND (x->>'revived')::boolean),
        'ownerChanges', count(DISTINCT x->>'code') FILTER (WHERE x->>'state' = 'VALID' AND (x->>'ownerChange')::boolean),
        'newOfferings', count(*) FILTER (WHERE x->>'state' = 'VALID' AND NOT (x->>'existingOffering')::boolean),
        'existingOfferings', count(*) FILTER (WHERE x->>'state' = 'VALID' AND (x->>'existingOffering')::boolean),
        'duplicateOfferings', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ starts with "DUPLICATE_OFFERING")'),
        'conflicts', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ starts with "COURSE_CONFLICT")' OR x->'errors' @? '$[*] ? (@ starts with "COURSE_ENDED")'),
        'ownerErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ starts with "OWNER_")'),
        'programmeErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ like_regex "PROGRAMME_")'),
        'departmentErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ like_regex "DEPARTMENT_")'),
        'facultyErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ like_regex "FACULTY_")'),
        'typeErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ starts with "OFFERING_TYPE" || @ starts with "CLASSIFICATION" || @ starts with "COURSE_TYPE")'),
        'prerequisiteErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ starts with "PREREQUISITE")'))
      INTO v_sum
      FROM jsonb_array_elements(v_rows) x;
    IF NOT coalesce(p_commit, false) THEN
        RETURN jsonb_build_object('committed', false, 'summary', v_sum, 'rows', v_rows);
    END IF;

    IF who IS NULL THEN RAISE EXCEPTION 'a catalogue upload is committed by a person' USING ERRCODE = '23514'; END IF;
    IF (v_sum->>'invalid')::int > 0 THEN
        RAISE EXCEPTION 'CAT_IMPORT_INVALID: % row(s) are invalid; nothing was written', v_sum->>'invalid' USING ERRCODE = '23514',
            HINT = 'Download the error report, correct the rows and upload the file again.';
    END IF;
    IF (v_sum->>'valid')::int = 0 THEN
        RAISE EXCEPTION 'CAT_IMPORT_EMPTY: the file has no row to import' USING ERRCODE = '23514';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('catalogue.course_catalogue'));
    v_ref := 'COURSE-IMPORT-' || to_char(now(), 'YYYY') || '-' || lpad(platform.next_number('COURSE_IMPORT', 'UNIVERSITY', to_char(now(), 'YYYY'))::text, 5, '0');
    PERFORM set_config('moaum.reason', 'Course catalogue upload ' || v_ref, true);
    PERFORM set_config('moaum.owner_source', 'IMPORT', true);
    v_valid := (SELECT jsonb_agg(x) FROM jsonb_array_elements(v_rows) x WHERE x->>'state' = 'VALID');

    -- one course per code: its title, units, semester and owner from its rows; its level from the owner programme's row
    WITH per AS (
        SELECT x->>'code' AS code,
               (array_agg(x->>'title' ORDER BY (x->>'n')::int) FILTER (WHERE x->>'title' IS NOT NULL))[1] AS title,
               (array_agg((x->>'units')::int ORDER BY (x->>'n')::int) FILTER (WHERE x->>'units' IS NOT NULL))[1] AS units,
               (array_agg((x->>'semester')::int ORDER BY (x->>'n')::int) FILTER (WHERE x->>'semester' IS NOT NULL))[1] AS semester,
               (array_agg((x->>'level')::int ORDER BY coalesce(x->>'offeringProgramme' = x->>'ownerProgramme', false) DESC, (x->>'level')::int))[1] AS level,
               (array_agg(x->>'ownerDepartment' ORDER BY (x->>'n')::int) FILTER (WHERE x->>'ownerDepartment' IS NOT NULL))[1] AS dept,
               (array_agg(x->>'ownerProgramme' ORDER BY (x->>'n')::int) FILTER (WHERE x->>'ownerProgramme' IS NOT NULL))[1] AS prog,
               (array_agg(x->>'courseType' ORDER BY (x->>'n')::int) FILTER (WHERE x->>'courseType' IS NOT NULL))[1] AS ctype,
               bool_or(x->>'basis' = 'GST') AS gst,
               (array_agg(x->>'description' ORDER BY (x->>'n')::int) FILTER (WHERE x->>'description' IS NOT NULL))[1] AS description,
               bool_or((x->>'existing')::boolean) AS existing, bool_or((x->>'general')::boolean) AS general,
               bool_or((x->>'revived')::boolean) AS revived, bool_or((x->>'ownerChange')::boolean) AS owner_change
          FROM jsonb_array_elements(v_valid) x GROUP BY x->>'code'
    ), ins AS (
        INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, owner_programme, kind, description, state)
        SELECT p.code, p.title, p.units, p.semester, p.level, p.dept, p.prog,
               CASE WHEN p.gst THEN 'GST' ELSE coalesce(p.ctype, 'Core') END, p.description, 'LIVE'
          FROM per p WHERE NOT p.existing
        RETURNING 1
    ), upd AS (
        UPDATE catalogue.course c
           SET title = coalesce(p.title, c.title), units = coalesce(p.units, c.units), semester = coalesce(p.semester, c.semester),
               dept_code = coalesce(p.dept, c.dept_code),
               owner_programme = CASE WHEN p.prog IS NOT NULL THEN p.prog WHEN p.dept IS NOT NULL AND p.dept <> c.dept_code THEN NULL ELSE c.owner_programme END,
               kind = CASE WHEN p.gst THEN 'GST' ELSE coalesce(p.ctype, c.kind) END,
               description = coalesce(p.description, c.description),
               state = CASE WHEN c.reset_batch_id IS NOT NULL OR c.state IN ('BOARD', 'SENATE') THEN 'LIVE' ELSE c.state END,
               ended_on = CASE WHEN c.reset_batch_id IS NOT NULL THEN NULL ELSE c.ended_on END,
               reset_batch_id = NULL
          FROM per p
         WHERE c.code = p.code AND p.existing AND NOT p.general
        RETURNING 1
    )
    SELECT (SELECT count(*) FROM ins), (SELECT count(*) FROM upd),
           (SELECT count(*) FROM per WHERE revived), (SELECT count(*) FROM per WHERE owner_change)
      INTO n_new, n_upd, n_rev, n_own;

    -- the offerings: one binding per course, programme and level, Core / Elective / GST as the row says
    SELECT count(*) FILTER (WHERE NOT (x->>'existingOffering')::boolean), count(*) FILTER (WHERE (x->>'existingOffering')::boolean)
      INTO n_bnew, n_bupd FROM jsonb_array_elements(v_valid) x;
    INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis, added_by, source)
    SELECT x->>'code', x->>'offeringProgramme', (x->>'level')::int, x->>'basis', who, 'IMPORT'
      FROM jsonb_array_elements(v_valid) x
    ON CONFLICT (course_code, programme_code, level) DO UPDATE SET basis = EXCLUDED.basis;

    -- the prerequisites
    WITH p AS (
        INSERT INTO catalogue.course_prerequisite (course_code, requires_code, added_by)
        SELECT DISTINCT x->>'code', q, who
          FROM jsonb_array_elements(v_valid) x CROSS JOIN LATERAL jsonb_array_elements_text(x->'prerequisites') q
        ON CONFLICT DO NOTHING
        RETURNING 1
    ) SELECT count(*) INTO n_pre FROM p;

    INSERT INTO catalogue.course_import (ref, file_name, rows, courses_created, courses_updated, courses_revived, owner_changes,
                                         offerings_created, offerings_updated, prerequisites, result, imported_by, imported_office)
    VALUES (v_ref, nullif(btrim(coalesce(p_file, '')), ''), (v_sum->>'total')::int, n_new, n_upd, n_rev, n_own, n_bnew, n_bupd, n_pre, v_rows, who, office)
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('committed', true, 'id', v_id, 'ref', v_ref, 'summary', v_sum || jsonb_build_object(
               'coursesCreated', n_new, 'coursesUpdated', n_upd, 'coursesRevived', n_rev, 'ownerChangesMade', n_own,
               'offeringsCreated', n_bnew, 'offeringsUpdated', n_bupd, 'prerequisitesAdded', n_pre), 'rows', v_rows);
END $$;
COMMENT ON FUNCTION catalogue.import_catalogue(jsonb, boolean, text) IS
  'V338: the course catalogue upload — one row per offering, naming the course, its owner faculty/department/programme and the programme that offers it as CORE or ELECTIVE. '
  'Every row is judged against the register first (nothing is created on the register); a commit writes only a file with no invalid row, in one transaction: '
  'one course per code (an archived one brought back), its owner recorded, one binding per programme and level, its prerequisites.';


-- ── 8 · the student's results and transcript read the title each offering keeps ────────────────────────

CREATE OR REPLACE FUNCTION assessment.student_results(p_student uuid)
RETURNS TABLE (session text, semester int, course_code text, title text, units int, entry_type text,
               stage text, published boolean, published_at timestamptz, senate_minute text,
               ca int, exam int, total int, grade text, points numeric, outcome text, lecturer text)
LANGUAGE sql STABLE AS $$
    SELECT r.session, r.semester, c.code, coalesce(o.title, c.title), e.units, e.entry_type,
           coalesce(cf.stage, 'NO_SHEET'), coalesce(cf.stage = 'PUBLISHED', false), cf.published_at, cf.senate_minute,
           CASE WHEN cf.stage = 'PUBLISHED' THEN cf.ca END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN cf.exam END,
           CASE WHEN cf.stage = 'PUBLISHED' AND cf.outcome = 'GRADED' THEN cf.total END,
           -- a published sheet with no score, or an absence, is an F: the candidate did not sit
           CASE WHEN cf.stage = 'PUBLISHED' THEN CASE WHEN cf.outcome = 'GRADED' THEN cf.grade
                                                     WHEN cf.outcome IS NULL OR cf.outcome = 'ABSENT' THEN 'F' END END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN CASE WHEN cf.outcome = 'GRADED' THEN cf.points
                                                     WHEN cf.outcome IS NULL OR cf.outcome = 'ABSENT' THEN 0::numeric END END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN CASE WHEN cf.outcome IS NULL THEN 'ABSENT' ELSE cf.outcome END END,
           CASE WHEN lp.id IS NULL THEN NULL ELSE lp.surname || ', ' || lp.given_names END
      FROM registration.course_registration r
      JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED','APPROVED')
      JOIN catalogue.offering o ON o.id = e.offering_id
      JOIN catalogue.course c ON c.code = o.course_code
      LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
      LEFT JOIN LATERAL assessment.course_final(p_student, o.id) cf ON true
     WHERE r.student_id = p_student AND r.status IN ('APPROVED','LOCKED')
     ORDER BY r.session, r.semester, c.code;
$$;

-- ── 9 · the programme structure upload brings a reset-archived course back ─────────────────────────────

CREATE OR REPLACE FUNCTION catalogue.import_courses_rows(p_programme text, p_rows jsonb, p_curriculum text DEFAULT NULL::text)
RETURNS TABLE(rows integer, courses integer, offers integer, no_dept integer, bad_code integer, skipped integer, first_error text, existing integer)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_prog text; v_dept text; v_code text; v_title text; v_units int; v_level int; v_sem int; v_status text;
        v_kind text; v_basis text; v_lh int; v_ph int; v_curr text; v_owner text;
        n int := 0; nc int := 0; no int := 0; nnd int := 0; nb int := 0; ns int := 0; ne int := 0; v_firsterr text := NULL;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a course upload is made by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the structure is rows: course code, title, units, status, level, semester' USING ERRCODE = '23514';
    END IF;
    v_curr := upper(nullif(btrim(coalesce(p_curriculum, '')), ''));
    IF v_curr IS NOT NULL AND v_curr NOT IN ('CCMAS', 'BMAS') THEN v_curr := NULL; END IF;
    SELECT code, dept_code INTO v_prog, v_dept FROM ref.programme
     WHERE upper(code) = upper(btrim(p_programme)) OR upper(name) = upper(btrim(p_programme)) ORDER BY archived, code LIMIT 1;
    IF v_prog IS NULL THEN RAISE EXCEPTION 'no programme is coded or named %', p_programme USING ERRCODE = '23503'; END IF;
    IF v_dept IS NULL OR NOT EXISTS (SELECT 1 FROM ref.department WHERE code = v_dept) THEN
        RAISE EXCEPTION 'the programme % has no department on the register to own its courses', v_prog USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_code := regexp_replace(upper(btrim(coalesce(r->>'code', r->>'courseCode', r->>'course_code', ''))), '\s+', ' ', 'g');
        IF v_code = '' OR v_code ~* '^course\s*code$' THEN CONTINUE; END IF;
        n := n + 1;
        IF v_code !~ '^[A-Z][A-Z0-9 /-]{2,19}$' THEN nb := nb + 1; CONTINUE; END IF;

        BEGIN
            v_title := nullif(btrim(coalesce(r->>'title', r->>'courseTitle', '')), '');
            IF v_title IS NULL THEN v_title := v_code; END IF;
            v_units := least(coalesce(nullif(regexp_replace(coalesce(r->>'units', ''), '[^0-9]', '', 'g'), '')::int, 0), 12);
            v_level := coalesce(nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int, 100);
            IF v_level NOT IN (100,200,300,400,500,600) THEN v_level := 100; END IF;
            v_sem := coalesce(nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int, 1);
            IF v_sem NOT IN (1,2,3) THEN v_sem := 1; END IF;
            v_lh := nullif(regexp_replace(coalesce(r->>'lh', r->>'LH', ''), '[^0-9]', '', 'g'), '')::int;
            v_ph := nullif(regexp_replace(coalesce(r->>'ph', r->>'PH', ''), '[^0-9]', '', 'g'), '')::int;
            v_status := upper(left(btrim(coalesce(r->>'status', 'C')), 1));
            v_kind := CASE WHEN v_code LIKE 'GST %' OR v_code LIKE 'GST%' THEN 'GST'
                           WHEN v_status = 'G' THEN 'GST'  -- GST/EPS courses carried by status, not a GST code
                           WHEN v_status = 'R' THEN 'Required' WHEN v_status = 'E' THEN 'Elective' ELSE 'Core' END;
            v_basis := CASE WHEN v_kind = 'GST' THEN 'GST' WHEN v_kind = 'Elective' THEN 'Elective' ELSE 'Core' END;

            SELECT dept_code INTO v_owner FROM catalogue.course WHERE code = v_code;
            IF v_owner IS NOT NULL AND v_owner <> v_dept THEN
                -- V332: another department's course, carried by this programme: one course, bound as Borrowed
                -- (or on the basis the row says where it is GST or Elective); its title, units and level are its owner's to set
                v_basis := CASE WHEN v_kind = 'GST' THEN 'GST' WHEN v_kind = 'Elective' THEN 'Elective' ELSE 'Borrowed' END;
                ne := ne + 1;
            ELSE
                INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, lecture_hours, practical_hours, curriculum, state)
                VALUES (v_code, v_title, v_units, v_sem, v_level, v_dept, v_kind, v_lh, v_ph, v_curr, 'LIVE')
                ON CONFLICT (code) DO UPDATE SET title = EXCLUDED.title, units = EXCLUDED.units, semester = EXCLUDED.semester,
                    level = EXCLUDED.level, kind = EXCLUDED.kind, lecture_hours = EXCLUDED.lecture_hours, practical_hours = EXCLUDED.practical_hours,
                    curriculum = coalesce(EXCLUDED.curriculum, catalogue.course.curriculum),
                    state = CASE WHEN catalogue.course.state IN ('BOARD', 'SENATE') OR catalogue.course.reset_batch_id IS NOT NULL THEN 'LIVE' ELSE catalogue.course.state END,
                    ended_on = CASE WHEN catalogue.course.reset_batch_id IS NOT NULL THEN NULL ELSE catalogue.course.ended_on END,
                    reset_batch_id = NULL;
                nc := nc + 1;
            END IF;

            INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis, added_by, source)
            VALUES (v_code, v_prog, v_level, v_basis, v_actor, 'IMPORT')
            ON CONFLICT (course_code, programme_code, level) DO UPDATE SET basis = EXCLUDED.basis;

            no := no + 1;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_firsterr IS NULL THEN v_firsterr := left(v_code || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, nc, no, nnd, nb, ns, v_firsterr, ne;
END $$;

-- ── grants ──
GRANT SELECT, INSERT ON catalogue.course_owner_history, catalogue.course_reset, catalogue.course_reset_item, catalogue.course_import TO app_registration;
GRANT UPDATE ON catalogue.course_reset TO app_registration;
GRANT SELECT, INSERT ON catalogue.course_prerequisite TO app_registration;
GRANT SELECT ON catalogue.course_owner_history, catalogue.course_reset, catalogue.course_reset_item, catalogue.course_import, catalogue.course_prerequisite TO app_auditor, app_results, app_student;

COMMIT;
