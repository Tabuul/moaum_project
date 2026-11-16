-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V772 · The Director of ICT removes one student's wrongly counted course registration
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The user's master prompt of 15 November 2026, §5: some students are counted as registered for courses they never chose — electives
--  above all (an old-portal upload registers every row it carries; a dropped course the registration screen ticked again on a later
--  save; an elective the record could not tell from a core course became an owed carry-over). No desk could take a course off a closed
--  semester or one with a mark: the support desk's and Student Edit's drop keep SEMESTER_RECORDS and NO_MARK as hard rules, and V702's
--  duplicate resolution needs marks on two classes of one course.
--
--  Now the Director of ICT (ict; super) takes one student's course off one registration, with a reason:
--    · the course, the curriculum and every other student's registration are untouched; the entry is WITHDRAWN (a student's save keeps
--      it so), its snapshot kept on registration.entry_removal (RCR-YYYY-NNNNN), with how the course came onto the registration (the
--      student, an office, the Registry's late registration, an old-portal upload, a carry-over, a deferment) read from the record;
--    · a course that carries a result (any mark, F or ABS) is held — the University's decision of 15 November 2026 (D4): the course
--      keeps counting until the Registrar or Deputy Registrar (not the requester) confirms, then the entry is withdrawn and the mark stays
--      on its sheet as history; the same course's later carry-overs can be named in the same request;
--    · two classes of one course both marked are decided on the Duplicate results page (V702), never here;
--    · a removal sticks: nothing puts the course back on that registration but the Director's undo (registration.entry_removal_holds),
--      an old-portal upload reports it REMOVED_ON_RECORD (or REMOVAL_PENDING while the Registry decides — V771's
--      registration.entry_held_out), and V702 refuses to decide a class with a live removal;
--    · a removed course no longer counts anywhere: the GST/EPS fee readers no longer count a WITHDRAWN entry as registered (V702's
--      withdrawn twins neither), the ICT result monitor no longer flags its kept mark, issued transcripts are flagged for review;
--    · the student's change history (people.student_edit_history) lists every removal.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V772: the Director of ICT removes a wrongly counted course registration', true);

CREATE TABLE registration.entry_removal (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref text NOT NULL UNIQUE CHECK (ref ~ '^RCR-[0-9]{4}-[0-9]{5,}$'),
    group_ref text NOT NULL,
    student_id uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    registration_id uuid REFERENCES registration.course_registration (id) ON DELETE SET NULL,
    offering_id uuid REFERENCES catalogue.offering (id) ON DELETE SET NULL,
    course_code text NOT NULL, code_as_taken text, title text, session text NOT NULL, semester int NOT NULL, level int,
    was_status text NOT NULL, was_units int NOT NULL, was_entry_type text, was_basis text, was_as_taken uuid,
    was_added text NOT NULL CHECK (was_added IN ('STUDENT', 'OFFICE', 'REGISTRY_LATE', 'OLD_PORTAL', 'CARRY_OVER', 'DEFERRED', 'UNKNOWN')),
    had_result boolean NOT NULL, result_words text, graduate boolean NOT NULL DEFAULT false,
    reason text NOT NULL CHECK (length(btrim(reason)) >= 10),
    state text NOT NULL CHECK (state IN ('PENDING', 'APPLIED', 'DECLINED', 'CANCELLED', 'UNDONE')),
    requested_by uuid NOT NULL, requested_office text NOT NULL, requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    decided_by uuid, decided_office text, decided_at timestamptz, decision_note text,
    undone_by uuid, undone_office text, undone_at timestamptz, undo_reason text
);
CREATE UNIQUE INDEX ux_entry_removal_live ON registration.entry_removal (registration_id, offering_id) WHERE state IN ('PENDING', 'APPLIED');
CREATE INDEX ix_entry_removal_student ON registration.entry_removal (student_id, requested_at DESC);
CREATE INDEX ix_entry_removal_state ON registration.entry_removal (state, requested_at DESC);
COMMENT ON TABLE registration.entry_removal IS
  'V772: the Director of ICT''s removal of one student''s wrongly counted course from one registration — the entry as it stood (status, units, category, how it came on), whether it carried a result, the reason; APPLIED at once without a result, else PENDING until the Registrar or Deputy Registrar confirms (APPLIED) or declines; CANCELLED or UNDONE by the Director. registration_id and offering_id are kept as values when the registration or class goes.';
SELECT audit.attach('registration.entry_removal');

CREATE FUNCTION registration.entry_removal_kept()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF pg_trigger_depth() > 1 OR coalesce(current_setting('moaum.maintenance', true), '') = 'on' THEN RETURN OLD; END IF;
        RAISE EXCEPTION 'RCR_KEPT: a registration correction is history and is not deleted' USING ERRCODE = '23514';
    END IF;
    IF (NEW.ref, NEW.group_ref, NEW.student_id, NEW.course_code, NEW.session, NEW.semester, NEW.was_status, NEW.was_units, NEW.reason, NEW.requested_by)
       IS DISTINCT FROM (OLD.ref, OLD.group_ref, OLD.student_id, OLD.course_code, OLD.session, OLD.semester, OLD.was_status, OLD.was_units, OLD.reason, OLD.requested_by)
       OR (NEW.registration_id IS DISTINCT FROM OLD.registration_id AND NEW.registration_id IS NOT NULL)
       OR (NEW.offering_id IS DISTINCT FROM OLD.offering_id AND NEW.offering_id IS NOT NULL) THEN
        RAISE EXCEPTION 'RCR_KEPT: what a registration correction recorded is not changed' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_entry_removal_kept BEFORE UPDATE OR DELETE ON registration.entry_removal
    FOR EACH ROW EXECUTE FUNCTION registration.entry_removal_kept();

