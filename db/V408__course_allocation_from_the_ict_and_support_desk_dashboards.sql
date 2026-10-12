-- ═══════════════════════════════════════
-- V408 — course allocation from the Director of ICT's and the ICT Support Desk's dashboards
--
--   The University allocates a class to its lecturers on one engine: catalogue.allocate_offering for the lead (V041, V396),
--   catalogue.offering_teacher for a co-lecturer (V158), the bulk import (V321). The Director of ICT and the support desk
--   now work that same engine from their own dashboards; nothing here is a second allocation system:
--
--     · the desk's vocabulary (helpdesk.support_capabilities) gains four capabilities the Head grants with a posting —
--       VIEW_ALLOCATIONS, ALLOCATE_COURSES, REMOVE_ALLOCATIONS and BULK_ALLOCATE — so a CPO allocates only within the
--       faculty or department their posting names, and only when the Head has said so (helpdesk.agent_scope_for);
--     · every allocation, by any desk or import, is on catalogue.allocation_event — who, what, from whom to whom, why, from
--       which desk, on which ticket — written by triggers on the class and its co-lecturers, so no path escapes it; the
--       allocations already on the register are entered once, as on record before the history was kept;
--     · catalogue.allocation_checks says, before anything is written, whether a lecturer may take a class and why not —
--       the course live, the class offered, the session, the lecturer active and teaching, the same allocation twice, the
--       load, a timetable clash where the timetable has slots, a score sheet already under way;
--     · catalogue.allocation_conflicts lists what is wrong with a semester's allocations as they stand;
--     · helpdesk.note_allocation puts an allocation made on a ticket on the ticket's timeline.
--
--   Nothing about fees, results or registration is touched: an allocation opens the score sheet only as V041 always did.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V408: course allocation from the ICT and support desk dashboards', true);

-- ── 1 · the support desk's vocabulary: the course allocation capabilities a posting may carry ─────────────────────
CREATE OR REPLACE FUNCTION helpdesk.support_capabilities()
RETURNS text[]
LANGUAGE sql IMMUTABLE AS $$
    SELECT ARRAY['VIEW_STUDENT', 'EDIT_CONTACT', 'EDIT_PERSONAL', 'EDIT_FAMILY', 'EDIT_PHOTO', 'REQUEST_CHANGE',
                 'VIEW_PAYMENTS', 'VIEW_DOCUMENTS', 'MANAGE_REGISTRATION', 'EXPORT_STUDENTS',
                 'OVERRIDE_REGISTRATION', 'RESET_PASSWORD', 'INVESTIGATE_PAYMENT', 'VERIFY_PAYMENT', 'SYNC_ENTITLEMENT',
                 'REGENERATE_RECEIPT', 'CREATE_TICKET', 'VIEW_SUPPORT_AUDIT',
                 'VIEW_ALLOCATIONS', 'ALLOCATE_COURSES', 'REMOVE_ALLOCATIONS', 'BULK_ALLOCATE']
$$;
COMMENT ON FUNCTION helpdesk.support_capabilities() IS
  'V334, V346, V408: what a support posting may carry. V408 adds course allocation — viewing the allocations, allocating and reassigning a lecturer, removing a co-lecturer, the bulk import — each within the posting''s scope. Results, refunds, fees, amounts, matriculation and admission decisions are never among them.';

