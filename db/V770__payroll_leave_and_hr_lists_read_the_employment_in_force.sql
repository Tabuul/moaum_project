-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V770 · Payroll, leave and HR's staff lists read the employment in force
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The user's word of 15 November 2026 ("align payroll and leave too"), after V768: an exit instrument ends an employment with its
--  effective date at once (V072), and V768 counts that employment in force until the date comes (hrm.employment_in_force). Payroll,
--  leave and HR's lists still dropped the member of staff the day the exit was entered. Now:
--    · a pay run for a month pays every employment in force on at least one day of it — ACTIVE, or ENDED from a date after the month's
--      first day — the exit's month whole, as an appointment's first month is paid whole (the user's choice: "pay the whole month");
--      nobody is paid for a month before their appointment; a suspended employment is not paid, as before — nor one an exit was
--      entered against while suspended (the exit overwrites the status; the last of its SUSPENSION and REINSTATEMENT movements
--      still says suspended); one person is paid once a month, from their ACTIVE employment where there is one;
--    · leave is requested and approved only for a member of staff whose employment is in force and not suspended, and never past the
--      last day of service (the day before the exit's effective date);
--    · the staff with no employment record (hrm.staff_without_employment, for HR to appoint) read the employment in force; the
--      promotion and appraisal list (hrm.promotion_view, one row a person) the employment serving today (in force and not
--      suspended); hrm.staff_status (V768) shows a member of staff still in service but not serving — suspended, or suspended
--      before an exit was entered — as SUSPENDED.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V770: payroll, leave and HR''s staff lists read the employment in force', true);

-- whether an employment's exit was entered while it was suspended: an exit overwrites the status SUSPENDED (V072), and the last of
-- the employment's implemented SUSPENSION and REINSTATEMENT movements still says so; read only for an exit still to take effect
CREATE FUNCTION hrm.employment_suspended_at_exit(p_employment uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT m.kind = 'SUSPENSION' FROM hrm.movement m
                      WHERE m.employment_id = p_employment AND m.state = 'IMPLEMENTED' AND m.kind IN ('SUSPENSION', 'REINSTATEMENT')
                      ORDER BY m.implemented_at DESC NULLS LAST LIMIT 1), false)
$$;
COMMENT ON FUNCTION hrm.employment_suspended_at_exit(uuid) IS
  'V770: whether the last of an employment''s implemented SUSPENSION and REINSTATEMENT movements is a SUSPENSION — an exit entered while it was suspended overwrites the status SUSPENDED (V072). hrm.employment_serving_on reads it for an exit still to take effect.';
CREATE INDEX IF NOT EXISTS ix_mv_employment_suspension ON hrm.movement (employment_id, implemented_at DESC NULLS LAST)
    WHERE state = 'IMPLEMENTED' AND kind IN ('SUSPENSION', 'REINSTATEMENT');

-- an employment serving and not suspended on a day: ACTIVE, or ENDED from a later date — the day an exit takes effect is the first
-- day out of service — and not suspended when its exit was entered. One plain expression, so the planner inlines it into the
-- reads (an ACTIVE row costs no function call; the movement lookup runs only for an exit still to take effect)
CREATE FUNCTION hrm.employment_serving_on(p_emp hrm.employment, p_day date)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT p_emp.status = 'ACTIVE'
        OR (p_emp.status = 'ENDED' AND p_emp.ended_on > p_day AND NOT hrm.employment_suspended_at_exit(p_emp.id))
$$;
COMMENT ON FUNCTION hrm.employment_serving_on(hrm.employment, date) IS
  'V770: whether an employment is serving (not suspended) on a day — ACTIVE, or ENDED by an exit whose effective date (the first day out of service) is later and not entered while it was suspended (hrm.employment_suspended_at_exit). A pay run reads it from the first day of its month; leave and the HR lists from Lagos today. Kept a plain expression so it inlines.';

-- a member of staff's status (V768): ENDED once out of service; SUSPENDED while in service but no employment serves (suspended, or
-- suspended before an exit was entered); else ACTIVE
CREATE OR REPLACE FUNCTION hrm.staff_status(p_person uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN NOT credentials.staff_in_service(p_person) THEN 'ENDED'
                WHEN EXISTS (SELECT 1 FROM hrm.employment e WHERE e.person_id = p_person)
                     AND NOT EXISTS (SELECT 1 FROM hrm.employment e WHERE e.person_id = p_person
                                        AND hrm.employment_serving_on(e, (now() AT TIME ZONE 'Africa/Lagos')::date)) THEN 'SUSPENDED'
                ELSE 'ACTIVE' END
$$;
COMMENT ON FUNCTION hrm.staff_status(uuid) IS
  'V768, V770: a member of staff''s status as the HR record and the staff register show it — ENDED once out of service (credentials.staff_in_service), SUSPENDED while in service with no employment serving (hrm.employment_serving_on: suspended, or suspended before an exit was entered), else ACTIVE.';

DO $$
DECLARE d text; i int; n int; f text;
    targets text[] := ARRAY['hrm.build_pay_run(date,text)', 'hrm.request_leave(uuid,text,date,date,text,text)', 'hrm.decide_leave(uuid,boolean,text)',
                            'hrm.staff_without_employment()', 'hrm.promotion_view(text)'];
    edits text[][];
BEGIN
    FOREACH f IN ARRAY targets LOOP
        edits := CASE f
            -- the pay run: every employment serving on a day of the month, one a person (their ACTIVE one first)
            WHEN 'hrm.build_pay_run(date,text)' THEN ARRAY[
                ARRAY['    FOR e IN
        SELECT em.id AS emp_id, em.person_id, em.staff_no, em.grade, em.step, em.category,
               em.bank_name, em.account_last4, gr.basic, gr.housing, gr.transport, gr.other_allowances,
               p.surname || '', '' || p.given_names AS name
          FROM hrm.employment em
          JOIN hrm.grade gr ON gr.grade = em.grade AND gr.step = em.step
          JOIN iam.person p ON p.id = em.person_id
         WHERE em.status = ''ACTIVE''
         ORDER BY em.staff_no
    LOOP',
                      '    -- V770: every employment serving on at least one day of the month (ACTIVE, or ended by an exit taking effect after its first
    -- day — the exit''s month paid whole), one a person, their ACTIVE employment first
    FOR e IN
        SELECT * FROM (
            SELECT DISTINCT ON (em.person_id) em.id AS emp_id, em.person_id, em.staff_no, em.grade, em.step, em.category,
                   em.bank_name, em.account_last4, gr.basic, gr.housing, gr.transport, gr.other_allowances,
                   p.surname || '', '' || p.given_names AS name
              FROM hrm.employment em
              JOIN hrm.grade gr ON gr.grade = em.grade AND gr.step = em.step
              JOIN iam.person p ON p.id = em.person_id
             WHERE hrm.employment_serving_on(em, v_period)
               AND em.appointment_date < (v_period + interval ''1 month'')::date   -- nobody paid for a month before their appointment
             ORDER BY em.person_id, (em.status = ''ACTIVE'') DESC, em.appointment_date DESC NULLS LAST) x
         ORDER BY x.staff_no
    LOOP']]
            -- leave: requested while serving, ending before the last day of service is past
            WHEN 'hrm.request_leave(uuid,text,date,date,text,text)' THEN ARRAY[
                ARRAY['v_emp uuid; v_days int;', 'v_emp uuid; v_end date; v_days int;'],
                ARRAY['    SELECT id INTO v_emp FROM hrm.employment WHERE person_id = p_person AND status = ''ACTIVE'';',
                      '    -- V770: the employment serving today (an exit not yet in effect still serves), its exit date if one is set
    SELECT e.id, e.ended_on INTO v_emp, v_end FROM hrm.employment e
     WHERE e.person_id = p_person AND hrm.employment_serving_on(e, (now() AT TIME ZONE ''Africa/Lagos'')::date)
     ORDER BY (e.status = ''ACTIVE'') DESC, e.appointment_date DESC NULLS LAST LIMIT 1;'],
                ARRAY['    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN RAISE EXCEPTION ''a leave period runs from a day to a later day'' USING ERRCODE = ''23514''; END IF;',
                      '    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN RAISE EXCEPTION ''a leave period runs from a day to a later day'' USING ERRCODE = ''23514''; END IF;
    IF v_end IS NOT NULL AND p_to >= v_end THEN
        RAISE EXCEPTION ''the leave runs past the last day of service (%): an exit takes effect on %'', to_char(v_end - 1, ''DD Mon YYYY''), to_char(v_end, ''DD Mon YYYY'')
            USING ERRCODE = ''23514'';
    END IF;']]
            -- leave approved only for a member of staff still serving, and not past the last day of service
            WHEN 'hrm.decide_leave(uuid,boolean,text)' THEN ARRAY[
                ARRAY['    IF NOT p_approve AND (p_note IS NULL OR btrim(p_note) = '''') THEN RAISE EXCEPTION ''a declined request says why'' USING ERRCODE = ''23514''; END IF;',
                      '    IF NOT p_approve AND (p_note IS NULL OR btrim(p_note) = '''') THEN RAISE EXCEPTION ''a declined request says why'' USING ERRCODE = ''23514''; END IF;
    -- V770: approved only while the employment serves, and not past the last day of service (an exit entered after the request)
    IF p_approve AND NOT EXISTS (SELECT 1 FROM hrm.employment e WHERE e.id = r.employment_id
                                    AND hrm.employment_serving_on(e, (now() AT TIME ZONE ''Africa/Lagos'')::date)) THEN
        RAISE EXCEPTION ''only a serving member of staff''''s leave is approved: decline it with the reason'' USING ERRCODE = ''23514'';
    END IF;
    IF p_approve AND EXISTS (SELECT 1 FROM hrm.employment e WHERE e.id = r.employment_id AND e.ended_on IS NOT NULL AND r.to_date >= e.ended_on) THEN
        RAISE EXCEPTION ''the leave runs past the last day of service: an exit takes effect on %'',
            (SELECT to_char(e.ended_on, ''DD Mon YYYY'') FROM hrm.employment e WHERE e.id = r.employment_id) USING ERRCODE = ''23514'';
    END IF;']]
            WHEN 'hrm.staff_without_employment()' THEN ARRAY[
                ARRAY['AND e.status <> ''ENDED'')', 'AND hrm.employment_in_force(e.status, e.ended_on))   /* V770 */']]
            ELSE ARRAY[
                ARRAY['     WHERE em.status = ''ACTIVE''',
                      '     WHERE hrm.employment_serving_on(em, (now() AT TIME ZONE ''Africa/Lagos'')::date)   -- V770: serving today, one row a person
       AND NOT EXISTS (SELECT 1 FROM hrm.employment o WHERE o.person_id = em.person_id AND o.id <> em.id
                          AND hrm.employment_serving_on(o, (now() AT TIME ZONE ''Africa/Lagos'')::date)
                          AND ((o.status = ''ACTIVE'' AND em.status <> ''ACTIVE'')
                               OR ((o.status = ''ACTIVE'') = (em.status = ''ACTIVE'') AND (o.appointment_date, o.id) > (em.appointment_date, em.id))))']] END;
        d := pg_get_functiondef(f::regprocedure);
        FOR i IN 1 .. array_length(edits, 1) LOOP
            n := (length(d) - length(replace(d, edits[i][1], ''))) / length(edits[i][1]);
            IF n <> 1 THEN RAISE EXCEPTION 'V770: % is not as it was left (% found % times)', f, left(edits[i][1], 50), n; END IF;
            d := replace(d, edits[i][1], edits[i][2]);
        END LOOP;
        EXECUTE d;
    END LOOP;
END $$;

COMMIT;