-- a removal sticks: nothing puts the course back on that registration but the Director's undo
CREATE FUNCTION registration.entry_removal_holds()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_ref text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- an insert that will meet the row already there (INSERT … ON CONFLICT) is not a return
        IF EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = NEW.registration_id AND e.offering_id = NEW.offering_id) THEN RETURN NEW; END IF;
    ELSIF NOT (OLD.status = 'WITHDRAWN' AND NEW.status IS DISTINCT FROM 'WITHDRAWN') THEN
        RETURN NEW;
    END IF;
    SELECT x.ref INTO v_ref FROM registration.entry_removal x
     WHERE x.registration_id = NEW.registration_id AND x.offering_id = NEW.offering_id AND x.state = 'APPLIED' LIMIT 1;
    IF v_ref IS NOT NULL THEN
        RAISE EXCEPTION 'RCR_REMOVED: this course was taken off the registration by the Director of ICT (%)', v_ref USING ERRCODE = '23514',
            HINT = 'Only that removal''s undo, on Course Registration Correction, puts it back.';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_entry_removal_holds BEFORE INSERT OR UPDATE OF status ON registration.entry
    FOR EACH ROW EXECUTE FUNCTION registration.entry_removal_holds();

-- V771's guard for uploads now reads the removals too
CREATE OR REPLACE FUNCTION registration.entry_held_out(p_registration uuid, p_offering uuid, p_student uuid, p_session text, p_semester int)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT w FROM (
        SELECT CASE x.state WHEN 'APPLIED' THEN 'REMOVED:' || x.ref ELSE 'PENDING:' || x.ref END AS w, 1 AS o
          FROM registration.entry_removal x
         WHERE x.registration_id = p_registration AND x.offering_id = p_offering AND x.state IN ('PENDING', 'APPLIED')
        UNION ALL
        SELECT 'REMOVED:' || coalesce('the duplicate resolution of ' || d.base_code, 'a duplicate resolution'), 2
          FROM assessment.duplicate_resolution d
         WHERE d.student_id = p_student AND d.session = p_session AND d.semester = p_semester AND d.dropped_offering = p_offering
           AND d.undone_at IS NULL) z
     ORDER BY o LIMIT 1
$$;

-- ── how a course came onto a registration, read from the record ─────────────────────────────────────────────────────────────────
CREATE FUNCTION registration.entry_came(p_registration uuid, p_offering uuid)
RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE e registration.entry; v_student uuid; v_office text; v_reason text; v_actor uuid;
BEGIN
    SELECT * INTO e FROM registration.entry WHERE registration_id = p_registration AND offering_id = p_offering;
    IF e.registration_id IS NULL THEN RETURN 'UNKNOWN'; END IF;
    SELECT r.student_id INTO v_student FROM registration.course_registration r WHERE r.id = p_registration;
    IF e.entry_type = 'DEFERRED' THEN RETURN 'DEFERRED'; END IF;
    IF e.support_override_reason LIKE 'Late registration by the Registry:%' THEN RETURN 'REGISTRY_LATE'; END IF;
    IF e.support_override_at IS NOT NULL THEN RETURN 'OFFICE'; END IF;
    -- the entry's first audit row (audit.record keys a keyed row by an md5 of its key)
    SELECT a.actor_office, a.reason, a.actor_id INTO v_office, v_reason, v_actor FROM audit.entries a
     WHERE a.subject_type = 'registration.entry'
       AND a.subject_id = md5(('registration.entry'::regclass)::oid::text || '|' || p_registration::text || '|' || p_offering::text)::uuid
       AND a.action = 'INSERT'
     ORDER BY a.occurred_at LIMIT 1;
    IF EXISTS (SELECT 1 FROM assessment.past_upload_change c WHERE c.registration_id = p_registration AND c.offering_id = p_offering AND c.kind = 'ENTRY_ADDED')
       OR v_reason ILIKE 'Legacy %imported%' OR v_reason ILIKE '%old portal%' THEN
        RETURN 'OLD_PORTAL';
    END IF;
    IF e.entry_type IN ('CARRYOVER', 'REPEAT') AND e.added_as IS DISTINCT FROM 'CARRY_OVER_DECLARED' THEN RETURN 'CARRY_OVER'; END IF;
    IF v_office = 'student' OR e.student_added_at IS NOT NULL THEN RETURN 'STUDENT'; END IF;
    IF v_office IS NOT NULL THEN RETURN 'OFFICE'; END IF;
    -- no audit row (before the spine, or a load with audit off): an imported score on the class is the old portal's
    IF EXISTS (SELECT 1 FROM assessment.score_sheet sh JOIN assessment.score s ON s.sheet_id = sh.id
                WHERE sh.offering_id = p_offering AND s.student_id = v_student AND s.imported) THEN
        RETURN 'OLD_PORTAL';
    END IF;
    RETURN 'UNKNOWN';
