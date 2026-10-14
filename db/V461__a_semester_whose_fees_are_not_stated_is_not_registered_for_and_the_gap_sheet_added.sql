-- ═══════════════════════════════════════
-- V461 — A semester whose fees are not stated is not registered for; the Bursary's filled-in gap sheet added as lines
--
--   1 · Course registration (registration.student_submit, restated from V392, the one change marked V461). V361 refused a
--       submission while no school fee of the session was stated for the student. A student whose first-semester line was
--       stated but whose second-semester line was not passed that test, and the second semester then read as cleared — what
--       was owed up to it was only the first semester's, already paid — so the student registered for a semester whose fees
--       nobody had stated. The submission is now refused for a semester that is open with no line of its own (or of the whole
--       session) reaching the student while another semester's does (finance.fee_unstated_semesters, V451):
--       REG_SEMESTER_FEES_NOT_STATED, until the Bursary states it; and finance.semester_cleared (restated from V454) never
--       reads such a semester as cleared, so the College's registration, ICT Support's added course, the entitlements and the
--       fees page hold it too.
--   2 · finance.add_fee_lines(session, rows): the sheet the Fee Schedule screen gives for the students with no fee stated (one
--       row per programme — or, for a faculty charged as another (V451), per faculty it follows — level, entry mode,
--       indigeneship and semester, the amount left for the Bursary to fill) comes back
--       as new lines of the session's schedule — added, never replacing the structure as the fees-structure upload does; a
--       row with no amount is left out, one the schedule already holds is not added twice, and a line is never added to a
--       faculty charged as another while its rule is in force — a line of its own would end the rule for all its students.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V461: a semester whose fees are not stated is not registered for; the gap sheet added as lines', true);

