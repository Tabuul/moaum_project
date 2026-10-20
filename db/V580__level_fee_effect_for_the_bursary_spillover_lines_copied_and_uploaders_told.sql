-- V580: the Bursary's whole picture before levels are corrected, last session's spillover lines copied on their own, and the
-- office that uploaded a contact told what became of it.
--
--   * The fee effect of every waiting level correction. V576 reads it for one batch; on the live-shaped copy of 20 October 2026
--     the first 500 spillover corrections alone take their 2025/2026 charges from ₦83.6m to ₦44.0m. A run
--     (people.level_fee_effect_run, one at a time) reads every correction waiting on the bases chosen, 500 at a time
--     (people.level_fee_effect_step, the levels raised and undone, with the basis of its start held for the whole run) and keeps
--     each student's charges now and after (people.level_fee_effect_row); people.level_fee_effect_report sums them for the
--     University, each faculty and each programme. Nothing is changed.
--   * finance.copy_spillover_lines(from, to, apply): the spillover lines of one session copied into another on their own, a
--     line the target already states kept (finance.copy_session_fees' rule, restricted to spillover lines); previewed first.
--   * policy.transition_readiness (restated from V400's text): SPILLOVER_FEE_LINES — the spillover students the session's fees
--     charge nothing, by the basis in force; said, never holding the transition nor the automatic clock.
--   * people.contact_refuse (restated from V575's text) tells the person who uploaded a contact the student says is not theirs
--     (template CONTACT_UPLOAD_REJECTED); people.chase_unconfirmed_contacts tells them each week of an upload a month old whose
--     contacts still wait for the students (CONTACT_UPLOAD_WAITING).

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'bursar', true);
SELECT set_config('moaum.reason', 'V580: level fee effect, spillover lines copied, uploaders told', true);

-- ── the fee effect of every waiting level correction ───────────────────────────────────────────────────────────────────────
CREATE TABLE people.level_fee_effect_run (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session        text NOT NULL,
    basis          text NOT NULL CHECK (basis IN ('LEVEL', 'COHORT')),
    bases          text[] NOT NULL,
    state          text NOT NULL DEFAULT 'RUNNING' CHECK (state IN ('RUNNING', 'DONE', 'FAILED')),
    students       integer NOT NULL DEFAULT 0,
    done           integer NOT NULL DEFAULT 0,
    error          text,
    started_by     uuid,
    started_office text,
    started_at     timestamptz NOT NULL DEFAULT now(),
    finished_at    timestamptz
);
CREATE UNIQUE INDEX ux_level_fee_effect_running ON people.level_fee_effect_run ((true)) WHERE state = 'RUNNING';
COMMENT ON TABLE people.level_fee_effect_run IS
  'V580: a reading of what correcting every waiting level would do to the current session''s charges — who started it, the basis held, how far it got';
SELECT audit.attach('people.level_fee_effect_run');

CREATE TABLE people.level_fee_effect_row (
    run_id        uuid NOT NULL REFERENCES people.level_fee_effect_run (id) ON DELETE CASCADE,
    student_id    uuid NOT NULL,
    basis         text,
    current_level integer,
    new_level     integer,
    charged_now   numeric,
    charged_after numeric,
    PRIMARY KEY (run_id, student_id)
);
CREATE INDEX ix_level_fee_effect_row_waiting ON people.level_fee_effect_row (run_id, student_id) WHERE charged_now IS NULL;
COMMENT ON TABLE people.level_fee_effect_row IS
  'V580: one student''s correction in a run (taken when it began) and the charges for the session now and with the corrected level, once read';
SELECT audit.exempt('people.level_fee_effect_row', 'a figure worked out from the record and the fee schedule, read back in a report; nothing on the record changes');

-- a run begun: the corrections waiting on the bases taken as they stand, the session and the basis held for it; one at a time
-- (an hour-old run is let go)
CREATE FUNCTION people.start_level_fee_effect(p_bases text[])
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_bases text[] := coalesce(p_bases, ARRAY['SPILLOVER', 'REGISTRATION']); v_id uuid; n int;
BEGIN
    IF EXISTS (SELECT 1 FROM unnest(v_bases) b WHERE b NOT IN ('SPILLOVER', 'REGISTRATION', 'ARITHMETIC')) THEN
        RAISE EXCEPTION 'LEVEL_CORRECTION_BASIS: a basis is SPILLOVER, REGISTRATION or ARITHMETIC' USING ERRCODE = '23514';
    END IF;
    UPDATE people.level_fee_effect_run SET state = 'FAILED', error = 'not finished within the hour', finished_at = now()
     WHERE state = 'RUNNING' AND started_at < now() - interval '1 hour';
    IF EXISTS (SELECT 1 FROM people.level_fee_effect_run WHERE state = 'RUNNING') THEN
        RAISE EXCEPTION 'LEVEL_EFFECT_RUNNING: the fee effect is being worked out already' USING ERRCODE = '23514';
    END IF;
    INSERT INTO people.level_fee_effect_run (session, basis, bases, started_by, started_office)
    VALUES (coalesce(policy.university_current_session(), ''), finance.spill_basis(), v_bases,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    RETURNING id INTO v_id;
    INSERT INTO people.level_fee_effect_row (run_id, student_id, basis, current_level, new_level)
    SELECT v_id, c.student_id, c.basis, c.current_level, c.proposed_level FROM people.level_correction c WHERE c.basis = ANY (v_bases);
    GET DIAGNOSTICS n = ROW_COUNT;
    UPDATE people.level_fee_effect_run SET students = n WHERE id = v_id;
    RETURN v_id;
END $fn$;

-- the next corrections of a run read (the levels raised and undone, the run's basis held); 0 once none is left, and the run done
CREATE FUNCTION people.level_fee_effect_step(p_run uuid, p_limit integer DEFAULT 500)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE r people.level_fee_effect_run; v_ids uuid[]; v_levels integer[]; n integer;
BEGIN
    SELECT * INTO r FROM people.level_fee_effect_run WHERE id = p_run FOR UPDATE;
    IF NOT FOUND OR r.state <> 'RUNNING' THEN
        RETURN 0;
    END IF;
    SELECT array_agg(x.student_id ORDER BY x.student_id), array_agg(x.new_level ORDER BY x.student_id)
      INTO v_ids, v_levels
      FROM (SELECT x.student_id, x.new_level FROM people.level_fee_effect_row x
             WHERE x.run_id = p_run AND x.charged_now IS NULL
             ORDER BY x.student_id
             LIMIT greatest(1, least(coalesce(p_limit, 500), 1000))) x;
    IF v_ids IS NULL THEN
        UPDATE people.level_fee_effect_run SET state = 'DONE', finished_at = now() WHERE id = p_run;
        RETURN 0;
    END IF;
    PERFORM set_config('moaum.spill_basis', r.basis, true);
    -- the level now is read again: a correction made since the run began reads as the same charge before and after
    UPDATE people.level_fee_effect_row x
       SET current_level = e.current_level, charged_now = coalesce(e.charged_now, 0), charged_after = coalesce(e.charged_after, 0)
      FROM finance.level_fee_effect(r.session, v_ids, v_levels) e
     WHERE x.run_id = p_run AND x.student_id = e.student_id;
    GET DIAGNOSTICS n = ROW_COUNT;
    -- a student the effect could not read (gone from the register) is counted at nothing either way, so the run ends
    UPDATE people.level_fee_effect_row x SET charged_now = 0, charged_after = 0
     WHERE x.run_id = p_run AND x.student_id = ANY (v_ids) AND x.charged_now IS NULL;
    PERFORM set_config('moaum.spill_basis', '', true);
    UPDATE people.level_fee_effect_run SET done = done + n WHERE id = p_run;
    RETURN n;
END $fn$;

-- the run summed for the University, each faculty and each programme
CREATE FUNCTION people.level_fee_effect_report(p_run uuid)
RETURNS TABLE (scope text, faculty_code text, faculty text, programme_code text, programme text, students bigint,
               charged_now numeric, charged_after numeric, more bigint, less bigint, same bigint, none_after bigint)
LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN grouping(f.code) = 1 THEN 'UNIVERSITY' WHEN grouping(p.code) = 1 THEN 'FACULTY' ELSE 'PROGRAMME' END,
           f.code, max(f.name), p.code, max(p.name), count(*),
           coalesce(sum(x.charged_now), 0), coalesce(sum(x.charged_after), 0),
           count(*) FILTER (WHERE x.charged_after > x.charged_now), count(*) FILTER (WHERE x.charged_after < x.charged_now),
           count(*) FILTER (WHERE x.charged_after = x.charged_now), count(*) FILTER (WHERE x.charged_after = 0)
      FROM people.level_fee_effect_row x
      JOIN people.student s ON s.id = x.student_id
      JOIN ref.programme p ON p.code = s.programme_code
      JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE x.run_id = p_run AND x.charged_now IS NOT NULL
     GROUP BY GROUPING SETS ((), (f.code), (f.code, p.code))
     ORDER BY grouping(f.code) DESC, max(f.name) NULLS FIRST, grouping(p.code) DESC, max(p.name) NULLS FIRST
$fn$;

-- ── a session's spillover lines copied on their own ────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.copy_spillover_lines(p_from text, p_to text, p_apply boolean)
RETURNS TABLE (item text, kind text, amount numeric, level integer, entry_mode text, faculty_code text, programme_code text, fee_group text,
               semester integer, indigene text, spillover boolean, ord integer, target_amount numeric, action text)
LANGUAGE plpgsql AS $fn$
BEGIN
    IF p_from IS NULL OR p_to IS NULL OR p_from = p_to THEN
        RAISE EXCEPTION 'FEE_COPY_SESSIONS: copy from one session into another' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_to) THEN
        RAISE EXCEPTION 'FEE_COPY_SESSION: % is not a session on the calendar', p_to USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM finance.fee_schedule f WHERE f.session = p_from AND f.ended_at IS NULL AND f.spillover) THEN
        RAISE EXCEPTION 'FEE_COPY_EMPTY: % states no spillover line to copy', p_from USING ERRCODE = '23514';
    END IF;
    IF p_apply AND nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'FEE_COPY_ACTOR: fees are copied by a person' USING ERRCODE = '23514';
    END IF;
    RETURN QUERY
    SELECT s.item, s.kind, s.amount, s.level, s.entry_mode, s.faculty_code, s.programme_code, s.fee_group, s.semester, s.indigene, s.spillover, s.ord,
           t.amount, CASE WHEN t.amount IS NULL THEN 'COPY' ELSE 'KEPT' END
      FROM finance.fee_schedule s
      LEFT JOIN LATERAL (SELECT x.amount FROM finance.fee_schedule x WHERE x.session = p_to AND x.ended_at IS NULL AND finance.fee_line_same_scope(x, s) LIMIT 1) t ON true
     WHERE s.session = p_from AND s.ended_at IS NULL AND s.spillover
     ORDER BY s.kind, s.ord, s.item, s.faculty_code NULLS FIRST, s.programme_code NULLS FIRST, s.level NULLS FIRST, s.semester NULLS FIRST;
    IF p_apply THEN
        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, ord, fee_group, semester, indigene, spillover, kind)
        SELECT p_to, s.item, s.amount, s.level, s.entry_mode, s.faculty_code, s.programme_code, s.ord, s.fee_group, s.semester, s.indigene, s.spillover, s.kind
          FROM finance.fee_schedule s
         WHERE s.session = p_from AND s.ended_at IS NULL AND s.spillover
           AND NOT EXISTS (SELECT 1 FROM finance.fee_schedule x WHERE x.session = p_to AND x.ended_at IS NULL AND finance.fee_line_same_scope(x, s));
    END IF;
END $fn$;
COMMENT ON FUNCTION finance.copy_spillover_lines(text, text, boolean) IS
  'V580: one session''s spillover fee lines copied into another, a line the target states kept (finance.copy_session_fees'' rule, spillover lines only)';

-- ── the session's readiness says what its spillover students are charged (restated from V400's text) ───────────────────────
CREATE OR REPLACE FUNCTION policy.transition_readiness(p_to text)
 RETURNS TABLE(code text, ok boolean, blocking boolean, detail text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s policy.academic_session%ROWTYPE; cur policy.academic_session%ROWTYPE; n_sem int; n_dated int; n_fee int; n_fresh int; n_win int; n_cur_sem int; n_cur_sheets int; n_cur_regs int; n_spill_none bigint; n_spill_lines int;
BEGIN
    SELECT * INTO s FROM policy.academic_session WHERE name = p_to;
    SELECT * INTO cur FROM policy.academic_session WHERE state = 'CURRENT';
    IF s.name IS NULL THEN
        RETURN QUERY SELECT 'SESSION_EXISTS', false, true, 'No session named ' || coalesce(p_to, '?') || ' is on the calendar.';
        RETURN;
    END IF;
    RETURN QUERY SELECT 'SESSION_EXISTS', true, true, p_to || ' is on the calendar (' || policy.session_label(s.state) || ').';
    RETURN QUERY SELECT 'STATE_PLANNED', s.state = 'PLANNED', true,
        CASE s.state WHEN 'PLANNED' THEN 'The session is planned.'
                     WHEN 'CURRENT' THEN 'The session is already current; nothing is to be done.'
                     WHEN 'DRAFT' THEN 'The session is still a draft: mark it planned once its setup is agreed.'
                     ELSE 'The session is ' || lower(policy.session_label(s.state)) || ' and cannot become current again.' END;
    RETURN QUERY SELECT 'SENATE_MINUTE', s.senate_minute IS NOT NULL AND btrim(s.senate_minute) <> '', true,
        CASE WHEN s.senate_minute IS NOT NULL AND btrim(s.senate_minute) <> '' THEN 'Senate minute ' || s.senate_minute || ' is recorded.'
             ELSE 'No Senate minute is recorded against the session; a session is not current without the minute that resolved to run it.' END;
    RETURN QUERY SELECT 'NO_CONFLICT', cur.name IS NULL OR cur.name = s.name OR s.starts_on > cur.starts_on, true,
        CASE WHEN cur.name IS NULL THEN 'No session is current; ' || p_to || ' becomes the first.'
             WHEN cur.name = s.name THEN 'Already the current session.'
             -- V377: the planned session may have begun while the current one runs; the transition completes it all the same
             WHEN s.starts_on > cur.starts_on AND s.starts_on <= cur.ends_on
                 THEN p_to || ' began on ' || to_char(s.starts_on, 'FMDD Mon YYYY') || ', while ' || cur.name || ' runs to '
                      || to_char(cur.ends_on, 'FMDD Mon YYYY') || '; the transition completes ' || cur.name || ' from then, and its records stay as they are.'
             WHEN s.starts_on > cur.starts_on THEN cur.name || ' is current and will be completed by the transition.'
             ELSE p_to || ' begins before the current session ' || cur.name || ' and cannot follow it.' END;
    -- V400: what is still open in the session the transition completes — said, never blocking: it is completed in its own time
    IF cur.name IS NOT NULL AND cur.name <> s.name THEN
        SELECT count(*) INTO n_cur_sem FROM policy.semester WHERE session = cur.name AND state = 'OPEN';
        RETURN QUERY SELECT 'CURRENT_SEMESTERS_OPEN', true, false,
            CASE WHEN n_cur_sem = 0 THEN 'No semester of ' || cur.name || ' is open.'
                 ELSE n_cur_sem || ' semester' || CASE WHEN n_cur_sem = 1 THEN '' ELSE 's' END || ' of ' || cur.name || ' still open; the transition does not close them.' END;
        SELECT count(*) INTO n_cur_sheets FROM assessment.score_sheet sh JOIN catalogue.offering o ON o.id = sh.offering_id
         WHERE o.session = cur.name AND sh.stage <> 'PUBLISHED';
        RETURN QUERY SELECT 'CURRENT_SHEETS_PENDING', true, false,
            CASE WHEN n_cur_sheets = 0 THEN 'Every score sheet of ' || cur.name || ' is published.'
                 ELSE n_cur_sheets || ' score sheet' || CASE WHEN n_cur_sheets = 1 THEN '' ELSE 's' END || ' of ' || cur.name || ' not yet published; they go on through the chain as before.' END;
        SELECT count(*) INTO n_cur_regs FROM registration.course_registration WHERE session = cur.name AND status = 'SUBMITTED';
        RETURN QUERY SELECT 'CURRENT_REGISTRATIONS_PENDING', true, false,
            CASE WHEN n_cur_regs = 0 THEN 'No registration of ' || cur.name || ' awaits approval.'
                 ELSE n_cur_regs || ' registration' || CASE WHEN n_cur_regs = 1 THEN '' ELSE 's' END || ' of ' || cur.name || ' still await approval.' END;
    END IF;
    SELECT count(*), count(*) FILTER (WHERE lectures_from IS NOT NULL) INTO n_sem, n_dated FROM policy.semester WHERE session = p_to;
    RETURN QUERY SELECT 'SEMESTERS_CONFIGURED', n_sem >= 1, false,
        CASE WHEN n_sem >= s.semesters THEN n_sem || ' of ' || s.semesters || ' semesters are on the calendar.'
             WHEN n_sem >= 1 THEN n_sem || ' of ' || s.semesters || ' semesters are on the calendar; the rest can follow.'
             ELSE 'No semester of ' || p_to || ' is on the calendar yet.' END;
    RETURN QUERY SELECT 'FIRST_SEMESTER_DATED', EXISTS (SELECT 1 FROM policy.semester WHERE session = p_to AND number = 1 AND lectures_from IS NOT NULL), false,
        CASE WHEN EXISTS (SELECT 1 FROM policy.semester WHERE session = p_to AND number = 1 AND lectures_from IS NOT NULL)
             THEN 'The first semester''s lectures are dated.' ELSE 'The first semester has no lecture dates; registration, examinations and results wait on them.' END;
    SELECT count(*) INTO n_fee FROM finance.fee_schedule WHERE session = p_to AND ended_at IS NULL;
    RETURN QUERY SELECT 'FEE_SCHEDULE', n_fee > 0, false,
        CASE WHEN n_fee > 0 THEN n_fee || ' fee schedule line(s) are stated for ' || p_to || '.' ELSE 'The Bursar has stated no fee schedule for ' || p_to || '; students see no charge.' END;
    -- V580: the spillover students the session's fees charge nothing, by the basis in force — said, never holding the transition or
    -- the automatic clock (which a check not met would hold, V289), as the current session's open semesters are said
    SELECT coalesce(sum(g.students), 0) INTO n_spill_none FROM finance.fee_gaps(p_to) g WHERE g.spillover AND NOT g.stated;
    SELECT count(*) INTO n_spill_lines FROM finance.fee_schedule WHERE session = p_to AND spillover AND ended_at IS NULL;
    RETURN QUERY SELECT 'SPILLOVER_FEE_LINES', true, false,
        CASE WHEN n_spill_none = 0 THEN 'Every spillover student is charged a spillover line for ' || p_to || ' (' || n_spill_lines || ' stated).'
             ELSE n_spill_none || ' spillover student' || CASE WHEN n_spill_none = 1 THEN ' has' ELSE 's have' END || ' no spillover line for ' || p_to
                  || ' (' || n_spill_lines || ' stated, charged ' || CASE finance.spill_basis() WHEN 'COHORT' THEN 'by the cohort' ELSE 'by the level' END
                  || '): state them, or copy the last session''s on the Fee Schedule.' END;
    SELECT count(*) INTO n_win FROM policy.portal_window WHERE session = p_to AND superseded_at IS NULL;
    RETURN QUERY SELECT 'PORTAL_WINDOWS', true, false,
        CASE WHEN n_win > 0 THEN n_win || ' portal window rule(s) are set for ' || p_to || '.' ELSE 'No portal window is configured for ' || p_to || '; school fees payment and course registration are open by default.' END;
    SELECT count(*) INTO n_fresh FROM people.student WHERE entry_session = p_to;
    RETURN QUERY SELECT 'FRESH_STUDENTS', true, false,
        CASE WHEN n_fresh > 0 THEN n_fresh || ' entrant(s) of ' || p_to || ' are on the register and continue under the same accounts.' ELSE 'No entrant of ' || p_to || ' is on the register yet.' END;
    RETURN QUERY SELECT 'RETURNING_STUDENTS', true, false,
        'Returning students are not moved by the transition: they progress by the results, promotion and roll-over rules that already exist.';
END $function$;

-- ── the uploading office told (contact_refuse restated from V575's text) ───────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('CONTACT_UPLOAD_REJECTED', 'A student says an uploaded contact is not theirs',
 'To the person who uploaded a student''s phone or e-mail (Student Contacts Upload) when the student says it is not theirs',
 '[STUDENT] says the [FIELD] you uploaded is not theirs',
 E'Dear [FIRST_NAME],\n\n[STUDENT] ([NUMBER]) says the [FIELD] [VALUE], which your upload [FILE] of [UPLOADED] gave the University, is not theirs. It has been taken off the record.\n\nPlease check the class list it came from and upload the right one: Student Contacts Upload, [PORTAL_URL]\n\nMOAUM Portal',
 NULL,
 'An uploaded [FIELD] is not [STUDENT]''s',
 '[STUDENT] ([NUMBER]) says the [FIELD] [VALUE] from your upload [FILE] of [UPLOADED] is not theirs. It has been taken off the record: check the class list and upload the right one.',
 ARRAY['FIRST_NAME','STUDENT','NUMBER','FIELD','VALUE','FILE','UPLOADED','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL'),
('CONTACT_UPLOAD_WAITING', 'Uploaded contacts still waiting for the students',
 'Each Monday to the person who uploaded students'' contacts, while contacts from an upload a month old still wait for the students to confirm them',
 '[COUNT] contacts from your upload [FILE] still wait for the students',
 E'Dear [FIRST_NAME],\n\n[COUNT] of the contacts your upload [FILE] of [UPLOADED] gave the University still wait for the students to confirm them. Until a student confirms (a code sent to the contact when they sign in) or ICT Support confirms it with them, no password reset link reaches it.\n\nAsk the students to sign in to the portal, or send them to the ICT Support Desk. Student Contacts Upload lists what became of each upload: [PORTAL_URL]\n\nThis notice comes each Monday while contacts wait.\n\nMOAUM Portal',
 NULL,
 '[COUNT] uploaded contacts still wait for the students',
 '[COUNT] contacts from your upload [FILE] of [UPLOADED] still wait for the students to confirm them. Ask the students to sign in, or send them to the ICT Support Desk.',
 ARRAY['FIRST_NAME','COUNT','FILE','UPLOADED','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL');

CREATE OR REPLACE FUNCTION people.contact_refuse(p_student uuid, p_field text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE v record; v_field text := upper(coalesce(p_field, '')); v_id uuid; u record;
BEGIN
    SELECT * INTO v FROM people.contact_pending_value(p_student, v_field);
    IF v.value IS NULL THEN
        RAISE EXCEPTION 'CONTACT_NOT_PENDING: there is no unconfirmed contact of that kind on the record' USING ERRCODE = '23514';
    END IF;
    UPDATE people.contact_confirmation SET outcome = 'REPLACED', decided_at = now()
     WHERE student_id = p_student AND field = v_field AND outcome IS NULL;
    INSERT INTO people.contact_confirmation (student_id, field, value, upload_id, outcome, decided_at, decided_by)
    VALUES (p_student, v_field, v.value, v.upload_id, 'REFUSED', now(), nullif(current_setting('moaum.actor_id', true), '')::uuid)
    RETURNING id INTO v_id;
    -- V580: the person who uploaded it is told, so the class list is put right
    SELECT x.uploaded_by, x.file_name, x.uploaded_at, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS student,
           coalesce(s.matric_no, s.admission_no, s.jamb_reg_no) AS number
      INTO u FROM people.contact_upload x CROSS JOIN people.student s WHERE x.id = v.upload_id AND s.id = p_student;
    IF u.uploaded_by IS NOT NULL THEN
        PERFORM platform.tell_person(u.uploaded_by, 'CONTACT_UPLOAD_REJECTED', NULL, jsonb_build_object(
                    'STUDENT', u.student, 'NUMBER', coalesce(u.number, ''), 'FIELD', CASE v_field WHEN 'EMAIL' THEN 'e-mail address' ELSE 'phone number' END,
                    'VALUE', v.value, 'FILE', coalesce(u.file_name, 'without a file name'),
                    'UPLOADED', to_char(u.uploaded_at AT TIME ZONE 'Africa/Lagos', 'FMDD Mon YYYY')),
                'contact-rejected:' || v_id);
    END IF;
    IF v_field = 'EMAIL' THEN
        UPDATE people.student_contact SET email = NULL, updated_at = now() WHERE student_id = p_student;
    ELSE
        UPDATE people.student_contact SET phone = NULL, updated_at = now() WHERE student_id = p_student;
    END IF;
    RETURN 'REFUSED';
END $function$;

-- each week, an upload at least p_days old whose contacts still wait: the uploader told once that week
CREATE FUNCTION people.chase_unconfirmed_contacts(p_days integer DEFAULT 30)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE u record; w bigint; n integer := 0; v_week text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'IYYY-"W"IW');
BEGIN
    FOR u IN SELECT x.id, x.file_name, x.uploaded_at, x.uploaded_by FROM people.contact_upload x
              WHERE x.uploaded_by IS NOT NULL AND x.uploaded_at <= now() - make_interval(days => greatest(0, coalesce(p_days, 30))) LOOP
        SELECT o.waiting INTO w FROM people.contact_upload_outcomes(u.id) o;
        CONTINUE WHEN coalesce(w, 0) = 0;
        n := n + platform.tell_person(u.uploaded_by, 'CONTACT_UPLOAD_WAITING', NULL, jsonb_build_object(
                     'COUNT', w::text, 'FILE', coalesce(u.file_name, 'without a file name'),
                     'UPLOADED', to_char(u.uploaded_at AT TIME ZONE 'Africa/Lagos', 'FMDD Mon YYYY')),
                 'contact-upload-waiting:' || v_week || ':' || u.id);
    END LOOP;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION people.chase_unconfirmed_contacts(integer) IS
  'V580: the uploaders of contacts still waiting for the students a month on, told once a week (CONTACT_UPLOAD_WAITING)';

COMMIT;
