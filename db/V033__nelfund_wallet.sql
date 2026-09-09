-- ═══════════════════════════════════════════════════════════════════════════
-- V033 — the NELFUND wallet, and the remittances behind it
--
--   The Fund decides, the University records, and the student must be able
--   to see which (proto/part37, part49). A remittance arrives in bulk and is
--   split across named students by matriculation number against the
--   register — never on a guess: a row that matches nobody sits in suspense
--   with an owner, and a wallet credited to the wrong student is money the
--   Fund reclaims from someone who never had it. A wallet is append-only:
--   every credit, application, reversal, refund and top-up is an entry, and
--   the balance is derived. It pays the charges the Fund carries, and only
--   those; applying it settles the invoice through the same confirmation
--   every other payment passes (V026), with the wallet as the channel.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE finance.wallet_entry (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id  uuid NOT NULL REFERENCES people.student(id),
    session     text NOT NULL,
    kind        text NOT NULL,
    amount      numeric(12,2) NOT NULL,
    reference   text NULL,
    note        text NULL,
    at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_we_kind CHECK (kind IN ('CREDIT','TOPUP','APPLIED','REVERSED','REFUND')),
    CONSTRAINT ck_we_amount CHECK (amount > 0)
);
CREATE INDEX ix_we_student ON finance.wallet_entry (student_id, at);
SELECT audit.attach('finance.wallet_entry');

CREATE TABLE finance.nelfund_batch (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref         text NOT NULL UNIQUE,
    session     text NOT NULL,
    received_on date NOT NULL,
    amount      numeric(14,2) NOT NULL,
    rows_read   int NOT NULL,
    note        text NULL,
    loaded_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_nb_amount CHECK (amount >= 0),
    CONSTRAINT ck_nb_ref CHECK (btrim(ref) <> '')
);
SELECT audit.attach('finance.nelfund_batch');

CREATE TABLE finance.nelfund_row (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id      uuid NOT NULL REFERENCES finance.nelfund_batch(id),
    matric_no     text NOT NULL,
    name_on_remit text NULL,
    amount        numeric(12,2) NOT NULL,
    state         text NOT NULL DEFAULT 'UNMATCHED',
    student_id    uuid NULL REFERENCES people.student(id),
    why           text NULL,
    owner         text NULL,
    decided_at    timestamptz NULL,
    CONSTRAINT ck_nr_state CHECK (state IN ('MATCHED','UNMATCHED','REVERSED')),
    CONSTRAINT ck_nr_amount CHECK (amount > 0),
    CONSTRAINT ck_nr_matched CHECK (state <> 'MATCHED' OR student_id IS NOT NULL)
);
CREATE INDEX ix_nr_batch ON finance.nelfund_row (batch_id, state);
SELECT audit.attach('finance.nelfund_row');

-- the Fund's decision on each applicant, as the Bursary receives the list
CREATE TABLE finance.nelfund_status (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session     text NOT NULL,
    number      text NOT NULL,
    name        text NULL,
    state       text NOT NULL,
    reason      text NULL,
    correctable boolean NOT NULL DEFAULT false,
    student_id  uuid NULL REFERENCES people.student(id),
    loaded_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ns_state CHECK (state IN ('APPROVED','NOT_APPROVED','PENDING'))
);
CREATE UNIQUE INDEX uq_ns_number ON finance.nelfund_status (session, number);
SELECT audit.attach('finance.nelfund_status');

-- ── the wallet ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.wallet_balance(p_student uuid)
RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT coalesce(sum(CASE WHEN kind IN ('CREDIT','TOPUP') THEN amount ELSE -amount END), 0) FROM finance.wallet_entry WHERE student_id = p_student
$$;

