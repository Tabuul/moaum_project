-- ═══════════════════════════════════════════════════════════════════════════
-- V354 — The JUPEB session calendar, the lecture rooms, the lectures due from the timetable, and clearance for the examination
--
--   · The calendar (jupeb.calendar_event). The Board's calendar for 2026/2027, as the JUPEB Office gave it (2026-2027 JUPEB
--     SESSION CALENDAR.pdf, 36 events: recruitment, teaching from 28 September 2026, the Board's registration of candidates
--     13 November 2026 – 29 January 2027, the examinations 26 July – 6 August 2027, results 7 September 2027 …), with the
--     University's own JUPEB events beside it. A session's calendar is copied forward as the plan of the next (a year on,
--     marked planned until confirmed). A few events mark what the portal works from: teaching starts (the first semester),
--     the second semester starts (the University's own — the Board's calendar leaves it to each Foundation School, so it is
--     never invented here), the Board's registration of candidates, the examinations, the results.
--   · The rooms (jupeb.room): a list to choose from, so LR8 and "LR 8" are one room; a slot names its room, and a room on no
--     list is refused. A room's capacity, when given, is weighed against the students a lecture has.
--   · A semester's timetable copied into another (the next semester, or the next session): into the second semester each
--     course moves on to the course of the same place there (GRY 001 → GRY 003, GRY 002 → GRY 004; MAT 002 → MAT 004A, with
--     MAT 004B noted).
--   · A notice to the students of one subject (announcement audience SUBJECT, a class too when given): the office's notice of
--     a timetable change, and a lecturer's to the students of the subjects they teach.
--   · The lectures due: every slot of the semester on every teaching day, from the day teaching starts (and the slot was on the
--     timetable) until the examinations — recorded (a register saved), open, not held (with the reason) or missed. A register
--     is now one lecture: a subject may have two in a day (a lecture and a practical), each with its own register, opened from
--     the slot; a register opened by hand for the day still stands for it.
--   · Clearance for the examination: three subjects registered (the option chosen of an either/or subject), a passport
--     photograph, the required documents verified, the school fee paid in full, attendance at the minimum (when one is set —
--     never assumed), and the examination number from the Board — each student's outstanding items said plainly.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'jupeb', true),
       set_config('moaum.reason', 'V354: the JUPEB calendar, rooms, lectures due and examination clearance', true);

-- ── 1 · the session calendar ───────────────────────────────────────────────────────────────────────────────────
CREATE TABLE jupeb.calendar_event (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session       text NOT NULL CHECK (session ~ '^[0-9]{4}/[0-9]{4}$'),
    ord           int NOT NULL DEFAULT 0,
    starts_on     date NOT NULL,
    ends_on       date NULL,
    title         text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 300),
    deadline_on   date NULL,
    deadline_note text NULL CHECK (deadline_note IS NULL OR length(deadline_note) <= 300),
    source        text NOT NULL DEFAULT 'SCHOOL' CHECK (source IN ('BOARD', 'SCHOOL')),
    marker        text NULL CHECK (marker IN ('TEACHING_STARTS', 'SEMESTER_2_STARTS', 'BOARD_REGISTRATION', 'LECTURE_MONITORING', 'CA_SUBMISSION',
                                              'CBT_MOCK', 'EXAMINATIONS', 'RESULTS')),
    for_students  boolean NOT NULL DEFAULT false,
    planned       boolean NOT NULL DEFAULT false,
    created_by    uuid NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    removed_at    timestamptz NULL,
    removed_by    uuid NULL,
    CONSTRAINT ck_jupeb_cal_span CHECK (ends_on IS NULL OR ends_on >= starts_on)
);
CREATE INDEX ix_jupeb_cal_session ON jupeb.calendar_event (session, starts_on) WHERE removed_at IS NULL;
CREATE UNIQUE INDEX ux_jupeb_cal_marker ON jupeb.calendar_event (session, marker) WHERE marker IS NOT NULL AND removed_at IS NULL;
SELECT audit.attach('jupeb.calendar_event');
COMMENT ON TABLE jupeb.calendar_event IS 'V354: an event of a JUPEB session''s calendar — the Board''s (its published calendar) or the University''s own; a marker names the events the portal works from; planned, copied forward from the session before until confirmed; removed, never deleted.';

/* the day an event marked so starts, in a session (none: NULL) */
CREATE OR REPLACE FUNCTION jupeb.calendar_date(p_session text, p_marker text)
RETURNS date LANGUAGE sql STABLE AS $$
    SELECT starts_on FROM jupeb.calendar_event WHERE session = p_session AND marker = p_marker AND removed_at IS NULL
$$;

/* the semester a day falls in: the second once the second semester has started by the calendar, else the first */
CREATE OR REPLACE FUNCTION jupeb.current_semester(p_session text DEFAULT NULL, p_day date DEFAULT NULL)
RETURNS int LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN jupeb.calendar_date(coalesce(p_session, jupeb.current_session()), 'SEMESTER_2_STARTS')
                     <= coalesce(p_day, (now() AT TIME ZONE 'Africa/Lagos')::date) THEN 2 ELSE 1 END
$$;

/* every year a text names (20xx) moved on by so many years: "the 2027 examination" → "the 2028 examination", "2026/2027" → "2027/2028" */
CREATE OR REPLACE FUNCTION jupeb.shift_years(p_text text, p_years int)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE done text := ''; rest text := p_text; m text[];
BEGIN
    IF p_text IS NULL OR p_years = 0 THEN RETURN p_text; END IF;
    LOOP
        m := regexp_match(rest, '^(.*?)\m(20[0-9]{2})\M(.*)$', 's');
        EXIT WHEN m IS NULL;
        done := done || m[1] || (m[2]::int + p_years)::text;
        rest := m[3];
    END LOOP;
    RETURN done || rest;
END $$;

