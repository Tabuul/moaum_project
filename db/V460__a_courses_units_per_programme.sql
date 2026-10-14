-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V460 — A course's units per programme: one programme takes a course at 2 units, another at 3
--
--   · Until now a course carried one number of units for every programme that offered it, and a department's structure upload
--     wrote the file's units over the course — for every programme at once — while another department's programme carrying
--     the course at a different number was not heard. The user: "not update for all, some may be offering as 2 credit unit
--     others maybe 3 credit unit", and once changed, let it reflect.
--   · catalogue.course_offer.units: the units this programme takes the course at, at this level; NULL = the course's own. Set
--     on Programme Structure (by the programme's department or a central office) and by the structure upload.
--   · catalogue.units_for(course, programme, level): the programme's units at the level, else (no level given — a carry-over)
--     at any level of the programme, else the course's.
--   · Registration takes the student's programme's units: registration.student_menu restated (the units of each course on the
--     menu; drafts, choices, adding a course and the support desk all read the menu).
--   · The structure upload (catalogue.import_courses_rows restated) creates a course with the file's units as before, but no
--     longer writes them over an existing course: a programme whose file says otherwise gets its own units on its binding —
--     the owner's programme and a borrowing programme alike.
--   · A change is the department's that sees it (the user: "it should not change for every programme or department but the
--     department that see it"): a change of a course's own units — on the course's page, by its department or a central
--     office — reaches only the programmes of the course's own department; every other department's programme that took the
--     course at the old units keeps them, pinned on its binding, and changes them on its own Programme Structure. A GST/EPS
--     course, the University's, reaches every programme.
--   · Reflected (once changed, it reflects): a programme's units, set or changed, reach its students' registrations of the
--     course at that level; a course's own units, changed, reach the registrations of its department's programmes that take
--     it at the course's units. Only where nothing is examined yet — a registration in a session not closed, the student with
--     no score on the class — so a result, a GPA or a transcript already worked out never moves. Each change is on the audit
--     spine.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V460: a course''s units per programme', true);

ALTER TABLE catalogue.course_offer ADD COLUMN IF NOT EXISTS units int NULL;
ALTER TABLE catalogue.course_offer DROP CONSTRAINT IF EXISTS ck_course_offer_units;
ALTER TABLE catalogue.course_offer ADD CONSTRAINT ck_course_offer_units CHECK (units IS NULL OR units BETWEEN 0 AND 12);
COMMENT ON COLUMN catalogue.course_offer.units IS
  'V460: the units this programme takes the course at, at this level — NULL takes the course''s own units.';

CREATE OR REPLACE FUNCTION catalogue.units_for(p_course text, p_programme text, p_level int)
RETURNS int LANGUAGE sql STABLE AS $fn$
    -- the binding at the level decides (its NULL is the course's units); with no binding at the level — a carry-over taken at a
    -- later level, or no level given — the programme's own units at any level, else the course's
    SELECT coalesce(
        (SELECT co.units FROM catalogue.course_offer co
          WHERE co.course_code = p_course AND co.programme_code = p_programme AND co.level = p_level),
        CASE WHEN p_level IS NULL OR NOT EXISTS (SELECT 1 FROM catalogue.course_offer co
                                                  WHERE co.course_code = p_course AND co.programme_code = p_programme AND co.level = p_level)
             THEN (SELECT co.units FROM catalogue.course_offer co
                    WHERE co.course_code = p_course AND co.programme_code = p_programme AND co.units IS NOT NULL
                    ORDER BY co.level LIMIT 1) END,
        (SELECT c.units FROM catalogue.course c WHERE c.code = p_course))
$fn$;
COMMENT ON FUNCTION catalogue.units_for(text, text, int) IS
  'V460: the units a programme takes a course at — the programme''s own at the level (any level of the programme when none is given, as for a carry-over), else the course''s.';

-- ── what has been examined does not move: the registrations a change of units reaches ──
CREATE OR REPLACE FUNCTION catalogue.reflect_units(p_course text, p_programme text, p_level int)
RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
    UPDATE registration.entry e
       SET units = catalogue.units_for(o.course_code, s.programme_code, r.level)
      FROM registration.course_registration r, people.student s, catalogue.offering o
     WHERE e.registration_id = r.id AND r.student_id = s.id AND e.offering_id = o.id
       AND o.course_code = p_course
       AND (p_programme IS NULL OR s.programme_code = p_programme)
       AND (p_level IS NULL OR r.level = p_level)
       AND e.units IS DISTINCT FROM catalogue.units_for(o.course_code, s.programme_code, r.level)
       AND NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = r.session AND a.state = 'CLOSED')
       AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh JOIN assessment.score sc ON sc.sheet_id = sh.id
                        WHERE sh.offering_id = o.id AND sc.student_id = r.student_id);
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION catalogue.reflect_units(text, text, int) IS
  'V460: a change of units reaches the registrations of the course (of one programme and level, or every programme) not yet examined — in a session not closed, the student with no score on the class.';

