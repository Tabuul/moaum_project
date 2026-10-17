-- ═══════════════════════════════════════
-- V512 — A GST or EPS carry-over waits for the GST fee, as every GST and EPS course does
--
--   A carry-over that runs in the semester is put on the student's registration by the engine itself (registration.student_draft,
--   and again on every save, registration.student_choose) — with no look at the GST fee. A student who failed GST 301 and owes the
--   GST fee had GST 301 put on the draft unpaid, and the submission then refused the whole registration for it (the GST fee check of
--   registration.submit_checks), while the student could not take a carry-over off.
--
--   Now a carry-over that is a GST or EPS course (catalogue.course kind GST) is held, like any GST or EPS course, while the GST fee
--   the student owes is not paid (registration.gst_gate, read from confirmed payments only — finance.gst_entitlement):
--     · registration.gst_course_hold — the gate's word for a GST/EPS course, NULL for any other;
--     · registration.student_draft and registration.student_choose put a held GST/EPS carry-over on the draft only once the fee is
--       paid (one already there, put on before, comes off a draft while the fee is owed); the student's other courses go on as the
--       rule allows (finance.gst_setting.required_for_all still holds the whole registration where the Bursary set it);
--     · registration.student_add_other (V504) refuses a held GST/EPS carry-over with GST_PAYMENT_REQUIRED, a carry-over named as
--       such; once the payment is confirmed the student registers it from the course registration screen, no ICT Support;
--     · registration.student_add (add and drop) as before (V504 already holds every course on the gate);
--     · registration.gst_course_event — the GST/EPS registration log: <GST|EPS>_PAYMENT_REQUIRED_FOR_REGISTRATION,
--       _PAYMENT_VERIFIED (the first time the registration reads the confirmed payment, per student and session),
--       _CARRY_OVER_REGISTRATION_ATTEMPTED, _CARRY_OVER_REGISTRATION_BLOCKED (both from the API: a refused attempt rolls back) and
--       _CARRY_OVER_REGISTERED; written once. The entry itself, and the payment's confirmation, stay on the audit spine.
--
--   The order is unchanged: a GST/EPS carry-over is listed under carry-over (registration.entry_rank), its GST/EPS classification
--   kept on the course for the fee, the permit (V492: kind GST, any entry type) and the reports.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V512: a GST or EPS carry-over waits for the GST fee, as every GST and EPS course does', true);

