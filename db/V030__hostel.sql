-- ═══════════════════════════════════════════════════════════════════════════
-- V030 — hostel and accommodation
--
--   Allocation is where discretion does the most damage, so it is designed
--   out (proto/part46 tHostel). Priority categories are filled first, by
--   rule and by name; what is left is drawn by ballot from a PUBLISHED SEED,
--   and the draw can be re-run from that seed by anybody holding it — the
--   order is a function of the seed and the applicants, and of nothing else.
--   An allocation is a hold, not a bed: it lapses unpaid after the hold
--   window, and the bed goes to the next name on the same draw, not back to
--   the office. The accommodation fee is a payment reference like every
--   other (V026), confirmed by the Bursary or the gateway; confirming it is
--   what makes the allocation a room.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE SCHEMA IF NOT EXISTS hostel;
GRANT USAGE ON SCHEMA hostel TO app_student, app_finance, app_auditor;

-- ── the inventory: a record, not a spreadsheet ──────────────────────────
CREATE TABLE hostel.hall (
    code      text PRIMARY KEY,
    name      text NOT NULL,
    sex       text NULL,                       -- F, M, or NULL for either
    ended_on  date NULL,
    CONSTRAINT ck_hall_sex CHECK (sex IS NULL OR sex IN ('F','M')),
    CONSTRAINT ck_hall_code CHECK (code ~ '^[A-Z0-9]{2,8}$')
);
SELECT audit.attach('hostel.hall');

CREATE TABLE hostel.room (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    hall_code      text NOT NULL REFERENCES hostel.hall(code),
    block          text NOT NULL,
    room_no        text NOT NULL,
    beds           int  NOT NULL,
    out_of_service boolean NOT NULL DEFAULT false,
    note           text NULL,
    UNIQUE (hall_code, block, room_no),
    CONSTRAINT ck_room_beds CHECK (beds BETWEEN 1 AND 12)
);
SELECT audit.attach('hostel.room');

-- ── the session: the fee, the hold window, the seed ─────────────────────
CREATE TABLE hostel.session_setting (
    session            text PRIMARY KEY REFERENCES policy.academic_session(name),
    fee                numeric(12,2) NOT NULL,
    hold_hours         int NOT NULL DEFAULT 72,
    applications_close date NULL,
    seed               text NULL,
    drawn_at           timestamptz NULL,
    drawn_by           uuid NULL,
    CONSTRAINT ck_hs_fee CHECK (fee >= 0),
    CONSTRAINT ck_hs_hold CHECK (hold_hours BETWEEN 1 AND 720),
    CONSTRAINT ck_hs_drawn CHECK ((drawn_at IS NULL) = (seed IS NULL))
);
SELECT audit.attach('hostel.session_setting');

-- ── applications, and the allocations drawn against them ────────────────
CREATE TABLE hostel.application (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id    uuid NOT NULL REFERENCES people.student(id),
    session       text NOT NULL REFERENCES policy.academic_session(name),
    hall_code     text NULL REFERENCES hostel.hall(code),
    category      text NOT NULL DEFAULT 'NONE',
    category_note text NULL,
    applied_at    timestamptz NOT NULL DEFAULT now(),
    state         text NOT NULL DEFAULT 'APPLIED',
    draw_position int  NULL,
    CONSTRAINT ck_ha_category CHECK (category IN ('NONE','DISABILITY','MEDICAL','FRESHER','FINALIST','SPORTS','OTHER')),
    CONSTRAINT ck_ha_state CHECK (state IN ('APPLIED','ALLOCATED','CONFIRMED','LAPSED','UNSUCCESSFUL','WITHDRAWN')),
    CONSTRAINT ck_ha_note CHECK (category = 'NONE' OR (category_note IS NOT NULL AND btrim(category_note) <> ''))
);
CREATE UNIQUE INDEX uq_ha_one_per_session ON hostel.application (student_id, session) WHERE state <> 'WITHDRAWN';
CREATE INDEX ix_ha_session ON hostel.application (session, state);
SELECT audit.attach('hostel.application');

