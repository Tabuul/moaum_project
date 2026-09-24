-- ═══════════════════════════════════════════════════════════════════════════
-- V247 — voluntary withdrawal: four consecutive semesters without registering
--
--   The University's regulation (stated 24 September 2026): a student who
--   does not register for courses in four consecutive semesters has
--   withdrawn voluntarily, and the record is removed from the University's
--   records. On the portal that is a status, VOLUNTARY_WITHDRAWAL: the
--   student is off every roll, class list and result sheet (all of which
--   read the active statuses), cannot register, and is refused at the
--   student portal with the reason. The record itself stays, as every
--   record does, with the change of status and its instrument on it.
--
--   The rule is computed from the record: the closed semesters (the
--   calendar's, past their late-registration date or marked closed) after
--   the student's last approved course registration — or since entry, for
--   a student who never registered. Four or more, and the student is due.
--   A change of status is a person's act on an instrument (V013), and the
--   audit spine admits no unattributed write, so the Registry closes the
--   records that are due from its desk; the portal names them.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE people.student DROP CONSTRAINT ck_student_status;
ALTER TABLE people.student ADD CONSTRAINT ck_student_status CHECK (status IN
        ('ADMITTED','ACTIVE','PROBATION','DEFERRED','SUSPENDED','RUSTICATED','WITHDRAWN',
         'EXPELLED','TRANSFERRED_OUT','GRADUATED','DECEASED','DORMANT','VOLUNTARY_WITHDRAWAL'));

-- the semesters closed for registration, in order: marked closed, or past their late-registration date
CREATE OR REPLACE FUNCTION registration.closed_semesters()
RETURNS TABLE (session text, semester int, closed_on date)
LANGUAGE sql STABLE AS $$
    SELECT s.session, s.number, coalesce(s.late_registration_closes, s.registration_closes, a.ends_on)
      FROM policy.semester s JOIN policy.academic_session a ON a.name = s.session
     WHERE s.state = 'CLOSED' OR coalesce(s.late_registration_closes, s.registration_closes, a.ends_on) < current_date
     ORDER BY s.session, s.number
$$;

-- the closed semesters since the student's last approved registration (or since entry): how many in a row, and which
CREATE OR REPLACE FUNCTION registration.semesters_unregistered(p_student uuid)
RETURNS TABLE (semesters int, last_registered text, first_missed text)
LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT * FROM people.student WHERE id = p_student),
    reg AS (SELECT r.session, r.semester FROM registration.course_registration r
             WHERE r.student_id = p_student AND r.status IN ('APPROVED','LOCKED')),
    missed AS (
        SELECT c.session, c.semester FROM registration.closed_semesters() c CROSS JOIN s
         WHERE c.session >= s.entry_session
           AND NOT EXISTS (SELECT 1 FROM reg WHERE (reg.session, reg.semester) >= (c.session, c.semester))
    ),
    word AS (SELECT 1 AS n, 'first' AS w UNION ALL SELECT 2, 'second' UNION ALL SELECT 3, 'third')
    SELECT (SELECT count(*) FROM missed)::int,
           (SELECT r.session || ' ' || coalesce(w.w, r.semester::text) || ' semester' FROM reg r LEFT JOIN word w ON w.n = r.semester ORDER BY r.session DESC, r.semester DESC LIMIT 1),
           (SELECT m.session || ' ' || coalesce(w.w, m.semester::text) || ' semester' FROM missed m LEFT JOIN word w ON w.n = m.semester ORDER BY m.session, m.semester LIMIT 1)
$$;
COMMENT ON FUNCTION registration.semesters_unregistered(uuid) IS
  'The closed semesters in a row, ending now, with no approved course registration — since the last one approved, or since entry; four make a voluntary withdrawal.';

-- the students due: on an active footing, four or more closed semesters without registering
CREATE OR REPLACE FUNCTION registration.voluntary_withdrawals_due()
RETURNS TABLE (student_id uuid, number text, surname text, other_names text, programme_code text, programme text,
               current_level int, status text, semesters int, last_registered text, first_missed text)
LANGUAGE sql STABLE AS $$
    SELECT st.id, coalesce(st.matric_no, st.admission_no), st.surname, st.other_names, st.programme_code, p.name,
           st.current_level, st.status, u.semesters, u.last_registered, u.first_missed
      FROM people.student st
      LEFT JOIN ref.programme p ON p.code = st.programme_code
      CROSS JOIN LATERAL registration.semesters_unregistered(st.id) u
     WHERE st.status IN ('ADMITTED','ACTIVE','PROBATION','DORMANT') AND u.semesters >= 4
     ORDER BY st.programme_code, st.current_level, st.surname, st.other_names
$$;

-- the Registry's act: the students due (one, or all) become VOLUNTARY_WITHDRAWAL on the instrument named
CREATE OR REPLACE FUNCTION registration.effect_voluntary_withdrawals(p_instrument text, p_student uuid DEFAULT NULL)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE d record; n int := 0;
BEGIN
    FOR d IN SELECT * FROM registration.voluntary_withdrawals_due() WHERE p_student IS NULL OR student_id = p_student LOOP
        PERFORM people.change_status(d.student_id, 'VOLUNTARY_WITHDRAWAL', p_instrument, current_date,
            format('%s consecutive semesters without an approved course registration, from %s; last registered %s',
                   d.semesters, coalesce(d.first_missed, '—'), coalesce(d.last_registered, 'never')));
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

COMMIT;
