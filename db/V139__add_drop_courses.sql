-- ═══════════════════════════════════════════════════════════════════════════
-- V139 — add and drop courses after the initial registration
--
--   Once a registration is submitted/approved, student_choose refuses to edit
--   it. But a student often needs to add or drop a course during the add/drop
--   window — the late-registration period the semester carries. These two
--   functions do exactly that, on an already-submitted or approved
--   registration, without re-opening the whole form:
--
--     - add:  the course must be offered to the student's programme and level
--             this semester, not already on the form, the Bursary must clear
--             them for registration, and the units must stay within the level's
--             maximum. A previously dropped course is simply reinstated.
--     - drop: an active course that is NOT a carryover (a carryover is
--             compulsory) and has no mark recorded yet. It is marked DROPPED,
--             not deleted, so the change is on the record.
--
--   The window is open while the semester is OPEN and on or before its
--   late-registration close (or its registration close, or with no date set,
--   for as long as the semester is open). A LOCKED registration is never edited.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION registration.add_drop_open(p_session text, p_semester int)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM policy.semester s
         WHERE s.session = p_session AND s.number = p_semester AND s.state = 'OPEN'
           AND current_date <= coalesce(s.late_registration_closes, s.registration_closes, current_date));
$$;

CREATE OR REPLACE FUNCTION registration.student_add(p_student uuid, p_session text, p_semester int, p_offering uuid)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; m record; lim policy.level_limit; v_units int; v_type text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF NOT FOUND THEN RAISE EXCEPTION 'register first, then add or drop' USING ERRCODE = '23514'; END IF;
    IF r.status = 'LOCKED' THEN RAISE EXCEPTION 'this registration is locked and cannot be changed' USING ERRCODE = '23514'; END IF;
    IF NOT registration.add_drop_open(p_session, p_semester) THEN
        RAISE EXCEPTION 'add and drop is not open for % semester %', p_session, p_semester USING ERRCODE = '23514',
            HINT = 'It runs while the semester is open, up to the late-registration deadline set by the Registry.';
    END IF;
    IF NOT finance.clears(p_student, p_session, 'REGISTRATION') THEN
        RAISE EXCEPTION 'the Bursary has not cleared you for registration in %', p_session USING ERRCODE = '23514';
    END IF;

    SELECT * INTO m FROM registration.student_menu(p_student, p_session, p_semester) WHERE offering_id = p_offering AND NOT carryover;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'that course is not offered to your programme at your level this semester' USING ERRCODE = '23514';
    END IF;
    v_units := m.units;
    v_type := CASE WHEN m.basis = 'GST' OR m.kind = 'GST' THEN 'GST' WHEN m.basis = 'Borrowed' THEN 'BORROWED'
                   WHEN m.basis = 'Elective' OR m.kind = 'Elective' THEN 'ELECTIVE' ELSE 'CURRENT' END;

    -- would this exceed the level's maximum?
    SELECT * INTO lim FROM policy.level_limit WHERE level = r.level;
    IF FOUND AND registration.units_of(r.id) + v_units > lim.max_units THEN
        RAISE EXCEPTION 'adding this course puts you at % units, over the maximum of % at % level',
            registration.units_of(r.id) + v_units, lim.max_units, r.level USING ERRCODE = '23514',
            HINT = 'Drop a course first, or ask your Head of Department for an overload.';
    END IF;

    -- reinstate a dropped entry, or add a new one (kept as REGISTERED — a live entry the register counts)
    IF EXISTS (SELECT 1 FROM registration.entry WHERE registration_id = r.id AND offering_id = p_offering) THEN
        UPDATE registration.entry SET status = 'REGISTERED', units = v_units, entry_type = v_type
         WHERE registration_id = r.id AND offering_id = p_offering;
    ELSE
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
        VALUES (r.id, p_offering, v_units, v_type, 'REGISTERED');
    END IF;
    RETURN registration.units_of(r.id);
END $$;

CREATE OR REPLACE FUNCTION registration.student_drop(p_student uuid, p_session text, p_semester int, p_offering uuid)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; e registration.entry;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF NOT FOUND THEN RAISE EXCEPTION 'no registration to change' USING ERRCODE = '23514'; END IF;
    IF r.status = 'LOCKED' THEN RAISE EXCEPTION 'this registration is locked and cannot be changed' USING ERRCODE = '23514'; END IF;
    IF NOT registration.add_drop_open(p_session, p_semester) THEN
        RAISE EXCEPTION 'add and drop is not open for % semester %', p_session, p_semester USING ERRCODE = '23514';
    END IF;

    SELECT * INTO e FROM registration.entry WHERE registration_id = r.id AND offering_id = p_offering AND status <> 'DROPPED';
    IF NOT FOUND THEN RAISE EXCEPTION 'that course is not on your registration' USING ERRCODE = '23514'; END IF;
    IF e.entry_type = 'CARRYOVER' THEN
        RAISE EXCEPTION 'a carryover cannot be dropped; it must be repeated' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM assessment.score sc JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id
                WHERE sc.student_id = p_student AND sh.offering_id = p_offering) THEN
        RAISE EXCEPTION 'a mark is already recorded in this course; it cannot be dropped' USING ERRCODE = '23514';
    END IF;

    UPDATE registration.entry SET status = 'DROPPED' WHERE registration_id = r.id AND offering_id = p_offering;
    RETURN registration.units_of(r.id);
END $$;

COMMENT ON FUNCTION registration.student_add(uuid, text, int, uuid) IS
  'Add a course to a submitted/approved registration during the add/drop window (units, clearance and level max enforced; a dropped course is reinstated).';
COMMENT ON FUNCTION registration.student_drop(uuid, text, int, uuid) IS
  'Drop a non-carryover course with no mark from a registration during the add/drop window (marked DROPPED, not deleted).';

COMMIT;
