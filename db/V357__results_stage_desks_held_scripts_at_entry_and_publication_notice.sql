-- V357: results — the integrity of the approval chain, held scripts kept within it, and a published result told.
--
-- 1. Each stage of a score sheet is taken by its own desk, on the server: the lecturer (or the GST / EPS office for their own
--    courses, or the Programme Examinations Officer on the lecturer's behalf) submits; the Programme Examinations Officer
--    verifies; the Head of Department, the Faculty Examinations Officer, the Faculty Officer and the Dean take the faculty's
--    stages; Exams & Records compile; the Registrar (or the Deputy Registrar) publishes on the Senate minute. Until now the
--    screen alone kept a desk to its stage. A sheet is returned only by the desk whose stage it is at. The rule is the same
--    table the screens read (`Sheets.DESK`), tested equal.
-- 2. A held script is held only on a sheet still at entry; and a released mark reaches the sheet only while it is at entry —
--    a mark never lands on a sheet a desk has already approved (or published). A student whose registration is approved
--    while the sheet is with a later desk is not lost: the script waits, does not lapse, and is released the moment the sheet
--    is returned to entry.
-- 3. A published sheet tells each of its students — by email, that the result in the course is published (no grade in the
--    message), and by one text a day however many sheets are published that day.
BEGIN;

-- ── 1 · the desk of each stage ──────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION assessment.stage_offices(p_stage text)
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_stage
        WHEN 'ENTRY' THEN ARRAY['lecturer', 'gst', 'eps', 'exams']
        WHEN 'VERIFICATION' THEN ARRAY['exams']
        WHEN 'DEPT_BOARD' THEN ARRAY['hod']
        WHEN 'FACULTY_SCRUTINY' THEN ARRAY['facultyexams']
        WHEN 'FACULTY_COMPILATION' THEN ARRAY['facultyofficer']
        WHEN 'FACULTY_BOARD' THEN ARRAY['dean']
        WHEN 'RECORDS' THEN ARRAY['records']
        WHEN 'SENATE' THEN ARRAY['registrar', 'dregistrar']
        ELSE ARRAY[]::text[]
    END
$$;
COMMENT ON FUNCTION assessment.stage_offices(text) IS 'V357: the offices that take a score sheet''s stage — the server''s rule, the same as the screens'' Sheets.DESK.';

CREATE OR REPLACE FUNCTION assessment.stage_desk_name(p_stage text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_stage
        WHEN 'ENTRY' THEN 'the lecturer'
        WHEN 'VERIFICATION' THEN 'the Programme Examinations Officer'
        WHEN 'DEPT_BOARD' THEN 'the Head of Department'
        WHEN 'FACULTY_SCRUTINY' THEN 'the Faculty Examinations Officer'
        WHEN 'FACULTY_COMPILATION' THEN 'the Faculty Officer'
        WHEN 'FACULTY_BOARD' THEN 'the Dean'
        WHEN 'RECORDS' THEN 'Exams & Records'
        WHEN 'SENATE' THEN 'the Registrar'
        ELSE 'no desk'
    END
$$;

/* a sheet's stage taken (or the sheet returned) only by that stage's desk */
CREATE OR REPLACE FUNCTION assessment.require_stage_desk(p_stage text, p_office text, p_act text)
RETURNS void LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF p_office IS NULL OR NOT (p_office = ANY (assessment.stage_offices(p_stage))) THEN
        RAISE EXCEPTION 'RES_NOT_YOUR_STAGE: a sheet at % is % by %, not by the % office',
            lower(replace(p_stage, '_', ' ')), p_act, assessment.stage_desk_name(p_stage), coalesce(p_office, 'unnamed')
            USING ERRCODE = '23514', HINT = 'Each stage of the chain belongs to one desk; the sheet waits for it.';
    END IF;
END $$;

-- V197's advance, with the desk of the stage required, and a published sheet told to its students
CREATE OR REPLACE FUNCTION assessment.advance(p_sheet uuid, p_comment text, p_minute text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE v_stage text; v_next text; v_actor uuid; v_office text; v_last uuid; v_missing int;
BEGIN
    v_actor  := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_office := nullif(current_setting('moaum.actor_office', true), '');
    SELECT stage INTO v_stage FROM assessment.score_sheet WHERE id = p_sheet FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no score sheet %', p_sheet USING ERRCODE = 'no_data_found';
    END IF;
    v_next := assessment.stage_after(v_stage);
    IF v_next IS NULL THEN
        RAISE EXCEPTION 'this sheet is published; there is no stage after publication'
            USING ERRCODE = 'check_violation';
    END IF;
    PERFORM assessment.require_stage_desk(v_stage, v_office, CASE WHEN v_stage = 'ENTRY' THEN 'submitted' ELSE 'approved' END);
    IF v_stage = 'ENTRY' THEN
        -- a sheet leaves the lecturer only when every candidate on its roster has an outcome (I-RES-4)
        SELECT count(*) INTO v_missing
          FROM assessment.sheet_candidates(p_sheet) c
         WHERE NOT EXISTS (SELECT 1 FROM assessment.score sc WHERE sc.sheet_id = p_sheet AND sc.student_id = c.student_id);
        IF v_missing > 0 THEN
            RAISE EXCEPTION '% registered candidate(s) on this sheet have no mark and no outcome', v_missing
                USING ERRCODE = 'check_violation',
                      HINT = 'Every candidate on the register is graded, absent, withheld, incomplete, malpractice or exempted. A blank is not an outcome.';
        END IF;
    END IF;
    SELECT d.actor_id INTO v_last FROM assessment.decision d
     WHERE d.sheet_id = p_sheet AND d.kind IN ('SUBMIT','ADVANCE')
     ORDER BY d.decided_at DESC LIMIT 1;
    IF v_last IS NOT NULL AND v_last = v_actor THEN
        RAISE EXCEPTION 'you approved the previous stage of this sheet; another desk must approve this one'
            USING ERRCODE = 'check_violation',
                  HINT = 'BR-006. The system refuses two consecutive stages by one person even where one person holds both offices.';
    END IF;
    IF v_next = 'PUBLISHED' AND (p_minute IS NULL OR btrim(p_minute) = '') THEN
        RAISE EXCEPTION 'a result reaches a student on the Senate minute that approved it, and none was cited'
            USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO assessment.decision (id, sheet_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
    VALUES (gen_random_uuid(), p_sheet, v_stage, v_next,
            CASE WHEN v_stage = 'ENTRY' THEN 'SUBMIT' ELSE 'ADVANCE' END, v_actor, v_office, p_comment);
    UPDATE assessment.score_sheet
       SET stage = v_next,
           submitted_at = CASE WHEN v_stage = 'ENTRY' THEN now() ELSE submitted_at END,
           senate_minute = CASE WHEN v_next = 'PUBLISHED' THEN p_minute ELSE senate_minute END,
           published_at  = CASE WHEN v_next = 'PUBLISHED' THEN now() ELSE published_at END,
           engine_version = CASE WHEN v_next = 'PUBLISHED' THEN 'GpaCalculator 2.1' ELSE engine_version END
     WHERE id = p_sheet;
    IF v_next = 'PUBLISHED' THEN
        PERFORM assessment.tell_published(p_sheet);
    END IF;
    RETURN v_next;
END;
$$;

-- V013's return, by the desk whose stage the sheet is at
CREATE OR REPLACE FUNCTION assessment.return_sheet(p_sheet uuid, p_comment text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE v_stage text; v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    SELECT stage INTO v_stage FROM assessment.score_sheet WHERE id = p_sheet FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no score sheet %', p_sheet USING ERRCODE = 'no_data_found';
    END IF;
    IF v_stage IN ('ENTRY','PUBLISHED') THEN
        RAISE EXCEPTION 'a sheet at % is not returned', lower(v_stage) USING ERRCODE = 'check_violation';
    END IF;
    PERFORM assessment.require_stage_desk(v_stage, v_office, 'returned');
    INSERT INTO assessment.decision (id, sheet_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
    VALUES (gen_random_uuid(), p_sheet, v_stage, 'ENTRY', 'RETURN',
            nullif(current_setting('moaum.actor_id', true), '')::uuid, v_office, p_comment);
    UPDATE assessment.score_sheet SET stage = 'ENTRY', returned_times = returned_times + 1 WHERE id = p_sheet;
END;
$$;

-- ── 2 · held scripts kept within the chain ──────────────────────────────────────────────────────────────────────
ALTER TABLE assessment.held_script ADD COLUMN waiting_since timestamptz NULL;
COMMENT ON COLUMN assessment.held_script.waiting_since IS 'V357: the registration was approved in time while the sheet was with a later desk — the script waits, does not lapse, and is released when the sheet is returned to entry.';

/* a script is held only on a sheet still at entry */
CREATE OR REPLACE FUNCTION assessment.held_script_at_entry()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_stage text;
BEGIN
    SELECT stage INTO v_stage FROM assessment.score_sheet WHERE id = NEW.sheet_id;
    IF v_stage IS DISTINCT FROM 'ENTRY' THEN
        RAISE EXCEPTION 'HELD_SHEET_NOT_AT_ENTRY: the sheet is at %; a script is held only while the sheet is with the lecturer',
            lower(replace(coalesce(v_stage, 'nowhere'), '_', ' ')) USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_held_script_at_entry BEFORE INSERT ON assessment.held_script FOR EACH ROW EXECUTE FUNCTION assessment.held_script_at_entry();

/* V240's release: into a sheet at entry only; a sheet with a later desk keeps the script waiting (approved in time) */
CREATE OR REPLACE FUNCTION assessment.release_held_scripts(p_student uuid, p_offering uuid)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE h record; v_sheet uuid; v_stage text; v_close date; n int := 0; v_version int;
BEGIN
    SELECT id, stage INTO v_sheet, v_stage FROM assessment.score_sheet WHERE offering_id = p_offering;
    IF v_sheet IS NULL THEN RETURN 0; END IF;
    IF NOT EXISTS (SELECT 1 FROM assessment.held_script WHERE sheet_id = v_sheet AND student_id = p_student AND state = 'HELD') THEN RETURN 0; END IF;
    IF NOT assessment.on_roll(p_student, p_offering) THEN RETURN 0; END IF;
    v_close := assessment.held_scripts_close(v_sheet);
    FOR h IN SELECT * FROM assessment.held_script WHERE sheet_id = v_sheet AND student_id = p_student AND state = 'HELD' FOR UPDATE LOOP
        IF h.waiting_since IS NULL AND v_close IS NOT NULL AND v_close < current_date THEN
            UPDATE assessment.held_script SET state = 'LAPSED', lapsed_at = now() WHERE id = h.id;
            CONTINUE;
        END IF;
        IF v_stage <> 'ENTRY' THEN
            -- the sheet is with a later desk (or published): the mark does not land on an approved sheet; it waits
            UPDATE assessment.held_script SET waiting_since = coalesce(waiting_since, now()) WHERE id = h.id;
            CONTINUE;
        END IF;
        SELECT coalesce(max(version), 0) + 1 INTO v_version FROM assessment.score WHERE sheet_id = v_sheet AND student_id = p_student;
        INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, outcome, reason)
        VALUES (v_sheet, p_student, v_version, h.ca, h.exam, h.outcome,
                'Released from a held script: the candidate sat the paper before registering, and the registration is now approved');
        UPDATE assessment.held_script SET state = 'RELEASED', released_at = now() WHERE id = h.id;
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

/* V240's lapse: a script waiting on a returned sheet does not lapse */
CREATE OR REPLACE FUNCTION assessment.lapse_held_scripts()
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    UPDATE assessment.held_script h SET state = 'LAPSED', lapsed_at = now()
     WHERE h.state = 'HELD' AND h.waiting_since IS NULL
       AND (SELECT assessment.held_scripts_close(h.sheet_id)) < current_date;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

/* a sheet returned to entry takes in the scripts waiting on it */
CREATE OR REPLACE FUNCTION assessment.release_waiting_scripts()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE w record;
BEGIN
    FOR w IN SELECT DISTINCT student_id FROM assessment.held_script WHERE sheet_id = NEW.id AND state = 'HELD' AND waiting_since IS NOT NULL LOOP
        PERFORM assessment.release_held_scripts(w.student_id, NEW.offering_id);
    END LOOP;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_score_sheet_release_waiting AFTER UPDATE OF stage ON assessment.score_sheet
    FOR EACH ROW WHEN (NEW.stage = 'ENTRY' AND OLD.stage IS DISTINCT FROM 'ENTRY') EXECUTE FUNCTION assessment.release_waiting_scripts();

-- the held list says which are waiting on the sheet's return
DROP FUNCTION assessment.held_scripts(uuid);
CREATE FUNCTION assessment.held_scripts(p_sheet uuid)
RETURNS TABLE (id uuid, student_id uuid, number text, surname text, other_names text, programme_name text, level int,
               ca int, exam int, outcome text, note text, state text, entered_by text, entered_at timestamptz,
               released_at timestamptz, lapsed_at timestamptz, closes_on date, waiting_since timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT h.id, h.student_id, coalesce(st.matric_no, st.admission_no), st.surname, st.other_names, p.name, st.current_level,
           h.ca, h.exam, h.outcome, h.note, h.state,
           CASE WHEN pe.id IS NULL THEN NULL ELSE pe.surname || ', ' || pe.given_names END,
           h.entered_at, h.released_at, h.lapsed_at, assessment.held_scripts_close(p_sheet), h.waiting_since
      FROM assessment.held_script h
      JOIN people.student st ON st.id = h.student_id
      JOIN ref.programme p ON p.code = st.programme_code
      LEFT JOIN iam.person pe ON pe.id = h.entered_by
     WHERE h.sheet_id = p_sheet
     ORDER BY (h.state = 'HELD') DESC, coalesce(st.matric_no, st.admission_no)
$$;

-- ── 3 · a published result told ─────────────────────────────────────────────────────────────────────────────────
/* each student of a published sheet: an email that the result in the course is published (no grade), and one text a day */
CREATE OR REPLACE FUNCTION assessment.tell_published(p_sheet uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE c record; r record; n int := 0; v_from text;
BEGIN
    SELECT o.course_code, cr.title, o.session, o.semester INTO c
      FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id JOIN catalogue.course cr ON cr.code = o.course_code
     WHERE s.id = p_sheet;
    IF c.course_code IS NULL THEN RETURN 0; END IF;
    v_from := coalesce((SELECT name FROM platform.institution_profile LIMIT 1), 'the University');
    FOR r IN SELECT st.id, st.surname, st.other_names, rc.email, rc.phone
               FROM people.student st LEFT JOIN LATERAL people.student_reach(st.id) rc ON true
              WHERE st.id IN (SELECT DISTINCT sc.student_id FROM assessment.score sc WHERE sc.sheet_id = p_sheet) LOOP
        PERFORM platform.queue_notice('EMAIL', r.email, 'Your result in ' || c.course_code || ' is published',
            'Dear ' || r.surname || ', ' || r.other_names || E',\n\n'
            || 'Your result in ' || c.course_code || ' — ' || c.title || ' (' || c.session || ', '
            || CASE c.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE c.semester::text END || ' semester) has been published on the Senate''s approval. '
            || E'Sign in to the University portal to see it.\n\n'
            || E'If you believe it is wrong, you may raise a result query from the portal.\n\n'
            || v_from || ' — Examinations and Records',
            'student', r.id);
        IF r.phone IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM platform.notice x WHERE x.channel = 'SMS' AND x.about_kind = 'student' AND x.about_id = r.id
               AND x.subject = 'Results published' AND x.created_at >= date_trunc('day', now())) THEN
            PERFORM platform.queue_notice('SMS', r.phone, 'Results published', 'MOAUM: new results of yours are published. Sign in to the portal to see them.', 'student', r.id);
        END IF;
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;
COMMENT ON FUNCTION assessment.tell_published(uuid) IS 'V357: a published sheet told to each of its students — an email per course (no grade), one text a day.';

COMMIT;