/* a session's calendar copied forward as the plan of a later one: every date and every year named a year on for each year between
   them, planned until the office confirms it against the Board's own calendar */
CREATE OR REPLACE FUNCTION jupeb.copy_calendar(p_from text, p_to text, p_actor uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE k int; years int := substr(p_to, 1, 4)::int - substr(p_from, 1, 4)::int;
BEGIN
    IF years <= 0 THEN RAISE EXCEPTION 'JUPEB_CALENDAR_COPY: a calendar is copied forward, into a later session' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM jupeb.calendar_event WHERE session = p_from AND removed_at IS NULL) THEN
        RAISE EXCEPTION 'JUPEB_CALENDAR_EMPTY: % has no calendar to copy', p_from USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM jupeb.calendar_event WHERE session = p_to AND removed_at IS NULL) THEN
        RAISE EXCEPTION 'JUPEB_CALENDAR_EXISTS: % already has its calendar; edit it there', p_to USING ERRCODE = '23514';
    END IF;
    INSERT INTO jupeb.calendar_event (session, ord, starts_on, ends_on, title, deadline_on, deadline_note, source, marker, for_students, planned, created_by)
    SELECT p_to, e.ord, (e.starts_on + make_interval(years => years))::date, (e.ends_on + make_interval(years => years))::date,
           jupeb.shift_years(e.title, years), (e.deadline_on + make_interval(years => years))::date, jupeb.shift_years(e.deadline_note, years),
           e.source, e.marker, e.for_students, true, p_actor
      FROM jupeb.calendar_event e WHERE e.session = p_from AND e.removed_at IS NULL;
    GET DIAGNOSTICS k = ROW_COUNT;
    RETURN k;
END $$;

-- the Board's calendar for 2026/2027
INSERT INTO jupeb.calendar_event (session, ord, starts_on, ends_on, title, deadline_on, deadline_note, source, marker, for_students)
SELECT '2026/2027', v.ord, v.s::date, v.e::date, v.title, v.d::date, v.note, 'BOARD', v.marker, v.students FROM (VALUES
    (1,  '2026-08-17', '2026-10-30', 'Recruitment of students in all universities for 2026/2027 session', NULL, NULL, NULL, false),
    (2,  '2026-09-28', NULL, 'Teaching commences in all universities', '2026-09-28', 'Every University is expected to have commenced teaching by 28 September 2026', 'TEACHING_STARTS', true),
    (3,  '2026-10-01', '2026-10-31', 'Training on the use of the new Central Registration Portal (CRP)', NULL, NULL, NULL, false),
    (4,  '2026-10-12', '2026-10-30', 'Submission of JUPEB Foundation School academic calendar for 2026/2027 session', '2026-10-30', NULL, NULL, false),
    (5,  '2026-11-03', '2026-12-31', 'Call for test items', '2026-12-31', NULL, NULL, false),
    (6,  '2026-11-13', '2027-01-29', 'Registration of candidates for the 2027 examination via the online Registration Portal', '2027-01-29', 'Registration Portal closes 29 January 2027', 'BOARD_REGISTRATION', false),
    (7,  '2026-12-10', NULL, 'Governing Board meeting', NULL, NULL, NULL, false),
    (8,  '2027-02-01', '2027-02-12', 'Deletion of unwanted candidates'' names and third-party data alignments', '2027-02-12', NULL, NULL, false),
    (9,  '2027-02-13', '2027-02-25', 'Third-party data alignment with a penalty of ₦50,000', '2027-02-25', NULL, NULL, false),
    (10, '2027-02-26', NULL, 'Upload of all registered candidates on the JAMB portal', NULL, NULL, NULL, false),
    (11, '2027-02-01', '2027-02-06', 'Moderation exercise', NULL, NULL, NULL, false),
    (12, '2027-03-04', NULL, 'Governing Board meeting', NULL, NULL, NULL, false),
    (13, '2027-03-08', '2027-04-16', 'Monitoring of lectures', NULL, NULL, 'LECTURE_MONITORING', false),
    (14, '2027-05-03', NULL, 'Release of the 2027 examinations timetable', NULL, NULL, NULL, true),
    (15, '2027-05-05', NULL, 'Request for supervisors from Programme Directors of partnering universities', '2027-05-17', NULL, NULL, false),
    (16, '2027-05-10', NULL, 'Request for invigilators from Programme Directors', '2027-06-07', NULL, NULL, false),
    (17, '2027-06-14', NULL, 'Request for submission of candidates'' continuous assessment scores from JFS', '2027-06-25', NULL, 'CA_SUBMISSION', false),
    (18, '2027-06-14', NULL, 'Governing Board meeting', NULL, NULL, NULL, false),
    (19, '2027-06-16', NULL, 'Request for assessors', '2027-07-03', NULL, NULL, false),
    (20, '2027-06-14', '2027-06-21', 'Appointment of supervisors', NULL, NULL, NULL, false),
    (21, '2027-06-24', '2027-06-29', 'Circulation of the invigilators'' schedule to Programme Directors', NULL, NULL, NULL, false),
    (22, '2027-06-28', '2027-06-29', 'Communication of instructions on practicals to JFS', NULL, NULL, NULL, false),
    (23, '2027-06-28', '2027-07-02', 'Appointment of technical officers for CBT', NULL, NULL, NULL, false),
    (24, '2027-06-28', '2027-07-15', 'Auto testing for all CBT centres', NULL, NULL, NULL, false),
    (25, '2027-07-05', '2027-07-07', 'Appointment of assessors, checkers and CCTV reviewers', NULL, NULL, NULL, false),
    (26, '2027-07-06', NULL, 'Programme Directors meeting', NULL, NULL, NULL, false),
    (27, '2027-07-22', NULL, 'Briefing of technical officers and supervisors', NULL, NULL, NULL, false),
    (28, '2027-07-22', '2027-07-24', 'CBT mock examinations', NULL, NULL, 'CBT_MOCK', true),
    (29, '2027-07-26', '2027-08-06', '2027 examinations in all universities', NULL, NULL, 'EXAMINATIONS', true),
    (30, '2027-07-29', NULL, 'Briefing of invigilators at the universities by supervisors', NULL, NULL, NULL, false),
    (31, '2027-08-10', '2027-08-20', 'Conference marking exercise', NULL, NULL, NULL, false),
    (32, '2027-08-11', '2027-08-26', 'Checking of marked scripts', NULL, NULL, NULL, false),
    (33, '2027-08-23', '2027-08-31', 'Processing of results', NULL, NULL, NULL, false),
    (34, '2027-09-01', NULL, 'Academic Board meeting for the consideration of results', NULL, NULL, NULL, false),
    (35, '2027-09-02', NULL, 'Governing Board meeting for the approval of results', NULL, NULL, NULL, false),
    (36, '2027-09-07', NULL, 'Release of results — end of the academic year', NULL, NULL, 'RESULTS', true)
  ) AS v(ord, s, e, title, d, note, marker, students)
 WHERE NOT EXISTS (SELECT 1 FROM jupeb.calendar_event WHERE session = '2026/2027');

