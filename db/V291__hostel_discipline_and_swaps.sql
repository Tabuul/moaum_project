-- ═══════════════════════════════════════════════════════════════════════════
-- V291 — hostel discipline (FR-HST-008) and the room swap (FR-HST-006), on
-- V261/V290.
--
--   · hostel.incident: an incident in a hostel, reported against a student
--     by the housing desk, Student Services or the Dean of Student Affairs;
--     the student is told and may answer it in their own words before any
--     sanction is decided; an incident is sanctioned or dismissed, never
--     deleted;
--   · hostel.sanction: what the Dean decides — a WARNING; a FINE, paid
--     through the Bursary on its own reference like a damage charge; LOSS OF
--     ACCOMMODATION, which cancels a stay not yet begun, or gives a student
--     checked in notice to vacate by a date through the same inspection and
--     clearance every stay ends by, and bars them from a bed until a date
--     (the end of the session unless the Dean says longer); or OTHER, a
--     measure recorded without an effect of the system's;
--   · the appeal: the student appeals a sanction once, within 14 days; the
--     Dean upholds, varies (the fine's amount, the bar's date) or quashes it;
--     a quashed fine unpaid is waived, a quashed bar lifted, a notice to
--     vacate not yet acted on withdrawn;
--   · hostel.eligibility: a bar in force refuses a bed; an unpaid fine does
--     too where the session refuses hostel debt, as a damage charge does;
--   · hostel.swap_request: two occupants of the same session exchange beds —
--     one proposes, naming the other by number; the other agrees; the Dean
--     approves; both beds move in one transaction, each stay closed and a new
--     one opened on the other's bed, the history kept. A swap is refused
--     where the beds carry a different fee or category, where a hall is not
--     for one of them, or where either is leaving, moving or unpaid;
--   · hostel.transfer now carries the stay's category, fee and fee status to
--     the new bed (V290 added them; V261's transfer predated them and left a
--     paid student reading OUTSTANDING after a move); the stays already moved
--     are corrected here;
--   · hostel.finance_summary counts fines apart from accommodation revenue.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'dsa', true),
       set_config('moaum.reason', 'V291: hostel discipline and swaps', true);

-- ── 1 · the kinds of incident ───────────────────────────────────────────
CREATE TABLE hostel.incident_kind (
    code   text PRIMARY KEY,
    label  text NOT NULL,
    active boolean NOT NULL DEFAULT true,
    ord    int NOT NULL DEFAULT 100,
    CONSTRAINT ck_ik_code CHECK (code ~ '^[A-Z][A-Z0-9_]{1,30}$')
);
COMMENT ON TABLE hostel.incident_kind IS 'What a hostel incident is (V291): the Dean of Student Affairs may add kinds; none is removed, only made inactive.';
SELECT audit.attach('hostel.incident_kind');
INSERT INTO hostel.incident_kind (code, label, ord) VALUES
    ('NOISE',            'Noise and disturbance',                  10),
    ('UNAUTHORISED_GUEST','Unauthorised visitor or squatter',     20),
    ('CURFEW',           'Breach of curfew or gate hours',         30),
    ('COOKING',          'Cooking or prohibited appliance in room', 40),
    ('PROPERTY_DAMAGE',  'Wilful damage to hostel property',       50),
    ('THEFT',            'Theft',                                  60),
    ('FIGHTING',         'Fighting or assault',                    70),
    ('SUBSTANCES',       'Alcohol, drugs or other prohibited substances', 80),
    ('HARASSMENT',       'Harassment or intimidation',             90),
    ('UNAUTHORISED_MOVE','Occupying a bed not allocated',          100),
    ('OTHER',            'Other breach of the hostel rules',       900)
ON CONFLICT (code) DO NOTHING;

-- ── 2 · the incident ────────────────────────────────────────────────────
CREATE TABLE hostel.incident (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference        text NOT NULL UNIQUE DEFAULT hostel.next_ref('HOSTEL_INCIDENT', 'HDI'),
    session          text NOT NULL REFERENCES policy.academic_session(name),
    student_id       uuid NOT NULL REFERENCES people.student(id),
    allocation_id    uuid NULL REFERENCES hostel.allocation(id),
    hall_code        text NULL REFERENCES hostel.hall(code),
    room_id          uuid NULL REFERENCES hostel.room(id),
    kind             text NOT NULL REFERENCES hostel.incident_kind(code),
    occurred_at      timestamptz NOT NULL,
    place            text NULL,
    description      text NOT NULL,
    witnesses        text NULL,
    reported_by      uuid NULL,
    reported_office  text NULL,
    reported_at      timestamptz NOT NULL DEFAULT now(),
    statement        text NULL,
    statement_at     timestamptz NULL,
    state            text NOT NULL DEFAULT 'REPORTED',
    decided_by       uuid NULL,
    decided_at       timestamptz NULL,
    decision_note    text NULL,
    CONSTRAINT ck_hi_state CHECK (state IN ('REPORTED', 'SANCTIONED', 'DISMISSED')),
    CONSTRAINT ck_hi_description CHECK (btrim(description) <> ''),
    CONSTRAINT ck_hi_dismissed CHECK (state <> 'DISMISSED' OR (decision_note IS NOT NULL AND btrim(decision_note) <> ''))
);
COMMENT ON TABLE hostel.incident IS 'A hostel disciplinary incident (V291, FR-HST-008): reported against a student, answered by the student, then sanctioned or dismissed by the Dean of Student Affairs. Never deleted.';
CREATE INDEX ix_hi_student ON hostel.incident (student_id, session);
CREATE INDEX ix_hi_session ON hostel.incident (session, state);
SELECT audit.attach('hostel.incident');

-- ── 3 · the sanction, and its appeal ────────────────────────────────────
CREATE TABLE hostel.sanction (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference        text NOT NULL UNIQUE DEFAULT hostel.next_ref('HOSTEL_SANCTION', 'HDS'),
    incident_id      uuid NOT NULL REFERENCES hostel.incident(id),
    student_id       uuid NOT NULL REFERENCES people.student(id),
    session          text NOT NULL REFERENCES policy.academic_session(name),
    kind             text NOT NULL,
    amount           numeric(12,2) NULL,
    payment_ref      text NULL,
    settled_at       timestamptz NULL,
    waived_at        timestamptz NULL,
    waived_by        uuid NULL,
    waived_reason    text NULL,
    barred_until     date NULL,
    vacate_by        date NULL,
    allocation_id    uuid NULL REFERENCES hostel.allocation(id),
    effect           text NULL,
    reason           text NOT NULL,
    decided_by       uuid NULL,
    decided_at       timestamptz NOT NULL DEFAULT now(),
    state            text NOT NULL DEFAULT 'IN_FORCE',
    appeal_by        date NOT NULL DEFAULT (current_date + 14),
    appeal_state     text NULL,
    appeal_ground    text NULL,
    appealed_at      timestamptz NULL,
    appeal_decided_by uuid NULL,
    appeal_decided_at timestamptz NULL,
    appeal_note      text NULL,
    CONSTRAINT ck_hsn_kind CHECK (kind IN ('WARNING', 'FINE', 'EVICTION', 'OTHER')),
    CONSTRAINT ck_hsn_state CHECK (state IN ('IN_FORCE', 'QUASHED')),
    CONSTRAINT ck_hsn_fine CHECK (kind <> 'FINE' OR amount IS NOT NULL AND amount >= 0),
    CONSTRAINT ck_hsn_amount CHECK (kind = 'FINE' OR amount IS NULL),
    CONSTRAINT ck_hsn_bar CHECK (kind = 'EVICTION' OR barred_until IS NULL),
    CONSTRAINT ck_hsn_reason CHECK (btrim(reason) <> ''),
    CONSTRAINT ck_hsn_appeal CHECK (appeal_state IS NULL OR appeal_state IN ('LODGED', 'UPHELD', 'VARIED', 'QUASHED')),
    CONSTRAINT ck_hsn_waived CHECK (waived_at IS NULL OR waived_reason IS NOT NULL)
);
COMMENT ON TABLE hostel.sanction IS 'What the Dean of Student Affairs decided on a hostel incident (V291): a warning, a fine paid through the Bursary, loss of accommodation with a bar until a date, or another measure recorded; appealed once, upheld, varied or quashed.';
COMMENT ON COLUMN hostel.sanction.barred_until IS 'Loss of accommodation: no bed is given to the student until this date passes (hostel.eligibility). Lifted when the sanction is quashed.';
CREATE INDEX ix_hsn_student ON hostel.sanction (student_id, state);
CREATE INDEX ix_hsn_incident ON hostel.sanction (incident_id);
SELECT audit.attach('hostel.sanction');

