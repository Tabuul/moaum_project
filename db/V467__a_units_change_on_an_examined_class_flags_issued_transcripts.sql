-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V467 — A units change on an examined class flags the transcripts already issued, as a changed mark does
--
--   · A changed mark flags the student's issued transcripts and statements (V262: credentials.score_changed on
--     assessment.score) — the Documents Office is told, checks each on its register, and reissues it when it no longer
--     matches; the earlier copy then verifies as REPLACED. A units correction (V465) changes the registration, not the mark,
--     so it flagged nothing: a transcript issued before it would have verified as current, at the old units, for good. Now a
--     change of units on a class whose results are worked on (the only registrations a change of units reaches since V464
--     are the unexamined, so this is the units correction and any repair of the record) flags them the same way.
--   · The student's e-mail said a transcript issued before an amendment "is superseded", which is so only once the Documents
--     Office reissues it. assessment.tell_amended (from V358) and assessment.tell_units_amended (from V465) restated to say
--     what happens: the transcript goes to the Documents Office to be checked, is reissued if it no longer matches, and the
--     earlier copy then verifies as replaced.
--   · Nothing is moved by this migration.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V467: a units change on an examined class flags issued transcripts', true);

CREATE OR REPLACE FUNCTION credentials.entry_units_changed()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_student uuid;
BEGIN
    SELECT r.student_id INTO v_student FROM registration.course_registration r WHERE r.id = NEW.registration_id;
    IF EXISTS (SELECT 1 FROM credentials.issued i WHERE i.student_id = v_student
                  AND i.kind IN ('TRANSCRIPT', 'SESSIONAL_TRANSCRIPT', 'MINI_TRANSCRIPT', 'ACADEMIC_STATEMENT') AND i.flagged_at IS NULL)
       AND catalogue.class_examined(NEW.offering_id) THEN
        PERFORM credentials.flag_documents(v_student, ARRAY['TRANSCRIPT', 'SESSIONAL_TRANSCRIPT', 'MINI_TRANSCRIPT', 'ACADEMIC_STATEMENT'],
                                           'The units of a course on the student''s record changed after issue');
    END IF;
    RETURN NEW;
END $fn$;
COMMENT ON FUNCTION credentials.entry_units_changed() IS
  'V467: a change of units on a class whose results are worked on flags the student''s issued transcripts and statements for the Documents Office, as a changed mark does (V262).';
DROP TRIGGER IF EXISTS trg_entry_units_flag_documents ON registration.entry;
CREATE TRIGGER trg_entry_units_flag_documents AFTER UPDATE OF units ON registration.entry
FOR EACH ROW WHEN (OLD.units IS DISTINCT FROM NEW.units) EXECUTE FUNCTION credentials.entry_units_changed();

/* restated from V358: the student told that a published result is amended — no mark in the message — and what happens to a
   transcript issued before */
CREATE OR REPLACE FUNCTION assessment.tell_amended(p_student uuid, p_course text, p_ref text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE r record; v_from text := coalesce((SELECT name FROM platform.institution_profile LIMIT 1), 'the University');
BEGIN
    SELECT st.surname, st.other_names, rc.email, rc.phone INTO r FROM people.student st LEFT JOIN LATERAL people.student_reach(st.id) rc ON true WHERE st.id = p_student;
    PERFORM platform.queue_notice('EMAIL', r.email, 'Your result in ' || p_course || ' is amended',
        'Dear ' || r.surname || ', ' || r.other_names || E',\n\nYour published result in ' || p_course || ' has been amended on the Senate''s approval (' || p_ref || '). '
        || 'Sign in to the University portal to see it. Any transcript or statement issued to you before the amendment goes to the Documents Office to be checked; '
        || E'if it no longer matches your record it is reissued, and the earlier copy then verifies as replaced.\n\n' || v_from || ' — Examinations and Records',
        'student', p_student);
    PERFORM platform.queue_notice('SMS', r.phone, 'Result amended', 'MOAUM: your result in ' || p_course || ' is amended. Sign in to the portal to see it.', 'student', p_student);
END $fn$;

/* restated from V465: the same for a units correction */
CREATE OR REPLACE FUNCTION assessment.tell_units_amended(p_sheet uuid, p_programme text, p_course text, p_units int, p_ref text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE r record; v_from text := coalesce((SELECT name FROM platform.institution_profile LIMIT 1), 'the University');
BEGIN
    FOR r IN SELECT DISTINCT st.id, st.surname, st.other_names, rc.email
               FROM assessment.score_sheet sh
               JOIN registration.entry e ON e.offering_id = sh.offering_id
               JOIN registration.course_registration cr ON cr.id = e.registration_id
               JOIN people.student st ON st.id = cr.student_id
               LEFT JOIN LATERAL people.student_reach(st.id) rc ON true
              WHERE sh.id = p_sheet AND st.programme_code = p_programme LOOP
        PERFORM platform.queue_notice('EMAIL', r.email, 'Your units in ' || p_course || ' are corrected',
            'Dear ' || r.surname || ', ' || r.other_names || E',\n\n' || p_course || ' is now recorded at ' || p_units || ' unit'
            || CASE WHEN p_units = 1 THEN '' ELSE 's' END || ' on your registration, corrected on the Senate''s approval (' || p_ref || '). '
            || 'Your grade point average reads the corrected units. Any transcript or statement issued to you before the correction goes to the Documents Office '
            || E'to be checked; if it no longer matches your record it is reissued, and the earlier copy then verifies as replaced.\n\n'
            || v_from || ' — Examinations and Records',
            'student', r.id);
    END LOOP;
END $fn$;

COMMIT;
