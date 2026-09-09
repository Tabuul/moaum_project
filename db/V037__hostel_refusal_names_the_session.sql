-- ═══════════════════════════════════════════════════════════════════════════
-- V037 — the closed-draw refusal names the session it was raised for
--
--   hostel.apply (V030) refused a late application with a message carrying a
--   placeholder and no argument, which PostgreSQL reports as "too few
--   parameters specified for RAISE" instead of the refusal itself. V030 had
--   already been applied where it stands, so the function is restated here,
--   unchanged but for that one line — a migration applied is never edited.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION hostel.apply(p_student uuid, p_session text, p_hall text, p_category text, p_note text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE s hostel.session_setting; v uuid := gen_random_uuid(); v_sex text; v_hall_sex text;
BEGIN
    SELECT * INTO s FROM hostel.session_setting WHERE session = p_session;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'accommodation for % is not open: no fee and no hold window are stated', p_session USING ERRCODE = '23514',
            HINT = 'Student Services states the accommodation fee and the hold window for the session before applications open.';
    END IF;
    IF s.drawn_at IS NOT NULL THEN
        RAISE EXCEPTION 'the draw for % has been run; applications are closed', p_session USING ERRCODE = '23514',
            HINT = 'A late application joins no list. Ask Student Services whether a lapsed bed is available.';
    END IF;
    IF s.applications_close IS NOT NULL AND s.applications_close < current_date THEN
        RAISE EXCEPTION 'applications for % closed on %', p_session, s.applications_close USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM hostel.application WHERE student_id = p_student AND session = p_session AND state <> 'WITHDRAWN') THEN
        RAISE EXCEPTION 'an application for % already stands', p_session USING ERRCODE = '23505',
            HINT = 'One application per session; withdraw it before making another.';
    END IF;
    IF p_hall IS NOT NULL THEN
        SELECT sex INTO v_hall_sex FROM hostel.hall WHERE code = p_hall AND ended_on IS NULL;
        IF NOT FOUND THEN RAISE EXCEPTION 'no hall %', p_hall USING ERRCODE = '23503'; END IF;
        SELECT sex INTO v_sex FROM people.student WHERE id = p_student;
        IF v_hall_sex IS NOT NULL AND v_sex IS NOT NULL AND v_hall_sex <> v_sex THEN
            RAISE EXCEPTION 'hall % is not for this student', p_hall USING ERRCODE = '23514';
        END IF;
    END IF;
    INSERT INTO hostel.application (id, student_id, session, hall_code, category, category_note)
    VALUES (v, p_student, p_session, p_hall, coalesce(upper(p_category), 'NONE'), nullif(btrim(p_note), ''));
    RETURN v;
END $$;

COMMIT;
