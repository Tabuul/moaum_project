-- ═══════════════════════════════════════════════════════════════════════════
-- V705 — the hostel follow-ups to V290, after the University's hostel brief was
-- read against what V030, V261, V290 and V291 already do (30 October 2026).
--
--   · The University's own workbook (the old portal's Hostel_Rooms.xlsx: a
--     "Block" there is a hostel, named by Block ID and Block Name, its gender
--     on the Hostel Blocks sheet) imports as it stands: a hostel is known by
--     the old portal's ID (hostel.hall.legacy_ref), so the two different
--     hostels both named "New Ultra-Modern Hostel" stay two, told apart by
--     their location; a room "Room A1" is room A1 (the screens say "Room");
--     a capacity is never cut below a bed someone holds.
--   · The 48 hours are 48 hours: a hostel fee reference expires when the hold
--     does, so no gateway takes the money after it; a hold past its deadline
--     no longer holds the bed in the room lists, and the student's reservation
--     lapses it first; the clock runs every five minutes.
--   · Money is never refused: a hostel payment that arrives after the bed went
--     to someone else is confirmed as money, the reservation stays expired, and
--     the student, the Dean of Student Affairs and the Bursary are told (before,
--     the error rolled the whole payment confirmation back).
--   · A room's capacity cannot go below a bed that is held or occupied.
--   · Dates are Lagos dates (the databases run in UTC; V539): every hostel rule
--     that read current_date now reads the Lagos day.
--   · "Notify me when a suitable room becomes available": hostel.room_watch,
--     told once by the clock when a room the student could reserve has a bed.
--   · The Dean of Student Affairs is told what the hostel desk is told; the
--     Dean's dashboard counts full, maintenance, special, Student Union and
--     Security rooms and the reservations awaiting payment.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'dsa', true),
       set_config('moaum.reason', 'V705: hostel follow-ups', true);

-- ── 1 · a hostel known by the old portal's ID ───────────────────────────
ALTER TABLE hostel.hall ADD COLUMN IF NOT EXISTS legacy_ref text NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_hall_legacy_ref ON hostel.hall (legacy_ref) WHERE legacy_ref IS NOT NULL;
COMMENT ON COLUMN hostel.hall.legacy_ref IS
  'The hostel''s ID on the old portal (its "Block ID", V705): a workbook that names it finds this hostel again, whatever its name, so two hostels of one name stay two.';

-- ── 2 · a room's capacity never goes below a bed someone holds ──────────
CREATE OR REPLACE FUNCTION hostel.room_capacity_guard()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_bed int; v_n int;
BEGIN
    IF NEW.beds < OLD.beds THEN
        SELECT max(b.number), count(*) INTO v_bed, v_n
          FROM hostel.allocation a JOIN hostel.bed b ON b.id = a.bed_id
         WHERE a.room_id = NEW.id AND b.number > NEW.beds AND a.lapsed_at IS NULL AND a.ended_at IS NULL
           AND NOT (a.state = 'HELD' AND a.held_until < now());
        IF v_n > 0 THEN
            RAISE EXCEPTION 'HOSTEL_CAPACITY_BELOW_OCCUPANCY: room % cannot go down to % bed(s): bed % is held or occupied', NEW.room_no, NEW.beds, v_bed
                USING ERRCODE = '23514', HINT = 'Transfer the occupant to another bed first; a room never holds more people than its capacity.';
        END IF;
    END IF;
    RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS trg_room_capacity_guard ON hostel.room;
CREATE TRIGGER trg_room_capacity_guard BEFORE UPDATE OF beds ON hostel.room
FOR EACH ROW EXECUTE FUNCTION hostel.room_capacity_guard();

-- ── 3 · the boards: a hold past its deadline no longer holds the bed ────
CREATE OR REPLACE FUNCTION hostel.bed_board(p_session text)
 RETURNS TABLE(hall_code text, hall_name text, hall_kind text, hall_sex text, hall_state text, campus text, block_id uuid, block text, block_state text, floor integer, room_id uuid, room_no text, room_type text, room_state text, capacity integer, bed_id uuid, bed_no integer, bed_label text, bed_state text, occupancy text, allocation_id uuid, allocation_state text, student_id uuid, student_name text, student_number text, sex text, programme text, programme_code text, dept_code text, department text, faculty_code text, faculty text, level integer, checked_in_at timestamp with time zone, end_on date)
 LANGUAGE sql STABLE AS $fn$
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
      -- V705: a reservation past its deadline holds nothing, whether or not the clock has lapsed it yet
      LEFT JOIN hostel.allocation al ON al.bed_id = b.id AND al.session = p_session AND al.lapsed_at IS NULL AND al.ended_at IS NULL
                                    AND NOT (al.state = 'HELD' AND al.held_until < now())
      LEFT JOIN people.student st ON st.id = al.student_id
      LEFT JOIN ref.programme p ON p.code = st.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE h.ended_on IS NULL
     ORDER BY h.name, r.block, r.floor, r.room_no, b.number
$fn$;

