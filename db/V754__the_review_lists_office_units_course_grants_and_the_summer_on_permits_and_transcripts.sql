-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V754 · Follow-ups of the Summer and identity-card reviews
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's "do 1 - 6" of 13 November 2026, on the follow-ups proposed after V753:
--    1. What V742, V746, V751 and V753 only counted is listed: the Bursary's payment reallocations recorded at a level the
--       first-year count now reads otherwise (finance.reallocations_at_old_level), and the Academic Office's Summer authorisations
--       that name a course no longer on the catalogue, or that a one-off repair rewrote to another course than the trail from the
--       grant gives (registration.summer_authorisations_to_review).
--    2. ICT sets the unit an office belongs to (ref.set_office_unit), so a staff card reads it for someone the HR record places
--       nowhere; V751 seeded seven.
--    3. A course-scoped grant follows its course: a code corrected or merged moves every grant naming it (iam.course_grant_follow,
--       triggers beside V746's), a live twin on the new code ending the old one rather than breaking the merge; grants already
--       naming a dead code are followed from the date they began.
--    4. (the staff card's check page reads the card's department — the API alone)
--    5. The University's decisions of 13 November 2026: a GST or EPS course registered in the Summer Semester has its examination
--       permit on the Summer payment alone — no separate GST fee, no school fees for semester 3; and semester 3 of a session that
--       had a Summer Semester is named the Summer semester on transcripts and results statements (any other semester 3 keeps
--       "Third"): registration.is_summer, the statement's and the examination card's 'summer' flags.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V754: follow-ups of the Summer and identity-card reviews', true);

-- ── a semester that is a session's Summer ────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION registration.is_summer(p_session text, p_semester integer) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT p_semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session);
$$;
COMMENT ON FUNCTION registration.is_summer(text, integer) IS
    'V754: true for semester 3 of a session that had a Summer Semester — named the Summer semester on permits, cards, transcripts and results statements; any other semester 3 is the third.';

-- ── 1. the lists ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.reallocations_at_old_level()
RETURNS TABLE (id uuid, realloc_ref text, status text, reference text, amount numeric, student_id uuid, matric_no text, name text,
               entry_session text, to_purpose text, to_session text, to_semester integer, level_recorded integer, level_now integer,
               initiated_at timestamptz, executed_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT x.id, x.realloc_ref, x.status, x.reference, x.amount, x.student_id, coalesce(s.matric_no, s.admission_no),
           s.surname || ', ' || s.other_names, s.entry_session, x.to_purpose, x.to_session, x.to_semester, x.to_level,
           people.level_in(x.student_id, x.to_session), x.initiated_at, x.executed_at
      FROM finance.payment_reallocation x JOIN people.student s ON s.id = x.student_id
     WHERE s.entry_mode NOT IN ('CCE', 'POSTGRADUATE')
       AND EXISTS (SELECT 1 FROM policy.cohort_start cs WHERE cs.admission_session = policy.session_normal(s.entry_session))
       AND x.to_level IS DISTINCT FROM people.level_in(x.student_id, x.to_session)
     ORDER BY x.initiated_at DESC;
$$;
COMMENT ON FUNCTION finance.reallocations_at_old_level() IS
    'V754: payment reallocations of students whose first year began the session after admission (V738) whose level, recorded at the decision, differs from the level the count gives now — what V742 counted, listed for the Bursary (nothing is changed).';

CREATE FUNCTION registration.summer_authorisations_to_review(p_session text)
RETURNS TABLE (kind text, session text, student_id uuid, number text, name text, course_named text, courses_now text[],
               trail_gives text, rewritten_by text, at timestamptz)
LANGUAGE sql STABLE AS $$
    -- an authorisation naming a course no longer on the catalogue (what the trail from the grant gives, where it gives one)
    SELECT 'DEAD_CODE', sa.session, sa.student_id, coalesce(st.matric_no, st.admission_no), st.surname || ', ' || st.other_names,
           upper(btrim(x)), sa.courses, registration.summer_code_after(x, sa.granted_at), NULL::text, sa.granted_at
      FROM registration.summer_authorisation sa JOIN people.student st ON st.id = sa.student_id
      CROSS JOIN LATERAL unnest(sa.courses) x
     WHERE (p_session IS NULL OR sa.session = p_session) AND sa.revoked_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = upper(btrim(x)))
    UNION ALL
    -- an authorisation a one-off repair (V746, V751) rewrote to another course than the trail from the grant gives, each choice
    -- brought forward to today (as V753 counts them)
    SELECT 'REWRITTEN', e.after_state ->> 'session', (e.after_state ->> 'student_id')::uuid, coalesce(st.matric_no, st.admission_no),
           st.surname || ', ' || st.other_names, o.old_code,
           ARRAY(SELECT upper(btrim(a)) FROM jsonb_array_elements_text(e.after_state -> 'courses') a),
           registration.summer_code_after(o.old_code, (e.before_state ->> 'granted_at')::timestamptz), split_part(e.reason, ':', 1), e.occurred_at
      FROM audit.entries e
      JOIN people.student st ON st.id = (e.after_state ->> 'student_id')::uuid
      CROSS JOIN LATERAL (SELECT upper(btrim(b)) AS old_code FROM jsonb_array_elements_text(e.before_state -> 'courses') b
                           WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(e.after_state -> 'courses') a WHERE upper(btrim(a)) = upper(btrim(b)))) o
     WHERE e.subject_type = 'registration.summer_authorisation' AND (e.reason LIKE 'V746:%' OR e.reason LIKE 'V751:%' OR e.reason LIKE 'V753:%')
       AND (p_session IS NULL OR e.after_state ->> 'session' = p_session)
       AND registration.summer_code_after(o.old_code, (e.before_state ->> 'granted_at')::timestamptz) IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(e.after_state -> 'courses') a
                        WHERE coalesce(registration.summer_code_after(upper(btrim(a)), e.occurred_at), upper(btrim(a)))
                              = registration.summer_code_after(o.old_code, (e.before_state ->> 'granted_at')::timestamptz))
    ORDER BY 1, 2, 5;
