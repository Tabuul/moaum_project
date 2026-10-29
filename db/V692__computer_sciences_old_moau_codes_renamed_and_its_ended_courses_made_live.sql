-- ═══════════════════════════════════════
-- V692 — B.Sc. Computer Science's three old MOAU codes renamed, and the ended courses its new structure lists made live again
--
-- The University's word of 29 October 2026, before uploading the Department of Mathematics and Computer Science's CCMAS structure for
-- B.Sc. Computer Science (C00023, "B.Sc. Computer Science CCMAS Program Sep 2026"): "rename the three old MOAU codes first". Three
-- courses bound to the programme carry the old code after the MOAU one — MOAU COS 123/CMP223 Computer Hardware, MOAU-COS 311/CMP 311
-- Compiler Construction I and MOAU-COS 315/CMP 315 Object Oriented Programming — and the structure names them MOAU-COS 123,
-- MOAU-COS 311 and MOAU-COS 315: uploaded as they stand, the upload would make three new courses beside them.
--
-- On the live-shaped copy of 26 October 2026 the three, with 27 other courses of the department, had been ended on 16 September 2026
-- by the department's duplicates desk, each in favour of a course of the same title, level and semester (the MOAU- courses in favour
-- of their BSU- twins, which V402 has since kept apart: each cohort registers its own codes). An ended course is not shown at
-- registration and gets no class, and the structure upload does not bring one back. The structure lists eight more of them: COS 202,
-- CSC 203, INS 401, MOAU-COS 104, MOAU-COS 120, MOAU-COS 205, MOAU-COS 262 and MOAU-INS 204. The University asked (29 October 2026)
-- for the three renamed and made live, and the eight made live too.
--
-- Done the way Course Management does it: catalogue.rename_course (the same course, its id kept; its bindings, classes,
-- registrations, results and the rest follow the code — on the copy, three bindings and three classes, no registration) and
-- catalogue.restore_course (live again). A code another course already holds, or one the pool's guard refuses, is left as it is and
-- named; a course already live, or not held here, is passed over. The other programmes that take these courses see them again too
-- (COS 202, CSC 203 and INS 401 are bound to C56345 and C67895 as well). MOAU COS 313, written with a space, is found by the upload
-- under its code as it is (catalogue.resolve_course_code) and is not touched.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V692: B.Sc. Computer Science''s old MOAU codes renamed and the ended courses its CCMAS structure lists made live', true);

DO $$
DECLARE r record; v_held text; v_err text; n_renamed int := 0; n_live int := 0;
BEGIN
    FOR r IN SELECT * FROM (VALUES ('MOAU COS 123/CMP223', 'MOAU-COS 123'),
                                   ('MOAU-COS 311/CMP 311', 'MOAU-COS 311'),
                                   ('MOAU-COS 315/CMP 315', 'MOAU-COS 315')) AS x(old_code, new_code) LOOP
        IF NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = r.old_code) THEN
            RAISE NOTICE 'V692: % is not held here; nothing to rename', r.old_code;
            CONTINUE;
        END IF;
        -- the new code already a course's (as written, written otherwise, or merged into one): left for the duplicates desk
        v_held := catalogue.resolve_course_code(r.new_code);
        IF v_held IS DISTINCT FROM r.old_code AND EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_held) THEN
            RAISE NOTICE 'V692: % left as it is — % is already the course %', r.old_code, r.new_code, v_held;
            CONTINUE;
        END IF;
        BEGIN
            PERFORM catalogue.rename_course(r.old_code, r.new_code);
            n_renamed := n_renamed + 1;
            RAISE NOTICE 'V692: % renamed %', r.old_code, r.new_code;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
            RAISE NOTICE 'V692: % left as it is — %', r.old_code, v_err;
        END;
    END LOOP;

    FOR r IN SELECT unnest(ARRAY['MOAU-COS 123', 'MOAU-COS 311', 'MOAU-COS 315', 'COS 202', 'CSC 203', 'INS 401', 'MOAU-COS 104',
                                 'MOAU-COS 120', 'MOAU-COS 205', 'MOAU-COS 262', 'MOAU-INS 204']) AS code LOOP
        IF EXISTS (SELECT 1 FROM catalogue.course WHERE code = r.code AND state = 'ENDED') THEN
            PERFORM catalogue.restore_course(r.code);
            n_live := n_live + 1;
            RAISE NOTICE 'V692: % made live again', r.code;
        END IF;
    END LOOP;
    RAISE NOTICE 'V692: % renamed, % made live again', n_renamed, n_live;
END $$;

COMMIT;
