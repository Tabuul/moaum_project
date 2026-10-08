-- V360: check codes signed by the API; students told of course material, assignments, marks and PG coursework.
--
-- 1. The check code a receipt, an examination card, a course form, a results statement or a PG offer carries in its QR
--    was a plain digest of what the document shows, so anyone could compute it for any student. The API now signs it
--    (CheckCodes); this records when that began, so a code of the old kind is honoured only for a record that existed
--    before — in full for a receipt (its old code needs the receipt number) and for the cards of an examination session
--    still open, and otherwise only as "genuine, printed before" with no details.
-- 2. Course material published, an assignment set and a submission marked on the LMS, and a PG course registration
--    endorsed and a PG score recorded, told no one. Each now tells the students it concerns by email, and by at most one
--    text a day of each kind, to what they have on record — naming the course, never a mark or a grade.
BEGIN;

-- ── 1 · when the signed codes began ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE platform.check_code_cutover (
    id          boolean PRIMARY KEY DEFAULT true CHECK (id),
    cut_over_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO platform.check_code_cutover (id) VALUES (true);
SELECT audit.attach('platform.check_code_cutover');
COMMENT ON TABLE platform.check_code_cutover IS 'V360: when printed documents began to carry check codes signed by the API; an old code is honoured only for a record made before.';

-- ── 2 · a student told ───────────────────────────────────────────────────────────────────────────────────────────
/* an email to the student's address on record, and a text to their phone — at most one text a day under the same
   heading, however many things happen; true when either went */
CREATE OR REPLACE FUNCTION people.tell_student(p_student uuid, p_subject text, p_body text, p_sms_subject text, p_sms text)
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE r record; v_sent boolean := false;
BEGIN
    SELECT * INTO r FROM people.student_reach(p_student);
    IF nullif(btrim(r.email), '') IS NOT NULL AND p_subject IS NOT NULL THEN
        PERFORM platform.queue_notice('EMAIL', r.email, p_subject, p_body, 'student', p_student);
        v_sent := true;
    END IF;
    IF nullif(btrim(r.phone), '') IS NOT NULL AND p_sms IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM platform.notice x WHERE x.channel = 'SMS' AND x.about_kind = 'student' AND x.about_id = p_student
           AND x.subject = p_sms_subject AND x.created_at >= date_trunc('day', now())) THEN
        PERFORM platform.queue_notice('SMS', r.phone, p_sms_subject, p_sms, 'student', p_student);
        v_sent := true;
    END IF;
    RETURN v_sent;
END $$;
COMMENT ON FUNCTION people.tell_student(uuid, text, text, text, text) IS 'V360: a student told by email, and by at most one text a day under the same heading, to what they have on record.';

CREATE OR REPLACE FUNCTION people.from_line()
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT name FROM platform.institution_profile LIMIT 1), 'the University')
$$;

