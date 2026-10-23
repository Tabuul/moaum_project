-- ═══════════════════════════════════════
-- V646 — One course code, different titles: separate courses
--
-- The University's master prompt of 23 October 2026 ("course code duplicates + BMAS/CCMAS course availability for 400 & 500
-- level"): the same course code may carry different courses — CSC 401 Computer Networks under CCMAS, CSC 401 Advanced Computer
-- Systems under BMAS — each its own course, never merged, never one title written over the other; with its answers: separate
-- courses (each its own record, class, lecturer, score sheet and results), and the courses already held reported for review.
--
-- What held: the course code is the pool's key (catalogue.course.code, V001) — the classes, programme bindings, registrations
-- (through the class), results, CBT papers, questions, prerequisites and deferrals point at it — so a code was one course. The
-- structure upload (catalogue.import_courses_rows, V484) wrote the file's title over the course's (ON CONFLICT … title =
-- EXCLUDED.title): a department uploading its BMAS structure, then its CCMAS one, left CSC 401 with the second file's title, and
-- both curricula's students in one class and one result sheet. A course created under a held code was refused (create_course).
-- The BMAS/CCMAS availability the prompt asks for at 400 and 500 Level already holds: since V590 (curriculum_open, on) a student
-- sees every course bound to the programme at their level whatever its curriculum, and a course added beside the list is judged
-- without the curriculum test.
--
-- Now:
--   · a second course under a code is its own course: its own key — the code and its curriculum, CSC 401 BMAS (CCMAS, or V2… for
--     one of no curriculum) — so every class, binding, registration, result, sheet, examination and carry-over already keyed by
--     the course stays exactly as it is, and the new course has its own; catalogue.course.id stays the Course ID;
--     catalogue.shown_code(key) is the code shown and searched (CSC 401), catalogue.code_variant(key) the curriculum mark;
--   · the pool holds a code and a title once (ux_course_shown_code_title on the code shown and catalogue.title_key(title), V445 —
--     case, spacing and punctuation aside): the same code with the same title is the same course, whatever the curriculum;
--   · catalogue.create_course takes the curriculum and creates a separate course under a code held under another title (the
--     same code and title refused as before);
--   · the structure upload never writes a title over a course's (nor a curriculum over the one it has): a row whose code the
--     pool holds under another title is
--     refused until the upload says, row by row, the same course (bound to it, its title kept; sameAs names which where the
--     code holds more than one) or a separate course (created under the code, with the file's title and curriculum) —
--     COURSE_TITLE_DIFFERS, previewed by catalogue.structure_title_choices;
--   · catalogue.same_code_courses(): the Duplicate course code report — every code held more than once, and every course whose
--     title was changed (from the audit trail), with its curriculum, owner, level, semester, state and the programmes it is
--     bound to; catalogue.separate_course moves chosen programme bindings of a course to a separate course under its code
--     (the Academic Office or the Registry, with a reason; history stays where it is).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V646: one course code, different titles — separate courses', true);

-- ── 1 · the code shown, the curriculum mark, the title compared ─────────────────────────────────────────────────────────
CREATE FUNCTION catalogue.shown_code(p_code text) RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT regexp_replace(p_code, ' (BMAS|CCMAS|V)[0-9]?$', '')
$$;
COMMENT ON FUNCTION catalogue.shown_code(text) IS
  'V646: the code a course is shown and searched under — its key without the mark of a separate course under the same code '
  '(CSC 401 BMAS, CSC 401 CCMAS2, CSC 401 V2 are all CSC 401).';

CREATE FUNCTION catalogue.code_variant(p_code text) RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT (regexp_match(p_code, ' ((BMAS|CCMAS|V)[0-9]?)$'))[1]
$$;
COMMENT ON FUNCTION catalogue.code_variant(text) IS
  'V646: the mark of a separate course under a code (BMAS, CCMAS2, V2), or NULL for the course the code was first held by.';

-- a title is compared by catalogue.title_key (V445): case, spacing and punctuation aside, Intro read as Introduction
CREATE UNIQUE INDEX ux_course_shown_code_title ON catalogue.course (catalogue.shown_code(code), catalogue.title_key(title));
COMMENT ON INDEX catalogue.ux_course_shown_code_title IS
  'V646: a code and a title are held once — the same code with the same title is the same course; the same code with another title is a separate course.';

-- the key of a separate course under a code: the code and its curriculum (CSC 401 BMAS), then a number; V2… for none
CREATE FUNCTION catalogue.variant_key(p_code text, p_curriculum text) RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE v_base text := catalogue.shown_code(regexp_replace(upper(btrim(coalesce(p_code, ''))), '\s+', ' ', 'g'));
        v_curr text := CASE WHEN upper(btrim(coalesce(p_curriculum, ''))) IN ('BMAS', 'CCMAS') THEN upper(btrim(p_curriculum)) END;
        v_try text;
BEGIN
    FOR i IN 1..8 LOOP
        v_try := v_base || ' ' || CASE WHEN v_curr IS NOT NULL THEN v_curr || CASE WHEN i > 1 THEN i::text ELSE '' END ELSE 'V' || (i + 1)::text END;
        IF v_try ~ '^[A-Z][A-Z0-9 /-]{2,19}$' AND NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_try) THEN
            RETURN v_try;
        END IF;
    END LOOP;
    RAISE EXCEPTION 'COURSE_CODE_FULL: no further course can be held under the code %', v_base USING ERRCODE = '23514',
        HINT = 'A code holds its first course and up to eight more; merge courses that are the same, or use another code.';
