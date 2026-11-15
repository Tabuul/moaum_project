-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V768 · In service read one way for staff — an HR exit counts from its effective date
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The user's word of 15 November 2026 ("align the identity reports and future-dated exits too"), after V765:
--    · an HR exit instrument (retirement, resignation, disengagement, dismissal) ends the employment with its effective date
--      (hrm.issue_movement_instrument, V072: status ENDED, ended_on the effective date). An employment so ended is still in force
--      until that date: credentials.staff_in_service counts a member of staff out of service in HR only once every employment has
--      ended by today — so a retirement issued ahead of its date no longer ends the card, the roster place or the check answer at once;
--    · V749's own reading of a member of staff in service (iam.staff_in_service — the blood-group self-confirmation, the identity
--      state the dashboard asks from — and credentials.identity_staff_rows — the Identity Completion report and its list) now
--      leaves out, as the staff card does since V765, someone out of service in HR;
--    · the category a staff row shows reads the employment in force on the same terms (one ended at a future date is still in force) —
--      the identity report, the card roster and the printed card's face, the roll's kind and absentees (V750) — and the HR record and
--      the staff register show a member of staff's status as the card reads it (hrm.staff_status: ENDED once out of service);
--    · "today" is Lagos today (V539: the databases run in UTC; an effective date is a Lagos date).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V768: in service read one way for staff — an HR exit counts from its effective date', true);

-- an employment in force: not ENDED, or ENDED from a date still to come — today being Lagos today (V539)
CREATE FUNCTION hrm.employment_in_force(p_status text, p_ended_on date)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT p_status <> 'ENDED' OR p_ended_on > (now() AT TIME ZONE 'Africa/Lagos')::date
$$;
COMMENT ON FUNCTION hrm.employment_in_force(text, date) IS
  'V768: whether an employment is in force — not ENDED, or ENDED by an exit instrument whose effective date (ended_on) is still to come, today read in Lagos. hrm.issue_movement_instrument (V072) ends an employment with its effective date at once.';

-- in service: not deactivated on the portal, and not out of service in HR — an employment on record, and none still in force
CREATE OR REPLACE FUNCTION credentials.staff_in_service(p_person uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM iam.person p WHERE p.id = p_person AND p.ended_on IS NULL)
       AND NOT (EXISTS (SELECT 1 FROM hrm.employment e WHERE e.person_id = p_person)
                AND NOT EXISTS (SELECT 1 FROM hrm.employment e WHERE e.person_id = p_person AND hrm.employment_in_force(e.status, e.ended_on)))
$$;
COMMENT ON FUNCTION credentials.staff_in_service(uuid) IS
  'V765, V768: whether a member of staff is in service — not deactivated on the portal (iam.person.ended_on), and not out of service in HR (an employment on record, every one ended by an exit instrument whose effective date has come). A staff card is valid while this holds; the check address answers LEFT when it does not; V749''s identity reading (iam.staff_in_service) reads it too.';