-- a remittance loaded: every row matched on the register or left in suspense with its owner
CREATE OR REPLACE FUNCTION finance.load_nelfund_batch(p_ref text, p_session text, p_received date, p_note text, p_rows jsonb)
RETURNS TABLE (batch_id uuid, matched int, unmatched int, amount numeric)
LANGUAGE plpgsql AS $$
DECLARE b uuid := gen_random_uuid(); r jsonb; v_matric text; v_amount numeric; v_student uuid; v_status text; n_m int := 0; n_u int := 0; v_total numeric := 0;
BEGIN
    IF p_ref IS NULL OR btrim(p_ref) = '' THEN RAISE EXCEPTION 'a remittance carries the Fund''s reference' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'a remittance is rows: matriculation number, name, amount' USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.nelfund_batch (id, ref, session, received_on, amount, rows_read, note)
    VALUES (b, btrim(p_ref), p_session, coalesce(p_received, current_date), 0, jsonb_array_length(p_rows), nullif(btrim(p_note), ''));
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matricNo', r->>'matric_no', '')));
        v_amount := nullif(regexp_replace(coalesce(r->>'amount', '0'), '[^0-9.]', '', 'g'), '')::numeric;
        IF v_amount IS NULL OR v_amount <= 0 THEN
            INSERT INTO finance.nelfund_row (batch_id, matric_no, name_on_remit, amount, state, why, owner)
            VALUES (b, v_matric, r->>'name', 1, 'UNMATCHED', 'The amount on the row is not a number', 'Bursary');
            n_u := n_u + 1;
            CONTINUE;
        END IF;
        v_total := v_total + v_amount;
        SELECT id, status INTO v_student, v_status FROM people.student WHERE upper(matric_no) = v_matric;
        IF v_student IS NULL THEN
            INSERT INTO finance.nelfund_row (batch_id, matric_no, name_on_remit, amount, state, why, owner)
            VALUES (b, v_matric, r->>'name', v_amount, 'UNMATCHED', 'Matriculation number not on the register', 'Registry');
            n_u := n_u + 1;
        ELSIF v_status IN ('WITHDRAWN','EXPELLED','TRANSFERRED_OUT','DECEASED','GRADUATED') THEN
            INSERT INTO finance.nelfund_row (batch_id, matric_no, name_on_remit, amount, state, student_id, why, owner)
            VALUES (b, v_matric, r->>'name', v_amount, 'UNMATCHED', v_student, 'The student is ' || lower(v_status) || ' — reverse to the Fund', 'Bursary');
            n_u := n_u + 1;
        ELSE
            INSERT INTO finance.nelfund_row (batch_id, matric_no, name_on_remit, amount, state, student_id, decided_at)
            VALUES (b, v_matric, r->>'name', v_amount, 'MATCHED', v_student, now());
            INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note)
            VALUES (v_student, p_session, 'CREDIT', v_amount, btrim(p_ref), 'NELFUND institutional charges, ' || p_session);
            n_m := n_m + 1;
        END IF;
    END LOOP;
    UPDATE finance.nelfund_batch SET amount = v_total WHERE id = b;
    RETURN QUERY SELECT b, n_m, n_u, v_total;
END $$;

-- suspense is owned, not parked: the Registry confirms the identity, the Bursary reverses
CREATE OR REPLACE FUNCTION finance.match_nelfund_row(p_row uuid, p_student uuid, p_note text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE r finance.nelfund_row; b finance.nelfund_batch;
BEGIN
    SELECT * INTO r FROM finance.nelfund_row WHERE id = p_row FOR UPDATE;
    IF NOT FOUND OR r.state <> 'UNMATCHED' THEN RAISE EXCEPTION 'row % is not in suspense', p_row USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_student) THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
    IF p_note IS NULL OR btrim(p_note) = '' THEN
        RAISE EXCEPTION 'a match made by hand says on what evidence' USING ERRCODE = '23514',
            HINT = 'The identity was confirmed in person, or the number is a prior format of the same student''s: say which.';
    END IF;
    SELECT * INTO b FROM finance.nelfund_batch WHERE id = r.batch_id;
    UPDATE finance.nelfund_row SET state = 'MATCHED', student_id = p_student, decided_at = now(), why = r.why || ' — ' || btrim(p_note) WHERE id = p_row;
    INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note)
    VALUES (p_student, b.session, 'CREDIT', r.amount, b.ref, 'NELFUND institutional charges, ' || b.session || ' (matched by hand: ' || btrim(p_note) || ')');