END $$;
COMMENT ON FUNCTION catalogue.variant_key(text, text) IS
  'V646: the key a separate course under a code takes — the code and its curriculum (CSC 401 BMAS, then CSC 401 BMAS2…), or CSC 401 V2… for one of no curriculum; the first free one.';

CREATE FUNCTION catalogue.course_by_code_title(p_code text, p_title text) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT c.code FROM catalogue.course c
     WHERE catalogue.shown_code(c.code) = catalogue.shown_code(p_code) AND catalogue.title_key(c.title) = catalogue.title_key(p_title)
     ORDER BY c.code LIMIT 1
$$;
COMMENT ON FUNCTION catalogue.course_by_code_title(text, text) IS
  'V646: the course the pool holds under a code (as shown) with a title (as compared), or NULL.';

-- ── 2 · a course created under a code held under another title ─────────────────────────────────────────────────────────
CREATE FUNCTION catalogue.create_course(p_code text, p_title text, p_units integer, p_semester integer, p_level integer, p_dept text, p_kind text,
                                        p_curriculum text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_code text;
        v_curr text := CASE WHEN upper(btrim(coalesce(p_curriculum, ''))) IN ('BMAS', 'CCMAS') THEN upper(btrim(p_curriculum)) END;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a course is created by a person' USING ERRCODE = '23514';
    END IF;
    -- V592: the plain code, or the plain code after BSU- or MOAU-, written loosely or not
    v_code := catalogue.normal_code(p_code);
    IF v_code IS NULL OR v_code !~ '^((BSU|MOAU)-)?[A-Z]{3} [0-9]{3}$' THEN
        RAISE EXCEPTION 'CAT_CODE: a course code is three letters, a space and three digits (CSC 311), or the same after BSU- or MOAU- (BSU-PHY 106, MOAU-PHY 106) — % fits neither', coalesce(p_code, '')
            USING ERRCODE = '23514', HINT = 'Three letters for the subject and a three-digit number, e.g. MTH 212; for a BSU- or MOAU- course the prefix and a hyphen first, e.g. BSU-PHY 106.';
    END IF;
    IF p_units IS NULL OR p_units < 0 OR p_units > 12 THEN
        RAISE EXCEPTION 'a course is worth between 0 and 12 units' USING ERRCODE = '23514',
            HINT = 'Most courses are 2 or 3 units; the approved teaching maximum for a lecturer is 12.';
    END IF;
    -- V646: the same code and title is the same course; the same code under another title is a separate course
    IF catalogue.course_by_code_title(v_code, p_title) IS NOT NULL THEN
        RAISE EXCEPTION 'a course with the code % and the title % already exists', v_code, btrim(p_title) USING ERRCODE = '23505',
            HINT = 'The same code and title is the same course: offer it to the programme instead.';
    END IF;
    IF EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_code) THEN
        v_code := catalogue.variant_key(v_code, v_curr);
    END IF;
    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, curriculum)
    VALUES (v_code, btrim(p_title), p_units, p_semester, p_level, p_dept, coalesce(nullif(btrim(p_kind), ''), 'Core'), 'BOARD', v_curr);
    RETURN v_code;
