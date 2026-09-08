-- ═══════════════════════════════════════════════════════════════════════════
-- V027 — the loops the student can now see closed
--
--   · The result query: one mark in one course, within the window that opens
--     when the set is published, routed to the department that owns the
--     course, answered on the record. A query is not an appeal against a
--     grade; a corrected mark goes back through the chain (V013), and the
--     answer here says so.
--   · The examination docket: the papers the approved registration carries
--     in an examination session that is open, with the day, time and venue
--     the Examinations Office timetabled, released only when the scheme
--     says the fees position releases EXAMINATION.
--   · The class timetable and attendance: the slots the department gives an
--     offering, and the register the lecturer marks against the class list.
--   · The identity card: issued by the Library on the matriculation number
--     when the scheme releases ID_CARD, one live card at a time, lost and
--     replaced on the record.
--   · The transcript request by the student, paid against a fee reference
--     like everything else, staged as the Registry's desk already stages it.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── the result query ────────────────────────────────────────────────────
CREATE TABLE assessment.result_query (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref          text NOT NULL UNIQUE,
    student_id   uuid NOT NULL REFERENCES people.student(id),
    sheet_id     uuid NOT NULL REFERENCES assessment.score_sheet(id),
    part         text NOT NULL,
    said         text NOT NULL,
    routed_dept  text NOT NULL REFERENCES ref.department(code),
    raised_at    timestamptz NOT NULL DEFAULT now(),
    state        text NOT NULL DEFAULT 'RAISED',
    answer       text NULL,
    answered_at  timestamptz NULL,
    answered_by  uuid NULL,
    CONSTRAINT ck_query_part CHECK (part IN ('EXAM','CA','ABSENT')),
    CONSTRAINT ck_query_state CHECK (state IN ('RAISED','UPHELD','CORRECTED','CLOSED')),
    CONSTRAINT ck_query_said CHECK (btrim(said) <> ''),
    CONSTRAINT ck_query_answered CHECK (state = 'RAISED' OR (answer IS NOT NULL AND answered_at IS NOT NULL AND answered_by IS NOT NULL)),
    CONSTRAINT ck_query_ref CHECK (ref ~ '^QRY-[0-9]{4}-[0-9]{5}$')
);
CREATE INDEX ix_query_dept ON assessment.result_query (routed_dept) WHERE state = 'RAISED';
CREATE INDEX ix_query_student ON assessment.result_query (student_id);
SELECT audit.attach('assessment.result_query');

