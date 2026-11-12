-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V739 · The review of V735 (the Summer Semester) applied
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  An adversarial review of V735 (five readers, each finding put to a refuter) confirmed 31 defects; the database's are answered here,
--  the API's and the screens' in the same change.
--
--  Money
--    · A reference confirmed late — expired as stale, its charges taken back or paid by a newer reference — paid nothing and recorded
--      nothing: the programme fee could be paid twice. Now the confirmation pays the charges it was drawn for still owed; then those
--      it was drawn for and taken back since, where nothing stands in their place and the course is still outstanding; then the
--      student's other charges of the Summer still owed (the programme fee first, a course never before it), each in whole; whatever
--      is left stands as an unapplied Summer credit (registration.summer_credit) the Bursary sees, to apply or refund. The other open
--      references of the Summer are closed.
--    · A registration that fails after the money is taken (a course ended since it was chosen, a gate on the registration) rolled the
--      confirmation back on every lane. Now the registration is made course by course, each failure recorded for the desk
--      (registration.summer_issue) and retried there; the payment always stands. A Summer class already open is reused, never reopened.
--    · Drawing a reference takes back a course no longer outstanding (passed since it was chosen) or no longer taught; a reference
--      that still holds a course no longer taught is not taken to a gateway.
--    · A Summer payment is not moved by a payment correction nor archived while charges stand paid by it (REALLOC_LINKED, PAR_LINKED).
--    · An open reference is shown only when it may be paid, with its own amount (summer_account.openReference / openAmount).
--  Results and standing
--    · A course left selected and unpaid at the close withheld every Summer result for good. A Summer result is now released by the
--      Summer itself (its courses are registered only once paid), save where the Bursar's scheme lets a balance owed for an earlier
--      session block everything — which the Summer had bypassed. Closing a Summer takes back what is selected and unpaid, and closes
--      its open references; an unpaid course may be taken back after the close too.
--    · A Summer made a student on probation or advised to withdraw read GOOD. standing_of is restored; a student's standing is read
--      from their last regular semester (assessment.student_standing leaves a session's Summer out).
--  School fees
--    · A Summer registration made a spillover student owe the session's whole-session spillover school fees, and listed them among
--      the registered without school fees. finance.reg_semesters and finance.registrations_without_fees leave a Summer out.
--  Eligibility and the desk
--    · A student in several categories was tested against the first only: a final-level spillover student was refused a Summer open
--      to Final year and Spillover. Every category a student falls in is read; the first the period admits is reported.
--    · A Summer entry carried the course's catalogue units, not the programme's (catalogue.units_for), skewing GPA and CGPA.
--    · Identification never re-read a student who had left the pool (an authorisation withdrawn, withdrawn, graduated): they stayed
--      eligible, listed and told. Each run re-reads them; an authorisation granted or withdrawn re-reads the student at once.
--
--  Not changed, and said so in docs/summer-semester.md: courses registered before with no result on this portal (old-portal results)
--  are not outstanding for the Summer (most past results are on the old portal; counting them would make nearly every final-year
--  student eligible for courses they passed) — the Academic Office authorises such a student for named courses. A fee withdrawn after
--  a selection keeps the figure the charge was made at (V735's rule: a charge keeps its figure).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V739: the review of V735 applied', true);

-- ── 1 · what the money and the registration leave for the desks ────────────────────────────────────────────────────────────────
CREATE TABLE registration.summer_credit (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id    uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    session       text NOT NULL REFERENCES policy.academic_session(name),
    reference_id  uuid NOT NULL REFERENCES finance.payment_reference(id) ON DELETE CASCADE,
    amount        numeric(12,2) NOT NULL CHECK (amount > 0),
    state         text NOT NULL DEFAULT 'OPEN' CHECK (state IN ('OPEN', 'APPLIED', 'REFUNDED')),
    created_at    timestamptz NOT NULL DEFAULT now(),
    settled_at    timestamptz,
    settled_by    uuid,
    settled_note  text,
    CONSTRAINT ck_summer_credit_settled CHECK (state = 'OPEN' OR (settled_at IS NOT NULL AND nullif(btrim(settled_note), '') IS NOT NULL))
);
CREATE INDEX ix_summer_credit_session ON registration.summer_credit (session, state);
COMMENT ON TABLE registration.summer_credit IS
  'V739: Summer money received beyond the charges it could pay — a reference confirmed after its charges were taken back or paid by another — for the Bursary to apply or refund; never lost from the Summer''s figures.';
SELECT audit.attach('registration.summer_credit');

CREATE TABLE registration.summer_issue (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id    uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    session       text NOT NULL REFERENCES policy.academic_session(name),
    reference_id  uuid REFERENCES finance.payment_reference(id) ON DELETE CASCADE,
    course_code   text,
    error         text NOT NULL,
    raised_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
    resolved_at   timestamptz,
    resolved_by   uuid
);
CREATE INDEX ix_summer_issue_open ON registration.summer_issue (session) WHERE resolved_at IS NULL;
COMMENT ON TABLE registration.summer_issue IS
  'V739: a paid Summer course the registration could not take (a course ended since it was chosen, a gate on the registration) — recorded for the Academic Office to put right and retry; the payment always stands.';
SELECT audit.attach('registration.summer_issue');

-- ── 2 · eligibility: every category a student falls in ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.summer_eligibility(p_student uuid, p_session text)
RETURNS TABLE(eligible boolean, category text, outstanding integer, reason text) LANGUAGE plpgsql STABLE AS $$
DECLARE s record; p registration.summer_period; a registration.summer_authorisation; v_cats text[]; v_cat text; v_out int; v_final int; v_beyond boolean;
BEGIN
    SELECT st.*, pr.category AS programme_category INTO s
      FROM people.student st LEFT JOIN ref.programme pr ON pr.code = st.programme_code WHERE st.id = p_student;
    SELECT * INTO p FROM registration.summer_period WHERE session = p_session;
    IF s.id IS NULL THEN RETURN QUERY SELECT false, NULL::text, 0, 'NO_STUDENT'; RETURN; END IF;
    IF p.session IS NULL THEN RETURN QUERY SELECT false, NULL::text, 0, 'NO_SUMMER'; RETURN; END IF;
    IF s.entry_mode IN ('CCE', 'POSTGRADUATE') OR coalesce(s.programme_category, '') <> 'UNDER GRADUATE' THEN
        RETURN QUERY SELECT false, NULL::text, 0, 'NOT_UNDERGRADUATE'; RETURN;
    END IF;
    IF s.status NOT IN ('ACTIVE', 'PROBATION') THEN RETURN QUERY SELECT false, NULL::text, 0, 'NOT_STUDYING'; RETURN; END IF;
    IF EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = p_student AND g.senate_state = 'APPROVED') THEN
        RETURN QUERY SELECT false, NULL::text, 0, 'GRADUATED'; RETURN;
    END IF;
    SELECT * INTO a FROM registration.summer_authorisation WHERE session = p_session AND student_id = p_student AND revoked_at IS NULL;
    v_out := (SELECT count(*) FROM registration.carryovers(p_student));
    v_final := coalesce(finance.final_level(s.programme_code), 400);
    v_beyond := coalesce((SELECT ap.spillover_years > 0 FROM people.academic_position ap WHERE ap.student_id = p_student), false);
    -- V739: every category the student falls in, the most specific first
    v_cats := array_remove(ARRAY[CASE WHEN v_beyond THEN 'BEYOND_DURATION' END,
                                 CASE WHEN finance.is_spillover(p_student) THEN 'SPILLOVER' END,
                                 CASE WHEN s.current_level >= v_final THEN 'FINAL_YEAR' END], NULL);
    IF a.student_id IS NOT NULL AND 'AUTHORISED' = ANY (p.categories) THEN
        RETURN QUERY SELECT true, 'AUTHORISED', v_out + coalesce(cardinality(a.courses), 0), NULL::text; RETURN;
    END IF;
    v_cat := (SELECT c FROM unnest(v_cats) WITH ORDINALITY u(c, i) WHERE c = ANY (p.categories) ORDER BY i LIMIT 1);
    IF p.programmes IS NOT NULL AND NOT (s.programme_code = ANY (p.programmes)) THEN
        RETURN QUERY SELECT false, coalesce(v_cat, v_cats[1]), v_out, 'PROGRAMME_NOT_IN_SUMMER'; RETURN;
    END IF;
    IF p.levels IS NOT NULL AND NOT (s.current_level = ANY (p.levels)) THEN
        RETURN QUERY SELECT false, coalesce(v_cat, v_cats[1]), v_out, 'LEVEL_NOT_IN_SUMMER'; RETURN;
    END IF;
    IF cardinality(v_cats) = 0 THEN RETURN QUERY SELECT false, NULL::text, v_out, 'NOT_FINAL_OR_SPILLOVER'; RETURN; END IF;
    IF v_cat IS NULL THEN RETURN QUERY SELECT false, v_cats[1], v_out, 'CATEGORY_NOT_IN_SUMMER'; RETURN; END IF;
    IF v_out = 0 THEN RETURN QUERY SELECT false, v_cat, 0, 'NO_OUTSTANDING_COURSE'; RETURN; END IF;
    RETURN QUERY SELECT true, v_cat, v_out, NULL::text;
