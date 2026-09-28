-- ═══════════════════════════════════════════════════════════════════════════
-- V290 — the hostel upgrade on V030/V261: the Dean of Student Affairs, rooms
-- of a category and any capacity, the Bursar's fee rules, the student's own
-- reservation of a room held 48 hours, special and institutional allocations
-- that are never invisible, the import of the University's hostel workbook,
-- and the accountability and finance reports.
--
--   · a new office, the Dean of Student Affairs (dsa), runs the hostels beside
--     the housing desk; the Bursar states the fees and reads the money;
--   · a room has a category (GENERAL, SPECIAL, STUDENT_UNION, SECURITY, and any
--     the Dean adds): whether students may choose it and whether it is charged;
--     a room's category says what it is for, its state what condition it is in;
--   · a room takes 1 to 64 beds; the beds stay rows (V261);
--   · hostel.fee_rule: the Bursar's fee by session, hostel, room type, category
--     and level, the most specific rule winning, the session's fee the floor;
--     a category that is not chargeable is NO CHARGE, which is not "unpaid";
--   · the window requires school fees paid and course registration submitted
--     (both enforced in hostel.eligibility, so no API call gets past them);
--   · hostel.reserve_room: an eligible student reserves a bed in a general room
--     of a first-come session; the bed is locked, so the last bed goes to one of
--     two students, never both; the hold is 48 hours by default, the clock
--     lapses it and the bed is free again; reminders go at 24, 6 and 1 hours;
--   · hostel.allocate_special: the Dean allocates a special, Student Union or
--     Security room to a student, a member of staff or a named person, payable
--     or free by the category, recorded either way;
--   · hostel.import_rows: the workbook's rows previewed and committed without
--     duplicates; hostel.accountability: who occupies every room; and
--     hostel.finance_summary: charges, paid, outstanding and exempt.
--   Every V030/V261 name keeps its rule; the hold stays the one door.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'housing', true),
       set_config('moaum.reason', 'V290: hostel upgrade', true);

-- ── 1 · the Dean of Student Affairs ─────────────────────────────────────
INSERT INTO ref.office (code, label, scope_kind) VALUES ('dsa', 'Dean of Student Affairs', 'institution')
ON CONFLICT (code) DO NOTHING;

-- ── 2 · room categories: what a room is for ─────────────────────────────
CREATE TABLE hostel.room_category (
    code              text PRIMARY KEY,
    label             text NOT NULL,
    general_selection boolean NOT NULL DEFAULT false,
    chargeable        boolean NOT NULL DEFAULT true,
    active            boolean NOT NULL DEFAULT true,
    note              text NULL,
    CONSTRAINT ck_rc_code CHECK (code ~ '^[A-Z][A-Z0-9_]{1,30}$')
);
COMMENT ON TABLE hostel.room_category IS
  'What a room is for (V290): GENERAL rooms are chosen by eligible students; every other category is allocated by the Dean of Student Affairs; a category that is not chargeable is NO CHARGE, recorded all the same.';
SELECT audit.attach('hostel.room_category');
INSERT INTO hostel.room_category (code, label, general_selection, chargeable, note) VALUES
    ('GENERAL',       'General',               true,  true,  'Chosen by eligible students through the application window'),
    ('SPECIAL',       'Special / reserved',    false, true,  'Reserved for particular people; allocated by the Dean; the hostel fee is payable'),
    ('STUDENT_UNION', 'Student Union',         false, false, 'Allocated by the Dean to Student Union occupants; no hostel charge'),
    ('SECURITY',      'Security',              false, false, 'Allocated by the Dean to security personnel; no hostel charge');

ALTER TABLE hostel.room ADD COLUMN IF NOT EXISTS category text NOT NULL DEFAULT 'GENERAL';
ALTER TABLE hostel.room DROP CONSTRAINT IF EXISTS fk_room_category;
ALTER TABLE hostel.room ADD CONSTRAINT fk_room_category FOREIGN KEY (category) REFERENCES hostel.room_category(code);

-- any capacity from one to sixty-four beds; the room's state gains out of service and inactive
ALTER TABLE hostel.room DROP CONSTRAINT IF EXISTS ck_room_beds;
ALTER TABLE hostel.room ADD CONSTRAINT ck_room_beds CHECK (beds BETWEEN 1 AND 64);
ALTER TABLE hostel.room_type DROP CONSTRAINT IF EXISTS ck_rt_beds;
ALTER TABLE hostel.room_type ADD CONSTRAINT ck_rt_beds CHECK (beds BETWEEN 1 AND 64);
INSERT INTO hostel.room_type (code, label, beds) VALUES ('TEN_BED', 'Ten-bed', 10), ('TWELVE_BED', 'Twelve-bed', 12), ('SIXTEEN_BED', 'Sixteen-bed', 16)
ON CONFLICT (code) DO NOTHING;
ALTER TABLE hostel.room DROP CONSTRAINT IF EXISTS ck_room_state;
ALTER TABLE hostel.room ADD CONSTRAINT ck_room_state CHECK (state IN ('AVAILABLE', 'MAINTENANCE', 'OUT_OF_SERVICE', 'INACTIVE', 'CLOSED', 'RESERVED'));

-- ── 3 · the window: the semester, the two prerequisites, the 48-hour hold ──
ALTER TABLE hostel.session_setting
    ADD COLUMN IF NOT EXISTS semester            int NULL,
    ADD COLUMN IF NOT EXISTS require_school_fees boolean NOT NULL DEFAULT true;
ALTER TABLE hostel.session_setting DROP CONSTRAINT IF EXISTS ck_hs_semester;
ALTER TABLE hostel.session_setting ADD CONSTRAINT ck_hs_semester CHECK (semester IS NULL OR semester BETWEEN 1 AND 3);
ALTER TABLE hostel.session_setting ALTER COLUMN hold_hours SET DEFAULT 48;
ALTER TABLE hostel.session_setting ALTER COLUMN require_registration SET DEFAULT true;
COMMENT ON COLUMN hostel.session_setting.hold_hours IS 'How long a reserved bed is held for payment: 48 hours by the University''s rule (V290); the clock lapses it and the bed is free again.';

-- ── 4 · the allocation: the occupant, the category, the fee and its status ──
ALTER TABLE hostel.allocation
    ALTER COLUMN application_id DROP NOT NULL,
    ALTER COLUMN student_id DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS occupant_kind      text NOT NULL DEFAULT 'STUDENT',
    ADD COLUMN IF NOT EXISTS occupant_person_id uuid NULL REFERENCES iam.person(id),
    ADD COLUMN IF NOT EXISTS occupant_name      text NULL,
    ADD COLUMN IF NOT EXISTS category           text NULL REFERENCES hostel.room_category(code),
    ADD COLUMN IF NOT EXISTS fee_amount         numeric(12,2) NULL,
    ADD COLUMN IF NOT EXISTS fee_status         text NULL,
    ADD COLUMN IF NOT EXISTS allocated_by       uuid NULL,
    ADD COLUMN IF NOT EXISTS reason             text NULL,
    ADD COLUMN IF NOT EXISTS reminders          jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE hostel.allocation DROP CONSTRAINT IF EXISTS ck_hal_basis;
ALTER TABLE hostel.allocation ADD CONSTRAINT ck_hal_basis CHECK (basis IN ('PRIORITY', 'BALLOT', 'RESERVE', 'SELF', 'SPECIAL'));
ALTER TABLE hostel.allocation DROP CONSTRAINT IF EXISTS ck_hal_occupant;
ALTER TABLE hostel.allocation ADD CONSTRAINT ck_hal_occupant CHECK (
    occupant_kind IN ('STUDENT', 'STAFF', 'OTHER')
    AND (occupant_kind <> 'STUDENT' OR student_id IS NOT NULL)
    AND (student_id IS NOT NULL OR occupant_person_id IS NOT NULL OR (occupant_name IS NOT NULL AND btrim(occupant_name) <> '')));
ALTER TABLE hostel.allocation DROP CONSTRAINT IF EXISTS ck_hal_fee;
ALTER TABLE hostel.allocation ADD CONSTRAINT ck_hal_fee CHECK (fee_status IS NULL OR fee_status IN ('PAYABLE', 'PAID', 'NO_CHARGE'));
COMMENT ON COLUMN hostel.allocation.fee_status IS 'PAYABLE: a charge stands unpaid. PAID: settled through the Bursary. NO_CHARGE: an institutional allocation with no fee, which is not the same as unpaid (V290).';
-- the stays already on the record carry the session's fee and what became of it
UPDATE hostel.allocation al SET
    category   = coalesce(al.category, r.category),
    fee_amount = coalesce(al.fee_amount, s.fee, 0),
    fee_status = coalesce(al.fee_status, CASE WHEN coalesce(s.fee, 0) = 0 THEN 'NO_CHARGE' WHEN al.confirmed_at IS NOT NULL THEN 'PAID' ELSE 'PAYABLE' END)
  FROM hostel.room r LEFT JOIN hostel.session_setting s ON false
 WHERE r.id = al.room_id AND (al.category IS NULL OR al.fee_amount IS NULL OR al.fee_status IS NULL);
