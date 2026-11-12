-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V735 · The Summer Semester for final-year and spillover students
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's master prompt of 12 November 2026, "INTRODUCTION OF SUMMER SEMESTER FOR FINAL-YEAR AND SPILLOVER STUDENTS":
--  a distinct academic period beside the First and Second Semesters, its own window and dates, in which an eligible student
--  (final year, spillover, beyond the programme's length, or authorised by the Academic Office) registers outstanding courses of
--  BOTH semesters at once, paying a programme fee once (₦50,000 by default) and a fee a course (₦5,000 by default) as the Bursary
--  states and publishes them, through the existing payment gateway, before the registration stands; the classes are taught,
--  examined, scored, approved and published by the existing machinery; a pass clears the carry-over.
--
--  Inspected first (six readers: the calendar, carry-overs, registration and allocation, fees and payment, examinations and
--  results, dashboards and notices; on main and on the late-October copy of live):
--    * A semester is an integer; 3 is accepted almost everywhere but nothing runs in it. Opening a policy.semester row 3 would make
--      it every regular student's current semester (registration.open_semester and about a dozen readers take the highest OPEN
--      semester), count a closed Summer as a missed semester toward voluntary withdrawal, and report it "unstated" for every
--      student's fees. academic_session.semesters is a divisor of programme lengths (2026/2027 on the live copy already holds 3).
--      So the Summer is NOT a policy.semester row and leaves academic_session.semesters alone: it is registration.summer_period,
--      and the registrations, classes, examination session, score sheets and results of the Summer are those of semester 3 of the
--      session, keyed as everything else is by (session, semester) — whose order already makes a Summer pass clear an earlier F.
--    * Outstanding courses are computed, never stored: registration.carryovers (published F or absence, not later passed, not an
--      elective) with each failure's session and semester (registration.carryover_attempts).
--    * School fees are fee_schedule lines summed without a kind filter and payments matched by the purpose 'School fees%': the
--      Summer's fees therefore live apart (finance.summer_fee, registration.summer_charge) and its payments carry the purpose
--      'Summer semester fees …', so no school-fee reader counts them; a charge row a fee component keeps the programme fee and the
--      course fees apart in every report.
--    * The live copy holds 1,103 old-portal Summer payments, each ₦50,000 + ₦5,000 × courses: the University's practice already.
--
--  Not invented (flagged for the Academic Office): academic standing is not pronounced on a Summer alone (assessment.standing_of
--  answers nothing for semester 3); CGPA counts every attempt, as the portal's rule already does (no replacement); the approval
--  of a paid Summer registration is the payment itself (the courses were the student's own outstanding ones, checked here).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V735: the Summer Semester for final-year and spillover students', true);

-- ── 1 · the period ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE registration.summer_period (
    session              text PRIMARY KEY REFERENCES policy.academic_session(name),
    state                text NOT NULL DEFAULT 'PLANNED' CHECK (state IN ('PLANNED', 'OPEN', 'CLOSED')),
    registration_opens   date,
    registration_closes  date,
    exams_from           date,
    exams_to             date,
    results_due          date,
    categories           text[] NOT NULL DEFAULT ARRAY['FINAL_YEAR', 'SPILLOVER', 'BEYOND_DURATION', 'AUTHORISED']
                         CHECK (categories <@ ARRAY['FINAL_YEAR', 'SPILLOVER', 'BEYOND_DURATION', 'AUTHORISED'] AND cardinality(categories) > 0),
    programmes           text[],          -- NULL: every undergraduate programme
    levels               integer[],       -- NULL: every level
    set_by               uuid NOT NULL,
    set_office           text NOT NULL,
    set_at               timestamptz NOT NULL DEFAULT now(),
    reason               text,
    CONSTRAINT ck_summer_registration_dates CHECK (registration_closes IS NULL OR registration_opens IS NULL OR registration_closes >= registration_opens),
    CONSTRAINT ck_summer_exam_dates CHECK (exams_to IS NULL OR exams_from IS NULL OR exams_to >= exams_from),
    CONSTRAINT ck_summer_results_due CHECK (results_due IS NULL OR exams_to IS NULL OR results_due >= exams_to),
    CONSTRAINT ck_summer_open_dated CHECK (state <> 'OPEN' OR (registration_opens IS NOT NULL AND registration_closes IS NOT NULL))
);
COMMENT ON TABLE registration.summer_period IS
  'V735: the Summer Semester of a session — its own state, registration window, examination dates, results deadline, the categories of student it admits and, where the Academic Office restricts it, the programmes and levels. Its registrations, classes, examination session and results are semester 3 of the session; it is not a policy.semester row (no reader of the open semester sees it).';
SELECT audit.attach('registration.summer_period');

/* the Academic Office's own: a student it admits to the Summer for an approved academic reason, and the courses it names, if any */
CREATE TABLE registration.summer_authorisation (
    session        text NOT NULL REFERENCES policy.academic_session(name),
    student_id     uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    courses        text[],            -- courses the authorisation adds beside the student's outstanding ones (not passed), or NULL
    reason         text NOT NULL CHECK (length(btrim(reason)) >= 10),
    granted_by     uuid NOT NULL,
    granted_office text NOT NULL,
    granted_at     timestamptz NOT NULL DEFAULT now(),
    revoked_at     timestamptz,
    revoked_by     uuid,
    PRIMARY KEY (session, student_id)
);
SELECT audit.attach('registration.summer_authorisation');

-- ── 2 · the fees: the Bursary's, stated and published (a draft is never charged) ────────────────────────────────────────────────
CREATE TABLE finance.summer_fee (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session          text NOT NULL REFERENCES policy.academic_session(name),
    programme_code   text REFERENCES ref.programme(code) ON UPDATE CASCADE,   -- NULL: every programme without its own
    programme_fee    numeric(12,2) NOT NULL DEFAULT 50000 CHECK (programme_fee > 0),
    course_fee       numeric(12,2) NOT NULL DEFAULT 5000 CHECK (course_fee > 0),
    effective_from   date NOT NULL DEFAULT current_date,
    state            text NOT NULL DEFAULT 'DRAFT' CHECK (state IN ('DRAFT', 'PUBLISHED', 'WITHDRAWN')),
    reason           text,
    stated_by        uuid NOT NULL,
    stated_office    text NOT NULL,
    stated_at        timestamptz NOT NULL DEFAULT now(),
    published_by     uuid,
    published_office text,
    published_at     timestamptz,
    withdrawn_by     uuid,
    withdrawn_at     timestamptz,
    withdrawn_reason text,
    CONSTRAINT ck_summer_fee_published CHECK (state = 'DRAFT' OR published_at IS NOT NULL),
    CONSTRAINT ck_summer_fee_withdrawn CHECK (state <> 'WITHDRAWN' OR (withdrawn_at IS NOT NULL AND nullif(btrim(withdrawn_reason), '') IS NOT NULL))
);
CREATE INDEX ix_summer_fee_session ON finance.summer_fee (session, programme_code, state, effective_from DESC);
COMMENT ON TABLE finance.summer_fee IS
  'V735: the Summer Semester''s fees as the Bursary states them — a programme fee once a student a Summer and a fee a course — for a session, every programme or one; a DRAFT is never charged; PUBLISHED from its effective date; a published statement is never changed (a new one is stated, and the old withdrawn); a charge keeps the figure it was made at.';
