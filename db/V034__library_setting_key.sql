-- ═══════════════════════════════════════════════════════════════════════════
-- V034 — the library rule's key is not called id
--
--   The audit spine (V002) reads a column named id as the row's own uuid.
--   library.setting (V031) is one row keyed by an integer called id, so the
--   first change to it was refused by the spine with "invalid input syntax
--   for type uuid". The key is renamed, the spine's subject key follows, and
--   the three functions that read the rule are restated over the new name.
--   Nothing else changes.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE library.setting RENAME COLUMN id TO row_no;
UPDATE audit.subject_key SET cols = ARRAY['row_no'] WHERE relid = 'library.setting'::regclass;

CREATE OR REPLACE FUNCTION library.issue(p_accession text, p_student uuid, p_person uuid)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE c library.copy; s library.setting; v uuid := gen_random_uuid(); n_open int; n_over int; v_item uuid;
BEGIN
    SELECT * INTO s FROM library.setting WHERE row_no = 1;
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
    SELECT * INTO s FROM library.setting WHERE row_no = 1;
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
    SELECT * INTO s FROM library.setting WHERE row_no = 1;
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

COMMIT;
