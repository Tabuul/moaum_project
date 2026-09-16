-- ═══════════════════════════════════════════════════════════════════════════
-- V147 — O'Level sittings de-duplicated on import, and a one-off cleanup
--
--   V099 deduped the O'Level *score* (a sitting sent twice was counted once) but
--   left both rows in admissions.olevel_sitting, so the candidate preview showed
--   the same sitting twice. The Office asked for the duplicates gone for real:
--
--     · olevel_from_attachment now skips a sitting whose identity already exists
--       for the candidate (its JAMB exam number where there is one, else the exam
--       body, year and the grades themselves — the same identity the score uses),
--       so a re-upload or a payload that repeats a sitting no longer adds a row;
--     · a one-off pass removes the duplicates already on the table, keeping the
--       first of each identity.
--
--   The tables are audit-exempt (V007/V020), so the cleanup needs no actor
--   context. Nothing that reads O'Level changes — the score already deduped.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── one-off cleanup: drop duplicate sittings, keep the first of each identity ──
CREATE TEMP TABLE _dup_sittings ON COMMIT DROP AS
    SELECT id FROM (
        SELECT st.id,
               row_number() OVER (
                 PARTITION BY st.session, st.jamb_key,
                   coalesce(nullif(upper(btrim(st.exam_number)), ''),
                     st.exam_body || '|' || coalesce(st.exam_year, '') || '|' ||
                     coalesce((SELECT string_agg(g.subject || '=' || g.grade, ',' ORDER BY g.subject, g.grade)
                                 FROM admissions.olevel_grade g WHERE g.sitting_id = st.id), ''))
                 ORDER BY st.ord, st.id) AS rn
          FROM admissions.olevel_sitting st) q
     WHERE q.rn > 1;

DELETE FROM admissions.olevel_grade   WHERE sitting_id IN (SELECT id FROM _dup_sittings);
DELETE FROM admissions.olevel_sitting WHERE id         IN (SELECT id FROM _dup_sittings);

-- ── de-duplicate on import ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.olevel_from_attachment(p_attachment uuid)
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
    a admissions.attachment;
    sittings jsonb;
    s jsonb;
    sub jsonb;
    v_sitting uuid;
    v_ord int := 0;
    seen text[];
    v_sig text;
BEGIN
    SELECT * INTO a FROM admissions.attachment WHERE id = p_attachment;
    IF NOT FOUND OR a.kind <> 'OLEVEL' OR a.jamb_key IS NULL THEN
        RETURN 0;
    END IF;
    DELETE FROM admissions.olevel_grade g USING admissions.olevel_sitting st
     WHERE g.sitting_id = st.id AND st.attachment_id = p_attachment;
    DELETE FROM admissions.olevel_sitting WHERE attachment_id = p_attachment;

    -- the identities already recorded for this candidate (from other attachments)
    seen := ARRAY(
        SELECT coalesce(nullif(upper(btrim(st.exam_number)), ''),
                 st.exam_body || '|' || coalesce(st.exam_year, '') || '|' ||
                 coalesce((SELECT string_agg(g.subject || '=' || g.grade, ',' ORDER BY g.subject, g.grade)
                             FROM admissions.olevel_grade g WHERE g.sitting_id = st.id), ''))
          FROM admissions.olevel_sitting st
         WHERE st.session = a.session AND st.jamb_key = a.jamb_key);

    IF jsonb_typeof(a.payload -> 'sittings') = 'array' THEN
        sittings := a.payload -> 'sittings';
    ELSE
        sittings := jsonb_build_array(a.payload);
    END IF;

    FOR s IN SELECT * FROM jsonb_array_elements(sittings) LOOP
        v_sig := coalesce(
            nullif(upper(btrim(s ->> 'examNumber')), ''),
            admissions.exam_body(s ->> 'type') || '|' || coalesce(nullif(btrim(s ->> 'year'), ''), '') || '|' ||
            coalesce((SELECT string_agg(btrim(x ->> 'subject') || '=' || upper(btrim(coalesce(x ->> 'grade', ''))), ','
                                        ORDER BY btrim(x ->> 'subject'), upper(btrim(coalesce(x ->> 'grade', ''))))
                        FROM jsonb_array_elements(coalesce(s -> 'subjects', '[]'::jsonb)) x), ''));
        IF v_sig = ANY(seen) THEN CONTINUE; END IF;   -- the same sitting again: skip it
        seen := array_append(seen, v_sig);

        v_ord := v_ord + 1;
        v_sitting := gen_random_uuid();
        INSERT INTO admissions.olevel_sitting (id, attachment_id, session, jamb_key, exam_body, exam_type_raw, exam_year, exam_number, ord)
        VALUES (v_sitting, a.id, a.session, a.jamb_key, admissions.exam_body(s ->> 'type'),
                nullif(btrim(s ->> 'type'), ''), nullif(btrim(s ->> 'year'), ''), nullif(btrim(s ->> 'examNumber'), ''), v_ord);
        FOR sub IN SELECT * FROM jsonb_array_elements(coalesce(s -> 'subjects', '[]'::jsonb)) LOOP
            IF nullif(btrim(sub ->> 'subject'), '') IS NOT NULL THEN
                INSERT INTO admissions.olevel_grade AS og (sitting_id, subject, grade, raw_subject)
                VALUES (v_sitting, btrim(sub ->> 'subject'), upper(btrim(coalesce(sub ->> 'grade', ''))), sub ->> 'raw')
                ON CONFLICT (sitting_id, subject) DO UPDATE
                    SET grade = CASE WHEN admissions.olevel_points(a.session, EXCLUDED.grade)
                                          > admissions.olevel_points(a.session, og.grade)
                                     THEN EXCLUDED.grade ELSE og.grade END;
            END IF;
        END LOOP;
    END LOOP;
    RETURN v_ord;
END $$;

COMMIT;