SELECT audit.attach('finance.summer_fee');
-- a programme merged into another (V574): a statement is kept as it was stated for the programme — a published one is never changed;
-- the Bursary states one for the kept programme, and until then its students read the statement for every programme
INSERT INTO ref.programme_reference (tab, col, policy, note)
VALUES ('finance.summer_fee', 'programme_code', 'KEEP', 'history: the Summer Semester fees as stated for the programme (V735); a published statement is never changed')
ON CONFLICT (tab, col) DO NOTHING;

/* a published statement is kept as it was published: only its withdrawal changes it */
CREATE FUNCTION finance.summer_fee_kept() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' AND OLD.state <> 'DRAFT' THEN
        RAISE EXCEPTION 'SUMMER_FEE_KEPT: a published Summer fee is withdrawn, never deleted' USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.state <> 'DRAFT'
       AND (NEW.programme_fee, NEW.course_fee, NEW.effective_from, NEW.session, NEW.programme_code)
           IS DISTINCT FROM (OLD.programme_fee, OLD.course_fee, OLD.effective_from, OLD.session, OLD.programme_code) THEN
        RAISE EXCEPTION 'SUMMER_FEE_KEPT: a published Summer fee is not changed; state a new one and withdraw this' USING ERRCODE = '23514';
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER trg_summer_fee_kept BEFORE UPDATE OR DELETE ON finance.summer_fee FOR EACH ROW EXECUTE FUNCTION finance.summer_fee_kept();

/* the published fee that applies to a student in a session today: the programme's own, else every programme's; the latest in effect */
CREATE FUNCTION finance.summer_fee_for(p_student uuid, p_session text)
RETURNS TABLE(fee_id uuid, programme_fee numeric, course_fee numeric) LANGUAGE sql STABLE AS $$
    SELECT f.id, f.programme_fee, f.course_fee
      FROM finance.summer_fee f JOIN people.student s ON s.id = p_student
     WHERE f.session = p_session AND f.state = 'PUBLISHED' AND f.effective_from <= current_date
       AND (f.programme_code = s.programme_code OR f.programme_code IS NULL)
     ORDER BY (f.programme_code IS NOT NULL) DESC, f.effective_from DESC, f.published_at DESC
     LIMIT 1;
$$;

-- the charges (what a student owes for the Summer) and the references drawn for them
CREATE TABLE registration.summer_charge (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id        uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    session           text NOT NULL REFERENCES policy.academic_session(name),
    kind              text NOT NULL CHECK (kind IN ('PROGRAMME', 'COURSE')),
    course_code       text REFERENCES catalogue.course(code) ON UPDATE CASCADE ON DELETE CASCADE,   -- the go-live reset clears courses
    original_session  text,
    original_semester integer,
    basis             text CHECK (basis IN ('CARRY_OVER', 'AUTHORISED')),
    amount            numeric(12,2) NOT NULL CHECK (amount > 0),
    fee_id            uuid NOT NULL REFERENCES finance.summer_fee(id),
    state             text NOT NULL DEFAULT 'DUE' CHECK (state IN ('DUE', 'PAID', 'CANCELLED')),
    paid_reference_id uuid REFERENCES finance.payment_reference(id) ON DELETE SET NULL,
    paid_at           timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),
    created_by        uuid,
    cancelled_at      timestamptz,
    CONSTRAINT ck_summer_charge_course CHECK ((kind = 'COURSE') = (course_code IS NOT NULL)),
    CONSTRAINT ck_summer_charge_paid CHECK (state <> 'PAID' OR paid_at IS NOT NULL)
);
CREATE UNIQUE INDEX uq_summer_charge_programme ON registration.summer_charge (student_id, session) WHERE kind = 'PROGRAMME' AND state <> 'CANCELLED';
CREATE UNIQUE INDEX uq_summer_charge_course ON registration.summer_charge (student_id, session, course_code) WHERE kind = 'COURSE' AND state <> 'CANCELLED';
CREATE INDEX ix_summer_charge_session ON registration.summer_charge (session, state);
COMMENT ON TABLE registration.summer_charge IS
  'V735: what a student owes for the Summer — the programme fee once a Summer, a course fee a course — each at the figure published when it was made, DUE until paid, PAID by the reference that settled it, CANCELLED when an unpaid selection is taken back. A course added after payment is one more COURSE charge; the programme fee is never charged twice.';
SELECT audit.attach('registration.summer_charge');

CREATE TABLE registration.summer_reference_charge (
    reference_id uuid NOT NULL REFERENCES finance.payment_reference(id) ON DELETE CASCADE,
    charge_id    uuid NOT NULL REFERENCES registration.summer_charge(id) ON DELETE CASCADE,
    PRIMARY KEY (reference_id, charge_id)
);
CREATE INDEX ix_summer_reference_charge_charge ON registration.summer_reference_charge (charge_id);
SELECT audit.attach('registration.summer_reference_charge');

-- ── 3 · eligibility ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
/* why a student is or is not a Summer candidate of a session: the category (FINAL_YEAR, SPILLOVER, BEYOND_DURATION, AUTHORISED), the
   count of outstanding courses, and — when not eligible — the reason. Never every final-year student: an outstanding course, or the
   Academic Office's authorisation, is needed. */
CREATE FUNCTION registration.summer_eligibility(p_student uuid, p_session text)
RETURNS TABLE(eligible boolean, category text, outstanding integer, reason text) LANGUAGE plpgsql STABLE AS $$
DECLARE s record; p registration.summer_period; a registration.summer_authorisation; v_cat text; v_out int; v_final int; v_beyond boolean;
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
    v_cat := CASE WHEN v_beyond THEN 'BEYOND_DURATION'
                  WHEN finance.is_spillover(p_student) THEN 'SPILLOVER'
                  WHEN s.current_level >= v_final THEN 'FINAL_YEAR' END;
    IF a.student_id IS NOT NULL AND 'AUTHORISED' = ANY (p.categories) THEN
        RETURN QUERY SELECT true, 'AUTHORISED', v_out + coalesce(cardinality(a.courses), 0), NULL::text; RETURN;
    END IF;
    IF p.programmes IS NOT NULL AND NOT (s.programme_code = ANY (p.programmes)) THEN
        RETURN QUERY SELECT false, v_cat, v_out, 'PROGRAMME_NOT_IN_SUMMER'; RETURN;
    END IF;
    IF p.levels IS NOT NULL AND NOT (s.current_level = ANY (p.levels)) THEN
        RETURN QUERY SELECT false, v_cat, v_out, 'LEVEL_NOT_IN_SUMMER'; RETURN;
    END IF;
    IF v_cat IS NULL THEN RETURN QUERY SELECT false, NULL::text, v_out, 'NOT_FINAL_OR_SPILLOVER'; RETURN; END IF;
    IF NOT (v_cat = ANY (p.categories)) THEN RETURN QUERY SELECT false, v_cat, v_out, 'CATEGORY_NOT_IN_SUMMER'; RETURN; END IF;
    IF v_out = 0 THEN RETURN QUERY SELECT false, v_cat, 0, 'NO_OUTSTANDING_COURSE'; RETURN; END IF;
    RETURN QUERY SELECT true, v_cat, v_out, NULL::text;
END $$;
COMMENT ON FUNCTION registration.summer_eligibility(uuid, text) IS
  'V735: a Summer candidate — a regular undergraduate studying (ACTIVE, PROBATION), no approved award, final year (current level at the programme''s final level), spillover (finance.is_spillover) or beyond the programme''s length (academic position spillover years), with at least one outstanding course (registration.carryovers), within the period''s categories, programmes and levels; or authorised by the Academic Office.';