END $$;

-- the units a Summer course is shown and registered at: the programme's own (catalogue.units_for), not the catalogue's
DO $$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('registration.summer_courses(uuid,text)'::regprocedure);
    IF position('    SELECT p.course_code, k.title, k.units, k.semester,' IN d) = 0 THEN
        RAISE EXCEPTION 'V739: registration.summer_courses is not as V735 left it';
    END IF;
    d := replace(d, '    SELECT p.course_code, k.title, k.units, k.semester,',
                    '    SELECT p.course_code, k.title,
           coalesce(catalogue.units_for(p.course_code, (SELECT st.programme_code FROM people.student st WHERE st.id = p_student), NULL), k.units)::int,   -- V739
           k.semester,');
    EXECUTE d;
END $$;

-- ── 3 · the reference, the confirmation and the registration ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.summer_reference(p_student uuid, p_session text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_due numeric; v_ref text; v_id uuid; v_courses int; v_prog boolean;
BEGIN
    PERFORM 1 FROM people.student WHERE id = p_student FOR UPDATE;
    -- paid while registration is open: a reference is never drawn for a Summer whose window has closed
    IF NOT registration.summer_open(p_session) THEN
        RAISE EXCEPTION 'SUMMER_CLOSED: registration for the Summer Semester of % is not open', p_session USING ERRCODE = '23514';
    END IF;
    -- V739: a course chosen and no longer outstanding (passed since) or no longer taught is not billed: taken back
    UPDATE registration.summer_charge c SET state = 'CANCELLED', cancelled_at = now()
     WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'COURSE' AND c.state = 'DUE'
       AND (EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = c.course_code AND k.state = 'ENDED')
            OR NOT EXISTS (SELECT 1 FROM registration.summer_courses(p_student, p_session) sc WHERE sc.course_code = c.course_code));
    UPDATE registration.summer_charge SET state = 'CANCELLED', cancelled_at = now()
     WHERE student_id = p_student AND session = p_session AND kind = 'PROGRAMME' AND state = 'DUE'
       AND NOT EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session
                         AND c.kind = 'COURSE' AND c.state IN ('DUE', 'PAID'));
    PERFORM registration.summer_close_stale_references(p_student, p_session);
    SELECT coalesce(sum(amount), 0), count(*) FILTER (WHERE kind = 'COURSE'), bool_or(kind = 'PROGRAMME')
      INTO v_due, v_courses, v_prog FROM registration.summer_charge
     WHERE student_id = p_student AND session = p_session AND state = 'DUE';
    IF v_due <= 0 THEN
        RAISE EXCEPTION 'SUMMER_NOTHING_DUE: nothing is owed for the Summer Semester of %', p_session USING ERRCODE = '23514',
            HINT = 'Select your courses first; what is paid stays registered.';
    END IF;
    SELECT r.reference INTO v_ref FROM finance.payment_reference r
     WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'Summer semester fees%'
       AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now() AND r.amount = v_due
     ORDER BY r.generated_at DESC LIMIT 1;
    IF v_ref IS NOT NULL THEN RETURN v_ref; END IF;
    v_ref := finance.new_purpose_reference(p_student, p_session, v_due,
        'Summer semester fees, ' || p_session || ': ' || concat_ws(' and ',
            CASE WHEN v_prog THEN 'programme fee' END,
            CASE WHEN v_courses > 0 THEN v_courses || ' course' || CASE WHEN v_courses = 1 THEN '' ELSE 's' END END));
    SELECT id INTO v_id FROM finance.payment_reference WHERE reference = v_ref;
    INSERT INTO registration.summer_reference_charge (reference_id, charge_id)
    SELECT v_id, c.id FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.state = 'DUE';
    RETURN v_ref;