-- ── 4 · the swap ────────────────────────────────────────────────────────
CREATE TABLE hostel.swap_request (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference         text NOT NULL UNIQUE DEFAULT hostel.next_ref('HOSTEL_SWAP', 'HSW'),
    session           text NOT NULL REFERENCES policy.academic_session(name),
    student_id        uuid NOT NULL REFERENCES people.student(id),
    allocation_id     uuid NOT NULL REFERENCES hostel.allocation(id),
    partner_id        uuid NOT NULL REFERENCES people.student(id),
    partner_allocation uuid NOT NULL REFERENCES hostel.allocation(id),
    reason            text NOT NULL,
    state             text NOT NULL DEFAULT 'PROPOSED',
    proposed_at       timestamptz NOT NULL DEFAULT now(),
    answered_at       timestamptz NULL,
    partner_note      text NULL,
    decided_by        uuid NULL,
    decided_at        timestamptz NULL,
    decision_note     text NULL,
    new_allocation    uuid NULL REFERENCES hostel.allocation(id),
    new_partner_allocation uuid NULL REFERENCES hostel.allocation(id),
    CONSTRAINT ck_hsw_state CHECK (state IN ('PROPOSED', 'AGREED', 'DECLINED', 'CANCELLED', 'REJECTED', 'COMPLETED')),
    CONSTRAINT ck_hsw_reason CHECK (btrim(reason) <> ''),
    CONSTRAINT ck_hsw_two CHECK (student_id <> partner_id)
);
COMMENT ON TABLE hostel.swap_request IS 'Two occupants of a session exchange beds (V291, FR-HST-006): proposed by one, agreed by the other, approved by the Dean of Student Affairs, both beds moved in one transaction.';
CREATE INDEX ix_hsw_session ON hostel.swap_request (session, state);
CREATE INDEX ix_hsw_student ON hostel.swap_request (student_id);
CREATE INDEX ix_hsw_partner ON hostel.swap_request (partner_id);
SELECT audit.attach('hostel.swap_request');

GRANT SELECT, INSERT, UPDATE ON hostel.incident_kind, hostel.incident, hostel.sanction, hostel.swap_request TO app_student, app_finance;
GRANT SELECT ON hostel.incident_kind, hostel.incident, hostel.sanction, hostel.swap_request TO app_auditor;

-- the Dean of Student Affairs is told too, beside the housing desk and Student Services
CREATE OR REPLACE FUNCTION hostel.tell_dean(p_subject text, p_body text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT DISTINCT pe.id, pe.email FROM iam.office_assignment a JOIN iam.person pe ON pe.id = a.person_id
         WHERE a.office_code IN ('dsa', 'housing', 'services') AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) AND pe.email IS NOT NULL
    LOOP
        PERFORM platform.queue_notice('EMAIL', r.email, p_subject, p_body, 'person', r.id);
    END LOOP;
END $$;

-- ── 5 · the incident reported, answered, dismissed ──────────────────────
CREATE OR REPLACE FUNCTION hostel.report_incident(p_student uuid, p_session text, p_kind text, p_occurred timestamptz, p_place text, p_description text, p_witnesses text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE st people.student; al hostel.allocation; r hostel.room; v uuid; v_ref text; k hostel.incident_kind;
BEGIN
    IF nullif(btrim(coalesce(p_description, '')), '') IS NULL THEN RAISE EXCEPTION 'HOSTEL_INCIDENT: say what happened' USING ERRCODE = '23514'; END IF;
    SELECT * INTO st FROM people.student WHERE id = p_student;
    IF st.id IS NULL THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN RAISE EXCEPTION 'no session %', p_session USING ERRCODE = '23503'; END IF;
    SELECT * INTO k FROM hostel.incident_kind WHERE code = upper(coalesce(p_kind, 'OTHER')) AND active;
    IF k.code IS NULL THEN RAISE EXCEPTION 'HOSTEL_INCIDENT: % is not a kind of incident', p_kind USING ERRCODE = '23514'; END IF;
    IF p_occurred IS NOT NULL AND p_occurred > now() + interval '1 hour' THEN RAISE EXCEPTION 'HOSTEL_INCIDENT: an incident is reported after it happens' USING ERRCODE = '23514'; END IF;
    -- the stay it happened in, if the student has one this session: its hall and room are on the incident
    SELECT * INTO al FROM hostel.allocation WHERE student_id = p_student AND session = p_session AND lapsed_at IS NULL AND ended_at IS NULL;
    IF al.id IS NOT NULL THEN SELECT * INTO r FROM hostel.room WHERE id = al.room_id; END IF;
    INSERT INTO hostel.incident (session, student_id, allocation_id, hall_code, room_id, kind, occurred_at, place, description, witnesses, reported_by, reported_office)
    VALUES (p_session, p_student, al.id, r.hall_code, r.id, k.code, coalesce(p_occurred, now()), nullif(btrim(coalesce(p_place, '')), ''), btrim(p_description), nullif(btrim(coalesce(p_witnesses, '')), ''),
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    RETURNING id, reference INTO v, v_ref;
    PERFORM hostel.log(NULL, al.id, p_student, r.hall_code, r.id, NULL, 'INCIDENT_REPORTED', NULL, v_ref || ' · ' || k.label, btrim(p_description));
    PERFORM hostel.tell_student(p_student, 'A hostel incident has been reported against you',
        'Incident ' || v_ref || ' (' || lower(k.label) || ') has been reported against you to the Dean of Student Affairs. '
        || 'You may give your own account of it under Hostel on the portal before any decision is made.',
        'MOAUM: hostel incident ' || v_ref || ' reported against you. Give your account on the portal.');
    PERFORM hostel.tell_dean('A hostel incident has been reported', 'Incident ' || v_ref || ' (' || lower(k.label) || ') against ' || st.surname || ', ' || st.other_names || ': ' || btrim(p_description));
    RETURN v;
END $$;
COMMENT ON FUNCTION hostel.report_incident(uuid, text, text, timestamptz, text, text, text) IS 'A hostel incident reported against a student (V291): the stay it happened in is attached, the student told and invited to answer, the Dean told.';

CREATE OR REPLACE FUNCTION hostel.answer_incident(p_incident uuid, p_student uuid, p_statement text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE i hostel.incident;
BEGIN
    SELECT * INTO i FROM hostel.incident WHERE id = p_incident FOR UPDATE;
    IF i.id IS NULL OR i.student_id <> p_student THEN RAISE EXCEPTION 'no such incident' USING ERRCODE = '23503'; END IF;
    IF i.state <> 'REPORTED' THEN RAISE EXCEPTION 'HOSTEL_INCIDENT_DECIDED: incident % has been %; appeal the sanction instead', i.reference, lower(i.state) USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_statement, '')), '') IS NULL THEN RAISE EXCEPTION 'HOSTEL_INCIDENT: write your account' USING ERRCODE = '23514'; END IF;
    UPDATE hostel.incident SET statement = btrim(p_statement), statement_at = now() WHERE id = i.id;
    PERFORM hostel.log(NULL, i.allocation_id, i.student_id, i.hall_code, i.room_id, NULL, 'INCIDENT_ANSWERED', NULL, i.reference, left(btrim(p_statement), 500));
    PERFORM hostel.tell_dean('A student has answered a hostel incident', 'The student has given an account of incident ' || i.reference || '.');
END $$;

