-- ═══════════════════════════════════════
-- V492 — The GST & EPS examination permit card
--
--   A student sits the GST and EPS examinations on a permit of their own, apart from the University's examination card. The
--   permit is drawn by the examination card's own document engine. It carries only the GST and EPS courses on the
--   student's approved course registration for the session and semester. It never lists the GST/EPS courses a programme
--   offers, and never lists a departmental course. Nothing new decides what a GST or EPS course is, what a registration is,
--   or what is paid:
--     · a course is GST or EPS by the classification the GST/EPS engine, the registration gate and the offices already read
--       (catalogue.course kind GST, general_office GST or EPS — V366/V367);
--     · the courses are the entries of the student's APPROVED (or LOCKED) registration that stand (REGISTERED or APPROVED),
--       read at each issue, so a reset (V491) or a new registration changes the permit at once and no course is kept from
--       an earlier version;
--     · the GST fee is the existing gate (registration.gst_gate): a permit waits for a GST fee the gate still asks for. The
--       Bursary's clearance for the examination (finance.clears_or_null, EXAMINATION) and the card's release (the V491 rule's
--       card on approval, or the examination session's cards released) are the examination card's own conditions;
--     · the dates, times and venues are the examination timetable's (assessment.exam_timetable) or the CBT engine's (the
--       student's own sitting and seat, or the examination's window), never invented: TO BE SCHEDULED until they are set.
--
--     · registration.gst_eps_permit — one permit a student and semester, made at its first issue, with a business reference
--       (GST-EPS/<year>/<number>) that is not the database's id. It holds how often it was viewed, downloaded and printed,
--       the courses it last carried, and its revocation (by the GST or EPS office, with a reason) on the audit spine;
--     · registration.gst_eps_permit_event — every issue, revocation and restoration (GST_EPS_PERMIT_GENERATED, _VIEWED,
--       _DOWNLOADED, _PRINTED, _REVOKED, _RESTORED) with the courses, the actor and the office, written once;
--     · registration.gst_eps_permit_courses / gst_eps_permit_state / issue_gst_eps_permit — the courses, whether the permit
--       may be issued and why not, and its issue;
--     · registration.revoke_gst_eps_permit — withdrawn or restored by the GST or EPS office whose course it carries; the
--       student told (GST_EPS_PERMIT_REVOKED / _RESTORED, no reason in the message);
--     · registration.gst_eps_permit_roster — the students an office's registered courses concern, with their permits.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'gst', true),
       set_config('moaum.reason', 'V492: the GST & EPS examination permit card', true);

-- ── the permit ──
CREATE SEQUENCE registration.gst_eps_permit_no;
COMMENT ON SEQUENCE registration.gst_eps_permit_no IS 'V492: the running number in a GST & EPS permit''s reference (GST-EPS/<year>/<number>)';

CREATE TABLE registration.gst_eps_permit (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference       text NOT NULL UNIQUE CHECK (reference ~ '^GST-EPS/[0-9]{4}/[0-9]{6,}$'),
    student_id      uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    session         text NOT NULL REFERENCES policy.academic_session (name),
    semester        integer NOT NULL CHECK (semester BETWEEN 1 AND 3),
    generated_at    timestamptz NOT NULL DEFAULT now(),
    last_issued_at  timestamptz NOT NULL DEFAULT now(),
    viewed          integer NOT NULL DEFAULT 0 CHECK (viewed >= 0),
    downloaded      integer NOT NULL DEFAULT 0 CHECK (downloaded >= 0),
    printed         integer NOT NULL DEFAULT 0 CHECK (printed >= 0),
    courses         jsonb NOT NULL DEFAULT '[]'::jsonb,
    revoked_at      timestamptz NULL,
    revoked_by      uuid NULL,
    revoked_office  text NULL,
    revoked_reason  text NULL,
    CONSTRAINT uq_gst_eps_permit UNIQUE (student_id, session, semester),
    CONSTRAINT ck_gst_eps_permit_revoked CHECK ((revoked_at IS NULL) = (revoked_reason IS NULL) AND (revoked_at IS NULL) = (revoked_office IS NULL))
);
COMMENT ON TABLE registration.gst_eps_permit IS
  'V492: a student''s GST & EPS examination permit for a session and semester, made at its first issue; its courses are read from the approved registration at every issue (courses holds those it last carried); revoked by the GST or EPS office with a reason';
SELECT audit.attach('registration.gst_eps_permit');

CREATE TABLE registration.gst_eps_permit_event (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    permit_id    uuid NOT NULL REFERENCES registration.gst_eps_permit (id) ON DELETE CASCADE,
    action       text NOT NULL CHECK (action IN ('GST_EPS_PERMIT_GENERATED', 'GST_EPS_PERMIT_VIEWED', 'GST_EPS_PERMIT_DOWNLOADED',
                                                 'GST_EPS_PERMIT_PRINTED', 'GST_EPS_PERMIT_REVOKED', 'GST_EPS_PERMIT_RESTORED')),
    courses      jsonb NULL,
    reason       text NULL,
    actor_id     uuid NULL,
    actor_office text NULL,
    at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_gst_eps_permit_event ON registration.gst_eps_permit_event (permit_id, at);
COMMENT ON TABLE registration.gst_eps_permit_event IS
  'V492: every issue (generated, viewed, downloaded, printed), revocation and restoration of a GST & EPS permit, with the courses it carried, the actor and the office; written once';
SELECT audit.exempt('registration.gst_eps_permit_event',
    'The log of a GST & EPS permit''s issues and revocations, written once; the permit itself and its revocation are on the spine.');

CREATE FUNCTION registration.gst_eps_permit_event_written_once()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'GST_EPS_PERMIT_EVENT_WRITTEN_ONCE: the record of a permit''s issue is written once' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_gst_eps_permit_event_once BEFORE UPDATE ON registration.gst_eps_permit_event
    FOR EACH ROW EXECUTE FUNCTION registration.gst_eps_permit_event_written_once();

-- the permit's state in one word: GENERATED, DOWNLOADED, PRINTED or REVOKED
CREATE FUNCTION registration.gst_eps_permit_status(p registration.gst_eps_permit)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p.id IS NULL THEN NULL WHEN p.revoked_at IS NOT NULL THEN 'REVOKED' WHEN p.printed > 0 THEN 'PRINTED'
                WHEN p.downloaded > 0 THEN 'DOWNLOADED' ELSE 'GENERATED' END
$$;

-- ── the courses: the GST and EPS courses on the approved registration, with the examination's slot where one is set ──
CREATE FUNCTION registration.gst_eps_permit_courses(p_student uuid, p_session text, p_semester integer)
RETURNS TABLE (offering_id uuid, course_code text, title text, units integer, course_type text, entry_type text,
               mode text, held_on date, starts_at time, ends_at time, venue text, seat_no integer, bar text)
LANGUAGE sql STABLE AS $$
    SELECT o.id, c.code, coalesce(o.title, c.title), e.units, c.general_office, e.entry_type,
           sl.mode, sl.held_on, sl.starts_at, sl.ends_at, sl.venue, sl.seat_no, attendance.exam_bar(p_student, o.id)
      FROM registration.course_registration r
      JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED')
      JOIN catalogue.offering o ON o.id = e.offering_id
      JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' AND c.general_office IN ('GST', 'EPS') AND c.code NOT LIKE 'DMO %'
      -- the slot: the student's own CBT sitting and seat, else the examination timetable's slot, else the CBT examination's window
      LEFT JOIN LATERAL (
          SELECT z.mode, z.held_on, z.starts_at, z.ends_at, z.venue, z.seat_no FROM (
              SELECT 1 AS rank, 'CBT'::text AS mode, (si.starts_at AT TIME ZONE 'Africa/Lagos')::date AS held_on,
                     (si.starts_at AT TIME ZONE 'Africa/Lagos')::time AS starts_at, (si.ends_at AT TIME ZONE 'Africa/Lagos')::time AS ends_at,
                     si.venue, se.seat_no
                FROM assessment.cbt_exam x
                JOIN assessment.cbt_seat se ON se.exam_id = x.id AND se.candidate_id = p_student
                JOIN assessment.cbt_sitting si ON si.id = se.sitting_id
               WHERE x.offering_id = o.id AND x.state IN ('SCHEDULED', 'PUBLISHED', 'CLOSED', 'COMPLETED')
              UNION ALL
              SELECT 2, 'WRITTEN', t.held_on, t.starts_at, t.ends_at, t.venue, NULL::integer
                FROM assessment.exam_timetable t WHERE t.offering_id = o.id
              UNION ALL
              SELECT 3, 'CBT', (x.starts_at AT TIME ZONE 'Africa/Lagos')::date, (x.starts_at AT TIME ZONE 'Africa/Lagos')::time,
                     CASE WHEN (x.ends_at AT TIME ZONE 'Africa/Lagos')::date = (x.starts_at AT TIME ZONE 'Africa/Lagos')::date
                          THEN (x.ends_at AT TIME ZONE 'Africa/Lagos')::time END,
                     CASE WHEN x.venue = 'REMOTE' THEN 'Online (CBT)' END, NULL::integer
                FROM assessment.cbt_exam x
               WHERE x.offering_id = o.id AND x.state IN ('SCHEDULED', 'PUBLISHED', 'CLOSED', 'COMPLETED') AND x.starts_at IS NOT NULL
          ) z ORDER BY z.rank, z.held_on NULLS LAST LIMIT 1) sl ON true
     WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester AND r.status IN ('APPROVED', 'LOCKED')
     ORDER BY c.general_office DESC, c.code
$$;
COMMENT ON FUNCTION registration.gst_eps_permit_courses(uuid, text, integer) IS
  'V492: the GST and EPS courses on a student''s approved registration for the session and semester (GST first), with the examination''s slot where one is set (the student''s CBT seat, the examination timetable, or the CBT window) and any attendance bar';

-- ── whether the permit may be issued, and why not: the first rule that fails ──
CREATE FUNCTION registration.gst_eps_permit_state(p_student uuid, p_session text, p_semester integer)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE s people.student; r registration.course_registration; pm registration.gst_eps_permit; v_rule registration.approval_policy;
        v_courses jsonb := '[]'::jsonb; v_n int := 0; v_gst int := 0; v_eps int := 0; v_units int := 0;
        v_code text; v_reason text; v_clear boolean; v_sem text; v_prog record;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'GST_EPS_PERMIT_NO_STUDENT: no such student' USING ERRCODE = '23503'; END IF;
    v_sem := p_session || ' ' || CASE p_semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END || ' semester';
    SELECT p.name AS programme, d.name AS department, f.name AS faculty INTO v_prog
      FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, p.faculty_code)
     WHERE p.code = s.programme_code;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    SELECT * INTO pm FROM registration.gst_eps_permit WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF r.id IS NOT NULL AND r.status IN ('APPROVED', 'LOCKED') THEN
        SELECT coalesce(jsonb_agg(to_jsonb(x) - 'offering_id' ORDER BY x.course_type DESC, x.course_code), '[]'::jsonb), count(*), count(*) FILTER (WHERE x.course_type = 'GST'),
               count(*) FILTER (WHERE x.course_type = 'EPS'), coalesce(sum(x.units), 0)
          INTO v_courses, v_n, v_gst, v_eps, v_units
          FROM registration.gst_eps_permit_courses(p_student, p_session, p_semester) x;
    END IF;

    IF s.status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') THEN
        v_code := 'GST_EPS_PERMIT_NOT_IN_STUDY';
        v_reason := 'Your student record is ' || lower(replace(s.status, '_', ' ')) || '; a GST & EPS examination permit is issued to a student in study.';
    ELSIF r.id IS NULL THEN
        v_code := 'GST_EPS_PERMIT_NO_REGISTRATION';
        v_reason := 'You have not registered courses for ' || v_sem || ', so no GST or EPS course is registered for the selected session and semester.';
    ELSIF r.status NOT IN ('APPROVED', 'LOCKED') THEN
        v_code := 'GST_EPS_PERMIT_NOT_APPROVED';
        v_reason := 'Your course registration for ' || v_sem || ' is ' || CASE r.status WHEN 'DRAFT' THEN 'not yet submitted' WHEN 'SUBMITTED' THEN 'awaiting approval'
                    WHEN 'RETURNED' THEN 'returned to you' ELSE lower(r.status) END || '; the permit is issued for an approved course registration.';
    ELSIF v_n = 0 THEN
        v_code := 'GST_EPS_PERMIT_NO_COURSES';
        v_reason := 'You have not registered any GST or EPS course for the selected session and semester.';
    ELSIF pm.revoked_at IS NOT NULL THEN
        v_code := 'GST_EPS_PERMIT_REVOKED';
        v_reason := 'Your GST & EPS examination permit for ' || v_sem || ' was withdrawn by the ' || pm.revoked_office || ' office on '
                    || to_char(pm.revoked_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY') || ': ' || pm.revoked_reason;
    -- the gate answers by the course's office alone, so it is asked once for a GST course and once for an EPS course
    ELSIF EXISTS (SELECT 1 FROM (SELECT DISTINCT ON (x->>'course_type') x->>'course_code' AS code FROM jsonb_array_elements(v_courses) x ORDER BY x->>'course_type') q
                   WHERE registration.gst_gate(p_student, p_session, q.code) IS NOT NULL) THEN
        v_code := 'GST_EPS_PERMIT_GST_PAYMENT';
        v_reason := 'Your GST fee for ' || p_session || ' is not yet confirmed as paid. GST payment covers both GST and EPS; the permit is issued once the payment is confirmed.';
    ELSE
        v_clear := finance.clears_or_null(p_student, p_session, 'EXAMINATION');
        v_rule := registration.approval_rule(p_session, p_semester);
        IF v_clear IS FALSE THEN
            v_code := 'GST_EPS_PERMIT_NOT_CLEARED';
            v_reason := 'The permit is issued when the Bursary clears you for the examination. Settle the fees the scheme requires.';
        ELSIF NOT (coalesce(v_rule.card_on_approval, true)
                   OR EXISTS (SELECT 1 FROM assessment.exam_session x WHERE x.session = p_session AND x.semester = p_semester AND x.state <> 'DRAFT'
                                 AND x.cards_released_at IS NOT NULL AND x.stream = people.student_stream(p_student))) THEN
            v_code := 'GST_EPS_PERMIT_NOT_RELEASED';
            v_reason := 'The permit is released with the examination cards for ' || v_sem || '.';
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'available', v_code IS NULL, 'code', v_code, 'reason', v_reason,
        'session', p_session, 'semester', p_semester,
        'student', jsonb_build_object('name', upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''),
                                      'matricNo', s.matric_no, 'number', coalesce(s.matric_no, s.admission_no), 'jambNo', s.jamb_reg_no,
                                      'faculty', v_prog.faculty, 'department', v_prog.department, 'programme', v_prog.programme,
                                      'level', coalesce(r.level, s.current_level), 'status', s.status),
        'registration', CASE WHEN r.id IS NULL THEN NULL ELSE jsonb_build_object('status', r.status, 'level', r.level, 'approvedAt', r.approved_at,
                                                                                'approvalMode', r.approval_mode) END,
        'courses', v_courses, 'gstCount', v_gst, 'epsCount', v_eps, 'units', v_units, 'cleared', v_clear,
        'permit', CASE WHEN pm.id IS NULL THEN NULL ELSE jsonb_build_object(
                      'reference', pm.reference, 'status', registration.gst_eps_permit_status(pm), 'generatedAt', pm.generated_at,
                      'lastIssuedAt', pm.last_issued_at, 'viewed', pm.viewed, 'downloaded', pm.downloaded, 'printed', pm.printed,
                      'revokedAt', pm.revoked_at, 'revokedOffice', pm.revoked_office, 'revokedReason', pm.revoked_reason) END);
