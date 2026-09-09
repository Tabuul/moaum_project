-- ═══════════════════════════════════════════════════════════════════════════
-- V031 — library circulation
--
--   The catalogue is items with copies; a loan is one copy to one patron
--   with a due date; a return closes it; a renewal moves the due date once
--   the copy is not reserved by somebody else. A fine is computed from the
--   days overdue at the daily rate in force, posted when the item is
--   returned, and settled as a payment reference like every other (V026).
--   The Library's clearance (LIBRARY unit, V013) is decided by the Library
--   on the clearance desk; this module tells that desk what stands against
--   a patron — items on loan and fines unpaid — so the hold names the item.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE SCHEMA IF NOT EXISTS library;
GRANT USAGE ON SCHEMA library TO app_student, app_finance, app_auditor;

CREATE TABLE library.setting (
    id            int PRIMARY KEY DEFAULT 1,
    loan_days     int NOT NULL DEFAULT 14,
    fine_per_day  numeric(8,2) NOT NULL DEFAULT 50,
    max_loans     int NOT NULL DEFAULT 3,
    max_renewals  int NOT NULL DEFAULT 1,
    CONSTRAINT ck_ls_one CHECK (id = 1),
    CONSTRAINT ck_ls_values CHECK (loan_days BETWEEN 1 AND 120 AND fine_per_day >= 0 AND max_loans BETWEEN 1 AND 20 AND max_renewals BETWEEN 0 AND 5)
);
-- the one row is seeded by the migration itself, before the table goes on the spine; every change after is attributed
INSERT INTO library.setting (id) VALUES (1);
SELECT audit.attach('library.setting');

CREATE TABLE library.item (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title      text NOT NULL,
    author     text NULL,
    edition    text NULL,
    year       int  NULL,
    isbn       text NULL,
    subject    text NULL,
    kind       text NOT NULL DEFAULT 'BOOK',
    ended_on   date NULL,
    CONSTRAINT ck_li_kind CHECK (kind IN ('BOOK','JOURNAL','THESIS','AUDIOVISUAL','REFERENCE')),
    CONSTRAINT ck_li_title CHECK (btrim(title) <> '')
);
SELECT audit.attach('library.item');

CREATE TABLE library.copy (
    accession   text PRIMARY KEY,
    item_id     uuid NOT NULL REFERENCES library.item(id),
    location    text NULL,
    state       text NOT NULL DEFAULT 'AVAILABLE',
    ended_on    date NULL,
    ended_reason text NULL,
    CONSTRAINT ck_lc_state CHECK (state IN ('AVAILABLE','ON_LOAN','RESERVED','LOST','WITHDRAWN')),
    CONSTRAINT ck_lc_accession CHECK (accession ~ '^[A-Z]{2,5}/[0-9]{4,8}$'),
    CONSTRAINT ck_lc_ended CHECK (ended_on IS NULL OR ended_reason IS NOT NULL)
);
CREATE INDEX ix_lc_item ON library.copy (item_id);
SELECT audit.attach('library.copy');

-- a patron is a student on the register or a member of staff; the loan names one of them
CREATE TABLE library.loan (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    accession    text NOT NULL REFERENCES library.copy(accession),
    student_id   uuid NULL REFERENCES people.student(id),
    person_id    uuid NULL REFERENCES iam.person(id),
    issued_at    timestamptz NOT NULL DEFAULT now(),
    due_on       date NOT NULL,
    renewals     int  NOT NULL DEFAULT 0,
    returned_at  timestamptz NULL,
    fine         numeric(10,2) NULL,
    fine_reference text NULL,
    fine_settled_at timestamptz NULL,
    fine_waived_at  timestamptz NULL,
    fine_waived_why text NULL,
    CONSTRAINT ck_ll_patron CHECK ((student_id IS NULL) <> (person_id IS NULL)),
    CONSTRAINT ck_ll_fine CHECK (fine IS NULL OR fine >= 0),
    CONSTRAINT ck_ll_waived CHECK (fine_waived_at IS NULL OR fine_waived_why IS NOT NULL)
);
CREATE INDEX ix_ll_student ON library.loan (student_id) WHERE student_id IS NOT NULL;
CREATE INDEX ix_ll_open ON library.loan (accession) WHERE returned_at IS NULL;
SELECT audit.attach('library.loan');

