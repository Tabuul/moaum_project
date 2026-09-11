-- ═══════════════════════════════════════════════════════════════════════════
-- V082 — migrating past results and registrations from the old portal
--
--   Students carried over from the legacy portal already have results and
--   course registrations — 100 Level for the current 200 Level, and so on.
--   The Examinations Officer and HODs need to load them so a transcript, a
--   GPA and a carry-over are computed from the whole record, not only from
--   what was entered here. Rather than a parallel store, the migration lands
--   the history as the real thing: an approved registration with its course
--   entries, and a PUBLISHED result under a legacy minute — so every screen
--   that reads results reads these too, with no special case.
--
--   The old record does not always carry the CA/Exam split; sometimes only a
--   total is known. A score may now hold that total directly, marked imported,
--   and the grade and points are read from it the same way. Every act is the
--   officer's, on the audit spine.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1 · a score may carry a total when the CA/Exam split is not in the old record ──
ALTER TABLE assessment.score ADD COLUMN total    int     NULL;
ALTER TABLE assessment.score ADD COLUMN imported boolean NOT NULL DEFAULT false;
ALTER TABLE assessment.score DROP CONSTRAINT ck_score_graded;
ALTER TABLE assessment.score ADD CONSTRAINT ck_score_graded CHECK (
    outcome <> 'GRADED' OR (ca IS NOT NULL AND exam IS NOT NULL) OR total IS NOT NULL);
ALTER TABLE assessment.score ADD CONSTRAINT ck_score_total CHECK (total IS NULL OR total BETWEEN 0 AND 100);
-- a bare total belongs only to an imported score; a native score always keeps the split
ALTER TABLE assessment.score ADD CONSTRAINT ck_score_total_imported CHECK (total IS NULL OR imported);

-- the total is the CA+Exam sum, or the imported total when the split is unknown; the grade reads off it
CREATE OR REPLACE FUNCTION assessment.latest_scores(p_sheet uuid)
RETURNS TABLE (student_id uuid, ca int, exam int, total int, grade text, points numeric,
               outcome text, version int, amended boolean)
LANGUAGE sql STABLE AS $$
    SELECT s.student_id, s.ca, s.exam,
           CASE WHEN s.outcome = 'GRADED' THEN coalesce(s.ca + s.exam, s.total) END,
           g.grade, g.points, s.outcome, s.version, s.version > 1
      FROM (SELECT DISTINCT ON (student_id) * FROM assessment.score
             WHERE sheet_id = p_sheet ORDER BY student_id, version DESC) s
      LEFT JOIN LATERAL policy.grade_of(CASE WHEN s.outcome = 'GRADED' THEN coalesce(s.ca + s.exam, s.total) END) g ON true
$$;

-- ── 2 · the scaffolding a migrated row needs, created only if it is missing ──

-- a past session the old portal used; created CLOSED, with its two semesters, from the name
CREATE OR REPLACE FUNCTION assessment.ensure_session(p_name text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE y1 int;
BEGIN
    IF p_name !~ '^[0-9]{4}/[0-9]{4}$' THEN RAISE EXCEPTION 'a session is named YYYY/YYYY, not %', p_name USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_name) THEN
        y1 := left(p_name, 4)::int;
        INSERT INTO policy.academic_session (id, name, starts_on, ends_on, state)
        VALUES (gen_random_uuid(), p_name, make_date(y1, 9, 1), make_date(y1 + 1, 8, 31), 'CLOSED');
    END IF;
    INSERT INTO policy.semester (id, session, number, state)
    SELECT gen_random_uuid(), p_name, n, 'CLOSED' FROM generate_series(1, 2) n
     WHERE NOT EXISTS (SELECT 1 FROM policy.semester s WHERE s.session = p_name AND s.number = n);
END $$;