/* the courses a student may register in the Summer: every outstanding course (each with the course's own semester and the session and
   semester of its last failure), and the courses an authorisation names (not passed); each selectable, or why not; the fee a course;
   what is already selected (DUE) or paid (REGISTERED) */
CREATE FUNCTION registration.summer_courses(p_student uuid, p_session text)
RETURNS TABLE(course_code text, title text, units integer, course_semester integer, both_semesters boolean, original_session text,
              original_semester integer, attempts integer, basis text, status text, selectable boolean, reason text, course_fee numeric)
LANGUAGE sql STABLE AS $$
    WITH fee AS (SELECT f.course_fee FROM finance.summer_fee_for(p_student, p_session) f),
    att AS (SELECT a.course_code, a.session, a.semester, row_number() OVER (PARTITION BY a.course_code ORDER BY a.session DESC, a.semester DESC) AS rk
              FROM registration.carryover_attempts(p_student) a),
    owed AS (SELECT c.course_code, c.attempts, x.session AS original_session, x.semester AS original_semester, 'CARRY_OVER'::text AS basis
               FROM registration.carryovers(p_student) c JOIN att x ON x.course_code = c.course_code AND x.rk = 1),
    authd AS (SELECT DISTINCT upper(btrim(code)) AS course_code
                FROM registration.summer_authorisation sa CROSS JOIN LATERAL unnest(coalesce(sa.courses, ARRAY[]::text[])) code
               WHERE sa.session = p_session AND sa.student_id = p_student AND sa.revoked_at IS NULL),
    passed AS (SELECT DISTINCT r.course_code FROM assessment.student_results(p_student) r WHERE r.published AND r.outcome = 'GRADED' AND r.points > 0),
    pool AS (SELECT o.course_code, o.attempts, o.original_session, o.original_semester, o.basis FROM owed o
             UNION ALL
             SELECT au.course_code, 0, NULL::text, NULL::int, 'AUTHORISED' FROM authd au
              WHERE NOT EXISTS (SELECT 1 FROM owed o WHERE o.course_code = au.course_code)),
    ch AS (SELECT c.course_code, c.state FROM registration.summer_charge c
            WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'COURSE' AND c.state <> 'CANCELLED'),
    -- a course whose result in this session is not yet published (taken in the first or second semester, awaiting its result)
    awaited AS (SELECT DISTINCT o.course_code
                  FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id
                  JOIN catalogue.offering o ON o.id = e.offering_id
                 WHERE r.student_id = p_student AND r.session = p_session AND r.semester IN (1, 2)
                   AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED') AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                   AND NOT EXISTS (SELECT 1 FROM assessment.student_results(p_student) x
                                    WHERE x.course_code = o.course_code AND x.session = p_session AND x.semester = r.semester AND x.published))
    SELECT p.course_code, k.title, k.units, k.semester, coalesce(k.both_semesters, false), p.original_session, p.original_semester, p.attempts,
           p.basis,
           CASE WHEN ch.state = 'PAID' THEN 'REGISTERED' WHEN ch.state = 'DUE' THEN 'SELECTED' ELSE 'OUTSTANDING' END,
           ch.state IS NULL AND k.code IS NOT NULL AND k.state <> 'ENDED' AND p.course_code NOT IN (SELECT course_code FROM passed)
               AND p.course_code NOT IN (SELECT course_code FROM awaited),
           CASE WHEN k.code IS NULL THEN 'COURSE_UNKNOWN' WHEN k.state = 'ENDED' THEN 'COURSE_ENDED'
                WHEN p.course_code IN (SELECT course_code FROM passed) THEN 'PASSED'
                WHEN p.course_code IN (SELECT course_code FROM awaited) THEN 'RESULT_AWAITED'
                WHEN ch.state = 'PAID' THEN 'ALREADY_REGISTERED' WHEN ch.state = 'DUE' THEN 'ALREADY_SELECTED' END,
           (SELECT course_fee FROM fee)
      FROM pool p
      LEFT JOIN catalogue.course k ON k.code = p.course_code
      LEFT JOIN ch ON ch.course_code = p.course_code
     ORDER BY coalesce(p.original_session, ''), coalesce(p.original_semester, k.semester), p.course_code;
$$;

-- ── 4 · the charges, their references and the registration they make ──────────────────────────────────────────────────────────

/* the period is open for registration today */
CREATE FUNCTION registration.summer_open(p_session text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT p.state = 'OPEN' AND current_date BETWEEN p.registration_opens AND p.registration_closes
                       FROM registration.summer_period p WHERE p.session = p_session), false);
$$;

/* the open references of a student's Summer that no longer match what is owed — a selection changed after the reference was drawn:
   closed so the bank never takes a figure the portal no longer owes */
CREATE FUNCTION registration.summer_close_stale_references(p_student uuid, p_session text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_due numeric; n int;
BEGIN
    SELECT coalesce(sum(c.amount), 0) INTO v_due FROM registration.summer_charge c
     WHERE c.student_id = p_student AND c.session = p_session AND c.state = 'DUE';
    UPDATE finance.payment_reference r SET expires_at = now()
     WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'Summer semester fees%'
       AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now()
       AND (r.amount <> v_due
            OR EXISTS (SELECT 1 FROM registration.summer_reference_charge rc JOIN registration.summer_charge c ON c.id = rc.charge_id
                        WHERE rc.reference_id = r.id AND c.state <> 'DUE')
            OR EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.state = 'DUE'
                          AND NOT EXISTS (SELECT 1 FROM registration.summer_reference_charge rc WHERE rc.reference_id = r.id AND rc.charge_id = c.id)));
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

