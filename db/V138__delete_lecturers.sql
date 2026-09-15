-- ═══════════════════════════════════════════════════════════════════════════
-- V138 — iam.delete_lecturers: remove wrongly-uploaded teaching staff
--
--   After a bulk teaching-staff upload, some rows may be wrong (a mistyped
--   department, a duplicate). This removes selected lecturers outright — the
--   person, their sign-in, their lecturer grants and their establishment
--   record — but ONLY when they carry no teaching history. Each id runs in its
--   own savepoint and the person is deleted last, so a lecturer who already
--   teaches or second-examines an offering (or is otherwise referenced) makes
--   the delete fail and roll back for that id alone: they are kept and counted
--   as skipped, and the rest still go. A safe, reversible-by-re-upload cleanup,
--   not a way to erase someone with a record.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION iam.delete_lecturers(p_ids uuid[])
RETURNS TABLE (deleted int, skipped int, first_error text)
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_id uuid; nd int := 0; ns int := 0; v_err text := NULL;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a deletion is made by a person' USING ERRCODE = '23514'; END IF;
    IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN
        RAISE EXCEPTION 'name the lecturers to remove' USING ERRCODE = '23514';
    END IF;

    FOREACH v_id IN ARRAY p_ids LOOP
        -- only a person who actually holds the lecturer office (never a random person id)
        IF NOT EXISTS (SELECT 1 FROM iam.office_assignment a
                        WHERE a.person_id = v_id AND a.office_code = 'lecturer' AND a.scope_kind = 'department') THEN
            ns := ns + 1;
            IF v_err IS NULL THEN v_err := 'One selected id is not a lecturer'; END IF;
            CONTINUE;
        END IF;
        -- kept if they teach or verify any offering — the savepoint below would fail the person delete
        IF EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.lecturer_id = v_id OR o.second_examiner_id = v_id) THEN
            ns := ns + 1;
            IF v_err IS NULL THEN v_err := 'A selected lecturer already teaches a course and was kept'; END IF;
            CONTINUE;
        END IF;

        BEGIN
            DELETE FROM iam.credential_event WHERE person_id = v_id;
            DELETE FROM iam.credential WHERE person_id = v_id;
            DELETE FROM iam.office_assignment WHERE person_id = v_id;
            DELETE FROM hrm.staff_photo WHERE person_id = v_id;
            DELETE FROM hrm.staff_profile WHERE person_id = v_id;
            DELETE FROM hrm.staff_record WHERE person_id = v_id;
            DELETE FROM iam.person WHERE id = v_id;
            nd := nd + 1;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_err IS NULL THEN v_err := left('A selected lecturer could not be removed (has a record): ' || SQLERRM, 300); END IF;
        END;
    END LOOP;

    RETURN QUERY SELECT nd, ns, v_err;
END $$;

COMMENT ON FUNCTION iam.delete_lecturers(uuid[]) IS
  'Remove selected lecturers (person + sign-in + lecturer grants + establishment) '
  'when they have no teaching history; a lecturer who teaches an offering is kept. '
  'Per-id savepoint, so one blocked id does not stop the rest.';

COMMIT;
