-- ═══════════════════════════════════════
-- V698 — Staff identity cards issued and printed in bulk by the Security Unit
--
--   The University's word of 29 October 2026: "add staff id card printing to chief security officer dashboard, let them be able to
--   print all the staff id cards too".
--
--   A staff identity card (V439) was issued one at a time on a staff number, to a member of staff holding an office on the portal
--   today, and printed one at a time. The non-teaching staff are on the HR staff register (hrm.staff_record, from the nominal roll)
--   but most hold no portal office: on the copy of 21 October 2026, 870 of the 1,541 staff in service, none of whom could be issued
--   a card.
--
--   1 · credentials.issue_staff_card (restated from V439): a member of staff in the University's service — an office today, or on the
--       HR staff register — may be issued a card; a staff number and not having left are asked as before (STAFF_CARD_NO_NUMBER,
--       STAFF_CARD_ENDED; STAFF_CARD_NO_OFFICE for one neither in office nor on the register).
--   2 · credentials.staff_card_roster(faculty, unit, q): every member of staff in service with what the card prints of them (rank,
--       category, department or unit, faculty), whether a photograph is on file, and the card in force if any — the Security Unit's
--       list to issue and print from.
--   3 · credentials.issue_staff_cards(persons, reason): a card for each person named who has none in force, one transaction; a person
--       with a card in force is passed over (HAS_CARD), a refusal is answered by its code; every card as one issued alone.
-- ═══════════════════════════════════════
BEGIN;

-- ── 1 · who may be issued a card ─────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION credentials.issue_staff_card(p_person uuid, p_reason text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
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
    -- V698: in the University's service — an office on the portal today, or the HR staff register (the non-teaching staff)
    IF NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = p_person AND a.valid_from <= current_date
                      AND (a.valid_to IS NULL OR a.valid_to >= current_date))
       AND NOT EXISTS (SELECT 1 FROM hrm.staff_record r WHERE r.person_id = p_person) THEN
        RAISE EXCEPTION 'STAFF_CARD_NO_OFFICE: % % holds no office at the University today and is not on the HR staff register', p.given_names, p.surname
            USING ERRCODE = '23514';
    END IF;
    IF who IS NULL THEN RAISE EXCEPTION 'STAFF_CARD_NO_ISSUER: a card is issued by a person' USING ERRCODE = '23514'; END IF;
    UPDATE credentials.staff_identity_card SET state = 'REPLACED', ended_at = now(), ended_reason = coalesce(nullif(btrim(p_reason), ''), 'replaced')
     WHERE person_id = p_person AND state = 'ISSUED';
    v_no := 'MOAUM/SID/' || to_char(current_date, 'YY') || '/'
            || lpad(platform.next_number('STAFF_IDENTITY_CARD', 'UNIVERSITY', to_char(current_date, 'YYYY'))::text, 5, '0');
    INSERT INTO credentials.staff_identity_card (person_id, card_no, issued_by, issued_office, valid_to)
    VALUES (p_person, v_no, who, coalesce(office, 'unknown'), make_date(extract(year FROM current_date)::int + 3, 12, 31));
    RETURN v_no;
END $function$;

-- ── 2 · the staff in service, with what the card prints and the card in force ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION credentials.staff_card_roster(p_faculty text DEFAULT NULL, p_unit text DEFAULT NULL, p_q text DEFAULT NULL)
RETURNS TABLE (person_id uuid, staff_number text, surname text, given_names text, category text, rank text,
               unit_code text, unit text, faculty_code text, faculty text, has_photo boolean, blood_group text,
               in_office boolean, card_id uuid, card_no text, issued_at timestamptz, valid_to date)
