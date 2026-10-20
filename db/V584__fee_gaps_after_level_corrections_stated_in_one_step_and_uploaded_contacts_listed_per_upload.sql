-- V584: what the fee effect of the level corrections finds missing, put right from the same report, and each contact upload's
-- students listed.
--
--   * The fee lines a corrected level leaves missing. V580's run reads every waiting correction; the students it finds charged
--     nothing after (166 on the live-shaped copy of 20 October 2026, every one on a College programme that states no line for
--     2025/2026 at all — B.Sc. Biochemistry, Radiography, Medical Laboratory Science) are grouped by programme and corrected
--     level (people.level_fee_effect_gaps), each group with the lines it could be stated from: what applies to the programme at
--     the nearest level, what applied to it at that level in the last session that states any, another programme of the
--     department or of the faculty at that level. What applies to a programme at a level (finance.programme_level_lines) is its
--     own lines, else its faculty's, else the University's — a structure kept faculty by faculty is read as one kept programme
--     by programme. finance.copy_programme_lines states those lines as the target programme's own at its level (a line already
--     stated for the same students kept; previewed first, nothing written; the Bursary's or the Students Account Officer's), so
--     the Bursary states the gap in one step and adjusts any amount afterwards.
--   * Corrected programme by programme. people.level_fee_effect_report (V580) says how many of each programme's students have
--     been brought to their level since the run, so the Registry corrects one programme at a time with its fee effect beside it.
--   * Each upload's students. people.contact_upload_students lists the students an upload gave a contact to, field by field,
--     with what became of it — waiting for the student (a code sent or not), confirmed by the student or at the desk, said not
--     to be theirs — so a department chases the students who have not answered.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'bursar', true);
SELECT set_config('moaum.reason', 'V584: fee gaps after level corrections, uploaded contacts listed per upload', true);

-- ── the run's sums, with how many of each group have been corrected since ──────────────────────────────────────────────────
DROP FUNCTION people.level_fee_effect_report(uuid);
CREATE FUNCTION people.level_fee_effect_report(p_run uuid)
RETURNS TABLE (scope text, faculty_code text, faculty text, programme_code text, programme text, students bigint,
               charged_now numeric, charged_after numeric, more bigint, less bigint, same bigint, none_after bigint, corrected bigint)
LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN grouping(f.code) = 1 THEN 'UNIVERSITY' WHEN grouping(p.code) = 1 THEN 'FACULTY' ELSE 'PROGRAMME' END,
           f.code, max(f.name), p.code, max(p.name), count(*),
           coalesce(sum(x.charged_now), 0), coalesce(sum(x.charged_after), 0),
           count(*) FILTER (WHERE x.charged_after > x.charged_now), count(*) FILTER (WHERE x.charged_after < x.charged_now),
           count(*) FILTER (WHERE x.charged_after = x.charged_now), count(*) FILTER (WHERE x.charged_after = 0),
           -- V584: brought to the corrected level (or beyond) since the run read them
           count(*) FILTER (WHERE s.current_level >= x.new_level)
      FROM people.level_fee_effect_row x
      JOIN people.student s ON s.id = x.student_id
      JOIN ref.programme p ON p.code = s.programme_code
      JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE x.run_id = p_run AND x.charged_now IS NOT NULL
     GROUP BY GROUPING SETS ((), (f.code), (f.code, p.code))
     ORDER BY grouping(f.code) DESC, max(f.name) NULLS FIRST, grouping(p.code) DESC, max(p.name) NULLS FIRST
$fn$;

-- ── the lines that apply to a programme at a level in a session ────────────────────────────────────────────────────────────
-- the programme's own lines at that level when it states any; else its faculty's (no programme named); else the University's (no
-- faculty or programme named) — the most specific stated, so a structure kept faculty by faculty (544 of 2025/2026's 756 ordinary
-- lines on the live-shaped copy) is read as readily as one kept programme by programme. Spillover lines apart.
CREATE FUNCTION finance.programme_level_lines(p_session text, p_programme text, p_level integer)
RETURNS TABLE (item text, kind text, amount numeric, entry_mode text, faculty_code text, fee_group text, semester integer, indigene text, ord integer,
               tier text)