/* the student selects courses (adds to what is selected or paid): each must be selectable now; the programme fee is charged once a Summer */
CREATE FUNCTION registration.summer_select(p_student uuid, p_session text, p_courses text[]) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; e record; fee record; c text; x record; n int := 0;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a Summer selection is made by a person' USING ERRCODE = '23514'; END IF;
    PERFORM 1 FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT registration.summer_open(p_session) THEN
        RAISE EXCEPTION 'SUMMER_CLOSED: the Summer Semester of % is not open for registration', p_session USING ERRCODE = '23514',
            HINT = 'The Academic Office opens the Summer Semester and dates its registration window.';
    END IF;
    SELECT * INTO e FROM registration.summer_eligibility(p_student, p_session);
    IF NOT e.eligible THEN
        RAISE EXCEPTION 'SUMMER_NOT_ELIGIBLE: % ', CASE e.reason
            WHEN 'NO_OUTSTANDING_COURSE' THEN 'you have no outstanding course to take in the Summer Semester'
            WHEN 'NOT_FINAL_OR_SPILLOVER' THEN 'the Summer Semester is for final-year and spillover students'
            WHEN 'GRADUATED' THEN 'your award is approved'
            ELSE 'you are not eligible for the Summer Semester (' || coalesce(e.reason, '?') || ')' END USING ERRCODE = '23514',
            HINT = 'The Academic Office may authorise a student for an approved academic reason.';
    END IF;
    SELECT * INTO fee FROM finance.summer_fee_for(p_student, p_session);
    IF fee.fee_id IS NULL THEN
        RAISE EXCEPTION 'SUMMER_FEE_NOT_PUBLISHED: the Bursary has not published the Summer Semester fees of %', p_session USING ERRCODE = '23514';
    END IF;
    IF p_courses IS NULL OR cardinality(p_courses) = 0 THEN
        RAISE EXCEPTION 'SUMMER_NO_COURSE: choose at least one course' USING ERRCODE = '23514';
    END IF;
    FOREACH c IN ARRAY p_courses LOOP
        SELECT * INTO x FROM registration.summer_courses(p_student, p_session) s WHERE s.course_code = upper(btrim(c));
        IF NOT FOUND THEN
            RAISE EXCEPTION 'SUMMER_COURSE_NOT_OUTSTANDING: % is not one of your outstanding courses', c USING ERRCODE = '23514';
        END IF;
        IF NOT x.selectable THEN
            RAISE EXCEPTION 'SUMMER_COURSE_REFUSED: % cannot be registered (%)', x.course_code, lower(replace(x.reason, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        INSERT INTO registration.summer_charge (student_id, session, kind, course_code, original_session, original_semester, basis, amount, fee_id, created_by)
        VALUES (p_student, p_session, 'COURSE', x.course_code, x.original_session, x.original_semester, x.basis, fee.course_fee, fee.fee_id, who);
        n := n + 1;
    END LOOP;
    -- the programme fee, once a Summer: not again when a course is added after it was paid
    INSERT INTO registration.summer_charge (student_id, session, kind, amount, fee_id, created_by)
    SELECT p_student, p_session, 'PROGRAMME', fee.programme_fee, fee.fee_id, who
     WHERE NOT EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session
                         AND c.kind = 'PROGRAMME' AND c.state <> 'CANCELLED');
    PERFORM registration.summer_close_stale_references(p_student, p_session);
    RETURN registration.summer_account(p_student, p_session) || jsonb_build_object('selected', n);
END $$;

/* an unpaid course taken back; with no course left selected or paid, the unpaid programme fee goes with it */
CREATE FUNCTION registration.summer_unselect(p_student uuid, p_session text, p_course text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    PERFORM 1 FROM people.student WHERE id = p_student FOR UPDATE;
    UPDATE registration.summer_charge SET state = 'CANCELLED', cancelled_at = now()
     WHERE student_id = p_student AND session = p_session AND kind = 'COURSE' AND course_code = upper(btrim(p_course)) AND state = 'DUE';
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n = 0 THEN
        RAISE EXCEPTION 'SUMMER_NOT_SELECTED: % is not a selected, unpaid course of your Summer Semester', p_course USING ERRCODE = '23514',
            HINT = 'A paid course stays registered; the University refunds no Summer fee without its approved policy.';
    END IF;
    UPDATE registration.summer_charge SET state = 'CANCELLED', cancelled_at = now()
     WHERE student_id = p_student AND session = p_session AND kind = 'PROGRAMME' AND state = 'DUE'
       AND NOT EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session
                         AND c.kind = 'COURSE' AND c.state IN ('DUE', 'PAID'));
    PERFORM registration.summer_close_stale_references(p_student, p_session);
    RETURN registration.summer_account(p_student, p_session);
END $$;

/* what the student's Summer stands at: the charges by kind, due and paid, the open reference, the registration */
CREATE FUNCTION registration.summer_account(p_student uuid, p_session text) RETURNS jsonb LANGUAGE sql STABLE AS $$
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
        'openReference', (SELECT r.reference FROM finance.payment_reference r WHERE r.student_id = p_student AND r.session = p_session
                            AND r.purpose LIKE 'Summer semester fees%' AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now()
                          ORDER BY r.generated_at DESC LIMIT 1),
        'registration', (SELECT jsonb_build_object('id', r.id, 'status', r.status, 'approvedAt', r.approved_at,
                                                  'courses', (SELECT count(*) FROM registration.entry e WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')))
                           FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = p_session AND r.semester = 3));
$$;

/* the reference for everything owed (the programme fee if unpaid, and every selected course): the open one for exactly that again,
   else a new one, the stale ones closed */
CREATE FUNCTION registration.summer_reference(p_student uuid, p_session text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_due numeric; v_ref text; v_id uuid; v_courses int; v_prog boolean;
BEGIN
    PERFORM 1 FROM people.student WHERE id = p_student FOR UPDATE;
    -- paid while registration is open: a reference is never drawn for a Summer whose window has closed
    IF NOT registration.summer_open(p_session) THEN
        RAISE EXCEPTION 'SUMMER_CLOSED: registration for the Summer Semester of % is not open', p_session USING ERRCODE = '23514';
    END IF;
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

/* the registration a paid Summer makes: semester 3 of the session, every paid course in its Summer class (opened when first needed),
   approved by the payment itself; a course paid later joins it. Idempotent. */
CREATE FUNCTION registration.summer_materialize(p_student uuid, p_session text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; c record; v_off uuid; v_new boolean := false; v_units int; v_n int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM registration.summer_charge WHERE student_id = p_student AND session = p_session AND kind = 'COURSE' AND state = 'PAID') THEN
        RETURN NULL;
    END IF;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = 3 FOR UPDATE;
    IF NOT FOUND THEN
        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status)
        SELECT gen_random_uuid(), s.id, p_session, 3, s.current_level, 'DRAFT' FROM people.student s WHERE s.id = p_student
        RETURNING * INTO r;
    END IF;
    FOR c IN SELECT ch.course_code, k.units FROM registration.summer_charge ch JOIN catalogue.course k ON k.code = ch.course_code
              WHERE ch.student_id = p_student AND ch.session = p_session AND ch.kind = 'COURSE' AND ch.state = 'PAID'
                AND NOT EXISTS (SELECT 1 FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id
                                 WHERE e.registration_id = r.id AND o.course_code = ch.course_code AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))
    LOOP
        v_off := catalogue.open_class(c.course_code, p_session, 3, 'REGULAR');
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
        VALUES (r.id, v_off, c.units, 'CARRYOVER', CASE WHEN r.status IN ('APPROVED', 'LOCKED') THEN 'APPROVED' ELSE 'REGISTERED' END)
        ON CONFLICT (registration_id, offering_id) DO UPDATE SET status = EXCLUDED.status;
        v_new := true;
    END LOOP;
    IF r.status IN ('DRAFT', 'RETURNED', 'SUBMITTED') THEN
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

/* a Summer reference confirmed (any lane: the gateways, PayDirect, a Bursary confirmation — they all end in finance.confirm_payment):
   the charges it was drawn for are paid, and the registration follows. A charge already paid by another reference is left as it is. */
CREATE FUNCTION registration.summer_reference_confirmed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE registration.summer_charge c SET state = 'PAID', paid_at = NEW.confirmed_at, paid_reference_id = NEW.id
      FROM registration.summer_reference_charge rc
     WHERE rc.reference_id = NEW.id AND rc.charge_id = c.id AND c.state = 'DUE';
    IF NEW.student_id IS NOT NULL THEN
        PERFORM registration.summer_materialize(NEW.student_id, NEW.session);
    END IF;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_summer_reference_confirmed AFTER UPDATE OF confirmed_at ON finance.payment_reference
    FOR EACH ROW WHEN (OLD.confirmed_at IS NULL AND NEW.confirmed_at IS NOT NULL AND NEW.purpose LIKE 'Summer semester fees%')
    EXECUTE FUNCTION registration.summer_reference_confirmed();

/* whether a Summer reference may be taken to a gateway or paid at the bank now: unpaid, unexpired, the Summer open, and exactly what is
   owed — every charge it was drawn for still owed, no charge owed that it was not drawn for, its amount theirs. A reference for another
   figure (a selection changed since) is never paid: the charges it would pay are paid by the one drawn for what is owed now. */
CREATE FUNCTION registration.summer_reference_payable(p_reference text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((
        SELECT r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now() AND r.student_id IS NOT NULL
               AND registration.summer_open(r.session)
               AND EXISTS (SELECT 1 FROM registration.summer_reference_charge rc WHERE rc.reference_id = r.id)
               AND NOT EXISTS (SELECT 1 FROM registration.summer_reference_charge rc JOIN registration.summer_charge c ON c.id = rc.charge_id
                                WHERE rc.reference_id = r.id AND c.state <> 'DUE')
               AND NOT EXISTS (SELECT 1 FROM registration.summer_charge c
                                WHERE c.student_id = r.student_id AND c.session = r.session AND c.state = 'DUE'
                                  AND NOT EXISTS (SELECT 1 FROM registration.summer_reference_charge rc WHERE rc.reference_id = r.id AND rc.charge_id = c.id))
               AND r.amount = (SELECT sum(c.amount) FROM registration.summer_reference_charge rc JOIN registration.summer_charge c ON c.id = rc.charge_id
                                WHERE rc.reference_id = r.id)
          FROM finance.payment_reference r
         WHERE r.reference = upper(btrim(coalesce(p_reference, ''))) AND r.purpose LIKE 'Summer semester fees%'), false);
$$;
COMMENT ON FUNCTION registration.summer_reference_payable(text) IS
  'V735: a Summer reference is paid (checkout, Quickteller, PayDirect validation) only while the Summer is open and it is exactly for what is owed now.';

-- ── 5 · the Academic Office's acts ──────────────────────────────────────────────────────────────────────────────────────────────
/* the period stated or changed (its examination session made or dated with it) */
CREATE FUNCTION registration.summer_set_period(p_session text, p_state text, p_opens date, p_closes date, p_exams_from date, p_exams_to date,
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
    -- the Summer's examination session (semester 3, MAIN, full-time), dated with the period; the existing desk opens it and releases sheets
    IF p_exams_from IS NOT NULL AND p_exams_to IS NOT NULL THEN
        INSERT INTO assessment.exam_session (id, session, semester, kind, exams_from, exams_to, sheets_due, stream)
        VALUES (gen_random_uuid(), p_session, 3, 'MAIN', p_exams_from, p_exams_to, coalesce(p_results_due, p_exams_to), 'REGULAR')
        ON CONFLICT (session, semester, kind, stream) DO UPDATE SET exams_from = EXCLUDED.exams_from, exams_to = EXCLUDED.exams_to,
               sheets_due = EXCLUDED.sheets_due;
    END IF;
    RETURN out;
END $$;

CREATE FUNCTION registration.summer_authorise(p_session text, p_student uuid, p_courses text[], p_reason text, p_revoke boolean DEFAULT false)
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
        RETURN;
    END IF;
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
END $$;

-- the candidates identified — the eligible list the desks read, refreshed in tranches (an eligibility reads every result of a student)
CREATE TABLE registration.summer_candidate (
    session      text NOT NULL REFERENCES policy.academic_session(name),
    student_id   uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    eligible     boolean NOT NULL,
    category     text,
    outstanding  integer NOT NULL DEFAULT 0,
    reason       text,
    evaluated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (session, student_id)
);
SELECT audit.attach('registration.summer_candidate');

/* one tranche of the identification: the regular undergraduates who may be candidates (final level, spillover or beyond the length,
   or authorised) not read since p_since, at most p_limit, each read through registration.summer_eligibility; answers how many are
   left to read */
CREATE FUNCTION registration.summer_identify(p_session text, p_since timestamptz, p_limit integer) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_done int := 0; v_left int; s record; e record;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM registration.summer_period WHERE session = p_session) THEN
        RAISE EXCEPTION 'NO_SUMMER: the Summer Semester of % is not set', p_session USING ERRCODE = '23514';
    END IF;
    FOR s IN
        SELECT st.id FROM people.student st JOIN ref.programme pr ON pr.code = st.programme_code
         WHERE st.status IN ('ACTIVE', 'PROBATION') AND st.entry_mode NOT IN ('CCE', 'POSTGRADUATE') AND pr.category = 'UNDER GRADUATE'
           AND (st.current_level >= coalesce(finance.final_level(st.programme_code), 400)
                OR EXISTS (SELECT 1 FROM people.academic_position ap WHERE ap.student_id = st.id AND (ap.spillover_years > 0 OR ap.spillover_state LIKE 'SPILLOVER%'))
                OR EXISTS (SELECT 1 FROM registration.summer_authorisation a WHERE a.session = p_session AND a.student_id = st.id AND a.revoked_at IS NULL))
           AND NOT EXISTS (SELECT 1 FROM registration.summer_candidate c WHERE c.session = p_session AND c.student_id = st.id AND c.evaluated_at >= p_since)
         ORDER BY st.id
         LIMIT greatest(coalesce(p_limit, 500), 1)
    LOOP
        SELECT * INTO e FROM registration.summer_eligibility(s.id, p_session);
        INSERT INTO registration.summer_candidate (session, student_id, eligible, category, outstanding, reason, evaluated_at)
        VALUES (p_session, s.id, e.eligible, e.category, e.outstanding, e.reason, clock_timestamp())
        ON CONFLICT (session, student_id) DO UPDATE SET eligible = EXCLUDED.eligible, category = EXCLUDED.category,
               outstanding = EXCLUDED.outstanding, reason = EXCLUDED.reason, evaluated_at = EXCLUDED.evaluated_at;
        v_done := v_done + 1;
    END LOOP;
    SELECT count(*) INTO v_left FROM people.student st JOIN ref.programme pr ON pr.code = st.programme_code
     WHERE st.status IN ('ACTIVE', 'PROBATION') AND st.entry_mode NOT IN ('CCE', 'POSTGRADUATE') AND pr.category = 'UNDER GRADUATE'
       AND (st.current_level >= coalesce(finance.final_level(st.programme_code), 400)
            OR EXISTS (SELECT 1 FROM people.academic_position ap WHERE ap.student_id = st.id AND (ap.spillover_years > 0 OR ap.spillover_state LIKE 'SPILLOVER%'))
            OR EXISTS (SELECT 1 FROM registration.summer_authorisation a WHERE a.session = p_session AND a.student_id = st.id AND a.revoked_at IS NULL))
       AND NOT EXISTS (SELECT 1 FROM registration.summer_candidate c WHERE c.session = p_session AND c.student_id = st.id AND c.evaluated_at >= p_since);
    RETURN jsonb_build_object('read', v_done, 'left', v_left,
                              'eligible', (SELECT count(*) FROM registration.summer_candidate c WHERE c.session = p_session AND c.eligible));
END $$;

/* every student of the Summer the desks and reports read: the eligible (as last identified) and everyone with a charge or a
   registration, with the unit, the category, what is selected, owed and paid by kind, the registration and the results */
CREATE FUNCTION registration.summer_students(p_session text)
RETURNS TABLE(student_id uuid, matric_no text, name text, programme_code text, programme text, dept_code text, department text,
              faculty_code text, faculty text, level integer, eligible boolean, category text, outstanding integer, reason text,
              courses_selected integer, courses_paid integer, programme_fee_due numeric, programme_fee_paid numeric,
              course_fees_due numeric, course_fees_paid numeric, payment_state text, registration_status text,
              courses_registered integer, results_published integer, results_passed integer, results_failed integer, cleared_all boolean)
LANGUAGE sql STABLE AS $$
    WITH ppl AS (
        SELECT c.student_id FROM registration.summer_candidate c WHERE c.session = p_session AND c.eligible
        UNION SELECT ch.student_id FROM registration.summer_charge ch WHERE ch.session = p_session AND ch.state <> 'CANCELLED'),
    ch AS (SELECT ch.student_id,
                  count(*) FILTER (WHERE ch.kind = 'COURSE' AND ch.state = 'DUE')::int AS sel,
                  count(*) FILTER (WHERE ch.kind = 'COURSE' AND ch.state = 'PAID')::int AS paid_n,
                  coalesce(sum(ch.amount) FILTER (WHERE ch.kind = 'PROGRAMME' AND ch.state = 'DUE'), 0) AS pf_due,
                  coalesce(sum(ch.amount) FILTER (WHERE ch.kind = 'PROGRAMME' AND ch.state = 'PAID'), 0) AS pf_paid,
                  coalesce(sum(ch.amount) FILTER (WHERE ch.kind = 'COURSE' AND ch.state = 'DUE'), 0) AS cf_due,
                  coalesce(sum(ch.amount) FILTER (WHERE ch.kind = 'COURSE' AND ch.state = 'PAID'), 0) AS cf_paid
             FROM registration.summer_charge ch WHERE ch.session = p_session AND ch.state <> 'CANCELLED' GROUP BY ch.student_id),
    reg AS (SELECT r.student_id, r.status, r.id,
                   (SELECT count(*) FROM registration.entry e WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))::int AS n
              FROM registration.course_registration r WHERE r.session = p_session AND r.semester = 3),
    res AS (SELECT r.student_id,
                   count(*) FILTER (WHERE m.published)::int AS pub,
                   count(*) FILTER (WHERE m.published AND m.outcome = 'GRADED' AND m.points > 0)::int AS pass,
                   count(*) FILTER (WHERE m.published AND ((m.outcome = 'GRADED' AND m.points = 0) OR m.outcome = 'ABSENT'))::int AS fail
              FROM reg r CROSS JOIN LATERAL assessment.student_results(r.student_id) m
             WHERE m.session = p_session AND m.semester = 3
             GROUP BY r.student_id)
    SELECT s.id, s.matric_no, s.surname || ', ' || s.other_names, s.programme_code, pr.name, d.code, d.name, f.code, f.name, s.current_level,
           coalesce(c.eligible, false), c.category, coalesce(c.outstanding, 0), c.reason,
           coalesce(ch.sel, 0), coalesce(ch.paid_n, 0), coalesce(ch.pf_due, 0), coalesce(ch.pf_paid, 0), coalesce(ch.cf_due, 0), coalesce(ch.cf_paid, 0),
           CASE WHEN ch.student_id IS NULL THEN 'NOT_STARTED'
                WHEN ch.pf_due + ch.cf_due > 0 AND ch.pf_paid + ch.cf_paid > 0 THEN 'PART_PAID'
                WHEN ch.pf_due + ch.cf_due > 0 THEN 'UNPAID' ELSE 'PAID' END,
           reg.status, coalesce(reg.n, 0), coalesce(res.pub, 0), coalesce(res.pass, 0), coalesce(res.fail, 0),
           reg.id IS NOT NULL AND coalesce(res.pub, 0) > 0 AND NOT EXISTS (SELECT 1 FROM registration.carryovers(s.id))
      FROM ppl
      JOIN people.student s ON s.id = ppl.student_id
      LEFT JOIN ref.programme pr ON pr.code = s.programme_code
      LEFT JOIN ref.department d ON d.code = pr.dept_code
      LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, pr.faculty_code)
      LEFT JOIN registration.summer_candidate c ON c.session = p_session AND c.student_id = s.id
      LEFT JOIN ch ON ch.student_id = s.id
      LEFT JOIN reg ON reg.student_id = s.id
      LEFT JOIN res ON res.student_id = s.id
     ORDER BY f.name, d.name, pr.name, s.current_level, s.surname;