-- ── 2 · the rooms ────────────────────────────────────────────────────────────────────────────────────────────────
/* a room's code as the list keeps it: upper case, no spaces (LR 8, lr8 → LR8) */
CREATE OR REPLACE FUNCTION jupeb.room_code(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT nullif(upper(regexp_replace(coalesce(p, ''), '\s', '', 'g')), '') $$;

CREATE TABLE jupeb.room (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code       text NOT NULL CHECK (code ~ '^[A-Z0-9][A-Z0-9/&().-]{0,39}$'),
    name       text NULL CHECK (name IS NULL OR length(btrim(name)) BETWEEN 2 AND 120),
    kind       text NOT NULL DEFAULT 'LECTURE' CHECK (kind IN ('LECTURE', 'LAB', 'HALL', 'OTHER')),
    capacity   int NULL CHECK (capacity IS NULL OR capacity BETWEEN 1 AND 5000),
    active     boolean NOT NULL DEFAULT true,
    created_by uuid NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_jupeb_room UNIQUE (code)
);
SELECT audit.attach('jupeb.room');
COMMENT ON TABLE jupeb.room IS 'V354: a room or laboratory JUPEB lectures are held in — chosen from this list, so one room is never written two ways; its capacity, when given, is weighed against the students of a lecture; closed, never deleted.';

/* a room's code kept as the list keeps it */
CREATE OR REPLACE FUNCTION jupeb.room_kept()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.code := jupeb.room_code(NEW.code);
    NEW.updated_at := now();
    RETURN NEW;
END $$;
CREATE TRIGGER trg_jupeb_room BEFORE INSERT OR UPDATE ON jupeb.room FOR EACH ROW EXECUTE FUNCTION jupeb.room_kept();

/* a room renamed: once the new code is stored, the lectures that name the room say it */
CREATE OR REPLACE FUNCTION jupeb.room_renamed()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE jupeb.timetable_slot SET venue = NEW.code WHERE room_id = NEW.id;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_jupeb_room_renamed AFTER UPDATE OF code ON jupeb.room FOR EACH ROW WHEN (NEW.code IS DISTINCT FROM OLD.code) EXECUTE FUNCTION jupeb.room_renamed();

INSERT INTO jupeb.room (code, kind)
SELECT DISTINCT jupeb.room_code(venue), CASE WHEN jupeb.room_code(venue) LIKE 'LAB%' THEN 'LAB' ELSE 'LECTURE' END
  FROM jupeb.timetable_slot WHERE jupeb.room_code(venue) ~ '^[A-Z0-9][A-Z0-9/&().-]{0,39}$'
ON CONFLICT (code) DO NOTHING;

ALTER TABLE jupeb.timetable_slot ADD COLUMN room_id uuid NULL REFERENCES jupeb.room(id);
UPDATE jupeb.timetable_slot t SET room_id = r.id FROM jupeb.room r WHERE r.code = jupeb.room_code(t.venue) AND t.room_id IS NULL;

/* V353's rule (a course of the subject, in its semester) and V351's (a room, or a named class, never twice in an hour) — now a
   room on the list: the room chosen, or a venue that is one of the list's rooms; a closed room takes no new lecture */
CREATE OR REPLACE FUNCTION jupeb.slot_clash()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE u jupeb.subject_unit; rm jupeb.room;
BEGIN
    IF NEW.course_code IS NOT NULL THEN NEW.course_code := upper(regexp_replace(btrim(NEW.course_code), '^([A-Z/]+) ?([0-9]{3}[A-Z]?)$', '\1 \2', 'i')); END IF;
    IF TG_OP = 'INSERT' OR NEW.course_code IS DISTINCT FROM OLD.course_code OR NEW.subject_id IS DISTINCT FROM OLD.subject_id OR NEW.semester IS DISTINCT FROM OLD.semester THEN
        NEW.unit_id := NULL;
        IF NEW.course_code IS NOT NULL AND EXISTS (SELECT 1 FROM jupeb.subject_unit x WHERE x.subject_id = NEW.subject_id) THEN
            SELECT * INTO u FROM jupeb.subject_unit x WHERE x.subject_id = NEW.subject_id AND x.code = NEW.course_code;
            IF u.id IS NULL THEN
                RAISE EXCEPTION 'JUPEB_SLOT_COURSE: % is not a course of % (its courses are %)', NEW.course_code, (SELECT title FROM jupeb.subject WHERE id = NEW.subject_id),
                    (SELECT string_agg(x.code, ', ' ORDER BY x.semester NULLS LAST, x.ord, x.code) FROM jupeb.subject_unit x WHERE x.subject_id = NEW.subject_id)
                    USING ERRCODE = '23514';
            END IF;
            IF u.semester IS NOT NULL AND u.semester <> NEW.semester THEN
                RAISE EXCEPTION 'JUPEB_SLOT_SEMESTER: % is taught in the % semester', u.code, CASE u.semester WHEN 1 THEN 'first' ELSE 'second' END USING ERRCODE = '23514';
            END IF;
            NEW.unit_id := u.id;
        END IF;
    END IF;
    IF NEW.room_id IS NULL AND jupeb.room_code(NEW.venue) IS NOT NULL THEN
        SELECT * INTO rm FROM jupeb.room WHERE code = jupeb.room_code(NEW.venue);
        IF rm.id IS NULL THEN
            RAISE EXCEPTION 'JUPEB_ROOM_UNKNOWN: % is not on the list of rooms', btrim(NEW.venue) USING ERRCODE = '23514',
                HINT = 'Add the room to the list of rooms first, or choose one of the list.';
        END IF;
        NEW.room_id := rm.id;
    ELSIF NEW.room_id IS NOT NULL THEN
        SELECT * INTO rm FROM jupeb.room WHERE id = NEW.room_id;
    END IF;
    IF rm.id IS NOT NULL AND NOT rm.active AND (TG_OP = 'INSERT' OR NEW.room_id IS DISTINCT FROM OLD.room_id) THEN
        RAISE EXCEPTION 'JUPEB_ROOM_CLOSED: % is closed and takes no new lecture', rm.code USING ERRCODE = '23514';
    END IF;
    NEW.venue := rm.code;
    IF NEW.active AND EXISTS (
        SELECT 1 FROM jupeb.timetable_slot s
         WHERE s.id <> NEW.id AND s.active AND s.session = NEW.session AND s.semester = NEW.semester AND s.weekday = NEW.weekday
           AND s.starts_at < NEW.ends_at AND NEW.starts_at < s.ends_at
           AND ((NEW.room_id IS NOT NULL AND s.room_id = NEW.room_id) OR (NEW.class_id IS NOT NULL AND s.class_id = NEW.class_id))) THEN
        RAISE EXCEPTION 'JUPEB_SLOT_CLASH: the room (or the class) already has a lecture at that time' USING ERRCODE = '23514';
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END $$;

-- ── 3 · a semester's timetable copied into another ───────────────────────────────────────────────────────────────
/* every slot of a session's semester copied into another session or semester that has none: classes found again by name in
   another session; into another semester each course moves on to the course in the same place there (the first course of the
   semester to the first, the second to the second), an alternative (MAT 004A/B) noted; a course with none in the same place is
   left for the office to choose. Returns how many were copied. */
CREATE OR REPLACE FUNCTION jupeb.copy_timetable(p_session text, p_semester int, p_to_session text, p_to_semester int, p_actor uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE t jupeb.timetable_slot; me jupeb.subject_unit; target jupeb.subject_unit; k int := 0; pos int; v_code text; v_note text; v_class uuid; others text;
BEGIN
    IF p_session = p_to_session AND p_semester = p_to_semester THEN
        RAISE EXCEPTION 'JUPEB_TIMETABLE_COPY: choose another semester or session to copy into' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM jupeb.timetable_slot WHERE session = p_session AND semester = p_semester AND active) THEN
        RAISE EXCEPTION 'JUPEB_TIMETABLE_EMPTY: the % semester of % has no lectures to copy', CASE p_semester WHEN 1 THEN 'first' ELSE 'second' END, p_session USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM jupeb.timetable_slot WHERE session = p_to_session AND semester = p_to_semester AND active) THEN
        RAISE EXCEPTION 'JUPEB_TIMETABLE_NOT_EMPTY: the % semester of % already has lectures; copy only into an empty timetable',
            CASE p_to_semester WHEN 1 THEN 'first' ELSE 'second' END, p_to_session USING ERRCODE = '23514';
    END IF;
    FOR t IN SELECT * FROM jupeb.timetable_slot WHERE session = p_session AND semester = p_semester AND active ORDER BY weekday, starts_at LOOP
        v_code := t.course_code; v_note := t.note; target := NULL; others := NULL; me := NULL;
        IF t.unit_id IS NOT NULL AND p_to_semester <> p_semester THEN
            SELECT * INTO me FROM jupeb.subject_unit WHERE id = t.unit_id;
            SELECT x.rn INTO pos FROM (SELECT u.id, row_number() OVER (ORDER BY u.ord, u.code) AS rn FROM jupeb.subject_unit u
                                        WHERE u.subject_id = me.subject_id AND u.semester = me.semester AND u.board_subject_id IS NOT DISTINCT FROM me.board_subject_id) x
             WHERE x.id = me.id;
            SELECT u.* INTO target FROM jupeb.subject_unit u JOIN (
                    SELECT y.id, row_number() OVER (ORDER BY y.ord, y.code) AS rn FROM jupeb.subject_unit y
                     WHERE y.subject_id = me.subject_id AND y.semester = p_to_semester AND y.board_subject_id IS NOT DISTINCT FROM me.board_subject_id AND y.areas IS NULL) x
                 ON x.id = u.id WHERE x.rn = pos;
            IF target.id IS NULL THEN
                /* past the courses common to all: the first alternative, the others noted */
                SELECT u.* INTO target FROM jupeb.subject_unit u
                 WHERE u.subject_id = me.subject_id AND u.semester = p_to_semester AND u.board_subject_id IS NOT DISTINCT FROM me.board_subject_id AND u.areas IS NOT NULL
                 ORDER BY u.ord, u.code LIMIT 1;
                IF target.id IS NOT NULL THEN
                    others := (SELECT string_agg(u.code, ', ' ORDER BY u.ord) FROM jupeb.subject_unit u
                                WHERE u.subject_id = target.subject_id AND u.semester = p_to_semester AND u.areas IS NOT NULL AND u.id <> target.id
                                  AND u.board_subject_id IS NOT DISTINCT FROM target.board_subject_id);
                END IF;
            END IF;
            v_code := target.code;
            IF target.id IS NULL THEN
                v_note := left(concat_ws(' · ', v_note, 'Course to choose: ' || t.course_code || ' has no course in the same place this semester'), 300);
            ELSIF others IS NOT NULL THEN
                v_note := left(concat_ws(' · ', v_note, 'Also ' || others || ' for the combinations that take it'), 300);
            END IF;
        END IF;
        v_class := t.class_id;
        IF p_to_session <> p_session AND t.class_id IS NOT NULL THEN
            v_class := (SELECT c2.id FROM jupeb.class c1 JOIN jupeb.class c2 ON c2.session = p_to_session AND c2.name = c1.name WHERE c1.id = t.class_id);
        END IF;
        INSERT INTO jupeb.timetable_slot (session, semester, class_id, subject_id, weekday, starts_at, ends_at, room_id, note, course_code, practical, created_by)
        VALUES (p_to_session, p_to_semester, v_class, t.subject_id, t.weekday, t.starts_at, t.ends_at, t.room_id, v_note, v_code, t.practical, p_actor);
        k := k + 1;
    END LOOP;
    RETURN k;