CREATE OR REPLACE FUNCTION hostel.dismiss_incident(p_incident uuid, p_note text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE i hostel.incident;
BEGIN
    SELECT * INTO i FROM hostel.incident WHERE id = p_incident FOR UPDATE;
    IF i.id IS NULL THEN RAISE EXCEPTION 'no such incident' USING ERRCODE = '23503'; END IF;
    IF i.state <> 'REPORTED' THEN RAISE EXCEPTION 'HOSTEL_INCIDENT_DECIDED: incident % has already been %', i.reference, lower(i.state) USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN RAISE EXCEPTION 'HOSTEL_INCIDENT: say why the incident is dismissed' USING ERRCODE = '23514'; END IF;
    UPDATE hostel.incident SET state = 'DISMISSED', decided_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, decided_at = now(), decision_note = btrim(p_note) WHERE id = i.id;
    PERFORM hostel.log(NULL, i.allocation_id, i.student_id, i.hall_code, i.room_id, NULL, 'INCIDENT_DISMISSED', 'REPORTED', 'DISMISSED', i.reference || ': ' || btrim(p_note));
    PERFORM hostel.tell_student(i.student_id, 'A hostel incident against you is dismissed',
        'Incident ' || i.reference || ' has been dismissed by the Dean of Student Affairs: ' || btrim(p_note) || '. No sanction follows.',
        'MOAUM: hostel incident ' || i.reference || ' dismissed.');
END $$;

-- ── 6 · the fine's payment reference: kept while it lives, made again when it has expired ──
CREATE OR REPLACE FUNCTION hostel.fine_reference(p_sanction uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE s hostel.sanction; v_ref text;
BEGIN
    SELECT * INTO s FROM hostel.sanction WHERE id = p_sanction FOR UPDATE;
    IF s.id IS NULL THEN RAISE EXCEPTION 'no such sanction' USING ERRCODE = '23503'; END IF;
    IF s.kind <> 'FINE' THEN RAISE EXCEPTION 'HOSTEL_FINE: sanction % is not a fine', s.reference USING ERRCODE = '23514'; END IF;
    IF s.state <> 'IN_FORCE' THEN RAISE EXCEPTION 'HOSTEL_FINE: sanction % was quashed; nothing is owed', s.reference USING ERRCODE = '23514'; END IF;
    IF s.settled_at IS NOT NULL THEN RAISE EXCEPTION 'HOSTEL_FINE: fine % is already paid', s.reference USING ERRCODE = '23505'; END IF;
    IF s.waived_at IS NOT NULL OR coalesce(s.amount, 0) = 0 THEN RAISE EXCEPTION 'HOSTEL_FINE: nothing is owed on fine %', s.reference USING ERRCODE = '23514'; END IF;
    IF s.payment_ref IS NOT NULL AND EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = s.payment_ref AND expires_at > now() AND confirmed_at IS NULL) THEN
        RETURN s.payment_ref;
    END IF;
    -- the purpose names the sanction, so a payment against a reference since replaced still finds it
    v_ref := finance.new_purpose_reference(s.student_id, s.session, s.amount, 'Hostel accommodation fine ' || s.reference || ' ' || s.id::text);
    UPDATE hostel.sanction SET payment_ref = v_ref WHERE id = s.id;
    RETURN v_ref;
END $$;
COMMENT ON FUNCTION hostel.fine_reference(uuid) IS 'The payment reference of a hostel fine (V291): the live one, or a new one when it has expired; paid through the Bursary like any other.';

-- ── 7 · the sanction decided, with its effect ──────────────────────────
CREATE OR REPLACE FUNCTION hostel.impose_sanction(p_incident uuid, p_kind text, p_amount numeric, p_barred_until date, p_vacate_by date, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE i hostel.incident; al hostel.allocation; v uuid; v_ref text; v_kind text := upper(coalesce(p_kind, '')); v_bar date; v_vacate date; v_effect text; v_pay text;
        who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_end date;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'HOSTEL_SANCTION: a sanction is decided by a person' USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'HOSTEL_SANCTION: a sanction carries its reason' USING ERRCODE = '23514'; END IF;
    IF v_kind NOT IN ('WARNING', 'FINE', 'EVICTION', 'OTHER') THEN RAISE EXCEPTION 'HOSTEL_SANCTION: a sanction is a warning, a fine, loss of accommodation or another measure' USING ERRCODE = '23514'; END IF;
    SELECT * INTO i FROM hostel.incident WHERE id = p_incident FOR UPDATE;
    IF i.id IS NULL THEN RAISE EXCEPTION 'no such incident' USING ERRCODE = '23503'; END IF;
    IF i.state = 'DISMISSED' THEN RAISE EXCEPTION 'HOSTEL_INCIDENT_DECIDED: incident % was dismissed', i.reference USING ERRCODE = '23514'; END IF;
    IF v_kind = 'FINE' AND (p_amount IS NULL OR p_amount <= 0) THEN RAISE EXCEPTION 'HOSTEL_SANCTION: a fine is an amount above nothing' USING ERRCODE = '23514'; END IF;
    SELECT ends_on INTO v_end FROM policy.academic_session WHERE name = i.session;
    IF v_kind = 'EVICTION' THEN
        v_bar := coalesce(p_barred_until, v_end, current_date);
        IF v_bar < current_date THEN RAISE EXCEPTION 'HOSTEL_SANCTION: the bar runs to a date not yet passed' USING ERRCODE = '23514'; END IF;
        v_vacate := coalesce(p_vacate_by, current_date);
        IF v_vacate < current_date THEN RAISE EXCEPTION 'HOSTEL_SANCTION: the date to vacate by is today or later' USING ERRCODE = '23514'; END IF;
    END IF;
    INSERT INTO hostel.sanction (incident_id, student_id, session, kind, amount, barred_until, vacate_by, reason, decided_by)
    VALUES (i.id, i.student_id, i.session, v_kind, CASE WHEN v_kind = 'FINE' THEN p_amount END, v_bar, v_vacate, btrim(p_reason), who)
    RETURNING id, reference INTO v, v_ref;
    UPDATE hostel.incident SET state = 'SANCTIONED', decided_by = who, decided_at = now(), decision_note = coalesce(decision_note || ' · ', '') || v_ref WHERE id = i.id;

    IF v_kind = 'FINE' THEN
        v_pay := hostel.fine_reference(v);
        v_effect := 'Fine of NGN ' || p_amount::text || ' on payment reference ' || v_pay;
    ELSIF v_kind = 'EVICTION' THEN
        -- the stay of the session: one not begun is cancelled; one checked in is given notice to vacate, and ends through inspection and clearance
        SELECT * INTO al FROM hostel.allocation WHERE student_id = i.student_id AND session = i.session AND lapsed_at IS NULL AND ended_at IS NULL FOR UPDATE;
        IF al.id IS NULL THEN
            v_effect := 'No stay stands this session; the student is barred from a bed until ' || to_char(v_bar, 'FMDD FMMonth YYYY');
        ELSIF al.state = 'CHECKED_IN' THEN
            UPDATE hostel.allocation SET checkout_requested_at = now(), checkout_on = v_vacate, checkout_reason = 'Loss of accommodation: sanction ' || v_ref WHERE id = al.id;
            PERFORM hostel.log(al.application_id, al.id, al.student_id, NULL, al.room_id, al.bed_id, 'NOTICE_TO_VACATE', NULL, v_vacate::text, 'Sanction ' || v_ref || ': ' || btrim(p_reason));
            v_effect := 'Notice to vacate ' || al.reference_no || ' by ' || to_char(v_vacate, 'FMDD FMMonth YYYY') || '; barred until ' || to_char(v_bar, 'FMDD FMMonth YYYY');
        ELSE
            UPDATE hostel.allocation SET state = 'CANCELLED', ended_at = now(), ended_reason = 'EVICTED: sanction ' || v_ref WHERE id = al.id;
            UPDATE hostel.application SET state = 'WITHDRAWN', withdrawn_at = now(), withdrawn_reason = 'Loss of accommodation: sanction ' || v_ref WHERE id = al.application_id;
            PERFORM hostel.log(al.application_id, al.id, al.student_id, NULL, al.room_id, al.bed_id, 'CANCELLED', al.state, 'CANCELLED', 'Loss of accommodation: sanction ' || v_ref);
            v_effect := 'Allocation ' || al.reference_no || ' cancelled before check-in' || CASE WHEN al.fee_status = 'PAID' THEN ' (the fee was paid: any refund is the Bursary''s decision)' ELSE '' END || '; barred until ' || to_char(v_bar, 'FMDD FMMonth YYYY');
        END IF;
        UPDATE hostel.sanction SET allocation_id = al.id WHERE id = v;
    ELSIF v_kind = 'WARNING' THEN
        v_effect := 'A written warning, kept on the record';
    ELSE
        v_effect := 'Recorded: ' || btrim(p_reason);
    END IF;
    UPDATE hostel.sanction SET effect = v_effect WHERE id = v;
    PERFORM hostel.log(NULL, i.allocation_id, i.student_id, i.hall_code, i.room_id, NULL, 'SANCTION_IMPOSED', i.reference, v_ref || ' · ' || v_kind, v_effect);
    PERFORM hostel.tell_student(i.student_id,
        CASE v_kind WHEN 'WARNING' THEN 'A hostel warning has been issued to you' WHEN 'FINE' THEN 'A hostel fine has been imposed on you'
                    WHEN 'EVICTION' THEN 'You have lost your hostel accommodation' ELSE 'A hostel sanction has been decided' END,
        'On incident ' || i.reference || ' the Dean of Student Affairs has decided sanction ' || v_ref || ': ' || btrim(p_reason) || '. ' || v_effect || '. '
        || 'You may appeal it once, under Hostel on the portal, until ' || to_char(current_date + 14, 'FMDD FMMonth YYYY') || '.',
        'MOAUM: hostel sanction ' || v_ref || ' (' || lower(v_kind) || '). Appeal by ' || to_char(current_date + 14, 'DD Mon') || '.');
    RETURN v;
END $$;
COMMENT ON FUNCTION hostel.impose_sanction(uuid, text, numeric, date, date, text) IS 'The Dean decides a sanction on an incident (V291): a warning; a fine on its own payment reference; loss of accommodation — a stay not begun cancelled, a stay checked in given notice to vacate through inspection and clearance, a bar until a date; or another measure recorded.';

-- ── 8 · the appeal, and the Dean's answer ───────────────────────────────
CREATE OR REPLACE FUNCTION hostel.appeal_sanction(p_sanction uuid, p_student uuid, p_ground text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE s hostel.sanction;
BEGIN
    SELECT * INTO s FROM hostel.sanction WHERE id = p_sanction FOR UPDATE;
    IF s.id IS NULL OR s.student_id <> p_student THEN RAISE EXCEPTION 'no such sanction' USING ERRCODE = '23503'; END IF;
    IF s.state <> 'IN_FORCE' THEN RAISE EXCEPTION 'HOSTEL_APPEAL: sanction % has been quashed', s.reference USING ERRCODE = '23514'; END IF;
    IF s.appeal_state IS NOT NULL THEN RAISE EXCEPTION 'HOSTEL_APPEAL: sanction % has already been appealed (%)', s.reference, lower(s.appeal_state) USING ERRCODE = '23514', HINT = 'A sanction is appealed once.'; END IF;
    IF current_date > s.appeal_by THEN RAISE EXCEPTION 'HOSTEL_APPEAL: the time to appeal sanction % closed on %', s.reference, to_char(s.appeal_by, 'FMDD FMMonth YYYY') USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_ground, '')), '') IS NULL THEN RAISE EXCEPTION 'HOSTEL_APPEAL: state the ground of the appeal' USING ERRCODE = '23514'; END IF;
    UPDATE hostel.sanction SET appeal_state = 'LODGED', appeal_ground = btrim(p_ground), appealed_at = now() WHERE id = s.id;
    PERFORM hostel.log(NULL, s.allocation_id, s.student_id, NULL, NULL, NULL, 'SANCTION_APPEALED', NULL, s.reference, left(btrim(p_ground), 500));
    PERFORM hostel.tell_dean('A hostel sanction has been appealed', 'Sanction ' || s.reference || ' (' || lower(s.kind) || ') is appealed: ' || btrim(p_ground));
    PERFORM hostel.tell_student(s.student_id, 'Your appeal is lodged', 'Your appeal against sanction ' || s.reference || ' is with the Dean of Student Affairs. The sanction stands until the appeal is decided.', 'MOAUM: appeal against ' || s.reference || ' lodged.');