END $$;
COMMENT ON FUNCTION registration.gst_eps_permit_state(uuid, text, integer) IS
  'V492: whether a student''s GST & EPS permit for the session and semester may be issued (the first rule that fails, with its code and words), the student, the registration, the GST and EPS courses on it, and the permit if one was made';

-- ── the issue: made once, counted every time, refused with the reason ──
CREATE FUNCTION registration.issue_gst_eps_permit(p_student uuid, p_session text, p_semester integer, p_act text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE st jsonb; pm registration.gst_eps_permit; v_codes jsonb; v_action text;
BEGIN
    v_action := CASE p_act WHEN 'VIEW' THEN 'GST_EPS_PERMIT_VIEWED' WHEN 'DOWNLOAD' THEN 'GST_EPS_PERMIT_DOWNLOADED' WHEN 'PRINT' THEN 'GST_EPS_PERMIT_PRINTED' END;
    IF v_action IS NULL THEN
        RAISE EXCEPTION 'GST_EPS_PERMIT_ACT: a permit is viewed (VIEW), downloaded (DOWNLOAD) or printed (PRINT)' USING ERRCODE = '23514';
    END IF;
    -- one issue at a time for the student's semester, so a double click never makes two permits
    PERFORM pg_advisory_xact_lock(hashtextextended('gst_eps_permit:' || p_student || ':' || p_session || ':' || p_semester, 0));
    st := registration.gst_eps_permit_state(p_student, p_session, p_semester);
    IF NOT (st->>'available')::boolean THEN
        RAISE EXCEPTION '%', (st->>'code') || ': ' || (st->>'reason') USING ERRCODE = '23514';
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object('code', x->>'course_code', 'type', x->>'course_type', 'units', (x->>'units')::int)), '[]'::jsonb)
      INTO v_codes FROM jsonb_array_elements(st->'courses') x;
    SELECT * INTO pm FROM registration.gst_eps_permit WHERE student_id = p_student AND session = p_session AND semester = p_semester FOR UPDATE;
    IF NOT FOUND THEN
        INSERT INTO registration.gst_eps_permit (reference, student_id, session, semester, courses)
        VALUES ('GST-EPS/' || left(p_session, 4) || '/' || lpad(nextval('registration.gst_eps_permit_no')::text, 6, '0'), p_student, p_session, p_semester, v_codes)
        RETURNING * INTO pm;
        INSERT INTO registration.gst_eps_permit_event (permit_id, action, courses, actor_id, actor_office)
        VALUES (pm.id, 'GST_EPS_PERMIT_GENERATED', v_codes, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
    END IF;
    UPDATE registration.gst_eps_permit
       SET last_issued_at = now(), courses = v_codes,
           viewed = viewed + (p_act = 'VIEW')::int, downloaded = downloaded + (p_act = 'DOWNLOAD')::int, printed = printed + (p_act = 'PRINT')::int
     WHERE id = pm.id;
    INSERT INTO registration.gst_eps_permit_event (permit_id, action, courses, actor_id, actor_office)
    VALUES (pm.id, v_action, v_codes, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
    RETURN registration.gst_eps_permit_state(p_student, p_session, p_semester);
END $$;
COMMENT ON FUNCTION registration.issue_gst_eps_permit(uuid, text, integer, text) IS
  'V492: issue a student''s GST & EPS permit (VIEW, DOWNLOAD or PRINT): refused with the reason when a rule fails; made at the first issue with its reference, counted at every one, the courses it carried logged';

-- ── withdrawn, or restored, by the GST or EPS office whose course it carries ──
CREATE FUNCTION registration.revoke_gst_eps_permit(p_permit uuid, p_office text, p_reason text, p_restore boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE pm registration.gst_eps_permit; v_sem text;
BEGIN
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'GST_EPS_PERMIT_REASON: give the reason in at least ten characters' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO pm FROM registration.gst_eps_permit WHERE id = p_permit FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'GST_EPS_PERMIT_NOT_FOUND: no such permit' USING ERRCODE = '23514'; END IF;
    IF p_office IS DISTINCT FROM 'SUPER' AND NOT EXISTS (
           SELECT 1 FROM registration.gst_eps_permit_courses(pm.student_id, pm.session, pm.semester) x WHERE x.course_type = p_office
           UNION ALL SELECT 1 FROM jsonb_array_elements(pm.courses) c WHERE c->>'type' = p_office) THEN
        RAISE EXCEPTION 'GST_EPS_PERMIT_OTHER_OFFICE: this permit carries no % course; the office whose course it carries withdraws it', p_office USING ERRCODE = '23514';
    END IF;
    v_sem := CASE pm.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END || ' semester';
    IF NOT p_restore AND pm.revoked_at IS NULL THEN
        UPDATE registration.gst_eps_permit SET revoked_at = now(), revoked_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
               revoked_office = CASE WHEN p_office = 'SUPER' THEN 'GST & EPS' ELSE p_office END, revoked_reason = btrim(p_reason)
         WHERE id = pm.id;
        INSERT INTO registration.gst_eps_permit_event (permit_id, action, reason, actor_id, actor_office)
        VALUES (pm.id, 'GST_EPS_PERMIT_REVOKED', btrim(p_reason), nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
        PERFORM platform.tell_student(pm.student_id, 'GST_EPS_PERMIT_REVOKED', NULL,
                jsonb_build_object('SESSION', pm.session, 'SEMESTER', v_sem, 'OFFICE', CASE WHEN p_office = 'SUPER' THEN 'GST & EPS' ELSE p_office END),
                'GST_EPS_PERMIT_REVOKED:' || pm.id || ':' || extract(epoch FROM now())::bigint);
    ELSIF p_restore AND pm.revoked_at IS NOT NULL THEN
        UPDATE registration.gst_eps_permit SET revoked_at = NULL, revoked_by = NULL, revoked_office = NULL, revoked_reason = NULL WHERE id = pm.id;
        INSERT INTO registration.gst_eps_permit_event (permit_id, action, reason, actor_id, actor_office)
        VALUES (pm.id, 'GST_EPS_PERMIT_RESTORED', btrim(p_reason), nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
        PERFORM platform.tell_student(pm.student_id, 'GST_EPS_PERMIT_RESTORED', NULL,
                jsonb_build_object('SESSION', pm.session, 'SEMESTER', v_sem),
                'GST_EPS_PERMIT_RESTORED:' || pm.id || ':' || extract(epoch FROM now())::bigint);
    END IF;
    RETURN registration.gst_eps_permit_state(pm.student_id, pm.session, pm.semester);
END $$;
COMMENT ON FUNCTION registration.revoke_gst_eps_permit(uuid, text, text, boolean) IS
  'V492: withdraw (or, with p_restore, restore) a GST & EPS permit, with a reason, by the GST or EPS office whose course it carries (SUPER any); the student told without the reason; a second click changes nothing';

-- ── an office's students: those its registered courses concern, with their permits ──
CREATE FUNCTION registration.gst_eps_permit_roster(p_session text, p_semester integer, p_office text)
RETURNS TABLE (student_id uuid, number text, name text, programme_code text, programme text, dept_code text, faculty_code text, level integer,
               reg_status text, courses text, course_count integer, units integer, permit_id uuid, reference text, permit_status text,
               generated_at timestamptz, last_issued_at timestamptz, viewed integer, downloaded integer, printed integer, revoked_at timestamptz)
LANGUAGE sql STABLE AS $$
    WITH oc AS (SELECT o.id, o.course_code FROM catalogue.course c
                  JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session
                 WHERE c.kind = 'GST' AND c.code NOT LIKE 'DMO %' AND (c.general_office = p_office OR (p_office IS NULL AND c.general_office IN ('GST', 'EPS')))),
         reg AS (SELECT r.student_id, r.level, r.status, string_agg(oc.course_code, ', ' ORDER BY oc.course_code) AS courses,
                        count(*)::int AS n, sum(e.units)::int AS units
                   FROM oc
                   JOIN registration.entry e ON e.offering_id = oc.id AND e.status IN ('REGISTERED', 'APPROVED')
                   JOIN registration.course_registration r ON r.id = e.registration_id AND r.session = p_session AND r.semester = p_semester
                                                          AND r.status IN ('APPROVED', 'LOCKED')
                  GROUP BY r.student_id, r.level, r.status)
    SELECT g.student_id, coalesce(s.matric_no, s.admission_no), upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''),
           s.programme_code, p.name, p.dept_code, p.faculty_code, g.level, g.status, g.courses, g.n, g.units,
           pm.id, pm.reference, registration.gst_eps_permit_status(pm), pm.generated_at, pm.last_issued_at,
           coalesce(pm.viewed, 0), coalesce(pm.downloaded, 0), coalesce(pm.printed, 0), pm.revoked_at
      FROM reg g
      JOIN people.student s ON s.id = g.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN registration.gst_eps_permit pm ON pm.student_id = g.student_id AND pm.session = p_session AND pm.semester = p_semester
$$;
COMMENT ON FUNCTION registration.gst_eps_permit_roster(text, integer, text) IS
  'V492: the students with an approved registration carrying the office''s GST or EPS courses (both offices'' with no office) for the session and semester, with the courses and their permit';

-- ── the notices ──
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('GST_EPS_PERMIT_REVOKED', 'GST & EPS examination permit withdrawn',
 'To the student when the GST or EPS office withdraws the GST & EPS examination permit (V492)',
 'Your GST & EPS examination permit for [SESSION] [SEMESTER] was withdrawn',
 E'Dear [FIRST_NAME],\n\nYour GST & EPS examination permit for [SESSION] [SEMESTER] was withdrawn by the [OFFICE] office. Sign in to see why, and contact the office.\n\n[PORTAL_URL]\n\nOffice of the Registrar, [UNIVERSITY_NAME]',
 'MOAUM: your GST & EPS examination permit for [SESSION] [SEMESTER] was withdrawn by the [OFFICE] office. Sign in to see why.',
 'GST & EPS permit withdrawn',
 'Your GST & EPS examination permit for [SESSION] [SEMESTER] was withdrawn by the [OFFICE] office. See Examinations for why.',
 ARRAY['FIRST_NAME','SESSION','SEMESTER','OFFICE','PORTAL_URL','UNIVERSITY_NAME'], true, 'NORMAL'),
('GST_EPS_PERMIT_RESTORED', 'GST & EPS examination permit restored',
 'To the student when a withdrawn GST & EPS examination permit is restored (V492)',
 'Your GST & EPS examination permit for [SESSION] [SEMESTER] is restored',
 E'Dear [FIRST_NAME],\n\nYour GST & EPS examination permit for [SESSION] [SEMESTER] is restored. You may view and print it on the Examinations page.\n\n[PORTAL_URL]\n\nOffice of the Registrar, [UNIVERSITY_NAME]',
 'MOAUM: your GST & EPS examination permit for [SESSION] [SEMESTER] is restored. Print it from Examinations.',
 'GST & EPS permit restored',
 'Your GST & EPS examination permit for [SESSION] [SEMESTER] is restored. You may view and print it on the Examinations page.',
 ARRAY['FIRST_NAME','SESSION','SEMESTER','PORTAL_URL','UNIVERSITY_NAME'], true, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

COMMIT;
