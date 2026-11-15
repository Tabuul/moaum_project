-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V765 · A staff identity card is valid while its holder is in service
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's decision of 15 November 2026: a staff identity card no longer expires on a date (V439 made each card valid to
--  31 December three years after the year it was issued). It holds while its holder is in service, and ends only when it is
--  replaced, reported lost, or its holder leaves — deactivated on the portal (iam.person.ended_on) or out of service in HR (an
--  employment ended by an exit instrument and none in force): credentials.staff_in_service, which the check address reads to answer
--  "carried by someone who has left the University". Cards in force on 15 November 2026 lose their end date too; a card ended before
--  then keeps the date it was issued with, as its history. Student identity cards keep theirs.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V765: a staff identity card is valid while its holder is in service', true);

ALTER TABLE credentials.staff_identity_card ALTER COLUMN valid_to DROP NOT NULL;
COMMENT ON COLUMN credentials.staff_identity_card.valid_to IS
  'V439: the date the card was valid to (31 December three years after its year of issue); V765: none since 15 November 2026 — a staff card is valid while its holder is in service (credentials.staff_in_service). A card ended before 15 November 2026 keeps the date it was issued with; a card in force then, or issued since, has none.';

-- in service: not deactivated on the portal, and not out of service in HR (an employment on record, none of them in force) — read for
-- every member of staff on the card roster, so the employments are found by person
CREATE INDEX IF NOT EXISTS ix_employment_person ON hrm.employment (person_id);
CREATE FUNCTION credentials.staff_in_service(p_person uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM iam.person p WHERE p.id = p_person AND p.ended_on IS NULL)
       AND NOT (EXISTS (SELECT 1 FROM hrm.employment e WHERE e.person_id = p_person)
                AND NOT EXISTS (SELECT 1 FROM hrm.employment e WHERE e.person_id = p_person AND e.status <> 'ENDED'))
$$;
COMMENT ON FUNCTION credentials.staff_in_service(uuid) IS
  'V765: whether a staff card''s holder is in service — not deactivated on the portal (iam.person.ended_on), and not out of service in HR (an employment on record, every one ENDED by an exit instrument). A staff card is valid while this holds; the check address answers LEFT when it does not.';

-- the live cards lose their end date
UPDATE credentials.staff_identity_card SET valid_to = NULL WHERE state = 'ISSUED' AND valid_to IS NOT NULL;

-- the card issued from now on carries none, and none is issued to someone out of service in HR (the check address would answer LEFT)
DO $$
DECLARE d text; i int; n int;
    edits text[][] := ARRAY[
      ARRAY['make_date(extract(year FROM current_date)::int + 3, 12, 31)', 'NULL::date   /* V765: valid while its holder is in service */'],
      ARRAY['        RAISE EXCEPTION ''STAFF_CARD_ENDED: % % left the University on %'', p.given_names, p.surname, p.ended_on USING ERRCODE = ''23514'';
    END IF;',
            '        RAISE EXCEPTION ''STAFF_CARD_ENDED: % % left the University on %'', p.given_names, p.surname, p.ended_on USING ERRCODE = ''23514'';
    END IF;
    -- V765: out of service in HR (every employment ended by an exit instrument): no card — valid while in service, it would be none
    IF NOT credentials.staff_in_service(p_person) THEN
        RAISE EXCEPTION ''STAFF_CARD_LEFT: % % is out of service in HR (every employment ended)'', p.given_names, p.surname USING ERRCODE = ''23514'';
    END IF;']];
BEGIN
    d := pg_get_functiondef('credentials.issue_staff_card(uuid,text)'::regprocedure);
    FOR i IN 1 .. array_length(edits, 1) LOOP
        n := (length(d) - length(replace(d, edits[i][1], ''))) / length(edits[i][1]);
        IF n <> 1 THEN RAISE EXCEPTION 'V765: credentials.issue_staff_card is not as V698 left it (% found % times)', left(edits[i][1], 50), n; END IF;
        d := replace(d, edits[i][1], edits[i][2]);
    END LOOP;
    EXECUTE d;
END $$;

-- the roster the Security Unit issues from lists only the staff in service
DO $$
DECLARE d text; a text := 'AND pe.ended_on IS NULL'; n int;
BEGIN
    d := pg_get_functiondef('credentials.staff_card_roster(text,text,text)'::regprocedure);
    n := (length(d) - length(replace(d, a, ''))) / length(a);
    IF n <> 1 THEN RAISE EXCEPTION 'V765: credentials.staff_card_roster is not as V698 left it (its filter found % times)', n; END IF;
    EXECUTE replace(d, a, 'AND pe.ended_on IS NULL AND credentials.staff_in_service(pe.id)   /* V765 */');
END $$;
COMMENT ON FUNCTION credentials.issue_staff_card(uuid, text) IS
  'V439, V698, V765: a staff identity card issued on the staff number to a member of staff in service (an office today, or the HR staff register), MOAUM/SID/YY/NNNNN, the card in force before it replaced; no end date — valid while its holder is in service (credentials.staff_in_service).';

COMMIT;