CREATE TABLE hostel.allocation (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES hostel.application(id),
    session        text NOT NULL REFERENCES policy.academic_session(name),
    room_id        uuid NOT NULL REFERENCES hostel.room(id),
    bed            int  NOT NULL,
    basis          text NOT NULL,
    draw_position  int  NULL,
    allocated_at   timestamptz NOT NULL DEFAULT now(),
    held_until     timestamptz NOT NULL,
    reference      text NULL,
    confirmed_at   timestamptz NULL,
    lapsed_at      timestamptz NULL,
    ended_at       timestamptz NULL,
    ended_reason   text NULL,
    CONSTRAINT ck_hal_basis CHECK (basis IN ('PRIORITY','BALLOT','RESERVE')),
    CONSTRAINT ck_hal_ended CHECK (ended_at IS NULL OR ended_reason IS NOT NULL)
);
CREATE UNIQUE INDEX uq_hal_bed_live ON hostel.allocation (session, room_id, bed) WHERE lapsed_at IS NULL AND ended_at IS NULL;
CREATE INDEX ix_hal_application ON hostel.allocation (application_id);
SELECT audit.attach('hostel.allocation');

CREATE TABLE hostel.maintenance_request (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id    uuid NOT NULL REFERENCES hostel.room(id),
    raised_by  uuid NOT NULL REFERENCES people.student(id),
    issue      text NOT NULL,
    raised_at  timestamptz NOT NULL DEFAULT now(),
    state      text NOT NULL DEFAULT 'RAISED',
    note       text NULL,
    decided_at timestamptz NULL,
    CONSTRAINT ck_hm_state CHECK (state IN ('RAISED','ASSIGNED','FIXED','CLOSED')),
    CONSTRAINT ck_hm_issue CHECK (btrim(issue) <> '')
);
SELECT audit.attach('hostel.maintenance_request');

-- ── the student applies ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION hostel.apply(p_student uuid, p_session text, p_hall text, p_category text, p_note text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE s hostel.session_setting; v uuid := gen_random_uuid(); v_sex text; v_hall_sex text;
BEGIN
    SELECT * INTO s FROM hostel.session_setting WHERE session = p_session;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'accommodation for % is not open: no fee and no hold window are stated', p_session USING ERRCODE = '23514',
            HINT = 'Student Services states the accommodation fee and the hold window for the session before applications open.';
    END IF;
    IF s.drawn_at IS NOT NULL THEN
        RAISE EXCEPTION 'the draw for % has been run; applications are closed' USING ERRCODE = '23514',
            HINT = 'A late application joins no list. Ask Student Services whether a lapsed bed is available.';
    END IF;
    IF s.applications_close IS NOT NULL AND s.applications_close < current_date THEN
        RAISE EXCEPTION 'applications for % closed on %', p_session, s.applications_close USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM hostel.application WHERE student_id = p_student AND session = p_session AND state <> 'WITHDRAWN') THEN
        RAISE EXCEPTION 'an application for % already stands', p_session USING ERRCODE = '23505',
            HINT = 'One application per session; withdraw it before making another.';
    END IF;
    IF p_hall IS NOT NULL THEN
        SELECT sex INTO v_hall_sex FROM hostel.hall WHERE code = p_hall AND ended_on IS NULL;
        IF NOT FOUND THEN RAISE EXCEPTION 'no hall %', p_hall USING ERRCODE = '23503'; END IF;
        SELECT sex INTO v_sex FROM people.student WHERE id = p_student;
        IF v_hall_sex IS NOT NULL AND v_sex IS NOT NULL AND v_hall_sex <> v_sex THEN
            RAISE EXCEPTION 'hall % is not for this student', p_hall USING ERRCODE = '23514';
        END IF;
    END IF;
    INSERT INTO hostel.application (id, student_id, session, hall_code, category, category_note)
    VALUES (v, p_student, p_session, p_hall, coalesce(upper(p_category), 'NONE'), nullif(btrim(p_note), ''));
    RETURN v;
END $$;