$$;
COMMENT ON FUNCTION registration.summer_authorisations_to_review(text) IS
    'V754: the Summer authorisations for the Academic Office to look at again — those naming a course no longer on the catalogue, and those a one-off repair (V746, V751, V753) rewrote to another course than the trail from the grant gives; nothing is changed (the Office re-authorises).';

-- ── 2. the unit an office belongs to, set by ICT ────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION ref.set_office_unit(p_office text, p_unit text, p_reason text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); o ref.office; v_unit text := nullif(upper(btrim(coalesce(p_unit, ''))), '');
BEGIN
    IF coalesce(v_office, '') NOT IN ('ict', 'super') THEN
        RAISE EXCEPTION 'OFFICE_UNIT_OFFICE: the unit an office belongs to is set by ICT' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO o FROM ref.office WHERE code = lower(btrim(coalesce(p_office, ''))) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'OFFICE_UNKNOWN: no office is coded %', p_office USING ERRCODE = 'P0002'; END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'OFFICE_UNIT_REASON: say why the office''s unit changes, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    IF v_unit IS NOT NULL AND NOT EXISTS (SELECT 1 FROM ref.unit u WHERE u.code = v_unit AND u.ended_on IS NULL) THEN
        RAISE EXCEPTION 'UNIT_UNKNOWN: no unit in service is coded %', p_unit USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', btrim(p_reason), true);
    UPDATE ref.office SET unit_code = v_unit WHERE code = o.code;
    RETURN ref.unit_card_name(v_unit);
END $$;
COMMENT ON FUNCTION ref.set_office_unit(text, text, text) IS
    'V754: ICT sets (or, with an empty unit, clears) the unit an office belongs to, with a reason on the audit trail; returns what a staff card then prints for someone the HR record places nowhere who holds the office.';

