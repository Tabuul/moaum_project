-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V315 — an O'Level duplicate is the SAME EXAM NUMBER; another number is another sitting
--
--   V298 held a second result for the same examining body, year and series as a duplicate, on the
--   premise that one cannot sit the same examination twice. The Academic Office says otherwise: a
--   candidate may hold two results of one body for one year under two exam numbers, and combining
--   O'Level results across sittings is allowed — so the premise blocked real files (35 candidates
--   with two NECO results of one series, every one of them with two different exam numbers).
--
--   The rule now reads the exam number alone:
--     · SAME_RESULT — the same examining body and exam number (compared without spaces, dashes or
--       slashes) with the same grades, or, where one side has no number, the same body, year and
--       series with the same grades: already on record, not recorded again;
--     · SAME_SITTING — the same examining body and exam number with OTHER grades: one sitting cannot
--       have two sets of grades, so it is held for the Office to keep the result on record or use
--       the uploaded one, with the verification;
--     · another exam number of the same body, whatever the year and series: a sitting of its own,
--       recorded;
--     · NUMBER_ELSEWHERE — unchanged: the same body and exam number on another applicant's record is
--       recorded and flagged until verified.
--   The screen's own check of the file reads the same rule before anything is uploaded.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V315: an O''Level duplicate is the same exam number', true);

CREATE OR REPLACE FUNCTION admissions.olevel_match(p_session text, p_jamb_key text, s jsonb)
RETURNS TABLE (kind text, sitting_id uuid)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_body text := admissions.exam_body(s ->> 'type'); v_year text := admissions.olevel_year(s ->> 'year');
        v_class text := admissions.olevel_series_class(s ->> 'type', s ->> 'series'); v_key text := admissions.olevel_exam_key(s ->> 'examNumber');
        v_grades text := admissions.olevel_payload_sig(s); hit uuid;
BEGIN
    -- 1 · the same examining body and exam number on the candidate's record: the same result, or the same sitting with other grades
    IF v_key IS NOT NULL THEN
        SELECT st.id INTO hit FROM admissions.olevel_sitting st
         WHERE st.session = p_session AND st.jamb_key = p_jamb_key AND st.exam_body = v_body AND st.exam_key = v_key
         ORDER BY st.ord LIMIT 1;
        IF hit IS NOT NULL THEN
            RETURN QUERY SELECT CASE WHEN admissions.olevel_grades_sig(hit) = v_grades THEN 'SAME_RESULT' ELSE 'SAME_SITTING' END::text, hit;
            RETURN;
        END IF;
    END IF;
    -- 2 · where the upload or the record has no number: the same examination (body, year, series) with the same grades is the same result
    IF v_year IS NOT NULL AND v_body <> 'OTHER' THEN
        SELECT st.id INTO hit FROM admissions.olevel_sitting st
         WHERE st.session = p_session AND st.jamb_key = p_jamb_key AND st.exam_body = v_body
           AND (v_key IS NULL OR st.exam_key IS NULL)
           AND admissions.olevel_year(st.exam_year) = v_year
           AND admissions.olevel_series_class(st.exam_type_raw, st.exam_series) = v_class
           AND admissions.olevel_grades_sig(st.id) = v_grades
         ORDER BY st.ord LIMIT 1;
        IF hit IS NOT NULL THEN RETURN QUERY SELECT 'SAME_RESULT'::text, hit; RETURN; END IF;
    END IF;
    IF v_key IS NULL THEN
        SELECT st.id INTO hit FROM admissions.olevel_sitting st
         WHERE st.session = p_session AND st.jamb_key = p_jamb_key AND st.exam_key IS NULL AND st.exam_body = v_body
           AND coalesce(st.exam_year, '') = coalesce(nullif(btrim(s ->> 'year'), ''), '')
           AND admissions.olevel_grades_sig(st.id) = v_grades
         ORDER BY st.ord LIMIT 1;
        IF hit IS NOT NULL THEN RETURN QUERY SELECT 'SAME_RESULT'::text, hit; RETURN; END IF;
    END IF;
    -- 3 · another exam number of the same body, whatever the year and series: a sitting of its own
    RETURN;
END $$;
COMMENT ON FUNCTION admissions.olevel_match(text, text, jsonb) IS
  'What a sitting as an upload carries it meets on the candidate''s record (V298, V315): SAME_RESULT — the same body and exam number with the same grades, or without a number the same body, year and series with the same grades; SAME_SITTING — the same body and exam number with other grades; nothing — another exam number is a sitting of its own.';

COMMENT ON TABLE admissions.olevel_duplicate IS
  'V298/V315: what an O''Level upload carried that was already on record (SAME_RESULT, not recorded again), the same exam number with other grades (SAME_SITTING, held for the Office), or an exam number on another applicant''s record (NUMBER_ELSEWHERE, recorded and flagged until verified).';
COMMENT ON FUNCTION admissions.olevel_from_attachment(uuid) IS
  'The sittings an O''Level upload carries (V020), each checked before it is recorded (V298, V315): the same result is not recorded again, the same exam number with other grades is held, another exam number is a sitting of its own, an exam number on another applicant''s record is recorded and flagged.';

COMMIT;