END $function$;
COMMENT ON FUNCTION catalogue.create_course(text, text, integer, integer, integer, text, text, text) IS
  'V049, V592, V646: a course created — its code three letters, a space and three digits (CSC 311), or the same after BSU- or MOAU-, put right when written loosely; the same code and title refused; (V646) a code held under another title gives a separate course under it (CSC 401 BMAS), of the curriculum named. Returns the course''s key.';

CREATE OR REPLACE FUNCTION catalogue.create_course(p_code text, p_title text, p_units integer, p_semester integer, p_level integer, p_dept text, p_kind text)
 RETURNS text LANGUAGE sql AS $$
    SELECT catalogue.create_course(p_code, p_title, p_units, p_semester, p_level, p_dept, p_kind, NULL::text)
$$;
COMMENT ON FUNCTION catalogue.create_course(text, text, integer, integer, integer, text, text) IS
  'V049, V592, V646: catalogue.create_course of no curriculum.';

-- ── 3 · the structure upload: the same course or a separate one, never a title written over ────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.import_courses_rows(p_programme text, p_rows jsonb, p_curriculum text DEFAULT NULL)
 RETURNS TABLE(rows integer, courses integer, offers integer, no_dept integer, bad_code integer, skipped integer, first_error text, existing integer)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_prog text; v_dept text; v_code text; v_title text; v_units int; v_level int; v_sem int; v_status text;
        v_kind text; v_basis text; v_lh int; v_ph int; v_curr text; v_owner text; v_status_raw text; v_class text; v_eps boolean; v_both boolean;
        v_pg boolean; v_pg_level int; v_pg_basis text; v_choice text; v_match text; v_undecided text;
        n int := 0; nc int := 0; no int := 0; nnd int := 0; nb int := 0; ns int := 0; ne int := 0; v_firsterr text := NULL;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a course upload is made by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the structure is rows: course code, title, units, status, level, semester' USING ERRCODE = '23514';
    END IF;
    v_curr := upper(nullif(btrim(coalesce(p_curriculum, '')), ''));
    IF v_curr IS NOT NULL AND v_curr NOT IN ('CCMAS', 'BMAS') THEN v_curr := NULL; END IF;
    SELECT code, dept_code, category = 'POST GRADUATE', CASE WHEN category = 'POST GRADUATE' THEN admissions.pg_award_level(pg_award) END
      INTO v_prog, v_dept, v_pg, v_pg_level FROM ref.programme
     WHERE upper(code) = upper(btrim(p_programme)) OR upper(name) = upper(btrim(p_programme)) ORDER BY archived, code LIMIT 1;
    IF v_prog IS NULL THEN RAISE EXCEPTION 'no programme is coded or named %', p_programme USING ERRCODE = '23503'; END IF;
    IF v_dept IS NULL OR NOT EXISTS (SELECT 1 FROM ref.department WHERE code = v_dept) THEN
        RAISE EXCEPTION 'the programme % has no department on the register to own its courses', v_prog USING ERRCODE = '23514';
    END IF;
    -- V646: a code the pool holds under another title is the same course or a separate one — the upload says which, row by row,
    -- before anything is written
    SELECT string_agg(DISTINCT q.code || ' "' || q.title || '" (held as: ' || q.held || ')', '; ') INTO v_undecided
      FROM (SELECT catalogue.resolve_course_code(regexp_replace(upper(btrim(coalesce(e->>'code', e->>'courseCode', e->>'course_code', ''))), '\s+', ' ', 'g')) AS code,
                   nullif(btrim(coalesce(e->>'title', e->>'courseTitle', '')), '') AS title, upper(coalesce(e->>'titleChoice', '')) AS choice
              FROM jsonb_array_elements(p_rows) e) w
      CROSS JOIN LATERAL (SELECT w.code, w.title, string_agg(c.title, ' / ' ORDER BY c.code) AS held
                            FROM catalogue.course c WHERE catalogue.shown_code(c.code) = catalogue.shown_code(w.code)
                          HAVING count(*) > 0 AND bool_and(catalogue.title_key(c.title) <> catalogue.title_key(w.title))) q
     WHERE w.code IS NOT NULL AND w.title IS NOT NULL AND w.choice NOT IN ('SAME', 'SEPARATE');
    IF v_undecided IS NOT NULL THEN
        RAISE EXCEPTION 'COURSE_TITLE_DIFFERS: the pool holds these codes under other titles; say for each whether it is the same course or a separate one: %', left(v_undecided, 1500)
            USING ERRCODE = '23514', HINT = 'The upload preview lists them: the same course keeps the title the pool holds; a separate course is created under the same code.';
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
            -- V646: the course the row means — the one held under this code and title; a separate course under the code where the
            -- upload says so; the course already held (its title kept), or the one sameAs names, where it says it is the same course
            v_choice := upper(coalesce(r->>'titleChoice', ''));
            v_match := catalogue.course_by_code_title(v_code, v_title);
            IF v_match IS NOT NULL THEN
                v_code := v_match;
            ELSIF v_choice = 'SEPARATE' AND EXISTS (SELECT 1 FROM catalogue.course c WHERE catalogue.shown_code(c.code) = catalogue.shown_code(v_code)) THEN
                v_code := catalogue.variant_key(v_code, v_curr);
            ELSIF v_choice = 'SAME' AND nullif(btrim(coalesce(r->>'sameAs', '')), '') IS NOT NULL
                  AND EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = upper(btrim(r->>'sameAs')) AND catalogue.shown_code(c.code) = catalogue.shown_code(v_code)) THEN
                v_code := upper(btrim(r->>'sameAs'));
            END IF;
            v_units := least(coalesce(nullif(regexp_replace(coalesce(r->>'units', ''), '[^0-9]', '', 'g'), '')::int, 0), 12);
            -- V484: a postgraduate programme's levels are 700, 800 and 900 (the programme's own award level when the row gives
            -- none, or one outside them); an undergraduate programme's 100 to 600, as before
            IF v_pg THEN
                v_level := coalesce(nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int, v_pg_level);
                IF v_level NOT IN (700, 800, 900) THEN v_level := v_pg_level; END IF;
            ELSE
                v_level := coalesce(nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int, 100);
                IF v_level NOT IN (100,200,300,400,500,600) THEN v_level := 100; END IF;
            END IF;
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
            -- V484: a postgraduate programme takes a course as Deficiency or Research where the row says so (D, DEF…, RES…,
            -- THESIS, DISSERTATION, PROJECT); such a course is a core course of the pool, its basis the programme's
            v_pg_basis := CASE WHEN NOT v_pg THEN NULL
                               WHEN v_status_raw ~ '^(D$|DEF)' THEN 'Deficiency'
                               WHEN v_status_raw ~ '^(RES|THES|DISS|PROJ)' THEN 'Research' END;
            IF v_pg_basis IS NOT NULL THEN v_kind := 'Core'; v_basis := v_pg_basis; END IF;
            IF v_pg AND v_kind = 'Required' THEN v_kind := 'Core'; END IF;

            SELECT dept_code INTO v_owner FROM catalogue.course WHERE code = v_code;
            IF v_owner IS NOT NULL AND v_owner <> v_dept THEN
                -- V332: another department's course, carried by this programme: one course, bound as Borrowed
                -- (or on the basis the row says where it is GST or Elective); its title, units and level are its owner's to set
                v_basis := coalesce(v_pg_basis, CASE WHEN v_kind = 'GST' THEN 'GST' WHEN v_kind = 'Elective' THEN 'Elective' ELSE 'Borrowed' END);
                ne := ne + 1;
            ELSE
                INSERT INTO catalogue.course (code, title, units, semester, both_semesters, level, dept_code, kind, lecture_hours, practical_hours, curriculum, state, general_office)
                VALUES (v_code, v_title, v_units, v_sem, v_both, v_level, v_dept, v_kind, v_lh, v_ph, v_curr, 'LIVE', CASE WHEN v_eps THEN 'EPS' END)
                -- V460: an existing course keeps its units; a programme whose file says otherwise gets its own on its binding
                -- V646: never the file's title over the course's — a different title is a separate course or the same course kept
                ON CONFLICT (code) DO UPDATE SET title = catalogue.course.title, units = catalogue.course.units, semester = EXCLUDED.semester, both_semesters = EXCLUDED.both_semesters,
                    level = EXCLUDED.level, kind = EXCLUDED.kind, lecture_hours = EXCLUDED.lecture_hours, practical_hours = EXCLUDED.practical_hours,
                    curriculum = coalesce(catalogue.course.curriculum, EXCLUDED.curriculum),   -- V646: a course keeps the curriculum it has
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
COMMENT ON FUNCTION catalogue.import_courses_rows(text, jsonb, text) IS
  'V386, V460, V484, V646: one programme''s course structure loaded — each course created or found in the pool and bound at its level; V484: a postgraduate programme''s rows at 700, 800 or 900 and as Deficiency or Research where the status says so; V646: a course found by its code and title, a title never written over, and a code held under another title refused (COURSE_TITLE_DIFFERS) until the row says the same course (titleChoice SAME, sameAs) or a separate one (SEPARATE, created under the code with the upload''s curriculum).';