CREATE OR REPLACE FUNCTION hostel.room_board(p_session text)
 RETURNS TABLE(room_id uuid, hall_code text, hall_name text, hall_sex text, hall_kind text, campus text, block text, floor integer, room_no text, room_type text, room_type_label text, category text, category_label text, general_selection boolean, chargeable boolean, room_state text, state_reason text, capacity integer, out_of_service integer, occupied integer, reserved integer, available integer, status text, fee numeric, fee_status text)
 LANGUAGE sql STABLE AS $fn$
    -- V705: the capacity is the room's own bed count; a bed it no longer has is not counted twice; every live occupant counts
    -- (none is hidden); a reservation past its deadline holds nothing
    WITH live AS (
        SELECT a.bed_id, a.state FROM hostel.allocation a
         WHERE a.session = p_session AND a.lapsed_at IS NULL AND a.ended_at IS NULL AND a.bed_id IS NOT NULL AND NOT (a.state = 'HELD' AND a.held_until < now())),
    beds AS (
        SELECT b.room_id,
               count(*) FILTER (WHERE b.number <= rr.beds AND b.state <> 'AVAILABLE' AND l.bed_id IS NULL)::int AS oos,
               count(l.bed_id) FILTER (WHERE l.state = 'CHECKED_IN')::int AS occupied,
               count(l.bed_id) FILTER (WHERE l.state <> 'CHECKED_IN')::int AS reserved
          FROM hostel.bed b JOIN hostel.room rr ON rr.id = b.room_id LEFT JOIN live l ON l.bed_id = b.id
         GROUP BY b.room_id)
    SELECT r.id, r.hall_code, h.name, coalesce(r.sex, h.sex), h.kind, h.campus, r.block, r.floor, r.room_no, r.room_type, rt.label,
           r.category, rc.label, rc.general_selection, rc.chargeable, r.state, r.state_reason,
           r.beds, coalesce(bd.oos, 0), coalesce(bd.occupied, 0), coalesce(bd.reserved, 0),
           greatest(r.beds - coalesce(bd.oos, 0) - coalesce(bd.occupied, 0) - coalesce(bd.reserved, 0), 0),
           CASE WHEN h.state <> 'ACTIVE' OR h.ended_on IS NOT NULL THEN 'INACTIVE'
                WHEN r.state <> 'AVAILABLE' THEN r.state
                WHEN NOT rc.general_selection AND coalesce(bd.occupied, 0) + coalesce(bd.reserved, 0) = 0 THEN 'SPECIAL_RESERVED'
                WHEN r.beds - coalesce(bd.oos, 0) - coalesce(bd.occupied, 0) - coalesce(bd.reserved, 0) <= 0 THEN 'FULL'
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