LANGUAGE sql STABLE AS $function$
    SELECT pe.id, pe.staff_number, pe.surname, pe.given_names,
           coalesce(e.category, sr.category) AS category, sr.present_rank AS rank,
           coalesce(sr.home_department, sr.home_unit) AS unit_code,
           coalesce(dp.name, u.name, sr.unit_as_given) AS unit,
           coalesce(dp.faculty_code, sr.home_faculty) AS faculty_code, f.name AS faculty,
           EXISTS (SELECT 1 FROM hrm.staff_photo ph WHERE ph.person_id = pe.id) AS has_photo,
           credentials.staff_blood_group(pe.id) AS blood_group,
           off.yes AS in_office,
           c.id, c.card_no, c.issued_at, c.valid_to
      FROM iam.person pe
      LEFT JOIN hrm.staff_record sr ON sr.person_id = pe.id
      LEFT JOIN LATERAL (SELECT x.category FROM hrm.employment x WHERE x.person_id = pe.id AND x.status <> 'ENDED' ORDER BY x.appointment_date DESC NULLS LAST LIMIT 1) e ON true
      LEFT JOIN ref.department dp ON dp.code = sr.home_department
      LEFT JOIN ref.unit u ON u.code = sr.home_unit
      LEFT JOIN ref.faculty f ON f.code = coalesce(dp.faculty_code, sr.home_faculty)
      CROSS JOIN LATERAL (SELECT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = pe.id AND a.valid_from <= current_date
                                            AND (a.valid_to IS NULL OR a.valid_to >= current_date)) AS yes) off
      LEFT JOIN credentials.staff_identity_card c ON c.person_id = pe.id AND c.state = 'ISSUED'
     WHERE pe.staff_number IS NOT NULL AND btrim(pe.staff_number) <> '' AND pe.ended_on IS NULL
       AND (off.yes OR sr.person_id IS NOT NULL)
       AND (p_faculty IS NULL OR coalesce(dp.faculty_code, sr.home_faculty) = p_faculty)
       AND (p_unit IS NULL OR coalesce(sr.home_department, sr.home_unit) = p_unit)
       AND (p_q IS NULL OR pe.staff_number ILIKE '%' || p_q || '%' OR pe.surname ILIKE '%' || p_q || '%' OR pe.given_names ILIKE '%' || p_q || '%'
            OR c.card_no ILIKE '%' || p_q || '%')
     ORDER BY pe.surname, pe.given_names, pe.staff_number
$function$;
COMMENT ON FUNCTION credentials.staff_card_roster(text, text, text) IS
  'V698: the staff in the University''s service (an office today, or the HR staff register; a staff number; not left), with what the identity card prints and the card in force — the Security Unit''s list to issue and print from.';

-- ── 3 · cards for many at once ──────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION credentials.issue_staff_cards(p_persons uuid[], p_reason text DEFAULT NULL)
RETURNS TABLE (person_id uuid, staff_number text, outcome text, card_no text)
LANGUAGE plpgsql AS $function$
DECLARE v uuid; v_no text; v_num text;
BEGIN
    IF p_persons IS NULL OR cardinality(p_persons) = 0 THEN
        RAISE EXCEPTION 'STAFF_CARDS_NONE: name the members of staff to issue cards to' USING ERRCODE = '23514';
    END IF;
    IF cardinality(p_persons) > 5000 THEN
        RAISE EXCEPTION 'STAFF_CARDS_TOO_MANY: % at once is more than the 5,000 a single issue takes', cardinality(p_persons) USING ERRCODE = '23514';
    END IF;
    FOR v IN SELECT DISTINCT x FROM unnest(p_persons) x LOOP
        SELECT pe.staff_number INTO v_num FROM iam.person pe WHERE pe.id = v;
        IF EXISTS (SELECT 1 FROM credentials.staff_identity_card c WHERE c.person_id = v AND c.state = 'ISSUED') THEN
            person_id := v; staff_number := v_num; outcome := 'HAS_CARD';
            card_no := (SELECT c.card_no FROM credentials.staff_identity_card c WHERE c.person_id = v AND c.state = 'ISSUED');
            RETURN NEXT; CONTINUE;
        END IF;
        BEGIN
            v_no := credentials.issue_staff_card(v, p_reason);
            person_id := v; staff_number := v_num; outcome := 'ISSUED'; card_no := v_no;
        EXCEPTION WHEN check_violation THEN
            person_id := v; staff_number := v_num; outcome := split_part(SQLERRM, ':', 1); card_no := NULL;
        END;
        RETURN NEXT;
    END LOOP;
END $function$;
COMMENT ON FUNCTION credentials.issue_staff_cards(uuid[], text) IS
  'V698: a staff identity card for each person named with none in force (HAS_CARD otherwise), each as credentials.issue_staff_card issues it; a refusal answered by its code.';

-- how many staff in service hold a card, and how many may now be issued one
DO $$
DECLARE n int; c int; o int;
BEGIN
    SELECT count(*), count(card_id), count(*) FILTER (WHERE NOT in_office) INTO n, c, o FROM credentials.staff_card_roster(NULL, NULL, NULL);
    RAISE NOTICE 'V698: % staff in service, % with a card in force; % of them on the HR staff register with no portal office, issuable now', n, c, o;
END $$;

COMMIT;