UPDATE hostel.allocation al SET fee_amount = s.fee, fee_status = CASE WHEN s.fee = 0 THEN 'NO_CHARGE' WHEN al.confirmed_at IS NOT NULL THEN 'PAID' ELSE 'PAYABLE' END
  FROM hostel.session_setting s WHERE s.session = al.session AND al.fee_amount = 0 AND s.fee > 0;

-- ── 5 · the Bursar's fee rules ──────────────────────────────────────────
CREATE TABLE hostel.fee_rule (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session    text NOT NULL REFERENCES policy.academic_session(name),
    hall_code  text NULL REFERENCES hostel.hall(code),
    room_type  text NULL REFERENCES hostel.room_type(code),
    category   text NULL REFERENCES hostel.room_category(code),
    level      int  NULL,
    amount     numeric(12,2) NOT NULL,
    note       text NULL,
    created_by uuid NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    ended_at   timestamptz NULL,
    ended_by   uuid NULL,
    CONSTRAINT ck_hfr_amount CHECK (amount >= 0),
    CONSTRAINT ck_hfr_level CHECK (level IS NULL OR level BETWEEN 100 AND 900)
);
COMMENT ON TABLE hostel.fee_rule IS 'The Bursar''s hostel fee by session, hostel, room type, category and level (V290): the most specific live rule wins; the session''s fee (hostel.session_setting.fee) is the floor. Ended, never deleted.';
CREATE UNIQUE INDEX uq_hostel_fee_rule_live ON hostel.fee_rule (session, coalesce(hall_code, ''), coalesce(room_type, ''), coalesce(category, ''), coalesce(level, 0)) WHERE ended_at IS NULL;
SELECT audit.attach('hostel.fee_rule');
GRANT SELECT, INSERT, UPDATE ON hostel.fee_rule TO app_student;
GRANT SELECT ON hostel.room_category TO app_student;

CREATE OR REPLACE FUNCTION hostel.fee_for(p_session text, p_hall text, p_room_type text, p_category text, p_level int)
RETURNS TABLE(amount numeric, status text, rule_id uuid)
LANGUAGE sql STABLE AS $fn$
    WITH cat AS (SELECT chargeable FROM hostel.room_category WHERE code = coalesce(p_category, 'GENERAL')),
         best AS (
            SELECT fr.id, fr.amount
              FROM hostel.fee_rule fr
             WHERE fr.session = p_session AND fr.ended_at IS NULL
               AND (fr.hall_code IS NULL OR fr.hall_code = p_hall)
               AND (fr.room_type IS NULL OR fr.room_type = p_room_type)
               AND (fr.category IS NULL OR fr.category = coalesce(p_category, 'GENERAL'))
               AND (fr.level IS NULL OR fr.level = p_level)
             ORDER BY (fr.hall_code IS NOT NULL)::int + (fr.room_type IS NOT NULL)::int + (fr.category IS NOT NULL)::int + (fr.level IS NOT NULL)::int DESC, fr.created_at DESC
             LIMIT 1),
         base AS (SELECT coalesce((SELECT b.amount FROM best b), (SELECT s.fee FROM hostel.session_setting s WHERE s.session = p_session), 0) AS amount)
    SELECT CASE WHEN NOT coalesce((SELECT chargeable FROM cat), true) THEN 0 ELSE base.amount END,
           CASE WHEN NOT coalesce((SELECT chargeable FROM cat), true) THEN 'NO_CHARGE' WHEN base.amount > 0 THEN 'PAYABLE' ELSE 'NO_CHARGE' END,
           CASE WHEN NOT coalesce((SELECT chargeable FROM cat), true) THEN NULL ELSE (SELECT b.id FROM best b) END
      FROM base
$fn$;
COMMENT ON FUNCTION hostel.fee_for(text, text, text, text, int) IS 'The hostel fee a bed carries (V290): nothing for a category that is not chargeable; else the most specific fee rule, else the session''s fee.';

-- ── 6 · the room board: every room with its capacity, occupancy and status ──
CREATE OR REPLACE FUNCTION hostel.room_board(p_session text)
RETURNS TABLE(room_id uuid, hall_code text, hall_name text, hall_sex text, hall_kind text, campus text, block text, floor int, room_no text, room_type text, room_type_label text,
              category text, category_label text, general_selection boolean, chargeable boolean, room_state text, state_reason text,
              capacity int, out_of_service int, occupied int, reserved int, available int, status text, fee numeric, fee_status text)
LANGUAGE sql STABLE AS $fn$
    WITH beds AS (
        SELECT b.room_id,
               count(*)::int AS capacity,
               count(*) FILTER (WHERE b.state <> 'AVAILABLE')::int AS oos,
               count(*) FILTER (WHERE b.state = 'AVAILABLE' AND EXISTS (SELECT 1 FROM hostel.allocation a WHERE a.bed_id = b.id AND a.session = p_session AND a.lapsed_at IS NULL AND a.ended_at IS NULL AND a.state = 'CHECKED_IN'))::int AS occupied,
               count(*) FILTER (WHERE b.state = 'AVAILABLE' AND EXISTS (SELECT 1 FROM hostel.allocation a WHERE a.bed_id = b.id AND a.session = p_session AND a.lapsed_at IS NULL AND a.ended_at IS NULL AND a.state <> 'CHECKED_IN'))::int AS reserved
          FROM hostel.bed b GROUP BY b.room_id)
    SELECT r.id, r.hall_code, h.name, coalesce(r.sex, h.sex), h.kind, h.campus, r.block, r.floor, r.room_no, r.room_type, rt.label,
           r.category, rc.label, rc.general_selection, rc.chargeable, r.state, r.state_reason,
           coalesce(bd.capacity, r.beds), coalesce(bd.oos, 0), coalesce(bd.occupied, 0), coalesce(bd.reserved, 0),
           greatest(coalesce(bd.capacity, r.beds) - coalesce(bd.oos, 0) - coalesce(bd.occupied, 0) - coalesce(bd.reserved, 0), 0),
           CASE WHEN h.state <> 'ACTIVE' OR h.ended_on IS NOT NULL THEN 'INACTIVE'
                WHEN r.state <> 'AVAILABLE' THEN r.state
                WHEN NOT rc.general_selection AND coalesce(bd.occupied, 0) + coalesce(bd.reserved, 0) = 0 THEN 'SPECIAL_RESERVED'
                WHEN coalesce(bd.capacity, r.beds) - coalesce(bd.oos, 0) - coalesce(bd.occupied, 0) - coalesce(bd.reserved, 0) <= 0 THEN 'FULL'
                WHEN coalesce(bd.occupied, 0) + coalesce(bd.reserved, 0) > 0 THEN 'PARTIALLY_OCCUPIED'
                ELSE 'AVAILABLE' END,
           f.amount, f.status
      FROM hostel.room r
      JOIN hostel.hall h ON h.code = r.hall_code
      JOIN hostel.room_category rc ON rc.code = r.category
      LEFT JOIN hostel.room_type rt ON rt.code = r.room_type
      LEFT JOIN beds bd ON bd.room_id = r.id
      LEFT JOIN LATERAL hostel.fee_for(p_session, r.hall_code, r.room_type, r.category, NULL) f ON true
     ORDER BY h.name, r.block, r.floor, r.room_no
$fn$;
COMMENT ON FUNCTION hostel.room_board(text) IS 'Every room of the inventory for a session (V290): capacity, beds out of service, occupied (checked in), reserved (held, confirmed, accepted), available, the derived status and the fee.';

-- ── 7 · free beds: only general rooms are chosen by students or drawn; every bed is the Dean's to allocate ──
CREATE OR REPLACE FUNCTION hostel.free_beds(p_session text)
 RETURNS TABLE(room_id uuid, hall_code text, hall_sex text, block text, room_no text, bed integer, bed_id uuid, room_type text, floor integer, block_id uuid)
 LANGUAGE sql STABLE AS $fn$
    SELECT r.id, r.hall_code, coalesce(r.sex, h.sex), r.block, r.room_no, b.number, b.id, r.room_type, r.floor, r.block_id
      FROM hostel.room r
      JOIN hostel.hall h ON h.code = r.hall_code AND h.ended_on IS NULL AND h.state = 'ACTIVE'
      JOIN hostel.room_category rc ON rc.code = r.category AND rc.general_selection AND rc.active
      JOIN hostel.bed b ON b.room_id = r.id AND b.state = 'AVAILABLE'
      LEFT JOIN hostel.block bl ON bl.id = r.block_id
     WHERE r.state = 'AVAILABLE' AND (bl.id IS NULL OR bl.state = 'ACTIVE')
       AND NOT EXISTS (SELECT 1 FROM hostel.allocation a
                        WHERE a.room_id = r.id AND a.bed = b.number AND a.lapsed_at IS NULL AND a.ended_at IS NULL AND a.session = p_session)
     ORDER BY h.code, r.block, r.room_no, b.number
