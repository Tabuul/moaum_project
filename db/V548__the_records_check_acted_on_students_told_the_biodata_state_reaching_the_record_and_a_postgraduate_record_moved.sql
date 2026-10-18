-- V548: the records check acted on — the students with no state of origin told, a state given on the Biodata form reaching
-- the record, and a postgraduate record moved to its programme.
--
-- The Registry's Records Check (V536) lists 423 live undergraduates with no state of origin on the live-shaped copy and three
-- postgraduate records on undergraduate programmes. It said the student gives the state "on the biodata form", but the form
-- writes people.biodata, and the record the fees and the check read is people.student.state_of_origin (with the admission's
-- state behind it): nothing a student or the Registry gave on the form reached it (307 students' forms on the copy name a state
-- the record does not hold).
--   * A state given on the Biodata form reaches the record: given by an office (the Registry on the student's page), always; given
--     by the student, only where neither the record nor the admission holds one, and never the home state (Benue) — a home-state
--     indigene pays less, which the Registry grants from the certificate of indigeneship by giving the state on the student's
--     Biodata. A value that is not a state of the register changes nothing. The students the form already names a state for
--     (not the home state) are given it now.
--   * people.tell_record_issue('NO_STATE_OF_ORIGIN'): the students listed are told through the notice engine (template
--     RECORD_STATE_OF_ORIGIN; e-mail, SMS and portal) at most once a week each — not one who has given the home state and waits
--     for the Registry — each telling kept in people.record_issue_notice; people.record_issue_progress shows how many were told,
--     have since given it, still have not, were never told, and the notices' delivery.
--   * people.move_record_to_programme: a postgraduate record on an undergraduate programme (the postgraduate entry mode, or a
--     level of 700 and above) is moved by the Registry or the School of Postgraduate Studies to a postgraduate programme at 700,
--     800 or 900 Level with the entry mode POSTGRADUATE, with a reason, kept in people.record_move and on the audit spine; any
--     other change of programme stays a transfer. people.record_move_options names the department's postgraduate programmes first.
--   * people.record_issues restated from V542: for a missing state, what the student gave on the form (the home state to
--     confirm, or a value that is not a state).

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'records', true);
SELECT set_config('moaum.reason', 'V548: the records check acted on — students told, the Biodata form''s state reaching the record, a postgraduate record moved', true);

-- ── a state given on the Biodata form reaches the record ──
CREATE FUNCTION people.biodata_state_to_record() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE v_name text; v_now text; v_home text; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor text := nullif(current_setting('moaum.actor_id', true), '');
BEGIN
    v_name := ref.state_named(NEW.value);
    IF v_name IS NULL OR v_office IS NULL THEN RETURN NEW; END IF;   -- not a state of the register, or an import: nothing changes
    SELECT coalesce(nullif(btrim(s.state_of_origin), ''), nullif(btrim(r.state_of_origin), '')) INTO v_now
      FROM people.student s
      LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
      LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
     WHERE s.id = NEW.student_id;
    IF lower(coalesce(v_now, '')) = lower(v_name) THEN RETURN NEW; END IF;
    IF v_office = 'student' OR v_actor = NEW.student_id::text THEN
        -- the student's own answer fills an empty record only, and never with the home state
        IF v_now IS NOT NULL THEN RETURN NEW; END IF;
        SELECT fs.home_state INTO v_home FROM finance.fee_setting fs WHERE fs.id = 1;
        IF lower(v_name) = lower(coalesce(v_home, '')) THEN RETURN NEW; END IF;
    END IF;
    UPDATE people.student SET state_of_origin = v_name WHERE id = NEW.student_id;
    RETURN NEW;
END $fn$;
COMMENT ON FUNCTION people.biodata_state_to_record() IS
  'V548: a state of origin given on the Biodata form reaches people.student — by an office always; by the student only where the record and the admission hold none, and never the home state (the Registry grants it from the certificate of indigeneship)';
