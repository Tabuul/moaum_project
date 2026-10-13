-- ═══════════════════════════════════════
-- V429 — intake never makes a second student; the possible duplicates listed for the Registry (portal gap audit)
--
--   On the live-shaped copy, eight JAMB candidates admitted for 2026/2027 stood on the register twice: once under an early admission
--   number with no candidate behind it (taken on by an earlier list or by hand), once under the number the candidate's own intake
--   drew — because people.intake_one looked for the candidate's student only by the candidate link. Nothing had been registered or
--   paid on either. Two more pairs share every name, the programme and the entry session.
--
--   1. people.intake_one links a student already on the register under the candidate's JAMB number for the same entry session and
--      linked to no candidate, instead of drawing a second admission number; untouched, it takes the admitted programme; with a history
--      on another programme it refuses (INTAKE_DUPLICATE_JAMB) for the Registry to reconcile.
--   2. One student per candidate, as a unique index — made only where the register holds no two students for one candidate, so this
--      migration never fails on a register that does (the Registry reconciles those first).
--   3. people.duplicate_students: the possible duplicates — the same JAMB number, or every name, the programme and the entry session —
--      with what each record carries (registrations, payments, marks, candidate), for the Registry. Read only: nothing is merged or
--      deleted.
-- ═══════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V429: intake never makes a second student', true);

-- ── 1 · intake links the student already on the register ──
CREATE OR REPLACE FUNCTION people.intake_one(p_candidate uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE c admissions.candidate; v_id uuid; v_code text; v_yy text; l admissions.cce_candidate; v_prev uuid; v_prev_prog text; v_busy boolean;
BEGIN
    SELECT * INTO c FROM admissions.candidate WHERE id = p_candidate;
    IF c.id IS NULL THEN RAISE EXCEPTION 'no such candidate' USING ERRCODE = '23503'; END IF;
    SELECT id INTO v_id FROM people.student WHERE candidate_id = c.id;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;
    IF c.offer_state NOT IN ('ADMITTED', 'ACCEPTED') THEN
        RAISE EXCEPTION 'only an admitted candidate is brought onto the register; % is %', c.jamb_reg_no, lower(coalesce(c.offer_state, 'not admitted')) USING ERRCODE = '23514';
    END IF;
    -- candidate.programme is the programme NAME; resolve it to a code, accepting a value that is already a code
    v_code := (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1);
    IF v_code IS NULL THEN
        IF EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = c.programme) THEN
            v_code := c.programme;
        ELSE
            RAISE EXCEPTION 'the programme "%" for candidate % is not one the University runs; it cannot be brought onto the register',
                c.programme, c.jamb_reg_no USING ERRCODE = '23503',
                HINT = 'Set the programme''s University name to match ref.programme, or correct the candidate''s programme.';
        END IF;
    END IF;
    -- V429: a student already on the register under the candidate's JAMB number for the same entry session, never linked to a candidate
    -- (taken on by an earlier list or by hand), IS the candidate: linked, never made a second time. Untouched yet (no registration,
    -- payment or mark), it takes the programme the admission names; with a history on another programme the Registry decides.
    SELECT s.id, s.programme_code INTO v_prev, v_prev_prog FROM people.student s
     WHERE s.candidate_id IS NULL AND s.jamb_reg_no IS NOT NULL AND upper(s.jamb_reg_no) = upper(c.jamb_reg_no) AND s.entry_session = c.session
     ORDER BY s.admission_no NULLS LAST LIMIT 1;
    IF v_prev IS NOT NULL THEN
        IF v_prev_prog IS DISTINCT FROM v_code THEN
            v_busy := EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = v_prev)
                   OR EXISTS (SELECT 1 FROM finance.payment_reference p WHERE p.student_id = v_prev)
                   OR EXISTS (SELECT 1 FROM assessment.score sc WHERE sc.student_id = v_prev);
            IF v_busy THEN
                RAISE EXCEPTION 'INTAKE_DUPLICATE_JAMB: % is already on the register for % on another programme, with registrations, payments or marks; the Registry reconciles the two before the candidate is taken on', c.jamb_reg_no, c.session
                    USING ERRCODE = '23514';
            END IF;
            UPDATE people.student SET programme_code = v_code WHERE id = v_prev;
        END IF;
        UPDATE people.student SET candidate_id = c.id WHERE id = v_prev;
        RETURN v_prev;
    END IF;
    v_yy := substr(c.session, 3, 2);
    -- V379: a CCE candidate comes onto the register CCE and part-time, in the CCE session admitted for, with what the list gave
    SELECT * INTO l FROM admissions.cce_candidate WHERE id = c.cce_candidate_id;
    INSERT INTO people.student (id, candidate_id, admission_no, jamb_reg_no, surname, other_names,
                                programme_code, entry_mode, entry_session, entry_level, current_level, study_mode, date_of_birth, sex, state_of_origin)
    VALUES (gen_random_uuid(), c.id,
            'MOAUM/ADM/' || v_yy || '/' || lpad(platform.next_number('ADMISSION', 'UNIVERSITY', c.session)::text, 6, '0'),
            c.jamb_reg_no, c.surname, c.other_names, v_code,
            CASE WHEN c.entry_mode IN ('UTME', 'DIRECT_ENTRY', 'CCE') THEN c.entry_mode ELSE 'UTME' END,
            c.session, c.entry_level, c.entry_level,
            CASE WHEN c.entry_mode = 'CCE' THEN coalesce((SELECT r.study_mode FROM policy.study_route r WHERE r.code = 'CCE'), 'PART_TIME') ELSE 'FULL_TIME' END,
            l.date_of_birth, l.sex, l.state_of_origin)
    RETURNING id INTO v_id;
    IF c.entry_mode = 'CCE' THEN
        INSERT INTO people.biodata (student_id, field, value)
        SELECT v_id, x.field, x.value FROM admissions.screening_answer x JOIN admissions.application a ON a.id = x.application_id
         WHERE a.candidate_id = c.id AND btrim(x.value) <> ''
        ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value;
    END IF;
    -- the nationality JAMB's state implies, on the record from the first day (V282)
    PERFORM people.default_nationality(v_id);
    RETURN v_id;
