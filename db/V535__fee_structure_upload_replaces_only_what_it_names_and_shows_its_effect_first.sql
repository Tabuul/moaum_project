-- V535: the fees structure upload replaces only what it names unless told otherwise, refuses names the portal does not hold, and
-- either fee upload shows its effect before it changes anything.
--
-- finance.import_fee_structure (V083, V313, V379, V380) replaced the session's whole full-time (or CCE) structure with the file,
-- so a file stating one college's fees ended every other faculty's lines (17 Oct 2026: the College of Health Sciences' sheet,
-- loaded that way, would have left eleven faculties with no fee for 2025/2026). And a faculty or programme name it did not
-- know became a line with no faculty — a fee charged to every student of the University.
--
-- Now:
--   * finance.import_fee_structure(session, rows, scope, confirm_whole): scope LISTED replaces only the faculties and programmes
--     the file names (a faculty's own lines for a faculty row, a programme's lines for a programme row, the University-wide lines
--     for a row naming neither) and leaves every other line as it is; scope SESSION replaces the whole structure as before, but is
--     refused (FEE_STRUCTURE_PARTIAL, naming them) when the file states no fee for a faculty that has lines in force, unless
--     confirm_whole says the Bursary means it. The two-argument form is scope SESSION, unconfirmed.
--   * a faculty or programme the file names that the portal does not hold refuses the upload (FEE_STRUCTURE_UNKNOWN, naming it):
--     nothing is changed, and no line is ever made for every student by a misspelt name.
--   * finance.fee_upload_effect(session, rows, action, scope): the structure upload (action STRUCTURE) or the "fees to state"
--     lines (action LINES) applied and undone, and what they would do returned: the lines in force before and after, for each
--     faculty or programme the lines new, changed (old and new amount), the same and ended, the faculties that would lose every
--     line, every amount that would change, and the students with no fee stated before and after — nothing is kept.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'bursar', true);
SELECT set_config('moaum.reason', 'V535: the fees structure upload replaces only what it names and shows its effect first', true);

