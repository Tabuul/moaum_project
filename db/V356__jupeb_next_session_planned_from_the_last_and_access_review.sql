-- V356: the next JUPEB session planned from the one before, and the fixes of the JUPEB access review.
--
-- 1. The next session is set up from the last, item by item, each only when the JUPEB Office says so: the settings (numbering
--    and screening — not its dates, the examination month or the results), the classes, the calendar (a year on, marked
--    planned), the timetable (both semesters, classes matched by name), the parts of the continuous assessment, the minimum
--    attendance, and the lecturers' assignments (a class matched by name; a lecturer who has left is not carried). Nothing is
--    carried over what the next session already has of its own, and every carry is on the record. The fees are the Bursary's:
--    only the Bursary carries a session's own fees into the next. The application windows stay the Director of ICT's.
-- 2. A lecturer of two or more classes of a subject (not every class) sees their classes' practice by topic, not every class's.
BEGIN;

-- ── 1 · the next session from the last ──────────────────────────────────────────────────────────────────────────
CREATE TABLE jupeb.session_rollover (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    from_session text NOT NULL CHECK (from_session ~ '^[0-9]{4}/[0-9]{4}$'),
    to_session   text NOT NULL CHECK (to_session ~ '^[0-9]{4}/[0-9]{4}$'),
    item         text NOT NULL CHECK (item IN ('SETTINGS', 'CLASSES', 'CALENDAR', 'TIMETABLE', 'CA_PARTS', 'ATTENDANCE_POLICY', 'LECTURERS', 'FEES')),
    carried      int NOT NULL,
    skipped      int NOT NULL DEFAULT 0,
    note         text NULL,
    actor        uuid NULL,
    office       text NULL,
    at           timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_jupeb_rollover_later CHECK (substr(to_session, 1, 4)::int > substr(from_session, 1, 4)::int)
);
SELECT audit.attach('jupeb.session_rollover');
COMMENT ON TABLE jupeb.session_rollover IS 'V356: what of a JUPEB session was carried into a later one, item by item, by whom — the next session is never set up behind anyone''s back.';

/* how much of an item a session holds of its own */
CREATE OR REPLACE FUNCTION jupeb.rollover_count(p_session text, p_item text)
RETURNS int LANGUAGE sql STABLE AS $$
    SELECT CASE p_item
        WHEN 'SETTINGS' THEN (SELECT count(*) FROM jupeb.setting WHERE session = p_session)
        WHEN 'CLASSES' THEN (SELECT count(*) FROM jupeb.class WHERE session = p_session)
        WHEN 'CALENDAR' THEN (SELECT count(*) FROM jupeb.calendar_event WHERE session = p_session AND removed_at IS NULL)
        WHEN 'TIMETABLE' THEN (SELECT count(*) FROM jupeb.timetable_slot WHERE session = p_session AND active)
        WHEN 'CA_PARTS' THEN (SELECT count(*) FROM jupeb.ca_component WHERE session = p_session AND active)
        WHEN 'ATTENDANCE_POLICY' THEN (SELECT count(*) FROM attendance.policy WHERE context = 'JUPEB' AND session = p_session)
        WHEN 'LECTURERS' THEN (SELECT count(*) FROM attendance.instructor WHERE context = 'JUPEB' AND session = p_session AND ended_at IS NULL)
        WHEN 'FEES' THEN (SELECT count(*) FROM jupeb.fee_setting WHERE session = p_session) + (SELECT count(*) FROM jupeb.school_fee WHERE session = p_session)
    END::int
$$;

