-- ═══════════════════════════════════════
-- V396 — a BSU- course and its MOAU- twin are taught once
--
--   The University keeps two codes for one course: students in 300 level and above carry the BSU- code, those in 100 and
--   200 level the MOAU- code — the same course, taught by the same lecturer in the same room (bf288fad keeps both out of
--   the duplicates). Each code had its own class, so the lecturer was allocated twice, the timetable was entered twice
--   (and a student of one code saw only what was entered for theirs) and the register was taken twice.
--
--   catalogue.course_twin links the pair: proposed from the rule the duplicates check uses (a BSU- and a MOAU- course of
--   one department with the same level, semester, curriculum and title — catalogue.twin_suggestions), confirmed by a person
--   (catalogue.link_twin), undone with a reason (catalogue.unlink_twin). A class of one code and the class of its twin in
--   the same session, semester and stream are one family (catalogue.offering_family), and:
--     · allocation — catalogue.allocate_offering sets the lecturer and second examiner on both and opens both score sheets;
--       a co-lecturer added to or removed from one is added to or removed from the other; a class opened for the twin later
--       takes the allocation already made; linking aligns the allocations of sessions still running where only one side
--       is allocated. The teaching load counts the pair once.
--     · timetable — a slot entered on either class is the slot of both: registration.student_timetable reads the family's
--       slots, so a student of either code sees it once.
--     · attendance — registration.mark_attendance marks the family's students on one register, each against their own
--       class, so each code keeps its own attendance.
--   Registration, score sheets, results and transcripts stay per code; nothing is merged and no history moves.
--   Not in this migration: the examination timetable and the CBT examination of a pair (each code keeps its own).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V396: BSU-/MOAU- twin courses taught once', true);

