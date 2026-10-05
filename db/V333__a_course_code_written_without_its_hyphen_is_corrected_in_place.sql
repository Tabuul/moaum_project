-- V333 · A course code written without its hyphen is corrected in place
--
-- The old portal's uploads carried the University's prefixed codes with the hyphen dropped — MOAUCHM 101 for
-- MOAU-CHM 101, BSUGEO 413 for BSU-GEO 413 — and the catalogue keeps them, since its check accepts any code of letters,
-- digits, spaces, slashes and hyphens. V332's rename accepted the plain three-letter form only. Now:
--
--     · catalogue.rename_course accepts every form the catalogue keys — AAA 999, PFX-SUB 999 (a known prefix, a
--       hyphen, the subject, the number) — normalising case and spacing; the course keeps its identity and every
--       reference follows (V332);
--     · catalogue.code_fixes(dept) lists a department's codes written without the hyphen with the code each should
--       read, whether that code already exists (then it is a duplicate for the duplicates desk, not a rename), and
--       what the wrong code carries;
--     · catalogue.apply_code_fixes(dept) renames every one whose corrected code is free, in one act, and leaves the
--       rest with the reason.
--
-- A prefix is known when the catalogue already carries it hyphenated (BSU-, MOAU-, MOAUM-, FBSU-) or it is one of the
-- University's own; the subject is two to four letters and the number three digits, with an optional letter.

CREATE OR REPLACE FUNCTION catalogue.known_prefixes()
RETURNS text[]
LANGUAGE sql STABLE AS $$
    SELECT array_agg(DISTINCT p ORDER BY p)
      FROM (SELECT unnest(ARRAY['MOAU', 'MOAUM', 'MOUA', 'BSU', 'FBSU']) AS p
            UNION
            SELECT (regexp_match(code, '^([A-Z]{2,5})-'))[1] FROM catalogue.course WHERE code ~ '^[A-Z]{2,5}-') x
     WHERE p IS NOT NULL
$$;
COMMENT ON FUNCTION catalogue.known_prefixes() IS 'V333: the institution prefixes a course code may carry before its hyphen — the University''s own, and every prefix the catalogue already carries hyphenated.';

-- the code a code should read: AAA 999 or PFX-SUB 999, case and spacing normalised; NULL where it fits neither and
-- is not an acceptable code as typed
CREATE OR REPLACE FUNCTION catalogue.normal_code(p_code text)
RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE u text := regexp_replace(upper(btrim(coalesce(p_code, ''))), '\s+', ' ', 'g'); m text[];
BEGIN
    m := regexp_match(u, '^([A-Z]{3})\s*([0-9]{3}[A-Z]?)$');
    IF m IS NOT NULL THEN RETURN m[1] || ' ' || m[2]; END IF;
    m := regexp_match(u, '^([A-Z]{2,5})\s*-\s*([A-Z]{2,4})\s*([0-9]{3}[A-Z]?)$');
    IF m IS NOT NULL THEN RETURN m[1] || '-' || m[2] || ' ' || m[3]; END IF;
    IF u ~ '^[A-Z][A-Z0-9 /-]{2,19}$' THEN RETURN u; END IF;
    RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION catalogue.rename_course(p_old text, p_new text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_old text := upper(btrim(coalesce(p_old, ''))); v_new text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a course is renamed by a person' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_old) THEN RAISE EXCEPTION 'no course is coded %', p_old USING ERRCODE = '23503'; END IF;
    v_new := catalogue.normal_code(p_new);
    IF v_new IS NULL THEN
        RAISE EXCEPTION 'CAT_CODE: a course code is three letters and three digits (CSC 311), or a prefix, a hyphen, the subject and the number (MOAU-CHM 101) — % fits neither', coalesce(p_new, '')
            USING ERRCODE = '23514', HINT = 'Letters, digits, one space before the number, a hyphen after the prefix.';
    END IF;
    IF v_new = v_old THEN RETURN v_new; END IF;
    IF EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_new) THEN
        RAISE EXCEPTION 'a course with the code % already exists', v_new USING ERRCODE = '23505',
            HINT = 'A code is unique across the University. If this is the same course under two codes, end or remove the duplicate on the duplicates desk.';
    END IF;
    UPDATE catalogue.course SET code = v_new WHERE code = v_old;
    UPDATE college.posting_course SET course_code = v_new WHERE course_code = v_old;
    UPDATE assessment.legacy_result_holding SET course_code = v_new WHERE course_code = v_old;
    UPDATE admissions.pg_legacy_holding SET course_code = v_new WHERE course_code = v_old;
    RETURN v_new;