END $$;

CREATE OR REPLACE FUNCTION finance.reverse_nelfund_row(p_row uuid, p_why text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE r finance.nelfund_row; b finance.nelfund_batch;
BEGIN
    SELECT * INTO r FROM finance.nelfund_row WHERE id = p_row FOR UPDATE;
    IF NOT FOUND OR r.state = 'REVERSED' THEN RAISE EXCEPTION 'row % is not reversible', p_row USING ERRCODE = '23514'; END IF;
    IF p_why IS NULL OR btrim(p_why) = '' THEN RAISE EXCEPTION 'a reversal to the Fund says why' USING ERRCODE = '23514'; END IF;
    SELECT * INTO b FROM finance.nelfund_batch WHERE id = r.batch_id;
    IF r.state = 'MATCHED' AND r.student_id IS NOT NULL THEN
        IF finance.wallet_balance(r.student_id) < r.amount THEN
            RAISE EXCEPTION 'the wallet has been applied; NGN % cannot be reversed from it', r.amount USING ERRCODE = '23514',
                HINT = 'A credit already applied to an invoice is recovered from the student, not reversed to the Fund.';
        END IF;
        INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note)
        VALUES (r.student_id, b.session, 'REVERSED', r.amount, b.ref, 'Reversed to the Fund: ' || btrim(p_why));
    END IF;
    UPDATE finance.nelfund_row SET state = 'REVERSED', why = btrim(p_why), decided_at = now() WHERE id = p_row;
END $$;

-- ── applying the wallet: the invoice settles through the same confirmation as every payment ──
CREATE OR REPLACE FUNCTION finance.apply_wallet(p_student uuid, p_session text, p_amount numeric)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE pos record; v_bal numeric; v_amount numeric; v_ref text;
BEGIN
    v_bal := finance.wallet_balance(p_student);
    SELECT * INTO pos FROM finance.position(p_student, p_session);
    v_amount := least(coalesce(p_amount, v_bal), v_bal, pos.balance);
    IF v_amount IS NULL OR v_amount <= 0 THEN
        RAISE EXCEPTION 'nothing to apply: the wallet holds NGN % and the balance for % is NGN %', v_bal, p_session, pos.balance USING ERRCODE = '23514',
            HINT = 'The wallet pays the session charge, and only what is outstanding on it.';
    END IF;
    v_ref := finance.new_reference(p_student, p_session, v_amount, NULL);
    INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note)
    VALUES (p_student, p_session, 'APPLIED', v_amount, v_ref, 'Applied to the ' || p_session || ' charge');
    PERFORM finance.confirm_payment(v_ref, 'NELFUND wallet', 'applied by the student from the wallet');
    RETURN v_ref;
END $$;

-- a top-up: a reference like every other; confirmed, it credits the wallet
CREATE OR REPLACE FUNCTION finance.wallet_topup_reference(p_student uuid, p_session text, p_amount numeric)
RETURNS text
LANGUAGE sql AS $$
    SELECT finance.new_purpose_reference(p_student, p_session, p_amount, 'Wallet top-up ' || p_session)
$$;

-- what the student sees: the statement, oldest first, with the running balance
CREATE OR REPLACE FUNCTION finance.wallet_statement(p_student uuid)
RETURNS TABLE (id uuid, at timestamptz, session text, kind text, amount numeric, reference text, note text, balance numeric)
LANGUAGE sql STABLE AS $$
    SELECT e.id, e.at, e.session, e.kind, e.amount, e.reference, e.note,
           sum(CASE WHEN e.kind IN ('CREDIT','TOPUP') THEN e.amount ELSE -e.amount END) OVER (ORDER BY e.at, e.id)
      FROM finance.wallet_entry e WHERE e.student_id = p_student ORDER BY e.at, e.id
$$;

