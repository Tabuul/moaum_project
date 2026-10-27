-- ═══════════════════════════════════════
-- V681 — a fee structure upload refused for its postgraduate rows names every programme at once
--
-- The University's word of 27 October 2026 ("name every programme at once"), after the Bursary's 2025/2026 PG returning-students
-- upload (Batches C, D and E, 1,136 rows) was refused naming twelve rows of one programme alone: "row 641 (C12916, 900 C): 900 C —
-- Year 3 is not a stage of the programme's qualification; row 642 …" — finance.import_fee_structure (V653) kept the first 12 problem
-- rows, so the next programme with the same fault (C93757, rows 669–680) showed only on the next attempt, and a file with faults in
-- many programmes would take as many attempts.
--
-- Now every PG row is checked as before (finance.pg_fee_line_problem) and every problem kept; the refusal (FEE_STRUCTURE_PG, nothing
-- changed) names each programme — or faculty, or "every faculty" — once, in the order of the file: its code and name on the register,
-- the rows (as ranges: 641–652), the stages its rows name (900 C, 900 D, 900 E), what is wrong, and, where a stage is not one of the
-- programme's qualification, what its name reads as (the portal takes a postgraduate programme's qualification from its name,
-- people.pg_level_of): "C12916 MSC/PH.D MANAGEMENT (its name reads as Masters) — rows 641–652 (900 C, 900 D, 900 E): 900 C — Year 3
-- is not a stage of the programme's qualification; C93757 … — rows 669–680 …". The lead counts the rows and programmes. The upload
-- window lists the entries one a line. Nothing else changes: the same rows are refused, before anything is written.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V681: a fee upload refused for its PG rows names every programme at once', true);

