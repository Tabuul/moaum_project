-- ═══════════════════════════════════════
-- V689 — A failed elective is an F, never a carry-over
--
--   The University's word of 28 October 2026: "PHL 114, and BSU-HIS 112 ARE ALL ELECTIVE COURSE FOR B.A ENGLISH STUDENT, THEY
--   SHOULD NOT COUNT AS CARRY OVERS FOR ALL THE STUDENT THAT FAIL, ELECTIVE COURSES ARE NOT TO BE COUNTED AS CARRY OVER, IF THE
--   STUDENT FAILS THE RESULT SHOULD BE CALCULATED AS F".
--
--   Since V242 an elective is never owed, and since V620 registration.is_elective_for reads a course as the student registered it
--   — the programme's basis for it on the entry (registration.entry.basis), read by registration.entry_category. An entry takes
--   that basis from the programme's binding at the registration's level when it is made (registration.entry_basis_snapshot); a
--   course the programme did not bind at that level — a B.A. English student's PHL 114 or BSU-HIS 112, which the programme did not
--   bind, an elective of a lower level taken late, a registration migrated before the structure was uploaded — has none, and
--   entry_category reads an entry of type CURRENT without one as CORE, whatever the course is. Its F was then owed: listed as a
--   carry-over, placed on the next registration, counted towards spillover and completion. On the copy of 21 October 2026 that held
--   141 failed courses of 105 students that are electives by the programme's structure or by the course itself (PSY 103,
--   BSU-PSY 109, POL 103, BSU-ACC 105 …).
--
--   1 · registration.is_elective_for restated from V620: a registration decides only where it carries the programme's basis (or was
--       registered as an elective or a GST course); otherwise the programme's structure today decides, then the course's own kind.
--       A course the structure makes core (B.A. History's BSU-HIS 112, B.A. Philosophy's PHL 114) is owed as before.
--   2 · B.A. English, English Studies and English Literature: PHL 114 and BSU-HIS 112 are electives — a binding of either that
--       says otherwise is made Elective, and each registration of either by the programme's students carries the basis Elective.
--
--   The F stays an F: its units are attempted and earn no points in the GPA and CGPA (unchanged), and the broadsheet's remark names
--   it "Fail:", not "CO:" (the API reads the same rule). Every reader of registration.carryovers follows: the carry-overs listed and
--   placed on registration, the picker, spillover, completion, the transcript and the reports.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V689: PHL 114 and BSU-HIS 112 are electives for B.A. English; a failed elective is an F, never a carry-over (the University, 28 October 2026)', true);

-- ── 1 · whether a course is an elective to a student ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.is_elective_for(p_student uuid, p_course text)
RETURNS boolean
LANGUAGE sql STABLE AS $function$
    -- V620: as the student registered it — the programme's basis for the course at the time and the entry's type, read as
    -- registration.entry_category reads them; V689: only where the registration carries that basis (or was made as an elective or a
    -- GST course) — an entry the programme's structure did not place is not read as core by default. Otherwise the programme's
    -- structure today, then the course's own kind.
    SELECT coalesce(
        (SELECT registration.entry_category(e.entry_type, c.kind, e.basis) = 'ELECTIVE'
           FROM registration.entry e
           JOIN registration.course_registration r ON r.id = e.registration_id
           JOIN catalogue.offering o ON o.id = e.offering_id
           JOIN catalogue.course c ON c.code = o.course_code
          WHERE r.student_id = p_student AND o.course_code = p_course
            AND e.status NOT IN ('DROPPED', 'WITHDRAWN') AND e.entry_type NOT IN ('CARRYOVER', 'DEFERRED', 'REPEAT')
            AND (e.basis IS NOT NULL OR e.entry_type IN ('ELECTIVE', 'GST'))
          ORDER BY r.session DESC, r.semester DESC LIMIT 1),
        (SELECT bool_or(co.basis = 'Elective')
           FROM catalogue.course_offer co
           JOIN people.student s ON s.id = p_student
          WHERE co.course_code = p_course AND co.programme_code = s.programme_code),
        (SELECT c.kind = 'Elective' FROM catalogue.course c WHERE c.code = p_course),
        false)
$function$;
COMMENT ON FUNCTION registration.is_elective_for(uuid, text) IS
  'V620, V689: whether a course is an elective to this student — as the student registered it where the registration carries the programme''s basis (or was made as an elective or GST course), else by the programme''s structure today, else by the course''s own kind. An elective failed is an F, never owed.';

-- ── 2 · B.A. English: PHL 114 and BSU-HIS 112 are electives ──────────────────────────────────────────────────────────────
DO $$
DECLARE v_progs text[] := ARRAY(SELECT code FROM ref.programme WHERE code IN ('C00002', 'C69405', 'C95933'));
        v_courses text[] := ARRAY(SELECT code FROM catalogue.course WHERE code IN ('PHL 114', 'BSU-HIS 112'));
        nb int; ne int;
BEGIN
    UPDATE catalogue.course_offer SET basis = 'Elective'
     WHERE programme_code = ANY (v_progs) AND course_code = ANY (v_courses) AND basis <> 'Elective';
    GET DIAGNOSTICS nb = ROW_COUNT;
    UPDATE registration.entry e SET basis = 'Elective'
      FROM registration.course_registration r, catalogue.offering o, people.student s
     WHERE r.id = e.registration_id AND o.id = e.offering_id AND s.id = r.student_id
       AND s.programme_code = ANY (v_progs) AND o.course_code = ANY (v_courses)
       AND e.entry_type NOT IN ('CARRYOVER', 'DEFERRED', 'REPEAT', 'GST')
       AND e.basis IS DISTINCT FROM 'Elective';
    GET DIAGNOSTICS ne = ROW_COUNT;
    RAISE NOTICE 'V689: B.A. English — % binding(s) of PHL 114 or BSU-HIS 112 made Elective, % registration(s) of them marked Elective', nb, ne;
END $$;

COMMIT;