/* course material published: the course's students told what it is and where it is — once, when it is published */
CREATE OR REPLACE FUNCTION lms.tell_material(p_material uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE m record; s record; n int := 0;
BEGIN
    SELECT x.id, x.title, x.week, x.kind, o.id AS offering_id, o.course_code, coalesce(o.title, c.title) AS course_title, o.session, o.semester
      INTO m FROM lms.material x JOIN catalogue.offering o ON o.id = x.offering_id JOIN catalogue.course c ON c.code = o.course_code
     WHERE x.id = p_material AND x.published_at IS NOT NULL AND x.ended_at IS NULL;
    IF m.id IS NULL THEN RETURN 0; END IF;
    FOR s IN SELECT DISTINCT g.student_id FROM lms.gradebook(m.offering_id) g LOOP
        IF people.tell_student(s.student_id, 'New material in ' || m.course_code || ': ' || m.title,
               'New material has been posted in ' || m.course_code || ' — ' || m.course_title || ' (' || m.session || '): '
               || m.title || CASE WHEN m.week IS NOT NULL THEN ', week ' || m.week ELSE '' END
               || E'.\n\nOpen it on the University portal, under My courses.\n\n' || people.from_line(),
               'Course update', 'MOAUM: new material in ' || m.course_code || ' on the portal (My courses).') THEN
            n := n + 1;
        END IF;
    END LOOP;
    RETURN n;
END $$;

/* an assignment set: the course's students told what it is and when it closes */
CREATE OR REPLACE FUNCTION lms.tell_assignment(p_assignment uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE a record; s record; n int := 0; v_due text;
BEGIN
    SELECT x.id, x.title, x.closes_at, o.id AS offering_id, o.course_code, coalesce(o.title, c.title) AS course_title, o.session
      INTO a FROM lms.assignment x JOIN catalogue.offering o ON o.id = x.offering_id JOIN catalogue.course c ON c.code = o.course_code
     WHERE x.id = p_assignment AND x.ended_at IS NULL;
    IF a.id IS NULL THEN RETURN 0; END IF;
    v_due := CASE WHEN a.closes_at IS NULL THEN NULL ELSE to_char(a.closes_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI, DD Mon YYYY') END;
    FOR s IN SELECT DISTINCT g.student_id FROM lms.gradebook(a.offering_id) g LOOP
        IF people.tell_student(s.student_id, 'New assignment in ' || a.course_code || ': ' || a.title,
               'An assignment has been set in ' || a.course_code || ' — ' || a.course_title || ' (' || a.session || '): ' || a.title
               || CASE WHEN v_due IS NOT NULL THEN E'.\nIt closes at ' || v_due ELSE '' END
               || E'.\n\nSee it and submit on the University portal, under My courses.\n\n' || people.from_line(),
               'Course update', 'MOAUM: new assignment in ' || a.course_code || coalesce(', closes ' || v_due, '') || '. See My courses on the portal.') THEN
            n := n + 1;
        END IF;
    END LOOP;
    RETURN n;
END $$;

/* a submission marked: its student told it is marked — the mark is on the portal, not in the message */
CREATE OR REPLACE FUNCTION lms.tell_marked(p_submission uuid)
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE x record;
BEGIN
    SELECT sb.student_id, a.title, o.course_code, coalesce(o.title, c.title) AS course_title
      INTO x FROM lms.submission sb JOIN lms.assignment a ON a.id = sb.assignment_id
      JOIN catalogue.offering o ON o.id = a.offering_id JOIN catalogue.course c ON c.code = o.course_code
     WHERE sb.id = p_submission AND sb.marked_at IS NOT NULL;
    IF x.student_id IS NULL THEN RETURN false; END IF;
    RETURN people.tell_student(x.student_id, 'Your ' || x.course_code || ' submission is marked',
        'Your submission for "' || x.title || '" in ' || x.course_code || ' — ' || x.course_title
        || E' has been marked.\n\nSee the mark and the lecturer''s feedback on the University portal, under My courses.\n\n' || people.from_line(),
        'Course update', 'MOAUM: your ' || x.course_code || ' submission is marked. See My courses on the portal.');
END $$;

/* a PG course registration endorsed: its student told */
CREATE OR REPLACE FUNCTION admissions.tell_pg_endorsed(p_registration uuid)
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    SELECT student_id, session, semester INTO r FROM admissions.pg_registration WHERE id = p_registration AND state = 'ENDORSED';
    IF r.student_id IS NULL THEN RETURN false; END IF;
    RETURN people.tell_student(r.student_id, 'Your course registration is endorsed',
        'Your postgraduate course registration for ' || r.session || ', ' || CASE r.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE r.semester::text END
        || E' semester, has been endorsed.\n\nSee it on the University portal, under Coursework.\n\n' || people.from_line(),
        'Registration endorsed', 'MOAUM: your PG course registration for ' || r.session || ' is endorsed. See Coursework on the portal.');
END $$;

/* a PG score recorded: its student told that a score is recorded in the course — once a day for the course, the score
   itself on the portal, not in the message */
CREATE OR REPLACE FUNCTION admissions.tell_pg_scored(p_entry uuid)
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE e record; v_subject text;
BEGIN
    SELECT r.student_id, r.session, c.code, c.title INTO e
      FROM admissions.pg_registration_entry x JOIN admissions.pg_registration r ON r.id = x.registration_id
      JOIN admissions.pg_course c ON c.id = x.course_id
     WHERE x.id = p_entry AND EXISTS (SELECT 1 FROM admissions.pg_score sc WHERE sc.entry_id = x.id);
    IF e.student_id IS NULL THEN RETURN false; END IF;
    v_subject := 'A score is recorded in ' || e.code;
    IF EXISTS (SELECT 1 FROM platform.notice x WHERE x.channel = 'EMAIL' AND x.about_kind = 'student' AND x.about_id = e.student_id
                  AND x.subject = v_subject AND x.created_at >= date_trunc('day', now())) THEN
        RETURN false;
    END IF;
    RETURN people.tell_student(e.student_id, v_subject,
        'A score has been recorded in ' || e.code || ' — ' || e.title || ' (' || e.session
        || E').\n\nSee it on the University portal, under Coursework.\n\n' || people.from_line(),
        'Coursework score', 'MOAUM: a score is recorded in ' || e.code || '. See Coursework on the portal.');
END $$;

COMMIT;