-- ── 3 · the importer: one semester of a programme, matched by matriculation and course code ──
CREATE OR REPLACE FUNCTION assessment.import_legacy_semester(p_session text, p_semester int, p_rows jsonb, p_with_results boolean)
RETURNS TABLE (rows int, students int, offerings int, registrations int, results int, no_student int, no_course int, no_mark int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_code text; v_units int; v_level int; v_ca int; v_exam int; v_total int; v_outcome text;
        v_student uuid; v_offering uuid; v_sheet uuid; v_reg uuid; v_have_mark boolean;
        n int := 0; n_off int := 0; n_reg int := 0; n_res int := 0; nns int := 0; nnc int := 0; nnm int := 0;
        seen_students uuid[] := '{}'; seen_offerings uuid[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, course, units and the mark' USING ERRCODE = '23514';
    END IF;
    PERFORM assessment.ensure_session(p_session);

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'regNo', r->>'reg_no', '')));
        v_code := upper(btrim(coalesce(r->>'course', r->>'courseCode', r->>'course_code', r->>'code', '')));
        v_code := regexp_replace(v_code, '^([A-Z]{2,4})\s*([0-9]{3})$', '\1 \2');
        IF v_matric = '' OR v_code = '' THEN CONTINUE; END IF;
        n := n + 1;

        SELECT id INTO v_student FROM people.student WHERE upper(matric_no) = v_matric;
        IF v_student IS NULL THEN nns := nns + 1; CONTINUE; END IF;

        IF NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_code) THEN nnc := nnc + 1; CONTINUE; END IF;
        SELECT units, level INTO v_units, v_level FROM catalogue.course WHERE code = v_code;
        v_units := coalesce(nullif(regexp_replace(coalesce(r->>'units', r->>'unit', r->>'cu', ''), '[^0-9]', '', 'g'), '')::int, v_units);
        v_level := coalesce(nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int, v_level);

        -- the offering for the course this session and semester
        SELECT id INTO v_offering FROM catalogue.offering WHERE course_code = v_code AND session = p_session AND semester = p_semester;
        IF v_offering IS NULL THEN
            v_offering := gen_random_uuid();
            INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (v_offering, v_code, p_session, p_semester);
        END IF;
        IF NOT (v_offering = ANY(seen_offerings)) THEN n_off := n_off + 1; seen_offerings := seen_offerings || v_offering; END IF;

        -- the student's enrolment and approved registration for the semester
        INSERT INTO people.enrolment (id, student_id, session, level)
        VALUES (gen_random_uuid(), v_student, p_session, v_level) ON CONFLICT (student_id, session) DO NOTHING;
        SELECT id INTO v_reg FROM registration.course_registration WHERE student_id = v_student AND session = p_session AND semester = p_semester;
        IF v_reg IS NULL THEN
            v_reg := gen_random_uuid();
            INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at, approved_by)
            VALUES (v_reg, v_student, p_session, p_semester, v_level, 'APPROVED', now(), now(), v_actor);
            n_reg := n_reg + 1;
        END IF;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
        VALUES (v_reg, v_offering, v_units, 'CURRENT', 'APPROVED')
        ON CONFLICT (registration_id, offering_id) DO UPDATE SET units = EXCLUDED.units, status = 'APPROVED';
        IF NOT (v_student = ANY(seen_students)) THEN seen_students := seen_students || v_student; END IF;

        IF NOT p_with_results THEN CONTINUE; END IF;

        -- the mark: the CA/Exam split when the old record has it, else the total
        v_ca := nullif(regexp_replace(coalesce(r->>'ca', r->>'CA', ''), '[^0-9]', '', 'g'), '')::int;
        v_exam := nullif(regexp_replace(coalesce(r->>'exam', r->>'EXAM', ''), '[^0-9]', '', 'g'), '')::int;
        v_total := nullif(regexp_replace(coalesce(r->>'total', r->>'TOTAL', r->>'score', r->>'SCORE', r->>'mark', ''), '[^0-9]', '', 'g'), '')::int;
        v_outcome := upper(btrim(coalesce(r->>'outcome', 'GRADED')));
        IF v_outcome NOT IN ('GRADED','ABSENT','WITHHELD','INCOMPLETE','MALPRACTICE','EXEMPTED') THEN v_outcome := 'GRADED'; END IF;
        v_have_mark := (v_ca IS NOT NULL AND v_exam IS NOT NULL) OR v_total IS NOT NULL;
        IF v_outcome = 'GRADED' AND NOT v_have_mark THEN nnm := nnm + 1; CONTINUE; END IF;
        IF v_ca IS NOT NULL AND v_exam IS NULL AND v_total IS NULL THEN v_total := v_ca; v_ca := NULL; END IF;

        -- the score sheet, PUBLISHED under a legacy minute so the result stands as final
        SELECT id INTO v_sheet FROM assessment.score_sheet WHERE offering_id = v_offering;
        IF v_sheet IS NULL THEN
            v_sheet := gen_random_uuid();
            INSERT INTO assessment.score_sheet (id, offering_id, stage, senate_minute, published_at)
            VALUES (v_sheet, v_offering, 'PUBLISHED', 'Migrated from the legacy portal', now());
        ELSIF (SELECT stage FROM assessment.score_sheet WHERE id = v_sheet) <> 'PUBLISHED' THEN
            UPDATE assessment.score_sheet SET stage = 'PUBLISHED', senate_minute = coalesce(senate_minute, 'Migrated from the legacy portal'),
                   published_at = coalesce(published_at, now()) WHERE id = v_sheet;
        END IF;
        INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, total, outcome, imported, reason)
        VALUES (v_sheet, v_student,
                coalesce((SELECT max(version) + 1 FROM assessment.score WHERE sheet_id = v_sheet AND student_id = v_student), 1),
                CASE WHEN v_outcome = 'GRADED' AND v_exam IS NOT NULL THEN v_ca END,
                CASE WHEN v_outcome = 'GRADED' AND v_exam IS NOT NULL THEN v_exam END,
                CASE WHEN v_outcome = 'GRADED' AND v_exam IS NULL THEN v_total END,
                v_outcome, true,
                CASE WHEN (SELECT count(*) FROM assessment.score WHERE sheet_id = v_sheet AND student_id = v_student) > 0
                     THEN 'Re-imported from the legacy portal' END);
        n_res := n_res + 1;
    END LOOP;
    RETURN QUERY SELECT n, cardinality(seen_students), n_off, n_reg, n_res, nns, nnc, nnm;