END $$;

-- a reference that still holds a course no longer taught is not taken to a gateway (drawing again takes the course back)
CREATE OR REPLACE FUNCTION registration.summer_reference_payable(p_reference text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((
        SELECT r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now() AND r.student_id IS NOT NULL
               AND registration.summer_open(r.session)
               AND EXISTS (SELECT 1 FROM registration.summer_reference_charge rc WHERE rc.reference_id = r.id)
               AND NOT EXISTS (SELECT 1 FROM registration.summer_reference_charge rc JOIN registration.summer_charge c ON c.id = rc.charge_id
                                WHERE rc.reference_id = r.id AND c.state <> 'DUE')
               AND NOT EXISTS (SELECT 1 FROM registration.summer_charge c
                                WHERE c.student_id = r.student_id AND c.session = r.session AND c.state = 'DUE'
                                  AND NOT EXISTS (SELECT 1 FROM registration.summer_reference_charge rc WHERE rc.reference_id = r.id AND rc.charge_id = c.id))
               AND NOT EXISTS (SELECT 1 FROM registration.summer_reference_charge rc JOIN registration.summer_charge c ON c.id = rc.charge_id
                                 JOIN catalogue.course k ON k.code = c.course_code
                                WHERE rc.reference_id = r.id AND k.state = 'ENDED')   -- V739
               AND r.amount = (SELECT sum(c.amount) FROM registration.summer_reference_charge rc JOIN registration.summer_charge c ON c.id = rc.charge_id
                                WHERE rc.reference_id = r.id)
          FROM finance.payment_reference r
         WHERE r.reference = upper(btrim(coalesce(p_reference, ''))) AND r.purpose LIKE 'Summer semester fees%'), false);
$$;

/* the registration a paid Summer makes: semester 3 of the session, every paid course in its Summer class (the one open, else opened),
   at the programme's own units, approved by the payment itself; a course paid later joins it. A course the registration cannot take is
   recorded for the desk and the rest go on. Idempotent. */
CREATE OR REPLACE FUNCTION registration.summer_materialize(p_student uuid, p_session text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; c record; v_off uuid; v_new boolean := false; v_units int; v_n int; v_prog text; v_err text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM registration.summer_charge WHERE student_id = p_student AND session = p_session AND kind = 'COURSE' AND state = 'PAID') THEN
        RETURN NULL;
    END IF;
    SELECT programme_code INTO v_prog FROM people.student WHERE id = p_student;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = 3 FOR UPDATE;
    IF NOT FOUND THEN
        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status)
        SELECT gen_random_uuid(), s.id, p_session, 3, s.current_level, 'DRAFT' FROM people.student s WHERE s.id = p_student
        RETURNING * INTO r;
    END IF;
    FOR c IN SELECT ch.course_code FROM registration.summer_charge ch
              WHERE ch.student_id = p_student AND ch.session = p_session AND ch.kind = 'COURSE' AND ch.state = 'PAID'
                AND NOT EXISTS (SELECT 1 FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id
                                 WHERE e.registration_id = r.id AND o.course_code = ch.course_code AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))
    LOOP
        BEGIN
            v_off := NULL;
            SELECT o.id INTO v_off FROM catalogue.offering o
             WHERE o.course_code = c.course_code AND o.session = p_session AND o.semester = 3 AND o.stream = 'REGULAR' LIMIT 1;
            IF v_off IS NULL THEN v_off := catalogue.open_class(c.course_code, p_session, 3, 'REGULAR'); END IF;
            INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
            VALUES (r.id, v_off, coalesce(catalogue.units_for(c.course_code, v_prog, r.level), (SELECT k.units FROM catalogue.course k WHERE k.code = c.course_code)),
                    'CARRYOVER', CASE WHEN r.status IN ('APPROVED', 'LOCKED') THEN 'APPROVED' ELSE 'REGISTERED' END)
            ON CONFLICT (registration_id, offering_id) DO UPDATE SET status = EXCLUDED.status;
            v_new := true;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
            INSERT INTO registration.summer_issue (student_id, session, course_code, error) VALUES (p_student, p_session, c.course_code, v_err);
        END;
    END LOOP;
    IF r.status IN ('DRAFT', 'RETURNED', 'SUBMITTED')
       AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')) THEN
        UPDATE registration.course_registration SET status = 'APPROVED', submitted_at = coalesce(submitted_at, now()), approved_at = now(),
               approved_by = NULL, approval_mode = 'AUTO'
         WHERE id = r.id;
        UPDATE registration.entry SET status = 'APPROVED' WHERE registration_id = r.id AND status = 'REGISTERED';
    END IF;
    IF v_new THEN
        SELECT count(*), coalesce(sum(e.units), 0) INTO v_n, v_units FROM registration.entry e WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN');
        PERFORM platform.tell_student(p_student, 'SUMMER_REGISTERED', NULL,
            jsonb_build_object('SESSION', p_session, 'COURSES', v_n, 'UNITS', v_units),
            'SUMMER_REGISTERED:' || r.id || ':' || v_n);
    END IF;
    RETURN r.id;
