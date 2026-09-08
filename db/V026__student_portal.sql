-- ═══════════════════════════════════════════════════════════════════════════
-- V026 — the student's side of the portal
--
--   · The student is an office the audit spine knows. The applicant account
--     becomes the student account on matriculation: the first sign-in with
--     the matriculation number verifies the password the applicant chose,
--     and the student account is opened on it. A student who came onto the
--     register another way is given a password by the Registry.
--   · Fees. The Bursar states the session's charges as a schedule — per
--     level, faculty, programme or entry mode where they differ — and a
--     student's charge is computed from it, never typed. A payment is a
--     reference this portal generates, confirmed by the Bursary or by a
--     gateway's signed webhook, exactly as the applicant's fee is; the
--     receipt is issued on confirmation. What a payment releases is the
--     clearance scheme's to say (policy.clears, V004): the Bursar puts the
--     recommended scheme in force here, and until one is, the portal refuses
--     rather than assumes.
--   · Registration by the student: the courses the programme and level were
--     made eligible for, the carryovers added because a published F says so,
--     a draft the student fills, submitted only when the Bursary clears the
--     student for registration and the units are within the level's range.
--     Approval stays with the level adviser and the Head of Department.
--   · Results: what the published score sheets say, and only those; the GPA
--     and the CGPA computed over them under the grading in force.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    PERFORM set_config('moaum.reason', 'The student as an office the audit spine knows (V026), Directorate of ICT', true);
END $seed$;

INSERT INTO ref.office (code, label, scope_kind) VALUES ('student', 'Student', 'institution')
ON CONFLICT (code) DO NOTHING;

-- ── the account ─────────────────────────────────────────────────────────
CREATE TABLE iam.student_account (
    id                uuid PRIMARY KEY,
    student_id        uuid NOT NULL UNIQUE REFERENCES people.student(id),
    password_hash     text NOT NULL,
    must_change       boolean NOT NULL DEFAULT false,
    failed_attempts   int  NOT NULL DEFAULT 0,
    locked_until      timestamptz NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    last_signed_in_at timestamptz NULL,
    CONSTRAINT ck_student_hash CHECK (password_hash LIKE '$2%$12$%')
);
SELECT audit.exempt('iam.student_account',
    'Carries a password hash; the acts on the student record are on the spine, and the sign-ins are in iam.student_event.');

CREATE TABLE iam.student_event (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NULL,
    identifier text NOT NULL,
    outcome    text NOT NULL,
    ip         text NULL,
    at         timestamptz NOT NULL DEFAULT now()
);
SELECT audit.exempt('iam.student_event', 'The sign-in log itself; auditing the audit of sign-ins doubles every row.');

