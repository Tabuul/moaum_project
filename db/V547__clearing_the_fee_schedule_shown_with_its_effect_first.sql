-- V547: "Clear the schedule" shows what it would end before it ends it.
--
-- Fee Setup's "Clear the schedule" ended every fee line of the session (or its full-time or its CCE lines) after a confirmation
-- that gave only a count of lines. finance.fee_upload_effect (V535) now also answers for action CLEAR, scope ALL, FULL_TIME or CCE:
-- the lines it would end for each faculty and programme, the faculties left with no fee, and the live students of that kind who would owe no school fee — applied and undone, nothing kept. The screen shows it and asks for a tick before it clears.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'bursar', true);
SELECT set_config('moaum.reason', 'V547: clearing the fee schedule shown with its effect first', true);

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
      FROM (SELECT id, faculty_code, programme_code, level, entry_mode, semester, indigene, spillover, kind, fee_group, item, amount
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
            'action', v_action, 'scope', CASE WHEN v_action = 'STRUCTURE' THEN coalesce(upper(p_scope), 'LISTED') WHEN v_action = 'CLEAR' THEN coalesce(upper(p_scope), 'ALL') END, 'result', v_res,
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
  'V535/V547: what a fee upload (STRUCTURE with scope LISTED or SESSION, or LINES) or clearing the schedule (CLEAR with scope ALL, FULL_TIME or CCE) would do to the session — applied and undone, nothing kept';

COMMIT;
