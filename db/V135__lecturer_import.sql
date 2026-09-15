-- ═══════════════════════════════════════════════════════════════════════════
-- V135 — iam.import_lecturers: bulk-onboard sign-in-able lecturers
--
--   Each row becomes a lecturer the same three ways the Users & roles screen
--   makes one, one row at a time:
--     1. the person            (iam.person, by staff number)
--     2. the sign-in           (iam.credential: username = staff number,
--                               password = staff number, must_change = true)
--     3. the lecturer office   (iam.office_assignment: office 'lecturer',
--                               scope_kind 'department', scope_id = the
--                               department CODE — exactly what teaching
--                               allocation reads: scope_kind='department'
--                               AND scope_id = <dept>)
--
--   Resilient and idempotent: each row runs in its own savepoint, a bad row is
--   skipped (counted, first error returned) and the rest go on; re-uploading
--   does not duplicate — an existing person is reused, an existing sign-in is
--   left untouched (no password reset on re-upload), and a live lecturer grant
--   for the same department is not added twice (uq_grant_one_live).
--
--   Runs as the caller (app_iam, which may INSERT across the iam schema and
--   SELECT ref.department) inside the request's audit context — the person,
--   grant and credential-event are attributed to the signed-in officer. The
--   password hash is bcrypt cost 12 (ck_credential_hash: $2%$12$%).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION iam.import_lecturers(p_rows jsonb)
RETURNS TABLE (rows int, created int, existing int, credentialed int, granted int, skipped int, first_error text)
LANGUAGE plpgsql AS $$
DECLARE
    v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    r jsonb;
    v_staff text; v_surname text; v_given text; v_dept text; v_email text; v_phone text;
    v_pid uuid;
    n int := 0; c_created int := 0; c_exist int := 0; c_cred int := 0; c_grant int := 0; c_skip int := 0;
    v_err text := NULL;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'lecturers are loaded by a person' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'the file is rows: staff number, surname, given names, department' USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_staff := btrim(coalesce(r->>'staff_number', r->>'staffNumber', r->>'staffno', r->>'staff', ''));
        -- skip a blank line or a header row that slipped through
        CONTINUE WHEN v_staff = '' OR v_staff ~* '^staff';
        n := n + 1;
        v_surname := btrim(coalesce(r->>'surname', r->>'lastname', r->>'last_name', ''));
        v_given   := btrim(coalesce(r->>'given_names', r->>'givenNames', r->>'othernames', r->>'other_names', r->>'firstname', r->>'first_name', ''));
        v_dept    := upper(btrim(coalesce(r->>'department_code', r->>'departmentCode', r->>'department', r->>'dept', r->>'deptCode', '')));
        v_email   := nullif(btrim(coalesce(r->>'email', '')), '');
        v_phone   := nullif(btrim(coalesce(r->>'phone', r->>'phone_number', '')), '');

        IF v_surname = '' OR v_given = '' OR v_dept = '' THEN
            c_skip := c_skip + 1;
            IF v_err IS NULL THEN v_err := 'Row ' || n || ' (' || v_staff || '): surname, given names and department are all required'; END IF;
            CONTINUE;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM ref.department d WHERE upper(d.code) = v_dept AND d.ended_on IS NULL) THEN
            c_skip := c_skip + 1;
            IF v_err IS NULL THEN v_err := 'Row ' || n || ' (' || v_staff || '): no department with code ' || v_dept; END IF;
            CONTINUE;
        END IF;

        BEGIN
            -- 1. the person, by staff number
            SELECT id INTO v_pid FROM iam.person WHERE staff_number = v_staff;
            IF v_pid IS NULL THEN
                v_pid := gen_random_uuid();
                INSERT INTO iam.person (id, staff_number, surname, given_names, email, phone)
                VALUES (v_pid, v_staff, v_surname, v_given, v_email, v_phone);
                c_created := c_created + 1;
            ELSE
                c_exist := c_exist + 1;
                -- fill in a missing email/phone from the file, but never overwrite one already on record
                UPDATE iam.person
                   SET email = coalesce(email, v_email), phone = coalesce(phone, v_phone)
                 WHERE id = v_pid AND (email IS NULL OR phone IS NULL);
            END IF;

            -- 2. the sign-in — only if the person has none yet (re-upload never resets a password)
            IF NOT EXISTS (SELECT 1 FROM iam.credential WHERE person_id = v_pid) THEN
                INSERT INTO iam.credential (person_id, username, password_hash, must_change, set_by)
                VALUES (v_pid, lower(v_staff), crypt(v_staff, gen_salt('bf', 12)), true, v_actor);
                INSERT INTO iam.credential_event (id, person_id, kind, by_person, note)
                VALUES (gen_random_uuid(), v_pid, 'SET', v_actor, 'Bulk lecturer upload (Users & roles)');
                c_cred := c_cred + 1;
            END IF;

            -- 3. the lecturer office, scoped to the department — only if not already live
            IF NOT EXISTS (SELECT 1 FROM iam.office_assignment
                            WHERE person_id = v_pid AND office_code = 'lecturer'
                              AND scope_kind = 'department' AND scope_id = v_dept AND valid_to IS NULL) THEN
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                VALUES (gen_random_uuid(), v_pid, 'lecturer', 'department', v_dept,
                        'Bulk lecturer upload (Users & roles)', v_actor, current_date);
                c_grant := c_grant + 1;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            c_skip := c_skip + 1;
            IF v_err IS NULL THEN v_err := 'Row ' || n || ' (' || v_staff || '): ' || SQLERRM; END IF;
        END;
    END LOOP;

    RETURN QUERY SELECT n, c_created, c_exist, c_cred, c_grant, c_skip, v_err;
END $$;

COMMENT ON FUNCTION iam.import_lecturers(jsonb) IS
  'Bulk-onboard lecturers: person + sign-in (username/password = staff number, '
  'must change) + lecturer office scoped to the department code. Resilient '
  '(per-row savepoint) and idempotent (existing person/credential/grant kept).';

COMMIT;