CREATE FUNCTION finance.import_fee_structure(p_session text, p_rows jsonb, p_scope text, p_confirm_whole boolean)
 RETURNS TABLE(rows integer, lines integer, faculties integer, no_faculty integer, no_programme integer, no_group integer, spillover integer, programmes integer)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_scope text := upper(btrim(coalesce(p_scope, 'SESSION')));
        v_fac text; v_fac_code text; v_level int; v_mode text; v_sem int; v_ind text; v_amt numeric; v_item text; v_ord int;
        v_spill boolean; v_prog text; v_prog_code text; v_grp text; v_grp_code text; v_kind text; v_cce boolean; v_full boolean;
        n int := 0; nl int := 0; nnf int := 0; nnp int := 0; nng int := 0; nsp int := 0; facs text[] := '{}'; progs text[] := '{}';
        v_unknown text[] := '{}'; v_row_facs text[] := '{}'; v_row_progs text[] := '{}'; v_prog_facs text[] := '{}'; v_universal boolean := false;
        v_left text; v_left_lines int;
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
        v_amt := nullif(regexp_replace(coalesce(r->>'amount', ''), '[^0-9.]', '', 'g'), '')::numeric;
        IF v_amt IS NULL OR v_amt < 0 THEN CONTINUE; END IF;
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
            ELSIF NOT (v_fac_code = ANY (v_row_facs)) THEN v_row_facs := v_row_facs || v_fac_code;
            END IF;
        ELSE
            v_universal := true;
        END IF;
    END LOOP;
    IF cardinality(v_unknown) > 0 THEN
        RAISE EXCEPTION 'FEE_STRUCTURE_UNKNOWN: the file names % that the portal does not hold; nothing was changed — correct the name or use the code',
            array_to_string(v_unknown, ', ') USING ERRCODE = '23514';
    END IF;

    IF v_scope = 'SESSION' THEN
        -- V535: the whole session is replaced only on purpose when the file leaves a faculty out
        SELECT string_agg(coalesce(fa.name, x.faculty_code) || ' (' || x.n || CASE WHEN x.n = 1 THEN ' line' ELSE ' lines' END || ')', ', ' ORDER BY coalesce(fa.name, x.faculty_code)), sum(x.n)
          INTO v_left, v_left_lines
          FROM (SELECT f.faculty_code, count(*) AS n FROM finance.fee_schedule f
                 WHERE f.session = p_session AND f.ended_at IS NULL AND f.faculty_code IS NOT NULL
                   AND ((v_cce AND f.entry_mode = 'CCE') OR (v_full AND f.entry_mode IS DISTINCT FROM 'CCE'))
                   AND NOT (f.faculty_code = ANY (v_row_facs || v_prog_facs))
                 GROUP BY f.faculty_code) x
          LEFT JOIN ref.faculty fa ON fa.code = x.faculty_code;
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
        -- V535: only what the file names — a programme's lines, a faculty's own lines, the University-wide lines — of its kind
        UPDATE finance.fee_schedule SET ended_at = now()
         WHERE session = p_session AND ended_at IS NULL
           AND ((v_cce AND entry_mode = 'CCE') OR (v_full AND entry_mode IS DISTINCT FROM 'CCE'))
           AND (programme_code = ANY (v_row_progs)
                OR (programme_code IS NULL AND faculty_code = ANY (v_row_facs))
                OR (v_universal AND programme_code IS NULL AND faculty_code IS NULL));
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
        v_spill := lower(btrim(coalesce(r->>'spillover', 'false'))) IN ('true', 't', '1', 'yes', 'y', 'spillover', 'spill');
        IF v_spill THEN v_level := NULL; nsp := nsp + 1; END IF;   -- a spillover line is level-agnostic (V088)
        v_kind := upper(regexp_replace(btrim(coalesce(r->>'kind', r->>'type', '')), '[^A-Za-z]', '', 'g'));
        v_kind := CASE WHEN v_kind LIKE 'LATEPAY%' THEN 'LATE_PAYMENT' WHEN v_kind LIKE 'LATEREG%' THEN 'LATE_REGISTRATION' ELSE 'FEE' END;
        v_item := nullif(btrim(coalesce(r->>'item', '')), '');
        IF v_item IS NULL THEN
            v_item := CASE v_kind WHEN 'LATE_PAYMENT' THEN 'Late payment fee' WHEN 'LATE_REGISTRATION' THEN 'Late registration fee'
                                  ELSE CASE WHEN v_spill THEN 'School fees (spillover)' ELSE 'School fees' END END
                      || CASE WHEN v_sem IS NULL THEN '' ELSE ' (semester ' || v_sem || ')' END;
        END IF;
        v_ord := coalesce(nullif(regexp_replace(coalesce(r->>'ord', r->>'order', ''), '[^0-9]', '', 'g'), '')::int,
                          coalesce(v_sem, 1) + CASE WHEN v_spill THEN 100 ELSE 0 END);

        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, fee_group, semester, indigene, ord, spillover, kind)
        VALUES (p_session, v_item, v_amt, v_level, v_mode, v_fac_code, v_prog_code, v_grp_code, v_sem, v_ind, v_ord, v_spill, v_kind);
        nl := nl + 1;
        IF v_fac_code IS NOT NULL AND NOT (v_fac_code = ANY(facs)) THEN facs := facs || v_fac_code; END IF;
        IF v_prog_code IS NOT NULL AND NOT (v_prog_code = ANY(progs)) THEN progs := progs || v_prog_code; END IF;
    END LOOP;
    RETURN QUERY SELECT n, nl, cardinality(facs), nnf, nnp, nng, nsp, cardinality(progs);
END $function$;