LANGUAGE sql STABLE AS $fn$
    WITH p AS (SELECT faculty_code FROM ref.programme WHERE code = p_programme),
    l AS (
        SELECT f.item, f.kind, f.amount, f.entry_mode, f.faculty_code, f.fee_group, f.semester, f.indigene, f.ord,
               CASE WHEN f.programme_code = p_programme THEN 1 WHEN f.faculty_code IS NOT NULL THEN 2 ELSE 3 END AS rank
          FROM finance.fee_schedule f, p
         WHERE f.session = p_session AND f.level = p_level AND NOT f.spillover AND f.ended_at IS NULL
           AND (f.programme_code = p_programme OR (f.programme_code IS NULL AND (f.faculty_code = p.faculty_code OR f.faculty_code IS NULL)))
    )
    SELECT l.item, l.kind, l.amount, l.entry_mode, l.faculty_code, l.fee_group, l.semester, l.indigene, l.ord,
           CASE l.rank WHEN 1 THEN 'PROGRAMME' WHEN 2 THEN 'FACULTY' ELSE 'UNIVERSITY' END
      FROM l WHERE l.rank = (SELECT min(rank) FROM l)
     ORDER BY l.kind, l.ord, l.item, l.semester NULLS FIRST, l.indigene NULLS FIRST, l.entry_mode NULLS FIRST
$fn$;
COMMENT ON FUNCTION finance.programme_level_lines(text, text, integer) IS
  'V584: the lines that apply to a programme at a level in a session — its own, else its faculty''s, else the University''s (spillover lines apart)';

-- ── the groups a run finds charged nothing after, and what each could be stated from ───────────────────────────────────────
CREATE FUNCTION people.level_fee_effect_gaps(p_run uuid)
RETURNS TABLE (programme_code text, programme text, faculty_code text, faculty text, department text, level integer, students bigint,
               corrected bigint, programme_states boolean, sources jsonb)
LANGUAGE sql STABLE AS $fn$
    WITH r AS (SELECT * FROM people.level_fee_effect_run WHERE id = p_run),
    g AS (
        SELECT s.programme_code, x.new_level AS level, count(*) AS students, count(*) FILTER (WHERE s.current_level >= x.new_level) AS corrected
          FROM people.level_fee_effect_row x JOIN people.student s ON s.id = x.student_id
         WHERE x.run_id = p_run AND x.charged_after = 0 AND x.new_level IS NOT NULL
         GROUP BY s.programme_code, x.new_level
    )
    SELECT g.programme_code, p.name, p.faculty_code, fa.name, d.name, g.level, g.students, g.corrected,
           EXISTS (SELECT 1 FROM finance.fee_schedule f, r WHERE f.session = r.session AND f.programme_code = g.programme_code
                                                             AND NOT f.spillover AND f.ended_at IS NULL),
           coalesce((SELECT jsonb_agg(c.src ORDER BY c.rank, c.lines DESC, c.name) FROM (
                -- 1. what applies to the programme at the nearest other level this session (the level below first)
                (SELECT 1 AS rank, n.lines, p.name,
                        jsonb_build_object('kind', 'SAME_PROGRAMME', 'session', r.session, 'programme_code', g.programme_code, 'programme', p.name,
                                           'level', lv, 'lines', n.lines, 'tier', n.tier) AS src
                   FROM r, unnest(ARRAY[100, 200, 300, 400, 500, 600, 700, 800, 900]) lv
                   CROSS JOIN LATERAL (SELECT count(*) AS lines, min(t.tier) AS tier FROM finance.programme_level_lines(r.session, g.programme_code, lv) t) n
                  WHERE lv <> g.level AND n.lines > 0
                  ORDER BY abs(lv - g.level), lv LIMIT 1)
                UNION ALL
                -- 2. what applied to it at that level in the last session that states any
                (SELECT 2, n.lines, p.name,
                        jsonb_build_object('kind', 'LAST_SESSION', 'session', a.name, 'programme_code', g.programme_code, 'programme', p.name,
                                           'level', g.level, 'lines', n.lines, 'tier', n.tier)
                   FROM r, policy.academic_session a
                   CROSS JOIN LATERAL (SELECT count(*) AS lines, min(t.tier) AS tier FROM finance.programme_level_lines(a.name, g.programme_code, g.level) t) n
                  WHERE a.name < r.session AND n.lines > 0
                  ORDER BY a.name DESC LIMIT 1)
                UNION ALL
                -- 3. another programme of the department, then of the faculty, stating its own lines at that level this session
                (SELECT CASE WHEN o.dept_code = p.dept_code THEN 3 ELSE 4 END, count(*), o.name,
                        jsonb_build_object('kind', CASE WHEN o.dept_code = p.dept_code THEN 'SAME_DEPARTMENT' ELSE 'SAME_FACULTY' END,
                                           'session', min(f.session), 'programme_code', o.code, 'programme', o.name,
                                           'level', g.level, 'lines', count(*), 'tier', 'PROGRAMME')
                   FROM finance.fee_schedule f JOIN ref.programme o ON o.code = f.programme_code, r
                  WHERE f.session = r.session AND f.level = g.level AND NOT f.spillover AND f.ended_at IS NULL
                    AND o.code <> g.programme_code AND o.faculty_code = p.faculty_code
                  GROUP BY o.code, o.name, o.dept_code
                  ORDER BY CASE WHEN o.dept_code = p.dept_code THEN 3 ELSE 4 END, count(*) DESC, o.name LIMIT 8)
           ) c), '[]'::jsonb)
      FROM g
      JOIN ref.programme p ON p.code = g.programme_code
      LEFT JOIN ref.faculty fa ON fa.code = p.faculty_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
     ORDER BY fa.name, p.name, g.level
