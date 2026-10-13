-- ═══════════════════════════════════════
-- V424 — the results held for the Senate, listed and chased; and who the absent rule (V422) now affects
--
--   1. A result withheld, incomplete or under a malpractice case is held for the Senate's decision (V422): never counted,
--      never owed, and the student's semester waits. Nothing listed them, so one could wait for ever.
--      assessment.held_results lists every held result on a published sheet — the student, the course, how long it has
--      waited, and the amendment that carries the Senate's decision when one is open — within an office's scope. Each day the
--      Registrar, the Deputy Registrar and Exams and Records are told, at most once a week, of the results held longer than the
--      University's days (policy.standing_setting.held_remind_days, 30 until the Academic Office or the Registry changes it;
--      0 sends nothing). assessment.held_reminder_log keeps what was sent.
--   2. V422 made a recorded absence owed, as the Senate's sheet already did. Before the next registration and fee run the
--      offices see who that touches: assessment.absence_carryovers — each student with a carryover that comes from a recorded
--      absence, for the Registry; finance.gst_eps_owed_for_absence — each student who owes a GST/EPS course again because of
--      one, for the Bursary. Both read only; nothing is charged or registered by them.
-- ═══════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V424: results held for the Senate listed; who the absent rule now affects', true);

-- ── 1 · the days a held result waits before the Registry is reminded ──
ALTER TABLE policy.standing_setting
    ADD COLUMN held_remind_days integer NOT NULL DEFAULT 30 CHECK (held_remind_days = 0 OR held_remind_days BETWEEN 7 AND 365);
COMMENT ON COLUMN policy.standing_setting.held_remind_days IS
  'V424: a result held for the Senate (withheld, incomplete, malpractice) longer than this many days is reminded to the Registry, at most once a week; 0 reminds nobody.';

CREATE FUNCTION policy.held_remind_days()
RETURNS integer LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT held_remind_days FROM policy.standing_setting WHERE row_no), 30);
$fn$;