-- ── 4 · the lapse: a hold lapsed once, whoever reaches it first (the clock, or a student's reservation) ──
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
        -- V705: two transactions may reach the same expired hold; the second finds it lapsed (or paid) and passes on
        UPDATE hostel.allocation SET lapsed_at = now(), state = 'LAPSED'
         WHERE id = a.id AND state = 'HELD' AND confirmed_at IS NULL AND lapsed_at IS NULL AND ended_at IS NULL;
        CONTINUE WHEN NOT FOUND;
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

-- ── 5 · the student's reservation: an expired hold is lapsed first; Lagos days ──
CREATE OR REPLACE FUNCTION hostel.reserve_room(p_student uuid, p_session text, p_room uuid)
 RETURNS uuid
 LANGUAGE plpgsql AS $fn$
DECLARE s hostel.session_setting; r hostel.room; rc hostel.room_category; ap hostel.application; b hostel.bed; v uuid; a record; e record;
        v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date;
BEGIN
    SELECT * INTO s FROM hostel.session_setting WHERE session = p_session;
    IF s.session IS NULL OR s.state IN ('DRAFT') THEN
        RAISE EXCEPTION 'HOSTEL_APPLICATION_CLOSED: hostel applications for % are not open', p_session USING ERRCODE = '23514';
    END IF;
    IF s.state = 'CLOSED' OR s.drawn_at IS NOT NULL THEN
        RAISE EXCEPTION 'HOSTEL_APPLICATION_CLOSED: hostel applications for % are currently closed', p_session USING ERRCODE = '23514';
    END IF;
    IF s.applications_open IS NOT NULL AND s.applications_open > v_today THEN
        RAISE EXCEPTION 'HOSTEL_APPLICATION_CLOSED: hostel applications for % open on %', p_session, to_char(s.applications_open, 'DD Month YYYY') USING ERRCODE = '23514';
    END IF;
    IF s.applications_close IS NOT NULL AND s.applications_close < v_today THEN
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
    -- V705: a reservation past its 48 hours is lapsed now, not at the clock's next turn: its bed is free this instant
    PERFORM hostel.lapse_holds(p_session);
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
     WHERE bd.room_id = r.id AND bd.state = 'AVAILABLE' AND bd.number <= r.beds
       AND NOT EXISTS (SELECT 1 FROM hostel.allocation x WHERE x.bed_id = bd.id AND x.session = p_session AND x.lapsed_at IS NULL AND x.ended_at IS NULL)
     ORDER BY bd.number
     FOR UPDATE SKIP LOCKED LIMIT 1;
    IF b.id IS NULL THEN
        RAISE EXCEPTION 'HOSTEL_ROOM_FULL: This room is no longer available. Please select another room.' USING ERRCODE = '23514';
    END IF;
    v := hostel.hold(ap.id, b.id, 'SELF', NULL, 'Reserved by the student');
    -- an alert the student set for a room has done its work
    UPDATE hostel.room_watch SET ended_at = now(), ended_reason = 'A room was reserved' WHERE student_id = p_student AND session = p_session AND told_at IS NULL AND ended_at IS NULL;
    SELECT al.state, al.held_until, al.fee_amount, al.reference_no, h.name AS hall INTO a
      FROM hostel.allocation al JOIN hostel.hall h ON h.code = r.hall_code WHERE al.id = v;
    PERFORM hostel.tell_student(p_student, 'Your hostel room is reserved',
        'Reservation ' || a.reference_no || ': ' || a.hall || CASE WHEN r.block = 'MAIN' THEN '' ELSE ', Block ' || r.block END || ', Room ' || r.room_no || ', ' || b.label || '. '
        || CASE WHEN a.state = 'HELD' THEN 'Pay the hostel fee of NGN ' || a.fee_amount::text || ' by ' || to_char(a.held_until AT TIME ZONE 'Africa/Lagos', 'FMDay DD FMMonth YYYY HH24:MI') || ' (' || coalesce(s.hold_hours, 48) || ' hours); unpaid, the reservation expires and the bed is released.'
                ELSE 'No hostel charge applies; accept the allocation on the portal.' END,
        'MOAUM: room ' || r.room_no || ' reserved. Pay by ' || to_char(a.held_until AT TIME ZONE 'Africa/Lagos', 'DD Mon HH24:MI') || '.');
    RETURN v;
END $fn$;
COMMENT ON FUNCTION hostel.reserve_room(uuid, text, uuid) IS 'An eligible student reserves a bed in a general room of a first-come session (V290): window (Lagos days, V705), eligibility and category enforced here, expired holds lapsed first (V705), the bed locked, held for the session''s hold hours.';

-- ── 6 · the fee reference lasts no longer than the hold ─────────────────
CREATE OR REPLACE FUNCTION hostel.new_fee_reference(p_application uuid)
 RETURNS text
 LANGUAGE plpgsql AS $fn$
DECLARE ap hostel.application; al hostel.allocation; v_ref text;
BEGIN
    SELECT * INTO ap FROM hostel.application WHERE id = p_application;
    IF NOT FOUND THEN RAISE EXCEPTION 'no application %', p_application USING ERRCODE = 'no_data_found'; END IF;
    SELECT * INTO al FROM hostel.allocation WHERE application_id = ap.id AND lapsed_at IS NULL AND ended_at IS NULL ORDER BY allocated_at DESC LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'no bed is held against this application' USING ERRCODE = '23514',
        HINT = 'The accommodation fee is paid against an allocated bed.'; END IF;
    IF al.fee_status = 'PAID' THEN RAISE EXCEPTION 'this allocation is already paid and confirmed' USING ERRCODE = '23505'; END IF;
    IF al.fee_status = 'NO_CHARGE' OR coalesce(al.fee_amount, 0) = 0 THEN RAISE EXCEPTION 'HOSTEL_NO_CHARGE: no hostel charge applies to this allocation' USING ERRCODE = '23514'; END IF;
    IF al.state = 'HELD' AND al.held_until < now() THEN RAISE EXCEPTION 'HOSTEL_RESERVATION_EXPIRED: the reservation of this bed expired at %', to_char(al.held_until AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') USING ERRCODE = '23514',
        HINT = 'The bed is released; reserve again if applications are open and a bed is free.'; END IF;
    IF al.reference IS NOT NULL AND EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = al.reference AND expires_at > now() AND confirmed_at IS NULL AND archived_at IS NULL) THEN
        RETURN al.reference;
    END IF;
    v_ref := finance.new_purpose_reference(ap.student_id, ap.session, al.fee_amount, 'Hostel accommodation ' || ap.session || ' ' || al.id::text);
    -- V705: a held bed is paid for within its hold: the reference expires with it, so no gateway takes the money after the deadline
    IF al.state = 'HELD' AND al.held_until IS NOT NULL THEN
        UPDATE finance.payment_reference SET expires_at = least(expires_at, al.held_until) WHERE reference = v_ref;
    END IF;
    UPDATE hostel.allocation SET reference = v_ref WHERE id = al.id;
    RETURN v_ref;
END $fn$;
COMMENT ON FUNCTION hostel.new_fee_reference(uuid) IS 'The hostel fee reference of an allocation (V030, V290); a held bed''s reference expires when its hold does (V705).';

-- ── 7 · the payment confirms the stay, or is told; it is never refused ──
CREATE OR REPLACE FUNCTION hostel.tell_desk(p_subject text, p_body text)
 RETURNS void
 LANGUAGE plpgsql AS $fn$
DECLARE r record; v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date;
BEGIN
    -- V705: the Dean of Student Affairs runs the hostels (V290) and is told what the desk is told
    FOR r IN
        SELECT DISTINCT pe.id, pe.email FROM iam.office_assignment a JOIN iam.person pe ON pe.id = a.person_id
         WHERE a.office_code IN ('dsa', 'housing', 'services') AND a.valid_from <= v_today AND (a.valid_to IS NULL OR a.valid_to >= v_today) AND pe.email IS NOT NULL
    LOOP
        PERFORM platform.queue_notice('EMAIL', r.email, p_subject, p_body, 'person', r.id);
    END LOOP;
END $fn$;

CREATE OR REPLACE FUNCTION hostel.tell_bursary(p_subject text, p_body text)
 RETURNS void
 LANGUAGE plpgsql AS $fn$
DECLARE r record; v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date;
BEGIN
    FOR r IN
        SELECT DISTINCT pe.id, pe.email FROM iam.office_assignment a JOIN iam.person pe ON pe.id = a.person_id
         WHERE a.office_code = 'bursar' AND a.valid_from <= v_today AND (a.valid_to IS NULL OR a.valid_to >= v_today) AND pe.email IS NOT NULL
    LOOP
        PERFORM platform.queue_notice('EMAIL', r.email, p_subject, p_body, 'person', r.id);
    END LOOP;
END $fn$;
COMMENT ON FUNCTION hostel.tell_bursary(text, text) IS 'Emails the Bursary''s staff in office today a hostel matter that is theirs: a hostel payment that arrived after its reservation expired (V705).';

CREATE OR REPLACE FUNCTION hostel.confirm_by_reference(p_reference text)
 RETURNS void
 LANGUAGE plpgsql AS $fn$
DECLARE al hostel.allocation; c hostel.damage_charge; v_purpose text; sn hostel.sanction; v_amount numeric; v_why text;
BEGIN
    -- a fine (V291): found by the sanction named in the purpose, whichever of its references was paid
    SELECT purpose, amount INTO v_purpose, v_amount FROM finance.payment_reference WHERE reference = p_reference;
    IF v_purpose LIKE 'Hostel accommodation fine %' THEN
        SELECT * INTO sn FROM hostel.sanction WHERE id::text = split_part(v_purpose, ' ', 5) FOR UPDATE;
        IF sn.id IS NOT NULL AND sn.settled_at IS NULL THEN
            UPDATE hostel.sanction SET settled_at = now(), payment_ref = p_reference WHERE id = sn.id;
            PERFORM hostel.log(NULL, sn.allocation_id, sn.student_id, NULL, NULL, NULL, 'FINE_PAID', NULL, sn.amount::text, sn.reference || ' · reference ' || p_reference);
            PERFORM hostel.tell_student(sn.student_id, 'Your hostel fine is paid', 'The Bursary has confirmed payment of fine ' || sn.reference || ' against ' || p_reference || '.', 'MOAUM: hostel fine ' || sn.reference || ' paid.');
        END IF;
        RETURN;
    END IF;
    SELECT * INTO c FROM hostel.damage_charge WHERE reference = p_reference AND settled_at IS NULL;
    IF c.id IS NOT NULL THEN
        UPDATE hostel.damage_charge SET settled_at = now() WHERE id = c.id;
        PERFORM hostel.log(NULL, c.allocation_id, (SELECT student_id FROM hostel.allocation WHERE id = c.allocation_id), NULL, NULL, NULL, 'CHARGE_SETTLED', NULL, c.charge::text, c.description);
        UPDATE hostel.clearance_item i SET state = 'CLEARED', decided_at = now(), remarks = 'Settled by payment ' || p_reference
          FROM hostel.clearance cl WHERE cl.id = i.clearance_id AND cl.allocation_id = c.allocation_id AND i.requirement = 'DAMAGE_CHARGES_SETTLED' AND i.state IN ('PENDING','NOT_CLEARED')
           AND NOT EXISTS (SELECT 1 FROM hostel.damage_charge x WHERE x.allocation_id = c.allocation_id AND x.id <> c.id AND x.settled_at IS NULL AND x.waived_at IS NULL);
        RETURN;
    END IF;
    SELECT * INTO al FROM hostel.allocation WHERE reference = p_reference AND coalesce(fee_status, 'PAYABLE') <> 'PAID' ORDER BY allocated_at DESC LIMIT 1 FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;
    IF al.lapsed_at IS NOT NULL THEN
        -- V705: money that arrives after the reservation expired is the University's to hold all the same — the payment is
        -- confirmed as money; the stay is confirmed only while its bed is still free and the student holds no other bed
        IF EXISTS (SELECT 1 FROM hostel.allocation o WHERE o.session = al.session AND o.room_id = al.room_id AND o.bed = al.bed
                      AND o.id <> al.id AND o.lapsed_at IS NULL AND o.ended_at IS NULL) THEN
            v_why := 'the bed went to another student after the reservation expired';
        ELSIF al.student_id IS NOT NULL AND EXISTS (SELECT 1 FROM hostel.allocation o WHERE o.student_id = al.student_id AND o.session = al.session
                      AND o.id <> al.id AND o.lapsed_at IS NULL AND o.ended_at IS NULL) THEN
            v_why := 'the student already holds another bed for ' || al.session;
        END IF;
        IF v_why IS NOT NULL THEN
            PERFORM hostel.log(al.application_id, al.id, al.student_id, NULL, al.room_id, al.bed_id, 'PAYMENT_AFTER_EXPIRY', al.state, 'NOT_APPLIED',
                               'Reference ' || p_reference || ' (NGN ' || coalesce(v_amount, al.fee_amount)::text || ') confirmed after the reservation expired: ' || v_why);
            IF al.student_id IS NOT NULL THEN
                PERFORM hostel.tell_student(al.student_id, 'Your hostel payment arrived after your reservation expired',
                    'Your payment against ' || p_reference || ' is received and recorded, but reservation ' || al.reference_no || ' had expired and ' || v_why || '. '
                    || 'The money is held for you: the Bursary refunds it, or the Dean of Student Affairs applies it to a bed that is free. Nothing more is owed against this reference.',
                    'MOAUM: hostel payment ' || p_reference || ' received after reservation ' || al.reference_no || ' expired. It is held for refund or another bed.');
            END IF;
            PERFORM hostel.tell_desk('A hostel payment arrived after its reservation expired',
                'Reference ' || p_reference || ' for reservation ' || al.reference_no || ' was confirmed after the reservation expired, and ' || v_why || '. Allocate the student a bed that is free, or ask the Bursary to refund.');
            PERFORM hostel.tell_bursary('A hostel payment arrived after its reservation expired',
                'Reference ' || p_reference || ' (NGN ' || coalesce(v_amount, al.fee_amount)::text || ') for hostel reservation ' || al.reference_no || ' is confirmed, but the reservation had expired and ' || v_why || '. Refund it, or hold it until the Dean of Student Affairs allocates a bed.');
            RETURN;
        END IF;
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
COMMENT ON FUNCTION hostel.confirm_by_reference(text) IS 'A confirmed hostel payment settles its fine, damage charge or bed (V030, V290, V291); after an expired reservation whose bed is gone it is recorded and told, never refused (V705).';

-- ── 8 · the workbook: the old portal's hostels by their ID, rooms without "Room " ──
CREATE OR REPLACE FUNCTION hostel.import_rows(p_rows jsonb, p_commit boolean)
 RETURNS TABLE(row_no integer, hall_code text, hall_name text, block text, room_no text, beds integer, category text, room_type text, sex text, floor integer, outcome text, message text)
 LANGUAGE plpgsql AS $fn$
#variable_conflict use_column
DECLARE r record; h record; v_code text; v_name text; v_block text; v_room text; v_beds int; v_cat text; v_type text; v_sex text; v_floor int; v_kind text;
        v_ref text; v_loc text; v_hsex text; v_base text; v_display text; v_held int;
        v_outcome text; v_msg text; seen text[] := ARRAY[]::text[]; k text; ex hostel.room; v_n int := 0; v_new int := 0; v_upd int := 0;
        refs jsonb := '{}'::jsonb;    -- the old portal's hostel ID → {code, name, error}
        used jsonb := '{}'::jsonb;    -- a code this file gives → the ID it is given to
        shared jsonb := '{}'::jsonb;  -- a hostel name → how many IDs carry it in the file
BEGIN
    -- 1 · the hostels the file names by the old portal's ID: a name two IDs share is told apart by its location; the
    --     code is the name's initials, with the ID when the name is shared or the initials are another hostel's
    SELECT coalesce(jsonb_object_agg(n, c), '{}'::jsonb) INTO shared
      FROM (SELECT lower(nm) AS n, count(DISTINCT rf) AS c
              FROM (SELECT nullif(btrim(coalesce(j->>'hall_name', j->>'hall', '')), '') AS nm, upper(regexp_replace(coalesce(j->>'hall_ref', ''), '[^A-Za-z0-9]', '', 'g')) AS rf
                      FROM jsonb_array_elements(p_rows) j) x
             WHERE nm IS NOT NULL AND rf <> '' GROUP BY lower(nm)) q;
    FOR h IN
        SELECT DISTINCT ON (rf) rf, nm, loc
          FROM (SELECT upper(regexp_replace(coalesce(j->>'hall_ref', ''), '[^A-Za-z0-9]', '', 'g')) AS rf,
                       nullif(btrim(coalesce(j->>'hall_name', j->>'hall', '')), '') AS nm,
                       nullif(regexp_replace(btrim(coalesce(j->>'location', '')), '\s*\(\s*', ' (', 'g'), '') AS loc,
                       nullif(btrim(coalesce(j->>'hall_code', '')), '') AS hc, ord
                  FROM jsonb_array_elements(p_rows) WITH ORDINALITY AS t(j, ord)) x
         WHERE rf <> '' AND hc IS NULL AND nm IS NOT NULL
         ORDER BY rf, ord
    LOOP
        v_display := CASE WHEN coalesce((shared->>lower(h.nm))::int, 1) > 1 THEN h.nm || ', ' || coalesce(h.loc, 'ID ' || h.rf) ELSE h.nm END;
        SELECT code INTO v_code FROM hostel.hall WHERE legacy_ref = h.rf;
        IF v_code IS NULL THEN
            v_base := upper(regexp_replace((SELECT string_agg(left(w, 1), '') FROM regexp_split_to_table(h.nm, '\s+') w WHERE w <> ''), '[^A-Za-z0-9]', '', 'g'));
            IF length(v_base) < 2 THEN v_base := upper(regexp_replace(h.nm, '[^A-Za-z0-9]', '', 'g')); END IF;
            v_code := left(v_base, 8);
            IF coalesce((shared->>lower(h.nm))::int, 1) > 1
               OR used ? v_code
               OR EXISTS (SELECT 1 FROM hostel.hall x WHERE x.code = v_code AND (x.legacy_ref IS NOT NULL OR lower(x.name) <> lower(v_display))) THEN
                v_code := left(v_base, greatest(8 - length(left(h.rf, 6)), 2)) || left(h.rf, 6);
            END IF;
        END IF;
        IF used ? v_code OR EXISTS (SELECT 1 FROM hostel.hall x WHERE x.code = v_code AND x.legacy_ref IS DISTINCT FROM h.rf AND (x.legacy_ref IS NOT NULL OR lower(x.name) <> lower(v_display))) THEN
            refs := refs || jsonb_build_object(h.rf, jsonb_build_object('code', v_code, 'name', v_display, 'error',
                    'The hostel code ' || v_code || ' is another hostel''s; add a Hostel code column for ID ' || h.rf));
        ELSE
            refs := refs || jsonb_build_object(h.rf, jsonb_build_object('code', v_code, 'name', v_display, 'location', h.loc));
            used := used || jsonb_build_object(v_code, h.rf);
        END IF;
    END LOOP;

    -- 2 · the rooms, row by row
    FOR r IN SELECT ord, j FROM jsonb_array_elements(p_rows) WITH ORDINALITY AS t(j, ord) LOOP
        v_n := v_n + 1;
        v_outcome := NULL; v_msg := NULL;
        v_ref := upper(regexp_replace(coalesce(r.j->>'hall_ref', ''), '[^A-Za-z0-9]', '', 'g'));
        v_loc := nullif(regexp_replace(btrim(coalesce(r.j->>'location', '')), '\s*\(\s*', ' (', 'g'), '');
        v_name := nullif(btrim(coalesce(r.j->>'hall_name', r.j->>'hall', '')), '');
        v_code := upper(regexp_replace(coalesce(nullif(btrim(coalesce(r.j->>'hall_code', '')), ''), ''), '[^A-Za-z0-9]', '', 'g'));
        IF v_code = '' AND v_ref <> '' AND refs ? v_ref THEN
            v_code := refs->v_ref->>'code'; v_name := refs->v_ref->>'name';
            IF refs->v_ref ? 'error' THEN v_outcome := 'ERROR'; v_msg := refs->v_ref->>'error'; END IF;
        ELSIF v_code = '' AND v_name IS NOT NULL THEN
            -- a code from the name: the initials of its words, then the letters, to eight characters
            v_code := upper(left(regexp_replace((SELECT string_agg(left(w, 1), '') FROM regexp_split_to_table(v_name, '\s+') w WHERE w <> ''), '[^A-Za-z0-9]', '', 'g'), 8));
            IF length(v_code) < 2 THEN v_code := upper(left(regexp_replace(v_name, '[^A-Za-z0-9]', '', 'g'), 8)); END IF;
        END IF;
        v_block := upper(nullif(btrim(coalesce(r.j->>'block', '')), ''));
        -- "Room A1" is room A1: every screen says "Room" before the number
        v_room := nullif(regexp_replace(btrim(coalesce(r.j->>'room_no', r.j->>'room', '')), '^[Rr][Oo][Oo][Mm]\s+', ''), '');
        v_beds := nullif(regexp_replace(coalesce(r.j->>'beds', r.j->>'capacity', ''), '[^0-9]', '', 'g'), '')::int;
        v_cat := upper(regexp_replace(nullif(btrim(coalesce(r.j->>'category', '')), ''), '[^A-Za-z0-9]+', '_', 'g'));
        v_cat := CASE WHEN v_cat IS NULL OR v_cat = '' THEN 'GENERAL' WHEN v_cat IN ('SU', 'STUDENT_UNION', 'STUDENTS_UNION', 'UNION') THEN 'STUDENT_UNION'
                      WHEN v_cat IN ('SEC', 'SECURITY') THEN 'SECURITY' WHEN v_cat IN ('SPECIAL', 'RESERVED', 'SPECIAL_RESERVED', 'SPECIAL_RESERVED_') THEN 'SPECIAL' ELSE v_cat END;
        v_type := upper(regexp_replace(nullif(btrim(coalesce(r.j->>'room_type', '')), ''), '[^A-Za-z0-9]+', '_', 'g'));
        v_sex := upper(left(nullif(btrim(coalesce(r.j->>'sex', r.j->>'gender', '')), ''), 1));
        v_sex := CASE WHEN v_sex IN ('F', 'M') THEN v_sex ELSE NULL END;
        v_hsex := upper(left(nullif(btrim(coalesce(r.j->>'hall_sex', '')), ''), 1));
        v_hsex := CASE WHEN v_hsex IN ('F', 'M') THEN v_hsex ELSE NULL END;
        v_floor := nullif(regexp_replace(coalesce(r.j->>'floor', ''), '[^0-9]', '', 'g'), '')::int;
        v_kind := upper(nullif(btrim(coalesce(r.j->>'hall_kind', r.j->>'kind', '')), ''));
        IF v_outcome IS NOT NULL THEN NULL;
        ELSIF v_name IS NULL AND (v_code IS NULL OR v_code = '') THEN v_outcome := 'ERROR'; v_msg := 'No hostel named';
        ELSIF v_code !~ '^[A-Z0-9]{2,8}$' THEN v_outcome := 'ERROR'; v_msg := 'The hostel code must be 2 to 8 letters or digits (' || v_code || ')';
        ELSIF v_room IS NULL THEN v_outcome := 'ERROR'; v_msg := 'No room number';
        ELSIF v_beds IS NULL OR v_beds < 1 OR v_beds > 64 THEN v_outcome := 'ERROR'; v_msg := 'The capacity must be 1 to 64 beds';
        ELSIF NOT EXISTS (SELECT 1 FROM hostel.room_category c WHERE c.code = v_cat) THEN v_outcome := 'ERROR'; v_msg := v_cat || ' is not a room category';
        ELSIF v_type IS NOT NULL AND NOT EXISTS (SELECT 1 FROM hostel.room_type t WHERE t.code = v_type) THEN v_outcome := 'ERROR'; v_msg := v_type || ' is not a room type';
        END IF;
        v_block := coalesce(v_block, 'MAIN');
        k := v_code || '|' || v_block || '|' || upper(coalesce(v_room, ''));
        IF v_outcome IS NULL AND k = ANY (seen) THEN v_outcome := 'DUPLICATE'; v_msg := 'The same hostel, block and room appears earlier in the file'; END IF;
        seen := seen || k;
        ex := NULL;
        IF v_outcome IS NULL THEN
            -- the room on the record, whether it was saved as "Room A1" or "A1"
            SELECT * INTO ex FROM hostel.room x WHERE x.hall_code = v_code AND x.block = v_block
               AND upper(regexp_replace(x.room_no, '^[Rr][Oo][Oo][Mm]\s+', '')) = upper(v_room)
             ORDER BY (upper(x.room_no) = upper(v_room)) DESC LIMIT 1;
            IF ex.id IS NULL THEN v_outcome := 'NEW'; v_msg := 'Will be created' || CASE WHEN NOT EXISTS (SELECT 1 FROM hostel.hall WHERE code = v_code) THEN ', with the hostel ' || v_code ELSE '' END;
            ELSIF ex.beds = v_beds AND ex.category = v_cat AND (v_type IS NULL OR ex.room_type = v_type) AND (v_sex IS NULL OR ex.sex = v_sex) AND (v_floor IS NULL OR ex.floor = v_floor) THEN v_outcome := 'EXISTING'; v_msg := 'Already on the record as stated';
            ELSE
                SELECT max(b.number) INTO v_held FROM hostel.allocation a JOIN hostel.bed b ON b.id = a.bed_id
                 WHERE a.room_id = ex.id AND a.lapsed_at IS NULL AND a.ended_at IS NULL AND NOT (a.state = 'HELD' AND a.held_until < now());
                IF v_beds < coalesce(v_held, 0) THEN
                    v_outcome := 'ERROR'; v_msg := 'Bed ' || v_held || ' is held or occupied: the capacity cannot go down to ' || v_beds || ' until its occupant moves';
                ELSE
                    v_outcome := 'UPDATED'; v_msg := 'Capacity ' || ex.beds || ' → ' || v_beds || CASE WHEN ex.category <> v_cat THEN ', category ' || ex.category || ' → ' || v_cat ELSE '' END;
                END IF;
            END IF;
        END IF;
        IF p_commit AND v_outcome IN ('NEW', 'UPDATED') THEN
            INSERT INTO hostel.hall (code, name, sex, kind, location, legacy_ref)
            VALUES (v_code, coalesce(v_name, v_code), coalesce(v_hsex, v_sex), coalesce(nullif(v_kind, ''), 'UNDERGRADUATE'),
                    CASE WHEN v_ref <> '' THEN coalesce(refs->v_ref->>'location', v_loc) ELSE v_loc END, nullif(v_ref, ''))
            ON CONFLICT (code) DO UPDATE SET name = coalesce(EXCLUDED.name, hostel.hall.name), sex = coalesce(hostel.hall.sex, EXCLUDED.sex),
                location = coalesce(hostel.hall.location, EXCLUDED.location), legacy_ref = coalesce(hostel.hall.legacy_ref, EXCLUDED.legacy_ref);
            INSERT INTO hostel.block (hall_code, code, name, floors) VALUES (v_code, v_block, 'Block ' || v_block, greatest(coalesce(v_floor, 0) + 1, 1))
            ON CONFLICT (hall_code, code) DO UPDATE SET floors = greatest(hostel.block.floors, EXCLUDED.floors);
            IF ex.id IS NULL THEN
                INSERT INTO hostel.room (hall_code, block, room_no, beds, floor, room_type, sex, category, block_id)
                VALUES (v_code, v_block, v_room, v_beds, coalesce(v_floor, 0), v_type, v_sex, v_cat, (SELECT id FROM hostel.block WHERE hall_code = v_code AND code = v_block));
                v_new := v_new + 1;
            ELSE
                UPDATE hostel.room SET beds = v_beds, floor = coalesce(v_floor, hostel.room.floor), room_type = coalesce(v_type, hostel.room.room_type),
                       sex = coalesce(v_sex, hostel.room.sex), category = v_cat WHERE id = ex.id;
                v_upd := v_upd + 1;
            END IF;
        END IF;
        row_no := r.ord::int; hall_code := v_code; hall_name := v_name; block := v_block; room_no := v_room; beds := v_beds; category := v_cat; room_type := v_type;
        sex := coalesce(v_sex, v_hsex); floor := v_floor; outcome := v_outcome; message := v_msg;
        RETURN NEXT;
    END LOOP;
    IF p_commit AND (v_new + v_upd) > 0 THEN
        PERFORM hostel.log(NULL, NULL, NULL, NULL, NULL, NULL, 'ROOMS_IMPORTED', NULL, v_new || ' new · ' || v_upd || ' updated', v_n || ' rows in the workbook');
    END IF;
END $fn$;
COMMENT ON FUNCTION hostel.import_rows(jsonb, boolean) IS 'The University''s hostel workbook, row by row (V290): NEW, EXISTING, UPDATED, DUPLICATE or ERROR; committed only when asked, idempotent on hostel + block + room number; a hostel named by the old portal''s ID is found by it (V705), its gender and location taken; "Room A1" is room A1; a capacity is never cut below a held bed.';

-- ── 9 · "notify me when a suitable room becomes available" ──────────────
CREATE TABLE hostel.room_watch (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id   uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    session      text NOT NULL REFERENCES policy.academic_session(name),
    hall_code    text NULL REFERENCES hostel.hall(code),
    room_type    text NULL REFERENCES hostel.room_type(code),
    created_at   timestamptz NOT NULL DEFAULT now(),
    told_at      timestamptz NULL,
    told_room_id uuid NULL REFERENCES hostel.room(id) ON DELETE SET NULL,
    ended_at     timestamptz NULL,
    ended_reason text NULL,
    CONSTRAINT ck_rw_ended CHECK (ended_at IS NULL OR (ended_reason IS NOT NULL AND btrim(ended_reason) <> ''))
);
COMMENT ON TABLE hostel.room_watch IS
  'A student''s request to be told when a room they could reserve has a free bed (V705): the hostel, the room type, or any; told once by the clock, then done. Not a reservation.';
CREATE UNIQUE INDEX uq_room_watch_live ON hostel.room_watch (student_id, session) WHERE told_at IS NULL AND ended_at IS NULL;
CREATE INDEX ix_room_watch_live ON hostel.room_watch (session) WHERE told_at IS NULL AND ended_at IS NULL;
SELECT audit.attach('hostel.room_watch');
GRANT SELECT, INSERT, UPDATE ON hostel.room_watch TO app_student;

CREATE OR REPLACE FUNCTION hostel.watch_rooms(p_student uuid, p_session text, p_hall text, p_room_type text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE s hostel.session_setting; e record; st people.student; hl hostel.hall; v uuid; v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date;
        v_hall text := nullif(upper(btrim(coalesce(p_hall, ''))), ''); v_type text := nullif(upper(btrim(coalesce(p_room_type, ''))), '');
BEGIN
    SELECT * INTO s FROM hostel.session_setting WHERE session = p_session;
    IF s.session IS NULL OR s.state <> 'OPEN' OR s.drawn_at IS NOT NULL OR (s.applications_close IS NOT NULL AND s.applications_close < v_today) THEN
        RAISE EXCEPTION 'HOSTEL_APPLICATION_CLOSED: hostel applications for % are not open', p_session USING ERRCODE = '23514';
    END IF;
    SELECT * INTO e FROM hostel.eligibility(p_student, p_session);
    IF NOT e.ok THEN RAISE EXCEPTION 'HOSTEL_NOT_ELIGIBLE: %', e.why USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM hostel.allocation x WHERE x.student_id = p_student AND x.session = p_session AND x.lapsed_at IS NULL AND x.ended_at IS NULL) THEN
        RAISE EXCEPTION 'HOSTEL_ALREADY_HELD: a bed is already held or allocated to you for %', p_session USING ERRCODE = '23514';
    END IF;
    SELECT * INTO st FROM people.student WHERE id = p_student;
    IF v_hall IS NOT NULL THEN
        SELECT * INTO hl FROM hostel.hall WHERE code = v_hall AND ended_on IS NULL AND state = 'ACTIVE';
        IF hl.code IS NULL THEN RAISE EXCEPTION 'HOSTEL_ALERT: no open hostel %', v_hall USING ERRCODE = '23514'; END IF;
        IF hl.sex IS NOT NULL AND st.sex IS NOT NULL AND hl.sex <> st.sex THEN RAISE EXCEPTION 'HOSTEL_ALERT: % is not a hostel for you', hl.name USING ERRCODE = '23514'; END IF;
    END IF;
    IF v_type IS NOT NULL AND NOT EXISTS (SELECT 1 FROM hostel.room_type WHERE code = v_type AND active) THEN
        RAISE EXCEPTION 'HOSTEL_ALERT: % is not a room type', v_type USING ERRCODE = '23514';
    END IF;
    UPDATE hostel.room_watch SET ended_at = now(), ended_reason = 'Replaced by a new alert' WHERE student_id = p_student AND session = p_session AND told_at IS NULL AND ended_at IS NULL;
    INSERT INTO hostel.room_watch (student_id, session, hall_code, room_type) VALUES (p_student, p_session, v_hall, v_type) RETURNING id INTO v;
    PERFORM hostel.log(NULL, NULL, p_student, v_hall, NULL, NULL, 'ROOM_ALERT_SET', NULL, coalesce(hl.name, 'any hostel') || ' · ' || coalesce(v_type, 'any room type'), NULL);
    RETURN v;
END $fn$;
COMMENT ON FUNCTION hostel.watch_rooms(uuid, text, text, text) IS 'An eligible student with no bed asks to be told when a room they could reserve has a free bed (V705): one alert a session, replaced by a new one.';

CREATE OR REPLACE FUNCTION hostel.unwatch_rooms(p_student uuid, p_session text)
RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
    UPDATE hostel.room_watch SET ended_at = now(), ended_reason = 'Cancelled by the student' WHERE student_id = p_student AND session = p_session AND told_at IS NULL AND ended_at IS NULL;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n > 0 THEN PERFORM hostel.log(NULL, NULL, p_student, NULL, NULL, NULL, 'ROOM_ALERT_CANCELLED', NULL, NULL, NULL); END IF;
    RETURN n;
END $fn$;

CREATE OR REPLACE FUNCTION hostel.tell_watchers()
RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE aw record; e record; n int := 0; v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date;
BEGIN
    -- an alert whose student now holds a bed, or whose window has closed, is done without a word
    UPDATE hostel.room_watch w SET ended_at = now(), ended_reason = 'A bed is held or allocated'
     WHERE w.told_at IS NULL AND w.ended_at IS NULL
       AND EXISTS (SELECT 1 FROM hostel.allocation x WHERE x.student_id = w.student_id AND x.session = w.session AND x.lapsed_at IS NULL AND x.ended_at IS NULL);
    UPDATE hostel.room_watch w SET ended_at = now(), ended_reason = 'Hostel applications closed'
      FROM hostel.session_setting s
     WHERE s.session = w.session AND w.told_at IS NULL AND w.ended_at IS NULL
       AND (s.state = 'CLOSED' OR s.drawn_at IS NOT NULL OR (s.applications_close IS NOT NULL AND s.applications_close < v_today));
    -- the rooms a student could reserve (hostel.room_choices' rule), read once a session, matched to each alert's hostel and room type
    FOR aw IN
        WITH live AS (SELECT * FROM hostel.room_watch WHERE told_at IS NULL AND ended_at IS NULL),
        open_rooms AS (
            SELECT q.session, rb.* FROM (SELECT DISTINCT session FROM live) q CROSS JOIN LATERAL hostel.room_board(q.session) rb
              JOIN hostel.hall h ON h.code = rb.hall_code
             WHERE rb.general_selection AND rb.room_state = 'AVAILABLE' AND rb.available > 0 AND h.state = 'ACTIVE' AND h.ended_on IS NULL)
        SELECT DISTINCT ON (lw.id) lw.id, lw.student_id, lw.session, o.room_id, o.hall_code, o.hall_name, o.block, o.room_no, o.available
          FROM live lw
          JOIN people.student st ON st.id = lw.student_id
          LEFT JOIN hostel.session_setting s ON s.session = lw.session
          JOIN open_rooms o ON o.session = lw.session
                           AND (lw.hall_code IS NULL OR o.hall_code = lw.hall_code) AND (lw.room_type IS NULL OR o.room_type = lw.room_type)
                           AND (o.hall_sex IS NULL OR st.sex IS NULL OR o.hall_sex = st.sex)
                           AND (s.eligible_kinds IS NULL OR array_length(s.eligible_kinds, 1) IS NULL OR o.hall_kind = ANY (s.eligible_kinds))
         ORDER BY lw.id, o.available DESC, o.hall_name, o.room_no
    LOOP
        SELECT * INTO e FROM hostel.eligibility(aw.student_id, aw.session);
        CONTINUE WHEN NOT e.ok;   -- told when they are eligible again, not before
        UPDATE hostel.room_watch SET told_at = now(), told_room_id = aw.room_id WHERE id = aw.id AND told_at IS NULL AND ended_at IS NULL;
        CONTINUE WHEN NOT FOUND;
        PERFORM hostel.tell_student(aw.student_id, 'A hostel room is available',
            aw.hall_name || CASE WHEN aw.block = 'MAIN' THEN '' ELSE ', Block ' || aw.block END || ', Room ' || aw.room_no || ' has ' || aw.available || ' free bed' || CASE WHEN aw.available = 1 THEN '' ELSE 's' END || ' for ' || aw.session || '. '
            || 'This alert is not a reservation: reserve it under Hostel on the portal before someone else does. Set a new alert there if it is gone.',
            'MOAUM: hostel room ' || aw.room_no || ' (' || aw.hall_name || ') has a free bed. Reserve it on the portal.');
        PERFORM hostel.log(NULL, NULL, aw.student_id, aw.hall_code, aw.room_id, NULL, 'ROOM_ALERT_SENT', NULL, aw.room_no, NULL);
        n := n + 1;
    END LOOP;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION hostel.tell_watchers() IS 'Run by the hostel clock (V705): each live room alert whose student is eligible and holds no bed is told once of a room with a free bed it could reserve; alerts of a closed window or a student with a bed end.';

-- ── 10 · the Dean's room figures ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION hostel.room_kpis(p_session text)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
    WITH rb AS (SELECT * FROM hostel.room_board(p_session) WHERE status <> 'INACTIVE')
    SELECT jsonb_build_object(
        'rooms', (SELECT count(*) FROM rb),
        'capacity', (SELECT coalesce(sum(capacity), 0) FROM rb),
        'full', (SELECT count(*) FROM rb WHERE status = 'FULL'),
        'maintenance', (SELECT count(*) FROM rb WHERE room_state IN ('MAINTENANCE', 'OUT_OF_SERVICE', 'CLOSED')),
        'pending_reservations', (SELECT count(*) FROM hostel.allocation a WHERE a.session = p_session AND a.state = 'HELD' AND a.lapsed_at IS NULL AND a.ended_at IS NULL AND a.held_until >= now()),
        'pending_applications', (SELECT count(*) FROM hostel.application ap WHERE ap.session = p_session AND ap.state = 'APPLIED'),
        'room_alerts', (SELECT count(*) FROM hostel.room_watch w WHERE w.session = p_session AND w.told_at IS NULL AND w.ended_at IS NULL),
        'byCategory', (SELECT coalesce(jsonb_agg(jsonb_build_object('category', c.code, 'label', c.label, 'general', c.general_selection, 'chargeable', c.chargeable,
                                                              'rooms', coalesce(g.rooms, 0), 'beds', coalesce(g.beds, 0), 'occupied', coalesce(g.occupied, 0),
                                                              'reserved', coalesce(g.reserved, 0), 'available', coalesce(g.available, 0))
                                            ORDER BY c.general_selection DESC, c.code), '[]'::jsonb)
                         FROM hostel.room_category c
                         LEFT JOIN (SELECT category, count(*) AS rooms, sum(capacity) AS beds, sum(occupied) AS occupied, sum(reserved) AS reserved, sum(available) AS available
                                      FROM rb GROUP BY category) g ON g.category = c.code
                        WHERE c.active OR coalesce(g.rooms, 0) > 0))
$fn$;
COMMENT ON FUNCTION hostel.room_kpis(text) IS 'The Dean of Student Affairs'' room figures for a session (V705): rooms and capacity of open hostels, full and maintenance rooms, rooms by category, reservations awaiting payment, applications waiting and room alerts.';

-- ── 11 · Lagos days in every hostel rule (V539's lesson): current_date was the UTC day ──
DO $$
DECLARE r record; n int := 0;
BEGIN
    FOR r IN
        SELECT p.oid, p.proname, pg_get_functiondef(p.oid) AS def
          FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
         WHERE ns.nspname = 'hostel' AND p.prokind = 'f' AND pg_get_functiondef(p.oid) ~* '\mcurrent_date\M'
    LOOP
        EXECUTE regexp_replace(r.def, '\mcurrent_date\M', '((now() AT TIME ZONE ''Africa/Lagos'')::date)', 'gi');
        n := n + 1;
        RAISE NOTICE 'V705: hostel.% reads the Lagos day', r.proname;
    END LOOP;
    RAISE NOTICE 'V705: % hostel function(s) re-created on Lagos days', n;
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
                WHERE ns.nspname = 'hostel' AND p.prokind = 'f' AND pg_get_functiondef(p.oid) ~* '\mcurrent_date\M') THEN
        RAISE EXCEPTION 'V705: a hostel function still reads current_date';
    END IF;
END $$;

COMMIT;