-- ── 1 · the link ───────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS catalogue.course_twin (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    bsu_code      text NOT NULL REFERENCES catalogue.course(code) ON UPDATE CASCADE ON DELETE CASCADE,
    moau_code     text NOT NULL REFERENCES catalogue.course(code) ON UPDATE CASCADE ON DELETE CASCADE,
    linked_by     uuid NULL,
    linked_office text NULL,
    linked_at     timestamptz NOT NULL DEFAULT now(),
    unlinked_at   timestamptz NULL,
    unlinked_by   uuid NULL,
    unlink_reason text NULL,
    CONSTRAINT ck_twin_codes CHECK (bsu_code ~ '^BSU-' AND moau_code ~ '^MOAU-'),
    CONSTRAINT ck_twin_unlinked CHECK (unlinked_at IS NULL OR btrim(coalesce(unlink_reason, '')) <> '')
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_course_twin_bsu ON catalogue.course_twin (bsu_code) WHERE unlinked_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_course_twin_moau ON catalogue.course_twin (moau_code) WHERE unlinked_at IS NULL;
COMMENT ON TABLE catalogue.course_twin IS
  'V396: a BSU- course and its MOAU- twin — one course carried under two codes (300 level and above BSU-, 100 and 200 level MOAU-) — linked so the class is allocated, timetabled and registered once; registration, score sheets and results stay per code. An unlinked pair keeps its row, with when, who and why.';
SELECT audit.attach('catalogue.course_twin') WHERE NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_audit_catalogue_course_twin');

/* the pair is one course: the same department, level and semester, neither ended */
CREATE OR REPLACE FUNCTION catalogue.course_twin_guard()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE b catalogue.course; m catalogue.course;
BEGIN
    IF NEW.unlinked_at IS NOT NULL THEN RETURN NEW; END IF;
    SELECT * INTO b FROM catalogue.course WHERE code = NEW.bsu_code;
    SELECT * INTO m FROM catalogue.course WHERE code = NEW.moau_code;
    IF b.dept_code IS DISTINCT FROM m.dept_code OR b.level IS DISTINCT FROM m.level OR b.semester IS DISTINCT FROM m.semester THEN
        RAISE EXCEPTION 'COURSE_TWIN_MISMATCH: % and % are not one course: twins share the department, the level and the semester', NEW.bsu_code, NEW.moau_code
            USING ERRCODE = '23514';
    END IF;
    IF b.state = 'ENDED' OR m.state = 'ENDED' THEN
        RAISE EXCEPTION 'COURSE_TWIN_ENDED: an ended course is not linked; restore it first' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS trg_course_twin_guard ON catalogue.course_twin;
CREATE TRIGGER trg_course_twin_guard BEFORE INSERT OR UPDATE ON catalogue.course_twin FOR EACH ROW EXECUTE FUNCTION catalogue.course_twin_guard();

/* the code a course is twinned with, while the link stands */
CREATE OR REPLACE FUNCTION catalogue.twin_code(p_code text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN t.bsu_code = p_code THEN t.moau_code ELSE t.bsu_code END
      FROM catalogue.course_twin t
     WHERE t.unlinked_at IS NULL AND p_code IN (t.bsu_code, t.moau_code)
     LIMIT 1
$fn$;

/* a class and the class of its twin in the same session, semester and stream: the class itself first */
CREATE OR REPLACE FUNCTION catalogue.offering_family(p_offering uuid)
RETURNS SETOF uuid LANGUAGE sql STABLE AS $fn$
    SELECT p_offering
    UNION ALL
    SELECT o2.id
      FROM catalogue.offering o
      JOIN catalogue.offering o2 ON o2.course_code = catalogue.twin_code(o.course_code)
                                AND o2.session = o.session AND o2.semester = o.semester AND o2.stream = o.stream
     WHERE o.id = p_offering
$fn$;
COMMENT ON FUNCTION catalogue.offering_family(uuid) IS
  'V396: the class and its twin''s class (a linked BSU-/MOAU- pair) in the same session, semester and stream — the classes taught as one.';

/* the pairs a department could link: a BSU- and a MOAU- course with the same level, semester, curriculum and title, the rule
   of the duplicates check (bf288fad), neither ended nor already linked */
CREATE OR REPLACE FUNCTION catalogue.twin_suggestions(p_dept text)
RETURNS TABLE(bsu_code text, bsu_title text, moau_code text, moau_title text, level int, semester int)
LANGUAGE sql STABLE AS $fn$
    WITH c AS (
        SELECT x.code, x.title, x.level, x.semester, coalesce(x.curriculum, '') AS curr,
               lower(regexp_replace(btrim(x.title), '\s+', ' ', 'g')) AS norm
          FROM catalogue.course x
         WHERE x.dept_code = p_dept AND x.state <> 'ENDED'
           AND NOT EXISTS (SELECT 1 FROM catalogue.course_twin t WHERE t.unlinked_at IS NULL AND x.code IN (t.bsu_code, t.moau_code)))
    SELECT b.code, b.title, m.code, m.title, b.level, b.semester
      FROM c b JOIN c m ON m.code ~ '^MOAU-' AND m.level = b.level AND m.semester = b.semester AND m.curr = b.curr AND m.norm = b.norm
     WHERE b.code ~ '^BSU-'
     ORDER BY b.level, b.semester, b.code
$fn$;

/* a score sheet opens with the allocation when the examination session of the class's stream is open and its sheets
   released — the rule catalogue.allocate_offering keeps, written once for each class of a pair */
CREATE OR REPLACE FUNCTION catalogue.open_sheet_if_due(p_offering uuid)
RETURNS void LANGUAGE sql AS $fn$
    INSERT INTO assessment.score_sheet (id, offering_id, exam_session_id, due_on)
    SELECT gen_random_uuid(), o.id, es.id, es.sheets_due
      FROM catalogue.offering o
      JOIN assessment.exam_session es ON es.session = o.session AND es.semester = o.semester AND es.state = 'OPEN'
                                     AND es.sheets_released_at IS NOT NULL AND es.stream = o.stream
     WHERE o.id = p_offering AND o.lecturer_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh WHERE sh.offering_id = o.id)
$fn$;

/* the classes of a pair in sessions still running: where one is allocated and the other is not, the other takes the
   allocation; the co-lecturers of either are the co-lecturers of both. A pair allocated to two different lecturers is left
   as it is (the next allocation of either sets both). */
CREATE OR REPLACE FUNCTION catalogue.align_twin_classes(p_bsu text, p_moau text)
RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE r record; n int := 0;
BEGIN
    FOR r IN SELECT a.id AS a_id, b.id AS b_id, a.lecturer_id AS a_lec, b.lecturer_id AS b_lec
               FROM catalogue.offering a
               JOIN catalogue.offering b ON b.course_code = p_moau AND b.session = a.session AND b.semester = a.semester AND b.stream = a.stream
               JOIN policy.academic_session s ON s.name = a.session AND s.state NOT IN ('CLOSED', 'ARCHIVED', 'CANCELLED')
              WHERE a.course_code = p_bsu
    LOOP
        IF r.a_lec IS NOT NULL AND r.b_lec IS NULL THEN
            UPDATE catalogue.offering t SET lecturer_id = f.lecturer_id, second_examiner_id = f.second_examiner_id, allocated_on = f.allocated_on
              FROM catalogue.offering f WHERE f.id = r.a_id AND t.id = r.b_id;
            PERFORM catalogue.open_sheet_if_due(r.b_id);
            n := n + 1;
        ELSIF r.b_lec IS NOT NULL AND r.a_lec IS NULL THEN
            UPDATE catalogue.offering t SET lecturer_id = f.lecturer_id, second_examiner_id = f.second_examiner_id, allocated_on = f.allocated_on
              FROM catalogue.offering f WHERE f.id = r.b_id AND t.id = r.a_id;
            PERFORM catalogue.open_sheet_if_due(r.a_id);
            n := n + 1;
        END IF;
        INSERT INTO catalogue.offering_teacher (offering_id, lecturer_id, added_by, programme_code)
        SELECT x.other, t.lecturer_id, t.added_by, t.programme_code
          FROM (VALUES (r.a_id, r.b_id), (r.b_id, r.a_id)) AS x(src, other)
          JOIN catalogue.offering_teacher t ON t.offering_id = x.src
          JOIN catalogue.offering o ON o.id = x.other
         WHERE o.lecturer_id IS DISTINCT FROM t.lecturer_id
        ON CONFLICT (offering_id, lecturer_id) DO NOTHING;
    END LOOP;
    RETURN n;
END $fn$;

/* a person links a pair: the classes of sessions still running are aligned at once */
CREATE OR REPLACE FUNCTION catalogue.link_twin(p_bsu text, p_moau text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), ''); v uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'COURSE_TWIN_ACTOR: a pair is linked by a person' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM catalogue.course_twin t WHERE t.unlinked_at IS NULL AND (t.bsu_code = upper(btrim(p_bsu)) OR t.moau_code = upper(btrim(p_moau)))) THEN
        RAISE EXCEPTION 'COURSE_TWIN_TAKEN: % or % is already linked to another course; unlink it first', p_bsu, p_moau USING ERRCODE = '23514';
    END IF;
    INSERT INTO catalogue.course_twin (bsu_code, moau_code, linked_by, linked_office)
    VALUES (upper(btrim(p_bsu)), upper(btrim(p_moau)), who, office) RETURNING id INTO v;
    PERFORM catalogue.align_twin_classes(upper(btrim(p_bsu)), upper(btrim(p_moau)));
    RETURN v;