-- the window: seven days from publication, which is five working days and a weekend
CREATE OR REPLACE FUNCTION assessment.query_window_open(p_sheet uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT s.stage = 'PUBLISHED' AND s.published_at IS NOT NULL AND s.published_at + interval '7 days' > now()
      FROM assessment.score_sheet s WHERE s.id = p_sheet;
$$;

CREATE OR REPLACE FUNCTION assessment.raise_query(p_student uuid, p_sheet uuid, p_part text, p_said text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v_ref text; v_dept text; v_year text := to_char(current_date, 'YYYY');
BEGIN
    IF NOT EXISTS (SELECT 1 FROM assessment.score s WHERE s.sheet_id = p_sheet AND s.student_id = p_student) THEN
        RAISE EXCEPTION 'no mark of yours is on this sheet' USING ERRCODE = '23514', HINT = 'A query is against one mark in one course you sat.';
    END IF;
    IF NOT assessment.query_window_open(p_sheet) THEN
        RAISE EXCEPTION 'the query window for this course is not open' USING ERRCODE = '23514',
            HINT = 'It opens when the result is published and runs for five working days.';
    END IF;
    IF EXISTS (SELECT 1 FROM assessment.result_query q WHERE q.student_id = p_student AND q.sheet_id = p_sheet AND q.state = 'RAISED') THEN
        RAISE EXCEPTION 'a query on this mark is already open' USING ERRCODE = '23505', HINT = 'The department answers it on the record; you will see the answer here.';
    END IF;
    SELECT c.dept_code INTO v_dept FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id
      JOIN catalogue.course c ON c.code = o.course_code WHERE s.id = p_sheet;
    v_ref := 'QRY-' || v_year || '-' || lpad(platform.next_number('RESULT_QUERY', 'UNIVERSITY', v_year)::text, 5, '0');
    INSERT INTO assessment.result_query (ref, student_id, sheet_id, part, said, routed_dept)
    VALUES (v_ref, p_student, p_sheet, p_part, btrim(p_said), v_dept);
    RETURN v_ref;
END $$;

CREATE OR REPLACE FUNCTION assessment.answer_query(p_query uuid, p_state text, p_answer text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE q assessment.result_query; reach record;
BEGIN
    SELECT * INTO q FROM assessment.result_query WHERE id = p_query;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such query' USING ERRCODE = '23503'; END IF;
    IF q.state <> 'RAISED' THEN RAISE EXCEPTION 'this query was answered on %', q.answered_at::date USING ERRCODE = '23514'; END IF;
    IF p_answer IS NULL OR btrim(p_answer) = '' THEN
        RAISE EXCEPTION 'a query is answered in words' USING ERRCODE = '23514', HINT = 'Say what was checked and what was found; the student reads this.';
    END IF;
    UPDATE assessment.result_query SET state = p_state, answer = btrim(p_answer), answered_at = now(),
           answered_by = nullif(current_setting('moaum.actor_id', true), '')::uuid WHERE id = p_query;
    SELECT * INTO reach FROM people.student_reach(q.student_id);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your result query ' || q.ref || ' is answered',
        'The department has answered your query ' || q.ref || ': ' || CASE p_state WHEN 'UPHELD' THEN 'the mark stands.' WHEN 'CORRECTED' THEN 'the mark is being corrected through the approval chain.' ELSE 'closed.' END
        || ' Sign in to read the answer.', 'student', q.student_id);
    PERFORM platform.queue_notice('SMS', reach.phone, 'Your result query is answered', 'MOAUM: query ' || q.ref || ' answered — ' || lower(p_state) || '. Sign in to read it.', 'student', q.student_id);
    RETURN p_state;
END $$;

-- ── the examination timetable and the docket ────────────────────────────
CREATE TABLE assessment.exam_timetable (
    offering_id uuid PRIMARY KEY REFERENCES catalogue.offering(id),
    held_on     date NOT NULL,
    starts_at   time NOT NULL,
    ends_at     time NOT NULL,
    venue       text NOT NULL,
    CONSTRAINT ck_exam_tt_times CHECK (ends_at > starts_at)
);
SELECT audit.attach('assessment.exam_timetable');

-- the papers an approved registration carries in an open examination session, with the slot where one is timetabled
CREATE OR REPLACE FUNCTION assessment.student_docket(p_student uuid, p_exam_session uuid)
RETURNS TABLE (offering_id uuid, course_code text, title text, units int, held_on date, starts_at time, ends_at time, venue text, sheet_stage text)
LANGUAGE sql STABLE AS $$
    SELECT o.id, c.code, c.title, e.units, t.held_on, t.starts_at, t.ends_at, t.venue, sh.stage
      FROM assessment.exam_session x
      JOIN registration.course_registration r ON r.student_id = p_student AND r.session = x.session AND r.semester = x.semester AND r.status IN ('APPROVED','LOCKED')
      JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED','APPROVED')
      JOIN catalogue.offering o ON o.id = e.offering_id
      JOIN catalogue.course c ON c.code = o.course_code
      LEFT JOIN assessment.score_sheet sh ON sh.offering_id = o.id AND sh.exam_session_id = x.id
      LEFT JOIN assessment.exam_timetable t ON t.offering_id = o.id
     WHERE x.id = p_exam_session
     ORDER BY t.held_on NULLS LAST, t.starts_at NULLS LAST, c.code;
$$;

-- ── the class timetable and the attendance register ─────────────────────
CREATE TABLE catalogue.class_slot (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    offering_id uuid NOT NULL REFERENCES catalogue.offering(id),
    weekday     int  NOT NULL,
    starts_at   time NOT NULL,
    ends_at     time NOT NULL,
    venue       text NOT NULL,
    kind        text NOT NULL DEFAULT 'LECTURE',
    ended_at    timestamptz NULL,
    CONSTRAINT ck_slot_day CHECK (weekday BETWEEN 1 AND 7),
    CONSTRAINT ck_slot_times CHECK (ends_at > starts_at),
    CONSTRAINT ck_slot_kind CHECK (kind IN ('LECTURE','PRACTICAL','TUTORIAL'))
);
CREATE INDEX ix_slot_offering ON catalogue.class_slot (offering_id) WHERE ended_at IS NULL;
SELECT audit.attach('catalogue.class_slot');

CREATE OR REPLACE FUNCTION registration.student_timetable(p_student uuid, p_session text, p_semester int)
RETURNS TABLE (weekday int, starts_at time, ends_at time, course_code text, title text, kind text, venue text, lecturer text, carryover boolean)
LANGUAGE sql STABLE AS $$
    SELECT s.weekday, s.starts_at, s.ends_at, c.code, c.title, s.kind, s.venue, p.surname || ', ' || p.given_names, e.entry_type = 'CARRYOVER'
      FROM registration.course_registration r
      JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED','APPROVED')
      JOIN catalogue.offering o ON o.id = e.offering_id
      JOIN catalogue.course c ON c.code = o.course_code
      JOIN catalogue.class_slot s ON s.offering_id = o.id AND s.ended_at IS NULL
      LEFT JOIN iam.person p ON p.id = o.lecturer_id
     WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester
     ORDER BY s.weekday, s.starts_at, c.code;
$$;

CREATE TABLE registration.attendance (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    offering_id uuid NOT NULL REFERENCES catalogue.offering(id),
    held_on     date NOT NULL,
    student_id  uuid NOT NULL REFERENCES people.student(id),
    present     boolean NOT NULL,
    recorded_by uuid NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_attendance UNIQUE (offering_id, held_on, student_id)
);
CREATE INDEX ix_attendance_student ON registration.attendance (student_id);
SELECT audit.attach('registration.attendance');

-- the register of one class on one day, over the class list and nothing else
CREATE OR REPLACE FUNCTION registration.mark_attendance(p_offering uuid, p_held_on date, p_present uuid[])
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int := 0; r record; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'attendance is recorded by a person' USING ERRCODE = '23514'; END IF;
    FOR r IN SELECT cr.student_id FROM registration.entry e
              JOIN registration.course_registration cr ON cr.id = e.registration_id AND cr.status IN ('APPROVED','LOCKED')
             WHERE e.offering_id = p_offering AND e.status IN ('REGISTERED','APPROVED')
    LOOP
        INSERT INTO registration.attendance (offering_id, held_on, student_id, present, recorded_by)
        VALUES (p_offering, p_held_on, r.student_id, r.student_id = ANY(p_present), who)
        ON CONFLICT (offering_id, held_on, student_id) DO UPDATE SET present = EXCLUDED.present, recorded_by = EXCLUDED.recorded_by, recorded_at = now();
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

CREATE OR REPLACE FUNCTION registration.attendance_rate(p_student uuid, p_session text, p_semester int)
RETURNS TABLE (course_code text, title text, attended int, held int, rate int)
LANGUAGE sql STABLE AS $$
    SELECT c.code, c.title,
           count(*) FILTER (WHERE a.present)::int,
           count(a.id)::int,
           CASE WHEN count(a.id) = 0 THEN NULL ELSE round(100.0 * count(*) FILTER (WHERE a.present) / count(a.id))::int END
      FROM registration.course_registration r
      JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED','APPROVED')
      JOIN catalogue.offering o ON o.id = e.offering_id
      JOIN catalogue.course c ON c.code = o.course_code
      LEFT JOIN registration.attendance a ON a.offering_id = o.id AND a.student_id = p_student
     WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester
     GROUP BY c.code, c.title ORDER BY c.code;
$$;

-- ── the identity card ───────────────────────────────────────────────────
CREATE TABLE credentials.identity_card (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id  uuid NOT NULL REFERENCES people.student(id),
    card_no     text NOT NULL UNIQUE,
    issued_at   timestamptz NOT NULL DEFAULT now(),
    issued_by   uuid NOT NULL,
    valid_to    date NOT NULL,
    state       text NOT NULL DEFAULT 'ISSUED',
    ended_at    timestamptz NULL,
    ended_reason text NULL,
    CONSTRAINT ck_card_state CHECK (state IN ('ISSUED','LOST','REPLACED','RETURNED')),
    CONSTRAINT ck_card_no CHECK (card_no ~ '^MOAUM/ID/[0-9]{2}/[0-9]{5}$'),
    CONSTRAINT ck_card_ended CHECK ((state = 'ISSUED') = (ended_at IS NULL)),
    CONSTRAINT ck_card_reason CHECK (state = 'ISSUED' OR ended_reason IS NOT NULL)
);
CREATE UNIQUE INDEX uq_card_live ON credentials.identity_card (student_id) WHERE state = 'ISSUED';
SELECT audit.attach('credentials.identity_card');

-- issued on the matriculation number when the scheme releases ID_CARD; one live card at a time
CREATE OR REPLACE FUNCTION credentials.issue_identity_card(p_student uuid, p_reason text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE s people.student; v_no text; v_yy text; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; ses text;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
    IF s.matric_no IS NULL THEN
        RAISE EXCEPTION 'an identity card is keyed on the matriculation number, and % has none yet', s.admission_no USING ERRCODE = '23514',
            HINT = 'The card is made after matriculation.';
    END IF;
    SELECT name INTO ses FROM policy.academic_session WHERE state = 'CURRENT';
    IF ses IS NOT NULL AND NOT finance.clears(p_student, ses, 'ID_CARD') THEN
        RAISE EXCEPTION 'the Bursary has not cleared this student for the identity card in %', ses USING ERRCODE = '23514',
            HINT = 'The scheme releases the card at the first instalment.';
    END IF;
    IF who IS NULL THEN RAISE EXCEPTION 'a card is issued by a person' USING ERRCODE = '23514'; END IF;
    UPDATE credentials.identity_card SET state = 'REPLACED', ended_at = now(), ended_reason = coalesce(p_reason, 'replaced')
     WHERE student_id = p_student AND state = 'ISSUED';
    v_yy := to_char(current_date, 'YY');
    v_no := 'MOAUM/ID/' || v_yy || '/' || lpad(platform.next_number('IDENTITY_CARD', 'UNIVERSITY', to_char(current_date, 'YYYY'))::text, 5, '0');
    INSERT INTO credentials.identity_card (student_id, card_no, issued_by, valid_to)
    VALUES (p_student, v_no, who, (current_date + interval '4 years')::date);
    RETURN v_no;
END $$;

CREATE OR REPLACE FUNCTION credentials.report_card_lost(p_student uuid, p_reason text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    UPDATE credentials.identity_card SET state = 'LOST', ended_at = now(), ended_reason = coalesce(nullif(btrim(p_reason), ''), 'reported lost')
     WHERE student_id = p_student AND state = 'ISSUED';
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

-- ── the transcript request by the student ───────────────────────────────
CREATE OR REPLACE FUNCTION credentials.student_transcript_request(p_student uuid, p_destination text, p_destination_name text, p_mode text, p_copies int)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v_year text := to_char(current_date, 'YYYY'); v_ref text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_student AND matric_no IS NOT NULL) THEN
        RAISE EXCEPTION 'a transcript is issued on the matriculation number' USING ERRCODE = '23514';
    END IF;
    v_ref := 'TRN-' || v_year || '-' || lpad(platform.next_number('TRANSCRIPT', 'UNIVERSITY', v_year)::text, 5, '0');
    INSERT INTO credentials.transcript_request (id, ref, student_id, destination, destination_name, mode, express, copies, stage)
    VALUES (gen_random_uuid(), v_ref, p_student, p_destination, nullif(btrim(coalesce(p_destination_name, '')), ''), coalesce(p_mode, 'DIGITAL'), false,
            coalesce(p_copies, 1), 'AWAITING_PAYMENT');
    RETURN v_ref;
END $$;

-- the fee schedule may carry the transcript charge as an item filtered to nobody; the reference names the request
CREATE OR REPLACE FUNCTION finance.transcript_fee(p_session text)
RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT f.amount FROM finance.fee_schedule f WHERE f.session = p_session AND f.ended_at IS NULL AND lower(f.item) LIKE 'transcript%' ORDER BY f.ord LIMIT 1), 5000);
$$;

-- confirming a payment (V026), now also settling a transcript request the reference names
CREATE OR REPLACE FUNCTION finance.confirm_payment(p_reference text, p_channel text, p_note text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE r finance.payment_reference; v_no text; reach record; pos record; v_trn text;
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
    IF r.purpose LIKE 'Transcript TRN-%' THEN
        v_trn := substr(r.purpose, 12, 14);
        UPDATE credentials.transcript_request t SET paid_at = now(),
               stage = CASE WHEN clearance.is_clear(t.student_id, 'TRANSCRIPT') THEN 'READY' ELSE 'HELD_AT_CLEARANCE' END
         WHERE t.ref = v_trn AND t.paid_at IS NULL;
    END IF;
    SELECT * INTO reach FROM people.student_reach(r.student_id);
    SELECT * INTO pos FROM finance.position(r.student_id, r.session);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your payment is confirmed',
        'Your payment of NGN ' || r.amount::text || ' against reference ' || r.reference || ' is confirmed. Receipt ' || v_no || '. '
        || CASE WHEN r.purpose LIKE 'Transcript%' THEN 'Your transcript request is with the Registry.'
                WHEN pos.balance = 0 THEN 'Your charges for ' || r.session || ' are settled in full.'
                ELSE 'NGN ' || pos.balance::text || ' remains for ' || r.session || '.' END
        || ' Sign in to download the receipt.', 'student', r.student_id);
    PERFORM platform.queue_notice('SMS', reach.phone, 'Your payment is confirmed',
        'MOAUM: payment ' || r.reference || ' confirmed, receipt ' || v_no || '.', 'student', r.student_id);
    RETURN 'confirmed';
END $$;

-- the position (V026) counts the session charge's payments only; a transcript paid is not fees paid
CREATE OR REPLACE FUNCTION finance.position(p_student uuid, p_session text)
RETURNS TABLE (due numeric, paid numeric, balance numeric, instalments_paid int, paid_in_full boolean, has_arrears boolean)
LANGUAGE sql STABLE AS $$
    WITH d AS (SELECT coalesce(sum(c.amount), 0) AS due FROM finance.charges(p_student, p_session) c),
         p AS (SELECT coalesce(sum(r.amount), 0) AS paid FROM finance.payment_reference r
                WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'),
         arrears AS (
             SELECT EXISTS (
                 SELECT 1 FROM (SELECT DISTINCT f.session FROM finance.fee_schedule f WHERE f.session < p_session AND f.ended_at IS NULL) past
                  WHERE (SELECT coalesce(sum(c.amount), 0) FROM finance.charges(p_student, past.session) c)
                      > (SELECT coalesce(sum(r.amount), 0) FROM finance.payment_reference r
                          WHERE r.student_id = p_student AND r.session = past.session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%')) AS yes)
    SELECT d.due, p.paid, greatest(d.due - p.paid, 0),
           CASE WHEN d.due = 0 THEN 2 WHEN p.paid >= d.due THEN 2 WHEN p.paid * 2 >= d.due THEN 1 ELSE 0 END,
           d.due = 0 OR p.paid >= d.due,
           arrears.yes
      FROM d, p, arrears;
$$;

-- a reference for a purpose other than the session charge (V026 new_reference is the charge's)
CREATE OR REPLACE FUNCTION finance.new_purpose_reference(p_student uuid, p_session text, p_amount numeric, p_purpose text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v_ref text; v_matric text;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'a payment is for an amount' USING ERRCODE = '23514'; END IF;
    SELECT coalesce(matric_no, admission_no, 'X') INTO v_matric FROM people.student WHERE id = p_student;
    v_ref := 'MOAUM-FEE-' || regexp_replace(right(v_matric, 7), '[^0-9A-Z]', '', 'g') || '-' || lpad((floor(random() * 10000))::int::text, 4, '0');
    INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at)
    VALUES (p_student, p_session, v_ref, p_purpose, p_amount, now() + interval '24 hours');
    RETURN v_ref;
END $$;

COMMIT;