END $$;
COMMENT ON FUNCTION registration.entry_came(uuid, uuid) IS
  'V772: how a course came onto a registration — STUDENT (chosen on the portal), OFFICE (an office added it), REGISTRY_LATE, OLD_PORTAL (an old-portal upload), CARRY_OVER (placed because the results state it), DEFERRED, else UNKNOWN — from the entry and its first audit row, never a guess.';

-- the result a student has on a class: whether any mark (any version, any sitting) is on record, and the latest in words
CREATE FUNCTION registration.entry_result(p_student uuid, p_offering uuid)
RETURNS TABLE(has_result boolean, words text)
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM assessment.score_sheet sh JOIN assessment.score s ON s.sheet_id = sh.id WHERE sh.offering_id = p_offering AND s.student_id = p_student),
           (SELECT assessment.legacy_mark_words(s.outcome, s.ca, s.exam, s.total) || CASE WHEN s.imported THEN ' (old portal)' ELSE '' END
              FROM assessment.score_sheet sh JOIN assessment.score s ON s.sheet_id = sh.id
              LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id
             WHERE sh.offering_id = p_offering AND s.student_id = p_student
             ORDER BY (coalesce(es.kind, 'MAIN') = 'MAIN') DESC, s.version DESC LIMIT 1)
$$;

-- one registration's courses, as the Director of ICT reads them before a correction
CREATE FUNCTION registration.correction_entries(p_student uuid, p_session text, p_semester int)
RETURNS TABLE(registration_id uuid, offering_id uuid, course_code text, code_as_taken text, title text, units int, status text, entry_type text,
              basis text, category text, is_elective boolean, came text, has_result boolean, result_words text,
              removal_id uuid, removal_ref text, removal_state text, registration_status text, level int, elsewhere jsonb)
LANGUAGE sql STABLE AS $$
    SELECT r.id, e.offering_id, o.course_code, at.code_as_taken, coalesce(at.title, o.title, c.title), e.units, e.status, e.entry_type, e.basis,
           registration.entry_category(e.entry_type, c.kind, e.basis), registration.is_elective_for(p_student, o.course_code),
           registration.entry_came(r.id, e.offering_id), res.has_result, res.words,
           rm.id, rm.ref, rm.state, r.status, r.level,
           -- the same course on the student's other registrations (a carry-over the removed result gave rise to, among them)
           coalesce((SELECT jsonb_agg(jsonb_build_object('registrationId', r2.id, 'offeringId', e2.offering_id, 'session', r2.session, 'semester', r2.semester,
                                                         'courseCode', o2.course_code, 'entryType', e2.entry_type, 'status', e2.status, 'units', e2.units,
                                                         'hasResult', res2.has_result, 'result', res2.words,
                                                         'removalRef', (SELECT x.ref FROM registration.entry_removal x WHERE x.registration_id = r2.id
                                                                          AND x.offering_id = e2.offering_id AND x.state IN ('PENDING', 'APPLIED') LIMIT 1))
                                      ORDER BY r2.session, r2.semester)
                       FROM registration.course_registration r2
                       JOIN registration.entry e2 ON e2.registration_id = r2.id
                       JOIN catalogue.offering o2 ON o2.id = e2.offering_id
                       CROSS JOIN LATERAL registration.entry_result(p_student, e2.offering_id) res2
                      WHERE r2.student_id = p_student AND r2.id <> r.id
                        AND assessment.base_course_code(o2.course_code) = assessment.base_course_code(o.course_code)), '[]'::jsonb)
      FROM registration.course_registration r
      JOIN registration.entry e ON e.registration_id = r.id
      JOIN catalogue.offering o ON o.id = e.offering_id
      JOIN catalogue.course c ON c.code = o.course_code
      LEFT JOIN catalogue.course_as_taken at ON at.id = e.as_taken_id
      CROSS JOIN LATERAL registration.entry_result(p_student, e.offering_id) res
      LEFT JOIN LATERAL (SELECT x.id, x.ref, x.state FROM registration.entry_removal x
                          WHERE x.registration_id = r.id AND x.offering_id = e.offering_id
                          ORDER BY (x.state IN ('PENDING', 'APPLIED')) DESC, x.requested_at DESC LIMIT 1) rm ON true
     WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester
     ORDER BY o.course_code
$$;
COMMENT ON FUNCTION registration.correction_entries(uuid, text, int) IS
  'V772: a student''s courses on one semester''s registration as the Director of ICT reads them before a correction — as taken, status, category, elective or not, how each came on, its result, any removal, and the same course on the student''s other registrations.';

