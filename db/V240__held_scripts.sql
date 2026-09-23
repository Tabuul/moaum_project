-- ═══════════════════════════════════════════════════════════════════════════
-- V240 — a script from a candidate not on the roll is held, and released by registration
--
--   A student who owes fees is held at the Bursary's clearance, never
--   registers, and is not on the score sheet's roll; yet some sit the paper.
--   The lecturer has a script and a mark and nowhere to keep them. Now the
--   mark is held against the sheet — not on the roll, not graded, not on the
--   broadsheet — until the student pays, registers the course and the
--   registration is approved. At that moment the register releases the held
--   script into the sheet as the candidate's mark, saying so. A held script
--   not released by the semester's late-registration closing date lapses:
--   it stays on record and never grades.
--
--   The roll's rule does not change: a candidate is on it by an approved
--   registration. The held script only stops a real script being lost.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE assessment.held_script (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sheet_id     uuid NOT NULL REFERENCES assessment.score_sheet(id),
    student_id   uuid NOT NULL REFERENCES people.student(id),
    ca           int  NULL,
    exam         int  NULL,
    outcome      text NOT NULL DEFAULT 'GRADED',
    note         text NULL,
    entered_by   uuid NOT NULL,
    entered_at   timestamptz NOT NULL DEFAULT now(),
    state        text NOT NULL DEFAULT 'HELD',
    released_at  timestamptz NULL,
    lapsed_at    timestamptz NULL,
    withdrawn_at timestamptz NULL,
    CONSTRAINT ck_held_state   CHECK (state IN ('HELD','RELEASED','LAPSED','WITHDRAWN')),
    CONSTRAINT ck_held_outcome CHECK (outcome IN ('GRADED','ABSENT','WITHHELD','INCOMPLETE','MALPRACTICE','EXEMPTED')),
    CONSTRAINT ck_held_graded  CHECK (outcome <> 'GRADED' OR (ca IS NOT NULL AND exam IS NOT NULL)),
    CONSTRAINT ck_held_range   CHECK ((ca IS NULL OR ca BETWEEN 0 AND 100) AND (exam IS NULL OR exam BETWEEN 0 AND 100)
                                      AND (ca IS NULL OR exam IS NULL OR ca + exam <= 100))
);
CREATE UNIQUE INDEX ux_held_script_open ON assessment.held_script (sheet_id, student_id) WHERE state = 'HELD';
CREATE INDEX ix_held_script_student ON assessment.held_script (student_id) WHERE state = 'HELD';
COMMENT ON TABLE assessment.held_script IS
  'A mark from a candidate who sat the paper without being on the roll, held until an approved registration releases it into the sheet, or the late-registration date passes and it lapses.';
SELECT audit.attach('assessment.held_script');

-- ── the closing date: the semester's late-registration date, if the Registry set one ──
CREATE OR REPLACE FUNCTION assessment.held_scripts_close(p_sheet uuid)
RETURNS date
LANGUAGE sql STABLE AS $$
    SELECT sem.late_registration_closes
      FROM assessment.score_sheet s
      JOIN catalogue.offering o ON o.id = s.offering_id
      JOIN policy.semester sem ON sem.session = o.session AND sem.number = o.semester
     WHERE s.id = p_sheet
$$;

-- ── is this student on this offering's roll? the roll's own rule ──
CREATE OR REPLACE FUNCTION assessment.on_roll(p_student uuid, p_offering uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM registration.entry e
          JOIN registration.course_registration r ON r.id = e.registration_id
         WHERE e.offering_id = p_offering AND e.status = 'APPROVED'
           AND r.student_id = p_student AND r.status IN ('APPROVED','LOCKED'))
$$;