-- ── the beds that may be drawn: rooms in service, in halls open to the student ──
CREATE OR REPLACE FUNCTION hostel.free_beds(p_session text)
RETURNS TABLE (room_id uuid, hall_code text, hall_sex text, block text, room_no text, bed int)
LANGUAGE sql STABLE AS $$
    SELECT r.id, r.hall_code, h.sex, r.block, r.room_no, b.n
      FROM hostel.room r
      JOIN hostel.hall h ON h.code = r.hall_code AND h.ended_on IS NULL
      CROSS JOIN LATERAL generate_series(1, r.beds) b(n)
     WHERE NOT r.out_of_service
       AND NOT EXISTS (SELECT 1 FROM hostel.allocation a
                        WHERE a.room_id = r.id AND a.bed = b.n AND a.lapsed_at IS NULL AND a.ended_at IS NULL AND a.session = p_session)
     ORDER BY h.code, r.block, r.room_no, b.n
$$;

-- ── the draw: priority by rule, the rest by the seed ────────────────────
CREATE OR REPLACE FUNCTION hostel.draw(p_session text, p_seed text)
RETURNS TABLE (allocated int, unsuccessful int, priority int)
LANGUAGE plpgsql AS $$
DECLARE s hostel.session_setting; a record; b record; pos int := 0; n_alloc int := 0; n_pri int := 0; n_un int := 0;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF p_seed IS NULL OR length(btrim(p_seed)) < 6 THEN
        RAISE EXCEPTION 'the draw runs from a published seed of at least six characters' USING ERRCODE = '23514',
            HINT = 'Publish the seed before the draw, not after; anybody holding it can reproduce the order.';
    END IF;
    SELECT * INTO s FROM hostel.session_setting WHERE session = p_session FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'accommodation for % is not open', p_session USING ERRCODE = '23514'; END IF;
    IF s.drawn_at IS NOT NULL THEN
        RAISE EXCEPTION 'the draw for % was run on % from seed %', p_session, s.drawn_at::date, s.seed USING ERRCODE = '23514',
            HINT = 'A draw is run once. Re-running it from the same seed reproduces the same order, which is what the record already holds.';
    END IF;
    UPDATE hostel.session_setting SET seed = btrim(p_seed), drawn_at = now(), drawn_by = v_actor WHERE session = p_session;
    -- the order: priority categories first, by the time they applied; then everybody else by the seed
    FOR a IN
        SELECT ap.id, ap.student_id, ap.hall_code, ap.category, st.sex,
               (ap.category <> 'NONE') AS is_priority
          FROM hostel.application ap JOIN people.student st ON st.id = ap.student_id
         WHERE ap.session = p_session AND ap.state = 'APPLIED'
         ORDER BY (ap.category <> 'NONE') DESC, CASE WHEN ap.category <> 'NONE' THEN ap.applied_at END,
                  md5(btrim(p_seed) || ap.student_id::text)
    LOOP
        pos := pos + 1;
        SELECT * INTO b FROM hostel.free_beds(p_session) fb
         WHERE (fb.hall_sex IS NULL OR a.sex IS NULL OR fb.hall_sex = a.sex)
         ORDER BY (fb.hall_code = a.hall_code) DESC, fb.hall_code, fb.block, fb.room_no, fb.bed
         LIMIT 1;
        IF FOUND THEN
            INSERT INTO hostel.allocation (application_id, session, room_id, bed, basis, draw_position, held_until)
            VALUES (a.id, p_session, b.room_id, b.bed, CASE WHEN a.is_priority THEN 'PRIORITY' ELSE 'BALLOT' END, pos, now() + make_interval(hours => s.hold_hours));
            UPDATE hostel.application SET state = 'ALLOCATED', draw_position = pos WHERE id = a.id;
            n_alloc := n_alloc + 1;
            IF a.is_priority THEN n_pri := n_pri + 1; END IF;
        ELSE
            -- a reserve, in the order the draw put them: a lapsed bed follows this order, not a telephone call
            UPDATE hostel.application SET state = 'UNSUCCESSFUL', draw_position = pos WHERE id = a.id;
            n_un := n_un + 1;
        END IF;
    END LOOP;
    RETURN QUERY SELECT n_alloc, n_un, n_pri;
END $$;