CREATE TRIGGER trg_biodata_state_to_record AFTER INSERT OR UPDATE OF value ON people.biodata
    FOR EACH ROW WHEN (NEW.field = 'state_of_origin') EXECUTE FUNCTION people.biodata_state_to_record();

-- the students whose form already names a state (not the home state) while the record and the admission hold none
DO $$
DECLARE n_given int; n_home int;
BEGIN
    WITH c AS MATERIALIZED (
        SELECT s.id, ref.state_named(b.value) AS named
          FROM people.student s
          JOIN people.biodata b ON b.student_id = s.id AND b.field = 'state_of_origin' AND btrim(b.value) <> ''
          LEFT JOIN admissions.candidate ca ON ca.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = ca.admitted_from
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
           AND nullif(btrim(s.state_of_origin), '') IS NULL AND nullif(btrim(r.state_of_origin), '') IS NULL),
    home AS (SELECT lower(fs.home_state) AS h FROM finance.fee_setting fs WHERE fs.id = 1),
    given AS (
        UPDATE people.student s SET state_of_origin = c.named
          FROM c WHERE s.id = c.id AND c.named IS NOT NULL AND lower(c.named) <> coalesce((SELECT h FROM home), '')
        RETURNING 1)
    SELECT (SELECT count(*) FROM given), (SELECT count(*) FROM c WHERE lower(c.named) = (SELECT h FROM home)) INTO n_given, n_home;
    RAISE NOTICE 'V548: % student(s) given the state their Biodata form names; % gave the home state and wait for the Registry', n_given, n_home;
END $$;

-- ── the students told ──
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
  ('RECORD_STATE_OF_ORIGIN', 'State of origin missing',
   'Sent from the Registry''s Records Check to a student whose record has no state of origin; at most once a week, none once it is given.',
   'Give your state of origin on the student portal',
   E'Dear [FIRST_NAME],\n\nYour record on the [UNIVERSITY_NAME] portal has no state of origin. The school fee depends on it: until it is given, you are charged as a non-indigene.\n\nSign in at [PORTAL_URL], open Biodata and choose your state of origin. If you are an indigene of [HOME_STATE] State, bring your certificate of indigeneship to the Registry (Records), who confirm it on your record.\n\nRegistry, [UNIVERSITY_NAME]',
   '[UNIVERSITY_SHORT]: your portal record has no state of origin. Sign in at [PORTAL_URL], open Biodata and choose it. [HOME_STATE] indigenes: show the Registry your certificate of indigeneship.',
   'Give your state of origin',
   'Your record has no state of origin, so the school fee reads you as a non-indigene. Open Biodata and choose it; an indigene of [HOME_STATE] State also shows the Registry the certificate of indigeneship.',
   ARRAY['FIRST_NAME', 'PORTAL_URL', 'UNIVERSITY_NAME', 'UNIVERSITY_SHORT', 'HOME_STATE'], true, 'NORMAL');

CREATE TABLE people.record_issue_notice (
    issue      text NOT NULL REFERENCES people.record_issue_kind (code),
    student_id uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    week       text NOT NULL CHECK (week ~ '^[0-9]{4}-W[0-9]{2}$'),
    told_at    timestamptz NOT NULL DEFAULT now(),
    told_by    uuid NOT NULL,
    queued     integer NOT NULL,
    PRIMARY KEY (issue, student_id, week)
);
CREATE INDEX ix_record_issue_notice_student ON people.record_issue_notice (student_id);
COMMENT ON TABLE people.record_issue_notice IS 'V548: each telling of a student about an issue of the records check, at most one a week';
SELECT audit.attach('people.record_issue_notice');

