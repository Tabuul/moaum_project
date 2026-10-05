-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V329 — a course that nothing carries is removed outright; one that is carried is ended, never deleted
--
--   The catalogue of V042 ends a course with a date and keeps it, so every transcript that carries it stays whole.
--   That is right for a course that was taught. It is wrong for a code that never existed: a course uploaded twice
--   under a second code (BSU-COS 202 beside COS 202), a code mistyped on the upload, a row that should never have
--   been there — ending it leaves a dead row in the catalogue for ever. The Head of Department asked to remove such
--   a course completely.
--   The rule: a course is removed outright only when nothing carries it — no registration, result, score sheet,
--   timetable slot, question bank, deferment or old-portal result names it. Its own configuration (the programmes it
--   was offered to, its session offerings nobody registered for) goes with it. Anything a student's record depends
--   on refuses the removal with COURSE_CARRIED, and the course is ended instead, as before.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V329: a course nothing carries is removed outright', true);

CREATE OR REPLACE FUNCTION catalogue.remove_course(p_code text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; c catalogue.course; n_legacy int; v_table text; v_words text;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a course is removed by a person' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM catalogue.course WHERE code = p_code FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no course % to remove', p_code USING ERRCODE = '23503', HINT = 'It may have been removed already.';
    END IF;
    -- an old-portal result names the course by its code, with no key between them: a student's record all the same
    SELECT (SELECT count(*) FROM assessment.legacy_result_holding WHERE course_code = p_code)
         + (SELECT count(*) FROM admissions.pg_legacy_holding WHERE course_code = p_code) INTO n_legacy;
    IF n_legacy > 0 THEN
        RAISE EXCEPTION 'COURSE_CARRIED: % is named on % old-portal result(s) and cannot be removed', p_code, n_legacy
            USING ERRCODE = '23514', HINT = 'End the course instead: it leaves registration and stays on the records that carry it.';
    END IF;
    BEGIN
        DELETE FROM catalogue.course_offer WHERE course_code = p_code;
        DELETE FROM catalogue.offering WHERE course_code = p_code;
        DELETE FROM catalogue.course WHERE code = p_code;
    EXCEPTION WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS v_table = TABLE_NAME;
        v_words := CASE v_table
                     WHEN 'course_registration_line' THEN 'a student''s registration' WHEN 'registration_line' THEN 'a student''s registration'
                     WHEN 'score_sheet' THEN 'a score sheet' WHEN 'exam_timetable' THEN 'the examination timetable'
                     WHEN 'attendance' THEN 'an attendance register' WHEN 'question' THEN 'a question bank'
                     WHEN 'deferred_course' THEN 'a deferment' WHEN 'exam' THEN 'a CBT examination'
                     ELSE coalesce(replace(v_table, '_', ' '), 'a record') END;
        RAISE EXCEPTION 'COURSE_CARRIED: % is carried by % and cannot be removed', p_code, v_words
            USING ERRCODE = '23514', HINT = 'End the course instead: it leaves registration and stays on the records that carry it.';
    END;
END $$;
COMMENT ON FUNCTION catalogue.remove_course(text) IS 'A course removed outright (V329): only when nothing carries it — no registration, result, score sheet, timetable, question bank, deferment or old-portal result; its own programme offers and empty session offerings go with it. Otherwise COURSE_CARRIED: the course is ended, never deleted.';

-- a list of codes: each removed where nothing carries it, ended where something does; what happened to each is returned
CREATE OR REPLACE FUNCTION catalogue.remove_or_end(p_codes text[])
RETURNS TABLE (code text, outcome text, detail text)
LANGUAGE plpgsql AS $$
DECLARE v_code text; v_msg text; v_state text;
BEGIN
    FOREACH v_code IN ARRAY coalesce(p_codes, '{}') LOOP
        BEGIN
            PERFORM catalogue.remove_course(v_code);
            code := v_code; outcome := 'REMOVED'; detail := 'Removed outright: nothing carried it';
            RETURN NEXT;
        EXCEPTION WHEN check_violation THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg NOT LIKE 'COURSE_CARRIED:%' THEN RAISE; END IF;
            SELECT c.state INTO v_state FROM catalogue.course c WHERE c.code = v_code;
            IF v_state IS DISTINCT FROM 'ENDED' THEN
                PERFORM catalogue.end_course(v_code);
                code := v_code; outcome := 'ENDED'; detail := substr(v_msg, length('COURSE_CARRIED: ') + 1);
            ELSE
                code := v_code; outcome := 'KEPT'; detail := substr(v_msg, length('COURSE_CARRIED: ') + 1) || '; it was ended already';
            END IF;
            RETURN NEXT;
        END;
    END LOOP;
    RETURN;
END $$;

COMMIT;