-- ── the hold runs whether anybody is watching: lapse, and move the bed on ──
CREATE OR REPLACE FUNCTION hostel.lapse_holds(p_session text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE s hostel.session_setting; a record; nxt record; n int := 0;
BEGIN
    SELECT * INTO s FROM hostel.session_setting WHERE session = p_session;
    IF NOT FOUND THEN RETURN 0; END IF;
    FOR a IN
        SELECT al.id, al.room_id, al.bed FROM hostel.allocation al JOIN hostel.application ap ON ap.id = al.application_id
         WHERE ap.session = p_session AND al.confirmed_at IS NULL AND al.lapsed_at IS NULL AND al.ended_at IS NULL AND al.held_until < now()
         ORDER BY al.held_until
    LOOP
        UPDATE hostel.allocation SET lapsed_at = now() WHERE id = a.id;
        UPDATE hostel.application SET state = 'LAPSED' WHERE id = (SELECT application_id FROM hostel.allocation WHERE id = a.id);
        n := n + 1;
        -- the bed goes to the next name on the draw, not back to the office
        SELECT ap.id AS application_id, ap.draw_position INTO nxt
          FROM hostel.application ap
          JOIN people.student st ON st.id = ap.student_id
          JOIN hostel.room r ON r.id = a.room_id JOIN hostel.hall h ON h.code = r.hall_code
         WHERE ap.session = p_session AND ap.state = 'UNSUCCESSFUL'
           AND (h.sex IS NULL OR st.sex IS NULL OR h.sex = st.sex)
         ORDER BY ap.draw_position LIMIT 1;
        IF FOUND THEN
            INSERT INTO hostel.allocation (application_id, session, room_id, bed, basis, draw_position, held_until)
            VALUES (nxt.application_id, p_session, a.room_id, a.bed, 'RESERVE', nxt.draw_position, now() + make_interval(hours => s.hold_hours));
            UPDATE hostel.application SET state = 'ALLOCATED' WHERE id = nxt.application_id;
        END IF;
    END LOOP;
    RETURN n;
END $$;

-- ── the fee: a reference like every other, confirmed by the Bursary or the gateway ──
CREATE OR REPLACE FUNCTION hostel.new_fee_reference(p_application uuid)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE ap hostel.application; al hostel.allocation; s hostel.session_setting; v_ref text;
BEGIN
    SELECT * INTO ap FROM hostel.application WHERE id = p_application;
    IF NOT FOUND THEN RAISE EXCEPTION 'no application %', p_application USING ERRCODE = 'no_data_found'; END IF;
    SELECT * INTO al FROM hostel.allocation WHERE application_id = ap.id AND lapsed_at IS NULL AND ended_at IS NULL ORDER BY allocated_at DESC LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'no bed is held against this application' USING ERRCODE = '23514',
        HINT = 'The accommodation fee is paid against a bed the draw allocated; without one there is nothing to pay for.'; END IF;
    IF al.confirmed_at IS NOT NULL THEN RAISE EXCEPTION 'this allocation is already paid and confirmed' USING ERRCODE = '23505'; END IF;
    IF al.held_until < now() THEN RAISE EXCEPTION 'the hold on this bed expired at %', al.held_until USING ERRCODE = '23514',
        HINT = 'The bed has gone, or will go, to the next name on the draw.'; END IF;
    SELECT * INTO s FROM hostel.session_setting WHERE session = ap.session;
    IF al.reference IS NOT NULL AND EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = al.reference AND expires_at > now() AND confirmed_at IS NULL) THEN
        RETURN al.reference;
    END IF;
    v_ref := finance.new_purpose_reference(ap.student_id, ap.session, s.fee, 'Hostel accommodation ' || ap.session || ' ' || al.id::text);
    UPDATE hostel.allocation SET reference = v_ref WHERE id = al.id;
    RETURN v_ref;
END $$;