END $$;

CREATE OR REPLACE FUNCTION hostel.decide_appeal(p_sanction uuid, p_decision text, p_amount numeric, p_barred_until date, p_note text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE s hostel.sanction; al hostel.allocation; v_dec text := upper(coalesce(p_decision, '')); who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_what text := '';
BEGIN
    SELECT * INTO s FROM hostel.sanction WHERE id = p_sanction FOR UPDATE;
    IF s.id IS NULL THEN RAISE EXCEPTION 'no such sanction' USING ERRCODE = '23503'; END IF;
    IF s.appeal_state IS DISTINCT FROM 'LODGED' THEN RAISE EXCEPTION 'HOSTEL_APPEAL: no appeal of sanction % waits', s.reference USING ERRCODE = '23514'; END IF;
    IF v_dec NOT IN ('UPHELD', 'VARIED', 'QUASHED') THEN RAISE EXCEPTION 'HOSTEL_APPEAL: an appeal is upheld, varied or quashed' USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN RAISE EXCEPTION 'HOSTEL_APPEAL: say why' USING ERRCODE = '23514'; END IF;
    IF v_dec = 'VARIED' THEN
        IF s.kind = 'FINE' THEN
            IF p_amount IS NULL OR p_amount < 0 THEN RAISE EXCEPTION 'HOSTEL_APPEAL: state the fine as varied' USING ERRCODE = '23514'; END IF;
            IF s.settled_at IS NOT NULL THEN RAISE EXCEPTION 'HOSTEL_APPEAL: fine % is already paid; a refund of the difference is the Bursary''s decision', s.reference USING ERRCODE = '23514'; END IF;
            UPDATE hostel.sanction SET amount = p_amount, payment_ref = NULL,
                   waived_at = CASE WHEN p_amount = 0 THEN now() END, waived_by = CASE WHEN p_amount = 0 THEN who END, waived_reason = CASE WHEN p_amount = 0 THEN 'Varied to nothing on appeal' END
             WHERE id = s.id;
            v_what := 'The fine is now NGN ' || p_amount::text;
        ELSIF s.kind = 'EVICTION' THEN
            IF p_barred_until IS NULL THEN RAISE EXCEPTION 'HOSTEL_APPEAL: state the date the bar runs to' USING ERRCODE = '23514'; END IF;
            UPDATE hostel.sanction SET barred_until = p_barred_until WHERE id = s.id;
            v_what := 'The bar now runs to ' || to_char(p_barred_until, 'FMDD FMMonth YYYY');
        ELSE
            RAISE EXCEPTION 'HOSTEL_APPEAL: a % is upheld or quashed, not varied', lower(s.kind) USING ERRCODE = '23514';
        END IF;
    ELSIF v_dec = 'QUASHED' THEN
        UPDATE hostel.sanction SET state = 'QUASHED', barred_until = NULL,
               waived_at = CASE WHEN kind = 'FINE' AND settled_at IS NULL THEN now() ELSE waived_at END,
               waived_by = CASE WHEN kind = 'FINE' AND settled_at IS NULL THEN who ELSE waived_by END,
               waived_reason = CASE WHEN kind = 'FINE' AND settled_at IS NULL THEN 'Quashed on appeal' ELSE waived_reason END
         WHERE id = s.id;
        v_what := 'The sanction no longer stands';
        IF s.kind = 'FINE' AND s.settled_at IS NOT NULL THEN v_what := v_what || '; the fine was paid, and its refund is the Bursary''s decision'; END IF;
        IF s.kind = 'EVICTION' AND s.allocation_id IS NOT NULL THEN
            SELECT * INTO al FROM hostel.allocation WHERE id = s.allocation_id FOR UPDATE;
            -- a notice to vacate not yet acted on is withdrawn; a stay already ended is not restored, but the bar is lifted
            IF al.state = 'CHECKED_IN' AND al.ended_at IS NULL AND al.checkout_reason LIKE '%' || s.reference AND NOT EXISTS (SELECT 1 FROM hostel.clearance c WHERE c.allocation_id = al.id) THEN
                UPDATE hostel.allocation SET checkout_requested_at = NULL, checkout_on = NULL, checkout_reason = NULL WHERE id = al.id;
                PERFORM hostel.log(al.application_id, al.id, al.student_id, NULL, al.room_id, al.bed_id, 'NOTICE_TO_VACATE_WITHDRAWN', NULL, NULL, 'Sanction ' || s.reference || ' quashed on appeal');
                v_what := v_what || '; the notice to vacate is withdrawn and the stay continues';
            ELSE
                v_what := v_what || '; the bar is lifted, and the student may apply for a bed again';
            END IF;
        END IF;
    END IF;
    UPDATE hostel.sanction SET appeal_state = v_dec, appeal_decided_by = who, appeal_decided_at = now(), appeal_note = btrim(p_note) WHERE id = s.id;
    PERFORM hostel.log(NULL, s.allocation_id, s.student_id, NULL, NULL, NULL, 'APPEAL_' || v_dec, 'LODGED', v_dec, s.reference || ': ' || btrim(p_note) || CASE WHEN v_what <> '' THEN ' · ' || v_what ELSE '' END);
    PERFORM hostel.tell_student(s.student_id, 'Your hostel appeal is decided',
        'Your appeal against sanction ' || s.reference || ' is ' || lower(v_dec) || ': ' || btrim(p_note) || '.' || CASE WHEN v_what <> '' THEN ' ' || v_what || '.' ELSE '' END,
        'MOAUM: appeal against ' || s.reference || ' ' || lower(v_dec) || '.');
END $$;

-- a fine the Dean waives outside an appeal, with the reason on the record
CREATE OR REPLACE FUNCTION hostel.waive_fine(p_sanction uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE s hostel.sanction;
BEGIN
    SELECT * INTO s FROM hostel.sanction WHERE id = p_sanction FOR UPDATE;
    IF s.id IS NULL THEN RAISE EXCEPTION 'no such sanction' USING ERRCODE = '23503'; END IF;
    IF s.kind <> 'FINE' THEN RAISE EXCEPTION 'HOSTEL_FINE: sanction % is not a fine', s.reference USING ERRCODE = '23514'; END IF;
    IF s.settled_at IS NOT NULL OR s.waived_at IS NOT NULL THEN RAISE EXCEPTION 'HOSTEL_FINE: fine % is already % ', s.reference, CASE WHEN s.settled_at IS NOT NULL THEN 'paid' ELSE 'waived' END USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'HOSTEL_FINE: say why the fine is waived' USING ERRCODE = '23514'; END IF;
    UPDATE hostel.sanction SET waived_at = now(), waived_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, waived_reason = btrim(p_reason) WHERE id = s.id;
    PERFORM hostel.log(NULL, s.allocation_id, s.student_id, NULL, NULL, NULL, 'FINE_WAIVED', s.amount::text, '0', s.reference || ': ' || btrim(p_reason));
    PERFORM hostel.tell_student(s.student_id, 'A hostel fine is waived', 'Fine ' || s.reference || ' of NGN ' || s.amount::text || ' has been waived: ' || btrim(p_reason) || '.', 'MOAUM: hostel fine ' || s.reference || ' waived.');
END $$;

-- ── 9 · the bar: what a sanction in force withholds ─────────────────────
CREATE OR REPLACE FUNCTION hostel.discipline_bar(p_student uuid, p_with_fines boolean)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT 'Barred from hostel accommodation until ' || to_char(s.barred_until, 'FMDD FMMonth YYYY') || ' by sanction ' || s.reference
           FROM hostel.sanction s WHERE s.student_id = p_student AND s.state = 'IN_FORCE' AND s.kind = 'EVICTION' AND s.barred_until >= current_date
          ORDER BY s.barred_until DESC LIMIT 1),
        CASE WHEN p_with_fines THEN
            (SELECT 'An unpaid hostel fine of NGN ' || sum(s.amount)::text || ' stands (' || string_agg(s.reference, ', ') || ')'
               FROM hostel.sanction s WHERE s.student_id = p_student AND s.state = 'IN_FORCE' AND s.kind = 'FINE' AND s.settled_at IS NULL AND s.waived_at IS NULL AND s.amount > 0
             HAVING count(*) > 0)
        END)
