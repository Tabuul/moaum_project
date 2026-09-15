-- ═══════════════════════════════════════════════════════════════════════════
-- V140 — iam.update_lecturer: edit one teaching-staff member
--
--   The teaching-staff page can add a lecturer (the single-row importer does
--   that) and now edit one: names, contact, sex, rank, CONUASS and the home
--   department. Changing the department ends the old lecturer grant and adds
--   the new one, so teaching allocation follows the change. The staff number
--   (P<PNO>) and the sign-in are not touched here.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION iam.update_lecturer(
    p_id uuid, p_surname text, p_given text, p_email text, p_phone text,
    p_sex text, p_rank text, p_conuass int, p_department text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_dept text; v_old text; v_sex text;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'an edit is made by a person' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = p_id AND a.office_code = 'lecturer' AND a.scope_kind = 'department') THEN
        RAISE EXCEPTION 'that person is not a lecturer' USING ERRCODE = '23514';
    END IF;
    IF btrim(coalesce(p_surname, '')) = '' OR btrim(coalesce(p_given, '')) = '' THEN
        RAISE EXCEPTION 'a surname and given names are required' USING ERRCODE = '23514';
    END IF;

    -- match the department by code or name (tolerant of case / spacing / & vs AND)
    SELECT d.code INTO v_dept FROM ref.department d
     WHERE d.ended_on IS NULL
       AND ( upper(d.code) = upper(btrim(p_department))
          OR regexp_replace(replace(upper(d.name), '&', 'AND'), '[^A-Z0-9]', '', 'g')
           = regexp_replace(replace(upper(btrim(p_department)), '&', 'AND'), '[^A-Z0-9]', '', 'g') )
     LIMIT 1;
    IF v_dept IS NULL THEN
        RAISE EXCEPTION 'no department matching %', coalesce(nullif(btrim(p_department), ''), '(blank)') USING ERRCODE = '23514';
    END IF;

    UPDATE iam.person
       SET surname = btrim(p_surname), given_names = btrim(p_given),
           email = nullif(btrim(coalesce(p_email, '')), ''), phone = nullif(btrim(coalesce(p_phone, '')), '')
     WHERE id = p_id;

    -- the home department the record currently names
    SELECT home_department INTO v_old FROM hrm.staff_record WHERE person_id = p_id;

    -- move the lecturer office when the department changes
    IF v_old IS DISTINCT FROM v_dept THEN
        UPDATE iam.office_assignment SET valid_to = current_date
         WHERE person_id = p_id AND office_code = 'lecturer' AND scope_kind = 'department'
           AND scope_id IS DISTINCT FROM v_dept AND valid_to IS NULL;
        IF NOT EXISTS (SELECT 1 FROM iam.office_assignment
                        WHERE person_id = p_id AND office_code = 'lecturer' AND scope_kind = 'department'
                          AND scope_id = v_dept AND valid_to IS NULL) THEN
            INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
            VALUES (gen_random_uuid(), p_id, 'lecturer', 'department', v_dept,
                    'Teaching-staff edit (Users & roles)', v_actor, current_date);
        END IF;
    END IF;

    v_sex := upper(left(nullif(btrim(coalesce(p_sex, '')), ''), 1));
    IF v_sex NOT IN ('M', 'F') THEN v_sex := NULL; END IF;
    INSERT INTO hrm.staff_record (person_id, sex, present_rank, conuass_step, home_department)
    VALUES (p_id, v_sex, nullif(btrim(coalesce(p_rank, '')), ''), p_conuass, v_dept)
    ON CONFLICT (person_id) DO UPDATE SET
        sex = v_sex, present_rank = nullif(btrim(coalesce(p_rank, '')), ''),
        conuass_step = p_conuass, home_department = v_dept, updated_at = now();
END $$;

COMMENT ON FUNCTION iam.update_lecturer(uuid, text, text, text, text, text, text, int, text) IS
  'Edit a lecturer: names, contact, sex, rank, CONUASS and home department '
  '(moving the lecturer office when the department changes). Staff number and sign-in unchanged.';

COMMIT;