END $$;

/* a slot in words, for a notice: "GRY 001 Elements of Physical Geography, Monday 08:00–09:00, LR8 (Class A)" */
CREATE OR REPLACE FUNCTION jupeb.slot_text(p_slot uuid)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN t.practical THEN s.title || ' practical' ELSE coalesce(t.course_code || coalesce(' ' || u.title, ''), s.title) END
           || ', ' || (ARRAY['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'])[t.weekday]
           || ' ' || to_char(t.starts_at, 'HH24:MI') || '–' || to_char(t.ends_at, 'HH24:MI') || ', ' || coalesce(t.venue, 'room to be confirmed')
           || CASE WHEN k.name IS NOT NULL THEN ' (' || k.name || ')' ELSE '' END
      FROM jupeb.timetable_slot t JOIN jupeb.subject s ON s.id = t.subject_id LEFT JOIN jupeb.subject_unit u ON u.id = t.unit_id LEFT JOIN jupeb.class k ON k.id = t.class_id
     WHERE t.id = p_slot
$$;

-- ── 4 · a notice to the students of one subject (and class) ─────────────────────────────────────────────────────
ALTER TABLE jupeb.announcement DROP CONSTRAINT announcement_audience_check;
ALTER TABLE jupeb.announcement ADD CONSTRAINT announcement_audience_check
    CHECK (audience IN ('ALL', 'APPLICANTS', 'ADMITTED', 'STUDENTS', 'CLASS', 'COMBINATION', 'PROGRAMME', 'STUDENT', 'SUBJECT'));
