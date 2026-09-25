-- ═══════════════════════════════════════════════════════════════════════════
-- V261 — the accommodation lifecycle on the hostel module (V030)
--
--   V030 gave the University the fair part: the ballot from a published seed,
--   the hold that lapses to the next name, the fee that makes the bed a room.
--   This carries the rest of a stay on the record:
--     · the inventory as it is: a hall of a kind and a campus, its blocks and
--       floors, rooms of a stated type, beds that are rows (so a bed under
--       maintenance is a bed nobody is given), facilities and assets;
--     · the application window with its eligibility rules, the preferences
--       and the roommate request, the review desk and the waitlist;
--     · the allocation with a reference, accepted under the hostel rules or
--       declined, checked in at the porter's lodge, moved on a transfer,
--       checked out through an inspection, the damage charged or waived, and
--       the hostel clearance that releases the bed and signs the graduation
--       clearance unit;
--     · every step on a trail, the student told at every turn, the housing
--       desk told what waits, and the whole history of where a student has
--       stayed.
--   Every V030 function keeps its name and its rule; the property test that
--   drew three applicants over two beds still draws them the same way.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'housing', true),
       set_config('moaum.reason', 'V261: accommodation lifecycle', true);

-- ── 1 · the inventory ────────────────────────────────────────────────────

ALTER TABLE hostel.hall
    ADD COLUMN IF NOT EXISTS kind        text NOT NULL DEFAULT 'UNDERGRADUATE',
    ADD COLUMN IF NOT EXISTS campus      text NULL,
    ADD COLUMN IF NOT EXISTS location    text NULL,
    ADD COLUMN IF NOT EXISTS description text NULL,
    ADD COLUMN IF NOT EXISTS state       text NOT NULL DEFAULT 'ACTIVE',
    ADD COLUMN IF NOT EXISTS state_reason text NULL,
    ADD CONSTRAINT ck_hall_state CHECK (state IN ('ACTIVE','CLOSED'));

/* the kinds of hall are configuration, not a list in the code */
CREATE TABLE hostel.hall_kind (
    code   text PRIMARY KEY,
    label  text NOT NULL,
    active boolean NOT NULL DEFAULT true,
    CONSTRAINT ck_hk_code CHECK (code ~ '^[A-Z][A-Z0-9_]{1,30}$')
);
SELECT audit.attach('hostel.hall_kind');
INSERT INTO hostel.hall_kind (code, label) VALUES
    ('UNDERGRADUATE', 'Undergraduate'), ('POSTGRADUATE', 'Postgraduate'), ('STAFF', 'Staff'), ('INTERNATIONAL', 'International'),
    ('MEDICAL', 'Medical / Health'), ('SPECIAL_NEEDS', 'Special needs'), ('OTHER', 'Other');
ALTER TABLE hostel.hall ADD CONSTRAINT fk_hall_kind FOREIGN KEY (kind) REFERENCES hostel.hall_kind(code);

CREATE TABLE hostel.room_type (
    code   text PRIMARY KEY,
    label  text NOT NULL,
    beds   int  NOT NULL,
    active boolean NOT NULL DEFAULT true,
    CONSTRAINT ck_rt_code CHECK (code ~ '^[A-Z][A-Z0-9_]{1,30}$'),
    CONSTRAINT ck_rt_beds CHECK (beds BETWEEN 1 AND 12)
);
SELECT audit.attach('hostel.room_type');
INSERT INTO hostel.room_type (code, label, beds) VALUES
    ('SINGLE', 'Single', 1), ('DOUBLE', 'Double', 2), ('TRIPLE', 'Triple', 3), ('QUADRUPLE', 'Quadruple', 4), ('SIX_BED', 'Six-bed', 6), ('EIGHT_BED', 'Eight-bed', 8), ('OTHER', 'Other', 12);

CREATE TABLE hostel.block (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    hall_code text NOT NULL REFERENCES hostel.hall(code) ON DELETE CASCADE,
    code      text NOT NULL,
    name      text NOT NULL,
    floors    int  NOT NULL DEFAULT 1,
    state     text NOT NULL DEFAULT 'ACTIVE',
    state_reason text NULL,
    note      text NULL,
    UNIQUE (hall_code, code),
    CONSTRAINT ck_block_floors CHECK (floors BETWEEN 1 AND 30),
    CONSTRAINT ck_block_state CHECK (state IN ('ACTIVE','CLOSED'))
);
SELECT audit.attach('hostel.block');