-- ── the gate's word for a GST/EPS course ──
CREATE FUNCTION registration.gst_course_hold(p_student uuid, p_session text, p_course text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN c.kind = 'GST' THEN registration.gst_gate(p_student, p_session, c.code) END
      FROM catalogue.course c WHERE c.code = p_course
$$;
COMMENT ON FUNCTION registration.gst_course_hold(uuid, text, text) IS
  'V512: why a GST or EPS course (catalogue.course kind GST) is held from the student''s registration — the GST fee owed and not paid (registration.gst_gate) — or NULL; NULL for any other course, which the whole-registration rule alone may hold';

-- ── the GST/EPS registration log ──
CREATE TABLE registration.gst_course_event (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id   uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    session      text NOT NULL,
    semester     integer NULL,
    course_code  text NULL,
    office       text NOT NULL CHECK (office IN ('GST', 'EPS')),
    carry_over   boolean NOT NULL DEFAULT false,
    event        text NOT NULL CHECK (event IN (
        'GST_PAYMENT_REQUIRED_FOR_REGISTRATION', 'GST_PAYMENT_VERIFIED', 'GST_CARRY_OVER_REGISTRATION_ATTEMPTED',
        'GST_CARRY_OVER_REGISTRATION_BLOCKED', 'GST_CARRY_OVER_REGISTERED',
        'EPS_PAYMENT_REQUIRED_FOR_REGISTRATION', 'EPS_PAYMENT_VERIFIED', 'EPS_CARRY_OVER_REGISTRATION_ATTEMPTED',
        'EPS_CARRY_OVER_REGISTRATION_BLOCKED', 'EPS_CARRY_OVER_REGISTERED')),
    detail       text NULL,
    actor_id     uuid NULL,
    actor_office text NULL,
    at           timestamptz NOT NULL DEFAULT clock_timestamp()   -- the moment itself: an attempt is logged in its own transaction beside the one it attempts
);
CREATE INDEX ix_gst_course_event ON registration.gst_course_event (student_id, session, at);
CREATE INDEX ix_gst_course_event_kind ON registration.gst_course_event (event, at);
COMMENT ON TABLE registration.gst_course_event IS
  'V512: the GST/EPS registration log — the payment the registration needs and reads, and each GST/EPS carry-over attempted, blocked and registered; written once (the entry and the payment''s confirmation are on the audit spine)';
SELECT audit.exempt('registration.gst_course_event',
    'The log of GST/EPS registration attempts and holds, written once; the registration''s entries and the payment''s confirmation are on the spine.');

CREATE FUNCTION registration.gst_course_event_written_once()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'GST_COURSE_EVENT_WRITTEN_ONCE: the GST/EPS registration log is written once' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_gst_course_event_once BEFORE UPDATE ON registration.gst_course_event
    FOR EACH ROW EXECUTE FUNCTION registration.gst_course_event_written_once();

-- one event: the course's office (GST, or EPS) names it; the payment read is noted once a student and session
CREATE FUNCTION registration.gst_course_event(p_student uuid, p_session text, p_semester integer, p_course text, p_carry boolean, p_what text, p_detail text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_office text; v_event text;
BEGIN
    SELECT CASE WHEN c.general_office = 'EPS' THEN 'EPS' ELSE 'GST' END INTO v_office FROM catalogue.course c WHERE c.code = p_course AND c.kind = 'GST';
    IF v_office IS NULL THEN RETURN; END IF;
    v_event := v_office || '_' || p_what;
    IF p_what = 'PAYMENT_VERIFIED' AND EXISTS (SELECT 1 FROM registration.gst_course_event e
                                                WHERE e.student_id = p_student AND e.session = p_session AND e.event = v_event) THEN
        RETURN;
    END IF;
    INSERT INTO registration.gst_course_event (student_id, session, semester, course_code, office, carry_over, event, detail, actor_id, actor_office)
    VALUES (p_student, p_session, p_semester, p_course, v_office, coalesce(p_carry, false), v_event, p_detail,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
END $$;
COMMENT ON FUNCTION registration.gst_course_event(uuid, text, integer, text, boolean, text, text) IS
  'V512: one entry of the GST/EPS registration log for a GST/EPS course — PAYMENT_REQUIRED_FOR_REGISTRATION, PAYMENT_VERIFIED (once a student and session), CARRY_OVER_REGISTRATION_ATTEMPTED, CARRY_OVER_REGISTRATION_BLOCKED, CARRY_OVER_REGISTERED — named by the course''s office; nothing for another course';

-- a GST/EPS course just put on a registration: a carry-over registered, and the confirmed payment the registration read
CREATE FUNCTION registration.gst_course_registered(p_registration uuid, p_offering uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    SELECT cr.student_id, cr.session, cr.semester, c.code, e.entry_type INTO r
      FROM registration.course_registration cr
      JOIN registration.entry e ON e.registration_id = cr.id AND e.offering_id = p_offering
      JOIN catalogue.offering o ON o.id = e.offering_id
      JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST'
     WHERE cr.id = p_registration;
    IF NOT FOUND THEN RETURN; END IF;
    IF r.entry_type IN ('CARRYOVER', 'DEFERRED') THEN
        PERFORM registration.gst_course_event(r.student_id, r.session, r.semester, r.code, true, 'CARRY_OVER_REGISTERED');
    END IF;
    IF EXISTS (SELECT 1 FROM finance.gst_entitlement(r.student_id, r.session) g WHERE g.required AND g.entitled) THEN
        PERFORM registration.gst_course_event(r.student_id, r.session, r.semester, r.code, r.entry_type IN ('CARRYOVER', 'DEFERRED'), 'PAYMENT_VERIFIED');
    END IF;
END $$;

-- ── the draft: the carry-overs and deferred courses, a GST/EPS one only once the GST fee is paid ──
CREATE OR REPLACE FUNCTION registration.student_draft(p_student uuid, p_session text, p_semester integer)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
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
        -- V512: a GST/EPS carry-over waits for the GST fee: being a carry-over does not pass it
        IF registration.gst_course_hold(p_student, p_session, m.course_code) IS NOT NULL THEN CONTINUE; END IF;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (v, m.offering_id, m.units, CASE WHEN m.deferred THEN 'DEFERRED' ELSE 'CARRYOVER' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        IF FOUND THEN PERFORM registration.gst_course_registered(v, m.offering_id); END IF;
    END LOOP;
    RETURN v;
END $function$;

-- ── saving the draft (V504): a GST/EPS carry-over goes on, and stays, only once the GST fee is paid ──
CREATE OR REPLACE FUNCTION registration.student_choose(p_registration uuid, p_offerings uuid[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; m record; n int := 0; v_gate text; v_unmet text[];
        v_added jsonb; v_menu uuid[]; v_code text; ctx record; v_ctx boolean := false; x record; v_units int;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status NOT IN ('DRAFT','RETURNED') THEN
        RAISE EXCEPTION 'this registration is %; it is not edited', lower(r.status) USING ERRCODE = '23514',
            HINT = 'A submitted registration is changed by the level adviser returning it.';
    END IF;
    -- V504: when each course the student added beside the menu was first added, kept across saves
    SELECT coalesce(jsonb_object_agg(e.offering_id::text, e.student_added_at), '{}'::jsonb) INTO v_added
      FROM registration.entry e WHERE e.registration_id = p_registration AND e.student_added_at IS NOT NULL;
    DELETE FROM registration.entry WHERE registration_id = p_registration AND entry_type NOT IN ('CARRYOVER','DEFERRED') AND support_override_at IS NULL;
    -- V512: a GST/EPS carry-over put on the draft before the GST fee was paid comes off it while the fee is owed (not one ICT Support
    -- put on the student's ticket)
    DELETE FROM registration.entry e USING catalogue.offering o
     WHERE e.registration_id = p_registration AND o.id = e.offering_id AND e.entry_type IN ('CARRYOVER', 'DEFERRED') AND e.support_override_at IS NULL
       AND registration.gst_course_hold(r.student_id, r.session, o.course_code) IS NOT NULL;
    -- a deferred course or a carry-over that has since become due is added to a draft that predates it — a GST/EPS one once the fee is paid
    FOR m IN SELECT * FROM registration.student_menu(r.student_id, r.session, r.semester) WHERE carryover LOOP
        IF registration.gst_course_hold(r.student_id, r.session, m.course_code) IS NOT NULL THEN CONTINUE; END IF;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (p_registration, m.offering_id, m.units, CASE WHEN m.deferred THEN 'DEFERRED' ELSE 'CARRYOVER' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        IF FOUND THEN PERFORM registration.gst_course_registered(p_registration, m.offering_id); END IF;
    END LOOP;
    SELECT coalesce(array_agg(mm.offering_id), '{}'::uuid[]) INTO v_menu FROM registration.student_menu(r.student_id, r.session, r.semester) mm;
    FOR m IN SELECT * FROM registration.student_menu(r.student_id, r.session, r.semester) WHERE NOT carryover AND offering_id = ANY(p_offerings) LOOP
        -- V314: a GST or EPS course is registered only by a student whose GST fee is paid
        v_gate := registration.gst_gate(r.student_id, r.session, m.course_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; registration opens the moment the payment is confirmed.';
        END IF;
        -- V482: where the Academic Office enforces prerequisites, a course whose prerequisite the student has not passed is refused
        IF registration.prerequisite_mode() = 'ENFORCED' THEN
            v_unmet := registration.prerequisites_unmet(r.student_id, m.course_code);
            IF cardinality(v_unmet) > 0 THEN
                RAISE EXCEPTION 'REG_PREREQUISITE: % needs % passed first; no published pass is on your record', m.course_code, array_to_string(v_unmet, ', ')
                    USING ERRCODE = '23514', HINT = 'If you passed it and the result is not yet published, or were exempted, your department asks ICT Support to add the course on your ticket.';
            END IF;
        END IF;
        -- V504: the programme's own setup (course_offer.basis) types it, as registration.is_elective_for reads it — a course the
        -- programme takes as core is core here though its own department offers it as an elective
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (p_registration, m.offering_id, m.units,
                CASE WHEN m.basis = 'GST' OR m.kind = 'GST' THEN 'GST' WHEN m.basis = 'Borrowed' THEN 'BORROWED'
                     WHEN m.basis = 'Elective' OR (m.basis IS NULL AND m.kind = 'Elective') THEN 'ELECTIVE' ELSE 'CURRENT' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        IF FOUND AND m.kind = 'GST' THEN PERFORM registration.gst_course_registered(p_registration, m.offering_id); END IF;
        n := n + 1;
    END LOOP;
    -- V504: a course beside the menu is kept only when the engine still allows it (registration.course_check); the record is
    -- read once for all of them
    FOR v_code IN SELECT o.course_code FROM catalogue.offering o
                   WHERE o.id = ANY (p_offerings) AND NOT o.id = ANY (v_menu)
                     AND NOT EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = p_registration AND e.offering_id = o.id)
                   ORDER BY o.course_code LOOP
        IF NOT v_ctx THEN SELECT * INTO ctx FROM registration.course_context(r.student_id, r.session, r.semester); v_ctx := true; END IF;
        SELECT * INTO x FROM registration.course_check(r.student_id, r.session, r.semester, v_code, ctx.passed, ctx.awaited, ctx.carry, ctx.other_semester);
        IF x.refusal IS NOT NULL THEN
            RAISE EXCEPTION '%', x.refusal USING ERRCODE = '23514', HINT = 'Remove ' || v_code || ' from your selection and save again.';
        END IF;
        IF NOT x.offering_id = ANY (p_offerings) THEN CONTINUE; END IF;   -- another stream's class of the course: not the student's
        -- V314: the GST fee owed holds every course the student registers, as on the menu (registration.gst_gate)
        v_gate := registration.gst_gate(r.student_id, r.session, v_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; registration opens the moment the payment is confirmed.';
        END IF;
        SELECT catalogue.units_for(v_code, s.programme_code, NULL) INTO v_units FROM people.student s WHERE s.id = r.student_id;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, student_added_at, added_as)
        VALUES (p_registration, x.offering_id, v_units,
                CASE x.category WHEN 'CARRY_OVER' THEN 'CARRYOVER' WHEN 'GST' THEN 'GST' WHEN 'ELECTIVE' THEN 'ELECTIVE' ELSE 'CURRENT' END,
                coalesce((v_added ->> x.offering_id::text)::timestamptz, now()), x.added_as)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        IF FOUND THEN PERFORM registration.gst_course_registered(p_registration, x.offering_id); END IF;
        n := n + 1;
    END LOOP;
    RETURN registration.units_of(p_registration);
END $function$;

-- ── the student adds a course (V504): a GST/EPS carry-over refused while the GST fee is owed ──
CREATE OR REPLACE FUNCTION registration.student_add_other(p_student uuid, p_session text, p_semester integer, p_offering uuid)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_reg uuid; r registration.course_registration; m record; x record; v_gate text; v_unmet text[]; v_type text; v_code text;
BEGIN
    v_reg := registration.student_draft(p_student, p_session, p_semester);
    SELECT * INTO r FROM registration.course_registration WHERE id = v_reg FOR UPDATE;   -- one add at a time on a registration
    IF r.status NOT IN ('DRAFT', 'RETURNED') THEN
        RAISE EXCEPTION 'REG_NOT_EDITABLE: this registration is %; a course is added to it during add and drop', lower(r.status) USING ERRCODE = '23514';
    END IF;
    SELECT o.course_code INTO v_code FROM catalogue.offering o WHERE o.id = p_offering;
    IF EXISTS (SELECT 1 FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id
                WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN') AND o.course_code = v_code) THEN
        RAISE EXCEPTION 'REG_ALREADY_ADDED: Course already added' USING ERRCODE = '23514';
    END IF;
    -- a course of the menu is added as choosing it adds it
    SELECT * INTO m FROM registration.student_menu(p_student, p_session, p_semester) mm WHERE mm.offering_id = p_offering LIMIT 1;
    IF FOUND THEN
        -- V512: a GST/EPS carry-over waits for the GST fee: being a carry-over does not pass it
        IF m.carryover THEN
            v_gate := registration.gst_course_hold(p_student, p_session, m.course_code);
            IF v_gate IS NOT NULL THEN
                RAISE EXCEPTION 'GST_PAYMENT_REQUIRED: % is a carry-over % course, and a carry-over does not pass the GST fee — %', m.course_code,
                    CASE WHEN m.course_code LIKE 'EPS%' THEN 'EPS' ELSE 'GST' END, regexp_replace(v_gate, '^GST_PAYMENT_REQUIRED: ', '')
                    USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; the carry-over can be registered the moment the payment is confirmed.';
            END IF;
        END IF;
        IF NOT m.carryover THEN
            v_gate := registration.gst_gate(p_student, p_session, m.course_code);
            IF v_gate IS NOT NULL THEN RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514'; END IF;
            IF registration.prerequisite_mode() = 'ENFORCED' THEN
                v_unmet := registration.prerequisites_unmet(p_student, m.course_code);
                IF cardinality(v_unmet) > 0 THEN
                    RAISE EXCEPTION 'REG_PREREQUISITE: % needs % passed first', m.course_code, array_to_string(v_unmet, ', ') USING ERRCODE = '23514';
                END IF;
            END IF;
        END IF;
        v_type := CASE WHEN m.deferred THEN 'DEFERRED' WHEN m.carryover THEN 'CARRYOVER' WHEN m.basis = 'GST' OR m.kind = 'GST' THEN 'GST'
                       WHEN m.basis = 'Borrowed' THEN 'BORROWED' WHEN m.basis = 'Elective' OR (m.basis IS NULL AND m.kind = 'Elective') THEN 'ELECTIVE' ELSE 'CURRENT' END;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type) VALUES (r.id, p_offering, m.units, v_type)
        ON CONFLICT (registration_id, offering_id) DO UPDATE SET status = 'REGISTERED', entry_type = EXCLUDED.entry_type, units = EXCLUDED.units;
        PERFORM registration.gst_course_registered(r.id, p_offering);
        RETURN jsonb_build_object('added', true, 'courseCode', m.course_code, 'category', registration.entry_category(v_type, m.kind, m.basis),
                                  'units', registration.units_of(r.id), 'recommended', true);
    END IF;
    SELECT * INTO x FROM registration.course_refusal(p_student, p_session, p_semester, p_offering);
    IF x.refusal IS NOT NULL THEN RAISE EXCEPTION '%', x.refusal USING ERRCODE = '23514'; END IF;
    -- V314: the GST fee owed holds every course the student registers, as on the menu (registration.gst_gate)
    v_gate := registration.gst_gate(p_student, p_session, v_code);
    IF v_gate IS NOT NULL THEN RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514'; END IF;
    v_type := CASE x.category WHEN 'CARRY_OVER' THEN 'CARRYOVER' WHEN 'GST' THEN 'GST' WHEN 'ELECTIVE' THEN 'ELECTIVE' ELSE 'CURRENT' END;
    INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, student_added_at, added_as)
    SELECT r.id, p_offering, catalogue.units_for(v_code, s.programme_code, NULL), v_type, now(), x.added_as FROM people.student s WHERE s.id = p_student
    ON CONFLICT (registration_id, offering_id) DO UPDATE SET status = 'REGISTERED', entry_type = EXCLUDED.entry_type, units = EXCLUDED.units,
        student_added_at = EXCLUDED.student_added_at, added_as = EXCLUDED.added_as;
    PERFORM registration.gst_course_registered(r.id, p_offering);
    RETURN jsonb_build_object('added', true, 'courseCode', v_code, 'category', x.category, 'addedAs', x.added_as, 'why', x.why,
                              'units', registration.units_of(r.id), 'recommended', false);
END $$;

-- ── add and drop (V504): the GST/EPS registration log ──
CREATE OR REPLACE FUNCTION registration.student_add(p_student uuid, p_session text, p_semester integer, p_offering uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; m record; lim policy.level_limit; v_units int; v_type text; v_status text; v_gate text; v_unmet text[];
        v_code text; x record; v_as text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF NOT FOUND THEN RAISE EXCEPTION 'register first, then add or drop' USING ERRCODE = '23514'; END IF;
    IF r.status = 'LOCKED' THEN RAISE EXCEPTION 'this registration is locked and cannot be changed' USING ERRCODE = '23514'; END IF;
    IF NOT registration.add_drop_open(p_student, p_session, p_semester) THEN   -- V380: by the student's calendar
        RAISE EXCEPTION 'add and drop is not open for % semester %', p_session, p_semester USING ERRCODE = '23514',
            HINT = 'It runs while the semester is open, up to the late-registration deadline set by the Registry.';
    END IF;
    IF NOT finance.clears(p_student, p_session, 'REGISTRATION') THEN
        RAISE EXCEPTION 'the Bursary has not cleared you for registration in %', p_session USING ERRCODE = '23514';
    END IF;
    -- V504: a course already on the registration is not added twice
    SELECT o.course_code INTO v_code FROM catalogue.offering o WHERE o.id = p_offering;
    IF EXISTS (SELECT 1 FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id
                WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN') AND o.course_code = v_code) THEN
        RAISE EXCEPTION 'REG_ALREADY_ADDED: Course already added' USING ERRCODE = '23514';
    END IF;

    SELECT * INTO m FROM registration.student_menu(p_student, p_session, p_semester) WHERE offering_id = p_offering AND NOT carryover;
    IF FOUND THEN
        -- V314: a GST or EPS course is added only by a student whose GST fee is paid
        v_gate := registration.gst_gate(p_student, p_session, m.course_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; it opens the moment the payment is confirmed.';
        END IF;
        -- V482: where the Academic Office enforces prerequisites, a course whose prerequisite the student has not passed is refused
        IF registration.prerequisite_mode() = 'ENFORCED' THEN
            v_unmet := registration.prerequisites_unmet(p_student, m.course_code);
            IF cardinality(v_unmet) > 0 THEN
                RAISE EXCEPTION 'REG_PREREQUISITE: % needs % passed first; no published pass is on your record', m.course_code, array_to_string(v_unmet, ', ')
                    USING ERRCODE = '23514', HINT = 'If you passed it and the result is not yet published, or were exempted, your department asks ICT Support to add the course on your ticket.';
            END IF;
        END IF;
        v_units := m.units;
        v_type := CASE WHEN m.basis = 'GST' OR m.kind = 'GST' THEN 'GST' WHEN m.basis = 'Borrowed' THEN 'BORROWED'
                       WHEN m.basis = 'Elective' OR (m.basis IS NULL AND m.kind = 'Elective') THEN 'ELECTIVE' ELSE 'CURRENT' END;
    ELSE
        -- V504: a course beside the menu, when the engine allows it (registration.course_check judges it; prerequisites included)
        SELECT * INTO x FROM registration.course_refusal(p_student, p_session, p_semester, p_offering);
        IF x.refusal IS NOT NULL THEN RAISE EXCEPTION '%', x.refusal USING ERRCODE = '23514'; END IF;
        -- V314: the GST fee owed holds every course the student registers, as on the menu (registration.gst_gate)
        v_gate := registration.gst_gate(p_student, p_session, v_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; it opens the moment the payment is confirmed.';
        END IF;
        SELECT catalogue.units_for(v_code, s.programme_code, NULL) INTO v_units FROM people.student s WHERE s.id = p_student;
        v_type := CASE x.category WHEN 'CARRY_OVER' THEN 'CARRYOVER' WHEN 'GST' THEN 'GST' WHEN 'ELECTIVE' THEN 'ELECTIVE' ELSE 'CURRENT' END;
        v_as := x.added_as;
    END IF;
    -- an approved registration has no further approval step, so the added course is examinable at once;
    -- a still-submitted one keeps REGISTERED and the HOD's approval flips it with the batch (RegistrationRepository)
    v_status := CASE WHEN r.status = 'APPROVED' THEN 'APPROVED' ELSE 'REGISTERED' END;

    -- would this exceed the level's maximum?
    SELECT * INTO lim FROM registration.unit_limit(p_student, r.level);   -- V380: the CCE course load for a CCE student
    IF FOUND AND registration.units_of(r.id) + v_units > lim.max_units THEN
        RAISE EXCEPTION 'adding this course puts you at % units, over the maximum of % at % level',
            registration.units_of(r.id) + v_units, lim.max_units, r.level USING ERRCODE = '23514',
            HINT = 'Drop a course first, or ask your Head of Department for an overload.';
    END IF;

    -- reinstate a dropped entry, or add a new one
    IF EXISTS (SELECT 1 FROM registration.entry WHERE registration_id = r.id AND offering_id = p_offering) THEN
        UPDATE registration.entry SET status = v_status, units = v_units, entry_type = v_type,
               student_added_at = CASE WHEN m.offering_id IS NULL THEN now() END, added_as = v_as
         WHERE registration_id = r.id AND offering_id = p_offering;
    ELSE
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status, student_added_at, added_as)
        VALUES (r.id, p_offering, v_units, v_type, v_status, CASE WHEN m.offering_id IS NULL THEN now() END, v_as);
    END IF;
    PERFORM registration.gst_course_registered(r.id, p_offering);   -- V512: the GST/EPS registration log
    RETURN registration.units_of(r.id);
END $function$;

COMMIT;
