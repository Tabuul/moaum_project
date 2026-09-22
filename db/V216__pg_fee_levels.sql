-- ═══════════════════════════════════════════════════════════════════════════
-- V216 — postgraduate levels in the approved-fees bulk import
--
--   V201 widened finance.fee_schedule to the postgraduate levels (700/800/900),
--   and the manual fee-setup form now offers them, so the Bursar can state a
--   postgraduate tuition charge by level (PGD/Master's/Doctoral). The bulk
--   approved-fees importer (V083), however, still silently dropped a level
--   outside 100–600 to "every level", so a spreadsheet with a postgraduate
--   level lost its scoping. This widens that acceptance to match — verbatim from
--   V083 but for the one level check — so a bulk upload keeps a 700/800/900 row.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION finance.import_fee_structure(p_session text, p_rows jsonb)
RETURNS TABLE (rows int, lines int, faculties int, no_faculty int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_fac text; v_fac_code text; v_level int; v_mode text; v_sem int; v_ind text; v_amt numeric; v_item text; v_ord int;
        n int := 0; nl int := 0; nnf int := 0; facs text[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a fees structure is uploaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the structure is rows: faculty, level, semester, indigeneship and the amount' USING ERRCODE = '23514';
    END IF;
    -- replace the session's approved structure: end what stands, then load the new
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
        v_level := nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int;
        IF v_level IS NOT NULL AND v_level NOT IN (100,200,300,400,500,600,700,800,900) THEN v_level := NULL; END IF;
        v_mode := nullif(upper(btrim(coalesce(r->>'entryMode', r->>'entry_mode', ''))), '');
        IF v_mode IS NOT NULL AND v_mode NOT IN ('UTME','DIRECT_ENTRY','TRANSFER','POSTGRADUATE','JUPEB','SANDWICH') THEN v_mode := NULL; END IF;
        v_sem := nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int;
        IF v_sem IS NOT NULL AND v_sem NOT IN (1,2,3) THEN v_sem := NULL; END IF;
        v_ind := upper(btrim(coalesce(r->>'indigene', '')));
        v_ind := CASE WHEN v_ind LIKE 'IND%' THEN 'INDIGENE' WHEN v_ind LIKE 'NON%' OR v_ind LIKE 'NN%' THEN 'NON_INDIGENE' ELSE NULL END;
        v_item := nullif(btrim(coalesce(r->>'item', '')), '');
        IF v_item IS NULL THEN v_item := 'School fees' || CASE WHEN v_sem IS NULL THEN '' ELSE ' (semester ' || v_sem || ')' END; END IF;
        v_ord := coalesce(nullif(regexp_replace(coalesce(r->>'ord', ''), '[^0-9]', '', 'g'), '')::int, coalesce(v_sem, 1));

        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, semester, indigene, ord)
        VALUES (p_session, v_item, v_amt, v_level, v_mode, v_fac_code, v_sem, v_ind, v_ord);
        nl := nl + 1;
        IF v_fac_code IS NOT NULL AND NOT (v_fac_code = ANY(facs)) THEN facs := facs || v_fac_code; END IF;
    END LOOP;
    RETURN QUERY SELECT n, nl, cardinality(facs), nnf;
END $$;

COMMIT;
