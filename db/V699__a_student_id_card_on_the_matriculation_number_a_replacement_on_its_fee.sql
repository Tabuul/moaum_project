-- ═══════════════════════════════════════
-- V699 — A student's identity card on the matriculation number; a replacement on its fee
--
--   The University's word of 29 October 2026: "they shouldnt be restriction for student id card, so far as the student has
--   matriculation number, id card should be issued to the student, except is for replacement, they have to pay a fee for replacement".
--
--   V605 printed a student's card only with the matriculation number, the official photograph, the student in study and the school
--   fees as the scheme in force releases them (and every earlier session paid in full); a replacement was printed on a reason alone.
--
--   1 · finance.fee_setting.id_card_replacement_fee — the replacement fee the Bursary sets (no amount until it does).
--   2 · credentials.identity_card.replacement_payment_id — the paid fee a replacement card was printed on: one payment, one card.
--       credentials.id_card_replacement_payments(student) — the student's confirmed replacement-fee payments (the "Identity card
--       replacement fee", classed ID_CARD) no card has used; credentials.id_card_replacement_state(student) — whether a new card would
--       be a replacement, the fee, whether it is paid, the payment and an open reference.
--   3 · credentials.id_card_eligibility (restated from V605): the matriculation number alone decides; the photograph (a blank frame
--       without), the study and the school fees are said to the desk as warnings, never held against the card.
--   4 · credentials.print_identity_card (restated from V605): the first card on the matriculation number; any card after it — a
--       replacement of the card in force, or a new card after one ended lost — once the student has paid the replacement fee, the
--       payment linked to the card (ID_CARD_REPLACEMENT_FEE otherwise). The card in force printed again costs nothing.
--   5 · credentials.id_card_replacement_reference(student) — the student's reference to pay the fee (the open one, else a new one at
--       the fee set): refused before a first card (ID_CARD_FIRST_FREE), with no fee set (ID_CARD_REPLACEMENT_FEE_NOT_SET), and with a
--       paid fee waiting for its card (ID_CARD_REPLACEMENT_PAID).
-- ═══════════════════════════════════════
BEGIN;

-- ── 1 · the fee the Bursary sets ────────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE finance.fee_setting ADD COLUMN IF NOT EXISTS id_card_replacement_fee numeric(12,2) NULL;
ALTER TABLE finance.fee_setting DROP CONSTRAINT IF EXISTS ck_fee_setting_id_card_replacement;
ALTER TABLE finance.fee_setting ADD CONSTRAINT ck_fee_setting_id_card_replacement CHECK (id_card_replacement_fee IS NULL OR id_card_replacement_fee > 0);
COMMENT ON COLUMN finance.fee_setting.id_card_replacement_fee IS 'V699: the student identity card replacement fee the Bursary sets; NULL until it does (no replacement is printed meanwhile).';

CREATE OR REPLACE FUNCTION credentials.id_card_replacement_fee()
RETURNS numeric LANGUAGE sql STABLE AS $function$
    SELECT id_card_replacement_fee FROM finance.fee_setting WHERE id = 1
$function$;

