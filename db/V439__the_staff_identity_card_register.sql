-- ═══════════════════════════════════════
-- V439 — the staff identity card register (portal gap audit, GAP-023)
--
--   A staff identity card was drawn on the fly: a serial made up at print time (STF-…-year) and a QR holding only that text, with
--   no record behind it — nothing to scan against, nothing to report lost. The staff card now has a register like the students'
--   (V027): a card number of its own, issued by a person, valid to a date, one live card per member of staff, ended when replaced or
--   reported lost. The card's QR carries an address signed over the card number (/verify/staffcard), answered by the API.
-- ═══════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V439: the staff identity card register', true);

CREATE TABLE credentials.staff_identity_card (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id    uuid NOT NULL REFERENCES iam.person (id),
    card_no      text NOT NULL UNIQUE,
    issued_at    timestamptz NOT NULL DEFAULT now(),
    issued_by    uuid NOT NULL REFERENCES iam.person (id),
    issued_office text NOT NULL,
    valid_to     date NOT NULL,
    state        text NOT NULL DEFAULT 'ISSUED',
    ended_at     timestamptz NULL,
    ended_reason text NULL,
    CONSTRAINT ck_staff_card_state CHECK (state IN ('ISSUED', 'LOST', 'REPLACED', 'RETURNED')),
    CONSTRAINT ck_staff_card_no CHECK (card_no ~ '^MOAUM/SID/[0-9]{2}/[0-9]{5}$'),
    CONSTRAINT ck_staff_card_ended CHECK ((state = 'ISSUED') = (ended_at IS NULL)),
    CONSTRAINT ck_staff_card_reason CHECK (state = 'ISSUED' OR ended_reason IS NOT NULL)
);
CREATE UNIQUE INDEX uq_staff_card_live ON credentials.staff_identity_card (person_id) WHERE state = 'ISSUED';
CREATE INDEX ix_staff_card_issued_by ON credentials.staff_identity_card (issued_by);
COMMENT ON TABLE credentials.staff_identity_card IS
  'V439: the staff identity cards the University issued — one live card per member of staff, ended when replaced or reported lost. The card''s QR carries /verify/staffcard with a code signed over the card number.';
SELECT audit.attach('credentials.staff_identity_card');

-- issued on the staff number, to a member of staff holding an office; one live card at a time, the old one replaced
CREATE FUNCTION credentials.issue_staff_card(p_person uuid, p_reason text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE p iam.person; v_no text; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    SELECT * INTO p FROM iam.person WHERE id = p_person;
    IF NOT FOUND THEN RAISE EXCEPTION 'STAFF_CARD_NO_PERSON: no such member of staff' USING ERRCODE = '23514'; END IF;
    IF p.staff_number IS NULL OR btrim(p.staff_number) = '' THEN
        RAISE EXCEPTION 'STAFF_CARD_NO_NUMBER: a staff identity card carries the staff number, and % % has none on record', p.given_names, p.surname
            USING ERRCODE = '23514';
    END IF;
    IF p.ended_on IS NOT NULL THEN
        RAISE EXCEPTION 'STAFF_CARD_ENDED: % % left the University on %', p.given_names, p.surname, p.ended_on USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = p_person AND a.valid_from <= current_date
                      AND (a.valid_to IS NULL OR a.valid_to >= current_date)) THEN
        RAISE EXCEPTION 'STAFF_CARD_NO_OFFICE: % % holds no office at the University today', p.given_names, p.surname USING ERRCODE = '23514';
    END IF;
    IF who IS NULL THEN RAISE EXCEPTION 'STAFF_CARD_NO_ISSUER: a card is issued by a person' USING ERRCODE = '23514'; END IF;
    UPDATE credentials.staff_identity_card SET state = 'REPLACED', ended_at = now(), ended_reason = coalesce(nullif(btrim(p_reason), ''), 'replaced')
     WHERE person_id = p_person AND state = 'ISSUED';
    v_no := 'MOAUM/SID/' || to_char(current_date, 'YY') || '/'
            || lpad(platform.next_number('STAFF_IDENTITY_CARD', 'UNIVERSITY', to_char(current_date, 'YYYY'))::text, 5, '0');
    INSERT INTO credentials.staff_identity_card (person_id, card_no, issued_by, issued_office, valid_to)
    VALUES (p_person, v_no, who, coalesce(office, 'unknown'), make_date(extract(year FROM current_date)::int + 3, 12, 31));
    RETURN v_no;
END $$;
COMMENT ON FUNCTION credentials.issue_staff_card(uuid, text) IS
  'V439: a staff identity card for a member of staff with a staff number and a live office; any live card is replaced. Valid to 31 December three years on, as the printed card had it.';

CREATE FUNCTION credentials.report_staff_card_lost(p_person uuid, p_reason text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    UPDATE credentials.staff_identity_card SET state = 'LOST', ended_at = now(), ended_reason = coalesce(nullif(btrim(p_reason), ''), 'reported lost')
     WHERE person_id = p_person AND state = 'ISSUED';
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

COMMIT;