-- the confirmation (V031) credits a top-up as it settles a fine
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
    ELSIF r.purpose LIKE 'Library fine%' THEN
        PERFORM library.settle_by_reference(r.reference);
    ELSIF r.purpose LIKE 'Wallet top-up%' THEN
        INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note)
        VALUES (r.student_id, r.session, 'TOPUP', r.amount, r.reference, 'Top-up paid by ' || coalesce(p_channel, 'the student'));
    END IF;
    SELECT * INTO reach FROM people.student_reach(r.student_id);
    SELECT * INTO pos FROM finance.position(r.student_id, r.session);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your payment is confirmed',
        'Your payment of NGN ' || r.amount::text || ' against reference ' || r.reference || ' is confirmed. Receipt ' || v_no || '. '
        || CASE WHEN r.purpose LIKE 'Transcript%' THEN 'Your transcript request is with the Registry.'
                WHEN r.purpose LIKE 'Hostel%' THEN 'Your bed space is confirmed; the Hostel screen names the hall and the room.'
                WHEN r.purpose LIKE 'Library fine%' THEN 'The Library fine is settled.'
                WHEN r.purpose LIKE 'Wallet top-up%' THEN 'Your wallet is credited.'
                WHEN pos.balance = 0 THEN 'Your charges for ' || r.session || ' are settled in full.'
                ELSE 'NGN ' || pos.balance::text || ' remains for ' || r.session || '.' END
        || ' Sign in to download the receipt.', 'student', r.student_id);
    PERFORM platform.queue_notice('SMS', reach.phone, 'Your payment is confirmed',
        'MOAUM: payment ' || r.reference || ' confirmed, receipt ' || v_no || '.', 'student', r.student_id);
    RETURN 'confirmed';
END $$;

-- the Fund's decisions, loaded as a list: approved, not approved with the reason, still with the Fund
CREATE OR REPLACE FUNCTION finance.load_nelfund_status(p_session text, p_rows jsonb)
RETURNS TABLE (loaded int, approved int, not_approved int, pending int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_no text; v_state text; v_reason text; n int := 0; a int := 0; na int := 0; pe int := 0;
BEGIN
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN RAISE EXCEPTION 'the list is rows' USING ERRCODE = '23514'; END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_no := upper(btrim(coalesce(r->>'number', r->>'matricNo', r->>'jambNo', '')));
        IF v_no = '' THEN CONTINUE; END IF;
        v_state := upper(replace(btrim(coalesce(r->>'state', r->>'status', 'PENDING')), ' ', '_'));
        IF v_state NOT IN ('APPROVED','NOT_APPROVED','PENDING') THEN
            v_state := CASE WHEN v_state LIKE 'APPROV%' THEN 'APPROVED' WHEN v_state LIKE 'NOT%' OR v_state LIKE 'REJ%' OR v_state LIKE 'REFUS%' OR v_state LIKE 'DECLIN%' THEN 'NOT_APPROVED' ELSE 'PENDING' END;
        END IF;
        v_reason := nullif(btrim(coalesce(r->>'reason', '')), '');
        INSERT INTO finance.nelfund_status (session, number, name, state, reason, correctable, student_id)
        VALUES (p_session, v_no, r->>'name', v_state, v_reason,
                v_state = 'NOT_APPROVED' AND (v_reason ILIKE '%BVN%' OR v_reason ILIKE '%institution code%' OR v_reason ILIKE '%name%match%'),
                (SELECT id FROM people.student WHERE upper(matric_no) = v_no OR upper(jamb_reg_no) = v_no LIMIT 1))
        ON CONFLICT (session, number) DO UPDATE SET name = EXCLUDED.name, state = EXCLUDED.state, reason = EXCLUDED.reason,
            correctable = EXCLUDED.correctable, student_id = EXCLUDED.student_id, loaded_at = now();
        n := n + 1;
        IF v_state = 'APPROVED' THEN a := a + 1; ELSIF v_state = 'NOT_APPROVED' THEN na := na + 1; ELSE pe := pe + 1; END IF;
    END LOOP;
    RETURN QUERY SELECT n, a, na, pe;
END $$;

COMMIT;