/* the plan: for each item, what the session it comes from holds, what the next holds, and whether it is to carry, done or has nothing */
CREATE OR REPLACE FUNCTION jupeb.rollover_plan(p_from text, p_to text)
RETURNS TABLE (item text, label text, whose text, from_count int, to_count int, state text, note text, carried_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT i.item, i.label, i.whose, f.n, t.n,
           CASE WHEN t.n > 0 THEN 'DONE' WHEN f.n = 0 THEN 'NOTHING' ELSE 'READY' END,
           i.note,
           (SELECT max(r.at) FROM jupeb.session_rollover r WHERE r.from_session = p_from AND r.to_session = p_to AND r.item = i.item)
      FROM (VALUES
            (1, 'SETTINGS', 'Numbering and screening', 'JUPEB Office',
             'The application number prefix and whether screening comes before school fees, with its venue and instructions. Screening dates, the examination month and results are the new session''s own.'),
            (2, 'CLASSES', 'Classes', 'JUPEB Office', 'Each class by name, with its combination and capacity — empty: students are placed in the new session.'),
            (3, 'CALENDAR', 'Session calendar', 'JUPEB Office', 'Every date moved on by the years between, marked planned until checked against the Board''s calendar.'),
            (4, 'TIMETABLE', 'Lecture timetable', 'JUPEB Office', 'Both semesters, the same days, hours, rooms and courses; a class matched by name, so the classes come first.'),
            (5, 'CA_PARTS', 'Parts of the continuous assessment', 'JUPEB Office', 'Each part and its maximum; scores are never carried.'),
            (6, 'ATTENDANCE_POLICY', 'Minimum attendance', 'JUPEB Office', 'The minimum, the warning band and the classes before it applies.'),
            (7, 'LECTURERS', 'Lecturers'' assignments', 'JUPEB Office', 'Each lecturer still in service, on the same subject; a class matched by name, so the classes come first.'),
            (8, 'FEES', 'Fees', 'Bursary', 'The session''s own fees and school fees — carried by the Bursary on the JUPEB fees page, never by the JUPEB Office. Without them the default applies.')
           ) i(ord, item, label, whose, note)
      CROSS JOIN LATERAL (SELECT jupeb.rollover_count(p_from, i.item) AS n) f
      CROSS JOIN LATERAL (SELECT jupeb.rollover_count(p_to, i.item) AS n) t
     ORDER BY i.ord
$$;

/* the checks every carry makes: two well-formed sessions, the later one ahead, something to carry, nothing there already */
CREATE OR REPLACE FUNCTION jupeb.rollover_check(p_from text, p_to text, p_item text)
RETURNS void LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF coalesce(p_from, '') !~ '^[0-9]{4}/[0-9]{4}$' OR coalesce(p_to, '') !~ '^[0-9]{4}/[0-9]{4}$'
       OR substr(p_from, 6, 4)::int <> substr(p_from, 1, 4)::int + 1 OR substr(p_to, 6, 4)::int <> substr(p_to, 1, 4)::int + 1 THEN
        RAISE EXCEPTION 'JUPEB_ROLLOVER_SESSION: a session is written as 2026/2027' USING ERRCODE = '23514';
    END IF;
    IF substr(p_to, 1, 4)::int <= substr(p_from, 1, 4)::int THEN
        RAISE EXCEPTION 'JUPEB_ROLLOVER_LATER: a session is carried forward, into a later one' USING ERRCODE = '23514';
    END IF;
    IF jupeb.rollover_count(p_from, p_item) = 0 THEN
        RAISE EXCEPTION 'JUPEB_ROLLOVER_NOTHING: % has nothing of its own of this to carry', p_from USING ERRCODE = '23514';
    END IF;
    IF jupeb.rollover_count(p_to, p_item) > 0 THEN
        RAISE EXCEPTION 'JUPEB_ROLLOVER_EXISTS: % already has its own; change it there', p_to USING ERRCODE = '23514';
    END IF;
END $$;

/* one item carried by the JUPEB Office; returns what was carried and what was left (and why) */
CREATE OR REPLACE FUNCTION jupeb.rollover_carry(p_from text, p_to text, p_item text, p_actor uuid, p_office text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE k int := 0; skipped int := 0; v_note text; sem int;
BEGIN
    IF p_item = 'FEES' THEN
        RAISE EXCEPTION 'JUPEB_ROLLOVER_FEES: the fees are the Bursary''s to carry, on the JUPEB fees page' USING ERRCODE = '23514';
    END IF;
    IF p_item NOT IN ('SETTINGS', 'CLASSES', 'CALENDAR', 'TIMETABLE', 'CA_PARTS', 'ATTENDANCE_POLICY', 'LECTURERS') THEN
        RAISE EXCEPTION 'JUPEB_ROLLOVER_ITEM: no such item' USING ERRCODE = '23514';
    END IF;
    PERFORM jupeb.rollover_check(p_from, p_to, p_item);
    IF p_item = 'SETTINGS' THEN
        INSERT INTO jupeb.setting (session, application_prefix, screening_required, screening_venue, screening_instructions, updated_by)
        SELECT p_to, s.application_prefix, s.screening_required, s.screening_venue, s.screening_instructions, p_actor FROM jupeb.setting s WHERE s.session = p_from;
        GET DIAGNOSTICS k = ROW_COUNT;
    ELSIF p_item = 'CLASSES' THEN
        INSERT INTO jupeb.class (session, name, combination_id, capacity, created_by)
        SELECT p_to, c.name, c.combination_id, c.capacity, p_actor FROM jupeb.class c WHERE c.session = p_from ORDER BY c.name;
        GET DIAGNOSTICS k = ROW_COUNT;
    ELSIF p_item = 'CALENDAR' THEN
        k := jupeb.copy_calendar(p_from, p_to, p_actor);
    ELSIF p_item = 'TIMETABLE' THEN
        IF EXISTS (SELECT 1 FROM jupeb.timetable_slot t JOIN jupeb.class c ON c.id = t.class_id WHERE t.session = p_from AND t.active
                    AND NOT EXISTS (SELECT 1 FROM jupeb.class c2 WHERE c2.session = p_to AND c2.name = c.name)) THEN
            RAISE EXCEPTION 'JUPEB_ROLLOVER_CLASSES_FIRST: lectures of % are for classes % does not have yet; carry the classes first', p_from, p_to USING ERRCODE = '23514';
        END IF;
        FOR sem IN SELECT DISTINCT semester FROM jupeb.timetable_slot WHERE session = p_from AND active ORDER BY 1 LOOP
            k := k + jupeb.copy_timetable(p_from, sem, p_to, sem, p_actor);
        END LOOP;
    ELSIF p_item = 'CA_PARTS' THEN
        INSERT INTO jupeb.ca_component (session, code, title, max_score, ord, active, created_by)
        SELECT p_to, c.code, c.title, c.max_score, c.ord, true, p_actor FROM jupeb.ca_component c WHERE c.session = p_from AND c.active;
        GET DIAGNOSTICS k = ROW_COUNT;
    ELSIF p_item = 'ATTENDANCE_POLICY' THEN
        INSERT INTO attendance.policy (context, session, min_percent, warn_band, min_classes, updated_by)
        SELECT 'JUPEB', p_to, p.min_percent, p.warn_band, p.min_classes, p_actor FROM attendance.policy p WHERE p.context = 'JUPEB' AND p.session = p_from;
        GET DIAGNOSTICS k = ROW_COUNT;
    ELSIF p_item = 'LECTURERS' THEN
        IF EXISTS (SELECT 1 FROM attendance.instructor i JOIN jupeb.class c ON c.id = i.class_ref WHERE i.context = 'JUPEB' AND i.session = p_from AND i.ended_at IS NULL
                    AND NOT EXISTS (SELECT 1 FROM jupeb.class c2 WHERE c2.session = p_to AND c2.name = c.name)) THEN
            RAISE EXCEPTION 'JUPEB_ROLLOVER_CLASSES_FIRST: lecturers of % teach classes % does not have yet; carry the classes first', p_from, p_to USING ERRCODE = '23514';
        END IF;
        INSERT INTO attendance.instructor (context, session, subject_ref, class_ref, person_id, assigned_by)
        SELECT 'JUPEB', p_to, i.subject_ref, (SELECT c2.id FROM jupeb.class c JOIN jupeb.class c2 ON c2.session = p_to AND c2.name = c.name WHERE c.id = i.class_ref),
               i.person_id, p_actor
          FROM attendance.instructor i JOIN iam.person p ON p.id = i.person_id
         WHERE i.context = 'JUPEB' AND i.session = p_from AND i.ended_at IS NULL AND (p.ended_on IS NULL OR p.ended_on > current_date);
        GET DIAGNOSTICS k = ROW_COUNT;
        skipped := jupeb.rollover_count(p_from, 'LECTURERS') - k;
        IF skipped > 0 THEN v_note := skipped || ' left: no longer in the University''s service'; END IF;
    END IF;
    INSERT INTO jupeb.session_rollover (from_session, to_session, item, carried, skipped, note, actor, office) VALUES (p_from, p_to, p_item, k, skipped, v_note, p_actor, p_office);
    RETURN jsonb_build_object('item', p_item, 'carried', k, 'skipped', skipped, 'note', v_note);
END $$;
COMMENT ON FUNCTION jupeb.rollover_carry(text, text, text, uuid, text) IS 'V356: one item of a JUPEB session carried into a later one by the JUPEB Office — never over what that session already has, never the fees.';

/* the Bursary carries a session's own fees and school fees into a later session that has none of its own */
CREATE OR REPLACE FUNCTION jupeb.carry_fees(p_from text, p_to text, p_actor uuid, p_office text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE k int; j int;
BEGIN
    IF coalesce(p_office, '') NOT IN ('bursar', 'super') THEN
        RAISE EXCEPTION 'JUPEB_ROLLOVER_FEES: the fees are the Bursary''s to carry' USING ERRCODE = '23514';
    END IF;
    PERFORM jupeb.rollover_check(p_from, p_to, 'FEES');
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_to) THEN
        RAISE EXCEPTION 'JUPEB_ROLLOVER_NO_SESSION: % is not yet on the University''s calendar of sessions', p_to USING ERRCODE = '23514';
    END IF;
    INSERT INTO jupeb.fee_setting (session, application_fee, checking_fee, acceptance_fee, first_percent, allow_full, activation, indigene_state, updated_by, updated_office)
    SELECT p_to, f.application_fee, f.checking_fee, f.acceptance_fee, f.first_percent, f.allow_full, f.activation, f.indigene_state, p_actor, p_office
      FROM jupeb.fee_setting f WHERE f.session = p_from;
    GET DIAGNOSTICS k = ROW_COUNT;
    INSERT INTO jupeb.school_fee (session, category, indigene, amount, updated_by, updated_office)
    SELECT p_to, s.category, s.indigene, s.amount, p_actor, p_office FROM jupeb.school_fee s WHERE s.session = p_from;
    GET DIAGNOSTICS j = ROW_COUNT;
    INSERT INTO jupeb.session_rollover (from_session, to_session, item, carried, actor, office) VALUES (p_from, p_to, 'FEES', k + j, p_actor, p_office);
    RETURN jsonb_build_object('item', 'FEES', 'carried', k + j, 'skipped', 0);
END $$;
COMMENT ON FUNCTION jupeb.carry_fees(text, text, uuid, text) IS 'V356: the Bursary carries a JUPEB session''s own fees into a later session without its own — the amounts unchanged, the Bursary''s to change after.';

-- ── 2 · a lecturer's classes' practice by topic ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION jupeb.practice_topics_classes(p_session text, p_subject uuid, p_classes uuid[])
RETURNS TABLE (topic_id uuid, label text, students int, answered int, percentage numeric)
LANGUAGE sql STABLE AS $$
    SELECT q.topic_id, jupeb.topic_label(q.topic_id), count(DISTINCT at.application_id)::int, count(*)::int, round(100.0 * count(*) FILTER (WHERE x.correct) / count(*), 1)
      FROM jupeb.practice_attempt at JOIN jupeb.practice_test t ON t.id = at.test_id JOIN jupeb.application a ON a.id = at.application_id
      JOIN jupeb.practice_answer x ON x.attempt_id = at.id JOIN jupeb.practice_question q ON q.id = x.question_id
     WHERE t.subject_id = p_subject AND a.session = p_session AND at.submitted_at IS NOT NULL AND q.topic_id IS NOT NULL AND a.class_id = ANY (p_classes)
     GROUP BY q.topic_id
     ORDER BY 5, 2
$$;
COMMENT ON FUNCTION jupeb.practice_topics_classes(text, uuid, uuid[]) IS 'V356: a subject''s practice by topic across the students of the classes given — a lecturer''s own classes, not every class.';

GRANT SELECT ON jupeb.session_rollover TO app_auditor;
GRANT SELECT, INSERT ON jupeb.session_rollover TO app_admissions;

COMMIT;