CREATE FUNCTION people.tell_record_issue(p_issue text, p_faculty text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_week text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'IYYY-"W"IW');
        v_home text; r record; v_q int; n_listed int := 0; n_told int := 0; n_before int := 0; n_waiting int := 0; n_unreached int := 0;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'RECORD_TELL_ACTOR: students are told by a person' USING ERRCODE = '23514'; END IF;
    IF upper(btrim(coalesce(p_issue, ''))) <> 'NO_STATE_OF_ORIGIN' THEN
        RAISE EXCEPTION 'RECORD_TELL_ISSUE: only a missing state of origin is the student''s to give; the other issues are corrected by an office'
            USING ERRCODE = '23514';
    END IF;
    SELECT fs.home_state INTO v_home FROM finance.fee_setting fs WHERE fs.id = 1;
    FOR r IN
        SELECT DISTINCT x.student_id,
               EXISTS (SELECT 1 FROM people.biodata b WHERE b.student_id = x.student_id AND b.field = 'state_of_origin'
                          AND lower(btrim(b.value)) = lower(coalesce(v_home, ''))) AS gave_home
          FROM people.record_issues('NO_STATE_OF_ORIGIN', p_faculty) x
    LOOP
        n_listed := n_listed + 1;
        IF r.gave_home THEN n_waiting := n_waiting + 1; CONTINUE; END IF;   -- done their part: the Registry confirms
        IF EXISTS (SELECT 1 FROM people.record_issue_notice n WHERE n.issue = 'NO_STATE_OF_ORIGIN' AND n.student_id = r.student_id AND n.week = v_week) THEN
            n_before := n_before + 1; CONTINUE;
        END IF;
        v_q := coalesce(platform.tell_student(r.student_id, 'RECORD_STATE_OF_ORIGIN', NULL, jsonb_build_object('HOME_STATE', coalesce(v_home, 'Benue')),
                                              'record-state:' || v_week || ':' || r.student_id), 0);
        INSERT INTO people.record_issue_notice (issue, student_id, week, told_by, queued) VALUES ('NO_STATE_OF_ORIGIN', r.student_id, v_week, v_actor, v_q);
        IF v_q = 0 THEN n_unreached := n_unreached + 1; ELSE n_told := n_told + 1; END IF;
    END LOOP;
    RETURN jsonb_build_object('issue', 'NO_STATE_OF_ORIGIN', 'week', v_week, 'listed', n_listed, 'told', n_told, 'toldThisWeekAlready', n_before,
                              'waitingForRegistry', n_waiting, 'unreached', n_unreached);
END $fn$;
COMMENT ON FUNCTION people.tell_record_issue(text, text) IS
  'V548: tell the students with no state of origin (of one faculty, or all) to give it — template RECORD_STATE_OF_ORIGIN, at most once a week each, not one who gave the home state and waits for the Registry';