$fn$;
COMMENT ON FUNCTION people.level_fee_effect_gaps(uuid) IS
  'V584: the programme and corrected level of the students a fee-effect run finds charged nothing after, each with the lines it could be stated from';

-- ── the lines that apply to one programme at one level, stated for another programme and level ─────────────────────────────
CREATE FUNCTION finance.copy_programme_lines(p_from_session text, p_from_programme text, p_from_level integer,
                                             p_to_session text, p_to_programme text, p_to_level integer, p_apply boolean)
RETURNS TABLE (item text, kind text, amount numeric, entry_mode text, fee_group text, semester integer, indigene text, ord integer,
               target_amount numeric, action text)
LANGUAGE plpgsql AS $fn$
DECLARE v_faculty text;
BEGIN
    IF p_to_level IS NULL OR p_to_level NOT IN (100, 200, 300, 400, 500, 600, 700, 800, 900) OR p_from_level IS NULL THEN
        RAISE EXCEPTION 'FEE_LEVEL: lines are copied from one level into one level (100 to 900)' USING ERRCODE = '23514';
    END IF;
    SELECT faculty_code INTO v_faculty FROM ref.programme WHERE code = p_to_programme;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'FEE_COPY_PROGRAMME: % is not a programme on the register', p_to_programme USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_to_session) THEN
        RAISE EXCEPTION 'FEE_COPY_SESSION: % is not a session on the calendar', p_to_session USING ERRCODE = '23514';
    END IF;
    IF p_from_session = p_to_session AND p_from_programme = p_to_programme AND p_from_level = p_to_level THEN
        RAISE EXCEPTION 'FEE_COPY_SESSIONS: copy from one programme or level into another' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM finance.programme_level_lines(p_from_session, p_from_programme, p_from_level)) THEN
        RAISE EXCEPTION 'FEE_COPY_EMPTY: % states no line for % at % Level', p_from_session, p_from_programme, p_from_level USING ERRCODE = '23514';
    END IF;
    IF p_apply AND nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'FEE_COPY_ACTOR: fees are copied by a person' USING ERRCODE = '23514';
    END IF;
    -- each source line as the target programme's own line at the target level (its faculty kept where the line named one), and
    -- the line the target already states for the same students (finance.fee_line_same_scope's columns); nothing written unless applied
    RETURN QUERY
    SELECT s.item, s.kind, s.amount, s.entry_mode, s.fee_group, s.semester, s.indigene, s.ord, t.amount,
           CASE WHEN t.amount IS NULL THEN 'COPY' ELSE 'KEPT' END
      FROM finance.programme_level_lines(p_from_session, p_from_programme, p_from_level) s
      LEFT JOIN LATERAL (SELECT x.amount FROM finance.fee_schedule x
                          WHERE x.session = p_to_session AND x.ended_at IS NULL AND NOT x.spillover
                            AND lower(btrim(x.item)) = lower(btrim(s.item)) AND x.kind = s.kind AND x.level = p_to_level AND x.programme_code = p_to_programme
                            AND x.faculty_code IS NOT DISTINCT FROM (CASE WHEN s.faculty_code IS NULL THEN NULL ELSE v_faculty END)
                            AND x.entry_mode IS NOT DISTINCT FROM s.entry_mode AND x.fee_group IS NOT DISTINCT FROM s.fee_group
                            AND x.semester IS NOT DISTINCT FROM s.semester AND x.indigene IS NOT DISTINCT FROM s.indigene
                          LIMIT 1) t ON true;
    IF p_apply THEN
        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, ord, fee_group, semester, indigene, spillover, kind)
        SELECT p_to_session, s.item, s.amount, p_to_level, s.entry_mode, CASE WHEN s.faculty_code IS NULL THEN NULL ELSE v_faculty END, p_to_programme,
               s.ord, s.fee_group, s.semester, s.indigene, false, s.kind
          FROM finance.programme_level_lines(p_from_session, p_from_programme, p_from_level) s
         WHERE NOT EXISTS (SELECT 1 FROM finance.fee_schedule x
                            WHERE x.session = p_to_session AND x.ended_at IS NULL AND NOT x.spillover
                              AND lower(btrim(x.item)) = lower(btrim(s.item)) AND x.kind = s.kind AND x.level = p_to_level AND x.programme_code = p_to_programme
                              AND x.faculty_code IS NOT DISTINCT FROM (CASE WHEN s.faculty_code IS NULL THEN NULL ELSE v_faculty END)
                              AND x.entry_mode IS NOT DISTINCT FROM s.entry_mode AND x.fee_group IS NOT DISTINCT FROM s.fee_group
                              AND x.semester IS NOT DISTINCT FROM s.semester AND x.indigene IS NOT DISTINCT FROM s.indigene);
    END IF;