-- ── 3. a course-scoped grant follows its course ──────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION iam.course_grant_follow(p_old text, p_new text) RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int; m int; v_ended uuid[];
BEGIN
    IF upper(btrim(p_old)) = upper(btrim(p_new)) THEN RETURN 0; END IF;
    -- a live grant whose holder already holds the same office on the new code ends, keeping the code it had (the merge must not
    -- fail on the twin)
    WITH e AS (
        UPDATE iam.office_assignment a SET valid_to = greatest(a.valid_from, current_date)
         WHERE a.scope_kind = 'course' AND upper(btrim(a.scope_id)) = upper(btrim(p_old)) AND a.valid_to IS NULL
           AND EXISTS (SELECT 1 FROM iam.office_assignment b
                        WHERE b.person_id = a.person_id AND b.office_code = a.office_code AND b.valid_to IS NULL
                          AND b.scope_kind = 'course' AND upper(btrim(b.scope_id)) = upper(btrim(p_new)))
        RETURNING a.id)
    SELECT coalesce(array_agg(e.id), '{}') INTO v_ended FROM e;
    m := cardinality(v_ended);
    UPDATE iam.office_assignment a SET scope_id = p_new
     WHERE a.scope_kind = 'course' AND upper(btrim(a.scope_id)) = upper(btrim(p_old))
       AND (a.valid_to IS NULL OR a.valid_to >= current_date) AND a.id <> ALL (v_ended);
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n + m;
END $$;
COMMENT ON FUNCTION iam.course_grant_follow(text, text) IS
    'V754: every grant in force bounded by a course code is bounded by its new code (a correction or a merge); a holder already bounded by the new code keeps that grant and the old one ends.';

CREATE FUNCTION iam.course_grant_code_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM iam.course_grant_follow(OLD.code, NEW.code);
    RETURN NULL;
END $$;
CREATE TRIGGER trg_course_grant_code_changed AFTER UPDATE OF code ON catalogue.course
    FOR EACH ROW WHEN (OLD.code IS DISTINCT FROM NEW.code) EXECUTE FUNCTION iam.course_grant_code_changed();

CREATE FUNCTION iam.course_grant_course_merged() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM iam.course_grant_follow(NEW.alias_code, NEW.course_code);
    RETURN NULL;
END $$;
CREATE TRIGGER trg_course_grant_course_merged AFTER INSERT ON catalogue.course_alias
    FOR EACH ROW EXECUTE FUNCTION iam.course_grant_course_merged();