-- ── 2 · the history of every allocation ───────────────────────────────────────────────────────────────────────────
CREATE TABLE catalogue.allocation_event (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    offering_id          uuid NOT NULL REFERENCES catalogue.offering(id) ON DELETE CASCADE,
    course_code          text NOT NULL,
    session              text NOT NULL,
    semester             int  NOT NULL,
    action               text NOT NULL,
    role                 text NOT NULL,
    lecturer_id          uuid NULL REFERENCES iam.person(id),
    previous_lecturer_id uuid NULL REFERENCES iam.person(id),
    reason               text NULL,
    ticket_id            uuid NULL REFERENCES helpdesk.ticket(id) ON DELETE SET NULL,
    source               text NOT NULL,
    actor_id             uuid NULL,
    actor_office         text NULL,
    at                   timestamptz NOT NULL DEFAULT clock_timestamp(),   -- several acts of one transaction keep their order
    CONSTRAINT ck_alloc_event_action CHECK (action IN ('ALLOCATED', 'REASSIGNED', 'UNALLOCATED', 'CO_LECTURER_ADDED', 'CO_LECTURER_REMOVED',
                                                       'SECOND_EXAMINER_SET', 'SECOND_EXAMINER_REMOVED', 'ON_RECORD')),
    CONSTRAINT ck_alloc_event_role CHECK (role IN ('LECTURER', 'CO_LECTURER', 'SECOND_EXAMINER')),
    CONSTRAINT ck_alloc_event_source CHECK (source IN ('DESK', 'IMPORT', 'SYSTEM'))
);
CREATE INDEX ix_alloc_event_offering ON catalogue.allocation_event (offering_id, at DESC);
CREATE INDEX ix_alloc_event_session ON catalogue.allocation_event (session, semester, at DESC);
CREATE INDEX ix_alloc_event_lecturer ON catalogue.allocation_event (lecturer_id) WHERE lecturer_id IS NOT NULL;
CREATE INDEX ix_alloc_event_previous ON catalogue.allocation_event (previous_lecturer_id) WHERE previous_lecturer_id IS NOT NULL;
CREATE INDEX ix_alloc_event_ticket ON catalogue.allocation_event (ticket_id) WHERE ticket_id IS NOT NULL;
SELECT audit.attach('catalogue.allocation_event');
COMMENT ON TABLE catalogue.allocation_event IS
  'V408: every allocation of a class — lead, co-lecturer, second examiner — as it happened: the action, the person and whom they replaced, the reason the request gave, the ticket it was made on, the desk or import it came from and who made it. Written by triggers on catalogue.offering and catalogue.offering_teacher, so every desk and the import are on it.';

/* the act being recorded: the request's reason, the ticket the desk named (moaum.allocation_ticket), and whether it came
   from the bulk import (moaum.allocation_source = IMPORT); a write with no actor is the system's */