CREATE OR REPLACE FUNCTION hostel.confirm_by_reference(p_reference text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE al hostel.allocation;
BEGIN
    SELECT * INTO al FROM hostel.allocation WHERE reference = p_reference AND confirmed_at IS NULL ORDER BY allocated_at DESC LIMIT 1;
    IF NOT FOUND THEN RETURN; END IF;
    IF al.lapsed_at IS NOT NULL AND EXISTS (SELECT 1 FROM hostel.allocation o WHERE o.session = al.session AND o.room_id = al.room_id AND o.bed = al.bed
                                              AND o.id <> al.id AND o.lapsed_at IS NULL AND o.ended_at IS NULL) THEN
        RAISE EXCEPTION 'the hold on this bed lapsed before the payment arrived, and the bed went to the next name on the draw'
        USING ERRCODE = '23514', HINT = 'The payment stands for the Bursary to refund or apply; Student Services allocates a bed that is free.';
    END IF;
    UPDATE hostel.allocation SET confirmed_at = now(), lapsed_at = NULL WHERE id = al.id;
    UPDATE hostel.application SET state = 'CONFIRMED' WHERE id = al.application_id;
END $$;

-- the confirmation (V027) settles the hostel purpose as it settles a transcript's
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
    ELSIF r.purpose LIKE 'Hostel accommodation%' THEN
        PERFORM hostel.confirm_by_reference(r.reference);
    END IF;
    SELECT * INTO reach FROM people.student_reach(r.student_id);
    SELECT * INTO pos FROM finance.position(r.student_id, r.session);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your payment is confirmed',
        'Your payment of NGN ' || r.amount::text || ' against reference ' || r.reference || ' is confirmed. Receipt ' || v_no || '. '
        || CASE WHEN r.purpose LIKE 'Transcript%' THEN 'Your transcript request is with the Registry.'
                WHEN r.purpose LIKE 'Hostel%' THEN 'Your bed space is confirmed; the Hostel screen names the hall and the room.'
                WHEN pos.balance = 0 THEN 'Your charges for ' || r.session || ' are settled in full.'
                ELSE 'NGN ' || pos.balance::text || ' remains for ' || r.session || '.' END
        || ' Sign in to download the receipt.', 'student', r.student_id);
    PERFORM platform.queue_notice('SMS', reach.phone, 'Your payment is confirmed',
        'MOAUM: payment ' || r.reference || ' confirmed, receipt ' || v_no || '.', 'student', r.student_id);
    RETURN 'confirmed';
END $$;

-- ── what the student sees ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION hostel.student_view(p_student uuid, p_session text)
RETURNS TABLE (application_id uuid, state text, hall_code text, hall_name text, category text, applied_at timestamptz,
               allocation_id uuid, room_id uuid, block text, room_no text, bed int, beds int, basis text, draw_position int,
               held_until timestamptz, confirmed_at timestamptz, lapsed_at timestamptz, reference text,
               fee numeric, hold_hours int, drawn_at timestamptz, seed text, applications_close date, open boolean)
LANGUAGE sql STABLE AS $$
    SELECT ap.id, ap.state, coalesce(r.hall_code, ap.hall_code), coalesce(hr.name, hp.name), ap.category, ap.applied_at,
           al.id, r.id, r.block, r.room_no, al.bed, r.beds, al.basis, coalesce(al.draw_position, ap.draw_position),
           al.held_until, al.confirmed_at, al.lapsed_at, al.reference,
           s.fee, s.hold_hours, s.drawn_at, s.seed, s.applications_close,
           s.session IS NOT NULL AND s.drawn_at IS NULL AND (s.applications_close IS NULL OR s.applications_close >= current_date)
      FROM (SELECT p_session AS session) q
      LEFT JOIN hostel.session_setting s ON s.session = q.session
      LEFT JOIN hostel.application ap ON ap.student_id = p_student AND ap.session = q.session AND ap.state <> 'WITHDRAWN'
      LEFT JOIN LATERAL (SELECT * FROM hostel.allocation x WHERE x.application_id = ap.id AND x.ended_at IS NULL
                          ORDER BY (x.lapsed_at IS NULL) DESC, x.allocated_at DESC LIMIT 1) al ON true
      LEFT JOIN hostel.room r ON r.id = al.room_id
      LEFT JOIN hostel.hall hr ON hr.code = r.hall_code
      LEFT JOIN hostel.hall hp ON hp.code = ap.hall_code
$$;

COMMIT;