$fn$;

CREATE OR REPLACE FUNCTION hostel.allocatable_beds(p_session text)
 RETURNS TABLE(room_id uuid, hall_code text, hall_name text, hall_sex text, block text, room_no text, bed integer, bed_id uuid, bed_label text, room_type text, floor integer, category text, category_label text, general_selection boolean, chargeable boolean, fee numeric, fee_status text)
 LANGUAGE sql STABLE AS $fn$
    SELECT r.id, r.hall_code, h.name, coalesce(r.sex, h.sex), r.block, r.room_no, b.number, b.id, b.label, r.room_type, r.floor, r.category, rc.label, rc.general_selection, rc.chargeable, f.amount, f.status
      FROM hostel.room r
      JOIN hostel.hall h ON h.code = r.hall_code AND h.ended_on IS NULL AND h.state = 'ACTIVE'
      JOIN hostel.room_category rc ON rc.code = r.category
      JOIN hostel.bed b ON b.room_id = r.id AND b.state = 'AVAILABLE'
      LEFT JOIN hostel.block bl ON bl.id = r.block_id
      LEFT JOIN LATERAL hostel.fee_for(p_session, r.hall_code, r.room_type, r.category, NULL) f ON true
     WHERE r.state = 'AVAILABLE' AND (bl.id IS NULL OR bl.state = 'ACTIVE')
       AND NOT EXISTS (SELECT 1 FROM hostel.allocation a
                        WHERE a.bed_id = b.id AND a.lapsed_at IS NULL AND a.ended_at IS NULL AND a.session = p_session)
     ORDER BY h.name, r.block, r.room_no, b.number
$fn$;

-- ── 8 · eligibility: school fees paid and course registration submitted ──
CREATE OR REPLACE FUNCTION hostel.eligibility(p_student uuid, p_session text)
 RETURNS TABLE(ok boolean, why text)
 LANGUAGE plpgsql STABLE AS $fn$
DECLARE s hostel.session_setting; st people.student; v_fac text; v_debt numeric; v_paid boolean;
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
    -- the University's two prerequisites (V290): school fees paid in full, and course registration submitted
    IF s.require_school_fees THEN
        SELECT p.paid_in_full INTO v_paid FROM finance.position(st.id, p_session) p;
        IF NOT coalesce(v_paid, false) THEN RETURN QUERY SELECT false, 'School fees payment for ' || p_session || ' is required before hostel application'; RETURN; END IF;
    END IF;
    IF s.require_registration AND NOT EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = st.id AND r.session = p_session AND r.status IN ('SUBMITTED','APPROVED','LOCKED')) THEN
        RETURN QUERY SELECT false, 'Course registration for ' || p_session || ' is required before hostel application'; RETURN;
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
END $fn$;

-- the checklist the student's dashboard shows: each prerequisite on its own, and the window
CREATE OR REPLACE FUNCTION hostel.eligibility_checklist(p_student uuid, p_session text)
RETURNS TABLE(school_fees boolean, course_registration boolean, status_ok boolean, window_open boolean, eligible boolean, why text, require_school_fees boolean, require_registration boolean)
LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT p.paid_in_full FROM finance.position(p_student, p_session) p), false),
           EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = p_session AND r.status IN ('SUBMITTED','APPROVED','LOCKED')),
           EXISTS (SELECT 1 FROM people.student st JOIN hostel.session_setting s ON s.session = p_session WHERE st.id = p_student AND st.status = ANY (s.eligible_statuses)),
           EXISTS (SELECT 1 FROM hostel.session_setting s WHERE s.session = p_session AND s.state = 'OPEN' AND s.drawn_at IS NULL
                      AND (s.applications_open IS NULL OR s.applications_open <= current_date) AND (s.applications_close IS NULL OR s.applications_close >= current_date)),
           e.ok, e.why,
           coalesce((SELECT s.require_school_fees FROM hostel.session_setting s WHERE s.session = p_session), true),
           coalesce((SELECT s.require_registration FROM hostel.session_setting s WHERE s.session = p_session), true)
      FROM hostel.eligibility(p_student, p_session) e
$fn$;

-- ── 9 · the hold: the one door, now aware of the category and the fee ──
CREATE OR REPLACE FUNCTION hostel.hold(p_application uuid, p_bed uuid, p_basis text, p_position integer, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql AS $fn$
DECLARE ap hostel.application; s hostel.session_setting; b hostel.bed; r hostel.room; h hostel.hall; rc hostel.room_category; st people.student; e record; f record; v uuid; v_state text;
        who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO ap FROM hostel.application WHERE id = p_application FOR UPDATE;
    IF ap.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    SELECT * INTO s FROM hostel.session_setting WHERE session = ap.session;
    SELECT * INTO b FROM hostel.bed WHERE id = p_bed FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such bed' USING ERRCODE = '23503'; END IF;
    SELECT * INTO r FROM hostel.room WHERE id = b.room_id;
    SELECT * INTO h FROM hostel.hall WHERE code = r.hall_code;
    SELECT * INTO rc FROM hostel.room_category WHERE code = r.category;
    SELECT * INTO st FROM people.student WHERE id = ap.student_id;
    IF ap.state NOT IN ('APPLIED','UNSUCCESSFUL','LAPSED') THEN RAISE EXCEPTION 'application % is %; only one that waits is seated', ap.reference, lower(ap.state) USING ERRCODE = '23514'; END IF;
    IF ap.review = 'REJECTED' THEN RAISE EXCEPTION 'application % was rejected at review', ap.reference USING ERRCODE = '23514'; END IF;
    IF s.requires_review AND ap.review IS DISTINCT FROM 'APPROVED' THEN RAISE EXCEPTION 'application % has not been approved at review', ap.reference USING ERRCODE = '23514', HINT = 'Approve it on the applications desk first.'; END IF;
    SELECT * INTO e FROM hostel.eligibility(ap.student_id, ap.session);
    IF NOT e.ok THEN RAISE EXCEPTION 'the student is not eligible: %', e.why USING ERRCODE = '23514'; END IF;
    -- a room that is not for general selection is the Dean's to allocate, never a student's to take nor the draw's to give
    IF NOT rc.general_selection AND p_basis <> 'SPECIAL' THEN
        RAISE EXCEPTION 'HOSTEL_ROOM_PROTECTED: room % of % is a % room and is not open to general reservation', r.room_no, h.name, lower(rc.label) USING ERRCODE = '23514';
    END IF;
    IF b.state <> 'AVAILABLE' THEN RAISE EXCEPTION 'bed % of room % is %', b.label, r.room_no, lower(replace(b.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
    IF r.state <> 'AVAILABLE' THEN RAISE EXCEPTION 'room % is %', r.room_no, lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
    IF h.state <> 'ACTIVE' OR h.ended_on IS NOT NULL THEN RAISE EXCEPTION 'hall % is closed', h.name USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM hostel.block bl WHERE bl.id = r.block_id AND bl.state <> 'ACTIVE') THEN RAISE EXCEPTION 'the block is closed' USING ERRCODE = '23514'; END IF;
    IF coalesce(r.sex, h.sex) IS NOT NULL AND st.sex IS NOT NULL AND coalesce(r.sex, h.sex) <> st.sex THEN RAISE EXCEPTION 'hall % is not for this student', h.name USING ERRCODE = '23514'; END IF;
    IF s.eligible_kinds IS NOT NULL AND array_length(s.eligible_kinds, 1) > 0 AND NOT (h.kind = ANY (s.eligible_kinds)) THEN RAISE EXCEPTION 'hall % is a % hall, not one open to this session', h.name, lower(h.kind) USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM hostel.allocation a WHERE a.room_id = r.id AND a.bed = b.number AND a.session = ap.session AND a.lapsed_at IS NULL AND a.ended_at IS NULL) THEN
        RAISE EXCEPTION 'HOSTEL_BED_TAKEN: bed % of room % is already taken', b.label, r.room_no USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM hostel.allocation a WHERE a.student_id = ap.student_id AND a.session = ap.session AND a.lapsed_at IS NULL AND a.ended_at IS NULL) THEN
        RAISE EXCEPTION 'the student already holds a bed for %', ap.session USING ERRCODE = '23514', HINT = 'Transfer the student instead; a student holds one bed a session.';
    END IF;
    SELECT * INTO f FROM hostel.fee_for(ap.session, r.hall_code, r.room_type, r.category, st.current_level);
    v_state := CASE WHEN coalesce(f.amount, 0) = 0 THEN 'CONFIRMED' ELSE 'HELD' END;
    INSERT INTO hostel.allocation (application_id, session, room_id, bed, bed_id, student_id, basis, draw_position, held_until, state, confirmed_at, start_on, end_on,
                                   occupant_kind, category, fee_amount, fee_status, allocated_by, reason)
    VALUES (ap.id, ap.session, r.id, b.number, b.id, ap.student_id, p_basis, p_position,
            now() + make_interval(hours => coalesce(s.hold_hours, 48)), v_state, CASE WHEN v_state = 'CONFIRMED' THEN now() END,
            coalesce(s.stay_from, (SELECT starts_on FROM policy.academic_session WHERE name = ap.session)),
            coalesce(s.stay_to, (SELECT ends_on FROM policy.academic_session WHERE name = ap.session)),
            'STUDENT', r.category, coalesce(f.amount, 0), f.status, who, coalesce(p_reason, p_basis))
    RETURNING id INTO v;
    UPDATE hostel.application SET state = CASE WHEN v_state = 'CONFIRMED' THEN 'CONFIRMED' ELSE 'ALLOCATED' END, draw_position = coalesce(p_position, draw_position) WHERE id = ap.id;
    PERFORM hostel.log(ap.id, v, ap.student_id, h.code, r.id, b.id, CASE WHEN p_basis = 'SELF' THEN 'RESERVATION_CREATED' ELSE 'ALLOCATED' END, NULL,
                       h.name || ' · ' || r.block || '-' || r.room_no || ' · ' || b.label || ' · ' || f.status || ' ' || coalesce(f.amount, 0)::text, coalesce(p_reason, p_basis));
    RETURN v;
