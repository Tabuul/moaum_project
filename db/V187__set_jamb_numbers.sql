-- ═══════════════════════════════════════════════════════════════════════════
-- V187 — set students' JAMB registration numbers from a matric → JAMB upload
--
--   Legacy students brought over by the old-portal biography list carry no JAMB
--   number on the register (the importer kept the application number only, as
--   provenance). This lets Records/ICT upload a simple two-column sheet —
--   matriculation number and JAMB registration number — to fill people.student
--   .jamb_reg_no, so the bulk passport upload (named by JAMB number) can match
--   them, and the number shows on the student's profile.
--
--   Audit-light: one attributed act by the officer, the per-row trigger disabled
--   around the bulk update (the same shape as the candidate-CAPS reconciliation).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION people.set_jamb_numbers(p_rows jsonb)
RETURNS TABLE (rows int, updated int, no_student int)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, people AS $$
DECLARE r jsonb; v_matric text; v_jamb text; v_upd int; c_rows int := 0; c_upd int := 0; c_no int := 0;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'the JAMB numbers are set by a person' USING ERRCODE = '23514';
    END IF;
    ALTER TABLE people.student DISABLE TRIGGER trg_audit_people_student;
    FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) LOOP
        c_rows := c_rows + 1;
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'matno', '')));
        v_jamb   := upper(btrim(coalesce(r->>'jamb', r->>'jambNo', r->>'jamb_no', r->>'jambRegNo', r->>'jamb_reg_no', '')));
        IF v_matric = '' OR v_jamb = '' THEN c_no := c_no + 1; CONTINUE; END IF;
        UPDATE people.student SET jamb_reg_no = v_jamb WHERE upper(matric_no) = v_matric;
        GET DIAGNOSTICS v_upd = ROW_COUNT;
        IF v_upd > 0 THEN c_upd := c_upd + 1; ELSE c_no := c_no + 1; END IF;
    END LOOP;
    ALTER TABLE people.student ENABLE TRIGGER trg_audit_people_student;
    RETURN QUERY SELECT c_rows, c_upd, c_no;
END $$;

COMMENT ON FUNCTION people.set_jamb_numbers(jsonb) IS
  'Set people.student.jamb_reg_no from a matric → JAMB upload, so passport photos named by JAMB number match. '
  'Keyed on matric_no; idempotent; a row with no matching matric is counted, not fatal.';

COMMIT;
