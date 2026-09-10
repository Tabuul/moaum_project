-- ═══════════════════════════════════════════════════════════════════════════
-- V064 — a matriculation number follows the school fees and the registration
--
--   The matriculation number is the number a student carries; it is issued at
--   matriculation, not with the offer of admission. A student earns it only by
--   paying the school fees AND registering courses for the session. Until then
--   they hold an admission number and wait.
--
--   The batch run (people.matriculate) issued a number to every admitted,
--   registered, unqueried candidate on a confirmed faculty list — but never
--   checked the fees. It now skips anyone whose fees are not settled for the
--   session (finance.position.paid_in_full; a student who owes nothing is
--   settled, so nothing changes where no fee schedule is in force).
--
--   A candidate who pays and registers after the ceremony is matriculated one
--   at a time — people.matriculate_student — which the Registry may call by
--   hand, or the portal may call the moment it sees both done. It refuses, with
--   the reason, anyone not yet admitted, not registered, or still owing.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION people.matriculate(p_session text)
RETURNS TABLE (run_ref text, issued int)
LANGUAGE plpgsql
AS $$
DECLARE v_missing text; v_run uuid := gen_random_uuid(); v_ref text; v_n int := 0; r record; v_serial bigint; v_yy text;
BEGIN
    SELECT string_agg(f.name, ', ' ORDER BY f.name) INTO v_missing
      FROM ref.faculty f
     WHERE EXISTS (SELECT 1 FROM people.faculty_list_rows(p_session, f.code))
       AND NOT EXISTS (SELECT 1 FROM people.faculty_list l
                        WHERE l.session = p_session AND l.faculty_code = f.code AND l.state = 'CONFIRMED');
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'the run cannot start: % has not confirmed its list', v_missing
            USING ERRCODE = 'check_violation',
                  HINT = 'A run with a faculty outstanding would leave its students unmatriculated after their classmates, or force a second run whose numbers sit at the end of the sequence. Confirm every list first.';
    END IF;
    v_yy := substr(p_session, 3, 2);
    v_ref := 'MAT/' || substr(p_session, 1, 4) || '/' || lpad(platform.next_number('MATRIC_RUN', 'UNIVERSITY', p_session)::text, 3, '0');
    INSERT INTO people.matriculation_run (id, ref, session, issued) VALUES (v_run, v_ref, p_session, 0);
    FOR r IN
        SELECT x.student_id, x.dept_code
          FROM ref.faculty f
          CROSS JOIN LATERAL people.faculty_list_rows(p_session, f.code) x
         WHERE x.query_reason IS NULL
           -- the fees must be settled for the session; a student who owes
           -- nothing (no schedule in force) is settled and matriculates as before
           AND (SELECT fp.paid_in_full FROM finance.position(x.student_id, p_session) fp)
         ORDER BY x.dept_code, x.surname, x.other_names
    LOOP
        v_serial := platform.next_number('MATRIC', r.dept_code, p_session);
        UPDATE people.student
           SET matric_no = 'MOAUM/' || r.dept_code || '/' || v_yy || '/' || lpad(v_serial::text, 4, '0'),
               matriculated_at = now(), matriculation_run = v_run, status = 'ACTIVE'
         WHERE id = r.student_id;
        INSERT INTO people.status_change (id, student_id, from_status, to_status, instrument, effective_on, reason)
        VALUES (gen_random_uuid(), r.student_id, 'ADMITTED', 'ACTIVE', v_ref, current_date, 'Matriculated');
        v_n := v_n + 1;
    END LOOP;
    IF v_n = 0 THEN
        RAISE EXCEPTION 'nobody on a confirmed list has both paid the fees and registered for %; there is nothing to matriculate', p_session
            USING ERRCODE = 'no_data_found';
    END IF;
    UPDATE people.matriculation_run SET issued = v_n WHERE id = v_run;
    RETURN QUERY SELECT v_ref, v_n;
END;
$$;

-- one student, matriculated the moment both conditions are met: the fees paid
-- and the courses registered. For the Registry to issue by hand, or the portal
-- to issue automatically. Idempotent: a student already matriculated keeps the
-- number. Refuses, with the reason, anyone not ready.
CREATE OR REPLACE FUNCTION people.matriculate_student(p_student uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE s people.student; v_dept text; v_run uuid; v_ref text; v_serial bigint; v_yy text; v_no text; v_paid boolean;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
    IF s.matric_no IS NOT NULL THEN RETURN s.matric_no; END IF;
    IF s.status <> 'ADMITTED' THEN
        RAISE EXCEPTION 'only an admitted student is matriculated; this one is %', lower(s.status) USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM registration.course_registration r
                    WHERE r.student_id = p_student AND r.session = s.entry_session AND r.status IN ('APPROVED','LOCKED')) THEN
        RAISE EXCEPTION 'the student has not registered courses for %', s.entry_session USING ERRCODE = '23514',
            HINT = 'A matriculation number is issued once the school fees are paid and the courses are registered.';
    END IF;
    SELECT fp.paid_in_full INTO v_paid FROM finance.position(p_student, s.entry_session) fp;
    IF NOT coalesce(v_paid, false) THEN
        RAISE EXCEPTION 'the school fees for % are not settled', s.entry_session USING ERRCODE = '23514',
            HINT = 'A matriculation number is issued once the school fees are paid and the courses are registered.';
    END IF;

    SELECT p.dept_code INTO v_dept FROM ref.programme p WHERE p.code = s.programme_code;
    v_yy := substr(s.entry_session, 3, 2);
    v_run := gen_random_uuid();
    v_ref := 'MAT/' || substr(s.entry_session, 1, 4) || '/' || lpad(platform.next_number('MATRIC_RUN', 'UNIVERSITY', s.entry_session)::text, 3, '0');
    INSERT INTO people.matriculation_run (id, ref, session, issued) VALUES (v_run, v_ref, s.entry_session, 1);
    v_serial := platform.next_number('MATRIC', v_dept, s.entry_session);
    v_no := 'MOAUM/' || v_dept || '/' || v_yy || '/' || lpad(v_serial::text, 4, '0');
    UPDATE people.student
       SET matric_no = v_no, matriculated_at = now(), matriculation_run = v_run, status = 'ACTIVE'
     WHERE id = p_student;
    INSERT INTO people.status_change (id, student_id, from_status, to_status, instrument, effective_on, reason)
    VALUES (gen_random_uuid(), p_student, 'ADMITTED', 'ACTIVE', v_ref, current_date, 'Matriculated on fees and registration');
    RETURN v_no;
END;
$$;

COMMIT;
