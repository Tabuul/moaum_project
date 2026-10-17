-- ═══════════════════════════════════════
-- V517 — The integration door's second read: a student's enrolment and fee clearance, for sponsors
--
-- NELFUND and the scholarship bodies ask the Bursary and the Registry, by e-mail, whether a student registered for the session and
-- whether the fees are settled. On the integration door (V511), a consumer holding the new scope students:enrolment asks it by
-- matriculation number (GET /api/integration/v1/students/enrolment?matric=…&session=…, the current session when none is named):
-- whether the student is in study, whether a course registration of the session is submitted or approved (and for which
-- semesters), and whether the Bursary clears the student for registration and for the examination (finance.clears_or_null: CLEARED,
-- NOT_CLEARED, or UNKNOWN when no clearance scheme is in force). No amount, no course, no result. The key, the scope and the daily
-- quota are checked and every call is logged, as for the status lookup.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V517: the integration door enrolment and fee clearance for sponsors', true);

INSERT INTO apimgmt.scope (code, label, reads, path) VALUES
('students:enrolment', 'Enrolment and fee clearance',
 'For a matriculation number and a session (the current one when none is named): whether the student is in study, whether a course registration of the session is submitted or approved and for which semesters, and whether the Bursary clears the student for registration and for the examination. No amounts, courses or results.',
 'GET /api/integration/v1/students/enrolment?matric=…&session=…');

CREATE FUNCTION apimgmt.student_enrolment(p_key text, p_matric text, p_session text, p_ip text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_no text := upper(btrim(coalesce(p_matric, ''))); v_session text := nullif(btrim(coalesce(p_session, '')), ''); c jsonb; s record; v_sems jsonb;
        v_reg boolean; v_r boolean; v_e boolean;
BEGIN
    c := apimgmt.check_key(p_key, 'students:enrolment', v_no, p_ip);
    IF NOT (c->>'ok')::boolean THEN RETURN c; END IF;
    v_session := coalesce(v_session, policy.university_current_session());
    IF v_no !~ '^[A-Z0-9/._-]{4,40}$' OR v_session IS NULL OR v_session !~ '^\d{4}/\d{4}$' THEN
        INSERT INTO apimgmt.request_log (consumer_id, key_id, scope, subject, outcome, ip)
        VALUES ((c->>'consumer_id')::uuid, (c->>'key_id')::uuid, 'students:enrolment', left(v_no, 60), 'BAD_REQUEST', left(p_ip, 60));
        RETURN jsonb_build_object('ok', false, 'outcome', 'BAD_REQUEST');
    END IF;
    SELECT x.id, x.matric_no, x.surname, x.other_names, x.status INTO s FROM people.student x WHERE upper(btrim(x.matric_no)) = v_no LIMIT 1;
    INSERT INTO apimgmt.request_log (consumer_id, key_id, scope, subject, outcome, ip)
    VALUES ((c->>'consumer_id')::uuid, (c->>'key_id')::uuid, 'students:enrolment', v_no || ' ' || v_session, CASE WHEN s.id IS NULL THEN 'NOT_FOUND' ELSE 'OK' END, left(p_ip, 60));
    IF s.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'outcome', 'NOT_FOUND'); END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object('semester', r.semester, 'status', CASE WHEN r.status IN ('APPROVED', 'LOCKED') THEN 'APPROVED' ELSE 'SUBMITTED' END)
                              ORDER BY r.semester), '[]'::jsonb)
      INTO v_sems FROM registration.course_registration r
     WHERE r.student_id = s.id AND r.session = v_session AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED');
    v_reg := jsonb_array_length(v_sems) > 0;
    v_r := finance.clears_or_null(s.id, v_session, 'REGISTRATION');
    v_e := finance.clears_or_null(s.id, v_session, 'EXAMINATION');
    RETURN jsonb_build_object('ok', true, 'outcome', 'OK', 'student', jsonb_build_object(
        'matric_no', s.matric_no,
        'name', upper(btrim(s.surname)) || coalesce(', ' || nullif((SELECT string_agg(left(w, 1) || '.', ' ') FROM regexp_split_to_table(btrim(coalesce(s.other_names, '')), '\s+') w WHERE w <> ''), ''), ''),
        'session', v_session,
        'in_study', s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION'),
        'registered', v_reg, 'semesters', v_sems,
        'fees_cleared_for_registration', CASE WHEN v_r THEN 'CLEARED' WHEN v_r IS FALSE THEN 'NOT_CLEARED' ELSE 'UNKNOWN' END,
        'fees_cleared_for_examination', CASE WHEN v_e THEN 'CLEARED' WHEN v_e IS FALSE THEN 'NOT_CLEARED' ELSE 'UNKNOWN' END,
        'as_at', now()));
END $$;
COMMENT ON FUNCTION apimgmt.student_enrolment(text, text, text, text) IS
  'V517: the integration door''s enrolment read (scope students:enrolment): the key, scope and quota checked, then for a matriculation number and a session whether the student is in study, registered (the semesters submitted or approved) and cleared by the Bursary for registration and for the examination — no amounts; every call logged';

COMMIT;
