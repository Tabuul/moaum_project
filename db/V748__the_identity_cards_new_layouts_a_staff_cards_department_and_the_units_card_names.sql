-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V748 · The identity cards' new layouts: a staff card's department, and the units' card names
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's master prompt of 12 November 2026, "UPDATE STUDENT AND STAFF IDENTITY CARD LAYOUTS": the staff card prints
--  DEPARTMENT in place of UNIT, FACULTY and OFFICE — the department or administrative office the member of staff belongs to, read from
--  the authoritative organisational record (the HR staff record's home department or home unit), never from the staff category.
--  Registry staff read REGISTRY, Bursary staff BURSARY, ICT staff INFORMATION AND COMMUNICATION TECHNOLOGY, store staff STORES.
--    · The unit register names its units formally ("Office of the Registrar", "Directorate of ICT", "Bursary Department", "Central
--      Stores (BAEC)"); academic departments are short ("Accounting"). A unit now has a card name (ref.unit.card_name), the short name a
--      staff card prints, kept by ICT on the unit register and seeded from the brief (the University's decision of 12 November 2026:
--      a short card name per unit). A unit without one prints its nearest parent's — a Payroll (FAT) clerk is the Bursary's — and a
--      unit with none above it prints its formal name. Nothing is hard-coded in the card.
--    · credentials.staff_card_department(person): the academic department when the HR record names one (it is never replaced by the
--      unit, the faculty or the office), else the unit's card name, else the unit as the nominal roll spelled it. The single card, the
--      print of them all and the desk's list read it.
--  Nothing is deleted: the level, session, faculty, office, unit and validity stay where they are; only the cards stop printing them.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V748: the identity cards'' new layouts — a staff card''s department and the units'' card names', true);

ALTER TABLE ref.unit ADD COLUMN card_name text
    CONSTRAINT ck_unit_card_name CHECK (card_name IS NULL OR (btrim(card_name) = card_name AND card_name <> '' AND length(card_name) <= 60));
COMMENT ON COLUMN ref.unit.card_name IS
    'V748: the short name a staff identity card prints as the department (kept by ICT on the unit register); a unit without one prints its nearest parent''s, else its formal name.';

-- the brief's examples, where the register holds the unit (never over a name already set)
UPDATE ref.unit SET card_name = 'Registry' WHERE code = 'REGISTRY' AND card_name IS NULL;
UPDATE ref.unit SET card_name = 'Bursary' WHERE code = 'BURSARY' AND card_name IS NULL;
UPDATE ref.unit SET card_name = 'Information and Communication Technology' WHERE code = 'ICT' AND card_name IS NULL;
UPDATE ref.unit SET card_name = 'Stores' WHERE code IN ('BUR_BAEC_CENTRAL_STORES', 'BUR_BAEC_CEFTER_STORES', 'CHS_FINANCE_STORES') AND card_name IS NULL;

-- ── the name a unit prints on a staff card: its own card name, else its nearest parent's, else its formal name ──
CREATE FUNCTION ref.unit_card_name(p_code text) RETURNS text LANGUAGE sql STABLE AS $$
    WITH RECURSIVE up AS (
        SELECT u.code, u.parent_code, u.card_name, u.name, 0 AS depth FROM ref.unit u WHERE u.code = p_code
        UNION ALL
        SELECT p.code, p.parent_code, p.card_name, p.name, up.depth + 1 FROM up JOIN ref.unit p ON p.code = up.parent_code
         WHERE up.card_name IS NULL AND up.depth < 12
    )
    SELECT coalesce((SELECT card_name FROM up WHERE card_name IS NOT NULL ORDER BY depth LIMIT 1),
                    (SELECT name FROM up WHERE depth = 0));
$$;
COMMENT ON FUNCTION ref.unit_card_name(text) IS
    'V748: what a staff identity card prints for a unit — its card name, else its nearest parent''s, else its formal name.';

-- ── a staff card's department ──
CREATE FUNCTION credentials.staff_card_department(p_person uuid) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce(d.name, ref.unit_card_name(sr.home_unit), nullif(btrim(sr.unit_as_given), ''))
      FROM hrm.staff_record sr LEFT JOIN ref.department d ON d.code = sr.home_department
     WHERE sr.person_id = p_person;
$$;
COMMENT ON FUNCTION credentials.staff_card_department(uuid) IS
    'V748: the department a staff identity card prints — the academic department the HR record names, else the unit''s card name (ref.unit_card_name), else the unit as the nominal roll spelled it; NULL when the record names none (the card then reads the portal office).';

-- ── ICT sets a unit's card name, with a reason ──
CREATE FUNCTION ref.set_unit_card_name(p_code text, p_name text, p_reason text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_name text := nullif(regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g'), '');
        u ref.unit;
BEGIN
    IF coalesce(v_office, '') NOT IN ('ict', 'super') THEN
        RAISE EXCEPTION 'UNIT_CARD_NAME_OFFICE: a unit''s card name is set by ICT' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO u FROM ref.unit WHERE code = upper(btrim(coalesce(p_code, ''))) FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'UNIT_UNKNOWN: no unit is coded %', p_code USING ERRCODE = 'P0002';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'UNIT_CARD_NAME_REASON: say why the card name changes, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    IF v_name IS NOT NULL AND length(v_name) > 60 THEN
        RAISE EXCEPTION 'UNIT_CARD_NAME_LONG: a card name is sixty characters at most; a card prints it on two lines at most' USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', btrim(p_reason), true);
    UPDATE ref.unit SET card_name = v_name WHERE code = u.code;
    RETURN ref.unit_card_name(u.code);
END $$;
COMMENT ON FUNCTION ref.set_unit_card_name(text, text, text) IS
    'V748: ICT sets (or, with an empty name, clears) the short name a unit prints on staff identity cards; the change is on the audit trail with its reason. Returns what the unit''s cards now print.';

DO $$
DECLARE n_named int; n_staff int;
BEGIN
    SELECT count(*) INTO n_named FROM ref.unit WHERE card_name IS NOT NULL;
    SELECT count(*) INTO n_staff FROM hrm.staff_record sr JOIN ref.unit u ON u.code = sr.home_unit
     WHERE sr.home_department IS NULL AND ref.unit_card_name(u.code) IS DISTINCT FROM u.name;
    RAISE NOTICE 'V748: % units carry a card name; % members of staff placed in a unit print a shorter department than its formal name', n_named, n_staff;
END $$;

COMMIT;