END $$;

-- ── 4 · the students themselves, exported from the old portal (the first migration step) ──
-- Students carried over already have a matriculation number and are on the register; created ACTIVE and
-- matriculated so the results and registration that follow can match them by number. Biodata upserted by number.
CREATE OR REPLACE FUNCTION people.import_students(p_rows jsonb)
RETURNS TABLE (rows int, created int, updated int, no_programme int, bad_number int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_prog text; v_prog_code text; v_sex text; v_dob date; v_mode text; v_es text; v_el int; v_cl int;
        v_surname text; v_others text; v_yy text; v_exists boolean;
        n int := 0; nc int := 0; nu int := 0; nnp int := 0; nbn int := 0;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, name, programme, level' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'regNo', '')));
        IF v_matric = '' THEN CONTINUE; END IF;
        n := n + 1;
        IF v_matric !~ '^MOAUM/[A-Z]{2,4}/[0-9]{2}/[0-9]{4}$' THEN nbn := nbn + 1; CONTINUE; END IF;

        v_prog := btrim(coalesce(r->>'programme', r->>'programmeCode', r->>'programme_code', r->>'course', ''));
        SELECT code INTO v_prog_code FROM ref.programme WHERE upper(code) = upper(v_prog);
        IF v_prog_code IS NULL THEN SELECT code INTO v_prog_code FROM ref.programme WHERE upper(name) = upper(v_prog) ORDER BY archived, code LIMIT 1; END IF;
        IF v_prog_code IS NULL THEN nnp := nnp + 1; CONTINUE; END IF;

        -- name: a surname + other names, or a single "SURNAME, Other Names" / "Other Names SURNAME" field
        v_surname := nullif(btrim(coalesce(r->>'surname', '')), '');
        v_others := nullif(btrim(coalesce(r->>'otherNames', r->>'other_names', r->>'othernames', '')), '');
        IF v_surname IS NULL THEN
            DECLARE nm text := btrim(coalesce(r->>'name', r->>'fullName', ''));
            BEGIN
                IF position(',' IN nm) > 0 THEN v_surname := btrim(split_part(nm, ',', 1)); v_others := btrim(substr(nm, position(',' IN nm) + 1));
                ELSE v_surname := split_part(nm, ' ', 1); v_others := nullif(btrim(substr(nm, length(split_part(nm, ' ', 1)) + 1)), ''); END IF;
            END;
        END IF;
        IF v_surname IS NULL OR v_surname = '' THEN v_surname := 'UNKNOWN'; END IF;
        v_others := coalesce(v_others, '');

        v_sex := upper(left(btrim(coalesce(r->>'sex', r->>'gender', '')), 1));
        IF v_sex NOT IN ('F','M') THEN v_sex := NULL; END IF;
        BEGIN v_dob := (r->>'dob')::date; EXCEPTION WHEN OTHERS THEN BEGIN v_dob := (r->>'dateOfBirth')::date; EXCEPTION WHEN OTHERS THEN v_dob := NULL; END; END;
        v_mode := upper(btrim(coalesce(r->>'entryMode', r->>'entry_mode', 'UTME')));
        IF v_mode NOT IN ('UTME','DIRECT_ENTRY','TRANSFER','POSTGRADUATE','JUPEB','SANDWICH') THEN v_mode := 'UTME'; END IF;
        v_yy := split_part(v_matric, '/', 3);
        v_es := coalesce(nullif(btrim(coalesce(r->>'entrySession', r->>'entry_session', '')), ''), '20' || v_yy || '/20' || lpad((v_yy::int + 1)::text, 2, '0'));
        v_el := coalesce(nullif(regexp_replace(coalesce(r->>'entryLevel', r->>'entry_level', ''), '[^0-9]', '', 'g'), '')::int, CASE WHEN v_mode = 'UTME' THEN 100 ELSE 200 END);
        v_cl := coalesce(nullif(regexp_replace(coalesce(r->>'level', r->>'currentLevel', r->>'current_level', ''), '[^0-9]', '', 'g'), '')::int, v_el);
        IF v_el NOT IN (100,200,300,400,500,600) THEN v_el := 100; END IF;
        IF v_cl NOT IN (100,200,300,400,500,600) THEN v_cl := v_el; END IF;

        SELECT true INTO v_exists FROM people.student WHERE upper(matric_no) = v_matric;
        INSERT INTO people.student (id, matric_no, surname, other_names, sex, date_of_birth, programme_code, entry_mode,
                                    entry_session, entry_level, current_level, status, matriculated_at)
        VALUES (gen_random_uuid(), v_matric, v_surname, v_others, v_sex, v_dob, v_prog_code, v_mode, v_es, v_el, v_cl, 'ACTIVE', now())
        ON CONFLICT (matric_no) DO UPDATE SET surname = EXCLUDED.surname, other_names = EXCLUDED.other_names,
            sex = coalesce(EXCLUDED.sex, people.student.sex), date_of_birth = coalesce(EXCLUDED.date_of_birth, people.student.date_of_birth),
            programme_code = EXCLUDED.programme_code, current_level = EXCLUDED.current_level;
        IF coalesce(v_exists, false) THEN nu := nu + 1; ELSE nc := nc + 1; END IF;
    END LOOP;
    RETURN QUERY SELECT n, nc, nu, nnp, nbn;
END $$;

COMMIT;