CREATE OR REPLACE FUNCTION catalogue.allocation_event_add(o catalogue.offering, p_action text, p_role text, p_lecturer uuid, p_previous uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid; v_ticket uuid;
BEGIN
    BEGIN v_actor := nullif(current_setting('moaum.actor_id', true), '')::uuid; EXCEPTION WHEN others THEN v_actor := NULL; END;
    BEGIN v_ticket := nullif(current_setting('moaum.allocation_ticket', true), '')::uuid; EXCEPTION WHEN others THEN v_ticket := NULL; END;
    IF v_ticket IS NOT NULL AND NOT EXISTS (SELECT 1 FROM helpdesk.ticket WHERE id = v_ticket) THEN v_ticket := NULL; END IF;
    INSERT INTO catalogue.allocation_event (offering_id, course_code, session, semester, action, role, lecturer_id, previous_lecturer_id,
                                            reason, ticket_id, source, actor_id, actor_office)
    VALUES (o.id, o.course_code, o.session, o.semester, p_action, p_role, p_lecturer, p_previous,
            nullif(btrim(coalesce(current_setting('moaum.reason', true), '')), ''), v_ticket,
            CASE WHEN coalesce(current_setting('moaum.allocation_source', true), '') = 'IMPORT' THEN 'IMPORT'
                 WHEN v_actor IS NULL OR v_actor = '00000000-0000-0000-0000-000000000000'::uuid THEN 'SYSTEM' ELSE 'DESK' END,
            v_actor, nullif(current_setting('moaum.actor_office', true), ''));
END $$;

CREATE OR REPLACE FUNCTION catalogue.offering_allocation_history()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.lecturer_id IS NOT NULL THEN PERFORM catalogue.allocation_event_add(NEW, 'ALLOCATED', 'LECTURER', NEW.lecturer_id, NULL); END IF;
        IF NEW.second_examiner_id IS NOT NULL THEN PERFORM catalogue.allocation_event_add(NEW, 'SECOND_EXAMINER_SET', 'SECOND_EXAMINER', NEW.second_examiner_id, NULL); END IF;
        RETURN NEW;
    END IF;
    IF NEW.lecturer_id IS DISTINCT FROM OLD.lecturer_id THEN
        PERFORM catalogue.allocation_event_add(NEW,
            CASE WHEN OLD.lecturer_id IS NULL THEN 'ALLOCATED' WHEN NEW.lecturer_id IS NULL THEN 'UNALLOCATED' ELSE 'REASSIGNED' END,
            'LECTURER', NEW.lecturer_id, OLD.lecturer_id);
    END IF;
    IF NEW.second_examiner_id IS DISTINCT FROM OLD.second_examiner_id THEN
        PERFORM catalogue.allocation_event_add(NEW, CASE WHEN NEW.second_examiner_id IS NULL THEN 'SECOND_EXAMINER_REMOVED' ELSE 'SECOND_EXAMINER_SET' END,
            'SECOND_EXAMINER', NEW.second_examiner_id, OLD.second_examiner_id);
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER tr_offering_allocation_history AFTER INSERT OR UPDATE OF lecturer_id, second_examiner_id ON catalogue.offering
    FOR EACH ROW EXECUTE FUNCTION catalogue.offering_allocation_history();

CREATE OR REPLACE FUNCTION catalogue.teacher_allocation_history()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE o catalogue.offering;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT * INTO o FROM catalogue.offering WHERE id = NEW.offering_id;
        IF FOUND THEN PERFORM catalogue.allocation_event_add(o, 'CO_LECTURER_ADDED', 'CO_LECTURER', NEW.lecturer_id, NULL); END IF;
        RETURN NEW;
    END IF;
    -- a co-lecturer taken off: when the class itself is being removed (a reset, a test's cleanup) there is nothing to record against
    SELECT * INTO o FROM catalogue.offering WHERE id = OLD.offering_id;
    IF FOUND THEN PERFORM catalogue.allocation_event_add(o, 'CO_LECTURER_REMOVED', 'CO_LECTURER', NULL, OLD.lecturer_id); END IF;
    RETURN OLD;
END $$;
CREATE TRIGGER tr_teacher_allocation_history AFTER INSERT OR DELETE ON catalogue.offering_teacher
    FOR EACH ROW EXECUTE FUNCTION catalogue.teacher_allocation_history();

-- the allocations already on the register, entered once as on record before the history was kept
INSERT INTO catalogue.allocation_event (offering_id, course_code, session, semester, action, role, lecturer_id, reason, source, at)
SELECT o.id, o.course_code, o.session, o.semester, 'ON_RECORD', 'LECTURER', o.lecturer_id, 'On the register before the allocation history was kept (V408)', 'SYSTEM',
       coalesce(o.allocated_on::timestamptz, now())
  FROM catalogue.offering o WHERE o.lecturer_id IS NOT NULL;
INSERT INTO catalogue.allocation_event (offering_id, course_code, session, semester, action, role, lecturer_id, reason, source, actor_id, at)
SELECT o.id, o.course_code, o.session, o.semester, 'ON_RECORD', 'CO_LECTURER', t.lecturer_id, 'On the register before the allocation history was kept (V408)', 'SYSTEM',
       t.added_by, t.added_at
  FROM catalogue.offering_teacher t JOIN catalogue.offering o ON o.id = t.offering_id;
INSERT INTO catalogue.allocation_event (offering_id, course_code, session, semester, action, role, lecturer_id, reason, source, at)
SELECT o.id, o.course_code, o.session, o.semester, 'ON_RECORD', 'SECOND_EXAMINER', o.second_examiner_id, 'On the register before the allocation history was kept (V408)', 'SYSTEM',
       coalesce(o.allocated_on::timestamptz, now())
  FROM catalogue.offering o WHERE o.second_examiner_id IS NOT NULL;

-- ── 3 · whether a person may take a class, said before anything is written ───────────────────────────────────────
/* the people who teach: a live lecturer or Head of Department grant (the same test as the allocation desk's lecturer list) */
CREATE OR REPLACE FUNCTION catalogue.teaching_departments(p_person uuid)
RETURNS text[]
LANGUAGE sql STABLE AS $$
    SELECT coalesce(array_agg(DISTINCT upper(a.scope_id) ORDER BY upper(a.scope_id)), '{}'::text[])
      FROM iam.office_assignment a
     WHERE a.person_id = p_person AND a.office_code IN ('lecturer', 'hod') AND a.scope_kind = 'department'
       AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
$$;
COMMENT ON FUNCTION catalogue.teaching_departments(uuid) IS 'V408: the departments a person teaches in now — their live lecturer and Head of Department grants; empty for a person who holds no teaching office.';

/* the units a person leads in a session and semester, a linked twin pair counted once (as catalogue.allocate_offering counts) */
CREATE OR REPLACE FUNCTION catalogue.teaching_load(p_person uuid, p_session text, p_semester int)
RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT coalesce(sum(c.units), 0)::int
      FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
     WHERE o.lecturer_id = p_person AND o.session = p_session AND o.semester = p_semester AND o.stream IN ('REGULAR', 'PG')
       AND NOT EXISTS (SELECT 1 FROM catalogue.offering_family(o.id) f JOIN catalogue.offering o3 ON o3.id = f
                        WHERE f <> o.id AND f < o.id AND o3.lecturer_id = p_person)
$$;

/* a timetable clash: a slot of this class (or its twin's) overlapping a slot of another class the person leads or co-teaches
   in the same session and semester. Without slots there is no clash to find, and none is invented. */
CREATE OR REPLACE FUNCTION catalogue.timetable_clashes(p_offering uuid, p_person uuid)
RETURNS text[]
LANGUAGE sql STABLE AS $$
    SELECT coalesce(array_agg(DISTINCT o2.course_code || ' on ' || (ARRAY['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'])[s2.weekday]
                              || ' ' || to_char(s2.starts_at, 'HH24:MI') || '–' || to_char(s2.ends_at, 'HH24:MI')), '{}'::text[])
      FROM catalogue.offering o
      JOIN catalogue.class_slot s ON s.offering_id IN (SELECT catalogue.offering_family(o.id)) AND s.ended_at IS NULL
      JOIN catalogue.offering o2 ON o2.session = o.session AND o2.semester = o.semester AND o2.id NOT IN (SELECT catalogue.offering_family(o.id))
                                AND (o2.lecturer_id = p_person OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o2.id AND t.lecturer_id = p_person))
      JOIN catalogue.class_slot s2 ON s2.offering_id = o2.id AND s2.ended_at IS NULL
                                  AND s2.weekday = s.weekday AND s2.starts_at < s.ends_at AND s.starts_at < s2.ends_at
     WHERE o.id = p_offering
$$;

/**
 * Whether p_person may take the class in p_role (LECTURER, CO_LECTURER), each check with its words: OK, WARNING (allowed,
 * said — an overload is allowed only when meant) or ERROR (refused, with the reason). Writes nothing.
 */
CREATE OR REPLACE FUNCTION catalogue.allocation_checks(p_offering uuid, p_person uuid, p_role text DEFAULT 'LECTURER')
RETURNS TABLE (code text, level text, words text)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE o catalogue.offering; c catalogue.course; p iam.person; v_name text; v_course text; v_depts text[]; v_load int; v_units int;
        v_state text; v_progs int; v_stage text; v_clash text[]; v_course_dept text; v_role text := upper(coalesce(p_role, 'LECTURER'));
BEGIN
    SELECT * INTO o FROM catalogue.offering WHERE id = p_offering;
    IF NOT FOUND THEN
        code := 'COURSE'; level := 'ERROR'; words := 'Course not found. Please create or upload the course through Course Management before allocation.'; RETURN NEXT; RETURN;
    END IF;
    SELECT * INTO c FROM catalogue.course WHERE catalogue.course.code = o.course_code;
    v_course := o.course_code || coalesce(' — ' || c.title, '');
    v_units := coalesce(c.units, o.units, 0);
    v_course_dept := c.dept_code;

    -- the course and its class
    IF c.code IS NULL THEN
        code := 'COURSE'; level := 'ERROR'; words := 'Course not found. Please create or upload the course through Course Management before allocation.'; RETURN NEXT;
    ELSIF c.state = 'ENDED' THEN
        code := 'COURSE'; level := 'ERROR'; words := v_course || ' has ended on the catalogue; restore it on Course Management before allocating it.'; RETURN NEXT;
    ELSE
        code := 'COURSE'; level := 'OK'; words := v_course || ' is on the catalogue (' || v_units || ' units).'; RETURN NEXT;
    END IF;
    IF o.stream = 'CCE' THEN
        code := 'OFFERED'; level := 'ERROR'; words := 'This is a class of the Centre for Continuing Education; the Centre allocates its lecturer.'; RETURN NEXT;
    ELSE
        SELECT count(DISTINCT co.programme_code) INTO v_progs FROM catalogue.course_offer co WHERE co.course_code = o.course_code;
        code := 'OFFERED'; level := CASE WHEN v_progs > 0 THEN 'OK' ELSE 'WARNING' END;
        words := CASE WHEN v_progs > 0 THEN 'Offered in ' || o.session || ', ' || CASE o.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END
                                            || ' semester, to ' || v_progs || ' programme' || CASE WHEN v_progs = 1 THEN '' ELSE 's' END || '.'
                      ELSE 'The class is open in ' || o.session || ', but no programme''s structure carries the course, so no student registers for it.' END;
        RETURN NEXT;
    END IF;
    SELECT s.state INTO v_state FROM policy.academic_session s WHERE s.name = o.session;
    code := 'SESSION';
    IF v_state IS NULL THEN level := 'ERROR'; words := o.session || ' is not on the academic calendar.';
    ELSIF v_state IN ('COMPLETED', 'ARCHIVED', 'CANCELLED') THEN level := 'WARNING'; words := o.session || ' is ' || lower(v_state) || '; an allocation now changes the record of a past session.';
    ELSE level := 'OK'; words := o.session || ' is ' || lower(v_state) || '.';
    END IF;
    RETURN NEXT;

    -- the person
    SELECT * INTO p FROM iam.person WHERE id = p_person;
    IF NOT FOUND THEN
        code := 'LECTURER'; level := 'ERROR'; words := 'No such staff member is on the register.'; RETURN NEXT; RETURN;
    END IF;
    v_name := concat_ws(', ', nullif(btrim(p.surname), ''), nullif(btrim(p.given_names), ''));
    IF p.ended_on IS NOT NULL THEN
        code := 'ACTIVE'; level := 'ERROR'; words := v_name || ' left the University''s service on ' || to_char(p.ended_on, 'FMDD FMMonth YYYY') || '.'; RETURN NEXT;
    ELSE
        code := 'ACTIVE'; level := 'OK'; words := v_name || coalesce(' (' || p.staff_number || ')', '') || ' is an active member of staff.'; RETURN NEXT;
    END IF;
    v_depts := catalogue.teaching_departments(p_person);
    IF cardinality(v_depts) = 0 THEN
        code := 'TEACHING'; level := 'ERROR';
        words := v_name || ' holds no lecturer office, so they cannot be given a class. The Director of ICT grants the office on the staff record.'; RETURN NEXT;
    ELSIF v_course_dept IS NOT NULL AND NOT (upper(v_course_dept) = ANY (v_depts)) THEN
        code := 'TEACHING'; level := 'OK';
        words := v_name || ' teaches in ' || (SELECT string_agg(coalesce(d.name, x), ', ') FROM unnest(v_depts) x LEFT JOIN ref.department d ON upper(d.code) = x)
                 || '; the course belongs to ' || coalesce((SELECT d.name FROM ref.department d WHERE d.code = v_course_dept), v_course_dept) || ' — teaching across departments.';
        RETURN NEXT;
    ELSE
        code := 'TEACHING'; level := 'OK'; words := v_name || ' is a lecturer of the course''s department.'; RETURN NEXT;
    END IF;

    -- the same allocation twice
    code := 'DUPLICATE';
    IF o.lecturer_id = p_person AND v_role = 'LECTURER' THEN
        level := 'ERROR'; words := 'Course already allocated to this lecturer for the selected session and semester.';
    ELSIF o.lecturer_id = p_person THEN
        level := 'ERROR'; words := v_name || ' is already the lead lecturer of this class.';
    ELSIF EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = p_person) THEN
        level := CASE WHEN v_role = 'LECTURER' THEN 'WARNING' ELSE 'ERROR' END;
        words := CASE WHEN v_role = 'LECTURER' THEN v_name || ' is a co-lecturer of this class; as the lead they stop being a co-lecturer.'
                      ELSE 'Course already allocated to this lecturer for the selected session and semester (as a co-lecturer).' END;
    ELSIF o.second_examiner_id = p_person AND v_role = 'LECTURER' THEN
        level := 'ERROR'; words := v_name || ' is the class''s second examiner, who verifies the lecturer''s marks; choose another second examiner first.';
    ELSE
        level := 'OK'; words := 'No such allocation is on record.';
    END IF;
    RETURN NEXT;

    -- the load, a lead's only (the approved maximum of catalogue.allocate_offering)
    IF v_role = 'LECTURER' THEN
        -- the load without this class (or its twin's, which is the same class), to which the class's units are added
        v_load := catalogue.teaching_load(p_person, o.session, o.semester)
                  - CASE WHEN EXISTS (SELECT 1 FROM catalogue.offering o2 WHERE o2.id IN (SELECT catalogue.offering_family(o.id)) AND o2.lecturer_id = p_person)
                         THEN v_units ELSE 0 END;
        code := 'LOAD';
        IF v_load + v_units > 12 THEN
            level := 'WARNING'; words := 'This puts ' || v_name || ' at ' || (v_load + v_units) || ' units this semester, over the approved maximum of 12: allocate it as an overload only if that is meant.';
        ELSE
            level := 'OK'; words := v_name || ' leads ' || v_load || ' units this semester; with this class, ' || (v_load + v_units) || '.';
        END IF;
        RETURN NEXT;
    END IF;

    -- the timetable, where it has slots
    v_clash := catalogue.timetable_clashes(o.id, p_person);
    code := 'TIMETABLE';
    IF cardinality(v_clash) > 0 THEN
        level := 'WARNING'; words := 'The class meets when ' || v_name || ' teaches ' || array_to_string(v_clash, '; ') || '.';
    ELSIF EXISTS (SELECT 1 FROM catalogue.class_slot s WHERE s.offering_id IN (SELECT catalogue.offering_family(o.id)) AND s.ended_at IS NULL) THEN
        level := 'OK'; words := 'No clash with ' || v_name || '''s other classes on the timetable.';
    ELSE
        level := 'OK'; words := 'The class has no timetable slot yet, so there is no clash to check.';
    END IF;
    RETURN NEXT;

    -- a score sheet already under way passes to the new lead
    IF v_role = 'LECTURER' AND o.lecturer_id IS NOT NULL THEN
        SELECT sh.stage INTO v_stage FROM assessment.score_sheet sh WHERE sh.offering_id = o.id ORDER BY (sh.stage = 'ENTRY') LIMIT 1;
        IF v_stage IS NOT NULL AND v_stage <> 'ENTRY' THEN
            code := 'SCORE_SHEET'; level := 'WARNING';
            words := 'The class''s score sheet has left the lecturer (it is at ' || initcap(replace(v_stage, '_', ' ')) || '); the new lead takes the class, not the marks already sent on.';
            RETURN NEXT;
        END IF;
    END IF;
END $$;
COMMENT ON FUNCTION catalogue.allocation_checks(uuid, uuid, text) IS
  'V408: whether a person may take a class as lead or co-lecturer, each check with OK, WARNING or ERROR and its words — the course live, the class offered, the session, the person active and teaching (across departments allowed), the same allocation twice, the 12-unit load, a timetable clash where there are slots, a score sheet under way. Writes nothing.';

-- ── 4 · what is wrong with a semester's allocations as they stand ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.allocation_conflicts(p_session text, p_semester int)
RETURNS TABLE (offering_id uuid, course_code text, dept_code text, kind text, words text)
LANGUAGE sql STABLE AS $$
    WITH cls AS (
        SELECT o.*, c.dept_code, c.state AS course_state, c.units AS course_units,
               concat_ws(', ', nullif(btrim(p.surname), ''), nullif(btrim(p.given_names), '')) AS lead_name, p.ended_on AS lead_ended
          FROM catalogue.offering o
          JOIN catalogue.course c ON c.code = o.course_code
          LEFT JOIN iam.person p ON p.id = o.lecturer_id
         WHERE o.session = p_session AND o.semester = p_semester AND o.stream IN ('REGULAR', 'PG')
    )
    SELECT id, course_code, dept_code, 'LECTURER_LEFT', lead_name || ' has left the University''s service but still leads the class.'
      FROM cls WHERE lecturer_id IS NOT NULL AND lead_ended IS NOT NULL
    UNION ALL
    SELECT id, course_code, dept_code, 'NO_TEACHING_OFFICE', lead_name || ' leads the class but holds no lecturer office.'
      FROM cls WHERE lecturer_id IS NOT NULL AND lead_ended IS NULL AND cardinality(catalogue.teaching_departments(lecturer_id)) = 0
    UNION ALL
    SELECT id, course_code, dept_code, 'COURSE_ENDED', 'The course has ended on the catalogue but the class still has a lecturer.'
      FROM cls WHERE lecturer_id IS NOT NULL AND course_state = 'ENDED'
    UNION ALL
    SELECT cls.id, cls.course_code, cls.dept_code, 'LEAD_ALSO_CO_LECTURER', lead_name || ' is both the lead and a co-lecturer of the class.'
      FROM cls WHERE EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = cls.id AND t.lecturer_id = cls.lecturer_id)
    UNION ALL
    SELECT id, course_code, dept_code, 'OVERLOAD', lead_name || ' leads ' || catalogue.teaching_load(lecturer_id, p_session, p_semester) || ' units this semester, over the approved 12.'
      FROM cls WHERE lecturer_id IS NOT NULL AND catalogue.teaching_load(lecturer_id, p_session, p_semester) > 12
    UNION ALL
    SELECT id, course_code, dept_code, 'TIMETABLE_CLASH', lead_name || ' is timetabled elsewhere when the class meets: ' || array_to_string(catalogue.timetable_clashes(id, lecturer_id), '; ') || '.'
      FROM cls WHERE lecturer_id IS NOT NULL AND cardinality(catalogue.timetable_clashes(id, lecturer_id)) > 0
$$;
COMMENT ON FUNCTION catalogue.allocation_conflicts(text, int) IS
  'V408: a semester''s allocations that need a look — a lead who has left or holds no lecturer office, an ended course still allocated, a lead also listed as co-lecturer, a lead over the 12-unit load, a lead timetabled elsewhere when the class meets (only where the timetable has slots). Full-time and postgraduate classes; the Centre''s are its own.';

-- ── 5 · an allocation made on a ticket, on the ticket's timeline ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.note_allocation(p_ticket uuid, p_summary text, p_reason text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF p_ticket IS NULL THEN RETURN; END IF;
    INSERT INTO helpdesk.ticket_event (ticket_id, actor_kind, actor_id, actor_name, action, to_value, detail)
    VALUES (p_ticket, 'AGENT', who, helpdesk.person_name(who), 'SUPPORT_COURSE_ALLOCATION', left(p_summary, 200),
            left('Action taken: ' || p_summary || coalesce(E'\nReason: ' || nullif(btrim(p_reason), ''), ''), 2000));
END $$;
COMMENT ON FUNCTION helpdesk.note_allocation(uuid, text, text) IS 'V408: a course allocation made on a ticket, put on the ticket''s timeline with what was done and why.';

COMMIT;
