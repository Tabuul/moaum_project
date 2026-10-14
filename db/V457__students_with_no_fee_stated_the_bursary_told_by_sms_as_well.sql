-- ═══════════════════════════════════════
-- V457 — Students with no fee stated: the Bursary told by SMS as well
--
--   V451's watch (finance.watch_fee_gaps) tells every Bursary office holder, by e-mail and on the portal, when a group of
--   live undergraduate students of the current session appears with no school fee stated while a semester is open. An
--   e-mail can wait unread while those students cannot register; the SMS the FEE_GAPS template already words now goes too,
--   to the phone on each holder's staff record (one without a phone is skipped by the outbox, as for every notice). Still
--   once per new group: the same event key, so a watch run again tells nobody twice.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V457: students with no fee stated, the Bursary told by SMS as well', true);

CREATE OR REPLACE FUNCTION finance.watch_fee_gaps(p_session text DEFAULT NULL)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE v_ses text := coalesce(p_session, policy.university_current_session()); v_keys text[]; v_new text[]; v_students bigint; v_groups int; v_list text;
        v_prev text[]; v_vars jsonb; v_at text; p record; told int := 0;
BEGIN
    -- only while a semester of the session (the current one, unless named) is open: a session not yet running is still being stated
    IF v_ses IS NULL OR NOT EXISTS (SELECT 1 FROM policy.semester WHERE session = v_ses AND state = 'OPEN') THEN
        RETURN 0;
    END IF;
    WITH g AS (SELECT * FROM finance.fee_gaps(v_ses)),
    fac AS (SELECT coalesce(g.faculty, g.faculty_code) AS f, sum(g.students) AS n FROM g GROUP BY 1)
    SELECT (SELECT coalesce(array_agg(x.k ORDER BY x.k), '{}'::text[])
              FROM (SELECT concat_ws('|', g.programme_code, g.level, g.entry_mode, g.indigene, g.spillover, coalesce(g.missing::text, 'none')) AS k FROM g) x),
           (SELECT coalesce(sum(g.students), 0) FROM g),
           (SELECT count(*) FROM g),
           (SELECT string_agg(replace(replace(replace(initcap(lower(fac.f)), ' And ', ' and '), ' Of ', ' of '), ' For ', ' for ')
                              || ' ' || to_char(fac.n, 'FM999,999,999'), '; ' ORDER BY fac.n DESC, fac.f) FROM fac)
      INTO v_keys, v_students, v_groups, v_list;
    SELECT w.told_keys INTO v_prev FROM finance.fee_gap_watch w WHERE w.session = v_ses FOR UPDATE;
    v_new := ARRAY(SELECT k FROM unnest(v_keys) k WHERE NOT k = ANY (coalesce(v_prev, '{}'::text[])));
    IF cardinality(v_new) > 0 THEN
        v_at := to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISSUS');   -- each telling its own event
        v_vars := jsonb_build_object('SESSION', v_ses, 'STUDENTS', to_char(v_students, 'FM999,999,999'), 'GROUPS', v_groups,
                                     'NEW_GROUPS', cardinality(v_new), 'FACULTIES', coalesce(v_list, ''));
        FOR p IN SELECT DISTINCT a.person_id
                   FROM iam.office_assignment a JOIN iam.person pe ON pe.id = a.person_id
                  WHERE a.office_code = 'bursar' AND pe.ended_on IS NULL
                    AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) LOOP
            told := told + platform.tell_person(p.person_id, 'FEE_GAPS', NULL, v_vars,
                                                'fee-gaps:' || v_ses || ':' || md5(array_to_string(v_new, ',')) || ':' || v_at, ARRAY['EMAIL', 'PORTAL', 'SMS']);
        END LOOP;
    END IF;
    -- the groups seen now are the ones told: a gap put right and opened again is told again
    INSERT INTO finance.fee_gap_watch AS w (session, told_keys, told_at, told, students, groups, checked_at)
    VALUES (v_ses, v_keys, CASE WHEN cardinality(v_new) > 0 THEN now() END, told, v_students, v_groups, now())
    ON CONFLICT (session) DO UPDATE
       SET told_keys = excluded.told_keys,
           told_at = coalesce(excluded.told_at, w.told_at),
           told = CASE WHEN excluded.told_at IS NOT NULL THEN excluded.told ELSE w.told END,
           students = excluded.students, groups = excluded.groups, checked_at = excluded.checked_at;
    RETURN told;
END $$;

COMMENT ON FUNCTION finance.watch_fee_gaps(text) IS
  'V451, V457: while a semester of the session (the current one by default) is open, reads finance.fee_gaps and tells every Bursary office holder '
  '(FEE_GAPS, by e-mail, on the portal and by SMS) when a group appears that it had not seen at its last reading. Returns the messages queued.';

COMMIT;