END $fn$;

-- ── 10 · the student's own reservation of a room, held 48 hours ────────
CREATE OR REPLACE FUNCTION hostel.reserve_room(p_student uuid, p_session text, p_room uuid)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE s hostel.session_setting; r hostel.room; rc hostel.room_category; ap hostel.application; b hostel.bed; v uuid; a record; e record;
BEGIN
    SELECT * INTO s FROM hostel.session_setting WHERE session = p_session;
    IF s.session IS NULL OR s.state IN ('DRAFT') THEN
        RAISE EXCEPTION 'HOSTEL_APPLICATION_CLOSED: hostel applications for % are not open', p_session USING ERRCODE = '23514';
    END IF;
    IF s.state = 'CLOSED' OR s.drawn_at IS NOT NULL THEN
        RAISE EXCEPTION 'HOSTEL_APPLICATION_CLOSED: hostel applications for % are currently closed', p_session USING ERRCODE = '23514';
    END IF;
    IF s.applications_open IS NOT NULL AND s.applications_open > current_date THEN
        RAISE EXCEPTION 'HOSTEL_APPLICATION_CLOSED: hostel applications for % open on %', p_session, to_char(s.applications_open, 'DD Month YYYY') USING ERRCODE = '23514';
    END IF;
    IF s.applications_close IS NOT NULL AND s.applications_close < current_date THEN
        RAISE EXCEPTION 'HOSTEL_APPLICATION_CLOSED: hostel applications for % closed on %', p_session, to_char(s.applications_close, 'DD Month YYYY') USING ERRCODE = '23514';
    END IF;
    IF s.allocation_method <> 'FIRST_COME' THEN
        RAISE EXCEPTION 'HOSTEL_SELF_RESERVATION: rooms for % are allocated by %, not chosen; apply and the desk allocates', p_session, lower(replace(s.allocation_method, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF s.requires_review THEN
        RAISE EXCEPTION 'HOSTEL_SELF_RESERVATION: applications for % are reviewed by the desk before a bed is given; apply first', p_session USING ERRCODE = '23514';
    END IF;
    SELECT * INTO e FROM hostel.eligibility(p_student, p_session);
    IF NOT e.ok THEN RAISE EXCEPTION 'HOSTEL_NOT_ELIGIBLE: %', e.why USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM hostel.room WHERE id = p_room;
    IF r.id IS NULL THEN RAISE EXCEPTION 'no such room' USING ERRCODE = '23503'; END IF;
    SELECT * INTO rc FROM hostel.room_category WHERE code = r.category;
    IF NOT rc.general_selection THEN
        RAISE EXCEPTION 'HOSTEL_ROOM_PROTECTED: room % is a % room and is not open to general reservation', r.room_no, lower(rc.label) USING ERRCODE = '23514';
    END IF;
    IF r.state <> 'AVAILABLE' THEN
        RAISE EXCEPTION 'HOSTEL_ROOM_UNAVAILABLE: room % is %', r.room_no, lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM hostel.allocation x WHERE x.student_id = p_student AND x.session = p_session AND x.lapsed_at IS NULL AND x.ended_at IS NULL) THEN
        RAISE EXCEPTION 'HOSTEL_ALREADY_HELD: a bed is already held or allocated to you for %', p_session USING ERRCODE = '23514';
    END IF;
    -- the application that carries the reservation: the one standing, or a new one through the same door as before
    SELECT * INTO ap FROM hostel.application WHERE student_id = p_student AND session = p_session AND state <> 'WITHDRAWN';
    IF ap.id IS NULL THEN
        v := hostel.apply(p_student, p_session, r.hall_code, 'NONE', NULL, r.room_type, r.block, NULL, NULL, NULL);
        SELECT * INTO ap FROM hostel.application WHERE id = v;
    END IF;
    -- the bed: one free bed of the room, locked so a second student in the same instant takes the next bed or none
    SELECT bd.* INTO b FROM hostel.bed bd
     WHERE bd.room_id = r.id AND bd.state = 'AVAILABLE'
       AND NOT EXISTS (SELECT 1 FROM hostel.allocation x WHERE x.bed_id = bd.id AND x.session = p_session AND x.lapsed_at IS NULL AND x.ended_at IS NULL)
     ORDER BY bd.number
     FOR UPDATE SKIP LOCKED LIMIT 1;
    IF b.id IS NULL THEN
        RAISE EXCEPTION 'HOSTEL_ROOM_FULL: This room is no longer available. Please select another room.' USING ERRCODE = '23514';
    END IF;
    v := hostel.hold(ap.id, b.id, 'SELF', NULL, 'Reserved by the student');
    SELECT al.state, al.held_until, al.fee_amount, al.reference_no, h.name AS hall INTO a
      FROM hostel.allocation al JOIN hostel.hall h ON h.code = r.hall_code WHERE al.id = v;
    PERFORM hostel.tell_student(p_student, 'Your hostel room is reserved',
        'Reservation ' || a.reference_no || ': ' || a.hall || ', Block ' || r.block || ', Room ' || r.room_no || ', ' || b.label || '. '
        || CASE WHEN a.state = 'HELD' THEN 'Pay the hostel fee of NGN ' || a.fee_amount::text || ' by ' || to_char(a.held_until AT TIME ZONE 'Africa/Lagos', 'FMDay DD FMMonth YYYY HH24:MI') || ' (' || coalesce(s.hold_hours, 48) || ' hours); unpaid, the reservation expires and the bed is released.'
                ELSE 'No hostel charge applies; accept the allocation on the portal.' END,
        'MOAUM: room ' || r.room_no || ' reserved. Pay by ' || to_char(a.held_until AT TIME ZONE 'Africa/Lagos', 'DD Mon HH24:MI') || '.');
    RETURN v;
END $fn$;
COMMENT ON FUNCTION hostel.reserve_room(uuid, text, uuid) IS 'An eligible student reserves a bed in a general room of a first-come session (V290): window, eligibility and category enforced here, the bed locked, held for the session''s hold hours.';

-- what an eligible student may choose: general rooms of active halls open to their sex, with a bed free
CREATE OR REPLACE FUNCTION hostel.room_choices(p_student uuid, p_session text)
RETURNS TABLE(room_id uuid, hall_code text, hall_name text, hall_sex text, hall_kind text, campus text, block text, floor int, room_no text, room_type text, room_type_label text,
              category text, category_label text, general_selection boolean, chargeable boolean, room_state text, state_reason text,
              capacity int, out_of_service int, occupied int, reserved int, available int, status text, fee numeric, fee_status text)
LANGUAGE sql STABLE AS $fn$
    SELECT rb.* FROM hostel.room_board(p_session) rb
      JOIN hostel.hall h ON h.code = rb.hall_code
      LEFT JOIN people.student st ON st.id = p_student
      LEFT JOIN hostel.session_setting s ON s.session = p_session
     WHERE rb.general_selection AND rb.room_state = 'AVAILABLE' AND rb.available > 0 AND h.state = 'ACTIVE' AND h.ended_on IS NULL
       AND (rb.hall_sex IS NULL OR st.sex IS NULL OR rb.hall_sex = st.sex)
       AND (s.eligible_kinds IS NULL OR array_length(s.eligible_kinds, 1) IS NULL OR h.kind = ANY (s.eligible_kinds))
     ORDER BY rb.hall_name, rb.block, rb.room_no
$fn$;

-- ── 11 · the Dean's special, Student Union and Security allocations ─────
CREATE OR REPLACE FUNCTION hostel.allocate_special(p_bed uuid, p_session text, p_category text, p_student uuid, p_person uuid, p_name text, p_reason text, p_start date, p_end date)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        b hostel.bed; r hostel.room; h hostel.hall; rc hostel.room_category; st people.student; f record; v uuid; v_app uuid; v_kind text; v_name text; v_action text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'HOSTEL_ALLOCATION_REFUSED: a special allocation is made by a person' USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'HOSTEL_ALLOCATION_REFUSED: a special allocation carries its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO b FROM hostel.bed WHERE id = p_bed FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such bed' USING ERRCODE = '23503'; END IF;
    SELECT * INTO r FROM hostel.room WHERE id = b.room_id;
    SELECT * INTO h FROM hostel.hall WHERE code = r.hall_code;
    SELECT * INTO rc FROM hostel.room_category WHERE code = r.category;
    IF p_category IS NOT NULL AND upper(p_category) <> r.category THEN
        RAISE EXCEPTION 'HOSTEL_ALLOCATION_REFUSED: room % is a % room; set its category first if it is to be %', r.room_no, lower(rc.label), lower(p_category) USING ERRCODE = '23514';
    END IF;
    IF b.state <> 'AVAILABLE' THEN RAISE EXCEPTION 'HOSTEL_ALLOCATION_REFUSED: bed % of room % is %', b.label, r.room_no, lower(replace(b.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
    IF r.state <> 'AVAILABLE' THEN RAISE EXCEPTION 'HOSTEL_ALLOCATION_REFUSED: room % is %', r.room_no, lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
    IF h.state <> 'ACTIVE' OR h.ended_on IS NOT NULL THEN RAISE EXCEPTION 'HOSTEL_ALLOCATION_REFUSED: hall % is closed', h.name USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM hostel.allocation a WHERE a.bed_id = b.id AND a.session = p_session AND a.lapsed_at IS NULL AND a.ended_at IS NULL) THEN
        RAISE EXCEPTION 'HOSTEL_BED_TAKEN: bed % of room % is already taken', b.label, r.room_no USING ERRCODE = '23514';
    END IF;
    IF p_student IS NOT NULL THEN
        SELECT * INTO st FROM people.student WHERE id = p_student;
        IF st.id IS NULL THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
        IF EXISTS (SELECT 1 FROM hostel.allocation a WHERE a.student_id = p_student AND a.session = p_session AND a.lapsed_at IS NULL AND a.ended_at IS NULL) THEN
            RAISE EXCEPTION 'HOSTEL_ALLOCATION_REFUSED: the student already holds a bed for %', p_session USING ERRCODE = '23514';
        END IF;
        IF coalesce(r.sex, h.sex) IS NOT NULL AND st.sex IS NOT NULL AND coalesce(r.sex, h.sex) <> st.sex THEN RAISE EXCEPTION 'HOSTEL_ALLOCATION_REFUSED: hall % is not for this student', h.name USING ERRCODE = '23514'; END IF;
        v_kind := 'STUDENT'; v_name := st.surname || ', ' || st.other_names;
        -- the stay is on the student's own record too: an application carries it, as every stay has one
        SELECT id INTO v_app FROM hostel.application WHERE student_id = p_student AND session = p_session AND state <> 'WITHDRAWN';
        IF v_app IS NULL THEN
            INSERT INTO hostel.application (student_id, session, hall_code, category, category_note, review, review_note, reviewed_by, reviewed_at, state)
            VALUES (p_student, p_session, r.hall_code, 'OTHER', 'Allocated by the Dean of Student Affairs: ' || btrim(p_reason), 'APPROVED', 'Special allocation', who, now(), 'CONFIRMED')
            RETURNING id INTO v_app;
        ELSE
            UPDATE hostel.application SET state = 'CONFIRMED', review = coalesce(review, 'APPROVED') WHERE id = v_app;
        END IF;
    ELSIF p_person IS NOT NULL THEN
        SELECT surname || ', ' || given_names INTO v_name FROM iam.person WHERE id = p_person;
        IF v_name IS NULL THEN RAISE EXCEPTION 'no such person' USING ERRCODE = '23503'; END IF;
        v_kind := 'STAFF';
    ELSE
        IF nullif(btrim(coalesce(p_name, '')), '') IS NULL THEN RAISE EXCEPTION 'HOSTEL_ALLOCATION_REFUSED: name the occupant' USING ERRCODE = '23514'; END IF;
        v_kind := 'OTHER'; v_name := btrim(p_name);
    END IF;
    SELECT * INTO f FROM hostel.fee_for(p_session, r.hall_code, r.room_type, r.category, CASE WHEN st.id IS NOT NULL THEN st.current_level END);
    INSERT INTO hostel.allocation (application_id, session, room_id, bed, bed_id, student_id, basis, held_until, state, confirmed_at, start_on, end_on,
                                   occupant_kind, occupant_person_id, occupant_name, category, fee_amount, fee_status, allocated_by, reason)
    VALUES (v_app, p_session, r.id, b.number, b.id, p_student, 'SPECIAL', now(), 'CONFIRMED', now(),
            coalesce(p_start, (SELECT stay_from FROM hostel.session_setting WHERE session = p_session), (SELECT starts_on FROM policy.academic_session WHERE name = p_session)),
            coalesce(p_end, (SELECT stay_to FROM hostel.session_setting WHERE session = p_session), (SELECT ends_on FROM policy.academic_session WHERE name = p_session)),
            v_kind, p_person, CASE WHEN v_kind = 'STUDENT' THEN NULL ELSE v_name END, r.category, coalesce(f.amount, 0), f.status, who, btrim(p_reason))
    RETURNING id INTO v;
    v_action := CASE r.category WHEN 'STUDENT_UNION' THEN 'SU_ALLOCATION_CREATED' WHEN 'SECURITY' THEN 'SECURITY_ALLOCATION_CREATED' ELSE 'SPECIAL_ALLOCATION_CREATED' END;
    PERFORM hostel.log(v_app, v, p_student, h.code, r.id, b.id, v_action, NULL, v_name || ' · ' || h.name || ' ' || r.block || '-' || r.room_no || ' ' || b.label || ' · ' || f.status || ' ' || coalesce(f.amount, 0)::text, btrim(p_reason));
    IF p_student IS NOT NULL THEN
        PERFORM hostel.tell_student(p_student, 'You have been allocated a hostel room',
            'The Dean of Student Affairs has allocated you ' || h.name || ', Block ' || r.block || ', Room ' || r.room_no || ', ' || b.label || ' for ' || p_session || '. '
            || CASE WHEN f.status = 'PAYABLE' THEN 'The hostel fee of NGN ' || f.amount::text || ' is payable: generate the reference under Hostel on the portal and pay it.' ELSE 'No hostel charge applies to this allocation.' END,
            'MOAUM: hostel room ' || r.room_no || ' allocated to you for ' || p_session || '.');
    END IF;
    RETURN v;
END $fn$;
COMMENT ON FUNCTION hostel.allocate_special(uuid, text, text, uuid, uuid, text, text, date, date) IS 'The Dean of Student Affairs allocates a bed of a special, Student Union or Security room (V290) to a student, a member of staff or a named person: payable or no charge by the category, confirmed at once, and always on the record.';

-- ── 12 · the fee reference and its confirmation follow the allocation's own fee ──
CREATE OR REPLACE FUNCTION hostel.new_fee_reference(p_application uuid)
 RETURNS text
 LANGUAGE plpgsql AS $fn$
DECLARE ap hostel.application; al hostel.allocation; v_ref text;
BEGIN
    SELECT * INTO ap FROM hostel.application WHERE id = p_application;
    IF NOT FOUND THEN RAISE EXCEPTION 'no application %', p_application USING ERRCODE = 'no_data_found'; END IF;
    SELECT * INTO al FROM hostel.allocation WHERE application_id = ap.id AND lapsed_at IS NULL AND ended_at IS NULL ORDER BY allocated_at DESC LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'no bed is held against this application' USING ERRCODE = '23514',
        HINT = 'The accommodation fee is paid against a bed allocated; without one there is nothing to pay for.'; END IF;
    IF al.fee_status = 'PAID' THEN RAISE EXCEPTION 'this allocation is already paid and confirmed' USING ERRCODE = '23505'; END IF;
    IF al.fee_status = 'NO_CHARGE' OR coalesce(al.fee_amount, 0) = 0 THEN RAISE EXCEPTION 'HOSTEL_NO_CHARGE: no hostel charge applies to this allocation' USING ERRCODE = '23514'; END IF;
    IF al.state = 'HELD' AND al.held_until < now() THEN RAISE EXCEPTION 'HOSTEL_RESERVATION_EXPIRED: the reservation of this bed expired at %', to_char(al.held_until AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') USING ERRCODE = '23514',
        HINT = 'The bed is released; reserve again if applications are open and a bed is free.'; END IF;
    IF al.reference IS NOT NULL AND EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = al.reference AND expires_at > now() AND confirmed_at IS NULL) THEN
        RETURN al.reference;
    END IF;
    v_ref := finance.new_purpose_reference(ap.student_id, ap.session, al.fee_amount, 'Hostel accommodation ' || ap.session || ' ' || al.id::text);
    UPDATE hostel.allocation SET reference = v_ref WHERE id = al.id;
    RETURN v_ref;
END $fn$;

CREATE OR REPLACE FUNCTION hostel.confirm_by_reference(p_reference text)
 RETURNS void
 LANGUAGE plpgsql AS $fn$
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
    SELECT * INTO al FROM hostel.allocation WHERE reference = p_reference AND coalesce(fee_status, 'PAYABLE') <> 'PAID' ORDER BY allocated_at DESC LIMIT 1;
    IF NOT FOUND THEN RETURN; END IF;
    IF al.lapsed_at IS NOT NULL AND EXISTS (SELECT 1 FROM hostel.allocation o WHERE o.session = al.session AND o.room_id = al.room_id AND o.bed = al.bed
                                              AND o.id <> al.id AND o.lapsed_at IS NULL AND o.ended_at IS NULL) THEN
        RAISE EXCEPTION 'the reservation of this bed expired before the payment arrived, and the bed went to another student'
        USING ERRCODE = '23514', HINT = 'The payment stands for the Bursary to refund or apply; the Dean of Student Affairs allocates a bed that is free.';
    END IF;
    UPDATE hostel.allocation SET confirmed_at = coalesce(confirmed_at, now()), lapsed_at = NULL, fee_status = 'PAID',
           state = CASE WHEN state IN ('HELD', 'LAPSED') THEN 'CONFIRMED' ELSE state END WHERE id = al.id;
    UPDATE hostel.application SET state = CASE WHEN state IN ('ALLOCATED', 'LAPSED') THEN 'CONFIRMED' ELSE state END WHERE id = al.application_id;
    PERFORM hostel.log(al.application_id, al.id, al.student_id, NULL, al.room_id, al.bed_id, 'PAYMENT_VERIFIED', al.state, 'CONFIRMED', 'Reference ' || p_reference);
    IF al.student_id IS NOT NULL THEN
        PERFORM hostel.tell_student(al.student_id, 'Your hostel payment is confirmed',
            'The Bursary has confirmed your hostel payment against ' || p_reference || '. Allocation ' || al.reference_no || ' is confirmed; accept it on the portal and check in at the porter''s lodge.',
            'MOAUM: hostel payment ' || p_reference || ' confirmed. Allocation ' || al.reference_no || ' is yours.');
    END IF;
    PERFORM hostel.tell_desk('A hostel fee has been confirmed', 'Allocation ' || al.reference_no || ' is paid and confirmed; the occupant may now accept and check in.');
END $fn$;

-- ── 13 · the lapse tells the student the reservation expired; the reminders before it ──
CREATE OR REPLACE FUNCTION hostel.lapse_holds(p_session text)
 RETURNS integer
 LANGUAGE plpgsql AS $fn$
DECLARE s hostel.session_setting; a record; nxt record; n int := 0; v uuid;
BEGIN
    SELECT * INTO s FROM hostel.session_setting WHERE session = p_session;
    IF NOT FOUND THEN RETURN 0; END IF;
    FOR a IN
        SELECT al.id, al.room_id, al.bed, al.bed_id, al.student_id, al.application_id, al.reference_no, al.basis FROM hostel.allocation al
         WHERE al.session = p_session AND al.state = 'HELD' AND al.confirmed_at IS NULL AND al.lapsed_at IS NULL AND al.ended_at IS NULL AND al.held_until < now()
         ORDER BY al.held_until
    LOOP
        UPDATE hostel.allocation SET lapsed_at = now(), state = 'LAPSED' WHERE id = a.id;
        UPDATE hostel.application SET state = 'LAPSED' WHERE id = a.application_id;
        PERFORM hostel.log(a.application_id, a.id, a.student_id, NULL, a.room_id, a.bed_id, 'RESERVATION_EXPIRED', 'HELD', 'EXPIRED', 'The hold expired unpaid; the bed is released');
        IF a.student_id IS NOT NULL THEN
            PERFORM hostel.tell_student(a.student_id, 'Your hostel reservation has expired',
                'The bed reserved for you under ' || a.reference_no || ' was not paid for within the hold window and has been released. '
                || CASE WHEN a.basis = 'SELF' THEN 'If applications are still open you may reserve again where a bed is free.' ELSE 'It has gone to the next name on the list.' END,
                'MOAUM: hostel reservation ' || a.reference_no || ' expired unpaid; the bed is released.');
        END IF;
        n := n + 1;
        -- a drawn bed goes to the next name on the list; a bed the student reserved simply becomes free again
        IF s.waitlist AND a.basis <> 'SELF' THEN
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
END $fn$;

CREATE OR REPLACE FUNCTION hostel.remind_holds()
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE a record; n int := 0; mark text;
BEGIN
    FOR a IN
        SELECT al.id, al.student_id, al.reference_no, al.held_until, al.fee_amount, al.reminders,
               EXTRACT(EPOCH FROM (al.held_until - now())) / 3600 AS hours_left
          FROM hostel.allocation al
         WHERE al.state = 'HELD' AND al.confirmed_at IS NULL AND al.lapsed_at IS NULL AND al.ended_at IS NULL AND al.student_id IS NOT NULL AND al.held_until > now()
    LOOP
        mark := CASE WHEN a.hours_left <= 1 THEN '1h' WHEN a.hours_left <= 6 THEN '6h' WHEN a.hours_left <= 24 THEN '24h' END;
        IF mark IS NOT NULL AND NOT (a.reminders ? mark) THEN
            UPDATE hostel.allocation SET reminders = reminders || to_jsonb(mark) WHERE id = a.id;
            PERFORM hostel.tell_student(a.student_id, 'Hostel payment deadline: ' || CASE mark WHEN '1h' THEN 'one hour' WHEN '6h' THEN 'six hours' ELSE '24 hours' END || ' remaining',
                'The bed reserved for you under ' || a.reference_no || ' is held until ' || to_char(a.held_until AT TIME ZONE 'Africa/Lagos', 'FMDay DD FMMonth YYYY HH24:MI') || '. Pay the hostel fee of NGN ' || coalesce(a.fee_amount, 0)::text || ' before then or the reservation expires and the bed is released.',
                'MOAUM: hostel reservation ' || a.reference_no || ' expires ' || to_char(a.held_until AT TIME ZONE 'Africa/Lagos', 'DD Mon HH24:MI') || '. Pay now.');
            n := n + 1;
        END IF;
    END LOOP;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION hostel.remind_holds() IS 'Once each at 24, 6 and 1 hours before a reservation expires, the student is reminded (V290); the marks on the allocation stop a reminder repeating.';

-- ── 14 · an occupied room is not taken out of service under its occupants ──
CREATE OR REPLACE FUNCTION hostel.close(p_kind text, p_id text, p_state text, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql AS $fn$
DECLARE n int := 0; occ int := 0;
BEGIN
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL AND p_state NOT IN ('ACTIVE','AVAILABLE') THEN RAISE EXCEPTION 'say why it is closed' USING ERRCODE = '23514'; END IF;
    IF p_kind = 'ROOM' AND p_state IN ('MAINTENANCE', 'OUT_OF_SERVICE', 'INACTIVE', 'CLOSED') THEN
        SELECT count(*) INTO occ FROM hostel.allocation al WHERE al.room_id = p_id::uuid AND al.state = 'CHECKED_IN' AND al.lapsed_at IS NULL AND al.ended_at IS NULL;
        IF occ > 0 THEN RAISE EXCEPTION 'HOSTEL_ROOM_OCCUPIED: % occupant(s) are checked in to this room; transfer them before it is taken out of service', occ USING ERRCODE = '23514'; END IF;
    END IF;
    IF p_kind = 'BED' AND p_state IN ('MAINTENANCE', 'OUT_OF_SERVICE') THEN
        SELECT count(*) INTO occ FROM hostel.allocation al WHERE al.bed_id = p_id::uuid AND al.state = 'CHECKED_IN' AND al.lapsed_at IS NULL AND al.ended_at IS NULL;
        IF occ > 0 THEN RAISE EXCEPTION 'HOSTEL_ROOM_OCCUPIED: the bed is occupied; transfer the occupant before it is taken out of service' USING ERRCODE = '23514'; END IF;
    END IF;
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
                       CASE WHEN p_kind = 'ROOM' AND p_state = 'MAINTENANCE' THEN 'ROOM_MARKED_MAINTENANCE' ELSE p_kind || '_' || p_state END, NULL, p_state,
                       coalesce(p_reason, '') || CASE WHEN n > 0 THEN ' · ' || n || ' occupant(s) affected' ELSE '' END);
    RETURN n;
END $fn$;

-- the category of a room, changed on the record
CREATE OR REPLACE FUNCTION hostel.set_room_category(p_room uuid, p_category text, p_reason text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE r hostel.room; occ int;
BEGIN
    SELECT * INTO r FROM hostel.room WHERE id = p_room FOR UPDATE;
    IF r.id IS NULL THEN RAISE EXCEPTION 'no such room' USING ERRCODE = '23503'; END IF;
    IF NOT EXISTS (SELECT 1 FROM hostel.room_category WHERE code = upper(p_category) AND active) THEN RAISE EXCEPTION 'HOSTEL_CATEGORY: % is not a room category', p_category USING ERRCODE = '23514'; END IF;
    IF r.category = upper(p_category) THEN RETURN; END IF;
    SELECT count(*) INTO occ FROM hostel.allocation al WHERE al.room_id = r.id AND al.lapsed_at IS NULL AND al.ended_at IS NULL;
    UPDATE hostel.room SET category = upper(p_category) WHERE id = r.id;
    PERFORM hostel.log(NULL, NULL, NULL, r.hall_code, r.id, NULL, 'ROOM_CATEGORY_CHANGED', r.category, upper(p_category),
                       coalesce(nullif(btrim(p_reason), ''), 'Category changed') || CASE WHEN occ > 0 THEN ' · ' || occ || ' current occupant(s) keep their allocation' ELSE '' END);
END $fn$;

-- ── 15 · the workbook: rows previewed and committed without duplicates ──
CREATE OR REPLACE FUNCTION hostel.import_rows(p_rows jsonb, p_commit boolean)
RETURNS TABLE(row_no int, hall_code text, hall_name text, block text, room_no text, beds int, category text, room_type text, sex text, floor int, outcome text, message text)
LANGUAGE plpgsql AS $fn$
#variable_conflict use_column
DECLARE r record; v_code text; v_name text; v_block text; v_room text; v_beds int; v_cat text; v_type text; v_sex text; v_floor int; v_kind text;
        v_outcome text; v_msg text; seen text[] := ARRAY[]::text[]; k text; ex hostel.room; v_n int := 0; v_new int := 0; v_upd int := 0;
BEGIN
    FOR r IN SELECT ord, j FROM jsonb_array_elements(p_rows) WITH ORDINALITY AS t(j, ord) LOOP
        v_n := v_n + 1;
        v_name := nullif(btrim(coalesce(r.j->>'hall_name', r.j->>'hall', '')), '');
        v_code := upper(regexp_replace(coalesce(nullif(btrim(coalesce(r.j->>'hall_code', '')), ''), ''), '[^A-Za-z0-9]', '', 'g'));
        IF v_code = '' AND v_name IS NOT NULL THEN
            -- a code from the name: the initials of its words, then the letters, to eight characters
            v_code := upper(left(regexp_replace((SELECT string_agg(left(w, 1), '') FROM regexp_split_to_table(v_name, '\s+') w WHERE w <> ''), '[^A-Za-z0-9]', '', 'g'), 8));
            IF length(v_code) < 2 THEN v_code := upper(left(regexp_replace(v_name, '[^A-Za-z0-9]', '', 'g'), 8)); END IF;
        END IF;
        v_block := upper(nullif(btrim(coalesce(r.j->>'block', '')), ''));
        v_room := nullif(btrim(coalesce(r.j->>'room_no', r.j->>'room', '')), '');
        v_beds := nullif(regexp_replace(coalesce(r.j->>'beds', r.j->>'capacity', ''), '[^0-9]', '', 'g'), '')::int;
        v_cat := upper(regexp_replace(nullif(btrim(coalesce(r.j->>'category', '')), ''), '[^A-Za-z0-9]+', '_', 'g'));
        v_cat := CASE WHEN v_cat IS NULL OR v_cat = '' THEN 'GENERAL' WHEN v_cat IN ('SU', 'STUDENT_UNION', 'STUDENTS_UNION', 'UNION') THEN 'STUDENT_UNION'
                      WHEN v_cat IN ('SEC', 'SECURITY') THEN 'SECURITY' WHEN v_cat IN ('SPECIAL', 'RESERVED', 'SPECIAL_RESERVED', 'SPECIAL_RESERVED_') THEN 'SPECIAL' ELSE v_cat END;
        v_type := upper(regexp_replace(nullif(btrim(coalesce(r.j->>'room_type', '')), ''), '[^A-Za-z0-9]+', '_', 'g'));
        v_sex := upper(left(nullif(btrim(coalesce(r.j->>'sex', r.j->>'gender', '')), ''), 1));
        v_sex := CASE WHEN v_sex IN ('F', 'M') THEN v_sex ELSE NULL END;
        v_floor := nullif(regexp_replace(coalesce(r.j->>'floor', ''), '[^0-9]', '', 'g'), '')::int;
        v_kind := upper(nullif(btrim(coalesce(r.j->>'hall_kind', r.j->>'kind', '')), ''));
        v_outcome := NULL; v_msg := NULL;
        IF v_name IS NULL AND (v_code IS NULL OR v_code = '') THEN v_outcome := 'ERROR'; v_msg := 'No hostel named';
        ELSIF v_code !~ '^[A-Z0-9]{2,8}$' THEN v_outcome := 'ERROR'; v_msg := 'The hostel code must be 2 to 8 letters or digits (' || v_code || ')';
        ELSIF v_room IS NULL THEN v_outcome := 'ERROR'; v_msg := 'No room number';
        ELSIF v_beds IS NULL OR v_beds < 1 OR v_beds > 64 THEN v_outcome := 'ERROR'; v_msg := 'The capacity must be 1 to 64 beds';
        ELSIF NOT EXISTS (SELECT 1 FROM hostel.room_category c WHERE c.code = v_cat) THEN v_outcome := 'ERROR'; v_msg := v_cat || ' is not a room category';
        ELSIF v_type IS NOT NULL AND NOT EXISTS (SELECT 1 FROM hostel.room_type t WHERE t.code = v_type) THEN v_outcome := 'ERROR'; v_msg := v_type || ' is not a room type';
        END IF;
        v_block := coalesce(v_block, 'MAIN');
        k := v_code || '|' || v_block || '|' || upper(v_room);
        IF v_outcome IS NULL AND k = ANY (seen) THEN v_outcome := 'DUPLICATE'; v_msg := 'The same hostel, block and room appears earlier in the file'; END IF;
        seen := seen || k;
        IF v_outcome IS NULL THEN
            SELECT * INTO ex FROM hostel.room x WHERE x.hall_code = v_code AND x.block = v_block AND upper(x.room_no) = upper(v_room);
            IF ex.id IS NULL THEN v_outcome := 'NEW'; v_msg := 'Will be created' || CASE WHEN NOT EXISTS (SELECT 1 FROM hostel.hall WHERE code = v_code) THEN ', with the hostel ' || v_code ELSE '' END;
            ELSIF ex.beds = v_beds AND ex.category = v_cat AND (v_type IS NULL OR ex.room_type = v_type) AND (v_sex IS NULL OR ex.sex = v_sex) AND (v_floor IS NULL OR ex.floor = v_floor) THEN v_outcome := 'EXISTING'; v_msg := 'Already on the record as stated';
            ELSE v_outcome := 'UPDATED'; v_msg := 'Capacity ' || ex.beds || ' → ' || v_beds || CASE WHEN ex.category <> v_cat THEN ', category ' || ex.category || ' → ' || v_cat ELSE '' END;
            END IF;
        END IF;
        IF p_commit AND v_outcome IN ('NEW', 'UPDATED') THEN
            INSERT INTO hostel.hall (code, name, sex, kind) VALUES (v_code, coalesce(v_name, v_code), v_sex, coalesce(nullif(v_kind, ''), 'UNDERGRADUATE'))
            ON CONFLICT (code) DO UPDATE SET name = coalesce(EXCLUDED.name, hostel.hall.name), sex = coalesce(hostel.hall.sex, EXCLUDED.sex);
            INSERT INTO hostel.block (hall_code, code, name, floors) VALUES (v_code, v_block, 'Block ' || v_block, greatest(coalesce(v_floor, 0) + 1, 1))
            ON CONFLICT (hall_code, code) DO UPDATE SET floors = greatest(hostel.block.floors, EXCLUDED.floors);
            INSERT INTO hostel.room (hall_code, block, room_no, beds, floor, room_type, sex, category, block_id)
            VALUES (v_code, v_block, v_room, v_beds, coalesce(v_floor, 0), v_type, v_sex, v_cat, (SELECT id FROM hostel.block WHERE hall_code = v_code AND code = v_block))
            ON CONFLICT (hall_code, block, room_no) DO UPDATE SET beds = EXCLUDED.beds, floor = coalesce(EXCLUDED.floor, hostel.room.floor), room_type = coalesce(EXCLUDED.room_type, hostel.room.room_type),
                sex = coalesce(EXCLUDED.sex, hostel.room.sex), category = EXCLUDED.category, block_id = coalesce(EXCLUDED.block_id, hostel.room.block_id);
            IF v_outcome = 'NEW' THEN v_new := v_new + 1; ELSE v_upd := v_upd + 1; END IF;
        END IF;
        row_no := r.ord::int; hall_code := v_code; hall_name := v_name; block := v_block; room_no := v_room; beds := v_beds; category := v_cat; room_type := v_type; sex := v_sex; floor := v_floor; outcome := v_outcome; message := v_msg;
        RETURN NEXT;
    END LOOP;
    IF p_commit AND (v_new + v_upd) > 0 THEN
        PERFORM hostel.log(NULL, NULL, NULL, NULL, NULL, NULL, 'ROOMS_IMPORTED', NULL, v_new || ' new · ' || v_upd || ' updated', v_n || ' rows in the workbook');
    END IF;
END $fn$;
COMMENT ON FUNCTION hostel.import_rows(jsonb, boolean) IS 'The University''s hostel workbook, row by row (V290): NEW, EXISTING, UPDATED, DUPLICATE or ERROR; committed only when asked, idempotent on hostel code + block + room number.';

-- ── 16 · accountability: who occupies every room, paying or not ─────────
CREATE OR REPLACE FUNCTION hostel.accountability(p_session text)
RETURNS TABLE(allocation_id uuid, reference_no text, hall_code text, hall_name text, block text, floor int, room_no text, capacity int, bed_label text,
              occupant text, occupant_number text, occupant_kind text, student_id uuid, category text, category_label text, allocation_type text,
              session text, semester int, fee_status text, fee_amount numeric, payment_status text, start_on date, end_on date, state text,
              allocated_by text, allocated_at timestamptz, reason text, checked_in_at timestamptz)
LANGUAGE sql STABLE AS $fn$
    SELECT al.id, al.reference_no, h.code, h.name, r.block, r.floor, r.room_no, r.beds, b.label,
           coalesce(st.surname || ', ' || st.other_names, al.occupant_name, p.surname || ', ' || p.given_names),
           coalesce(st.matric_no, st.admission_no, p.staff_number),
           al.occupant_kind, al.student_id, coalesce(al.category, r.category), rc.label,
           CASE al.basis WHEN 'SELF' THEN 'Reserved by the student' WHEN 'SPECIAL' THEN 'Allocated by the Dean' WHEN 'BALLOT' THEN 'Ballot' WHEN 'PRIORITY' THEN 'Priority / manual' WHEN 'RESERVE' THEN 'From the waiting list' ELSE al.basis END,
           al.session, s.semester, coalesce(al.fee_status, 'PAYABLE'), coalesce(al.fee_amount, 0),
           CASE coalesce(al.fee_status, 'PAYABLE') WHEN 'NO_CHARGE' THEN 'NOT REQUIRED' WHEN 'PAID' THEN 'PAID' ELSE 'OUTSTANDING' END,
           al.start_on, al.end_on, al.state,
           coalesce(ab.surname || ', ' || ab.given_names, CASE WHEN al.basis = 'BALLOT' THEN 'The draw' WHEN al.basis = 'SELF' THEN 'The student' END),
           al.allocated_at, al.reason, al.checked_in_at
      FROM hostel.allocation al
      JOIN hostel.room r ON r.id = al.room_id
      JOIN hostel.hall h ON h.code = r.hall_code
      JOIN hostel.room_category rc ON rc.code = coalesce(al.category, r.category)
      LEFT JOIN hostel.bed b ON b.id = al.bed_id
      LEFT JOIN people.student st ON st.id = al.student_id
      LEFT JOIN iam.person p ON p.id = al.occupant_person_id
      LEFT JOIN iam.person ab ON ab.id = al.allocated_by
      LEFT JOIN hostel.session_setting s ON s.session = al.session
     WHERE al.session = p_session AND al.lapsed_at IS NULL AND al.ended_at IS NULL
     ORDER BY h.name, r.block, r.room_no, b.number
$fn$;
COMMENT ON FUNCTION hostel.accountability(text) IS 'Who occupies or holds every bed of the session (V290), paying, paid or not required: no occupied room is invisible to this report.';

-- ── 17 · the Bursar's hostel figures ────────────────────────────────────
CREATE OR REPLACE FUNCTION hostel.finance_summary(p_session text)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
    WITH live AS (
        SELECT al.*, r.hall_code, h.name AS hall_name, coalesce(al.category, r.category) AS cat
          FROM hostel.allocation al JOIN hostel.room r ON r.id = al.room_id JOIN hostel.hall h ON h.code = r.hall_code
         WHERE al.session = p_session AND al.lapsed_at IS NULL AND al.ended_at IS NULL),
        tx AS (SELECT count(*) AS n, coalesce(sum(pr.amount), 0) AS amount FROM finance.payment_reference pr
                WHERE pr.session = p_session AND pr.confirmed_at IS NOT NULL AND pr.purpose ~* '^hostel accommodation(?! damage)')
    SELECT jsonb_build_object(
        'session', p_session,
        'totals', jsonb_build_object(
            'charges', coalesce((SELECT sum(fee_amount) FROM live WHERE fee_status IN ('PAYABLE', 'PAID')), 0),
            'paid', coalesce((SELECT sum(fee_amount) FROM live WHERE fee_status = 'PAID'), 0),
            'outstanding', coalesce((SELECT sum(fee_amount) FROM live WHERE fee_status = 'PAYABLE'), 0),
            'transactions', (SELECT n FROM tx), 'transactions_amount', (SELECT amount FROM tx),
            'paid_occupants', (SELECT count(*) FROM live WHERE fee_status = 'PAID'),
            'unpaid_occupants', (SELECT count(*) FROM live WHERE fee_status = 'PAYABLE'),
            'exempt_allocations', (SELECT count(*) FROM live WHERE fee_status = 'NO_CHARGE'),
            'refunds', 0),
        'byHall', coalesce((SELECT jsonb_agg(jsonb_build_object('hall', g.hall_name, 'code', g.hall_code, 'charges', g.charges, 'paid', g.paid, 'outstanding', g.outstanding, 'exempt', g.exempt, 'occupants', g.occupants) ORDER BY g.hall_name)
                             FROM (SELECT hall_name, hall_code, coalesce(sum(fee_amount) FILTER (WHERE fee_status IN ('PAYABLE','PAID')), 0) AS charges, coalesce(sum(fee_amount) FILTER (WHERE fee_status = 'PAID'), 0) AS paid,
                                          coalesce(sum(fee_amount) FILTER (WHERE fee_status = 'PAYABLE'), 0) AS outstanding, count(*) FILTER (WHERE fee_status = 'NO_CHARGE') AS exempt, count(*) AS occupants
                                     FROM live GROUP BY hall_name, hall_code) g), '[]'::jsonb),
        'byCategory', coalesce((SELECT jsonb_agg(jsonb_build_object('category', g.cat, 'label', g.label, 'charges', g.charges, 'paid', g.paid, 'outstanding', g.outstanding, 'exempt', g.exempt, 'occupants', g.occupants) ORDER BY g.cat)
                                 FROM (SELECT live.cat, rc.label, coalesce(sum(fee_amount) FILTER (WHERE fee_status IN ('PAYABLE','PAID')), 0) AS charges, coalesce(sum(fee_amount) FILTER (WHERE fee_status = 'PAID'), 0) AS paid,
                                              coalesce(sum(fee_amount) FILTER (WHERE fee_status = 'PAYABLE'), 0) AS outstanding, count(*) FILTER (WHERE fee_status = 'NO_CHARGE') AS exempt, count(*) AS occupants
                                         FROM live JOIN hostel.room_category rc ON rc.code = live.cat GROUP BY live.cat, rc.label) g), '[]'::jsonb),
        'byStatus', coalesce((SELECT jsonb_agg(jsonb_build_object('status', g.fee_status, 'occupants', g.occupants, 'amount', g.amount) ORDER BY g.fee_status)
                               FROM (SELECT fee_status, count(*) AS occupants, coalesce(sum(fee_amount), 0) AS amount FROM live GROUP BY fee_status) g), '[]'::jsonb))
$fn$;
COMMENT ON FUNCTION hostel.finance_summary(text) IS 'The Bursar''s hostel figures for a session (V290): charges, paid, outstanding, exempt (no charge, never revenue), by hostel, category and status.';

COMMIT;
