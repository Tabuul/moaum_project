-- ═══════════════════════════════════════
-- V510 — A new appointment in HR: the employment record made from a form or an Excel upload (checked first), and the salary grades
--
--   hrm.employment is read by payroll, identity cards, the Head of Department's screen and the staff registers, but rows arrived
--   only by the demonstration seed (PRD FR-HR-04); on the live-shaped copy there are none, and no salary grade either. Now, by the
--   Director of Human Resource Management (hrm; super as break-glass):
--   · hrm.set_grade — a salary grade and step (ACADEMIC or NON_ACADEMIC; basic and allowances, monthly), set with a reason; the
--     Bursary may set them too. A grade in use keeps its category.
--   · hrm.appointment_check(row) — what an appointment would do and why not: the staff number (2–30 letters, digits, / . _ -), the
--     person it names (an existing person by staff number is linked, else one is made from the surname and given names), never a
--     person already in employment or a staff number already on an employment record, the category, a grade and step set up in
--     that category, the date of appointment (from 1960, up to a year ahead; Excel day numbers and DD/MM/YYYY read), the
--     department (required for an academic appointment) or unit, sex, e-mail, phone, and the bank and pension details (only the last
--     four digits of an account number are kept). Nothing is written.
--   · hrm.appoint(row) — the appointment made: the person (made or linked; an e-mail or phone filled where the record has none), the
--     establishment record (department or unit, rank, sex, category, salary scale, first appointment), and the employment record
--     (ACTIVE). hrm.appointments_check(rows) checks an upload row by row (a staff number repeated in the file refused);
--     hrm.appoint_many(rows) makes the appointments whose rows pass and lists the rest with their reasons.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'hrm', true),
       set_config('moaum.reason', 'V510: HR new appointment by form or upload, and the salary grades', true);