ALTER TABLE hostel.room
    ADD COLUMN IF NOT EXISTS block_id  uuid NULL REFERENCES hostel.block(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS floor     int  NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS room_type text NULL REFERENCES hostel.room_type(code),
    ADD COLUMN IF NOT EXISTS sex       text NULL,
    ADD COLUMN IF NOT EXISTS state     text NOT NULL DEFAULT 'AVAILABLE',
    ADD COLUMN IF NOT EXISTS state_reason text NULL,
    ADD CONSTRAINT ck_room_state CHECK (state IN ('AVAILABLE','MAINTENANCE','CLOSED','RESERVED')),
    ADD CONSTRAINT ck_room_sex CHECK (sex IS NULL OR sex IN ('F','M')),
    ADD CONSTRAINT ck_room_floor CHECK (floor BETWEEN 0 AND 30);

/* a bed is a row: it can be under maintenance, out of service, or free to be given */
CREATE TABLE hostel.bed (
    id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id uuid NOT NULL REFERENCES hostel.room(id) ON DELETE CASCADE,
    number  int  NOT NULL,
    label   text NOT NULL,
    state   text NOT NULL DEFAULT 'AVAILABLE',
    state_reason text NULL,
    UNIQUE (room_id, number),
    CONSTRAINT ck_bed_state CHECK (state IN ('AVAILABLE','MAINTENANCE','OUT_OF_SERVICE'))
);
CREATE INDEX ix_bed_room ON hostel.bed (room_id, state);
SELECT audit.attach('hostel.bed');

CREATE TABLE hostel.facility (
    code   text PRIMARY KEY,
    label  text NOT NULL,
    active boolean NOT NULL DEFAULT true,
    CONSTRAINT ck_fac_code CHECK (code ~ '^[A-Z][A-Z0-9_]{1,30}$')
);
SELECT audit.attach('hostel.facility');
INSERT INTO hostel.facility (code, label) VALUES
    ('BED', 'Bed'), ('MATTRESS', 'Mattress'), ('WARDROBE', 'Wardrobe'), ('READING_TABLE', 'Reading table'), ('CHAIR', 'Chair'), ('FAN', 'Fan'),
    ('AIR_CONDITIONER', 'Air conditioner'), ('BATHROOM', 'Bathroom'), ('TOILET', 'Toilet'), ('WATER', 'Water supply'), ('POWER', 'Power supply'),
    ('GENERATOR', 'Generator'), ('INTERNET', 'Internet / Wi-Fi'), ('FIRE_EXTINGUISHER', 'Fire extinguisher'), ('SECURITY', 'Security system');

CREATE TABLE hostel.room_facility (
    room_id       uuid NOT NULL REFERENCES hostel.room(id) ON DELETE CASCADE,
    facility_code text NOT NULL REFERENCES hostel.facility(code),
    quantity      int  NOT NULL DEFAULT 1,
    PRIMARY KEY (room_id, facility_code),
    CONSTRAINT ck_rf_qty CHECK (quantity BETWEEN 0 AND 100)
);
SELECT audit.attach('hostel.room_facility');

CREATE TABLE hostel.asset (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tag         text NOT NULL UNIQUE,
    kind        text NOT NULL,
    hall_code   text NOT NULL REFERENCES hostel.hall(code),
    block_id    uuid NULL REFERENCES hostel.block(id) ON DELETE SET NULL,
    room_id     uuid NULL REFERENCES hostel.room(id) ON DELETE SET NULL,
    quantity    int  NOT NULL DEFAULT 1,
    condition   text NOT NULL DEFAULT 'GOOD',
    acquired_on date NULL,
    value       numeric(12,2) NULL,
    state       text NOT NULL DEFAULT 'ACTIVE',
    note        text NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_asset_condition CHECK (condition IN ('NEW','GOOD','FAIR','DAMAGED','REPAIR_REQUIRED','REPLACED','DISPOSED')),
    CONSTRAINT ck_asset_state CHECK (state IN ('ACTIVE','RETIRED')),
    CONSTRAINT ck_asset_qty CHECK (quantity BETWEEN 1 AND 1000)
);
SELECT audit.attach('hostel.asset');

/* the beds of a room follow its bed count: numbered when the room is saved, never removed — a bed the room
   no longer has is out of service, so a stay that held it stays explained */
CREATE OR REPLACE FUNCTION hostel.room_beds(p_room uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE r hostel.room; n int;
BEGIN
    SELECT * INTO r FROM hostel.room WHERE id = p_room;
    INSERT INTO hostel.bed (room_id, number, label)
    SELECT r.id, g, 'Bed ' || g FROM generate_series(1, r.beds) g
    ON CONFLICT (room_id, number) DO UPDATE SET state = CASE WHEN hostel.bed.state = 'OUT_OF_SERVICE' THEN 'AVAILABLE' ELSE hostel.bed.state END;
    UPDATE hostel.bed SET state = 'OUT_OF_SERVICE', state_reason = 'The room no longer has this bed' WHERE room_id = r.id AND number > r.beds AND state <> 'OUT_OF_SERVICE';
    SELECT count(*) INTO n FROM hostel.bed WHERE room_id = r.id AND state = 'AVAILABLE';
    RETURN n;
END $$;

/* a room names its block and its type; its out_of_service flag (V030) and its state say the same thing */
CREATE OR REPLACE FUNCTION hostel.room_before_write()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_block uuid;
BEGIN
    NEW.block := upper(btrim(NEW.block));
    SELECT id INTO v_block FROM hostel.block WHERE hall_code = NEW.hall_code AND code = NEW.block;
    IF v_block IS NULL THEN
        INSERT INTO hostel.block (hall_code, code, name) VALUES (NEW.hall_code, NEW.block, 'Block ' || NEW.block) RETURNING id INTO v_block;
    END IF;
    NEW.block_id := v_block;
    IF NEW.room_type IS NULL THEN
        SELECT code INTO NEW.room_type FROM hostel.room_type WHERE beds = NEW.beds AND active ORDER BY code LIMIT 1;
        IF NEW.room_type IS NULL THEN NEW.room_type := 'OTHER'; END IF;
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF NEW.out_of_service AND NEW.state = 'AVAILABLE' THEN NEW.state := 'MAINTENANCE'; END IF;
        NEW.out_of_service := NEW.state IN ('MAINTENANCE','CLOSED');
    ELSE
        IF NEW.state IS DISTINCT FROM OLD.state THEN
            NEW.out_of_service := NEW.state IN ('MAINTENANCE','CLOSED');
        ELSIF NEW.out_of_service IS DISTINCT FROM OLD.out_of_service THEN
            NEW.state := CASE WHEN NEW.out_of_service THEN 'MAINTENANCE' ELSE 'AVAILABLE' END;
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_room_before_write BEFORE INSERT OR UPDATE ON hostel.room
FOR EACH ROW EXECUTE FUNCTION hostel.room_before_write();

CREATE OR REPLACE FUNCTION hostel.room_after_write()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.beds IS DISTINCT FROM OLD.beds THEN PERFORM hostel.room_beds(NEW.id); END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_room_after_write AFTER INSERT OR UPDATE ON hostel.room
FOR EACH ROW EXECUTE FUNCTION hostel.room_after_write();

-- every room already on the record gets its block and its beds
INSERT INTO hostel.block (hall_code, code, name)
SELECT DISTINCT r.hall_code, upper(btrim(r.block)), 'Block ' || upper(btrim(r.block)) FROM hostel.room r
ON CONFLICT (hall_code, code) DO NOTHING;
UPDATE hostel.room r SET block_id = b.id, room_type = coalesce(r.room_type, (SELECT code FROM hostel.room_type t WHERE t.beds = r.beds ORDER BY code LIMIT 1), 'OTHER'),
       state = CASE WHEN r.out_of_service THEN 'MAINTENANCE' ELSE 'AVAILABLE' END
  FROM hostel.block b WHERE b.hall_code = r.hall_code AND b.code = upper(btrim(r.block));
SELECT hostel.room_beds(id) FROM hostel.room;

-- ── 2 · the window and its rules ─────────────────────────────────────────

ALTER TABLE hostel.session_setting
    ADD COLUMN IF NOT EXISTS applications_open   date NULL,
    ADD COLUMN IF NOT EXISTS allocation_method   text NOT NULL DEFAULT 'BALLOT',
    ADD COLUMN IF NOT EXISTS requires_review     boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS waitlist            boolean NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS max_applications    int NULL,
    ADD COLUMN IF NOT EXISTS eligible_statuses   text[] NOT NULL DEFAULT ARRAY['ACTIVE','ADMITTED','PROBATION'],
    ADD COLUMN IF NOT EXISTS eligible_levels     int[] NULL,
    ADD COLUMN IF NOT EXISTS eligible_faculties  text[] NULL,
    ADD COLUMN IF NOT EXISTS eligible_kinds      text[] NULL,
    ADD COLUMN IF NOT EXISTS require_registration boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS refuse_hostel_debt  boolean NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS rules               text NULL,
    ADD COLUMN IF NOT EXISTS rules_version       int NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS stay_from           date NULL,
    ADD COLUMN IF NOT EXISTS stay_to             date NULL,
    ADD COLUMN IF NOT EXISTS state               text NOT NULL DEFAULT 'OPEN',
    ADD COLUMN IF NOT EXISTS updated_at          timestamptz NOT NULL DEFAULT now(),
    ADD CONSTRAINT ck_hs_method CHECK (allocation_method IN ('BALLOT','FIRST_COME','LEVEL','FACULTY','PROGRAMME','SPECIAL_NEEDS','MANUAL')),
    ADD CONSTRAINT ck_hs_state CHECK (state IN ('DRAFT','OPEN','CLOSED','ALLOCATED')),
    ADD CONSTRAINT ck_hs_max CHECK (max_applications IS NULL OR max_applications > 0);
UPDATE hostel.session_setting SET state = CASE WHEN drawn_at IS NOT NULL THEN 'ALLOCATED' WHEN applications_close IS NOT NULL AND applications_close < current_date THEN 'CLOSED' ELSE 'OPEN' END;

-- ── 3 · the application: a reference, preferences, a roommate, a review ──

ALTER TABLE hostel.application
    ADD COLUMN IF NOT EXISTS reference        text NULL,
    ADD COLUMN IF NOT EXISTS room_type_pref   text NULL REFERENCES hostel.room_type(code),
    ADD COLUMN IF NOT EXISTS block_pref       text NULL,
    ADD COLUMN IF NOT EXISTS special_need     text NULL,
    ADD COLUMN IF NOT EXISTS roommate_id      uuid NULL REFERENCES people.student(id),
    ADD COLUMN IF NOT EXISTS roommate_note    text NULL,
    ADD COLUMN IF NOT EXISTS review           text NULL,
    ADD COLUMN IF NOT EXISTS review_note      text NULL,
    ADD COLUMN IF NOT EXISTS reviewed_by      uuid NULL,
    ADD COLUMN IF NOT EXISTS reviewed_at      timestamptz NULL,
    ADD COLUMN IF NOT EXISTS withdrawn_at     timestamptz NULL,
    ADD COLUMN IF NOT EXISTS withdrawn_reason text NULL,
    ADD CONSTRAINT ck_ha_review CHECK (review IS NULL OR review IN ('APPROVED','REJECTED','WAITLISTED','CORRECTION'));
ALTER TABLE hostel.application DROP CONSTRAINT ck_ha_state;
ALTER TABLE hostel.application ADD CONSTRAINT ck_ha_state CHECK (state IN ('APPLIED','ALLOCATED','CONFIRMED','LAPSED','UNSUCCESSFUL','WITHDRAWN','REJECTED'));

/* HST-YYYY-NNNNN, a series that never reuses a number */
CREATE OR REPLACE FUNCTION hostel.next_ref(p_kind text, p_prefix text)
RETURNS text LANGUAGE sql AS $$
    SELECT p_prefix || '-' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '-'
           || lpad(platform.next_number(p_kind, 'UNIVERSITY', to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY'))::text, 5, '0');
$$;
UPDATE hostel.application SET reference = hostel.next_ref('HOSTEL_APPLICATION', 'HST') WHERE reference IS NULL;
ALTER TABLE hostel.application ALTER COLUMN reference SET NOT NULL, ALTER COLUMN reference SET DEFAULT hostel.next_ref('HOSTEL_APPLICATION', 'HST');
CREATE UNIQUE INDEX uq_ha_reference ON hostel.application (reference);

-- ── 4 · the allocation: a reference, a bed, a state, and every date of the stay ──

ALTER TABLE hostel.allocation
    ADD COLUMN IF NOT EXISTS reference_no      text NULL,
    ADD COLUMN IF NOT EXISTS student_id        uuid NULL REFERENCES people.student(id),
    ADD COLUMN IF NOT EXISTS bed_id            uuid NULL REFERENCES hostel.bed(id),
    ADD COLUMN IF NOT EXISTS state             text NOT NULL DEFAULT 'HELD',
    ADD COLUMN IF NOT EXISTS start_on          date NULL,
    ADD COLUMN IF NOT EXISTS end_on            date NULL,
    ADD COLUMN IF NOT EXISTS accepted_at       timestamptz NULL,
    ADD COLUMN IF NOT EXISTS rules_version     int NULL,
    ADD COLUMN IF NOT EXISTS declined_at       timestamptz NULL,
    ADD COLUMN IF NOT EXISTS decline_reason    text NULL,
    ADD COLUMN IF NOT EXISTS checked_in_at     timestamptz NULL,
    ADD COLUMN IF NOT EXISTS checked_in_by     uuid NULL,
    ADD COLUMN IF NOT EXISTS checkin_note      text NULL,
    ADD COLUMN IF NOT EXISTS checkout_requested_at timestamptz NULL,
    ADD COLUMN IF NOT EXISTS checkout_on       date NULL,
    ADD COLUMN IF NOT EXISTS checkout_reason   text NULL,
    ADD COLUMN IF NOT EXISTS checked_out_at    timestamptz NULL,
    ADD COLUMN IF NOT EXISTS checked_out_by    uuid NULL,
    ADD COLUMN IF NOT EXISTS moved_from        uuid NULL REFERENCES hostel.allocation(id),
    ADD CONSTRAINT ck_hal_state CHECK (state IN ('HELD','CONFIRMED','ACCEPTED','CHECKED_IN','CHECKED_OUT','DECLINED','LAPSED','CANCELLED','TRANSFERRED'));
UPDATE hostel.allocation al SET student_id = ap.student_id FROM hostel.application ap WHERE ap.id = al.application_id AND al.student_id IS NULL;
UPDATE hostel.allocation al SET bed_id = b.id FROM hostel.bed b WHERE b.room_id = al.room_id AND b.number = al.bed AND al.bed_id IS NULL;
UPDATE hostel.allocation SET reference_no = hostel.next_ref('HOSTEL_ALLOCATION', 'ALC') WHERE reference_no IS NULL;
UPDATE hostel.allocation SET state = CASE WHEN ended_at IS NOT NULL THEN 'CANCELLED' WHEN lapsed_at IS NOT NULL THEN 'LAPSED' WHEN confirmed_at IS NOT NULL THEN 'CONFIRMED' ELSE 'HELD' END;
ALTER TABLE hostel.allocation ALTER COLUMN student_id SET NOT NULL, ALTER COLUMN reference_no SET NOT NULL,
    ALTER COLUMN reference_no SET DEFAULT hostel.next_ref('HOSTEL_ALLOCATION', 'ALC');
CREATE UNIQUE INDEX uq_hal_reference ON hostel.allocation (reference_no);
CREATE INDEX ix_hal_student ON hostel.allocation (student_id, session);
-- one live allocation per student per session, whatever route it came by
CREATE UNIQUE INDEX uq_hal_one_live ON hostel.allocation (student_id, session) WHERE lapsed_at IS NULL AND ended_at IS NULL;

-- ── 5 · the trail, and who is told ──────────────────────────────────────

CREATE TABLE hostel.event (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NULL REFERENCES hostel.application(id) ON DELETE CASCADE,
    allocation_id  uuid NULL REFERENCES hostel.allocation(id) ON DELETE CASCADE,
    student_id     uuid NULL REFERENCES people.student(id) ON DELETE CASCADE,
    hall_code      text NULL,
    room_id        uuid NULL REFERENCES hostel.room(id) ON DELETE CASCADE,
    bed_id         uuid NULL REFERENCES hostel.bed(id) ON DELETE CASCADE,
    action         text NOT NULL,
    from_value     text NULL,
    to_value       text NULL,
    note           text NULL,
    actor_id       uuid NULL,
    actor_office   text NULL,
    at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_hev_allocation ON hostel.event (allocation_id, at);
CREATE INDEX ix_hev_student ON hostel.event (student_id, at);
CREATE INDEX ix_hev_room ON hostel.event (room_id, at);
SELECT audit.attach('hostel.event');
CREATE OR REPLACE FUNCTION hostel.event_is_written_once()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('moaum.maintenance', true) = 'on' THEN RETURN NEW; END IF;
    RAISE EXCEPTION 'the accommodation trail is written once; it is not edited' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_hostel_event_written_once BEFORE UPDATE ON hostel.event FOR EACH ROW EXECUTE FUNCTION hostel.event_is_written_once();

CREATE OR REPLACE FUNCTION hostel.log(p_app uuid, p_alloc uuid, p_student uuid, p_hall text, p_room uuid, p_bed uuid, p_action text, p_from text, p_to text, p_note text)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO hostel.event (application_id, allocation_id, student_id, hall_code, room_id, bed_id, action, from_value, to_value, note, actor_id, actor_office)
    VALUES (p_app, p_alloc, p_student, p_hall, p_room, p_bed, p_action, p_from, p_to, p_note,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
$$;

CREATE OR REPLACE FUNCTION hostel.tell_student(p_student uuid, p_subject text, p_body text, p_sms text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE reach record;
BEGIN
    SELECT * INTO reach FROM people.student_reach(p_student);
    PERFORM platform.queue_notice('EMAIL', reach.email, p_subject, p_body, 'student', p_student);
    PERFORM platform.queue_notice('SMS', reach.phone, p_subject, coalesce(p_sms, left(p_body, 150)), 'student', p_student);
END $$;

/* the housing desk, and Student Services, told what waits — every person holding either office today */
CREATE OR REPLACE FUNCTION hostel.tell_desk(p_subject text, p_body text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT DISTINCT pe.id, pe.email FROM iam.office_assignment a JOIN iam.person pe ON pe.id = a.person_id
         WHERE a.office_code IN ('housing','services') AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) AND pe.email IS NOT NULL
    LOOP
        PERFORM platform.queue_notice('EMAIL', r.email, p_subject, p_body, 'person', r.id);
    END LOOP;
END $$;

-- ── 6 · eligibility, read from the record against the session's rules ───

CREATE OR REPLACE FUNCTION hostel.eligibility(p_student uuid, p_session text)
RETURNS TABLE (ok boolean, why text)
LANGUAGE plpgsql STABLE AS $$
DECLARE s hostel.session_setting; st people.student; v_fac text; v_debt numeric;
BEGIN
    SELECT * INTO s FROM hostel.session_setting WHERE session = p_session;
    IF s.session IS NULL THEN RETURN QUERY SELECT false, 'Accommodation for ' || p_session || ' is not open'; RETURN; END IF;
    SELECT * INTO st FROM people.student WHERE id = p_student;
    IF st.id IS NULL THEN RETURN QUERY SELECT false, 'No student record'; RETURN; END IF;
    IF NOT (st.status = ANY (s.eligible_statuses)) THEN RETURN QUERY SELECT false, 'A student whose status is ' || lower(replace(st.status, '_', ' ')) || ' is not eligible'; RETURN; END IF;
    IF s.eligible_levels IS NOT NULL AND array_length(s.eligible_levels, 1) > 0 AND NOT (st.current_level = ANY (s.eligible_levels)) THEN
        RETURN QUERY SELECT false, st.current_level || ' Level is not eligible this session'; RETURN;
    END IF;
    SELECT p.faculty_code INTO v_fac FROM ref.programme p WHERE p.code = st.programme_code;
    IF s.eligible_faculties IS NOT NULL AND array_length(s.eligible_faculties, 1) > 0 AND NOT (v_fac = ANY (s.eligible_faculties)) THEN
        RETURN QUERY SELECT false, 'The faculty is not eligible this session'; RETURN;
    END IF;
    IF s.require_registration AND NOT EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = st.id AND r.session = p_session AND r.status IN ('SUBMITTED','APPROVED','LOCKED')) THEN
        RETURN QUERY SELECT false, 'Course registration for ' || p_session || ' has not been submitted'; RETURN;
    END IF;
    IF s.refuse_hostel_debt THEN
        SELECT coalesce(sum(c.charge), 0) INTO v_debt FROM hostel.damage_charge c JOIN hostel.allocation al ON al.id = c.allocation_id
         WHERE al.student_id = st.id AND c.waived_at IS NULL AND c.settled_at IS NULL;
        IF v_debt > 0 THEN RETURN QUERY SELECT false, 'An unsettled hostel damage charge of NGN ' || v_debt::text || ' stands'; RETURN; END IF;
        IF EXISTS (SELECT 1 FROM hostel.clearance c JOIN hostel.allocation al ON al.id = c.allocation_id WHERE al.student_id = st.id AND c.state = 'NOT_CLEARED') THEN
            RETURN QUERY SELECT false, 'A previous stay was not cleared'; RETURN;
        END IF;
    END IF;
    IF EXISTS (SELECT 1 FROM hostel.allocation al WHERE al.student_id = st.id AND al.session <> p_session AND al.state = 'CHECKED_IN') THEN
        RETURN QUERY SELECT false, 'The student is still checked in to a room of another session'; RETURN;
    END IF;
    RETURN QUERY SELECT true, 'Eligible';
END $$;

-- ── 7 · the tables the eligibility rule reads: charges and clearance ─────

CREATE TABLE hostel.inspection (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    allocation_id uuid NOT NULL REFERENCES hostel.allocation(id) ON DELETE CASCADE,
    kind          text NOT NULL DEFAULT 'CHECKOUT',
    inspected_by  uuid NULL,
    inspected_at  timestamptz NOT NULL DEFAULT now(),
    condition     text NOT NULL,
    cleanliness   text NULL,
    damages       text NULL,
    keys_returned boolean NULL,
    card_returned boolean NULL,
    remarks       text NULL,
    CONSTRAINT ck_ins_kind CHECK (kind IN ('CHECKIN','CHECKOUT')),
    CONSTRAINT ck_ins_condition CHECK (condition IN ('GOOD','FAIR','DAMAGED')),
    CONSTRAINT ck_ins_clean CHECK (cleanliness IS NULL OR cleanliness IN ('CLEAN','ACCEPTABLE','DIRTY'))
);
CREATE INDEX ix_ins_allocation ON hostel.inspection (allocation_id);
SELECT audit.attach('hostel.inspection');

CREATE TABLE hostel.damage_charge (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    allocation_id    uuid NOT NULL REFERENCES hostel.allocation(id) ON DELETE CASCADE,
    inspection_id    uuid NULL REFERENCES hostel.inspection(id) ON DELETE SET NULL,
    asset_id         uuid NULL REFERENCES hostel.asset(id) ON DELETE SET NULL,
    description      text NOT NULL,
    repair_cost      numeric(12,2) NULL,
    replacement_cost numeric(12,2) NULL,
    charge           numeric(12,2) NOT NULL,
    reference        text NULL,
    raised_by        uuid NULL,
    raised_at        timestamptz NOT NULL DEFAULT now(),
    settled_at       timestamptz NULL,
    waived_at        timestamptz NULL,
    waived_by        uuid NULL,
    waived_reason    text NULL,
    CONSTRAINT ck_dc_charge CHECK (charge >= 0),
    CONSTRAINT ck_dc_waived CHECK (waived_at IS NULL OR waived_reason IS NOT NULL)
);
CREATE INDEX ix_dc_allocation ON hostel.damage_charge (allocation_id);
SELECT audit.attach('hostel.damage_charge');

CREATE TABLE hostel.clearance (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    allocation_id uuid NOT NULL UNIQUE REFERENCES hostel.allocation(id) ON DELETE CASCADE,
    reference     text NOT NULL UNIQUE DEFAULT hostel.next_ref('HOSTEL_CLEARANCE', 'HCL'),
    state         text NOT NULL DEFAULT 'PENDING',
    started_at    timestamptz NOT NULL DEFAULT now(),
    started_by    uuid NULL,
    completed_at  timestamptz NULL,
    completed_by  uuid NULL,
    note          text NULL,
    CONSTRAINT ck_hcl_state CHECK (state IN ('PENDING','CLEARED','NOT_CLEARED'))
);
SELECT audit.attach('hostel.clearance');

CREATE TABLE hostel.clearance_requirement (
    code   text PRIMARY KEY,
    label  text NOT NULL,
    ord    int  NOT NULL,
    active boolean NOT NULL DEFAULT true
);
SELECT audit.attach('hostel.clearance_requirement');
INSERT INTO hostel.clearance_requirement (code, label, ord) VALUES
    ('ROOM_RETURNED', 'Room returned in good order', 1), ('BED_RETURNED', 'Bed and mattress returned', 2), ('KEY_RETURNED', 'Key returned', 3),
    ('ACCESS_CARD_RETURNED', 'Access card returned', 4), ('ASSETS_RETURNED', 'Furniture and assets accounted for', 5), ('NO_DAMAGE', 'No damage outstanding', 6),
    ('NO_MAINTENANCE_ISSUE', 'No maintenance issue assigned to the student', 7), ('FEES_SETTLED', 'Accommodation fee settled', 8), ('DAMAGE_CHARGES_SETTLED', 'Damage charges settled', 9);

CREATE TABLE hostel.clearance_item (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    clearance_id uuid NOT NULL REFERENCES hostel.clearance(id) ON DELETE CASCADE,
    requirement  text NOT NULL REFERENCES hostel.clearance_requirement(code),
    state        text NOT NULL DEFAULT 'PENDING',
    officer_id   uuid NULL,
    decided_at   timestamptz NULL,
    remarks      text NULL,
    UNIQUE (clearance_id, requirement),
    CONSTRAINT ck_hci_state CHECK (state IN ('PENDING','CLEARED','NOT_CLEARED','WAIVED','NOT_APPLICABLE'))
);
SELECT audit.attach('hostel.clearance_item');

CREATE TABLE hostel.transfer_request (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    allocation_id   uuid NOT NULL REFERENCES hostel.allocation(id) ON DELETE CASCADE,
    student_id      uuid NOT NULL REFERENCES people.student(id),
    requested_hall  text NULL REFERENCES hostel.hall(code),
    requested_type  text NULL REFERENCES hostel.room_type(code),
    reason          text NOT NULL,
    state           text NOT NULL DEFAULT 'SUBMITTED',
    submitted_at    timestamptz NOT NULL DEFAULT now(),
    decided_by      uuid NULL,
    decided_at      timestamptz NULL,
    decision_note   text NULL,
    new_allocation  uuid NULL REFERENCES hostel.allocation(id),
    CONSTRAINT ck_tr_state CHECK (state IN ('SUBMITTED','UNDER_REVIEW','APPROVED','REJECTED','COMPLETED','CANCELLED')),
    CONSTRAINT ck_tr_reason CHECK (btrim(reason) <> '')
);
CREATE INDEX ix_tr_allocation ON hostel.transfer_request (allocation_id, state);
SELECT audit.attach('hostel.transfer_request');

ALTER TABLE hostel.maintenance_request
    ADD COLUMN IF NOT EXISTS category    text NOT NULL DEFAULT 'OTHER',
    ADD COLUMN IF NOT EXISTS priority    text NOT NULL DEFAULT 'NORMAL',
    ADD COLUMN IF NOT EXISTS bed_id      uuid NULL REFERENCES hostel.bed(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS asset_id    uuid NULL REFERENCES hostel.asset(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS assigned_to text NULL,
    ADD CONSTRAINT ck_hm_category CHECK (category IN ('BED','FURNITURE','WATER','ELECTRICITY','PLUMBING','INTERNET','CLEANING','SECURITY','OTHER')),
    ADD CONSTRAINT ck_hm_priority CHECK (priority IN ('LOW','NORMAL','HIGH','URGENT'));

-- ── 8 · the free beds, from the bed rows ─────────────────────────────────

DROP FUNCTION IF EXISTS hostel.free_beds(text);
CREATE OR REPLACE FUNCTION hostel.free_beds(p_session text)
RETURNS TABLE (room_id uuid, hall_code text, hall_sex text, block text, room_no text, bed int, bed_id uuid, room_type text, floor int, block_id uuid)
LANGUAGE sql STABLE AS $$
    SELECT r.id, r.hall_code, coalesce(r.sex, h.sex), r.block, r.room_no, b.number, b.id, r.room_type, r.floor, r.block_id
      FROM hostel.room r
      JOIN hostel.hall h ON h.code = r.hall_code AND h.ended_on IS NULL AND h.state = 'ACTIVE'
      JOIN hostel.bed b ON b.room_id = r.id AND b.state = 'AVAILABLE'
      LEFT JOIN hostel.block bl ON bl.id = r.block_id
     WHERE r.state = 'AVAILABLE' AND (bl.id IS NULL OR bl.state = 'ACTIVE')
       AND NOT EXISTS (SELECT 1 FROM hostel.allocation a
                        WHERE a.room_id = r.id AND a.bed = b.number AND a.lapsed_at IS NULL AND a.ended_at IS NULL AND a.session = p_session)
     ORDER BY h.code, r.block, r.room_no, b.number
$$;

/* the one door every seating passes through: the checks, the row, the trail */
CREATE OR REPLACE FUNCTION hostel.hold(p_application uuid, p_bed uuid, p_basis text, p_position int, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE ap hostel.application; s hostel.session_setting; b hostel.bed; r hostel.room; h hostel.hall; st people.student; e record; v uuid; v_state text;
BEGIN
    SELECT * INTO ap FROM hostel.application WHERE id = p_application FOR UPDATE;
    IF ap.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    SELECT * INTO s FROM hostel.session_setting WHERE session = ap.session;
    SELECT * INTO b FROM hostel.bed WHERE id = p_bed FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such bed' USING ERRCODE = '23503'; END IF;
    SELECT * INTO r FROM hostel.room WHERE id = b.room_id;
    SELECT * INTO h FROM hostel.hall WHERE code = r.hall_code;
    SELECT * INTO st FROM people.student WHERE id = ap.student_id;
    IF ap.state NOT IN ('APPLIED','UNSUCCESSFUL','LAPSED') THEN RAISE EXCEPTION 'application % is %; only one that waits is seated', ap.reference, lower(ap.state) USING ERRCODE = '23514'; END IF;
    IF ap.review = 'REJECTED' THEN RAISE EXCEPTION 'application % was rejected at review', ap.reference USING ERRCODE = '23514'; END IF;
    IF s.requires_review AND ap.review IS DISTINCT FROM 'APPROVED' THEN RAISE EXCEPTION 'application % has not been approved at review', ap.reference USING ERRCODE = '23514', HINT = 'Approve it on the applications desk first.'; END IF;
    SELECT * INTO e FROM hostel.eligibility(ap.student_id, ap.session);
    IF NOT e.ok THEN RAISE EXCEPTION 'the student is not eligible: %', e.why USING ERRCODE = '23514'; END IF;
    IF b.state <> 'AVAILABLE' THEN RAISE EXCEPTION 'bed % of room % is %', b.label, r.room_no, lower(replace(b.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
    IF r.state <> 'AVAILABLE' THEN RAISE EXCEPTION 'room % is %', r.room_no, lower(r.state) USING ERRCODE = '23514'; END IF;
    IF h.state <> 'ACTIVE' OR h.ended_on IS NOT NULL THEN RAISE EXCEPTION 'hall % is closed', h.name USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM hostel.block bl WHERE bl.id = r.block_id AND bl.state <> 'ACTIVE') THEN RAISE EXCEPTION 'the block is closed' USING ERRCODE = '23514'; END IF;
    IF coalesce(r.sex, h.sex) IS NOT NULL AND st.sex IS NOT NULL AND coalesce(r.sex, h.sex) <> st.sex THEN RAISE EXCEPTION 'hall % is not for this student', h.name USING ERRCODE = '23514'; END IF;
    IF s.eligible_kinds IS NOT NULL AND array_length(s.eligible_kinds, 1) > 0 AND NOT (h.kind = ANY (s.eligible_kinds)) THEN RAISE EXCEPTION 'hall % is a % hall, not one open to this session', h.name, lower(h.kind) USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM hostel.allocation a WHERE a.room_id = r.id AND a.bed = b.number AND a.session = ap.session AND a.lapsed_at IS NULL AND a.ended_at IS NULL) THEN
        RAISE EXCEPTION 'bed % of room % is already taken', b.label, r.room_no USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM hostel.allocation a WHERE a.student_id = ap.student_id AND a.session = ap.session AND a.lapsed_at IS NULL AND a.ended_at IS NULL) THEN
        RAISE EXCEPTION 'the student already holds a bed for %', ap.session USING ERRCODE = '23514', HINT = 'Transfer the student instead; a student holds one bed a session.';
    END IF;
    v_state := CASE WHEN coalesce(s.fee, 0) = 0 THEN 'CONFIRMED' ELSE 'HELD' END;
    INSERT INTO hostel.allocation (application_id, session, room_id, bed, bed_id, student_id, basis, draw_position, held_until, state, confirmed_at, start_on, end_on)
    VALUES (ap.id, ap.session, r.id, b.number, b.id, ap.student_id, p_basis, p_position,
            now() + make_interval(hours => coalesce(s.hold_hours, 72)), v_state, CASE WHEN v_state = 'CONFIRMED' THEN now() END,
            coalesce(s.stay_from, (SELECT starts_on FROM policy.academic_session WHERE name = ap.session)),
            coalesce(s.stay_to, (SELECT ends_on FROM policy.academic_session WHERE name = ap.session)))
    RETURNING id INTO v;
    UPDATE hostel.application SET state = CASE WHEN v_state = 'CONFIRMED' THEN 'CONFIRMED' ELSE 'ALLOCATED' END, draw_position = coalesce(p_position, draw_position) WHERE id = ap.id;
    PERFORM hostel.log(ap.id, v, ap.student_id, h.code, r.id, b.id, 'ALLOCATED', NULL, h.name || ' · ' || r.block || '-' || r.room_no || ' · ' || b.label, coalesce(p_reason, p_basis));
    RETURN v;
END $$;

-- ── 9 · the application: the rules, the preferences, the roommate ────────

CREATE OR REPLACE FUNCTION hostel.apply(p_student uuid, p_session text, p_hall text, p_category text, p_note text,
                                        p_room_type text, p_block text, p_special text, p_roommate uuid, p_roommate_note text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE s hostel.session_setting; v uuid := gen_random_uuid(); v_sex text; v_hall_sex text; e record; rm people.student; v_n int;
BEGIN
    SELECT * INTO s FROM hostel.session_setting WHERE session = p_session;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'accommodation for % is not open: no fee and no hold window are stated', p_session USING ERRCODE = '23514',
            HINT = 'Student Services states the accommodation fee and the hold window for the session before applications open.';
    END IF;
    IF s.state IN ('DRAFT','CLOSED') THEN
        RAISE EXCEPTION 'applications for % are %', p_session, lower(s.state) USING ERRCODE = '23514', HINT = 'The housing desk opens the window.';
    END IF;
    IF s.drawn_at IS NOT NULL THEN
        RAISE EXCEPTION 'the draw for % has been run; applications are closed', p_session USING ERRCODE = '23514',
            HINT = 'A late application joins no list. Ask Student Services whether a lapsed bed is available.';
    END IF;
    IF s.applications_open IS NOT NULL AND s.applications_open > current_date THEN
        RAISE EXCEPTION 'applications for % open on %', p_session, s.applications_open USING ERRCODE = '23514';
    END IF;
    IF s.applications_close IS NOT NULL AND s.applications_close < current_date THEN
        RAISE EXCEPTION 'applications for % closed on %', p_session, s.applications_close USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM hostel.application WHERE student_id = p_student AND session = p_session AND state <> 'WITHDRAWN') THEN
        RAISE EXCEPTION 'an application for % already stands', p_session USING ERRCODE = '23505',
            HINT = 'One application per session; withdraw it before making another.';
    END IF;
    SELECT * INTO e FROM hostel.eligibility(p_student, p_session);
    IF NOT e.ok THEN RAISE EXCEPTION 'not eligible for accommodation: %', e.why USING ERRCODE = '23514'; END IF;
    IF s.max_applications IS NOT NULL THEN
        SELECT count(*) INTO v_n FROM hostel.application WHERE session = p_session AND state <> 'WITHDRAWN';
        IF v_n >= s.max_applications THEN RAISE EXCEPTION 'the application window for % is full (% applications)', p_session, s.max_applications USING ERRCODE = '23514'; END IF;
    END IF;
    SELECT sex INTO v_sex FROM people.student WHERE id = p_student;
    IF p_hall IS NOT NULL THEN
        SELECT sex INTO v_hall_sex FROM hostel.hall WHERE code = p_hall AND ended_on IS NULL AND state = 'ACTIVE';
        IF NOT FOUND THEN RAISE EXCEPTION 'no hall %', p_hall USING ERRCODE = '23503'; END IF;
        IF v_hall_sex IS NOT NULL AND v_sex IS NOT NULL AND v_hall_sex <> v_sex THEN
            RAISE EXCEPTION 'hall % is not for this student', p_hall USING ERRCODE = '23514';
        END IF;
    END IF;
    IF p_roommate IS NOT NULL THEN
        SELECT * INTO rm FROM people.student WHERE id = p_roommate;
        IF rm.id IS NULL THEN RAISE EXCEPTION 'no such student for the roommate request' USING ERRCODE = '23503'; END IF;
        IF rm.id = p_student THEN RAISE EXCEPTION 'a roommate is another student' USING ERRCODE = '23514'; END IF;
        IF rm.sex IS NOT NULL AND v_sex IS NOT NULL AND rm.sex <> v_sex THEN RAISE EXCEPTION 'a roommate shares the hall, so shares the sex restriction' USING ERRCODE = '23514'; END IF;
        SELECT * INTO e FROM hostel.eligibility(rm.id, p_session);
        IF NOT e.ok THEN RAISE EXCEPTION 'the roommate asked for is not eligible: %', e.why USING ERRCODE = '23514'; END IF;
    END IF;
    INSERT INTO hostel.application (id, student_id, session, hall_code, category, category_note, room_type_pref, block_pref, special_need, roommate_id, roommate_note,
                                    review)
    VALUES (v, p_student, p_session, p_hall, coalesce(upper(p_category), 'NONE'), nullif(btrim(p_note), ''), p_room_type, nullif(upper(btrim(p_block)), ''),
            nullif(btrim(p_special), ''), p_roommate, nullif(btrim(p_roommate_note), ''), CASE WHEN s.requires_review THEN NULL ELSE 'APPROVED' END);
    PERFORM hostel.log(v, NULL, p_student, p_hall, NULL, NULL, 'APPLIED', NULL, 'APPLIED', 'Application ' || (SELECT reference FROM hostel.application WHERE id = v));
    PERFORM hostel.tell_student(p_student, 'Your hostel application is in',
        'Your application for accommodation in ' || p_session || ' has been received, reference ' || (SELECT reference FROM hostel.application WHERE id = v) || '. '
        || CASE WHEN s.requires_review THEN 'It goes to the housing desk for review; you will be told the outcome.' ELSE 'Allocation follows when the window closes; you will be told your bed.' END
        || ' Preferences are not a promise of a particular hall or room.',
        'MOAUM: hostel application ' || (SELECT reference FROM hostel.application WHERE id = v) || ' received for ' || p_session || '.');
    IF s.requires_review THEN PERFORM hostel.tell_desk('A hostel application awaits review', 'Application ' || (SELECT reference FROM hostel.application WHERE id = v) || ' for ' || p_session || ' awaits review on the applications desk.'); END IF;
    RETURN v;
END $$;

/* the V030 signature stays: no preferences beyond the hall */
CREATE OR REPLACE FUNCTION hostel.apply(p_student uuid, p_session text, p_hall text, p_category text, p_note text)
RETURNS uuid LANGUAGE sql AS $$
    SELECT hostel.apply(p_student, p_session, p_hall, p_category, p_note, NULL, NULL, NULL, NULL, NULL);
$$;

CREATE OR REPLACE FUNCTION hostel.withdraw(p_application uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE ap hostel.application; al hostel.allocation;
BEGIN
    SELECT * INTO ap FROM hostel.application WHERE id = p_application FOR UPDATE;
    IF ap.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF ap.state = 'WITHDRAWN' THEN RETURN; END IF;
    SELECT * INTO al FROM hostel.allocation WHERE application_id = ap.id AND lapsed_at IS NULL AND ended_at IS NULL;
    IF al.id IS NOT NULL AND al.state = 'CHECKED_IN' THEN RAISE EXCEPTION 'a student checked in leaves by checkout, not by withdrawing the application' USING ERRCODE = '23514'; END IF;
    IF al.id IS NOT NULL THEN
        UPDATE hostel.allocation SET state = 'CANCELLED', ended_at = now(), ended_reason = 'WITHDRAWN: ' || coalesce(p_reason, 'application withdrawn') WHERE id = al.id;
        PERFORM hostel.log(ap.id, al.id, ap.student_id, NULL, al.room_id, al.bed_id, 'CANCELLED', al.state, 'CANCELLED', 'Application withdrawn: ' || coalesce(p_reason, ''));
    END IF;
    UPDATE hostel.application SET state = 'WITHDRAWN', withdrawn_at = now(), withdrawn_reason = p_reason WHERE id = ap.id;
    PERFORM hostel.log(ap.id, NULL, ap.student_id, NULL, NULL, NULL, 'WITHDRAWN', ap.state, 'WITHDRAWN', p_reason);
END $$;

/* the review desk: approved into the draw, rejected with the reason, waitlisted, or sent back for correction */
CREATE OR REPLACE FUNCTION hostel.review(p_application uuid, p_decision text, p_note text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE ap hostel.application; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF p_decision NOT IN ('APPROVED','REJECTED','WAITLISTED','CORRECTION') THEN RAISE EXCEPTION 'a review approves, rejects, waitlists or asks for a correction' USING ERRCODE = '23514'; END IF;
    IF p_decision IN ('REJECTED','CORRECTION') AND nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN RAISE EXCEPTION 'say why' USING ERRCODE = '23514'; END IF;
    SELECT * INTO ap FROM hostel.application WHERE id = p_application FOR UPDATE;
    IF ap.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF ap.state NOT IN ('APPLIED','UNSUCCESSFUL','REJECTED') THEN RAISE EXCEPTION 'application % is %; the review is over', ap.reference, lower(ap.state) USING ERRCODE = '23514'; END IF;
    UPDATE hostel.application SET review = p_decision, review_note = p_note, reviewed_by = v_actor, reviewed_at = now(),
           state = CASE p_decision WHEN 'REJECTED' THEN 'REJECTED' WHEN 'WAITLISTED' THEN 'UNSUCCESSFUL' ELSE 'APPLIED' END,
           draw_position = CASE WHEN p_decision = 'WAITLISTED' AND draw_position IS NULL THEN (SELECT coalesce(max(draw_position), 0) + 1 FROM hostel.application WHERE session = ap.session) ELSE draw_position END
     WHERE id = ap.id;
    PERFORM hostel.log(ap.id, NULL, ap.student_id, NULL, NULL, NULL, 'REVIEWED', ap.review, p_decision, p_note);
    PERFORM hostel.tell_student(ap.student_id,
        CASE p_decision WHEN 'APPROVED' THEN 'Your hostel application is approved' WHEN 'REJECTED' THEN 'Your hostel application was not approved'
                        WHEN 'WAITLISTED' THEN 'Your hostel application is on the waiting list' ELSE 'Your hostel application needs a correction' END,
        'Application ' || ap.reference || ' for ' || ap.session || ': '
        || CASE p_decision WHEN 'APPROVED' THEN 'approved for allocation. You will be told your bed when the allocation is made.'
                           WHEN 'REJECTED' THEN 'not approved. ' || coalesce(p_note, '')
                           WHEN 'WAITLISTED' THEN 'placed on the waiting list. A bed is offered in list order when one becomes free.'
                           ELSE 'the housing desk asks for a correction: ' || coalesce(p_note, '') END,
        'MOAUM: hostel application ' || ap.reference || ' ' || lower(p_decision) || '.');
END $$;

-- ── 10 · the draw, by the session's method; the lapse; the manual seating ─

CREATE OR REPLACE FUNCTION hostel.pick_bed(p_session text, p_sex text, p_hall text, p_type text, p_block text, p_kinds text[])
RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT fb.bed_id FROM hostel.free_beds(p_session) fb JOIN hostel.hall h ON h.code = fb.hall_code
     WHERE (fb.hall_sex IS NULL OR p_sex IS NULL OR fb.hall_sex = p_sex)
       AND (p_kinds IS NULL OR array_length(p_kinds, 1) IS NULL OR h.kind = ANY (p_kinds))
     ORDER BY (fb.hall_code = p_hall) DESC, (fb.room_type = p_type) DESC, (fb.block = p_block) DESC, fb.hall_code, fb.block, fb.room_no, fb.bed
     LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION hostel.draw(p_session text, p_seed text)
RETURNS TABLE (allocated int, unsuccessful int, priority int)
LANGUAGE plpgsql AS $$
DECLARE s hostel.session_setting; a record; v_bed uuid; pos int := 0; n_alloc int := 0; n_pri int := 0; n_un int := 0;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_seed text; v_alloc uuid; r record;
BEGIN
    SELECT * INTO s FROM hostel.session_setting WHERE session = p_session FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'accommodation for % is not open', p_session USING ERRCODE = '23514'; END IF;
    IF s.allocation_method = 'MANUAL' THEN RAISE EXCEPTION 'allocation for % is manual: seat each student from the applications desk', p_session USING ERRCODE = '23514'; END IF;
    v_seed := CASE WHEN s.allocation_method = 'BALLOT' THEN btrim(p_seed) ELSE coalesce(nullif(btrim(p_seed), ''), s.allocation_method) END;
    IF s.allocation_method = 'BALLOT' AND (p_seed IS NULL OR length(btrim(p_seed)) < 6) THEN
        RAISE EXCEPTION 'the draw runs from a published seed of at least six characters' USING ERRCODE = '23514',
            HINT = 'Publish the seed before the draw, not after; anybody holding it can reproduce the order.';
    END IF;
    IF s.drawn_at IS NOT NULL THEN
        RAISE EXCEPTION 'the draw for % was run on % from seed %', p_session, s.drawn_at::date, s.seed USING ERRCODE = '23514',
            HINT = 'A draw is run once. Re-running it from the same seed reproduces the same order, which is what the record already holds.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM hostel.free_beds(p_session)) THEN RAISE EXCEPTION 'no bed is free to allocate' USING ERRCODE = '23514', HINT = 'Add rooms, or return beds to service, before the draw.'; END IF;
    UPDATE hostel.session_setting SET seed = v_seed, drawn_at = now(), drawn_by = v_actor, state = 'ALLOCATED', updated_at = now() WHERE session = p_session;
    -- the order: priority categories first, by the time they applied; then everybody else by the session's method
    FOR a IN
        SELECT ap.id, ap.student_id, ap.hall_code, ap.category, ap.room_type_pref, ap.block_pref, st.sex,
               (ap.category <> 'NONE' OR (s.allocation_method = 'SPECIAL_NEEDS' AND ap.special_need IS NOT NULL)) AS is_priority
          FROM hostel.application ap JOIN people.student st ON st.id = ap.student_id
          LEFT JOIN ref.programme p ON p.code = st.programme_code
         WHERE ap.session = p_session AND ap.state = 'APPLIED' AND (NOT s.requires_review OR ap.review = 'APPROVED') AND ap.review IS DISTINCT FROM 'REJECTED'
         ORDER BY (ap.category <> 'NONE' OR (s.allocation_method = 'SPECIAL_NEEDS' AND ap.special_need IS NOT NULL)) DESC,
                  CASE WHEN ap.category <> 'NONE' THEN ap.applied_at END,
                  CASE s.allocation_method
                      WHEN 'FIRST_COME' THEN to_char(ap.applied_at, 'YYYYMMDDHH24MISSUS')
                      WHEN 'LEVEL' THEN lpad((1000 - st.current_level)::text, 4, '0') || to_char(ap.applied_at, 'YYYYMMDDHH24MISSUS')
                      WHEN 'FACULTY' THEN coalesce(p.faculty_code, 'ZZZ') || coalesce(p.dept_code, 'ZZZ') || st.surname || st.other_names
                      WHEN 'PROGRAMME' THEN coalesce(p.code, 'ZZZ') || st.surname || st.other_names
                      ELSE md5(v_seed || ap.student_id::text) END,
                  md5(v_seed || ap.student_id::text)
    LOOP
        pos := pos + 1;
        v_bed := hostel.pick_bed(p_session, a.sex, a.hall_code, a.room_type_pref, a.block_pref, s.eligible_kinds);
        IF v_bed IS NOT NULL THEN
            v_alloc := hostel.hold(a.id, v_bed, CASE WHEN a.is_priority THEN 'PRIORITY' ELSE 'BALLOT' END, pos, 'Allocation of ' || p_session || ' by ' || lower(s.allocation_method));
            n_alloc := n_alloc + 1;
            IF a.is_priority THEN n_pri := n_pri + 1; END IF;
        ELSE
            -- a reserve, in the order the draw put them: a lapsed bed follows this order, not a telephone call
            UPDATE hostel.application SET state = 'UNSUCCESSFUL', draw_position = pos WHERE id = a.id;
            PERFORM hostel.log(a.id, NULL, a.student_id, NULL, NULL, NULL, 'WAITLISTED', 'APPLIED', 'UNSUCCESSFUL', 'Position ' || pos || ': no bed free when the turn came');
            n_un := n_un + 1;
        END IF;
    END LOOP;
    -- everyone told, from the record the draw wrote
    FOR r IN
        SELECT al.id, al.student_id, al.state, al.held_until, h.name AS hall, rm.block, rm.room_no, b.label, al.reference_no
          FROM hostel.allocation al JOIN hostel.room rm ON rm.id = al.room_id JOIN hostel.hall h ON h.code = rm.hall_code JOIN hostel.bed b ON b.id = al.bed_id
         WHERE al.session = p_session AND al.lapsed_at IS NULL AND al.ended_at IS NULL AND al.allocated_at >= now() - interval '1 minute'
    LOOP
        PERFORM hostel.tell_student(r.student_id, 'You have been allocated a bed',
            'Allocation ' || r.reference_no || ' for ' || p_session || ': ' || r.hall || ', Block ' || r.block || ', Room ' || r.room_no || ', ' || r.label || '. '
            || CASE WHEN r.state = 'HELD' THEN 'The bed is held until ' || to_char(r.held_until AT TIME ZONE 'Africa/Lagos', 'FMDay DD FMMonth HH24:MI') || ' for payment of the accommodation fee; unpaid, it goes to the next name.'
                    ELSE 'Accept the allocation on the portal under the hostel rules, then check in at the porter''s lodge.' END,
            'MOAUM: bed allocated — ' || r.hall || ' ' || r.block || '-' || r.room_no || ' ' || r.label || '. See the portal.');
    END LOOP;
    FOR r IN SELECT ap.student_id, ap.draw_position FROM hostel.application ap WHERE ap.session = p_session AND ap.state = 'UNSUCCESSFUL' LOOP
        PERFORM hostel.tell_student(r.student_id, 'Your hostel application is on the waiting list',
            'Every bed was taken before your turn (position ' || r.draw_position || ') came up for ' || p_session || '. Waitlisted students are offered a bed in order when one becomes free.',
            'MOAUM: hostel waiting list position ' || r.draw_position || ' for ' || p_session || '.');
    END LOOP;
    RETURN QUERY SELECT n_alloc, n_un, n_pri;
END $$;

/* the hold runs whether anybody is watching: lapse, and move the bed on to the waiting list */
CREATE OR REPLACE FUNCTION hostel.lapse_holds(p_session text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE s hostel.session_setting; a record; nxt record; n int := 0; v uuid;
BEGIN
    SELECT * INTO s FROM hostel.session_setting WHERE session = p_session;
    IF NOT FOUND THEN RETURN 0; END IF;
    FOR a IN
        SELECT al.id, al.room_id, al.bed, al.bed_id, al.student_id, al.application_id, al.reference_no FROM hostel.allocation al JOIN hostel.application ap ON ap.id = al.application_id
         WHERE ap.session = p_session AND al.confirmed_at IS NULL AND al.lapsed_at IS NULL AND al.ended_at IS NULL AND al.held_until < now()
         ORDER BY al.held_until
    LOOP
        UPDATE hostel.allocation SET lapsed_at = now(), state = 'LAPSED' WHERE id = a.id;
        UPDATE hostel.application SET state = 'LAPSED' WHERE id = a.application_id;
        PERFORM hostel.log(a.application_id, a.id, a.student_id, NULL, a.room_id, a.bed_id, 'LAPSED', 'HELD', 'LAPSED', 'The hold expired unpaid');
        PERFORM hostel.tell_student(a.student_id, 'Your hostel hold has lapsed',
            'The bed held for you under allocation ' || a.reference_no || ' was not paid for within the hold window and has gone to the next name on the list.',
            'MOAUM: hostel hold ' || a.reference_no || ' lapsed unpaid.');
        n := n + 1;
        -- the bed goes to the next name on the draw, not back to the office
        IF s.waitlist THEN
            SELECT ap.id AS application_id, ap.draw_position, ap.student_id INTO nxt
              FROM hostel.application ap
              JOIN people.student st ON st.id = ap.student_id
              JOIN hostel.room r ON r.id = a.room_id JOIN hostel.hall h ON h.code = r.hall_code
             WHERE ap.session = p_session AND ap.state = 'UNSUCCESSFUL'
               AND (coalesce(r.sex, h.sex) IS NULL OR st.sex IS NULL OR coalesce(r.sex, h.sex) = st.sex)
               AND NOT EXISTS (SELECT 1 FROM hostel.allocation x WHERE x.student_id = ap.student_id AND x.session = p_session AND x.lapsed_at IS NULL AND x.ended_at IS NULL)
             ORDER BY ap.draw_position LIMIT 1;
            IF FOUND THEN
                BEGIN
                    v := hostel.hold(nxt.application_id, a.bed_id, 'RESERVE', nxt.draw_position, 'A lapsed hold passed to the next name on the list');
                    PERFORM hostel.tell_student(nxt.student_id, 'A hostel bed has been offered to you',
                        'A bed has become free and is held for you in list order (position ' || nxt.draw_position || '). Sign in to see it and pay the accommodation fee within the hold window.',
                        'MOAUM: a hostel bed is held for you. See the portal.');
                EXCEPTION WHEN OTHERS THEN NULL; -- a reserve who is no longer eligible is passed over
                END;
            END IF;
        END IF;
    END LOOP;
    RETURN n;
END $$;

/* the desk seats one student by hand: the same checks the draw makes */
CREATE OR REPLACE FUNCTION hostel.allocate(p_application uuid, p_bed uuid, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid; r record;
BEGIN
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'a manual allocation carries its reason' USING ERRCODE = '23514'; END IF;
    v := hostel.hold(p_application, p_bed, 'PRIORITY', NULL, 'Manual: ' || btrim(p_reason));
    SELECT al.student_id, al.state, al.held_until, h.name AS hall, rm.block, rm.room_no, b.label, al.reference_no INTO r
      FROM hostel.allocation al JOIN hostel.room rm ON rm.id = al.room_id JOIN hostel.hall h ON h.code = rm.hall_code JOIN hostel.bed b ON b.id = al.bed_id WHERE al.id = v;
    PERFORM hostel.tell_student(r.student_id, 'You have been allocated a bed',
        'Allocation ' || r.reference_no || ': ' || r.hall || ', Block ' || r.block || ', Room ' || r.room_no || ', ' || r.label || '. '
        || CASE WHEN r.state = 'HELD' THEN 'The bed is held until ' || to_char(r.held_until AT TIME ZONE 'Africa/Lagos', 'FMDay DD FMMonth HH24:MI') || ' for payment of the accommodation fee.'
                ELSE 'Accept the allocation on the portal, then check in at the porter''s lodge.' END,
        'MOAUM: bed allocated — ' || r.hall || ' ' || r.block || '-' || r.room_no || ' ' || r.label || '.');
    RETURN v;
END $$;

-- ── 11 · the fee (V030), and the damage charge settled through the same door ──

CREATE OR REPLACE FUNCTION hostel.confirm_by_reference(p_reference text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE al hostel.allocation; c hostel.damage_charge;
BEGIN
    SELECT * INTO c FROM hostel.damage_charge WHERE reference = p_reference AND settled_at IS NULL;
    IF c.id IS NOT NULL THEN
        UPDATE hostel.damage_charge SET settled_at = now() WHERE id = c.id;
        PERFORM hostel.log(NULL, c.allocation_id, (SELECT student_id FROM hostel.allocation WHERE id = c.allocation_id), NULL, NULL, NULL, 'CHARGE_SETTLED', NULL, c.charge::text, c.description);
        UPDATE hostel.clearance_item i SET state = 'CLEARED', decided_at = now(), remarks = 'Settled by payment ' || p_reference
          FROM hostel.clearance cl WHERE cl.id = i.clearance_id AND cl.allocation_id = c.allocation_id AND i.requirement = 'DAMAGE_CHARGES_SETTLED' AND i.state IN ('PENDING','NOT_CLEARED')
           AND NOT EXISTS (SELECT 1 FROM hostel.damage_charge x WHERE x.allocation_id = c.allocation_id AND x.id <> c.id AND x.settled_at IS NULL AND x.waived_at IS NULL);
        RETURN;
    END IF;
    SELECT * INTO al FROM hostel.allocation WHERE reference = p_reference AND confirmed_at IS NULL ORDER BY allocated_at DESC LIMIT 1;
    IF NOT FOUND THEN RETURN; END IF;
    IF al.lapsed_at IS NOT NULL AND EXISTS (SELECT 1 FROM hostel.allocation o WHERE o.session = al.session AND o.room_id = al.room_id AND o.bed = al.bed
                                              AND o.id <> al.id AND o.lapsed_at IS NULL AND o.ended_at IS NULL) THEN
        RAISE EXCEPTION 'the hold on this bed lapsed before the payment arrived, and the bed went to the next name on the draw'
        USING ERRCODE = '23514', HINT = 'The payment stands for the Bursary to refund or apply; Student Services allocates a bed that is free.';
    END IF;
    UPDATE hostel.allocation SET confirmed_at = now(), lapsed_at = NULL, state = 'CONFIRMED' WHERE id = al.id;
    UPDATE hostel.application SET state = 'CONFIRMED' WHERE id = al.application_id;
    PERFORM hostel.log(al.application_id, al.id, al.student_id, NULL, al.room_id, al.bed_id, 'PAID', al.state, 'CONFIRMED', 'Reference ' || p_reference);
    PERFORM hostel.tell_desk('A hostel fee has been confirmed', 'Allocation ' || al.reference_no || ' is paid and confirmed; the student may now accept and check in.');
END $$;

-- ── 12 · accepted under the rules, or declined; checked in at the lodge ──

CREATE OR REPLACE FUNCTION hostel.accept(p_allocation uuid, p_student uuid, p_rules_version int)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE al hostel.allocation; s hostel.session_setting;
BEGIN
    SELECT * INTO al FROM hostel.allocation WHERE id = p_allocation FOR UPDATE;
    IF al.id IS NULL OR al.student_id <> p_student THEN RAISE EXCEPTION 'no such allocation' USING ERRCODE = '23503'; END IF;
    SELECT * INTO s FROM hostel.session_setting WHERE session = al.session;
    IF al.state = 'HELD' THEN RAISE EXCEPTION 'the accommodation fee is paid before the allocation is accepted' USING ERRCODE = '23514', HINT = 'Generate the payment reference and pay it within the hold window.'; END IF;
    IF al.state <> 'CONFIRMED' THEN RAISE EXCEPTION 'allocation % is %', al.reference_no, lower(al.state) USING ERRCODE = '23514'; END IF;
    IF s.rules IS NOT NULL AND coalesce(p_rules_version, 0) <> s.rules_version THEN RAISE EXCEPTION 'the hostel rules (version %) are acknowledged before the allocation is accepted', s.rules_version USING ERRCODE = '23514'; END IF;
    UPDATE hostel.allocation SET state = 'ACCEPTED', accepted_at = now(), rules_version = CASE WHEN s.rules IS NULL THEN NULL ELSE s.rules_version END WHERE id = al.id;
    PERFORM hostel.log(al.application_id, al.id, al.student_id, NULL, al.room_id, al.bed_id, 'ACCEPTED', 'CONFIRMED', 'ACCEPTED', CASE WHEN s.rules IS NULL THEN NULL ELSE 'Rules version ' || s.rules_version || ' acknowledged' END);
    PERFORM hostel.tell_student(al.student_id, 'Your hostel allocation is accepted', 'Allocation ' || al.reference_no || ' is accepted. Check in at the porter''s lodge with your identity card and the allocation letter.', 'MOAUM: allocation ' || al.reference_no || ' accepted. Check in at the lodge.');
END $$;

CREATE OR REPLACE FUNCTION hostel.decline(p_allocation uuid, p_student uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE al hostel.allocation;
BEGIN
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'a declined allocation carries its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO al FROM hostel.allocation WHERE id = p_allocation FOR UPDATE;
    IF al.id IS NULL OR al.student_id <> p_student THEN RAISE EXCEPTION 'no such allocation' USING ERRCODE = '23503'; END IF;
    IF al.state NOT IN ('HELD','CONFIRMED','ACCEPTED') THEN RAISE EXCEPTION 'allocation % is %; it cannot be declined now', al.reference_no, lower(al.state) USING ERRCODE = '23514'; END IF;
    UPDATE hostel.allocation SET state = 'DECLINED', declined_at = now(), decline_reason = btrim(p_reason), ended_at = now(), ended_reason = 'DECLINED: ' || btrim(p_reason) WHERE id = al.id;
    UPDATE hostel.application SET state = 'WITHDRAWN', withdrawn_at = now(), withdrawn_reason = 'Allocation declined: ' || btrim(p_reason) WHERE id = al.application_id;
    PERFORM hostel.log(al.application_id, al.id, al.student_id, NULL, al.room_id, al.bed_id, 'DECLINED', al.state, 'DECLINED', btrim(p_reason));
    PERFORM hostel.tell_desk('A hostel allocation was declined', 'Allocation ' || al.reference_no || ' was declined by the student: ' || btrim(p_reason) || '. The bed is free again.');
    PERFORM hostel.tell_student(al.student_id, 'Your hostel allocation is declined', 'Allocation ' || al.reference_no || ' has been declined at your request and the bed released. ' || CASE WHEN al.confirmed_at IS NOT NULL THEN 'Any refund of the fee is a Bursary decision.' ELSE '' END, 'MOAUM: allocation ' || al.reference_no || ' declined; bed released.');
END $$;

CREATE OR REPLACE FUNCTION hostel.checkin(p_allocation uuid, p_note text, p_condition text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE al hostel.allocation; s hostel.session_setting; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO al FROM hostel.allocation WHERE id = p_allocation FOR UPDATE;
    IF al.id IS NULL THEN RAISE EXCEPTION 'no such allocation' USING ERRCODE = '23503'; END IF;
    SELECT * INTO s FROM hostel.session_setting WHERE session = al.session;
    IF al.state = 'HELD' THEN RAISE EXCEPTION 'the accommodation fee is not confirmed; nobody checks in on a hold' USING ERRCODE = '23514'; END IF;
    IF al.state = 'CONFIRMED' AND s.rules IS NOT NULL THEN RAISE EXCEPTION 'the student accepts the allocation under the hostel rules before checking in' USING ERRCODE = '23514'; END IF;
    IF al.state NOT IN ('CONFIRMED','ACCEPTED') THEN RAISE EXCEPTION 'allocation % is %', al.reference_no, lower(al.state) USING ERRCODE = '23514'; END IF;
    UPDATE hostel.allocation SET state = 'CHECKED_IN', checked_in_at = now(), checked_in_by = v_actor, checkin_note = p_note, accepted_at = coalesce(accepted_at, now()) WHERE id = al.id;
    INSERT INTO hostel.inspection (allocation_id, kind, inspected_by, condition, remarks) VALUES (al.id, 'CHECKIN', v_actor, coalesce(p_condition, 'GOOD'), p_note);
    PERFORM hostel.log(al.application_id, al.id, al.student_id, NULL, al.room_id, al.bed_id, 'CHECKED_IN', al.state, 'CHECKED_IN', p_note);
    PERFORM hostel.tell_student(al.student_id, 'You are checked in', 'Your check-in under allocation ' || al.reference_no || ' is recorded. The room and its assets were noted as ' || lower(coalesce(p_condition, 'good')) || ' at check-in; report any fault from the portal.', 'MOAUM: hostel check-in recorded, ' || al.reference_no || '.');
END $$;

-- ── 13 · a transfer: the old stay closed, the new one opened, the history kept ──

CREATE OR REPLACE FUNCTION hostel.transfer(p_allocation uuid, p_bed uuid, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE al hostel.allocation; b hostel.bed; r hostel.room; h hostel.hall; st people.student; v uuid; v_state text;
BEGIN
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'a transfer carries its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO al FROM hostel.allocation WHERE id = p_allocation FOR UPDATE;
    IF al.id IS NULL THEN RAISE EXCEPTION 'no such allocation' USING ERRCODE = '23503'; END IF;
    IF al.state NOT IN ('CONFIRMED','ACCEPTED','CHECKED_IN','HELD') THEN RAISE EXCEPTION 'allocation % is %; there is nothing to transfer', al.reference_no, lower(al.state) USING ERRCODE = '23514'; END IF;
    SELECT * INTO b FROM hostel.bed WHERE id = p_bed FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such bed' USING ERRCODE = '23503'; END IF;
    IF b.id = al.bed_id THEN RAISE EXCEPTION 'that is the bed the student already holds' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM hostel.room WHERE id = b.room_id; SELECT * INTO h FROM hostel.hall WHERE code = r.hall_code; SELECT * INTO st FROM people.student WHERE id = al.student_id;
    IF b.state <> 'AVAILABLE' THEN RAISE EXCEPTION 'bed % of room % is %', b.label, r.room_no, lower(replace(b.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
    IF r.state <> 'AVAILABLE' THEN RAISE EXCEPTION 'room % is %', r.room_no, lower(r.state) USING ERRCODE = '23514'; END IF;
    IF h.state <> 'ACTIVE' OR h.ended_on IS NOT NULL THEN RAISE EXCEPTION 'hall % is closed', h.name USING ERRCODE = '23514'; END IF;
    IF coalesce(r.sex, h.sex) IS NOT NULL AND st.sex IS NOT NULL AND coalesce(r.sex, h.sex) <> st.sex THEN RAISE EXCEPTION 'hall % is not for this student', h.name USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM hostel.allocation a WHERE a.room_id = r.id AND a.bed = b.number AND a.session = al.session AND a.lapsed_at IS NULL AND a.ended_at IS NULL) THEN
        RAISE EXCEPTION 'bed % of room % is already taken', b.label, r.room_no USING ERRCODE = '23514';
    END IF;
    -- the old stay closes first, so one bed a session holds
    UPDATE hostel.allocation SET state = 'TRANSFERRED', ended_at = now(), ended_reason = 'TRANSFERRED: ' || btrim(p_reason), checked_out_at = CASE WHEN state = 'CHECKED_IN' THEN now() END WHERE id = al.id;
    v_state := CASE WHEN al.state = 'HELD' THEN 'HELD' WHEN al.state = 'CHECKED_IN' THEN 'CHECKED_IN' ELSE al.state END;
    INSERT INTO hostel.allocation (application_id, session, room_id, bed, bed_id, student_id, basis, draw_position, held_until, reference, confirmed_at, state,
                                   start_on, end_on, accepted_at, rules_version, checked_in_at, checked_in_by, moved_from)
    VALUES (al.application_id, al.session, r.id, b.number, b.id, al.student_id, al.basis, al.draw_position, al.held_until, al.reference, al.confirmed_at, v_state,
            coalesce(al.start_on, current_date), al.end_on, al.accepted_at, al.rules_version, CASE WHEN v_state = 'CHECKED_IN' THEN now() END,
            CASE WHEN v_state = 'CHECKED_IN' THEN nullif(current_setting('moaum.actor_id', true), '')::uuid END, al.id)
    RETURNING id INTO v;
    PERFORM hostel.log(al.application_id, al.id, al.student_id, h.code, al.room_id, al.bed_id, 'TRANSFERRED_OUT', al.state, 'TRANSFERRED', btrim(p_reason));
    PERFORM hostel.log(al.application_id, v, al.student_id, h.code, r.id, b.id, 'TRANSFERRED_IN', NULL, h.name || ' · ' || r.block || '-' || r.room_no || ' · ' || b.label, btrim(p_reason));
    PERFORM hostel.tell_student(al.student_id, 'Your hostel room has changed',
        'You have been moved to ' || h.name || ', Block ' || r.block || ', Room ' || r.room_no || ', ' || b.label || ' (' || btrim(p_reason) || '). The new allocation reference is ' || (SELECT reference_no FROM hostel.allocation WHERE id = v) || '; the earlier stay is kept on your record.',
        'MOAUM: hostel room changed to ' || h.name || ' ' || r.block || '-' || r.room_no || ' ' || b.label || '.');
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION hostel.request_transfer(p_student uuid, p_session text, p_hall text, p_type text, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE al hostel.allocation; v uuid;
BEGIN
    SELECT * INTO al FROM hostel.allocation WHERE student_id = p_student AND session = p_session AND lapsed_at IS NULL AND ended_at IS NULL;
    IF al.id IS NULL THEN RAISE EXCEPTION 'no allocation stands for %', p_session USING ERRCODE = '23514'; END IF;
    IF al.state NOT IN ('CONFIRMED','ACCEPTED','CHECKED_IN') THEN RAISE EXCEPTION 'a transfer is asked for from a confirmed room' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM hostel.transfer_request WHERE allocation_id = al.id AND state IN ('SUBMITTED','UNDER_REVIEW')) THEN RAISE EXCEPTION 'a transfer request is already waiting' USING ERRCODE = '23505'; END IF;
    INSERT INTO hostel.transfer_request (allocation_id, student_id, requested_hall, requested_type, reason) VALUES (al.id, p_student, p_hall, p_type, btrim(p_reason)) RETURNING id INTO v;
    PERFORM hostel.log(al.application_id, al.id, p_student, NULL, al.room_id, al.bed_id, 'TRANSFER_REQUESTED', NULL, coalesce(p_hall, 'any hall'), btrim(p_reason));
    PERFORM hostel.tell_desk('A room transfer is requested', 'The student under allocation ' || al.reference_no || ' asks to move' || coalesce(' to ' || p_hall, '') || ': ' || btrim(p_reason));
    PERFORM hostel.tell_student(p_student, 'Your transfer request is in', 'Your request to change room is with the housing desk. Your current allocation stands until a decision is made.', 'MOAUM: hostel transfer request received.');
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION hostel.decide_transfer(p_request uuid, p_decision text, p_bed uuid, p_note text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE t hostel.transfer_request; v uuid; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO t FROM hostel.transfer_request WHERE id = p_request FOR UPDATE;
    IF t.id IS NULL THEN RAISE EXCEPTION 'no such request' USING ERRCODE = '23503'; END IF;
    IF t.state NOT IN ('SUBMITTED','UNDER_REVIEW') THEN RAISE EXCEPTION 'the request is %', lower(t.state) USING ERRCODE = '23514'; END IF;
    IF p_decision = 'UNDER_REVIEW' THEN UPDATE hostel.transfer_request SET state = 'UNDER_REVIEW' WHERE id = t.id; RETURN NULL; END IF;
    IF p_decision = 'REJECTED' THEN
        IF nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN RAISE EXCEPTION 'say why the transfer is refused' USING ERRCODE = '23514'; END IF;
        UPDATE hostel.transfer_request SET state = 'REJECTED', decided_by = v_actor, decided_at = now(), decision_note = p_note WHERE id = t.id;
        PERFORM hostel.log(NULL, t.allocation_id, t.student_id, NULL, NULL, NULL, 'TRANSFER_REJECTED', NULL, NULL, p_note);
        PERFORM hostel.tell_student(t.student_id, 'Your transfer request was not approved', 'The housing desk did not approve your request to change room: ' || p_note, 'MOAUM: hostel transfer not approved.');
        RETURN NULL;
    END IF;
    IF p_decision <> 'APPROVED' THEN RAISE EXCEPTION 'a transfer request is approved, rejected or put under review' USING ERRCODE = '23514'; END IF;
    IF p_bed IS NULL THEN RAISE EXCEPTION 'name the bed the student moves to' USING ERRCODE = '23514'; END IF;
    v := hostel.transfer(t.allocation_id, p_bed, 'Transfer request approved' || coalesce(': ' || p_note, ''));
    UPDATE hostel.transfer_request SET state = 'COMPLETED', decided_by = v_actor, decided_at = now(), decision_note = p_note, new_allocation = v WHERE id = t.id;
    RETURN v;
END $$;

-- ── 14 · checkout: the request, the inspection, the charge, the clearance ─

CREATE OR REPLACE FUNCTION hostel.request_checkout(p_student uuid, p_session text, p_on date, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE al hostel.allocation;
BEGIN
    SELECT * INTO al FROM hostel.allocation WHERE student_id = p_student AND session = p_session AND lapsed_at IS NULL AND ended_at IS NULL FOR UPDATE;
    IF al.id IS NULL THEN RAISE EXCEPTION 'no allocation stands for %', p_session USING ERRCODE = '23514'; END IF;
    IF al.state <> 'CHECKED_IN' THEN RAISE EXCEPTION 'checkout follows check-in; the student is %', lower(al.state) USING ERRCODE = '23514'; END IF;
    UPDATE hostel.allocation SET checkout_requested_at = now(), checkout_on = coalesce(p_on, current_date), checkout_reason = p_reason WHERE id = al.id;
    PERFORM hostel.log(al.application_id, al.id, p_student, NULL, al.room_id, al.bed_id, 'CHECKOUT_REQUESTED', NULL, coalesce(p_on, current_date)::text, p_reason);
    PERFORM hostel.tell_desk('A checkout is requested', 'The student under allocation ' || al.reference_no || ' asks to check out on ' || coalesce(p_on, current_date)::text || coalesce(': ' || p_reason, '') || '. An inspection is due.');
    PERFORM hostel.tell_student(p_student, 'Your checkout request is in', 'The housing desk will inspect the room on or after ' || coalesce(p_on, current_date)::text || '; clearance follows the inspection.', 'MOAUM: hostel checkout requested for ' || coalesce(p_on, current_date)::text || '.');
    RETURN al.id;
END $$;

/* the clearance opened with every requirement pending; the ones the record already answers are answered */
CREATE OR REPLACE FUNCTION hostel.start_clearance(p_allocation uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE al hostel.allocation; v uuid; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_open int;
BEGIN
    SELECT * INTO al FROM hostel.allocation WHERE id = p_allocation;
    IF al.id IS NULL THEN RAISE EXCEPTION 'no such allocation' USING ERRCODE = '23503'; END IF;
    SELECT id INTO v FROM hostel.clearance WHERE allocation_id = al.id;
    IF v IS NOT NULL THEN RETURN v; END IF;
    INSERT INTO hostel.clearance (allocation_id, started_by) VALUES (al.id, v_actor) RETURNING id INTO v;
    INSERT INTO hostel.clearance_item (clearance_id, requirement) SELECT v, code FROM hostel.clearance_requirement WHERE active;
    UPDATE hostel.clearance_item SET state = CASE WHEN al.confirmed_at IS NOT NULL THEN 'CLEARED' ELSE 'NOT_CLEARED' END, decided_at = now(),
           remarks = CASE WHEN al.confirmed_at IS NOT NULL THEN 'Fee confirmed ' || al.confirmed_at::date ELSE 'The accommodation fee was not confirmed' END
     WHERE clearance_id = v AND requirement = 'FEES_SETTLED';
    UPDATE hostel.clearance_item SET state = 'NOT_APPLICABLE', decided_at = now(), remarks = 'No damage charge raised' WHERE clearance_id = v AND requirement = 'DAMAGE_CHARGES_SETTLED'
       AND NOT EXISTS (SELECT 1 FROM hostel.damage_charge c WHERE c.allocation_id = al.id);
    SELECT count(*) INTO v_open FROM hostel.maintenance_request m WHERE m.room_id = al.room_id AND m.raised_by = al.student_id AND m.state IN ('RAISED','ASSIGNED');
    UPDATE hostel.clearance_item SET state = CASE WHEN v_open = 0 THEN 'CLEARED' ELSE 'PENDING' END, decided_at = CASE WHEN v_open = 0 THEN now() END,
           remarks = CASE WHEN v_open = 0 THEN 'No open request by the student for the room' ELSE v_open || ' request(s) still open' END
     WHERE clearance_id = v AND requirement = 'NO_MAINTENANCE_ISSUE';
    PERFORM hostel.log(al.application_id, al.id, al.student_id, NULL, al.room_id, al.bed_id, 'CLEARANCE_STARTED', NULL, (SELECT reference FROM hostel.clearance WHERE id = v), NULL);
    PERFORM hostel.tell_student(al.student_id, 'Your hostel clearance has started', 'Clearance ' || (SELECT reference FROM hostel.clearance WHERE id = v) || ' for allocation ' || al.reference_no || ' is open. Each requirement is shown on the portal as the desk clears it.', 'MOAUM: hostel clearance started, ' || (SELECT reference FROM hostel.clearance WHERE id = v) || '.');
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION hostel.inspect(p_allocation uuid, p_condition text, p_cleanliness text, p_damages text, p_keys boolean, p_card boolean, p_remarks text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE al hostel.allocation; v uuid; c uuid; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO al FROM hostel.allocation WHERE id = p_allocation FOR UPDATE;
    IF al.id IS NULL THEN RAISE EXCEPTION 'no such allocation' USING ERRCODE = '23503'; END IF;
    IF al.state <> 'CHECKED_IN' THEN RAISE EXCEPTION 'a checkout inspection is of a student checked in; the student is %', lower(al.state) USING ERRCODE = '23514'; END IF;
    INSERT INTO hostel.inspection (allocation_id, kind, inspected_by, condition, cleanliness, damages, keys_returned, card_returned, remarks)
    VALUES (al.id, 'CHECKOUT', v_actor, p_condition, p_cleanliness, nullif(btrim(coalesce(p_damages, '')), ''), p_keys, p_card, p_remarks) RETURNING id INTO v;
    c := hostel.start_clearance(al.id);
    UPDATE hostel.clearance_item SET state = CASE WHEN p_keys THEN 'CLEARED' ELSE 'NOT_CLEARED' END, officer_id = v_actor, decided_at = now(), remarks = CASE WHEN p_keys THEN 'Returned at inspection' ELSE 'Not returned at inspection' END WHERE clearance_id = c AND requirement = 'KEY_RETURNED' AND p_keys IS NOT NULL;
    UPDATE hostel.clearance_item SET state = CASE WHEN p_card THEN 'CLEARED' ELSE 'NOT_CLEARED' END, officer_id = v_actor, decided_at = now(), remarks = CASE WHEN p_card THEN 'Returned at inspection' ELSE 'Not returned at inspection' END WHERE clearance_id = c AND requirement = 'ACCESS_CARD_RETURNED' AND p_card IS NOT NULL;
    UPDATE hostel.clearance_item SET state = CASE WHEN p_condition = 'DAMAGED' THEN 'NOT_CLEARED' ELSE 'CLEARED' END, officer_id = v_actor, decided_at = now(), remarks = 'Inspected: ' || lower(p_condition) || coalesce(', ' || lower(p_cleanliness), '') WHERE clearance_id = c AND requirement IN ('ROOM_RETURNED','BED_RETURNED','ASSETS_RETURNED');
    UPDATE hostel.clearance_item SET state = CASE WHEN p_condition = 'DAMAGED' THEN 'NOT_CLEARED' ELSE 'CLEARED' END, officer_id = v_actor, decided_at = now(), remarks = coalesce(nullif(btrim(coalesce(p_damages, '')), ''), 'No damage found') WHERE clearance_id = c AND requirement = 'NO_DAMAGE';
    PERFORM hostel.log(al.application_id, al.id, al.student_id, NULL, al.room_id, al.bed_id, 'INSPECTED', NULL, p_condition, coalesce(p_damages, p_remarks));
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION hostel.charge(p_allocation uuid, p_asset uuid, p_description text, p_repair numeric, p_replacement numeric, p_charge numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE al hostel.allocation; v uuid; v_ref text; c uuid; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF nullif(btrim(coalesce(p_description, '')), '') IS NULL THEN RAISE EXCEPTION 'say what was damaged' USING ERRCODE = '23514'; END IF;
    IF p_charge IS NULL OR p_charge < 0 THEN RAISE EXCEPTION 'a charge is an amount, zero or more' USING ERRCODE = '23514'; END IF;
    SELECT * INTO al FROM hostel.allocation WHERE id = p_allocation;
    IF al.id IS NULL THEN RAISE EXCEPTION 'no such allocation' USING ERRCODE = '23503'; END IF;
    INSERT INTO hostel.damage_charge (allocation_id, inspection_id, asset_id, description, repair_cost, replacement_cost, charge, raised_by)
    VALUES (al.id, (SELECT id FROM hostel.inspection WHERE allocation_id = al.id AND kind = 'CHECKOUT' ORDER BY inspected_at DESC LIMIT 1), p_asset, btrim(p_description), p_repair, p_replacement, p_charge, v_actor)
    RETURNING id INTO v;
    IF p_charge > 0 THEN
        v_ref := finance.new_purpose_reference(al.student_id, al.session, p_charge, 'Hostel accommodation damage ' || al.reference_no || ' ' || v::text);
        UPDATE hostel.damage_charge SET reference = v_ref WHERE id = v;
    ELSE
        UPDATE hostel.damage_charge SET settled_at = now() WHERE id = v;
    END IF;
    IF p_asset IS NOT NULL THEN UPDATE hostel.asset SET condition = 'DAMAGED' WHERE id = p_asset AND condition IN ('NEW','GOOD','FAIR'); END IF;
    c := hostel.start_clearance(al.id);
    UPDATE hostel.clearance_item SET state = CASE WHEN p_charge > 0 THEN 'NOT_CLEARED' ELSE 'CLEARED' END, officer_id = v_actor, decided_at = now(), remarks = btrim(p_description) || ' · NGN ' || p_charge::text WHERE clearance_id = c AND requirement = 'DAMAGE_CHARGES_SETTLED';
    PERFORM hostel.log(al.application_id, al.id, al.student_id, NULL, al.room_id, al.bed_id, 'CHARGED', NULL, p_charge::text, btrim(p_description));
    IF p_charge > 0 THEN
        PERFORM hostel.tell_student(al.student_id, 'A hostel damage charge stands against you',
            'A charge of NGN ' || p_charge::text || ' for ' || btrim(p_description) || ' has been raised under allocation ' || al.reference_no || ', payment reference ' || v_ref || '. Hostel clearance completes when it is settled or waived.',
            'MOAUM: hostel damage charge NGN ' || p_charge::text || ', reference ' || v_ref || '.');
    END IF;
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION hostel.waive_charge(p_charge uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE c hostel.damage_charge; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; cl uuid;
BEGIN
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'a waiver carries its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO c FROM hostel.damage_charge WHERE id = p_charge FOR UPDATE;
    IF c.id IS NULL THEN RAISE EXCEPTION 'no such charge' USING ERRCODE = '23503'; END IF;
    IF c.settled_at IS NOT NULL THEN RAISE EXCEPTION 'the charge is already settled' USING ERRCODE = '23514'; END IF;
    UPDATE hostel.damage_charge SET waived_at = now(), waived_by = v_actor, waived_reason = btrim(p_reason) WHERE id = c.id;
    SELECT id INTO cl FROM hostel.clearance WHERE allocation_id = c.allocation_id;
    UPDATE hostel.clearance_item SET state = 'WAIVED', officer_id = v_actor, decided_at = now(), remarks = 'Waived: ' || btrim(p_reason) WHERE clearance_id = cl AND requirement = 'DAMAGE_CHARGES_SETTLED'
       AND NOT EXISTS (SELECT 1 FROM hostel.damage_charge x WHERE x.allocation_id = c.allocation_id AND x.id <> c.id AND x.settled_at IS NULL AND x.waived_at IS NULL);
    PERFORM hostel.log(NULL, c.allocation_id, (SELECT student_id FROM hostel.allocation WHERE id = c.allocation_id), NULL, NULL, NULL, 'CHARGE_WAIVED', c.charge::text, '0', btrim(p_reason));
END $$;

CREATE OR REPLACE FUNCTION hostel.decide_item(p_item uuid, p_state text, p_remarks text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE i hostel.clearance_item; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF p_state NOT IN ('PENDING','CLEARED','NOT_CLEARED','WAIVED','NOT_APPLICABLE') THEN RAISE EXCEPTION 'not a clearance state' USING ERRCODE = '23514'; END IF;
    IF p_state IN ('NOT_CLEARED','WAIVED') AND nullif(btrim(coalesce(p_remarks, '')), '') IS NULL THEN RAISE EXCEPTION 'say why' USING ERRCODE = '23514'; END IF;
    SELECT * INTO i FROM hostel.clearance_item WHERE id = p_item FOR UPDATE;
    IF i.id IS NULL THEN RAISE EXCEPTION 'no such item' USING ERRCODE = '23503'; END IF;
    IF EXISTS (SELECT 1 FROM hostel.clearance WHERE id = i.clearance_id AND state = 'CLEARED') THEN RAISE EXCEPTION 'the clearance is complete' USING ERRCODE = '23514'; END IF;
    UPDATE hostel.clearance_item SET state = p_state, officer_id = v_actor, decided_at = now(), remarks = p_remarks WHERE id = i.id;
    PERFORM hostel.log(NULL, (SELECT allocation_id FROM hostel.clearance WHERE id = i.clearance_id), NULL, NULL, NULL, NULL, 'CLEARANCE_ITEM', i.state, p_state, i.requirement || coalesce(': ' || p_remarks, ''));
END $$;

/* every requirement answered: the stay ends, the bed is free, the graduation clearance unit is signed */
CREATE OR REPLACE FUNCTION hostel.complete_clearance(p_clearance uuid, p_note text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE cl hostel.clearance; al hostel.allocation; v_pending int; v_not int; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_state text;
BEGIN
    SELECT * INTO cl FROM hostel.clearance WHERE id = p_clearance FOR UPDATE;
    IF cl.id IS NULL THEN RAISE EXCEPTION 'no such clearance' USING ERRCODE = '23503'; END IF;
    IF cl.state = 'CLEARED' THEN RETURN 'CLEARED'; END IF;
    SELECT * INTO al FROM hostel.allocation WHERE id = cl.allocation_id FOR UPDATE;
    SELECT count(*) FILTER (WHERE state = 'PENDING'), count(*) FILTER (WHERE state = 'NOT_CLEARED') INTO v_pending, v_not FROM hostel.clearance_item WHERE clearance_id = cl.id;
    IF v_pending > 0 THEN RAISE EXCEPTION '% requirement(s) still pending', v_pending USING ERRCODE = '23514', HINT = 'Clear, waive or mark each requirement not applicable first.'; END IF;
    v_state := CASE WHEN v_not > 0 THEN 'NOT_CLEARED' ELSE 'CLEARED' END;
    UPDATE hostel.clearance SET state = v_state, completed_at = now(), completed_by = v_actor, note = p_note WHERE id = cl.id;
    IF v_state = 'CLEARED' THEN
        UPDATE hostel.allocation SET state = 'CHECKED_OUT', checked_out_at = now(), checked_out_by = v_actor, ended_at = now(), ended_reason = 'CHECKED_OUT: clearance ' || cl.reference WHERE id = al.id AND ended_at IS NULL;
        INSERT INTO clearance.item (id, student_id, purpose, unit, state, officer_id, decided_at, note)
        SELECT gen_random_uuid(), al.student_id, 'CONVOCATION', 'HOSTEL', 'CLEARED', v_actor, now(), 'Hostel clearance ' || cl.reference || ' · allocation ' || al.reference_no
         WHERE v_actor IS NOT NULL AND EXISTS (SELECT 1 FROM iam.person WHERE id = v_actor);
        PERFORM hostel.log(al.application_id, al.id, al.student_id, NULL, al.room_id, al.bed_id, 'CLEARED', 'CHECKED_IN', 'CHECKED_OUT', 'Clearance ' || cl.reference || coalesce(': ' || p_note, ''));
        PERFORM hostel.tell_student(al.student_id, 'Your hostel clearance is complete', 'Clearance ' || cl.reference || ' is complete and your stay under allocation ' || al.reference_no || ' is closed. The clearance certificate is on the portal.', 'MOAUM: hostel clearance ' || cl.reference || ' complete.');
    ELSE
        INSERT INTO clearance.item (id, student_id, purpose, unit, state, item, officer_id, decided_at, note)
        SELECT gen_random_uuid(), al.student_id, 'CONVOCATION', 'HOSTEL', 'HELD', (SELECT string_agg(r.label, '; ') FROM hostel.clearance_item i JOIN hostel.clearance_requirement r ON r.code = i.requirement WHERE i.clearance_id = cl.id AND i.state = 'NOT_CLEARED'),
               v_actor, now(), 'Hostel clearance ' || cl.reference || ' not cleared'
         WHERE v_actor IS NOT NULL AND EXISTS (SELECT 1 FROM iam.person WHERE id = v_actor);
        PERFORM hostel.log(al.application_id, al.id, al.student_id, NULL, al.room_id, al.bed_id, 'NOT_CLEARED', NULL, 'NOT_CLEARED', 'Clearance ' || cl.reference || coalesce(': ' || p_note, ''));
        PERFORM hostel.tell_student(al.student_id, 'Your hostel clearance has outstanding items', 'Clearance ' || cl.reference || ' could not be completed: ' || (SELECT string_agg(r.label, '; ') FROM hostel.clearance_item i JOIN hostel.clearance_requirement r ON r.code = i.requirement WHERE i.clearance_id = cl.id AND i.state = 'NOT_CLEARED') || '. Settle them at the housing desk.', 'MOAUM: hostel clearance ' || cl.reference || ' has outstanding items.');
    END IF;
    RETURN v_state;
END $$;

/* a clearance found wanting is reopened once the student has settled what was owed */
CREATE OR REPLACE FUNCTION hostel.reopen_clearance(p_clearance uuid, p_note text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE cl hostel.clearance;
BEGIN
    SELECT * INTO cl FROM hostel.clearance WHERE id = p_clearance FOR UPDATE;
    IF cl.id IS NULL THEN RAISE EXCEPTION 'no such clearance' USING ERRCODE = '23503'; END IF;
    IF cl.state <> 'NOT_CLEARED' THEN RAISE EXCEPTION 'only a clearance found wanting is reopened' USING ERRCODE = '23514'; END IF;
    UPDATE hostel.clearance SET state = 'PENDING', completed_at = NULL, completed_by = NULL, note = p_note WHERE id = cl.id;
    UPDATE hostel.clearance_item SET state = 'PENDING' WHERE clearance_id = cl.id AND state = 'NOT_CLEARED';
    PERFORM hostel.log(NULL, cl.allocation_id, NULL, NULL, NULL, NULL, 'CLEARANCE_REOPENED', 'NOT_CLEARED', 'PENDING', p_note);
END $$;

/* the desk cancels a stay that never began, or ends one by administrative decision */
CREATE OR REPLACE FUNCTION hostel.cancel(p_allocation uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE al hostel.allocation;
BEGIN
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'a cancellation carries its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO al FROM hostel.allocation WHERE id = p_allocation FOR UPDATE;
    IF al.id IS NULL THEN RAISE EXCEPTION 'no such allocation' USING ERRCODE = '23503'; END IF;
    IF al.ended_at IS NOT NULL OR al.lapsed_at IS NOT NULL THEN RAISE EXCEPTION 'allocation % is already %', al.reference_no, lower(al.state) USING ERRCODE = '23514'; END IF;
    IF al.state = 'CHECKED_IN' THEN RAISE EXCEPTION 'a student checked in leaves through inspection and clearance' USING ERRCODE = '23514'; END IF;
    UPDATE hostel.allocation SET state = 'CANCELLED', ended_at = now(), ended_reason = 'CANCELLED: ' || btrim(p_reason) WHERE id = al.id;
    UPDATE hostel.application SET state = 'WITHDRAWN', withdrawn_at = now(), withdrawn_reason = 'Allocation cancelled: ' || btrim(p_reason) WHERE id = al.application_id;
    PERFORM hostel.log(al.application_id, al.id, al.student_id, NULL, al.room_id, al.bed_id, 'CANCELLED', al.state, 'CANCELLED', btrim(p_reason));
    PERFORM hostel.tell_student(al.student_id, 'Your hostel allocation is cancelled', 'Allocation ' || al.reference_no || ' has been cancelled by the housing desk: ' || btrim(p_reason) || '.', 'MOAUM: hostel allocation ' || al.reference_no || ' cancelled.');
END $$;

-- ── 15 · closing a hall, a block, a room or a bed, and who it affects ────

CREATE OR REPLACE FUNCTION hostel.close(p_kind text, p_id text, p_state text, p_reason text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int := 0;
BEGIN
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL AND p_state NOT IN ('ACTIVE','AVAILABLE') THEN RAISE EXCEPTION 'say why it is closed' USING ERRCODE = '23514'; END IF;
    IF p_kind = 'HALL' THEN
        UPDATE hostel.hall SET state = p_state, state_reason = CASE WHEN p_state = 'ACTIVE' THEN NULL ELSE p_reason END WHERE code = p_id;
        SELECT count(*) INTO n FROM hostel.allocation al JOIN hostel.room r ON r.id = al.room_id WHERE r.hall_code = p_id AND al.lapsed_at IS NULL AND al.ended_at IS NULL;
    ELSIF p_kind = 'BLOCK' THEN
        UPDATE hostel.block SET state = p_state, state_reason = CASE WHEN p_state = 'ACTIVE' THEN NULL ELSE p_reason END WHERE id = p_id::uuid;
        SELECT count(*) INTO n FROM hostel.allocation al JOIN hostel.room r ON r.id = al.room_id WHERE r.block_id = p_id::uuid AND al.lapsed_at IS NULL AND al.ended_at IS NULL;
    ELSIF p_kind = 'ROOM' THEN
        UPDATE hostel.room SET state = p_state, state_reason = CASE WHEN p_state = 'AVAILABLE' THEN NULL ELSE p_reason END WHERE id = p_id::uuid;
        SELECT count(*) INTO n FROM hostel.allocation al WHERE al.room_id = p_id::uuid AND al.lapsed_at IS NULL AND al.ended_at IS NULL;
    ELSIF p_kind = 'BED' THEN
        UPDATE hostel.bed SET state = p_state, state_reason = CASE WHEN p_state = 'AVAILABLE' THEN NULL ELSE p_reason END WHERE id = p_id::uuid;
        SELECT count(*) INTO n FROM hostel.allocation al WHERE al.bed_id = p_id::uuid AND al.lapsed_at IS NULL AND al.ended_at IS NULL;
    ELSE
        RAISE EXCEPTION 'a hall, a block, a room or a bed is closed' USING ERRCODE = '23514';
    END IF;
    PERFORM hostel.log(NULL, NULL, NULL, CASE WHEN p_kind = 'HALL' THEN p_id END, CASE WHEN p_kind = 'ROOM' THEN p_id::uuid END, CASE WHEN p_kind = 'BED' THEN p_id::uuid END,
                       p_kind || '_' || p_state, NULL, p_state, coalesce(p_reason, '') || CASE WHEN n > 0 THEN ' · ' || n || ' occupant(s) affected' ELSE '' END);
    RETURN n;
END $$;

-- ── 16 · what the student sees; the roommates; the history ──────────────

DROP FUNCTION IF EXISTS hostel.student_view(uuid, text);
CREATE OR REPLACE FUNCTION hostel.student_view(p_student uuid, p_session text)
RETURNS TABLE (application_id uuid, state text, hall_code text, hall_name text, category text, applied_at timestamptz,
               allocation_id uuid, room_id uuid, block text, room_no text, bed int, beds int, basis text, draw_position int,
               held_until timestamptz, confirmed_at timestamptz, lapsed_at timestamptz, reference text,
               fee numeric, hold_hours int, drawn_at timestamptz, seed text, applications_close date, open boolean,
               application_ref text, allocation_ref text, allocation_state text, floor int, room_type text, bed_label text, hall_location text, hall_campus text,
               accepted_at timestamptz, checked_in_at timestamptz, checkout_requested_at timestamptz, checkout_on date, checked_out_at timestamptz, start_on date, end_on date,
               review text, review_note text, room_type_pref text, block_pref text, special_need text, roommate_id uuid, roommate_note text,
               rules text, rules_version int, rules_accepted int, applications_open date, requires_review boolean, allocation_method text, window_state text,
               eligible boolean, eligibility_why text, clearance_id uuid, clearance_ref text, clearance_state text, transfer_state text,
               damage_due numeric, withdrawn_reason text)
LANGUAGE sql STABLE AS $$
    SELECT ap.id, ap.state, coalesce(r.hall_code, ap.hall_code), coalesce(hr.name, hp.name), ap.category, ap.applied_at,
           al.id, r.id, r.block, r.room_no, al.bed, r.beds, al.basis, coalesce(al.draw_position, ap.draw_position),
           al.held_until, al.confirmed_at, al.lapsed_at, al.reference,
           s.fee, s.hold_hours, s.drawn_at, s.seed, s.applications_close,
           s.session IS NOT NULL AND s.state = 'OPEN' AND s.drawn_at IS NULL AND (s.applications_close IS NULL OR s.applications_close >= current_date) AND (s.applications_open IS NULL OR s.applications_open <= current_date),
           ap.reference, al.reference_no, al.state, r.floor, rt.label, b.label, hr.location, hr.campus,
           al.accepted_at, al.checked_in_at, al.checkout_requested_at, al.checkout_on, al.checked_out_at, al.start_on, al.end_on,
           ap.review, ap.review_note, ap.room_type_pref, ap.block_pref, ap.special_need, ap.roommate_id, ap.roommate_note,
           s.rules, s.rules_version, al.rules_version, s.applications_open, s.requires_review, s.allocation_method, s.state,
           e.ok, e.why, cl.id, cl.reference, cl.state,
           (SELECT t.state FROM hostel.transfer_request t WHERE t.allocation_id = al.id ORDER BY t.submitted_at DESC LIMIT 1),
           (SELECT coalesce(sum(c.charge), 0) FROM hostel.damage_charge c WHERE c.allocation_id = al.id AND c.settled_at IS NULL AND c.waived_at IS NULL),
           ap.withdrawn_reason
      FROM (SELECT p_session AS session) q
      LEFT JOIN hostel.session_setting s ON s.session = q.session
      LEFT JOIN hostel.application ap ON ap.student_id = p_student AND ap.session = q.session AND ap.state <> 'WITHDRAWN'
      -- the live allocation first; failing one, the latest stay that ended, so a checked-out student still sees the clearance
      LEFT JOIN LATERAL (SELECT * FROM hostel.allocation x WHERE x.application_id = ap.id
                          ORDER BY (x.lapsed_at IS NULL AND x.ended_at IS NULL) DESC, (x.state = 'CHECKED_OUT') DESC, x.allocated_at DESC LIMIT 1) al ON true
      LEFT JOIN hostel.room r ON r.id = al.room_id
      LEFT JOIN hostel.room_type rt ON rt.code = r.room_type
      LEFT JOIN hostel.bed b ON b.id = al.bed_id
      LEFT JOIN hostel.hall hr ON hr.code = r.hall_code
      LEFT JOIN hostel.hall hp ON hp.code = ap.hall_code
      LEFT JOIN hostel.clearance cl ON cl.allocation_id = al.id
      LEFT JOIN LATERAL hostel.eligibility(p_student, q.session) e ON true
$$;

CREATE OR REPLACE FUNCTION hostel.roommates(p_allocation uuid)
RETURNS TABLE (student_id uuid, name text, number text, programme text, bed text, state text)
LANGUAGE sql STABLE AS $$
    SELECT st.id, st.surname || ', ' || st.other_names, coalesce(st.matric_no, st.admission_no), p.name, b.label, o.state
      FROM hostel.allocation me JOIN hostel.allocation o ON o.room_id = me.room_id AND o.session = me.session AND o.id <> me.id AND o.lapsed_at IS NULL AND o.ended_at IS NULL
      JOIN people.student st ON st.id = o.student_id LEFT JOIN ref.programme p ON p.code = st.programme_code LEFT JOIN hostel.bed b ON b.id = o.bed_id
     WHERE me.id = p_allocation ORDER BY o.bed
$$;

CREATE OR REPLACE FUNCTION hostel.history(p_student uuid)
RETURNS TABLE (session text, application_ref text, application_state text, allocation_ref text, allocation_state text, hall_name text, block text, room_no text, bed int, bed_label text,
               basis text, allocated_at timestamptz, confirmed_at timestamptz, checked_in_at timestamptz, checked_out_at timestamptz, ended_at timestamptz, ended_reason text, clearance_state text, clearance_ref text)
LANGUAGE sql STABLE AS $$
    SELECT ap.session, ap.reference, ap.state, al.reference_no, al.state, h.name, r.block, r.room_no, al.bed, b.label,
           al.basis, al.allocated_at, al.confirmed_at, al.checked_in_at, al.checked_out_at, al.ended_at, al.ended_reason, cl.state, cl.reference
      FROM hostel.application ap
      LEFT JOIN hostel.allocation al ON al.application_id = ap.id
      LEFT JOIN hostel.room r ON r.id = al.room_id LEFT JOIN hostel.hall h ON h.code = r.hall_code LEFT JOIN hostel.bed b ON b.id = al.bed_id
      LEFT JOIN hostel.clearance cl ON cl.allocation_id = al.id
     WHERE ap.student_id = p_student ORDER BY ap.session DESC, al.allocated_at DESC NULLS LAST
$$;

-- ── 17 · what the desk reads: the inventory, the occupancy, the figures ──

/* every bed with its physical state and what sits on it this session */
CREATE OR REPLACE FUNCTION hostel.bed_board(p_session text)
RETURNS TABLE (hall_code text, hall_name text, hall_kind text, hall_sex text, hall_state text, campus text, block_id uuid, block text, block_state text, floor int,
               room_id uuid, room_no text, room_type text, room_state text, capacity int, bed_id uuid, bed_no int, bed_label text, bed_state text,
               occupancy text, allocation_id uuid, allocation_state text, student_id uuid, student_name text, student_number text, sex text, programme text, programme_code text,
               dept_code text, department text, faculty_code text, faculty text, level int, checked_in_at timestamptz, end_on date)
LANGUAGE sql STABLE AS $$
    SELECT h.code, h.name, h.kind, h.sex, h.state, h.campus, bl.id, r.block, coalesce(bl.state, 'ACTIVE'), r.floor,
           r.id, r.room_no, r.room_type, r.state, r.beds, b.id, b.number, b.label, b.state,
           CASE WHEN al.id IS NOT NULL AND al.state = 'CHECKED_IN' THEN 'OCCUPIED'
                WHEN al.id IS NOT NULL THEN 'RESERVED'
                WHEN b.state = 'MAINTENANCE' OR r.state IN ('MAINTENANCE','CLOSED') OR h.state = 'CLOSED' OR coalesce(bl.state, 'ACTIVE') = 'CLOSED' THEN 'MAINTENANCE'
                WHEN b.state = 'OUT_OF_SERVICE' THEN 'OUT_OF_SERVICE'
                WHEN r.state = 'RESERVED' THEN 'RESERVED'
                ELSE 'AVAILABLE' END,
           al.id, al.state, st.id, st.surname || ', ' || st.other_names, coalesce(st.matric_no, st.admission_no), st.sex, p.name, p.code, d.code, d.name, f.code, f.name, st.current_level,
           al.checked_in_at, al.end_on
      FROM hostel.hall h
      JOIN hostel.room r ON r.hall_code = h.code
      LEFT JOIN hostel.block bl ON bl.id = r.block_id
      JOIN hostel.bed b ON b.room_id = r.id
      LEFT JOIN hostel.allocation al ON al.bed_id = b.id AND al.session = p_session AND al.lapsed_at IS NULL AND al.ended_at IS NULL
      LEFT JOIN people.student st ON st.id = al.student_id
      LEFT JOIN ref.programme p ON p.code = st.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE h.ended_on IS NULL
     ORDER BY h.name, r.block, r.floor, r.room_no, b.number
$$;

/* every application of the session with the student, the standing and the seat */
CREATE OR REPLACE FUNCTION hostel.applications(p_session text)
RETURNS TABLE (application_id uuid, reference text, state text, review text, review_note text, category text, category_note text, applied_at timestamptz, draw_position int,
               student_id uuid, student_name text, student_number text, sex text, level int, programme text, programme_code text, dept_code text, department text, faculty_code text, faculty text,
               hall_pref text, hall_pref_name text, room_type_pref text, block_pref text, special_need text, roommate_name text,
               eligible boolean, eligibility_why text, allocation_id uuid, allocation_ref text, allocation_state text, hall_name text, block text, room_no text, bed_label text,
               fee_paid boolean, held_until timestamptz, reference_no text)
LANGUAGE sql STABLE AS $$
    SELECT ap.id, ap.reference, ap.state, ap.review, ap.review_note, ap.category, ap.category_note, ap.applied_at, ap.draw_position,
           st.id, st.surname || ', ' || st.other_names, coalesce(st.matric_no, st.admission_no), st.sex, st.current_level, p.name, p.code, d.code, d.name, f.code, f.name,
           ap.hall_code, hp.name, ap.room_type_pref, ap.block_pref, ap.special_need, rm.surname || ', ' || rm.other_names,
           e.ok, e.why, al.id, al.reference_no, al.state, h.name, r.block, r.room_no, b.label,
           al.confirmed_at IS NOT NULL, al.held_until, al.reference
      FROM hostel.application ap
      JOIN people.student st ON st.id = ap.student_id
      LEFT JOIN ref.programme p ON p.code = st.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN hostel.hall hp ON hp.code = ap.hall_code
      LEFT JOIN people.student rm ON rm.id = ap.roommate_id
      LEFT JOIN LATERAL (SELECT * FROM hostel.allocation x WHERE x.application_id = ap.id AND x.ended_at IS NULL ORDER BY (x.lapsed_at IS NULL) DESC, x.allocated_at DESC LIMIT 1) al ON true
      LEFT JOIN hostel.room r ON r.id = al.room_id LEFT JOIN hostel.hall h ON h.code = r.hall_code LEFT JOIN hostel.bed b ON b.id = al.bed_id
      CROSS JOIN LATERAL hostel.eligibility(st.id, ap.session) e
     WHERE ap.session = p_session
     ORDER BY st.surname, st.other_names
$$;

/* the figures of a session, and each breakdown the charts draw */
CREATE OR REPLACE FUNCTION hostel.dashboard(p_session text)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH bb AS (SELECT * FROM hostel.bed_board(p_session)),
    ap AS (SELECT * FROM hostel.applications(p_session))
    SELECT jsonb_build_object(
        'session', p_session,
        'setting', (SELECT to_jsonb(s) FROM hostel.session_setting s WHERE s.session = p_session),
        'totals', jsonb_build_object(
            'halls', (SELECT count(*) FROM hostel.hall WHERE ended_on IS NULL),
            'halls_active', (SELECT count(*) FROM hostel.hall WHERE ended_on IS NULL AND state = 'ACTIVE'),
            'blocks', (SELECT count(*) FROM hostel.block),
            'rooms', (SELECT count(DISTINCT room_id) FROM bb),
            'rooms_available', (SELECT count(DISTINCT room_id) FROM bb WHERE occupancy = 'AVAILABLE'),
            'beds', (SELECT count(*) FROM bb WHERE occupancy <> 'OUT_OF_SERVICE'),
            'occupied', (SELECT count(*) FROM bb WHERE occupancy = 'OCCUPIED'),
            'reserved', (SELECT count(*) FROM bb WHERE occupancy = 'RESERVED'),
            'available', (SELECT count(*) FROM bb WHERE occupancy = 'AVAILABLE'),
            'maintenance', (SELECT count(*) FROM bb WHERE occupancy = 'MAINTENANCE'),
            'out_of_service', (SELECT count(*) FROM bb WHERE occupancy = 'OUT_OF_SERVICE'),
            'students_accommodated', (SELECT count(*) FROM bb WHERE allocation_id IS NOT NULL),
            'applications', (SELECT count(*) FROM ap WHERE state <> 'WITHDRAWN'),
            'pending_review', (SELECT count(*) FROM ap WHERE state = 'APPLIED' AND review IS NULL),
            'approved', (SELECT count(*) FROM ap WHERE review = 'APPROVED' AND state = 'APPLIED'),
            'rejected', (SELECT count(*) FROM ap WHERE state = 'REJECTED'),
            'allocated', (SELECT count(*) FROM ap WHERE allocation_state IN ('HELD','CONFIRMED','ACCEPTED','CHECKED_IN')),
            'unallocated', (SELECT count(*) FROM ap WHERE state = 'APPLIED'),
            'waitlisted', (SELECT count(*) FROM ap WHERE state = 'UNSUCCESSFUL'),
            'lapsed', (SELECT count(*) FROM ap WHERE state = 'LAPSED'),
            'checked_in', (SELECT count(*) FROM bb WHERE allocation_state = 'CHECKED_IN'),
            'checked_out', (SELECT count(*) FROM hostel.allocation WHERE session = p_session AND state = 'CHECKED_OUT'),
            'pending_clearance', (SELECT count(*) FROM hostel.clearance c JOIN hostel.allocation a ON a.id = c.allocation_id WHERE a.session = p_session AND c.state <> 'CLEARED'),
            'cleared', (SELECT count(*) FROM hostel.clearance c JOIN hostel.allocation a ON a.id = c.allocation_id WHERE a.session = p_session AND c.state = 'CLEARED'),
            'transfers_pending', (SELECT count(*) FROM hostel.transfer_request t JOIN hostel.allocation a ON a.id = t.allocation_id WHERE a.session = p_session AND t.state IN ('SUBMITTED','UNDER_REVIEW')),
            'checkouts_pending', (SELECT count(*) FROM hostel.allocation WHERE session = p_session AND state = 'CHECKED_IN' AND checkout_requested_at IS NOT NULL),
            'maintenance_open', (SELECT count(*) FROM hostel.maintenance_request WHERE state IN ('RAISED','ASSIGNED'))),
        'bedStatus', (SELECT coalesce(jsonb_agg(jsonb_build_object('status', occupancy, 'n', n) ORDER BY occupancy), '[]') FROM (SELECT occupancy, count(*) AS n FROM bb GROUP BY occupancy) q),
        'byHall', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', hall_code, 'hall', hall_name, 'kind', hall_kind, 'sex', hall_sex, 'beds', beds, 'occupied', occupied, 'reserved', reserved, 'available', available, 'maintenance', maintenance) ORDER BY hall_name), '[]')
                    FROM (SELECT hall_code, hall_name, hall_kind, hall_sex, count(*) FILTER (WHERE occupancy <> 'OUT_OF_SERVICE') AS beds, count(*) FILTER (WHERE occupancy = 'OCCUPIED') AS occupied,
                                 count(*) FILTER (WHERE occupancy = 'RESERVED') AS reserved, count(*) FILTER (WHERE occupancy = 'AVAILABLE') AS available, count(*) FILTER (WHERE occupancy = 'MAINTENANCE') AS maintenance
                            FROM bb GROUP BY hall_code, hall_name, hall_kind, hall_sex) q),
        'byBlock', (SELECT coalesce(jsonb_agg(jsonb_build_object('hall', hall_name, 'block', block, 'block_id', block_id, 'beds', beds, 'occupied', occupied, 'reserved', reserved, 'available', available, 'maintenance', maintenance) ORDER BY hall_name, block), '[]')
                     FROM (SELECT hall_name, block, block_id, count(*) FILTER (WHERE occupancy <> 'OUT_OF_SERVICE') AS beds, count(*) FILTER (WHERE occupancy = 'OCCUPIED') AS occupied,
                                  count(*) FILTER (WHERE occupancy = 'RESERVED') AS reserved, count(*) FILTER (WHERE occupancy = 'AVAILABLE') AS available, count(*) FILTER (WHERE occupancy = 'MAINTENANCE') AS maintenance
                             FROM bb GROUP BY hall_name, block, block_id) q),
        'byRoomType', (SELECT coalesce(jsonb_agg(jsonb_build_object('room_type', room_type, 'label', label, 'beds', beds, 'occupied', occupied, 'available', available) ORDER BY label), '[]')
                        FROM (SELECT bb.room_type, coalesce(rt.label, bb.room_type) AS label, count(*) FILTER (WHERE occupancy <> 'OUT_OF_SERVICE') AS beds, count(*) FILTER (WHERE occupancy IN ('OCCUPIED','RESERVED')) AS occupied, count(*) FILTER (WHERE occupancy = 'AVAILABLE') AS available
                                FROM bb LEFT JOIN hostel.room_type rt ON rt.code = bb.room_type GROUP BY bb.room_type, rt.label) q),
        'byFaculty', (SELECT coalesce(jsonb_agg(jsonb_build_object('faculty', faculty, 'faculty_code', faculty_code, 'accommodated', n) ORDER BY faculty), '[]')
                       FROM (SELECT faculty, faculty_code, count(*) AS n FROM bb WHERE allocation_id IS NOT NULL GROUP BY faculty, faculty_code) q),
        'byDepartment', (SELECT coalesce(jsonb_agg(jsonb_build_object('department', department, 'dept_code', dept_code, 'faculty', faculty, 'accommodated', n) ORDER BY department), '[]')
                          FROM (SELECT department, dept_code, faculty, count(*) AS n FROM bb WHERE allocation_id IS NOT NULL GROUP BY department, dept_code, faculty) q),
        'bySex', (SELECT coalesce(jsonb_agg(jsonb_build_object('sex', sex, 'accommodated', n)), '[]') FROM (SELECT sex, count(*) AS n FROM bb WHERE allocation_id IS NOT NULL GROUP BY sex) q),
        'byLevel', (SELECT coalesce(jsonb_agg(jsonb_build_object('level', level, 'accommodated', n) ORDER BY level), '[]') FROM (SELECT level, count(*) AS n FROM bb WHERE allocation_id IS NOT NULL GROUP BY level) q),
        'applicationStatus', (SELECT coalesce(jsonb_agg(jsonb_build_object('status', st, 'n', n) ORDER BY st), '[]')
                               FROM (SELECT CASE WHEN state = 'APPLIED' AND review IS NULL THEN 'UNDER_REVIEW' WHEN state = 'APPLIED' AND review = 'CORRECTION' THEN 'CORRECTION' WHEN state = 'APPLIED' THEN 'APPROVED'
                                                 WHEN state = 'ALLOCATED' THEN 'ALLOCATED' WHEN state = 'CONFIRMED' THEN 'CONFIRMED' WHEN state = 'UNSUCCESSFUL' THEN 'WAITLISTED' ELSE state END AS st, count(*) AS n
                                       FROM ap WHERE state <> 'WITHDRAWN' GROUP BY 1) q),
        'applicationsByHall', (SELECT coalesce(jsonb_agg(jsonb_build_object('hall', coalesce(hall_pref_name, 'No preference'), 'n', n) ORDER BY n DESC), '[]') FROM (SELECT hall_pref_name, count(*) AS n FROM ap WHERE state <> 'WITHDRAWN' GROUP BY hall_pref_name) q),
        'applicationsByFaculty', (SELECT coalesce(jsonb_agg(jsonb_build_object('faculty', coalesce(faculty, 'No faculty'), 'faculty_code', faculty_code, 'n', n) ORDER BY faculty), '[]') FROM (SELECT faculty, faculty_code, count(*) AS n FROM ap WHERE state <> 'WITHDRAWN' GROUP BY faculty, faculty_code) q),
        'applicationsByLevel', (SELECT coalesce(jsonb_agg(jsonb_build_object('level', level, 'n', n) ORDER BY level), '[]') FROM (SELECT level, count(*) AS n FROM ap WHERE state <> 'WITHDRAWN' GROUP BY level) q)
    );
$$;

CREATE OR REPLACE FUNCTION hostel.preview(p_session text)
RETURNS TABLE (eligible_applicants int, approved int, pending_review int, free_beds int, halls int, rooms int, will_seat int, will_wait int)
LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT * FROM hostel.session_setting WHERE session = p_session),
    ap AS (SELECT * FROM hostel.applications(p_session) a WHERE a.state = 'APPLIED'),
    fb AS (SELECT * FROM hostel.free_beds(p_session))
    SELECT (SELECT count(*) FROM ap WHERE eligible)::int,
           (SELECT count(*) FROM ap WHERE eligible AND (review = 'APPROVED' OR NOT (SELECT requires_review FROM s)))::int,
           (SELECT count(*) FROM ap WHERE review IS NULL AND (SELECT requires_review FROM s))::int,
           (SELECT count(*) FROM fb)::int, (SELECT count(DISTINCT hall_code) FROM fb)::int, (SELECT count(DISTINCT room_id) FROM fb)::int,
           least((SELECT count(*) FROM ap WHERE eligible AND (review = 'APPROVED' OR NOT (SELECT requires_review FROM s))), (SELECT count(*) FROM fb))::int,
           greatest(0, (SELECT count(*) FROM ap WHERE eligible AND (review = 'APPROVED' OR NOT (SELECT requires_review FROM s))) - (SELECT count(*) FROM fb))::int;
$$;

-- ── 18 · who may read and write ──────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA hostel TO app_student, app_finance;
GRANT SELECT ON ALL TABLES IN SCHEMA hostel TO app_auditor;

COMMIT;