-- what the student may change; everything else on the record is the Registry's
CREATE TABLE people.student_contact (
    student_id uuid PRIMARY KEY REFERENCES people.student(id),
    phone      text NULL,
    email      text NULL,
    address    text NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_contact_phone CHECK (phone IS NULL OR phone ~ '^0[0-9]{10}$'),
    CONSTRAINT ck_contact_email CHECK (email IS NULL OR email ~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$')
);
SELECT audit.attach('people.student_contact');

-- where the University reaches a student: the contact they gave, else the application account they came in on
CREATE OR REPLACE FUNCTION people.student_reach(p_student uuid)
RETURNS TABLE (email text, phone text)
LANGUAGE sql STABLE AS $$
    SELECT coalesce(c.email, a.email), coalesce(c.phone, a.phone)
      FROM people.student s
      LEFT JOIN people.student_contact c ON c.student_id = s.id
      LEFT JOIN admissions.applicant_account a ON a.candidate_id = s.candidate_id
     WHERE s.id = p_student;
$$;

-- ── the fees ────────────────────────────────────────────────────────────
CREATE TABLE finance.fee_schedule (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session        text NOT NULL,
    item           text NOT NULL,
    amount         numeric(12,2) NOT NULL,
    level          int  NULL,
    entry_mode     text NULL,
    faculty_code   text NULL REFERENCES ref.faculty(code),
    programme_code text NULL REFERENCES ref.programme(code),
    ord            int  NOT NULL DEFAULT 0,
    ended_at       timestamptz NULL,
    CONSTRAINT ck_fee_amount CHECK (amount >= 0),
    CONSTRAINT ck_fee_item CHECK (btrim(item) <> ''),
    CONSTRAINT ck_fee_level CHECK (level IS NULL OR level IN (100,200,300,400,500,600))
);
CREATE INDEX ix_fee_session ON finance.fee_schedule (session) WHERE ended_at IS NULL;
SELECT audit.attach('finance.fee_schedule');

COMMENT ON TABLE finance.fee_schedule IS
  'The session''s charges as the Bursar states them: an item applies to a student when every filter it '
  'carries — level, entry mode, faculty, programme — matches, or is blank. A student''s charge is computed, never typed.';

CREATE OR REPLACE FUNCTION finance.charges(p_student uuid, p_session text)
RETURNS TABLE (id uuid, item text, amount numeric, ord int)
LANGUAGE sql STABLE AS $$
    SELECT f.id, f.item, f.amount, f.ord
      FROM finance.fee_schedule f, people.student s
      JOIN ref.programme p ON p.code = s.programme_code
     WHERE s.id = p_student AND f.session = p_session AND f.ended_at IS NULL
       AND (f.level IS NULL OR f.level = s.current_level)
       AND (f.entry_mode IS NULL OR f.entry_mode = s.entry_mode)
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
       AND (f.programme_code IS NULL OR f.programme_code = s.programme_code)
     ORDER BY f.ord, f.item;
$$;

CREATE TABLE finance.payment_reference (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id   uuid NOT NULL REFERENCES people.student(id),
    session      text NOT NULL,
    reference    text NOT NULL UNIQUE,
    purpose      text NOT NULL,
    amount       numeric(12,2) NOT NULL,
    generated_at timestamptz NOT NULL DEFAULT now(),
    expires_at   timestamptz NOT NULL,
    confirmed_at timestamptz NULL,
    confirmed_by uuid NULL,
    channel      text NULL,
    note         text NULL,
    receipt_no   text NULL UNIQUE,
    CONSTRAINT ck_pref_amount CHECK (amount > 0),
    CONSTRAINT ck_pref_confirmed CHECK (confirmed_at IS NULL OR (confirmed_by IS NOT NULL AND channel IS NOT NULL AND receipt_no IS NOT NULL))
);
CREATE INDEX ix_pref_student ON finance.payment_reference (student_id, session);
SELECT audit.attach('finance.payment_reference');

-- the student's position in a session: due from the schedule, paid from confirmed references
CREATE OR REPLACE FUNCTION finance.position(p_student uuid, p_session text)
RETURNS TABLE (due numeric, paid numeric, balance numeric, instalments_paid int, paid_in_full boolean, has_arrears boolean)
LANGUAGE sql STABLE AS $$
    WITH d AS (SELECT coalesce(sum(c.amount), 0) AS due FROM finance.charges(p_student, p_session) c),
         p AS (SELECT coalesce(sum(r.amount), 0) AS paid FROM finance.payment_reference r
                WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL),
         arrears AS (
             SELECT EXISTS (
                 SELECT 1 FROM (SELECT DISTINCT f.session FROM finance.fee_schedule f WHERE f.session < p_session AND f.ended_at IS NULL) past
                  WHERE (SELECT coalesce(sum(c.amount), 0) FROM finance.charges(p_student, past.session) c)
                      > (SELECT coalesce(sum(r.amount), 0) FROM finance.payment_reference r
                          WHERE r.student_id = p_student AND r.session = past.session AND r.confirmed_at IS NOT NULL)) AS yes)
    SELECT d.due, p.paid, greatest(d.due - p.paid, 0),
           CASE WHEN d.due = 0 THEN 2 WHEN p.paid >= d.due THEN 2 WHEN p.paid * 2 >= d.due THEN 1 ELSE 0 END,
           d.due = 0 OR p.paid >= d.due,
           arrears.yes
      FROM d, p, arrears;
$$;

-- what the policy says this student's position releases, this session; fails closed while no scheme is in force (D-Q4)
CREATE OR REPLACE FUNCTION finance.clears(p_student uuid, p_session text, p_purpose text)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT policy.clears(p_purpose, pos.instalments_paid, pos.paid_in_full, pos.has_arrears, current_date, 'UNIVERSITY')
      FROM finance.position(p_student, p_session) pos;
$$;

CREATE OR REPLACE FUNCTION finance.new_reference(p_student uuid, p_session text, p_amount numeric, p_purpose text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE pos record; v_ref text; v_matric text;
BEGIN
    SELECT * INTO pos FROM finance.position(p_student, p_session);
    IF pos.due = 0 THEN
        RAISE EXCEPTION 'no charge is stated for % yet', p_session USING ERRCODE = '23514',
            HINT = 'The Bursar states the session''s fee schedule before anything is paid against it.';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'a payment is for an amount' USING ERRCODE = '23514';
    END IF;
    IF p_amount > pos.balance THEN
        RAISE EXCEPTION 'the amount % is more than the balance of %', p_amount, pos.balance USING ERRCODE = '23514',
            HINT = 'Pay the balance, or part of it; nothing is taken beyond what is owed.';
    END IF;
    SELECT coalesce(matric_no, admission_no, 'X') INTO v_matric FROM people.student WHERE id = p_student;
    v_ref := 'MOAUM-FEE-' || regexp_replace(right(v_matric, 7), '[^0-9A-Z]', '', 'g') || '-' || lpad((floor(random() * 10000))::int::text, 4, '0');
    INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at)
    VALUES (p_student, p_session, v_ref, coalesce(p_purpose, 'School fees ' || p_session), p_amount, now() + interval '24 hours');
    RETURN v_ref;
END $$;

-- confirmed by the Bursary against the bank's record, or by a gateway's signed webhook; the receipt is issued here
CREATE OR REPLACE FUNCTION finance.confirm_payment(p_reference text, p_channel text, p_note text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE r finance.payment_reference; v_no text; reach record; pos record;
BEGIN
    SELECT * INTO r FROM finance.payment_reference WHERE reference = upper(btrim(p_reference));
    IF NOT FOUND THEN RAISE EXCEPTION 'no reference % was generated by this portal', p_reference USING ERRCODE = '23503',
        HINT = 'Only a reference this portal generated is confirmed; money sent anywhere else did not reach the University.'; END IF;
    IF r.confirmed_at IS NOT NULL THEN RETURN 'already confirmed'; END IF;
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a payment is confirmed by a person' USING ERRCODE = '23514';
    END IF;
    v_no := 'RCT-' || left(r.session, 4) || '-' || lpad(platform.next_number('RECEIPT', 'UNIVERSITY', r.session)::text, 5, '0');
    UPDATE finance.payment_reference SET confirmed_at = now(), confirmed_by = current_setting('moaum.actor_id', true)::uuid,
           channel = p_channel, note = p_note, receipt_no = v_no WHERE id = r.id;
    SELECT * INTO reach FROM people.student_reach(r.student_id);
    SELECT * INTO pos FROM finance.position(r.student_id, r.session);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your payment is confirmed',
        'Your payment of NGN ' || r.amount::text || ' against reference ' || r.reference || ' is confirmed. Receipt ' || v_no
        || '. ' || CASE WHEN pos.balance = 0 THEN 'Your charges for ' || r.session || ' are settled in full.'
                        ELSE 'NGN ' || pos.balance::text || ' remains for ' || r.session || '.' END
        || ' Sign in to download the receipt.', 'student', r.student_id);
    PERFORM platform.queue_notice('SMS', reach.phone, 'Your payment is confirmed',
        'MOAUM: payment ' || r.reference || ' confirmed, receipt ' || v_no || '. '
        || CASE WHEN pos.balance = 0 THEN 'Fees settled in full.' ELSE 'Balance NGN ' || pos.balance::text || '.' END, 'student', r.student_id);
    RETURN 'confirmed';
END $$;

-- the Bursar puts the recommended clearance scheme in force, under an instrument, from a date
CREATE OR REPLACE FUNCTION finance.put_scheme_in_force(p_instrument text, p_from date)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid(); office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF p_instrument IS NULL OR btrim(p_instrument) = '' THEN
        RAISE EXCEPTION 'a clearance scheme is put in force under an instrument' USING ERRCODE = '23514',
            HINT = 'Cite the Council or Bursary minute that approved it.';
    END IF;
    IF policy.in_force('clearance', 'UNIVERSITY', p_from) IS NOT NULL THEN
        RAISE EXCEPTION 'a clearance scheme is already in force on %', p_from USING ERRCODE = '23514',
            HINT = 'Two schemes cannot overlap; end the one in force first, on the record.';
    END IF;
    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
    VALUES (v, 'clearance', 'UNIVERSITY', daterange(p_from, NULL), btrim(p_instrument), coalesce(office, 'bursar'));
    INSERT INTO policy.clearance_scheme VALUES (v, true);
    INSERT INTO policy.clearance_rule VALUES
        (v, 'REGISTRATION', 'INSTALMENT_1'),
        (v, 'ID_CARD',      'INSTALMENT_1'),
        (v, 'LIBRARY',      'INSTALMENT_1'),
        (v, 'HOSTEL',       'NEVER_GATED'),
        (v, 'EXAMINATION',  'PAID_IN_FULL'),
        (v, 'RESULTS',      'PAID_IN_FULL'),
        (v, 'TRANSCRIPT',   'PAID_IN_FULL'),
        (v, 'CONVOCATION',  'PAID_IN_FULL');
    PERFORM policy.assert_scheme_complete(v);
    RETURN v;
END $$;

-- ── results, as the published sheets say ────────────────────────────────
CREATE OR REPLACE FUNCTION assessment.student_results(p_student uuid)
RETURNS TABLE (session text, semester int, course_code text, title text, units int, entry_type text,
               stage text, published boolean, published_at timestamptz, senate_minute text,
               ca int, exam int, total int, grade text, points numeric, outcome text)
LANGUAGE sql STABLE AS $$
    SELECT r.session, r.semester, c.code, c.title, e.units, e.entry_type,
           coalesce(sh.stage, 'NO_SHEET'), sh.stage = 'PUBLISHED', sh.published_at, sh.senate_minute,
           CASE WHEN sh.stage = 'PUBLISHED' THEN ls.ca END,
           CASE WHEN sh.stage = 'PUBLISHED' THEN ls.exam END,
           CASE WHEN sh.stage = 'PUBLISHED' THEN ls.total END,
           CASE WHEN sh.stage = 'PUBLISHED' THEN ls.grade END,
           CASE WHEN sh.stage = 'PUBLISHED' THEN ls.points END,
           CASE WHEN sh.stage = 'PUBLISHED' THEN ls.outcome END
      FROM registration.course_registration r
      JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED','APPROVED')
      JOIN catalogue.offering o ON o.id = e.offering_id
      JOIN catalogue.course c ON c.code = o.course_code
      LEFT JOIN assessment.score_sheet sh ON sh.offering_id = o.id
      LEFT JOIN LATERAL (SELECT * FROM assessment.latest_scores(sh.id) x WHERE x.student_id = p_student) ls ON sh.id IS NOT NULL
     WHERE r.student_id = p_student AND r.status IN ('APPROVED','LOCKED')
     ORDER BY r.session, r.semester, c.code;
$$;

-- the GPA of each semester with a published grade, and the CGPA to that point
CREATE OR REPLACE FUNCTION assessment.student_gpa(p_student uuid)
RETURNS TABLE (session text, semester int, units int, gpa numeric, cgpa numeric, published_count int, registered_count int)
LANGUAGE sql STABLE AS $$
    WITH rows AS (SELECT * FROM assessment.student_results(p_student)),
    per AS (
        SELECT r.session, r.semester,
               sum(r.units) FILTER (WHERE r.published AND r.outcome = 'GRADED')::int AS graded_units,
               sum(r.units * r.points) FILTER (WHERE r.published AND r.outcome = 'GRADED') AS pts,
               count(*) FILTER (WHERE r.published)::int AS published_count,
               count(*)::int AS registered_count
          FROM rows r GROUP BY r.session, r.semester)
    SELECT p.session, p.semester, coalesce(p.graded_units, 0),
           CASE WHEN coalesce(p.graded_units, 0) > 0 THEN round(p.pts / p.graded_units, 2) END,
           CASE WHEN sum(coalesce(p.graded_units, 0)) OVER w > 0
                THEN round(sum(coalesce(p.pts, 0)) OVER w / sum(coalesce(p.graded_units, 0)) OVER w, 2) END,
           p.published_count, p.registered_count
      FROM per p
    WINDOW w AS (ORDER BY p.session, p.semester ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
     ORDER BY p.session, p.semester;
$$;

-- a course failed on a published sheet and not passed since: added to the next registration, not asked for
CREATE OR REPLACE FUNCTION registration.carryovers(p_student uuid)
RETURNS TABLE (course_code text, title text, units int, failed_in text)
LANGUAGE sql STABLE AS $$
    SELECT f.course_code, f.title, f.units, f.session || ' semester ' || f.semester
      FROM assessment.student_results(p_student) f
     WHERE f.published AND f.outcome = 'GRADED' AND f.points = 0
       AND NOT EXISTS (SELECT 1 FROM assessment.student_results(p_student) g
                        WHERE g.course_code = f.course_code AND g.published AND g.outcome = 'GRADED' AND g.points > 0
                          AND (g.session, g.semester) > (f.session, f.semester));
$$;

-- ── the student's registration ──────────────────────────────────────────
-- the courses on the form: the eligible set for the programme and level with an offering this semester, and the carryovers
CREATE OR REPLACE FUNCTION registration.student_menu(p_student uuid, p_session text, p_semester int)
RETURNS TABLE (offering_id uuid, course_code text, title text, units int, kind text, basis text, owner_dept text,
               carryover boolean, failed_in text, lecturer text)
LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT * FROM people.student WHERE id = p_student),
    eligible AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, co.basis, c.dept_code
          FROM s
          JOIN catalogue.course_offer co ON co.programme_code = s.programme_code AND co.level = s.current_level
          JOIN catalogue.course c ON c.code = co.course_code AND c.state <> 'ENDED'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester),
    carry AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, 'Carryover'::text AS basis, c.dept_code, cv.failed_in
          FROM registration.carryovers(p_student) cv
          JOIN catalogue.course c ON c.code = cv.course_code
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester)
    SELECT x.offering_id, x.code, x.title, x.units, x.kind, x.basis, d.name,
           (x.basis = 'Carryover'), x.failed_in, p.surname || ', ' || p.given_names
      FROM (SELECT e.*, NULL::text AS failed_in FROM eligible e
            WHERE NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.offering_id = e.offering_id)
            UNION ALL SELECT * FROM carry) x
      JOIN ref.department d ON d.code = x.dept_code
      JOIN catalogue.offering o ON o.id = x.offering_id
      LEFT JOIN iam.person p ON p.id = o.lecturer_id
     ORDER BY (x.basis = 'Carryover') DESC, x.kind, x.code;