END $$;

/* a Summer reference confirmed (any lane — the gateways, PayDirect, a Bursary confirmation — all end in finance.confirm_payment). The
   money pays, in order: the charges it was drawn for still owed; those it was drawn for and taken back since, where nothing stands in
   their place and the course is still outstanding; the student's other charges of the Summer still owed (the programme fee first, a
   course never before it), each in whole; what is left stands as a Summer credit. The other open references are closed and the
   registration follows; a registration that fails is recorded for the desk, and never undoes the payment. */
CREATE OR REPLACE FUNCTION registration.summer_reference_confirmed() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_applied numeric := 0; c registration.summer_charge; v_err text;
BEGIN
    IF NEW.student_id IS NULL THEN RETURN NULL; END IF;
    WITH u AS (UPDATE registration.summer_charge ch SET state = 'PAID', paid_at = NEW.confirmed_at, paid_reference_id = NEW.id
                 FROM registration.summer_reference_charge rc
                WHERE rc.reference_id = NEW.id AND rc.charge_id = ch.id AND ch.state = 'DUE'
               RETURNING ch.amount)
    SELECT coalesce(sum(u.amount), 0) INTO v_applied FROM u;
    FOR c IN SELECT ch.* FROM registration.summer_reference_charge rc JOIN registration.summer_charge ch ON ch.id = rc.charge_id
              WHERE rc.reference_id = NEW.id AND ch.state = 'CANCELLED' ORDER BY (ch.kind = 'PROGRAMME') DESC, ch.created_at
    LOOP
        CONTINUE WHEN NEW.amount - v_applied < c.amount;
        CONTINUE WHEN EXISTS (SELECT 1 FROM registration.summer_charge x WHERE x.student_id = c.student_id AND x.session = c.session AND x.kind = c.kind
                                 AND x.course_code IS NOT DISTINCT FROM c.course_code AND x.state <> 'CANCELLED');
        CONTINUE WHEN c.kind = 'COURSE' AND NOT EXISTS (SELECT 1 FROM registration.summer_courses(c.student_id, c.session) sc WHERE sc.course_code = c.course_code);
        CONTINUE WHEN c.kind = 'COURSE' AND NOT EXISTS (SELECT 1 FROM registration.summer_charge y WHERE y.student_id = c.student_id AND y.session = c.session
                                                           AND y.kind = 'PROGRAMME' AND y.state = 'PAID');
        UPDATE registration.summer_charge SET state = 'PAID', paid_at = NEW.confirmed_at, paid_reference_id = NEW.id, cancelled_at = NULL WHERE id = c.id;
        v_applied := v_applied + c.amount;
    END LOOP;
    FOR c IN SELECT x.* FROM registration.summer_charge x WHERE x.student_id = NEW.student_id AND x.session = NEW.session AND x.state = 'DUE'
              ORDER BY (x.kind = 'PROGRAMME') DESC, x.created_at
    LOOP
        EXIT WHEN c.kind = 'COURSE' AND EXISTS (SELECT 1 FROM registration.summer_charge y WHERE y.student_id = NEW.student_id AND y.session = NEW.session
                                                   AND y.kind = 'PROGRAMME' AND y.state = 'DUE');
        CONTINUE WHEN NEW.amount - v_applied < c.amount;
        UPDATE registration.summer_charge SET state = 'PAID', paid_at = NEW.confirmed_at, paid_reference_id = NEW.id WHERE id = c.id;
        v_applied := v_applied + c.amount;
    END LOOP;
    IF NEW.amount - v_applied >= 1 THEN
        INSERT INTO registration.summer_credit (student_id, session, reference_id, amount) VALUES (NEW.student_id, NEW.session, NEW.id, NEW.amount - v_applied);
    END IF;
    PERFORM registration.summer_close_stale_references(NEW.student_id, NEW.session);
    BEGIN
        PERFORM registration.summer_materialize(NEW.student_id, NEW.session);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
        INSERT INTO registration.summer_issue (student_id, session, reference_id, error) VALUES (NEW.student_id, NEW.session, NEW.id, v_err);
    END;
    RETURN NULL;