-- what loading these structures would ask: the rows whose code the pool holds under other titles — read, nothing written
CREATE FUNCTION catalogue.structure_title_choices(p_groups jsonb)
RETURNS TABLE (programme text, code text, title text, level integer, held jsonb) LANGUAGE sql STABLE AS $$
    WITH g AS (
        SELECT upper(btrim(x->>'programme')) AS programme, r
          FROM jsonb_array_elements(coalesce(p_groups, '[]'::jsonb)) x, jsonb_array_elements(coalesce(x->'rows', '[]'::jsonb)) r),
    f AS (
        SELECT DISTINCT g.programme,
               catalogue.resolve_course_code(regexp_replace(upper(btrim(coalesce(g.r->>'code', g.r->>'courseCode', g.r->>'course_code', ''))), '\s+', ' ', 'g')) AS code,
               nullif(btrim(coalesce(g.r->>'title', g.r->>'courseTitle', '')), '') AS title,
               nullif(regexp_replace(coalesce(g.r->>'level', ''), '[^0-9]', '', 'g'), '')::int AS level
          FROM g)
    SELECT f.programme, f.code, f.title, f.level,
           (SELECT jsonb_agg(jsonb_build_object('code', c.code, 'title', c.title, 'curriculum', c.curriculum, 'dept', c.dept_code,
                                                'level', c.level, 'semester', c.semester, 'variant', catalogue.code_variant(c.code)) ORDER BY c.code)
              FROM catalogue.course c WHERE catalogue.shown_code(c.code) = catalogue.shown_code(f.code))
      FROM f
     WHERE f.code IS NOT NULL AND f.title IS NOT NULL
       AND EXISTS (SELECT 1 FROM catalogue.course c WHERE catalogue.shown_code(c.code) = catalogue.shown_code(f.code))
       AND NOT EXISTS (SELECT 1 FROM catalogue.course c WHERE catalogue.shown_code(c.code) = catalogue.shown_code(f.code)
                          AND catalogue.title_key(c.title) = catalogue.title_key(f.title))
     ORDER BY f.code, f.programme, f.level
