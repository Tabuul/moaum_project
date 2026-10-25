-- V653: the fee spreadsheet upload with postgraduate stages. V651 let a fee line name a PG stage (800 B — Year 2) or fresh or
-- returning students, from the Fee Setup form and the Postgraduate fee structure panel; the uploads did not know of either:
--   · the structure upload (finance.import_fee_structure) could not state a stage line, and a University-wide or faculty-wide row
--     of an undergraduate file, uploaded for the faculties in the file only, ended the stage lines of the same scope with it;
--   · the "fees to state" sheet (finance.add_fee_lines) did not tell a stage line from the level's line in its duplicate check;
--   · the preview of either (finance.fee_upload_effect) paired an old and a new line by scope without the stage, so an 800 B line
--     and an 800 A line of one programme could read as one line changed.
-- Now:
--   · finance.pg_stage_from_text reads a stage cell however a person writes it — 800B, 800 B, "800 B — Year 2", 700 Extension,
--     900 D — Extension 1 — against the stages in use; finance.fee_category_from_text reads Fresh / Returning (F, R, New, Old);
--   · finance.pg_fee_line_problem says what is wrong with a PG line (its stage, level, spillover, programme, category) in one
--     place: the table's guard (finance.trg_fee_line_pg, restated to call it) and the upload's own check read it alike;
--   · the structure upload reads a "PG stage" and a "Fresh or returning" column: every PG row checked before anything changes
--     (FEE_STRUCTURE_PG names the rows), an unknown stage refused with the names the file holds wrong (FEE_STRUCTURE_UNKNOWN);
--     uploaded for the faculties and programmes in the file, an undergraduate row ends the lines of its kind only and a stage row
--     the stage lines of its scope and level; as the whole session, a file with no stage row that would end stage lines asks to
--     be confirmed (FEE_STRUCTURE_PARTIAL), as it does for a faculty it leaves out;
--   · the "fees to state" sheet reads the stage and category, and a line already stated for the stage is not added twice;
--   · the preview pairs lines by stage and category too, and names the stage of each change;
--   · finance.pg_unstated_by_stage: the PG students with no fee stated, by programme, level, stage and fresh or returning — what
--     the Bursary states next (finance.pg_unstated is kept as it was, the readiness and its checks read it).

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V653: the fee spreadsheet upload with postgraduate stages', true);

