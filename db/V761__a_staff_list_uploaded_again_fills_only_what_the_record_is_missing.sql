-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V761 · A staff list uploaded again fills only what the record is missing
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's decisions of 14 November 2026, on uploading the teaching or non-teaching staff list again:
--    · a member of staff already on record (found by the staff number) keeps what the record holds: each detail the list gives —
--      the names, sex, date of birth, LGA, state, dates of appointment, confirmation and promotion, rank, category, cadre — is
--      written only where the record has none (NA, NIL or a dash on record is none, as on the list); a different value on record
--      is kept and reported ("differs from the one on the portal, which is kept"), for HR to look at. Each date with the note the
--      roll may give in its place (confirmation, last promotion) is one detail;
--    · the posting (unit, department, faculty and the posting as the roll writes it) is one detail: a record placed nowhere takes
--      the roll's posting; a record placed in the same place as the roll — the most specific place on record (unit, else
--      department, else faculty) is the roll's at that level — has only its missing parts filled; on the teaching-staff list a
--      faculty alone on record (the half posting an upload may have left) also takes a department of that faculty; a record
--      placed elsewhere keeps its whole posting, reported once ("Current posting: the roll's … differs from the one on the
--      portal, which is kept (…)"); a faculty the roll states against the one on record, or against the department's, is reported
--      and not written;
--    · the salary scale and step are one detail too: a record with neither takes the roll's; one on the roll's scale has a
--      missing step filled; any other grade on record is kept, reported once ("Salary scale and step");
--    · their sign-in, password and offices are never touched by an upload: the teaching-staff upload filling a department beside a
--      lecturer office open in another department leaves the office where it is and reports it (the Edit form moves it);
--    · a staff number not on record is still a new member of staff, with every detail the list gives; the teaching-staff upload
--      still gives them a sign-in and the lecturer office, the non-teaching upload still none (the University's decision);
--    · the Add forms (one member of staff typed by an officer, the names confirmed before a rename) still write what is typed, and
--      the lecturer Add form still moves the lecturer office with a department it changes.
--  V750's decision of 12 November 2026 ("names, rank, dates and posting follow the roll") is replaced by this one.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V761: a staff list uploaded again fills only what the record is missing', true);

-- ── hrm.roll_apply: someone on record has only what the record lacks filled ─────────────────────────────────────────────────────
DO $$
DECLARE d text; n int; i int;
    edits text[][] := ARRAY[
      ARRAY['    v_pid uuid := p_person;',
            '    v_pid uuid := p_person;
    -- V761: a list row on someone on record fills only what the record lacks; an Add form (typed by an officer) writes what it gives
    v_fill boolean := p_person IS NOT NULL AND NOT coalesce((p_vals->>''add_form'')::boolean, false);
    -- V761: the posting and the grade on record and on the roll, and what the upload does with each (WRITE, SAME, ELSEWHERE)
    v_ru text; v_rd text; v_rf text; v_nu text; v_nd text; v_nf text; v_posting text := ''WRITE'';
    v_rs text; v_rstep text; v_ns text; v_nstep text; v_grade text := ''WRITE''; v_dfac text;'],
      ARRAY['    -- the names follow the roll (case and spacing aside), and a blank, NA or query cell never erases one (V750 b; hrm.roll_read',
            '    -- V761: for someone on record a name is written only where the record has none (else kept and reported); for someone new or
    -- an Add form the names follow the roll (case and spacing aside), and a blank, NA or query cell never erases one (V750 b; hrm.roll_read'],
      ARRAY['    IF p_vals->>''surname'' IS NOT NULL AND hrm.roll_key(v_person->>''surname'') IS DISTINCT FROM hrm.roll_key(p_vals->>''surname'') THEN
        v_changes := v_changes || jsonb_build_object(''field'', ''surname'', ''from'', v_person->>''surname'', ''to'', p_vals->>''surname'');
        v_set_surname := p_vals->>''surname'';
    END IF;',
            '    IF p_vals->>''surname'' IS NOT NULL AND hrm.roll_key(v_person->>''surname'') IS DISTINCT FROM hrm.roll_key(p_vals->>''surname'') THEN
        IF v_fill AND hrm.roll_text(v_person->>''surname'') IS NOT NULL THEN       -- V761: a name on record is kept, the roll''s reported
            v_kept := v_kept || jsonb_build_object(''field'', ''surname'', ''onRecord'', v_person->>''surname'', ''onRoll'', p_vals->>''surname'', ''reason'', ''DIFFERS'');
        ELSE
            v_changes := v_changes || jsonb_build_object(''field'', ''surname'', ''from'', v_person->>''surname'', ''to'', p_vals->>''surname'');
            v_set_surname := p_vals->>''surname'';
        END IF;
    END IF;'],
      ARRAY['    IF v_given IS NOT NULL AND hrm.roll_key(v_person->>''given_names'') IS DISTINCT FROM hrm.roll_key(v_given) THEN
        v_changes := v_changes || jsonb_build_object(''field'', ''given_names'', ''from'', v_person->>''given_names'', ''to'', v_given);
        v_set_given := v_given;
    END IF;',
            '    IF v_given IS NOT NULL AND hrm.roll_key(v_person->>''given_names'') IS DISTINCT FROM hrm.roll_key(v_given) THEN
        IF v_fill AND hrm.roll_text(v_person->>''given_names'') IS NOT NULL THEN
            -- V761: the given names on record kept; the roll''s own cells reported (not a name made from them and the record)
            v_kept := v_kept || jsonb_build_object(''field'', ''given_names'', ''onRecord'', v_person->>''given_names'',
                ''onRoll'', CASE WHEN p_vals ? ''given_names'' THEN p_vals->>''given_names'' ELSE concat_ws('' '', v_first, p_vals->>''middle_name'') END,
                ''reason'', ''DIFFERS'');
        ELSE
            v_changes := v_changes || jsonb_build_object(''field'', ''given_names'', ''from'', v_person->>''given_names'', ''to'', v_given);
            v_set_given := v_given;
        END IF;
    END IF;'],
      ARRAY['    -- the record follows the roll, field by field; a field the row does not give is left as it is',
            '    -- V761: the posting is one detail for someone on record. Placed nowhere (no unit, department or faculty): the roll''s posting
    -- is written. Placed where the roll places them — the most specific place on record (unit, else department, else faculty) is
    -- the roll''s at that level; on the teaching-staff list a faculty alone on record also takes a department of that faculty (the
    -- half posting an upload may have left) — only the parts the record lacks are filled. Placed elsewhere: the whole posting is
    -- kept, reported once by the names of the places
    IF v_fill AND p_vals ?| ARRAY[''home_department'', ''home_faculty'', ''home_unit'', ''unit_as_given''] THEN
        v_ru := hrm.roll_text(v_old->>''home_unit'');
        v_rd := hrm.roll_text(v_old->>''home_department'');
        v_rf := hrm.roll_text(v_old->>''home_faculty'');
        v_nu := hrm.roll_text(p_vals->>''home_unit'');
        v_nd := hrm.roll_text(p_vals->>''home_department'');
        v_nf := hrm.roll_text(p_vals->>''home_faculty'');
        v_posting := CASE
            WHEN coalesce(v_ru, v_rd, v_rf) IS NULL THEN ''WRITE''
            WHEN coalesce(v_nu, v_nd, v_nf) IS NULL THEN ''SAME''
            -- (the teaching-staff list has no unit: there a unit on record beside a department is placed by the department)
            WHEN v_ru IS NOT NULL AND NOT (p_vals->>''category'' = ''ACADEMIC'' AND v_nu IS NULL AND v_rd IS NOT NULL)
                 THEN CASE WHEN v_ru = v_nu THEN ''SAME'' ELSE ''ELSEWHERE'' END
            -- on the teaching-staff list a faculty alone (its department not on the portal) is no other place when it is the
            -- faculty the record''s department is under
            WHEN v_rd IS NOT NULL THEN CASE WHEN v_nu IS NULL AND v_rd = v_nd THEN ''SAME''
                                            WHEN p_vals->>''category'' = ''ACADEMIC'' AND v_nu IS NULL AND v_nd IS NULL
                                                 AND v_nf = coalesce(v_rf, (SELECT d.faculty_code FROM ref.department d WHERE d.code = v_rd)) THEN ''SAME''
                                            ELSE ''ELSEWHERE'' END
            WHEN v_nu IS NULL AND v_nd IS NULL AND v_nf = v_rf THEN ''SAME''
            WHEN p_vals->>''category'' = ''ACADEMIC'' AND v_nu IS NULL AND v_nd IS NOT NULL
                 AND coalesce(v_nf, (SELECT d.faculty_code FROM ref.department d WHERE d.code = v_nd)) = v_rf THEN ''SAME''
            ELSE ''ELSEWHERE'' END;
        IF v_posting = ''ELSEWHERE'' THEN
            v_kept := v_kept || jsonb_build_object(''field'', ''posting'',
                ''onRecord'', coalesce(hrm.roll_shown(''home_unit'', v_ru), hrm.roll_shown(''home_department'', v_rd), hrm.roll_shown(''home_faculty'', v_rf)),
                ''onRoll'', coalesce(hrm.roll_shown(''home_unit'', v_nu), hrm.roll_shown(''home_department'', v_nd), hrm.roll_shown(''home_faculty'', v_nf)),
                ''reason'', ''DIFFERS'');
        END IF;
        -- the faculty the department is under on the register: a faculty the roll states against it is not written
        v_dfac := (SELECT d.faculty_code FROM ref.department d WHERE d.code = coalesce(v_rd, v_nd));
    END IF;

    -- V761: the salary scale and step are one detail too. A record with neither takes the roll''s; one on the roll''s scale has a
    -- missing step filled; any other grade on record is kept, reported once
    IF v_fill AND p_vals ?| ARRAY[''salary_scale'', ''contiss_step'', ''conuass_step''] THEN
        -- a step names its scale where no scale is stated beside it: a CONUASS step (the teaching list''s CONUASS column) is on
        -- the CONUASS scale, a CONTISS step on the CONTISS scale — so a step is compared only within its scale
        v_rs := coalesce(hrm.roll_text(v_old->>''salary_scale''),
                         CASE WHEN hrm.roll_text(v_old->>''conuass_step'') IS NOT NULL THEN ''CONUASS''
                              WHEN hrm.roll_text(v_old->>''contiss_step'') IS NOT NULL THEN ''CONTISS'' END);
        v_rstep := coalesce(hrm.roll_text(v_old->>''contiss_step''), hrm.roll_text(v_old->>''conuass_step''));
        v_ns := coalesce(hrm.roll_text(p_vals->>''salary_scale''),
                         CASE WHEN hrm.roll_text(p_vals->>''conuass_step'') IS NOT NULL THEN ''CONUASS''
                              WHEN hrm.roll_text(p_vals->>''contiss_step'') IS NOT NULL THEN ''CONTISS'' END);
        v_nstep := coalesce(hrm.roll_text(p_vals->>''contiss_step''), hrm.roll_text(p_vals->>''conuass_step''));
        -- the same grade: the scales agree where both state one, the steps agree where both state one, and at least one of them is
        -- stated on both sides (a scale alone on record is not filled with a step of a scale the roll does not name, nor a step
        -- alone with a scale whose step the roll does not give)
        v_grade := CASE
            WHEN v_rs IS NULL AND v_rstep IS NULL THEN ''WRITE''
            WHEN v_ns IS NULL AND v_nstep IS NULL THEN ''SAME''
            WHEN (v_rs IS NULL OR v_ns IS NULL OR hrm.roll_key(v_rs) = hrm.roll_key(v_ns))
                 AND (v_rstep IS NULL OR v_nstep IS NULL OR v_rstep = v_nstep)
                 AND ((v_rs IS NOT NULL AND v_ns IS NOT NULL) OR (v_rstep IS NOT NULL AND v_nstep IS NOT NULL)) THEN ''SAME''
            ELSE ''ELSEWHERE'' END;
        IF v_grade = ''ELSEWHERE'' THEN
            v_kept := v_kept || jsonb_build_object(''field'', ''grade'',
                ''onRecord'', nullif(concat_ws('' '', hrm.roll_text(v_old->>''salary_scale''), ''step '' || v_rstep), ''''),
                ''onRoll'', nullif(concat_ws('' '', hrm.roll_text(p_vals->>''salary_scale''),
                                             CASE WHEN hrm.roll_text(p_vals->>''conuass_step'') IS NOT NULL AND hrm.roll_text(p_vals->>''salary_scale'') IS NULL
                                                  THEN ''CONUASS'' END, ''step '' || v_nstep), ''''), ''reason'', ''DIFFERS'');
        END IF;
    END IF;

    -- the record follows the roll, field by field; a field the row does not give is left as it is (V761: for someone on record,
    -- only where the record has none)'],
      ARRAY['        IF hrm.roll_key(v_old->>k) IS DISTINCT FROM hrm.roll_key(p_vals->>k) THEN
            v_new := jsonb_set(v_new, ARRAY[k], p_vals->k);
            v_changes := v_changes || jsonb_build_object(''field'', k, ''from'', hrm.roll_shown(k, v_old->>k), ''to'', hrm.roll_shown(k, p_vals->>k));
        END IF;',
            '        IF hrm.roll_key(v_old->>k) IS DISTINCT FROM hrm.roll_key(p_vals->>k) THEN
            IF v_fill AND k IN (''home_department'', ''home_faculty'', ''home_unit'', ''unit_as_given'') AND v_posting <> ''WRITE'' THEN
                -- V761: the posting where the record places them: a part it lacks filled (the same place) — a faculty the roll states
                -- against the department''s on the register reported, not written; a unit, department or faculty on record that the
                -- roll states differently reported; else kept, reported above
                IF v_posting = ''SAME'' AND hrm.roll_text(p_vals->>k) IS NOT NULL THEN
                    IF hrm.roll_text(v_old->>k) IS NULL AND k = ''home_faculty'' AND v_dfac IS NOT NULL AND v_dfac <> hrm.roll_text(p_vals->>k) THEN
                        v_kept := v_kept || jsonb_build_object(''field'', k, ''onRecord'', hrm.roll_shown(k, v_dfac), ''onRoll'', hrm.roll_shown(k, p_vals->>k),
                                                               ''reason'', ''NOT_THE_DEPARTMENTS'');
                    ELSIF hrm.roll_text(v_old->>k) IS NULL THEN
                        v_new := jsonb_set(v_new, ARRAY[k], p_vals->k);
                        v_changes := v_changes || jsonb_build_object(''field'', k, ''from'', hrm.roll_shown(k, v_old->>k), ''to'', hrm.roll_shown(k, p_vals->>k));
                    ELSIF k <> ''unit_as_given'' THEN
                        v_kept := v_kept || jsonb_build_object(''field'', k, ''onRecord'', hrm.roll_shown(k, v_old->>k), ''onRoll'', hrm.roll_shown(k, p_vals->>k), ''reason'', ''DIFFERS'');
                    END IF;
                END IF;
            ELSIF v_fill AND k IN (''salary_scale'', ''contiss_step'', ''conuass_step'') AND v_grade <> ''WRITE'' THEN
                -- V761: the grade: a part the record lacks filled on the same scale; else kept, reported above
                IF v_grade = ''SAME'' AND hrm.roll_text(v_old->>k) IS NULL AND hrm.roll_text(p_vals->>k) IS NOT NULL THEN
                    v_new := jsonb_set(v_new, ARRAY[k], p_vals->k);
                    v_changes := v_changes || jsonb_build_object(''field'', k, ''from'', hrm.roll_shown(k, v_old->>k), ''to'', hrm.roll_shown(k, p_vals->>k));
                END IF;
            ELSIF v_fill AND (hrm.roll_text(v_old->>k) IS NOT NULL
                              -- a date and the note kept in its place are one detail: either on record keeps both
                              OR (k IN (''date_of_confirmation'', ''confirmation_note'')
                                  AND coalesce(hrm.roll_text(v_old->>''date_of_confirmation''), hrm.roll_text(v_old->>''confirmation_note'')) IS NOT NULL)
                              OR (k IN (''date_of_last_promotion'', ''promotion_note'')
                                  AND coalesce(hrm.roll_text(v_old->>''date_of_last_promotion''), hrm.roll_text(v_old->>''promotion_note'')) IS NOT NULL)) THEN
                -- V761: on record already: kept, and reported for HR (a value the roll leaves out, or NA, is no difference); a date
                -- kept for the note in its place (or the note for the date) shows what the record holds
                IF hrm.roll_text(p_vals->>k) IS NOT NULL THEN
                    v_kept := v_kept || jsonb_build_object(''field'', k,
                        ''onRecord'', coalesce(hrm.roll_text(v_old->>k), v_old->>(CASE k WHEN ''date_of_confirmation'' THEN ''confirmation_note''
                                                                                        WHEN ''confirmation_note'' THEN ''date_of_confirmation''
                                                                                        WHEN ''date_of_last_promotion'' THEN ''promotion_note''
                                                                                        WHEN ''promotion_note'' THEN ''date_of_last_promotion'' END)),
                        ''onRoll'', hrm.roll_shown(k, p_vals->>k), ''reason'', ''DIFFERS'');
                END IF;
            ELSE
                v_new := jsonb_set(v_new, ARRAY[k], p_vals->k);
                v_changes := v_changes || jsonb_build_object(''field'', k, ''from'', hrm.roll_shown(k, v_old->>k), ''to'', hrm.roll_shown(k, p_vals->>k));
            END IF;
        END IF;']];
BEGIN
    d := pg_get_functiondef('hrm.roll_apply(uuid,text,jsonb,jsonb)'::regprocedure);
    FOR i IN 1 .. array_length(edits, 1) LOOP
        n := (length(d) - length(replace(d, edits[i][1], ''))) / length(edits[i][1]);
        IF n <> 1 THEN RAISE EXCEPTION 'V761: hrm.roll_apply is not as V750 left it (% found % times)', left(edits[i][1], 60), n; END IF;
        d := replace(d, edits[i][1], edits[i][2]);
    END LOOP;
    EXECUTE d;
END $$;
COMMENT ON FUNCTION hrm.roll_apply(uuid, text, jsonb, jsonb) IS
    'V750, V761: one row of a staff list written: a new member of staff takes every detail the list gives; someone on record (by staff number) has a detail written only where the record has none (NA on record is none), a different value kept and reported (DIFFERS); the posting one detail (written where the record has none, its missing parts filled where the record places them in the same place — on the teaching-staff list a faculty alone also taking a department of that faculty — else kept and reported once as posting; a faculty stated against the department''s reported as NOT_THE_DEPARTMENTS); the salary scale and step one detail (reported once as grade); a date and the note in its place one detail; an Add form writes what it gives; a blank, NA or query cell never erases anything; the e-mail and phone filled only where missing.';

-- ── iam.import_lecturers: an upload never moves a lecturer office ─────────────────────────────────────────────────────────────
DO $$
DECLARE d text; n int; i int;
    edits text[][] := ARRAY[
      ARRAY['                        -- a home department the roll changes takes the lecturer office with it, as the Edit form moves it',
            '                        -- V761: an upload moves no office (it reports OFFICE_KEPT, below); on an Add form a home department the form
                        -- changes takes the lecturer office with it, as the Edit form moves it'],
      ARRAY['                            IF v_office_from IS NOT NULL THEN
                                UPDATE iam.office_assignment SET valid_to = current_date',
            '                            IF v_office_from IS NOT NULL AND NOT coalesce((v_vals->>''add_form'')::boolean, false) THEN
                                -- V761: an upload touches no office: a department it fills beside a lecturer office open in another
                                -- department leaves the office where it is, reported for HR (the Edit form moves it)
                                v_out := jsonb_set(v_out, ''{kept}'', (v_out->''kept'') || jsonb_build_array(jsonb_build_object(
                                             ''field'', ''lecturer_office'', ''onRecord'', v_office_from,
                                             ''onRoll'', hrm.roll_shown(''home_department'', v_dept), ''reason'', ''OFFICE_KEPT'')));
                            ELSIF v_office_from IS NOT NULL THEN
                                UPDATE iam.office_assignment SET valid_to = current_date']];
BEGIN
    d := pg_get_functiondef('iam.import_lecturers(jsonb,boolean,jsonb)'::regprocedure);
    FOR i IN 1 .. array_length(edits, 1) LOOP
        n := (length(d) - length(replace(d, edits[i][1], ''))) / length(edits[i][1]);
        IF n <> 1 THEN RAISE EXCEPTION 'V761: iam.import_lecturers is not as V750 left it (% found % times)', left(edits[i][1], 60), n; END IF;
        d := replace(d, edits[i][1], edits[i][2]);
    END LOOP;
    EXECUTE d;
END $$;

-- ── the two uploads' descriptions say the rule now in force ──────────────────────────────────────────────────────────────────
DO $$
DECLARE c text; a text; b text;
BEGIN
    c := obj_description('iam.import_lecturers(jsonb,boolean,jsonb)'::regprocedure, 'pg_proc');
    a := $q$Someone on record: what the roll gives follows the roll, the e-mail and phone only filled, a blank, NA or query name cell erasing no name, the department left when it does not resolve; never a sign-in, and no office but this one: a home department the roll changes moves the lecturer office still open in another department to the new one, as the Edit form does (iam.update_lecturer) — listed as the change {field lecturer_office, from, to} (the departments' names).$q$;
    b := $q$Someone on record (V761): only what the record lacks is filled — a different value kept and reported under kept (DIFFERS; the posting once as posting, the salary scale and step once as grade) — the e-mail and phone only filled, a blank, NA or query name cell erasing no name, the department left when it does not resolve; never a sign-in, and no office moved: a department the upload fills beside a lecturer office open in another department leaves the office there, reported under kept as {field lecturer_office, reason OFFICE_KEPT}; the Add form (the given names whole) still moves it, as the Edit form does (iam.update_lecturer), listed as the change {field lecturer_office, from, to} (the departments' names).$q$;
    IF c IS NULL OR position(a IN c) = 0 THEN RAISE EXCEPTION 'V761: the description of iam.import_lecturers is not as V750 left it'; END IF;
    EXECUTE format('COMMENT ON FUNCTION iam.import_lecturers(jsonb, boolean, jsonb) IS %L', replace(c, a, b));

    c := obj_description('iam.import_staff(jsonb,boolean,jsonb)'::regprocedure, 'pg_proc');
    a := $q$Someone on record: what the roll gives follows the roll, the e-mail and phone only filled, a blank, NA or query name cell erasing no name, the posting left when it does not resolve;$q$;
    b := $q$Someone on record (V761): only what the record lacks is filled — a different value kept and reported under kept (DIFFERS; the posting once as posting, the salary scale and step once as grade) — the e-mail and phone only filled, a blank, NA or query name cell erasing no name, the posting left when it does not resolve; their sign-in, password and offices never touched;$q$;
    IF c IS NULL OR position(a IN c) = 0 THEN RAISE EXCEPTION 'V761: the description of iam.import_staff is not as V750 left it'; END IF;
    EXECUTE format('COMMENT ON FUNCTION iam.import_staff(jsonb, boolean, jsonb) IS %L', replace(c, a, b));
END $$;

COMMIT;
