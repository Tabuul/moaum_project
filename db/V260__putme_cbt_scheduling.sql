-- ═══════════════════════════════════════════════════════════════════════════
-- V260 · Post-UTME CBT: the examination, its centres, rooms, seats and slots;
--        the candidates eligible, batched, seated, slipped, checked in
--
--   V021 gave the screening a batch — a label, a day, two times, a venue in
--   words, a capacity — and seated the submitted applications over it in the
--   order of their numbers. That stays the batch. This migration gives it what
--   an examination of thousands needs: the examination itself as an event with
--   its dates, check-in and duration; CBT centres with rooms and numbered
--   workstations; time slots; eligibility judged on the record (the programme
--   the session screens by examination, the application submitted, the fee
--   confirmed); batches generated over the capacity by a stated strategy and
--   validated before they are published; every seating kept in history, so a
--   candidate moved or a batch postponed leaves the old seat on the record;
--   the candidate checked in at the door on a slip's QR; attendance and the
--   examination's status marked; and the score, entered as before, feeding
--   the admission as it always has. Nothing about the admission changes.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V260: Post-UTME CBT scheduling', true);

-- ── 1 · the examination, the centres, the rooms, the seats, the slots ────

CREATE TABLE admissions.putme_exam (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session               text NOT NULL,
    name                  text NOT NULL,
    kind                  text NOT NULL DEFAULT 'POST_UTME',
    starts_on             date NULL,
    ends_on               date NULL,
    checkin_minutes       int  NOT NULL DEFAULT 30,
    duration_minutes      int  NOT NULL DEFAULT 120,
    buffer_minutes        int  NOT NULL DEFAULT 30,
    registration_deadline date NULL,
    state                 text NOT NULL DEFAULT 'DRAFT',
    strategy              text NOT NULL DEFAULT 'PROGRAMME',
    keep_programme        boolean NOT NULL DEFAULT true,
    instructions          text NULL,
    venue_instructions    text NULL,
    contact               text NULL,
    published_at          timestamptz NULL,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    UNIQUE (session, name),
    CONSTRAINT ck_pe_state CHECK (state IN ('DRAFT','CONFIGURING','OPEN_FOR_SCHEDULING','SCHEDULING_IN_PROGRESS','SCHEDULED','ONGOING','COMPLETED','CANCELLED')),
    CONSTRAINT ck_pe_strategy CHECK (strategy IN ('PROGRAMME','DEPARTMENT','FACULTY','ALPHABETICAL','APPLICATION_NO','BALANCED')),
    CONSTRAINT ck_pe_dates CHECK (ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on),
    CONSTRAINT ck_pe_minutes CHECK (checkin_minutes BETWEEN 0 AND 240 AND duration_minutes BETWEEN 10 AND 600 AND buffer_minutes BETWEEN 0 AND 240)
);
SELECT audit.attach('admissions.putme_exam');
COMMENT ON TABLE admissions.putme_exam IS 'A Post-UTME examination event of a session: its dates, check-in, duration, strategy and state.';

CREATE TABLE admissions.cbt_centre (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code           text NOT NULL UNIQUE,
    name           text NOT NULL,
    location       text NULL,
    address        text NULL,
    contact_person text NULL,
    contact_info   text NULL,
    state          text NOT NULL DEFAULT 'ACTIVE',
    created_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_cc_state CHECK (state IN ('ACTIVE','INACTIVE')),
    CONSTRAINT ck_cc_code CHECK (code ~ '^[A-Z0-9-]{2,12}$')
);
SELECT audit.attach('admissions.cbt_centre');

CREATE TABLE admissions.cbt_room (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    centre_id    uuid NOT NULL REFERENCES admissions.cbt_centre(id),
    code         text NOT NULL,
    name         text NOT NULL,
    capacity     int  NOT NULL,
    workstations int  NOT NULL,
    state        text NOT NULL DEFAULT 'ACTIVE',
    created_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (centre_id, code),
    CONSTRAINT ck_cr_state CHECK (state IN ('ACTIVE','INACTIVE')),
    CONSTRAINT ck_cr_capacity CHECK (capacity BETWEEN 1 AND 2000 AND workstations BETWEEN 0 AND capacity)
);
SELECT audit.attach('admissions.cbt_room');

CREATE TABLE admissions.cbt_workstation (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id     uuid NOT NULL REFERENCES admissions.cbt_room(id) ON DELETE CASCADE,
    number      int  NOT NULL,
    label       text NOT NULL,
    operational boolean NOT NULL DEFAULT true,
    UNIQUE (room_id, number)
);
SELECT audit.attach('admissions.cbt_workstation');

/* a room's workstations numbered from 1, kept in step with the count the room states; a workstation the room no longer has is removed
   only when no active seating holds it */