$$;
COMMENT ON FUNCTION hostel.discipline_bar(uuid, boolean) IS 'Why a sanction in force withholds a bed (V291): a bar from loss of accommodation not yet passed; and, where hostel debt is refused, an unpaid fine. NULL when nothing does.';

-- eligibility, as V290 left it, with the bar read beside the hostel debt
CREATE OR REPLACE FUNCTION hostel.eligibility(p_student uuid, p_session text)
 RETURNS TABLE(ok boolean, why text)
 LANGUAGE plpgsql STABLE AS $fn$
DECLARE s hostel.session_setting; st people.student; v_fac text; v_debt numeric; v_paid boolean; v_bar text;
BEGIN
    SELECT * INTO s FROM hostel.session_setting WHERE session = p_session;
    IF s.session IS NULL THEN RETURN QUERY SELECT false, 'Accommodation for ' || p_session || ' is not open'; RETURN; END IF;
    SELECT * INTO st FROM people.student WHERE id = p_student;
    IF st.id IS NULL THEN RETURN QUERY SELECT false, 'No student record'; RETURN; END IF;
    IF NOT (st.status = ANY (s.eligible_statuses)) THEN RETURN QUERY SELECT false, 'A student whose status is ' || lower(replace(st.status, '_', ' ')) || ' is not eligible'; RETURN; END IF;
    -- a sanction in force (V291): the bar always; an unpaid fine where the session refuses hostel debt
    v_bar := hostel.discipline_bar(st.id, s.refuse_hostel_debt);
    IF v_bar IS NOT NULL THEN RETURN QUERY SELECT false, v_bar; RETURN; END IF;
    IF s.eligible_levels IS NOT NULL AND array_length(s.eligible_levels, 1) > 0 AND NOT (st.current_level = ANY (s.eligible_levels)) THEN
        RETURN QUERY SELECT false, st.current_level || ' Level is not eligible this session'; RETURN;
    END IF;
    SELECT p.faculty_code INTO v_fac FROM ref.programme p WHERE p.code = st.programme_code;
    IF s.eligible_faculties IS NOT NULL AND array_length(s.eligible_faculties, 1) > 0 AND NOT (v_fac = ANY (s.eligible_faculties)) THEN
        RETURN QUERY SELECT false, 'The faculty is not eligible this session'; RETURN;
    END IF;
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

-- ── 10 · the payment: a fine settled through the same door as the fee and the damage charge ──
CREATE OR REPLACE FUNCTION hostel.confirm_by_reference(p_reference text)
 RETURNS void
 LANGUAGE plpgsql AS $fn$
DECLARE al hostel.allocation; c hostel.damage_charge; v_purpose text; sn hostel.sanction;
BEGIN
    -- a fine (V291): found by the sanction named in the purpose, whichever of its references was paid
    SELECT purpose INTO v_purpose FROM finance.payment_reference WHERE reference = p_reference;
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

-- ── 11 · a move keeps the stay's category, fee and fee status ───────────
-- a stay moved to another bed is two steps: the old closed, then a new one opened carrying everything the stay carried.
-- A transfer does both at once; a swap closes both stays before it opens either, since each bed holds one live stay.
CREATE OR REPLACE FUNCTION hostel.close_for_move(p_allocation uuid, p_ended text, p_reason text)
RETURNS void LANGUAGE sql AS $$
    UPDATE hostel.allocation SET state = 'TRANSFERRED', ended_at = now(), ended_reason = p_ended || ': ' || btrim(p_reason),
           checked_out_at = CASE WHEN state = 'CHECKED_IN' THEN now() END
     WHERE id = p_allocation AND ended_at IS NULL;
$$;