CREATE OR REPLACE FUNCTION finance.import_fee_structure(p_session text, p_rows jsonb, p_scope text, p_confirm_whole boolean)
 RETURNS TABLE(rows integer, lines integer, faculties integer, no_faculty integer, no_programme integer, no_group integer, spillover integer, programmes integer)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_scope text := upper(btrim(coalesce(p_scope, 'SESSION')));
        v_fac text; v_fac_code text; v_level int; v_mode text; v_sem int; v_ind text; v_amt numeric; v_item text; v_ord int;
        v_spill boolean; v_spill_year int; v_prog text; v_prog_code text; v_grp text; v_grp_code text; v_kind text; v_cce boolean; v_full boolean;
        n int := 0; nl int := 0; nnf int := 0; nnp int := 0; nng int := 0; nsp int := 0; facs text[] := '{}'; progs text[] := '{}';
        v_unknown text[] := '{}'; v_row_facs text[] := '{}'; v_row_progs text[] := '{}'; v_prog_facs text[] := '{}'; v_universal boolean := false;
        v_left text; v_left_lines int;
        -- V653: the PG stage and fresh/returning of a row; the faculty-wide and University-wide stage rows apart from the others
        v_pos int := 0; v_stage_cell text; v_cat_cell text; v_stage text; v_cat text; v_pg_row boolean; v_has_pg boolean := false;
        v_row_facs_pg text[] := '{}'; v_universal_pg boolean := false; v_pg_levels int[] := '{}'; v_pg_all boolean := false;
        v_problem text; v_pg_left int;
        -- V681: every PG problem of the file, then one entry a programme (or faculty) in the refusal
        v_probs jsonb := '[]'; v_msg text; v_nrows int; v_nwho int; v_nprog int;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a fees structure is uploaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the structure is rows: faculty or programme, level, semester, indigeneship and the amount' USING ERRCODE = '23514';
    END IF;
    IF v_scope NOT IN ('SESSION', 'LISTED') THEN
        RAISE EXCEPTION 'FEE_STRUCTURE_SCOPE: a structure replaces the whole session (SESSION) or only the faculties and programmes it names (LISTED)' USING ERRCODE = '23514';
    END IF;
    v_cce := EXISTS (SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE upper(btrim(coalesce(x->>'entryMode', x->>'entry_mode', ''))) = 'CCE');
    v_full := EXISTS (SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE upper(btrim(coalesce(x->>'entryMode', x->>'entry_mode', ''))) <> 'CCE');

    -- V535: what the file names, before anything changes — every name held, and the faculties and programmes it states
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_pos := v_pos + 1;
        v_amt := nullif(regexp_replace(coalesce(r->>'amount', ''), '[^0-9.]', '', 'g'), '')::numeric;
        IF v_amt IS NULL OR v_amt < 0 THEN CONTINUE; END IF;
        -- V653: the stage and fresh/returning cells
        v_stage_cell := btrim(coalesce(r->>'pgStage', r->>'pg_stage', r->>'stage', ''));
        v_cat_cell := btrim(coalesce(r->>'feeCategory', r->>'fee_category', r->>'category', ''));
        v_stage := finance.pg_stage_from_text(v_stage_cell);
        v_cat := finance.fee_category_from_text(v_cat_cell);
        IF v_stage_cell <> '' AND v_stage IS NULL AND NOT ('PG stage ' || v_stage_cell = ANY (v_unknown)) THEN
            v_unknown := v_unknown || ('PG stage ' || v_stage_cell);
        END IF;
        IF v_cat_cell <> '' AND v_cat IS NULL AND NOT ('fresh or returning "' || v_cat_cell || '"' = ANY (v_unknown)) THEN
            v_unknown := v_unknown || ('fresh or returning "' || v_cat_cell || '"');
        END IF;
        v_pg_row := v_stage IS NOT NULL OR v_cat IS NOT NULL;
        IF v_pg_row THEN v_has_pg := true; END IF;
        v_fac := btrim(coalesce(r->>'faculty', r->>'facultyCode', r->>'faculty_code', ''));
        v_prog := btrim(coalesce(r->>'programmeCode', r->>'programme_code', r->>'programme', r->>'program', ''));
        v_fac_code := NULL; v_prog_code := NULL;
        IF v_prog <> '' THEN
            SELECT code INTO v_prog_code FROM ref.programme WHERE upper(code) = upper(v_prog);
            IF v_prog_code IS NULL THEN SELECT code INTO v_prog_code FROM ref.programme WHERE upper(name) = upper(v_prog) ORDER BY archived LIMIT 1; END IF;
            IF v_prog_code IS NULL THEN
                IF NOT ('programme ' || v_prog = ANY (v_unknown)) THEN v_unknown := v_unknown || ('programme ' || v_prog); END IF;
            ELSE
                IF NOT (v_prog_code = ANY (v_row_progs)) THEN v_row_progs := v_row_progs || v_prog_code; END IF;
                SELECT faculty_code INTO v_fac_code FROM ref.programme WHERE code = v_prog_code;
                IF v_fac_code IS NOT NULL AND NOT (v_fac_code = ANY (v_prog_facs)) THEN v_prog_facs := v_prog_facs || v_fac_code; END IF;
            END IF;
        ELSIF v_fac <> '' THEN
            SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(code) = upper(v_fac);
            IF v_fac_code IS NULL THEN SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(name) = upper(v_fac) LIMIT 1; END IF;
            IF v_fac_code IS NULL THEN SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(name) LIKE '%' || upper(v_fac) || '%' LIMIT 1; END IF;
            IF v_fac_code IS NULL THEN
                IF NOT ('faculty ' || v_fac = ANY (v_unknown)) THEN v_unknown := v_unknown || ('faculty ' || v_fac); END IF;
            ELSIF v_pg_row THEN
                IF NOT (v_fac_code = ANY (v_row_facs_pg)) THEN v_row_facs_pg := v_row_facs_pg || v_fac_code; END IF;
            ELSIF NOT (v_fac_code = ANY (v_row_facs)) THEN v_row_facs := v_row_facs || v_fac_code;
            END IF;
        ELSIF v_pg_row THEN
            v_universal_pg := true;
        ELSE
            v_universal := true;
        END IF;
        -- V653: a PG row checked as the table's guard would check it, so nothing changes until every row is right
        IF v_pg_row THEN
            v_level := nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int;
            IF v_level IS NOT NULL AND v_level NOT IN (100,200,300,400,500,600,700,800,900) THEN v_level := NULL; END IF;
            v_mode := nullif(upper(replace(btrim(coalesce(r->>'entryMode', r->>'entry_mode', '')), ' ', '_')), '');
            v_spill := finance.spill_year_of(r->>'spillover', coalesce(r->>'spillYear', r->>'spill_year')) IS NOT NULL
                       OR lower(btrim(coalesce(r->>'spillover', 'false'))) IN ('true', 't', '1', 'yes', 'y', 'spillover', 'spill');
            v_grp := btrim(coalesce(r->>'feeGroup', r->>'fee_group', r->>'group', ''));
            v_grp_code := CASE WHEN v_grp = '' THEN NULL
                               ELSE coalesce((SELECT code FROM ref.fee_group WHERE upper(code) = upper(v_grp)), (SELECT code FROM ref.fee_group WHERE upper(name) = upper(v_grp) LIMIT 1)) END;
            v_problem := finance.pg_fee_line_problem(v_stage, v_cat, v_level, v_spill, v_prog_code, v_mode, v_grp_code);
            -- V681: every problem kept (V653 kept the first 12 rows, so a file with more named only the first programme or two)
            IF v_problem IS NOT NULL THEN
                v_probs := v_probs || jsonb_build_object(
                    'row', v_pos, 'code', substring(v_problem from '^([A-Z_]+):'), 'text', regexp_replace(v_problem, '^[A-Z_]+: ', ''),
                    'prog', v_prog_code,
                    'who', CASE WHEN v_prog_code IS NOT NULL THEN v_prog_code WHEN v_fac <> '' THEN coalesce(v_fac_code, v_fac) ELSE 'every faculty' END,
                    'stage', coalesce(nullif(v_stage_cell, ''), nullif(v_cat_cell, '')));
            END IF;
            -- the level a faculty-wide or University-wide stage row replaces: the stage's, else the row's; none, every PG level
            IF v_prog_code IS NULL THEN
                v_level := coalesce((SELECT q.level FROM admissions.pg_stage s JOIN admissions.pg_qualification q ON q.code = s.qualification WHERE s.code = v_stage), v_level);
                IF v_level IS NULL THEN v_pg_all := true; ELSIF NOT (v_level = ANY (v_pg_levels)) THEN v_pg_levels := v_pg_levels || v_level; END IF;
            END IF;
        END IF;
    END LOOP;
    IF cardinality(v_unknown) > 0 THEN
        RAISE EXCEPTION 'FEE_STRUCTURE_UNKNOWN: the file names % that the portal does not hold; nothing was changed — correct the name or use the code',
            array_to_string(v_unknown, ', ') USING ERRCODE = '23514';
    END IF;
    -- V681: one entry a programme (or faculty) and kind of problem, in the order of the file: its rows (ranges), the stages its rows
    -- name, what is wrong and, where the stage is not of the programme's qualification, what its name reads as
    IF jsonb_array_length(v_probs) > 0 THEN
        WITH p AS (SELECT (e->>'row')::int AS rn, e->>'code' AS code, e->>'text' AS txt, e->>'prog' AS prog, e->>'who' AS who, e->>'stage' AS stage
                     FROM jsonb_array_elements(v_probs) e),
             isl AS (SELECT who, code, rn, rn - row_number() OVER (PARTITION BY who, code ORDER BY rn) AS k FROM p),
             rng AS (SELECT who, code, string_agg(CASE WHEN lo = hi THEN lo::text ELSE lo || '–' || hi END, ', ' ORDER BY lo) AS rows_text
                       FROM (SELECT who, code, min(rn) AS lo, max(rn) AS hi FROM isl GROUP BY who, code, k) x
                      GROUP BY who, code),
             stg AS (SELECT who, code, string_agg(stage, ', ' ORDER BY f) AS stages
                       FROM (SELECT who, code, stage, min(rn) AS f FROM p WHERE stage IS NOT NULL GROUP BY who, code, stage) x
                      GROUP BY who, code),
             g AS (SELECT who, code, min(rn) AS first_row, count(*) AS n, max(prog) AS prog,
                          -- one reason, or — rows of several stages failing alike — one for them all
                          CASE WHEN count(DISTINCT txt) = 1 THEN min(txt)
                               WHEN bool_and(txt LIKE '% is not a stage of the programme''s qualification') THEN 'these are not stages of the programme''s qualification'
                               ELSE string_agg(DISTINCT txt, ' / ') END AS txt
                     FROM p GROUP BY who, code)
        SELECT string_agg(
                   g.who || coalesce(' ' || pr.name, ' ' || fa.name, '')
                   || CASE WHEN g.code = 'FEE_PG_STAGE_PROGRAMME' AND pr.category = 'POST GRADUATE' AND q.label IS NOT NULL
                           THEN ' (its name reads as ' || q.label || ')' ELSE '' END
                   || ' — ' || CASE WHEN g.n = 1 THEN 'row ' ELSE 'rows ' END || r.rows_text
                   || coalesce(' (' || s.stages || ')', '') || ': ' || g.txt,
                   '; ' ORDER BY g.first_row),
               sum(g.n), count(DISTINCT g.who), count(DISTINCT g.prog)
          INTO v_msg, v_nrows, v_nwho, v_nprog
          FROM g
          JOIN rng r ON r.who = g.who AND r.code = g.code
          LEFT JOIN stg s ON s.who = g.who AND s.code = g.code
          LEFT JOIN ref.programme pr ON pr.code = g.prog
          LEFT JOIN ref.faculty fa ON g.prog IS NULL AND fa.code = g.who
          LEFT JOIN admissions.pg_qualification q ON q.code = admissions.pg_qualification_of(g.prog);
        RAISE EXCEPTION 'FEE_STRUCTURE_PG: the postgraduate rows do not agree with their stages (% % of %) — %; nothing was changed',
            v_nrows, CASE WHEN v_nrows = 1 THEN 'row' ELSE 'rows' END,
            CASE WHEN v_nwho = v_nprog THEN v_nprog || CASE WHEN v_nprog = 1 THEN ' programme' ELSE ' programmes' END
                 ELSE v_nwho || ' programmes or faculties' END,
            v_msg
            USING ERRCODE = '23514';
    END IF;

    IF v_scope = 'SESSION' THEN
        -- V535: the whole session is replaced only on purpose when the file leaves a faculty out
        SELECT string_agg(coalesce(fa.name, x.faculty_code) || ' (' || x.n || CASE WHEN x.n = 1 THEN ' line' ELSE ' lines' END || ')', ', ' ORDER BY coalesce(fa.name, x.faculty_code)), sum(x.n)
          INTO v_left, v_left_lines
          FROM (SELECT f.faculty_code, count(*) AS n FROM finance.fee_schedule f
                 WHERE f.session = p_session AND f.ended_at IS NULL AND f.faculty_code IS NOT NULL
                   AND ((v_cce AND f.entry_mode = 'CCE') OR (v_full AND f.entry_mode IS DISTINCT FROM 'CCE'))
                   AND NOT (f.faculty_code = ANY (v_row_facs || v_prog_facs || v_row_facs_pg))
                 GROUP BY f.faculty_code) x
          LEFT JOIN ref.faculty fa ON fa.code = x.faculty_code;
        -- V653: and when a file with no stage row would end the session's stage lines (those not already counted with a faculty)
        IF NOT v_has_pg THEN
            SELECT count(*) INTO v_pg_left FROM finance.fee_schedule f
             WHERE f.session = p_session AND f.ended_at IS NULL AND (f.pg_stage IS NOT NULL OR f.fee_category IS NOT NULL)
               AND ((v_cce AND f.entry_mode = 'CCE') OR (v_full AND f.entry_mode IS DISTINCT FROM 'CCE'))
               AND (f.faculty_code IS NULL OR f.faculty_code = ANY (v_row_facs || v_prog_facs));
            IF v_pg_left > 0 THEN
                v_left := concat_ws(', ', v_left, 'the postgraduate stages (' || v_pg_left || CASE WHEN v_pg_left = 1 THEN ' line' ELSE ' lines' END || ')');
                v_left_lines := coalesce(v_left_lines, 0) + v_pg_left;
            END IF;
        END IF;
        IF v_left IS NOT NULL AND NOT coalesce(p_confirm_whole, false) THEN
            RAISE EXCEPTION 'FEE_STRUCTURE_PARTIAL: this file states no fee for %; as the whole session it would end those % fee lines in force — upload it for the faculties and programmes in the file only, or confirm that the whole session is replaced',
                v_left, v_left_lines USING ERRCODE = '23514';
        END IF;
        -- replace the session's approved structure: end what stands, then load the new. V380: only the lines of the upload's own
        -- kind — a CCE (part-time) structure replaces the CCE lines, a full-time structure every other line
        UPDATE finance.fee_schedule SET ended_at = now()
         WHERE session = p_session AND ended_at IS NULL
           AND ((v_cce AND entry_mode = 'CCE') OR (v_full AND entry_mode IS DISTINCT FROM 'CCE'));
    ELSE
        -- V535: only what the file names — a programme's lines, a faculty's own lines, the University-wide lines — of its kind;
        -- V653: a faculty-wide or University-wide undergraduate row ends the lines with no stage or category, a stage or
        -- fresh/returning row the stage and category lines of its scope at the levels it states
        UPDATE finance.fee_schedule SET ended_at = now()
         WHERE session = p_session AND ended_at IS NULL
           AND ((v_cce AND entry_mode = 'CCE') OR (v_full AND entry_mode IS DISTINCT FROM 'CCE'))
           AND (programme_code = ANY (v_row_progs)
                OR (programme_code IS NULL AND faculty_code = ANY (v_row_facs) AND pg_stage IS NULL AND fee_category IS NULL)
                OR (v_universal AND programme_code IS NULL AND faculty_code IS NULL AND pg_stage IS NULL AND fee_category IS NULL)
                OR ((pg_stage IS NOT NULL OR fee_category IS NOT NULL) AND programme_code IS NULL
                    AND ((faculty_code = ANY (v_row_facs_pg)) OR (v_universal_pg AND faculty_code IS NULL))
                    AND (v_pg_all OR level = ANY (v_pg_levels))));
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_amt := nullif(regexp_replace(coalesce(r->>'amount', ''), '[^0-9.]', '', 'g'), '')::numeric;
        IF v_amt IS NULL OR v_amt < 0 THEN CONTINUE; END IF;
        n := n + 1;

        -- the faculty, by code or name
        v_fac := btrim(coalesce(r->>'faculty', r->>'facultyCode', r->>'faculty_code', ''));
        v_fac_code := NULL;
        IF v_fac <> '' THEN
            SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(code) = upper(v_fac);
            IF v_fac_code IS NULL THEN SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(name) = upper(v_fac) LIMIT 1; END IF;
            IF v_fac_code IS NULL THEN SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(name) LIKE '%' || upper(v_fac) || '%' LIMIT 1; END IF;
            IF v_fac_code IS NULL THEN nnf := nnf + 1; END IF;
        END IF;

        -- the programme, by code or name: the line is that programme's alone
        v_prog := btrim(coalesce(r->>'programmeCode', r->>'programme_code', r->>'programme', r->>'program', ''));
        v_prog_code := NULL;
        IF v_prog <> '' THEN
            SELECT code INTO v_prog_code FROM ref.programme WHERE upper(code) = upper(v_prog);
            IF v_prog_code IS NULL THEN SELECT code INTO v_prog_code FROM ref.programme WHERE upper(name) = upper(v_prog) ORDER BY archived LIMIT 1; END IF;
            IF v_prog_code IS NULL THEN nnp := nnp + 1; END IF;
            -- a programme names its faculty; the faculty column is not needed beside it
            IF v_prog_code IS NOT NULL AND v_fac_code IS NULL THEN SELECT faculty_code INTO v_fac_code FROM ref.programme WHERE code = v_prog_code; END IF;
        END IF;

        -- the fee group, by code or name
        v_grp := btrim(coalesce(r->>'feeGroup', r->>'fee_group', r->>'group', ''));
        v_grp_code := NULL;
        IF v_grp <> '' THEN
            SELECT code INTO v_grp_code FROM ref.fee_group WHERE upper(code) = upper(v_grp);
            IF v_grp_code IS NULL THEN SELECT code INTO v_grp_code FROM ref.fee_group WHERE upper(name) = upper(v_grp) LIMIT 1; END IF;
            IF v_grp_code IS NULL THEN nng := nng + 1; END IF;
        END IF;

        v_level := nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int;
        IF v_level IS NOT NULL AND v_level NOT IN (100,200,300,400,500,600,700,800,900) THEN v_level := NULL; END IF;
        v_mode := nullif(upper(replace(btrim(coalesce(r->>'entryMode', r->>'entry_mode', '')), ' ', '_')), '');
        IF v_mode IS NOT NULL AND v_mode NOT IN ('UTME','DIRECT_ENTRY','TRANSFER','POSTGRADUATE','JUPEB','SANDWICH','CCE') THEN v_mode := NULL; END IF;
        v_sem := nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int;
        IF v_sem IS NOT NULL AND v_sem NOT IN (1,2,3) THEN v_sem := NULL; END IF;
        v_ind := upper(btrim(coalesce(r->>'indigene', '')));
        v_ind := CASE WHEN v_ind LIKE 'IND%' THEN 'INDIGENE' WHEN v_ind LIKE 'NON%' OR v_ind LIKE 'NN%' THEN 'NON_INDIGENE' ELSE NULL END;
        v_spill_year := finance.spill_year_of(r->>'spillover', coalesce(r->>'spillYear', r->>'spill_year'));   -- V613: SP1, SP2, SP3
        v_spill := v_spill_year IS NOT NULL OR lower(btrim(coalesce(r->>'spillover', 'false'))) IN ('true', 't', '1', 'yes', 'y', 'spillover', 'spill');
        -- V613: a spillover line keeps the level the sheet gives it — the programme's final level — or has none and reaches every programme (V088)
        IF v_spill THEN nsp := nsp + 1; END IF;
        v_kind := upper(regexp_replace(btrim(coalesce(r->>'kind', r->>'type', '')), '[^A-Za-z]', '', 'g'));
        v_kind := CASE WHEN v_kind LIKE 'LATEPAY%' THEN 'LATE_PAYMENT' WHEN v_kind LIKE 'LATEREG%' THEN 'LATE_REGISTRATION' ELSE 'FEE' END;
        -- V653: the stage (its level the stage's when the row gives none) and fresh/returning
        v_stage := finance.pg_stage_from_text(coalesce(r->>'pgStage', r->>'pg_stage', r->>'stage'));
        v_cat := finance.fee_category_from_text(coalesce(r->>'feeCategory', r->>'fee_category', r->>'category'));
        v_item := nullif(btrim(coalesce(r->>'item', '')), '');
        IF v_item IS NULL THEN
            v_item := CASE v_kind WHEN 'LATE_PAYMENT' THEN 'Late payment fee' WHEN 'LATE_REGISTRATION' THEN 'Late registration fee'
                                  ELSE CASE WHEN v_spill_year IS NOT NULL THEN 'School fees (spillover SP' || v_spill_year || ')' WHEN v_spill THEN 'School fees (spillover)' ELSE 'School fees' END END
                      || CASE WHEN v_sem IS NULL THEN '' ELSE ' (semester ' || v_sem || ')' END;
        END IF;
        v_ord := coalesce(nullif(regexp_replace(coalesce(r->>'ord', r->>'order', ''), '[^0-9]', '', 'g'), '')::int,
                          coalesce(v_sem, 1) + CASE WHEN v_spill THEN 100 ELSE 0 END);

        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, fee_group, semester, indigene, ord, spillover, spill_year, kind,
                                          pg_stage, fee_category)
        VALUES (p_session, v_item, v_amt, v_level, v_mode, v_fac_code, v_prog_code, v_grp_code, v_sem, v_ind, v_ord, v_spill, v_spill_year, v_kind,
                v_stage, v_cat);
        nl := nl + 1;
        IF v_fac_code IS NOT NULL AND NOT (v_fac_code = ANY(facs)) THEN facs := facs || v_fac_code; END IF;
        IF v_prog_code IS NOT NULL AND NOT (v_prog_code = ANY(progs)) THEN progs := progs || v_prog_code; END IF;
    END LOOP;
    RETURN QUERY SELECT n, nl, cardinality(facs), nnf, nnp, nng, nsp, cardinality(progs);
END $function$;

COMMIT;