END $$;
COMMENT ON FUNCTION catalogue.rename_course(text, text) IS 'V332/V333: change a course''s code to any form the catalogue keys — the same course (its id unchanged); its bindings, offerings, registrations, results, questions, CBT examinations, deferred courses, postings and old-portal results follow the new code.';

-- a department's codes written without the hyphen, each with the code it should read
CREATE OR REPLACE FUNCTION catalogue.code_fixes(p_dept text DEFAULT NULL)
RETURNS TABLE (code text, proposed text, title text, dept_code text, state text, twin_exists boolean, offers bigint, offerings bigint, carried bigint)
LANGUAGE sql STABLE AS $$
    -- the known prefixes as one alternation, the longest first, so MOAUMCHM reads MOAUM-CHM and MOAUCHM reads MOAU-CHM
    WITH px AS (SELECT '^(' || string_agg(p, '|' ORDER BY length(p) DESC, p) || ')([A-Z]{2,4}) ?([0-9]{3}[A-Z]?)$' AS pat
                  FROM unnest(catalogue.known_prefixes()) AS p),
    cand AS (
        SELECT c.code, c.title, c.dept_code, c.state, m.arr[1] AS pfx, m.arr[2] AS subj, m.arr[3] AS num
          FROM catalogue.course c
          CROSS JOIN px
          CROSS JOIN LATERAL regexp_match(c.code, px.pat) AS m(arr)
         WHERE (p_dept IS NULL OR c.dept_code = p_dept)
           AND c.code !~ '^[A-Z]{3} [0-9]{3}[A-Z]?$'
           AND m.arr IS NOT NULL)
    SELECT k.code, k.pfx || '-' || k.subj || ' ' || k.num AS proposed, k.title, k.dept_code, k.state,
           EXISTS (SELECT 1 FROM catalogue.course h WHERE h.code = k.pfx || '-' || k.subj || ' ' || k.num) AS twin_exists,
           (SELECT count(*) FROM catalogue.course_offer o WHERE o.course_code = k.code) AS offers,
           (SELECT count(*) FROM catalogue.offering o WHERE o.course_code = k.code) AS offerings,
           (SELECT count(*) FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id WHERE o.course_code = k.code)
             + (SELECT count(*) FROM assessment.legacy_result_holding l WHERE l.course_code = k.code) AS carried
      FROM cand k
     ORDER BY k.code
$$;
COMMENT ON FUNCTION catalogue.code_fixes(text) IS 'V333: the codes written without the hyphen after their prefix (MOAUCHM 101 for MOAU-CHM 101), the code each should read, whether that code is already taken, and what the wrong code carries.';

-- every one whose corrected code is free is renamed; one whose corrected code exists is a duplicate and is left for the duplicates desk
CREATE OR REPLACE FUNCTION catalogue.apply_code_fixes(p_dept text DEFAULT NULL)
RETURNS TABLE (code text, proposed text, outcome text)
LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    FOR r IN SELECT * FROM catalogue.code_fixes(p_dept) ORDER BY 1 LOOP
        code := r.code; proposed := r.proposed;
        IF r.twin_exists THEN
            outcome := 'TWIN_EXISTS';
        ELSE
            PERFORM catalogue.rename_course(r.code, r.proposed);
            outcome := 'RENAMED';
        END IF;
        RETURN NEXT;
    END LOOP;
END $$;
COMMENT ON FUNCTION catalogue.apply_code_fixes(text) IS 'V333: correct a department''s codes written without the hyphen in one act — renamed where the corrected code is free (the course and everything on it keep their identity), left as TWIN_EXISTS where the corrected code is another course already.';
