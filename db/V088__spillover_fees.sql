-- ═══════════════════════════════════════════════════════════════════════════
-- V088 — spillover students and their fees
--
--   A student who has passed the normal length of the programme without
--   graduating is "spilling over" — a four-year programme's student still
--   enrolled beyond 400 level, and not graduated, is a spillover. The final
--   level follows the same rule graduation uses: 500 for LL.B and Pharmacy,
--   600 for Medicine (C00061), 400 otherwise.
--
--   The approved-fees table carries a spillover band; it is now kept as a
--   spillover fee line rather than skipped. A spillover student is charged the
--   spillover lines for their faculty and semester; every other student is
--   charged the normal level lines, and never the spillover ones.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'bursar', true);
SELECT set_config('moaum.reason', 'Spillover students and their fees (V088)', true);

ALTER TABLE finance.fee_schedule ADD COLUMN IF NOT EXISTS spillover boolean NOT NULL DEFAULT false;

-- the last level of a programme, the same rule graduation uses
CREATE OR REPLACE FUNCTION finance.final_level(p_programme text) RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN p.code = 'C00061' THEN 600
                WHEN upper(p.name) LIKE 'LL.B%' OR upper(p.name) LIKE '%PHARMACY%' THEN 500
                ELSE 400 END
      FROM ref.programme p WHERE p.code = p_programme;
$$;

-- is a student spilling over: past the programme's final level, and not graduated
CREATE OR REPLACE FUNCTION finance.is_spillover(p_student uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT coalesce(s.current_level > finance.final_level(s.programme_code) AND s.status <> 'GRADUATED', false)
      FROM people.student s WHERE s.id = p_student;
$$;

-- charges: a spillover student pays the spillover lines; everyone else the normal (non-spillover) lines
CREATE OR REPLACE FUNCTION finance.charges(p_student uuid, p_session text)
RETURNS TABLE (id uuid, item text, amount numeric, ord int)
LANGUAGE sql STABLE AS $$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS (
        SELECT s.id, s.programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               coalesce(s.current_level > finance.final_level(s.programme_code) AND s.status <> 'GRADUATED', false) AS is_spill
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.id = p_student)
    SELECT f.id, f.item, f.amount, f.ord
      FROM finance.fee_schedule f
      CROSS JOIN me
      JOIN ref.programme p ON p.code = me.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
      CROSS JOIN home
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND f.spillover = me.is_spill
       AND (me.is_spill OR f.level IS NULL OR f.level = me.current_level)
       AND (f.entry_mode IS NULL OR f.entry_mode = me.entry_mode)
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)))
       AND (f.semester IS NULL
            OR f.semester = (SELECT sm.number FROM policy.semester sm
                              WHERE sm.session = p_session AND sm.state = 'OPEN'
                              ORDER BY sm.number LIMIT 1))
     ORDER BY f.ord, f.item;
$$;

-- the importer now keeps the spillover band (level-agnostic) instead of skipping it
CREATE OR REPLACE FUNCTION finance.import_fee_structure(p_session text, p_rows jsonb)
RETURNS TABLE (rows int, lines int, faculties int, no_faculty int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_fac text; v_fac_code text; v_level int; v_mode text; v_sem int; v_ind text; v_amt numeric; v_item text; v_ord int; v_spill boolean;
        n int := 0; nl int := 0; nnf int := 0; facs text[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a fees structure is uploaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the structure is rows: faculty, level, semester, indigeneship and the amount' USING ERRCODE = '23514';
    END IF;
    UPDATE finance.fee_schedule SET ended_at = now() WHERE session = p_session AND ended_at IS NULL;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_amt := nullif(regexp_replace(coalesce(r->>'amount', ''), '[^0-9.]', '', 'g'), '')::numeric;
        IF v_amt IS NULL OR v_amt < 0 THEN CONTINUE; END IF;
        n := n + 1;
        v_fac := btrim(coalesce(r->>'faculty', r->>'facultyCode', r->>'faculty_code', ''));
        v_fac_code := NULL;
        IF v_fac <> '' THEN
            SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(code) = upper(v_fac);
            IF v_fac_code IS NULL THEN SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(name) = upper(v_fac) LIMIT 1; END IF;
            IF v_fac_code IS NULL THEN SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(name) LIKE '%' || upper(v_fac) || '%' LIMIT 1; END IF;
            IF v_fac_code IS NULL THEN nnf := nnf + 1; END IF;
        END IF;
        v_spill := lower(btrim(coalesce(r->>'spillover', 'false'))) IN ('true', 't', '1', 'yes', 'y');
        v_level := nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int;
        IF v_level IS NOT NULL AND v_level NOT IN (100,200,300,400,500,600) THEN v_level := NULL; END IF;
        IF v_spill THEN v_level := NULL; END IF;   -- a spillover line is level-agnostic
        v_mode := nullif(upper(btrim(coalesce(r->>'entryMode', r->>'entry_mode', ''))), '');
        IF v_mode IS NOT NULL AND v_mode NOT IN ('UTME','DIRECT_ENTRY','TRANSFER','POSTGRADUATE','JUPEB','SANDWICH') THEN v_mode := NULL; END IF;
        v_sem := nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int;
        IF v_sem IS NOT NULL AND v_sem NOT IN (1,2,3) THEN v_sem := NULL; END IF;
        v_ind := upper(btrim(coalesce(r->>'indigene', '')));
        v_ind := CASE WHEN v_ind LIKE 'IND%' THEN 'INDIGENE' WHEN v_ind LIKE 'NON%' OR v_ind LIKE 'NN%' THEN 'NON_INDIGENE' ELSE NULL END;
        v_item := nullif(btrim(coalesce(r->>'item', '')), '');
        IF v_item IS NULL THEN v_item := CASE WHEN v_spill THEN 'School fees (spillover)' ELSE 'School fees' END
            || CASE WHEN v_sem IS NULL THEN '' ELSE ' (semester ' || v_sem || ')' END; END IF;
        v_ord := coalesce(nullif(regexp_replace(coalesce(r->>'ord', ''), '[^0-9]', '', 'g'), '')::int, coalesce(v_sem, 1)) + CASE WHEN v_spill THEN 100 ELSE 0 END;

        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, semester, indigene, ord, spillover)
        VALUES (p_session, v_item, v_amt, v_level, v_mode, v_fac_code, v_sem, v_ind, v_ord, v_spill);
        nl := nl + 1;
        IF v_fac_code IS NOT NULL AND NOT (v_fac_code = ANY(facs)) THEN facs := facs || v_fac_code; END IF;
    END LOOP;
    RETURN QUERY SELECT n, nl, cardinality(facs), nnf;
END $$;

COMMIT;