END $fn$;
COMMENT ON FUNCTION finance.copy_programme_lines(text, text, integer, text, text, integer, boolean) IS
  'V584: the lines that apply to one programme at one level (its own, else its faculty''s, else the University''s; not the spillover lines) stated as another programme''s at a level, a line the target states for the same students kept; previewed first';

-- ── what became of each contact an upload gave ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.contact_upload_students(p_upload uuid)
RETURNS TABLE (student_id uuid, number text, name text, programme text, department text, level integer, field text, value text,
               outcome text, code_sent boolean, decided_at timestamptz)
LANGUAGE sql STABLE AS $fn$
    WITH w AS (
        -- still waiting for the student: the upload's mark is on the record
        SELECT c.student_id, 'EMAIL' AS field, c.email AS value FROM people.student_contact c WHERE c.email_upload_id = p_upload AND c.email_pending
        UNION ALL
        SELECT c.student_id, 'PHONE', c.phone FROM people.student_contact c WHERE c.phone_upload_id = p_upload AND c.phone_pending
    ),
    d AS (
        -- answered: the latest decision on each field the upload gave
        SELECT DISTINCT ON (x.student_id, x.field) x.student_id, x.field, x.value, x.outcome, x.decided_at
          FROM people.contact_confirmation x
         WHERE x.upload_id = p_upload AND x.outcome IN ('CONFIRMED', 'DESK', 'REFUSED')
         ORDER BY x.student_id, x.field, x.decided_at DESC
    ),
    a AS (
        SELECT w.student_id, w.field, w.value, 'WAITING' AS outcome, NULL::timestamptz AS decided_at FROM w
        UNION ALL
        SELECT d.student_id, d.field, d.value, d.outcome, d.decided_at FROM d
         WHERE NOT EXISTS (SELECT 1 FROM w WHERE w.student_id = d.student_id AND w.field = d.field)
    )
    SELECT a.student_id, coalesce(s.matric_no, s.admission_no, s.jamb_reg_no),
           upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''),
           p.name, dp.name, s.current_level, a.field, a.value, a.outcome,
           a.outcome = 'WAITING' AND EXISTS (SELECT 1 FROM people.contact_confirmation k
                                              WHERE k.student_id = a.student_id AND k.field = a.field AND k.outcome IS NULL AND k.expires_at > now()),
           a.decided_at
      FROM a
      JOIN people.student s ON s.id = a.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.department dp ON dp.code = p.dept_code
     ORDER BY CASE a.outcome WHEN 'WAITING' THEN 0 WHEN 'REFUSED' THEN 1 ELSE 2 END, p.name, s.current_level, 3, a.field
$fn$;
COMMENT ON FUNCTION people.contact_upload_students(uuid) IS
  'V584: the students an upload gave a contact to, field by field, with what became of it (waiting, confirmed, at the desk, not theirs)';

COMMIT;