END $$;

/* the desk retries a Summer registration once what stopped it is put right: the student's open issues of the Summer are resolved and
   the registration made again (a course still refused is recorded again) */
CREATE FUNCTION registration.summer_issue_retry(p_issue uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        i registration.summer_issue; v_left int;
BEGIN
    IF who IS NULL OR v_office IS NULL OR v_office NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'SUMMER_OFFICE: a Summer registration is retried by the Academic Office or the Registry' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO i FROM registration.summer_issue WHERE id = p_issue;
    IF NOT FOUND THEN RAISE EXCEPTION 'SUMMER_ISSUE_UNKNOWN: no such issue' USING ERRCODE = '23514'; END IF;
    UPDATE registration.summer_issue SET resolved_at = now(), resolved_by = who
     WHERE student_id = i.student_id AND session = i.session AND resolved_at IS NULL;
    PERFORM registration.summer_materialize(i.student_id, i.session);
    SELECT count(*) INTO v_left FROM registration.summer_issue WHERE student_id = i.student_id AND session = i.session AND resolved_at IS NULL;
    RETURN jsonb_build_object('student', i.student_id, 'session', i.session, 'stillRefused', v_left);
END $$;

/* what the student's Summer stands at — an open reference only when it may be paid, with its own amount; the unapplied credit */
CREATE OR REPLACE FUNCTION registration.summer_account(p_student uuid, p_session text) RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH ref AS (SELECT r.reference, r.amount FROM finance.payment_reference r
                  WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'Summer semester fees%'
                    AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now()
                    AND registration.summer_reference_payable(r.reference)
                  ORDER BY r.generated_at DESC LIMIT 1)
    SELECT jsonb_build_object(
        'session', p_session,
        'programmeFee', (SELECT c.amount FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'PROGRAMME' AND c.state <> 'CANCELLED' ORDER BY c.created_at DESC LIMIT 1),
        'programmeFeeState', (SELECT c.state FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'PROGRAMME' AND c.state <> 'CANCELLED' ORDER BY c.created_at DESC LIMIT 1),
        'coursesSelected', (SELECT count(*) FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'COURSE' AND c.state = 'DUE'),
        'coursesPaid', (SELECT count(*) FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'COURSE' AND c.state = 'PAID'),
        'courseFeesDue', (SELECT coalesce(sum(c.amount), 0) FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'COURSE' AND c.state = 'DUE'),
        'programmeFeeDue', (SELECT coalesce(sum(c.amount), 0) FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'PROGRAMME' AND c.state = 'DUE'),
        'due', (SELECT coalesce(sum(c.amount), 0) FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.state = 'DUE'),
        'paid', (SELECT coalesce(sum(c.amount), 0) FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.state = 'PAID'),
        'openReference', (SELECT ref.reference FROM ref),
        'openAmount', (SELECT ref.amount FROM ref),
        'credit', (SELECT coalesce(sum(x.amount), 0) FROM registration.summer_credit x WHERE x.student_id = p_student AND x.session = p_session AND x.state = 'OPEN'),
        'registration', (SELECT jsonb_build_object('id', r.id, 'status', r.status, 'approvedAt', r.approved_at,
                                                  'courses', (SELECT count(*) FROM registration.entry e WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')))
                           FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = p_session AND r.semester = 3));
$$;

-- ── 4 · the period, the authorisation, the identification ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.summer_set_period(p_session text, p_state text, p_opens date, p_closes date, p_exams_from date, p_exams_to date,
                                                          p_results_due date, p_categories text[], p_programmes text[], p_levels integer[], p_reason text)
RETURNS registration.summer_period LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        s policy.academic_session; out registration.summer_period;
BEGIN
    IF who IS NULL OR v_office IS NULL OR v_office NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'SUMMER_OFFICE: the Summer Semester is set by the Academic Office or the Registry' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO s FROM policy.academic_session WHERE name = p_session;
    IF s.id IS NULL OR s.state = 'CANCELLED' OR s.merged_into IS NOT NULL THEN
        RAISE EXCEPTION 'SUMMER_SESSION: % is not a session on the calendar that holds classes', p_session USING ERRCODE = '23514';
    END IF;
    INSERT INTO registration.summer_period (session, state, registration_opens, registration_closes, exams_from, exams_to, results_due,
                                            categories, programmes, levels, set_by, set_office, reason)
    VALUES (p_session, coalesce(p_state, 'PLANNED'), p_opens, p_closes, p_exams_from, p_exams_to, p_results_due,
            coalesce(p_categories, ARRAY['FINAL_YEAR', 'SPILLOVER', 'BEYOND_DURATION', 'AUTHORISED']),
            nullif(p_programmes, ARRAY[]::text[]), nullif(p_levels, ARRAY[]::integer[]), who, v_office, nullif(btrim(p_reason), ''))
    ON CONFLICT (session) DO UPDATE SET state = EXCLUDED.state, registration_opens = EXCLUDED.registration_opens,
           registration_closes = EXCLUDED.registration_closes, exams_from = EXCLUDED.exams_from, exams_to = EXCLUDED.exams_to,
           results_due = EXCLUDED.results_due, categories = EXCLUDED.categories, programmes = EXCLUDED.programmes, levels = EXCLUDED.levels,
           set_by = EXCLUDED.set_by, set_office = EXCLUDED.set_office, set_at = now(), reason = EXCLUDED.reason
    RETURNING * INTO out;
    IF p_exams_from IS NOT NULL AND p_exams_to IS NOT NULL THEN
        INSERT INTO assessment.exam_session (id, session, semester, kind, exams_from, exams_to, sheets_due, stream)
        VALUES (gen_random_uuid(), p_session, 3, 'MAIN', p_exams_from, p_exams_to, coalesce(p_results_due, p_exams_to), 'REGULAR')
        ON CONFLICT (session, semester, kind, stream) DO UPDATE SET exams_from = EXCLUDED.exams_from, exams_to = EXCLUDED.exams_to,
               sheets_due = EXCLUDED.sheets_due;
    END IF;
    -- V739: a Summer closed takes back what was selected and not paid, and closes its open references (a payment already on its way
    -- still pays: the confirmation pays a course taken back when it is still outstanding)
    IF out.state = 'CLOSED' THEN
        UPDATE registration.summer_charge SET state = 'CANCELLED', cancelled_at = now() WHERE session = p_session AND state = 'DUE';
        UPDATE finance.payment_reference SET expires_at = now()
         WHERE session = p_session AND purpose LIKE 'Summer semester fees%' AND confirmed_at IS NULL AND archived_at IS NULL AND expires_at > now();
    END IF;
    RETURN out;
END $$;

CREATE OR REPLACE FUNCTION registration.summer_authorise(p_session text, p_student uuid, p_courses text[], p_reason text, p_revoke boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), ''); bad text;
BEGIN
    IF who IS NULL OR v_office IS NULL OR v_office NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'SUMMER_OFFICE: a student is authorised for the Summer Semester by the Academic Office or the Registry' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM registration.summer_period WHERE session = p_session) THEN
        RAISE EXCEPTION 'NO_SUMMER: the Summer Semester of % is not set', p_session USING ERRCODE = '23514';
    END IF;
    IF p_revoke THEN
        UPDATE registration.summer_authorisation SET revoked_at = now(), revoked_by = who WHERE session = p_session AND student_id = p_student AND revoked_at IS NULL;
    ELSE
        IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
            RAISE EXCEPTION 'SUMMER_REASON: an authorisation names its approved academic reason (ten characters or more)' USING ERRCODE = '23514';
        END IF;
        SELECT x INTO bad FROM unnest(coalesce(p_courses, ARRAY[]::text[])) x
         WHERE NOT EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = upper(btrim(x)) AND k.state <> 'ENDED') LIMIT 1;
        IF bad IS NOT NULL THEN
            RAISE EXCEPTION 'SUMMER_COURSE_UNKNOWN: % is not a course taught', bad USING ERRCODE = '23514';
        END IF;
        INSERT INTO registration.summer_authorisation (session, student_id, courses, reason, granted_by, granted_office)
        VALUES (p_session, p_student, (SELECT array_agg(DISTINCT upper(btrim(x))) FROM unnest(p_courses) x WHERE btrim(x) <> ''), btrim(p_reason), who, v_office)
        ON CONFLICT (session, student_id) DO UPDATE SET courses = EXCLUDED.courses, reason = EXCLUDED.reason, granted_by = EXCLUDED.granted_by,
               granted_office = EXCLUDED.granted_office, granted_at = now(), revoked_at = NULL, revoked_by = NULL;
    END IF;
    -- V739: the student re-read at once, whichever way the authorisation went
    INSERT INTO registration.summer_candidate (session, student_id, eligible, category, outstanding, reason, evaluated_at)
    SELECT p_session, p_student, e.eligible, e.category, e.outstanding, e.reason, clock_timestamp() FROM registration.summer_eligibility(p_student, p_session) e
    ON CONFLICT (session, student_id) DO UPDATE SET eligible = EXCLUDED.eligible, category = EXCLUDED.category,
           outstanding = EXCLUDED.outstanding, reason = EXCLUDED.reason, evaluated_at = EXCLUDED.evaluated_at;