-- ── a removal asked for, decided, undone ────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION registration.request_entry_removal(p_student uuid, p_entries jsonb, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_group text; v_ref text; x jsonb; v_reg uuid; v_off uuid; e registration.entry; r registration.course_registration; o catalogue.offering;
        v_res record; v_state text; v_at catalogue.course_as_taken; v_title text; v_out jsonb := '[]'::jsonb; v_graduate boolean; v_id uuid;
BEGIN
    IF v_office IS NULL OR v_office NOT IN ('ict', 'super') THEN
        RAISE EXCEPTION 'RCR_OFFICE: a course registration is corrected by the Director of ICT' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'RCR_REASON: say why the course is taken off (ten characters or more); it goes on the record with your name' USING ERRCODE = '23514';
    END IF;
    IF p_entries IS NULL OR jsonb_typeof(p_entries) <> 'array' OR jsonb_array_length(p_entries) = 0 THEN
        RAISE EXCEPTION 'RCR_NONE: name the course to take off' USING ERRCODE = '23514';
    END IF;
    PERFORM 1 FROM people.student WHERE id = p_student FOR UPDATE;   -- one correction of a student at a time
    v_graduate := EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = p_student AND g.senate_state = 'APPROVED');
    FOR x IN SELECT * FROM jsonb_array_elements(p_entries) LOOP
        v_reg := (x->>'registrationId')::uuid; v_off := (x->>'offeringId')::uuid;
        SELECT * INTO r FROM registration.course_registration WHERE id = v_reg;
        SELECT * INTO e FROM registration.entry WHERE registration_id = v_reg AND offering_id = v_off FOR UPDATE;
        IF r.id IS NULL OR e.registration_id IS NULL OR r.student_id <> p_student THEN
            RAISE EXCEPTION 'RCR_NOT_FOUND: that course is not on this student''s registration' USING ERRCODE = 'P0002';
        END IF;
        SELECT * INTO o FROM catalogue.offering WHERE id = v_off;
        IF e.status NOT IN ('APPROVED', 'REGISTERED') THEN
            RAISE EXCEPTION 'RCR_NOT_COUNTED: % in % semester % is % on the registration, not counted', o.course_code, r.session, r.semester, lower(e.status)
                USING ERRCODE = '23514';
        END IF;
        IF EXISTS (SELECT 1 FROM registration.entry_removal z WHERE z.registration_id = v_reg AND z.offering_id = v_off AND z.state IN ('PENDING', 'APPLIED')) THEN
            RAISE EXCEPTION 'RCR_OPEN: % in % semester % has a removal already', o.course_code, r.session, r.semester USING ERRCODE = '23514';
        END IF;
        SELECT * INTO v_res FROM registration.entry_result(p_student, v_off);
        -- two classes of one course, both marked, are decided where the duplicate results are (V702)
        IF v_res.has_result AND EXISTS (
               SELECT 1 FROM catalogue.offering o2 JOIN assessment.score_sheet sh ON sh.offering_id = o2.id JOIN assessment.score s ON s.sheet_id = sh.id
                WHERE o2.id <> v_off AND o2.session = o.session AND o2.semester = o.semester AND s.student_id = p_student
                  AND assessment.base_course_code(o2.course_code) = assessment.base_course_code(o.course_code)
                  -- a class the Duplicate results page shows withdrawn is no second result (as assessment.result_duplicates reads it):
                  -- a first result its upload's rollback took back, on either class …
                  AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh2
                                   WHERE sh2.offering_id IN (o2.id, v_off) AND assessment.result_rolled_back(sh2.id, p_student))
                  -- … or a class the Director of ICT has already taken off
                  AND NOT EXISTS (SELECT 1 FROM registration.entry_removal z
                                   WHERE z.student_id = p_student AND z.offering_id = o2.id AND z.state = 'APPLIED')
                  AND NOT EXISTS (SELECT 1 FROM assessment.duplicate_resolution d WHERE d.student_id = p_student AND d.undone_at IS NULL
                                     AND d.dropped_offering IN (o2.id, v_off))) THEN
            RAISE EXCEPTION 'RCR_USE_DUPLICATES: two classes of % carry marks for the student in % semester %; decide which stands on the Duplicate results page',
                            assessment.base_course_code(o.course_code), o.session, o.semester USING ERRCODE = '23514';
        END IF;
        v_ref := 'RCR-' || to_char(now(), 'YYYY') || '-' || lpad(platform.next_number('ENTRY_REMOVAL', 'UNIVERSITY', to_char(now(), 'YYYY'))::text, 5, '0');
        v_group := coalesce(v_group, v_ref);
        v_state := CASE WHEN v_res.has_result THEN 'PENDING' ELSE 'APPLIED' END;
        v_at := NULL;
        IF e.as_taken_id IS NOT NULL THEN SELECT * INTO v_at FROM catalogue.course_as_taken WHERE id = e.as_taken_id; END IF;
        SELECT coalesce(v_at.title, o.title, c.title) INTO v_title FROM catalogue.course c WHERE c.code = o.course_code;
        INSERT INTO registration.entry_removal (ref, group_ref, student_id, registration_id, offering_id, course_code, code_as_taken, title, session, semester, level,
                                                was_status, was_units, was_entry_type, was_basis, was_as_taken, was_added, had_result, result_words, graduate,
                                                reason, state, requested_by, requested_office)
        VALUES (v_ref, v_group, p_student, v_reg, v_off, o.course_code, v_at.code_as_taken, v_title, r.session, r.semester, r.level,
                e.status, e.units, e.entry_type, e.basis, e.as_taken_id, registration.entry_came(v_reg, v_off), v_res.has_result, v_res.words, v_graduate,
                btrim(p_reason), v_state, v_actor, v_office)
        RETURNING id INTO v_id;
        IF v_state = 'APPLIED' THEN
            UPDATE registration.entry SET status = 'WITHDRAWN' WHERE registration_id = v_reg AND offering_id = v_off;
            IF catalogue.class_examined(v_off) THEN
                PERFORM credentials.flag_documents(p_student, ARRAY['TRANSCRIPT', 'SESSIONAL_TRANSCRIPT', 'MINI_TRANSCRIPT', 'ACADEMIC_STATEMENT'],
                                                   'A course was taken off the student''s registration (' || v_ref || ')');
            END IF;
        END IF;
        v_out := v_out || jsonb_build_object('id', v_id, 'ref', v_ref, 'state', v_state, 'courseCode', o.course_code, 'session', r.session, 'semester', r.semester);
    END LOOP;
    RETURN jsonb_build_object('groupRef', v_group, 'graduate', v_graduate, 'removals', v_out);
