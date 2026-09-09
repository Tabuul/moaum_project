-- ═══════════════════════════════════════════════════════════════════════════
-- V063 — bringing a candidate onto the register uses the programme CODE
--
--   people.intake (V013) inserted people.student.programme_code from
--   admissions.candidate.programme. But candidate.programme holds the
--   programme NAME (set from the CAPS row; the code is resolved from it
--   everywhere else — see V061). student.programme_code is a foreign key to
--   ref.programme(code), so on a database where ref.programme is populated the
--   insert put a name where a code belongs and failed:
--       insert or update on table "student" violates foreign key constraint
--       "student_programme_code_fkey".
--   The property suite never called people.intake (its student rows are
--   inserted directly with a real code), so the bug stayed hidden until real
--   accepted candidates were brought onto the register.
--
--   Resolve the candidate's programme name to a code the same way V061 does,
--   accept a value that is already a code (older data), and raise a clear error
--   for a programme the University does not run rather than an opaque FK error.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION people.intake(p_session text)
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE c record; v_n int := 0; v_yy text := substr(p_session, 3, 2); v_code text;
BEGIN
    FOR c IN
        SELECT * FROM admissions.candidate a
         WHERE a.session = p_session AND a.offer_state IN ('ADMITTED','ACCEPTED')
           AND NOT EXISTS (SELECT 1 FROM people.student s WHERE s.candidate_id = a.id)
         ORDER BY a.surname, a.other_names
    LOOP
        -- candidate.programme is the programme NAME; resolve it to a code.
        v_code := (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1);
        IF v_code IS NULL THEN
            -- accept a value that is already a code (older/legacy candidates)
            IF EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = c.programme) THEN
                v_code := c.programme;
            ELSE
                RAISE EXCEPTION 'the programme "%" for candidate % is not one the University runs; it cannot be brought onto the register',
                    c.programme, c.jamb_reg_no USING ERRCODE = '23503',
                    HINT = 'Set the programme''s University name to match ref.programme, or correct the candidate''s programme.';
            END IF;
        END IF;

        INSERT INTO people.student (id, candidate_id, admission_no, jamb_reg_no, surname, other_names,
                                    programme_code, entry_mode, entry_session, entry_level, current_level)
        VALUES (gen_random_uuid(), c.id,
                'MOAUM/ADM/' || v_yy || '/' || lpad(platform.next_number('ADMISSION', 'UNIVERSITY', p_session)::text, 6, '0'),
                c.jamb_reg_no, c.surname, c.other_names, v_code,
                CASE WHEN c.entry_mode IN ('UTME','DIRECT_ENTRY') THEN c.entry_mode ELSE 'UTME' END,
                p_session, c.entry_level, c.entry_level);
        v_n := v_n + 1;
    END LOOP;
    RETURN v_n;
END;
$$;

COMMIT;