END $$;

/* one tranche of the identification: the regular undergraduates who may be candidates (final level, spillover or beyond the length,
   or authorised) and — V739 — every student identified before, not read since p_since, at most p_limit, each read through
   registration.summer_eligibility (one who has left the pool is re-read, and so no longer eligible); answers how many are left */
CREATE OR REPLACE FUNCTION registration.summer_identify(p_session text, p_since timestamptz, p_limit integer) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_done int := 0; v_left int; s record; e record;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM registration.summer_period WHERE session = p_session) THEN
        RAISE EXCEPTION 'NO_SUMMER: the Summer Semester of % is not set', p_session USING ERRCODE = '23514';
    END IF;
    CREATE TEMP TABLE IF NOT EXISTS summer_pool (student_id uuid PRIMARY KEY) ON COMMIT DROP;
    TRUNCATE summer_pool;
    INSERT INTO summer_pool (student_id)
    SELECT st.id FROM people.student st JOIN ref.programme pr ON pr.code = st.programme_code
     WHERE st.status IN ('ACTIVE', 'PROBATION') AND st.entry_mode NOT IN ('CCE', 'POSTGRADUATE') AND pr.category = 'UNDER GRADUATE'
       AND (st.current_level >= coalesce(finance.final_level(st.programme_code), 400)
            OR EXISTS (SELECT 1 FROM people.academic_position ap WHERE ap.student_id = st.id AND (ap.spillover_years > 0 OR ap.spillover_state LIKE 'SPILLOVER%'))
            OR EXISTS (SELECT 1 FROM registration.summer_authorisation a WHERE a.session = p_session AND a.student_id = st.id AND a.revoked_at IS NULL))
    UNION
    SELECT c.student_id FROM registration.summer_candidate c WHERE c.session = p_session;
    DELETE FROM summer_pool sp WHERE EXISTS (SELECT 1 FROM registration.summer_candidate c WHERE c.session = p_session AND c.student_id = sp.student_id AND c.evaluated_at >= p_since);
    FOR s IN SELECT sp.student_id AS id FROM summer_pool sp ORDER BY sp.student_id LIMIT greatest(coalesce(p_limit, 500), 1)
    LOOP
        SELECT * INTO e FROM registration.summer_eligibility(s.id, p_session);
        INSERT INTO registration.summer_candidate (session, student_id, eligible, category, outstanding, reason, evaluated_at)
        VALUES (p_session, s.id, e.eligible, e.category, e.outstanding, e.reason, clock_timestamp())
        ON CONFLICT (session, student_id) DO UPDATE SET eligible = EXCLUDED.eligible, category = EXCLUDED.category,
               outstanding = EXCLUDED.outstanding, reason = EXCLUDED.reason, evaluated_at = EXCLUDED.evaluated_at;
        v_done := v_done + 1;
    END LOOP;
    SELECT count(*) - v_done INTO v_left FROM summer_pool;
    RETURN jsonb_build_object('read', v_done, 'left', greatest(v_left, 0),
                              'eligible', (SELECT count(*) FROM registration.summer_candidate c WHERE c.session = p_session AND c.eligible));