-- ── a stage cell and a fresh/returning cell, as a person writes them ──
CREATE OR REPLACE FUNCTION finance.pg_stage_from_text(p_text text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
    -- the code (800B), the code spaced (800 B), the label (800 B — Year 2, 700 Extension, 700 Level) or the short label, read
    -- without case, spaces or punctuation; the stages in use only
    SELECT s.code
      FROM admissions.pg_stage s
     WHERE s.active
       AND nullif(lower(regexp_replace(coalesce(p_text, ''), '[^A-Za-z0-9]', '', 'g')), '') IN
           (lower(s.code), lower(regexp_replace(s.label, '[^A-Za-z0-9]', '', 'g')), lower(regexp_replace(s.short_label, '[^A-Za-z0-9]', '', 'g')))
     ORDER BY s.sequence
     LIMIT 1
$$;
COMMENT ON FUNCTION finance.pg_stage_from_text(text) IS
  'V653: a PG stage cell of a fee spreadsheet read to its code — 800B, 800 B, "800 B — Year 2", 700 Extension — against the stages in use; NULL when it names none.';

CREATE OR REPLACE FUNCTION finance.fee_category_from_text(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN w IN ('FRESH', 'F', 'NEW', 'FRESHER', 'FRESHERS', 'FRESHSTUDENTS') THEN 'FRESH'
                WHEN w IN ('RETURNING', 'R', 'OLD', 'RETURNINGSTUDENTS', 'CONTINUING') THEN 'RETURNING' END
      FROM (SELECT upper(regexp_replace(coalesce(p_text, ''), '[^A-Za-z]', '', 'g')) AS w) x
$$;
COMMENT ON FUNCTION finance.fee_category_from_text(text) IS
  'V653: a "Fresh or returning" cell of a fee spreadsheet: FRESH (Fresh, F, New) or RETURNING (Returning, R, Old, Continuing); NULL otherwise.';

-- ── what is wrong with a PG line, in one place ──
CREATE OR REPLACE FUNCTION finance.pg_fee_line_problem(p_stage text, p_category text, p_level integer, p_spillover boolean, p_programme text,
                                                       p_entry_mode text, p_fee_group text, p_insert boolean DEFAULT true)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE st admissions.pg_stage; v_level int;
BEGIN
    IF p_stage IS NOT NULL THEN
        SELECT * INTO st FROM admissions.pg_stage WHERE code = p_stage;
        IF NOT FOUND THEN
            RETURN format('FEE_PG_STAGE: %s is not a postgraduate stage', p_stage);
        END IF;
        SELECT q.level INTO v_level FROM admissions.pg_qualification q WHERE q.code = st.qualification;
        IF p_insert AND NOT st.active THEN
            RETURN format('FEE_PG_STAGE: %s is not a stage in use', st.label);
        END IF;
        IF coalesce(p_level, v_level) <> v_level THEN
            RETURN format('FEE_PG_STAGE_LEVEL: %s is a %s Level stage, not %s Level', st.label, v_level, p_level);
        END IF;
        IF coalesce(p_spillover, false) THEN
            RETURN 'FEE_PG_STAGE_SPILLOVER: a postgraduate stage line is not a spillover line';
        END IF;
        -- a stage line names a postgraduate programme (one of the School's, or one a postgraduate student is on)
        IF p_programme IS NOT NULL AND NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = p_programme AND p.category = 'POST GRADUATE')
           AND NOT EXISTS (SELECT 1 FROM people.student x WHERE x.programme_code = p_programme AND x.entry_mode = 'POSTGRADUATE') THEN
            RETURN format('FEE_PG_STAGE_PROGRAMME: %s is not a postgraduate programme', p_programme);
        END IF;
        IF p_programme IS NOT NULL AND admissions.pg_qualification_of(p_programme) IS DISTINCT FROM st.qualification THEN
            RETURN format('FEE_PG_STAGE_PROGRAMME: %s is not a stage of the programme''s qualification', st.label);
        END IF;
        IF p_category IS NOT NULL AND p_category <> (CASE WHEN st.sequence = 1 THEN 'FRESH' ELSE 'RETURNING' END) THEN
            RETURN format('FEE_PG_STAGE_CATEGORY: %s is %s', st.label,
                          CASE WHEN st.sequence = 1 THEN 'the first stage: its students are FRESH' ELSE 'a later stage: its students are RETURNING' END);
        END IF;
    ELSIF p_category IS NOT NULL
          AND NOT (coalesce(p_level, 0) IN (700, 800, 900) OR p_entry_mode IS NOT DISTINCT FROM 'POSTGRADUATE'
                   OR EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = p_programme AND p.category = 'POST GRADUATE')
                   OR EXISTS (SELECT 1 FROM ref.fee_group g WHERE g.code = p_fee_group AND g.applies_category = 'POST GRADUATE')) THEN
        RETURN 'FEE_PG_CATEGORY: fresh and returning are postgraduate categories — the line names a PG level, the Postgraduate entry mode, a PG programme or the PG group';
    END IF;
    RETURN NULL;
END $$;
COMMENT ON FUNCTION finance.pg_fee_line_problem(text, text, integer, boolean, text, text, text, boolean) IS
  'V653: what is wrong with a fee line''s PG stage or category ("CODE: message"), NULL when nothing is — read by the table''s guard and by the uploads before they change anything.';

-- the table's guard (V651) restated to read it: the same refusals, the level and the category set by the stage
CREATE OR REPLACE FUNCTION finance.trg_fee_line_pg()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE v_problem text; st admissions.pg_stage;
BEGIN
    v_problem := finance.pg_fee_line_problem(NEW.pg_stage, NEW.fee_category, NEW.level, NEW.spillover, NEW.programme_code, NEW.entry_mode,
                                             NEW.fee_group, TG_OP = 'INSERT');
    IF v_problem IS NOT NULL THEN
        RAISE EXCEPTION '%', v_problem USING ERRCODE = '23514';
    END IF;
    IF NEW.pg_stage IS NOT NULL THEN
        SELECT * INTO st FROM admissions.pg_stage WHERE code = NEW.pg_stage;
        NEW.level := coalesce(NEW.level, (SELECT q.level FROM admissions.pg_qualification q WHERE q.code = st.qualification));
        NEW.fee_category := CASE WHEN st.sequence = 1 THEN 'FRESH' ELSE 'RETURNING' END;
    END IF;
    RETURN NEW;
END $$;

-- ── the structure upload (V535, V613) with the PG stage and fresh/returning ──
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
        v_problem text; v_bad text[] := '{}'; v_pg_left int;
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
            IF v_problem IS NOT NULL AND cardinality(v_bad) < 12 THEN
                v_bad := v_bad || format('row %s (%s%s): %s', v_pos, coalesce(nullif(v_prog, ''), nullif(v_fac, ''), 'every faculty'),
                                         CASE WHEN v_stage_cell <> '' THEN ', ' || v_stage_cell WHEN v_cat_cell <> '' THEN ', ' || v_cat_cell ELSE '' END,
                                         regexp_replace(v_problem, '^[A-Z_]+: ', ''));
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
    IF cardinality(v_bad) > 0 THEN
        RAISE EXCEPTION 'FEE_STRUCTURE_PG: the postgraduate rows do not agree with their stages — %; nothing was changed', array_to_string(v_bad, '; ')
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

-- ── the "fees to state" sheet (V461, V613) with the PG stage and fresh/returning ──
CREATE OR REPLACE FUNCTION finance.add_fee_lines(p_session text, p_rows jsonb)
 RETURNS TABLE(rows integer, added integer, no_amount integer, already integer, no_programme integer, charged_as integer, skipped integer, first_error text)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_prog text; v_fac text; v_level int; v_mode text; v_sem int; v_ind text; v_spill boolean; v_spill_year int; v_amt numeric; v_item text;
        n int := 0; na int := 0; nb int := 0; nal int := 0; nnp int := 0; nca int := 0; ns int := 0; v_err text;
        v_stage_cell text; v_cat_cell text; v_stage text; v_cat text;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'FEE_LINES_PERSON: fee lines are added by a person' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN
        RAISE EXCEPTION 'FEE_LINES_SESSION: % is not on the calendar', p_session USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'FEE_LINES_ROWS: the sheet is rows: programme, level, entry mode, semester, indigeneship and the amount' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        n := n + 1;
        BEGIN
            v_amt := nullif(regexp_replace(coalesce(r->>'amount', ''), '[^0-9.]', '', 'g'), '')::numeric;
            IF v_amt IS NULL THEN nb := nb + 1; CONTINUE; END IF;
            -- a programme's line, or — with no programme — a faculty's line (the sheet asks for the faculty a
            -- "charged as" faculty follows, V451, so its own students and the faculty's are stated together)
            v_prog := nullif(upper(btrim(coalesce(r->>'programmeCode', r->>'programme_code', r->>'programme', ''))), '');
            v_fac := nullif(upper(btrim(coalesce(r->>'facultyCode', r->>'faculty_code', ''))), '');
            IF v_prog IS NOT NULL THEN
                SELECT p.code, p.faculty_code INTO v_prog, v_fac FROM ref.programme p WHERE upper(p.code) = v_prog;
                IF v_prog IS NULL THEN nnp := nnp + 1; CONTINUE; END IF;
                -- a line of its own would end the rule for every student of a faculty charged as another: refused here
                IF finance.fee_source_of(v_fac, p_session) IS NOT NULL THEN nca := nca + 1; CONTINUE; END IF;
            ELSE
                SELECT f.code INTO v_fac FROM ref.faculty f WHERE upper(f.code) = v_fac;
                IF v_fac IS NULL THEN nnp := nnp + 1; CONTINUE; END IF;
                IF finance.fee_source_of(v_fac, p_session) IS NOT NULL THEN nca := nca + 1; CONTINUE; END IF;
            END IF;
            -- V613: the Spillover cell says Yes (any spillover year) or SP1, SP2, SP3 (that year alone); a spillYear column likewise
            v_spill_year := finance.spill_year_of(r->>'spillover', coalesce(r->>'spillYear', r->>'spill_year'));
            v_spill := v_spill_year IS NOT NULL OR lower(btrim(coalesce(r->>'spillover', ''))) IN ('true', 't', '1', 'yes', 'y', 'spillover', 'spill');
            -- V613: a spillover line's level, where the sheet gives one, is the programme's final level (400 on a four-year programme)
            v_level := nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int;
            IF v_level IS NOT NULL AND v_level NOT IN (100, 200, 300, 400, 500, 600, 700, 800, 900) THEN v_level := NULL; END IF;
            v_mode := nullif(upper(replace(btrim(coalesce(r->>'entryMode', r->>'entry_mode', '')), ' ', '_')), '');
            IF v_mode IS NOT NULL AND v_mode NOT IN ('UTME', 'DIRECT_ENTRY', 'TRANSFER', 'POSTGRADUATE', 'JUPEB', 'SANDWICH') THEN v_mode := NULL; END IF;
            v_sem := nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int;
            IF v_sem IS NOT NULL AND v_sem NOT IN (1, 2, 3) THEN v_sem := NULL; END IF;
            v_ind := upper(btrim(coalesce(r->>'indigene', '')));
            v_ind := CASE WHEN v_ind LIKE 'NON%' OR v_ind LIKE 'NN%' THEN 'NON_INDIGENE' WHEN v_ind LIKE 'IND%' THEN 'INDIGENE' ELSE NULL END;
            -- V653: the PG stage (its level the stage's) and fresh/returning; a cell naming neither is the row's error
            v_stage_cell := btrim(coalesce(r->>'pgStage', r->>'pg_stage', r->>'stage', ''));
            v_cat_cell := btrim(coalesce(r->>'feeCategory', r->>'fee_category', r->>'category', ''));
            v_stage := finance.pg_stage_from_text(v_stage_cell);
            v_cat := finance.fee_category_from_text(v_cat_cell);
            IF v_stage_cell <> '' AND v_stage IS NULL THEN
                RAISE EXCEPTION 'FEE_PG_STAGE: % is not a postgraduate stage in use', v_stage_cell USING ERRCODE = '23514';
            END IF;
            IF v_cat_cell <> '' AND v_cat IS NULL THEN
                RAISE EXCEPTION 'FEE_PG_CATEGORY: "%" is neither Fresh nor Returning', v_cat_cell USING ERRCODE = '23514';
            END IF;
            IF v_stage IS NOT NULL THEN
                v_level := coalesce(v_level, (SELECT q.level FROM admissions.pg_stage s JOIN admissions.pg_qualification q ON q.code = s.qualification WHERE s.code = v_stage));
                v_cat := coalesce(v_cat, (SELECT CASE WHEN s.sequence = 1 THEN 'FRESH' ELSE 'RETURNING' END FROM admissions.pg_stage s WHERE s.code = v_stage));
            END IF;
            -- a line the schedule already holds is not added twice
            IF EXISTS (SELECT 1 FROM finance.fee_schedule f
                        WHERE f.session = p_session AND f.ended_at IS NULL AND f.kind = 'FEE'
                          AND f.programme_code IS NOT DISTINCT FROM v_prog AND f.faculty_code IS NOT DISTINCT FROM v_fac
                          AND f.level IS NOT DISTINCT FROM v_level AND f.entry_mode IS NOT DISTINCT FROM v_mode
                          AND f.semester IS NOT DISTINCT FROM v_sem AND f.indigene IS NOT DISTINCT FROM v_ind AND f.spillover = v_spill AND f.spill_year IS NOT DISTINCT FROM v_spill_year
                          AND f.pg_stage IS NOT DISTINCT FROM v_stage AND f.fee_category IS NOT DISTINCT FROM v_cat) THEN
                nal := nal + 1; CONTINUE;
            END IF;
            v_item := CASE WHEN v_spill_year IS NOT NULL THEN 'School fees (spillover SP' || v_spill_year || ')' WHEN v_spill THEN 'School fees (spillover)' ELSE 'School fees' END
                      || CASE WHEN v_sem IS NULL THEN '' ELSE ' (semester ' || v_sem || ')' END;
            INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, semester, indigene, ord, spillover, spill_year, kind,
                                              pg_stage, fee_category)
            VALUES (p_session, v_item, v_amt, v_level, v_mode, v_fac, v_prog, v_sem, v_ind,
                    coalesce(v_sem, 1) + CASE WHEN v_spill THEN 100 ELSE 0 END, v_spill, v_spill_year, 'FEE', v_stage, v_cat);
            na := na + 1;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_err IS NULL THEN v_err := left('row ' || n || ': ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, na, nb, nal, nnp, nca, ns, v_err;
END $function$;

-- ── the preview of an upload (V535, V547, V613): lines paired by stage and category too, the stage named ──
CREATE OR REPLACE FUNCTION finance.fee_upload_effect(p_session text, p_rows jsonb, p_action text, p_scope text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE v_before jsonb; v_gaps_before jsonb; v_res jsonb; v_out jsonb; v_msg text; v_action text := upper(btrim(coalesce(p_action, '')));
BEGIN
    IF v_action NOT IN ('STRUCTURE', 'LINES', 'CLEAR') THEN
        RAISE EXCEPTION 'FEE_UPLOAD_ACTION: an upload is the structure (STRUCTURE) or the fees to state (LINES); clearing is CLEAR' USING ERRCODE = '23514';
    END IF;
    SELECT coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb) INTO v_before
      FROM (SELECT id, faculty_code, programme_code, level, entry_mode, semester, indigene, spillover, spill_year, kind, fee_group, item, amount, pg_stage, fee_category
              FROM finance.fee_schedule WHERE session = p_session AND ended_at IS NULL) f;
    SELECT jsonb_build_object('students', coalesce(sum(g.students), 0), 'groups', count(*)) INTO v_gaps_before FROM finance.fee_gaps(p_session) g;
    BEGIN
        IF v_action = 'LINES' THEN
            SELECT to_jsonb(x) INTO v_res FROM finance.add_fee_lines(p_session, p_rows) x;
        ELSIF v_action = 'CLEAR' THEN
            -- V547: what "Clear the schedule" would end — every line of the session, or its full-time or its CCE lines alone
            WITH ended AS (
                UPDATE finance.fee_schedule SET ended_at = now()
                 WHERE session = p_session AND ended_at IS NULL
                   AND CASE upper(coalesce(p_scope, 'ALL')) WHEN 'CCE' THEN entry_mode = 'CCE'
                                                           WHEN 'FULL_TIME' THEN entry_mode IS DISTINCT FROM 'CCE' ELSE true END
                RETURNING 1)
            -- the live students of that kind, who would owe no school fee for the session (the gap list says nothing once a
            -- session states no line at all)
            SELECT jsonb_build_object('ended', (SELECT count(*) FROM ended),
                     'students', (SELECT count(*) FROM people.student st JOIN ref.programme pr ON pr.code = st.programme_code
                                   WHERE st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
                                     AND CASE upper(coalesce(p_scope, 'ALL')) WHEN 'CCE' THEN st.entry_mode = 'CCE'
                                              WHEN 'FULL_TIME' THEN st.entry_mode IS DISTINCT FROM 'CCE' ELSE true END))
              INTO v_res;
        ELSE
            SELECT to_jsonb(x) INTO v_res FROM finance.import_fee_structure(p_session, p_rows, coalesce(p_scope, 'LISTED'), true) x;
        END IF;
        WITH b AS (
            SELECT * FROM jsonb_to_recordset(v_before) AS x(id uuid, faculty_code text, programme_code text, level int, entry_mode text, semester int,
                                                              indigene text, spillover boolean, spill_year int, kind text, fee_group text, item text, amount numeric,
                                                              pg_stage text, fee_category text)),
        a AS (
            SELECT id, faculty_code, programme_code, level, entry_mode, semester, indigene, spillover, spill_year, kind, fee_group, item, amount, pg_stage, fee_category
              FROM finance.fee_schedule WHERE session = p_session AND ended_at IS NULL),
        ended AS (SELECT b.*, row(b.faculty_code, b.programme_code, b.level, b.entry_mode, b.semester, b.indigene, b.spillover, b.spill_year, b.kind, b.fee_group, lower(btrim(b.item)),
                                  b.pg_stage, b.fee_category)::text AS k
                    FROM b WHERE NOT EXISTS (SELECT 1 FROM a WHERE a.id = b.id)),
        added AS (SELECT a.*, row(a.faculty_code, a.programme_code, a.level, a.entry_mode, a.semester, a.indigene, a.spillover, a.spill_year, a.kind, a.fee_group, lower(btrim(a.item)),
                                  a.pg_stage, a.fee_category)::text AS k
                    FROM a WHERE NOT EXISTS (SELECT 1 FROM b WHERE b.id = a.id)),
        pairs AS (
            SELECT coalesce(d.faculty_code, e.faculty_code) AS faculty_code, coalesce(d.programme_code, e.programme_code) AS programme_code,
                   coalesce(d.level, e.level) AS level, coalesce(d.entry_mode, e.entry_mode) AS entry_mode, coalesce(d.semester, e.semester) AS semester,
                   coalesce(d.indigene, e.indigene) AS indigene, coalesce(d.spillover, e.spillover) AS spillover, coalesce(d.spill_year, e.spill_year) AS spill_year, coalesce(d.item, e.item) AS item,
                   coalesce(d.pg_stage, e.pg_stage) AS pg_stage, coalesce(d.fee_category, e.fee_category) AS fee_category,
                   e.amount AS old, d.amount AS new,
                   CASE WHEN e.k IS NULL THEN 'NEW' WHEN d.k IS NULL THEN 'ENDED' WHEN e.amount = d.amount THEN 'SAME' ELSE 'CHANGED' END AS what
              FROM ended e FULL JOIN added d ON d.k = e.k),
        named AS (
            SELECT p.*, coalesce(fa.name, p.faculty_code, 'Every faculty') AS faculty, pr.name AS programme, st.label AS pg_stage_label
              FROM pairs p LEFT JOIN ref.faculty fa ON fa.code = p.faculty_code LEFT JOIN ref.programme pr ON pr.code = p.programme_code
              LEFT JOIN admissions.pg_stage st ON st.code = p.pg_stage),
        grp AS (
            SELECT n.faculty, n.faculty_code, n.programme, n.programme_code,
                   count(*) FILTER (WHERE n.what = 'NEW') AS new, count(*) FILTER (WHERE n.what = 'CHANGED') AS changed,
                   count(*) FILTER (WHERE n.what = 'SAME') AS same, count(*) FILTER (WHERE n.what = 'ENDED') AS ended,
                   count(*) FILTER (WHERE n.what = 'ENDED' AND (n.pg_stage IS NOT NULL OR n.fee_category IS NOT NULL)) AS ended_stage
              FROM named n GROUP BY 1, 2, 3, 4),
        kept AS (   -- of each faculty or programme the upload touches, the lines that stay in force as they were
            SELECT a.faculty_code, a.programme_code, count(*) AS n FROM a WHERE NOT EXISTS (SELECT 1 FROM added d WHERE d.id = a.id) GROUP BY 1, 2),
        gaps AS (SELECT * FROM finance.fee_gaps(p_session))
        SELECT jsonb_build_object(
            'action', v_action, 'scope', CASE WHEN v_action = 'STRUCTURE' THEN coalesce(upper(p_scope), 'LISTED') WHEN v_action = 'CLEAR' THEN coalesce(upper(p_scope), 'ALL') END, 'result', v_res,
            'linesBefore', jsonb_array_length(v_before), 'linesAfter', (SELECT count(*) FROM a),
            'totals', (SELECT jsonb_build_object('new', coalesce(sum(new), 0), 'changed', coalesce(sum(changed), 0), 'same', coalesce(sum(same), 0), 'ended', coalesce(sum(ended), 0),
                                                 'endedStage', coalesce(sum(ended_stage), 0)) FROM grp),
            'groups', (SELECT coalesce(jsonb_agg(jsonb_build_object('faculty', g.faculty, 'facultyCode', g.faculty_code, 'programme', g.programme, 'programmeCode', g.programme_code,
                                                                     'new', g.new, 'changed', g.changed, 'same', g.same, 'ended', g.ended,
                                                                     'losesAll', g.ended > 0 AND g.new + g.changed + g.same = 0
                                                                                 AND NOT EXISTS (SELECT 1 FROM kept k WHERE k.faculty_code IS NOT DISTINCT FROM g.faculty_code
                                                                                                                         AND k.programme_code IS NOT DISTINCT FROM g.programme_code))
                                                  ORDER BY g.faculty, g.programme NULLS FIRST), '[]'::jsonb) FROM grp g),
            'changes', (SELECT coalesce(jsonb_agg(c ORDER BY c->>'faculty', c->>'programme', (c->>'semester')::int NULLS FIRST, (c->>'level')::int NULLS LAST, c->>'pgStage' NULLS FIRST), '[]'::jsonb)
                          FROM (SELECT jsonb_build_object('faculty', n.faculty, 'programme', n.programme, 'level', n.level, 'entryMode', n.entry_mode, 'semester', n.semester,
                                                          'indigene', n.indigene, 'spillover', n.spillover, 'spillYear', n.spill_year, 'item', n.item, 'old', n.old, 'new', n.new,
                                                          'pgStage', n.pg_stage, 'pgStageLabel', n.pg_stage_label, 'feeCategory', n.fee_category) AS c
                                  FROM named n WHERE n.what = 'CHANGED' ORDER BY n.faculty, n.programme, n.semester, n.level, n.pg_stage LIMIT 400) x),
            'gaps', jsonb_build_object(
                'before', v_gaps_before,
                'after', (SELECT jsonb_build_object('students', coalesce(sum(students), 0), 'groups', count(*)) FROM gaps),
                'rows', (SELECT coalesce(jsonb_agg(jsonb_build_object('faculty', coalesce(x.faculty, x.faculty_code), 'programme', x.programme, 'level', x.level,
                                                                      'entryMode', x.entry_mode, 'spillover', x.spillover, 'spillYear', x.spill_year, 'finalLevel', x.final_level, 'students', x.students)
                                                    ORDER BY x.students DESC), '[]'::jsonb)
                           FROM (SELECT * FROM gaps ORDER BY students DESC LIMIT 60) x)))
          INTO v_out;
        RAISE EXCEPTION 'FEE_UPLOAD_PREVIEW_UNDO';
    EXCEPTION WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg <> 'FEE_UPLOAD_PREVIEW_UNDO' THEN RAISE; END IF;
    END;
    RETURN v_out;
END $function$;

-- ── the PG students with no fee stated, by stage: what the Bursary states next ──
CREATE OR REPLACE FUNCTION finance.pg_unstated_by_stage(p_session text)
RETURNS TABLE(level integer, programme_code text, programme text, stage_code text, stage_label text, category text, students bigint)
LANGUAGE sql
STABLE
AS $$
    -- as finance.pg_unstated (V447, V651), each student's stage read for the list; alike students are told apart by the stage and
    -- category only when the session states a line by them (else one student of a group answers for it, as before)
    WITH staged AS MATERIALIZED (SELECT EXISTS (SELECT 1 FROM finance.fee_schedule f WHERE f.session = p_session AND f.ended_at IS NULL
                                                AND (f.pg_stage IS NOT NULL OR f.fee_category IS NOT NULL)) AS y),
    pgs AS MATERIALIZED (SELECT x.student_id, x.stage_code, x.category FROM admissions.pg_stages_of(p_session, NULL) x),
    live AS (
        SELECT s.id, s.current_level, s.programme_code, p.name, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) = lower(h.home_state) AS indigene,
               pgs.stage_code, pgs.category,
               CASE WHEN staged.y THEN pgs.stage_code END AS stage_key, CASE WHEN staged.y THEN pgs.category END AS category_key
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
          CROSS JOIN staged
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          LEFT JOIN finance.fee_setting h ON h.id = 1
          LEFT JOIN pgs ON pgs.student_id = s.id
         WHERE people.is_postgraduate(s.entry_mode, p.category)
           AND s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
    alike AS (
        SELECT g.programme_code, g.current_level, g.entry_mode, g.indigene, g.stage_key, g.category_key, finance.fee_stated(g.one, p_session) AS stated
          FROM (SELECT l.programme_code, l.current_level, l.entry_mode, l.indigene, l.stage_key, l.category_key, (array_agg(l.id))[1] AS one
                  FROM live l
                 GROUP BY l.programme_code, l.current_level, l.entry_mode, l.indigene, l.stage_key, l.category_key) g)
    SELECT l.current_level, l.programme_code, l.name, l.stage_code, st.label, l.category, count(*)
      FROM live l
      JOIN alike a ON a.programme_code = l.programme_code
                  AND a.current_level IS NOT DISTINCT FROM l.current_level
                  AND a.entry_mode IS NOT DISTINCT FROM l.entry_mode
                  AND a.indigene IS NOT DISTINCT FROM l.indigene
                  AND a.stage_key IS NOT DISTINCT FROM l.stage_key
                  AND a.category_key IS NOT DISTINCT FROM l.category_key
      LEFT JOIN admissions.pg_stage st ON st.code = l.stage_code
     WHERE NOT a.stated
     GROUP BY l.current_level, l.programme_code, l.name, l.stage_code, st.label, st.sequence, l.category
     ORDER BY l.current_level, l.programme_code, st.sequence NULLS LAST;
$$;
COMMENT ON FUNCTION finance.pg_unstated_by_stage(text) IS
  'V653: the live PG students with no fee line stated for the session, by programme, level, PG stage and fresh/returning — the stage the Bursary states next. finance.pg_unstated is the same count without the stage.';

COMMIT;