$$;
COMMENT ON FUNCTION catalogue.structure_title_choices(jsonb) IS
  'V646: the rows of structures to be uploaded whose code the pool holds under other titles, each with the courses held under the code — the choice the upload asks for (the same course, or a separate one). Read, nothing written.';

-- ── 4 · the Duplicate course code report ────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION catalogue.same_code_courses()
RETURNS TABLE (shown_code text, course_code text, course_id uuid, title text, curriculum text, variant text, dept_code text, department text,
               faculty text, level integer, semester integer, kind text, state text, programmes integer, programme_list text,
               courses_under_code integer, title_changes integer, earlier_titles text, last_title_change timestamptz)
LANGUAGE sql STABLE AS $$
    WITH c AS (SELECT x.*, catalogue.shown_code(x.code) AS shown FROM catalogue.course x),
    n AS (SELECT shown, count(*)::int AS k FROM c GROUP BY shown),
    -- a title changed after the course was created, from the audit trail
    t AS (SELECT a.subject_id AS id, count(*)::int AS changes, string_agg(DISTINCT a.before_state->>'title', ' / ') AS earlier, max(a.occurred_at) AS last_at
            FROM audit.entries a
           WHERE a.subject_type = 'catalogue.course' AND a.action = 'UPDATE'
             AND a.before_state->>'title' IS DISTINCT FROM a.after_state->>'title'
           GROUP BY a.subject_id),
    b AS (SELECT o.course_code, count(*)::int AS k, string_agg(o.programme_code || ' (' || o.level || ')', ', ' ORDER BY o.programme_code, o.level) AS list
            FROM catalogue.course_offer o GROUP BY o.course_code)
    SELECT c.shown, c.code, c.id, c.title, c.curriculum, catalogue.code_variant(c.code), c.dept_code, d.name, f.name, c.level, c.semester, c.kind, c.state,
           coalesce(b.k, 0), b.list, n.k, coalesce(t.changes, 0), t.earlier, t.last_at
      FROM c
      JOIN n ON n.shown = c.shown
      LEFT JOIN t ON t.id = c.id
      LEFT JOIN b ON b.course_code = c.code
      LEFT JOIN ref.department d ON d.code = c.dept_code
      LEFT JOIN ref.faculty f ON f.code = d.faculty_code
     WHERE n.k > 1 OR t.changes > 0
     ORDER BY c.shown, c.code