ALTER TABLE jupeb.announcement DROP CONSTRAINT ck_jupeb_ann_ref;
ALTER TABLE jupeb.announcement ADD CONSTRAINT ck_jupeb_ann_ref CHECK ((audience IN ('CLASS', 'COMBINATION', 'PROGRAMME', 'STUDENT', 'SUBJECT')) = (audience_ref IS NOT NULL));
ALTER TABLE jupeb.announcement ADD CONSTRAINT ck_jupeb_ann_subject CHECK (audience <> 'SUBJECT' OR audience_ref ~ '^[0-9a-f-]{36}(/[0-9a-f-]{36})?$');

CREATE OR REPLACE FUNCTION jupeb.audience_reaches(p_session text, p_audience text, p_ref text, p_app jupeb.application)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT p_app.session = p_session AND p_app.state <> 'WITHDRAWN' AND CASE p_audience
        WHEN 'ALL' THEN true
        WHEN 'APPLICANTS' THEN p_app.state IN ('DRAFT', 'SUBMITTED', 'RETURNED', 'UNDER_REVIEW', 'ELIGIBLE', 'PENDING')
        WHEN 'ADMITTED' THEN p_app.state IN ('ADMITTED', 'STUDENT', 'COMPLETED', 'DEFERRED')
        WHEN 'STUDENTS' THEN p_app.state IN ('STUDENT', 'COMPLETED')
        WHEN 'CLASS' THEN p_app.class_id::text = p_ref
        WHEN 'COMBINATION' THEN EXISTS (SELECT 1 FROM jupeb.combination c WHERE c.id = p_app.combination_id AND upper(c.code) = upper(p_ref))
        WHEN 'PROGRAMME' THEN (CASE WHEN p_app.stream = 'ARTS' THEN 'NON_SCIENCE' ELSE p_app.stream END) = p_ref
        WHEN 'STUDENT' THEN p_app.id::text = p_ref
        WHEN 'SUBJECT' THEN p_app.state IN ('STUDENT', 'COMPLETED')
                            AND EXISTS (SELECT 1 FROM jupeb.subject_registration r WHERE r.application_id = p_app.id AND r.subject_id::text = split_part(p_ref, '/', 1))
                            AND (split_part(p_ref, '/', 2) = '' OR p_app.class_id::text = split_part(p_ref, '/', 2))
        ELSE false END
$$;

-- ── 5 · a register is one lecture ────────────────────────────────────────────────────────────────────────────────
ALTER TABLE attendance.register ADD COLUMN slot_ref uuid NULL;
COMMENT ON COLUMN attendance.register.slot_ref IS 'V354: the timetable slot (jupeb.timetable_slot) this register records on its day; empty for a register opened by hand for the day.';
DROP INDEX attendance.ux_attendance_register;
CREATE UNIQUE INDEX ux_attendance_register ON attendance.register
    (context, session, semester, subject_ref, coalesce(class_ref, '00000000-0000-0000-0000-000000000000'::uuid), held_on, coalesce(slot_ref, '00000000-0000-0000-0000-000000000000'::uuid));
CREATE INDEX ix_attendance_register_slot ON attendance.register (slot_ref, held_on) WHERE slot_ref IS NOT NULL;