CREATE FUNCTION policy.set_held_remind_days(p_days integer)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF who IS NULL OR coalesce(v_office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'STANDING_SETTING_OFFICE: the reminder for held results is set by the Academic Office or the Registry' USING ERRCODE = '23514';
    END IF;
    IF p_days IS NULL OR NOT (p_days = 0 OR p_days BETWEEN 7 AND 365) THEN
        RAISE EXCEPTION 'STANDING_SETTING_HELD_DAYS: a held result is reminded after 7 to 365 days, or never (0)' USING ERRCODE = '23514';
    END IF;
    UPDATE policy.standing_setting SET held_remind_days = p_days, updated_at = now(), updated_by = who, updated_office = v_office WHERE row_no;
    RETURN p_days;
END $fn$;

-- ── 1 · the held results ──
-- the held outcomes are few among the marks: found by this index, never by reading every mark
CREATE INDEX ix_score_held ON assessment.score (sheet_id, student_id, version) WHERE outcome IN ('WITHHELD', 'INCOMPLETE', 'MALPRACTICE');
CREATE INDEX ix_score_absent ON assessment.score (sheet_id, student_id, version) WHERE outcome = 'ABSENT';

CREATE FUNCTION assessment.held_results(p_fac text, p_dept text, p_prog text, p_session text)
RETURNS TABLE(student_id uuid, number text, name text, programme_code text, course_code text, title text, dept_code text, dept_name text,
              session text, semester integer, outcome text, sheet_id uuid, held_since timestamptz, days integer, amendment_ref text, amendment_stage text)
LANGUAGE sql STABLE AS $fn$
    WITH h AS (
        SELECT sc.sheet_id, sc.student_id, sc.outcome, sc.entered_at
          FROM assessment.score sc
         WHERE sc.outcome IN ('WITHHELD', 'INCOMPLETE', 'MALPRACTICE')
           -- the latest version of the mark only: a held result later decided is no longer held
           AND NOT EXISTS (SELECT 1 FROM assessment.score n WHERE n.sheet_id = sc.sheet_id AND n.student_id = sc.student_id AND n.version > sc.version))
    SELECT st.id, coalesce(st.matric_no, st.admission_no), upper(st.surname) || ', ' || st.other_names, st.programme_code,
           o.course_code, coalesce(o.title, c.title), c.dept_code, d.name, o.session, o.semester, h.outcome, h.sheet_id,
           -- held since the sheet was published, or since the mark was made held after it
           greatest(coalesce(sh.published_at, h.entered_at), h.entered_at),
           (current_date - greatest(coalesce(sh.published_at, h.entered_at), h.entered_at)::date)::int,
           m.ref, m.stage
      FROM h
      JOIN assessment.score_sheet sh ON sh.id = h.sheet_id AND sh.stage = 'PUBLISHED'
      JOIN catalogue.offering o ON o.id = sh.offering_id
      JOIN catalogue.course c ON c.code = o.course_code
      JOIN ref.department d ON d.code = c.dept_code
      JOIN people.student st ON st.id = h.student_id
      LEFT JOIN LATERAL (SELECT a.ref, a.stage FROM assessment.amendment a
                          WHERE a.sheet_id = h.sheet_id AND a.student_id = h.student_id AND a.stage NOT IN ('APPLIED', 'REFUSED', 'WITHDRAWN')
                          LIMIT 1) m ON true
     WHERE (p_fac IS NULL OR d.faculty_code = p_fac)
       AND (p_dept IS NULL OR c.dept_code = p_dept)
       AND (p_prog IS NULL OR st.programme_code = p_prog)
       AND (p_session IS NULL OR o.session = p_session)
     ORDER BY 14 DESC, o.course_code, st.surname, st.other_names
$fn$;
COMMENT ON FUNCTION assessment.held_results(text, text, text, text) IS
  'V424: every result held for the Senate (withheld, incomplete, malpractice — the latest version of the mark, on a published sheet) in a faculty, department, programme or session (all when NULL): the student, the course, since when and how many days, and the amendment carrying the decision when one is open.';

CREATE TABLE assessment.held_reminder_log (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sent_at    timestamptz NOT NULL DEFAULT now(),
    held       integer NOT NULL,
    oldest     integer NOT NULL,
    recipients integer NOT NULL
);
SELECT audit.attach('assessment.held_reminder_log');
COMMENT ON TABLE assessment.held_reminder_log IS
  'V424: each reminder of the results held for the Senate past the University''s days — how many, the oldest in days, and how many officers were told.';

/* the Registry told of the results held past the University's days — once a week at most; returns the officers told */
CREATE FUNCTION assessment.remind_held_results()
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE v_days int := policy.held_remind_days(); v_n int; v_oldest int; v_told int := 0; r record;
        v_from text := coalesce((SELECT name FROM platform.institution_profile LIMIT 1), 'the University');
BEGIN
    IF v_days = 0 THEN RETURN 0; END IF;
    IF EXISTS (SELECT 1 FROM assessment.held_reminder_log l WHERE l.sent_at > now() - interval '7 days') THEN RETURN 0; END IF;
    SELECT count(*), max(h.days) INTO v_n, v_oldest FROM assessment.held_results(NULL, NULL, NULL, NULL) h WHERE h.days >= v_days;
    IF coalesce(v_n, 0) = 0 THEN RETURN 0; END IF;
    FOR r IN
        SELECT DISTINCT ON (a.person_id) a.person_id, h.name, h.email
          FROM iam.office_assignment a
          JOIN iam.person pe ON pe.id = a.person_id
         CROSS JOIN LATERAL assessment.staff_reach(a.person_id) h
         WHERE a.office_code IN ('registrar', 'dregistrar', 'records')
           AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) AND pe.ended_on IS NULL
         ORDER BY a.person_id
    LOOP
        IF platform.queue_notice('EMAIL', r.email,
               v_n || ' result' || CASE WHEN v_n = 1 THEN '' ELSE 's' END || ' held for the Senate''s decision',
               'Dear ' || coalesce(r.name, 'colleague') || E',\n\n' || v_n || ' result' || CASE WHEN v_n = 1 THEN ' has' ELSE 's have' END
               || ' been held for the Senate''s decision (withheld, incomplete or a malpractice case) for more than ' || v_days || ' days; the oldest for '
               || v_oldest || E' days. While a result is held the student''s semester is not complete and no standing is pronounced on it.\n\n'
               || E'Open the University portal: Result pipeline, "Held for the Senate", for the list. The Senate''s decision is recorded as an amendment of the mark.\n\n'
               || v_from || ' — Examinations and Records',
               'person', r.person_id) IS NOT NULL THEN
            v_told := v_told + 1;
        END IF;
    END LOOP;
    INSERT INTO assessment.held_reminder_log (held, oldest, recipients) VALUES (v_n, v_oldest, v_told);
    RETURN v_told;
END $fn$;
COMMENT ON FUNCTION assessment.remind_held_results() IS
  'V424: the Registrar, the Deputy Registrar and Exams and Records told by email of the results held for the Senate longer than policy.standing_setting.held_remind_days — at most once a week; nothing when none is that old or the days are 0.';

-- ── 2 · who the absent rule (V422) now affects ──
CREATE FUNCTION assessment.absence_carryovers(p_fac text, p_dept text, p_prog text)
RETURNS TABLE(student_id uuid, number text, name text, programme_code text, programme text, level integer, status text,
              course_code text, title text, units integer, absent_in text)