-- ── 2 · the payment a replacement card is printed on ────────────────────────────────────────────────────────────────────
ALTER TABLE credentials.identity_card ADD COLUMN IF NOT EXISTS replacement_payment_id uuid NULL REFERENCES finance.payment_reference (id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_identity_card_replacement_payment ON credentials.identity_card (replacement_payment_id) WHERE replacement_payment_id IS NOT NULL;
COMMENT ON COLUMN credentials.identity_card.replacement_payment_id IS 'V699: the replacement fee paid for this card (a card after the first); one payment, one card.';

CREATE OR REPLACE FUNCTION credentials.id_card_replacement_payments(p_student uuid)
RETURNS TABLE (id uuid, reference text, amount numeric, confirmed_at timestamptz)
LANGUAGE sql STABLE AS $function$
    SELECT r.id, r.reference, r.amount, r.confirmed_at
      FROM finance.payment_reference r
     WHERE r.student_id = p_student AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
       AND r.purpose ILIKE 'Identity card replacement%'
       AND NOT EXISTS (SELECT 1 FROM credentials.identity_card c WHERE c.replacement_payment_id = r.id)
     ORDER BY r.confirmed_at, r.reference
$function$;
COMMENT ON FUNCTION credentials.id_card_replacement_payments(uuid) IS
  'V699: the student''s confirmed identity card replacement fee payments no card has been printed on yet.';

CREATE OR REPLACE FUNCTION credentials.id_card_replacement_state(p_student uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $function$
    SELECT jsonb_build_object(
        -- a new card would be a replacement: the student has had a card
        'needed', EXISTS (SELECT 1 FROM credentials.identity_card c WHERE c.student_id = p_student),
        'fee', credentials.id_card_replacement_fee(),
        'paid', EXISTS (SELECT 1 FROM credentials.id_card_replacement_payments(p_student)),
        'payment', (SELECT x.reference FROM credentials.id_card_replacement_payments(p_student) x LIMIT 1),
        'openReference', (SELECT r.reference FROM finance.payment_reference r
                           WHERE r.student_id = p_student AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now()
                             AND r.purpose ILIKE 'Identity card replacement%' ORDER BY r.generated_at DESC LIMIT 1),
        'openAmount', (SELECT r.amount FROM finance.payment_reference r
                        WHERE r.student_id = p_student AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now()
                          AND r.purpose ILIKE 'Identity card replacement%' ORDER BY r.generated_at DESC LIMIT 1))
$function$;
CREATE OR REPLACE FUNCTION credentials.id_card_replacement_take(p_student uuid)
RETURNS uuid LANGUAGE plpgsql AS $function$
-- the paid replacement fee a new card is printed on (the earliest unused), or the refusal that names what is missing
DECLARE v_pay uuid; v_fee numeric := credentials.id_card_replacement_fee();
        v_no text := (SELECT coalesce(s.matric_no, s.admission_no) FROM people.student s WHERE s.id = p_student);
BEGIN
    SELECT x.id INTO v_pay FROM credentials.id_card_replacement_payments(p_student) x ORDER BY x.confirmed_at, x.reference LIMIT 1;
    IF v_pay IS NOT NULL THEN RETURN v_pay; END IF;
    IF v_fee IS NULL THEN
        RAISE EXCEPTION 'ID_CARD_REPLACEMENT_FEE: a replacement card is printed once its fee is paid, and the Bursary has not set the replacement fee yet'
            USING ERRCODE = '23514', HINT = 'The Bursary sets the ID card replacement fee on Fee Setup; the student then pays it on their portal.';
    END IF;
    RAISE EXCEPTION 'ID_CARD_REPLACEMENT_FEE: a replacement card is printed once its fee of % is paid; % has not paid it', finance.naira(v_fee), v_no
        USING ERRCODE = '23514', HINT = 'The student pays the ID card replacement fee on their portal (Identity Card); the card is printed once the payment is confirmed.';
END $function$;

COMMENT ON FUNCTION credentials.id_card_replacement_state(uuid) IS
  'V699: whether a new identity card would be a replacement, the fee the Bursary set, whether it is paid (and by which payment), and an open reference to pay it.';

-- ── 3 · the eligibility: the matriculation number alone ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION credentials.id_card_eligibility(p_student uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s people.student; reasons text[] := '{}'; warnings text[] := '{}'; v_repl jsonb; v_ses text; v_rule boolean; v_stated boolean; v_in_study boolean; v_photo boolean;
        v_short jsonb := '[]'::jsonb; r record; v_fees_ok boolean := true; v_sessions jsonb := '[]'::jsonb; v_live record;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('eligible', false, 'reasons', jsonb_build_array('No such student on the register'));
    END IF;
    -- V699: the matriculation number alone decides a card; what follows is said to the desk, never held against the card
    v_in_study := s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION', 'DORMANT');
    IF NOT v_in_study THEN
        warnings := array_append(warnings, CASE WHEN s.status = 'GRADUATED' THEN 'The record has graduated: no new card is issued; the cards held stay on the record'
                                   ELSE 'Not in study on the register (' || lower(replace(s.status, '_', ' ')) || '): no new card is issued' END);
    END IF;
    IF s.matric_no IS NULL THEN
        reasons := array_append(reasons, 'Matriculation number not yet issued');
    END IF;
    v_photo := credentials.has_photo(p_student);
    IF NOT v_photo THEN
        warnings := array_append(warnings, 'Student photograph is missing: the card prints with a blank frame');
    END IF;
    -- the school fees, as finance records them, over the sessions the record shows the student in (an enrolment, or a submitted
    -- registration): the latest of them released for the card by the scheme the Bursary put in force — the University's
    -- school-fee condition — and every earlier one with stated fees paid in full, "from 100 Level"
    SELECT max(x.session) INTO v_ses
      FROM (SELECT e.session FROM people.enrolment e WHERE e.student_id = p_student
            UNION SELECT cr.session FROM registration.course_registration cr WHERE cr.student_id = p_student AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) x;
    IF v_ses IS NULL THEN
        v_fees_ok := false;
        warnings := array_append(warnings, 'School fees: the record shows no session in study, so no school fees to read');
    ELSE
        v_stated := finance.fee_stated(p_student, v_ses);
        v_rule := CASE WHEN v_stated THEN finance.clears(p_student, v_ses, 'ID_CARD') ELSE NULL END;
        IF v_stated IS NOT TRUE THEN
            v_fees_ok := false;
            warnings := array_append(warnings, ('School fees: the school fees for ' || v_ses || ' are not yet stated for this programme and level'));
        ELSIF NOT v_rule THEN
            v_fees_ok := false;
            warnings := array_append(warnings, ('School fees: the school fees for ' || v_ses || ' are not paid as the scheme in force requires'));
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
            warnings := array_append(warnings, ('School fees: outstanding for ' ||
                                   (SELECT string_agg(value #>> '{}', ', ') FROM jsonb_array_elements(v_short))));
        END IF;
    END IF;
    SELECT c.card_no, c.state, c.version INTO v_live FROM credentials.identity_card c WHERE c.student_id = p_student AND c.state IN ('PRINTED', 'ISSUED');
    v_repl := credentials.id_card_replacement_state(p_student);
    RETURN jsonb_build_object(
        'eligible', cardinality(reasons) = 0,
        'reasons', to_jsonb(reasons),
        -- V699: said, not held — the photograph, the study, the school fees; and a new card after the first waits on its fee
        'warnings', to_jsonb(warnings),
        'replacement', v_repl,
        'checks', jsonb_build_object('in_study', v_in_study, 'matric', s.matric_no IS NOT NULL, 'photo', v_photo, 'fees', v_fees_ok),
        'fees', jsonb_build_object('session', v_ses, 'stated', v_stated, 'released', v_rule, 'earlier', v_sessions, 'short', v_short),
        'card', CASE WHEN v_live.card_no IS NULL THEN NULL ELSE jsonb_build_object('card_no', v_live.card_no, 'state', v_live.state, 'version', v_live.version) END);
END $function$;

-- ── 4 · the print: a replacement on its paid fee ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION credentials.print_identity_card(p_student uuid, p_replace_reason text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE s people.student; live credentials.identity_card; e jsonb; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_no text; v_id uuid := gen_random_uuid(); v_version int; v_prev uuid; v_prev_no text; v_ended text; v_pay uuid;
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
        -- V699: a replacement is printed once the student has paid its fee (one payment, one card)
        v_pay := credentials.id_card_replacement_take(p_student);
        v_ended := CASE p_replace_reason WHEN 'LOST' THEN 'LOST' WHEN 'DAMAGED' THEN 'DAMAGED' ELSE 'REPLACED' END;
        UPDATE credentials.identity_card
           SET state = v_ended, ended_at = now(),
               ended_reason = lower(replace(p_replace_reason, '_', ' ')) || coalesce(' — ' || nullif(btrim(p_note), ''), '')
         WHERE id = live.id;
        PERFORM credentials.card_event(p_student, 'ID_CARD_REPLACED', live.state, v_ended, live.card_no || ' replaced: ' || lower(replace(p_replace_reason, '_', ' ')) || coalesce(' — ' || nullif(btrim(p_note), ''), ''));
        v_prev := live.id; v_prev_no := live.card_no;
    ELSE
        SELECT c.id, c.card_no INTO v_prev, v_prev_no FROM credentials.identity_card c WHERE c.student_id = p_student ORDER BY c.issued_at DESC LIMIT 1;
        -- V699: the first card is the student's on the matriculation number; a new card after one ended is a replacement, on its fee
        IF v_prev IS NOT NULL THEN v_pay := credentials.id_card_replacement_take(p_student); END IF;
    END IF;
    SELECT coalesce(max(c.version), 0) + 1 INTO v_version FROM credentials.identity_card c WHERE c.student_id = p_student;
    v_no := 'MOAUM/ID/' || to_char(current_date, 'YY') || '/' || lpad(platform.next_number('IDENTITY_CARD', 'UNIVERSITY', to_char(current_date, 'YYYY'))::text, 5, '0');
    INSERT INTO credentials.identity_card (id, student_id, card_no, issued_by, valid_to, state, printed_at, printed_by, print_count, previous_card_id, replacement_reason, version,
                                           replacement_payment_id)
    VALUES (v_id, p_student, v_no, who, (current_date + interval '4 years')::date, 'PRINTED', now(), who, 1, v_prev, CASE WHEN live.id IS NOT NULL THEN p_replace_reason END, v_version,
            v_pay);
    PERFORM credentials.card_event(p_student, 'ID_CARD_PRINTED', NULL, 'PRINTED', v_no || ' printed (version ' || v_version || ')' || coalesce(', replacing ' || v_prev_no, '') || coalesce(' — ' || nullif(btrim(p_note), ''), ''));
    RETURN jsonb_build_object('card_id', v_id, 'card_no', v_no, 'state', 'PRINTED', 'version', v_version, 'print_count', 1,
                              'replaced', live.id IS NOT NULL, 'previous_card_no', v_prev_no,
                              'replacement_payment', (SELECT r.reference FROM finance.payment_reference r WHERE r.id = v_pay));
END $function$;

-- ── 5 · the student's reference to pay the replacement fee ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION credentials.id_card_replacement_reference(p_student uuid)
RETURNS text LANGUAGE plpgsql AS $function$
DECLARE st jsonb := credentials.id_card_replacement_state(p_student); v_fee numeric; v_ses text;
BEGIN
    IF NOT (st->>'needed')::boolean THEN
        RAISE EXCEPTION 'ID_CARD_FIRST_FREE: your first identity card is issued on your matriculation number without a fee; collect it from the Security Unit'
            USING ERRCODE = '23514';
    END IF;
    IF (st->>'paid')::boolean THEN
        RAISE EXCEPTION 'ID_CARD_REPLACEMENT_PAID: your replacement fee (%) is paid; the Security Unit prints your replacement card', st->>'payment'
            USING ERRCODE = '23514';
    END IF;
    IF st->>'openReference' IS NOT NULL THEN RETURN st->>'openReference'; END IF;
    v_fee := credentials.id_card_replacement_fee();
    IF v_fee IS NULL THEN
        RAISE EXCEPTION 'ID_CARD_REPLACEMENT_FEE_NOT_SET: the Bursary has not set the ID card replacement fee yet' USING ERRCODE = '23514',
            HINT = 'Ask the Bursary; the fee is set on Fee Setup.';
    END IF;
    v_ses := coalesce(people.student_current_session(p_student), policy.university_current_session());
    RETURN finance.new_purpose_reference(p_student, v_ses, v_fee, 'Identity card replacement fee');
END $function$;
COMMENT ON FUNCTION credentials.id_card_replacement_reference(uuid) IS
  'V699: the student''s reference to pay the identity card replacement fee — the open one, else a new one at the fee the Bursary set.';

-- how many students hold a card, and how many have had one ended with none in force (a new card for them is a replacement)
DO $$
DECLARE live int; ended int;
BEGIN
    SELECT count(DISTINCT c.student_id) FILTER (WHERE c.state IN ('PRINTED', 'ISSUED')),
           count(DISTINCT c.student_id) FILTER (WHERE NOT EXISTS (SELECT 1 FROM credentials.identity_card x WHERE x.student_id = c.student_id AND x.state IN ('PRINTED', 'ISSUED')))
      INTO live, ended FROM credentials.identity_card c;
    RAISE NOTICE 'V699: % student(s) with a card in force; % with only ended cards, whose next card is a replacement on its fee', live, ended;
END $$;

COMMIT;