CREATE OR REPLACE FUNCTION attendance.check_slot_ref()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.slot_ref IS NOT NULL AND (NEW.context <> 'JUPEB' OR NOT EXISTS (
            SELECT 1 FROM jupeb.timetable_slot t WHERE t.id = NEW.slot_ref AND t.subject_id = NEW.subject_ref AND t.session = NEW.session
               AND t.semester = NEW.semester AND t.class_id IS NOT DISTINCT FROM NEW.class_ref)) THEN
        RAISE EXCEPTION 'ATT_SLOT: that lecture is not of this subject, class, session and semester' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_attendance_register_slot BEFORE INSERT OR UPDATE OF slot_ref ON attendance.register FOR EACH ROW EXECUTE FUNCTION attendance.check_slot_ref();

/* V342's register of a subject (and class) on a day, opened by hand: found again whichever lecture of the day it is */
CREATE OR REPLACE FUNCTION attendance.open_register(p_context text, p_session text, p_semester integer, p_subject uuid, p_class uuid, p_held_on date, p_topic text, p_actor uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
    IF p_held_on > current_date THEN RAISE EXCEPTION 'ATT_FUTURE: a register is not taken for a day still to come' USING ERRCODE = '23514'; END IF;
    SELECT id INTO v FROM attendance.register
     WHERE context = p_context AND session = p_session AND semester = p_semester AND subject_ref = p_subject
       AND coalesce(class_ref, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_class, '00000000-0000-0000-0000-000000000000'::uuid) AND held_on = p_held_on
     ORDER BY (slot_ref IS NULL) DESC, opened_at LIMIT 1;
    IF v IS NOT NULL THEN RETURN v; END IF;
    INSERT INTO attendance.register (context, session, semester, subject_ref, class_ref, held_on, topic, opened_by)
    VALUES (p_context, p_session, p_semester, p_subject, p_class, p_held_on, nullif(btrim(coalesce(p_topic, '')), ''), p_actor)
    RETURNING id INTO v;
    RETURN v;
END $$;

-- ── 6 · a lecture not held ───────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE jupeb.lecture_not_held (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slot_id          uuid NOT NULL REFERENCES jupeb.timetable_slot(id),
    held_on          date NOT NULL,
    reason           text NOT NULL CHECK (length(btrim(reason)) BETWEEN 5 AND 300),
    recorded_by      uuid NULL,
    recorded_office  text NULL,
    recorded_at      timestamptz NOT NULL DEFAULT now(),
    withdrawn_at     timestamptz NULL,
    withdrawn_by     uuid NULL
);
CREATE UNIQUE INDEX ux_jupeb_not_held ON jupeb.lecture_not_held (slot_id, held_on) WHERE withdrawn_at IS NULL;
SELECT audit.attach('jupeb.lecture_not_held');
COMMENT ON TABLE jupeb.lecture_not_held IS 'V354: a timetabled lecture that was not held on a day (a public holiday, the lecturer away …), with the reason — so it is not counted missed; withdrawn, never deleted.';

/* the register of a timetabled lecture on its day: the lecture's own once opened; a register opened by hand for the subject that
   day becomes the lecture's; a day the lecture is not on, a day to come or a lecture recorded as not held is refused */
CREATE OR REPLACE FUNCTION jupeb.open_lecture_register(p_slot uuid, p_day date, p_actor uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE t jupeb.timetable_slot; v uuid;
BEGIN
    SELECT * INTO t FROM jupeb.timetable_slot WHERE id = p_slot;
    IF t.id IS NULL OR NOT t.active THEN RAISE EXCEPTION 'ATT_SLOT: that lecture is not on the timetable' USING ERRCODE = '23514'; END IF;
    IF extract(isodow FROM p_day)::int <> t.weekday THEN
        RAISE EXCEPTION 'ATT_SLOT_DAY: % is on %s', jupeb.slot_text(t.id), (ARRAY['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'])[t.weekday]
            USING ERRCODE = '23514';
    END IF;
    IF p_day > (now() AT TIME ZONE 'Africa/Lagos')::date THEN RAISE EXCEPTION 'ATT_FUTURE: a register is not taken for a day still to come' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM jupeb.lecture_not_held n WHERE n.slot_id = t.id AND n.held_on = p_day AND n.withdrawn_at IS NULL) THEN
        RAISE EXCEPTION 'JUPEB_LECTURE_NOT_HELD: the lecture is recorded as not held that day; withdraw that first' USING ERRCODE = '23514';
    END IF;
    SELECT id INTO v FROM attendance.register WHERE context = 'JUPEB' AND slot_ref = t.id AND held_on = p_day;
    IF v IS NOT NULL THEN RETURN v; END IF;
    SELECT id INTO v FROM attendance.register
     WHERE context = 'JUPEB' AND session = t.session AND semester = t.semester AND subject_ref = t.subject_id AND class_ref IS NOT DISTINCT FROM t.class_id
       AND held_on = p_day AND slot_ref IS NULL
     ORDER BY opened_at LIMIT 1;
    IF v IS NOT NULL THEN
        UPDATE attendance.register SET slot_ref = t.id WHERE id = v;
        RETURN v;
    END IF;
    INSERT INTO attendance.register (context, session, semester, subject_ref, class_ref, held_on, topic, opened_by, slot_ref)
    VALUES ('JUPEB', t.session, t.semester, t.subject_id, t.class_id, p_day,
            left(CASE WHEN t.practical THEN 'Practical' ELSE coalesce(t.course_code || coalesce(' ' || (SELECT title FROM jupeb.subject_unit WHERE id = t.unit_id), ''), 'Lecture') END, 300),
            p_actor, t.id)
    RETURNING id INTO v;
    RETURN v;
END $$;

/* a timetabled lecture recorded as not held on a day, with the reason — not once its register has marks */
CREATE OR REPLACE FUNCTION jupeb.record_not_held(p_slot uuid, p_day date, p_reason text, p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE t jupeb.timetable_slot; v uuid;
BEGIN
    SELECT * INTO t FROM jupeb.timetable_slot WHERE id = p_slot;
    IF t.id IS NULL OR NOT t.active THEN RAISE EXCEPTION 'ATT_SLOT: that lecture is not on the timetable' USING ERRCODE = '23514'; END IF;
    IF extract(isodow FROM p_day)::int <> t.weekday THEN
        RAISE EXCEPTION 'ATT_SLOT_DAY: % is on %s', jupeb.slot_text(t.id), (ARRAY['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'])[t.weekday]
            USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'JUPEB_NOT_HELD_REASON: say why the lecture was not held' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM attendance.register r JOIN attendance.mark k ON k.register_id = r.id WHERE r.slot_ref = t.id AND r.held_on = p_day) THEN
        RAISE EXCEPTION 'JUPEB_LECTURE_RECORDED: the lecture''s attendance is taken that day, so it was held' USING ERRCODE = '23514';
    END IF;
    SELECT id INTO v FROM jupeb.lecture_not_held WHERE slot_id = t.id AND held_on = p_day AND withdrawn_at IS NULL;
    IF v IS NOT NULL THEN
        UPDATE jupeb.lecture_not_held SET reason = btrim(p_reason) WHERE id = v;
        RETURN v;
    END IF;
    INSERT INTO jupeb.lecture_not_held (slot_id, held_on, reason, recorded_by, recorded_office) VALUES (t.id, p_day, btrim(p_reason), p_actor, p_office) RETURNING id INTO v;
    RETURN v;
END $$;

-- ── 7 · the lectures due ─────────────────────────────────────────────────────────────────────────────────────────
/* every timetabled lecture of a session from one day to another: the semester's slots on each teaching day — from the day teaching
   starts by the calendar (and the slot was on the timetable) until the examinations — and what became of each: RECORDED (its
   register saved), OPEN (opened, not saved), NOT_HELD (with the reason), DUE (today), MISSED (a day gone with no register) or UPCOMING */
CREATE OR REPLACE FUNCTION jupeb.lectures_due(p_session text, p_from date, p_to date)
RETURNS TABLE (slot_id uuid, day date, weekday int, semester int, subject_id uuid, subject_code text, subject_title text, course_code text, unit_title text,
               practical boolean, class_id uuid, class_name text, venue text, starts_at text, ends_at text, register_id uuid, saved_at timestamptz,
               locked_at timestamptz, marked int, not_held text, state text)
LANGUAGE sql STABLE AS $$
    WITH days AS (SELECT d::date AS day FROM generate_series(p_from, least(p_to, p_from + 400), interval '1 day') d),
    sem AS (SELECT days.day, jupeb.current_semester(p_session, days.day) AS semester FROM days),
    bounds AS (SELECT jupeb.calendar_date(p_session, 'TEACHING_STARTS') AS starts, jupeb.calendar_date(p_session, 'EXAMINATIONS') AS exams,
                      (now() AT TIME ZONE 'Africa/Lagos')::date AS today)
    SELECT t.id, sem.day, t.weekday, t.semester, t.subject_id, s.code, s.title, t.course_code, u.title, t.practical, t.class_id, k.name, t.venue,
           to_char(t.starts_at, 'HH24:MI'), to_char(t.ends_at, 'HH24:MI'), g.id, g.saved_at, g.locked_at,
           (SELECT count(*)::int FROM attendance.mark m WHERE m.register_id = g.id), n.reason,
           CASE WHEN n.id IS NOT NULL THEN 'NOT_HELD' WHEN g.saved_at IS NOT NULL THEN 'RECORDED' WHEN g.id IS NOT NULL THEN 'OPEN'
                WHEN sem.day = b.today THEN 'DUE' WHEN sem.day < b.today THEN 'MISSED' ELSE 'UPCOMING' END
      FROM sem CROSS JOIN bounds b
      JOIN jupeb.timetable_slot t ON t.session = p_session AND t.active AND t.semester = sem.semester AND t.weekday = extract(isodow FROM sem.day)::int
      JOIN jupeb.subject s ON s.id = t.subject_id
      LEFT JOIN jupeb.subject_unit u ON u.id = t.unit_id
      LEFT JOIN jupeb.class k ON k.id = t.class_id
      LEFT JOIN LATERAL (SELECT r.id, r.saved_at, r.locked_at FROM attendance.register r
                          WHERE r.context = 'JUPEB' AND r.session = p_session AND r.held_on = sem.day AND r.subject_ref = t.subject_id
                            AND r.class_ref IS NOT DISTINCT FROM t.class_id AND (r.slot_ref = t.id OR (r.slot_ref IS NULL AND r.semester = t.semester))
                          ORDER BY (r.slot_ref IS NOT NULL) DESC, r.opened_at LIMIT 1) g ON true
      LEFT JOIN jupeb.lecture_not_held n ON n.slot_id = t.id AND n.held_on = sem.day AND n.withdrawn_at IS NULL
     WHERE (b.starts IS NULL OR sem.day >= b.starts) AND (b.exams IS NULL OR sem.day < b.exams)
       AND sem.day >= (t.created_at AT TIME ZONE 'Africa/Lagos')::date
     ORDER BY sem.day, t.starts_at, s.code
$$;
COMMENT ON FUNCTION jupeb.lectures_due(text, date, date) IS 'V354: the timetabled lectures of a session between two days, from teaching''s start by the calendar until the examinations, each RECORDED, OPEN, NOT_HELD, DUE, MISSED or UPCOMING.';

-- ── 8 · clearance for the examination ────────────────────────────────────────────────────────────────────────────
/* each active student of a session against what sitting the Board's examination needs: three subjects registered (and the option
   of an either/or subject chosen), a passport photograph, the required documents verified, the school fee paid in full, attendance
   at the minimum when the JUPEB Office has set one (none set: held against no one), and the examination number */
CREATE OR REPLACE FUNCTION jupeb.exam_clearance(p_session text)
RETURNS TABLE (application_id uuid, application_no text, name text, class_name text, combination_code text, exam_no text, checks jsonb, outstanding text[], cleared boolean)
LANGUAGE sql STABLE AS $$
    WITH a AS (SELECT x.* FROM jupeb.application x WHERE x.session = p_session AND x.state = 'STUDENT'),
    st AS (SELECT member_ref, string_agg(DISTINCT code, ', ') AS short FROM attendance.jupeb_standing(p_session) WHERE verdict = 'NOT_ELIGIBLE' GROUP BY member_ref),
    c AS (
        SELECT a.id,
               a.subjects_registered_at IS NOT NULL AND (SELECT count(*) FROM jupeb.subject_registration r WHERE r.application_id = a.id) = 3 AS subjects_ok,
               (SELECT string_agg(s.title, ', ') FROM jupeb.subject_registration r JOIN jupeb.subject s ON s.id = r.subject_id
                 WHERE r.application_id = a.id AND r.board_subject_id IS NULL AND (SELECT count(*) FROM jupeb.board_subject b WHERE b.subject_id = r.subject_id) > 1) AS no_option,
               EXISTS (SELECT 1 FROM jupeb.document d WHERE d.application_id = a.id AND d.kind = 'PASSPORT' AND d.status NOT IN ('REJECTED', 'REPLACEMENT_REQUIRED')) AS photo_ok,
               (SELECT string_agg(k.label, ', ' ORDER BY k.ord) FROM jupeb.document_kind k
                 WHERE k.required AND k.active AND NOT EXISTS (SELECT 1 FROM jupeb.document d WHERE d.application_id = a.id AND d.kind = k.code)) AS docs_missing,
               (SELECT string_agg(k.label || ' (' || lower(replace(d.status, '_', ' ')) || ')', ', ' ORDER BY k.ord) FROM jupeb.document_kind k
                  JOIN jupeb.document d ON d.kind = k.code AND d.application_id = a.id WHERE k.required AND k.active AND d.status <> 'VERIFIED') AS docs_unverified,
               sf.outstanding, (SELECT p.min_percent FROM attendance.policy_of('JUPEB', p_session) p) AS min_percent, st.short
          FROM a CROSS JOIN LATERAL jupeb.school_fees(a.id) sf LEFT JOIN st ON st.member_ref = a.id),
    k AS (
        SELECT c.id, jsonb_build_array(
                   jsonb_build_object('key', 'SUBJECTS', 'label', 'Three subjects registered', 'ok', c.subjects_ok, 'note', CASE WHEN NOT c.subjects_ok THEN 'The three subjects are not registered' END),
                   jsonb_build_object('key', 'OPTION', 'label', 'The option of an either/or subject chosen', 'ok', c.no_option IS NULL, 'note', 'Say which is taken: ' || c.no_option),
                   jsonb_build_object('key', 'PHOTO', 'label', 'Passport photograph on file', 'ok', c.photo_ok, 'note', CASE WHEN NOT c.photo_ok THEN 'No passport photograph on file' END),
                   jsonb_build_object('key', 'DOCUMENTS', 'label', 'Required documents verified', 'ok', c.docs_missing IS NULL AND c.docs_unverified IS NULL,
                                      'note', nullif(concat_ws('; ', 'Not on file: ' || c.docs_missing, 'Not yet verified: ' || c.docs_unverified), '')),
                   jsonb_build_object('key', 'FEES', 'label', 'School fee paid in full', 'ok', coalesce(c.outstanding, 0) = 0,
                                      'note', CASE WHEN coalesce(c.outstanding, 0) > 0 THEN 'School fee outstanding: ₦' || to_char(c.outstanding, 'FM999,999,990') END),
                   jsonb_build_object('key', 'ATTENDANCE', 'label', 'Attendance at the minimum', 'ok', c.min_percent IS NULL OR c.short IS NULL,
                                      'note', CASE WHEN c.min_percent IS NULL THEN 'No minimum attendance is set' WHEN c.short IS NOT NULL THEN 'Below the minimum attendance in ' || c.short END),
                   jsonb_build_object('key', 'EXAM_NO', 'label', 'JUPEB examination number', 'ok', a.exam_no IS NOT NULL, 'note', CASE WHEN a.exam_no IS NULL THEN 'No examination number from the Board yet' END)
               ) AS checks
          FROM c JOIN a ON a.id = c.id)
    SELECT a.id, a.application_no, upper(a.surname) || ', ' || a.first_name || coalesce(' ' || a.middle_name, ''), cl.name, cb.code, a.exam_no, k.checks,
           ARRAY(SELECT x->>'note' FROM jsonb_array_elements(k.checks) x WHERE NOT (x->>'ok')::boolean),
           NOT EXISTS (SELECT 1 FROM jsonb_array_elements(k.checks) x WHERE NOT (x->>'ok')::boolean)
      FROM a JOIN k ON k.id = a.id LEFT JOIN jupeb.class cl ON cl.id = a.class_id LEFT JOIN jupeb.combination cb ON cb.id = a.combination_id
     ORDER BY a.surname, a.first_name
$$;
COMMENT ON FUNCTION jupeb.exam_clearance(text) IS 'V354: each active JUPEB student of a session against what sitting the examination needs, with what is outstanding said plainly; a minimum attendance is held against no one until the JUPEB Office sets one.';

-- ── 9 · the read-only and admissions roles reach the new tables ─────────────────────────────────────────────────
GRANT SELECT ON jupeb.calendar_event, jupeb.room, jupeb.lecture_not_held TO app_auditor;
GRANT SELECT, INSERT, UPDATE ON jupeb.calendar_event, jupeb.room, jupeb.lecture_not_held TO app_admissions;

COMMIT;