CREATE OR REPLACE FUNCTION hostel.open_moved(p_from uuid, p_state text, p_bed uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE al hostel.allocation; b hostel.bed; r hostel.room; v uuid;
BEGIN
    SELECT * INTO al FROM hostel.allocation WHERE id = p_from;
    SELECT * INTO b FROM hostel.bed WHERE id = p_bed;
    SELECT * INTO r FROM hostel.room WHERE id = b.room_id;
    INSERT INTO hostel.allocation (application_id, session, room_id, bed, bed_id, student_id, basis, draw_position, held_until, reference, confirmed_at, state,
                                   start_on, end_on, accepted_at, rules_version, checked_in_at, checked_in_by, moved_from,
                                   occupant_kind, occupant_person_id, occupant_name, category, fee_amount, fee_status, allocated_by, reason)
    VALUES (al.application_id, al.session, r.id, b.number, b.id, al.student_id, al.basis, al.draw_position, al.held_until, al.reference, al.confirmed_at, p_state,
            coalesce(al.start_on, current_date), al.end_on, al.accepted_at, al.rules_version, CASE WHEN p_state = 'CHECKED_IN' THEN now() END,
            CASE WHEN p_state = 'CHECKED_IN' THEN nullif(current_setting('moaum.actor_id', true), '')::uuid END, al.id,
            al.occupant_kind, al.occupant_person_id, al.occupant_name, r.category, al.fee_amount, al.fee_status, al.allocated_by, al.reason)
    RETURNING id INTO v;
    RETURN v;
END $$;
COMMENT ON FUNCTION hostel.open_moved(uuid, text, uuid) IS 'The new stay of a move (V291): opened on the bed in the state the stay was in, carrying its fee, fee status, category of the new room and dates, moved_from pointing back. The callers check the bed.';

CREATE OR REPLACE FUNCTION hostel.transfer(p_allocation uuid, p_bed uuid, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE al hostel.allocation; b hostel.bed; r hostel.room; h hostel.hall; st people.student; v uuid;
BEGIN
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'a transfer carries its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO al FROM hostel.allocation WHERE id = p_allocation FOR UPDATE;
    IF al.id IS NULL THEN RAISE EXCEPTION 'no such allocation' USING ERRCODE = '23503'; END IF;
    IF al.ended_at IS NOT NULL OR al.lapsed_at IS NOT NULL OR al.state NOT IN ('CONFIRMED','ACCEPTED','CHECKED_IN','HELD') THEN RAISE EXCEPTION 'allocation % is %; there is nothing to transfer', al.reference_no, lower(al.state) USING ERRCODE = '23514'; END IF;
    SELECT * INTO b FROM hostel.bed WHERE id = p_bed FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such bed' USING ERRCODE = '23503'; END IF;
    IF b.id = al.bed_id THEN RAISE EXCEPTION 'that is the bed the student already holds' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM hostel.room WHERE id = b.room_id; SELECT * INTO h FROM hostel.hall WHERE code = r.hall_code; SELECT * INTO st FROM people.student WHERE id = al.student_id;
    IF b.state <> 'AVAILABLE' THEN RAISE EXCEPTION 'bed % of room % is %', b.label, r.room_no, lower(replace(b.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
    IF r.state <> 'AVAILABLE' THEN RAISE EXCEPTION 'room % is %', r.room_no, lower(r.state) USING ERRCODE = '23514'; END IF;
    IF h.state <> 'ACTIVE' OR h.ended_on IS NOT NULL THEN RAISE EXCEPTION 'hall % is closed', h.name USING ERRCODE = '23514'; END IF;
    IF coalesce(r.sex, h.sex) IS NOT NULL AND st.sex IS NOT NULL AND coalesce(r.sex, h.sex) <> st.sex THEN RAISE EXCEPTION 'hall % is not for this student', h.name USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM hostel.allocation a WHERE a.bed_id = b.id AND a.session = al.session AND a.lapsed_at IS NULL AND a.ended_at IS NULL) THEN
        RAISE EXCEPTION 'bed % of room % is already taken', b.label, r.room_no USING ERRCODE = '23514';
    END IF;
    -- the old stay closes first, so one bed a session holds
    PERFORM hostel.close_for_move(al.id, 'TRANSFERRED', p_reason);
    v := hostel.open_moved(al.id, al.state, b.id);
    PERFORM hostel.log(al.application_id, al.id, al.student_id, h.code, al.room_id, al.bed_id, 'TRANSFERRED_OUT', al.state, 'TRANSFERRED', btrim(p_reason));
    PERFORM hostel.log(al.application_id, v, al.student_id, h.code, r.id, b.id, 'TRANSFERRED_IN', NULL, h.name || ' · ' || r.block || '-' || r.room_no || ' · ' || b.label, btrim(p_reason));
    PERFORM hostel.tell_student(al.student_id, 'Your hostel room has changed',
        'You have been moved to ' || h.name || ', Block ' || r.block || ', Room ' || r.room_no || ', ' || b.label || ' (' || btrim(p_reason) || '). The new allocation reference is ' || (SELECT reference_no FROM hostel.allocation WHERE id = v) || '; the earlier stay is kept on your record.',
        'MOAUM: hostel room changed to ' || h.name || ' ' || r.block || '-' || r.room_no || ' ' || b.label || '.');
    RETURN v;
END $$;

-- the stays moved before this migration carry what they moved from, down the chain
DO $$
DECLARE v_rows int;
BEGIN
    LOOP
        UPDATE hostel.allocation nw SET category = coalesce(nw.category, o.category),
                                        fee_amount = coalesce(nw.fee_amount, o.fee_amount),
                                        fee_status = coalesce(nw.fee_status, o.fee_status),
                                        occupant_kind = o.occupant_kind
          FROM hostel.allocation o
         WHERE o.id = nw.moved_from AND (nw.fee_status IS NULL OR nw.fee_amount IS NULL OR nw.category IS NULL) AND o.fee_status IS NOT NULL;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        EXIT WHEN v_rows = 0;
    END LOOP;
END $$;

-- ── 12 · the swap: proposed, agreed, approved, both beds moved ──────────
/* every rule a swap must meet, checked when it is proposed and again when it is approved */
CREATE OR REPLACE FUNCTION hostel.swap_check(p_a uuid, p_b uuid, p_ignore uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE a hostel.allocation; b hostel.allocation; ra hostel.room; rb hostel.room; ha hostel.hall; hb hostel.hall; sa people.student; sb people.student; fa record; fb record;
BEGIN
    SELECT * INTO a FROM hostel.allocation WHERE id = p_a;
    SELECT * INTO b FROM hostel.allocation WHERE id = p_b;
    IF a.id IS NULL OR b.id IS NULL THEN RAISE EXCEPTION 'no such allocation' USING ERRCODE = '23503'; END IF;
    IF a.session <> b.session THEN RAISE EXCEPTION 'HOSTEL_SWAP: a swap is between two stays of the same session' USING ERRCODE = '23514'; END IF;
    IF a.ended_at IS NOT NULL OR a.lapsed_at IS NOT NULL OR a.state NOT IN ('CONFIRMED', 'ACCEPTED', 'CHECKED_IN') THEN
        RAISE EXCEPTION 'HOSTEL_SWAP: allocation % is %; a swap is between two confirmed stays', a.reference_no, lower(a.state) USING ERRCODE = '23514'; END IF;
    IF b.ended_at IS NOT NULL OR b.lapsed_at IS NOT NULL OR b.state NOT IN ('CONFIRMED', 'ACCEPTED', 'CHECKED_IN') THEN
        RAISE EXCEPTION 'HOSTEL_SWAP: the other student''s allocation is %; a swap is between two confirmed stays', lower(b.state) USING ERRCODE = '23514'; END IF;
    IF a.student_id IS NULL OR b.student_id IS NULL OR a.occupant_kind <> 'STUDENT' OR b.occupant_kind <> 'STUDENT' THEN
        RAISE EXCEPTION 'HOSTEL_SWAP: a swap is between two students' USING ERRCODE = '23514'; END IF;
    IF a.room_id = b.room_id THEN RAISE EXCEPTION 'HOSTEL_SWAP: you share the room already; the porter settles who takes which bed' USING ERRCODE = '23514'; END IF;
    SELECT * INTO ra FROM hostel.room WHERE id = a.room_id; SELECT * INTO rb FROM hostel.room WHERE id = b.room_id;
    SELECT * INTO ha FROM hostel.hall WHERE code = ra.hall_code; SELECT * INTO hb FROM hostel.hall WHERE code = rb.hall_code;
    SELECT * INTO sa FROM people.student WHERE id = a.student_id; SELECT * INTO sb FROM people.student WHERE id = b.student_id;
    IF coalesce(rb.sex, hb.sex) IS NOT NULL AND sa.sex IS NOT NULL AND coalesce(rb.sex, hb.sex) <> sa.sex
       OR coalesce(ra.sex, ha.sex) IS NOT NULL AND sb.sex IS NOT NULL AND coalesce(ra.sex, ha.sex) <> sb.sex THEN
        RAISE EXCEPTION 'HOSTEL_SWAP: the halls are not for the same students' USING ERRCODE = '23514'; END IF;
    IF ha.state <> 'ACTIVE' OR hb.state <> 'ACTIVE' OR ra.state <> 'AVAILABLE' OR rb.state <> 'AVAILABLE'
       OR EXISTS (SELECT 1 FROM hostel.bed x WHERE x.id IN (a.bed_id, b.bed_id) AND x.state <> 'AVAILABLE') THEN
        RAISE EXCEPTION 'HOSTEL_SWAP: one of the rooms or beds is out of service' USING ERRCODE = '23514'; END IF;
    IF ra.category <> rb.category THEN
        RAISE EXCEPTION 'HOSTEL_SWAP: the rooms are of different categories (% and %); only the Dean moves a student between them', lower(ra.category), lower(rb.category) USING ERRCODE = '23514'; END IF;
    -- the fee each would carry on the other's bed is what each already carries: nobody pays more or less by swapping
    SELECT * INTO fa FROM hostel.fee_for(a.session, rb.hall_code, rb.room_type, rb.category, sa.current_level);
    SELECT * INTO fb FROM hostel.fee_for(b.session, ra.hall_code, ra.room_type, ra.category, sb.current_level);
    IF coalesce(fa.amount, 0) <> coalesce(a.fee_amount, 0) OR coalesce(fb.amount, 0) <> coalesce(b.fee_amount, 0)
       OR coalesce(a.fee_status, 'PAYABLE') <> coalesce(b.fee_status, 'PAYABLE') THEN
        RAISE EXCEPTION 'HOSTEL_SWAP_FEE_DIFFERS: the two beds do not carry the same hostel fee; ask for a transfer instead' USING ERRCODE = '23514'; END IF;
    IF coalesce(a.fee_status, 'PAYABLE') = 'PAYABLE' THEN RAISE EXCEPTION 'HOSTEL_SWAP: the hostel fee is paid before a bed is swapped' USING ERRCODE = '23514'; END IF;
    IF a.checkout_requested_at IS NOT NULL OR b.checkout_requested_at IS NOT NULL
       OR EXISTS (SELECT 1 FROM hostel.clearance c WHERE c.allocation_id IN (a.id, b.id)) THEN
        RAISE EXCEPTION 'HOSTEL_SWAP: a student who is checking out does not swap' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM hostel.transfer_request t WHERE t.allocation_id IN (a.id, b.id) AND t.state IN ('SUBMITTED', 'UNDER_REVIEW')) THEN
        RAISE EXCEPTION 'HOSTEL_SWAP: a transfer request is waiting; withdraw it or wait for its decision' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM hostel.swap_request w WHERE w.state IN ('PROPOSED', 'AGREED') AND w.id IS DISTINCT FROM p_ignore
                  AND (w.allocation_id IN (a.id, b.id) OR w.partner_allocation IN (a.id, b.id))) THEN
        RAISE EXCEPTION 'HOSTEL_SWAP: one of you already has a swap waiting' USING ERRCODE = '23514'; END IF;
END $$;

CREATE OR REPLACE FUNCTION hostel.propose_swap(p_student uuid, p_session text, p_partner_number text, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE a hostel.allocation; b hostel.allocation; pt people.student; me people.student; v uuid; v_ref text; rb hostel.room; hb hostel.hall; ra hostel.room; ha hostel.hall;
BEGIN
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'HOSTEL_SWAP: say why you wish to swap' USING ERRCODE = '23514'; END IF;
    SELECT * INTO pt FROM people.student WHERE upper(matric_no) = upper(btrim(p_partner_number)) OR upper(admission_no) = upper(btrim(p_partner_number)) LIMIT 1;
    IF pt.id IS NULL THEN RAISE EXCEPTION 'HOSTEL_SWAP: no student is numbered %', btrim(p_partner_number) USING ERRCODE = '23514'; END IF;
    IF pt.id = p_student THEN RAISE EXCEPTION 'HOSTEL_SWAP: name the student you would swap with, not yourself' USING ERRCODE = '23514'; END IF;
    SELECT * INTO a FROM hostel.allocation WHERE student_id = p_student AND session = p_session AND lapsed_at IS NULL AND ended_at IS NULL;
    IF a.id IS NULL THEN RAISE EXCEPTION 'HOSTEL_SWAP: no bed stands against you for %', p_session USING ERRCODE = '23514'; END IF;
    SELECT * INTO b FROM hostel.allocation WHERE student_id = pt.id AND session = p_session AND lapsed_at IS NULL AND ended_at IS NULL;
    IF b.id IS NULL THEN RAISE EXCEPTION 'HOSTEL_SWAP: % holds no bed for %', btrim(p_partner_number), p_session USING ERRCODE = '23514'; END IF;
    PERFORM hostel.swap_check(a.id, b.id, NULL);
    INSERT INTO hostel.swap_request (session, student_id, allocation_id, partner_id, partner_allocation, reason)
    VALUES (p_session, p_student, a.id, pt.id, b.id, btrim(p_reason)) RETURNING id, reference INTO v, v_ref;
    SELECT * INTO me FROM people.student WHERE id = p_student;
    SELECT * INTO ra FROM hostel.room WHERE id = a.room_id; SELECT * INTO ha FROM hostel.hall WHERE code = ra.hall_code;
    SELECT * INTO rb FROM hostel.room WHERE id = b.room_id; SELECT * INTO hb FROM hostel.hall WHERE code = rb.hall_code;
    PERFORM hostel.log(a.application_id, a.id, p_student, ha.code, ra.id, a.bed_id, 'SWAP_PROPOSED', ha.name || ' ' || ra.block || '-' || ra.room_no, hb.name || ' ' || rb.block || '-' || rb.room_no, v_ref || ': ' || btrim(p_reason));
    PERFORM hostel.log(b.application_id, b.id, pt.id, hb.code, rb.id, b.bed_id, 'SWAP_PROPOSED_TO_YOU', hb.name || ' ' || rb.block || '-' || rb.room_no, ha.name || ' ' || ra.block || '-' || ra.room_no, v_ref);
    PERFORM hostel.tell_student(pt.id, 'A room swap is proposed to you',
        me.surname || ', ' || me.other_names || ' (' || coalesce(me.matric_no, me.admission_no, '') || '), in ' || ha.name || ', Block ' || ra.block || ', Room ' || ra.room_no
        || ', proposes to exchange beds with you (' || v_ref || '). Agree or decline it under Hostel on the portal; nothing moves unless you agree and the Dean of Student Affairs approves.',
        'MOAUM: room swap ' || v_ref || ' proposed to you. Answer it on the portal.');
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION hostel.answer_swap(p_swap uuid, p_student uuid, p_agree boolean, p_note text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE w hostel.swap_request;
BEGIN
    SELECT * INTO w FROM hostel.swap_request WHERE id = p_swap FOR UPDATE;
    IF w.id IS NULL OR w.partner_id <> p_student THEN RAISE EXCEPTION 'no such swap' USING ERRCODE = '23503'; END IF;
    IF w.state <> 'PROPOSED' THEN RAISE EXCEPTION 'HOSTEL_SWAP: swap % is %', w.reference, lower(w.state) USING ERRCODE = '23514'; END IF;
    IF p_agree THEN
        PERFORM hostel.swap_check(w.allocation_id, w.partner_allocation, w.id);
        UPDATE hostel.swap_request SET state = 'AGREED', answered_at = now(), partner_note = nullif(btrim(coalesce(p_note, '')), '') WHERE id = w.id;
        PERFORM hostel.log(NULL, w.partner_allocation, p_student, NULL, NULL, NULL, 'SWAP_AGREED', 'PROPOSED', 'AGREED', w.reference);
        PERFORM hostel.tell_student(w.student_id, 'Your room swap is agreed', 'The other student has agreed to swap ' || w.reference || '. It is with the Dean of Student Affairs for approval.', 'MOAUM: swap ' || w.reference || ' agreed; awaiting the Dean.');
        PERFORM hostel.tell_dean('A room swap waits for approval', 'Two students have agreed to exchange beds under ' || w.reference || ': ' || w.reason);
    ELSE
        UPDATE hostel.swap_request SET state = 'DECLINED', answered_at = now(), partner_note = nullif(btrim(coalesce(p_note, '')), '') WHERE id = w.id;
        PERFORM hostel.log(NULL, w.partner_allocation, p_student, NULL, NULL, NULL, 'SWAP_DECLINED', 'PROPOSED', 'DECLINED', w.reference);
        PERFORM hostel.tell_student(w.student_id, 'Your room swap was declined', 'The other student declined swap ' || w.reference || '. Your bed is unchanged.', 'MOAUM: swap ' || w.reference || ' declined.');
    END IF;
END $$;

CREATE OR REPLACE FUNCTION hostel.cancel_swap(p_swap uuid, p_student uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE w hostel.swap_request;
BEGIN
    SELECT * INTO w FROM hostel.swap_request WHERE id = p_swap FOR UPDATE;
    IF w.id IS NULL OR p_student NOT IN (w.student_id, w.partner_id) THEN RAISE EXCEPTION 'no such swap' USING ERRCODE = '23503'; END IF;
    IF w.state NOT IN ('PROPOSED', 'AGREED') THEN RAISE EXCEPTION 'HOSTEL_SWAP: swap % is %', w.reference, lower(w.state) USING ERRCODE = '23514'; END IF;
    UPDATE hostel.swap_request SET state = 'CANCELLED', decided_at = now(), decision_note = 'Withdrawn by a student' WHERE id = w.id;
    PERFORM hostel.log(NULL, w.allocation_id, p_student, NULL, NULL, NULL, 'SWAP_CANCELLED', w.state, 'CANCELLED', w.reference);
    PERFORM hostel.tell_student(CASE WHEN p_student = w.student_id THEN w.partner_id ELSE w.student_id END, 'A room swap was withdrawn', 'Swap ' || w.reference || ' has been withdrawn. Your bed is unchanged.', 'MOAUM: swap ' || w.reference || ' withdrawn.');
END $$;

CREATE OR REPLACE FUNCTION hostel.decide_swap(p_swap uuid, p_decision text, p_note text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE w hostel.swap_request; a hostel.allocation; b hostel.allocation; ba hostel.bed; bb hostel.bed; ra hostel.room; rb hostel.room; ha hostel.hall; hb hostel.hall;
        na uuid; nb uuid; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_dec text := upper(coalesce(p_decision, ''));
BEGIN
    SELECT * INTO w FROM hostel.swap_request WHERE id = p_swap FOR UPDATE;
    IF w.id IS NULL THEN RAISE EXCEPTION 'no such swap' USING ERRCODE = '23503'; END IF;
    IF w.state <> 'AGREED' THEN RAISE EXCEPTION 'HOSTEL_SWAP: swap % is %; the Dean decides a swap both students have agreed', w.reference, lower(w.state) USING ERRCODE = '23514'; END IF;
    IF v_dec = 'REJECTED' THEN
        IF nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN RAISE EXCEPTION 'HOSTEL_SWAP: say why the swap is refused' USING ERRCODE = '23514'; END IF;
        UPDATE hostel.swap_request SET state = 'REJECTED', decided_by = who, decided_at = now(), decision_note = btrim(p_note) WHERE id = w.id;
        PERFORM hostel.log(NULL, w.allocation_id, w.student_id, NULL, NULL, NULL, 'SWAP_REJECTED', 'AGREED', 'REJECTED', w.reference || ': ' || btrim(p_note));
        PERFORM hostel.tell_student(w.student_id, 'Your room swap was not approved', 'Swap ' || w.reference || ' was not approved: ' || btrim(p_note) || '.', 'MOAUM: swap ' || w.reference || ' not approved.');
        PERFORM hostel.tell_student(w.partner_id, 'Your room swap was not approved', 'Swap ' || w.reference || ' was not approved: ' || btrim(p_note) || '.', 'MOAUM: swap ' || w.reference || ' not approved.');
        RETURN;
    END IF;
    IF v_dec <> 'APPROVED' THEN RAISE EXCEPTION 'HOSTEL_SWAP: a swap is approved or rejected' USING ERRCODE = '23514'; END IF;
    -- both stays locked in a fixed order, so two decisions at once cannot each hold one
    PERFORM 1 FROM hostel.allocation WHERE id IN (w.allocation_id, w.partner_allocation) ORDER BY id FOR UPDATE;
    PERFORM hostel.swap_check(w.allocation_id, w.partner_allocation, w.id);
    SELECT * INTO a FROM hostel.allocation WHERE id = w.allocation_id;
    SELECT * INTO b FROM hostel.allocation WHERE id = w.partner_allocation;
    -- both close before either opens: each bed is free for the other in the same transaction
    PERFORM hostel.close_for_move(a.id, 'SWAPPED', w.reference);
    PERFORM hostel.close_for_move(b.id, 'SWAPPED', w.reference);
    na := hostel.open_moved(a.id, a.state, b.bed_id);
    nb := hostel.open_moved(b.id, b.state, a.bed_id);
    UPDATE hostel.swap_request SET state = 'COMPLETED', decided_by = who, decided_at = now(), decision_note = nullif(btrim(coalesce(p_note, '')), ''), new_allocation = na, new_partner_allocation = nb WHERE id = w.id;
    SELECT * INTO ba FROM hostel.bed WHERE id = b.bed_id; SELECT * INTO rb FROM hostel.room WHERE id = b.room_id; SELECT * INTO hb FROM hostel.hall WHERE code = rb.hall_code;
    SELECT * INTO bb FROM hostel.bed WHERE id = a.bed_id; SELECT * INTO ra FROM hostel.room WHERE id = a.room_id; SELECT * INTO ha FROM hostel.hall WHERE code = ra.hall_code;
    PERFORM hostel.log(a.application_id, a.id, a.student_id, ha.code, ra.id, a.bed_id, 'SWAPPED_OUT', a.state, 'TRANSFERRED', w.reference);
    PERFORM hostel.log(a.application_id, na, a.student_id, hb.code, rb.id, b.bed_id, 'SWAPPED_IN', NULL, hb.name || ' · ' || rb.block || '-' || rb.room_no || ' · ' || ba.label, w.reference);
    PERFORM hostel.log(b.application_id, b.id, b.student_id, hb.code, rb.id, b.bed_id, 'SWAPPED_OUT', b.state, 'TRANSFERRED', w.reference);
    PERFORM hostel.log(b.application_id, nb, b.student_id, ha.code, ra.id, a.bed_id, 'SWAPPED_IN', NULL, ha.name || ' · ' || ra.block || '-' || ra.room_no || ' · ' || bb.label, w.reference);
    PERFORM hostel.tell_student(a.student_id, 'Your room swap is approved',
        'Swap ' || w.reference || ' is approved. Your bed is now ' || hb.name || ', Block ' || rb.block || ', Room ' || rb.room_no || ', ' || ba.label || '; the new allocation reference is ' || (SELECT reference_no FROM hostel.allocation WHERE id = na) || '. Hand in your old key at the porter''s lodge.',
        'MOAUM: swap ' || w.reference || ' approved. Your bed: ' || hb.name || ' ' || rb.block || '-' || rb.room_no || ' ' || ba.label || '.');
    PERFORM hostel.tell_student(b.student_id, 'Your room swap is approved',
        'Swap ' || w.reference || ' is approved. Your bed is now ' || ha.name || ', Block ' || ra.block || ', Room ' || ra.room_no || ', ' || bb.label || '; the new allocation reference is ' || (SELECT reference_no FROM hostel.allocation WHERE id = nb) || '. Hand in your old key at the porter''s lodge.',
        'MOAUM: swap ' || w.reference || ' approved. Your bed: ' || ha.name || ' ' || ra.block || '-' || ra.room_no || ' ' || bb.label || '.');
END $$;
COMMENT ON FUNCTION hostel.decide_swap(uuid, text, text) IS 'The Dean approves or refuses a swap both students have agreed (V291): on approval every rule is checked again, both stays closed and each reopened on the other''s bed in one transaction.';

-- ── 13 · what the desk and the student read ─────────────────────────────
CREATE OR REPLACE FUNCTION hostel.discipline_register(p_session text)
RETURNS TABLE(incident_id uuid, reference text, session text, student_id uuid, student_name text, student_number text, sex text, programme text,
              hall_name text, block text, room_no text, kind text, kind_label text, occurred_at timestamptz, place text, description text, witnesses text,
              reported_by text, reported_office text, reported_at timestamptz, statement text, statement_at timestamptz, state text, decided_at timestamptz, decision_note text,
              sanctions jsonb, prior_incidents int)
LANGUAGE sql STABLE AS $$
    SELECT i.id, i.reference, i.session, i.student_id, st.surname || ', ' || st.other_names, coalesce(st.matric_no, st.admission_no), st.sex, p.name,
           h.name, r.block, r.room_no, i.kind, k.label, i.occurred_at, i.place, i.description, i.witnesses,
           coalesce(rp.surname || ', ' || rp.given_names, ''), i.reported_office, i.reported_at, i.statement, i.statement_at, i.state, i.decided_at, i.decision_note,
           coalesce((SELECT jsonb_agg(jsonb_build_object('id', s.id, 'reference', s.reference, 'kind', s.kind, 'amount', s.amount, 'payment_ref', s.payment_ref, 'settled_at', s.settled_at,
                                                       'waived_at', s.waived_at, 'barred_until', s.barred_until, 'vacate_by', s.vacate_by, 'effect', s.effect, 'reason', s.reason, 'state', s.state,
                                                       'decided_at', s.decided_at, 'appeal_by', s.appeal_by, 'appeal_state', s.appeal_state, 'appeal_ground', s.appeal_ground,
                                                       'appealed_at', s.appealed_at, 'appeal_note', s.appeal_note, 'appeal_decided_at', s.appeal_decided_at) ORDER BY s.decided_at)
                       FROM hostel.sanction s WHERE s.incident_id = i.id), '[]'::jsonb),
           (SELECT count(*)::int FROM hostel.incident x WHERE x.student_id = i.student_id AND x.id <> i.id AND x.reported_at < i.reported_at AND x.state <> 'DISMISSED')
      FROM hostel.incident i
      JOIN people.student st ON st.id = i.student_id
      JOIN hostel.incident_kind k ON k.code = i.kind
      LEFT JOIN ref.programme p ON p.code = st.programme_code
      LEFT JOIN hostel.hall h ON h.code = i.hall_code
      LEFT JOIN hostel.room r ON r.id = i.room_id
      LEFT JOIN iam.person rp ON rp.id = i.reported_by
     WHERE i.session = p_session
     ORDER BY i.reported_at DESC
$$;
COMMENT ON FUNCTION hostel.discipline_register(text) IS 'Every hostel incident of a session (V291), with the student''s account, each sanction and its appeal, and how many earlier incidents stand against the student.';

CREATE OR REPLACE FUNCTION hostel.swaps(p_session text)
RETURNS TABLE(id uuid, reference text, session text, state text, reason text, proposed_at timestamptz, answered_at timestamptz, partner_note text, decided_at timestamptz, decision_note text,
              student_id uuid, student_name text, student_number text, student_room text, student_bed text,
              partner_id uuid, partner_name text, partner_number text, partner_room text, partner_bed text, category text, fee_amount numeric, fee_status text)
LANGUAGE sql STABLE AS $$
    SELECT w.id, w.reference, w.session, w.state, w.reason, w.proposed_at, w.answered_at, w.partner_note, w.decided_at, w.decision_note,
           w.student_id, sa.surname || ', ' || sa.other_names, coalesce(sa.matric_no, sa.admission_no), ha.name || ' · ' || ra.block || '-' || ra.room_no, ba.label,
           w.partner_id, sb.surname || ', ' || sb.other_names, coalesce(sb.matric_no, sb.admission_no), hb.name || ' · ' || rb.block || '-' || rb.room_no, bb.label,
           ra.category, a.fee_amount, a.fee_status
      FROM hostel.swap_request w
      JOIN hostel.allocation a ON a.id = w.allocation_id JOIN hostel.allocation b ON b.id = w.partner_allocation
      JOIN people.student sa ON sa.id = w.student_id JOIN people.student sb ON sb.id = w.partner_id
      JOIN hostel.room ra ON ra.id = a.room_id JOIN hostel.hall ha ON ha.code = ra.hall_code LEFT JOIN hostel.bed ba ON ba.id = a.bed_id
      JOIN hostel.room rb ON rb.id = b.room_id JOIN hostel.hall hb ON hb.code = rb.hall_code LEFT JOIN hostel.bed bb ON bb.id = b.bed_id
     WHERE w.session = p_session
     ORDER BY (w.state = 'AGREED') DESC, (w.state = 'PROPOSED') DESC, w.proposed_at DESC
$$;

-- ── 14 · the Bursar's figures: fines are not accommodation revenue ──────
CREATE OR REPLACE FUNCTION hostel.finance_summary(p_session text)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
    WITH live AS (
        SELECT al.*, r.hall_code, h.name AS hall_name, coalesce(al.category, r.category) AS cat
          FROM hostel.allocation al JOIN hostel.room r ON r.id = al.room_id JOIN hostel.hall h ON h.code = r.hall_code
         WHERE al.session = p_session AND al.lapsed_at IS NULL AND al.ended_at IS NULL),
        tx AS (SELECT count(*) AS n, coalesce(sum(pr.amount), 0) AS amount FROM finance.payment_reference pr
                WHERE pr.session = p_session AND pr.confirmed_at IS NOT NULL AND pr.purpose ~* '^hostel accommodation(?! damage| fine)'),
        fines AS (SELECT * FROM hostel.sanction WHERE session = p_session AND kind = 'FINE')
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
            'refunds', 0,
            'fines_imposed', coalesce((SELECT sum(amount) FROM fines WHERE state = 'IN_FORCE'), 0),
            'fines_paid', coalesce((SELECT sum(amount) FROM fines WHERE settled_at IS NOT NULL), 0),
            'fines_outstanding', coalesce((SELECT sum(amount) FROM fines WHERE state = 'IN_FORCE' AND settled_at IS NULL AND waived_at IS NULL), 0),
            'fines_waived', coalesce((SELECT sum(amount) FROM fines WHERE waived_at IS NOT NULL AND settled_at IS NULL), 0)),
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
COMMENT ON FUNCTION hostel.finance_summary(text) IS 'The Bursar''s hostel figures for a session (V290): charges, paid, outstanding, exempt (no charge, never revenue), by hostel, category and status; and, apart from them, the disciplinary fines imposed, paid, outstanding and waived (V291).';

COMMIT;