-- a member of staff's status as the HR record and the staff register show it: ENDED once out of service (deactivated, or every
-- employment ended), SUSPENDED while an employment in force is suspended, else ACTIVE
CREATE FUNCTION hrm.staff_status(p_person uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN NOT credentials.staff_in_service(p_person) THEN 'ENDED'
                WHEN EXISTS (SELECT 1 FROM hrm.employment e WHERE e.person_id = p_person AND e.status = 'SUSPENDED') THEN 'SUSPENDED'
                ELSE 'ACTIVE' END
$$;
COMMENT ON FUNCTION hrm.staff_status(uuid) IS
  'V768: a member of staff''s status as the HR record and the staff register show it — ENDED once out of service (credentials.staff_in_service: deactivated, or every employment ended by an exit whose effective date has come), SUSPENDED while an employment is suspended, else ACTIVE.';

-- V749's reading: V698's (a staff number, not left, an office today or the HR staff register) and in service as the card reads it
CREATE OR REPLACE FUNCTION iam.staff_in_service(p_person uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM iam.person pe
                    WHERE pe.id = p_person AND pe.staff_number IS NOT NULL AND btrim(pe.staff_number) <> '' AND pe.ended_on IS NULL
                      AND (EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = pe.id AND a.valid_from <= current_date
                                     AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                           OR EXISTS (SELECT 1 FROM hrm.staff_record r WHERE r.person_id = pe.id)))
       AND credentials.staff_in_service(p_person)
$$;
COMMENT ON FUNCTION iam.staff_in_service(uuid) IS
  'V749, V768: whether the person is a member of staff in the University''s service — a staff number, not left, an office today or a row on the HR staff register (V698), and not out of service in HR (credentials.staff_in_service: every employment ended by an exit whose effective date has come)';

-- the blood-group self-confirmation's refusal says the reading it now applies
DO $$
DECLARE d text; a text := 'members of staff in the University''''s service (a staff number, an office today or the HR staff register)'''; n int;
BEGIN
    d := pg_get_functiondef('credentials.confirm_my_blood_group(text,boolean)'::regprocedure);
    n := (length(d) - length(replace(d, a, ''))) / length(a);
    IF n <> 1 THEN RAISE EXCEPTION 'V768: credentials.confirm_my_blood_group is not as V749 left it (its refusal found % times)', n; END IF;
    EXECUTE replace(d, a, 'members of staff in the University''''s service (a staff number, an office today or the HR staff register, and not out of service in HR)''');
END $$;

-- the Identity Completion report's rows, the card roster, the roll's kind and absentees: the same reading, the category from the
-- employment in force
DO $$
DECLARE d text; i int; n int; f text;
    targets text[] := ARRAY['credentials.identity_staff_rows(text,text,text)', 'credentials.staff_card_roster(text,text,text)',
                            'hrm.roll_kind(uuid)', 'hrm.roll_absent(text,text[])'];
    edits text[][];
BEGIN
    FOREACH f IN ARRAY targets LOOP
        edits := CASE f
            WHEN 'credentials.identity_staff_rows(text,text,text)' THEN ARRAY[
                ARRAY['x.status <> ''ENDED''', 'hrm.employment_in_force(x.status, x.ended_on)'],
                ARRAY['       AND (off.yes OR sr.person_id IS NOT NULL)',
                      '       AND (off.yes OR sr.person_id IS NOT NULL)
       AND credentials.staff_in_service(pe.id)   /* V768: not out of service in HR */']]
            WHEN 'credentials.staff_card_roster(text,text,text)' THEN ARRAY[
                ARRAY['x.status <> ''ENDED''', 'hrm.employment_in_force(x.status, x.ended_on)'],
                ARRAY['credentials.staff_in_service(pe.id)   /* V765 */', 'credentials.staff_in_service(pe.id)   /* V765, V768 */']]
            -- the roll's kind (teaching or not) and its absentees: the category of the employment in force
            ELSE ARRAY[
                ARRAY['x.status <> ''ENDED''', 'hrm.employment_in_force(x.status, x.ended_on)']] END;
        d := pg_get_functiondef(f::regprocedure);
        FOR i IN 1 .. array_length(edits, 1) LOOP
            n := (length(d) - length(replace(d, edits[i][1], ''))) / length(edits[i][1]);
            IF n <> 1 THEN RAISE EXCEPTION 'V768: % is not as V749/V765 left it (% found % times)', f, left(edits[i][1], 50), n; END IF;
            d := replace(d, edits[i][1], edits[i][2]);
        END LOOP;
        EXECUTE d;
    END LOOP;
END $$;
DO $$
DECLARE c text := obj_description('credentials.identity_staff_rows(text,text,text)'::regprocedure, 'pg_proc');
BEGIN
    IF c IS NULL THEN RAISE EXCEPTION 'V768: credentials.identity_staff_rows has no description to extend'; END IF;
    EXECUTE format('COMMENT ON FUNCTION credentials.identity_staff_rows(text, text, text) IS %L',
                   c || ' V768: and not out of service in HR (credentials.staff_in_service), the category from the employment in force.');
END $$;

COMMIT;