-- ── 1 · course registration (restated from V392) ────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.student_submit(p_registration uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; lim policy.level_limit; units int; st record; v_gate text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status NOT IN ('DRAFT', 'RETURNED') THEN RETURN 'already ' || lower(r.status); END IF;
    -- V361: the school fees the student owes for the session must be stated before they can be paid, or cleared
    IF NOT finance.fee_stated(r.student_id, r.session) THEN
        SELECT p.name AS programme, s.current_level AS level INTO st
          FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = r.student_id;
        RAISE EXCEPTION 'REG_FEES_NOT_STATED: the school fees of % at % level for % are not stated yet, so they cannot be paid or cleared',
            coalesce(st.programme, 'the programme'), st.level, r.session
            USING ERRCODE = '23514',
            HINT = 'Course registration opens when the Bursary states the session''s school fees on Fee Setup and they are paid.';
    END IF;
    -- V461: and the semester's own: while no school-fee line of this semester (or of the whole session) reaches the
    -- student, though another semester's does, the semester reads as paid when it is not stated — refused until it is
    IF r.semester = ANY (finance.fee_unstated_semesters(r.student_id, r.session)) THEN
        SELECT p.name AS programme, s.current_level AS level INTO st
          FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = r.student_id;
        RAISE EXCEPTION 'REG_SEMESTER_FEES_NOT_STATED: the % semester school fees of % at % level for % are not stated yet, so they cannot be paid or cleared',
            CASE r.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' WHEN 3 THEN 'third' ELSE r.semester::text END,
            coalesce(st.programme, 'the programme'), st.level, r.session
            USING ERRCODE = '23514',
            HINT = 'Course registration for the semester opens when the Bursary states its school fees on Fee Setup and they are paid.';
    END IF;
    IF NOT finance.semester_cleared(r.student_id, r.session, r.semester) THEN
        RAISE EXCEPTION 'the % semester school fees for % are not fully paid',
            CASE r.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' WHEN 3 THEN 'third' ELSE r.semester::text END, r.session
            USING ERRCODE = '23514',
            HINT = 'Course registration for a semester opens when that semester''s school fees are cleared in full.';
    END IF;
    -- V314: where the University holds the whole registration on the GST fee, an unpaid student does not submit
    v_gate := registration.gst_gate(r.student_id, r.session, NULL);
    IF v_gate IS NOT NULL THEN
        RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; submission opens the moment the payment is confirmed.';
    END IF;
    -- and a GST/EPS course already on the draft is not submitted unpaid either
    SELECT registration.gst_gate(r.student_id, r.session, o.course_code) INTO v_gate
      FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST'
     WHERE e.registration_id = p_registration AND e.status <> 'DROPPED' AND registration.gst_gate(r.student_id, r.session, o.course_code) IS NOT NULL
     LIMIT 1;
    IF v_gate IS NOT NULL THEN
        RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS, or remove the GST/EPS courses from the registration.';
    END IF;
    units := registration.units_of(p_registration);
    SELECT * INTO lim FROM registration.unit_limit(r.student_id, r.level);   -- V380: the CCE course load for a CCE student
    IF FOUND AND (units < lim.min_units OR units > lim.max_units) THEN
        RAISE EXCEPTION 'the registration carries % units; at % level the range is % to %', units, r.level, lim.min_units, lim.max_units
        USING ERRCODE = '23514', HINT = 'Add or drop courses to bring it within the range, or obtain an overload approval from the Head of Department.';
    END IF;
    SELECT * INTO st FROM assessment.student_standing(r.student_id);
    IF FOUND AND st.standing IN ('PROBATION', 'ADVISED_TO_WITHDRAW') AND lim.probation_max_units IS NOT NULL AND units > lim.probation_max_units THEN
        RAISE EXCEPTION 'you are on probation (CGPA % after % % semester); the registration carries % units and the limit on probation at % level is %',
            st.cgpa, st.pronounced_session, CASE st.pronounced_semester WHEN 1 THEN 'first' ELSE 'second' END, units, r.level, lim.probation_max_units
        USING ERRCODE = '23514', HINT = 'Drop courses to bring the registration within the probation limit. The carryovers stay; choose fewer new courses.';
    END IF;
    UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE id = p_registration;
    RETURN 'submitted';
END $function$
;

-- ── 1 · and the semester gate every other path reads (restated from V454, the one change marked V461) ──────────────────
CREATE OR REPLACE FUNCTION finance.semester_cleared(p_student uuid, p_session text, p_semester integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    -- V454: short of the semester's cumulative due by under one naira is cleared
    -- V461: and never a semester whose own fees are not stated for the student while another semester's are; every
    -- gate that reads this (course registration, the College's, ICT Support's, entitlements, the fees page) holds it.
    -- Asked in this order so the semester's own lines are read only for an open semester the student has paid up to
    SELECT CASE WHEN NOT finance.fee_stated(p_student, p_session) THEN false
                WHEN finance.fee_short(finance.due_for_semester(p_student, p_session, p_semester),
                                 coalesce((SELECT sum(r.amount) FROM finance.payment_reference r
                                            WHERE r.student_id = p_student AND r.session = p_session
                                              AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'), 0)) THEN false
                WHEN EXISTS (SELECT 1 FROM policy.semester sm WHERE sm.session = p_session AND sm.number = p_semester AND sm.state = 'OPEN')
                     AND p_semester = ANY (finance.fee_unstated_semesters(p_student, p_session)) THEN false
                ELSE true END;
$function$;

-- ── 2 · the filled-in gap sheet, added ──────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.add_fee_lines(p_session text, p_rows jsonb)
RETURNS TABLE (rows integer, added integer, no_amount integer, already integer, no_programme integer, charged_as integer, skipped integer, first_error text)
LANGUAGE plpgsql AS $fn$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_prog text; v_fac text; v_level int; v_mode text; v_sem int; v_ind text; v_spill boolean; v_amt numeric; v_item text;
        n int := 0; na int := 0; nb int := 0; nal int := 0; nnp int := 0; nca int := 0; ns int := 0; v_err text;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'FEE_LINES_PERSON: fee lines are added by a person' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN
        RAISE EXCEPTION 'FEE_LINES_SESSION: % is not on the calendar', p_session USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'FEE_LINES_ROWS: the sheet is rows: programme, level, entry mode, semester, indigeneship and the amount' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        n := n + 1;
        BEGIN
            v_amt := nullif(regexp_replace(coalesce(r->>'amount', ''), '[^0-9.]', '', 'g'), '')::numeric;
            IF v_amt IS NULL THEN nb := nb + 1; CONTINUE; END IF;
            -- a programme's line, or — with no programme — a faculty's line (the sheet asks for the faculty a
            -- "charged as" faculty follows, V451, so its own students and the faculty's are stated together)
            v_prog := nullif(upper(btrim(coalesce(r->>'programmeCode', r->>'programme_code', r->>'programme', ''))), '');
            v_fac := nullif(upper(btrim(coalesce(r->>'facultyCode', r->>'faculty_code', ''))), '');
            IF v_prog IS NOT NULL THEN
                SELECT p.code, p.faculty_code INTO v_prog, v_fac FROM ref.programme p WHERE upper(p.code) = v_prog;
                IF v_prog IS NULL THEN nnp := nnp + 1; CONTINUE; END IF;
                -- a line of its own would end the rule for every student of a faculty charged as another: refused here
                IF finance.fee_source_of(v_fac, p_session) IS NOT NULL THEN nca := nca + 1; CONTINUE; END IF;
            ELSE
                SELECT f.code INTO v_fac FROM ref.faculty f WHERE upper(f.code) = v_fac;
                IF v_fac IS NULL THEN nnp := nnp + 1; CONTINUE; END IF;
                IF finance.fee_source_of(v_fac, p_session) IS NOT NULL THEN nca := nca + 1; CONTINUE; END IF;
            END IF;
            v_spill := lower(btrim(coalesce(r->>'spillover', ''))) IN ('true', 't', '1', 'yes', 'y', 'spillover');
            v_level := CASE WHEN v_spill THEN NULL
                            ELSE nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int END;
            IF v_level IS NOT NULL AND v_level NOT IN (100, 200, 300, 400, 500, 600, 700, 800, 900) THEN v_level := NULL; END IF;
            v_mode := nullif(upper(replace(btrim(coalesce(r->>'entryMode', r->>'entry_mode', '')), ' ', '_')), '');
            IF v_mode IS NOT NULL AND v_mode NOT IN ('UTME', 'DIRECT_ENTRY', 'TRANSFER', 'POSTGRADUATE', 'JUPEB', 'SANDWICH') THEN v_mode := NULL; END IF;
            v_sem := nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int;
            IF v_sem IS NOT NULL AND v_sem NOT IN (1, 2, 3) THEN v_sem := NULL; END IF;
            v_ind := upper(btrim(coalesce(r->>'indigene', '')));
            v_ind := CASE WHEN v_ind LIKE 'NON%' OR v_ind LIKE 'NN%' THEN 'NON_INDIGENE' WHEN v_ind LIKE 'IND%' THEN 'INDIGENE' ELSE NULL END;
            -- a line the schedule already holds is not added twice
            IF EXISTS (SELECT 1 FROM finance.fee_schedule f
                        WHERE f.session = p_session AND f.ended_at IS NULL AND f.kind = 'FEE'
                          AND f.programme_code IS NOT DISTINCT FROM v_prog AND f.faculty_code IS NOT DISTINCT FROM v_fac
                          AND f.level IS NOT DISTINCT FROM v_level AND f.entry_mode IS NOT DISTINCT FROM v_mode
                          AND f.semester IS NOT DISTINCT FROM v_sem AND f.indigene IS NOT DISTINCT FROM v_ind AND f.spillover = v_spill) THEN
                nal := nal + 1; CONTINUE;
            END IF;
            v_item := CASE WHEN v_spill THEN 'School fees (spillover)' ELSE 'School fees' END
                      || CASE WHEN v_sem IS NULL THEN '' ELSE ' (semester ' || v_sem || ')' END;
            INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, semester, indigene, ord, spillover, kind)
            VALUES (p_session, v_item, v_amt, v_level, v_mode, v_fac, v_prog, v_sem, v_ind,
                    coalesce(v_sem, 1) + CASE WHEN v_spill THEN 100 ELSE 0 END, v_spill, 'FEE');
            na := na + 1;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_err IS NULL THEN v_err := left('row ' || n || ': ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, na, nb, nal, nnp, nca, ns, v_err;
END $fn$;
COMMENT ON FUNCTION finance.add_fee_lines(text, jsonb) IS
  'V461: the Bursary''s filled-in gap sheet as new FEE lines of a session — a programme''s line (or, with no programme, a '
  'faculty''s) by level, entry mode, semester, indigeneship and spillover — added beside the structure (never ending a line); a '
  'row with no amount is left out, one the schedule already holds is not added twice, and none is added to a faculty charged '
  'as another while its rule is in force (the sheet names the faculty it follows instead).';

COMMIT;