END $$;
COMMENT ON FUNCTION registration.request_entry_removal(uuid, jsonb, text) IS
  'V772: the Director of ICT takes courses off a student''s registrations under one reason ([{registrationId, offeringId}]): one without a result is withdrawn at once (APPLIED), one with a result held PENDING for the Registry (D4). Refusals RCR_OFFICE, RCR_REASON, RCR_NONE, RCR_NOT_FOUND, RCR_NOT_COUNTED, RCR_OPEN, RCR_USE_DUPLICATES.';

CREATE FUNCTION registration.decide_entry_removal(p_removal uuid, p_confirm boolean, p_note text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        x registration.entry_removal; e registration.entry;
BEGIN
    IF v_office IS NULL OR v_office NOT IN ('registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'RCR_DECIDER: a removal with a result is confirmed by the Registrar or the Deputy Registrar' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO x FROM registration.entry_removal WHERE id = p_removal FOR UPDATE;
    IF x.id IS NULL THEN RAISE EXCEPTION 'RCR_NOT_FOUND: no such correction' USING ERRCODE = 'P0002'; END IF;
    IF x.state <> 'PENDING' THEN RAISE EXCEPTION 'RCR_STATE: % is %, not awaiting a decision', x.ref, lower(x.state) USING ERRCODE = '23514'; END IF;
    IF x.requested_by = v_actor THEN
        RAISE EXCEPTION 'RCR_SAME_PERSON: you asked for this removal; another officer decides it' USING ERRCODE = '23514';
    END IF;
    IF p_confirm THEN
        SELECT * INTO e FROM registration.entry WHERE registration_id = x.registration_id AND offering_id = x.offering_id FOR UPDATE;
        IF e.registration_id IS NULL OR e.status NOT IN ('APPROVED', 'REGISTERED') OR e.units <> x.was_units THEN
            RAISE EXCEPTION 'RCR_STALE: the course has changed on the registration since % was asked for; decline it and ask again', x.ref USING ERRCODE = '23514';
        END IF;
        UPDATE registration.entry_removal SET state = 'APPLIED', decided_by = v_actor, decided_office = v_office, decided_at = clock_timestamp(),
               decision_note = nullif(btrim(coalesce(p_note, '')), '') WHERE id = p_removal;
        UPDATE registration.entry SET status = 'WITHDRAWN' WHERE registration_id = x.registration_id AND offering_id = x.offering_id;
        IF catalogue.class_examined(x.offering_id) THEN
            PERFORM credentials.flag_documents(x.student_id, ARRAY['TRANSCRIPT', 'SESSIONAL_TRANSCRIPT', 'MINI_TRANSCRIPT', 'ACADEMIC_STATEMENT'],
                                               'A course was taken off the student''s registration (' || x.ref || ')');
        END IF;
        RETURN 'APPLIED';
    END IF;
    IF length(btrim(coalesce(p_note, ''))) < 10 THEN
        RAISE EXCEPTION 'RCR_NOTE: say why the removal is declined (ten characters or more)' USING ERRCODE = '23514';
    END IF;
    UPDATE registration.entry_removal SET state = 'DECLINED', decided_by = v_actor, decided_office = v_office, decided_at = clock_timestamp(),
           decision_note = btrim(p_note) WHERE id = p_removal;
    RETURN 'DECLINED';
END $$;
COMMENT ON FUNCTION registration.decide_entry_removal(uuid, boolean, text) IS
  'V772: the Registrar or Deputy Registrar (not the officer who asked) confirms a removal held for a result — the entry is withdrawn, its mark kept on the sheet as history — or declines it with a note. Refusals RCR_DECIDER, RCR_NOT_FOUND, RCR_STATE, RCR_SAME_PERSON, RCR_STALE, RCR_NOTE.';

CREATE FUNCTION registration.undo_entry_removal(p_removal uuid, p_reason text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        x registration.entry_removal;
BEGIN
    IF v_office IS NULL OR v_office NOT IN ('ict', 'super') THEN
        RAISE EXCEPTION 'RCR_OFFICE: a registration correction is undone by the Director of ICT' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'RCR_REASON: say why the correction is undone (ten characters or more)' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO x FROM registration.entry_removal WHERE id = p_removal FOR UPDATE;
    IF x.id IS NULL THEN RAISE EXCEPTION 'RCR_NOT_FOUND: no such correction' USING ERRCODE = 'P0002'; END IF;
    IF x.state NOT IN ('PENDING', 'APPLIED') THEN RAISE EXCEPTION 'RCR_STATE: % is %', x.ref, lower(x.state) USING ERRCODE = '23514'; END IF;
    UPDATE registration.entry_removal SET state = CASE WHEN x.state = 'PENDING' THEN 'CANCELLED' ELSE 'UNDONE' END,
           undone_by = v_actor, undone_office = v_office, undone_at = clock_timestamp(), undo_reason = btrim(p_reason) WHERE id = p_removal;
    IF x.state = 'APPLIED' THEN
        UPDATE registration.entry SET status = x.was_status
         WHERE registration_id = x.registration_id AND offering_id = x.offering_id AND status = 'WITHDRAWN';
        IF catalogue.class_examined(x.offering_id) THEN
            PERFORM credentials.flag_documents(x.student_id, ARRAY['TRANSCRIPT', 'SESSIONAL_TRANSCRIPT', 'MINI_TRANSCRIPT', 'ACADEMIC_STATEMENT'],
                                               'A course taken off the student''s registration was put back (' || x.ref || ')');
        END IF;
        RETURN 'UNDONE';
    END IF;
    RETURN 'CANCELLED';
END $$;
COMMENT ON FUNCTION registration.undo_entry_removal(uuid, text) IS
  'V772: the Director of ICT cancels a removal awaiting the Registry, or undoes an applied one (the entry back as it stood). Refusals RCR_OFFICE, RCR_REASON, RCR_NOT_FOUND, RCR_STATE.';

-- ── a removed course counts nowhere: the result monitor, the duplicates, the GST/EPS fee readers ─────────────────────────────────
DO $$
DECLARE d text; f text; i int; n int; want int;
    plan jsonb := jsonb_build_array(
        jsonb_build_object('f', 'assessment.result_exceptions(text,integer,text,text,text,integer)', 'edits', jsonb_build_array(
            jsonb_build_array('WHERE dr.student_id = d.student_id AND dr.dropped_offering = d.offering_id AND dr.undone_at IS NULL)',
                              'WHERE dr.student_id = d.student_id AND dr.dropped_offering = d.offering_id AND dr.undone_at IS NULL)
           AND NOT EXISTS (SELECT 1 FROM registration.entry_removal x   -- V772: a class taken off by the Director of ICT is not counted
                            WHERE x.student_id = d.student_id AND x.offering_id = d.offering_id AND x.state = ''APPLIED'')
           AND NOT assessment.result_rolled_back(d.sheet_id, d.student_id)   -- V771: nor a first result its upload''s rollback took back', 1),
            jsonb_build_array('WHERE dr.student_id = m.student_id AND dr.dropped_offering = m.offering_id AND dr.undone_at IS NULL)',
                              'WHERE dr.student_id = m.student_id AND dr.dropped_offering = m.offering_id AND dr.undone_at IS NULL)
       AND NOT EXISTS (SELECT 1 FROM registration.entry_removal x   -- V772: taken off by the Director of ICT, its mark kept as history
                        WHERE x.student_id = m.student_id AND x.offering_id = m.offering_id AND x.state = ''APPLIED'')
       -- V771: a first result an upload posted and its rollback took back is kept as history; a mark that was there before the upload
       -- (the record back as it stood) or one made since is judged as any other
       AND NOT assessment.result_rolled_back(m.sheet_id, m.student_id)', 2))),
        jsonb_build_object('f', 'assessment.result_duplicates(text,integer,text,text,text)', 'edits', jsonb_build_array(
            jsonb_build_array('CASE WHEN dr.dropped_offering = m.offering_id THEN ''WITHDRAWN''',
                              'CASE WHEN dr.dropped_offering = m.offering_id OR EXISTS (SELECT 1 FROM registration.entry_removal x   -- V772
                                                                     WHERE x.student_id = m.student_id AND x.offering_id = m.offering_id AND x.state = ''APPLIED'')
                         OR EXISTS (SELECT 1 FROM assessment.score_sheet sh2   -- V771: a first result its upload''s rollback took back
                                     WHERE sh2.offering_id = m.offering_id AND assessment.result_rolled_back(sh2.id, m.student_id)) THEN ''WITHDRAWN''', 1))),
        jsonb_build_object('f', 'assessment.resolve_duplicate(uuid,uuid,uuid,text)', 'edits', jsonb_build_array(
            jsonb_build_array('    SELECT e.status INTO v_was FROM registration.entry e',
                              '    IF EXISTS (SELECT 1 FROM registration.entry_removal x WHERE x.student_id = p_student AND x.offering_id IN (p_keep, p_drop)
                AND x.state IN (''PENDING'', ''APPLIED'')) THEN   -- V772
        RAISE EXCEPTION ''DUP_REMOVAL: one of these classes is being taken off the registration by the Director of ICT; settle that first'' USING ERRCODE = ''23514'';
    END IF;
    SELECT e.status INTO v_was FROM registration.entry e', 1))),
        jsonb_build_object('f', 'finance.gst_eps_rows(text,uuid)', 'edits', jsonb_build_array(
            jsonb_build_array('x.entry_status <> ''DROPPED''', 'x.entry_status NOT IN (''DROPPED'', ''WITHDRAWN'')', 1))),
        jsonb_build_object('f', 'finance.gst_population(text,integer)', 'edits', jsonb_build_array(
            jsonb_build_array('e.status <> ''DROPPED''', 'e.status NOT IN (''DROPPED'', ''WITHDRAWN'')', 1))),
        jsonb_build_object('f', 'finance.gst_course_stats(text,integer,text)', 'edits', jsonb_build_array(
            jsonb_build_array('e.status <> ''DROPPED''', 'e.status NOT IN (''DROPPED'', ''WITHDRAWN'')', 2))),
        jsonb_build_object('f', 'finance.gst_unpaid_remind(text,text,uuid[])', 'edits', jsonb_build_array(
            jsonb_build_array('e.status <> ''DROPPED''', 'e.status NOT IN (''DROPPED'', ''WITHDRAWN'')', 1))),
        jsonb_build_object('f', 'registration.student_reset(uuid,text,integer,text,text)', 'edits', jsonb_build_array(
            jsonb_build_array('DELETE FROM registration.entry WHERE registration_id = r.id AND support_override_at IS NULL',
                              'DELETE FROM registration.entry WHERE registration_id = r.id AND support_override_at IS NULL AND status <> ''WITHDRAWN''   -- V772: a course taken off stays off', 1),
            jsonb_build_array('count(*) FILTER (WHERE (e.entry_type NOT IN (''CARRYOVER'', ''DEFERRED'') OR e.added_as = ''CARRY_OVER_DECLARED'' OR v_spill) AND e.support_override_at IS NULL)',
                              'count(*) FILTER (WHERE (e.entry_type NOT IN (''CARRYOVER'', ''DEFERRED'') OR e.added_as = ''CARRY_OVER_DECLARED'' OR v_spill) AND e.support_override_at IS NULL AND e.status <> ''WITHDRAWN'')', 1))),
        jsonb_build_object('f', 'registration.student_choose(uuid,uuid[])', 'edits', jsonb_build_array(
            jsonb_build_array('AND e.entry_type IN (''CARRYOVER'', ''DEFERRED'') AND e.support_override_at IS NULL',
                              'AND e.entry_type IN (''CARRYOVER'', ''DEFERRED'') AND e.support_override_at IS NULL AND e.status <> ''WITHDRAWN''', 1))),
        jsonb_build_object('f', 'registration.submit_checks(uuid)', 'edits', jsonb_build_array(
            jsonb_build_array('e.status <> ''DROPPED'' AND registration.gst_gate', 'e.status NOT IN (''DROPPED'', ''WITHDRAWN'') AND registration.gst_gate', 1))),
        jsonb_build_object('f', 'registration.support_drop_checks(uuid,text,integer,uuid)', 'edits', jsonb_build_array(
            jsonb_build_array('passed := e.offering_id IS NOT NULL AND e.status <> ''DROPPED'';',
                              'passed := e.offering_id IS NOT NULL AND e.status NOT IN (''DROPPED'', ''WITHDRAWN'');   -- V772: a course taken off is not on it', 1))),
        jsonb_build_object('f', 'people.student_edit_history(uuid)', 'edits', jsonb_build_array(
            jsonb_build_array('      FROM people.classification_decision d WHERE d.student_id = p_student',
                              '      FROM people.classification_decision d WHERE d.student_id = p_student
    UNION ALL   -- V772: the Director of ICT''s registration corrections
    SELECT x.requested_at, x.ref, ''REGISTRATION'', ''IMPORTANT'', ''REGISTRATION'',
           coalesce(x.code_as_taken, x.course_code) || '' · '' || x.session || '' semester '' || x.semester,
           initcap(lower(x.was_status)),
           CASE x.state WHEN ''APPLIED'' THEN ''Withdrawn'' WHEN ''PENDING'' THEN ''Held for the Registry'' WHEN ''DECLINED'' THEN ''Declined by the Registry''
                        WHEN ''CANCELLED'' THEN ''Cancelled'' ELSE ''Put back'' END,
           x.reason, helpdesk.person_name(x.requested_by), x.requested_office, ''Course Registration Correction''
      FROM registration.entry_removal x WHERE x.student_id = p_student', 1))));
    p jsonb; ed jsonb;
BEGIN
    FOR p IN SELECT * FROM jsonb_array_elements(plan) LOOP
        f := p->>'f';
        d := pg_get_functiondef(f::regprocedure);
        FOR ed IN SELECT * FROM jsonb_array_elements(p->'edits') LOOP
            want := (ed->>2)::int;
            n := (length(d) - length(replace(d, ed->>0, ''))) / length(ed->>0);
            IF n <> want THEN RAISE EXCEPTION 'V772: % is not as it was left (% found % times, % wanted)', f, left(ed->>0, 60), n, want; END IF;
            d := replace(d, ed->>0, ed->>1);
        END LOOP;
        EXECUTE d;
    END LOOP;
END $$;

-- a rollback leaves a course a Course Registration Correction has been recorded on since the upload put it there (asked for, decided
-- or undone): a person has acted on it, whatever it reads now
CREATE OR REPLACE FUNCTION registration.entry_corrected_since(p_registration uuid, p_offering uuid, p_since timestamptz)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM registration.entry_removal z
                    WHERE z.registration_id = p_registration AND z.offering_id = p_offering
                      AND greatest(z.requested_at, coalesce(z.decided_at, z.requested_at), coalesce(z.undone_at, z.requested_at)) > p_since)
$$;

-- a held result whose course the Director of ICT took off is neither posted nor counted as held while the removal stands (its undo
-- posts it on the next reconcile)
CREATE OR REPLACE FUNCTION assessment.reconcile_legacy_holding()
 RETURNS TABLE(reconciled integer, still_held integer)
 LANGUAGE plpgsql
AS $function$
DECLARE grp record; v_before int; v_after int;
BEGIN
    PERFORM set_config('moaum.legacy_reconcile', 'on', true);  -- V627: posting held results is open to every migrating office
    SELECT count(*) INTO v_before FROM assessment.legacy_result_holding h
     WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric) AND NOT assessment.held_row_removed(h);
    FOR grp IN
        -- V771's reading (a row an earlier upload still standing held before is posted first, under that upload), without the removed
        WITH RECURSIVE held AS (
            SELECT h.session, h.semester, h.matric, h.course_code, h.as_taken, h.upload_id, h.raw, h.loaded_at, h.prior, 0 AS depth
              FROM assessment.legacy_result_holding h
             WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric) AND NOT assessment.held_row_removed(h)
            UNION ALL
            SELECT c.session, c.semester, c.matric, c.course_code, coalesce((c.prior->>'as_taken')::boolean, false), (c.prior->>'upload_id')::uuid,
                   c.prior->'raw', (c.prior->>'loaded_at')::timestamptz, c.prior->'prior', c.depth + 1
              FROM held c WHERE jsonb_typeof(c.prior) = 'object')
        SELECT k.session, k.semester, k.as_taken, k.upload_id, jsonb_agg(k.raw ORDER BY k.loaded_at) AS rows
          FROM (SELECT DISTINCT ON (q.session, q.semester, q.matric, q.course_code, q.upload_id) q.*   -- an upload's newest hold of the row only
                  FROM held q ORDER BY q.session, q.semester, q.matric, q.course_code, q.upload_id, q.depth) k
          LEFT JOIN assessment.past_upload pu ON pu.id = k.upload_id
         WHERE k.depth = 0 OR pu.state IS DISTINCT FROM 'REVERTED'
         GROUP BY k.session, k.semester, k.as_taken, k.upload_id
         ORDER BY min(pu.created_at) NULLS FIRST, min(pu.ref) NULLS FIRST, max(k.depth) DESC
    LOOP
        PERFORM assessment.legacy_semester_load(grp.session, grp.semester, grp.rows, true, false, grp.upload_id, grp.as_taken);
    END LOOP;
    SELECT count(*) INTO v_after FROM assessment.legacy_result_holding h
     WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric) AND NOT assessment.held_row_removed(h);
    PERFORM set_config('moaum.legacy_reconcile', '', true);
    RETURN QUERY SELECT greatest(v_before - v_after, 0),
                        (SELECT count(*)::int FROM assessment.legacy_result_holding h WHERE NOT assessment.held_row_removed(h));
END $function$;

CREATE FUNCTION assessment.held_row_removed(h assessment.legacy_result_holding)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    -- exactly what the loader will decide (registration.entry_held_out: the Director's removal or a V702 duplicate resolution), on the
    -- class as it stands now
    SELECT EXISTS (SELECT 1 FROM people.student s
                     JOIN registration.course_registration r ON r.student_id = s.id AND r.session = h.session AND r.semester = h.semester
                     JOIN registration.entry e ON e.registration_id = r.id
                     JOIN catalogue.offering o ON o.id = e.offering_id AND o.course_code = h.course_code
                    WHERE upper(s.matric_no) = h.matric
                      AND registration.entry_held_out(r.id, e.offering_id, s.id, h.session, h.semester) LIKE 'REMOVED:%')
        -- a held row of an upload since rolled back never posts
        OR EXISTS (SELECT 1 FROM assessment.past_upload u WHERE u.id = h.upload_id AND u.state = 'REVERTED')
$$;
COMMENT ON FUNCTION assessment.held_row_removed(assessment.legacy_result_holding) IS
  'V772: a held old-portal result whose class the Director of ICT took off the student''s registration (or a V702 duplicate resolution withdrew), or whose upload was rolled back — kept, but neither posted nor counted as held while that stands.';

DO $$
DECLARE rl text;
BEGIN
    FOREACH rl IN ARRAY ARRAY['app_auditor', 'app_acrecords', 'app_reporting', 'app_registration'] LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = rl) THEN
            EXECUTE format('GRANT SELECT ON registration.entry_removal TO %I', rl);
        END IF;
    END LOOP;
END $$;

COMMIT;