-- ── the salary grades ──
CREATE FUNCTION hrm.set_grade(p_grade text, p_step integer, p_category text, p_basic numeric, p_housing numeric, p_transport numeric,
                              p_other numeric, p_reason text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_grade text := upper(regexp_replace(btrim(coalesce(p_grade, '')), '\s+', ' ', 'g'));
        v_cat text := upper(replace(replace(btrim(coalesce(p_category, '')), '-', '_'), ' ', '_')); v_used text;
BEGIN
    IF coalesce(v_office, '') NOT IN ('hrm', 'bursar', 'super') THEN
        RAISE EXCEPTION 'HR_GRADE_OFFICE: salary grades are set by Human Resources or the Bursary' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'HR_GRADE_REASON: say why, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    IF v_grade !~ '^[A-Z0-9][A-Z0-9 ./-]{0,29}$' THEN
        RAISE EXCEPTION 'HR_GRADE_NAME: a grade is named in up to 30 letters and digits, e.g. CONUASS 3 or CONTISS 7' USING ERRCODE = '23514';
    END IF;
    IF p_step IS NULL OR p_step NOT BETWEEN 1 AND 30 THEN
        RAISE EXCEPTION 'HR_GRADE_STEP: a step is 1 to 30' USING ERRCODE = '23514';
    END IF;
    IF v_cat NOT IN ('ACADEMIC', 'NON_ACADEMIC') THEN
        RAISE EXCEPTION 'HR_GRADE_CATEGORY: a grade is ACADEMIC or NON_ACADEMIC' USING ERRCODE = '23514';
    END IF;
    IF coalesce(p_basic, -1) < 0 OR coalesce(p_housing, 0) < 0 OR coalesce(p_transport, 0) < 0 OR coalesce(p_other, 0) < 0 THEN
        RAISE EXCEPTION 'HR_GRADE_AMOUNT: the basic salary and allowances are amounts of 0 or more' USING ERRCODE = '23514';
    END IF;
    SELECT e.category INTO v_used FROM hrm.employment e WHERE upper(e.grade) = v_grade AND e.category <> v_cat LIMIT 1;
    IF v_used IS NOT NULL THEN
        RAISE EXCEPTION 'HR_GRADE_IN_USE: % is held by % staff; it stays %', v_grade, lower(replace(v_used, '_', '-')), v_used USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', btrim(p_reason), true);
    INSERT INTO hrm.grade (grade, step, category, basic, housing, transport, other_allowances)
    VALUES (v_grade, p_step, v_cat, p_basic, coalesce(p_housing, 0), coalesce(p_transport, 0), coalesce(p_other, 0))
    ON CONFLICT (grade, step) DO UPDATE SET category = EXCLUDED.category, basic = EXCLUDED.basic, housing = EXCLUDED.housing,
        transport = EXCLUDED.transport, other_allowances = EXCLUDED.other_allowances;
    RETURN v_grade || ' step ' || p_step;
END $$;
COMMENT ON FUNCTION hrm.set_grade(text, integer, text, numeric, numeric, numeric, numeric, text) IS
  'V510: a salary grade and step set by Human Resources or the Bursary with a reason (monthly basic and allowances); a grade held by staff of the other category keeps its category';

-- ── a day as an upload or a form gives it: YYYY-MM-DD, DD/MM/YYYY, or an Excel day number ──
CREATE FUNCTION hrm.read_day(p text)
RETURNS date LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v text := btrim(coalesce(p, ''));
BEGIN
    IF v ~ '^\d{4}-\d{1,2}-\d{1,2}$' THEN RETURN to_date(v, 'YYYY-MM-DD'); END IF;
    IF v ~ '^\d{1,2}[/.-]\d{1,2}[/.-]\d{4}$' THEN RETURN to_date(regexp_replace(v, '[.-]', '/', 'g'), 'DD/MM/YYYY'); END IF;
    IF v ~ '^\d{5}(\.0+)?$' THEN RETURN DATE '1899-12-30' + floor(v::numeric)::int; END IF;
    RETURN NULL;
EXCEPTION WHEN others THEN RETURN NULL;
END $$;

-- ── what an appointment would do, and why not ──
CREATE FUNCTION hrm.appointment_check(p jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE v_no text := btrim(coalesce(p->>'staff_no', ''));
        v_sur text := btrim(coalesce(p->>'surname', '')); v_given text := btrim(coalesce(p->>'given_names', ''));
        v_cat text := upper(replace(replace(btrim(coalesce(p->>'category', '')), '-', '_'), ' ', '_'));
        v_grade text := upper(regexp_replace(btrim(coalesce(p->>'grade', '')), '\s+', ' ', 'g'));
        v_step int := CASE WHEN btrim(coalesce(p->>'step', '')) ~ '^\d{1,2}$' THEN btrim(p->>'step')::int END;
        v_date date := hrm.read_day(p->>'appointment_date');
        v_dept_in text := nullif(upper(btrim(coalesce(p->>'department', ''))), ''); v_unit_in text := nullif(upper(btrim(coalesce(p->>'unit', ''))), '');
        v_sex text := upper(btrim(coalesce(p->>'sex', ''))); v_email text := nullif(lower(btrim(coalesce(p->>'email', ''))), '');
        v_phone text := nullif(regexp_replace(btrim(coalesce(p->>'phone', '')), '[\s()-]', '', 'g'), '');
        v_acct text := regexp_replace(coalesce(p->>'account_number', p->>'account_last4', ''), '\D', '', 'g');
        v_pin text := nullif(upper(btrim(coalesce(p->>'pension_pin', ''))), '');
        v_dept text; v_unit text; per record; g record; v_emp record; probs text[] := '{}'; warns text[] := '{}';
BEGIN
    IF v_no !~ '^[A-Za-z0-9/._-]{2,30}$' THEN probs := probs || 'The staff number is 2 to 30 letters, digits, / . _ or -.'::text; END IF;
    SELECT x.id, x.surname, x.given_names, x.ended_on, x.email INTO per FROM iam.person x WHERE upper(btrim(x.staff_number)) = upper(v_no) LIMIT 1;
    IF per.id IS NOT NULL THEN
        IF per.ended_on IS NOT NULL THEN probs := probs || ('The person with staff number ' || v_no || ' was ended on ' || to_char(per.ended_on, 'DD Mon YYYY') || '; ICT restores the record first.'); END IF;
        SELECT e.staff_no, e.status INTO v_emp FROM hrm.employment e WHERE e.person_id = per.id AND e.status <> 'ENDED' LIMIT 1;
        IF v_emp.staff_no IS NOT NULL THEN probs := probs || (per.surname || ' is already in employment (' || v_emp.staff_no || ', ' || lower(v_emp.status) || ').'); END IF;
        IF v_sur <> '' AND upper(v_sur) <> upper(btrim(per.surname)) THEN
            warns := warns || ('The staff number is ' || per.surname || ', ' || per.given_names || '''s; the row says ' || v_sur || '.');
        END IF;
    ELSE
        IF length(v_sur) < 2 OR length(v_given) < 2 THEN probs := probs || 'A new member of staff needs a surname and given names.'::text; END IF;
    END IF;
    IF v_no <> '' AND EXISTS (SELECT 1 FROM hrm.employment e WHERE upper(e.staff_no) = upper(v_no) AND (per.id IS NULL OR e.person_id <> per.id OR e.status = 'ENDED')) THEN
        probs := probs || ('Staff number ' || v_no || ' is already on an employment record; a return to service is a Movement (reinstatement).');
    END IF;
    IF v_cat NOT IN ('ACADEMIC', 'NON_ACADEMIC') THEN probs := probs || 'The category is ACADEMIC or NON_ACADEMIC.'::text; END IF;
    SELECT x.grade, x.step, x.category INTO g FROM hrm.grade x WHERE upper(x.grade) = v_grade AND x.step = v_step;
    IF g.grade IS NULL THEN
        probs := probs || ('Grade ' || coalesce(nullif(v_grade, ''), '(none)') || ' step ' || coalesce(v_step::text, '(none)') || ' is not set up; set it on Salary grades first.');
    ELSIF v_cat IN ('ACADEMIC', 'NON_ACADEMIC') AND g.category <> v_cat THEN
        probs := probs || (g.grade || CASE g.category WHEN 'ACADEMIC' THEN ' is an academic grade.' ELSE ' is a non-academic grade.' END);
    END IF;
    IF v_date IS NULL THEN probs := probs || 'The date of appointment is a day (YYYY-MM-DD or DD/MM/YYYY).'::text;
    ELSIF v_date < DATE '1960-01-01' OR v_date > current_date + 366 THEN probs := probs || 'The date of appointment is from 1960 and at most a year ahead.'::text;
    END IF;
    IF v_dept_in IS NOT NULL THEN
        SELECT d.code INTO v_dept FROM ref.department d WHERE (upper(d.code) = v_dept_in OR upper(d.name) = v_dept_in) AND d.ended_on IS NULL LIMIT 1;
        IF v_dept IS NULL THEN probs := probs || ('No live department ' || v_dept_in || '.'); END IF;
    END IF;
    IF v_unit_in IS NOT NULL THEN
        SELECT u.code INTO v_unit FROM ref.unit u WHERE (upper(u.code) = v_unit_in OR upper(u.name) = v_unit_in) AND u.ended_on IS NULL LIMIT 1;
        IF v_unit IS NULL THEN probs := probs || ('No live unit ' || v_unit_in || '.'); END IF;
    END IF;
    IF v_cat = 'ACADEMIC' AND v_dept_in IS NULL THEN probs := probs || 'An academic appointment names the department.'::text;
    ELSIF v_dept_in IS NULL AND v_unit_in IS NULL THEN probs := probs || 'Name the department or the unit of the appointment.'::text;
    END IF;
    IF v_sex <> '' AND v_sex NOT IN ('M', 'F', 'MALE', 'FEMALE') THEN probs := probs || 'Sex is M or F.'::text; END IF;
    IF v_email IS NOT NULL AND v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN probs := probs || 'The e-mail address is not one.'::text; END IF;
    IF v_email IS NOT NULL AND EXISTS (SELECT 1 FROM iam.person x WHERE lower(x.email) = v_email AND x.id IS DISTINCT FROM per.id) THEN
        probs := probs || ('The e-mail ' || v_email || ' belongs to another person.');
    END IF;
    IF v_phone IS NOT NULL AND v_phone !~ '^\+?\d{7,15}$' THEN probs := probs || 'The phone number is 7 to 15 digits.'::text; END IF;
    IF v_acct <> '' AND length(v_acct) < 4 THEN probs := probs || 'The account number has at least four digits (only the last four are kept).'::text; END IF;
    IF v_pin IS NOT NULL AND v_pin !~ '^[A-Z0-9]{6,20}$' THEN probs := probs || 'The pension PIN is 6 to 20 letters and digits.'::text; END IF;
    RETURN jsonb_build_object(
        'ok', cardinality(probs) = 0, 'problems', to_jsonb(probs), 'warnings', to_jsonb(warns),
        'action', CASE WHEN per.id IS NOT NULL THEN 'LINK' ELSE 'CREATE' END, 'person_id', per.id,
        'name', CASE WHEN per.id IS NOT NULL THEN upper(btrim(per.surname)) || ', ' || btrim(per.given_names) ELSE upper(v_sur) || ', ' || v_given END,
        'staff_no', v_no, 'category', v_cat, 'grade', coalesce(g.grade, v_grade), 'step', v_step, 'appointment_date', v_date,
        'department', v_dept, 'unit', v_unit,
        'sex', CASE WHEN v_sex IN ('M', 'MALE') THEN 'M' WHEN v_sex IN ('F', 'FEMALE') THEN 'F' END,
        'email', v_email, 'phone', v_phone, 'account_last4', CASE WHEN length(v_acct) >= 4 THEN right(v_acct, 4) END, 'pension_pin', v_pin);
END $$;
COMMENT ON FUNCTION hrm.appointment_check(jsonb) IS
  'V510: what an appointment row would do (LINK an existing person by staff number, or CREATE one) and every reason it may not: staff number, person already in employment, staff number on an employment record, category, grade and step set up in the category, date, department or unit, sex, e-mail, phone, account and pension; writes nothing';

-- ── the appointment made ──
CREATE FUNCTION hrm.appoint(p jsonb)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); c jsonb; v_person uuid; v_emp uuid; v_scale text;
BEGIN
    IF coalesce(v_office, '') NOT IN ('hrm', 'super') THEN
        RAISE EXCEPTION 'HR_APPOINT_OFFICE: an appointment is made by Human Resources' USING ERRCODE = '42501';
    END IF;
    c := hrm.appointment_check(p);
    IF NOT (c->>'ok')::boolean THEN
        RAISE EXCEPTION 'HR_APPOINTMENT_INVALID: %', (SELECT string_agg(x, ' ') FROM jsonb_array_elements_text(c->'problems') x) USING ERRCODE = '23514';
    END IF;
    v_person := (c->>'person_id')::uuid;
    IF v_person IS NULL THEN
        v_person := gen_random_uuid();
        INSERT INTO iam.person (id, staff_number, surname, given_names, email, phone)
        VALUES (v_person, c->>'staff_no', upper(btrim(p->>'surname')), btrim(p->>'given_names'), c->>'email', c->>'phone');
    ELSE
        UPDATE iam.person SET email = coalesce(email, c->>'email'), phone = coalesce(phone, c->>'phone') WHERE id = v_person;
    END IF;
    v_scale := CASE WHEN split_part(c->>'grade', ' ', 1) IN ('CONUASS', 'CONTISS', 'CONUNASS', 'CONMESS', 'CONHESS', 'CONSOLIDATED') THEN split_part(c->>'grade', ' ', 1) END;
    INSERT INTO hrm.staff_record AS sr (person_id, sex, date_first_appointment, present_rank, home_department, home_unit, category, salary_scale, updated_at)
    VALUES (v_person, c->>'sex', (c->>'appointment_date')::date, nullif(btrim(coalesce(p->>'rank', '')), ''), c->>'department', c->>'unit', c->>'category', v_scale, now())
    ON CONFLICT (person_id) DO UPDATE SET
        sex = coalesce(EXCLUDED.sex, sr.sex),
        date_first_appointment = coalesce(sr.date_first_appointment, EXCLUDED.date_first_appointment),
        present_rank = coalesce(EXCLUDED.present_rank, sr.present_rank),
        home_department = coalesce(EXCLUDED.home_department, sr.home_department),
        home_unit = coalesce(EXCLUDED.home_unit, sr.home_unit),
        category = EXCLUDED.category, salary_scale = coalesce(EXCLUDED.salary_scale, sr.salary_scale), updated_at = now();
    INSERT INTO hrm.employment (person_id, staff_no, grade, step, category, appointment_date, status, bank_name, account_name, account_last4, pension_pin)
    VALUES (v_person, c->>'staff_no', c->>'grade', (c->>'step')::int, c->>'category', (c->>'appointment_date')::date, 'ACTIVE',
            nullif(btrim(coalesce(p->>'bank_name', '')), ''), nullif(btrim(coalesce(p->>'account_name', '')), ''), c->>'account_last4', c->>'pension_pin')
    RETURNING id INTO v_emp;
    RETURN v_emp;
END $$;
COMMENT ON FUNCTION hrm.appoint(jsonb) IS
  'V510: Human Resources makes an appointment — the person (made, or linked by staff number), the establishment record and the ACTIVE employment record — refused with every reason hrm.appointment_check gives';

-- ── an upload, row by row ──
CREATE FUNCTION hrm.appointments_check(p_rows jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH r AS (SELECT x.value AS row, x.ordinality AS n, upper(btrim(coalesce(x.value->>'staff_no', ''))) AS no
                 FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) WITH ORDINALITY x),
    dup AS (SELECT no, array_agg(coalesce(r.row->>'row', r.n::text) ORDER BY r.n) AS rows FROM r WHERE no <> '' GROUP BY no HAVING count(*) > 1),
    c AS (SELECT r.n, r.row, hrm.appointment_check(r.row) AS chk, d.rows AS dup_rows FROM r LEFT JOIN dup d ON d.no = r.no)
    SELECT coalesce(jsonb_agg(
        c.chk || jsonb_build_object('row', coalesce(c.row->>'row', c.n::text),
                                    'ok', (c.chk->>'ok')::boolean AND c.dup_rows IS NULL,
                                    'problems', (c.chk->'problems') || CASE WHEN c.dup_rows IS NULL THEN '[]'::jsonb
                                        ELSE jsonb_build_array('The staff number is repeated in the file (rows ' || array_to_string(c.dup_rows, ', ') || ').') END)
        ORDER BY c.n), '[]'::jsonb)
      FROM c
$$;

CREATE FUNCTION hrm.appoint_many(p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); chk jsonb; x jsonb; rowval jsonb; i int := 0; made int := 0; out jsonb := '[]'::jsonb; v_emp uuid;
BEGIN
    IF coalesce(v_office, '') NOT IN ('hrm', 'super') THEN
        RAISE EXCEPTION 'HR_APPOINT_OFFICE: an appointment is made by Human Resources' USING ERRCODE = '42501';
    END IF;
    IF jsonb_array_length(coalesce(p_rows, '[]'::jsonb)) > 2000 THEN
        RAISE EXCEPTION 'HR_APPOINT_TOO_MANY: an upload holds at most 2,000 appointments' USING ERRCODE = '23514';
    END IF;
    chk := hrm.appointments_check(p_rows);
    FOR x IN SELECT value FROM jsonb_array_elements(chk) LOOP
        i := i + 1;
        rowval := p_rows->(i - 1);
        IF (x->>'ok')::boolean THEN
            v_emp := hrm.appoint(rowval);
            made := made + 1;
            out := out || jsonb_build_object('row', x->>'row', 'staff_no', x->>'staff_no', 'name', x->>'name', 'appointed', true, 'employment_id', v_emp);
        ELSE
            out := out || jsonb_build_object('row', x->>'row', 'staff_no', x->>'staff_no', 'name', x->>'name', 'appointed', false, 'problems', x->'problems');
        END IF;
    END LOOP;
    RETURN jsonb_build_object('appointed', made, 'skipped', i - made, 'rows', out);
END $$;
COMMENT ON FUNCTION hrm.appoint_many(jsonb) IS
  'V510: an upload of appointments: each row that passes hrm.appointments_check (a staff number repeated in the file refused) is appointed; the rest are listed with their reasons';

COMMIT;