CREATE OR REPLACE FUNCTION catalogue.offer_units_reflect()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.units IS NULL THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE' AND OLD.units IS NOT DISTINCT FROM NEW.units THEN RETURN NEW; END IF;
    PERFORM catalogue.reflect_units(NEW.course_code, NEW.programme_code, NEW.level);
    RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS trg_offer_units_reflect ON catalogue.course_offer;
CREATE TRIGGER trg_offer_units_reflect AFTER INSERT OR UPDATE OF units ON catalogue.course_offer
FOR EACH ROW EXECUTE FUNCTION catalogue.offer_units_reflect();

-- a course's own units, changed, reach its own department's programmes that take it at the course's units; another department's
-- programme keeps the units it had, pinned on its binding (a GST/EPS course, the University's, reaches every programme)
CREATE OR REPLACE FUNCTION catalogue.course_units_reflect()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF OLD.units IS DISTINCT FROM NEW.units THEN
        IF NEW.general_office IS NULL AND NEW.kind <> 'GST' THEN
            UPDATE catalogue.course_offer co SET units = OLD.units
              FROM ref.programme p
             WHERE co.course_code = NEW.code AND co.units IS NULL AND p.code = co.programme_code
               AND p.dept_code IS DISTINCT FROM NEW.dept_code;
        END IF;
        PERFORM catalogue.reflect_units(NEW.code, NULL, NULL);
    END IF;
    RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS trg_course_units_reflect ON catalogue.course;
CREATE TRIGGER trg_course_units_reflect AFTER UPDATE OF units ON catalogue.course
FOR EACH ROW EXECUTE FUNCTION catalogue.course_units_reflect();

CREATE OR REPLACE FUNCTION registration.student_menu(p_student uuid, p_session text, p_semester integer)
 RETURNS TABLE(offering_id uuid, course_code text, title text, units integer, kind text, basis text, owner_dept text, carryover boolean, failed_in text, lecturer text, deferred boolean, deferred_from text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V380: the student's stream: a CCE student is offered the Centre's classes, every other student the full-time ones
    WITH s AS (SELECT st.*, people.student_stream(st.id) AS stream FROM people.student st WHERE st.id = p_student),   -- V389: and the School's classes for a PG student
    -- V366: the GST/EPS courses of the programme at this level the student has already passed
    gst_passed AS (SELECT x.course_code FROM finance.gst_eps_rows(p_session, p_student) x WHERE x.status = 'ALREADY_PASSED'),
    offered AS (
        SELECT o.id AS offering_id, c.code, c.title, coalesce(co.units, c.units) AS units, c.kind, co.basis, c.dept_code   -- V460: the programme's units
          FROM s
          JOIN catalogue.course_offer co ON co.programme_code = s.programme_code AND co.level = s.current_level
                                        AND (co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
          JOIN catalogue.course c ON c.code = co.course_code AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester AND o.stream = s.stream
         WHERE (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)
           AND NOT (c.kind = 'GST' AND c.code IN (SELECT gp.course_code FROM gst_passed gp))),
    -- V402: a BSU- code and its MOAU- twin are both on offer; where both reach the student, the student sees their cohort's
    -- family only (cohorts admitted from the stated session register MOAU-, earlier cohorts BSU-); a code with no twin on offer,
    -- or the rule unstated, is shown as before. Carry-overs and deferred courses come by their own code and are untouched.
    eligible AS (
        SELECT e.* FROM offered e
         WHERE NOT (catalogue.other_familys_code(p_student, e.code)
                    AND EXISTS (SELECT 1 FROM offered e2 WHERE e2.code = catalogue.twin_by_code(e.code)))),
    carry AS (
        SELECT o.id AS offering_id, c.code, c.title, catalogue.units_for(c.code, s.programme_code, NULL) AS units, c.kind, 'Carryover'::text AS basis, c.dept_code, cv.failed_in
          FROM registration.carryovers(p_student) cv
          JOIN catalogue.course c ON c.code = cv.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
          CROSS JOIN s
         WHERE o.stream = s.stream AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)),
    -- a course set aside by an approved deferment, due since the student returned, offered this semester and not yet passed
    deferred AS (
        SELECT o.id AS offering_id, c.code, c.title, catalogue.units_for(c.code, s.programme_code, NULL) AS units, c.kind, 'Deferred'::text AS basis, c.dept_code,
               dc.original_session || ' semester ' || dc.original_semester AS deferred_from
          FROM people.deferred_courses(p_student) dc
          JOIN catalogue.course c ON c.code = dc.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
          CROSS JOIN s
         WHERE o.stream = s.stream AND dc.status = 'DEFERRED' AND dc.due
           AND (dc.original_session, dc.original_semester) < (p_session, p_semester)
           AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.code = c.code))
    SELECT x.offering_id, x.code, x.title, x.units, x.kind, x.basis, d.name,
           (x.basis IN ('Carryover','Deferred')), x.failed_in, p.surname || ', ' || p.given_names,
           (x.basis = 'Deferred'), x.deferred_from
      FROM (SELECT e.*, NULL::text AS failed_in, NULL::text AS deferred_from FROM eligible e
            WHERE NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.offering_id = e.offering_id)
              AND NOT EXISTS (SELECT 1 FROM deferred df WHERE df.offering_id = e.offering_id)
            UNION ALL SELECT cv.*, NULL::text AS deferred_from FROM carry cv
            UNION ALL SELECT df.offering_id, df.code, df.title, df.units, df.kind, df.basis, df.dept_code, NULL::text, df.deferred_from FROM deferred df) x
      JOIN ref.department d ON d.code = x.dept_code
      JOIN catalogue.offering o ON o.id = x.offering_id
      LEFT JOIN iam.person p ON p.id = o.lecturer_id
     ORDER BY (x.basis = 'Carryover') DESC, (x.basis = 'Deferred') DESC, x.kind, x.code;
