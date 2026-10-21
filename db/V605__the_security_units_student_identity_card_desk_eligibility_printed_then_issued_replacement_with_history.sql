-- ═══════════════════════════════════════
-- V605 — the Security Unit's student identity card desk: eligibility, printed then issued, replacement with history
--
--   What the portal already had (kept): the card register credentials.identity_card (V027) — one card number MOAUM/ID/YY/NNNNN
--   from platform.next_number, keyed on the matriculation number, one live card a student, ended as LOST, REPLACED or RETURNED
--   with a reason, on the audit spine; the Security Unit alone issuing (GAP-005, 16 Oct 2026) and every other office reading;
--   the printable card drawn by the portal's PDF engine with the University's design and a QR that carries the signed check
--   address (/verify/idcard, V360/V435); the photograph where every photograph is (people.student_photo, else the admission's
--   passport document, else the attachment store); the student's own status page; the staff card register (V439).
--
--   The University's brief (21 Oct 2026): the Security Unit searches a student, sees the particulars, the photograph, the
--   matriculation number, the school-fee eligibility and the card; previews, prints, issues, reprints or replaces it on a reason;
--   reads the whole history. The card never waits on the office-by-office clearance (Bursary, Department, Faculty, Library, Health,
--   Hostel, Alumni …): clearance and the card are two processes. It did not here — the register's gate was the Bursary's fee scheme
--   (finance.clears for the ID_CARD purpose, the instalment the scheme releases the card at), which is finance's own word — but the
--   refusal spoke of "clearance", and nothing said why a student was not eligible, nothing separated printed from handed over, a
--   replacement carried no reason code and no link to the card it replaced, and there was no search, no eligibility reading and no
--   report. So, on the same register:
--     · credentials.id_card_eligibility(student) — the one reading: on the register and in study (a graduated or withdrawn record is
--       issued no new card; its cards stay), a matriculation number, an official photograph, and the school fees as finance records
--       them over the sessions the record shows the student in: the latest released for the card by the scheme the Bursary put in
--       force (the University's school-fee condition), every earlier one with stated fees paid in full — "from 100 Level". Each failing check is
--       a reason in words. Clearance is not read, and is never a reason;
--     · states PRINTED (made and printed, awaiting collection) and ISSUED (handed to the student, in force), then LOST, DAMAGED,
--       REPLACED, RETURNED, REVOKED, CANCELLED — ended with a reason, never deleted; one live card a student, enforced by the index;
--     · credentials.print_identity_card — the Security Unit's act: the student row locked (two clicks make one card), eligibility
--       read again, the live card printed again (counted) or, on a reason from the list (lost, damaged, name correction, programme
--       change, matriculation correction, photograph update, security replacement, expired, other), ended and replaced by a new
--       number, version +1, linked to the card it replaced; credentials.collect_identity_card — the card handed over, by whom and
--       when; credentials.end_identity_card — lost, damaged, returned, revoked or cancelled on a reason. Every act is an event on
--       credentials.event (ID_CARD_PRINTED, ID_CARD_ISSUED, ID_CARD_REPLACED, ID_CARD_LOST …) beside the audit spine;
--     · credentials.issue_identity_card and credentials.report_card_lost keep their signatures for the doors that call them (the
--       student's own "lost" button, the old desk): issue = print and hand over in one act, lost = ended as LOST.
--   Nothing is written to finance, matriculation, clearance or the photograph; the card reads them.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'security', true),
       set_config('moaum.reason', 'V605: the Security Unit''s student identity card desk — eligibility, printed then issued, replacement with history', true);

-- ── the register: printed, collected, versions, the card replaced ───────────────────────────────────────────────
ALTER TABLE credentials.identity_card
    ADD COLUMN printed_at          timestamptz,
    ADD COLUMN printed_by          uuid,
    ADD COLUMN print_count         integer NOT NULL DEFAULT 0,
    ADD COLUMN collected_at        timestamptz,
    ADD COLUMN collected_by        uuid,
    ADD COLUMN previous_card_id    uuid REFERENCES credentials.identity_card(id) ON DELETE SET NULL,
    ADD COLUMN replacement_reason  text,
    ADD COLUMN version             integer NOT NULL DEFAULT 1;
-- the cards issued before: printed at the desk and handed over at issue
UPDATE credentials.identity_card SET printed_at = issued_at, printed_by = issued_by, print_count = 1, collected_at = issued_at, collected_by = issued_by;
ALTER TABLE credentials.identity_card DROP CONSTRAINT ck_card_state;
ALTER TABLE credentials.identity_card ADD CONSTRAINT ck_card_state
    CHECK (state IN ('PRINTED', 'ISSUED', 'LOST', 'DAMAGED', 'REPLACED', 'RETURNED', 'REVOKED', 'CANCELLED'));
ALTER TABLE credentials.identity_card DROP CONSTRAINT ck_card_ended;
ALTER TABLE credentials.identity_card ADD CONSTRAINT ck_card_ended CHECK ((state IN ('PRINTED', 'ISSUED')) = (ended_at IS NULL));
ALTER TABLE credentials.identity_card DROP CONSTRAINT ck_card_reason;
ALTER TABLE credentials.identity_card ADD CONSTRAINT ck_card_reason CHECK (state IN ('PRINTED', 'ISSUED') OR ended_reason IS NOT NULL);
-- collected_at is the handover the desk records; a card issued by the older door or a migrated row may carry none
ALTER TABLE credentials.identity_card ADD CONSTRAINT ck_card_replacement_reason
    CHECK (replacement_reason IS NULL OR replacement_reason IN ('LOST', 'DAMAGED', 'NAME_CORRECTION', 'PROGRAMME_CHANGE', 'MATRIC_CORRECTION',
                                                                 'PHOTOGRAPH_UPDATE', 'SECURITY_REPLACEMENT', 'EXPIRED', 'OTHER'));
DROP INDEX credentials.uq_card_live;
CREATE UNIQUE INDEX uq_card_live ON credentials.identity_card (student_id) WHERE state IN ('PRINTED', 'ISSUED');
CREATE INDEX identity_card_student_idx ON credentials.identity_card (student_id, issued_at DESC);
COMMENT ON COLUMN credentials.identity_card.state IS
  'V605: PRINTED (made and printed, awaiting collection), ISSUED (handed to the student, in force), then LOST, DAMAGED, REPLACED, RETURNED, REVOKED or CANCELLED with ended_at and ended_reason';
COMMENT ON COLUMN credentials.identity_card.previous_card_id IS 'V605: the card this one replaced, with replacement_reason the code from the list';

-- ── the photograph, as the card reads it ───────────────────────────────────────────────────────────────────────
CREATE FUNCTION credentials.has_photo(p_student uuid) RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT EXISTS (SELECT 1 FROM people.student_photo ph WHERE ph.student_id = p_student)
        OR EXISTS (SELECT 1 FROM people.student s
                     JOIN admissions.application a ON a.candidate_id = s.candidate_id
                     JOIN admissions.application_document d ON d.application_id = a.id AND d.kind = 'PASSPORT' AND d.superseded_at IS NULL
                    WHERE s.id = p_student)
        OR EXISTS (SELECT 1 FROM people.student s
                     JOIN admissions.attachment at ON at.kind = 'PASSPORT' AND (jsonb_exists(at.payload, 'dataUrl') OR at.object_id IS NOT NULL)
                      AND (at.candidate_id = s.candidate_id OR (s.jamb_reg_no IS NOT NULL AND at.jamb_key = upper(btrim(s.jamb_reg_no))))
                    WHERE s.id = p_student)
$fn$;
COMMENT ON FUNCTION credentials.has_photo(uuid) IS
  'V605: whether the student has an official photograph where the portal keeps them — replaced on the portal, the admission''s passport document, or the attachment store — the same order the portal serves it in';

-- ── eligibility: the one reading, every failing check a reason ─────────────────────────────────────────────────
CREATE FUNCTION credentials.id_card_eligibility(p_student uuid) RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE s people.student; reasons text[] := '{}'; v_ses text; v_rule boolean; v_stated boolean; v_in_study boolean; v_photo boolean;
        v_short jsonb := '[]'::jsonb; r record; v_fees_ok boolean := true; v_sessions jsonb := '[]'::jsonb; v_live record;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('eligible', false, 'reasons', jsonb_build_array('No such student on the register'));
    END IF;
    v_in_study := s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION', 'DORMANT');
    IF NOT v_in_study THEN
        reasons := array_append(reasons, CASE WHEN s.status = 'GRADUATED' THEN 'The record has graduated: no new card is issued; the cards held stay on the record'
                                   ELSE 'Not in study on the register (' || lower(replace(s.status, '_', ' ')) || '): no new card is issued' END);
    END IF;
    IF s.matric_no IS NULL THEN
        reasons := array_append(reasons, 'Matriculation number not yet issued');
    END IF;
    v_photo := credentials.has_photo(p_student);
    IF NOT v_photo THEN
        reasons := array_append(reasons, 'Student photograph is missing');
    END IF;
    -- the school fees, as finance records them, over the sessions the record shows the student in (an enrolment, or a submitted
    -- registration): the latest of them released for the card by the scheme the Bursary put in force — the University's
    -- school-fee condition — and every earlier one with stated fees paid in full, "from 100 Level"
    SELECT max(x.session) INTO v_ses
      FROM (SELECT e.session FROM people.enrolment e WHERE e.student_id = p_student
            UNION SELECT cr.session FROM registration.course_registration cr WHERE cr.student_id = p_student AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) x;
    IF v_ses IS NULL THEN
        v_fees_ok := false;
        reasons := array_append(reasons, 'Required school-fee condition not satisfied: the record shows no session in study, so no school fees to read');
    ELSE
        v_stated := finance.fee_stated(p_student, v_ses);
        v_rule := CASE WHEN v_stated THEN finance.clears(p_student, v_ses, 'ID_CARD') ELSE NULL END;
        IF v_stated IS NOT TRUE THEN
            v_fees_ok := false;
            reasons := array_append(reasons, ('Required school-fee condition not satisfied: the school fees for ' || v_ses || ' are not yet stated for this programme and level'));
        ELSIF NOT v_rule THEN
            v_fees_ok := false;
            reasons := array_append(reasons, ('Required school-fee condition not satisfied: the school fees for ' || v_ses || ' are not paid as the scheme in force requires for the card'));
        END IF;
        FOR r IN
            SELECT x.session, pos.due, pos.paid, pos.balance, pos.paid_in_full
              FROM (SELECT DISTINCT e.session FROM people.enrolment e WHERE e.student_id = p_student
                    UNION SELECT cr.session FROM registration.course_registration cr WHERE cr.student_id = p_student AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) x
              CROSS JOIN LATERAL finance.position(p_student, x.session) pos
             WHERE x.session < v_ses AND finance.fee_stated(p_student, x.session)
             ORDER BY x.session
        LOOP
            v_sessions := v_sessions || jsonb_build_object('session', r.session, 'due', r.due, 'paid', r.paid, 'balance', r.balance, 'paid_in_full', r.paid_in_full);
            IF NOT r.paid_in_full THEN
                v_fees_ok := false;
                v_short := v_short || to_jsonb(r.session);
            END IF;
        END LOOP;
        IF jsonb_array_length(v_short) > 0 THEN
            reasons := array_append(reasons, ('Required school-fee condition not satisfied: school fees outstanding for ' ||
                                   (SELECT string_agg(value #>> '{}', ', ') FROM jsonb_array_elements(v_short)) || ' — the card is issued to a student who has paid from the first session'));
        END IF;
    END IF;
    SELECT c.card_no, c.state, c.version INTO v_live FROM credentials.identity_card c WHERE c.student_id = p_student AND c.state IN ('PRINTED', 'ISSUED');
    RETURN jsonb_build_object(
        'eligible', cardinality(reasons) = 0,
        'reasons', to_jsonb(reasons),
        'checks', jsonb_build_object('in_study', v_in_study, 'matric', s.matric_no IS NOT NULL, 'photo', v_photo, 'fees', v_fees_ok),
        'fees', jsonb_build_object('session', v_ses, 'stated', v_stated, 'released', v_rule, 'earlier', v_sessions, 'short', v_short),
        'card', CASE WHEN v_live.card_no IS NULL THEN NULL ELSE jsonb_build_object('card_no', v_live.card_no, 'state', v_live.state, 'version', v_live.version) END);
END $fn$;
COMMENT ON FUNCTION credentials.id_card_eligibility(uuid) IS
  'V605: whether the Security Unit may print a card for the student, with every failing check in words — in study on the register, a matriculation number, an official photograph, the school fees as finance records them over the sessions the record shows the student in (the latest released by the scheme in force, every earlier stated one paid in full). The office clearance is not read and is never a reason';

-- ── the events on the credentials trail ────────────────────────────────────────────────────────────────────────
CREATE FUNCTION credentials.card_event(p_student uuid, p_action text, p_from text, p_to text, p_note text) RETURNS void LANGUAGE sql AS $fn$
    INSERT INTO credentials.event (student_id, action, from_state, to_state, note, actor_id, actor_office)
    VALUES (p_student, p_action, p_from, p_to, left(p_note, 400),
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
$fn$;

-- ── the acts ───────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION credentials.print_identity_card(p_student uuid, p_replace_reason text, p_note text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE s people.student; live credentials.identity_card; e jsonb; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_no text; v_id uuid := gen_random_uuid(); v_version int; v_prev uuid; v_prev_no text; v_ended text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'ID_CARD_ACTOR: a card is printed by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;   -- two clicks, one card
    IF NOT FOUND THEN RAISE EXCEPTION 'ID_CARD_NO_STUDENT: no such student' USING ERRCODE = '23503'; END IF;
    e := credentials.id_card_eligibility(p_student);
    IF NOT (e->>'eligible')::boolean THEN
        RAISE EXCEPTION 'ID_CARD_NOT_ELIGIBLE: %', (SELECT string_agg(value #>> '{}', '; ') FROM jsonb_array_elements(e->'reasons')) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO live FROM credentials.identity_card c WHERE c.student_id = p_student AND c.state IN ('PRINTED', 'ISSUED') FOR UPDATE;
    IF live.id IS NOT NULL AND p_replace_reason IS NULL THEN
        -- the live card printed again: the same number, counted
        UPDATE credentials.identity_card SET print_count = print_count + 1, printed_at = now(), printed_by = who WHERE id = live.id;
        PERFORM credentials.card_event(p_student, 'ID_CARD_PRINTED', live.state, live.state,
                                       live.card_no || ' printed again (print ' || (live.print_count + 1) || ')' || coalesce(' — ' || nullif(btrim(p_note), ''), ''));
        RETURN jsonb_build_object('card_id', live.id, 'card_no', live.card_no, 'state', live.state, 'version', live.version,
                                  'print_count', live.print_count + 1, 'replaced', false);
    END IF;
    IF live.id IS NOT NULL THEN
        IF p_replace_reason NOT IN ('LOST', 'DAMAGED', 'NAME_CORRECTION', 'PROGRAMME_CHANGE', 'MATRIC_CORRECTION', 'PHOTOGRAPH_UPDATE', 'SECURITY_REPLACEMENT', 'EXPIRED', 'OTHER') THEN
            RAISE EXCEPTION 'ID_CARD_REASON: a replacement is made on a reason from the list' USING ERRCODE = '23514';
        END IF;
        IF p_replace_reason = 'OTHER' AND length(coalesce(btrim(p_note), '')) < 5 THEN
            RAISE EXCEPTION 'ID_CARD_REASON: "other" says what happened, in a few words' USING ERRCODE = '23514';
        END IF;
        v_ended := CASE p_replace_reason WHEN 'LOST' THEN 'LOST' WHEN 'DAMAGED' THEN 'DAMAGED' ELSE 'REPLACED' END;
        UPDATE credentials.identity_card
           SET state = v_ended, ended_at = now(),
               ended_reason = lower(replace(p_replace_reason, '_', ' ')) || coalesce(' — ' || nullif(btrim(p_note), ''), '')
         WHERE id = live.id;
        PERFORM credentials.card_event(p_student, 'ID_CARD_REPLACED', live.state, v_ended, live.card_no || ' replaced: ' || lower(replace(p_replace_reason, '_', ' ')) || coalesce(' — ' || nullif(btrim(p_note), ''), ''));
        v_prev := live.id; v_prev_no := live.card_no;
    ELSE
        SELECT c.id, c.card_no INTO v_prev, v_prev_no FROM credentials.identity_card c WHERE c.student_id = p_student ORDER BY c.issued_at DESC LIMIT 1;
    END IF;
    SELECT coalesce(max(c.version), 0) + 1 INTO v_version FROM credentials.identity_card c WHERE c.student_id = p_student;
    v_no := 'MOAUM/ID/' || to_char(current_date, 'YY') || '/' || lpad(platform.next_number('IDENTITY_CARD', 'UNIVERSITY', to_char(current_date, 'YYYY'))::text, 5, '0');
    INSERT INTO credentials.identity_card (id, student_id, card_no, issued_by, valid_to, state, printed_at, printed_by, print_count, previous_card_id, replacement_reason, version)
    VALUES (v_id, p_student, v_no, who, (current_date + interval '4 years')::date, 'PRINTED', now(), who, 1, v_prev, CASE WHEN live.id IS NOT NULL THEN p_replace_reason END, v_version);
    PERFORM credentials.card_event(p_student, 'ID_CARD_PRINTED', NULL, 'PRINTED', v_no || ' printed (version ' || v_version || ')' || coalesce(', replacing ' || v_prev_no, '') || coalesce(' — ' || nullif(btrim(p_note), ''), ''));
    RETURN jsonb_build_object('card_id', v_id, 'card_no', v_no, 'state', 'PRINTED', 'version', v_version, 'print_count', 1,
                              'replaced', live.id IS NOT NULL, 'previous_card_no', v_prev_no);
END $fn$;
COMMENT ON FUNCTION credentials.print_identity_card(uuid, text, text) IS
  'V605: the Security Unit prints a student''s card — eligibility read again under the student''s lock; the live card printed again and counted, or, on a reason from the list, ended and replaced by a new number (version +1, linked to the card it replaced); every act an event';

CREATE FUNCTION credentials.collect_identity_card(p_student uuid, p_note text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE live credentials.identity_card; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'ID_CARD_ACTOR: a card is handed over by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO live FROM credentials.identity_card c WHERE c.student_id = p_student AND c.state IN ('PRINTED', 'ISSUED') FOR UPDATE;
    IF live.id IS NULL THEN RAISE EXCEPTION 'ID_CARD_NOT_PRINTED: no card has been printed for this student' USING ERRCODE = '23514'; END IF;
    IF live.state = 'ISSUED' THEN RAISE EXCEPTION 'ID_CARD_ALREADY_ISSUED: card % was handed over already', live.card_no USING ERRCODE = '23514'; END IF;
    UPDATE credentials.identity_card SET state = 'ISSUED', collected_at = now(), collected_by = who WHERE id = live.id;
    PERFORM credentials.card_event(p_student, 'ID_CARD_ISSUED', 'PRINTED', 'ISSUED', live.card_no || ' handed to the student' || coalesce(' — ' || nullif(btrim(p_note), ''), ''));
    RETURN jsonb_build_object('card_id', live.id, 'card_no', live.card_no, 'state', 'ISSUED', 'version', live.version);
END $fn$;
COMMENT ON FUNCTION credentials.collect_identity_card(uuid, text) IS 'V605: the printed card handed to the student — ISSUED, by whom and when';

CREATE FUNCTION credentials.end_identity_card(p_card uuid, p_state text, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE live credentials.identity_card;
BEGIN
    IF p_state NOT IN ('LOST', 'DAMAGED', 'RETURNED', 'REVOKED', 'CANCELLED') THEN
        RAISE EXCEPTION 'ID_CARD_STATE: a card is ended as lost, damaged, returned, revoked or cancelled' USING ERRCODE = '23514';
    END IF;
    IF length(coalesce(btrim(p_reason), '')) < 5 THEN RAISE EXCEPTION 'ID_CARD_REASON: say why, in a few words' USING ERRCODE = '23514'; END IF;
    SELECT * INTO live FROM credentials.identity_card c WHERE c.id = p_card FOR UPDATE;
    IF live.id IS NULL THEN RAISE EXCEPTION 'ID_CARD_NONE: no such card' USING ERRCODE = '23503'; END IF;
    IF live.state NOT IN ('PRINTED', 'ISSUED') THEN RAISE EXCEPTION 'ID_CARD_ENDED: card % is already %', live.card_no, lower(live.state) USING ERRCODE = '23514'; END IF;
    UPDATE credentials.identity_card SET state = p_state, ended_at = now(), ended_reason = btrim(p_reason) WHERE id = live.id;
    PERFORM credentials.card_event(live.student_id, 'ID_CARD_' || p_state, live.state, p_state, live.card_no || ': ' || btrim(p_reason));
    RETURN jsonb_build_object('card_id', live.id, 'card_no', live.card_no, 'state', p_state);
END $fn$;
COMMENT ON FUNCTION credentials.end_identity_card(uuid, text, text) IS 'V605: a live card ended as lost, damaged, returned, revoked or cancelled, on a reason; the record stays';

-- the doors that call the old names keep them: issue = print and hand over in one act; lost = ended as LOST
CREATE OR REPLACE FUNCTION credentials.issue_identity_card(p_student uuid, p_reason text) RETURNS text LANGUAGE plpgsql AS $function$
DECLARE live credentials.identity_card; r jsonb;
BEGIN
    SELECT * INTO live FROM credentials.identity_card c WHERE c.student_id = p_student AND c.state IN ('PRINTED', 'ISSUED');
    IF live.id IS NOT NULL AND live.state = 'PRINTED' THEN
        r := credentials.collect_identity_card(p_student, p_reason);
    ELSE
        r := credentials.print_identity_card(p_student, CASE WHEN live.id IS NOT NULL THEN 'OTHER' END,
                                             CASE WHEN live.id IS NOT NULL THEN coalesce(nullif(btrim(p_reason), ''), 'replaced at the desk') ELSE p_reason END);
        r := credentials.collect_identity_card(p_student, NULL);
    END IF;
    RETURN r->>'card_no';
END $function$;
COMMENT ON FUNCTION credentials.issue_identity_card(uuid, text) IS 'V027/V605: the card made, printed and handed over in one act at the desk (a printed one awaiting collection is handed over)';

CREATE OR REPLACE FUNCTION credentials.report_card_lost(p_student uuid, p_reason text) RETURNS integer LANGUAGE plpgsql AS $function$
DECLARE live credentials.identity_card;
BEGIN
    SELECT * INTO live FROM credentials.identity_card c WHERE c.student_id = p_student AND c.state IN ('PRINTED', 'ISSUED');
    IF live.id IS NULL THEN RETURN 0; END IF;
    PERFORM credentials.end_identity_card(live.id, 'LOST', coalesce(nullif(btrim(p_reason), ''), 'reported lost'));
    RETURN 1;
END $function$;

COMMIT;