CREATE OR REPLACE FUNCTION admissions.cbt_room_workstations(p_room uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE r admissions.cbt_room; n int := 0;
BEGIN
    SELECT * INTO r FROM admissions.cbt_room WHERE id = p_room;
    INSERT INTO admissions.cbt_workstation (room_id, number, label)
    SELECT r.id, g, 'Computer ' || lpad(g::text, 3, '0') FROM generate_series(1, r.workstations) g
    ON CONFLICT (room_id, number) DO UPDATE SET operational = true;
    -- a workstation the room no longer has is out of service, never removed: a seating that held it stays explained
    UPDATE admissions.cbt_workstation w SET operational = false WHERE w.room_id = r.id AND w.number > r.workstations;
    SELECT count(*) INTO n FROM admissions.cbt_workstation WHERE room_id = r.id AND operational;
    RETURN n;
END $$;

CREATE TABLE admissions.putme_slot (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    exam_id   uuid NOT NULL REFERENCES admissions.putme_exam(id) ON DELETE CASCADE,
    code      text NOT NULL,
    starts_at time NOT NULL,
    ends_at   time NOT NULL,
    ord       int  NOT NULL DEFAULT 0,
    active    boolean NOT NULL DEFAULT true,
    UNIQUE (exam_id, code),
    CONSTRAINT ck_ps_times CHECK (ends_at > starts_at)
);
SELECT audit.attach('admissions.putme_slot');

CREATE TABLE admissions.putme_day (
    exam_id uuid NOT NULL REFERENCES admissions.putme_exam(id) ON DELETE CASCADE,
    held_on date NOT NULL,
    active  boolean NOT NULL DEFAULT true,
    PRIMARY KEY (exam_id, held_on)
);
SELECT audit.attach('admissions.putme_day');

CREATE TABLE admissions.putme_exam_centre (
    exam_id   uuid NOT NULL REFERENCES admissions.putme_exam(id) ON DELETE CASCADE,
    centre_id uuid NOT NULL REFERENCES admissions.cbt_centre(id),
    active    boolean NOT NULL DEFAULT true,
    PRIMARY KEY (exam_id, centre_id)
);
SELECT audit.attach('admissions.putme_exam_centre');

-- ── 2 · the batch, now placed; the seating, now kept ──────────────────────

ALTER TABLE admissions.screening_batch
    ADD COLUMN IF NOT EXISTS exam_id   uuid NULL REFERENCES admissions.putme_exam(id),
    ADD COLUMN IF NOT EXISTS centre_id uuid NULL REFERENCES admissions.cbt_centre(id),
    ADD COLUMN IF NOT EXISTS room_id   uuid NULL REFERENCES admissions.cbt_room(id),
    ADD COLUMN IF NOT EXISTS slot_id   uuid NULL REFERENCES admissions.putme_slot(id),
    ADD COLUMN IF NOT EXISTS state     text NOT NULL DEFAULT 'PUBLISHED',
    ADD COLUMN IF NOT EXISTS ordinal   int  NULL,
    ADD COLUMN IF NOT EXISTS note      text NULL;
ALTER TABLE admissions.screening_batch ADD CONSTRAINT ck_batch_state CHECK (state IN ('DRAFT','PUBLISHED','POSTPONED','CANCELLED'));
-- a room is not booked twice for the same day and slot
CREATE UNIQUE INDEX uq_batch_room_slot ON admissions.screening_batch (room_id, held_on, slot_id) WHERE room_id IS NOT NULL AND slot_id IS NOT NULL AND state IN ('DRAFT','PUBLISHED');
CREATE INDEX ix_batch_exam ON admissions.screening_batch (exam_id, held_on, ordinal);

ALTER TABLE admissions.application
    ADD COLUMN IF NOT EXISTS putme_token     text NOT NULL DEFAULT encode(gen_random_bytes(8), 'hex'),
    ADD COLUMN IF NOT EXISTS schedule_review boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX uq_application_putme_token ON admissions.application (putme_token);

CREATE TABLE admissions.screening_assignment (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES admissions.application(id),
    batch_id       uuid NOT NULL REFERENCES admissions.screening_batch(id),
    seat           text NOT NULL,
    workstation_id uuid NULL REFERENCES admissions.cbt_workstation(id),
    state          text NOT NULL DEFAULT 'ACTIVE',
    reason         text NULL,
    assigned_at    timestamptz NOT NULL DEFAULT now(),
    assigned_by    uuid NULL,
    ended_at       timestamptz NULL,
    ended_by       uuid NULL,
    checked_in_at  timestamptz NULL,
    checked_in_by  uuid NULL,
    attendance     text NOT NULL DEFAULT 'NOT_CHECKED_IN',
    exam_status    text NOT NULL DEFAULT 'NOT_STARTED',
    remarks        text NULL,
    CONSTRAINT ck_sa_state CHECK (state IN ('ACTIVE','SUPERSEDED','CANCELLED')),
    CONSTRAINT ck_sa_attendance CHECK (attendance IN ('NOT_CHECKED_IN','CHECKED_IN','PRESENT','ABSENT','DISQUALIFIED')),
    CONSTRAINT ck_sa_exam CHECK (exam_status IN ('NOT_STARTED','IN_PROGRESS','COMPLETED','ABSENT','DISQUALIFIED'))
);
CREATE UNIQUE INDEX uq_sa_one_active ON admissions.screening_assignment (application_id) WHERE state = 'ACTIVE';
CREATE UNIQUE INDEX uq_sa_seat ON admissions.screening_assignment (batch_id, seat) WHERE state = 'ACTIVE';
CREATE UNIQUE INDEX uq_sa_workstation ON admissions.screening_assignment (batch_id, workstation_id) WHERE state = 'ACTIVE' AND workstation_id IS NOT NULL;
CREATE INDEX ix_sa_batch ON admissions.screening_assignment (batch_id, state);
SELECT audit.attach('admissions.screening_assignment');
COMMENT ON TABLE admissions.screening_assignment IS
  'Every seating of a candidate in a screening batch, kept: the one ACTIVE, the earlier SUPERSEDED or CANCELLED with the reason; the check-in, attendance and examination status ride on the active one.';

CREATE TABLE admissions.putme_event (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    exam_id        uuid NULL REFERENCES admissions.putme_exam(id),
    batch_id       uuid NULL REFERENCES admissions.screening_batch(id),
    application_id uuid NULL REFERENCES admissions.application(id),
    action         text NOT NULL,
    from_value     text NULL,
    to_value       text NULL,
    note           text NULL,
    actor_id       uuid NULL,
    actor_office   text NULL,
    at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_putme_event ON admissions.putme_event (exam_id, at);
CREATE INDEX ix_putme_event_app ON admissions.putme_event (application_id, at);
SELECT audit.attach('admissions.putme_event');
CREATE OR REPLACE FUNCTION admissions.putme_history_is_written_once()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('moaum.maintenance', true) = 'on' THEN RETURN COALESCE(NEW, OLD); END IF;
    RAISE EXCEPTION 'the Post-UTME trail is written once' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_putme_event_written_once BEFORE UPDATE OR DELETE ON admissions.putme_event
FOR EACH ROW EXECUTE FUNCTION admissions.putme_history_is_written_once();

CREATE OR REPLACE FUNCTION admissions.putme_log(p_exam uuid, p_batch uuid, p_app uuid, p_action text, p_from text, p_to text, p_note text)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO admissions.putme_event (exam_id, batch_id, application_id, action, from_value, to_value, note, actor_id, actor_office)
    VALUES (p_exam, p_batch, p_app, p_action, p_from, p_to, p_note,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
$$;

/* the seating kept in step with the application's own columns, whichever path wrote them (V021's assign_screening or
   the functions below): the earlier active seating is superseded with the reason the transaction carries; the new one opened */
CREATE OR REPLACE FUNCTION admissions.screening_assignment_sync()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_ws uuid; v_reason text := nullif(current_setting('moaum.putme_reason', true), '');
BEGIN
    IF NEW.screening_batch_id IS NOT DISTINCT FROM OLD.screening_batch_id AND NEW.seat IS NOT DISTINCT FROM OLD.seat THEN RETURN NEW; END IF;
    UPDATE admissions.screening_assignment
       SET state = CASE WHEN NEW.screening_batch_id IS NULL THEN 'CANCELLED' ELSE 'SUPERSEDED' END,
           ended_at = now(), ended_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
           reason = coalesce(v_reason, current_setting('moaum.reason', true))
     WHERE application_id = NEW.id AND state = 'ACTIVE';
    IF NEW.screening_batch_id IS NOT NULL THEN
        SELECT w.id INTO v_ws FROM admissions.screening_batch b JOIN admissions.cbt_workstation w ON w.room_id = b.room_id
         WHERE b.id = NEW.screening_batch_id AND w.number = nullif(regexp_replace(NEW.seat, '^.*?([0-9]+)$', '\1'), '')::int AND w.operational;
        INSERT INTO admissions.screening_assignment (application_id, batch_id, seat, workstation_id, assigned_by, reason)
        VALUES (NEW.id, NEW.screening_batch_id, NEW.seat, v_ws, nullif(current_setting('moaum.actor_id', true), '')::uuid, v_reason);
        NEW.schedule_review := false;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_screening_assignment_sync BEFORE UPDATE OF screening_batch_id, seat ON admissions.application
FOR EACH ROW EXECUTE FUNCTION admissions.screening_assignment_sync();

-- every seating already on the register is on the history too
INSERT INTO admissions.screening_assignment (application_id, batch_id, seat, assigned_at)
SELECT a.id, a.screening_batch_id, a.seat, coalesce(b.created_at, a.created_at)
  FROM admissions.application a JOIN admissions.screening_batch b ON b.id = a.screening_batch_id
 WHERE a.screening_batch_id IS NOT NULL;

/* a candidate whose programme changes after seating: the seating stands, flagged for review */
CREATE OR REPLACE FUNCTION admissions.putme_flag_programme_change()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.programme IS DISTINCT FROM OLD.programme THEN
        UPDATE admissions.application a SET schedule_review = true WHERE a.candidate_id = NEW.id AND a.screening_batch_id IS NOT NULL;
        PERFORM admissions.putme_log(NULL, a.screening_batch_id, a.id, 'PROGRAMME_CHANGED', OLD.programme, NEW.programme, 'Schedule requires review')
          FROM admissions.application a WHERE a.candidate_id = NEW.id AND a.screening_batch_id IS NOT NULL;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_putme_programme_change AFTER UPDATE OF programme ON admissions.candidate
FOR EACH ROW EXECUTE FUNCTION admissions.putme_flag_programme_change();

-- ── 3 · eligibility, judged on the record ─────────────────────────────────

CREATE OR REPLACE FUNCTION admissions.putme_programme_code(p_programme_name text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT p.code FROM ref.programme p WHERE p.name = p_programme_name ORDER BY p.archived, p.code LIMIT 1;
$$;

/* where a candidate stands for the Post-UTME: the programme the session screens by examination, the application
   submitted, the fee confirmed, then the seating, the sitting, the score */
CREATE OR REPLACE FUNCTION admissions.putme_eligibility(p_app uuid)
RETURNS TABLE (status text, why text)
LANGUAGE plpgsql STABLE AS $$
DECLARE a admissions.application; c admissions.candidate; sa admissions.screening_assignment; v_code text; v_any boolean;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN QUERY SELECT 'NOT_ELIGIBLE', 'No application'; RETURN; END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    v_code := admissions.putme_programme_code(c.programme);
    SELECT EXISTS (SELECT 1 FROM admissions.screening_exam_programme e WHERE e.session = a.session) INTO v_any;
    IF c.offer_state IN ('WITHDRAWN','DECLINED','LAPSED') THEN RETURN QUERY SELECT 'NOT_ELIGIBLE', 'The candidate is ' || lower(c.offer_state); RETURN; END IF;
    IF v_any AND NOT admissions.screened_by_exam(a.session, v_code) THEN RETURN QUERY SELECT 'NOT_ELIGIBLE', 'The programme is not screened by the Post-UTME examination this session'; RETURN; END IF;
    IF NOT v_any THEN RETURN QUERY SELECT 'NOT_ELIGIBLE', 'No programme is named as screened by examination for ' || a.session || ' yet'; RETURN; END IF;
    SELECT * INTO sa FROM admissions.screening_assignment WHERE application_id = a.id AND state = 'ACTIVE';
    IF sa.id IS NOT NULL AND sa.attendance = 'DISQUALIFIED' THEN RETURN QUERY SELECT 'DISQUALIFIED', coalesce(sa.remarks, 'Disqualified at the examination'); RETURN; END IF;
    IF a.screening_score IS NOT NULL OR (sa.id IS NOT NULL AND sa.exam_status = 'COMPLETED') THEN RETURN QUERY SELECT 'EXAM_COMPLETED', 'The examination has been sat'; RETURN; END IF;
    IF sa.id IS NOT NULL AND sa.attendance = 'ABSENT' THEN RETURN QUERY SELECT 'ABSENT', 'Marked absent from the examination'; RETURN; END IF;
    IF sa.id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM admissions.screening_assignment x WHERE x.application_id = a.id AND x.state <> 'ACTIVE') THEN RETURN QUERY SELECT 'RESCHEDULED', 'Seated again after an earlier seating'; RETURN; END IF;
        RETURN QUERY SELECT 'SCHEDULED', 'Seated in a batch'; RETURN;
    END IF;
    -- the fee comes first on the portal (the form opens when it is confirmed), so it is the first thing missing
    IF a.fee_confirmed_at IS NULL THEN RETURN QUERY SELECT 'PAYMENT_PENDING', 'The screening fee is not confirmed'; RETURN; END IF;
    IF a.submitted_at IS NULL THEN RETURN QUERY SELECT 'DOCUMENT_PENDING', 'The application is not yet submitted'; RETURN; END IF;
    IF EXISTS (SELECT 1 FROM admissions.screening_assignment x WHERE x.application_id = a.id AND x.state <> 'ACTIVE' AND x.reason LIKE 'POSTPONED%') THEN
        RETURN QUERY SELECT 'RESCHEDULE_REQUIRED', 'The batch was postponed; a new seating is needed'; RETURN;
    END IF;
    RETURN QUERY SELECT 'READY_FOR_SCHEDULING', 'Submitted, paid, programme screened by examination';
END $$;

/* every applicant of the session with where they stand, their seating and its place */
CREATE OR REPLACE FUNCTION admissions.putme_candidates(p_session text)
RETURNS TABLE (
    application_id uuid, application_no text, surname text, other_names text, jamb_reg_no text, utme int, entry_mode text,
    programme_code text, programme text, dept_code text, department text, faculty_code text, faculty text,
    fee_confirmed_at timestamptz, submitted_at timestamptz, status text, why text, schedule_review boolean, putme_token text,
    batch_id uuid, batch text, held_on date, starts_at time, ends_at time, centre text, room text, seat text, workstation text,
    attendance text, exam_status text, checked_in_at timestamptz, screening_score numeric, score_released_at timestamptz
)
LANGUAGE sql STABLE AS $$
    SELECT a.id, a.application_no, c.surname, c.other_names, c.jamb_reg_no, r.aggregate, c.entry_mode,
           p.code, coalesce(p.name, c.programme), d.code, d.name, f.code, f.name,
           a.fee_confirmed_at, a.submitted_at, e.status, e.why, a.schedule_review, a.putme_token,
           b.id, b.label, b.held_on, b.starts_at, b.ends_at, coalesce(cc.name, b.venue), cr.name, a.seat, w.label,
           coalesce(sa.attendance, 'NOT_CHECKED_IN'), coalesce(sa.exam_status, 'NOT_STARTED'), sa.checked_in_at, a.screening_score, a.score_released_at
      FROM admissions.application a
      JOIN admissions.candidate c ON c.id = a.candidate_id
      LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
      LEFT JOIN ref.programme p ON p.code = admissions.putme_programme_code(c.programme)
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN admissions.screening_batch b ON b.id = a.screening_batch_id
      LEFT JOIN admissions.cbt_centre cc ON cc.id = b.centre_id
      LEFT JOIN admissions.cbt_room cr ON cr.id = b.room_id
      LEFT JOIN admissions.screening_assignment sa ON sa.application_id = a.id AND sa.state = 'ACTIVE'
      LEFT JOIN admissions.cbt_workstation w ON w.id = sa.workstation_id
      CROSS JOIN LATERAL admissions.putme_eligibility(a.id) e
     WHERE a.session = p_session;
$$;

-- ── 4 · the capacity, the preview, the batches generated ──────────────────

/* each place the examination can seat candidates: a day, a slot, a room of one of its centres — and what sits there already */
CREATE OR REPLACE FUNCTION admissions.putme_capacity(p_exam uuid)
RETURNS TABLE (held_on date, slot_id uuid, slot text, starts_at time, ends_at time, centre_id uuid, centre text, room_id uuid, room text, capacity int, assigned int, batch_id uuid)
LANGUAGE sql STABLE AS $$
    SELECT d.held_on, s.id, s.code, s.starts_at, s.ends_at, c.id, c.name, r.id, r.name,
           coalesce(nullif((SELECT count(*) FROM admissions.cbt_workstation w WHERE w.room_id = r.id AND w.operational), 0), r.capacity)::int,
           coalesce((SELECT count(*) FROM admissions.application a WHERE a.screening_batch_id = b.id), 0)::int,
           b.id
      FROM admissions.putme_day d
      CROSS JOIN admissions.putme_slot s
      JOIN admissions.putme_exam_centre ec ON ec.exam_id = d.exam_id
      JOIN admissions.cbt_centre c ON c.id = ec.centre_id AND c.state = 'ACTIVE'
      JOIN admissions.cbt_room r ON r.centre_id = c.id AND r.state = 'ACTIVE'
      LEFT JOIN admissions.screening_batch b ON b.exam_id = d.exam_id AND b.held_on = d.held_on AND b.slot_id = s.id AND b.room_id = r.id AND b.state IN ('DRAFT','PUBLISHED')
     WHERE d.exam_id = p_exam AND d.active AND s.exam_id = p_exam AND s.active AND ec.active
     ORDER BY d.held_on, s.ord, s.starts_at, c.name, r.name;
$$;

CREATE OR REPLACE FUNCTION admissions.putme_preview(p_exam uuid)
RETURNS TABLE (eligible int, ready int, scheduled int, unscheduled int, capacity int, used int, places int, required_batches int, centres int, rooms int, days int, slots int)
LANGUAGE sql STABLE AS $$
    WITH x AS (SELECT * FROM admissions.putme_exam WHERE id = p_exam),
    cand AS (SELECT e.status FROM x, admissions.putme_candidates(x.session) e),
    cap AS (SELECT * FROM admissions.putme_capacity(p_exam))
    SELECT (SELECT count(*) FROM cand WHERE status IN ('READY_FOR_SCHEDULING','SCHEDULED','RESCHEDULED','RESCHEDULE_REQUIRED','EXAM_COMPLETED','ABSENT'))::int,
           (SELECT count(*) FROM cand WHERE status IN ('READY_FOR_SCHEDULING','RESCHEDULE_REQUIRED'))::int,
           (SELECT count(*) FROM cand WHERE status IN ('SCHEDULED','RESCHEDULED'))::int,
           (SELECT count(*) FROM cand WHERE status IN ('READY_FOR_SCHEDULING','RESCHEDULE_REQUIRED'))::int,
           (SELECT coalesce(sum(capacity), 0) FROM cap)::int,
           (SELECT coalesce(sum(assigned), 0) FROM cap)::int,
           (SELECT count(*) FROM cap)::int,
           (SELECT CASE WHEN coalesce(max(capacity), 0) = 0 THEN 0 ELSE ceil((SELECT count(*) FROM cand WHERE status IN ('READY_FOR_SCHEDULING','RESCHEDULE_REQUIRED'))::numeric / max(capacity)) END FROM cap)::int,
           (SELECT count(DISTINCT centre_id) FROM cap)::int, (SELECT count(DISTINCT room_id) FROM cap)::int,
           (SELECT count(DISTINCT held_on) FROM cap)::int, (SELECT count(DISTINCT slot_id) FROM cap)::int;
$$;

/* the batches generated over the capacity: the ready candidates in the order the strategy states, each place filled to its
   capacity in turn, a batch made for each place used, a seat and a workstation given to each; DRAFT until published */
CREATE OR REPLACE FUNCTION admissions.putme_generate(p_exam uuid)
RETURNS TABLE (batches int, seated int, unseated int)
LANGUAGE plpgsql AS $$
DECLARE x admissions.putme_exam; place record; cand record; v_batch uuid; v_label text; v_n int; v_ord int; v_free int;
        v_batches int := 0; v_seated int := 0; v_unseated int := 0; cur refcursor; v_done boolean := false;
BEGIN
    SELECT * INTO x FROM admissions.putme_exam WHERE id = p_exam FOR UPDATE;
    IF x.id IS NULL THEN RAISE EXCEPTION 'no such examination' USING ERRCODE = '23503'; END IF;
    IF x.state IN ('SCHEDULED','ONGOING','COMPLETED','CANCELLED') THEN
        RAISE EXCEPTION 'the schedule of % is %; candidates are moved one by one, or a batch postponed', x.name, lower(x.state) USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM admissions.putme_capacity(p_exam)) THEN
        RAISE EXCEPTION 'the examination has no place to seat anyone: name its dates, its slots and its centres with rooms first' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.putme_exam SET state = 'SCHEDULING_IN_PROGRESS', updated_at = now() WHERE id = p_exam;
    SELECT coalesce(max(ordinal), 0) INTO v_ord FROM admissions.screening_batch WHERE exam_id = p_exam;
    OPEN cur FOR
        SELECT e.application_id, e.surname, e.other_names
          FROM admissions.putme_candidates(x.session) e
         WHERE e.status IN ('READY_FOR_SCHEDULING','RESCHEDULE_REQUIRED')
         ORDER BY CASE x.strategy
                      WHEN 'ALPHABETICAL' THEN e.surname || ' ' || e.other_names
                      WHEN 'APPLICATION_NO' THEN e.application_no
                      WHEN 'BALANCED' THEN lpad((row_number() OVER (PARTITION BY e.programme_code ORDER BY e.surname, e.other_names))::text, 8, '0') || e.programme
                      WHEN 'FACULTY' THEN e.faculty || '|' || e.department || '|' || e.programme || '|' || e.surname || ' ' || e.other_names
                      WHEN 'DEPARTMENT' THEN e.department || '|' || e.programme || '|' || e.surname || ' ' || e.other_names
                      ELSE e.programme || '|' || e.surname || ' ' || e.other_names END,
                  e.surname, e.other_names, e.application_no;
    FETCH cur INTO cand;
    IF NOT FOUND THEN CLOSE cur; RETURN QUERY SELECT 0, 0, 0; RETURN; END IF;
    FOR place IN SELECT * FROM admissions.putme_capacity(p_exam) LOOP
        EXIT WHEN v_done;
        v_free := place.capacity - place.assigned;
        CONTINUE WHEN v_free <= 0;
        v_batch := place.batch_id;
        IF v_batch IS NULL THEN
            v_ord := v_ord + 1;
            v_label := 'B' || lpad(v_ord::text, 3, '0');
            INSERT INTO admissions.screening_batch (id, session, label, held_on, starts_at, ends_at, venue, capacity, exam_id, centre_id, room_id, slot_id, state, ordinal)
            VALUES (gen_random_uuid(), x.session, v_label, place.held_on, place.starts_at, place.ends_at, place.centre || ' · ' || place.room, place.capacity,
                    p_exam, place.centre_id, place.room_id, place.slot_id, 'DRAFT', v_ord)
            RETURNING id INTO v_batch;
            v_batches := v_batches + 1;
            PERFORM admissions.putme_log(p_exam, v_batch, NULL, 'BATCH_GENERATED', NULL, v_label, place.centre || ' · ' || place.room || ' · ' || place.held_on || ' ' || place.slot);
        END IF;
        v_n := place.assigned;
        WHILE v_free > 0 LOOP
            v_n := v_n + 1;
            -- the next seat not taken in this batch
            WHILE EXISTS (SELECT 1 FROM admissions.screening_assignment s WHERE s.batch_id = v_batch AND s.state = 'ACTIVE' AND s.seat = lpad(v_n::text, 3, '0')) LOOP v_n := v_n + 1; END LOOP;
            PERFORM set_config('moaum.putme_reason', 'Generated', true);
            UPDATE admissions.application SET screening_batch_id = v_batch, seat = lpad(v_n::text, 3, '0') WHERE id = cand.application_id;
            v_seated := v_seated + 1;
            v_free := v_free - 1;
            FETCH cur INTO cand;
            IF NOT FOUND THEN v_done := true; EXIT; END IF;
        END LOOP;
    END LOOP;
    IF NOT v_done THEN
        -- whoever is left had no place
        LOOP
            v_unseated := v_unseated + 1;
            FETCH cur INTO cand;
            EXIT WHEN NOT FOUND;
        END LOOP;
    END IF;
    CLOSE cur;
    PERFORM set_config('moaum.putme_reason', '', true);
    PERFORM admissions.putme_log(p_exam, NULL, NULL, 'GENERATED', NULL, NULL, v_batches || ' batch(es), ' || v_seated || ' seated, ' || v_unseated || ' without a place');
    RETURN QUERY SELECT v_batches, v_seated, v_unseated;
END $$;

/* what stands in the way of publishing: each finding with its severity and count */
CREATE OR REPLACE FUNCTION admissions.putme_validate(p_exam uuid)
RETURNS TABLE (severity text, code text, message text, n int)
LANGUAGE sql STABLE AS $$
    WITH x AS (SELECT * FROM admissions.putme_exam WHERE id = p_exam),
    b AS (SELECT sb.*, (SELECT count(*) FROM admissions.application a WHERE a.screening_batch_id = sb.id) AS assigned,
                 coalesce(nullif((SELECT count(*) FROM admissions.cbt_workstation w WHERE w.room_id = sb.room_id AND w.operational), 0), sb.capacity) AS room_cap
            FROM admissions.screening_batch sb WHERE sb.exam_id = p_exam AND sb.state IN ('DRAFT','PUBLISHED')),
    cand AS (SELECT e.* FROM x, admissions.putme_candidates(x.session) e)
    SELECT 'ERROR', 'CAPACITY', 'Room capacity exceeded: ' || string_agg(b.label || ' has ' || b.assigned || ' of ' || least(b.capacity, b.room_cap), ', '), count(*)::int FROM b WHERE b.assigned > least(b.capacity, b.room_cap) HAVING count(*) > 0
    UNION ALL
    SELECT 'ERROR', 'DUPLICATE', 'A candidate is seated more than once', count(*)::int FROM (SELECT application_id FROM admissions.screening_assignment WHERE state = 'ACTIVE' GROUP BY application_id HAVING count(*) > 1) d HAVING count(*) > 0
    UNION ALL
    SELECT 'ERROR', 'ROOM_CLASH', 'A room is booked twice for the same day and slot', count(*)::int FROM (SELECT room_id, held_on, slot_id FROM b WHERE room_id IS NOT NULL GROUP BY room_id, held_on, slot_id HAVING count(*) > 1) d HAVING count(*) > 0
    UNION ALL
    SELECT 'ERROR', 'INELIGIBLE', 'Candidates seated whose programme is not screened by examination or whose candidacy is closed', count(*)::int FROM cand WHERE cand.batch_id IS NOT NULL AND cand.status = 'NOT_ELIGIBLE' HAVING count(*) > 0
    UNION ALL
    SELECT 'ERROR', 'UNPAID', 'Candidates seated whose screening fee is not confirmed', count(*)::int FROM cand WHERE cand.batch_id IS NOT NULL AND cand.fee_confirmed_at IS NULL HAVING count(*) > 0
    UNION ALL
    SELECT 'ERROR', 'UNSUBMITTED', 'Candidates seated whose application is not submitted', count(*)::int FROM cand WHERE cand.batch_id IS NOT NULL AND cand.submitted_at IS NULL HAVING count(*) > 0
    UNION ALL
    SELECT 'ERROR', 'UNPLACED_BATCH', 'A batch of this examination has no centre, room or slot', count(*)::int FROM b WHERE b.centre_id IS NULL OR b.room_id IS NULL OR b.slot_id IS NULL HAVING count(*) > 0
    UNION ALL
    SELECT 'WARNING', 'UNSCHEDULED', 'Eligible candidates not yet seated', count(*)::int FROM cand WHERE cand.status IN ('READY_FOR_SCHEDULING','RESCHEDULE_REQUIRED') HAVING count(*) > 0
    UNION ALL
    SELECT 'WARNING', 'REVIEW', 'Seated candidates whose programme changed after seating', count(*)::int FROM cand WHERE cand.schedule_review HAVING count(*) > 0
    UNION ALL
    SELECT 'WARNING', 'NO_WORKSTATION', 'Seated candidates without a numbered workstation (the room states none)', count(*)::int FROM admissions.screening_assignment sa JOIN b ON b.id = sa.batch_id WHERE sa.state = 'ACTIVE' AND sa.workstation_id IS NULL AND b.room_id IS NOT NULL AND EXISTS (SELECT 1 FROM admissions.cbt_workstation w WHERE w.room_id = b.room_id) HAVING count(*) > 0;
$$;

/* the schedule made official: no error stands, every draft batch published, the examination SCHEDULED, every seated candidate told */
CREATE OR REPLACE FUNCTION admissions.putme_publish(p_exam uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE x admissions.putme_exam; v_err text; r record; n int := 0;
BEGIN
    SELECT * INTO x FROM admissions.putme_exam WHERE id = p_exam FOR UPDATE;
    IF x.id IS NULL THEN RAISE EXCEPTION 'no such examination' USING ERRCODE = '23503'; END IF;
    SELECT string_agg(message, '; ') INTO v_err FROM admissions.putme_validate(p_exam) WHERE severity = 'ERROR';
    IF v_err IS NOT NULL THEN RAISE EXCEPTION 'the schedule cannot be published: %', v_err USING ERRCODE = '23514', HINT = 'Resolve each finding on the validation report, then publish.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM admissions.screening_batch WHERE exam_id = p_exam AND state IN ('DRAFT','PUBLISHED')) THEN
        RAISE EXCEPTION 'nothing to publish: generate the batches first' USING ERRCODE = '23514';
    END IF;
    FOR r IN
        SELECT a.id, b.label, b.held_on, b.starts_at, b.ends_at, coalesce(cc.name, b.venue) AS centre, cr.name AS room, a.seat, b.state AS bstate
          FROM admissions.application a JOIN admissions.screening_batch b ON b.id = a.screening_batch_id
          LEFT JOIN admissions.cbt_centre cc ON cc.id = b.centre_id LEFT JOIN admissions.cbt_room cr ON cr.id = b.room_id
         WHERE b.exam_id = p_exam AND b.state = 'DRAFT'
    LOOP
        PERFORM admissions.notify_applicant(r.id, 'Your Post-UTME examination schedule',
            'You are scheduled for the ' || x.name || ' in batch ' || r.label || ' on ' || to_char(r.held_on, 'FMDay DD FMMonth YYYY') || ', ' || to_char(r.starts_at, 'HH24:MI') || ' to ' || to_char(r.ends_at, 'HH24:MI')
            || ' at ' || r.centre || coalesce(', ' || r.room, '') || ', seat ' || r.seat || '. Report ' || x.checkin_minutes || ' minutes before the start with your examination slip and a photo identification. Sign in to the portal to download the slip.',
            'MOAUM Post-UTME: batch ' || r.label || ', ' || to_char(r.held_on, 'DD Mon') || ' ' || to_char(r.starts_at, 'HH24:MI') || ', ' || r.centre || coalesce(' ' || r.room, '') || ', seat ' || r.seat || '. Download your slip on the portal.');
        n := n + 1;
    END LOOP;
    UPDATE admissions.screening_batch SET state = 'PUBLISHED' WHERE exam_id = p_exam AND state = 'DRAFT';
    UPDATE admissions.putme_exam SET state = 'SCHEDULED', published_at = now(), updated_at = now() WHERE id = p_exam;
    PERFORM admissions.putme_log(p_exam, NULL, NULL, 'PUBLISHED', NULL, 'SCHEDULED', n || ' candidate(s) told');
    RETURN n;
END $$;

-- ── 5 · a candidate moved, a batch postponed, the door, the hall ──────────

/* a candidate moved to another batch (or seated for the first time by hand): the old seating superseded with the reason,
   the next free seat given, the candidate told when the batch is published */
CREATE OR REPLACE FUNCTION admissions.putme_move(p_app uuid, p_batch uuid, p_reason text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE a admissions.application; b admissions.screening_batch; x admissions.putme_exam; e record; v_cap int; v_n int := 0; v_seat text; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
BEGIN
    IF v_reason IS NULL THEN RAISE EXCEPTION 'a move carries its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO a FROM admissions.application WHERE id = p_app FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    SELECT * INTO b FROM admissions.screening_batch WHERE id = p_batch;
    IF b.id IS NULL OR b.state NOT IN ('DRAFT','PUBLISHED') THEN RAISE EXCEPTION 'that batch is not open for seating' USING ERRCODE = '23514'; END IF;
    IF a.screening_batch_id = p_batch THEN RETURN 'already in ' || b.label; END IF;
    SELECT * INTO e FROM admissions.putme_eligibility(a.id);
    IF e.status IN ('NOT_ELIGIBLE','PAYMENT_PENDING','DOCUMENT_PENDING','DISQUALIFIED') THEN
        RAISE EXCEPTION 'the candidate is not eligible for seating: %', e.why USING ERRCODE = '23514';
    END IF;
    v_cap := least(b.capacity, coalesce(nullif((SELECT count(*) FROM admissions.cbt_workstation w WHERE w.room_id = b.room_id AND w.operational), 0), b.capacity));
    IF (SELECT count(*) FROM admissions.application WHERE screening_batch_id = p_batch) >= v_cap THEN
        RAISE EXCEPTION 'ROOM CAPACITY EXCEEDED: batch % is full (% of %)', b.label, v_cap, v_cap USING ERRCODE = '23514';
    END IF;
    LOOP
        v_n := v_n + 1; v_seat := lpad(v_n::text, 3, '0');
        EXIT WHEN NOT EXISTS (SELECT 1 FROM admissions.screening_assignment s WHERE s.batch_id = p_batch AND s.state = 'ACTIVE' AND s.seat = v_seat) AND v_n <= v_cap;
        IF v_n > v_cap THEN RAISE EXCEPTION 'no free seat in batch %', b.label USING ERRCODE = '23514'; END IF;
    END LOOP;
    PERFORM set_config('moaum.putme_reason', v_reason, true);
    UPDATE admissions.application SET screening_batch_id = p_batch, seat = v_seat WHERE id = a.id;
    PERFORM set_config('moaum.putme_reason', '', true);
    PERFORM admissions.putme_log(b.exam_id, p_batch, a.id, CASE WHEN a.screening_batch_id IS NULL THEN 'SEATED' ELSE 'MOVED' END,
        (SELECT label FROM admissions.screening_batch WHERE id = a.screening_batch_id), b.label || ' seat ' || v_seat, v_reason);
    IF b.state = 'PUBLISHED' THEN
        SELECT * INTO x FROM admissions.putme_exam WHERE id = b.exam_id;
        PERFORM admissions.notify_applicant(a.id, CASE WHEN a.screening_batch_id IS NULL THEN 'Your Post-UTME examination schedule' ELSE 'Your Post-UTME schedule has changed' END,
            'You are now scheduled in batch ' || b.label || ' on ' || to_char(b.held_on, 'FMDay DD FMMonth YYYY') || ', ' || to_char(b.starts_at, 'HH24:MI') || ' to ' || to_char(b.ends_at, 'HH24:MI')
            || ' at ' || b.venue || ', seat ' || v_seat || '. Reason: ' || v_reason || '. Download the new slip on the portal; the earlier one no longer admits you.',
            'MOAUM Post-UTME: new schedule — batch ' || b.label || ', ' || to_char(b.held_on, 'DD Mon') || ' ' || to_char(b.starts_at, 'HH24:MI') || ', ' || b.venue || ', seat ' || v_seat || '.');
    END IF;
    RETURN b.label || ' seat ' || v_seat;
END $$;

/* a candidate taken out of the schedule, the seating kept as cancelled with the reason */
CREATE OR REPLACE FUNCTION admissions.putme_unschedule(p_app uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE a admissions.application; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
BEGIN
    IF v_reason IS NULL THEN RAISE EXCEPTION 'unscheduling carries its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO a FROM admissions.application WHERE id = p_app FOR UPDATE;
    IF a.screening_batch_id IS NULL THEN RETURN; END IF;
    PERFORM set_config('moaum.putme_reason', v_reason, true);
    UPDATE admissions.application SET screening_batch_id = NULL, seat = NULL WHERE id = a.id;
    PERFORM set_config('moaum.putme_reason', '', true);
    PERFORM admissions.putme_log((SELECT exam_id FROM admissions.screening_batch WHERE id = a.screening_batch_id), a.screening_batch_id, a.id, 'UNSCHEDULED', a.seat, NULL, v_reason);
    PERFORM admissions.notify_applicant(a.id, 'Your Post-UTME seating has been withdrawn',
        'Your seat in the Post-UTME examination has been withdrawn: ' || v_reason || '. You will be seated again and told your new day, time, centre and seat.',
        'Your Post-UTME seat has been withdrawn: ' || left(v_reason, 60) || '. A new seating will be published.');
END $$;

/* a batch postponed or cancelled: every seating in it ends with the reason, each candidate is told and waits to be seated again */
CREATE OR REPLACE FUNCTION admissions.putme_batch_state(p_batch uuid, p_state text, p_reason text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE b admissions.screening_batch; r record; n int := 0; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
BEGIN
    IF p_state NOT IN ('POSTPONED','CANCELLED') THEN RAISE EXCEPTION 'a batch is postponed or cancelled' USING ERRCODE = '23514'; END IF;
    IF v_reason IS NULL THEN RAISE EXCEPTION 'say why the batch is %', lower(p_state) USING ERRCODE = '23514'; END IF;
    SELECT * INTO b FROM admissions.screening_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such batch' USING ERRCODE = '23503'; END IF;
    FOR r IN SELECT a.id, a.seat FROM admissions.application a WHERE a.screening_batch_id = p_batch LOOP
        PERFORM set_config('moaum.putme_reason', p_state || ': ' || v_reason, true);
        UPDATE admissions.application SET screening_batch_id = NULL, seat = NULL WHERE id = r.id;
        IF b.state = 'PUBLISHED' THEN
            PERFORM admissions.notify_applicant(r.id, 'Your Post-UTME batch has been ' || lower(p_state),
                'Batch ' || b.label || ' on ' || to_char(b.held_on, 'FMDay DD FMMonth YYYY') || ' at ' || b.venue || ' has been ' || lower(p_state) || ': ' || v_reason
                || '. You will be given a new date and seat; the portal and your email will carry the new slip. The earlier slip no longer admits you.',
                'MOAUM Post-UTME: batch ' || b.label || ' ' || lower(p_state) || '. A new schedule follows; watch the portal.');
        END IF;
        n := n + 1;
    END LOOP;
    PERFORM set_config('moaum.putme_reason', '', true);
    UPDATE admissions.screening_batch SET state = p_state, note = v_reason WHERE id = p_batch;
    PERFORM admissions.putme_log(b.exam_id, p_batch, NULL, p_state, b.state, p_state, v_reason || ' · ' || n || ' candidate(s) unseated');
    RETURN n;
END $$;

/* the door: the candidate checked in on the active seating */
CREATE OR REPLACE FUNCTION admissions.putme_checkin(p_app uuid, p_by uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE sa admissions.screening_assignment; b admissions.screening_batch;
BEGIN
    SELECT * INTO sa FROM admissions.screening_assignment WHERE application_id = p_app AND state = 'ACTIVE' FOR UPDATE;
    IF sa.id IS NULL THEN RAISE EXCEPTION 'the candidate is not seated in any batch' USING ERRCODE = '23514'; END IF;
    SELECT * INTO b FROM admissions.screening_batch WHERE id = sa.batch_id;
    IF b.state <> 'PUBLISHED' THEN RAISE EXCEPTION 'batch % is %; check-in is at a published batch', b.label, lower(b.state) USING ERRCODE = '23514'; END IF;
    IF sa.attendance IN ('CHECKED_IN','PRESENT') THEN RETURN 'already checked in at ' || to_char(sa.checked_in_at, 'HH24:MI'); END IF;
    IF sa.attendance = 'DISQUALIFIED' THEN RAISE EXCEPTION 'the candidate is disqualified' USING ERRCODE = '23514'; END IF;
    UPDATE admissions.screening_assignment SET checked_in_at = now(), checked_in_by = p_by, attendance = 'CHECKED_IN' WHERE id = sa.id;
    PERFORM admissions.putme_log(b.exam_id, b.id, p_app, 'CHECKED_IN', sa.attendance, 'CHECKED_IN', 'seat ' || sa.seat);
    RETURN 'checked in';
END $$;

/* attendance and the examination's status marked on the active seating */
CREATE OR REPLACE FUNCTION admissions.putme_mark(p_app uuid, p_attendance text, p_exam_status text, p_remarks text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE sa admissions.screening_assignment;
BEGIN
    SELECT * INTO sa FROM admissions.screening_assignment WHERE application_id = p_app AND state = 'ACTIVE' FOR UPDATE;
    IF sa.id IS NULL THEN RAISE EXCEPTION 'the candidate is not seated in any batch' USING ERRCODE = '23514'; END IF;
    UPDATE admissions.screening_assignment
       SET attendance = coalesce(p_attendance, attendance), exam_status = coalesce(p_exam_status, exam_status), remarks = coalesce(nullif(btrim(coalesce(p_remarks, '')), ''), remarks)
     WHERE id = sa.id;
    PERFORM admissions.putme_log((SELECT exam_id FROM admissions.screening_batch WHERE id = sa.batch_id), sa.batch_id, p_app, 'MARKED',
        sa.attendance || '/' || sa.exam_status, coalesce(p_attendance, sa.attendance) || '/' || coalesce(p_exam_status, sa.exam_status), p_remarks);
END $$;

-- ── grants ────────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE ON admissions.putme_exam, admissions.cbt_centre, admissions.cbt_room, admissions.cbt_workstation, admissions.putme_slot,
      admissions.putme_day, admissions.putme_exam_centre, admissions.screening_assignment, admissions.putme_event TO app_admissions;
GRANT SELECT ON admissions.putme_exam, admissions.cbt_centre, admissions.cbt_room, admissions.cbt_workstation, admissions.putme_slot,
      admissions.putme_day, admissions.putme_exam_centre, admissions.screening_assignment, admissions.putme_event TO app_auditor;

COMMIT;