$$;
COMMENT ON FUNCTION catalogue.same_code_courses() IS
  'V646: the Duplicate course code report — every course under a code the pool holds more than once, and every course whose title was changed after it was created (the earlier titles and the last change from the audit trail), with its curriculum, owner, faculty, level, semester, kind, state and the programmes it is bound to.';

-- a course's bindings moved to a separate course under its code
CREATE FUNCTION catalogue.separate_course(p_code text, p_title text, p_curriculum text, p_bindings jsonb, p_reason text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
        v_curr text := CASE WHEN upper(btrim(coalesce(p_curriculum, ''))) IN ('BMAS', 'CCMAS') THEN upper(btrim(p_curriculum)) END;
        c catalogue.course; v_new text; b jsonb; n int; moved int := 0; opened int;
BEGIN
    IF coalesce(v_office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'COURSE_SEPARATE_OFFICE: a separate course under a code is made by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF v_reason IS NULL OR length(v_reason) < 10 THEN
        RAISE EXCEPTION 'COURSE_SEPARATE_REASON: say why the course is separated, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM catalogue.course WHERE code = upper(btrim(p_code)) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'COURSE_NOT_FOUND: no course %', p_code USING ERRCODE = 'P0002'; END IF;
    IF nullif(btrim(coalesce(p_title, '')), '') IS NULL THEN
        RAISE EXCEPTION 'COURSE_SEPARATE_TITLE: a separate course has its own title' USING ERRCODE = '23514';
    END IF;
    IF catalogue.course_by_code_title(c.code, p_title) IS NOT NULL THEN
        RAISE EXCEPTION 'COURSE_SAME_TITLE: % already holds a course titled %; that is the same course', catalogue.shown_code(c.code), btrim(p_title) USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', v_reason, true);
    v_new := catalogue.variant_key(c.code, v_curr);
    INSERT INTO catalogue.course (code, title, units, semester, both_semesters, level, dept_code, kind, lecture_hours, practical_hours, curriculum, state,
                                  general_office, ca_max, industrial_training, cbt_enabled, owner_programme, description)
    VALUES (v_new, btrim(p_title), c.units, c.semester, c.both_semesters, c.level, c.dept_code, c.kind, c.lecture_hours, c.practical_hours, v_curr, 'LIVE',
            c.general_office, c.ca_max, c.industrial_training, c.cbt_enabled, c.owner_programme, NULL);
    FOR b IN SELECT * FROM jsonb_array_elements(coalesce(p_bindings, '[]'::jsonb)) LOOP
        UPDATE catalogue.course_offer SET course_code = v_new
         WHERE course_code = c.code AND programme_code = upper(btrim(b->>'programme')) AND level = (b->>'level')::int;
        GET DIAGNOSTICS n = ROW_COUNT;
        moved := moved + n;
    END LOOP;
    opened := catalogue.open_classes_for_courses(ARRAY[v_new]);
    RETURN jsonb_build_object('code', v_new, 'shownCode', catalogue.shown_code(v_new), 'title', btrim(p_title), 'curriculum', v_curr,
                              'bindingsMoved', moved, 'classesOpened', opened);
END $$;
COMMENT ON FUNCTION catalogue.separate_course(text, text, text, jsonb, text) IS
  'V646: a separate course under a course''s code — its own title and curriculum, the course''s units, semester, level, owner, kind and settings — with the chosen programme bindings (programme, level) moved to it and its classes opened for the sessions open; the Academic Office or the Registry, with a reason. Classes, registrations and results already held stay with the course they were made under.';

COMMIT;