END $$;

-- ── 5 · results, standing and school fees ──────────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE d text;
BEGIN
    -- a Summer result: released by the Summer itself (its courses are registered only once paid), save where the Bursar's scheme lets a
    -- balance owed for an earlier session block everything
    d := pg_get_functiondef('finance.results_cleared(uuid,text,integer)'::regprocedure);
    IF position('    IF p_semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session) THEN
        RETURN NOT EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.state = ''DUE'');
    END IF;' IN d) = 0 THEN
        RAISE EXCEPTION 'V739: finance.results_cleared is not as V735 left it';
    END IF;
    d := replace(d, '    IF p_semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session) THEN
        RETURN NOT EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.state = ''DUE'');
    END IF;',
                    '    -- V739: an unpaid course left selected never withholds the paid ones; the Bursar''s arrears rule holds for the Summer too
    IF p_semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session) THEN
        IF coalesce(v_block, false) AND finance.results_arrears(p_student, p_session) THEN RETURN false; END IF;
        RETURN true;
    END IF;');
    EXECUTE d;

    -- standing: standing_of as before V735; a student's standing is read from their last regular semester
    d := pg_get_functiondef('assessment.standing_of(integer,integer,numeric,numeric,boolean)'::regprocedure);
    IF position('        WHEN p_semester = 3 THEN NULL' IN d) = 0 THEN
        RAISE EXCEPTION 'V739: assessment.standing_of is not as V735 left it';
    END IF;
    d := regexp_replace(d, '\n        -- V735: the Summer Semester \(semester 3\)[^\n]*\n        WHEN p_semester = 3 THEN NULL', '');
    IF position('WHEN p_semester = 3' IN d) > 0 THEN RAISE EXCEPTION 'V739: assessment.standing_of''s Summer branch remains'; END IF;
    EXECUTE d;
    d := pg_get_functiondef('assessment.student_standing(uuid)'::regprocedure);
    IF position('         WHERE g.cgpa IS NOT NULL AND g.published_count > 0 AND g.published_count = g.registered_count' IN d) = 0 THEN
        RAISE EXCEPTION 'V739: assessment.student_standing is not as V422 left it';
    END IF;
    d := replace(d, '         WHERE g.cgpa IS NOT NULL AND g.published_count > 0 AND g.published_count = g.registered_count',
                    '         WHERE g.cgpa IS NOT NULL AND g.published_count > 0 AND g.published_count = g.registered_count
           -- V739: a Summer is no regular semester: the standing stands as the last regular semester left it
           AND NOT (g.semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = g.session))');
    EXECUTE d;

    -- the school fees: a Summer registration is no semester registered for school fees
    d := pg_get_functiondef('finance.reg_semesters(uuid,text)'::regprocedure);
    IF position('             WHERE cr.student_id = p_student AND cr.session = p_session
' IN d) = 0 THEN
        RAISE EXCEPTION 'V739: finance.reg_semesters is not as V697 left it';
    END IF;
    d := replace(d, '             WHERE cr.student_id = p_student AND cr.session = p_session
',
                    '             WHERE cr.student_id = p_student AND cr.session = p_session
               AND NOT (cr.semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session))   -- V739: the Summer
');
    EXECUTE d;
    d := pg_get_functiondef('finance.registrations_without_fees(text)'::regprocedure);
    IF position('         WHERE r.session = p_session AND r.status IN (''SUBMITTED'', ''APPROVED'', ''LOCKED'')),' IN d) = 0 THEN
        RAISE EXCEPTION 'V739: finance.registrations_without_fees is not as V524 left it';
    END IF;
    d := replace(d, '         WHERE r.session = p_session AND r.status IN (''SUBMITTED'', ''APPROVED'', ''LOCKED'')),',
                    '         WHERE r.session = p_session AND r.status IN (''SUBMITTED'', ''APPROVED'', ''LOCKED'')
           AND NOT (r.semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session))),   -- V739: the Summer');
    EXECUTE d;

    -- a Summer payment that pays Summer charges is neither moved by a correction nor archived
    d := pg_get_functiondef('finance.payment_reallocation_check(uuid,text,text,integer,uuid,text)'::regprocedure);
    IF position('    IF r.channel IS DISTINCT FROM ''Legacy'' AND r.purpose ~* ''^(hostel accommodation|transcript)'' THEN' IN d) = 0 THEN
        RAISE EXCEPTION 'V739: finance.payment_reallocation_check is not as V727 left it';
    END IF;
    d := replace(d, '    IF r.channel IS DISTINCT FROM ''Legacy'' AND r.purpose ~* ''^(hostel accommodation|transcript)'' THEN',
                    '    IF EXISTS (SELECT 1 FROM registration.summer_charge x WHERE x.paid_reference_id = r.id AND x.state = ''PAID'') THEN   -- V739
        refusals := refusals || ''REALLOC_LINKED: the payment pays Summer Semester courses that stand registered; it is not moved''::text;
    END IF;
    IF r.channel IS DISTINCT FROM ''Legacy'' AND r.purpose ~* ''^(hostel accommodation|transcript)'' THEN');
    EXECUTE d;
    d := pg_get_functiondef('finance.payment_archive_refusals(uuid)'::regprocedure);
    IF position('    SELECT x.swap_ref INTO v FROM finance.payment_swap x' IN d) = 0 THEN
        RAISE EXCEPTION 'V739: finance.payment_archive_refusals is not as V670 left it';
    END IF;
    d := replace(d, '    SELECT x.swap_ref INTO v FROM finance.payment_swap x',
                    '    IF EXISTS (SELECT 1 FROM registration.summer_charge x WHERE x.paid_reference_id = r.id AND x.state = ''PAID'') THEN   -- V739
        refusals := refusals || ''PAR_LINKED: the payment pays Summer Semester courses that stand registered; the registration is settled first''::text;
    END IF;
    SELECT x.swap_ref INTO v FROM finance.payment_swap x');
    EXECUTE d;
END $$;

COMMIT;