$$;

-- the draft, made when the student first opens the form; the carryovers are on it from the start
CREATE OR REPLACE FUNCTION registration.student_draft(p_student uuid, p_session text, p_semester int)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid; s people.student; m record;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
    SELECT id INTO v FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF v IS NOT NULL THEN RETURN v; END IF;
    v := gen_random_uuid();
    INSERT INTO registration.course_registration (id, student_id, session, semester, level)
    VALUES (v, p_student, p_session, p_semester, s.current_level);
    FOR m IN SELECT * FROM registration.student_menu(p_student, p_session, p_semester) WHERE carryover LOOP
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type) VALUES (v, m.offering_id, m.units, 'CARRYOVER');
    END LOOP;
    RETURN v;
END $$;

-- the student's choice, replaced whole: the carryovers stay, everything else is what was named
CREATE OR REPLACE FUNCTION registration.student_choose(p_registration uuid, p_offerings uuid[])
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; m record; n int := 0;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status NOT IN ('DRAFT','RETURNED') THEN
        RAISE EXCEPTION 'this registration is %; it is not edited', lower(r.status) USING ERRCODE = '23514',
            HINT = 'A submitted registration is changed by the level adviser returning it.';
    END IF;
    DELETE FROM registration.entry WHERE registration_id = p_registration AND entry_type <> 'CARRYOVER';
    FOR m IN SELECT * FROM registration.student_menu(r.student_id, r.session, r.semester) WHERE NOT carryover AND offering_id = ANY(p_offerings) LOOP
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (p_registration, m.offering_id, m.units,
                CASE WHEN m.basis = 'GST' OR m.kind = 'GST' THEN 'GST' WHEN m.basis = 'Borrowed' THEN 'BORROWED'
                     WHEN m.basis = 'Elective' OR m.kind = 'Elective' THEN 'ELECTIVE' ELSE 'CURRENT' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        n := n + 1;
    END LOOP;
    RETURN registration.units_of(p_registration);
END $$;

-- submitted only when the Bursary clears the student for registration and the units are within the level's range
CREATE OR REPLACE FUNCTION registration.student_submit(p_registration uuid)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; lim policy.level_limit; units int; cleared boolean;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status NOT IN ('DRAFT','RETURNED') THEN RETURN 'already ' || lower(r.status); END IF;
    cleared := finance.clears(r.student_id, r.session, 'REGISTRATION');
    IF NOT cleared THEN
        RAISE EXCEPTION 'the Bursary has not cleared this student for registration in %', r.session USING ERRCODE = '23514',
            HINT = 'Pay the fees the clearance scheme requires for registration; the position updates the moment a payment is confirmed.';
    END IF;
    units := registration.units_of(p_registration);
    SELECT * INTO lim FROM policy.level_limit WHERE level = r.level;
    IF FOUND AND (units < lim.min_units OR units > lim.max_units) THEN
        RAISE EXCEPTION 'the registration carries % units; at % level the range is % to %', units, r.level, lim.min_units, lim.max_units
        USING ERRCODE = '23514', HINT = 'Add or drop courses to bring it within the range, or obtain an overload approval from the Head of Department.';
    END IF;
    UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE id = p_registration;
    RETURN 'submitted';
END $$;

COMMIT;