LANGUAGE sql STABLE AS $fn$
    WITH ab AS (
        SELECT DISTINCT sc.student_id, o.course_code, o.session || ' semester ' || o.semester AS absent_in
          FROM assessment.score sc
          JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id AND sh.stage = 'PUBLISHED'
          JOIN catalogue.offering o ON o.id = sh.offering_id
         WHERE sc.outcome = 'ABSENT'
           AND NOT EXISTS (SELECT 1 FROM assessment.score n WHERE n.sheet_id = sc.sheet_id AND n.student_id = sc.student_id AND n.version > sc.version)),
    who AS (
        SELECT DISTINCT ab.student_id FROM ab
          JOIN people.student st ON st.id = ab.student_id
          JOIN ref.programme p ON p.code = st.programme_code
         -- the students still on the register: a graduate or a withdrawal owes no course
         WHERE st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION', 'DEFERRED', 'SUSPENDED', 'RUSTICATED', 'DORMANT')
           AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR st.programme_code = p_prog)),
    -- each student's carryovers, read once
    co AS (SELECT who.student_id, x.course_code, x.title, x.units, x.failed_in FROM who CROSS JOIN LATERAL registration.carryovers(who.student_id) x)
    SELECT st.id, coalesce(st.matric_no, st.admission_no), upper(st.surname) || ', ' || st.other_names, st.programme_code, p.name,
           st.current_level, st.status, co.course_code, co.title, co.units, co.failed_in
      FROM co
      JOIN ab ON ab.student_id = co.student_id AND ab.course_code = co.course_code AND ab.absent_in = co.failed_in
      JOIN people.student st ON st.id = co.student_id
      JOIN ref.programme p ON p.code = st.programme_code
     -- owed only because of the absence: no graded F of the same course still owed (that was owed before V422)
     WHERE NOT EXISTS (SELECT 1 FROM co f WHERE f.student_id = co.student_id AND f.course_code = co.course_code
                         AND NOT EXISTS (SELECT 1 FROM ab x WHERE x.student_id = f.student_id AND x.course_code = f.course_code AND x.absent_in = f.failed_in))
     ORDER BY p.name, st.current_level, st.surname, st.other_names, co.course_code
$fn$;
COMMENT ON FUNCTION assessment.absence_carryovers(text, text, text) IS
  'V424: the students still on the register (in a faculty, department or programme, or all when NULL) owing a course only because of a recorded absence (V422) — for the Registry before registration. A course also owed for a graded F was owed before and is not listed. Reads only.';

CREATE FUNCTION finance.gst_eps_owed_for_absence(p_session text)
RETURNS TABLE(student_id uuid, number text, name text, programme text, level integer, course_code text, title text, office text,
              absent_in text, owed_this_session boolean, status text)
LANGUAGE sql STABLE AS $fn$
    WITH ab AS (
        SELECT DISTINCT sc.student_id, o.course_code, o.session || ' semester ' || o.semester AS absent_in
          FROM assessment.score sc
          JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id AND sh.stage = 'PUBLISHED'
          JOIN catalogue.offering o ON o.id = sh.offering_id
          JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' AND c.general_office IS NOT NULL
         WHERE sc.outcome = 'ABSENT' AND o.session < p_session
           AND NOT EXISTS (SELECT 1 FROM assessment.score n WHERE n.sheet_id = sc.sheet_id AND n.student_id = sc.student_id AND n.version > sc.version))
    SELECT st.id, coalesce(st.matric_no, st.admission_no), upper(st.surname) || ', ' || st.other_names, p.name, g.level,
           g.course_code, g.title, g.office, g.failed_in, g.counts, g.status
      FROM (SELECT DISTINCT ab.student_id FROM ab) s
     CROSS JOIN LATERAL finance.gst_eps_rows(p_session, s.student_id) g
      -- owed as a carryover, and the carryover is the absence itself
      JOIN ab ON ab.student_id = s.student_id AND ab.course_code = g.course_code AND ab.absent_in = g.failed_in
      JOIN people.student st ON st.id = s.student_id
      JOIN ref.programme p ON p.code = st.programme_code
     WHERE g.source = 'CARRYOVER'
     ORDER BY g.counts DESC, p.name, st.surname, st.other_names, g.course_code
$fn$;
COMMENT ON FUNCTION finance.gst_eps_owed_for_absence(text) IS
  'V424: the students who owe a GST/EPS course again in a session because they were recorded absent from it before (V422) — the course, the office, the absence, whether it is owed this session and where it stands. For the Bursary. Reads only.';

COMMIT;