END $fn$;

/* undone with a reason: each code keeps the allocation, slots and attendance it has; from then each is its own class again */
CREATE OR REPLACE FUNCTION catalogue.unlink_twin(p_id uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'COURSE_TWIN_ACTOR: a pair is unlinked by a person' USING ERRCODE = '23514'; END IF;
    IF btrim(coalesce(p_reason, '')) = '' THEN RAISE EXCEPTION 'COURSE_TWIN_REASON: say why the pair is unlinked' USING ERRCODE = '23514'; END IF;
    UPDATE catalogue.course_twin SET unlinked_at = now(), unlinked_by = who, unlink_reason = btrim(p_reason)
     WHERE id = p_id AND unlinked_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'COURSE_TWIN_NONE: no such linked pair' USING ERRCODE = '23514'; END IF;
END $fn$;

-- ── 2 · allocation follows the pair ─────────────────────────────────────────────────────────────────────────────
/* a co-lecturer added to or removed from one class of a pair is added to or removed from the other */
CREATE OR REPLACE FUNCTION catalogue.offering_teacher_twin()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO catalogue.offering_teacher (offering_id, lecturer_id, added_by, programme_code)
        SELECT f, NEW.lecturer_id, NEW.added_by, NEW.programme_code
          FROM catalogue.offering_family(NEW.offering_id) f
          JOIN catalogue.offering o ON o.id = f
         WHERE f <> NEW.offering_id AND o.lecturer_id IS DISTINCT FROM NEW.lecturer_id
        ON CONFLICT (offering_id, lecturer_id) DO NOTHING;
        RETURN NEW;
    END IF;
    DELETE FROM catalogue.offering_teacher t
     WHERE t.lecturer_id = OLD.lecturer_id AND t.offering_id <> OLD.offering_id
       AND t.offering_id IN (SELECT catalogue.offering_family(OLD.offering_id));
    RETURN OLD;
END $fn$;
DROP TRIGGER IF EXISTS trg_offering_teacher_twin ON catalogue.offering_teacher;
CREATE TRIGGER trg_offering_teacher_twin AFTER INSERT OR DELETE ON catalogue.offering_teacher
    FOR EACH ROW EXECUTE FUNCTION catalogue.offering_teacher_twin();

/* a class opened for a course whose twin's class is already allocated takes that allocation */
CREATE OR REPLACE FUNCTION catalogue.offering_twin_allocation()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE src catalogue.offering;
BEGIN
    IF NEW.lecturer_id IS NOT NULL THEN RETURN NULL; END IF;
    SELECT o.* INTO src FROM catalogue.offering_family(NEW.id) f JOIN catalogue.offering o ON o.id = f
     WHERE f <> NEW.id AND o.lecturer_id IS NOT NULL LIMIT 1;
    IF src.id IS NULL THEN RETURN NULL; END IF;
    UPDATE catalogue.offering SET lecturer_id = src.lecturer_id, second_examiner_id = src.second_examiner_id, allocated_on = src.allocated_on
     WHERE id = NEW.id;
    INSERT INTO catalogue.offering_teacher (offering_id, lecturer_id, added_by, programme_code)
    SELECT NEW.id, t.lecturer_id, t.added_by, t.programme_code FROM catalogue.offering_teacher t WHERE t.offering_id = src.id
    ON CONFLICT (offering_id, lecturer_id) DO NOTHING;
    PERFORM catalogue.open_sheet_if_due(NEW.id);
    RETURN NULL;
END $fn$;
DROP TRIGGER IF EXISTS trg_offering_twin_allocation ON catalogue.offering;
CREATE TRIGGER trg_offering_twin_allocation AFTER INSERT ON catalogue.offering
    FOR EACH ROW EXECUTE FUNCTION catalogue.offering_twin_allocation();

-- ── 3 · the restated functions (from their definitions after V395) ──────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.allocate_offering(p_offering uuid, p_lecturer uuid, p_second uuid, p_overload_ok boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    o        catalogue.offering;
    who      uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_units  int;
    v_load   int;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a teaching allocation is made by a person' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO o FROM catalogue.offering WHERE id = p_offering;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no such offering' USING ERRCODE = '23503';
    END IF;
    IF p_lecturer IS NULL THEN
        RAISE EXCEPTION 'an allocation names the lecturer who teaches it' USING ERRCODE = '23514';
    END IF;
    IF p_second IS NOT NULL AND p_second = p_lecturer THEN
        RAISE EXCEPTION 'the second examiner cannot be the lecturer' USING ERRCODE = '23514',
            HINT = 'The person who enters the marks may not be the person who verifies them.';
    END IF;

    SELECT c.units INTO v_units FROM catalogue.course c WHERE c.code = o.course_code;
    SELECT coalesce(sum(c2.units), 0) INTO v_load
      FROM catalogue.offering o2 JOIN catalogue.course c2 ON c2.code = o2.course_code
     WHERE o2.lecturer_id = p_lecturer AND o2.session = o.session AND o2.semester = o.semester AND o2.stream = o.stream
       -- V396: this class and its twin's are one class, and a pair the lecturer already teaches is counted once
       AND o2.id NOT IN (SELECT catalogue.offering_family(p_offering))
       AND NOT EXISTS (SELECT 1 FROM catalogue.offering_family(o2.id) f JOIN catalogue.offering o3 ON o3.id = f
                        WHERE f <> o2.id AND f < o2.id AND o3.lecturer_id = p_lecturer);
    IF v_load + coalesce(v_units, 0) > 12 AND NOT p_overload_ok THEN
        RAISE EXCEPTION 'this assignment puts the lecturer at % units, over the approved maximum of 12', v_load + coalesce(v_units, 0)
            USING ERRCODE = '23514', HINT = 'Assign it as an overload (reported to the Dean) if the department intends it.';
    END IF;

    -- V396: the class and its twin's class (a linked BSU-/MOAU- pair) are allocated together
    UPDATE catalogue.offering
       SET lecturer_id = p_lecturer, second_examiner_id = p_second, allocated_on = current_date
     WHERE id IN (SELECT catalogue.offering_family(p_offering));

    -- assigning the lecturer opens the score sheet, if the examination session of the class's stream is open, its sheets
    -- released, and none exists yet (V381) — for each class of a pair (V396)
    PERFORM catalogue.open_sheet_if_due(f) FROM catalogue.offering_family(p_offering) f;
END $function$;

CREATE OR REPLACE FUNCTION registration.student_timetable(p_student uuid, p_session text, p_semester integer)
 RETURNS TABLE(weekday integer, starts_at time without time zone, ends_at time without time zone, course_code text, title text, kind text, venue text, lecturer text, carryover boolean)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT DISTINCT s.weekday, s.starts_at, s.ends_at, c.code, c.title, s.kind, s.venue, p.surname || ', ' || p.given_names, e.entry_type = 'CARRYOVER'
      FROM registration.course_registration r
      JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED','APPROVED')
      JOIN catalogue.offering o ON o.id = e.offering_id
      JOIN catalogue.course c ON c.code = o.course_code
      -- V396: a slot entered on either class of a linked pair is the slot of both
      JOIN catalogue.class_slot s ON s.offering_id IN (SELECT catalogue.offering_family(o.id)) AND s.ended_at IS NULL
      LEFT JOIN iam.person p ON p.id = o.lecturer_id
     WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester
     ORDER BY s.weekday, s.starts_at, c.code;
$function$;

CREATE OR REPLACE FUNCTION registration.mark_attendance(p_offering uuid, p_held_on date, p_present uuid[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int := 0; r record; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'attendance is recorded by a person' USING ERRCODE = '23514'; END IF;
    -- V396: the students of a linked pair's two classes on one register, each marked against their own class
    FOR r IN SELECT e.offering_id, cr.student_id FROM registration.entry e
              JOIN registration.course_registration cr ON cr.id = e.registration_id AND cr.status IN ('APPROVED','LOCKED')
             WHERE e.offering_id IN (SELECT catalogue.offering_family(p_offering)) AND e.status IN ('REGISTERED','APPROVED')
    LOOP
        INSERT INTO registration.attendance (offering_id, held_on, student_id, present, recorded_by)
        VALUES (r.offering_id, p_held_on, r.student_id, r.student_id = ANY(p_present), who)
        ON CONFLICT (offering_id, held_on, student_id) DO UPDATE SET present = EXCLUDED.present, recorded_by = EXCLUDED.recorded_by, recorded_at = now();
        n := n + 1;
    END LOOP;
    RETURN n;
END $function$;

COMMENT ON FUNCTION catalogue.allocate_offering(uuid, uuid, uuid, boolean) IS
  'A teaching allocation (lecturer and second examiner) of a class, within the 12-unit load unless an overload is meant; the class of a linked BSU-/MOAU- twin is allocated with it and the pair counted once (V396).';
COMMENT ON FUNCTION registration.student_timetable(uuid, text, integer) IS
  'A student''s week: the slots of the classes they are registered on — for a class of a linked twin pair, the slots entered on either class (V396).';
COMMENT ON FUNCTION registration.mark_attendance(uuid, date, uuid[]) IS
  'A class''s register for one day over its class list — for a linked twin pair, both classes'' students, each against their own class (V396).';

COMMIT;