$$;

/* whether the Summer Semester page is in a student's menu (read on every screen, so cheap): a Summer set and not closed for which they
   were identified eligible, are authorised, have a charge, or stand where the Summer is for (an undergraduate at or past the final
   level, or in a spillover) — the page says why when they are not eligible after all; or a Summer they registered for */
CREATE FUNCTION registration.summer_area(p_student uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = p_student AND r.semester = 3)
        OR EXISTS (
            SELECT 1 FROM registration.summer_period p
             WHERE p.state IN ('PLANNED', 'OPEN')
               AND (EXISTS (SELECT 1 FROM registration.summer_candidate c WHERE c.session = p.session AND c.student_id = p_student AND c.eligible)
                    OR EXISTS (SELECT 1 FROM registration.summer_authorisation a WHERE a.session = p.session AND a.student_id = p_student AND a.revoked_at IS NULL)
                    OR EXISTS (SELECT 1 FROM registration.summer_charge ch WHERE ch.session = p.session AND ch.student_id = p_student)
                    OR EXISTS (SELECT 1 FROM people.student st JOIN ref.programme pr ON pr.code = st.programme_code
                                WHERE st.id = p_student AND st.status IN ('ACTIVE', 'PROBATION') AND pr.category = 'UNDER GRADUATE'
                                  AND st.entry_mode NOT IN ('CCE', 'POSTGRADUATE')
                                  AND (st.current_level >= coalesce(finance.final_level(st.programme_code), 400)
                                       OR EXISTS (SELECT 1 FROM people.academic_position ap WHERE ap.student_id = st.id
                                                     AND (ap.spillover_years > 0 OR ap.spillover_state LIKE 'SPILLOVER%'))))));