END $function$;

-- ── 2 · one student per candidate, where the register already holds it so ──
DO $do$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM people.student WHERE candidate_id IS NOT NULL GROUP BY candidate_id HAVING count(*) > 1)
       AND NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'people' AND indexname = 'ux_student_candidate') THEN
        CREATE UNIQUE INDEX ux_student_candidate ON people.student (candidate_id) WHERE candidate_id IS NOT NULL;
    END IF;
END $do$;

-- ── 3 · the possible duplicates, for the Registry ──
CREATE FUNCTION people.duplicate_students()
RETURNS TABLE(kind text, match_key text, student_id uuid, number text, name text, programme_code text, entry_session text, status text,
              jamb_reg_no text, linked_candidate boolean, registrations bigint, payments bigint, marks bigint)
LANGUAGE sql STABLE AS $fn$
    WITH by_jamb AS (
        SELECT 'SAME_JAMB'::text AS kind, upper(s.jamb_reg_no) AS match_key, s.id FROM people.student s
         WHERE s.jamb_reg_no IS NOT NULL AND upper(s.jamb_reg_no) IN (SELECT upper(x.jamb_reg_no) FROM people.student x WHERE x.jamb_reg_no IS NOT NULL
                                                                        GROUP BY 1 HAVING count(*) > 1)),
    by_name AS (
        SELECT 'SAME_NAME'::text, upper(s.surname) || ', ' || upper(s.other_names) || ' · ' || s.programme_code || ' · ' || s.entry_session, s.id
          FROM people.student s
         WHERE (upper(s.surname), upper(s.other_names), s.programme_code, s.entry_session) IN
               (SELECT upper(x.surname), upper(x.other_names), x.programme_code, x.entry_session FROM people.student x
                 GROUP BY 1, 2, 3, 4 HAVING count(*) > 1)
           AND s.id NOT IN (SELECT id FROM by_jamb)),
    found AS (SELECT * FROM by_jamb UNION ALL SELECT * FROM by_name)
    SELECT f.kind, f.match_key, s.id, coalesce(s.matric_no, s.admission_no), upper(s.surname) || ', ' || s.other_names, s.programme_code,
           s.entry_session, s.status, s.jamb_reg_no, s.candidate_id IS NOT NULL,
           (SELECT count(*) FROM registration.course_registration r WHERE r.student_id = s.id),
           (SELECT count(*) FROM finance.payment_reference p WHERE p.student_id = s.id),
           (SELECT count(*) FROM assessment.score sc WHERE sc.student_id = s.id)
      FROM found f JOIN people.student s ON s.id = f.id
     ORDER BY f.kind, f.match_key, coalesce(s.matric_no, s.admission_no)
$fn$;
COMMENT ON FUNCTION people.duplicate_students() IS
  'V429: the students who may be one person on the register twice — the same JAMB number, or every name, the programme and the entry session — with the registrations, payments and marks each record carries and whether a candidate stands behind it. For the Registry; read only.';

COMMIT;