CREATE TABLE library.reservation (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id     uuid NOT NULL REFERENCES library.item(id),
    student_id  uuid NOT NULL REFERENCES people.student(id),
    reserved_at timestamptz NOT NULL DEFAULT now(),
    state       text NOT NULL DEFAULT 'WAITING',
    decided_at  timestamptz NULL,
    CONSTRAINT ck_lr_state CHECK (state IN ('WAITING','READY','FULFILLED','CANCELLED','EXPIRED'))
);
CREATE UNIQUE INDEX uq_lr_one_open ON library.reservation (item_id, student_id) WHERE state IN ('WAITING','READY');
SELECT audit.attach('library.reservation');

-- ── the acts ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION library.issue(p_accession text, p_student uuid, p_person uuid)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE c library.copy; s library.setting; v uuid := gen_random_uuid(); n_open int; n_over int; v_item uuid;
BEGIN
    SELECT * INTO s FROM library.setting WHERE id = 1;
    SELECT * INTO c FROM library.copy WHERE accession = upper(btrim(p_accession)) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no copy % on the shelf list', p_accession USING ERRCODE = '23503'; END IF;
    IF c.state <> 'AVAILABLE' AND c.state <> 'RESERVED' THEN
        RAISE EXCEPTION 'copy % is %', c.accession, lower(replace(c.state, '_', ' ')) USING ERRCODE = '23514',
            HINT = 'A copy on loan is returned before it is issued again; a lost or withdrawn copy is not issued.';
    END IF;
    IF (p_student IS NULL) = (p_person IS NULL) THEN
        RAISE EXCEPTION 'a loan is to one patron: a student or a member of staff' USING ERRCODE = '23514';
    END IF;
    IF p_student IS NOT NULL THEN
        SELECT count(*), count(*) FILTER (WHERE due_on < current_date) INTO n_open, n_over
          FROM library.loan WHERE student_id = p_student AND returned_at IS NULL;
        IF n_over > 0 THEN
            RAISE EXCEPTION 'the patron has % overdue item(s); nothing is issued until they are returned', n_over USING ERRCODE = '23514',
                HINT = 'Return the overdue items first. The fine is posted on return and settled like any other charge.';
        END IF;
        IF n_open >= s.max_loans THEN
            RAISE EXCEPTION 'the patron already has % items on loan, the most the rule allows', n_open USING ERRCODE = '23514';
        END IF;
        IF EXISTS (SELECT 1 FROM library.loan l WHERE l.student_id = p_student AND l.returned_at IS NOT NULL
                    AND l.fine IS NOT NULL AND l.fine > 0 AND l.fine_settled_at IS NULL AND l.fine_waived_at IS NULL) THEN
            RAISE EXCEPTION 'an unpaid fine stands against the patron' USING ERRCODE = '23514',
                HINT = 'The fine is settled against its payment reference, or waived by the Librarian with the reason on the record.';
        END IF;
        -- a reserved copy goes to the patron who reserved it
        IF c.state = 'RESERVED' THEN
            IF NOT EXISTS (SELECT 1 FROM library.reservation r WHERE r.item_id = c.item_id AND r.student_id = p_student AND r.state = 'READY') THEN
                RAISE EXCEPTION 'copy % is held for the patron who reserved it', c.accession USING ERRCODE = '23514';
            END IF;
            UPDATE library.reservation SET state = 'FULFILLED', decided_at = now() WHERE item_id = c.item_id AND student_id = p_student AND state = 'READY';
        END IF;
    END IF;
    INSERT INTO library.loan (id, accession, student_id, person_id, due_on) VALUES (v, c.accession, p_student, p_person, current_date + s.loan_days);
    UPDATE library.copy SET state = 'ON_LOAN' WHERE accession = c.accession;
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION library.give_back(p_accession text)
RETURNS TABLE (loan_id uuid, days_overdue int, fine numeric)
LANGUAGE plpgsql AS $$
DECLARE l library.loan; s library.setting; v_days int; v_fine numeric; v_next record;
BEGIN
    SELECT * INTO s FROM library.setting WHERE id = 1;
    SELECT * INTO l FROM library.loan WHERE accession = upper(btrim(p_accession)) AND returned_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'copy % is not on loan', p_accession USING ERRCODE = '23514'; END IF;
    v_days := greatest(0, current_date - l.due_on);
    v_fine := round(v_days * s.fine_per_day, 2);
    UPDATE library.loan SET returned_at = now(), fine = CASE WHEN v_fine > 0 THEN v_fine ELSE NULL END WHERE id = l.id;
    -- the copy is held for the next reservation, else it is available
    SELECT r.id, r.student_id INTO v_next FROM library.reservation r JOIN library.copy c ON c.item_id = r.item_id
     WHERE c.accession = l.accession AND r.state = 'WAITING' ORDER BY r.reserved_at LIMIT 1;
    IF FOUND THEN
        UPDATE library.reservation SET state = 'READY', decided_at = now() WHERE id = v_next.id;
        UPDATE library.copy SET state = 'RESERVED' WHERE accession = l.accession;
    ELSE
        UPDATE library.copy SET state = 'AVAILABLE' WHERE accession = l.accession;
    END IF;
    RETURN QUERY SELECT l.id, v_days, CASE WHEN v_fine > 0 THEN v_fine ELSE 0::numeric END;