CREATE FUNCTION people.record_issue_progress(p_issue text, p_faculty text DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql STABLE AS $fn$
    WITH listed AS MATERIALIZED (SELECT DISTINCT x.student_id FROM people.record_issues(upper(p_issue), p_faculty) x),
    told AS MATERIALIZED (
        SELECT n.student_id, max(n.told_at) AS last_at, max(n.week) AS last_week
          FROM people.record_issue_notice n
          JOIN people.student s ON s.id = n.student_id
          LEFT JOIN ref.programme pr ON pr.code = s.programme_code
         WHERE n.issue = upper(p_issue) AND (p_faculty IS NULL OR pr.faculty_code = p_faculty)
         GROUP BY n.student_id),
    home AS (SELECT lower(fs.home_state) AS h FROM finance.fee_setting fs WHERE fs.id = 1),
    notes AS (
        SELECT pn.channel, pn.state, pn.delivery_state
          FROM people.record_issue_notice t
          JOIN told ON told.student_id = t.student_id
          JOIN platform.notice pn ON pn.event_key = 'record-state:' || t.week || ':' || t.student_id
                                 AND pn.about_kind = 'student' AND pn.about_id = t.student_id
         WHERE t.issue = upper(p_issue))
    SELECT jsonb_build_object(
        'issue', upper(p_issue), 'faculty', p_faculty,
        'week', to_char(now() AT TIME ZONE 'Africa/Lagos', 'IYYY-"W"IW'),
        'listed', (SELECT count(*) FROM listed),
        'told', (SELECT count(*) FROM told),
        'toldThisWeek', (SELECT count(*) FROM told WHERE told.last_week = to_char(now() AT TIME ZONE 'Africa/Lagos', 'IYYY-"W"IW')),
        'givenSince', (SELECT count(*) FROM told t WHERE NOT EXISTS (SELECT 1 FROM listed l WHERE l.student_id = t.student_id)),
        'stillMissing', (SELECT count(*) FROM told t JOIN listed l ON l.student_id = t.student_id),
        'neverTold', (SELECT count(*) FROM listed l WHERE NOT EXISTS (SELECT 1 FROM told t WHERE t.student_id = l.student_id)),
        'waitingForRegistry', (SELECT count(*) FROM listed l JOIN people.biodata b ON b.student_id = l.student_id AND b.field = 'state_of_origin'
                                WHERE lower(btrim(b.value)) = (SELECT h FROM home)),
        -- those "Tell the students" would tell now: listed, not told this week, not waiting for the Registry
        'toTell', (SELECT count(*) FROM listed l
                    WHERE NOT EXISTS (SELECT 1 FROM told t WHERE t.student_id = l.student_id AND t.last_week = to_char(now() AT TIME ZONE 'Africa/Lagos', 'IYYY-"W"IW'))
                      AND NOT EXISTS (SELECT 1 FROM people.biodata b WHERE b.student_id = l.student_id AND b.field = 'state_of_origin'
                                         AND lower(btrim(b.value)) = (SELECT h FROM home))),
        'lastTold', (SELECT max(last_at) FROM told),
        'notices', (SELECT coalesce(jsonb_agg(jsonb_build_object('channel', x.channel, 'state', x.state, 'n', x.n) ORDER BY x.channel, x.state), '[]'::jsonb)
                      FROM (SELECT notes.channel, coalesce(notes.delivery_state, notes.state) AS state, count(*) AS n FROM notes GROUP BY 1, 2) x))
$fn$;
COMMENT ON FUNCTION people.record_issue_progress(text, text) IS
  'V548: of an issue the students are told about (of one faculty, or all) — listed now, told (ever, this week), given since, still missing, never told, waiting for the Registry, and the notices by channel and state';

-- ── a postgraduate record moved to its programme ──
CREATE TABLE people.record_move (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id     uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    from_programme text,
    to_programme   text NOT NULL REFERENCES ref.programme (code),
    from_level     integer,
    to_level       integer NOT NULL CHECK (to_level IN (700, 800, 900)),
    from_entry     text,
    reason         text NOT NULL CHECK (length(btrim(reason)) >= 10),
    moved_by       uuid NOT NULL,
    moved_office   text,
    moved_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_record_move_student ON people.record_move (student_id);
CREATE INDEX ix_record_move_programme ON people.record_move (to_programme);
COMMENT ON TABLE people.record_move IS 'V548: a postgraduate record on an undergraduate programme moved to a postgraduate programme, by whom and why';
SELECT audit.attach('people.record_move');

-- what moving a student's record would offer: the student, whether it may be moved, and the postgraduate programmes (the department's first)
CREATE FUNCTION people.record_move_options(p_student uuid)
RETURNS jsonb
LANGUAGE sql STABLE AS $fn$
    SELECT jsonb_build_object(
        'student', jsonb_build_object('id', s.id, 'name', btrim(coalesce(s.surname, '') || ', ' || coalesce(s.other_names, ''), ', '),
                                      'number', coalesce(s.matric_no, s.admission_no), 'programmeCode', s.programme_code, 'programme', p.name,
                                      'category', p.category, 'department', p.dept_code, 'level', s.current_level, 'entryMode', s.entry_mode, 'status', s.status),
        'movable', s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION') AND coalesce(p.category, '') <> 'POST GRADUATE'
                   AND (s.entry_mode = 'POSTGRADUATE' OR s.current_level >= 700),
        'registrations', (SELECT count(*) FROM registration.course_registration cr WHERE cr.student_id = s.id),
        'moves', (SELECT coalesce(jsonb_agg(jsonb_build_object('from', m.from_programme, 'to', m.to_programme, 'level', m.to_level, 'reason', m.reason, 'at', m.moved_at)
                                            ORDER BY m.moved_at DESC), '[]'::jsonb) FROM people.record_move m WHERE m.student_id = s.id),
        'options', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', g.code, 'name', g.name, 'department', g.dept_code, 'sameDepartment', g.dept_code = p.dept_code)
                                              ORDER BY g.dept_code IS DISTINCT FROM p.dept_code, g.name), '[]'::jsonb)
                      FROM ref.programme g WHERE g.category = 'POST GRADUATE' AND NOT g.archived))
      FROM people.student s
      LEFT JOIN ref.programme p ON p.code = s.programme_code
     WHERE s.id = p_student