-- ── 5. the Summer: the GST & EPS permit on the Summer payment; the Summer named ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.gst_eps_permit_state(p_student uuid, p_session text, p_semester integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s people.student; r registration.course_registration; pm registration.gst_eps_permit;
        v_courses jsonb := '[]'::jsonb; v_n int := 0; v_gst int := 0; v_eps int := 0; v_units int := 0;
        v_carry int := 0; v_first int := 0; v_pending jsonb := '[]'::jsonb; v_other int[] := '{}'; v_elsewhere text := '';
        v_code text; v_reason text; v_paid boolean; v_sem text; v_prog record; v_summer boolean;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'GST_EPS_PERMIT_NO_STUDENT: no such student' USING ERRCODE = '23503'; END IF;
    -- V754: a Summer registration (the University's decision of 13 November 2026): its permit stands on the Summer payment alone
    v_summer := registration.is_summer(p_session, p_semester) AND s.entry_mode NOT IN ('CCE', 'POSTGRADUATE');
    v_sem := p_session || ' ' || CASE p_semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE CASE WHEN v_summer THEN 'Summer' ELSE 'third' END END || ' semester';
    SELECT p.name AS programme, d.name AS department, f.name AS faculty INTO v_prog
      FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, p.faculty_code)
     WHERE p.code = s.programme_code;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    SELECT * INTO pm FROM registration.gst_eps_permit WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF r.id IS NOT NULL AND r.status <> 'DRAFT' THEN
        SELECT coalesce(jsonb_agg(to_jsonb(x) - 'offering_id' ORDER BY x.course_type DESC, x.course_code), '[]'::jsonb), count(*), count(*) FILTER (WHERE x.course_type = 'GST'),
               count(*) FILTER (WHERE x.course_type = 'EPS'), coalesce(sum(x.units), 0),
               count(*) FILTER (WHERE x.classification = 'CARRY_OVER'), count(*) FILTER (WHERE x.classification = 'FIRST_TIME')
          INTO v_courses, v_n, v_gst, v_eps, v_units, v_carry, v_first
          FROM registration.gst_eps_permit_courses(p_student, p_session, p_semester) x;
    END IF;
    -- V728: a draft's GST and EPS courses — carry-overs among them — said while the registration waits to be submitted
    IF r.id IS NOT NULL AND r.status = 'DRAFT' THEN
        SELECT coalesce(jsonb_agg(jsonb_build_object('course_code', c.code, 'title', coalesce(o.title, c.title), 'course_type', c.general_office,
                                                     'entry_type', e.entry_type) ORDER BY c.general_office DESC, c.code), '[]'::jsonb)
          INTO v_pending
          FROM registration.entry e
          JOIN catalogue.offering o ON o.id = e.offering_id
          JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' AND c.general_office IN ('GST', 'EPS') AND c.code NOT LIKE 'DMO %'
         WHERE e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED');
    END IF;
    -- V728: with no GST or EPS course on this semester's registration, the other semesters of the session whose submitted
    -- registration carries one — a carry-over sits on the registration of the semester it was added in
    IF v_n = 0 THEN
        SELECT coalesce(array_agg(DISTINCT r2.semester ORDER BY r2.semester), '{}'::int[]) INTO v_other
          FROM registration.course_registration r2
          JOIN registration.entry e ON e.registration_id = r2.id AND e.status IN ('REGISTERED', 'APPROVED')
          JOIN catalogue.offering o ON o.id = e.offering_id
          JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' AND c.general_office IN ('GST', 'EPS') AND c.code NOT LIKE 'DMO %'
         WHERE r2.student_id = p_student AND r2.session = p_session AND r2.semester <> p_semester AND r2.status <> 'DRAFT';
        IF cardinality(v_other) > 0 THEN
            v_elsewhere := ' Your GST and EPS courses of ' || p_session || ' are on your '
                           || array_to_string(ARRAY(SELECT CASE x WHEN 1 THEN 'first' WHEN 2 THEN 'second'
                                                                  ELSE CASE WHEN registration.is_summer(p_session, 3) THEN 'Summer' ELSE 'third' END END
                                                      FROM unnest(v_other) x ORDER BY x), ' and ')
                           || ' semester registration: choose that semester.';
        END IF;
    END IF;
    -- V589: the school fees as the examination card reads them (V567): a confirmed school-fees payment for the session, any amount;
    -- V754: a Summer registration, the Summer payment (its courses are registered only once paid, V735)
    v_paid := CASE WHEN v_summer
                   THEN EXISTS (SELECT 1 FROM registration.summer_charge sc WHERE sc.student_id = p_student AND sc.session = p_session AND sc.state = 'PAID')
                   ELSE registration.exam_card_paid(p_student, p_session) END;

    -- V589: the card's terms (registered and paid) and the GST fee — no approval, no clearance scheme, no release switch
    IF s.status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') THEN
        v_code := 'GST_EPS_PERMIT_NOT_IN_STUDY';
        v_reason := 'Your student record is ' || lower(replace(s.status, '_', ' ')) || '; a GST & EPS examination permit is issued to a student in study.';
    ELSIF r.id IS NULL THEN
        v_code := 'GST_EPS_PERMIT_NO_REGISTRATION';
        v_reason := CASE WHEN v_summer
                         THEN 'You have no Summer Semester registration for ' || p_session || ': select your outstanding courses on the Summer Semester page; they are registered once paid.'
                         ELSE 'You have not registered courses for ' || v_sem || ', so no GST or EPS course is registered for the selected session and semester.' || v_elsewhere END;
    ELSIF r.status = 'DRAFT' THEN
        v_code := 'GST_EPS_PERMIT_NOT_SUBMITTED';
        v_reason := 'Your course registration for ' || v_sem || ' is not yet submitted. Submit it, and the permit is yours once your school fees are paid.';
    ELSIF v_n = 0 THEN
        v_code := 'GST_EPS_PERMIT_NO_COURSES';
        v_reason := 'You have not registered any GST or EPS course for the selected session and semester.' || v_elsewhere;
    ELSIF pm.revoked_at IS NOT NULL THEN
        v_code := 'GST_EPS_PERMIT_REVOKED';
        v_reason := 'Your GST & EPS examination permit for ' || v_sem || ' was withdrawn by the ' || pm.revoked_office || ' office on '
                    || to_char(pm.revoked_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY') || ': ' || pm.revoked_reason;
    -- the gate answers by the course's office alone, so it is asked once for a GST course and once for an EPS course;
    -- V754: never for a Summer registration — its course fee is the fee for that sitting
    ELSIF NOT v_summer AND EXISTS (SELECT 1 FROM (SELECT DISTINCT ON (x->>'course_type') x->>'course_code' AS code FROM jsonb_array_elements(v_courses) x ORDER BY x->>'course_type') q
                   WHERE registration.gst_gate(p_student, p_session, q.code) IS NOT NULL) THEN
        v_code := 'GST_EPS_PERMIT_GST_PAYMENT';
        v_reason := 'Your GST fee for ' || p_session || ' is not yet confirmed as paid. GST payment covers both GST and EPS; the permit is issued once the payment is confirmed.'
                    -- V728: a carry-over is examined in this session, so this session's fee is asked (V690); an earlier one does not cover it
                    || CASE WHEN v_carry > 0 THEN ' A carry-over GST or EPS course is examined in ' || p_session || ', so the GST fee of ' || p_session
                                                  || ' is asked; a GST fee paid in an earlier session does not cover it.' ELSE '' END;
    ELSIF NOT v_paid THEN
        v_code := 'GST_EPS_PERMIT_NOT_PAID';
        v_reason := CASE WHEN v_summer
                         THEN 'Your GST & EPS examination permit for the Summer Semester of ' || p_session || ' is issued once your Summer Semester fees are paid on the Summer Semester page.'
                         ELSE 'Your GST & EPS examination permit is issued once your school fees for ' || p_session || ' are paid, as your examination card is. '
                              || 'A payment made at a bank or on Quickteller shows here once Interswitch reports it.' END;
    END IF;

    RETURN jsonb_build_object(
        'available', v_code IS NULL, 'code', v_code, 'reason', v_reason,
        'session', p_session, 'semester', p_semester, 'summer', v_summer,
        'student', jsonb_build_object('name', upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''),
                                      'matricNo', s.matric_no, 'number', coalesce(s.matric_no, s.admission_no), 'jambNo', s.jamb_reg_no,
                                      'faculty', v_prog.faculty, 'department', v_prog.department, 'programme', v_prog.programme,
                                      'level', coalesce(r.level, s.current_level), 'status', s.status),
        'registration', CASE WHEN r.id IS NULL THEN NULL ELSE jsonb_build_object('status', r.status, 'level', r.level, 'approvedAt', r.approved_at,
                                                                                'approvalMode', r.approval_mode) END,
        'courses', v_courses, 'gstCount', v_gst, 'epsCount', v_eps, 'units', v_units, 'cleared', v_paid,
        -- V728: how many of the courses are carry-overs and how many first registrations; the draft's courses; the other semesters
        -- holding GST or EPS courses; and whether the screens show the permit at all (courses, a draft holding some, or a permit)
        'carryOverCount', v_carry, 'firstTimeCount', v_first, 'pending', v_pending, 'otherSemesters', to_jsonb(v_other),
        'shown', (v_n > 0 OR jsonb_array_length(v_pending) > 0 OR pm.id IS NOT NULL),
        'permit', CASE WHEN pm.id IS NULL THEN NULL ELSE jsonb_build_object(
                      'reference', pm.reference, 'status', registration.gst_eps_permit_status(pm), 'generatedAt', pm.generated_at,
                      'lastIssuedAt', pm.last_issued_at, 'viewed', pm.viewed, 'downloaded', pm.downloaded, 'printed', pm.printed,
                      'revokedAt', pm.revoked_at, 'revokedOffice', pm.revoked_office, 'revokedReason', pm.revoked_reason) END);
END $function$;

-- the statement's semesters and the examination card say whether a semester 3 was the session's Summer
DO $$
DECLARE d text;
    ug text := 'jsonb_build_object(''semester'', r.semester, ''courses'', r.courses, ''units'', gp.units,';
    pg text := 'jsonb_build_object(''semester'', r.semester, ''courses'', r.courses, ''units'', r.units,';
    card text := '''session'', p_session, ''semester'', p_semester,';
BEGIN
    d := pg_get_functiondef('credentials.build_statement(uuid,text,text,integer)'::regprocedure);
    IF position(ug IN d) = 0 OR position(pg IN d) = 0 THEN RAISE EXCEPTION 'V754: credentials.build_statement is not as V488 left it'; END IF;
    d := replace(d, ug, 'jsonb_build_object(''semester'', r.semester, ''summer'', registration.is_summer(r.session, r.semester), ''courses'', r.courses, ''units'', gp.units,');
    d := replace(d, pg, 'jsonb_build_object(''semester'', r.semester, ''summer'', registration.is_summer(r.session, r.semester), ''courses'', r.courses, ''units'', r.units,');
    EXECUTE d;
    d := pg_get_functiondef('registration.exam_card_state(uuid,text,integer)'::regprocedure);
    IF position(card IN d) = 0 THEN RAISE EXCEPTION 'V754: registration.exam_card_state is not as V739 left it'; END IF;
    EXECUTE replace(d, card, '''session'', p_session, ''semester'', p_semester, ''summer'', registration.is_summer(p_session, p_semester),');
END $$;

-- ── put right, and told ──────────────────────────────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE r record; v_new text; n_grants int := 0; n_dead_grants int; n_realloc int; n_auth int;
BEGIN
    -- course-scoped grants in force already naming a code no longer on the catalogue: followed from the date each began
    FOR r IN SELECT a.id, a.scope_id, a.valid_from FROM iam.office_assignment a
              WHERE a.scope_kind = 'course' AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                AND NOT EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = upper(btrim(a.scope_id))) LOOP
        v_new := registration.summer_code_after(r.scope_id, r.valid_from::timestamptz);
        IF v_new IS NOT NULL AND v_new <> upper(btrim(r.scope_id)) THEN
            n_grants := n_grants + iam.course_grant_follow(r.scope_id, v_new);
        END IF;
    END LOOP;
    SELECT count(*) INTO n_dead_grants FROM iam.office_assignment a
     WHERE a.scope_kind = 'course' AND (a.valid_to IS NULL OR a.valid_to >= current_date)
       AND NOT EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = upper(btrim(a.scope_id)));
    SELECT count(*) INTO n_realloc FROM finance.reallocations_at_old_level();
    SELECT count(*) INTO n_auth FROM registration.summer_authorisations_to_review(NULL);
    RAISE NOTICE 'V754: % course-scoped grants followed to their course''s code (% still name no course); listed now: % reallocations at the old count (the Bursary), % Summer authorisations to look at again (the Academic Office); % offices carry the unit they belong to',
        n_grants, n_dead_grants, n_realloc, n_auth, (SELECT count(*) FROM ref.office WHERE unit_code IS NOT NULL);
END $$;

COMMIT;