END $$;

CREATE OR REPLACE FUNCTION library.renew(p_loan uuid)
RETURNS date
LANGUAGE plpgsql AS $$
DECLARE l library.loan; s library.setting; c library.copy;
BEGIN
    SELECT * INTO s FROM library.setting WHERE id = 1;
    SELECT * INTO l FROM library.loan WHERE id = p_loan AND returned_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no open loan %', p_loan USING ERRCODE = 'no_data_found'; END IF;
    IF l.renewals >= s.max_renewals THEN
        RAISE EXCEPTION 'this loan has been renewed % time(s), the most the rule allows', l.renewals USING ERRCODE = '23514',
            HINT = 'Return the item; it may be borrowed again once it has been on the shelf.';
    END IF;
    IF l.due_on < current_date THEN
        RAISE EXCEPTION 'an overdue item is returned, not renewed' USING ERRCODE = '23514',
            HINT = 'The fine runs from the due date; bring the item in.';
    END IF;
    SELECT * INTO c FROM library.copy WHERE accession = l.accession;
    IF EXISTS (SELECT 1 FROM library.reservation r WHERE r.item_id = c.item_id AND r.state = 'WAITING'
                AND (l.student_id IS NULL OR r.student_id <> l.student_id)) THEN
        RAISE EXCEPTION 'another patron is waiting for this item; it is not renewed' USING ERRCODE = '23514';
    END IF;
    UPDATE library.loan SET due_on = due_on + s.loan_days, renewals = renewals + 1 WHERE id = l.id;
    RETURN l.due_on + s.loan_days;
END $$;

CREATE OR REPLACE FUNCTION library.reserve(p_item uuid, p_student uuid)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid();
BEGIN
    IF NOT EXISTS (SELECT 1 FROM library.item WHERE id = p_item AND ended_on IS NULL) THEN
        RAISE EXCEPTION 'no such item' USING ERRCODE = '23503';
    END IF;
    IF EXISTS (SELECT 1 FROM library.copy WHERE item_id = p_item AND state = 'AVAILABLE') THEN
        RAISE EXCEPTION 'a copy is on the shelf; borrow it rather than reserving it' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM library.loan l JOIN library.copy c ON c.accession = l.accession WHERE c.item_id = p_item AND l.student_id = p_student AND l.returned_at IS NULL) THEN
        RAISE EXCEPTION 'you have a copy of this item on loan already' USING ERRCODE = '23505';
    END IF;
    INSERT INTO library.reservation (id, item_id, student_id) VALUES (v, p_item, p_student);
    RETURN v;
END $$;