$$;

-- ── 6 · the existing machinery taught the Summer ────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE d text;
BEGIN
    -- a class of the Summer: any course may run in semester 3 of a session with a Summer Semester (its students' outstanding courses)
    d := pg_get_functiondef('catalogue.open_class(text,text,integer,text)'::regprocedure);
    IF position('    IF NOT catalogue.runs_in(c.semester, c.both_semesters, p_semester) THEN' IN d) = 0 THEN
        RAISE EXCEPTION 'V735: catalogue.open_class is not as V443 left it';
    END IF;
    d := replace(d, '    IF NOT catalogue.runs_in(c.semester, c.both_semesters, p_semester) THEN',
                    '    IF NOT catalogue.runs_in(c.semester, c.both_semesters, p_semester)
       AND NOT (p_semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = btrim(coalesce(p_session, ''''))))   -- V735: the Summer runs any course
       THEN');
    EXECUTE d;

    -- a course of both semesters registered once a session: the Summer is the session's second chance at it, not a second registration
    d := pg_get_functiondef('registration.entry_once_a_session()'::regprocedure);
    IF position('    IF NOT coalesce(v_both, false) THEN RETURN NEW; END IF;' IN d) = 0 THEN
        RAISE EXCEPTION 'V735: registration.entry_once_a_session is not as V386 left it';
    END IF;
    d := replace(d, '    IF NOT coalesce(v_both, false) THEN RETURN NEW; END IF;',
                    '    IF NOT coalesce(v_both, false) OR v_semester = 3 THEN RETURN NEW; END IF;   -- V735: a Summer registration repeats a course of the session');
    EXECUTE d;

    -- the registration gate: semester 3 is the Summer Semester's, registered on its own page (selected, paid, then registered)
    d := pg_get_functiondef('registration.registration_gate(uuid,text,integer)'::regprocedure);
    IF position('             WHEN st.entry_mode = ''CCE'' THEN registration.cce_gate(p_student, p_session, p_semester)' IN d) = 0 THEN
        RAISE EXCEPTION 'V735: registration.registration_gate is not as V733 left it';
    END IF;
    d := replace(d, '             WHEN st.entry_mode = ''CCE'' THEN registration.cce_gate(p_student, p_session, p_semester)',
                    '             -- V735: the Summer Semester is registered on its own page: the outstanding courses selected, paid for, then registered
             WHEN p_semester = 3 AND st.entry_mode NOT IN (''CCE'', ''POSTGRADUATE'')
                  AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session)
                  THEN ''The Summer Semester of '' || p_session || '' is registered on the Summer Semester page.''
             WHEN st.entry_mode = ''CCE'' THEN registration.cce_gate(p_student, p_session, p_semester)');
    EXECUTE d;

    -- results: a Summer result is released when the Summer is paid (nothing of it owed), not by the session's school fees
    d := pg_get_functiondef('finance.results_cleared(uuid,text,integer)'::regprocedure);
    IF position('    IF v_releases = ''NEVER_GATED'' THEN RETURN true; END IF;' IN d) = 0 THEN
        RAISE EXCEPTION 'V735: finance.results_cleared is not as V685 left it';
    END IF;
    d := replace(d, '    IF v_releases = ''NEVER_GATED'' THEN RETURN true; END IF;',
                    '    IF v_releases = ''NEVER_GATED'' THEN RETURN true; END IF;
    -- V735: a Summer Semester result: released once nothing of that Summer is owed
    IF p_semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session) THEN
        RETURN NOT EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.state = ''DUE'');
    END IF;');
    EXECUTE d;

    -- the result exceptions: a Summer mark of a first- or second-semester course is no exception
    d := pg_get_functiondef('assessment.result_exceptions(text,integer,text,text,text,integer)'::regprocedure);
    IF position('FROM rec r WHERE r.has_score AND r.course_semester IS NOT NULL AND NOT catalogue.runs_in(r.course_semester, coalesce(r.both_semesters, false), p_sem)' IN d) = 0 THEN
        RAISE EXCEPTION 'V735: assessment.result_exceptions is not as V702 left it';
    END IF;
    d := replace(d, 'FROM rec r WHERE r.has_score AND r.course_semester IS NOT NULL AND NOT catalogue.runs_in(r.course_semester, coalesce(r.both_semesters, false), p_sem)',
                    'FROM rec r WHERE r.has_score AND r.course_semester IS NOT NULL AND p_sem <> 3 AND NOT catalogue.runs_in(r.course_semester, coalesce(r.both_semesters, false), p_sem)');
    EXECUTE d;

    -- the examination card of a Summer: issued once the Summer is paid (its registration holds only paid courses), not by the
    -- session's school fees; said as the Summer Semester
    d := pg_get_functiondef('registration.exam_card_state(uuid,text,integer)'::regprocedure);
    IF position('    v_paid := registration.exam_card_paid(p_student, p_session);' IN d) = 0
       OR position('CASE p_semester WHEN 1 THEN ''first'' WHEN 2 THEN ''second'' ELSE ''third'' END' IN d) = 0
       OR position('        v_reason := ''Your examination card is issued once your school fees for '' || p_session || '' are paid. A payment made at a bank or on Quickteller shows here once Interswitch reports it.'';' IN d) = 0 THEN
        RAISE EXCEPTION 'V735: registration.exam_card_state is not as V567 left it';
    END IF;
    d := replace(d, 'CASE p_semester WHEN 1 THEN ''first'' WHEN 2 THEN ''second'' ELSE ''third'' END',
                    'CASE WHEN p_semester = 1 THEN ''first'' WHEN p_semester = 2 THEN ''second''
                         WHEN EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session) THEN ''Summer'' ELSE ''third'' END');
    d := replace(d, '    v_paid := registration.exam_card_paid(p_student, p_session);',
                    '    v_paid := CASE WHEN p_semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session)
                   THEN EXISTS (SELECT 1 FROM registration.summer_charge sc WHERE sc.student_id = p_student AND sc.session = p_session AND sc.state = ''PAID'')
                   ELSE registration.exam_card_paid(p_student, p_session) END;   -- V735');
    d := replace(d, '        v_reason := ''Your examination card is issued once your school fees for '' || p_session || '' are paid. A payment made at a bank or on Quickteller shows here once Interswitch reports it.'';',
                    '        v_reason := CASE WHEN p_semester = 3 AND v_sem LIKE ''% Summer semester''   -- V735
                         THEN ''Your examination card is issued once your Summer Semester fees for '' || p_session || '' are paid on the Summer Semester page.''
                         ELSE ''Your examination card is issued once your school fees for '' || p_session || '' are paid. A payment made at a bank or on Quickteller shows here once Interswitch reports it.'' END;');
    IF position('        v_reason := ''You have not registered courses for '' || v_sem || ''. Register your courses, and the examination card is yours once your school fees are paid.'';' IN d) = 0 THEN
        RAISE EXCEPTION 'V735: registration.exam_card_state''s unregistered reason is not as V567 left it';
    END IF;
    d := replace(d, '        v_reason := ''You have not registered courses for '' || v_sem || ''. Register your courses, and the examination card is yours once your school fees are paid.'';',
                    '        v_reason := ''You have not registered courses for '' || v_sem || CASE WHEN p_semester = 3 AND v_sem LIKE ''% Summer semester''   -- V735
                         THEN ''. Select your outstanding courses on the Summer Semester page; paying for them registers them, and the examination card is yours.''
                         ELSE ''. Register your courses, and the examination card is yours once your school fees are paid.'' END;');
    EXECUTE d;

    d := pg_get_functiondef('registration.exam_cards_withheld(text,integer)'::regprocedure);
    IF position('                         WHEN NOT EXISTS (SELECT 1 FROM paid WHERE paid.student_id = r.student_id) THEN ''EXAM_CARD_NOT_PAID'' END AS code' IN d) = 0
       OR position('                       ELSE ''No school-fees payment for the session on record'' END' IN d) = 0 THEN
        RAISE EXCEPTION 'V735: registration.exam_cards_withheld is not as V567 left it';
    END IF;
    d := replace(d, '                         WHEN NOT EXISTS (SELECT 1 FROM paid WHERE paid.student_id = r.student_id) THEN ''EXAM_CARD_NOT_PAID'' END AS code',
                    '                         WHEN r.semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session)   -- V735: the Summer''s own payment
                              THEN CASE WHEN NOT EXISTS (SELECT 1 FROM registration.summer_charge sc
                                                          WHERE sc.student_id = r.student_id AND sc.session = p_session AND sc.state = ''PAID'')
                                        THEN ''EXAM_CARD_NOT_PAID'' END
                         WHEN NOT EXISTS (SELECT 1 FROM paid WHERE paid.student_id = r.student_id) THEN ''EXAM_CARD_NOT_PAID'' END AS code');
    d := replace(d, '                       ELSE ''No school-fees payment for the session on record'' END',
                    '                       ELSE CASE WHEN k.semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session)
                                 THEN ''No Summer Semester payment on record'' ELSE ''No school-fees payment for the session on record'' END END');
    EXECUTE d;
END $$;

-- academic standing is not pronounced on a Summer alone (no approved rule; flagged for the Academic Office)
CREATE OR REPLACE FUNCTION assessment.standing_of(p_level integer, p_semester integer, p_cgpa numeric, p_prev_cgpa numeric, p_de_at_200 boolean)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    WITH t AS (SELECT policy.probation_below_cgpa() AS below)
    SELECT CASE
        WHEN p_cgpa IS NULL OR p_cgpa >= t.below THEN NULL
        -- V735: the Summer Semester (semester 3): no standing is pronounced on it alone — no rule of the University's says it
        WHEN p_semester = 3 THEN NULL
        -- a first semester: the probation list, from 200 level, never a Direct Entry student's 200 level
        WHEN p_semester = 1 THEN CASE WHEN p_level >= 200 AND NOT coalesce(p_de_at_200, false) THEN 'PROBATION' END
        -- a second semester: still under the threshold after that level's probation list is advice to withdraw;
        -- otherwise (100 level, a fresh fall, a Direct Entry student's 200 level) probation
        WHEN p_level >= 200 AND NOT coalesce(p_de_at_200, false) AND p_prev_cgpa IS NOT NULL AND p_prev_cgpa < t.below THEN 'ADVISED_TO_WITHDRAW'
        ELSE 'PROBATION'
    END
      FROM t
$function$;

DO $$
DECLARE d text;
BEGIN
    -- an expired Summer reference regenerated (Fees & payments, the payment button): the reference for what is owed now — the one open
    -- for it, or a new one — never the old figure reopened; nothing owed, or the Summer closed, is said so
    d := pg_get_functiondef('finance.renew_reference(uuid,text)'::regprocedure);
    IF position('    ELSIF r.purpose LIKE ''Inter-departmental transfer%'' THEN' IN d) = 0 THEN
        RAISE EXCEPTION 'V735: finance.renew_reference is not as V727 left it';
    END IF;
    d := replace(d, '    ELSIF r.purpose LIKE ''Inter-departmental transfer%'' THEN',
                    '    ELSIF r.purpose LIKE ''Summer semester fees%'' THEN
        -- V735: the reference for what the Summer is owed now (registration.summer_reference refuses a closed Summer and nothing owed)
        BEGIN
            v_new := registration.summer_reference(p_student, r.session);
        EXCEPTION WHEN check_violation THEN
            IF SQLERRM LIKE ''SUMMER_NOTHING_DUE%'' THEN
                RAISE EXCEPTION ''REFERENCE_NOTHING_OWED: nothing is owed for the Summer Semester of %; reference % is not needed'', r.session, r.reference USING ERRCODE = ''23514'';
            END IF;
            RAISE;
        END;
        RETURN QUERY SELECT x.reference, x.amount, x.expires_at, x.purpose, CASE WHEN x.reference = r.reference THEN ''OPEN'' ELSE ''NEW'' END
          FROM finance.payment_reference x WHERE x.reference = v_new;
        RETURN;
    ELSIF r.purpose LIKE ''Inter-departmental transfer%'' THEN');
    EXECUTE d;
END $$;

-- ── 7 · the payments' category: the Summer's own, not "Other" (the old portal's Summer payments read under it too) ──────────────
INSERT INTO finance.payment_purpose (code, label, ord, gl_account) VALUES ('SUMMER_SEMESTER', 'Summer Semester fees', 95, '4090')
ON CONFLICT (code) DO NOTHING;
INSERT INTO finance.payment_category (code, label, pattern, ord, purpose) VALUES ('SUMMER_SEMESTER', 'Summer Semester fees', '^summer semester', 92, 'SUMMER_SEMESTER')
ON CONFLICT (code) DO NOTHING;

-- ── 8 · the notices ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority)
VALUES
 ('SUMMER_OPEN', 'Summer Semester open', 'To an eligible student when the Academic Office announces the Summer Semester (V735)',
  'The Summer Semester of [SESSION] is open',
  E'Dear [FIRST_NAME],\n\nThe Summer Semester of [SESSION] is open for registration from [OPENS] to [CLOSES]. You have [OUTSTANDING] outstanding course(s) you may register in it, from the first and the second semester together.\n\nSign in, open Summer Semester, select your courses and pay the Summer fees; your registration stands once they are paid.\n\n[PORTAL_URL]\n\n[UNIVERSITY_NAME]',
  'MOAUM: the Summer Semester of [SESSION] is open, [OPENS] to [CLOSES]. You may register your outstanding courses on the portal.',
  'Summer Semester open', 'The Summer Semester of [SESSION] is open from [OPENS] to [CLOSES]: register your outstanding courses on the Summer Semester page.',
  ARRAY['FIRST_NAME', 'SESSION', 'OPENS', 'CLOSES', 'OUTSTANDING', 'PORTAL_URL', 'UNIVERSITY_NAME'], true, 'NORMAL'),
 ('SUMMER_CLOSING', 'Summer Semester closing', 'To an eligible student who has not completed the Summer registration, before it closes (V735)',
  'The Summer Semester registration of [SESSION] closes on [CLOSES]',
  E'Dear [FIRST_NAME],\n\nThe Summer Semester registration of [SESSION] closes on [CLOSES]. Your registration stands only once your courses are selected and the Summer fees paid.\n\n[PORTAL_URL]\n\n[UNIVERSITY_NAME]',
  'MOAUM: the Summer Semester registration of [SESSION] closes on [CLOSES]. Select and pay on the portal.',
  'Summer registration closing', 'The Summer Semester registration of [SESSION] closes on [CLOSES].',
  ARRAY['FIRST_NAME', 'SESSION', 'CLOSES', 'PORTAL_URL', 'UNIVERSITY_NAME'], true, 'NORMAL'),
 ('SUMMER_REGISTERED', 'Summer Semester registered', 'To the student when the Summer fees are paid and the courses registered (V735)',
  'Your Summer Semester registration of [SESSION]',
  E'Dear [FIRST_NAME],\n\nYour payment is confirmed and your Summer Semester registration of [SESSION] stands: [COURSES] course(s), [UNITS] credit unit(s). Print your Summer registration from the Summer Semester page.\n\n[PORTAL_URL]\n\n[UNIVERSITY_NAME]',
  'MOAUM: your Summer Semester registration of [SESSION] stands: [COURSES] course(s). Print it on the portal.',
  'Summer registration complete', 'Your Summer Semester registration of [SESSION] stands: [COURSES] course(s), [UNITS] credit unit(s).',
  ARRAY['FIRST_NAME', 'SESSION', 'COURSES', 'UNITS', 'PORTAL_URL', 'UNIVERSITY_NAME'], true, 'NORMAL'),
 ('SUMMER_TIMETABLE', 'Summer Semester examinations', 'To a student registered in the Summer when its examination timetable is published (V735)',
  'The Summer Semester examinations of [SESSION]',
  E'Dear [FIRST_NAME],\n\nThe Summer Semester examinations of [SESSION] hold from [EXAMS_FROM] to [EXAMS_TO]. See the timetable on the portal.\n\n[PORTAL_URL]\n\n[UNIVERSITY_NAME]',
  'MOAUM: Summer Semester examinations of [SESSION]: [EXAMS_FROM] to [EXAMS_TO]. Timetable on the portal.',
  'Summer examinations', 'The Summer Semester examinations of [SESSION] hold from [EXAMS_FROM] to [EXAMS_TO].',
  ARRAY['FIRST_NAME', 'SESSION', 'EXAMS_FROM', 'EXAMS_TO', 'PORTAL_URL', 'UNIVERSITY_NAME'], true, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

COMMIT;