-- the two-argument form, as every caller before V535 knew it: the whole session, refused when the file leaves a faculty out
CREATE OR REPLACE FUNCTION finance.import_fee_structure(p_session text, p_rows jsonb)
 RETURNS TABLE(rows integer, lines integer, faculties integer, no_faculty integer, no_programme integer, no_group integer, spillover integer, programmes integer)
 LANGUAGE sql
AS $function$
    SELECT * FROM finance.import_fee_structure(p_session, p_rows, 'SESSION', false)
$function$;

-- what an upload would do, done and undone: nothing is kept
CREATE FUNCTION finance.fee_upload_effect(p_session text, p_rows jsonb, p_action text, p_scope text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE v_before jsonb; v_gaps_before jsonb; v_res jsonb; v_out jsonb; v_msg text; v_action text := upper(btrim(coalesce(p_action, '')));
BEGIN
    IF v_action NOT IN ('STRUCTURE', 'LINES') THEN
        RAISE EXCEPTION 'FEE_UPLOAD_ACTION: an upload is the structure (STRUCTURE) or the fees to state (LINES)' USING ERRCODE = '23514';
    END IF;
    SELECT coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb) INTO v_before
      FROM (SELECT id, faculty_code, programme_code, level, entry_mode, semester, indigene, spillover, kind, fee_group, item, amount
              FROM finance.fee_schedule WHERE session = p_session AND ended_at IS NULL) f;
    SELECT jsonb_build_object('students', coalesce(sum(g.students), 0), 'groups', count(*)) INTO v_gaps_before FROM finance.fee_gaps(p_session) g;
    BEGIN
        IF v_action = 'LINES' THEN
            SELECT to_jsonb(x) INTO v_res FROM finance.add_fee_lines(p_session, p_rows) x;
        ELSE
            SELECT to_jsonb(x) INTO v_res FROM finance.import_fee_structure(p_session, p_rows, coalesce(p_scope, 'LISTED'), true) x;
        END IF;
        WITH b AS (
            SELECT * FROM jsonb_to_recordset(v_before) AS x(id uuid, faculty_code text, programme_code text, level int, entry_mode text, semester int,
                                                              indigene text, spillover boolean, kind text, fee_group text, item text, amount numeric)),
        a AS (
            SELECT id, faculty_code, programme_code, level, entry_mode, semester, indigene, spillover, kind, fee_group, item, amount
              FROM finance.fee_schedule WHERE session = p_session AND ended_at IS NULL),
        ended AS (SELECT b.*, row(b.faculty_code, b.programme_code, b.level, b.entry_mode, b.semester, b.indigene, b.spillover, b.kind, b.fee_group, lower(btrim(b.item)))::text AS k
                    FROM b WHERE NOT EXISTS (SELECT 1 FROM a WHERE a.id = b.id)),
        added AS (SELECT a.*, row(a.faculty_code, a.programme_code, a.level, a.entry_mode, a.semester, a.indigene, a.spillover, a.kind, a.fee_group, lower(btrim(a.item)))::text AS k
                    FROM a WHERE NOT EXISTS (SELECT 1 FROM b WHERE b.id = a.id)),
        pairs AS (
            SELECT coalesce(d.faculty_code, e.faculty_code) AS faculty_code, coalesce(d.programme_code, e.programme_code) AS programme_code,
                   coalesce(d.level, e.level) AS level, coalesce(d.entry_mode, e.entry_mode) AS entry_mode, coalesce(d.semester, e.semester) AS semester,
                   coalesce(d.indigene, e.indigene) AS indigene, coalesce(d.spillover, e.spillover) AS spillover, coalesce(d.item, e.item) AS item,
                   e.amount AS old, d.amount AS new,
                   CASE WHEN e.k IS NULL THEN 'NEW' WHEN d.k IS NULL THEN 'ENDED' WHEN e.amount = d.amount THEN 'SAME' ELSE 'CHANGED' END AS what
              FROM ended e FULL JOIN added d ON d.k = e.k),
        named AS (
            SELECT p.*, coalesce(fa.name, p.faculty_code, 'Every faculty') AS faculty, pr.name AS programme
              FROM pairs p LEFT JOIN ref.faculty fa ON fa.code = p.faculty_code LEFT JOIN ref.programme pr ON pr.code = p.programme_code),
        grp AS (
            SELECT n.faculty, n.faculty_code, n.programme, n.programme_code,
                   count(*) FILTER (WHERE n.what = 'NEW') AS new, count(*) FILTER (WHERE n.what = 'CHANGED') AS changed,
                   count(*) FILTER (WHERE n.what = 'SAME') AS same, count(*) FILTER (WHERE n.what = 'ENDED') AS ended
              FROM named n GROUP BY 1, 2, 3, 4),
        kept AS (   -- of each faculty or programme the upload touches, the lines that stay in force as they were
            SELECT a.faculty_code, a.programme_code, count(*) AS n FROM a WHERE NOT EXISTS (SELECT 1 FROM added d WHERE d.id = a.id) GROUP BY 1, 2),
        gaps AS (SELECT * FROM finance.fee_gaps(p_session))
        SELECT jsonb_build_object(
            'action', v_action, 'scope', CASE WHEN v_action = 'STRUCTURE' THEN coalesce(upper(p_scope), 'LISTED') END, 'result', v_res,
            'linesBefore', jsonb_array_length(v_before), 'linesAfter', (SELECT count(*) FROM a),
            'totals', (SELECT jsonb_build_object('new', coalesce(sum(new), 0), 'changed', coalesce(sum(changed), 0), 'same', coalesce(sum(same), 0), 'ended', coalesce(sum(ended), 0)) FROM grp),
            'groups', (SELECT coalesce(jsonb_agg(jsonb_build_object('faculty', g.faculty, 'facultyCode', g.faculty_code, 'programme', g.programme, 'programmeCode', g.programme_code,
                                                                     'new', g.new, 'changed', g.changed, 'same', g.same, 'ended', g.ended,
                                                                     'losesAll', g.ended > 0 AND g.new + g.changed + g.same = 0
                                                                                 AND NOT EXISTS (SELECT 1 FROM kept k WHERE k.faculty_code IS NOT DISTINCT FROM g.faculty_code
                                                                                                                         AND k.programme_code IS NOT DISTINCT FROM g.programme_code))
                                                  ORDER BY g.faculty, g.programme NULLS FIRST), '[]'::jsonb) FROM grp g),
            'changes', (SELECT coalesce(jsonb_agg(c ORDER BY c->>'faculty', c->>'programme', (c->>'semester')::int NULLS FIRST, (c->>'level')::int NULLS LAST), '[]'::jsonb)
                          FROM (SELECT jsonb_build_object('faculty', n.faculty, 'programme', n.programme, 'level', n.level, 'entryMode', n.entry_mode, 'semester', n.semester,
                                                          'indigene', n.indigene, 'spillover', n.spillover, 'item', n.item, 'old', n.old, 'new', n.new) AS c
                                  FROM named n WHERE n.what = 'CHANGED' ORDER BY n.faculty, n.programme, n.semester, n.level LIMIT 400) x),
            'gaps', jsonb_build_object(
                'before', v_gaps_before,
                'after', (SELECT jsonb_build_object('students', coalesce(sum(students), 0), 'groups', count(*)) FROM gaps),
                'rows', (SELECT coalesce(jsonb_agg(jsonb_build_object('faculty', coalesce(x.faculty, x.faculty_code), 'programme', x.programme, 'level', x.level,
                                                                      'entryMode', x.entry_mode, 'spillover', x.spillover, 'students', x.students)
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

COMMENT ON FUNCTION finance.fee_upload_effect(text, jsonb, text, text) IS
  'V535: what a fee upload (STRUCTURE with scope LISTED or SESSION, or LINES) would do to the session — applied and undone, nothing kept';

COMMIT;