$fn$;
COMMENT ON FUNCTION people.record_move_options(uuid) IS
  'V548: a student''s record, whether it is a postgraduate record on an undergraduate programme (movable), and the postgraduate programmes to move it to, the department''s first';

CREATE FUNCTION people.move_record_to_programme(p_student uuid, p_programme text, p_level integer, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; s record; g record;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'RECORD_MOVE_ACTOR: a record is moved by a person' USING ERRCODE = '23514'; END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'RECORD_MOVE_REASON: say why the record is moved (the admission letter, the School''s list…)' USING ERRCODE = '23514';
    END IF;
    SELECT st.id, st.programme_code, st.current_level, st.entry_mode, st.status, pr.category INTO s
      FROM people.student st LEFT JOIN ref.programme pr ON pr.code = st.programme_code
     WHERE st.id = p_student FOR UPDATE OF st;
    IF NOT FOUND THEN RAISE EXCEPTION 'RECORD_MOVE_STUDENT: no such student' USING ERRCODE = '23514'; END IF;
    IF s.status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') OR coalesce(s.category, '') = 'POST GRADUATE'
       OR NOT (s.entry_mode = 'POSTGRADUATE' OR coalesce(s.current_level, 0) >= 700) THEN
        RAISE EXCEPTION 'RECORD_MOVE_NOT_POSTGRADUATE: only a live postgraduate record on an undergraduate programme is moved here; any other change of programme is a transfer'
            USING ERRCODE = '23514';
    END IF;
    SELECT code, category, archived INTO g FROM ref.programme WHERE code = upper(btrim(coalesce(p_programme, '')));
    IF NOT FOUND OR g.archived OR g.category IS DISTINCT FROM 'POST GRADUATE' THEN
        RAISE EXCEPTION 'RECORD_MOVE_PROGRAMME: choose a postgraduate programme on the register' USING ERRCODE = '23514';
    END IF;
    IF p_level IS NULL OR p_level NOT IN (700, 800, 900) THEN
        RAISE EXCEPTION 'RECORD_MOVE_LEVEL: a postgraduate student is at 700 (a postgraduate diploma), 800 (a master''s) or 900 (a doctorate)' USING ERRCODE = '23514';
    END IF;
    UPDATE people.student SET programme_code = g.code, current_level = p_level, entry_mode = 'POSTGRADUATE' WHERE id = p_student;
    INSERT INTO people.record_move (student_id, from_programme, to_programme, from_level, to_level, from_entry, reason, moved_by, moved_office)
    VALUES (p_student, s.programme_code, g.code, s.current_level, p_level, s.entry_mode, btrim(p_reason), v_actor, nullif(current_setting('moaum.actor_office', true), ''));
    RETURN jsonb_build_object('student', p_student, 'from', s.programme_code, 'to', g.code, 'fromLevel', s.current_level, 'level', p_level,
                              'fromEntry', s.entry_mode, 'entryMode', 'POSTGRADUATE');
END $fn$;
COMMENT ON FUNCTION people.move_record_to_programme(uuid, text, integer, text) IS
  'V548: a live postgraduate record on an undergraduate programme moved to a postgraduate programme at 700/800/900 Level, entry mode POSTGRADUATE, with the reason (people.record_move)';

UPDATE people.record_issue_kind
   SET corrects = 'Student (on the Biodata form); Registry (Records) for the home state',
       how = 'Tell the students from this page (at most once a week each): the state a student chooses on the Biodata form reaches the record — except the home state, which the Registry confirms from the certificate of indigeneship by giving it on the student''s Biodata.'
 WHERE code = 'NO_STATE_OF_ORIGIN';
UPDATE people.record_issue_kind
   SET how = 'Give the entry mode the student was admitted by (UTME, Direct Entry, Transfer) — or, for a postgraduate student, move the record to the postgraduate programme from this page, with the reason.'
 WHERE code = 'UG_POSTGRADUATE_ENTRY';

-- ── V542's people.record_issues, with what the student gave on the Biodata form for a missing state ──
CREATE OR REPLACE FUNCTION people.record_issues(p_issue text DEFAULT NULL::text, p_faculty text DEFAULT NULL::text)
 RETURNS TABLE(student_id uuid, matric_no text, admission_no text, name text, faculty_code text, faculty text, programme_code text, programme text, current_level integer, entry_mode text, status text, state text, final_level integer, issue text, suggestion text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH allowed AS (SELECT coalesce((SELECT max_spillover_years FROM policy.progression_setting ORDER BY row_no LIMIT 1), 2) AS years),
    -- V541/V542: held, so the final level is read once a programme; inlined, it was read for every student joined to it
    fl AS MATERIALIZED (SELECT pr.code, finance.final_level(pr.code) AS final FROM ref.programme pr),
    st AS (SELECT lower(name) AS name FROM ref.state),
    live AS (
        SELECT s.id, s.matric_no, s.admission_no, btrim(coalesce(s.surname, '') || ', ' || coalesce(s.other_names, ''), ', ') AS name,
               p.faculty_code, p.dept_code, s.programme_code, p.name AS programme, p.category, p.archived, p.code IS NULL AS no_programme,
               s.current_level, s.entry_mode, s.status, fl.final,
               coalesce(nullif(btrim(s.state_of_origin), ''), nullif(btrim(r.state_of_origin), '')) AS state,
               people.is_postgraduate(s.entry_mode, p.category) AS pg_student
          FROM people.student s
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN fl ON fl.code = s.programme_code
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
           AND (p_faculty IS NULL OR p.faculty_code = p_faculty)),
    -- V542: each spelling read once — a state of the register, or a country (a student from abroad is not listed)
    spelt AS MATERIALIZED (
        SELECT d.state, ref.state_named(d.state) AS state_name, ref.country_named(d.state) AS country_name
          FROM (SELECT DISTINCT l.state FROM live l WHERE l.state IS NOT NULL) d
         WHERE NOT EXISTS (SELECT 1 FROM st WHERE st.name = lower(d.state))),
    found AS (
        SELECT l.*, x.issue
          FROM live l
         CROSS JOIN LATERAL (VALUES
            (CASE WHEN l.category IS DISTINCT FROM 'POST GRADUATE' AND NOT l.no_programme AND l.final IS NOT NULL
                       AND l.current_level > l.final + 100 * (SELECT years FROM allowed) THEN 'LEVEL_BEYOND_PROGRAMME' END),
            (CASE WHEN l.category IS DISTINCT FROM 'POST GRADUATE' AND NOT l.no_programme AND l.entry_mode = 'POSTGRADUATE' THEN 'UG_POSTGRADUATE_ENTRY' END),
            (CASE WHEN l.category = 'POST GRADUATE' AND l.current_level < 700 THEN 'PG_UNDERGRADUATE_LEVEL' END),
            (CASE WHEN l.entry_mode = 'DIRECT_ENTRY' AND l.current_level = 100 THEN 'DIRECT_ENTRY_AT_100' END),
            (CASE WHEN nullif(btrim(l.entry_mode), '') IS NULL THEN 'NO_ENTRY_MODE' END),
            (CASE WHEN l.current_level IS NULL OR l.current_level NOT IN (100, 200, 300, 400, 500, 600, 700, 800, 900) THEN 'LEVEL_NOT_A_LEVEL' END),
            (CASE WHEN l.archived THEN 'PROGRAMME_ARCHIVED' END),
            (CASE WHEN l.no_programme THEN 'PROGRAMME_UNKNOWN' END),
            -- a fee reads indigeneship for an undergraduate; a postgraduate or CCE student's fee does not turn on it
            (CASE WHEN l.state IS NULL AND NOT l.pg_student AND l.entry_mode IS DISTINCT FROM 'CCE' THEN 'NO_STATE_OF_ORIGIN' END),
            (CASE WHEN EXISTS (SELECT 1 FROM spelt sp WHERE sp.state = l.state AND sp.country_name IS NULL) THEN 'STATE_NOT_ON_REGISTER' END)
         ) AS x(issue)
         WHERE x.issue IS NOT NULL AND (p_issue IS NULL OR x.issue = p_issue))
    SELECT f.id, f.matric_no, f.admission_no, f.name, f.faculty_code, fa.name, f.programme_code, f.programme, f.current_level, f.entry_mode,
           f.status, f.state, f.final, f.issue,
           -- V542: what the record most likely should say
           CASE WHEN f.issue = 'UG_POSTGRADUATE_ENTRY' OR (f.issue = 'LEVEL_BEYOND_PROGRAMME' AND f.current_level >= 700)
                     THEN CASE WHEN pg.list IS NOT NULL THEN 'Postgraduate programmes of the department: ' || pg.list
                               ELSE 'The department has no postgraduate programme on the register' END
                WHEN f.issue = 'STATE_NOT_ON_REGISTER'
                     THEN (SELECT 'The register''s name: ' || sp.state_name FROM spelt sp WHERE sp.state = f.state AND sp.state_name IS NOT NULL)
                -- V548: what the student gave on the Biodata form — the home state, for the Registry to confirm, or a value that is no state
                WHEN f.issue = 'NO_STATE_OF_ORIGIN'
                     THEN (SELECT CASE WHEN ref.state_named(b.value) IS NULL
                                       THEN 'The student gave "' || btrim(b.value) || '" on the Biodata form, which is not a state on the register'
                                       ELSE 'The student gave ' || ref.state_named(b.value) || ' on the Biodata form'
                                            || coalesce(' on ' || to_char(b.updated_at AT TIME ZONE 'Africa/Lagos', 'FMDD Mon YYYY'), '')
                                            || ': confirm it from the certificate of indigeneship and give it on the student''s Biodata' END
                             FROM people.biodata b WHERE b.student_id = f.id AND b.field = 'state_of_origin' AND btrim(b.value) <> '')
           END
      FROM found f
      LEFT JOIN ref.faculty fa ON fa.code = f.faculty_code
      LEFT JOIN (SELECT pp.dept_code, string_agg(pp.name || ' (' || pp.code || ')', '; ' ORDER BY pp.name) AS list
                   FROM ref.programme pp WHERE pp.category = 'POST GRADUATE' AND NOT pp.archived GROUP BY pp.dept_code) pg ON pg.dept_code = f.dept_code
     ORDER BY f.issue, fa.name NULLS FIRST, f.programme, f.current_level, f.matric_no NULLS LAST, f.name
$function$;

COMMENT ON FUNCTION people.record_issues(text, text) IS
  'V536/V542/V548: the live students (ADMITTED, ACTIVE, PROBATION) whose record is inconsistent, by issue (people.record_issue_kind), with what it most likely should say (for a missing state, what the student gave on the Biodata form); optionally of one issue and one faculty';

COMMIT;