$function$;

CREATE OR REPLACE FUNCTION catalogue.import_courses_rows(p_programme text, p_rows jsonb, p_curriculum text DEFAULT NULL::text)
 RETURNS TABLE(rows integer, courses integer, offers integer, no_dept integer, bad_code integer, skipped integer, first_error text, existing integer)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_prog text; v_dept text; v_code text; v_title text; v_units int; v_level int; v_sem int; v_status text;
        v_kind text; v_basis text; v_lh int; v_ph int; v_curr text; v_owner text; v_status_raw text; v_class text; v_eps boolean; v_both boolean;
        n int := 0; nc int := 0; no int := 0; nnd int := 0; nb int := 0; ns int := 0; ne int := 0; v_firsterr text := NULL;
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
        -- V386: the course the pool holds, however the code is written (CSC101, a merged code, a session copy); a new one in the normal form
        v_code := coalesce(catalogue.resolve_course_code(v_code), v_code);
        n := n + 1;
        IF v_code !~ '^[A-Z][A-Z0-9 /-]{2,19}$' THEN nb := nb + 1; CONTINUE; END IF;

        BEGIN
            v_title := nullif(btrim(coalesce(r->>'title', r->>'courseTitle', '')), '');
            IF v_title IS NULL THEN v_title := v_code; END IF;
            v_units := least(coalesce(nullif(regexp_replace(coalesce(r->>'units', ''), '[^0-9]', '', 'g'), '')::int, 0), 12);
            v_level := coalesce(nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int, 100);
            IF v_level NOT IN (100,200,300,400,500,600) THEN v_level := 100; END IF;
            v_both := catalogue.both_semesters_text(r->>'semester');   -- V386: "Both", "1 & 2"
            v_sem := CASE WHEN v_both THEN 1 ELSE coalesce(nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int, 1) END;
            IF v_sem NOT IN (1,2,3) THEN v_sem := 1; END IF;
            v_lh := nullif(regexp_replace(coalesce(r->>'lh', r->>'LH', ''), '[^0-9]', '', 'g'), '')::int;
            v_ph := nullif(regexp_replace(coalesce(r->>'ph', r->>'PH', ''), '[^0-9]', '', 'g'), '')::int;
            -- V370: the status is read whole before its first letter, so EPS is not taken for E (Elective); EPS, or a GST/EPS
            -- classification column, makes the course general, and EPS files it with the EPS office
            v_status_raw := upper(btrim(coalesce(r->>'status', 'C')));
            v_class := upper(nullif(btrim(coalesce(r->>'classification', r->>'gstEps', '')), ''));
            v_eps := v_status_raw = 'EPS' OR v_class = 'EPS';
            v_status := CASE WHEN v_status_raw IN ('GST', 'EPS') OR v_class IN ('GST', 'EPS') THEN 'G' ELSE upper(left(v_status_raw, 1)) END;
            v_kind := CASE WHEN v_code LIKE 'GST %' OR v_code LIKE 'GST%' THEN 'GST'
                           WHEN v_status = 'G' THEN 'GST'  -- GST/EPS courses carried by status, not a GST code
                           WHEN v_status = 'R' THEN 'Required' WHEN v_status = 'E' THEN 'Elective' ELSE 'Core' END;
            v_basis := CASE WHEN v_kind = 'GST' THEN 'GST' WHEN v_kind = 'Elective' THEN 'Elective' ELSE 'Core' END;

            SELECT dept_code INTO v_owner FROM catalogue.course WHERE code = v_code;
            IF v_owner IS NOT NULL AND v_owner <> v_dept THEN
                -- V332: another department's course, carried by this programme: one course, bound as Borrowed
                -- (or on the basis the row says where it is GST or Elective); its title, units and level are its owner's to set
                v_basis := CASE WHEN v_kind = 'GST' THEN 'GST' WHEN v_kind = 'Elective' THEN 'Elective' ELSE 'Borrowed' END;
                ne := ne + 1;
            ELSE
                INSERT INTO catalogue.course (code, title, units, semester, both_semesters, level, dept_code, kind, lecture_hours, practical_hours, curriculum, state, general_office)
                VALUES (v_code, v_title, v_units, v_sem, v_both, v_level, v_dept, v_kind, v_lh, v_ph, v_curr, 'LIVE', CASE WHEN v_eps THEN 'EPS' END)
                -- V460: an existing course keeps its units; a programme whose file says otherwise gets its own on its binding
                ON CONFLICT (code) DO UPDATE SET title = EXCLUDED.title, units = catalogue.course.units, semester = EXCLUDED.semester, both_semesters = EXCLUDED.both_semesters,
                    level = EXCLUDED.level, kind = EXCLUDED.kind, lecture_hours = EXCLUDED.lecture_hours, practical_hours = EXCLUDED.practical_hours,
                    curriculum = coalesce(EXCLUDED.curriculum, catalogue.course.curriculum),
                    state = CASE WHEN catalogue.course.state IN ('BOARD', 'SENATE') OR catalogue.course.reset_batch_id IS NOT NULL THEN 'LIVE' ELSE catalogue.course.state END,
                    ended_on = CASE WHEN catalogue.course.reset_batch_id IS NOT NULL THEN NULL ELSE catalogue.course.ended_on END,
                    reset_batch_id = NULL,
                    -- V370: EPS files a course no office holds with the EPS office; an office's course stays the office's
                    general_office = CASE WHEN catalogue.course.general_office IS NULL THEN EXCLUDED.general_office ELSE catalogue.course.general_office END;
                nc := nc + 1;
            END IF;

            -- V460: the programme takes the course at the file's units where they differ from the course's
            INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis, added_by, source, units)
            VALUES (v_code, v_prog, v_level, v_basis, v_actor, 'IMPORT',
                    CASE WHEN v_units > 0 AND v_units IS DISTINCT FROM (SELECT c.units FROM catalogue.course c WHERE c.code = v_code) THEN v_units END)
            ON CONFLICT (course_code, programme_code, level) DO UPDATE SET basis = EXCLUDED.basis, units = EXCLUDED.units;

            no := no + 1;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_firsterr IS NULL THEN v_firsterr := left(v_code || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, nc, no, nnd, nb, ns, v_firsterr, ne;
END $function$;

COMMIT;
