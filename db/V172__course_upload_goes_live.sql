-- ═══════════════════════════════════════════════════════════════════════════
-- V172 — an uploaded course structure goes Live, and a course can be made Live
--
--   A course is created into BOARD state (V042): a brand-new course a department
--   invents is a curriculum change the Faculty Board sees and Senate approves.
--   But catalogue.import_courses left uploaded courses in BOARD too, so a whole
--   uploaded CCMAS/BMAS structure — the University's already-approved,
--   already-taught courses — sat at "At the Faculty Board" for ever, never Live,
--   even while students registered them and lecturers were allocated (only ENDED
--   gates registration, not BOARD). The catalogue read as 0 Live / hundreds
--   awaiting approval, which is misleading: those courses are the real ones.
--
--   So: a structure upload now lands its courses LIVE (and lifts an existing
--   BOARD/SENATE course to LIVE on re-upload; an ENDED course is left ended —
--   it is restored explicitly, V171). And make_course_live lets an existing
--   BOARD/SENATE course be made Live one at a time or in bulk, for the courses
--   already uploaded before this change. A single hand-created course still
--   starts at BOARD; making it live is the deliberate step.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION catalogue.make_course_live(p_code text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_code text := upper(btrim(p_code));
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a course is made live by a person' USING ERRCODE = '23514';
    END IF;
    UPDATE catalogue.course SET state = 'LIVE' WHERE code = v_code AND state IN ('BOARD', 'SENATE');
    IF NOT FOUND THEN
        IF EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_code AND state = 'ENDED') THEN
            RAISE EXCEPTION 'course % has ended; restore it instead of making it live', v_code USING ERRCODE = '23514',
                HINT = 'Restore the course, which returns it to Live.';
        END IF;
        RAISE EXCEPTION 'no course % awaiting approval to make live', v_code USING ERRCODE = '23503',
            HINT = 'It may already be live.';
    END IF;
    RETURN v_code;
END $$;

COMMENT ON FUNCTION catalogue.make_course_live(text) IS
'Lift a BOARD/SENATE course to LIVE. Refuses an ended course (restore it) and no course to promote.';

-- the uploaded structure is an approved, taught set of courses: land it Live, and lift an
-- existing course that was still awaiting approval; never silently resurrect an ended course
CREATE OR REPLACE FUNCTION catalogue.import_courses(p_programme text, p_rows jsonb, p_curriculum text DEFAULT NULL)
RETURNS TABLE (rows int, courses int, offers int, no_dept int, bad_code int, skipped int, first_error text)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_prog text; v_dept text; v_code text; v_title text; v_units int; v_level int; v_sem int; v_status text;
        v_kind text; v_basis text; v_lh int; v_ph int; v_curr text;
        n int := 0; nc int := 0; no int := 0; nnd int := 0; nb int := 0; ns int := 0; v_firsterr text := NULL;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a course upload is made by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the structure is rows: course code, title, units, status, level, semester' USING ERRCODE = '23514';
    END IF;
    v_curr := upper(nullif(btrim(coalesce(p_curriculum, '')), ''));
    IF v_curr IS NOT NULL AND v_curr NOT IN ('CCMAS', 'BMAS') THEN v_curr := NULL; END IF;
    SELECT code, dept_code INTO v_prog, v_dept FROM ref.programme
     WHERE upper(code) = upper(btrim(p_programme)) OR upper(name) = upper(btrim(p_programme)) ORDER BY archived, code LIMIT 1;
    IF v_prog IS NULL THEN RAISE EXCEPTION 'no programme is coded or named %', p_programme USING ERRCODE = '23503'; END IF;
    IF v_dept IS NULL OR NOT EXISTS (SELECT 1 FROM ref.department WHERE code = v_dept) THEN
        RAISE EXCEPTION 'the programme % has no department on the register to own its courses', v_prog USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_code := regexp_replace(upper(btrim(coalesce(r->>'code', r->>'courseCode', r->>'course_code', ''))), '\s+', ' ', 'g');
        IF v_code = '' OR v_code ~* '^course\s*code$' THEN CONTINUE; END IF;
        n := n + 1;
        IF v_code !~ '^[A-Z][A-Z0-9 /-]{2,19}$' THEN nb := nb + 1; CONTINUE; END IF;

        BEGIN
            v_title := nullif(btrim(coalesce(r->>'title', r->>'courseTitle', '')), '');
            IF v_title IS NULL THEN v_title := v_code; END IF;
            v_units := least(coalesce(nullif(regexp_replace(coalesce(r->>'units', ''), '[^0-9]', '', 'g'), '')::int, 0), 12);
            v_level := coalesce(nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int, 100);
            IF v_level NOT IN (100,200,300,400,500,600) THEN v_level := 100; END IF;
            v_sem := coalesce(nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int, 1);
            IF v_sem NOT IN (1,2,3) THEN v_sem := 1; END IF;
            v_lh := nullif(regexp_replace(coalesce(r->>'lh', r->>'LH', ''), '[^0-9]', '', 'g'), '')::int;
            v_ph := nullif(regexp_replace(coalesce(r->>'ph', r->>'PH', ''), '[^0-9]', '', 'g'), '')::int;
            v_status := upper(left(btrim(coalesce(r->>'status', 'C')), 1));
            v_kind := CASE WHEN v_code LIKE 'GST %' OR v_code LIKE 'GST%' THEN 'GST'
                           WHEN v_status = 'G' THEN 'GST'  -- GST/EPS courses carried by status, not a GST code
                           WHEN v_status = 'R' THEN 'Required' WHEN v_status = 'E' THEN 'Elective' ELSE 'Compulsory' END;
            v_basis := CASE WHEN v_kind = 'GST' THEN 'GST' WHEN v_kind = 'Elective' THEN 'Elective' ELSE 'Core' END;

            INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, lecture_hours, practical_hours, curriculum, state)
            VALUES (v_code, v_title, v_units, v_sem, v_level, v_dept, v_kind, v_lh, v_ph, v_curr, 'LIVE')
            ON CONFLICT (code) DO UPDATE SET title = EXCLUDED.title, units = EXCLUDED.units, semester = EXCLUDED.semester,
                level = EXCLUDED.level, kind = EXCLUDED.kind, lecture_hours = EXCLUDED.lecture_hours, practical_hours = EXCLUDED.practical_hours,
                curriculum = coalesce(EXCLUDED.curriculum, catalogue.course.curriculum),
                state = CASE WHEN catalogue.course.state IN ('BOARD', 'SENATE') THEN 'LIVE' ELSE catalogue.course.state END;

            INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis)
            VALUES (v_code, v_prog, v_level, v_basis)
            ON CONFLICT (course_code, programme_code, level) DO UPDATE SET basis = EXCLUDED.basis;

            nc := nc + 1;
            no := no + 1;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_firsterr IS NULL THEN v_firsterr := left(v_code || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, nc, no, nnd, nb, ns, v_firsterr;
END $$;

COMMIT;