-- ── hold a script ──
CREATE OR REPLACE FUNCTION assessment.hold_script(p_sheet uuid, p_number text, p_ca int, p_exam int, p_outcome text, p_note text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_student uuid; v_offering uuid; v_code text; v_ca_max int; v_close date; v_outcome text; v_id uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a script is held by a person' USING ERRCODE = '23514'; END IF;
    SELECT o.id, c.code, c.ca_max INTO v_offering, v_code, v_ca_max
      FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id JOIN catalogue.course c ON c.code = o.course_code
     WHERE s.id = p_sheet;
    IF v_offering IS NULL THEN RAISE EXCEPTION 'no score sheet %', p_sheet USING ERRCODE = 'no_data_found'; END IF;
    SELECT st.id INTO v_student FROM people.student st
     WHERE upper(btrim(p_number)) IN (upper(st.matric_no), upper(st.admission_no))
     ORDER BY (upper(st.matric_no) = upper(btrim(p_number))) DESC LIMIT 1;
    IF v_student IS NULL THEN
        RAISE EXCEPTION 'no student on the register is numbered %', btrim(p_number)
            USING ERRCODE = '23514', HINT = 'Check the number on the script against the register; a candidate the University does not know cannot be held.';
    END IF;
    IF assessment.on_roll(v_student, v_offering) THEN
        RAISE EXCEPTION '% is on the roll of %; enter the mark on the sheet', btrim(p_number), v_code
            USING ERRCODE = '23514', HINT = 'A held script is for a candidate who is not registered for the course.';
    END IF;
    v_close := assessment.held_scripts_close(p_sheet);
    IF v_close IS NOT NULL AND v_close < current_date THEN
        RAISE EXCEPTION 'late registration for this semester closed on %; a script can no longer be held for %', to_char(v_close, 'DD Month YYYY'), v_code
            USING ERRCODE = '23514', HINT = 'The Registry sets the late-registration date on the calendar.';
    END IF;
    v_outcome := coalesce(nullif(upper(btrim(p_outcome)), ''), 'GRADED');
    IF v_outcome = 'GRADED' THEN
        IF p_ca IS NULL OR p_exam IS NULL THEN RAISE EXCEPTION 'a graded script carries both the CA and the examination mark' USING ERRCODE = '23514'; END IF;
        IF p_ca > v_ca_max THEN RAISE EXCEPTION 'continuous assessment in % is out of %, not %', v_code, v_ca_max, p_ca USING ERRCODE = '23514'; END IF;
        IF p_exam > 100 - v_ca_max THEN RAISE EXCEPTION 'the examination in % is out of %, not %', v_code, 100 - v_ca_max, p_exam USING ERRCODE = '23514'; END IF;
    END IF;
    INSERT INTO assessment.held_script (sheet_id, student_id, ca, exam, outcome, note, entered_by)
    VALUES (p_sheet, v_student, CASE WHEN v_outcome = 'GRADED' THEN p_ca END, CASE WHEN v_outcome = 'GRADED' THEN p_exam END, v_outcome, nullif(btrim(p_note), ''), v_actor)
    RETURNING id INTO v_id;
    RETURN v_id;
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'a script is already held for % on %', btrim(p_number), v_code USING ERRCODE = '23514',
        HINT = 'Withdraw the held script first if the mark on it is wrong.';
END $$;

-- ── release: the student is now on the roll, so the held script becomes the mark ──
CREATE OR REPLACE FUNCTION assessment.release_held_scripts(p_student uuid, p_offering uuid)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE h record; v_sheet uuid; v_close date; n int := 0; v_version int;
BEGIN
    SELECT id INTO v_sheet FROM assessment.score_sheet WHERE offering_id = p_offering;
    IF v_sheet IS NULL THEN RETURN 0; END IF;
    IF NOT EXISTS (SELECT 1 FROM assessment.held_script WHERE sheet_id = v_sheet AND student_id = p_student AND state = 'HELD') THEN RETURN 0; END IF;
    IF NOT assessment.on_roll(p_student, p_offering) THEN RETURN 0; END IF;
    v_close := assessment.held_scripts_close(v_sheet);
    FOR h IN SELECT * FROM assessment.held_script WHERE sheet_id = v_sheet AND student_id = p_student AND state = 'HELD' FOR UPDATE LOOP
        IF v_close IS NOT NULL AND v_close < current_date THEN
            UPDATE assessment.held_script SET state = 'LAPSED', lapsed_at = now() WHERE id = h.id;
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

-- an approved entry, or a registration reaching approval, releases whatever is held for that student
CREATE OR REPLACE FUNCTION assessment.trg_entry_releases_held() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_student uuid;
BEGIN
    IF NEW.status = 'APPROVED' THEN
        SELECT student_id INTO v_student FROM registration.course_registration WHERE id = NEW.registration_id;
        PERFORM assessment.release_held_scripts(v_student, NEW.offering_id);
    END IF;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_entry_releases_held
    AFTER INSERT OR UPDATE OF status ON registration.entry
    FOR EACH ROW EXECUTE FUNCTION assessment.trg_entry_releases_held();

CREATE OR REPLACE FUNCTION assessment.trg_registration_releases_held() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE e record;
BEGIN
    IF NEW.status IN ('APPROVED','LOCKED') AND (TG_OP = 'INSERT' OR OLD.status NOT IN ('APPROVED','LOCKED')) THEN
        FOR e IN SELECT offering_id FROM registration.entry WHERE registration_id = NEW.id AND status = 'APPROVED' LOOP
            PERFORM assessment.release_held_scripts(NEW.student_id, e.offering_id);
        END LOOP;
    END IF;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_registration_releases_held
    AFTER INSERT OR UPDATE OF status ON registration.course_registration
    FOR EACH ROW EXECUTE FUNCTION assessment.trg_registration_releases_held();

-- ── lapse: past the closing date, a held script stays on record and never grades ──
CREATE OR REPLACE FUNCTION assessment.lapse_held_scripts()
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    UPDATE assessment.held_script h SET state = 'LAPSED', lapsed_at = now()
     WHERE h.state = 'HELD'
       AND (SELECT assessment.held_scripts_close(h.sheet_id)) < current_date;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

-- ── withdraw: the lecturer takes back a held script entered wrongly ──
CREATE OR REPLACE FUNCTION assessment.withdraw_held_script(p_id uuid)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE assessment.held_script SET state = 'WITHDRAWN', withdrawn_at = now() WHERE id = p_id AND state = 'HELD';
    IF NOT FOUND THEN RAISE EXCEPTION 'only a script still held is withdrawn' USING ERRCODE = '23514'; END IF;
END $$;

-- ── the sheet's held scripts, for the desk ──
CREATE OR REPLACE FUNCTION assessment.held_scripts(p_sheet uuid)
RETURNS TABLE (id uuid, student_id uuid, number text, surname text, other_names text, programme_name text, level int,
               ca int, exam int, outcome text, note text, state text, entered_by text, entered_at timestamptz,
               released_at timestamptz, lapsed_at timestamptz, closes_on date)
LANGUAGE sql STABLE AS $$
    SELECT h.id, h.student_id, coalesce(st.matric_no, st.admission_no), st.surname, st.other_names, p.name, st.current_level,
           h.ca, h.exam, h.outcome, h.note, h.state,
           CASE WHEN pe.id IS NULL THEN NULL ELSE pe.surname || ', ' || pe.given_names END,
           h.entered_at, h.released_at, h.lapsed_at, assessment.held_scripts_close(p_sheet)
      FROM assessment.held_script h
      JOIN people.student st ON st.id = h.student_id
      JOIN ref.programme p ON p.code = st.programme_code
      LEFT JOIN iam.person pe ON pe.id = h.entered_by
     WHERE h.sheet_id = p_sheet
     ORDER BY (h.state = 'HELD') DESC, coalesce(st.matric_no, st.admission_no)
$$;

-- ── the Bursar's list: students with a held script, and what they owe ──
CREATE OR REPLACE FUNCTION assessment.held_scripts_owing()
RETURNS TABLE (student_id uuid, number text, surname text, other_names text, programme_name text, level int, session text,
               scripts bigint, courses text, closes_on date, due numeric, paid numeric, balance numeric)
LANGUAGE sql STABLE AS $$
    WITH h AS (
        SELECT hs.student_id, o.session, count(*) AS scripts,
               string_agg(o.course_code, ', ' ORDER BY o.course_code) AS courses,
               min(assessment.held_scripts_close(hs.sheet_id)) AS closes_on
          FROM assessment.held_script hs
          JOIN assessment.score_sheet s ON s.id = hs.sheet_id
          JOIN catalogue.offering o ON o.id = s.offering_id
         WHERE hs.state = 'HELD'
         GROUP BY hs.student_id, o.session
    )
    SELECT h.student_id, coalesce(st.matric_no, st.admission_no), st.surname, st.other_names, p.name, st.current_level, h.session,
           h.scripts, h.courses, h.closes_on, pos.due, pos.paid, pos.balance
      FROM h
      JOIN people.student st ON st.id = h.student_id
      JOIN ref.programme p ON p.code = st.programme_code
      LEFT JOIN LATERAL finance.position(h.student_id, h.session) pos ON true
     ORDER BY h.session DESC, st.surname, st.other_names
$$;

COMMIT;