-- ── the fine: a reference like every other, settled on confirmation ─────
CREATE OR REPLACE FUNCTION library.fine_reference(p_loan uuid)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE l library.loan; v_session text; v_ref text;
BEGIN
    SELECT * INTO l FROM library.loan WHERE id = p_loan;
    IF NOT FOUND OR l.student_id IS NULL THEN RAISE EXCEPTION 'no student loan %', p_loan USING ERRCODE = 'no_data_found'; END IF;
    IF l.fine IS NULL OR l.fine = 0 OR l.fine_settled_at IS NOT NULL OR l.fine_waived_at IS NOT NULL THEN
        RAISE EXCEPTION 'no fine stands against this loan' USING ERRCODE = '23514';
    END IF;
    IF l.fine_reference IS NOT NULL AND EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = l.fine_reference AND expires_at > now() AND confirmed_at IS NULL) THEN
        RETURN l.fine_reference;
    END IF;
    SELECT name INTO v_session FROM policy.academic_session WHERE state = 'CURRENT';
    v_ref := finance.new_purpose_reference(l.student_id, coalesce(v_session, '2026/2027'), l.fine, 'Library fine ' || l.id::text);
    UPDATE library.loan SET fine_reference = v_ref WHERE id = l.id;
    RETURN v_ref;
END $$;

CREATE OR REPLACE FUNCTION library.settle_by_reference(p_reference text)
RETURNS void
LANGUAGE sql AS $$
    UPDATE library.loan SET fine_settled_at = now() WHERE fine_reference = p_reference AND fine_settled_at IS NULL;
$$;

CREATE OR REPLACE FUNCTION library.waive_fine(p_loan uuid, p_why text)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF p_why IS NULL OR btrim(p_why) = '' THEN RAISE EXCEPTION 'a fine is waived for a reason on the record' USING ERRCODE = '23514'; END IF;
    UPDATE library.loan SET fine_waived_at = now(), fine_waived_why = btrim(p_why) WHERE id = p_loan AND fine IS NOT NULL AND fine_settled_at IS NULL AND fine_waived_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'no unsettled fine on loan %', p_loan USING ERRCODE = 'no_data_found'; END IF;
END $$;

-- ── what stands against a patron: what the clearance desk reads ─────────
CREATE OR REPLACE FUNCTION library.standing(p_student uuid)
RETURNS TABLE (on_loan int, overdue int, fines_unpaid numeric, clear boolean)
LANGUAGE sql STABLE AS $$
    SELECT count(*) FILTER (WHERE returned_at IS NULL)::int,
           count(*) FILTER (WHERE returned_at IS NULL AND due_on < current_date)::int,
           coalesce(sum(fine) FILTER (WHERE returned_at IS NOT NULL AND fine_settled_at IS NULL AND fine_waived_at IS NULL), 0),
           count(*) FILTER (WHERE returned_at IS NULL) = 0
               AND coalesce(sum(fine) FILTER (WHERE returned_at IS NOT NULL AND fine_settled_at IS NULL AND fine_waived_at IS NULL), 0) = 0
      FROM library.loan WHERE student_id = p_student
$$;

-- the confirmation (V030) settles a library fine as it settles a hostel fee
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
    END IF;
    SELECT * INTO reach FROM people.student_reach(r.student_id);
    SELECT * INTO pos FROM finance.position(r.student_id, r.session);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your payment is confirmed',
        'Your payment of NGN ' || r.amount::text || ' against reference ' || r.reference || ' is confirmed. Receipt ' || v_no || '. '
        || CASE WHEN r.purpose LIKE 'Transcript%' THEN 'Your transcript request is with the Registry.'
                WHEN r.purpose LIKE 'Hostel%' THEN 'Your bed space is confirmed; the Hostel screen names the hall and the room.'
                WHEN r.purpose LIKE 'Library fine%' THEN 'The Library fine is settled.'
                WHEN pos.balance = 0 THEN 'Your charges for ' || r.session || ' are settled in full.'
                ELSE 'NGN ' || pos.balance::text || ' remains for ' || r.session || '.' END
        || ' Sign in to download the receipt.', 'student', r.student_id);
    PERFORM platform.queue_notice('SMS', reach.phone, 'Your payment is confirmed',
        'MOAUM: payment ' || r.reference || ' confirmed, receipt ' || v_no || '.', 'student', r.student_id);
    RETURN 'confirmed';
END $$;

COMMIT;
